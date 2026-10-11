import XCTest
@testable import FuzzCodeCore

final class GitHubConnectorTests: XCTestCase {
    
    func testGitHubConfigInitialization() {
        let config = GitHubConfig(
            isConnected: false,
            keychainTokenKey: "fuzzcode_gh_token",
            scopes: ["repo", "workflow"]
        )
        
        XCTAssertFalse(config.isConnected)
        XCTAssertEqual(config.scopes.count, 2)
        XCTAssertTrue(config.scopes.contains("repo"))
    }
    
    func testGitHubRepoDecoding() throws {
        let json = """
        {
          "id": 123456,
          "name": "fuzzcode",
          "full_name": "developer/fuzzcode",
          "private": true,
          "default_branch": "main",
          "description": "Native iOS AI Coding Agent Control Center",
          "html_url": "https://github.com/developer/fuzzcode",
          "stargazers_count": 42,
          "updated_at": "2026-10-11T12:00:00Z",
          "open_issues_count": 2
        }
        """.data(using: .utf8)!
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let repo = try decoder.decode(GitHubRepo.self, from: json)
        
        XCTAssertEqual(repo.id, 123456)
        XCTAssertEqual(repo.name, "fuzzcode")
        XCTAssertTrue(repo.isPrivate)
        XCTAssertEqual(repo.defaultBranch, "main")
        XCTAssertEqual(repo.stargazersCount, 42)
    }
}
