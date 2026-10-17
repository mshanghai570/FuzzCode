import Foundation
import XCTest
@testable import FuzzCodeCore

final class ProviderSecurityTests: XCTestCase {
    private func config(_ kind: ProviderKind, base: String? = nil) -> ProviderConfig {
        ProviderConfig(displayName: "Test", baseURLString: base ?? kind.defaultBaseURLString, providerKind: kind, selectedModel: kind.defaultModel)
    }
    func testGeminiUsesHeaderAndNormalizesVersionPath() throws {
        let provider = try GeminiProvider(config: config(.gemini, base: "https://example.test/v1beta/"))
        let request = try provider.generateRequest(stream: true, apiKey: "secret", systemPrompt: nil, messages: [])
        XCTAssertEqual(request.url?.path, "/v1beta/models/gemini-2.0-flash:streamGenerateContent")
        XCTAssertFalse(request.url!.absoluteString.contains("secret"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "secret")
    }
    func testAnthropicNormalizesVersionAndMovesSystemMessages() throws {
        let provider = try AnthropicProvider(config: config(.anthropic, base: "https://example.test/v1/"))
        let request = try provider.messagesRequest(messages: [ChatMessage(role: .system, content: "policy"), ChatMessage(role: .user, content: "Hi")], systemPrompt: "instructions", stream: false, apiKey: "secret")
        XCTAssertEqual(request.url?.path, "/v1/messages")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(body["system"] as? String, "instructions\n\npolicy")
        XCTAssertEqual((body["messages"] as? [[String: Any]])?.count, 1)
    }
    func testMalformedDiscoveryFailsInsteadOfReturningCuratedModels() async throws {
        for kind in [ProviderKind.anthropic, .gemini] {
            let cfg = config(kind)
            let performer: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
                (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let provider: any AIProvider = kind == .anthropic
                ? try AnthropicProvider(config: cfg, credentialStore: StubCredentialStore(secret: "secret"), requestPerformer: performer)
                : try GeminiProvider(config: cfg, credentialStore: StubCredentialStore(secret: "secret"), requestPerformer: performer)
            do { _ = try await provider.discoverModels(); XCTFail("Expected invalid response") }
            catch { XCTAssertEqual(error as? AIProviderError, .invalidResponse) }
        }
    }
    func testNativeToolAdaptersReplayCallsAndResults() async throws {
        for kind in [ProviderKind.anthropic, .gemini] {
            let cfg = config(kind)
            let performer: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
                let body = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
                let history = try XCTUnwrap(body[kind == .anthropic ? "messages" : "contents"] as? [[String: Any]])
                XCTAssertEqual(history.count, 3)
                let last = try XCTUnwrap(history.last)
                if kind == .anthropic {
                    let result = try XCTUnwrap((last["content"] as? [[String: Any]])?.first)
                    XCTAssertEqual(result["tool_use_id"] as? String, "call-1")
                } else {
                    let result = try XCTUnwrap(((last["parts"] as? [[String: Any]])?.first)?["functionResponse"] as? [String: Any])
                    XCTAssertEqual(result["name"] as? String, "read_file")
                }
                let json = kind == .anthropic ? #"{"content":[{"type":"text","text":"Done"}]}"# : #"{"candidates":[{"content":{"parts":[{"text":"Done"}]}}]}"#
                return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let provider: any AIProvider = kind == .anthropic
                ? try AnthropicProvider(config: cfg, credentialStore: StubCredentialStore(secret: "secret"), requestPerformer: performer)
                : try GeminiProvider(config: cfg, credentialStore: StubCredentialStore(secret: "secret"), requestPerformer: performer)
            let call = ProviderToolCall(id: "call-1", name: "read_file", arguments: Data(#"{"path":"a"}"#.utf8))
            let result = try await provider.completeWithTools(messages: [ChatMessage(role: .user, content: "Read")], systemPrompt: nil, tools: [], toolResults: [ProviderToolExchange(calls: [call], results: [ProviderToolResult(toolCallID: call.id, content: "file text")])])
            XCTAssertEqual(result, .message("Done"))
        }
    }
    func testNativeNetworkErrorsDoNotEchoCredentials() async throws {
        let provider = try GeminiProvider(config: config(.gemini), credentialStore: StubCredentialStore(secret: "private-key"), requestPerformer: { _ in
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "failed private-key"])
        })
        do { _ = try await provider.discoverModels(); XCTFail("Expected network error") }
        catch { XCTAssertFalse(error.localizedDescription.contains("private-key")) }
    }

    func testNativeDecodersPreserveProviderReplay() async throws {
        for kind in [ProviderKind.anthropic, .gemini] {
            let json = kind == .anthropic
                ? #"{"content":[{"type":"text","text":"Checking"},{"type":"tool_use","id":"c1","name":"read_file","input":{"path":"a"}}]}"#
                : #"{"candidates":[{"content":{"role":"model","parts":[{"thoughtSignature":"opaque","functionCall":{"id":"c1","name":"read_file","args":{"path":"a"}}}]}}]}"#
            let perform: @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
                (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            let provider: any AIProvider = kind == .anthropic
                ? try AnthropicProvider(config: config(kind), credentialStore: StubCredentialStore(secret: "key"), requestPerformer: perform)
                : try GeminiProvider(config: config(kind), credentialStore: StubCredentialStore(secret: "key"), requestPerformer: perform)
            let result = try await provider.completeWithTools(messages: [], systemPrompt: nil, tools: [], toolResults: [])
            guard case .toolCalls(let calls) = result else { return XCTFail("Expected calls") }
            XCTAssertEqual(calls.first?.id, "c1")
            XCTAssertEqual(calls.first?.name, "read_file")
            let arguments = try XCTUnwrap(calls.first?.arguments)
            XCTAssertEqual((try JSONSerialization.jsonObject(with: arguments) as? [String: String])?["path"], "a")
        }
    }

    func testCompatibleClientDoesNotExposeServerBodyOrTransportError() async throws {
        for networkFailure in [false, true] {
            let client = try OpenAIClient(config: config(.openai), credentialLookup: { _ in "private-key" }, requestPerformer: { request in
                if networkFailure { throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "private-key transport failure"]) }
                return (Data("private-key server echo".utf8), HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!)
            })
            do { _ = try await client.completeWithTools(messages: [], systemPrompt: nil, tools: []); XCTFail("Expected failure") }
            catch { XCTAssertFalse(error.localizedDescription.contains("private-key")); XCTAssertFalse(String(describing: error).contains("private-key")) }
        }
    }

}
