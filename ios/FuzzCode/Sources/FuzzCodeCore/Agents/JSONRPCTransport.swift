import Foundation

public typealias AgentJSONValue = MCPJSONValue

public extension MCPJSONValue {
    var rpcObject: [String: Self]? { if case .object(let value) = self { return value }; return nil }
    var rpcString: String? { if case .string(let value) = self { return value }; return nil }
    var rpcArray: [Self]? { if case .array(let value) = self { return value }; return nil }
    var rpcBool: Bool { if case .bool(let value) = self { return value }; return false }
    var rpcNumber: Double? { if case .number(let value) = self { return value }; return nil }
}

public struct AgentRPCError: Codable, Sendable {
    public let code: Int
    public let message: String
}

public struct AgentRPCMessage: Codable, Sendable {
    public var jsonrpc: String?
    public var id: AgentJSONValue?
    public var method: String?
    public var params: AgentJSONValue?
    public var result: AgentJSONValue?
    public var error: AgentRPCError?

    public init(id: AgentJSONValue? = nil, method: String? = nil, params: AgentJSONValue? = nil,
                result: AgentJSONValue? = nil, jsonrpc: String? = "2.0") {
        self.jsonrpc = jsonrpc; self.id = id; self.method = method
        self.params = params; self.result = result
    }
}

/// Bidirectional JSON-RPC transport. ACP and Codex adapters own their different protocol messages.
public protocol ACPTransport: Sendable {
    func connect() async throws
    func disconnect() async
    func request(method: String, params: AgentJSONValue, timeoutSeconds: TimeInterval) async throws -> AgentJSONValue
    func notify(method: String, params: AgentJSONValue) async throws
    func respond(id: AgentJSONValue, result: AgentJSONValue) async throws
    func incomingMessages() async -> AsyncThrowingStream<AgentRPCMessage, Error>
}

public extension ACPTransport {
    func request(method: String, params: AgentJSONValue = .object([:])) async throws -> AgentJSONValue {
        try await request(method: method, params: params, timeoutSeconds: 30)
    }
}

public actor WebSocketACPTransport: ACPTransport {
    private let host: OpenCodeHostConfig
    private let credentials: any CredentialStore
    private let session: URLSession
    private let includesVersion: Bool
    private var socket: URLSessionWebSocketTask?
    private var reader: Task<Void, Never>?
    private var pending: [String: CheckedContinuation<AgentJSONValue, Error>] = [:]
    private var timers: [String: Task<Void, Never>] = [:]
    private var subscribers: [UUID: AsyncThrowingStream<AgentRPCMessage, Error>.Continuation] = [:]

    public init(hostConfig: OpenCodeHostConfig, credentialStore: any CredentialStore = KeychainCredentialStore(),
                session: URLSession = .shared, includesJSONRPCVersion: Bool = true) {
        host = hostConfig; credentials = credentialStore; self.session = session
        includesVersion = includesJSONRPCVersion
    }

    public func connect() async throws {
        if socket != nil { return }
        let endpoint = try host.validatedEndpoint()
        let request = try host.authenticatedRequest(url: endpoint, credentials: credentials)
        let task = session.webSocketTask(with: request)
        task.maximumMessageSize = 1_048_576
        socket = task
        task.resume()
        reader = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    let frame = try await task.receive()
                    let data: Data
                    switch frame {
                    case .data(let value): data = value
                    case .string(let value): data = Data(value.utf8)
                    @unknown default: throw AgentConnectionError.invalidResponse
                    }
                    let message = try JSONDecoder().decode(AgentRPCMessage.self, from: data)
                    await self?.receive(message)
                }
            } catch {
                await self?.fail(AgentConnectionError.transportFailed("WebSocket disconnected. Reconnect to resume the session."))
            }
        }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                task.sendPing { error in
                    if error != nil { continuation.resume(throwing: AgentConnectionError.transportFailed("Authenticated WebSocket handshake failed.")) }
                    else { continuation.resume() }
                }
            }
        } catch {
            await disconnect()
            throw error
        }
    }

    public func disconnect() async {
        reader?.cancel(); reader = nil
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        fail(AgentConnectionError.transportFailed("Connection closed."))
    }

    public func request(method: String, params: AgentJSONValue, timeoutSeconds: TimeInterval) async throws -> AgentJSONValue {
        try Task.checkCancellation()
        guard socket != nil else { throw AgentConnectionError.transportFailed("Connect before sending requests.") }
        let key = UUID().uuidString
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[key] = continuation
                timers[key] = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: UInt64(max(0.1, timeoutSeconds) * 1_000_000_000))
                        await self?.complete(key, result: .failure(AgentConnectionError.transportFailed("Request timed out.")))
                    } catch {}
                }
                Task { [weak self] in
                    do { try await self?.send(AgentRPCMessage(id: .string(key), method: method, params: params)) }
                    catch { await self?.complete(key, result: .failure(AgentConnectionError.transportFailed("Request could not be sent."))) }
                }
            }
        } onCancel: {
            Task { await self.complete(key, result: .failure(CancellationError())) }
        }
    }

    public func notify(method: String, params: AgentJSONValue) async throws {
        try await send(AgentRPCMessage(method: method, params: params))
    }

    public func respond(id: AgentJSONValue, result: AgentJSONValue) async throws {
        try await send(AgentRPCMessage(id: id, result: result))
    }

    public func incomingMessages() async -> AsyncThrowingStream<AgentRPCMessage, Error> {
        let key = UUID()
        return AsyncThrowingStream { continuation in
            subscribers[key] = continuation
            continuation.onTermination = { @Sendable _ in Task { await self.removeSubscriber(key) } }
        }
    }

    private func removeSubscriber(_ key: UUID) { subscribers.removeValue(forKey: key) }

    private func send(_ incoming: AgentRPCMessage) async throws {
        guard let socket else { throw AgentConnectionError.transportFailed("Connection closed.") }
        var message = incoming
        message.jsonrpc = includesVersion ? "2.0" : nil
        let data = try JSONEncoder().encode(message)
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }

    private func receive(_ message: AgentRPCMessage) {
        if message.method == nil, let key = message.id?.rpcString, pending[key] != nil {
            if let error = message.error {
                // Remote messages may reflect credentials; expose only the stable error code.
                complete(key, result: .failure(AgentConnectionError.remoteError("JSON-RPC error \(error.code)")))
            } else if let result = message.result { complete(key, result: .success(result)) }
            else { complete(key, result: .failure(AgentConnectionError.invalidResponse)) }
        } else if message.method != nil {
            for subscriber in subscribers.values { subscriber.yield(message) }
        }
    }

    private func complete(_ key: String, result: Result<AgentJSONValue, Error>) {
        timers.removeValue(forKey: key)?.cancel()
        pending.removeValue(forKey: key)?.resume(with: result)
    }

    private func fail(_ error: Error) {
        socket?.cancel(with: .goingAway, reason: nil); socket = nil
        for key in Array(pending.keys) { complete(key, result: .failure(error)) }
        for subscriber in subscribers.values { subscriber.finish(throwing: error) }
        subscribers.removeAll()
    }
}
