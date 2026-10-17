import Foundation
import XCTest
@testable import FuzzCodeCore

final class IntegrationPersistenceTests: XCTestCase {
    func testMCPServersRoundTripWithDiscoveredToolMetadata() throws {
        let (storage, directoryURL) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let tool = MCPTool(
            name: "query",
            description: "Run a read-only database query",
            inputSchema: MCPToolInputSchema(
                properties: [
                    "sql": MCPToolParameterProperty(type: "string", description: "SQL statement")
                ],
                required: ["sql"]
            )
        )
        let servers = [
            MCPServerConfig(
                name: "Database",
                serverDescription: "Analytics database",
                endpointURLString: "https://mcp.example.com",
                authTokenKey: "database_mcp_token",
                discoveredTools: [tool],
                discoveredResources: [
                    MCPResource(uri: "db://schema", name: "Schema", mimeType: "application/json")
                ],
                isConnected: true,
                lastPingMs: 24.5
            ),
            MCPServerConfig(
                name: "Local tools",
                transport: .websocket,
                endpointURLString: "wss://tools.example.com",
                discoveredTools: [
                    MCPTool(name: "status", description: "Get status", inputSchema: MCPToolInputSchema())
                ]
            )
        ]

        try storage.saveMCPServers(servers)

        XCTAssertEqual(try storage.loadMCPServers(), servers)
    }

    func testMarkUnverifiedClearsRuntimeMetadataAndPreservesConfiguration() {
        let id = UUID()
        let tool = MCPTool(
            name: "query",
            description: "Run a query",
            inputSchema: MCPToolInputSchema()
        )
        let resource = MCPResource(uri: "db://schema", name: "Schema")
        let header = HTTPHeaderField(key: "X-Workspace", value: "analytics")
        var server = MCPServerConfig(
            id: id,
            name: "Database",
            serverDescription: "Analytics database",
            transport: .websocket,
            endpointURLString: "wss://mcp.example.com",
            command: "mcp-server",
            authTokenKey: "database_mcp_token",
            customHeaders: [header],
            envVars: ["WORKSPACE": "analytics"],
            isEnabled: false,
            discoveredTools: [tool],
            discoveredResources: [resource],
            isConnected: true,
            lastPingMs: 24.5,
            lastError: "Stale connection error"
        )

        server.markUnverified()

        XCTAssertFalse(server.isConnected)
        XCTAssertNil(server.lastPingMs)
        XCTAssertTrue(server.discoveredTools.isEmpty)
        XCTAssertTrue(server.discoveredResources.isEmpty)
        XCTAssertNil(server.lastError)
        XCTAssertEqual(server.id, id)
        XCTAssertEqual(server.name, "Database")
        XCTAssertEqual(server.serverDescription, "Analytics database")
        XCTAssertEqual(server.transport, .websocket)
        XCTAssertEqual(server.endpointURLString, "wss://mcp.example.com")
        XCTAssertEqual(server.command, "mcp-server")
        XCTAssertEqual(server.authTokenKey, "database_mcp_token")
        XCTAssertEqual(server.customHeaders, [header])
        XCTAssertEqual(server.envVars, ["WORKSPACE": "analytics"])
        XCTAssertFalse(server.isEnabled)
    }

    func testGitHubConfigRoundTripsProfileMetadata() throws {
        let (storage, directoryURL) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let connectedAt = Date(timeIntervalSince1970: 1_728_000_000)
        let config = GitHubConfig(
            isConnected: true,
            keychainTokenKey: "github_account_token_reference",
            user: GitHubUser(
                login: "octocat",
                name: "The Octocat",
                avatarUrl: "https://github.com/images/octocat.png",
                htmlUrl: "https://github.com/octocat",
                publicRepos: 42,
                totalPrivateRepos: 3
            ),
            scopes: ["repo", "read:user"],
            connectedAt: connectedAt
        )

        try storage.saveGitHubConfig(config)

        XCTAssertEqual(try storage.loadGitHubConfig(), config)
    }

    func testMCPPersistenceExcludesRawCredentialValues() throws {
        let (storage, directoryURL) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let secret = "never-write-this-token"
        let server = MCPServerConfig(
            name: "Credentialed server",
            endpointURLString: "https://mcp.example.com",
            authTokenKey: "mcp_token_reference",
            customHeaders: [HTTPHeaderField(key: "Authorization", value: secret)],
            envVars: ["API_TOKEN": secret]
        )

        try storage.saveMCPServers([server])

        let persistedJSON = try String(
            contentsOf: directoryURL.appendingPathComponent("mcp_servers.json"),
            encoding: .utf8
        )
        XCTAssertFalse(persistedJSON.contains(secret))
        let restored = try XCTUnwrap(storage.loadMCPServers().first)
        XCTAssertEqual(restored.authTokenKey, "mcp_token_reference")
        XCTAssertTrue(restored.customHeaders.isEmpty)
        XCTAssertTrue(restored.envVars.isEmpty)
    }

    func testMissingIntegrationFilesReturnDefaults() throws {
        let (storage, directoryURL) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        XCTAssertEqual(try storage.loadMCPServers(), [])
        XCTAssertEqual(try storage.loadGitHubConfig(), GitHubConfig())
    }

    func testMalformedIntegrationJSONThrows() throws {
        let (storage, directoryURL) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        try Data("{invalid".utf8).write(to: directoryURL.appendingPathComponent("mcp_servers.json"))
        XCTAssertThrowsError(try storage.loadMCPServers())

        try Data("{invalid".utf8).write(to: directoryURL.appendingPathComponent("github_config.json"))
        XCTAssertThrowsError(try storage.loadGitHubConfig())
    }

    private func makeStorage() throws -> (storage: StorageService, directoryURL: URL) {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("IntegrationPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        return (StorageService(directoryURL: directoryURL), directoryURL)
    }
}
