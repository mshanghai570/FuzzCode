# FuzzCode Architecture

FuzzCode enforces a clean tripartite architectural separation:

```
[ Model Providers ]  <-- Independent Inference (OpenAI, Groq, Kilo, Ollama)
        |
[ Coding Agents ]    <-- Autonomous Dev Loop (OpenCode, Sessions, Tools, Diffs)
        |
[ Execution Hosts ]  <-- Physical Remote Runtimes (MacBook, Linux Server, Cloud)
```

## 1. Protocols & Boundaries
- `ModelProviderProtocol`: Implemented by `OpenAIClient`. Supplies raw token completions and model catalog discovery.
- `CodingAgentProtocol`: Implemented by `OpenCodeClient`. Supplies session lifecycle, tool execution event streams, git diffs, and permission gate resolution.
- `ExecutionHostProtocol`: Manages machine transport, network pairing, and health checks.

## 2. Security Invariants
- No CLI binaries are executed on iOS. The iPhone serves as an authenticated control surface.
- All secrets are routed to `KeychainService`.
- No general-purpose unauthenticated shell is ever exposed.
- Dangerous agent tools (e.g. bash commands, file deletes) must pass through an interactive approval gate (`PermissionRequest`).

## 3. Extensibility
To add another coding agent (such as Aider or Claude Code):
1. Create a struct conforming to `CodingAgentProtocol`.
2. Implement `connect()`, `listSessions()`, `createSession()`, and `sendInstruction()`.
3. Register the agent in the `AgentsView` runtime registry.
