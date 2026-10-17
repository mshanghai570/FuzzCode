# FUZZCODE — Native iOS AI Coding Agent Control Center

> **Tagline:** A little distortion. A lot of control.  
> Inspired by [CodeAgent Mobile](https://www.codeagent-mobile.com/).

FuzzCode is a native iOS application built with Swift and SwiftUI that turns your iPhone into a command center for AI coding agents and custom model providers.

---

## ⚡ Key Capabilities

1. **Custom OpenAI-Compatible Endpoints**
   - Connect to OpenAI, Groq, Kilo, Ollama, LM Studio, vLLM, or self-hosted proxies.
   - Streaming token responses over Server-Sent Events (SSE).
   - Dynamic model discovery via `GET /models`.
   - URL normalization for standard `/v1` paths.
   - Non-HTTPS allowed only through explicit local development toggles.

2. **Built-in AI Chat**
   - Live token-by-token streaming with cancellation controls.
   - Selectable response text and one-tap copy.
   - Conversation history persistence.

3. **OpenCode Coding Agent Runtime Integration**
   - Treats OpenCode as a true remote runtime (not a mere chat endpoint).
   - Secure host pairing via authenticated HTTP and WebSocket transports.
   - Real-time tool execution tracking (`bash`, `file_edit`, `ripgrep`).
   - Interactive security gate: Explicitly allow or deny risky bash/filesystem actions.
   - Live Git status and syntax-highlighted diff inspection (unified and split modes).

4. **Rock & Fuzz Pedal Sensory Aesthetic**
   - Deep charcoal palette (`#0B0C0E`), acid green accents (`#22C55E`), and electric purple highlights (`#8B5CF6`).
   - Stompbox bypass feedback and rotary gain dial haptics (`UIImpactFeedbackGenerator`).

5. **Credential Storage**
   - All API keys and host pairing tokens are stored exclusively in the native iOS Keychain (`kSecClassGenericPassword`).
   - Credentials are automatically redacted in logs, UI, and exported diagnostics.

---

## 🛠 Project Structure

```text
FuzzCode/
├── Package.swift                     # Swift Package Manifest (iOS 17+)
├── Sources/
│   ├── FuzzCodeCore/                 # Core Architecture & Networking
│   │   ├── Architecture/             # ModelProvider, CodingAgent, ExecutionHost protocols
│   │   ├── Models/                   # Provider, Agent, Session, Diff, and Permission data models
│   │   ├── Networking/               # OpenAIClient with URL normalization & SSE streaming
│   │   ├── OpenCode/                 # OpenCodeClient with tool streaming & permission handling
│   │   ├── Persistence/              # StorageService with atomic JSON serialization
│   │   └── Security/                 # KeychainService with safe redaction
│   └── FuzzCodeUI/                   # Native SwiftUI Interface
│       ├── App/                      # FuzzCodeApp (@main entry point) & MainTabView
│       ├── Theme/                    # FuzzTheme, FuzzKnobView & Stompbox feedback
│       └── Views/                    # HomeView, ChatView, AgentsView, ProvidersView, CodeDiffView, SettingsView
└── Tests/
    └── FuzzCodeTests/                # Automated XCTest Suites
        ├── EndpointNormalizationTests.swift
        ├── SSEStreamingParserTests.swift
        ├── OpenCodeCapabilityTests.swift
        └── KeychainSecurityTests.swift
```

---

## 🚀 Building & Running

### Requirements
- macOS 14+ with Xcode 15 or 16+
- iOS 17.0+ deployment target (optimized for iPhone 15/16 Pro)
- Swift 5.9+

### Open and run the iOS app
1. Open `FuzzCode.xcodeproj` in this directory.
2. Select the **FuzzCode** scheme and an iPhone simulator.
3. Press Cmd + R. For a physical iPhone, choose your signing team under Signing & Capabilities.

The checked-in project contains an application target, a core framework, and unit tests. `Package.swift` remains available for consumers of the core and UI libraries.

To regenerate the Xcode project after adding files or changing targets (requires [XcodeGen](https://github.com/yonaskolb/XcodeGen)):

```sh
xcodegen generate --spec project.yml
```

Build and test from this directory:

```sh
xcodebuild -project FuzzCode.xcodeproj -scheme FuzzCode -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project FuzzCode.xcodeproj -scheme FuzzCodeCoreTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

### Conversation project context
In Chat, open **Project context** in the toolbar to edit the system prompt, add pasted documents or code, and tune retrieval. Context is saved per conversation and restored from history. Matching source names appear above the composer after a request. Retrieval is local keyword matching, not embedding-based semantic search; only enabled sources are considered, with a configurable approximate token budget.

### Current integration boundaries
- Chat requires a working OpenAI-compatible endpoint and API credentials, configured under Providers.
- The existing OpenCode client expects a custom `/api/v1` companion API; compatibility with a stock OpenCode server still needs validation.
- MCP and GitHub connector views and services are scaffolding. MCP needs proper initialization, discovery, session handling, authenticated calls, and tool approvals before agent use. They are not yet wired into agent execution.
- ChatGPT subscription settings are not a working OAuth integration. Use an API key with a compatible provider.
- Rich Markdown/code rendering, repository editing, app icons, and physical-device accessibility checks remain follow-up work.

### Latest local verification
The simulator app build passed, and all 28 core tests passed using a temporary core-only macOS package. The installed simulator was not available to Xcode's destination discovery; direct simulator installation timed out. Visual QA, device accessibility checks, and live API/agent integration tests are still pending.
