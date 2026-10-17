import Foundation
import CoreFoundation

public enum MCPClientError: LocalizedError {
    case unsupportedTransport(String)
    case invalidURL
    case missingCredential
    case notInitialized
    case httpStatus(Int)
    case invalidResponse(String)
    case serverError(code: Int, message: String, details: String?)
    case toolExecutionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedTransport(let transport):
            return "The MCP transport \(transport) is not supported on this platform."
        case .invalidURL:
            return "The MCP server URL is invalid."
        case .missingCredential:
            return "The configured MCP credential was not found in the Keychain."
        case .notInitialized:
            return "The MCP server session has not been initialized."
        case .httpStatus(let status):
            return "The MCP server returned HTTP status \(status)."
        case .invalidResponse(let detail):
            return "The MCP server returned an invalid response: \(detail)"
        case .serverError(let code, let message, let details):
            return "MCP server error \(code): \(message)" + (details.map { " (\($0))" } ?? "")
        case .toolExecutionFailed(let message):
            return "MCP tool execution failed: \(message)"
        }
    }
}

private struct MCPServerEvent {
    let name: String
    let data: String
}

private func mcpEvents(from data: Data) -> [MCPServerEvent] {
    let text = String(decoding: data, as: UTF8.self)
    var parser = MCPEventParser()
    var events: [MCPServerEvent] = []
    for rawLine in text.components(separatedBy: "\n") {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if let event = parser.consume(line) { events.append(event) }
    }
    if let event = parser.finish() { events.append(event) }
    return events
}

private struct MCPEventParser {
    private var name = "message"
    private var data: [String] = []

    mutating func consume(_ line: String) -> MCPServerEvent? {
        if line.isEmpty { return finish() }
        guard !line.hasPrefix(":") else { return nil }
        let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let field = String(parts[0])
        var value = parts.count > 1 ? String(parts[1]) : ""
        if value.first == " " { value.removeFirst() }
        if field == "event" { name = value }
        if field == "data" { data.append(value) }
        return nil
    }

    mutating func finish() -> MCPServerEvent? {
        defer {
            name = "message"
            data = []
        }
        guard !data.isEmpty else { return nil }
        return MCPServerEvent(name: name, data: data.joined(separator: "\n"))
    }
}

private actor MCPEventChannel {
    private var iterator: AsyncThrowingStream<MCPServerEvent, Error>.Iterator
    private let readerTask: Task<Void, Never>

    init(iterator: AsyncThrowingStream<MCPServerEvent, Error>.Iterator, readerTask: Task<Void, Never>) {
        self.iterator = iterator
        self.readerTask = readerTask
    }

    deinit {
        readerTask.cancel()
    }

    func next() async throws -> MCPServerEvent? {
        var currentIterator = iterator
        let event = try await currentIterator.next()
        iterator = currentIterator
        return event
    }

    static func open(session: URLSession, request: URLRequest) -> MCPEventChannel {
        let (stream, continuation) = AsyncThrowingStream<MCPServerEvent, Error>.makeStream()
        let task = Task {
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw MCPClientError.invalidResponse("The event stream was not an HTTP response.")
                }
                guard (200...299).contains(httpResponse.statusCode) else {
                    throw MCPClientError.httpStatus(httpResponse.statusCode)
                }
                var parser = MCPEventParser()
                for try await line in bytes.lines {
                    if let event = parser.consume(line) { continuation.yield(event) }
                }
                if let event = parser.finish() { continuation.yield(event) }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        return MCPEventChannel(iterator: stream.makeAsyncIterator(), readerTask: task)
    }

    static func open(data: Data) -> MCPEventChannel {
        let (stream, continuation) = AsyncThrowingStream<MCPServerEvent, Error>.makeStream()
        let task = Task {
            mcpEvents(from: data).forEach { continuation.yield($0) }
            continuation.finish()
        }
        return MCPEventChannel(iterator: stream.makeAsyncIterator(), readerTask: task)
    }
}

/// Native MCP client using Streamable HTTP and legacy HTTP+SSE transports.
public actor MCPClient {
    private static let initialProtocolVersion = "2024-11-05"
    private let config: MCPServerConfig
    private let session: URLSession
    private let credentialLookup: @Sendable (String) -> String?
    private let requestPerformer: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let eventStreamResponse: (@Sendable (URLRequest) async throws -> Data)?
    private var nextRequestID = 1
    private var sessionID: String?
    private var protocolVersion: String?
    private var initialized = false
    private var legacyMessageURL: URL?
    private var legacyEvents: MCPEventChannel?

    public init(
        config: MCPServerConfig,
        session: URLSession = .shared,
        credentialLookup: @escaping @Sendable (String) -> String? = { KeychainService.shared.get(key: $0) }
    ) {
        self.config = config
        self.session = session
        self.credentialLookup = credentialLookup
        self.requestPerformer = { request in try await session.data(for: request) }
        self.eventStreamResponse = nil
    }

    init(
        config: MCPServerConfig,
        session: URLSession,
        credentialLookup: @escaping @Sendable (String) -> String?,
        requestPerformer: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse),
        eventStreamResponse: (@Sendable (URLRequest) async throws -> Data)? = nil
    ) {
        self.config = config
        self.session = session
        self.credentialLookup = credentialLookup
        self.requestPerformer = requestPerformer
        self.eventStreamResponse = eventStreamResponse
    }

    /// Initializes an MCP session and discovers its tools and resources.
    public func initializeAndDiscover() async throws -> (tools: [MCPTool], resources: [MCPResource], latencyMs: Double) {
        try requireSupportedTransport()
        guard let endpoint = URL(string: config.endpointURLString) else {
            throw MCPClientError.invalidURL
        }
        let started = CFAbsoluteTimeGetCurrent()
        initialized = false
        sessionID = nil
        protocolVersion = nil
        if config.transport == .sse {
            try await openLegacyEventStream(endpoint: endpoint)
        }

        let initializeResult = try await sendRequest("initialize", params: [
            "protocolVersion": Self.initialProtocolVersion,
            "capabilities": ["tools": [:], "resources": [:]],
            "clientInfo": ["name": "FuzzCode-iOS", "version": "1.0.0"]
        ])
        guard let negotiatedVersion = initializeResult["protocolVersion"] as? String,
              !negotiatedVersion.isEmpty else {
            throw MCPClientError.invalidResponse("initialize did not return a protocol version.")
        }
        protocolVersion = negotiatedVersion
        try await sendNotification("notifications/initialized")
        initialized = true

        var tools: [MCPTool] = []
        var cursor: String?
        var seenCursors = Set<String>()
        repeat {
            let result = try await sendRequest("tools/list", params: cursor.map { ["cursor": $0] } ?? [:])
            guard let entries = result["tools"] as? [[String: Any]] else {
                throw MCPClientError.invalidResponse("tools/list did not return a tools array.")
            }
            tools.append(contentsOf: try entries.map(decodeTool))
            cursor = result["nextCursor"] as? String
            if let cursor, !seenCursors.insert(cursor).inserted {
                throw MCPClientError.invalidResponse("tools/list repeated a pagination cursor.")
            }
        } while cursor != nil

        var resources: [MCPResource] = []
        cursor = nil
        seenCursors = []
        repeat {
            let result = try await sendRequest("resources/list", params: cursor.map { ["cursor": $0] } ?? [:])
            guard let entries = result["resources"] as? [[String: Any]] else {
                throw MCPClientError.invalidResponse("resources/list did not return a resources array.")
            }
            resources.append(contentsOf: try entries.map(decodeResource))
            cursor = result["nextCursor"] as? String
            if let cursor, !seenCursors.insert(cursor).inserted {
                throw MCPClientError.invalidResponse("resources/list repeated a pagination cursor.")
            }
        } while cursor != nil

        return (tools, resources, max((CFAbsoluteTimeGetCurrent() - started) * 1000, 0))
    }

    /// Invokes a tool in the initialized MCP session.
    public func callTool(name: String, arguments: [String: Any]) async throws -> String {
        try requireSupportedTransport()
        guard initialized else { throw MCPClientError.notInitialized }
        let result = try await sendRequest("tools/call", params: ["name": name, "arguments": arguments])
        if let rawIsError = result["isError"] {
            guard let isError = rawIsError as? Bool else {
                throw MCPClientError.invalidResponse("tools/call returned a non-boolean isError value.")
            }
            if isError {
                throw MCPClientError.toolExecutionFailed(textContent(in: result) ?? "The server reported an error.")
            }
        }

        if let content = result["content"] {
            guard let blocks = content as? [[String: Any]] else {
                throw MCPClientError.invalidResponse("tools/call returned malformed content.")
            }
            let text = blocks.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }
            if !text.isEmpty { return text.joined(separator: "\n") }
            if !blocks.isEmpty { return Self.jsonText(blocks) ?? "" }
        }
        if let structuredContent = result["structuredContent"] {
            return Self.jsonText(structuredContent) ?? ""
        }
        return ""
    }

    private func requireSupportedTransport() throws {
        switch config.transport {
        case .streamableHTTP, .sse:
            return
        case .websocket, .stdioRemote:
            throw MCPClientError.unsupportedTransport(config.transport.rawValue)
        }
    }

    private func openLegacyEventStream(endpoint: URL) async throws {
        var request = try makeRequest(url: endpoint, method: "GET", accept: "text/event-stream")
        request.httpBody = nil
        let channel: MCPEventChannel
        if let eventStreamResponse {
            channel = MCPEventChannel.open(data: try await eventStreamResponse(request))
        } else {
            channel = MCPEventChannel.open(session: session, request: request)
        }
        legacyEvents = channel
        while let event = try await channel.next() {
            guard event.name.lowercased() == "endpoint" else { continue }
            let value = event.data.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: value, relativeTo: endpoint)?.absoluteURL else {
                throw MCPClientError.invalidResponse("The SSE endpoint event did not contain a valid message URL.")
            }
            legacyMessageURL = url
            return
        }
        throw MCPClientError.invalidResponse("The SSE stream ended before its endpoint event.")
    }

    private func sendRequest(_ method: String, params: [String: Any]) async throws -> [String: Any] {
        let requestID = nextRequestID
        nextRequestID += 1
        let payload: [String: Any] = ["jsonrpc": "2.0", "id": requestID, "method": method, "params": params]
        let body = try JSONSerialization.data(withJSONObject: payload)

        switch config.transport {
        case .streamableHTTP:
            guard let endpoint = URL(string: config.endpointURLString) else { throw MCPClientError.invalidURL }
            let (data, response) = try await streamablePOST(url: endpoint, body: body, expectedID: requestID)
            updateSession(from: response)
            return try Self.decodeRPCResponse(data, expectedID: requestID)
        case .sse:
            guard let messageURL = legacyMessageURL, let channel = legacyEvents else {
                throw MCPClientError.notInitialized
            }
            let (_, response) = try await post(body, to: messageURL)
            updateSession(from: response)
            while let event = try await channel.next() {
                if event.name.lowercased() == "endpoint" { continue }
                let data = Data(event.data.utf8)
                let object = try Self.jsonObject(from: data)
                guard let responseID = object["id"] else { continue }
                if Self.idsMatch(requestID, responseID) {
                    return try Self.decodeRPCResponse(data, expectedID: requestID)
                }
            }
            throw MCPClientError.invalidResponse("The SSE stream ended before responding to request \(requestID).")
        case .websocket, .stdioRemote:
            throw MCPClientError.unsupportedTransport(config.transport.rawValue)
        }
    }

    private func sendNotification(_ method: String) async throws {
        let payload: [String: Any] = ["jsonrpc": "2.0", "method": method]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let endpoint: URL
        if config.transport == .streamableHTTP {
            guard let url = URL(string: config.endpointURLString) else { throw MCPClientError.invalidURL }
            endpoint = url
        } else {
            guard let url = legacyMessageURL else { throw MCPClientError.notInitialized }
            endpoint = url
        }
        let (_, response) = try await post(body, to: endpoint)
        updateSession(from: response)
    }

    private func post(_ body: Data, to url: URL) async throws -> (Data, HTTPURLResponse) {
        var request = try makeRequest(url: url, method: "POST", accept: "application/json, text/event-stream")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await requestPerformer(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPClientError.invalidResponse("The server response was not HTTP.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw MCPClientError.httpStatus(httpResponse.statusCode)
        }
        return (data, httpResponse)
    }

    private func streamablePOST(url: URL, body: Data, expectedID: Int) async throws -> (Data, HTTPURLResponse) {
        var request = try makeRequest(url: url, method: "POST", accept: "application/json, text/event-stream")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (responseData, response) = try await requestPerformer(request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPClientError.invalidResponse("The server response was not HTTP.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw MCPClientError.httpStatus(httpResponse.statusCode)
        }
        if httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("text/event-stream") == true {
            for event in mcpEvents(from: responseData) {
                if let data = try Self.matchingResponseData(event.data, expectedID: expectedID) {
                    return (data, httpResponse)
                }
            }
            throw MCPClientError.invalidResponse("The SSE response ended without a matching request id.")
        }
        return (responseData, httpResponse)
    }

    private func makeRequest(url: URL, method: String, accept: String) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("FuzzCode-MCP-Client/1.0", forHTTPHeaderField: "User-Agent")
        for header in config.customHeaders where !header.key.isEmpty && !header.value.isEmpty {
            let value = credentialLookup(header.value) ?? header.value
            request.setValue(value, forHTTPHeaderField: header.key)
        }
        if let tokenKey = config.authTokenKey {
            guard let token = credentialLookup(tokenKey), !token.isEmpty else {
                throw MCPClientError.missingCredential
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
        if let protocolVersion {
            request.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        }
        return request
    }

    private func updateSession(from response: HTTPURLResponse) {
        if let value = response.value(forHTTPHeaderField: "Mcp-Session-Id"), !value.isEmpty {
            sessionID = value
        }
    }

    private func decodeTool(_ entry: [String: Any]) throws -> MCPTool {
        guard let name = entry["name"] as? String, !name.isEmpty,
              let rawSchema = entry["inputSchema"], JSONSerialization.isValidJSONObject(rawSchema) else {
            throw MCPClientError.invalidResponse("tools/list contained a tool without a valid input schema.")
        }
        let schemaData = try JSONSerialization.data(withJSONObject: rawSchema)
        let schema = try JSONDecoder().decode(MCPToolInputSchema.self, from: schemaData)
        return MCPTool(name: name, description: entry["description"] as? String ?? "", inputSchema: schema)
    }

    private func decodeResource(_ entry: [String: Any]) throws -> MCPResource {
        guard let uri = entry["uri"] as? String, !uri.isEmpty,
              let name = entry["name"] as? String, !name.isEmpty else {
            throw MCPClientError.invalidResponse("resources/list contained a resource without a URI or name.")
        }
        return MCPResource(
            uri: uri,
            name: name,
            description: entry["description"] as? String,
            mimeType: entry["mimeType"] as? String
        )
    }

    private func textContent(in result: [String: Any]) -> String? {
        guard let blocks = result["content"] as? [[String: Any]] else { return nil }
        let text = blocks.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }
        return text.isEmpty ? nil : text.joined(separator: "\n")
    }

    private static func jsonText(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func matchingResponseData(_ string: String, expectedID: Int) throws -> Data? {
        let data = Data(string.utf8)
        let object = try jsonObject(from: data)
        guard let responseID = object["id"] else { return nil }
        guard idsMatch(expectedID, responseID) else {
            throw MCPClientError.invalidResponse("The JSON-RPC response id did not match the request.")
        }
        return data
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let value = try? JSONSerialization.jsonObject(with: data),
              let object = value as? [String: Any] else {
            throw MCPClientError.invalidResponse("The response body was not a JSON object.")
        }
        return object
    }

    private static func decodeRPCResponse(_ data: Data, expectedID: Int) throws -> [String: Any] {
        let response = try jsonObject(from: data)
        guard response["jsonrpc"] as? String == "2.0" else {
            throw MCPClientError.invalidResponse("The JSON-RPC version was not 2.0.")
        }
        guard let responseID = response["id"] else {
            throw MCPClientError.invalidResponse("The JSON-RPC response did not contain an id.")
        }
        guard idsMatch(expectedID, responseID) else {
            throw MCPClientError.invalidResponse("The JSON-RPC response id did not match the request.")
        }
        if let rawError = response["error"] {
            guard let error = rawError as? [String: Any],
                  let code = error["code"] as? Int,
                  let message = error["message"] as? String else {
                throw MCPClientError.invalidResponse("The JSON-RPC error object was malformed.")
            }
            guard response["result"] == nil else {
                throw MCPClientError.invalidResponse("The JSON-RPC response contained both result and error.")
            }
            throw MCPClientError.serverError(
                code: code,
                message: message,
                details: error["data"].flatMap { jsonText($0) }
            )
        }
        guard let result = response["result"] as? [String: Any] else {
            throw MCPClientError.invalidResponse("The JSON-RPC response did not contain a result object.")
        }
        return result
    }

    private static func idsMatch(_ expected: Any, _ received: Any) -> Bool {
        if let expected = expected as? String { return (received as? String) == expected }
        guard let expectedNumber = expected as? NSNumber,
              let receivedNumber = received as? NSNumber,
              CFGetTypeID(expectedNumber) != CFBooleanGetTypeID(),
              CFGetTypeID(receivedNumber) != CFBooleanGetTypeID() else { return false }
        return expectedNumber == receivedNumber
    }
}
