import Foundation

/// Native local persistence service for nonsecret application models.
/// Uses the iOS Application Support directory with atomic file writes.
/// Secret tokens/keys are excluded and managed strictly by KeychainService.
public final class StorageService: Sendable {
    public static let shared = StorageService()
    
    private let fileManager = FileManager.default
    
    public init() {}
    
    private var storageDirectoryURL: URL {
        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let dir = paths[0].appendingPathComponent("FuzzCode", isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    // MARK: - Generic Persistence
    
    public func save<T: Encodable>(_ item: T, to filename: String) throws {
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
    
    public func saveHosts(_ hosts: [OpenCodeHostConfig]) {
        try? save(hosts, to: "hosts.json")
    }
    
    public func loadHosts() -> [OpenCodeHostConfig] {
        return load([OpenCodeHostConfig].self, from: "hosts.json") ?? []
    }
}
