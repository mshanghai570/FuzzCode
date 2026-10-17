import Foundation

public struct ProviderToolDefinition: Equatable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: MCPToolInputSchema

    public init(name: String, description: String, inputSchema: MCPToolInputSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct ProviderToolCall: Equatable, Sendable {
    public let id: String
    public let name: String
    public let arguments: Data

    /// Opaque assistant response used to replay provider content, including thought signatures.
    /// This stays separate from tool arguments and is never executed by a tool.
    public let replayContent: Data?

    public init(id: String, name: String, arguments: Data, replayContent: Data? = nil) {
        self.id = id
        self.name = name
        self.arguments = arguments
        self.replayContent = replayContent
    }
}

public struct ProviderToolResult: Equatable, Sendable {
    public let toolCallID: String
    public let content: String

    public init(toolCallID: String, content: String) {
        self.toolCallID = toolCallID
        self.content = content
    }
}

public struct ProviderToolExchange: Equatable, Sendable {
    public let calls: [ProviderToolCall]
    public let results: [ProviderToolResult]

    public init(calls: [ProviderToolCall], results: [ProviderToolResult]) {
        self.calls = calls
        self.results = results
    }
}

public enum ProviderTurnResult: Equatable, Sendable {
    case message(String)
    case toolCalls([ProviderToolCall])
}
