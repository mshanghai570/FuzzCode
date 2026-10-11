import XCTest
@testable import FuzzCodeCore

final class RAGServiceTests: XCTestCase {
    
    func testChunkSourceSplitsByDoubleNewlines() async {
        let text = """
        Paragraph One: First chunk of knowledge.
        
        Paragraph Two: Second chunk of knowledge.
        
        Paragraph Three: Third chunk of knowledge.
        """
        let source = RAGSource(title: "Architecture Spec", type: .document, content: text, tokens: 40)
        let chunks = await RAGService.shared.chunkSource(source)
        
        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].sourceTitle, "Architecture Spec")
        XCTAssertTrue(chunks[0].content.contains("Paragraph One"))
    }
    
    func testRetrievalScoresRelevantChunks() async {
        let source = RAGSource(
            title: "Keychain Rules",
            type: .guideline,
            content: "Never log raw credentials. Store tokens in iOS Keychain with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly.",
            tokens: 30
        )
        let config = RAGConfig(isEnabled: true, topK: 3, similarityThreshold: 0.1)
        
        let result = await RAGService.shared.retrieve(query: "How should tokens be stored in Keychain?", sources: [source], config: config)
        
        XCTAssertFalse(result.citations.isEmpty)
        XCTAssertEqual(result.citations[0].sourceTitle, "Keychain Rules")
        XCTAssertTrue(result.augmentedContext.contains("<project_knowledge_base>"))
    }
    
    func testSystemPromptAugmentation() async {
        let base = "You are a Swift developer."
        let context = "<project_knowledge_base>[Source: Rules] Never fail.</project_knowledge_base>"
        let prompt = await RAGService.shared.buildSystemPrompt(basePrompt: base, ragContext: context)
        
        XCTAssertTrue(prompt.contains(base))
        XCTAssertTrue(prompt.contains("Verified Project Knowledge"))
    }
}
