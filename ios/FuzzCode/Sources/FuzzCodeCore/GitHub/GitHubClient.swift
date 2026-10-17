import Foundation

/// Native GitHub REST client. The token remains private to this actor and is never
/// returned in models, URLs, errors, or request bodies.
public actor GitHubClient {
    private let session: URLSession
    private let token: String
    private let apiRoot = URL(string: "https://api.github.com")!

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    /// Authenticates with GitHub and returns account metadata and granted OAuth scopes.
    public func authenticate() async throws -> (user: GitHubUser, scopes: [String]) {
        let (data, response) = try await request(path: ["user"])
        let scopesHeader = response.value(forHTTPHeaderField: "X-OAuth-Scopes") ?? ""
        let scopes = scopesHeader.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        struct RawUser: Decodable {
            let login: String
            let name: String?
            let avatar_url: String
            let html_url: String
            let public_repos: Int?
            let total_private_repos: Int?
        }
        let raw = try JSONDecoder().decode(RawUser.self, from: data)
        let user = GitHubUser(login: raw.login, name: raw.name ?? raw.login, avatarUrl: raw.avatar_url,
                              htmlUrl: raw.html_url, publicRepos: raw.public_repos ?? 0,
                              totalPrivateRepos: raw.total_private_repos ?? 0)
        return (user, scopes)
    }

    /// Fetches the first bounded page of repositories accessible to the token.
    public func fetchRepositories(perPage: Int = 30) async throws -> [GitHubRepo] {
        let pageSize = min(max(perPage, 1), 100)
        let (data, _) = try await request(path: ["user", "repos"], query: [
            URLQueryItem(name: "sort", value: "updated"), URLQueryItem(name: "per_page", value: String(pageSize))
        ])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([GitHubRepo].self, from: data)
    }

    public func fetchPullRequests(owner: String, repo: String) async throws -> [GitHubPullRequest] {
        let (data, _) = try await request(path: ["repos", owner, repo, "pulls"], query: [
            URLQueryItem(name: "state", value: "all"), URLQueryItem(name: "per_page", value: "15")
        ])
        struct RawPR: Decodable {
            let id: Int
            let number: Int
            let title: String
            let state: String
            let user: RawUser
            let head: BranchInfo
            let base: BranchInfo
            let created_at: String
            let html_url: String?
            struct RawUser: Decodable { let login: String }
            struct BranchInfo: Decodable { let ref: String }
        }
        let raw = try JSONDecoder().decode([RawPR].self, from: data)
        let formatter = ISO8601DateFormatter()
        return raw.map {
            GitHubPullRequest(id: $0.id, number: $0.number, title: $0.title, state: $0.state,
                              user: $0.user.login, headBranch: $0.head.ref, baseBranch: $0.base.ref,
                              createdAt: formatter.date(from: $0.created_at) ?? Date(), additions: 0,
                              deletions: 0, htmlURL: $0.html_url)
        }
    }

    /// Fetches the complete recursive tree for a branch. GitHub-truncated results
    /// are rejected instead of silently presenting an incomplete workspace.
    public func fetchRepositoryTree(owner: String, repo: String, branch: String) async throws -> GitHubRepositoryTree {
        let (data, _) = try await request(path: ["repos", owner, repo, "git", "trees", branch],
                                          query: [URLQueryItem(name: "recursive", value: "1")])
        struct RawTree: Decodable {
            let sha: String
            let truncated: Bool
            let tree: [RawEntry]
            struct RawEntry: Decodable { let path: String; let type: String; let sha: String; let size: Int? }
        }
        let raw = try JSONDecoder().decode(RawTree.self, from: data)
        guard !raw.truncated else { throw GitHubClientError.repositoryTreeTruncated }
        let files = raw.tree.filter { $0.type == "blob" }.map { GitHubTreeFile(path: $0.path, sha: $0.sha, size: $0.size) }
        return GitHubRepositoryTree(commitSHA: raw.sha, files: files)
    }

    /// Reads a UTF-8 file from a GitHub repository at a branch, tag, or commit ref.
    public func fetchFile(owner: String, repo: String, path: String, ref: String) async throws -> String {
        guard isSafeRepositoryPath(path) else { throw GitHubClientError.invalidPath }
        let (data, _) = try await request(path: ["repos", owner, repo, "contents"] + path.split(separator: "/").map(String.init),
                                          query: [URLQueryItem(name: "ref", value: ref)])
        struct RawContent: Decodable { let type: String; let encoding: String?; let content: String? }
        let raw = try JSONDecoder().decode(RawContent.self, from: data)
        guard raw.type == "file", raw.encoding == "base64", let encoded = raw.content,
              let decoded = Data(base64Encoded: encoded.filter { !$0.isWhitespace }),
              let text = String(data: decoded, encoding: .utf8) else {
            throw GitHubClientError.unsupportedContent(path)
        }
        guard decoded.count <= WorkspaceManager.maxReadBytes else { throw GitHubClientError.tooLarge }
        return text
    }

    /// Downloads a bounded text-only snapshot into an isolated local workspace.
    /// Content is fetched and validated before any workspace file is written.
    public func importRepository(owner: String, repo: String, branch: String, into workspace: WorkspaceManager) async throws -> GitHubRepositoryTree {
        let tree = try await fetchRepositoryTree(owner: owner, repo: repo, branch: branch)
        let candidates = tree.files.filter { ($0.size ?? 0) <= WorkspaceManager.maxReadBytes }
        guard candidates.count <= WorkspaceManager.maxListEntries else { throw GitHubClientError.tooLarge }
        var totalBytes = 0
        var imported: [(String, String)] = []
        for file in candidates {
            let content = try await fetchFile(owner: owner, repo: repo, path: file.path, ref: branch)
            totalBytes += content.utf8.count
            guard totalBytes <= WorkspaceManager.maxWorkspaceBytes else { throw GitHubClientError.tooLarge }
            imported.append((file.path, content))
        }
        for (path, content) in imported { try workspace.writeFile(relativePath: path, content: content) }
        try workspace.captureBaseline()
        return tree
    }

    /// Creates a branch, one Git commit containing all reviewed file contents, and
    /// a pull request. Callers must show the complete diff and obtain explicit user
    /// approval before passing `reviewApproved: true`.
    public func publishChanges(
        owner: String,
        repo: String,
        baseBranch: String,
        branchName: String,
        commitMessage: String,
        pullRequestTitle: String,
        pullRequestBody: String,
        changes: [GitHubFileChange],
        reviewApproved: Bool
    ) async throws -> GitHubPublishResult {
        guard reviewApproved else { throw GitHubClientError.reviewRequired }
        guard !changes.isEmpty else { throw GitHubClientError.noChanges }
        guard changes.count <= WorkspaceManager.maxListEntries,
              changes.allSatisfy({ isSafeRepositoryPath($0.path) && $0.content.utf8.count <= WorkspaceManager.maxReadBytes }),
              changes.reduce(0, { $0 + $1.content.utf8.count }) <= WorkspaceManager.maxWorkspaceBytes,
              isSafeBranchName(branchName), !commitMessage.isEmpty, !pullRequestTitle.isEmpty else {
            throw GitHubClientError.invalidPath
        }
        guard Set(changes.map(\.path)).count == changes.count else { throw GitHubClientError.invalidPath }

        struct RefResponse: Decodable { let object: Object; struct Object: Decodable { let sha: String } }
        struct CommitResponse: Decodable { let sha: String; let tree: Object; struct Object: Decodable { let sha: String } }
        struct SHAResponse: Decodable { let sha: String }
        struct PullRequestResponse: Decodable { let number: Int; let html_url: String; let title: String; let state: String }

        let (refData, _) = try await request(path: ["repos", owner, repo, "git", "ref", "heads", baseBranch])
        let base = try JSONDecoder().decode(RefResponse.self, from: refData).object.sha
        let (baseData, _) = try await request(path: ["repos", owner, repo, "git", "commits", base])
        let baseTree = try JSONDecoder().decode(CommitResponse.self, from: baseData).tree.sha

        var treeEntries: [[String: Any]] = []
        for change in changes {
            let blob = try await post(path: ["repos", owner, repo, "git", "blobs"], body: ["content": change.content, "encoding": "utf-8"])
            treeEntries.append(["path": change.path, "mode": "100644", "type": "blob", "sha": try JSONDecoder().decode(SHAResponse.self, from: blob).sha])
        }
        let treeData = try await post(path: ["repos", owner, repo, "git", "trees"], body: ["base_tree": baseTree, "tree": treeEntries])
        let treeSHA = try JSONDecoder().decode(SHAResponse.self, from: treeData).sha
        let commitData = try await post(path: ["repos", owner, repo, "git", "commits"], body: ["message": commitMessage, "tree": treeSHA, "parents": [base]])
        let commitSHA = try JSONDecoder().decode(SHAResponse.self, from: commitData).sha
        let refBody: [String: Any] = ["ref": "refs/heads/\(branchName)", "sha": commitSHA]
        _ = try await post(path: ["repos", owner, repo, "git", "refs"], body: refBody)
        let prData = try await post(path: ["repos", owner, repo, "pulls"], body: ["title": pullRequestTitle, "head": branchName, "base": baseBranch, "body": pullRequestBody])
        let pr = try JSONDecoder().decode(PullRequestResponse.self, from: prData)
        let pullRequest = GitHubPullRequest(id: pr.number, number: pr.number, title: pr.title, state: pr.state,
                                            user: "", headBranch: branchName, baseBranch: baseBranch,
                                            createdAt: Date(), additions: 0, deletions: 0, htmlURL: pr.html_url)
        return GitHubPublishResult(branchName: branchName, commitSHA: commitSHA, pullRequest: pullRequest)
    }

    private func request(path: [String], query: [URLQueryItem] = []) async throws -> (Data, HTTPURLResponse) {
        try await send(path: path, method: "GET", query: query, body: nil)
    }

    private func post(path: [String], body: [String: Any]) async throws -> Data {
        let data = try JSONSerialization.data(withJSONObject: body)
        return try await send(path: path, method: "POST", query: [], body: data).0
    }

    private func send(path: [String], method: String, query: [URLQueryItem], body: Data?) async throws -> (Data, HTTPURLResponse) {
        guard let url = makeURL(path: path, query: query) else { throw GitHubClientError.invalidPath }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("FuzzCode-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubClientError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw GitHubClientError.httpStatus(http.statusCode) }
        return (data, http)
    }

    private func makeURL(path: [String], query: [URLQueryItem]) -> URL? {
        guard !path.isEmpty, path.allSatisfy({ !$0.isEmpty && !$0.contains("/") && !$0.contains("\\") && !$0.contains("..") }) else { return nil }
        var components = URLComponents(url: apiRoot, resolvingAgainstBaseURL: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let encoded = path.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? "" }
        components?.percentEncodedPath = "/" + encoded.joined(separator: "/")
        components?.queryItems = query.isEmpty ? nil : query
        return components?.url
    }

    private func isSafeRepositoryPath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") &&
        path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private func isSafeBranchName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("/") && !name.hasSuffix("/") && !name.contains("..") &&
        !name.contains(" ") && !name.contains("~") && !name.contains("^") && !name.contains(":") &&
        !name.contains("?") && !name.contains("*") && !name.contains("[") && !name.contains("\\")
    }
}
