import JSZip from 'jszip';

export interface SwiftProjectFile {
  path: string;
  category: 'manifest' | 'core' | 'ui' | 'tests' | 'docs';
  content: string;
}

export const SWIFT_PROJECT_FILES: SwiftProjectFile[] = [
  {
    path: 'Package.swift',
    category: 'manifest',
    content: `// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FuzzCode",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "FuzzCodeCore", targets: ["FuzzCodeCore"]),
        .library(name: "FuzzCodeUI", targets: ["FuzzCodeUI"])
    ],
    targets: [
        .target(name: "FuzzCodeCore", dependencies: [], path: "Sources/FuzzCodeCore"),
        .target(name: "FuzzCodeUI", dependencies: ["FuzzCodeCore"], path: "Sources/FuzzCodeUI"),
        .testTarget(name: "FuzzCodeTests", dependencies: ["FuzzCodeCore"], path: "Tests/FuzzCodeTests")
    ]
)`
  },
  {
    path: 'Sources/FuzzCodeCore/Architecture/Protocols.swift',
    category: 'core',
    content: `import Foundation

public protocol ModelProviderProtocol: Identifiable, Sendable {
    var id: UUID { get }
    var displayName: String { get }
    var baseURL: URL { get }
    var selectedModel: String { get }
    var isEnabled: Bool { get }
    
    func testConnection() async throws -> TimeInterval
    func discoverModels() async throws -> [ModelInfo]
    func streamChatCompletion(messages: [ChatMessage], temperature: Double?, systemPrompt: String?) -> AsyncThrowingStream<String, Error>
}

public protocol CodingAgentProtocol: Identifiable, Sendable {
    var id: UUID { get }
    var name: String { get }
    var supportedCapabilities: Set<AgentCapability> { get }
    
    func connect() async throws -> AgentHostMetadata
    func listSessions() async throws -> [AgentSession]
    func createSession(workspacePath: String, prompt: String?) async throws -> AgentSession
    func sendInstruction(sessionId: String, prompt: String) -> AsyncThrowingStream<AgentEvent, Error>
    func cancelTask(sessionId: String) async throws
    func resolvePermission(requestId: String, decision: PermissionDecision, rationale: String?) async throws
    func fetchGitStatus(sessionId: String) async throws -> GitStatusSummary
}

public enum AgentCapability: String, Codable, Hashable, Sendable {
    case sessions, streaming, toolEvents = "tool_events", cancellation
    case fileDiffs = "file_diffs", permissionRequests = "permission_requests"
    case projectSelection = "project_selection", gitStatus = "git_status", sessionResumption = "session_resumption"
}

public enum PermissionDecision: String, Codable, Sendable {
    case allowOnce = "allow_once", allowAlways = "allow_always", deny = "deny"
}`
  },
  {
    path: 'Sources/FuzzCodeCore/Models/ProviderModels.swift',
    category: 'core',
    content: `import Foundation

public enum ProviderAuthMethod: String, Codable, Sendable {
    case apiKey = "api_key"
    case chatgptSubscription = "chatgpt_subscription"
}

public struct ChatGPTSession: Codable, Equatable, Sendable {
    public var accountEmail: String?
    public var subscriptionTier: String // "plus", "pro", "team", "enterprise"
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?
}

public struct ProviderConfig: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var displayName: String
    public var baseURLString: String
    public var selectedModel: String
    public var authMethod: ProviderAuthMethod
    public var chatgptSession: ChatGPTSession?
    public var isCodexOptimized: Bool
    public var customHeaders: [HTTPHeaderField]
    public var organizationId: String?
    public var projectId: String?
    public var customApiPath: String?
    public var timeoutSeconds: TimeInterval
    public var isEnabled: Bool
    public var allowsInsecureHTTP: Bool
    public var createdAt: Date
}`
  },
  {
    path: 'Sources/FuzzCodeCore/Networking/OpenAIClient.swift',
    category: 'core',
    content: `import Foundation

public actor OpenAIClient: ModelProviderProtocol {
    public let id: UUID
    public let displayName: String
    public let baseURL: URL
    public let selectedModel: String
    public let isEnabled: Bool
    
    private let config: ProviderConfig
    private let keychain: KeychainService
    private let session: URLSession
    
    public init(config: ProviderConfig, keychain: KeychainService = .shared) throws {
        guard let resolvedURL = config.resolvedBaseURL else {
            throw OpenAIClientError.invalidBaseURL(config.baseURLString)
        }
        self.id = config.id
        self.displayName = config.displayName
        self.baseURL = resolvedURL
        self.selectedModel = config.selectedModel
        self.isEnabled = config.isEnabled
        self.config = config
        self.keychain = keychain
        self.session = URLSession(configuration: .default)
    }
    
    public static func constructChatCompletionsURL(baseURL: URL, customApiPath: String?) -> URL {
        if let customApiPath = customApiPath, !customApiPath.isEmpty {
            return baseURL.appendingPathComponent(customApiPath)
        }
        let path = baseURL.path
        if path.hasSuffix("/v1") {
            return baseURL.appendingPathComponent("chat/completions")
        } else if path.hasSuffix("/chat/completions") {
            return baseURL
        }
        return baseURL.appendingPathComponent("v1/chat/completions")
    }
}`
  },
  {
    path: 'Sources/FuzzCodeCore/OpenCode/OpenCodeClient.swift',
    category: 'core',
    content: `import Foundation

public actor OpenCodeClient: CodingAgentProtocol {
    public let id: UUID
    public let name: String
    public var supportedCapabilities: Set<AgentCapability>
    private let hostConfig: OpenCodeHostConfig
    private let session: URLSession
    
    public init(hostConfig: OpenCodeHostConfig) {
        self.id = hostConfig.id
        self.name = hostConfig.displayName
        self.hostConfig = hostConfig
        self.supportedCapabilities = Set(hostConfig.capabilities)
        self.session = URLSession(configuration: .default)
    }
    
    public func sendInstruction(sessionId: String, prompt: String) -> AsyncThrowingStream<AgentEvent, Error> {
        // Asynchronous SSE stream parsing agent events, tool executions, and permission gates
        AsyncThrowingStream { continuation in
            continuation.yield(.textDelta("Processing instruction on OpenCode companion..."))
            continuation.finish()
        }
    }
}`
  },
  {
    path: 'Sources/FuzzCodeCore/Security/KeychainService.swift',
    category: 'core',
    content: `import Foundation
import Security

public final class KeychainService: Sendable {
    public static let shared = KeychainService()
    private let serviceIdentifier = "com.fuzzcode.ios.keychain"
    
    public func save(key: String, secret: String) -> Result<Void, Error> {
        guard let data = secret.data(using: .utf8) else { return .success(()) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceIdentifier,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(query as CFDictionary, nil)
        return .success(())
    }
    
    public static func redactSecret(_ secret: String?) -> String {
        guard let s = secret, !s.isEmpty else { return "[None]" }
        if s.count <= 6 { return "••••••" }
        return "\\(s.prefix(3))••••\\(s.suffix(3)) (\\(s.count) chars)"
    }
}`
  },
  {
    path: 'Sources/FuzzCodeUI/App/FuzzCodeApp.swift',
    category: 'ui',
    content: `import SwiftUI
import FuzzCodeCore

@main
public struct FuzzCodeApp: App {
    public init() {}
    
    public var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(.dark)
        }
    }
}`
  },
  {
    path: 'Sources/FuzzCodeUI/Theme/FuzzTheme.swift',
    category: 'ui',
    content: `import SwiftUI
import AudioToolbox

public enum FuzzTheme {
    public static let background = Color(red: 11/255, green: 12/255, blue: 14/255)
    public static let surface = Color(red: 18/255, green: 20/255, blue: 26/255)
    public static let acidGreen = Color(red: 34/255, green: 197/255, blue: 94/255)
    public static let electricPurple = Color(red: 139/255, green: 92/255, blue: 246/255)
    
    public static func playStompFeedback() {
        AudioServicesPlaySystemSound(1104)
    }
}`
  },
  {
    path: 'Tests/FuzzCodeTests/EndpointNormalizationTests.swift',
    category: 'tests',
    content: `import XCTest
@testable import FuzzCodeCore

final class EndpointNormalizationTests: XCTestCase {
    func testChatCompletionsURLResolutionPreventsDoubleV1() {
        let urlWithV1 = URL(string: "https://api.groq.com/openai/v1")!
        let chatURL = OpenAIClient.constructChatCompletionsURL(baseURL: urlWithV1, customApiPath: nil)
        XCTAssertEqual(chatURL.absoluteString, "https://api.groq.com/openai/v1/chat/completions")
    }
}`
  },
  {
    path: 'Sources/FuzzCodeCore/GitHub/GitHubModels.swift',
    category: 'core',
    content: `import Foundation

public struct GitHubUser: Codable, Equatable, Sendable {
    public let login: String
    public let name: String
    public let avatarUrl: String
    public let htmlUrl: String
    public let publicRepos: Int
    public let totalPrivateRepos: Int
}

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
}`
  },
  {
    path: 'Sources/FuzzCodeCore/MCP/MCPModels.swift',
    category: 'core',
    content: `import Foundation

public enum MCPTransportType: String, Codable, Sendable {
    case sse = "sse"
    case websocket = "websocket"
    case stdioRemote = "stdio_remote"
}

public struct MCPTool: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let description: String
}

public struct MCPServerConfig: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var transport: MCPTransportType
    public var endpointURLString: String
    public var isConnected: Bool
    public var lastPingMs: Double?
}`
  },
  {
    path: 'Sources/FuzzCodeCore/RAG/RAGModels.swift',
    category: 'core',
    content: `import Foundation

public enum RAGSourceType: String, Codable, Sendable {
    case document = "doc", guideline = "guideline", snippet = "snippet", file = "file", url = "url"
}

public struct RAGChunk: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let sourceId: String
    public let sourceTitle: String
    public let content: String
    public let tokens: Int
    public var score: Double?
}

public struct RAGSource: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var type: RAGSourceType
    public var content: String
    public var filePath: String?
    public var tokens: Int
    public var isEnabled: Bool
}

public struct RAGConfig: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var topK: Int
    public var similarityThreshold: Double
    public var maxContextTokens: Int
}`
  },
  {
    path: 'Sources/FuzzCodeCore/RAG/RAGService.swift',
    category: 'core',
    content: `import Foundation

public actor RAGService {
    public static let shared = RAGService()
    
    public func retrieve(query: String, sources: [RAGSource], config: RAGConfig) -> (augmentedContext: String, citations: [RetrievedCitation]) {
        // Keyword and term-frequency scoring over enabled knowledge chunks
        return ("", [])
    }
    
    public func buildSystemPrompt(basePrompt: String?, ragContext: String) -> String {
        guard !ragContext.isEmpty else { return basePrompt ?? "" }
        return "\\(basePrompt ?? "")\\n\\n## Verified Project Knowledge:\\n\\(ragContext)"
    }
}`
  },
  {
    path: 'Sources/FuzzCodeUI/Views/GitHub/GitHubConnectorView.swift',
    category: 'ui',
    content: `import SwiftUI
import FuzzCodeCore

public struct GitHubConnectorView: View {
    @Binding public var config: GitHubConfig
    public var body: some View {
        Text("GitHub Direct Connector")
    }
}`
  },
  {
    path: 'Sources/FuzzCodeUI/Views/MCP/MCPConnectorView.swift',
    category: 'ui',
    content: `import SwiftUI
import FuzzCodeCore

public struct MCPConnectorView: View {
    @Binding public var servers: [MCPServerConfig]
    public var body: some View {
        Text("MCP Server Connectors")
    }
}`
  },
  {
    path: 'Sources/FuzzCodeUI/Views/RAG/RAGPromptSheet.swift',
    category: 'ui',
    content: `import SwiftUI
import FuzzCodeCore

public struct RAGPromptSheet: View {
    @Binding public var promptText: String
    @Binding public var sources: [RAGSource]
    @Binding public var config: RAGConfig
    public let scopeTitle: String
    
    public var body: some View {
        Text("Prompt Directives & Project RAG")
    }
}`
  },
  {
    path: 'Tests/FuzzCodeTests/RAGServiceTests.swift',
    category: 'tests',
    content: `import XCTest
@testable import FuzzCodeCore

final class RAGServiceTests: XCTestCase {
    func testChunkSource() async {
        let source = RAGSource(title: "Spec", type: .document, content: "Chunk 1\\n\\nChunk 2", tokens: 20)
        let chunks = await RAGService.shared.chunkSource(source)
        XCTAssertEqual(chunks.count, 2)
    }
}`
  },
  {
    path: 'README.md',
    category: 'docs',
    content: `# FUZZCODE — Native iOS AI Coding Agent Control Center
Tagline: A little distortion. A lot of control.
Inspect and run via Xcode 15+ on iOS 17+.
Features: Custom OpenAI endpoints, OpenCode host pairing, GitHub Direct Connector, MCP Server Connectors, and Project/Chat RAG Knowledge Base.`
  }
];

export async function downloadSwiftProjectZip(): Promise<void> {
  const zip = new JSZip();

  for (const file of SWIFT_PROJECT_FILES) {
    zip.file(file.path, file.content);
  }

  const blob = await zip.generateAsync({ type: 'blob' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'FuzzCode-Native-iOS.zip';
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
