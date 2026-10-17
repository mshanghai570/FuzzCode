import Foundation

/// The stock `opencode serve` API. The older FuzzCode companion remains a separate adapter.
public actor OpenCodeHTTPConnection: AgentConnection {
    public nonisolated let id: UUID
    public nonisolated let displayName: String
    public nonisolated let kind: AgentConnectionKind = .opencode
    public nonisolated let capabilities: Set<AgentCapability> = [
        .sessions, .sessionResumption, .streaming, .toolEvents, .permissionRequests,
        .cancellation, .fileDiffs, .projectSelection
    ]
    public typealias EventPerformer = @Sendable (URLRequest) async throws -> (AsyncThrowingStream<String, Error>, URLResponse)
    private let config: OpenCodeHostConfig
    private let credentials: any CredentialStore
    private let endpoint: URL
    private let perform: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let events: EventPerformer?
    private let session: URLSession
    private var directories: [String: String] = [:]
    private struct PermissionContext { let sessionID: String; let modern: Bool }
    private var permissions: [String: PermissionContext] = [:]
    private struct Turn { let id: UUID; let task: Task<Void, Never>; let continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation }
    private var turns: [String: Turn] = [:]

    public init(hostConfig: OpenCodeHostConfig, credentialStore: any CredentialStore = KeychainCredentialStore(),
                session: URLSession = .shared,
                requestPerformer: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil,
                eventPerformer: EventPerformer? = nil) throws {
        guard hostConfig.resolvedProtocol == .openCodeHTTP, hostConfig.resolvedKind == .opencode else {
            throw AgentConnectionError.notSupported("This adapter requires stock OpenCode HTTP.")
        }
        self.endpoint = try hostConfig.validatedEndpoint()
        self.id = hostConfig.id; self.displayName = hostConfig.displayName
        self.config = hostConfig; self.credentials = credentialStore
        self.perform = requestPerformer ?? { try await session.data(for: $0) }
        self.events = eventPerformer
        self.session = session
    }

    private func request(_ components: [String], method: String = "GET", directory: String? = nil,
                         body: [String: Any]? = nil) throws -> URLRequest {
        var url = endpoint
        for component in components {
            guard !component.isEmpty, !component.contains("/"), component != ".", component != ".." else {
                throw AgentConnectionError.invalidResponse
            }
            url.appendPathComponent(component)
        }
        var parsed = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        if let directory, !directory.isEmpty { parsed.queryItems = [URLQueryItem(name: "directory", value: directory)] }
        guard let result = parsed.url else { throw AgentConnectionError.invalidResponse }
        var request = try config.authenticatedRequest(url: result, credentials: credentials)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            // Never surface a response body or URL that might contain server secrets.
            throw AgentConnectionError.transportFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
    }

    private func json(_ components: [String], method: String = "GET", directory: String? = nil,
                      body: [String: Any]? = nil) async throws -> Any {
        let outgoing = try request(components, method: method, directory: directory, body: body)
        let result: (Data, URLResponse)
        do { result = try await perform(outgoing) }
        catch let error as AgentConnectionError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch { throw AgentConnectionError.transportFailed("The HTTP request failed.") }
        try validate(result.1)
        if result.0.isEmpty { return NSNull() }
        guard let object = try? JSONSerialization.jsonObject(with: result.0, options: [.fragmentsAllowed]) else {
            throw AgentConnectionError.invalidResponse
        }
        return object
    }

    public func connect() async throws -> AgentHostMetadata {
        guard let health = try await json(["global", "health"]) as? [String: Any],
              health["healthy"] as? Bool == true, let version = health["version"] as? String else {
            throw AgentConnectionError.invalidResponse
        }
        return AgentHostMetadata(hostId: id.uuidString, name: displayName, version: version, osName: "Remote",
                                 defaultWorkspace: config.currentWorkspace, capabilities: Array(capabilities))
    }

    private func session(_ object: [String: Any], fallbackDirectory: String = "") throws -> AgentSession {
        guard let sessionID = object["id"] as? String, !sessionID.isEmpty else { throw AgentConnectionError.invalidResponse }
        let directory = object["directory"] as? String ?? fallbackDirectory
        directories[sessionID] = directory
        let time = object["time"] as? [String: Double] ?? [:]
        return AgentSession(id: sessionID, hostId: id, title: object["title"] as? String ?? "OpenCode session",
            workspacePath: directory, createdAt: Date(timeIntervalSince1970: (time["created"] ?? 0) / 1000),
            updatedAt: Date(timeIntervalSince1970: (time["updated"] ?? 0) / 1000), connectionKind: .opencode)
    }

    public func listSessions() async throws -> [AgentSession] {
        guard let objects = try await json(["session"], directory: config.currentWorkspace) as? [[String: Any]] else {
            throw AgentConnectionError.invalidResponse
        }
        return try objects.map { try session($0, fallbackDirectory: config.currentWorkspace ?? "") }
    }

    public func createSession(workspacePath: String, prompt: String? = nil) async throws -> AgentSession {
        guard let object = try await json(["session"], method: "POST", directory: workspacePath,
            body: prompt.map { ["title": String($0.prefix(80))] } ?? [:]) as? [String: Any] else {
            throw AgentConnectionError.invalidResponse
        }
        return try session(object, fallbackDirectory: workspacePath)
    }

    public func resumeSession(sessionId: String, workspacePath: String) async throws -> AgentSession {
        guard let object = try await json(["session", sessionId], directory: workspacePath) as? [String: Any] else {
            throw AgentConnectionError.invalidResponse
        }
        guard object["id"] as? String == sessionId else { throw AgentConnectionError.invalidResponse }
        var restored = try session(object, fallbackDirectory: workspacePath)
        guard let messages = try await json(["session", sessionId, "message"], directory: restored.workspacePath) as? [[String: Any]] else {
            throw AgentConnectionError.invalidResponse
        }
        restored.messages = messages.compactMap { message in
            guard let info = message["info"] as? [String: Any], let messageID = info["id"] as? String,
                  let roleString = info["role"] as? String, let role = MessageRole(rawValue: roleString) else { return nil }
            let content = (message["parts"] as? [[String: Any]] ?? []).filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }.joined()
            return AgentSessionMessage(id: messageID, role: role, content: content)
        }
        return restored
    }

    public func sendInstruction(sessionId: String, prompt: String) async -> AsyncThrowingStream<AgentEvent, Error> {
        let pair = AsyncThrowingStream<AgentEvent, Error>.makeStream()
        guard turns[sessionId] == nil else {
            pair.continuation.finish(throwing: AgentConnectionError.transportFailed("A turn is already running for this session."))
            return pair.stream
        }
        let turnID = UUID()
        let task = Task { await run(sessionID: sessionId, prompt: prompt, turnID: turnID, continuation: pair.continuation) }
        turns[sessionId] = Turn(id: turnID, task: task, continuation: pair.continuation)
        pair.continuation.onTermination = { _ in task.cancel() }
        return pair.stream
    }

    private func run(sessionID: String, prompt: String, turnID: UUID,
                     continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation) async {
        defer { if turns[sessionID]?.id == turnID { turns[sessionID] = nil } }
        do {
            var subscription = try request(["event"], directory: directories[sessionID] ?? config.currentWorkspace)
            subscription.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            subscription.timeoutInterval = 300
            let lines: AsyncThrowingStream<String, Error>
            let response: URLResponse
            let stop: @Sendable () -> Void
            if let events {
                (lines, response) = try await events(subscription)
                stop = {}
            } else {
                let (bytes, receivedResponse) = try await session.bytes(for: subscription)
                response = receivedResponse
                let pair = AsyncThrowingStream<String, Error>.makeStream()
                let producer = Task {
                    do {
                        for try await line in bytes.lines {
                            try Task.checkCancellation()
                            pair.continuation.yield(line)
                        }
                        pair.continuation.finish()
                    } catch { pair.continuation.finish(throwing: error) }
                }
                stop = { producer.cancel(); bytes.task.cancel(); pair.continuation.finish() }
                pair.continuation.onTermination = { _ in producer.cancel(); bytes.task.cancel() }
                lines = pair.stream
            }
            // Close the SSE HTTP request on completion, failure, or cancellation, including an early idle event.
            defer { stop() }
            try validate(response)
            guard (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true else {
                throw AgentConnectionError.invalidResponse
            }
            var dataLines: [String] = [], submitted = false
            var roles: [String: String] = [:], text: [String: String] = [:]
            var startedTools: Set<String> = [], completedTools: Set<String> = []
            for try await rawLine in lines {
                try Task.checkCancellation()
                let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
                if line.hasPrefix("data:") {
                    var value = String(line.dropFirst(5)); if value.first == " " { value.removeFirst() }
                    dataLines.append(value); continue
                }
                guard line.isEmpty, !dataLines.isEmpty else { continue }
                let payload = dataLines.joined(separator: "\n"); dataLines.removeAll()
                guard let event = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                      let type = event["type"] as? String else { throw AgentConnectionError.invalidResponse }
                let properties = event["properties"] as? [String: Any] ?? [:]
                if type == "server.connected", !submitted {
                    try Task.checkCancellation()
                    _ = try await json(["session", sessionID, "prompt_async"], method: "POST",
                        directory: directories[sessionID] ?? config.currentWorkspace,
                        body: ["parts": [["type": "text", "text": prompt]]])
                    submitted = true; continuation.yield(.statusChanged(.running)); continue
                }
                guard submitted else { continue }
                let part = properties["part"] as? [String: Any] ?? [:]
                let info = properties["info"] as? [String: Any] ?? [:]
                guard (properties["sessionID"] as? String ?? part["sessionID"] as? String ?? info["sessionID"] as? String) == sessionID else { continue }
                switch type {
                case "message.updated":
                    if let messageID = info["id"] as? String { roles[messageID] = info["role"] as? String }
                case "message.part.delta":
                    guard properties["field"] as? String == "text", let delta = properties["delta"] as? String,
                          let partID = properties["partID"] as? String,
                          roles[properties["messageID"] as? String ?? ""] == "assistant" else { continue }
                    text[partID, default: ""] += delta; continuation.yield(.textDelta(delta))
                case "message.part.updated":
                    guard let partID = part["id"] as? String else { continue }
                    if part["type"] as? String == "text", roles[part["messageID"] as? String ?? ""] == "assistant" {
                        if let delta = properties["delta"] as? String, !delta.isEmpty {
                            text[partID, default: ""] += delta; continuation.yield(.textDelta(delta))
                        } else if let snapshot = part["text"] as? String {
                            let previous = text[partID] ?? ""
                            if snapshot.hasPrefix(previous) {
                                let delta = String(snapshot.dropFirst(previous.count))
                                if !delta.isEmpty { continuation.yield(.textDelta(delta)) }
                            }
                            text[partID] = snapshot
                        }
                    } else if part["type"] as? String == "tool", let state = part["state"] as? [String: Any] {
                        let toolID = part["callID"] as? String ?? partID
                        if startedTools.insert(toolID).inserted {
                            let arguments = state["input"].flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
                            continuation.yield(.toolStarted(AgentToolEvent(id: toolID, toolName: part["tool"] as? String ?? "tool",
                                argumentsJSON: arguments.flatMap { String(data: $0, encoding: .utf8) } ?? "{}")))
                        }
                        if ["completed", "error"].contains(state["status"] as? String ?? ""), completedTools.insert(toolID).inserted {
                            continuation.yield(.toolCompleted(toolId: toolID, output: state["output"] as? String ?? state["error"] as? String ?? "",
                                                             success: state["status"] as? String == "completed"))
                        }
                    }
                case "permission.asked", "permission.updated":
                    guard let permissionID = properties["id"] as? String else { throw AgentConnectionError.invalidResponse }
                    permissions[permissionID] = PermissionContext(sessionID: sessionID, modern: type == "permission.asked")
                    let metadata = properties["metadata"] as? [String: Any] ?? [:]
                    let parameters = metadata.mapValues { value -> String in
                        if let string = value as? String { return string }
                        if let encoded = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys]),
                           let string = String(data: encoded, encoding: .utf8) { return string }
                        return ""
                    }
                    continuation.yield(.permissionRequested(PermissionRequest(id: permissionID,
                        toolName: properties["permission"] as? String ?? properties["type"] as? String ?? "tool",
                        commandOrPath: (properties["patterns"] as? [String])?.joined(separator: "\n") ?? properties["title"] as? String ?? "",
                        fullParameters: parameters)))
                    continuation.yield(.statusChanged(.waitingPermission))
                case "permission.replied":
                    if let requestID = properties["requestID"] as? String { permissions[requestID] = nil }
                    continuation.yield(.statusChanged(.running))
                case "session.status":
                    let status = (properties["status"] as? [String: Any])?["type"] as? String
                    if status == "idle" { continuation.yield(.statusChanged(.completed)); continuation.yield(.finished); continuation.finish(); return }
                    continuation.yield(.statusChanged(.running))
                case "session.idle":
                    continuation.yield(.statusChanged(.completed)); continuation.yield(.finished); continuation.finish(); return
                case "session.error":
                    throw AgentConnectionError.remoteError("The OpenCode session failed.")
                default: break
                }
            }
            try Task.checkCancellation()
            throw AgentConnectionError.transportFailed("Event stream ended before the turn completed.")
        } catch is CancellationError { continuation.finish(throwing: CancellationError()) }
        catch let error as AgentConnectionError { continuation.finish(throwing: error) }
        catch { continuation.finish(throwing: AgentConnectionError.transportFailed("The event stream failed.")) }
    }

    public func cancelTask(sessionId: String) async throws {
        let turn = turns.removeValue(forKey: sessionId)
        turn?.task.cancel(); turn?.continuation.yield(.statusChanged(.cancelled)); turn?.continuation.finish()
        let result = try await json(["session", sessionId, "abort"], method: "POST", directory: directories[sessionId] ?? config.currentWorkspace)
        guard result as? Bool == true else { throw AgentConnectionError.invalidResponse }
        permissions = permissions.filter { $0.value.sessionID != sessionId }
    }

    public func resolvePermission(requestId: String, decision: PermissionDecision, rationale: String? = nil) async throws {
        guard let context = permissions[requestId] else { throw AgentConnectionError.invalidResponse }
        let reply: String
        switch decision { case .allowOnce: reply = "once"; case .allowAlways: reply = "always"; case .deny: reply = "reject" }
        let path = context.modern ? ["permission", requestId, "reply"] : ["session", context.sessionID, "permissions", requestId]
        var body: [String: Any] = [context.modern ? "reply" : "response": reply]
        if context.modern, decision == .deny, let rationale { body["message"] = rationale }
        let result = try await json(path, method: "POST", directory: directories[context.sessionID] ?? config.currentWorkspace, body: body)
        guard result as? Bool == true else { throw AgentConnectionError.invalidResponse }
        permissions[requestId] = nil
    }

    public func fetchGitStatus(sessionId: String) async throws -> GitStatusSummary {
        let directory = directories[sessionId] ?? config.currentWorkspace
        guard let files = try await json(["session", sessionId, "diff"], directory: directory) as? [[String: Any]] else {
            throw AgentConnectionError.invalidResponse
        }
        let changes = try files.map { file -> GitFileDiff in
            guard let path = file["file"] as? String, let before = file["before"] as? String,
                  let after = file["after"] as? String else { throw AgentConnectionError.invalidResponse }
            func lines(_ content: String) -> [String] {
                guard !content.isEmpty else { return [] }
                var result = content.components(separatedBy: "\n")
                if content.hasSuffix("\n") { result.removeLast() }
                return result
            }
            let old = lines(before), new = lines(after)
            let patch = "--- a/\(path)\n+++ b/\(path)\n@@ -\(old.isEmpty ? 0 : 1),\(old.count) +\(new.isEmpty ? 0 : 1),\(new.count) @@\n" +
                old.map { "-" + $0 }.joined(separator: "\n") + "\n" + new.map { "+" + $0 }.joined(separator: "\n")
            let status: GitFileStatus = before.isEmpty ? .added : (after.isEmpty ? .deleted : .modified)
            return GitFileDiff(filePath: path, status: status, additions: file["additions"] as? Int ?? 0,
                               deletions: file["deletions"] as? Int ?? 0, patch: patch)
        }
        // OpenCode session diffs do not expose upstream ahead/behind counts, so `.gitStatus` is not advertised.
        return GitStatusSummary(branch: "", changedFiles: changes)
    }
}
