import Foundation

/// Real integration client for an external OpenCode Coding Agent runtime.
/// Connects to OpenCode's HTTP & WebSocket server protocol (defaulting to standard companion port /api/v1).
/// Manages remote sessions, streaming tool execution events, git status diffs, and interactive permission gates.
public actor OpenCodeClient: CodingAgentProtocol {
    public let id: UUID
    public let name: String
    public var supportedCapabilities: Set<AgentCapability>
    
    private let hostConfig: OpenCodeHostConfig
    private let keychain: KeychainService
    private let session: URLSession
    
    public init(hostConfig: OpenCodeHostConfig, keychain: KeychainService = .shared) {
        self.id = hostConfig.id
        self.name = hostConfig.displayName
        self.hostConfig = hostConfig
        self.keychain = keychain
        self.supportedCapabilities = Set(hostConfig.capabilities)
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45.0
        self.session = URLSession(configuration: config)
    }
    
    private var baseHostURL: URL? {
        var str = hostConfig.hostURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        while str.hasSuffix("/") { str.removeLast() }
        return URL(string: str)
    }
    
    // MARK: - Handshake & Health
    
    public func connect() async throws -> AgentHostMetadata {
        guard let url = baseHostURL?.appendingPathComponent("api/v1/health") else {
            throw OpenCodeError.invalidHostURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(to: &request)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenCodeError.connectionFailed("No HTTP response")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw OpenCodeError.unauthorized
            }
            throw OpenCodeError.connectionFailed("Host responded with status \(httpResponse.statusCode)")
        }
        
        struct HealthPayload: Decodable {
            let hostId: String?
            let name: String?
            let version: String
            let os: String?
            let defaultWorkspace: String?
            let capabilities: [String]?
        }
        
        let payload = try JSONDecoder().decode(HealthPayload.self, from: data)
        let resolvedCaps = (payload.capabilities ?? []).compactMap { AgentCapability(rawValue: $0) }
        self.supportedCapabilities = Set(resolvedCaps.isEmpty ? hostConfig.capabilities : resolvedCaps)
        
        return AgentHostMetadata(
            hostId: payload.hostId ?? UUID().uuidString,
            name: payload.name ?? hostConfig.displayName,
            version: payload.version,
            osName: payload.os ?? "Darwin / macOS",
            defaultWorkspace: payload.defaultWorkspace ?? "/Users/developer/Projects/workspace",
            capabilities: Array(self.supportedCapabilities)
        )
    }
    
    // MARK: - Sessions
    
    public func listSessions() async throws -> [AgentSession] {
        guard let url = baseHostURL?.appendingPathComponent("api/v1/sessions") else {
            throw OpenCodeError.invalidHostURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(to: &request)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw OpenCodeError.remoteOperationFailed("Failed to fetch sessions")
        }
        
        return try JSONDecoder().decode([AgentSession].self, from: data)
    }
    
    public func createSession(workspacePath: String, prompt: String? = nil) async throws -> AgentSession {
        guard let url = baseHostURL?.appendingPathComponent("api/v1/sessions") else {
            throw OpenCodeError.invalidHostURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)
        
        var payload: [String: Any] = [
            "workspacePath": workspacePath,
            "hostId": hostConfig.id.uuidString
        ]
        if let prompt = prompt {
            payload["initialPrompt"] = prompt
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw OpenCodeError.remoteOperationFailed("Failed to create agent session")
        }
        
        return try JSONDecoder().decode(AgentSession.self, from: data)
    }
    
    // MARK: - Instruction & Event Streaming
    
    public func sendInstruction(sessionId: String, prompt: String) -> AsyncThrowingStream<AgentEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard let url = self.baseHostURL?.appendingPathComponent("api/v1/sessions/\(sessionId)/instruct") else {
                        continuation.finish(throwing: OpenCodeError.invalidHostURL)
                        return
                    }
                    
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    self.applyAuth(to: &request)
                    
                    let bodyData = try JSONSerialization.data(withJSONObject: ["prompt": prompt])
                    request.httpBody = bodyData
                    
                    let (asyncBytes, response) = try await self.session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
                        continuation.finish(throwing: OpenCodeError.remoteOperationFailed("Instruction request rejected"))
                        return
                    }
                    
                    for try await line in asyncBytes.lines {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard trimmed.hasPrefix("data:") else { continue }
                        let json = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        
                        if json == "[DONE]" {
                            continuation.yield(.finished)
                            continuation.finish()
                            return
                        }
                        
                        guard let data = json.data(using: .utf8),
                              let eventDict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = eventDict["type"] as? String else {
                            continue
                        }
                        
                        switch type {
                        case "text_delta":
                            if let delta = eventDict["text"] as? String {
                                continuation.yield(.textDelta(delta))
                            }
                        case "tool_started":
                            if let toolData = try? JSONSerialization.data(withJSONObject: eventDict["tool"] ?? [:]),
                               let tool = try? JSONDecoder().decode(AgentToolEvent.self, from: toolData) {
                                continuation.yield(.toolStarted(tool))
                            }
                        case "tool_completed":
                            let toolId = eventDict["toolId"] as? String ?? ""
                            let output = eventDict["output"] as? String ?? ""
                            let success = eventDict["success"] as? Bool ?? true
                            continuation.yield(.toolCompleted(toolId: toolId, output: output, success: success))
                        case "permission_required":
                            if let permData = try? JSONSerialization.data(withJSONObject: eventDict["permission"] ?? [:]),
                               let perm = try? JSONDecoder().decode(PermissionRequest.self, from: permData) {
                                continuation.yield(.permissionRequested(perm))
                            }
                        case "status_change":
                            if let statusStr = eventDict["status"] as? String,
                               let status = SessionStatus(rawValue: statusStr) {
                                continuation.yield(.statusChanged(status))
                            }
                        case "git_summary":
                            if let gitData = try? JSONSerialization.data(withJSONObject: eventDict["git"] ?? [:]),
                               let git = try? JSONDecoder().decode(GitStatusSummary.self, from: gitData) {
                                continuation.yield(.gitUpdated(git))
                            }
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Permission & Cancellation
    
    public func resolvePermission(requestId: String, decision: PermissionDecision, rationale: String? = nil) async throws {
        guard let url = baseHostURL?.appendingPathComponent("api/v1/permissions/\(requestId)/resolve") else {
            throw OpenCodeError.invalidHostURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(to: &request)
        
        var payload: [String: Any] = ["decision": decision.rawValue]
        if let rationale = rationale {
            payload["rationale"] = rationale
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw OpenCodeError.remoteOperationFailed("Could not resolve permission on remote host")
        }
    }
    
    public func cancelTask(sessionId: String) async throws {
        guard let url = baseHostURL?.appendingPathComponent("api/v1/sessions/\(sessionId)/cancel") else {
            throw OpenCodeError.invalidHostURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyAuth(to: &request)
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw OpenCodeError.remoteOperationFailed("Failed to cancel remote task")
        }
    }
    
    public func fetchGitStatus(sessionId: String) async throws -> GitStatusSummary {
        guard let url = baseHostURL?.appendingPathComponent("api/v1/sessions/\(sessionId)/git") else {
            throw OpenCodeError.invalidHostURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(to: &request)
        
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw OpenCodeError.remoteOperationFailed("Could not fetch git diff")
        }
        
        return try JSONDecoder().decode(GitStatusSummary.self, from: data)
    }
    
    private func applyAuth(to request: inout URLRequest) {
        if let token = keychain.get(key: hostConfig.authTokenKey) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }
}

public enum OpenCodeError: Error, LocalizedError, Equatable {
    case invalidHostURL
    case unauthorized
    case connectionFailed(String)
    case unsupportedCapability(AgentCapability)
    case remoteOperationFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidHostURL:
            return "The OpenCode host URL is malformed or invalid."
        case .unauthorized:
            return "Unauthorized: OpenCode companion token is invalid or expired."
        case .connectionFailed(let reason):
            return "Failed to connect to OpenCode host: \(reason)"
        case .unsupportedCapability(let cap):
            return "The connected OpenCode runtime does not support capability: \(cap.rawValue)"
        case .remoteOperationFailed(let msg):
            return "Remote agent error: \(msg)"
        }
    }
}
