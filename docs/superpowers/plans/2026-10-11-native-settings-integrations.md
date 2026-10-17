# Native Settings Integrations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make MCP and GitHub connector management reachable from native Settings and persist their non-secret configuration.

**Architecture:** Add a focused Integrations screen linked from Settings. It owns persisted connector configuration and presents the existing MCP and GitHub screens with bindings; network clients and secret handling remain in their respective feature plans.

**Tech Stack:** Swift 5.9+, SwiftUI, Foundation, XCTest, iOS 17.

**Spec:** `docs/superpowers/specs/2026-10-11-native-integrations-design.md`

## Global Constraints

- The iOS deployment target is iOS 17.0.
- FuzzCode uses pure native iOS frameworks and has zero third-party runtime dependencies.
- All secrets are routed to `KeychainService`.
- Dangerous agent tools must pass through an interactive approval gate.
- Do not present a connector as connected without a successful live handshake.

---

### Task 1: Persist MCP and GitHub connector configuration

**Files:**
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/Persistence/StorageService.swift`
- Create: `ios/FuzzCode/Tests/FuzzCodeTests/IntegrationPersistenceTests.swift`

**Interfaces:**
- Produces `saveMCPServers(_:) throws`, `loadMCPServers() throws`, `saveGitHubConfig(_:) throws`, and `loadGitHubConfig() throws` on `StorageService`.
- These methods persist configuration and metadata only; they must not write credential values. GitHub's existing `keychainTokenKey` remains a reference.
- Add `StorageService(directoryURL:)` for isolated tests while keeping `StorageService.shared` on the application-support directory. Missing files return defaults; malformed data and write failures throw.

- [ ] **Step 1: Write failing storage round-trip tests**

Add tests using a temporary directory that save two MCP server configs (including discovered tool metadata) and a `GitHubConfig` with profile metadata, load them back, and assert equality. Add tests that absent integration files return an empty MCP list and disconnected default GitHub config, while malformed JSON throws.

- [ ] **Step 2: Run the focused test target and confirm failure**

Run: `cd ios/FuzzCode && swift test --filter IntegrationPersistenceTests`
Expected: compilation fails because the four storage accessors are not defined.

- [ ] **Step 3: Add explicit storage accessors**

Add the injectable storage directory and implement typed accessors for `mcp_servers.json` and `github_config.json`. Return defaults only when the file does not exist; propagate file, encoding, and decoding errors. Do not add secret fields or silently serialize GitHub access tokens.

- [ ] **Step 4: Run focused tests**

Run: `cd ios/FuzzCode && swift test --filter IntegrationPersistenceTests`
Expected: both round-trip and absent-file tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeCore/Persistence/StorageService.swift ios/FuzzCode/Tests/FuzzCodeTests/IntegrationPersistenceTests.swift
git commit -m "feat: persist integration configuration"
```

### Task 2: Expose connectors from Settings

**Files:**
- Create: `ios/FuzzCode/Sources/FuzzCodeUI/Views/Settings/IntegrationsView.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeUI/Views/Settings/SettingsView.swift`
- Test: `ios/FuzzCode/Tests/FuzzCodeTests/IntegrationPersistenceTests.swift`

**Interfaces:**
- `IntegrationsView` loads MCP servers and `GitHubConfig` from `StorageService`, then saves changes made in bound connector screens.
- Existing screens remain `MCPConnectorView(servers:)` and `GitHubConnectorView(config:)`.
- Load/save errors are shown in the screen and do not present an unsaved edit as persisted.

- [ ] **Step 1: Add the Settings navigation entry**

Add a `SettingsView` section named “Integrations” with a `NavigationLink` labeled “MCP & GitHub”. The destination is `IntegrationsView`; do not duplicate connector implementation inside Settings.

- [ ] **Step 2: Create the integration list and state owner**

Create `IntegrationsView` as a `NavigationStack`/`List` with MCP and GitHub rows. Since both existing connector views contain their own `NavigationStack`, present them in sheets rather than pushing nested navigation stacks. Initialize `@State` from `StorageService.shared.loadMCPServers()` and `.loadGitHubConfig()`. Bind each existing connector view to that state and save on change or sheet dismissal. Use the current FuzzTheme list styling.

- [ ] **Step 3: Verify routes and configuration persistence**

Run: `cd ios/FuzzCode && swift test --filter IntegrationPersistenceTests`
Expected: persisted connector data round-trips and the app target compiles with both routes.

- [ ] **Step 4: Build the native app**

Run: `cd ios/FuzzCode && xcodebuild -project FuzzCode.xcodeproj -scheme FuzzCode -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: build succeeds; Settings presents the connector entry and each connector screen.

- [ ] **Step 5: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeUI/Views/Settings/SettingsView.swift ios/FuzzCode/Sources/FuzzCodeUI/Views/Settings/IntegrationsView.swift
git commit -m "feat: expose connectors in settings"
```

---

### Task 3: Keep integration status honest on launch

**Files:**
- Modify: `ios/FuzzCode/Sources/FuzzCodeUI/Views/Settings/IntegrationsView.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/MCP/MCPModels.swift`
- Test: `ios/FuzzCode/Tests/FuzzCodeTests/IntegrationPersistenceTests.swift`

**Interfaces:**
- Persisted configuration loads into the Settings owner. Live connection status is established by the relevant connector plan, not inferred from the presence of stored configuration.
- `MCPServerConfig.markUnverified()` sets disconnected state, clears latency and discovered tools/resources, and clears stale errors before a server is exposed as callable.

- [ ] **Step 1: Add and test the runtime reset method**

Add a test that a config with prior connection status, latency, and cached tools becomes disconnected with empty live metadata after `markUnverified()`, while its server name, endpoint, transport, auth reference, and enabled setting are unchanged.

- [ ] **Step 2: Reset status on load and surface storage errors**

On loading stored MCP configurations, call `markUnverified()` and retain endpoint, auth-key references, headers, and enabled state. GitHub's persisted account metadata may remain visible, but the GitHub connector must validate the Keychain token before claiming it is connected (implemented in the GitHub plan). Display errors thrown by load/save operations and retain the last persisted state on failure.

- [ ] **Step 3: Run the integration tests and app build**

Run: `cd ios/FuzzCode && swift test --filter IntegrationPersistenceTests && xcodebuild -project FuzzCode.xcodeproj -scheme FuzzCode -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: tests and build pass; saved configuration is available without asserting a live connection.

- [ ] **Step 4: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeUI/Views/Settings/IntegrationsView.swift ios/FuzzCode/Tests/FuzzCodeTests/IntegrationPersistenceTests.swift
git commit -m "fix: restore integrations as unverified"
```
