import Foundation

/// Type of RAG knowledge source.
public enum RAGSourceType: String, Codable, Sendable {
    case document = "doc"
    case guideline = "guideline"
    case snippet = "snippet"
    case file = "file"
    case url = "url"
}

/// A semantic chunk of indexed knowledge.
public struct RAGChunk: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let sourceId: String
    public let sourceTitle: String
    public let content: String
    public let tokens: Int
    public var score: Double?
    
    public init(id: String, sourceId: String, sourceTitle: String, content: String, tokens: Int, score: Double? = nil) {
        self.id = id
        self.sourceId = sourceId
        self.sourceTitle = sourceTitle
        self.content = content
        self.tokens = tokens
        self.score = score
    }
}

/// A registered RAG knowledge source belonging to a Chat conversation or Agent Project.
public struct RAGSource: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var type: RAGSourceType
    public var content: String
    public var filePath: String?
    public var tokens: Int
    public var chunksCount: Int
    public var isEnabled: Bool
    public var addedAt: Date
    
    public init(id: String = UUID().uuidString, title: String, type: RAGSourceType, content: String, filePath: String? = nil, tokens: Int, chunksCount: Int = 1, isEnabled: Bool = true, addedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.type = type
        self.content = content
        self.filePath = filePath
        self.tokens = tokens
        self.chunksCount = chunksCount
        self.isEnabled = isEnabled
        self.addedAt = addedAt
    }
}

/// Retrieval parameters for RAG execution.
public struct RAGConfig: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var topK: Int
    public var similarityThreshold: Double
    public var maxContextTokens: Int
    
    public init(isEnabled: Bool = true, topK: Int = 3, similarityThreshold: Double = 0.15, maxContextTokens: Int = 1500) {
        self.isEnabled = isEnabled
        self.topK = topK
        self.similarityThreshold = similarityThreshold
        self.maxContextTokens = maxContextTokens
    }
}

/// Curated system prompt directive template.
public struct PromptTemplate: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let category: String
    public let description: String
    public let content: String
    
    public init(id: String, title: String, category: String, description: String, content: String) {
        self.id = id
        self.title = title
        self.category = category
        self.description = description
        self.content = content
    }
}

/// Citation result from RAG retrieval.
public struct RetrievedCitation: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let sourceTitle: String
    public let sourceType: String
    public let snippet: String
    public let score: Double
    
    public init(id: String, sourceTitle: String, sourceType: String, snippet: String, score: Double) {
        self.id = id
        self.sourceTitle = sourceTitle
        self.sourceType = sourceType
        self.snippet = snippet
        self.score = score
    }
}
