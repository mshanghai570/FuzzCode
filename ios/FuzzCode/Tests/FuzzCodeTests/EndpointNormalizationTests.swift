import XCTest
@testable import FuzzCodeCore

final class EndpointNormalizationTests: XCTestCase {
    
    func testBaseURLNormalizationWithoutTrailingSlash() {
        let config = ProviderConfig(
            displayName: "Test",
            baseURLString: "https://api.openai.com/v1"
        )
        XCTAssertEqual(config.resolvedBaseURL?.absoluteString, "https://api.openai.com/v1")
    }
    
    func testBaseURLNormalizationWithTrailingSlashes() {
        let config = ProviderConfig(
            displayName: "Test",
            baseURLString: "https://api.openai.com/v1///"
        )
        XCTAssertEqual(config.resolvedBaseURL?.absoluteString, "https://api.openai.com/v1")
    }
    
    func testChatCompletionsURLResolutionPreventsDoubleV1() {
        let urlWithV1 = URL(string: "https://api.groq.com/openai/v1")!
        let chatURL = OpenAIClient.constructChatCompletionsURL(baseURL: urlWithV1, customApiPath: nil)
        XCTAssertEqual(chatURL.absoluteString, "https://api.groq.com/openai/v1/chat/completions")
    }
    
    func testChatCompletionsURLResolutionAddsV1WhenMissing() {
        let urlWithoutV1 = URL(string: "https://api.openai.com")!
        let chatURL = OpenAIClient.constructChatCompletionsURL(baseURL: urlWithoutV1, customApiPath: nil)
        XCTAssertEqual(chatURL.absoluteString, "https://api.openai.com/v1/chat/completions")
    }
    
    func testModelsURLResolutionAvoidsDuplicateV1() {
        let url = URL(string: "https://api.openai.com/v1")!
        let modelsURL = OpenAIClient.constructModelsURL(baseURL: url)
        XCTAssertEqual(modelsURL.absoluteString, "https://api.openai.com/v1/models")
    }
    
    func testCustomApiPathOverride() {
        let url = URL(string: "https://custom-ai.company.internal/proxy")!
        let chatURL = OpenAIClient.constructChatCompletionsURL(baseURL: url, customApiPath: "/v2/completions")
        XCTAssertEqual(chatURL.absoluteString, "https://custom-ai.company.internal/proxy/v2/completions")
    }
    
    func testInsecureHTTPRejectedByDefault() {
        let config = ProviderConfig(
            displayName: "Local Insecure",
            baseURLString: "http://192.168.1.50:8000/v1",
            allowsInsecureHTTP: false
        )
        XCTAssertNil(config.resolvedBaseURL, "Plain HTTP must be rejected when allowsInsecureHTTP is false")
    }
    
    func testInsecureHTTPAllowedWhenExplicitlyEnabled() {
        let config = ProviderConfig(
            displayName: "Local Insecure Allowed",
            baseURLString: "http://192.168.1.50:8000/v1",
            allowsInsecureHTTP: true
        )
        XCTAssertNotNil(config.resolvedBaseURL)
        XCTAssertEqual(config.resolvedBaseURL?.absoluteString, "http://192.168.1.50:8000/v1")
    }
}
