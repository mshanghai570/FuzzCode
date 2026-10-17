import Foundation

/// Native local persistence service for nonsecret application models.
/// Uses the iOS Application Support directory with atomic file writes.
/// Secret tokens/keys are excluded and managed strictly by KeychainService.
public final class StorageService: Sendable {
    public static let shared = StorageService()
    
    private var fileManager: FileManager { FileManager.default }
    private let storageDirectoryOverride: URL?
    
    public init() {
        storageDirectoryOverride = nil
    }

    public init(directoryURL: URL) {
        storageDirectoryOverride = directoryURL
    }
    
    private var storageDirectoryURL: URL {
        if let storageDirectoryOverride {
            return storageDirectoryOverride
        }
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("FuzzCode", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    // MARK: - Generic Persistence
    
    public func save<T: Encodable>(_ item: T, to filename: String) throws {
        try fileManager.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
        let url = storageDirectoryURL.appendingPathComponent(filename)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)
        try data.write(to: url, options: [.atomic])
    }
    
    public func load<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let url = storageDirectoryURL.appendingPathComponent(filename)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }
    
    // MARK: - Convenience Accessors
    
    public func saveProviders(_ providers: [ProviderConfig]) {
        try? save(providers, to: "providers.json")
    }
    
    public func loadProviders() -> [ProviderConfig] {
        return load([ProviderConfig].self, from: "providers.json") ?? []
    }
    
    public func saveConversations(_ conversations: [ChatConversation]) {
        try? save(conversations, to: "conversations.json")
    }
    
    public func loadConversations() -> [ChatConversation] {
        return load([ChatConversation].self, from: "conversations.json") ?? []
    }
    
    public func saveAgentSessions(_ sessions: [AgentSession]) {
        try? save(sessions, to: "agent_sessions.json")
    }

    public func loadAgentSessions() -> [AgentSession] {
        return load([AgentSession].self, from: "agent_sessions.json") ?? []
    }

    public func saveHosts(_ hosts: [OpenCodeHostConfig]) {
        try? save(hosts, to: "hosts.json")
    }
    
    public func loadHosts() -> [OpenCodeHostConfig] {
        return load([OpenCodeHostConfig].self, from: "hosts.json") ?? []
    }

    public func saveMCPServers(_ servers: [MCPServerConfig]) throws {
        var persistableServers = servers
        for index in persistableServers.indices {
            // These free-form fields may contain credentials; persist only the Keychain reference.
            persistableServers[index].customHeaders = []
            persistableServers[index].envVars = [:]
        }
        try saveIntegrationConfiguration(persistableServers, to: "mcp_servers.json")
    }

    public func loadMCPServers() throws -> [MCPServerConfig] {
        try loadIntegrationConfiguration([MCPServerConfig].self, from: "mcp_servers.json") ?? []
    }

    public func saveGitHubConfig(_ config: GitHubConfig) throws {
        try saveIntegrationConfiguration(config, to: "github_config.json")
    }

    public func loadGitHubConfig() throws -> GitHubConfig {
        try loadIntegrationConfiguration(GitHubConfig.self, from: "github_config.json") ?? GitHubConfig()
    }

    public func saveSkills(_ skills: [AgentSkill]) throws {
        try saveIntegrationConfiguration(skills, to: "skills.json")
    }

    public func loadSkills() throws -> [AgentSkill] {
        try loadIntegrationConfiguration([AgentSkill].self, from: "skills.json") ?? []
    }

    private func saveIntegrationConfiguration<T: Encodable>(_ item: T, to filename: String) throws {
        try fileManager.createDirectory(at: storageDirectoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(item)
        try data.write(to: storageDirectoryURL.appendingPathComponent(filename), options: [.atomic])
    }

    private func loadIntegrationConfiguration<T: Decodable>(_ type: T.Type, from filename: String) throws -> T? {
        let url = storageDirectoryURL.appendingPathComponent(filename)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }
}
