import XCTest
import Foundation
@testable import FuzzCodeCore

final class MCPConnectorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }
    
    func testMCPServerConfigDefaultValues() {
        let server = MCPServerConfig(
            name: "PostgreSQL MCP",
            transport: .sse,
            endpointURLString: "http://localhost:8080/sse"
        )
        
        XCTAssertEqual(server.name, "PostgreSQL MCP")
        XCTAssertEqual(server.transport, .sse)
        XCTAssertTrue(server.isEnabled)
        XCTAssertFalse(server.isConnected)
    }
    
    func testMCPToolSchemaEncoding() throws {
        let schema = MCPToolInputSchema(
            type: "object",
            properties: [
                "sql": MCPToolParameterProperty(type: "string", description: "Query to execute")
            ],
            required: ["sql"]
        )
        let tool = MCPTool(name: "query", description: "Execute SQL query", inputSchema: schema)
        
        XCTAssertEqual(tool.name, "query")
        XCTAssertEqual(tool.inputSchema.required, ["sql"])
    }

    func testInitializeAndDiscoverThrowsOnJSONRPCErrorInsteadOfUsingCachedTools() async throws {
        let cachedTool = MCPTool(name: "cached", description: "Cached tool", inputSchema: MCPToolInputSchema())
        let server = makeServer(discoveredTools: [cachedTool])
        MockURLProtocol.install { request in
            try Self.jsonResponse(
                for: request,
                body: [
                    "jsonrpc": "2.0",
                    "id": 1,
                    "error": ["code": -32000, "message": "Initialization failed"]
                ]
            )
        }

        let client = makeClient(config: server)
        do {
            _ = try await client.initializeAndDiscover()
            XCTFail("Expected a JSON-RPC error to fail discovery")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Initialization failed"))
        }

        XCTAssertEqual(Self.methods(in: MockURLProtocol.capturedRequests), ["initialize"])
    }

    func testInitializeAndDiscoverThrowsOnHTTPUnauthorizedInsteadOfUsingCachedTools() async throws {
        let cachedTool = MCPTool(name: "cached", description: "Cached tool", inputSchema: MCPToolInputSchema())
        let server = makeServer(discoveredTools: [cachedTool])
        MockURLProtocol.install { _ in
            MockURLProtocol.Response(
                statusCode: 401,
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"error":"Unauthorized"}"#.utf8)
            )
        }

        let client = makeClient(config: server)
        do {
            _ = try await client.initializeAndDiscover()
            XCTFail("Expected HTTP 401 to fail discovery")
        } catch {
            XCTAssertFalse(error.localizedDescription.isEmpty)
        }

        XCTAssertEqual(Self.methods(in: MockURLProtocol.capturedRequests), ["initialize"])
    }

    func testInitializeAndDiscoverDecodesLiveToolsAndResources() async throws {
        let toolSchema: [String: Any] = [
            "type": "object",
            "title": "Query arguments",
            "additionalProperties": false,
            "properties": [
                "sql": ["type": "string", "description": "SQL query", "minLength": 1],
                "tags": [
                    "type": "array",
                    "items": ["type": "string", "enum": ["read", "write"]]
                ]
            ],
            "required": ["sql", "tags"]
        ]
        MockURLProtocol.install { request in
            let method = try Self.method(in: request)
            switch method {
            case "initialize":
                return try Self.jsonResponse(
                    for: request,
                    result: [
                        "protocolVersion": "2024-11-05",
                        "capabilities": [
                            "tools": [String: String](),
                            "resources": [String: String]()
                        ],
                        "serverInfo": ["name": "Test MCP", "version": "1.0"]
                    ]
                )
            case "notifications/initialized":
                return MockURLProtocol.Response(statusCode: 202, body: Data())
            case "tools/list":
                return try Self.jsonResponse(
                    for: request,
                    result: [
                        "tools": [[
                            "name": "query",
                            "description": "Run a SQL query",
                            "inputSchema": toolSchema
                        ]]
                    ]
                )
            case "resources/list":
                return try Self.jsonResponse(
                    for: request,
                    result: [
                        "resources": [[
                            "uri": "file:///schema.sql",
                            "name": "Database schema",
                            "description": "Current schema",
                            "mimeType": "text/plain"
                        ]]
                    ]
                )
            default:
                return MockURLProtocol.Response(
                    statusCode: 500,
                    body: Data(#"{"error":"Unexpected method"}"#.utf8)
                )
            }
        }

        let server = makeServer()
        let client = makeClient(config: server)
        let discovery = try await client.initializeAndDiscover()

        XCTAssertEqual(discovery.tools, [
            MCPTool(
                name: "query",
                description: "Run a SQL query",
                inputSchema: MCPToolInputSchema(
                    properties: [
                        "sql": MCPToolParameterProperty(
                            type: "string",
                            description: "SQL query",
                            additionalFields: ["minLength": .number(1)]
                        ),
                        "tags": MCPToolParameterProperty(
                            type: "array",
                            items: MCPToolParameterProperty(type: "string", enumValues: ["read", "write"])
                        )
                    ],
                    required: ["sql", "tags"],
                    additionalFields: [
                        "title": .string("Query arguments"),
                        "additionalProperties": .bool(false)
                    ]
                )
            )
        ])
        XCTAssertEqual(discovery.resources, [
            MCPResource(
                uri: "file:///schema.sql",
                name: "Database schema",
                description: "Current schema",
                mimeType: "text/plain"
            )
        ])
        XCTAssertEqual(
            Self.methods(in: MockURLProtocol.capturedRequests),
            ["initialize", "notifications/initialized", "tools/list", "resources/list"]
        )
    }

    func testCallToolDecodesTextContentFromJSONRPCResponse() async throws {
        MockURLProtocol.install { request in
            switch try Self.method(in: request) {
            case "tools/call":
                let requestBody = try Self.requestBody(in: request)
                return try Self.jsonResponse(
                    id: try XCTUnwrap(requestBody["id"]),
                    result: ["content": [["type": "text", "text": "Found 3 rows"]]]
                )
            default:
                return try Self.defaultResponse(for: request)
            }
        }

        let client = makeClient(config: makeServer())
        _ = try await client.initializeAndDiscover()
        let result = try await client.callTool(name: "query", arguments: ["sql": "SELECT 1"])

        XCTAssertEqual(result, "Found 3 rows")
        XCTAssertEqual(Self.methods(in: MockURLProtocol.capturedRequests), [
            "initialize", "notifications/initialized", "tools/list", "resources/list", "tools/call"
        ])
        let call = try XCTUnwrap(MockURLProtocol.capturedRequests.first { request in
            (try? Self.method(in: request)) == "tools/call"
        })
        let body = try Self.requestBody(in: call)
        let params = try XCTUnwrap(body["params"] as? [String: Any])
        XCTAssertEqual(params["name"] as? String, "query")
        XCTAssertEqual(params["arguments"] as? [String: String], ["sql": "SELECT 1"])
    }

    func testInitializeRejectsMalformedJSONAndWrongResponseID() async throws {
        for response in [
            MockURLProtocol.Response(body: Data("not-json".utf8)),
            MockURLProtocol.Response(body: Data(#"{"jsonrpc":"2.0","id":999,"result":{"protocolVersion":"2024-11-05"}}"#.utf8))
        ] {
            MockURLProtocol.install { _ in response }
            let client = makeClient(config: makeServer())
            do {
                _ = try await client.initializeAndDiscover()
                XCTFail("Expected an invalid initialize response to fail")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("invalid response"))
            }
        }
    }

    func testStreamableHTTPUsesSessionAndNegotiatedProtocolVersionHeaders() async throws {
        MockURLProtocol.install { request in
            let method = try Self.method(in: request)
            if method == "initialize" {
                return try Self.jsonResponse(
                    for: request,
                    result: [
                        "protocolVersion": "2024-11-05",
                        "capabilities": ["tools": [String: String](), "resources": [String: String]()],
                        "serverInfo": ["name": "test", "version": "1"]
                    ],
                    headers: ["Content-Type": "application/json", "Mcp-Session-Id": "session-123"]
                )
            }
            return try Self.defaultResponse(for: request)
        }

        let client = makeClient(config: makeServer())
        _ = try await client.initializeAndDiscover()

        let requests = MockURLProtocol.capturedRequests
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "Mcp-Session-Id"))
        XCTAssertNil(requests[0].value(forHTTPHeaderField: "MCP-Protocol-Version"))
        for request in requests.dropFirst() {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Mcp-Session-Id"), "session-123")
            XCTAssertEqual(request.value(forHTTPHeaderField: "MCP-Protocol-Version"), "2024-11-05")
        }
    }

    func testStreamableHTTPAcceptsSSEResponseForRPC() async throws {
        MockURLProtocol.install { request in
            guard try Self.method(in: request) == "initialize" else {
                return try Self.defaultResponse(for: request)
            }
            let message = try Self.sseMessage(
                id: 1,
                result: [
                    "protocolVersion": "2024-11-05",
                    "capabilities": ["tools": [String: String](), "resources": [String: String]()],
                    "serverInfo": ["name": "test", "version": "1"]
                ]
            )
            return MockURLProtocol.Response(
                headers: ["Content-Type": "text/event-stream"],
                body: Data(message.utf8)
            )
        }

        let client = makeClient(config: makeServer())
        let discovery = try await client.initializeAndDiscover()
        XCTAssertEqual(discovery.tools, [])
        XCTAssertEqual(discovery.resources, [])
    }

    func testLegacySSEReadsEndpointAndCorrelatesJSONRPCMessages() async throws {
        let eventBody = try [
            "event: endpoint\ndata: /messages?session=legacy\n\n",
            Self.sseMessage(id: 1, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [String: String](), "resources": [String: String]()],
                "serverInfo": ["name": "legacy", "version": "1"]
            ]),
            Self.sseMessage(id: 2, result: ["tools": []]),
            Self.sseMessage(id: 3, result: ["resources": []]),
            Self.sseMessage(id: 4, result: ["content": [["type": "text", "text": "legacy result"]]])
        ].joined()
        MockURLProtocol.install { request in
            XCTAssertEqual(request.url?.path, "/messages")
            return MockURLProtocol.Response(statusCode: 202, body: Data())
        }

        let server = MCPServerConfig(
            name: "Legacy MCP",
            transport: .sse,
            endpointURLString: "https://mcp.example.test/sse"
        )
        let client = makeClient(config: server, eventStreamResponse: { request in
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/event-stream")
                return Data(eventBody.utf8)
            })
        _ = try await client.initializeAndDiscover()
        let output = try await client.callTool(name: "query", arguments: [:])
        XCTAssertEqual(output, "legacy result")
        XCTAssertEqual(Self.methods(in: MockURLProtocol.capturedRequests), [
            "initialize", "notifications/initialized", "tools/list", "resources/list", "tools/call"
        ])
        XCTAssertEqual(
            MockURLProtocol.capturedRequests.filter { $0.httpMethod == "POST" }.compactMap { $0.url?.path },
            Array(repeating: "/messages", count: 5)
        )
    }

    func testCallToolRejectsHTTPAndJSONRPCErrorsAndMCPIsError() async throws {
        for failure in ["http", "rpc", "tool"] {
            MockURLProtocol.install { request in
                if try Self.method(in: request) == "tools/call" {
                    if failure == "http" {
                        return MockURLProtocol.Response(statusCode: 503, body: Data())
                    }
                    let requestID = try XCTUnwrap(Self.requestBody(in: request)["id"])
                    if failure == "rpc" {
                        return try Self.jsonErrorResponse(id: requestID, code: -32000, message: "call rejected")
                    }
                    return try Self.jsonResponse(
                        id: requestID,
                        result: ["isError": true, "content": [["type": "text", "text": "tool failed"]]]
                    )
                }
                return try Self.defaultResponse(for: request)
            }
            let client = makeClient(config: makeServer())
            _ = try await client.initializeAndDiscover()
            do {
                _ = try await client.callTool(name: "query", arguments: [:])
                XCTFail("Expected \(failure) tool failure")
            } catch {
                XCTAssertFalse(error.localizedDescription.isEmpty)
                if failure == "http" { XCTAssertTrue(error.localizedDescription.contains("503")) }
                if failure == "rpc" { XCTAssertTrue(error.localizedDescription.contains("call rejected")) }
                if failure == "tool" { XCTAssertTrue(error.localizedDescription.contains("tool failed")) }
            }
        }
    }

    func testCallToolReturnsJSONTextForNonTextContent() async throws {
        MockURLProtocol.install { request in
            if try Self.method(in: request) == "tools/call" {
                let requestID = try XCTUnwrap(Self.requestBody(in: request)["id"])
                return try Self.jsonResponse(
                    id: requestID,
                    result: ["content": [["type": "image", "data": "AQID", "mimeType": "image/png"]]]
                )
            }
            return try Self.defaultResponse(for: request)
        }
        let client = makeClient(config: makeServer())
        _ = try await client.initializeAndDiscover()
        let output = try await client.callTool(name: "image", arguments: [:])
        let blocks = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(output.utf8)) as? [[String: Any]]
        )
        XCTAssertEqual(blocks.first?["type"] as? String, "image")
        XCTAssertEqual(blocks.first?["mimeType"] as? String, "image/png")
    }

    func testUnsupportedTransportsThrowWithoutMakingHTTPRequests() async throws {
        MockURLProtocol.install { _ in
            XCTFail("Unsupported transports must not make HTTP requests")
            return MockURLProtocol.Response(statusCode: 500, body: Data())
        }
        for transport in [MCPTransportType.websocket, .stdioRemote] {
            let config = MCPServerConfig(
                name: "Unsupported",
                transport: transport,
                endpointURLString: "https://mcp.example.test/"
            )
            let client = makeClient(config: config)
            do {
                _ = try await client.initializeAndDiscover()
                XCTFail("Expected \(transport.rawValue) to be rejected")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("not supported"))
            }
            do {
                _ = try await client.callTool(name: "query", arguments: [:])
                XCTFail("Expected \(transport.rawValue) call to be rejected")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("not supported"))
            }
        }
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }

    func testAuthorizationAndCustomHeaderUseConfiguredKeychainValues() async throws {
        let tokenKey = "mcp-test-token-\(UUID().uuidString)"
        let headerKey = "mcp-test-header-\(UUID().uuidString)"
        let token = "actual-token-value"
        let headerValue = "custom-secret-value"
        MockURLProtocol.install { request in try Self.defaultResponse(for: request) }
        let config = MCPServerConfig(
            name: "Authenticated MCP",
            transport: .streamableHTTP,
            endpointURLString: "https://mcp.example.test/",
            authTokenKey: tokenKey,
            customHeaders: [HTTPHeaderField(key: "X-Test", value: headerKey)]
        )
        let encodedConfig = try JSONEncoder().encode(config)
        let encodedText = try XCTUnwrap(String(data: encodedConfig, encoding: .utf8))
        XCTAssertTrue(encodedText.contains(tokenKey))
        XCTAssertFalse(encodedText.contains(token))
        XCTAssertFalse(encodedText.contains(headerValue))

        let client = makeClient(config: config, credentials: [tokenKey: token, headerKey: headerValue])
        _ = try await client.initializeAndDiscover()

        XCTAssertEqual(MockURLProtocol.capturedRequests.count, 4)
        for request in MockURLProtocol.capturedRequests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Test"), headerValue)
        }
    }

    func testTransportEnumContinuesToDecodePreviouslySavedValues() throws {
        for (rawValue, expected) in [
            ("sse", MCPTransportType.sse),
            ("websocket", .websocket),
            ("stdio_remote", .stdioRemote)
        ] {
            let data = Data("\"\(rawValue)\"".utf8)
            XCTAssertEqual(try JSONDecoder().decode(MCPTransportType.self, from: data), expected)
        }
        XCTAssertEqual(MCPTransportType.streamableHTTP.rawValue, "streamable_http")
    }

    private static func defaultResponse(for request: URLRequest) throws -> MockURLProtocol.Response {
        switch try method(in: request) {
        case "initialize":
            return try jsonResponse(
                for: request,
                result: [
                    "protocolVersion": "2024-11-05",
                    "capabilities": ["tools": [String: String](), "resources": [String: String]()],
                    "serverInfo": ["name": "Test MCP", "version": "1.0"]
                ]
            )
        case "notifications/initialized":
            return MockURLProtocol.Response(statusCode: 202, body: Data())
        case "tools/list":
            return try jsonResponse(for: request, result: ["tools": []])
        case "resources/list":
            return try jsonResponse(for: request, result: ["resources": []])
        default:
            return MockURLProtocol.Response(statusCode: 500, body: Data())
        }
    }

    private static func jsonErrorResponse(
        id: Any,
        code: Int,
        message: String
    ) throws -> MockURLProtocol.Response {
        MockURLProtocol.Response(
            body: try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0",
                "id": id,
                "error": ["code": code, "message": message, "data": ["reason": "invalid arguments"]]
            ])
        )
    }

    private static func sseMessage(id: Int, result: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ])
        return "event: message\ndata: \(String(decoding: data, as: UTF8.self))\n\n"
    }

    private func makeServer(discoveredTools: [MCPTool] = []) -> MCPServerConfig {
        MCPServerConfig(
            name: "Test MCP",
            transport: .streamableHTTP,
            endpointURLString: "https://mcp.example.test/",
            discoveredTools: discoveredTools
        )
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func makeClient(
        config: MCPServerConfig,
        credentials: [String: String] = [:],
        eventStreamResponse: (@Sendable (URLRequest) async throws -> Data)? = nil
    ) -> MCPClient {
        MCPClient(
            config: config,
            session: makeSession(),
            credentialLookup: { credentials[$0] },
            requestPerformer: { try MockURLProtocol.execute($0) },
            eventStreamResponse: eventStreamResponse
        )
    }

    private static func methods(in requests: [URLRequest]) -> [String] {
        requests.compactMap { request in
            guard let body = request.httpBody,
                  let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
                return nil
            }
            return object["method"] as? String
        }
    }

    private static func method(in request: URLRequest) throws -> String {
        let body = try requestBody(in: request)
        guard let method = body["method"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        return method
    }

    private static func requestBody(in request: URLRequest) throws -> [String: Any] {
        guard let data = request.httpBody,
              let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return body
    }

    private static func jsonResponse(
        for request: URLRequest,
        result: [String: Any]? = nil,
        body: [String: Any]? = nil,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) throws -> MockURLProtocol.Response {
        let requestBody = try requestBody(in: request)
        let requestID = requestBody["id"]
        var responseBody = body ?? [
            "jsonrpc": "2.0",
            "result": result ?? [:]
        ]
        if responseBody["id"] == nil {
            responseBody["id"] = requestID
        }
        return MockURLProtocol.Response(
            headers: headers,
            body: try JSONSerialization.data(withJSONObject: responseBody)
        )
    }

    private static func jsonResponse(
        id: Any,
        result: [String: Any]
    ) throws -> MockURLProtocol.Response {
        MockURLProtocol.Response(
            body: try JSONSerialization.data(withJSONObject: [
                "jsonrpc": "2.0",
                "id": id,
                "result": result
            ])
        )
    }
}
