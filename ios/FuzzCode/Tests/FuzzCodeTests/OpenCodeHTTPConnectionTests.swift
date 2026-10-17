import XCTest
@testable import FuzzCodeCore

private struct OpenCodeTestCredentials: CredentialStore {
    func retrieve(key: String) -> String? { "test-password" }
    func store(key: String, secret: String) {}
    func remove(key: String) {}
}

private actor OpenCodeWireFixture {
    var requests: [URLRequest] = []
    var streamOpened = false
    var promptAfterStream = false
    func open(_ request: URLRequest, events: [String]) -> (AsyncThrowingStream<String, Error>, URLResponse) {
        requests.append(request); streamOpened = true
        let stream = AsyncThrowingStream<String, Error> { continuation in
            for event in events { continuation.yield("data: \(event)"); continuation.yield("") }
            continuation.finish()
        }
        return (stream, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!)
    }
    func perform(_ request: URLRequest) throws -> (Data, URLResponse) {
        requests.append(request)
        let path = request.url!.path
        let body: String
        if path.hasSuffix("/global/health") { body = "{\"healthy\":true,\"version\":\"1.0\"}" }
        else if path.hasSuffix("/prompt_async") { promptAfterStream = streamOpened; body = "" }
        else if path.hasSuffix("/message") { body = "[{\"info\":{\"id\":\"m1\",\"role\":\"assistant\"},\"parts\":[{\"type\":\"text\",\"text\":\"restored\"}]}]" }
        else if path.hasSuffix("/diff") { body = "[{\"file\":\"a.swift\",\"before\":\"old\\n\",\"after\":\"new\\n\",\"additions\":1,\"deletions\":1}]" }
        else if path.hasSuffix("/vcs") { body = "{\"branch\":\"feature\"}" }
        else if path.hasSuffix("/abort") || path.hasSuffix("/reply") || path.contains("/permissions/") { body = "true" }
        else if path.hasSuffix("/session") && request.httpMethod != "POST" { body = "[\(Self.sessionJSON)]" }
        else { body = Self.sessionJSON }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: path.hasSuffix("/prompt_async") ? 204 : 200, httpVersion: nil, headerFields: nil)!)
    }
    static let sessionJSON = "{\"id\":\"ses_1\",\"title\":\"Remote\",\"directory\":\"/remote/project\",\"time\":{\"created\":1000,\"updated\":2000}}"
}

final class OpenCodeHTTPConnectionTests: XCTestCase {
    private func make(_ fixture: OpenCodeWireFixture, events: [String] = []) throws -> OpenCodeHTTPConnection {
        let config = OpenCodeHostConfig(displayName: "Stock", hostURLString: "https://example.com/proxy", currentWorkspace: "/remote/project", remoteProtocol: .openCodeHTTP)
        return try OpenCodeHTTPConnection(hostConfig: config, credentialStore: OpenCodeTestCredentials(), requestPerformer: { try await fixture.perform($0) }, eventPerformer: { await fixture.open($0, events: events) })
    }
    func testHealthSessionDirectoryBasicAuthAndResume() async throws {
        let fixture = OpenCodeWireFixture(), connection = try make(fixture)
        let health = try await connection.connect()
        XCTAssertEqual(health.version, "1.0")
        let created = try await connection.createSession(workspacePath: "/remote/project", prompt: nil)
        XCTAssertEqual(created.id, "ses_1")
        let resumed = try await connection.resumeSession(sessionId: created.id, workspacePath: created.workspacePath)
        XCTAssertEqual(resumed.messages.first?.content, "restored")
        let requests = await fixture.requests
        XCTAssertEqual(requests.first?.url?.path, "/proxy/global/health")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Basic \(Data("opencode:test-password".utf8).base64EncodedString())")
        XCTAssertTrue(requests.contains { $0.url?.query?.contains("directory=") == true })
        XCTAssertFalse(requests.contains { $0.url?.path.contains("api/v1") == true })
    }
    func testStreamOpensBeforePromptFiltersSessionsAndTranslatesPermission() async throws {
        let fixture = OpenCodeWireFixture()
        let events = [
            "{\"type\":\"server.connected\",\"properties\":{}}",
            "{\"type\":\"message.updated\",\"properties\":{\"info\":{\"id\":\"m1\",\"sessionID\":\"ses_1\",\"role\":\"assistant\"}}}",
            "{\"type\":\"message.part.delta\",\"properties\":{\"sessionID\":\"other\",\"messageID\":\"m1\",\"partID\":\"p1\",\"field\":\"text\",\"delta\":\"wrong\"}}",
            "{\"type\":\"message.part.delta\",\"properties\":{\"sessionID\":\"ses_1\",\"messageID\":\"m1\",\"partID\":\"p1\",\"field\":\"text\",\"delta\":\"hello\"}}",
            "{\"type\":\"permission.asked\",\"properties\":{\"sessionID\":\"ses_1\",\"id\":\"per_1\",\"permission\":\"edit\",\"patterns\":[\"a.swift\"],\"metadata\":{\"diff\":\"+new\"}}}",
            "{\"type\":\"session.status\",\"properties\":{\"sessionID\":\"ses_1\",\"status\":{\"type\":\"idle\"}}}"
        ]
        let connection = try make(fixture, events: events)
        var text = "", permission: PermissionRequest?, finished = false
        for try await event in await connection.sendInstruction(sessionId: "ses_1", prompt: "work") {
            switch event { case .textDelta(let delta): text += delta
            case .permissionRequested(let request): permission = request
            case .finished: finished = true
            default: break }
        }
        XCTAssertEqual(text, "hello"); XCTAssertTrue(finished)
        XCTAssertEqual(permission?.fullParameters["diff"], "+new")
        try await connection.resolvePermission(requestId: "per_1", decision: .deny, rationale: "Declined")
        let ordered = await fixture.promptAfterStream
        XCTAssertTrue(ordered)
        let requests = await fixture.requests
        let prompt = try XCTUnwrap(requests.first { $0.url?.path.hasSuffix("/prompt_async") == true })
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: prompt.httpBody!) as? [String: Any])
        XCTAssertEqual((body["parts"] as? [[String: String]])?.first?["text"], "work")
        let reply = try XCTUnwrap(requests.last?.httpBody)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: reply) as? [String: String])?["reply"], "reject")
    }
    func testPrematureEventEOFDoesNotReportSuccess() async throws {
        let connection = try make(OpenCodeWireFixture(), events: ["{\"type\":\"server.connected\",\"properties\":{}}"])
        do {
            for try await _ in await connection.sendInstruction(sessionId: "ses_1", prompt: "work") {}
            XCTFail("Unexpected EOF must fail the turn")
        } catch { XCTAssertEqual(error as? AgentConnectionError, .transportFailed("Event stream ended before the turn completed.")) }
    }
    func testNativeDiffAndUnknownPermissionFailure() async throws {
        let connection = try make(OpenCodeWireFixture())
        let diff = try await connection.fetchGitStatus(sessionId: "ses_1")
        XCTAssertEqual(diff.changedFiles.first?.filePath, "a.swift")
        XCTAssertTrue(diff.changedFiles.first?.patch.contains("-old") == true)
        XCTAssertTrue(diff.changedFiles.first?.patch.contains("+new") == true)
        do { try await connection.resolvePermission(requestId: "missing", decision: .allowOnce, rationale: nil); XCTFail() }
        catch { XCTAssertEqual(error as? AgentConnectionError, .invalidResponse) }
    }
    func testUnhealthyHandshakeAndHTTPFailureStayErrors() async throws {
        let config = OpenCodeHostConfig(displayName: "Stock", hostURLString: "https://example.com", remoteProtocol: .openCodeHTTP)
        for status in [200, 401] {
            let connection = try OpenCodeHTTPConnection(hostConfig: config, credentialStore: OpenCodeTestCredentials(), requestPerformer: { request in
                (Data("{\"healthy\":false,\"version\":\"1\",\"secret\":\"test-password\"}".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            })
            do { _ = try await connection.connect(); XCTFail("Handshake should fail") }
            catch { XCTAssertFalse(error.localizedDescription.contains("test-password")) }
        }
    }

    func testCancellationAbortsRemoteSessionAndTerminatesStream() async throws {
        let fixture = OpenCodeWireFixture()
        let config = OpenCodeHostConfig(displayName: "Stock", hostURLString: "https://example.com", remoteProtocol: .openCodeHTTP)
        let connection = try OpenCodeHTTPConnection(hostConfig: config, credentialStore: OpenCodeTestCredentials(), requestPerformer: { try await fixture.perform($0) }, eventPerformer: { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield("data: {\"type\":\"server.connected\",\"properties\":{}}")
                continuation.yield("")
            }
            return (stream, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!)
        })
        let stream = await connection.sendInstruction(sessionId: "ses_1", prompt: "work")
        var iterator = stream.makeAsyncIterator()
        guard case .statusChanged(.running)? = try await iterator.next() else { return XCTFail("Missing running event") }
        try await connection.cancelTask(sessionId: "ses_1")
        guard case .statusChanged(.cancelled)? = try await iterator.next() else { return XCTFail("Missing cancelled event") }
        let end = try await iterator.next()
        XCTAssertNil(end)
        let requests = await fixture.requests
        XCTAssertTrue(requests.contains { $0.url?.path == "/session/ses_1/abort" && $0.httpMethod == "POST" })
    }

    func testAssistantSnapshotsAndToolUpdatesDoNotDuplicate() async throws {
        let fixture = OpenCodeWireFixture()
        let wire: [[String: Any]] = [
            ["type": "server.connected", "properties": [:]],
            ["type": "message.updated", "properties": ["info": ["id": "user", "sessionID": "ses_1", "role": "user"]]],
            ["type": "message.part.updated", "properties": ["part": ["id": "up", "messageID": "user", "sessionID": "ses_1", "type": "text", "text": "echo"]]],
            ["type": "message.updated", "properties": ["info": ["id": "assistant", "sessionID": "ses_1", "role": "assistant"]]],
            ["type": "message.part.updated", "properties": ["part": ["id": "ap", "messageID": "assistant", "sessionID": "ses_1", "type": "text", "text": "hello"]]],
            ["type": "message.part.updated", "properties": ["part": ["id": "ap", "messageID": "assistant", "sessionID": "ses_1", "type": "text", "text": "hello"]]],
            ["type": "message.part.updated", "properties": ["part": ["id": "tp", "sessionID": "ses_1", "type": "tool", "callID": "call", "tool": "read", "state": ["status": "running", "input": ["filePath": "a.swift"]]]]],
            ["type": "message.part.updated", "properties": ["part": ["id": "tp", "sessionID": "ses_1", "type": "tool", "callID": "call", "tool": "read", "state": ["status": "completed", "output": "content"]]]],
            ["type": "message.part.updated", "properties": ["part": ["id": "tp", "sessionID": "ses_1", "type": "tool", "callID": "call", "tool": "read", "state": ["status": "completed", "output": "content"]]]],
            ["type": "session.idle", "properties": ["sessionID": "ses_1"]]
        ]
        let events = try wire.map { String(data: try JSONSerialization.data(withJSONObject: $0), encoding: .utf8)! }
        let connection = try make(fixture, events: events)
        var text = "", started = 0, completed = 0
        for try await event in await connection.sendInstruction(sessionId: "ses_1", prompt: "work") {
            switch event {
            case .textDelta(let delta): text += delta
            case .toolStarted(let tool): started += 1; XCTAssertEqual(tool.toolName, "read")
            case .toolCompleted(_, let output, let success): completed += 1; XCTAssertEqual(output, "content"); XCTAssertTrue(success)
            default: break
            }
        }
        XCTAssertEqual(text, "hello"); XCTAssertEqual(started, 1); XCTAssertEqual(completed, 1)
    }

}
