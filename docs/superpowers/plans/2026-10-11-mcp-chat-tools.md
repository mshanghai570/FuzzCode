# MCP Chat Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect configured MCP servers correctly and let users approve, execute, and see MCP tool results during chat.

**Architecture:** Keep MCP JSON-RPC/session logic in `MCPClient`, expose tool requests through the existing OpenAI-compatible chat transport only when supported, and pause chat in `ChatView` for explicit per-call approval before invoking a tool. The Integrations Settings plan supplies persisted server management.

**Tech Stack:** Swift 5.9+, Foundation `URLSession`, SwiftUI, JSON-RPC 2.0, XCTest, iOS 17.

**Spec:** `docs/superpowers/specs/2026-10-11-native-integrations-design.md`

**Prerequisite:** Complete `docs/superpowers/plans/2026-10-11-native-settings-integrations.md` first so MCP configurations can be opened and persisted from Settings.

## Global Constraints

- The iOS deployment target is iOS 17.0.
- FuzzCode uses pure native iOS frameworks and has zero third-party runtime dependencies.
- Never report a connection or discovered capability from a nominal fallback.
- Every MCP tool invocation requires explicit per-call user approval.
- Surface protocol and transport failures; do not silently substitute cached tools or successful outputs.
- Support MCP Streamable HTTP and legacy HTTP+SSE; explicitly reject WebSocket and stdio-remote configurations rather than implying they work.

---

### Task 1: Add deterministic MCP HTTP tests

**Files:**
- Modify: `ios/FuzzCode/Tests/FuzzCodeTests/MCPConnectorTests.swift`
- Create: `ios/FuzzCode/Tests/FuzzCodeTests/MockURLProtocol.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/MCP/MCPClient.swift`

**Interfaces:**
- Add an injectable `URLSession` path using the existing `MCPClient(config:session:)` initializer.
- Mock handlers return configured HTTP status, headers, and JSON-RPC bodies for each request.

- [ ] **Step 1: Add mock URL protocol and failing behavioral tests**

Implement `MockURLProtocol` with a static request handler and captured requests. Test initialization error response, HTTP 401, tools-list discovery, and tools/call result decoding. Verify a failed request throws instead of returning the config's cached tools.

- [ ] **Step 2: Run MCP tests to capture current behavior**

Run: `cd ios/FuzzCode && swift test --filter MCPConnectorTests`
Expected: the existing no-op model tests pass; new live-discovery and no-fallback assertions fail.

- [ ] **Step 3: Add test session construction**

Create an ephemeral `URLSessionConfiguration`, set `protocolClasses = [MockURLProtocol.self]`, and inject the resulting session. Keep production defaults unchanged.

- [ ] **Step 4: Verify mock transport**

Run: `cd ios/FuzzCode && swift test --filter MCPConnectorTests`
Expected: test requests reach the mock handler and assertions fail only on the unimplemented protocol behavior.

- [ ] **Step 5: Commit**

```bash
git add ios/FuzzCode/Tests/FuzzCodeTests/MCPConnectorTests.swift ios/FuzzCode/Tests/FuzzCodeTests/MockURLProtocol.swift
git commit -m "test: add MCP transport coverage"
```

### Task 2: Implement MCP transport, initialize, session, and discovery

**Files:**
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/MCP/MCPClient.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/MCP/MCPModels.swift`
- Modify: `ios/FuzzCode/Tests/FuzzCodeTests/MCPConnectorTests.swift`

**Interfaces:**
- `initializeAndDiscover() async throws -> (tools: [MCPTool], resources: [MCPResource], latencyMs: Double)` throws on any transport, HTTP, or JSON-RPC error.
- `callTool(name:arguments:) async throws -> String` uses the initialized MCP session and decodes text content or reports an MCP error.
- `MCPServerConfig.customHeaders` stores header names and Keychain lookup references, never header secret values.

- [ ] **Step 1: Define test protocol responses**

Add Streamable HTTP JSON-RPC response fixtures with protocol version, server info, tools with real input schemas, resources, and an HTTP `Mcp-Session-Id`. Add legacy SSE fixtures for the server-sent `endpoint` event and subsequent JSON-RPC messages. Add fixtures for JSON-RPC `error`, malformed JSON, non-2xx status, and `tools/call` `isError`.

- [ ] **Step 2: Parse JSON-RPC and HTTP errors**

Implement typed internal response decoding for `jsonrpc`, `id`, `result`, and `error`. Require 2xx status and a valid response matching the request ID. Convert server errors into a localized `MCPClientError`; preserve server error details without including authorization values.

- [ ] **Step 3: Implement both supported HTTP transports**

For Streamable HTTP, POST `initialize` with the supported protocol version and client capabilities; retain the returned session ID; send `notifications/initialized`; request `tools/list` and `resources/list`; decode complete schemas and resource metadata, accepting the protocol's JSON or SSE response form. For legacy HTTP+SSE, open the SSE endpoint, parse its `endpoint` event, send JSON-RPC POSTs to that message endpoint, and correlate SSE responses by request ID. Preserve cancellation and close the event stream when the client is released. Never fall back to configured discovered metadata when any request fails.

- [ ] **Step 4: Implement authenticated/session-aware tool calls**

Resolve the Keychain token value as `Authorization: Bearer <token>` and custom-header values from their Keychain references for every request. Add the session ID to follow-up requests. POST `tools/call`, check HTTP and JSON-RPC errors, return concatenated text content, and throw on an MCP `isError` result.

- [ ] **Step 5: Run MCP tests**

Run: `cd ios/FuzzCode && swift test --filter MCPConnectorTests`
Expected: initialization, discovery, tool invocation, malformed response, auth error, and server error cases pass.

- [ ] **Step 6: Reject unsupported transports explicitly**

Add `.streamableHTTP` as a transport option while preserving decoding of existing `.sse`, `.websocket`, and `.stdioRemote` values. Keep `.sse` as the legacy HTTP+SSE transport. The UI offers Streamable HTTP and legacy SSE; saved WebSocket/stdio-remote entries display an unsupported-transport error and cannot test or call tools. Do not implement local process spawning on iOS.

- [ ] **Step 7: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeCore/MCP/MCPClient.swift ios/FuzzCode/Sources/FuzzCodeCore/MCP/MCPModels.swift ios/FuzzCode/Tests/FuzzCodeTests/MCPConnectorTests.swift
git commit -m "fix: implement MCP session discovery"
```

### Task 3: Report only live MCP connection status

**Files:**
- Modify: `ios/FuzzCode/Sources/FuzzCodeUI/Views/MCP/MCPConnectorView.swift`
- Modify: `ios/FuzzCode/Tests/FuzzCodeTests/MCPConnectorTests.swift`

**Interfaces:**
- The connector view updates `isConnected`, latency, tools, and resources only after `initializeAndDiscover()` succeeds.
- A failed attempt sets `isConnected = false`, clears stale discovered metadata, and displays `lastError`.
- The Add/Edit Server form stores only a Keychain reference in `authTokenKey`; the bearer token itself is saved through `KeychainService` and never serialized with `MCPServerConfig`.

- [ ] **Step 1: Test error-state policy**

Test that a failed probe calls `MCPServerConfig.markUnverified()`, leaves the server disconnected with empty tools/resources, and then stores the thrown error in `lastError`. Test that a prior connection is not retained after failed refresh.

- [ ] **Step 2: Add secure server credentials and supported transport choices**

Add a `SecureField` to the server form. On save, write a supplied token to Keychain under a stable server-specific key, assign only that key to `authTokenKey`, and check the `KeychainService.save` result before updating server state. Reuse an existing credential when editing without a replacement token. If custom headers are editable, store their values under per-server Keychain keys and persist only header names plus lookup references. Add a model migration test that rejects or safely migrates any legacy custom header containing a raw credential. Offer Streamable HTTP and legacy SSE only; keep unsupported saved transports visible with an explanatory error.

- [ ] **Step 3: Replace stale success behavior**

Update the test action to preserve thrown errors in the server row, clear `testingServerId` on both paths, and avoid presenting a nominal latency or success haptic after failure.

- [ ] **Step 4: Build and run MCP tests**

Run: `cd ios/FuzzCode && swift test --filter MCPConnectorTests && xcodebuild -project FuzzCode.xcodeproj -scheme FuzzCode -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: tests and native app build pass.

- [ ] **Step 5: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeUI/Views/MCP/MCPConnectorView.swift ios/FuzzCode/Tests/FuzzCodeTests/MCPConnectorTests.swift
git commit -m "fix: show MCP connection failures"
```

### Task 4: Model provider tool-call requests and results

**Files:**
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/Networking/OpenAIClient.swift`
- Create: `ios/FuzzCode/Sources/FuzzCodeCore/Networking/ToolCallModels.swift`
- Create: `ios/FuzzCode/Tests/FuzzCodeTests/ProviderToolCallingTests.swift`

**Interfaces:**
- `ProviderToolDefinition` contains `name`, `description`, and `MCPToolInputSchema`.
- `ProviderToolCall` contains `id`, `name`, and decoded `[String: Any]` arguments.
- `ProviderTurnResult` is either `.message(String)` or `.toolCalls([ProviderToolCall])`.
- `OpenAIClient.completeWithTools(messages:systemPrompt:tools:toolResults:) async throws -> ProviderTurnResult` performs a non-streaming OpenAI-compatible Chat Completions request and surfaces HTTP/API errors.

- [ ] **Step 1: Write request/response tests**

Use the mock URL protocol to assert tool definitions map to OpenAI `type: "function"` schema, a normal completion decodes as `.message`, tool calls decode with IDs and JSON arguments, tool results serialize as `role: "tool"` with matching `tool_call_id`, and HTTP errors throw.

- [ ] **Step 2: Run focused tests**

Run: `cd ios/FuzzCode && swift test --filter ProviderToolCallingTests`
Expected: compilation fails because the tool models and method are missing.

- [ ] **Step 3: Add typed tool models**

Implement the public `ProviderToolDefinition`, `ProviderToolCall`, and `ProviderTurnResult` types. For arbitrary JSON arguments use `Data` or a JSON-compatible wrapper in the public `Sendable` type, then decode to a dictionary only at the request boundary; do not declare `[String: Any]` as `Sendable`.

- [ ] **Step 4: Implement authenticated non-streaming tool completion**

Reuse `constructChatCompletionsURL`, configured headers, timeout, and error mapping. Decode `choices[0].message.content`, `tool_calls`, function name/arguments, and finish reason. Include prior assistant tool-call messages and tool-role result messages in subsequent requests.

- [ ] **Step 5: Run focused tests**

Run: `cd ios/FuzzCode && swift test --filter ProviderToolCallingTests`
Expected: request shape, normal output, tool call/result decoding, and errors pass.

- [ ] **Step 6: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeCore/Networking/OpenAIClient.swift ios/FuzzCode/Sources/FuzzCodeCore/Networking/ToolCallModels.swift ios/FuzzCode/Tests/FuzzCodeTests/ProviderToolCallingTests.swift
git commit -m "feat: support provider tool calls"
```

### Task 5: Gate tool execution in chat

**Files:**
- Modify: `ios/FuzzCode/Sources/FuzzCodeUI/Views/Chat/ChatView.swift`
- Create: `ios/FuzzCode/Sources/FuzzCodeUI/Views/Chat/MCPToolApprovalView.swift`
- Modify: `ios/FuzzCode/Tests/FuzzCodeTests/ProviderToolCallingTests.swift`

**Interfaces:**
- Chat state holds pending tool calls and approval decisions. `MCPToolApprovalView` displays server name, tool name, formatted arguments, and separate Approve/Deny actions.
- Approved calls alone invoke `MCPClient.callTool`; denial adds a denied result and never performs network I/O.

- [ ] **Step 1: Add coordinator-level tool-cycle tests**

Test with injected provider/MCP executors that denied requests make zero MCP calls, approved requests execute once with exact arguments, execution errors become visible tool results, and cancellation prevents later tool calls.

- [ ] **Step 2: Add approval UI**

Create an accessible confirmation card/sheet that shows server identity, tool, and arguments as selectable text. Require an explicit Approve tap for every request; do not add an “always allow” path.

- [ ] **Step 3: Wire tool discovery into the request**

Before sending, collect tools only from enabled servers whose current connection was successfully verified. Namespace tool names with a stable server identifier to prevent collisions and retain the mapping back to `MCPClient`. If no eligible server or no tools exist, retain the existing streaming completion path.

- [ ] **Step 4: Implement bounded request/approval/result loop**

For a tool-capable turn, call `completeWithTools`; append normal model messages directly. For each returned tool call, present approval, execute only approved calls, collect results, then submit the assistant tool-call message and tool results for the next provider turn. Cap tool-call rounds at 8; when reached, display a clear limit error and stop. Preserve cancellation checks before every network call and state update.

- [ ] **Step 5: Show outcomes in the transcript**

Append concise visible transcript entries for approved tool name/result and denied tool calls; show execution failures in `errorMessage`. Never expose auth headers or raw secrets. Keep original user prompt and assistant message persistence intact.

- [ ] **Step 6: Run all focused tests and app build**

Run: `cd ios/FuzzCode && swift test --filter 'MCPConnectorTests|ProviderToolCallingTests|ConversationPersistenceTests' && xcodebuild -project FuzzCode.xcodeproj -scheme FuzzCode -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: tests and app build pass; unsupported providers with ordinary chat remain unaffected.

- [ ] **Step 7: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeUI/Views/Chat/ChatView.swift ios/FuzzCode/Sources/FuzzCodeUI/Views/Chat/MCPToolApprovalView.swift ios/FuzzCode/Tests/FuzzCodeTests/ProviderToolCallingTests.swift
git commit -m "feat: approve MCP tools in chat"
```
