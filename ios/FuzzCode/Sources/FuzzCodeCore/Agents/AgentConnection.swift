import Foundation

// MARK: - Abstractions

public enum AgentConnectionKind: String, Codable, Sendable {
    case native = "native"
    case opencode = "opencode"
    case codex = "codex"
    case claudeCode = "claude_code"
    case customACP = "custom_acp"

    public var displayName: String {
        switch self {
        case .native: return "FuzzCode Agent"
        case .opencode: return "OpenCode"
        case .codex: return "Codex"
        case .claudeCode: return "Claude Code"
        case .customACP: return "Custom ACP Agent"
        }
    }

    /// Remote kinds need a reachable runtime; native runs on-device.
    public var requiresRemoteRuntime: Bool { self != .native }
}

/// Modular abstraction for a coding-agent connection (native engine or remote runtime).
/// Property requirements are async so actor-backed engines (e.g. the native engine)
/// can conform without crossing isolation boundaries.
public protocol AgentConnection: Sendable {
    var id: UUID { get async }
    var displayName: String { get async }
    var kind: AgentConnectionKind { get async }
    var capabilities: Set<AgentCapability> { get async }

    func connect() async throws -> AgentHostMetadata
    func listSessions() async throws -> [AgentSession]
    func createSession(workspacePath: String, prompt: String?) async throws -> AgentSession
    func sendInstruction(sessionId: String, prompt: String) async -> AsyncThrowingStream<AgentEvent, Error>
    func resumeSession(sessionId: String, workspacePath: String) async throws -> AgentSession
    func cancelTask(sessionId: String) async throws
    func resolvePermission(requestId: String, decision: PermissionDecision, rationale: String?) async throws
    func fetchGitStatus(sessionId: String) async throws -> GitStatusSummary
}

public extension AgentConnection {
    func resumeSession(sessionId: String, workspacePath: String) async throws -> AgentSession {
        guard let session = try await listSessions().first(where: { $0.id == sessionId }) else {
            throw AgentConnectionError.notSupported("Session resumption")
        }
        return session
    }
}

/// Transport abstraction for Agent Client Protocol (ACP) JSON-RPC traffic.
/// Concrete transports: HTTP POST (remote daemons), WebSocket/stdio (future).


/// Generic JSON-RPC 2.0 transport over HTTPS POST with Bearer auth from a CredentialStore.
/// Used as the adapter for agents that expose a native HTTP API.
public struct HTTPACPTransport {
    private let endpoint: URL
    private let credentialKey: String?
    private let credentialStore: CredentialStore
    private let session: URLSession
    private let requestPerformer: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(
        endpoint: URL,
        credentialKey: String? = nil,
        credentialStore: CredentialStore = KeychainCredentialStore(),
        session: URLSession = .shared,
        requestPerformer: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil
    ) {
        self.endpoint = endpoint
        self.credentialKey = credentialKey
        self.credentialStore = credentialStore
        self.session = session
        self.requestPerformer = requestPerformer ?? { try await session.data(for: $0) }
    }

    public func send(method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let credentialKey, let token = credentialStore.retrieve(key: credentialKey), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let body: [String: Any] = ["jsonrpc": "2.0", "id": UUID().uuidString, "method": method, "params": params]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await requestPerformer(request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw AgentConnectionError.transportFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AgentConnectionError.invalidResponse
        }
        if let error = object["error"] as? [String: Any] {
            throw AgentConnectionError.remoteError(error["message"] as? String ?? "Unknown remote error")
        }
        guard let result = object["result"] as? [String: Any] else {
            throw AgentConnectionError.invalidResponse
        }
        return result
    }
}

public enum AgentConnectionError: Error, LocalizedError, Equatable {
    case transportFailed(String)
    case invalidResponse
    case remoteError(String)
    case notSupported(String)

    public var errorDescription: String? {
        switch self {
        case .transportFailed(let detail): return "Agent transport failed: \(detail)"
        case .invalidResponse: return "The agent returned an unexpected response."
        case .remoteError(let message): return "Agent error: \(message)"
        case .notSupported(let what): return "\(what) is not supported by this connection."
        }
    }
}

// MARK: - Remote agent descriptors

/// Describes a remote coding agent. Descriptor-only kinds (codex, claudeCode, customACP)
/// are experimental: they need a compatible remote runtime and do not assume a shared protocol.
public struct RemoteAgentDescriptor: Identifiable, Sendable {
    public let id: String
    public let kind: AgentConnectionKind
    public let defaultPort: Int?
    public let defaultPath: String
    public let capabilities: Set<AgentCapability>
    public let isExperimental: Bool
    public let notes: String

    public static let opencode = RemoteAgentDescriptor(
        id: "opencode", kind: .opencode, defaultPort: 4096, defaultPath: "api/v1",
        capabilities: [.sessions, .streaming, .toolEvents, .cancellation, .fileDiffs, .permissionRequests, .gitStatus, .sessionResumption],
        isExperimental: false,
        notes: "Native HTTP API adapter (OpenCodeClient). Preserves existing host pairing."
    )
    public static let codex = RemoteAgentDescriptor(
        id: "codex", kind: .codex, defaultPort: nil, defaultPath: "",
        capabilities: [.sessions, .streaming],
        isExperimental: true,
        notes: "Requires a Codex-compatible remote runtime. No shared protocol assumed."
    )
    public static let claudeCode = RemoteAgentDescriptor(
        id: "claude-code", kind: .claudeCode, defaultPort: nil, defaultPath: "",
        capabilities: [.sessions, .streaming],
        isExperimental: true,
        notes: "Requires a Claude Code-compatible remote runtime. No shared protocol assumed."
    )
    public static let customACP = RemoteAgentDescriptor(
        id: "custom-acp", kind: .customACP, defaultPort: nil, defaultPath: "",
        capabilities: [.sessions, .streaming, .toolEvents],
        isExperimental: true,
        notes: "Generic JSON-RPC 2.0 over HTTPACPTransport. Configure endpoint manually."
    )

    public static let all: [RemoteAgentDescriptor] = [.opencode, .codex, .claudeCode, .customACP]
}

// MARK: - OpenCode adapter

/// AgentConnection adapter preserving the existing OpenCode host pairing behavior.
public struct OpenCodeAgentConnection: AgentConnection {
    public let id: UUID
    public let displayName: String
    public let kind: AgentConnectionKind = .opencode
    public let hostConfig: OpenCodeHostConfig
    private let client: OpenCodeClient

    public init(hostConfig: OpenCodeHostConfig) {
        self.id = hostConfig.id
        self.displayName = hostConfig.displayName
        self.hostConfig = hostConfig
        self.client = OpenCodeClient(hostConfig: hostConfig)
    }

    public var capabilities: Set<AgentCapability> { Set(hostConfig.capabilities) }

    public func connect() async throws -> AgentHostMetadata {
        try await client.connect()
    }

    public func listSessions() async throws -> [AgentSession] {
        try await client.listSessions()
    }

    public func createSession(workspacePath: String, prompt: String? = nil) async throws -> AgentSession {
        try await client.createSession(workspacePath: workspacePath, prompt: prompt)
    }

    public func sendInstruction(sessionId: String, prompt: String) async -> AsyncThrowingStream<AgentEvent, Error> {
        await client.sendInstruction(sessionId: sessionId, prompt: prompt)
    }

    public func cancelTask(sessionId: String) async throws {
        try await client.cancelTask(sessionId: sessionId)
    }

    public func resolvePermission(requestId: String, decision: PermissionDecision, rationale: String? = nil) async throws {
        try await client.resolvePermission(requestId: requestId, decision: decision, rationale: rationale)
    }

    public func fetchGitStatus(sessionId: String) async throws -> GitStatusSummary {
        try await client.fetchGitStatus(sessionId: sessionId)
    }
}
