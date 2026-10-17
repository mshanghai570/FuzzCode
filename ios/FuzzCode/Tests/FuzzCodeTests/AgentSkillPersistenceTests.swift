import Foundation
import XCTest
@testable import FuzzCodeCore

final class AgentSkillPersistenceTests: XCTestCase {
    func testAgentSkillCodableRoundTrip() throws {
        let skill = AgentSkill(
            id: UUID(uuidString: "D95FE92F-29DF-4F8D-A8D0-5D15D355330B")!,
            name: "Swift conventions",
            content: "Prefer value types.",
            updatedAt: Date(timeIntervalSince1970: 1_728_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        XCTAssertEqual(try decoder.decode(AgentSkill.self, from: encoder.encode(skill)), skill)
    }

    func testSkillsPersistencePreservesMarkdownExactly() throws {
        let (storage, directoryURL) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let markdown = """
        ---
        name: Swift conventions
        description: Preserve this front matter and fenced example exactly.
        ---

        # Guidelines

        Keep the original whitespace and Markdown syntax.

        ```swift
        struct Example {
            let value = "unchanged"
        }
        ```
        """
        let skill = AgentSkill(
            id: UUID(uuidString: "D95FE92F-29DF-4F8D-A8D0-5D15D355330B")!,
            name: "Swift conventions",
            content: markdown,
            updatedAt: Date(timeIntervalSince1970: 1_728_000_000)
        )

        try storage.saveSkills([skill])

        let restored = try XCTUnwrap(storage.loadSkills().first)
        XCTAssertEqual(restored, skill)
        XCTAssertEqual(restored.content, markdown)
    }

    func testMissingSkillsFileReturnsEmptyList() throws {
        let (storage, directoryURL) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        XCTAssertEqual(try storage.loadSkills(), [])
    }

    func testMalformedSkillsJSONThrows() throws {
        let (storage, directoryURL) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try Data("{invalid".utf8).write(to: directoryURL.appendingPathComponent("skills.json"))

        XCTAssertThrowsError(try storage.loadSkills())
    }

    func testSkillsReadFailureThrows() throws {
        let (storage, directoryURL) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try FileManager.default.createDirectory(
            at: directoryURL.appendingPathComponent("skills.json", isDirectory: true),
            withIntermediateDirectories: true
        )

        XCTAssertThrowsError(try storage.loadSkills())
    }

    func testSkillsWriteFailureThrows() throws {
        let (storage, directoryURL) = try makeStorage()
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        try Data("not a directory".utf8).write(to: directoryURL)

        XCTAssertThrowsError(try storage.saveSkills([]))
    }

    private func makeStorage() throws -> (storage: StorageService, directoryURL: URL) {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentSkillPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        return (StorageService(directoryURL: directoryURL), directoryURL)
    }
}
