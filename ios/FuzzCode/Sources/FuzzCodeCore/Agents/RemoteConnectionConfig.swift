import Foundation

public enum RemoteAgentProtocol: String, Codable, CaseIterable, Sendable {
    case legacyOpenCode = "legacy_opencode"
    case openCodeHTTP = "opencode_http"
    case codexAppServer = "codex_app_server"
    case acpWebSocket = "acp_websocket"

    public var displayName: String {
        switch self {
        case .legacyOpenCode: return "Legacy OpenCode companion"
        case .openCodeHTTP: return "OpenCode HTTP API"
        case .codexAppServer: return "Codex app-server WebSocket"
        case .acpWebSocket: return "ACP WebSocket bridge"
        }
    }
    public var isWebSocket: Bool { self == .codexAppServer || self == .acpWebSocket }
    public static func recommended(for kind: AgentConnectionKind) -> Self {
        switch kind {
        case .opencode: return .openCodeHTTP
        case .codex: return .codexAppServer
        case .claudeCode, .customACP, .native: return .acpWebSocket
        }
    }
}

public extension OpenCodeHostConfig {
    var resolvedKind: AgentConnectionKind { agentKind ?? .opencode }
    var resolvedProtocol: RemoteAgentProtocol { remoteProtocol ?? .legacyOpenCode }

    func validatedEndpoint() throws -> URL {
        guard let url = URL(string: hostURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              (resolvedProtocol.isWebSocket ? ["ws", "wss"] : ["http", "https"]).contains(scheme) else {
            throw AgentConnectionError.transportFailed("Enter a valid endpoint without embedded credentials or query parameters.")
        }
        // Old companion records retain their explicit local pairing behavior.
        let legacyLocal = remoteProtocol == nil && resolvedProtocol == .legacyOpenCode
        if ["http", "ws"].contains(scheme), allowsInsecureTransport != true && !legacyLocal {
            throw AgentConnectionError.transportFailed("Use TLS, or explicitly enable local development transport.")
        }
        return url
    }

    func authenticatedRequest(url: URL, credentials: any CredentialStore) throws -> URLRequest {
        _ = try validatedEndpoint()
        guard let token = credentials.retrieve(key: authTokenKey), !token.isEmpty else {
            throw AIProviderError.missingCredential
        }
        var request = URLRequest(url: url)
        if resolvedProtocol == .openCodeHTTP {
            let pair = "\(username?.isEmpty == false ? username! : "opencode"):\(token)"
            request.setValue("Basic \(Data(pair.utf8).base64EncodedString())", forHTTPHeaderField: "Authorization")
        } else {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 30
        return request
    }
}

/// QR exports contain connection metadata only. Each import gets a new local Keychain reference.
public struct AgentPairingPayload: Codable, Equatable, Sendable {
    public let version: Int
    public let name: String
    public let kind: AgentConnectionKind
    public let transport: RemoteAgentProtocol
    public let endpoint: String
    public let username: String?

    public init(host: OpenCodeHostConfig) {
        version = 1; name = host.displayName; kind = host.resolvedKind
        transport = host.resolvedProtocol; endpoint = host.hostURLString; username = host.username
    }

    public func configuration(allowsInsecureTransport: Bool = false) throws -> OpenCodeHostConfig {
        guard version == 1, kind != .native, !name.isEmpty else { throw AgentConnectionError.invalidResponse }
        let host = OpenCodeHostConfig(displayName: name, hostURLString: endpoint,
            authTokenKey: "agent_token_\(UUID().uuidString)", capabilities: [], agentKind: kind,
            remoteProtocol: transport, allowsInsecureTransport: allowsInsecureTransport, username: username)
        _ = try host.validatedEndpoint()
        return host
    }

    public static func decode(_ text: String, allowsInsecureTransport: Bool = false) throws -> OpenCodeHostConfig {
        guard text.utf8.count <= 16_384, let data = text.data(using: .utf8) else { throw AgentConnectionError.invalidResponse }
        let payload = try JSONDecoder().decode(Self.self, from: data)
        return try payload.configuration(allowsInsecureTransport: allowsInsecureTransport)
    }
}
