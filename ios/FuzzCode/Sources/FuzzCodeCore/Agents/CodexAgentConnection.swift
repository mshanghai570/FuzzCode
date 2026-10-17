import Foundation

/// Codex app-server v2 adapter. This is not ACP; the upstream remote WebSocket transport is experimental.
public actor CodexAgentConnection: AgentConnection {
    public let id: UUID
    public let displayName: String
    public let kind: AgentConnectionKind = .codex
    public let capabilities: Set<AgentCapability> = [.sessions, .streaming, .toolEvents, .cancellation, .permissionRequests, .sessionResumption, .fileDiffs]
    private let config: OpenCodeHostConfig
    private let transport: any ACPTransport
    private let storage: StorageService
    private var initialized = false
    private var listener: Task<Void, Never>?
    private var sessions: [String: AgentSession] = [:]
    private var streams: [String: AsyncThrowingStream<AgentEvent, Error>.Continuation] = [:]
    private var requests: [String: Task<Void, Never>] = [:]
    private var turnIDs: [String: String] = [:]
    private var cancelled = Set<String>()
    private var diffs: [String: GitStatusSummary] = [:]
    private var approvals: [String: (AgentJSONValue, String)] = [:]

    public init(hostConfig: OpenCodeHostConfig, transport: any ACPTransport, storage: StorageService = .shared) {
        id = hostConfig.id; displayName = hostConfig.displayName; config = hostConfig
        self.transport = transport; self.storage = storage
    }

    public func connect() async throws -> AgentHostMetadata {
        if !initialized {
            let incoming = await transport.incomingMessages()
            listener = Task { [weak self] in
                do { for try await message in incoming { await self?.handle(message) } }
                catch { await self?.disconnected() }
            }
            do {
                try await transport.connect()
                let result = try await transport.request(method: "initialize", params: .object([
                    "clientInfo": .object(["name": .string("fuzzcode"), "title": .string("FuzzCode"), "version": .string("1.0")])]))
                guard result.rpcObject != nil else { throw AgentConnectionError.invalidResponse }
                try await transport.notify(method: "initialized", params: .object([:]))
                initialized = true
                return metadata(version: result.rpcObject?["userAgent"]?.rpcString ?? "Codex app-server")
            } catch {
                listener?.cancel(); listener = nil; await transport.disconnect(); throw error
            }
        }
        return metadata(version: "Codex app-server")
    }

    private func metadata(version: String) -> AgentHostMetadata {
        AgentHostMetadata(hostId: id.uuidString, name: displayName, version: version, osName: "Remote runtime",
            defaultWorkspace: config.currentWorkspace, capabilities: Array(capabilities))
    }

    public func listSessions() async throws -> [AgentSession] {
        _ = try await connect()
        let response = try await transport.request(method: "thread/list", params: .object(["limit": .number(50)]))
        guard let threads = response.rpcObject?["data"]?.rpcArray else { throw AgentConnectionError.invalidResponse }
        var result: [AgentSession] = []
        for thread in threads {
            let session = try decodeThread(thread)
            sessions[session.id] = session; save(session); result.append(session)
        }
        return result
    }

    public func createSession(workspacePath: String, prompt: String?) async throws -> AgentSession {
        _ = try await connect()
        let response = try await transport.request(method: "thread/start", params: .object([
            "cwd": .string(workspacePath), "approvalPolicy": .string("on-request"), "sandbox": .string("workspaceWrite")]))
        guard let thread = response.rpcObject?["thread"] else { throw AgentConnectionError.invalidResponse }
        var session = try decodeThread(thread)
        if let prompt, !prompt.isEmpty { session.title = String(prompt.prefix(60)) }
        sessions[session.id] = session; save(session); return session
    }

    public func resumeSession(sessionId: String, workspacePath: String) async throws -> AgentSession {
        _ = try await connect()
        let response = try await transport.request(method: "thread/resume", params: .object(["threadId": .string(sessionId)]))
        guard let thread = response.rpcObject?["thread"] else { throw AgentConnectionError.invalidResponse }
        let session = try decodeThread(thread)
        sessions[session.id] = session; save(session); return session
    }

    public func sendInstruction(sessionId: String, prompt: String) async -> AsyncThrowingStream<AgentEvent, Error> {
        guard streams[sessionId] == nil else { return AsyncThrowingStream { $0.finish(throwing: AgentConnectionError.notSupported("Concurrent turns")) } }
        cancelled.remove(sessionId)
        return AsyncThrowingStream { continuation in
            streams[sessionId] = continuation
            requests[sessionId] = Task {
                do {
                    _ = try await self.connect()
                    try Task.checkCancellation()
                    self.recordUser(sessionId, prompt: prompt)
                    continuation.yield(.statusChanged(.running))
                    let response = try await self.transport.request(method: "turn/start", params: .object([
                        "threadId": .string(sessionId), "input": .array([.object(["type": .string("text"), "text": .string(prompt)])])]))
                    guard let turnID = response.rpcObject?["turn"]?.rpcObject?["id"]?.rpcString else { throw AgentConnectionError.invalidResponse }
                    if self.streams[sessionId] != nil { self.turnIDs[sessionId] = turnID }
                    if self.cancelled.contains(sessionId) {
                        _ = try? await self.transport.request(method: "turn/interrupt", params: .object(["threadId": .string(sessionId), "turnId": .string(turnID)]))
                    }
                } catch {
                    self.finish(sessionId, status: Task.isCancelled ? .cancelled : .failed, error: Task.isCancelled ? nil : error)
                }
            }
            continuation.onTermination = { @Sendable _ in Task { await self.cancelIfRunning(sessionId) } }
        }
    }

    public func cancelTask(sessionId: String) async throws {
        cancelled.insert(sessionId)
        for (requestID, approval) in approvals where approval.1 == sessionId {
            try? await transport.respond(id: approval.0, result: .object(["decision": .string("cancel")]))
            approvals.removeValue(forKey: requestID)
        }
        if let turnID = turnIDs[sessionId] {
            _ = try await transport.request(method: "turn/interrupt", params: .object([
                "threadId": .string(sessionId), "turnId": .string(turnID)]))
        }
        // Keep a pending turn/start alive until it returns its id, then immediately interrupt it.
        finish(sessionId, status: .cancelled)
    }

    private func cancelIfRunning(_ id: String) async { if streams[id] != nil { try? await cancelTask(sessionId: id) } }

    public func resolvePermission(requestId: String, decision: PermissionDecision, rationale: String?) async throws {
        guard let approval = approvals.removeValue(forKey: requestId) else { throw AgentConnectionError.invalidResponse }
        let value: String
        switch decision { case .allowOnce: value = "accept"; case .allowAlways: value = "acceptForSession"; case .deny: value = "decline" }
        try await transport.respond(id: approval.0, result: .object(["decision": .string(value)]))
    }

    public func fetchGitStatus(sessionId: String) async throws -> GitStatusSummary {
        guard let summary = diffs[sessionId] else { throw AgentConnectionError.notSupported("No streamed diff is available for this turn") }
        return summary
    }

    private func handle(_ message: AgentRPCMessage) async {
        guard let method = message.method, let params = message.params?.rpcObject,
              let sessionID = params["threadId"]?.rpcString else { return }
        if method == "item/commandExecution/requestApproval" || method == "item/fileChange/requestApproval", let rpcID = message.id {
            guard let stream = streams[sessionID] else {
                try? await transport.respond(id: rpcID, result: .object(["decision": .string("decline")]))
                return
            }
            let preview = String(decoding: (try? JSONEncoder().encode(message.params)) ?? Data(), as: UTF8.self)
            let request = PermissionRequest(toolName: method.contains("commandExecution") ? "Remote command" : "Remote file changes",
                commandOrPath: params["command"]?.rpcString ?? params["reason"]?.rpcString ?? "Review remote action",
                fullParameters: ["preview": preview], riskLevel: .high)
            approvals[request.id] = (rpcID, sessionID); stream.yield(.permissionRequested(request)); return
        }
        guard let stream = streams[sessionID] else { return }
        switch method {
        case "item/agentMessage/delta":
            if let delta = params["delta"]?.rpcString { stream.yield(.textDelta(delta)); recordText(sessionID, text: delta) }
        case "item/started", "item/completed":
            guard let item = params["item"]?.rpcObject, let itemID = item["id"]?.rpcString,
                  let type = item["type"]?.rpcString, ["commandExecution", "fileChange", "mcpToolCall"].contains(type) else { return }
            if method == "item/started" {
                stream.yield(.toolStarted(AgentToolEvent(id: itemID, toolName: type, argumentsJSON: item["command"]?.rpcString ?? "{}")))
            } else {
                let status = item["status"]?.rpcString ?? "completed"
                stream.yield(.toolCompleted(toolId: itemID, output: item["aggregatedOutput"]?.rpcString ?? "",
                    success: status != "failed" && status != "declined"))
            }
        case "turn/diff/updated":
            if let diff = params["diff"]?.rpcString {
                let summary = Self.summary(diff)
                diffs[sessionID] = summary; stream.yield(.gitUpdated(summary))
            }
        case "turn/completed":
            let status = params["turn"]?.rpcObject?["status"]?.rpcString ?? "failed"
            finish(sessionID, status: status == "completed" ? .completed : status == "interrupted" ? .cancelled : .failed,
                error: status == "failed" ? AgentConnectionError.remoteError("Remote turn failed.") : nil)
        case "error": finish(sessionID, status: .failed, error: AgentConnectionError.remoteError("Remote turn failed."))
        default: break
        }
    }

    private func decodeThread(_ value: AgentJSONValue) throws -> AgentSession {
        guard let object = value.rpcObject, let sessionID = object["id"]?.rpcString else { throw AgentConnectionError.invalidResponse }
        var session = storage.loadAgentSessions().first { $0.id == sessionID && $0.hostId == id }
            ?? AgentSession(id: sessionID, hostId: id, title: "Codex thread", workspacePath: object["cwd"]?.rpcString ?? "", connectionKind: .codex)
        session.title = object["name"]?.rpcString ?? object["preview"]?.rpcString ?? session.title
        if let turns = object["turns"]?.rpcArray, !turns.isEmpty {
            var messages: [AgentSessionMessage] = []
            for turn in turns {
                for value in turn.rpcObject?["items"]?.rpcArray ?? [] {
                    guard let item = value.rpcObject, let type = item["type"]?.rpcString else { continue }
                    if type == "agentMessage", let text = item["text"]?.rpcString {
                        messages.append(AgentSessionMessage(role: .assistant, content: text))
                    } else if type == "userMessage" {
                        let text = (item["content"]?.rpcArray ?? []).compactMap { $0.rpcObject?["text"]?.rpcString }.joined(separator: "\n")
                        messages.append(AgentSessionMessage(role: .user, content: text))
                    }
                }
            }
            session.messages = messages
        }
        return session
    }

    private func save(_ session: AgentSession) {
        var all = storage.loadAgentSessions()
        if let index = all.firstIndex(where: { $0.id == session.id && $0.hostId == session.hostId }) { all[index] = session }
        else { all.insert(session, at: 0) }
        storage.saveAgentSessions(all)
    }
    private func recordUser(_ id: String, prompt: String) {
        var session = sessions[id] ?? AgentSession(id: id, hostId: self.id, title: String(prompt.prefix(60)), workspacePath: "", connectionKind: .codex)
        session.messages.append(AgentSessionMessage(role: .user, content: prompt)); session.messages.append(AgentSessionMessage(role: .assistant, content: ""))
        session.status = .running; sessions[id] = session; save(session)
    }
    private func recordText(_ id: String, text: String) {
        guard var session = sessions[id], let last = session.messages.indices.last else { return }
        session.messages[last].content += text; session.updatedAt = Date(); sessions[id] = session; save(session)
    }
    private func finish(_ id: String, status: SessionStatus, error: Error? = nil) {
        let stream = streams.removeValue(forKey: id)
        requests.removeValue(forKey: id); turnIDs.removeValue(forKey: id)
        if var session = sessions[id] { session.status = status; session.updatedAt = Date(); sessions[id] = session; save(session) }
        stream?.yield(.statusChanged(status))
        if let error { stream?.finish(throwing: error) }
        else { if status == .completed { stream?.yield(.finished) }; stream?.finish() }
    }
    private func disconnected() {
        initialized = false
        for id in Array(streams.keys) { finish(id, status: .failed, error: AgentConnectionError.transportFailed("Codex connection lost. Reconnect to resume.")) }
    }
    private static func summary(_ diff: String) -> GitStatusSummary {
        var files: [GitFileDiff] = []
        var path: String?
        var lines: [String] = []
        func appendFile() {
            guard let path else { return }
            files.append(GitFileDiff(filePath: path, status: .modified,
                additions: lines.filter { $0.hasPrefix("+") && !$0.hasPrefix("+++") }.count,
                deletions: lines.filter { $0.hasPrefix("-") && !$0.hasPrefix("---") }.count, patch: lines.joined(separator: "\n")))
        }
        for line in diff.components(separatedBy: "\n") {
            if line.hasPrefix("diff --git ") { appendFile(); path = nil; lines = [] }
            if line.hasPrefix("+++ b/") { path = String(line.dropFirst(6)) }
            lines.append(line)
        }
        appendFile()
        return GitStatusSummary(branch: "remote changes", changedFiles: files)
    }
}
