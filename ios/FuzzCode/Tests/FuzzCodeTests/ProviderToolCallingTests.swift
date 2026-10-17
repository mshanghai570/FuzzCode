import Foundation
import XCTest
@testable import FuzzCodeCore

final class ProviderToolCallingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.reset()
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testToolRequestUsesProviderSchemaAndConfiguredAuthentication() async throws {
        MockURLProtocol.install { _ in
            try Self.response(message: ["content": "Ready"])
        }
        let apiKey = "provider-test-secret"
        let client = try makeClient(apiKey: apiKey)
        let definition = ProviderToolDefinition(
            name: "database_query",
            description: "Run a database query",
            inputSchema: MCPToolInputSchema(
                properties: ["sql": MCPToolParameterProperty(type: "string")],
                required: ["sql"]
            )
        )

        let result = try await client.completeWithTools(
            messages: [ChatMessage(role: .user, content: "List the records")],
            systemPrompt: "Use tools when needed.",
            tools: [definition]
        )

        XCTAssertEqual(result, .message("Ready"))
        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        XCTAssertEqual(request.url?.path, "/v1/chat/completions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(apiKey)")
        let payload = try Self.requestBody(request)
        XCTAssertEqual(payload["model"] as? String, "test-model")
        XCTAssertEqual(payload["stream"] as? Bool, false)
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user"])
        let tools = try XCTUnwrap(payload["tools"] as? [[String: Any]])
        let function = try XCTUnwrap(tools.first?["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "database_query")
        let schema = try XCTUnwrap(function["parameters"] as? [String: Any])
        XCTAssertEqual(schema["required"] as? [String], ["sql"])
    }

    func testToolCallsDecodeIdentifiersAndJSONArguments() async throws {
        let arguments = #"{"sql":"SELECT 1"}"#
        MockURLProtocol.install { _ in
            try Self.response(message: [
                "content": NSNull(),
                "tool_calls": [[
                    "id": "call-1",
                    "type": "function",
                    "function": ["name": "database_query", "arguments": arguments]
                ]]
            ])
        }
        let client = try makeClient()

        let result = try await client.completeWithTools(
            messages: [ChatMessage(role: .user, content: "Run a query")],
            systemPrompt: nil,
            tools: []
        )

        guard case .toolCalls(let calls) = result else {
            return XCTFail("Expected a provider tool call")
        }
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.id, "call-1")
        XCTAssertEqual(calls.first?.name, "database_query")
        XCTAssertEqual(String(data: try XCTUnwrap(calls.first?.arguments), encoding: .utf8), arguments)
    }

    func testPriorToolCallsAndResultsAreIncludedInFollowUpRequest() async throws {
        MockURLProtocol.install { _ in try Self.response(message: ["content": "Done"]) }
        let client = try makeClient()
        let call = ProviderToolCall(
            id: "call-2",
            name: "database_query",
            arguments: Data(#"{"sql":"SELECT 2"}"#.utf8)
        )
        let exchange = ProviderToolExchange(
            calls: [call],
            results: [ProviderToolResult(toolCallID: "call-2", content: "2")]
        )

        let result = try await client.completeWithTools(
            messages: [ChatMessage(role: .user, content: "Run another query")],
            systemPrompt: nil,
            tools: [],
            toolResults: [exchange]
        )

        XCTAssertEqual(result, .message("Done"))
        let request = try XCTUnwrap(MockURLProtocol.capturedRequests.first)
        let payload = try Self.requestBody(request)
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        let assistant = try XCTUnwrap(messages.first { $0["role"] as? String == "assistant" })
        let assistantCalls = try XCTUnwrap(assistant["tool_calls"] as? [[String: Any]])
        let function = try XCTUnwrap(assistantCalls.first?["function"] as? [String: Any])
        XCTAssertEqual(assistantCalls.first?["id"] as? String, "call-2")
        XCTAssertEqual(function["arguments"] as? String, #"{"sql":"SELECT 2"}"#)
        let toolResult = try XCTUnwrap(messages.first { $0["role"] as? String == "tool" })
        XCTAssertEqual(toolResult["tool_call_id"] as? String, "call-2")
        XCTAssertEqual(toolResult["content"] as? String, "2")
    }

    func testMalformedToolArgumentsAndHTTPFailuresThrow() async throws {
        MockURLProtocol.install { _ in
            try Self.response(message: [
                "tool_calls": [[
                    "id": "call-bad",
                    "type": "function",
                    "function": ["name": "database_query", "arguments": "not-json"]
                ]]
            ])
        }
        let client = try makeClient()
        do {
            _ = try await client.completeWithTools(messages: [], systemPrompt: nil, tools: [])
            XCTFail("Expected malformed arguments to fail")
        } catch let error as OpenAIClientError {
            guard case .invalidResponseFormat = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        MockURLProtocol.install { _ in
            MockURLProtocol.Response(
                statusCode: 429,
                headers: ["Content-Type": "application/json"],
                body: Data(#"{"error":{"message":"rate limited"}}"#.utf8)
            )
        }
        do {
            _ = try await client.completeWithTools(messages: [], systemPrompt: nil, tools: [])
            XCTFail("Expected HTTP 429 to fail")
        } catch let error as OpenAIClientError {
            guard case .rateLimited = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    private func makeClient(apiKey: String? = nil) throws -> OpenAIClient {
        let config = ProviderConfig(
            displayName: "Test Provider",
            baseURLString: "https://api.example.test/v1",
            selectedModel: "test-model"
        )
        let credentialKey = "api_key_\(config.id.uuidString)"
        return try OpenAIClient(
            config: config,
            session: URLSession(configuration: .ephemeral),
            credentialLookup: { key in
                key == credentialKey ? apiKey : nil
            },
            requestPerformer: { try MockURLProtocol.execute($0) }
        )
    }

    private static func response(message: [String: Any]) throws -> MockURLProtocol.Response {
        MockURLProtocol.Response(
            body: try JSONSerialization.data(withJSONObject: [
                "choices": [["message": message, "finish_reason": "stop"]]
            ])
        )
    }

    private static func requestBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
