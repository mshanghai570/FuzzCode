import Foundation

/// High-performance networking client for arbitrary OpenAI-compatible Chat Completions endpoints.
/// Supports normalized URL resolution, Bearer authentication, custom headers, and asynchronous SSE streaming.
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
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = config.timeoutSeconds
        configuration.timeoutIntervalForResource = config.timeoutSeconds * 2
        self.session = URLSession(configuration: configuration)
    }
    
    // MARK: - Normalization Helpers
    
    /// Normalizes endpoint path without accidentally duplicating /v1 or subpaths.
    public static func constructChatCompletionsURL(baseURL: URL, customApiPath: String?) -> URL {
        if let customApiPath = customApiPath, !customApiPath.isEmpty {
            let path = customApiPath.hasPrefix("/") ? String(customApiPath.dropFirst()) : customApiPath
            return baseURL.appendingPathComponent(path)
        }
        
        let existingPath = baseURL.path
        if existingPath.hasSuffix("/v1") {
            return baseURL.appendingPathComponent("chat/completions")
        } else if existingPath.hasSuffix("/chat/completions") {
            return baseURL
        } else {
            return baseURL.appendingPathComponent("v1/chat/completions")
        }
    }
    
    public static func constructModelsURL(baseURL: URL) -> URL {
        let existingPath = baseURL.path
        if existingPath.hasSuffix("/v1") {
            return baseURL.appendingPathComponent("models")
        } else if existingPath.hasSuffix("/models") {
            return baseURL
        } else {
            return baseURL.appendingPathComponent("v1/models")
        }
    }
    
    // MARK: - Connection & Discovery
    
    public func testConnection() async throws -> TimeInterval {
        let startTime = Date()
        let modelsURL = Self.constructModelsURL(baseURL: baseURL)
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenAIClientError.invalidResponseFormat("Non-HTTP response received")
            }
            
            if (200...299).contains(httpResponse.statusCode) {
                return Date().timeIntervalSince(startTime) * 1000.0
            } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw OpenAIClientError.authenticationFailed("Invalid API Key or unauthorized access (HTTP \(httpResponse.statusCode))")
            } else if httpResponse.statusCode == 404 {
                // If /models does not exist, try a minimal completion test
                return try await testFallbackCompletion(startTime: startTime)
            } else {
                let bodyString = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw OpenAIClientError.serverError(statusCode: httpResponse.statusCode, message: bodyString)
            }
        } catch let error as OpenAIClientError {
            throw error
        } catch {
            throw OpenAIClientError.networkError(error.localizedDescription)
        }
    }
    
    private func testFallbackCompletion(startTime: Date) async throws -> TimeInterval {
        let completionsURL = Self.constructChatCompletionsURL(baseURL: baseURL, customApiPath: config.customApiPath)
        var request = URLRequest(url: completionsURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyHeaders(to: &request)
        
        let payload: [String: Any] = [
            "model": selectedModel,
            "messages": [["role": "user", "content": "ping"]],
            "max_tokens": 1
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponseFormat("Non-HTTP response received")
        }
        
        if (200...299).contains(httpResponse.statusCode) {
            return Date().timeIntervalSince(startTime) * 1000.0
        } else if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw OpenAIClientError.authenticationFailed("Invalid API Key (HTTP \(httpResponse.statusCode))")
        } else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIClientError.serverError(statusCode: httpResponse.statusCode, message: body)
        }
    }
    
    public func discoverModels() async throws -> [ModelInfo] {
        let modelsURL = Self.constructModelsURL(baseURL: baseURL)
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        applyHeaders(to: &request)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAIClientError.invalidResponseFormat("Invalid response object")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 404 {
                throw OpenAIClientError.modelDiscoveryUnavailable("The endpoint does not expose a standard /v1/models route.")
            }
            throw OpenAIClientError.serverError(statusCode: httpResponse.statusCode, message: String(data: data, encoding: .utf8) ?? "")
        }
        
        struct ModelsResponse: Decodable {
            struct ModelEntry: Decodable {
                let id: String
                let owned_by: String?
            }
            let data: [ModelEntry]
        }
        
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.map { ModelInfo(id: $0.id, ownedBy: $0.owned_by) }
    }
    
    // MARK: - Streaming Chat Completions
    
    public func streamChatCompletion(
        messages: [ChatMessage],
        temperature: Double? = 0.7,
        systemPrompt: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let completionsURL = Self.constructChatCompletionsURL(baseURL: self.baseURL, customApiPath: self.config.customApiPath)
                    var request = URLRequest(url: completionsURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    self.applyHeaders(to: &request)
                    
                    var messagePayload: [[String: String]] = []
                    if let systemPrompt = systemPrompt, !systemPrompt.isEmpty {
                        messagePayload.append(["role": "system", "content": systemPrompt])
                    }
                    for msg in messages {
                        messagePayload.append(["role": msg.role.rawValue, "content": msg.content])
                    }
                    
                    var requestBody: [String: Any] = [
                        "model": self.selectedModel,
                        "messages": messagePayload,
                        "stream": true
                    ]
                    if let temp = temperature {
                        requestBody["temperature"] = temp
                    }
                    
                    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
                    
                    let (asyncBytes, response) = try await self.session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: OpenAIClientError.invalidResponseFormat("Stream failed"))
                        return
                    }
                    
                    if !(200...299).contains(httpResponse.statusCode) {
                        var body = ""
                        for try await line in asyncBytes.lines {
                            body += line
                        }
                        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                            continuation.finish(throwing: OpenAIClientError.authenticationFailed("Invalid API key"))
                        } else if httpResponse.statusCode == 429 {
                            continuation.finish(throwing: OpenAIClientError.rateLimited("Rate limit exceeded"))
                        } else {
                            continuation.finish(throwing: OpenAIClientError.serverError(statusCode: httpResponse.statusCode, message: body))
                        }
                        return
                    }
                    
                    for try await line in asyncBytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data:") else { continue }
                        
                        let dataContent = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if dataContent == "[DONE]" {
                            continuation.finish()
                            return
                        }
                        
                        guard let chunkData = dataContent.data(using: .utf8) else { continue }
                        if let deltaText = Self.extractDeltaContent(from: chunkData) {
                            continuation.yield(deltaText)
                        }
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Delta Parsing
    
    public static func extractDeltaContent(from jsonData: Data) -> String? {
        struct StreamChunk: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable {
                    let content: String?
                }
                let delta: Delta?
            }
            let choices: [Choice]?
        }
        
        guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: jsonData),
              let firstChoice = chunk.choices?.first,
              let content = firstChoice.delta?.content else {
            return nil
        }
        return content
    }
    
    private func applyHeaders(to request: inout URLRequest) {
        if let apiKey = keychain.get(key: "api_key_\(config.id.uuidString)") {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        if config.authMethod == .chatgptSubscription {
            let tier = config.chatgptSession?.subscriptionTier ?? "plus"
            request.setValue(tier, forHTTPHeaderField: "X-OpenAI-Subscription")
            request.setValue("codex=v1", forHTTPHeaderField: "OpenAI-Beta")
        }
        if let orgId = config.organizationId, !orgId.isEmpty {
            request.setValue(orgId, forHTTPHeaderField: "OpenAI-Organization")
        }
        if let projId = config.projectId, !projId.isEmpty {
            request.setValue(projId, forHTTPHeaderField: "OpenAI-Project")
        }
        for header in config.customHeaders {
            request.setValue(header.value, forHTTPHeaderField: header.key)
        }
    }
}

public enum OpenAIClientError: Error, LocalizedError, Equatable {
    case invalidBaseURL(String)
    case authenticationFailed(String)
    case rateLimited(String)
    case modelDiscoveryUnavailable(String)
    case serverError(statusCode: Int, message: String)
    case invalidResponseFormat(String)
    case networkError(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let url):
            return "Invalid Base URL: \(url). Please check format and scheme."
        case .authenticationFailed(let msg):
            return "Authentication Failed: \(msg)"
        case .rateLimited(let msg):
            return "Rate Limited: \(msg)"
        case .modelDiscoveryUnavailable(let msg):
            return "Model Discovery Unavailable: \(msg)"
        case .serverError(let code, let msg):
            return "Server Error (HTTP \(code)): \(msg)"
        case .invalidResponseFormat(let msg):
            return "Invalid Response: \(msg)"
        case .networkError(let msg):
            return "Network Error: \(msg)"
        }
    }
}
