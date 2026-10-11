import Foundation

/// Supported transport layers for Model Context Protocol (MCP) servers.
public enum MCPTransportType: String, Codable, Sendable {
    case sse = "sse"
    case websocket = "websocket"
    case stdioRemote = "stdio_remote"
}

/// JSON Schema definition for MCP tool parameters.
public struct MCPToolParameterProperty: Codable, Equatable, Sendable {
    public let type: String
    public let description: String?
    public let enumValues: [String]?
    
    enum CodingKeys: String, CodingKey {
        case type
        case description
        case enumValues = "enum"
    }
    
    public init(type: String, description: String? = nil, enumValues: [String]? = nil) {
        self.type = type
        self.description = description
        self.enumValues = enumValues
    }
}

public struct MCPToolInputSchema: Codable, Equatable, Sendable {
    public let type: String
    public let properties: [String: MCPToolParameterProperty]?
    public let required: [String]?
    
    public init(type: String = "object", properties: [String: MCPToolParameterProperty]? = nil, required: [String]? = nil) {
        self.type = type
        self.properties = properties
        self.required = required
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
}
