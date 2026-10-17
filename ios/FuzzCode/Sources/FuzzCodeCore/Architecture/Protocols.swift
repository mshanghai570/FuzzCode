import Foundation

/// Core Protocol defining an AI Inference Model Provider (e.g. OpenAI, Kilo, Ollama, Groq, custom compatible endpoints).
public protocol ModelProviderProtocol: Identifiable, Sendable {
    var id: UUID { get }
    var displayName: String { get }
    var baseURL: URL { get }
    var selectedModel: String { get }
    var isEnabled: Bool { get }
    
    /// Tests connectivity to the endpoint and returns round-trip latency in milliseconds.
    func testConnection() async throws -> TimeInterval
    
    /// Queries the endpoint's model catalog via GET /models (if supported).
    func discoverModels() async throws -> [ModelInfo]
    
    /// Streams chat completions using Server-Sent Events (SSE).
    func streamChatCompletion(
        messages: [ChatMessage],
        temperature: Double?,
        systemPrompt: String?
    ) async -> AsyncThrowingStream<String, Error>
}

/// Core Protocol defining an external Coding Agent runtime (e.g. OpenCode, Aider, Claude Code).
public protocol CodingAgentProtocol: Identifiable, Sendable {
    var id: UUID { get }
    var name: String { get }
    var supportedCapabilities: Set<AgentCapability> { get async }
    
    /// Connects to the agent host and performs handshake / capability detection.
    func connect() async throws -> AgentHostMetadata
    
    /// Lists active development sessions on the remote host.
    func listSessions() async throws -> [AgentSession]
    
    /// Creates a new coding agent session attached to a remote workspace path.
    func createSession(workspacePath: String, prompt: String?) async throws -> AgentSession
    
    /// Dispatches a prompt or instruction into an existing session and yields streamed events.
    func sendInstruction(
        sessionId: String,
        prompt: String
    ) async -> AsyncThrowingStream<AgentEvent, Error>
    
    /// Requests cancellation of the currently active session task.
    func cancelTask(sessionId: String) async throws
    
    /// Resolves an interactive tool permission request (Allow or Deny).
    func resolvePermission(
        requestId: String,
        decision: PermissionDecision,
        rationale: String?
    ) async throws
    
    /// Fetches the current git status and file diffs for the session workspace.
    func fetchGitStatus(sessionId: String) async throws -> GitStatusSummary
}

/// Core Protocol defining an Execution Host where external agents run (Mac, Linux VM, Cloud Workspace).
public protocol ExecutionHostProtocol: Identifiable, Sendable {
    var id: UUID { get }
    var displayName: String { get }
    var hostURL: URL { get }
    var connectionType: HostTransportType { get }
    var isPaired: Bool { get }
    
    func pair(authToken: String) async throws -> Bool
    func disconnect() async
    func checkHealth() async throws -> HostHealthStatus
}

/// Capabilities declared by connected coding agent runtimes.
public enum AgentCapability: String, Codable, Hashable, Sendable {
    case sessions = "sessions"
    case streaming = "streaming"
    case toolEvents = "tool_events"
    case cancellation = "cancellation"
    case fileDiffs = "file_diffs"
    case permissionRequests = "permission_requests"
    case projectSelection = "project_selection"
    case gitStatus = "git_status"
    case sessionResumption = "session_resumption"
}

/// Decision made on an interactive permission prompt.
public enum PermissionDecision: String, Codable, Sendable {
    case allowOnce = "allow_once"
    case allowAlways = "allow_always"
    case deny = "deny"
}

public enum HostTransportType: String, Codable, Sendable {
    case http = "http"
    case webSocket = "websocket"
}

public struct HostHealthStatus: Codable, Sendable {
    public let isReachable: Bool
    public let latencyMs: Double
    public let agentVersion: String?
    public let systemLoad: String?
    
    public init(isReachable: Bool, latencyMs: Double, agentVersion: String?, systemLoad: String?) {
        self.isReachable = isReachable
        self.latencyMs = latencyMs
        self.agentVersion = agentVersion
        self.systemLoad = systemLoad
    }
}

public struct AgentHostMetadata: Codable, Sendable {
    public let hostId: String
    public let name: String
    public let version: String
    public let osName: String
    public let defaultWorkspace: String?
    public let capabilities: [AgentCapability]
    
    public init(hostId: String, name: String, version: String, osName: String, defaultWorkspace: String?, capabilities: [AgentCapability]) {
        self.hostId = hostId
        self.name = name
        self.version = version
        self.osName = osName
        self.defaultWorkspace = defaultWorkspace
        self.capabilities = capabilities
    }
}
