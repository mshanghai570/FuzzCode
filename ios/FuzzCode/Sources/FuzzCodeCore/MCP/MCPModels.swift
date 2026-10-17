import Foundation

/// Supported transport layers for Model Context Protocol (MCP) servers.
public enum MCPTransportType: String, Codable, Sendable {
    case streamableHTTP = "streamable_http"
    // Retained for servers using the legacy HTTP+SSE transport.
    case sse = "sse"
    case websocket = "websocket"
    case stdioRemote = "stdio_remote"
}

public indirect enum MCPJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: MCPJSONValue])
    case array([MCPJSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: MCPJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([MCPJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

private struct MCPDynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

/// JSON Schema definition for MCP tool parameters.
public struct MCPToolParameterProperty: Codable, Equatable, Sendable {
    public let type: String
    public let description: String?
    public let enumValues: [String]?
    public let properties: [String: MCPToolParameterProperty]?
    public let required: [String]?
    private let itemsStorage: [MCPToolParameterProperty]?
    public var items: MCPToolParameterProperty? { itemsStorage?.first }
    public let additionalFields: [String: MCPJSONValue]
    
    enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
    }
    
    public init(
        type: String,
        description: String? = nil,
        enumValues: [String]? = nil,
        properties: [String: MCPToolParameterProperty]? = nil,
        required: [String]? = nil,
        items: MCPToolParameterProperty? = nil,
        additionalFields: [String: MCPJSONValue] = [:]
    ) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
        self.properties = properties
        self.required = required
        self.itemsStorage = items.map { [$0] }
        self.additionalFields = additionalFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: MCPDynamicCodingKey.self)
        type = try container.decode(String.self, forKey: MCPDynamicCodingKey("type"))
        description = try container.decodeIfPresent(String.self, forKey: MCPDynamicCodingKey("description"))
        let decodedEnum = try container.decodeIfPresent([MCPJSONValue].self, forKey: MCPDynamicCodingKey("enum"))
        if let decodedEnum, decodedEnum.allSatisfy({ if case .string = $0 { return true }; return false }) {
            enumValues = decodedEnum.compactMap { if case .string(let value) = $0 { return value }; return nil }
        } else {
            enumValues = nil
        }
        properties = try container.decodeIfPresent(
            [String: MCPToolParameterProperty].self,
            forKey: MCPDynamicCodingKey("properties")
        )
        required = try container.decodeIfPresent([String].self, forKey: MCPDynamicCodingKey("required"))
        itemsStorage = try container.decodeIfPresent(
            MCPToolParameterProperty.self,
            forKey: MCPDynamicCodingKey("items")
        ).map { [$0] }
        let knownKeys: Set<String> = ["type", "description", "enum", "properties", "required", "items"]
        var fields = try Dictionary(uniqueKeysWithValues: container.allKeys
            .filter { !knownKeys.contains($0.stringValue) }
            .map { ($0.stringValue, try container.decode(MCPJSONValue.self, forKey: $0)) })
        if let decodedEnum, !decodedEnum.allSatisfy({ if case .string = $0 { return true }; return false }) {
            fields["enum"] = .array(decodedEnum)
        }
        additionalFields = fields
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: MCPDynamicCodingKey.self)
        try container.encode(type, forKey: MCPDynamicCodingKey("type"))
        try container.encodeIfPresent(description, forKey: MCPDynamicCodingKey("description"))
        if let enumValues {
            try container.encode(enumValues, forKey: MCPDynamicCodingKey("enum"))
        } else if let enumField = additionalFields["enum"] {
            try container.encode(enumField, forKey: MCPDynamicCodingKey("enum"))
        }
        try container.encodeIfPresent(properties, forKey: MCPDynamicCodingKey("properties"))
        try container.encodeIfPresent(required, forKey: MCPDynamicCodingKey("required"))
        try container.encodeIfPresent(items, forKey: MCPDynamicCodingKey("items"))
        for (key, value) in additionalFields where key != "enum" {
            try container.encode(value, forKey: MCPDynamicCodingKey(key))
        }
    }
}

public struct MCPToolInputSchema: Codable, Equatable, Sendable {
    public let type: String
    public let properties: [String: MCPToolParameterProperty]?
    public let required: [String]?
    public let additionalFields: [String: MCPJSONValue]
    
    public init(
        type: String = "object",
        properties: [String: MCPToolParameterProperty]? = nil,
        required: [String]? = nil,
        additionalFields: [String: MCPJSONValue] = [:]
    ) {
        self.type = type
        self.properties = properties
        self.required = required
        self.additionalFields = additionalFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: MCPDynamicCodingKey.self)
        type = try container.decode(String.self, forKey: MCPDynamicCodingKey("type"))
        properties = try container.decodeIfPresent(
            [String: MCPToolParameterProperty].self,
            forKey: MCPDynamicCodingKey("properties")
        )
        required = try container.decodeIfPresent([String].self, forKey: MCPDynamicCodingKey("required"))
        let knownKeys: Set<String> = ["type", "properties", "required"]
        additionalFields = try Dictionary(uniqueKeysWithValues: container.allKeys
            .filter { !knownKeys.contains($0.stringValue) }
            .map { ($0.stringValue, try container.decode(MCPJSONValue.self, forKey: $0)) })
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: MCPDynamicCodingKey.self)
        try container.encode(type, forKey: MCPDynamicCodingKey("type"))
        try container.encodeIfPresent(properties, forKey: MCPDynamicCodingKey("properties"))
        try container.encodeIfPresent(required, forKey: MCPDynamicCodingKey("required"))
        for (key, value) in additionalFields {
            try container.encode(value, forKey: MCPDynamicCodingKey(key))
        }
    }
}

/// Discovered MCP Tool.
public struct MCPTool: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let inputSchema: MCPToolInputSchema
    
    public init(name: String, description: String, inputSchema: MCPToolInputSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// Discovered MCP Resource.
public struct MCPResource: Identifiable, Codable, Equatable, Sendable {
    public var id: String { uri }
    public let uri: String
    public let name: String
    public let description: String?
    public let mimeType: String?
    
    public init(uri: String, name: String, description: String? = nil, mimeType: String? = nil) {
        self.uri = uri
        self.name = name
        self.description = description
        self.mimeType = mimeType
    }
}

/// Configuration for an MCP Server connection in FuzzCode.
public struct MCPServerConfig: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var serverDescription: String?
    public var transport: MCPTransportType
    public var endpointURLString: String
    public var command: String?
    public var authTokenKey: String? // Keychain lookup key
    public var customHeaders: [HTTPHeaderField]
    public var envVars: [String: String]
    public var isEnabled: Bool
    public var discoveredTools: [MCPTool]
    public var discoveredResources: [MCPResource]
    public var isConnected: Bool
    public var lastPingMs: Double?
    public var lastError: String?
    
    public init(
        id: UUID = UUID(),
        name: String,
        serverDescription: String? = nil,
        transport: MCPTransportType = .sse,
        endpointURLString: String,
        command: String? = nil,
        authTokenKey: String? = nil,
        customHeaders: [HTTPHeaderField] = [],
        envVars: [String: String] = [:],
        isEnabled: Bool = true,
        discoveredTools: [MCPTool] = [],
        discoveredResources: [MCPResource] = [],
        isConnected: Bool = false,
        lastPingMs: Double? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.name = name
        self.serverDescription = serverDescription
        self.transport = transport
        self.endpointURLString = endpointURLString
        self.command = command
        self.authTokenKey = authTokenKey
        self.customHeaders = customHeaders
        self.envVars = envVars
        self.isEnabled = isEnabled
        self.discoveredTools = discoveredTools
        self.discoveredResources = discoveredResources
        self.isConnected = isConnected
        self.lastPingMs = lastPingMs
        self.lastError = lastError
    }

    public mutating func markUnverified() {
        isConnected = false
        lastPingMs = nil
        discoveredTools = []
        discoveredResources = []
        lastError = nil
    }
}
