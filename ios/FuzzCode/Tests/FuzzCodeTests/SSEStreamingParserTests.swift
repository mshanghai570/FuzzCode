import XCTest
@testable import FuzzCodeCore

final class SSEStreamingParserTests: XCTestCase {
    
    func testExtractDeltaContentFromValidChunk() {
        let sampleJSON = """
        {
          "id": "chatcmpl-123",
          "object": "chat.completion.chunk",
          "created": 1694268190,
          "model": "gpt-4o",
          "choices": [
            {
              "index": 0,
              "delta": {
                "content": "Hello, world!"
              },
              "finish_reason": null
            }
          ]
        }
        """.data(using: .utf8)!
        
        let delta = OpenAIClient.extractDeltaContent(from: sampleJSON)
        XCTAssertEqual(delta, "Hello, world!")
    }
    
    func testExtractDeltaContentWithEmptyRoleDelta() {
        let sampleJSON = """
        {
          "id": "chatcmpl-123",
          "object": "chat.completion.chunk",
          "created": 1694268190,
          "model": "gpt-4o",
          "choices": [
            {
              "index": 0,
              "delta": {
                "role": "assistant"
              },
              "finish_reason": null
            }
          ]
        }
        """.data(using: .utf8)!
        
        let delta = OpenAIClient.extractDeltaContent(from: sampleJSON)
        XCTAssertNil(delta, "Should return nil when delta does not contain content text")
    }
    
    func testExtractDeltaContentHandlesMalformedJSONGracefully() {
        let malformed = "this is not json".data(using: .utf8)!
        let delta = OpenAIClient.extractDeltaContent(from: malformed)
        XCTAssertNil(delta)
    }
}
