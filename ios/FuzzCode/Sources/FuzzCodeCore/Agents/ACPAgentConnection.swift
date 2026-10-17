import Foundation

/// ACP v1 over a remote WebSocket bridge. Agent-side filesystem/terminal operations stay on the host.
public actor ACPAgentConnection: AgentConnection {
    public let id: UUID
    public let displayName: String
    public let kind: AgentConnectionKind
    public private(set) var capabilities: Set<AgentCapability> = []
    private let config: OpenCodeHostConfig
    private let transport: any ACPTransport
    private let storage: StorageService
    private var initialized = false
    private var supportsList = false
    private var listener: Task<Void, Never>?
    private var sessions: [String: AgentSession] = [:]
    private var streams: [String: AsyncThrowingStream<AgentEvent, Error>.Continuation] = [:]
    private var turns: [String: Task<Void, Never>] = [:]
    private struct Approval {
        let id: AgentJSONValue
        let session: String
        let options: [AgentJSONValue]
    }
    private var approvals: [String: Approval] = [:]

    public init(hostConfig: OpenCodeHostConfig, transport: any ACPTransport, storage: StorageService = .shared) {
        id = hostConfig.id; displayName = hostConfig.displayName; kind = hostConfig.resolvedKind
        config = hostConfig; self.transport = transport; self.storage = storage
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
                let response = try await transport.request(method: "initialize", params: .object([
                    "protocolVersion": .number(1),
                    "clientInfo": .object(["name": .string("fuzzcode"), "version": .string("1.0")]),
                    "clientCapabilities": .object([
                        "fs": .object(["readTextFile": .bool(false), "writeTextFile": .bool(false)]),
                        "terminal": .bool(false)])]))
                guard let object = response.rpcObject, object["protocolVersion"]?.rpcNumber == 1 else {
                    throw AgentConnectionError.notSupported("ACP protocol version")
                }
                let advertised = object["agentCapabilities"]?.rpcObject ?? [:]
                capabilities = [.sessions, .streaming, .toolEvents, .cancellation, .permissionRequests]
                if advertised["loadSession"]?.rpcBool == true { capabilities.insert(.sessionResumption) }
                supportsList = advertised["sessionCapabilities"]?.rpcObject?["list"]?.rpcObject != nil
                initialized = true
                let agent = object["agentInfo"]?.rpcObject ?? [:]
                return metadata(name: agent["name"]?.rpcString ?? displayName, version: agent["version"]?.rpcString ?? "ACP v1")
            } catch {
                listener?.cancel(); listener = nil
                await transport.disconnect()
                throw error
            }
        }
        return metadata(name: displayName, version: "ACP v1")
    }

    private func metadata(name: String, version: String) -> AgentHostMetadata {
        AgentHostMetadata(hostId: id.uuidString, name: name, version: version, osName: "Remote runtime",
            defaultWorkspace: config.currentWorkspace, capabilities: Array(capabilities))
    }

    public func listSessions() async throws -> [AgentSession] {
        _ = try await connect()
        if supportsList {
            let response = try await transport.request(method: "session/list", params: .object([:]))
            for value in response.rpcObject?["sessions"]?.rpcArray ?? [] {
                guard let object = value.rpcObject, let sessionID = object["sessionId"]?.rpcString else { continue }
                let session = stored(sessionID) ?? AgentSession(id: sessionID, hostId: id,
                    title: object["title"]?.rpcString ?? "ACP session", workspacePath: object["cwd"]?.rpcString ?? "",
                    connectionKind: kind)
                sessions[sessionID] = session; save(session)
            }
        }
        return storage.loadAgentSessions().filter { $0.hostId == id }.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func createSession(workspacePath: String, prompt: String?) async throws -> AgentSession {
        _ = try await connect()
        let response = try await transport.request(method: "session/new", params: .object([
            "cwd": .string(workspacePath), "mcpServers": .array([])]))
        guard let sessionID = response.rpcObject?["sessionId"]?.rpcString else { throw AgentConnectionError.invalidResponse }
        let session = AgentSession(id: sessionID, hostId: id, title: prompt?.isEmpty == false ? String(prompt!.prefix(60)) : "ACP session",
            workspacePath: workspacePath, connectionKind: kind)
        sessions[sessionID] = session; save(session)
        return session
    }

    public func resumeSession(sessionId: String, workspacePath: String) async throws -> AgentSession {
        _ = try await connect()
        guard capabilities.contains(.sessionResumption) else { throw AgentConnectionError.notSupported("ACP session/load") }
        sessions[sessionId] = stored(sessionId) ?? AgentSession(id: sessionId, hostId: id,
            title: "ACP session", workspacePath: workspacePath, connectionKind: kind)
        _ = try await transport.request(method: "session/load", params: .object([
            "sessionId": .string(sessionId), "cwd": .string(workspacePath), "mcpServers": .array([])]))
        return sessions[sessionId]!
    }

    public func sendInstruction(sessionId: String, prompt: String) async -> AsyncThrowingStream<AgentEvent, Error> {
        guard turns[sessionId] == nil else {
            return AsyncThrowingStream { $0.finish(throwing: AgentConnectionError.notSupported("Concurrent turns in one session")) }
        }
        return AsyncThrowingStream { continuation in
            streams[sessionId] = continuation
            turns[sessionId] = Task {
                do {
                    _ = try await self.connect()
                    self.recordUser(sessionId, prompt: prompt)
                    continuation.yield(.statusChanged(.running))
                    let response = try await self.transport.request(method: "session/prompt", params: .object([
                        "sessionId": .string(sessionId), "prompt": .array([.object(["type": .string("text"), "text": .string(prompt)])])]), timeoutSeconds: 600)
                    let cancelled = response.rpcObject?["stopReason"]?.rpcString == "cancelled"
                    await self.finish(sessionId, status: cancelled ? .cancelled : .completed)
                } catch {
                    await self.finish(sessionId, status: Task.isCancelled ? .cancelled : .failed, error: Task.isCancelled ? nil : error)
                }
            }
            continuation.onTermination = { @Sendable _ in Task { await self.cancelIfRunning(sessionId) } }
        }
    }

    public func cancelTask(sessionId: String) async throws {
        turns[sessionId]?.cancel()
        for (key, approval) in approvals where approval.session == sessionId {
            try? await transport.respond(id: approval.id, result: .object(["outcome": .object(["outcome": .string("cancelled")])]))
            approvals.removeValue(forKey: key)
        }
        try await transport.notify(method: "session/cancel", params: .object(["sessionId": .string(sessionId)]))
        await finish(sessionId, status: .cancelled)
    }

    private func cancelIfRunning(_ session: String) async {
        if turns[session] != nil { try? await cancelTask(sessionId: session) }
    }

    public func resolvePermission(requestId: String, decision: PermissionDecision, rationale: String?) async throws {
        guard let approval = approvals.removeValue(forKey: requestId) else { throw AgentConnectionError.invalidResponse }
        let optionKind: String
        switch decision { case .allowOnce: optionKind = "allow_once"; case .allowAlways: optionKind = "allow_always"; case .deny: optionKind = "reject_once" }
        let optionID = approval.options.first { $0.rpcObject?["kind"]?.rpcString == optionKind }?.rpcObject?["optionId"]?.rpcString
        let outcome: AgentJSONValue = optionID.map { .object(["outcome": .string("selected"), "optionId": .string($0)]) }
            ?? .object(["outcome": .string("cancelled")])
        try await transport.respond(id: approval.id, result: .object(["outcome": outcome]))
    }

    public func fetchGitStatus(sessionId: String) async throws -> GitStatusSummary {
        throw AgentConnectionError.notSupported("ACP git status; review streamed tool diffs")
    }

    private func handle(_ message: AgentRPCMessage) async {
        guard let method = message.method, let params = message.params?.rpcObject,
              let sessionID = params["sessionId"]?.rpcString else { return }
        if method == "session/request_permission", let rpcID = message.id {
            guard let stream = streams[sessionID] else {
                try? await transport.respond(id: rpcID, result: .object(["outcome": .object(["outcome": .string("cancelled")])]))
                return
            }
            let tool = params["toolCall"]?.rpcObject ?? [:]
            let request = PermissionRequest(toolName: tool["title"]?.rpcString ?? "Remote tool",
                commandOrPath: tool["title"]?.rpcString ?? "Remote action", fullParameters: ["preview": String(describing: tool)], riskLevel: .high)
            approvals[request.id] = Approval(id: rpcID, session: sessionID, options: params["options"]?.rpcArray ?? [])
            stream.yield(.permissionRequested(request)); return
        }
        guard method == "session/update", let update = params["update"]?.rpcObject,
              let updateKind = update["sessionUpdate"]?.rpcString else { return }
        let stream = streams[sessionID]
        if updateKind == "agent_message_chunk", let text = update["content"]?.rpcObject?["text"]?.rpcString {
            stream?.yield(.textDelta(text)); recordText(sessionID, text: text)
        } else if updateKind == "tool_call" || updateKind == "tool_call_update" {
            guard let toolID = update["toolCallId"]?.rpcString else { return }
            let status = update["status"]?.rpcString ?? "in_progress"
            if updateKind == "tool_call" {
                stream?.yield(.toolStarted(AgentToolEvent(id: toolID, toolName: update["title"]?.rpcString ?? "Tool", argumentsJSON: "{}")))
            }
            if status == "completed" || status == "failed" {
                let output = (update["content"]?.rpcArray ?? []).compactMap { $0.rpcObject?["content"]?.rpcObject?["text"]?.rpcString }.joined(separator: "\n")
                stream?.yield(.toolCompleted(toolId: toolID, output: output, success: status == "completed"))
            }
        }
    }

    private func stored(_ id: String) -> AgentSession? { storage.loadAgentSessions().first { $0.id == id && $0.hostId == self.id } }
    private func save(_ session: AgentSession) {
        var all = storage.loadAgentSessions()
        if let index = all.firstIndex(where: { $0.id == session.id && $0.hostId == session.hostId }) { all[index] = session }
        else { all.insert(session, at: 0) }
        storage.saveAgentSessions(all)
    }
    private func recordUser(_ id: String, prompt: String) {
        var session = sessions[id] ?? stored(id) ?? AgentSession(id: id, hostId: self.id, title: String(prompt.prefix(60)), workspacePath: "", connectionKind: kind)
        session.messages.append(AgentSessionMessage(role: .user, content: prompt))
        session.messages.append(AgentSessionMessage(role: .assistant, content: ""))
        session.status = .running; session.updatedAt = Date(); sessions[id] = session; save(session)
    }
    private func recordText(_ id: String, text: String) {
        guard var session = sessions[id], let last = session.messages.indices.last, session.messages[last].role == .assistant else { return }
        session.messages[last].content += text; session.updatedAt = Date(); sessions[id] = session; save(session)
    }
    private func finish(_ id: String, status: SessionStatus, error: Error? = nil) async {
        let stream = streams.removeValue(forKey: id)
        turns.removeValue(forKey: id)
        if var session = sessions[id] { session.status = status; session.updatedAt = Date(); sessions[id] = session; save(session) }
        stream?.yield(.statusChanged(status))
        if let error { stream?.finish(throwing: error) }
        else { if status == .completed { stream?.yield(.finished) }; stream?.finish() }
    }
    private func disconnected() async {
        initialized = false
        for id in Array(streams.keys) { await finish(id, status: .failed, error: AgentConnectionError.transportFailed("ACP connection lost. Reconnect to resume.")) }
    }
}
