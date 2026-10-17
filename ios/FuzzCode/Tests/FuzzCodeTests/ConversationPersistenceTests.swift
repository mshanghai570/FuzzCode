import XCTest
@testable import FuzzCodeCore

final class ConversationPersistenceTests: XCTestCase {
    func testExistingConversationDecodesWithoutContextFields() throws {
        let original = ChatConversation(title: "Existing", providerId: UUID(), modelId: "test")
        let encoder = JSONEncoder()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(original)) as? [String: Any])
        json.removeValue(forKey: "systemPrompt")
        json.removeValue(forKey: "ragSources")
        json.removeValue(forKey: "ragConfig")
        json.removeValue(forKey: "selectedSkillIDs")
        let restored = try JSONDecoder().decode(ChatConversation.self,
            from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(restored.id, original.id)
        XCTAssertNil(restored.systemPrompt)
        XCTAssertNil(restored.ragSources)
        XCTAssertNil(restored.ragConfig)
        XCTAssertNil(restored.selectedSkillIDs)
    }

    func testConversationContextRoundTrips() throws {
        var conversation = ChatConversation(title: "Project", providerId: UUID(), modelId: "test")
        conversation.systemPrompt = "Follow the project conventions."
        conversation.ragSources = [RAGSource(title: "Architecture", type: .guideline,
            content: "Use Swift actors.", tokens: 4)]
        conversation.ragConfig = RAGConfig(topK: 2, maxContextTokens: 100)
        conversation.selectedSkillIDs = [UUID(), UUID()]
        let restored = try JSONDecoder().decode(ChatConversation.self, from: JSONEncoder().encode(conversation))
        XCTAssertEqual(restored, conversation)
    }
}
