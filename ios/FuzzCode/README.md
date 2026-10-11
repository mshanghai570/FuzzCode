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
   - Strict URL normalization preventing duplicate `/v1` paths.
   - Non-HTTPS allowed only through explicit local development toggles.

2. **Built-in AI Chat**
   - Live token-by-token streaming with cancellation controls.
   - Markdown formatting with syntax-highlighted code blocks & one-tap copy.
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

5. **Enterprise Security**
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

### Open in Xcode
1. Open Xcode and select `File > Open...`
2. Select the `Package.swift` file in this directory.
3. Select an iOS 17+ Simulator or your connected iPhone.
4. Press `Cmd + R` to build and run.
