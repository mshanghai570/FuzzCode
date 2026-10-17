import Foundation

/// GitHub user account metadata.
public struct GitHubUser: Codable, Equatable, Sendable {
    public let login: String
    public let name: String
    public let avatarUrl: String
    public let htmlUrl: String
    public let publicRepos: Int
    public let totalPrivateRepos: Int
    
    public init(login: String, name: String, avatarUrl: String, htmlUrl: String, publicRepos: Int, totalPrivateRepos: Int) {
        self.login = login
        self.name = name
        self.avatarUrl = avatarUrl
        self.htmlUrl = htmlUrl
        self.publicRepos = publicRepos
        self.totalPrivateRepos = totalPrivateRepos
    }
}

/// GitHub repository metadata.
public struct GitHubRepo: Identifiable, Codable, Equatable, Sendable {
    public let id: Int
    public let name: String
    public let fullName: String
    public let isPrivate: Bool
    public let defaultBranch: String
    public let repoDescription: String?
    public let htmlUrl: String
    public let stargazersCount: Int
    public let updatedAt: Date
    public let openIssuesCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case isPrivate = "private"
        case defaultBranch = "default_branch"
        case repoDescription = "description"
        case htmlUrl = "html_url"
        case stargazersCount = "stargazers_count"
        case updatedAt = "updated_at"
        case openIssuesCount = "open_issues_count"
    }
    
    public init(id: Int, name: String, fullName: String, isPrivate: Bool, defaultBranch: String, repoDescription: String?, htmlUrl: String, stargazersCount: Int, updatedAt: Date, openIssuesCount: Int) {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.isPrivate = isPrivate
        self.defaultBranch = defaultBranch
        self.repoDescription = repoDescription
        self.htmlUrl = htmlUrl
        self.stargazersCount = stargazersCount
        self.updatedAt = updatedAt
        self.openIssuesCount = openIssuesCount
    }
}

/// GitHub Pull Request metadata.
public struct GitHubPullRequest: Identifiable, Codable, Equatable, Sendable {
    public let id: Int
    public let number: Int
    public let title: String
    public let state: String
    public let user: String
    public let headBranch: String
    public let baseBranch: String
    public let createdAt: Date
    public let additions: Int
    public let deletions: Int
    public let htmlURL: String?
    
    public init(id: Int, number: Int, title: String, state: String, user: String, headBranch: String, baseBranch: String, createdAt: Date, additions: Int, deletions: Int, htmlURL: String? = nil) {
        self.id = id
        self.number = number
        self.title = title
        self.state = state
        self.user = user
        self.headBranch = headBranch
        self.baseBranch = baseBranch
        self.createdAt = createdAt
        self.additions = additions
        self.deletions = deletions
        self.htmlURL = htmlURL
    }
}

/// Configuration for GitHub connection in FuzzCode.
public struct GitHubConfig: Codable, Equatable, Sendable {
    public var isConnected: Bool
    public var keychainTokenKey: String
    public var user: GitHubUser?
    public var selectedRepo: GitHubRepo?
    public var scopes: [String]
    public var connectedAt: Date?
    
    public init(isConnected: Bool = false, keychainTokenKey: String = "fuzzcode_github_token", user: GitHubUser? = nil, selectedRepo: GitHubRepo? = nil, scopes: [String] = [], connectedAt: Date? = nil) {
        self.isConnected = isConnected
        self.keychainTokenKey = keychainTokenKey
        self.user = user
        self.selectedRepo = selectedRepo
        self.scopes = scopes
        self.connectedAt = connectedAt
    }
}

public struct GitHubTreeFile: Codable, Equatable, Sendable {
    public let path: String
    public let sha: String
    public let size: Int?

    public init(path: String, sha: String, size: Int? = nil) {
        self.path = path
        self.sha = sha
        self.size = size
    }
}

public struct GitHubRepositoryTree: Codable, Equatable, Sendable {
    public let commitSHA: String
    public let files: [GitHubTreeFile]

    public init(commitSHA: String, files: [GitHubTreeFile]) {
        self.commitSHA = commitSHA
        self.files = files
    }
}

public struct GitHubFileChange: Equatable, Sendable {
    public let path: String
    public let content: String

    public init(path: String, content: String) {
        self.path = path
        self.content = content
    }
}

public struct GitHubPublishResult: Equatable, Sendable {
    public let branchName: String
    public let commitSHA: String
    public let pullRequest: GitHubPullRequest

    public init(branchName: String, commitSHA: String, pullRequest: GitHubPullRequest) {
        self.branchName = branchName
        self.commitSHA = commitSHA
        self.pullRequest = pullRequest
    }
}

public enum GitHubClientError: Error, Equatable {
    case invalidPath
    case repositoryTreeTruncated
    case unsupportedContent(String)
    case invalidResponse
    case httpStatus(Int)
    case noChanges
    case reviewRequired
    case tooLarge
}

public struct GitHubSearchMatch: Equatable, Sendable {
    public let path: String
    public let lineNumber: Int
    public let text: String
}
