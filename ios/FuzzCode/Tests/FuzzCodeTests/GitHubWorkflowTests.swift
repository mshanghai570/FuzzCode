import Foundation
import XCTest
@testable import FuzzCodeCore

final class GitHubWorkflowTests: XCTestCase {
    private let token = "fixture-secret-token"

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testRepositoryTreeAndContentUseAuthenticatedGitHubRoutes() async throws {
        MockURLProtocol.install { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(self.token)")
            switch request.url?.path {
            case "/repos/acme/project/git/trees/main":
                return .init(body: Data(#"{"sha":"tree-1","truncated":false,"tree":[{"path":"Sources/Hello.swift","mode":"100644","type":"blob","sha":"blob-1","size":18},{"path":"Assets","mode":"040000","type":"tree","sha":"tree-2"}]}"#.utf8))
            case "/repos/acme/project/contents/Sources/Hello.swift":
                let encoded = Data("print(\"hello\")".utf8).base64EncodedString()
                let response: [String: String] = ["type": "file", "encoding": "base64", "content": encoded]
                return .init(body: try JSONSerialization.data(withJSONObject: response))
            default:
                XCTFail("Unexpected GitHub route: \(request.url?.absoluteString ?? "nil")")
                return .init(statusCode: 404, body: Data())
            }
        }

        let client = GitHubClient(token: token, session: makeSession())
        let tree = try await client.fetchRepositoryTree(owner: "acme", repo: "project", branch: "main")
        XCTAssertEqual(tree.commitSHA, "tree-1")
        XCTAssertEqual(tree.files.map(\.path), ["Sources/Hello.swift"])
        let content = try await client.fetchFile(owner: "acme", repo: "project", path: "Sources/Hello.swift", ref: "main")
        XCTAssertEqual(content, "print(\"hello\")")
        XCTAssertTrue(MockURLProtocol.capturedRequests.allSatisfy { $0.url?.absoluteString.contains(token) == false })
    }

    func testRepositoryImportStoresTheFetchedSnapshotAsWorkspaceBaseline() async throws {
        MockURLProtocol.install { request in
            switch request.url?.path {
            case "/repos/acme/project/git/trees/main":
                return .init(body: Data(#"{"sha":"tree-1","truncated":false,"tree":[{"path":"README.md","type":"blob","sha":"blob-1","size":11}]}"#.utf8))
            case "/repos/acme/project/contents/README.md":
                let encoded = Data("hello repo\n".utf8).base64EncodedString()
                let response: [String: String] = ["type": "file", "encoding": "base64", "content": encoded]
                return .init(body: try JSONSerialization.data(withJSONObject: response))
            default:
                XCTFail("Unexpected GitHub route: \(request.url?.path ?? "nil")")
                return .init(statusCode: 404, body: Data())
            }
        }
        let workspace = try WorkspaceManager(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        let client = GitHubClient(token: token, session: makeSession())
        _ = try await client.importRepository(owner: "acme", repo: "project", branch: "main", into: workspace)
        XCTAssertEqual(try workspace.readFile(relativePath: "README.md"), "hello repo\n")
        XCTAssertTrue(try workspace.changeSummary().changedFiles.isEmpty)
    }

    func testRemotePublishingCannotStartWithoutExplicitReviewApproval() async throws {
        MockURLProtocol.install { _ in
            XCTFail("A rejected publication must not send a GitHub request")
            return .init(statusCode: 500, body: Data())
        }
        let client = GitHubClient(token: token, session: makeSession())
        do {
            _ = try await client.publishChanges(owner: "acme", repo: "project", baseBranch: "main",
                                                branchName: "fuzzcode/change", commitMessage: "change",
                                                pullRequestTitle: "change", pullRequestBody: "",
                                                changes: [GitHubFileChange(path: "a.swift", content: "let a = 1")],
                                                reviewApproved: false)
            XCTFail("Remote writes must require explicit diff review")
        } catch {
            XCTAssertEqual(error as? GitHubClientError, .reviewRequired)
        }
        XCTAssertTrue(MockURLProtocol.capturedRequests.isEmpty)
    }

    func testTruncatedTreeIsRejectedInsteadOfImportingAnIncompleteRepository() async throws {
        MockURLProtocol.install { _ in
            .init(body: Data(#"{"sha":"tree-1","truncated":true,"tree":[]}"#.utf8))
        }
        let client = GitHubClient(token: token, session: makeSession())
        do {
            _ = try await client.fetchRepositoryTree(owner: "acme", repo: "large", branch: "main")
            XCTFail("A truncated tree must not be treated as a complete repository")
        } catch {
            XCTAssertEqual(error as? GitHubClientError, .repositoryTreeTruncated)
        }
    }

    func testWorkspaceSearchReturnsOnlyMatchingFilesWithinBoundedInventory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspace = try WorkspaceManager(root: root)
        try workspace.writeFile(relativePath: "Sources/Agent.swift", content: "struct Agent { let repository = true }\n")
        try workspace.writeFile(relativePath: "README.md", content: "A mobile coding tool\n")

        let matches = try workspace.searchFiles(query: "repository")
        XCTAssertEqual(matches.map(\.path), ["Sources/Agent.swift"])
        XCTAssertEqual(matches[0].lineNumber, 1)
        XCTAssertTrue(matches[0].text.contains("repository"))
    }

    func testPublishingWritesOneMultiFileCommitThenCreatesBranchAndPullRequest() async throws {
        MockURLProtocol.install { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(self.token)")
            XCTAssertFalse(request.url?.absoluteString.contains(self.token) ?? true)
            switch (request.httpMethod, request.url?.path) {
            case ("GET", "/repos/acme/project/git/ref/heads/main"):
                return .init(body: Data(#"{"object":{"sha":"base-commit"}}"#.utf8))
            case ("GET", "/repos/acme/project/git/commits/base-commit"):
                return .init(body: Data(#"{"sha":"base-commit","tree":{"sha":"base-tree"}}"#.utf8))
            case ("POST", "/repos/acme/project/git/blobs"):
                return .init(body: Data(#"{"sha":"blob-new"}"#.utf8))
            case ("POST", "/repos/acme/project/git/trees"):
                let body = try XCTUnwrap(request.httpBody)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
                XCTAssertEqual(json["base_tree"] as? String, "base-tree")
                XCTAssertEqual((json["tree"] as? [[String: Any]])?.count, 2)
                return .init(body: Data(#"{"sha":"tree-new"}"#.utf8))
            case ("POST", "/repos/acme/project/git/commits"):
                return .init(body: Data(#"{"sha":"commit-new"}"#.utf8))
            case ("POST", "/repos/acme/project/git/refs"):
                return .init(statusCode: 201, body: Data(#"{"ref":"refs/heads/fuzzcode/change"}"#.utf8))
            case ("POST", "/repos/acme/project/pulls"):
                return .init(statusCode: 201, body: Data(#"{"number":42,"html_url":"https://github.com/acme/project/pull/42","title":"Improve parser","state":"open"}"#.utf8))
            default:
                XCTFail("Unexpected GitHub request: \(request.httpMethod ?? "nil") \(request.url?.path ?? "nil")")
                return .init(statusCode: 404, body: Data())
            }
        }

        let client = GitHubClient(token: token, session: makeSession())
        let result = try await client.publishChanges(
            owner: "acme", repo: "project", baseBranch: "main", branchName: "fuzzcode/change",
            commitMessage: "Improve parser", pullRequestTitle: "Improve parser", pullRequestBody: "Reviewed from FuzzCode.",
            changes: [
                GitHubFileChange(path: "Sources/Parser.swift", content: "struct Parser {}\n"),
                GitHubFileChange(path: "Tests/ParserTests.swift", content: "final class ParserTests {}\n")
            ],
            reviewApproved: true)

        XCTAssertEqual(result.branchName, "fuzzcode/change")
        XCTAssertEqual(result.commitSHA, "commit-new")
        XCTAssertEqual(result.pullRequest.number, 42)
        let requests = MockURLProtocol.capturedRequests
        XCTAssertEqual(requests.filter { $0.url?.path == "/repos/acme/project/git/trees" }.count, 1)
        XCTAssertEqual(requests.filter { $0.url?.path == "/repos/acme/project/git/commits" }.count, 1)
        XCTAssertEqual(requests.filter { $0.url?.path == "/repos/acme/project/git/blobs" }.count, 2)
        XCTAssertFalse(requests.contains { String(data: $0.httpBody ?? Data(), encoding: .utf8)?.contains(token) == true })
    }
}
