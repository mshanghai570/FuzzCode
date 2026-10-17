# Native GitHub Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the existing native GitHub connector authenticate securely, browse repositories and pull requests, and allow explicit repository context selection for chat.

**Architecture:** Keep GitHub REST calls in `GitHubClient`, store access credentials only in Keychain, persist non-secret `GitHubConfig` through `StorageService`, and require an explicit in-chat action before selected repository content enters a model prompt.

**Tech Stack:** Swift 5.9+, SwiftUI, Foundation `URLSession`, Apple Keychain, XCTest, iOS 17.

**Spec:** `docs/superpowers/specs/2026-10-11-native-integrations-design.md`

**Prerequisite:** Complete `docs/superpowers/plans/2026-10-11-native-settings-integrations.md` first so GitHub management is reachable and its non-secret configuration persists.

## Global Constraints

- The iOS deployment target is iOS 17.0.
- FuzzCode uses pure native iOS frameworks and has zero third-party runtime dependencies.
- GitHub access tokens are stored only in `KeychainService`.
- Repository data is not silently injected into a prompt; the user must explicitly select it.
- Surface API, authorization, and decoding failures instead of substituting fabricated data.

---

### Task 1: Add authenticated injectable GitHub requests

**Files:**
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/GitHub/GitHubClient.swift`
- Modify: `ios/FuzzCode/Tests/FuzzCodeTests/GitHubConnectorTests.swift`
- Create: `ios/FuzzCode/Tests/FuzzCodeTests/GitHubMockURLProtocol.swift`

**Interfaces:**
- `GitHubClient(token:session:)` accepts an injectable URLSession.
- Internal request construction centralizes `Authorization: Bearer`, GitHub Accept, API version, and User-Agent headers.

- [ ] **Step 1: Add URL protocol test harness**

Implement `GitHubMockURLProtocol` with a static request handler and captured requests. Add tests for `/user`, `/user/repos`, and repository pull requests. Assert the auth header uses the token supplied to the client and that no request includes credentials in URL query parameters.

- [ ] **Step 2: Run GitHub tests**

Run: `cd ios/FuzzCode && swift test --filter GitHubConnectorTests`
Expected: current decoding tests pass; new request assertions expose missing injection/error-detail coverage.

- [ ] **Step 3: Centralize authenticated request handling**

Add one private method that creates and sends requests with `Authorization: Bearer <token>`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`, and the current User-Agent. Require a 2xx HTTP response; convert 401/403 distinctly from other server errors.

- [ ] **Step 4: Remove fabricated response fields**

Decode actual PR `additions` and `deletions` from GitHub API responses instead of fixed `45`/`12` values. Parse timestamps with the ISO8601 decoder and throw on invalid required fields rather than substituting `Date()`.

- [ ] **Step 5: Run tests**

Run: `cd ios/FuzzCode && swift test --filter GitHubConnectorTests`
Expected: authentication, request headers, repository decoding, real PR fields, and HTTP errors pass.

- [ ] **Step 6: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeCore/GitHub/GitHubClient.swift ios/FuzzCode/Tests/FuzzCodeTests/GitHubConnectorTests.swift ios/FuzzCode/Tests/FuzzCodeTests/GitHubMockURLProtocol.swift
git commit -m "fix: use verified GitHub API responses"
```

### Task 2: Persist and restore GitHub credentials safely

**Files:**
- Modify: `ios/FuzzCode/Sources/FuzzCodeUI/Views/GitHub/GitHubConnectorView.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/GitHub/GitHubModels.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/Persistence/StorageService.swift`
- Modify: `ios/FuzzCode/Tests/FuzzCodeTests/GitHubConnectorTests.swift`

**Interfaces:**
- `GitHubConfig.keychainTokenKey` references a Keychain item; no token is a Codable model field.
- `GitHubConnectorView` stores a token after successful authentication and reads it from Keychain before restoring a connected session.

- [ ] **Step 1: Add Keychain behavior tests**

Test token replacement/read/delete with `KeychainService.shared` using a unique test key and clean it up with `defer`. Assert encoded `GitHubConfig` contains the key reference but not the credential value.

- [ ] **Step 2: Implement credential lifecycle**

On Connect, authenticate with the entered token first. Only after profile authentication succeeds, save token under `config.keychainTokenKey`, save the non-secret config, and fetch repositories. On Disconnect, delete the Keychain entry, clear account/profile/selection state, save disconnected config, and clear rendered lists.

- [ ] **Step 3: Restore by validating stored credentials**

On screen appearance, load the Keychain token and call `authenticate()`. Show connected state only if that request succeeds. If Keychain access or authentication fails, show the disconnected sign-in UI and a readable error; do not delete the token automatically on transient network failure.

- [ ] **Step 4: Run tests and build**

Run: `cd ios/FuzzCode && swift test --filter GitHubConnectorTests && xcodebuild -project FuzzCode.xcodeproj -scheme FuzzCode -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: storage/credential tests and app build pass.

- [ ] **Step 5: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeUI/Views/GitHub/GitHubConnectorView.swift ios/FuzzCode/Sources/FuzzCodeCore/GitHub/GitHubModels.swift ios/FuzzCode/Sources/FuzzCodeCore/Persistence/StorageService.swift ios/FuzzCode/Tests/FuzzCodeTests/GitHubConnectorTests.swift
git commit -m "feat: persist GitHub credentials securely"
```

### Task 3: Load repositories and pull requests accurately

**Files:**
- Modify: `ios/FuzzCode/Sources/FuzzCodeUI/Views/GitHub/GitHubConnectorView.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/GitHub/GitHubClient.swift`
- Modify: `ios/FuzzCode/Tests/FuzzCodeTests/GitHubConnectorTests.swift`

**Interfaces:**
- `GitHubClient.fetchRepositories(perPage:)` returns API-decoded accessible repositories.
- `GitHubClient.fetchPullRequests(owner:repo:)` returns real PR metadata for the selected repository.

- [ ] **Step 1: Add repository selection and pull-request load tests**

Test loading repos after valid authentication and requesting pull requests for the selected `owner/repo`; assert decoded PR values are displayed data, not constants.

- [ ] **Step 2: Connect UI selection to API calls**

Make repository rows selectable and persist `config.selectedRepo`. When Pull Requests is selected, require a selected repository and load its pull requests asynchronously. Display loading, empty, and error states. Do not leave a tab that renders an empty list without explaining that a repository must be selected.

- [ ] **Step 3: Add refresh and error handling**

Use a task or explicit refresh action to reload the selected collection; cancel stale requests on repository changes. Preserve `errorMessage` in the screen and clear it only when a new request starts or succeeds.

- [ ] **Step 4: Run tests and build**

Run: `cd ios/FuzzCode && swift test --filter GitHubConnectorTests && xcodebuild -project FuzzCode.xcodeproj -scheme FuzzCode -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: tests/build pass and the UI displays real per-repository PR data.

- [ ] **Step 5: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeUI/Views/GitHub/GitHubConnectorView.swift ios/FuzzCode/Sources/FuzzCodeCore/GitHub/GitHubClient.swift ios/FuzzCode/Tests/FuzzCodeTests/GitHubConnectorTests.swift
git commit -m "feat: browse GitHub pull requests"
```

### Task 4: Add explicit repository context to chat

**Files:**
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/GitHub/GitHubClient.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/Models/ProviderModels.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeUI/Views/Chat/ChatView.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeUI/Views/RAG/RAGPromptSheet.swift`
- Modify: `ios/FuzzCode/Tests/FuzzCodeTests/GitHubConnectorTests.swift`
- Modify: `ios/FuzzCode/Tests/FuzzCodeTests/ConversationPersistenceTests.swift`

**Interfaces:**
- `GitHubClient.fetchRepositoryReadme(owner:repo:) async throws -> String` returns decoded README text from the contents API.
- `ChatConversation` has optional `includeGitHubRepositoryContext: Bool?` and `selectedGitHubRepository: GitHubRepo?`; absent values decode as false/nil.

- [ ] **Step 1: Test README decoding and privacy default**

Mock contents API base64 response and assert decoded Markdown matches exactly. Test old conversations without GitHub selection decode with repository context disabled.

- [ ] **Step 2: Implement README fetch with authenticated API**

Request the selected repository's README endpoint using the centralized authenticated request helper. Decode GitHub's base64 content safely and throw clear API/content errors.

- [ ] **Step 3: Add explicit per-conversation selection control**

Add a GitHub context section to the project-context sheet. It defaults off and lets the user choose one accessible repository; when turned on, show which repository's README may be sent. Persist only the selected repository metadata and opt-in flag on the conversation.

- [ ] **Step 4: Add context only at send time after explicit opt-in**

When the user opts in, fetch the chosen README, wrap it as an explicitly labeled repository source, and pass it into the existing RAG/context prompt composition. When off, make no GitHub content request and append no GitHub text. Surface fetch failures without silently falling back to stale README content.

- [ ] **Step 5: Verify opt-in and request behavior**

Run: `cd ios/FuzzCode && swift test --filter 'GitHubConnectorTests|ConversationPersistenceTests' && xcodebuild -project FuzzCode.xcodeproj -scheme FuzzCode -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: tests/build pass; disabled context results in zero README request and no prompt inclusion.

- [ ] **Step 6: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeCore/GitHub/GitHubClient.swift ios/FuzzCode/Sources/FuzzCodeCore/Models/ProviderModels.swift ios/FuzzCode/Sources/FuzzCodeUI/Views/Chat/ChatView.swift ios/FuzzCode/Sources/FuzzCodeUI/Views/RAG/RAGPromptSheet.swift ios/FuzzCode/Tests/FuzzCodeTests/GitHubConnectorTests.swift ios/FuzzCode/Tests/FuzzCodeTests/ConversationPersistenceTests.swift
git commit -m "feat: add opt-in GitHub chat context"
```
