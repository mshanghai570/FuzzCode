import Foundation

/// Lightweight on-device coding-agent engine built on Swift concurrency.
/// Runs an agent execution loop against any AIProvider: repository browsing,
/// file reading/editing, patch generation/application, diff previews, and
/// user-controlled tool permissions. No shell execution; filesystem access is
/// confined to the sandboxed WorkspaceManager root.
public actor NativeAgentEngine: AgentConnection {
    public static let maxTurns = 8

    /// Returns only an explicitly selected enabled provider, or the sole enabled provider.
    /// Ambiguous/missing selections must be resolved by the UI rather than silently choosing one.
    public static func configuredProvider(from providers: [ProviderConfig], selectedProviderID: UUID?) -> ProviderConfig? {
        let enabled = providers.filter(\.isEnabled)
        if let selectedProviderID {
            return enabled.first { $0.id == selectedProviderID }
        }
        return enabled.count == 1 ? enabled[0] : nil
    }

    public let id: UUID
    public let displayName: String
    public let kind: AgentConnectionKind = .native
    public let workspace: WorkspaceManager

    private let provider: any AIProvider
    private let storage: StorageService
    private let permissionHandler: @Sendable (PermissionRequest) async -> PermissionDecision
    private var cancelledSessionIDs = Set<String>()

    public var capabilities: Set<AgentCapability> {
        [.sessions, .streaming, .toolEvents, .cancellation, .fileDiffs, .permissionRequests, .sessionResumption]
    }

    public init(
        provider: any AIProvider,
        workspace: WorkspaceManager,
        storage: StorageService = .shared,
        id: UUID = UUID(),
        displayName: String = "FuzzCode Agent",
        permissionHandler: @Sendable @escaping (PermissionRequest) async -> PermissionDecision
    ) {
        self.id = id
        self.provider = provider
        self.workspace = workspace
        self.storage = storage
        self.displayName = displayName
        self.permissionHandler = permissionHandler
    }

    // MARK: - AgentConnection

    public func connect() async throws -> AgentHostMetadata {
        _ = try await provider.testConnection()
        return AgentHostMetadata(
            hostId: id.uuidString,
            name: displayName,
            version: "native-1.0",
            osName: "iOS (sandboxed)",
            defaultWorkspace: workspace.relativeString(of: workspace.root),
            capabilities: Array(capabilities)
        )
    }

    public func listSessions() async throws -> [AgentSession] {
        storage.loadAgentSessions().filter { $0.hostId == id }
    }

    public func createSession(workspacePath: String, prompt: String? = nil) async throws -> AgentSession {
        var sessions = storage.loadAgentSessions()
        let session = AgentSession(
            hostId: id,
            title: prompt?.isEmpty == false ? String(prompt!.prefix(40)) : "Native Session",
            workspacePath: workspacePath,
            connectionKind: .native,
            providerId: provider.id
        )
        sessions.insert(session, at: 0)
        storage.saveAgentSessions(sessions)
        return session
    }

    public func cancelTask(sessionId: String) async throws {
        cancelledSessionIDs.insert(sessionId)
    }
    public func resolvePermission(requestId: String, decision: PermissionDecision, rationale: String? = nil) async throws {
        // Native permissions resolve inline via permissionHandler; nothing to forward.
    }

    public func fetchGitStatus(sessionId: String) async throws -> GitStatusSummary {
        try workspace.changeSummary()
    }

    public func sendInstruction(sessionId: String, prompt: String) async -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await self.runLoop(sessionId: sessionId, prompt: prompt, continuation: continuation)
            }
        }
    }

    // MARK: - Execution loop

    private func runLoop(
        sessionId: String,
        prompt: String,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async {
        cancelledSessionIDs.remove(sessionId)
        var session = (storage.loadAgentSessions().first { $0.id == sessionId })
            ?? AgentSession(id: sessionId, hostId: id, title: String(prompt.prefix(40)), workspacePath: workspace.relativeString(of: workspace.root))
        session.status = .running
        session.connectionKind = .native
        session.providerId = provider.id
        session.messages.append(AgentSessionMessage(role: .user, content: prompt))
        let agentMessageId = UUID().uuidString
        session.messages.append(AgentSessionMessage(id: agentMessageId, role: .assistant, content: ""))
        persist(session)
        continuation.yield(.statusChanged(.running))

        let tools = Self.toolDefinitions()
        let history: [ChatMessage] = session.messages
            .filter { !$0.content.isEmpty }
            .map { ChatMessage(role: $0.role, content: $0.content) }
        var exchanges: [ProviderToolExchange] = []

        func emit(_ text: String) {
            continuation.yield(.textDelta(text))
            if let index = session.messages.firstIndex(where: { $0.id == agentMessageId }) {
                session.messages[index].content += text
            }
        }

        func finish(_ status: SessionStatus) {
            session.status = status
            persist(session)
            continuation.yield(.statusChanged(status))
            continuation.yield(.finished)
            continuation.finish()
        }

        do {
            for _ in 0..<Self.maxTurns {
                if cancelledSessionIDs.contains(sessionId) { finish(.cancelled); return }
                let turn: ProviderTurnResult
                do {
                    turn = try await provider.completeWithTools(
                        messages: history, systemPrompt: Self.systemPrompt, tools: tools, toolResults: exchanges)
                } catch AIProviderError.toolsUnsupported {
                    // Chat-only provider: single streamed turn, no tools.
                    let stream = await provider.streamChat(messages: history, systemPrompt: Self.systemPrompt)
                    for try await delta in stream { emit(delta) }
                    finish(.completed)
                    return
                }
                switch turn {
                case .message(let text):
                    emit(text)
                    finish(.completed)
                    return
                case .toolCalls(let calls):
                    var results: [ProviderToolResult] = []
                    var stopStatus: SessionStatus?
                    for call in calls {
                        if cancelledSessionIDs.contains(sessionId) { stopStatus = .cancelled; break }
                        var event = AgentToolEvent(
                            toolName: call.name,
                            argumentsJSON: String(decoding: call.arguments, as: UTF8.self),
                            status: .running)
                        continuation.yield(.toolStarted(event))
                        let outcome = await perform(call: call, sessionId: sessionId, continuation: continuation)
                        switch outcome {
                        case .succeeded(let output):
                            event.status = .success
                            event.outputSnippet = output
                            results.append(ProviderToolResult(toolCallID: call.id, content: output))
                        case .denied(let output):
                            event.status = .denied
                            event.outputSnippet = output
                            results.append(ProviderToolResult(toolCallID: call.id, content: output))
                            stopStatus = .failed
                        case .cancelled:
                            event.status = .failed
                            event.outputSnippet = "Cancelled before execution."
                            stopStatus = .cancelled
                        case .failed(let output):
                            event.status = .failed
                            event.outputSnippet = output
                            results.append(ProviderToolResult(toolCallID: call.id, content: output))
                        }
                        event.completedAt = Date()
                        if let index = session.messages.firstIndex(where: { $0.id == agentMessageId }) {
                            session.messages[index].toolEvents.append(event)
                        }
                        persist(session)
                        continuation.yield(.toolCompleted(toolId: event.id, output: event.outputSnippet ?? "", success: event.status == .success))
                        if stopStatus != nil { break }
                    }
                    if let stopStatus { finish(stopStatus); return }
                    exchanges.append(ProviderToolExchange(calls: calls, results: results))
                }
            }
            finish(.completed)
        } catch {
            session.status = .failed
            persist(session)
            continuation.yield(.error(error.localizedDescription))
            continuation.finish(throwing: error)
        }
    }

    private func persist(_ session: AgentSession) {
        var sessions = storage.loadAgentSessions()
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        storage.saveAgentSessions(sessions)
    }

    // MARK: - Tools

    static func toolDefinitions() -> [ProviderToolDefinition] {
        func schema(_ properties: [String: String], required: [String]) -> MCPToolInputSchema {
            MCPToolInputSchema(
                type: "object",
                properties: Dictionary(uniqueKeysWithValues: properties.map {
                    ($0.key, MCPToolParameterProperty(type: $0.value))
                }),
                required: required
            )
        }
        return [
            ProviderToolDefinition(name: "list_files",
                description: "List files in the sandboxed workspace directory.",
                inputSchema: schema(["path": "string"], required: [])),
            ProviderToolDefinition(name: "read_file",
                description: "Read a file from the sandboxed workspace.",
                inputSchema: schema(["path": "string"], required: ["path"])),
            ProviderToolDefinition(name: "write_file",
                description: "Create or overwrite a file. Requires user approval.",
                inputSchema: schema(["path": "string", "content": "string"], required: ["path", "content"])),
            ProviderToolDefinition(name: "apply_patch",
                description: "Apply a unified diff patch. Requires user approval. Show the preview to the user.",
                inputSchema: schema(["patch": "string"], required: ["patch"])),
            ProviderToolDefinition(name: "search_files",
                description: "Search text in the bounded sandboxed repository workspace.",
                inputSchema: schema(["query": "string"], required: ["query"]))
        ]
    }

    static let systemPrompt = """
        You are FuzzCode Agent, an on-device coding assistant. You can only access \
        files inside the sandboxed workspace via the provided tools. Never claim to run \
        shell commands, access files outside the workspace, or use tools you were not given. \
        Use search_files to find relevant code. Prefer read_file before editing. After apply_patch or write_file, summarize the diff preview.
        """

    private enum ToolOutcome {
        case succeeded(String)
        case denied(String)
        case cancelled
        case failed(String)
    }

    private func perform(
        call: ProviderToolCall,
        sessionId: String,
        continuation: AsyncThrowingStream<AgentEvent, Error>.Continuation
    ) async -> ToolOutcome {
        guard let tool = WorkspaceAgentTool(rawValue: call.name) else {
            return .failed("Error: unknown tool \(call.name).")
        }
        let prepared: PreparedAgentTool
        do {
            prepared = try tool.prepare(arguments: call.arguments, workspace: workspace)
        } catch {
            return .failed("Error: \(error.localizedDescription)")
        }

        if let permission = prepared.permission {
            continuation.yield(.permissionRequested(permission))
            let decision = await permissionHandler(permission)
            // Cancellation wins over a late approval: never execute after the user cancels.
            if cancelledSessionIDs.contains(sessionId) { return .cancelled }
            guard decision == .allowOnce || decision == .allowAlways else { return .denied("Denied by user.") }
            if cancelledSessionIDs.contains(sessionId) { return .cancelled }
        }

        do {
            return .succeeded(try prepared.execute())
        } catch {
            return .failed("Error: \(error.localizedDescription)")
        }
    }
}
