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

    func testSystemPromptOmitsSelectedSkillsWhenEmpty() async {
        let prompt = await RAGService.shared.buildSystemPrompt(basePrompt: "Base prompt", ragContext: "")

        XCTAssertEqual(prompt, "Base prompt")
        XCTAssertFalse(prompt.contains("<selected_skills>"))
    }

    func testSystemPromptIncludesSelectedSkillNameAndExactBody() async {
        let skillBody = "---\nname: Review\n\nPreserve this body exactly.\n```swift\nlet answer = 42\n```"
        let prompt = await RAGService.shared.buildSystemPrompt(
            basePrompt: nil,
            ragContext: "",
            skillContents: [(name: "Code Review", content: skillBody)]
        )

        XCTAssertTrue(prompt.contains("[Skill: Code Review]\n\(skillBody)"))
        XCTAssertTrue(prompt.hasSuffix("<selected_skills>\n[Skill: Code Review]\n\(skillBody)\n</selected_skills>"))
    }

    func testSystemPromptIncludesMultipleSelectedSkills() async {
        let prompt = await RAGService.shared.buildSystemPrompt(
            basePrompt: nil,
            ragContext: "",
            skillContents: [
                (name: "First", content: "First skill body."),
                (name: "Second", content: "Second skill body.")
            ]
        )

        XCTAssertTrue(prompt.contains("[Skill: First]\nFirst skill body."))
        XCTAssertTrue(prompt.contains("[Skill: Second]\nSecond skill body."))
    }

    func testSystemPromptComposesOnlyExplicitlySelectedSkills() async {
        let selectedSkill = AgentSkill(name: "Selected", content: "Include this selected guidance.")
        let unselectedSkill = AgentSkill(name: "Unselected", content: "Never include this guidance.")
        let selectedIDs: Set<UUID> = [selectedSkill.id]
        let skillContents = [selectedSkill, unselectedSkill]
            .filter { selectedIDs.contains($0.id) }
            .map { (name: $0.name, content: $0.content) }

        let prompt = await RAGService.shared.buildSystemPrompt(
            basePrompt: "Custom system prompt.",
            ragContext: "<project_knowledge_base>Existing RAG context.</project_knowledge_base>",
            skillContents: skillContents)

        XCTAssertTrue(prompt.contains("Custom system prompt."))
        XCTAssertTrue(prompt.contains("Existing RAG context."))
        XCTAssertTrue(prompt.contains("[Skill: Selected]\nInclude this selected guidance."))
        XCTAssertFalse(prompt.contains("Unselected"))
        XCTAssertFalse(prompt.contains("Never include this guidance."))
    }

    func testSystemPromptRetainsBasePromptAndRAGContextWithSelectedSkills() async {
        let basePrompt = "You are a careful assistant."
        let ragContext = "<project_knowledge_base>Verified project guidance.</project_knowledge_base>"
        let prompt = await RAGService.shared.buildSystemPrompt(
            basePrompt: basePrompt,
            ragContext: ragContext,
            skillContents: [(name: "Concise", content: "Be concise.")]
        )

        XCTAssertTrue(prompt.contains(basePrompt))
        XCTAssertTrue(prompt.contains("## Verified Project Knowledge:\n\(ragContext)"))
        XCTAssertTrue(prompt.contains("<selected_skills>\n[Skill: Concise]\nBe concise.\n</selected_skills>"))
    }

    func testRetrievalRespectsContextBudget() async {
        let source = RAGSource(title: "Oversized", type: .document,
                               content: String(repeating: "Swift concurrency ", count: 100), tokens: 450)
        let result = await RAGService.shared.retrieve(query: "Swift", sources: [source],
            config: RAGConfig(maxContextTokens: 10))
        XCTAssertTrue(result.augmentedContext.isEmpty)
        XCTAssertTrue(result.citations.isEmpty)
    }

    func testRetrievalSkipsOversizedChunkAndIncludesSmallerMatch() async {
        let source = RAGSource(title: "Rules", type: .guideline,
            content: String(repeating: "Swift ", count: 100) + "\n\nSwift actors.", tokens: 155)
        let result = await RAGService.shared.retrieve(query: "Swift", sources: [source],
            config: RAGConfig(maxContextTokens: 30))
        XCTAssertEqual(result.citations.count, 1)
        XCTAssertEqual(result.citations.first?.snippet, "Swift actors.")
    }

    func testZeroRetrievalLimitsReturnNoContext() async {
        let source = RAGSource(title: "Rules", type: .document, content: "Swift actors", tokens: 3)
        for config in [RAGConfig(topK: 0), RAGConfig(maxContextTokens: 0)] {
            let result = await RAGService.shared.retrieve(query: "Swift", sources: [source], config: config)
            XCTAssertTrue(result.citations.isEmpty)
        }
    }

}
