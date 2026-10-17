import XCTest
@testable import FuzzCodeCore

final class RemoteConnectionTests: XCTestCase {
    func testLegacyHostKeepsCompanionProtocol() throws {
        let host = OpenCodeHostConfig(displayName: "Existing", hostURLString: "http://192.168.1.2:4096")
        XCTAssertEqual(host.resolvedProtocol, .legacyOpenCode)
        XCTAssertEqual(host.resolvedKind, .opencode)
        XCTAssertNoThrow(try host.validatedEndpoint())
    }

    func testNewRemoteConnectionRejectsCleartextWithoutOptIn() {
        let host = OpenCodeHostConfig(displayName: "Codex", hostURLString: "ws://192.168.1.2:4500",
            agentKind: .codex, remoteProtocol: .codexAppServer)
        XCTAssertThrowsError(try host.validatedEndpoint())
    }

    func testEndpointRejectsEmbeddedSecretsAndWrongProtocol() {
        for endpoint in ["wss://token@host.test/rpc", "wss://host.test/rpc?token=secret", "https://host.test/rpc"] {
            let host = OpenCodeHostConfig(displayName: "ACP", hostURLString: endpoint,
                agentKind: .customACP, remoteProtocol: .acpWebSocket)
            XCTAssertThrowsError(try host.validatedEndpoint())
        }
    }

    func testQRImportUsesFreshLocalIdentityAndNoCredentials() throws {
        let host = OpenCodeHostConfig(displayName: "Claude", hostURLString: "wss://host.test/acp",
            authTokenKey: "secret-reference", isConnected: true, agentKind: .claudeCode, remoteProtocol: .acpWebSocket)
        let data = try JSONEncoder().encode(AgentPairingPayload(host: host))
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("secret-reference"))
        let restored = try AgentPairingPayload.decode(text)
        XCTAssertNotEqual(restored.id, host.id)
        XCTAssertNotEqual(restored.authTokenKey, host.authTokenKey)
        XCTAssertFalse(restored.isConnected)
        XCTAssertEqual(restored.resolvedKind, .claudeCode)
    }

    func testACPDoesNotAdvertiseTerminalOrClientFilesystem() async throws {
        let transport = ScriptedAgentTransport(result: .object([
            "protocolVersion": .number(1), "agentCapabilities": .object(["loadSession": .bool(true)]),
            "agentInfo": .object(["name": .string("test"), "version": .string("1")])]))
        let config = OpenCodeHostConfig(displayName: "ACP", hostURLString: "wss://host.test/rpc",
            agentKind: .customACP, remoteProtocol: .acpWebSocket)
        let agent = ACPAgentConnection(hostConfig: config, transport: transport)
        let metadata = try await agent.connect()
        XCTAssertTrue(metadata.capabilities.contains(.sessionResumption))
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.0, "initialize")
        XCTAssertEqual(requests.first?.1.rpcObject?["clientCapabilities"], .object([
            "fs": .object(["readTextFile": .bool(false), "writeTextFile": .bool(false)]), "terminal": .bool(false)]))
    }

    func testACPRejectsUnsupportedProtocolVersion() async throws {
        let transport = ScriptedAgentTransport(result: .object(["protocolVersion": .number(99)]))
        let config = OpenCodeHostConfig(displayName: "ACP", hostURLString: "wss://host.test/rpc")
        let agent = ACPAgentConnection(hostConfig: config, transport: transport)
        do { _ = try await agent.connect(); XCTFail("Version must be negotiated") }
        catch { XCTAssertTrue(error is AgentConnectionError) }
    }

    func testCodexHandshakeUsesItsOwnInitialization() async throws {
        let transport = ScriptedAgentTransport(result: .object(["userAgent": .string("codex/1")]))
        let config = OpenCodeHostConfig(displayName: "Codex", hostURLString: "wss://host.test/rpc",
            agentKind: .codex, remoteProtocol: .codexAppServer)
        let agent = CodexAgentConnection(hostConfig: config, transport: transport)
        _ = try await agent.connect()
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.0, "initialize")
        XCTAssertNil(requests.first?.1.rpcObject?["protocolVersion"])
        let notifications = await transport.notifications
        XCTAssertEqual(notifications.first?.0, "initialized")
    }

    func testRPCFramesPreserveNumericServerRequestIDs() throws {
        let data = Data(#"{"id":17,"method":"session/request_permission","params":{"sessionId":"s"}}"#.utf8)
        let message = try JSONDecoder().decode(AgentRPCMessage.self, from: data)
        XCTAssertEqual(message.id, .number(17))
        let reply = AgentRPCMessage(id: message.id, result: .object(["outcome": .object(["outcome": .string("cancelled")])]))
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(reply)) as? [String: Any]
        XCTAssertEqual(object?["id"] as? Int, 17)
    }

    func testRecommendedProtocolPerAgentKind() {
        XCTAssertEqual(RemoteAgentProtocol.recommended(for: .opencode), .openCodeHTTP)
        XCTAssertEqual(RemoteAgentProtocol.recommended(for: .codex), .codexAppServer)
        XCTAssertEqual(RemoteAgentProtocol.recommended(for: .claudeCode), .acpWebSocket)
        XCTAssertEqual(RemoteAgentProtocol.recommended(for: .customACP), .acpWebSocket)
        XCTAssertEqual(RemoteAgentProtocol.recommended(for: .native), .acpWebSocket)
    }

    func testFactoryRoutesEachProtocolToItsTransport() throws {
        let store = InMemoryCredentialStore()
        let hosts = [
            OpenCodeHostConfig(displayName: "Legacy", hostURLString: "http://192.168.1.2:4096"),
            OpenCodeHostConfig(displayName: "HTTP", hostURLString: "https://host.test/api",
                agentKind: .opencode, remoteProtocol: .openCodeHTTP),
            OpenCodeHostConfig(displayName: "Codex", hostURLString: "wss://host.test/rpc",
                agentKind: .codex, remoteProtocol: .codexAppServer),
            OpenCodeHostConfig(displayName: "ACP", hostURLString: "wss://host.test/acp",
                agentKind: .claudeCode, remoteProtocol: .acpWebSocket)
        ]
        let connections = try hosts.map { try makeRemoteAgentConnection(host: $0, credentialStore: store) }
        XCTAssertTrue(connections[0] is OpenCodeAgentConnection)
        XCTAssertTrue(connections[1] is OpenCodeHTTPConnection)
        XCTAssertTrue(connections[2] is CodexAgentConnection)
        XCTAssertTrue(connections[3] is ACPAgentConnection)
    }

    func testFactoryPropagatesEndpointValidation() {
        let host = OpenCodeHostConfig(displayName: "Insecure", hostURLString: "ws://192.168.1.2:4500",
            agentKind: .codex, remoteProtocol: .codexAppServer)
        XCTAssertThrowsError(try makeRemoteAgentConnection(host: host))
    }
}

struct InMemoryCredentialStore: CredentialStore {
    func retrieve(key: String) -> String? { nil }
    func store(key: String, secret: String) {}
    func remove(key: String) {}
}

actor ScriptedAgentTransport: ACPTransport {
    var requests: [(String, AgentJSONValue)] = []
    var notifications: [(String, AgentJSONValue)] = []
    var responses: [(AgentJSONValue, AgentJSONValue)] = []
    private let result: AgentJSONValue
    init(result: AgentJSONValue) { self.result = result }
    func connect() async throws {}
    func disconnect() async {}
    func request(method: String, params: AgentJSONValue, timeoutSeconds: TimeInterval) async throws -> AgentJSONValue {
        requests.append((method, params)); return result
    }
    func notify(method: String, params: AgentJSONValue) async throws { notifications.append((method, params)) }
    func respond(id: AgentJSONValue, result: AgentJSONValue) async throws { responses.append((id, result)) }
    func incomingMessages() async -> AsyncThrowingStream<AgentRPCMessage, Error> { AsyncThrowingStream { $0.finish() } }
}
