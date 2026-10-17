import Foundation

public struct OpenCodeHostConfig: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var hostURLString: String
    public var authTokenKey: String // Keychain lookup key
    public var isConnected: Bool
    public var osVersion: String?
    public var agentVersion: String?
    public var currentWorkspace: String?
    public var capabilities: [AgentCapability]
    public var lastSeen: Date?
    public var agentKind: AgentConnectionKind?
    public var remoteProtocol: RemoteAgentProtocol?
    public var allowsInsecureTransport: Bool?
    public var username: String?
    
    public init(
        id: UUID = UUID(),
        displayName: String,
        hostURLString: String,
        authTokenKey: String = "opencode_token_default",
        isConnected: Bool = false,
        osVersion: String? = nil,
        agentVersion: String? = nil,
        currentWorkspace: String? = nil,
        capabilities: [AgentCapability] = [.sessions, .streaming, .toolEvents, .cancellation, .fileDiffs, .permissionRequests, .gitStatus],
        lastSeen: Date? = nil,
        agentKind: AgentConnectionKind? = nil,
        remoteProtocol: RemoteAgentProtocol? = nil,
        allowsInsecureTransport: Bool? = nil,
        username: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.hostURLString = hostURLString
        self.authTokenKey = authTokenKey
        self.isConnected = isConnected
        self.osVersion = osVersion
        self.agentVersion = agentVersion
        self.currentWorkspace = currentWorkspace
        self.capabilities = capabilities
        self.lastSeen = lastSeen
        self.agentKind = agentKind
        self.remoteProtocol = remoteProtocol
        self.allowsInsecureTransport = allowsInsecureTransport
        self.username = username
    }
}

public struct AgentSession: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var hostId: UUID
    public var title: String
    public var workspacePath: String
    public var status: SessionStatus
    public var createdAt: Date
    public var updatedAt: Date
    public var messages: [AgentSessionMessage]
    public var pendingPermission: PermissionRequest?
    public var connectionKind: AgentConnectionKind?
    public var providerId: UUID?
    
    public init(
        id: String = UUID().uuidString,
        hostId: UUID,
        title: String,
        workspacePath: String,
        status: SessionStatus = .idle,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        messages: [AgentSessionMessage] = [],
        pendingPermission: PermissionRequest? = nil,
        connectionKind: AgentConnectionKind? = nil,
        providerId: UUID? = nil
    ) {
        self.id = id
        self.hostId = hostId
        self.title = title
        self.workspacePath = workspacePath
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
        self.pendingPermission = pendingPermission
        self.connectionKind = connectionKind
        self.providerId = providerId
    }
}

public enum SessionStatus: String, Codable, Sendable {
    case idle = "idle"
    case running = "running"
    case waitingPermission = "waiting_permission"
    case completed = "completed"
    case cancelled = "cancelled"
    case failed = "failed"
}

public struct AgentSessionMessage: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var role: MessageRole
    public var content: String
    public var timestamp: Date
    public var toolEvents: [AgentToolEvent]
    
    public init(
        id: String = UUID().uuidString,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        toolEvents: [AgentToolEvent] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolEvents = toolEvents
    }
}

public struct AgentToolEvent: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var toolName: String
    public var argumentsJSON: String
    public var outputSnippet: String?
    public var status: ToolStatus
    public var startedAt: Date
    public var completedAt: Date?
    
    public init(
        id: String = UUID().uuidString,
        toolName: String,
        argumentsJSON: String,
        outputSnippet: String? = nil,
        status: ToolStatus = .running,
        startedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.argumentsJSON = argumentsJSON
        self.outputSnippet = outputSnippet
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

public enum ToolStatus: String, Codable, Sendable {
    case pending = "pending"
    case running = "running"
    case success = "success"
    case failed = "failed"
    case denied = "denied"
}

public struct PermissionRequest: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var toolName: String
    public var commandOrPath: String
    public var fullParameters: [String: String]
    public var riskLevel: RiskLevel
    public var requestedAt: Date
    
    public init(
        id: String = UUID().uuidString,
        toolName: String,
        commandOrPath: String,
        fullParameters: [String: String] = [:],
        riskLevel: RiskLevel = .medium,
        requestedAt: Date = Date()
    ) {
        self.id = id
        self.toolName = toolName
        self.commandOrPath = commandOrPath
        self.fullParameters = fullParameters
        self.riskLevel = riskLevel
        self.requestedAt = requestedAt
    }
}

public enum RiskLevel: String, Codable, Sendable {
    case low = "low"
    case medium = "medium"
    case high = "high"
    case destructive = "destructive"
}

public enum AgentEvent: Sendable {
    case textDelta(String)
    case toolStarted(AgentToolEvent)
    case toolCompleted(toolId: String, output: String, success: Bool)
    case permissionRequested(PermissionRequest)
    case statusChanged(SessionStatus)
    case gitUpdated(GitStatusSummary)
    case error(String)
    case finished
}

public struct GitStatusSummary: Codable, Equatable, Sendable {
    public var branch: String
    public var ahead: Int
    public var behind: Int
    public var changedFiles: [GitFileDiff]
    
    public init(branch: String = "main", ahead: Int = 0, behind: Int = 0, changedFiles: [GitFileDiff] = []) {
        self.branch = branch
        self.ahead = ahead
        self.behind = behind
        self.changedFiles = changedFiles
    }
}

public struct GitFileDiff: Identifiable, Codable, Equatable, Sendable {
    public var id: String { filePath }
    public var filePath: String
    public var status: GitFileStatus
    public var additions: Int
    public var deletions: Int
    public var patch: String
    
    public init(filePath: String, status: GitFileStatus, additions: Int, deletions: Int, patch: String) {
        self.filePath = filePath
        self.status = status
        self.additions = additions
        self.deletions = deletions
        self.patch = patch
    }
}

public enum GitFileStatus: String, Codable, Sendable {
    case modified = "modified"
    case added = "added"
    case deleted = "deleted"
    case renamed = "renamed"
    case untracked = "untracked"
}
