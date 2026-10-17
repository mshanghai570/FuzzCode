import Foundation

// MARK: - Abstractions

/// Modular abstraction for a direct AI inference provider (OpenAI, Anthropic, Gemini, ...).
/// Implementations must never include secrets in errors, logs, or thrown messages.
public protocol AIProvider: Identifiable, Sendable {
    var id: UUID { get }
    var displayName: String { get }
    var modelId: String { get }
    var kind: ProviderKind { get }

    func testConnection() async throws -> TimeInterval
    func discoverModels() async throws -> [ModelInfo]
    func streamChat(messages: [ChatMessage], systemPrompt: String?) async -> AsyncThrowingStream<String, Error>
    func completeWithTools(
        messages: [ChatMessage],
        systemPrompt: String?,
        tools: [ProviderToolDefinition],
        toolResults: [ProviderToolExchange]
    ) async throws -> ProviderTurnResult
}

public extension AIProvider {
    func completeWithTools(
        messages: [ChatMessage],
        systemPrompt: String?,
        tools: [ProviderToolDefinition],
        toolResults: [ProviderToolExchange]
    ) async throws -> ProviderTurnResult {
        throw AIProviderError.toolsUnsupported(kind.displayName)
    }
}

/// Secret storage abstraction. The Keychain-backed implementation never logs values.
public protocol CredentialStore: Sendable {
    func retrieve(key: String) -> String?
    func store(key: String, secret: String)
    func remove(key: String)
}

public struct KeychainCredentialStore: CredentialStore {
    private let keychain: KeychainService
    public init(keychain: KeychainService = .shared) {
        self.keychain = keychain
    }
    public func retrieve(key: String) -> String? { keychain.get(key: key) }
    public func store(key: String, secret: String) { keychain.save(key: key, secret: secret) }
    public func remove(key: String) { keychain.delete(key: key) }
}

public enum AIProviderError: Error, LocalizedError, Equatable {
    case missingCredential
    case invalidBaseURL(String)
    case authenticationFailed
    case rateLimited
    case serverError(statusCode: Int)
    case invalidResponse
    case networkError(String)
    case toolsUnsupported(String)

    public var errorDescription: String? {
        switch self {
        case .missingCredential:
            return "No API key is stored for this provider. Add one in Providers."
        case .invalidBaseURL:
            return "Invalid base URL. Check the format and scheme."
        case .authenticationFailed:
            return "Authentication failed. Check the stored API key."
        case .rateLimited:
            return "Rate limit exceeded. Try again shortly."
        case .serverError(let code):
            return "Server error (HTTP \(code))."
        case .invalidResponse:
            return "The provider returned an unexpected response."
        case .networkError(let message):
            return "Network error: \(message)"
        case .toolsUnsupported(let name):
            return "\(name) does not support the native tool loop yet."
        }
    }
}

/// Builds an AIProvider for a stored config. Never logs credentials.
public func makeAIProvider(
    config: ProviderConfig,
    credentialStore: CredentialStore = KeychainCredentialStore()
) throws -> any AIProvider {
    switch config.resolvedKind {
    case .anthropic:
        return try AnthropicProvider(config: config, credentialStore: credentialStore)
    case .gemini:
        return try GeminiProvider(config: config, credentialStore: credentialStore)
    case .openai, .openRouter, .groq, .custom:
        return try OpenAICompatibleProvider(config: config, credentialStore: credentialStore)
    }
}

func apiKey(for config: ProviderConfig, credentialStore: CredentialStore) throws -> String {
    guard let key = credentialStore.retrieve(key: "api_key_\(config.id.uuidString)"), !key.isEmpty else {
        throw AIProviderError.missingCredential
    }
    return key
}

// MARK: - OpenAI-compatible adapter

/// Adapter for OpenAI / OpenRouter / Groq / custom endpoints. Wraps OpenAIClient.
public struct OpenAICompatibleProvider: AIProvider {
    public let id: UUID
    public let displayName: String
    public let modelId: String
    public let kind: ProviderKind
    private let client: OpenAIClient

    public init(config: ProviderConfig, credentialStore: CredentialStore = KeychainCredentialStore(),
                session: URLSession? = nil,
                requestPerformer: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil) throws {
        // The injected credential store is the source of truth so tests and Keychain behave identically.
        self.client = try OpenAIClient(config: config, session: session,
            credentialLookup: { credentialStore.retrieve(key: $0) }, requestPerformer: requestPerformer)
        self.id = config.id
        self.displayName = config.displayName
        self.modelId = config.selectedModel
        self.kind = config.resolvedKind
    }

    public func testConnection() async throws -> TimeInterval {
        try await client.testConnection()
    }

    public func discoverModels() async throws -> [ModelInfo] {
        try await client.discoverModels()
    }

    public func streamChat(messages: [ChatMessage], systemPrompt: String?) async -> AsyncThrowingStream<String, Error> {
        await client.streamChatCompletion(messages: messages, temperature: 0.7, systemPrompt: systemPrompt)
    }

    public func completeWithTools(
        messages: [ChatMessage],
        systemPrompt: String?,
        tools: [ProviderToolDefinition],
        toolResults: [ProviderToolExchange]
    ) async throws -> ProviderTurnResult {
        try await client.completeWithTools(messages: messages, systemPrompt: systemPrompt, tools: tools, toolResults: toolResults)
    }
}

// MARK: - Native provider helpers

private func nativeURL(base: URL, version: String, route: String) -> URL {
    var root = base
    if root.lastPathComponent == "messages" || root.lastPathComponent == "models" { root.deleteLastPathComponent() }
    if root.lastPathComponent != version { root.appendPathComponent(version) }
    return root.appendingPathComponent(route)
}

private func nativeSystem(messages: [ChatMessage], prompt: String?) -> String? {
    let parts = ([prompt].compactMap { $0 } + messages.filter { $0.role == .system }.map(\.content)).filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
}

private func checkNativeResponse(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse else { throw AIProviderError.invalidResponse }
    switch http.statusCode {
    case 200...299: return
    case 401, 403: throw AIProviderError.authenticationFailed
    case 429: throw AIProviderError.rateLimited
    default: throw AIProviderError.serverError(statusCode: http.statusCode)
    }
}

private func safeNativeError(_ error: Error) -> Error {
    if error is CancellationError || (error as? URLError)?.code == .cancelled { return CancellationError() }
    if let error = error as? AIProviderError { return error }
    return AIProviderError.networkError("Unable to reach the provider.")
}

private func nativeObject(_ data: Data) throws -> [String: Any] {
    guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw AIProviderError.invalidResponse }
    return object
}

private func nativeSchema(_ tool: ProviderToolDefinition) throws -> [String: Any] {
    try nativeObject(JSONEncoder().encode(tool.inputSchema))
}

private func validateExchange(_ exchange: ProviderToolExchange) throws {
    let ids = exchange.calls.map(\.id)
    guard !ids.isEmpty, Set(ids).count == ids.count,
          exchange.results.count == ids.count,
          Set(exchange.results.map(\.toolCallID)) == Set(ids) else { throw AIProviderError.invalidResponse }
}

// MARK: - Anthropic adapter

public struct AnthropicProvider: AIProvider {
    public let id: UUID
    public let displayName: String
    public let modelId: String
    public let kind: ProviderKind = .anthropic
    private let config: ProviderConfig
    private let credentialStore: CredentialStore
    private let session: URLSession
    private let requestPerformer: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(config: ProviderConfig, credentialStore: CredentialStore = KeychainCredentialStore(), session: URLSession = .shared,
                requestPerformer: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil) throws {
        guard config.resolvedBaseURL != nil else { throw AIProviderError.invalidBaseURL("") }
        self.id = config.id; self.displayName = config.displayName; self.modelId = config.selectedModel
        self.config = config; self.credentialStore = credentialStore; self.session = session
        self.requestPerformer = requestPerformer ?? { try await session.data(for: $0) }
    }

    private func request(route: String, apiKey: String) -> URLRequest {
        var request = URLRequest(url: nativeURL(base: config.resolvedBaseURL!, version: "v1", route: route))
        request.timeoutInterval = config.timeoutSeconds
        for header in config.customHeaders { request.setValue(header.value, forHTTPHeaderField: header.key) }
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    func messagesRequest(messages: [ChatMessage], systemPrompt: String?, stream: Bool, apiKey: String) throws -> URLRequest {
        var request = request(route: "messages", apiKey: apiKey)
        request.httpMethod = "POST"
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        var body: [String: Any] = ["model": modelId, "max_tokens": 2048, "stream": stream,
            "messages": messages.filter { $0.role != .system }.map { ["role": $0.role == .assistant ? "assistant" : "user", "content": $0.content] }]
        if let system = nativeSystem(messages: messages, prompt: systemPrompt) { body["system"] = system }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do { let (data, response) = try await requestPerformer(request); try checkNativeResponse(response); return data }
        catch { throw safeNativeError(error) }
    }

    public func testConnection() async throws -> TimeInterval {
        let start = Date(); _ = try await discoverModels(); return Date().timeIntervalSince(start) * 1000
    }
    public func discoverModels() async throws -> [ModelInfo] {
        let key = try apiKey(for: config, credentialStore: credentialStore)
        var request = request(route: "models", apiKey: key); request.httpMethod = "GET"
        let object = try nativeObject(await perform(request))
        guard let entries = object["data"] as? [[String: Any]] else { throw AIProviderError.invalidResponse }
        return try entries.map { entry in
            guard let id = entry["id"] as? String, !id.isEmpty else { throw AIProviderError.invalidResponse }
            return ModelInfo(id: id)
        }
    }

    public func completeWithTools(messages: [ChatMessage], systemPrompt: String?, tools: [ProviderToolDefinition], toolResults: [ProviderToolExchange]) async throws -> ProviderTurnResult {
        let key = try apiKey(for: config, credentialStore: credentialStore)
        var request = try messagesRequest(messages: messages, systemPrompt: systemPrompt, stream: false, apiKey: key)
        var body = try nativeObject(request.httpBody!)
        var history = body["messages"] as? [[String: Any]] ?? []
        for exchange in toolResults {
            try validateExchange(exchange)
            let blocks: [[String: Any]]
            if let replay = exchange.calls.first?.replayContent,
               let content = (try? JSONSerialization.jsonObject(with: replay)) as? [[String: Any]] { blocks = content }
            else { blocks = try exchange.calls.map { ["type": "tool_use", "id": $0.id, "name": $0.name, "input": try nativeObject($0.arguments)] } }
            history.append(["role": "assistant", "content": blocks])
            history.append(["role": "user", "content": exchange.results.map { ["type": "tool_result", "tool_use_id": $0.toolCallID, "content": $0.content] }])
        }
        body["messages"] = history
        if !tools.isEmpty {
            body["tools"] = try tools.map { ["name": $0.name, "description": $0.description, "input_schema": try nativeSchema($0)] }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let response = try nativeObject(await perform(request))
        guard let blocks = response["content"] as? [[String: Any]], !blocks.isEmpty else { throw AIProviderError.invalidResponse }
        let replay = try JSONSerialization.data(withJSONObject: blocks)
        let calls = try blocks.filter { $0["type"] as? String == "tool_use" }.map { block -> ProviderToolCall in
            guard let id = block["id"] as? String, !id.isEmpty, let name = block["name"] as? String, !name.isEmpty,
                  let args = block["input"] as? [String: Any] else { throw AIProviderError.invalidResponse }
            return ProviderToolCall(id: id, name: name, arguments: try JSONSerialization.data(withJSONObject: args), replayContent: replay)
        }
        if !calls.isEmpty { return .toolCalls(calls) }
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }
        guard !text.isEmpty else { throw AIProviderError.invalidResponse }
        return .message(text.joined())
    }

    public func streamChat(messages: [ChatMessage], systemPrompt: String?) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    let key = try apiKey(for: config, credentialStore: credentialStore)
                    let request = try messagesRequest(messages: messages, systemPrompt: systemPrompt, stream: true, apiKey: key)
                    let (bytes, response) = try await session.bytes(for: request); try checkNativeResponse(response)
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if let data = payload.data(using: .utf8), let object = try? nativeObject(data), object["type"] as? String == "error" { throw AIProviderError.invalidResponse }
                        if let text = Self.extractStreamText(from: payload) { continuation.yield(text) }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: safeNativeError(error)) }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }
    static func extractStreamText(from payload: String) -> String? {
        guard let data = payload.data(using: .utf8), let object = try? nativeObject(data),
              object["type"] as? String == "content_block_delta", let delta = object["delta"] as? [String: Any] else { return nil }
        return delta["text"] as? String
    }
}

// MARK: - Gemini adapter

public struct GeminiProvider: AIProvider {
    public let id: UUID
    public let displayName: String
    public let modelId: String
    public let kind: ProviderKind = .gemini
    private let config: ProviderConfig
    private let credentialStore: CredentialStore
    private let session: URLSession
    private let requestPerformer: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(config: ProviderConfig, credentialStore: CredentialStore = KeychainCredentialStore(), session: URLSession = .shared,
                requestPerformer: (@Sendable (URLRequest) async throws -> (Data, URLResponse))? = nil) throws {
        guard config.resolvedBaseURL != nil else { throw AIProviderError.invalidBaseURL("") }
        self.id = config.id; self.displayName = config.displayName; self.modelId = config.selectedModel
        self.config = config; self.credentialStore = credentialStore; self.session = session
        self.requestPerformer = requestPerformer ?? { try await session.data(for: $0) }
    }
    private func request(route: String, apiKey: String, stream: Bool = false) -> URLRequest {
        var components = URLComponents(url: nativeURL(base: config.resolvedBaseURL!, version: "v1beta", route: route), resolvingAgainstBaseURL: false)!
        // Credentials never belong in URLs (including imported query strings).
        components.queryItems = stream ? [URLQueryItem(name: "alt", value: "sse")] : nil
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = config.timeoutSeconds
        for header in config.customHeaders { request.setValue(header.value, forHTTPHeaderField: header.key) }
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    func generateRequest(stream: Bool, apiKey: String, systemPrompt: String?, messages: [ChatMessage]) throws -> URLRequest {
        let model = modelId.hasPrefix("models/") ? String(modelId.dropFirst(7)) : modelId
        var request = request(route: "models/\(model):\(stream ? "streamGenerateContent" : "generateContent")", apiKey: apiKey, stream: stream)
        request.httpMethod = "POST"
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        var body: [String: Any] = ["contents": messages.filter { $0.role != .system }.map { ["role": $0.role == .assistant ? "model" : "user", "parts": [["text": $0.content]]] }]
        if let system = nativeSystem(messages: messages, prompt: systemPrompt) { body["system_instruction"] = ["parts": [["text": system]]] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    private func perform(_ request: URLRequest) async throws -> Data {
        do { let (data, response) = try await requestPerformer(request); try checkNativeResponse(response); return data }
        catch { throw safeNativeError(error) }
    }
    public func testConnection() async throws -> TimeInterval {
        let start = Date(); _ = try await discoverModels(); return Date().timeIntervalSince(start) * 1000
    }
    public func discoverModels() async throws -> [ModelInfo] {
        let key = try apiKey(for: config, credentialStore: credentialStore)
        var request = request(route: "models", apiKey: key); request.httpMethod = "GET"
        let object = try nativeObject(await perform(request))
        guard let entries = object["models"] as? [[String: Any]] else { throw AIProviderError.invalidResponse }
        return try entries.map { entry in
            guard let name = entry["name"] as? String, !name.isEmpty else { throw AIProviderError.invalidResponse }
            return ModelInfo(id: name.hasPrefix("models/") ? String(name.dropFirst(7)) : name)
        }
    }
    public func completeWithTools(messages: [ChatMessage], systemPrompt: String?, tools: [ProviderToolDefinition], toolResults: [ProviderToolExchange]) async throws -> ProviderTurnResult {
        let key = try apiKey(for: config, credentialStore: credentialStore)
        var request = try generateRequest(stream: false, apiKey: key, systemPrompt: systemPrompt, messages: messages)
        var body = try nativeObject(request.httpBody!)
        var history = body["contents"] as? [[String: Any]] ?? []
        for exchange in toolResults {
            try validateExchange(exchange)
            if let replay = exchange.calls.first?.replayContent { history.append(try nativeObject(replay)) }
            else { history.append(["role": "model", "parts": try exchange.calls.map { ["functionCall": ["name": $0.name, "args": try nativeObject($0.arguments)]] }]) }
            let parts = try exchange.results.map { result -> [String: Any] in
                guard let call = exchange.calls.first(where: { $0.id == result.toolCallID }) else { throw AIProviderError.invalidResponse }
                var response: [String: Any] = ["name": call.name, "response": ["output": result.content]]
                if let replay = call.replayContent, let content = try? nativeObject(replay), let blocks = content["parts"] as? [[String: Any]],
                   blocks.contains(where: { ($0["functionCall"] as? [String: Any])?["id"] as? String == call.id }) { response["id"] = call.id }
                return ["functionResponse": response]
            }
            history.append(["role": "user", "parts": parts])
        }
        body["contents"] = history
        if !tools.isEmpty { body["tools"] = [["functionDeclarations": try tools.map { ["name": $0.name, "description": $0.description, "parameters": try nativeSchema($0)] }]] }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let response = try nativeObject(await perform(request))
        guard let candidates = response["candidates"] as? [[String: Any]], let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]], !parts.isEmpty else { throw AIProviderError.invalidResponse }
        var replayContent = content; replayContent["role"] = "model"
        let replay = try JSONSerialization.data(withJSONObject: replayContent)
        let calls = try parts.filter { $0["functionCall"] != nil }.map { part -> ProviderToolCall in
            guard let function = part["functionCall"] as? [String: Any], let name = function["name"] as? String, !name.isEmpty else { throw AIProviderError.invalidResponse }
            let args: [String: Any]
            if function["args"] == nil { args = [:] }
            else if let value = function["args"] as? [String: Any] { args = value }
            else { throw AIProviderError.invalidResponse }
            return ProviderToolCall(id: function["id"] as? String ?? UUID().uuidString, name: name, arguments: try JSONSerialization.data(withJSONObject: args), replayContent: replay)
        }
        if !calls.isEmpty { return .toolCalls(calls) }
        let text = parts.filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }
        guard !text.isEmpty else { throw AIProviderError.invalidResponse }
        return .message(text.joined())
    }
    public func streamChat(messages: [ChatMessage], systemPrompt: String?) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let producer = Task {
                do {
                    let key = try apiKey(for: config, credentialStore: credentialStore)
                    let request = try generateRequest(stream: true, apiKey: key, systemPrompt: systemPrompt, messages: messages)
                    let (bytes, response) = try await session.bytes(for: request); try checkNativeResponse(response)
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if let data = payload.data(using: .utf8), let object = try? nativeObject(data), object["error"] != nil { throw AIProviderError.invalidResponse }
                        for text in Self.extractStreamTexts(from: payload) { continuation.yield(text) }
                    }
                    continuation.finish()
                } catch { continuation.finish(throwing: safeNativeError(error)) }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel() }
        }
    }
    static func extractStreamTexts(from payload: String) -> [String] {
        guard let data = payload.data(using: .utf8), let object = try? nativeObject(data), let candidates = object["candidates"] as? [[String: Any]] else { return [] }
        return candidates.compactMap { candidate in
            guard let content = candidate["content"] as? [String: Any], let parts = content["parts"] as? [[String: Any]] else { return nil }
            let texts = parts.filter { $0["thought"] as? Bool != true }.compactMap { $0["text"] as? String }
            return texts.isEmpty ? nil : texts.joined()
        }
    }
}
