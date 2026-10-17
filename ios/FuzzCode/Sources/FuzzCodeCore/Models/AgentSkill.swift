import Foundation

public struct AgentSkill: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var content: String
    public var updatedAt: Date

    public init(id: UUID = UUID(), name: String, content: String, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.content = content
        self.updatedAt = updatedAt
    }
}
