# Codex ChatGPT Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give users a truthful Codex authentication option and implement ChatGPT sign-in only if OpenAI documents a supported authorization flow for third-party native iOS clients.

**Architecture:** Verify official OpenAI documentation and policy before changing authentication behavior. If a supported flow exists, use `ASWebAuthenticationSession`/system browser authorization and Keychain-only token storage; if not, clearly explain that ChatGPT subscription sign-in is unavailable to this client and retain API-key authentication.

**Tech Stack:** Swift 5.9+, SwiftUI, AuthenticationServices, Security/Keychain, XCTest, iOS 17.

**Spec:** `docs/superpowers/specs/2026-10-11-native-integrations-design.md`

## Global Constraints

- The iOS deployment target is iOS 17.0.
- FuzzCode uses pure native iOS frameworks and has zero third-party runtime dependencies.
- Do not collect a ChatGPT password or embed private OAuth client secrets in the app.
- Store any authorized credentials only in Keychain.
- Do not advertise or send unsupported subscription-token headers as a login implementation.

---

### Task 1: Verify official authorization support before implementation

**Files:**
- Read: OpenAI's current official authentication, OAuth, Codex, and third-party application documentation.
- Modify: `docs/superpowers/specs/2026-10-11-native-integrations-design.md` only if official evidence changes the agreed constraint.
- Test: no code test; this is a prerequisite evidence review.

**Interfaces:**
- The research result is a recorded decision: supported native third-party OAuth flow with official endpoint/scopes/PKCE/redirect requirements, or no supported public flow.

- [ ] **Step 1: Check current first-party documentation**

Review only official OpenAI developer/help documentation for ChatGPT subscription authentication in third-party clients, Codex authentication API availability, OAuth client registration requirements, native-app redirect support, token refresh/revocation, and applicable policy. Do not treat community reverse-engineering, copied CLI credentials, or undocumented endpoints as support.

- [ ] **Step 2: Record evidence and choose the implementation branch**

If all required details are documented for third-party native clients, record their official URLs, retrieval date, flow, scopes, and restrictions in the code-review/PR description and continue to Task 2. If any mandatory item is absent or terms prohibit this use, continue to Task 4 and do not implement OAuth.

- [ ] **Step 3: Confirm the branch with a focused build baseline**

Run: `cd ios/FuzzCode && xcodebuild -project FuzzCode.xcodeproj -scheme FuzzCode -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: baseline build passes before authentication changes.

### Task 2: Implement the documented native authorization flow (only if Task 1 confirms support)

**Files:**
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/Models/ProviderModels.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/Networking/OpenAIClient.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/Security/KeychainService.swift` only if a missing secure operation is required
- Create: `ios/FuzzCode/Sources/FuzzCodeCore/Networking/CodexAuthorizationService.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeUI/Views/Providers/ProvidersView.swift`
- Create: `ios/FuzzCode/Tests/FuzzCodeTests/CodexAuthorizationTests.swift`

**Interfaces:**
- `CodexAuthorizationService` exposes `authorize() async throws -> CodexCredentialReference`, `refreshIfNeeded(_:) async throws -> CodexCredentialReference`, and `signOut(_:)`.
- Provider persistence stores only a Keychain credential reference and non-secret account metadata; access/refresh tokens remain in Keychain.

- [ ] **Step 1: Add auth flow tests from official requirements**

Use an injected authorization transport/session to test PKCE verifier/challenge generation, exact documented redirect/state validation, denial and callback mismatch, token exchange errors, refresh, and Keychain-only token persistence. Test strings and endpoints must be taken from the verified official specification, not invented.

- [ ] **Step 2: Implement system-browser authorization**

Use `ASWebAuthenticationSession` with the documented authorization endpoint, PKCE, redirect URI, and state/nonce parameters. Do not embed a confidential client secret. Validate callback state before exchanging the authorization code.

- [ ] **Step 3: Store credentials and handle expiry**

Persist access/refresh tokens using Keychain references only. Refresh only when documented and needed; on revocation/refresh failure surface reauthentication and never fall back to fabricated subscription headers.

- [ ] **Step 4: Add visible Codex sign-in and sign-out UI**

Add a provider auth choice that clearly distinguishes supported Codex sign-in from API-key auth. Show account/status metadata and a sign-out action. Do not ask for a ChatGPT password or copy credentials from another app.

- [ ] **Step 5: Run focused auth tests and app build**

Run: `cd ios/FuzzCode && swift test --filter CodexAuthorizationTests && xcodebuild -project FuzzCode.xcodeproj -scheme FuzzCode -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: auth tests and build pass without live credentials.

- [ ] **Step 6: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeCore/Models/ProviderModels.swift ios/FuzzCode/Sources/FuzzCodeCore/Networking/OpenAIClient.swift ios/FuzzCode/Sources/FuzzCodeCore/Networking/CodexAuthorizationService.swift ios/FuzzCode/Sources/FuzzCodeUI/Views/Providers/ProvidersView.swift ios/FuzzCode/Tests/FuzzCodeTests/CodexAuthorizationTests.swift
git commit -m "feat: add supported Codex sign-in"
```

### Task 3: Use authorized Codex credentials only as documented (only if Task 1 confirms support)

**Files:**
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/Networking/OpenAIClient.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/Models/ProviderModels.swift`
- Modify: `ios/FuzzCode/Tests/FuzzCodeTests/CodexAuthorizationTests.swift`

**Interfaces:**
- Authentication header and endpoint behavior follow the verified official flow exactly; no `X-OpenAI-Subscription` or beta marker is used unless the official documentation explicitly requires it.

- [ ] **Step 1: Add authenticated request tests**

Assert authorized requests obtain credentials from Keychain and use only official documented headers/routes. Assert serialized provider configuration excludes access/refresh token strings.

- [ ] **Step 2: Wire provider request authorization**

Update `OpenAIClient` to retrieve valid credentials by Keychain reference and apply only the documented authorization mechanism. Preserve API-key behavior for other providers and explicit API-key fallback.

- [ ] **Step 3: Verify with focused tests/build**

Run: `cd ios/FuzzCode && swift test --filter CodexAuthorizationTests && xcodebuild -project FuzzCode.xcodeproj -scheme FuzzCode -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: tests/build pass and API-key providers remain unchanged.

- [ ] **Step 4: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeCore/Networking/OpenAIClient.swift ios/FuzzCode/Sources/FuzzCodeCore/Models/ProviderModels.swift ios/FuzzCode/Tests/FuzzCodeTests/CodexAuthorizationTests.swift
git commit -m "fix: use documented Codex authorization"
```

### Task 4: Explain unsupported ChatGPT subscription sign-in (if Task 1 does not confirm support)

**Files:**
- Modify: `ios/FuzzCode/Sources/FuzzCodeUI/Views/Providers/ProvidersView.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/Models/ProviderModels.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/Networking/OpenAIClient.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/Persistence/StorageService.swift`
- Create: `ios/FuzzCode/Tests/FuzzCodeTests/CodexAuthorizationTests.swift`

**Interfaces:**
- The provider screen continues to support API-key authentication. Any existing ChatGPT-subscription pseudo-auth option is removed or disabled and replaced with an explicit explanation that no supported third-party native sign-in flow is available.

- [ ] **Step 1: Add tests preventing pseudo-auth**

In `CodexAuthorizationTests`, assert unsupported subscription mode cannot construct an authenticated request and that no ChatGPT password prompt, invented subscription header, or token copied from another application is used.

- [ ] **Step 2: Migrate legacy credentials without breaking provider decoding**

Keep the legacy `chatgpt_subscription` enum case and `ChatGPTSession` decoding shape long enough to decode existing `providers.json` files. During `StorageService.loadProviders()`, migrate legacy subscription-auth providers to `.apiKey`, discard `chatgptSession` (including its plaintext access/refresh tokens), and rewrite the sanitized provider file. Remove unsupported `X-OpenAI-Subscription`/`OpenAI-Beta` header injection. Add tests proving one legacy provider does not make the rest of the provider file unreadable, the migrated file contains no legacy token, and API-key providers remain unchanged.

- [ ] **Step 3: Add clear UI explanation**

Replace the sign-in action with a disabled/explanatory state that says ChatGPT subscription login is not available in this client, and directs users to configure an API key with a supported provider. The view must not ask the user to enter a password or paste session tokens.

- [ ] **Step 4: Run focused tests and build**

Run: `cd ios/FuzzCode && swift test --filter 'OpenCodeCapabilityTests|CodexAuthorizationTests' && xcodebuild -project FuzzCode.xcodeproj -scheme FuzzCode -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: unsupported flow cannot send credentials and API-key configuration still builds and passes.

- [ ] **Step 5: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeUI/Views/Providers/ProvidersView.swift ios/FuzzCode/Sources/FuzzCodeCore/Models/ProviderModels.swift ios/FuzzCode/Sources/FuzzCodeCore/Networking/OpenAIClient.swift ios/FuzzCode/Sources/FuzzCodeCore/Persistence/StorageService.swift ios/FuzzCode/Tests/FuzzCodeTests/CodexAuthorizationTests.swift
git commit -m "fix: remove unsupported ChatGPT sign-in"
```
