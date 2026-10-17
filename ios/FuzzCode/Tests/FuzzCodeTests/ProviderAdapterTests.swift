import XCTest
import Foundation
@testable import FuzzCodeCore

struct StubCredentialStore: CredentialStore {
    let secret: String?
    func retrieve(key: String) -> String? { secret }
    func store(key: String, secret: String) {}
    func remove(key: String) {}
}

final class ProviderAdapterTests: XCTestCase {

    func testProviderKindPresets() {
        XCTAssertEqual(ProviderKind.openai.defaultBaseURLString, "https://api.openai.com/v1")
        XCTAssertEqual(ProviderKind.anthropic.defaultBaseURLString, "https://api.anthropic.com")
        XCTAssertEqual(ProviderKind.gemini.defaultBaseURLString, "https://generativelanguage.googleapis.com")
        XCTAssertEqual(ProviderKind.openRouter.defaultBaseURLString, "https://openrouter.ai/api/v1")
        XCTAssertEqual(ProviderKind.groq.defaultBaseURLString, "https://api.groq.com/openai/v1")
        for kind in [ProviderKind.openai, .anthropic, .gemini, .openRouter, .groq] {
            XCTAssertFalse(kind.curatedModels.isEmpty, "\(kind) should ship curated models")
        }
        XCTAssertTrue(ProviderKind.openai.isOpenAICompatible)
        XCTAssertTrue(ProviderKind.groq.isOpenAICompatible)
        XCTAssertFalse(ProviderKind.anthropic.isOpenAICompatible)
        XCTAssertFalse(ProviderKind.gemini.isOpenAICompatible)
        XCTAssertTrue(ProviderKind.anthropic.supportsNativeToolLoop)
        XCTAssertTrue(ProviderKind.openai.supportsNativeToolLoop)
    }

    func testProviderConfigDecodesLegacyPayloadWithoutKind() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","displayName":"Old","baseURLString":"https://api.openai.com/v1","selectedModel":"gpt-4o","authMethod":"api_key","isCodexOptimized":false,"customHeaders":[],"timeoutSeconds":30,"isEnabled":true,"allowsInsecureHTTP":false,"createdAt":"2026-01-01T00:00:00Z"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let config = try decoder.decode(ProviderConfig.self, from: legacy)
        XCTAssertNil(config.providerKind)
        XCTAssertEqual(config.resolvedKind, .custom)
    }

    func testMakeAIProviderReturnsCorrectAdapterKind() throws {
        let store = StubCredentialStore(secret: "test-key")
        for kind in ProviderKind.allCases {
            let config = ProviderConfig(displayName: kind.displayName, baseURLString: kind.defaultBaseURLString, providerKind: kind, selectedModel: kind.defaultModel)
            let adapter = try makeAIProvider(config: config, credentialStore: store)
            XCTAssertEqual(adapter.kind, kind)
        }
    }

    func testAnthropicRequestUsesNativeHeaders() throws {
        let config = ProviderConfig(displayName: "Anthropic", baseURLString: "https://api.anthropic.com", providerKind: .anthropic, selectedModel: "claude-sonnet-4-5")
        let provider = try AnthropicProvider(config: config, credentialStore: StubCredentialStore(secret: "sk-ant-test"))
        let request = try provider.messagesRequest(
            messages: [ChatMessage(role: .user, content: "hi")],
            systemPrompt: "sys",
            stream: true,
            apiKey: "sk-ant-test")
        XCTAssertEqual(request.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-api-key"), "sk-ant-test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
        XCTAssertEqual(body?["model"] as? String, "claude-sonnet-4-5")
        XCTAssertEqual(body?["system"] as? String, "sys")
    }

    func testAnthropicStreamTextParsing() {
        let payload = #"{"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}"#
        XCTAssertEqual(AnthropicProvider.extractStreamText(from: payload), "Hello")
        XCTAssertNil(AnthropicProvider.extractStreamText(from: #"{"type":"message_start"}"#))
        XCTAssertNil(AnthropicProvider.extractStreamText(from: "not json"))
    }

    func testGeminiRequestShape() throws {
        let config = ProviderConfig(displayName: "Gemini", baseURLString: "https://generativelanguage.googleapis.com", providerKind: .gemini, selectedModel: "gemini-2.0-flash")
        let provider = try GeminiProvider(config: config, credentialStore: StubCredentialStore(secret: "g-key"))
        let request = try provider.generateRequest(
            stream: true,
            apiKey: "g-key",
            systemPrompt: "sys",
            messages: [ChatMessage(role: .user, content: "hi")])
        let url = request.url?.absoluteString ?? ""
        XCTAssertTrue(url.contains("streamGenerateContent"))
        XCTAssertFalse(url.contains("key=g-key"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "g-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any]
        XCTAssertNotNil(body?["system_instruction"])
    }

    func testGeminiStreamTextParsing() {
        let payload = #"{"candidates":[{"content":{"parts":[{"text":"Hello "},{"text":"world"}]}}]}"#
        XCTAssertEqual(GeminiProvider.extractStreamTexts(from: payload), ["Hello world"])
        XCTAssertTrue(GeminiProvider.extractStreamTexts(from: #"{"promptFeedback":{}}"#).isEmpty)
    }

    func testHTTPACPTransportRoundTrip() async throws {
        let result: [String: Any] = ["ok": true]
        let data = try JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": "1", "result": result])
        let response = HTTPURLResponse(url: URL(string: "https://agent.local/rpc")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let transport = HTTPACPTransport(endpoint: URL(string: "https://agent.local/rpc")!) { _ in (data, response) }
        let returned = try await transport.send(method: "session/new", params: ["a": 1])
        XCTAssertEqual(returned["ok"] as? Bool, true)
    }

    func testHTTPACPTransportSurfacesRemoteErrors() async {
        let data = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": "1", "error": ["code": -1, "message": "boom"]])
        let response = HTTPURLResponse(url: URL(string: "https://agent.local/rpc")!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let transport = HTTPACPTransport(endpoint: URL(string: "https://agent.local/rpc")!) { _ in (data, response) }
        do {
            _ = try await transport.send(method: "x")
            XCTFail("expected remote error")
        } catch let error as AgentConnectionError {
            XCTAssertEqual(error, .remoteError("boom"))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testRemoteAgentDescriptorsMarkExperimentalKinds() {
        XCTAssertFalse(RemoteAgentDescriptor.opencode.isExperimental)
        XCTAssertFalse(RemoteAgentDescriptor.opencode.kind.requiresRemoteRuntime == false)
        XCTAssertTrue(RemoteAgentDescriptor.codex.isExperimental)
        XCTAssertTrue(RemoteAgentDescriptor.claudeCode.isExperimental)
        XCTAssertTrue(RemoteAgentDescriptor.customACP.isExperimental)
        XCTAssertFalse(AgentConnectionKind.native.requiresRemoteRuntime)
    }
}
