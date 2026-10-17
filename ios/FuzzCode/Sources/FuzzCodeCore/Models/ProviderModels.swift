import Foundation

public enum ProviderAuthMethod: String, Codable, Sendable {
    case apiKey = "api_key"
    case chatgptSubscription = "chatgpt_subscription"
}

public struct ChatGPTSession: Codable, Equatable, Sendable {
    public var accountEmail: String?
    public var subscriptionTier: String // "plus", "pro", "team", "enterprise"
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?
    
    public init(accountEmail: String? = nil, subscriptionTier: String = "plus", accessToken: String, refreshToken: String? = nil, expiresAt: Date? = nil) {
        self.accountEmail = accountEmail
        self.subscriptionTier = subscriptionTier
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

public struct ProviderConfig: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var baseURLString: String
    // Defaulted so providers.json files saved by older builds still decode.
    public var providerKind: ProviderKind? = nil
    public var selectedModel: String
    public var authMethod: ProviderAuthMethod
    public var chatgptSession: ChatGPTSession?
    public var isCodexOptimized: Bool
    public var customHeaders: [HTTPHeaderField]
    public var organizationId: String?
    public var projectId: String?
    public var customApiPath: String?
    public var timeoutSeconds: TimeInterval
    public var isEnabled: Bool
    public var allowsInsecureHTTP: Bool
    public var createdAt: Date
    public var lastTestedAt: Date?
    public var lastLatencyMs: Double?
    
    public var resolvedKind: ProviderKind { providerKind ?? .custom }

    public init(
        id: UUID = UUID(),
        displayName: String,
        baseURLString: String,
        providerKind: ProviderKind? = nil,
        selectedModel: String = "gpt-4o",
        authMethod: ProviderAuthMethod = .apiKey,
        chatgptSession: ChatGPTSession? = nil,
        isCodexOptimized: Bool = false,
        customHeaders: [HTTPHeaderField] = [],
        organizationId: String? = nil,
        projectId: String? = nil,
        customApiPath: String? = nil,
        timeoutSeconds: TimeInterval = 30.0,
        isEnabled: Bool = true,
        allowsInsecureHTTP: Bool = false,
        createdAt: Date = Date(),
        lastTestedAt: Date? = nil,
        lastLatencyMs: Double? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.baseURLString = baseURLString
        self.providerKind = providerKind
        self.selectedModel = selectedModel
        self.authMethod = authMethod
        self.chatgptSession = chatgptSession
        self.isCodexOptimized = isCodexOptimized
        self.customHeaders = customHeaders
        self.organizationId = organizationId
        self.projectId = projectId
        self.customApiPath = customApiPath
        self.timeoutSeconds = timeoutSeconds
        self.isEnabled = isEnabled
        self.allowsInsecureHTTP = allowsInsecureHTTP
        self.createdAt = createdAt
        self.lastTestedAt = lastTestedAt
        self.lastLatencyMs = lastLatencyMs
    }
    
    /// Normalizes base URL, stripping trailing slashes and ensuring appropriate /v1 resolution
    public var resolvedBaseURL: URL? {
        var trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard let url = URL(string: trimmed) else { return nil }
        
        // Disallow plain HTTP unless explicitly flagged for trusted local development
        if url.scheme?.lowercased() == "http" && !allowsInsecureHTTP {
            return nil
        }
        return url
    }
}

public struct HTTPHeaderField: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var key: String
    public var value: String
    
    public init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

public struct ModelInfo: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var ownedBy: String?
    public var contextWindow: Int?
    
    public init(id: String, ownedBy: String? = nil, contextWindow: Int? = nil) {
        self.id = id
        self.ownedBy = ownedBy
        self.contextWindow = contextWindow
    }
}

public struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var role: MessageRole
    public var content: String
    public var timestamp: Date
    public var isStreaming: Bool
    
    public init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date(), isStreaming: Bool = false) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }
}

public enum MessageRole: String, Codable, Sendable {
    case system = "system"
    case user = "user"
    case assistant = "assistant"
}

public struct ChatConversation: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var providerId: UUID
    public var modelId: String
    public var messages: [ChatMessage]
    public var updatedAt: Date
    // Optional fields preserve decoding of conversations saved by earlier versions.
    public var systemPrompt: String?
    public var ragSources: [RAGSource]?
    public var ragConfig: RAGConfig?
    public var selectedSkillIDs: [UUID]?
    
    public init(id: UUID = UUID(), title: String, providerId: UUID, modelId: String, messages: [ChatMessage] = [], updatedAt: Date = Date(), selectedSkillIDs: [UUID]? = nil) {
        self.id = id
        self.title = title
        self.providerId = providerId
        self.modelId = modelId
        self.messages = messages
        self.updatedAt = updatedAt
        self.selectedSkillIDs = selectedSkillIDs
    }
}
