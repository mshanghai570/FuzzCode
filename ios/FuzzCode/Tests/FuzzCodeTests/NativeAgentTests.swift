import XCTest
import Foundation
@testable import FuzzCodeCore

struct StubAIProvider: AIProvider {
    let id = UUID()
    let displayName = "Stub"
    let modelId = "stub-model"
    let kind: ProviderKind = .custom
    let turnResult: ProviderTurnResult

    func testConnection() async throws -> TimeInterval { 1.0 }
    func discoverModels() async throws -> [ModelInfo] { [ModelInfo(id: "stub-model")] }
    func streamChat(messages: [ChatMessage], systemPrompt: String?) async -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.yield("stub"); $0.finish() }
    }
    func completeWithTools(
        messages: [ChatMessage],
        systemPrompt: String?,
        tools: [ProviderToolDefinition],
        toolResults: [ProviderToolExchange]
    ) async throws -> ProviderTurnResult {
        turnResult
    }
}

final class NativeAgentTests: XCTestCase {

    func testNativeAgentKeepsConfiguredProviderSelectionInsteadOfChoosingFirstEnabled() throws {
        let first = ProviderConfig(displayName: "First", baseURLString: "https://first.example/v1", isEnabled: true)
        let selected = ProviderConfig(displayName: "Selected", baseURLString: "https://selected.example/v1", isEnabled: true)
        XCTAssertEqual(NativeAgentEngine.configuredProvider(from: [first, selected], selectedProviderID: selected.id)?.id, selected.id)
    }

    func testNativeAgentDoesNotSilentlyFallBackWhenSelectedProviderIsUnavailable() throws {
        let first = ProviderConfig(displayName: "First", baseURLString: "https://first.example/v1", isEnabled: true)
        let selectedID = UUID()
        XCTAssertNil(NativeAgentEngine.configuredProvider(from: [first], selectedProviderID: selectedID))
    }

    func testNativeAgentUsesOnlyEnabledProviderWhenSelectionIsUnambiguous() throws {
        let disabled = ProviderConfig(displayName: "Disabled", baseURLString: "https://disabled.example/v1", isEnabled: false)
        let enabled = ProviderConfig(displayName: "Enabled", baseURLString: "https://enabled.example/v1", isEnabled: true)
        XCTAssertEqual(NativeAgentEngine.configuredProvider(from: [disabled, enabled], selectedProviderID: nil)?.id, enabled.id)
    }

    func testNativeAgentRequiresChoiceWhenMultipleProvidersAreEnabled() throws {
        let first = ProviderConfig(displayName: "First", baseURLString: "https://first.example/v1", isEnabled: true)
        let second = ProviderConfig(displayName: "Second", baseURLString: "https://second.example/v1", isEnabled: true)
        XCTAssertNil(NativeAgentEngine.configuredProvider(from: [first, second], selectedProviderID: nil))
    }

    private func makeWorkspace() throws -> WorkspaceManager {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return try WorkspaceManager(root: dir)
    }

    func testWorkspaceRejectsPathEscape() throws {
        let workspace = try makeWorkspace()
        XCTAssertThrowsError(try workspace.readFile(relativePath: "../outside.txt")) { error in
            XCTAssertEqual(error as? WorkspaceManager.WorkspaceError, .pathEscapesRoot)
        }
        XCTAssertThrowsError(try workspace.writeFile(relativePath: "a/../../evil.txt", content: "x")) { error in
            XCTAssertEqual(error as? WorkspaceManager.WorkspaceError, .pathEscapesRoot)
        }
    }

    func testWorkspaceWriteReadListRoundTrip() throws {
        let workspace = try makeWorkspace()
        try workspace.writeFile(relativePath: "notes/hello.txt", content: "hello world")
        XCTAssertEqual(try workspace.readFile(relativePath: "notes/hello.txt"), "hello world")
        let files = try workspace.listFiles()
        XCTAssertTrue(files.contains("notes/"))
        XCTAssertTrue(files.contains("notes/hello.txt"))
    }

    func testApplyUnifiedPatchModifiesFile() throws {
        let workspace = try makeWorkspace()
        try workspace.writeFile(relativePath: "code.swift", content: "line1\nline2\nline3\n")
        let patch = """
        --- a/code.swift
        +++ b/code.swift
        @@ -1,3 +1,3 @@
         line1
        -line2
        +line2 edited
         line3
        """
        let preview = try workspace.applyUnifiedPatch(patch)
        XCTAssertTrue(preview.contains("code.swift"))
        XCTAssertEqual(try workspace.readFile(relativePath: "code.swift"), "line1\nline2 edited\nline3\n")
    }

    func testApplyUnifiedPatchCreatesNewFile() throws {
        let workspace = try makeWorkspace()
        let patch = """
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1,2 @@
        +first
        +second
        """
        let preview = try workspace.applyUnifiedPatch(patch)
        XCTAssertTrue(preview.contains("new.txt"))
        XCTAssertEqual(try workspace.readFile(relativePath: "new.txt"), "first\nsecond")
    }

    func testApplyUnifiedPatchRejectsContextMismatch() throws {
        let workspace = try makeWorkspace()
        try workspace.writeFile(relativePath: "code.swift", content: "different\ncontent\n")
        let patch = """
        --- a/code.swift
        +++ b/code.swift
        @@ -1,2 +1,2 @@
        -line1
        +line1 edited
         content
        """
        XCTAssertThrowsError(try workspace.applyUnifiedPatch(patch))
    }

    func testNativeEngineToolDefinitions() {
        let names = Set(NativeAgentEngine.toolDefinitions().map(\.name))
        XCTAssertEqual(names, ["list_files", "read_file", "write_file", "apply_patch", "search_files"])
        XCTAssertFalse(NativeAgentEngine.systemPrompt.isEmpty)
    }

    func testNativeEngineCompletesPlainMessageTurn() async throws {
        let workspace = try makeWorkspace()
        let storage = StorageService(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        let engine = NativeAgentEngine(
            provider: StubAIProvider(turnResult: .message("done")),
            workspace: workspace,
            storage: storage,
            permissionHandler: { _ in .deny })
        let session = try await engine.createSession(workspacePath: "native:test")
        let stream = await engine.sendInstruction(sessionId: session.id, prompt: "hello")
        var sawFinished = false
        for try await event in stream {
            if case .finished = event { sawFinished = true }
        }
        XCTAssertTrue(sawFinished)
        let stored = storage.loadAgentSessions()
        XCTAssertEqual(stored.first?.status, .completed)
        XCTAssertEqual(stored.first?.messages.first?.role, .user)
        XCTAssertEqual(stored.first?.messages.first?.content, "hello")
        XCTAssertEqual(stored.first?.messages.last?.content, "done")
        XCTAssertEqual(stored.first?.connectionKind, .native)
    }

    func testNativeEngineDeniesWriteWithoutApproval() async throws {
        let workspace = try makeWorkspace()
        let storage = StorageService(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        let call = ProviderToolCall(id: "1", name: "write_file",
            arguments: Data(#"{"path":"x.txt","content":"hi"}"#.utf8))
        let engine = NativeAgentEngine(
            provider: StubAIProvider(turnResult: .toolCalls([call])),
            workspace: workspace,
            storage: storage,
            permissionHandler: { _ in .deny })
        let session = try await engine.createSession(workspacePath: "native:test2")
        let stream = await engine.sendInstruction(sessionId: session.id, prompt: "write it")
        do { for try await _ in stream {} } catch { /* A repeated tool-only provider exhausts the bounded loop. */ }
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.root.appendingPathComponent("x.txt").path))
        XCTAssertEqual(storage.loadAgentSessions().first?.status, .failed)
        XCTAssertEqual(storage.loadAgentSessions().first?.messages.last?.toolEvents.first?.status, .denied)
    }
}

final class WorkspaceSafetyTests: XCTestCase {
    func testRejectsSymlinkReadWriteAndInventory() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspace = try WorkspaceManager(root: base.appendingPathComponent("workspace", isDirectory: true))
        let outside = base.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try "secret".write(to: outside.appendingPathComponent("secret.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: workspace.root.appendingPathComponent("link"), withDestinationURL: outside)
        XCTAssertThrowsError(try workspace.readFile(relativePath: "link/secret.txt"))
        XCTAssertThrowsError(try workspace.writeFile(relativePath: "link/new.txt", content: "bad"))
        XCTAssertFalse(try workspace.listFiles().contains("link/secret.txt"))
    }
    func testMultipleHunksUseOldCoordinates() throws {
        let workspace = try WorkspaceManager(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        try workspace.writeFile(relativePath: "x", content: "a\nb\nc\nd\n")
        try workspace.applyUnifiedPatch("--- a/x\n+++ b/x\n@@ -1,1 +1,2 @@\n a\n+extra\n@@ -3,1 +4,1 @@\n-c\n+C")
        XCTAssertEqual(try workspace.readFile(relativePath: "x"), "a\nextra\nb\nC\nd\n")
    }
    func testValidMultiFilePatchUpdatesEachTarget() throws {
        let workspace = try WorkspaceManager(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        try workspace.writeFile(relativePath: "x", content: "a")
        try workspace.writeFile(relativePath: "y", content: "b")
        try workspace.applyUnifiedPatch("--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+A\n--- a/y\n+++ b/y\n@@ -1 +1 @@\n-b\n+B")
        XCTAssertEqual(try workspace.readFile(relativePath: "x"), "A")
        XCTAssertEqual(try workspace.readFile(relativePath: "y"), "B")
    }
    func testMalformedCountsAndTraversalPatchNeverMutate() throws {
        let workspace = try WorkspaceManager(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        try workspace.writeFile(relativePath: "x", content: "a")
        XCTAssertThrowsError(try workspace.applyUnifiedPatch("--- a/x\n+++ b/x\n@@ -1,2 +1,1 @@\n-a\n+A"))
        XCTAssertThrowsError(try workspace.applyUnifiedPatch("--- /dev/null\n+++ b/../outside\n@@ -0,0 +1,1 @@\n+bad"))
        XCTAssertEqual(try workspace.readFile(relativePath: "x"), "a")
    }
    func testInvalidSecondFileDoesNotMutateFirst() throws {
        let workspace = try WorkspaceManager(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        try workspace.writeFile(relativePath: "x", content: "a")
        XCTAssertThrowsError(try workspace.applyUnifiedPatch("--- a/x\n+++ b/x\n@@ -1 +1 @@\n-a\n+A\n--- a/y\n+++ b/y\n@@ -1 +1 @@\n-missing\n+B"))
        XCTAssertEqual(try workspace.readFile(relativePath: "x"), "a")
    }
}

actor ApprovalGate {
    private var continuation: CheckedContinuation<PermissionDecision, Never>?
    private var waiting = false
    func request() async -> PermissionDecision {
        waiting = true
        return await withCheckedContinuation { continuation = $0 }
    }
    func isWaiting() -> Bool { waiting }
    func approve() { continuation?.resume(returning: .allowOnce); continuation = nil }
}
final class NativeCancellationTests: XCTestCase {
    func testCancellationCannotAuthorizePendingWrite() async throws {
        let workspace = try WorkspaceManager(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        let storage = StorageService(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        let gate = ApprovalGate()
        let call = ProviderToolCall(id: "write", name: "write_file", arguments: Data(#"{"path":"x","content":"bad"}"#.utf8))
        let engine = NativeAgentEngine(provider: StubAIProvider(turnResult: .toolCalls([call])), workspace: workspace, storage: storage, permissionHandler: { _ in await gate.request() })
        let session = try await engine.createSession(workspacePath: workspace.root.path)
        let stream = await engine.sendInstruction(sessionId: session.id, prompt: "edit")
        let consumer = Task { do { for try await _ in stream {} } catch {} }
        for _ in 0..<1000 {
            if await gate.isWaiting() { break }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        let waiting = await gate.isWaiting()
        XCTAssertTrue(waiting)
        try await engine.cancelTask(sessionId: session.id)
        await gate.approve()
        await consumer.value
        XCTAssertThrowsError(try workspace.readFile(relativePath: "x"))
        XCTAssertEqual(storage.loadAgentSessions().first?.status, .cancelled)
    }
}

final class NativeIdentityTests: XCTestCase {
    func testStableIdentityRestoresOnlyOwnWorkspaceSessions() async throws {
        let workspace = try WorkspaceManager(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        let storage = StorageService(directoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        let provider = StubAIProvider(turnResult: .message("done"))
        let hostId = UUID()
        let engine = NativeAgentEngine(provider: provider, workspace: workspace, storage: storage, id: hostId, permissionHandler: { _ in .deny })
        let created = try await engine.createSession(workspacePath: workspace.root.path)
        storage.saveAgentSessions(storage.loadAgentSessions() + [AgentSession(hostId: UUID(), title: "unrelated", workspacePath: workspace.root.path)])
        let restored = NativeAgentEngine(provider: provider, workspace: workspace, storage: storage, id: hostId, permissionHandler: { _ in .deny })
        let sessions = try await restored.listSessions()
        XCTAssertEqual(sessions.map(\.id), [created.id])
        XCTAssertEqual(sessions.first?.providerId, provider.id)
        XCTAssertEqual(sessions.first?.connectionKind, .native)
    }
}
final class WorkspacePreviewTests: XCTestCase {
    func testPreviewNeverWritesAndSummaryUsesPersistentBaseline() throws {
        let workspace = try WorkspaceManager(root: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true))
        try workspace.writeFile(relativePath: "x", content: "old")
        try workspace.captureBaseline()
        let patch = "--- a/x\n+++ b/x\n@@ -1 +1 @@\n-old\n+new"
        XCTAssertTrue(try workspace.previewUnifiedPatch(patch).contains("new"))
        XCTAssertEqual(try workspace.readFile(relativePath: "x"), "old")
        XCTAssertTrue(try workspace.changeSummary().changedFiles.isEmpty)
        try workspace.applyUnifiedPatch(patch)
        let restored = try WorkspaceManager(root: workspace.root)
        let changed = try XCTUnwrap(restored.changeSummary().changedFiles.first)
        XCTAssertEqual(changed.status, .modified)
        XCTAssertEqual(changed.additions, 1)
        XCTAssertEqual(changed.deletions, 1)
        XCTAssertTrue(changed.patch.contains("-old"))
        XCTAssertTrue(changed.patch.contains("+new"))
    }
}
