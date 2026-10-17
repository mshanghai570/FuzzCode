import Foundation
import XCTest
@testable import FuzzCodeCore

/// Holds an SSE connection open after its first delta to verify cancellation reaches URLSession.
private final class HoldingProviderStream: URLProtocol {
    static var started: XCTestExpectation?
    static var stopped: XCTestExpectation?
    static var payload = ""
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.payload.utf8))
        Self.started?.fulfill()
    }
    override func stopLoading() { Self.stopped?.fulfill() }
}

final class ProviderStreamingTests: XCTestCase {
    func testCancelConsumerStopsEachProviderStreamingRequest() async throws {
        for kind in [ProviderKind.openai, .anthropic, .gemini] {
            let received = expectation(description: "Received \(kind) text")
            HoldingProviderStream.started = nil
            HoldingProviderStream.stopped = expectation(description: "Stopped \(kind) HTTP stream")
            HoldingProviderStream.stopped?.assertForOverFulfill = false
            switch kind {
            case .anthropic: HoldingProviderStream.payload = "data: {\"type\":\"content_block_delta\",\"delta\":{\"type\":\"text_delta\",\"text\":\"hello\"}}\n\n"
            case .gemini: HoldingProviderStream.payload = "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"hello\"}]}}]}\n\n"
            default: HoldingProviderStream.payload = "data: {\"choices\":[{\"delta\":{\"content\":\"hello\"}}]}\n\n"
            }
            let sessionConfig = URLSessionConfiguration.ephemeral
            sessionConfig.protocolClasses = [HoldingProviderStream.self]
            let session = URLSession(configuration: sessionConfig)
            let config = ProviderConfig(displayName: "Fixture", baseURLString: "https://fixture.test", providerKind: kind, selectedModel: kind.defaultModel)
            let store = StubCredentialStore(secret: "fixture-key")
            let provider: any AIProvider
            switch kind {
            case .anthropic: provider = try AnthropicProvider(config: config, credentialStore: store, session: session)
            case .gemini: provider = try GeminiProvider(config: config, credentialStore: store, session: session)
            default: provider = try OpenAICompatibleProvider(config: config, credentialStore: store, session: session)
            }
            let consumer = Task {
                let stream = await provider.streamChat(messages: [ChatMessage(role: .user, content: "hello")], systemPrompt: nil)
                do {
                    for try await text in stream {
                        XCTAssertEqual(text, "hello")
                        received.fulfill()
                    }
                } catch { /* Cancellation ends the consumer. */ }
            }
            await fulfillment(of: [received], timeout: 5)
            consumer.cancel()
            await fulfillment(of: [HoldingProviderStream.stopped!], timeout: 5)
            session.invalidateAndCancel()
        }
        HoldingProviderStream.stopped = nil
    }
}
