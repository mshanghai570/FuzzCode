import Foundation

public func makeRemoteAgentConnection(host: OpenCodeHostConfig,
    credentialStore: any CredentialStore = KeychainCredentialStore()) throws -> any AgentConnection {
    _ = try host.validatedEndpoint()
    switch host.resolvedProtocol {
    case .legacyOpenCode: return OpenCodeAgentConnection(hostConfig: host)
    case .openCodeHTTP: return try OpenCodeHTTPConnection(hostConfig: host, credentialStore: credentialStore)
    case .codexAppServer:
        return CodexAgentConnection(hostConfig: host,
            transport: WebSocketACPTransport(hostConfig: host, credentialStore: credentialStore, includesJSONRPCVersion: false))
    case .acpWebSocket:
        return ACPAgentConnection(hostConfig: host, transport: WebSocketACPTransport(hostConfig: host, credentialStore: credentialStore))
    }
}
