# Connection Modes Implementation Plan

> Execute the independently scoped provider, native-engine, and remote/UI tasks with regression tests and review between integration steps.

**Goal:** Implement optional direct providers, protocol-specific remote agents, and a sandboxed native FuzzCode agent.
**Architecture:** Preserve existing AIProvider/AgentConnection interfaces and legacy records. Add explicit remote protocol metadata and typed bidirectional JSON-RPC transport; adapters own protocol wire formats. Native workspaces use validated file access, persistent identity, and provider-neutral tools.
**Tech Stack:** Swift, Foundation/URLSession, SwiftUI, Security Keychain, Network Bonjour, AVFoundation; no added packages.
**Spec:** docs/superpowers/specs/2026-10-11-connection-modes.md

## Global constraints
- iOS 17 minimum; preserve custom providers, legacy companion pairing, chat/MCP/RAG/skills and GitHub settings.
- Keys in Keychain; no secrets in errors, logs, persisted connection metadata, or QR exports.
- No shell, macOS binaries, or unrestricted device filesystem.

## Provider increment
Files: Providers/AIProvider.swift, Providers/ProviderKind.swift, Networking/OpenAIClient.swift, provider tests.
- [ ] Add regressions showing credential injection, query-key removal, error redaction, and native tools/history formats.
- [ ] Implement and verify adapter request/response paths with injected networking.
- [ ] Keep protocol errors explicit; model choice supports discovery and free-form IDs.

## Native increment
Files: Agents/WorkspaceManager.swift, Agents/NativeAgentEngine.swift, Agents/AgentTool.swift, native tests.
- [ ] Reproduce symlink escapes, incorrect hunk coordinates, lost user history, denied tool success and cancellation bugs.
- [ ] Reject unsafe/invalid patches before writes; expose preview/change baselines.
- [ ] Preserve stable engine/provider identity and cancellation; persist history and tool statuses.
- [ ] Verify approved and denied edits, cancelled writes, resumed sessions and bounded tool loops.

## Remote increment
Files: Models/AgentModels.swift; Agents/RemoteConnectionConfig.swift, JSONRPCTransport.swift, ACPAgentConnection.swift, CodexAgentConnection.swift, OpenCodeHTTPConnection.swift, LANDiscovery.swift; remote tests.
- [ ] Add optional kind/protocol/security/session metadata preserving old decoding.
- [ ] Implement authenticated WebSocket RPC with requests, notifications, server permissions and cancellation.
- [ ] Implement ACP initialization/new/load/prompt/cancel and negotiated capability checks.
- [ ] Implement Codex initialize/initialized/thread/turn flows independently of ACP.
- [ ] Implement stock OpenCode native HTTP/event routes independently of legacy companion.
- [ ] Test protocol routing, frame/event translation, auth and permissions; validate QR metadata.

## UI and GitHub increment
Files: Views/Agents (selection, pairing, camera scanner, native setup, console), provider configuration, Agents/GitHubWorkspaceImporter.swift, project.yml.
- [ ] Always expose all three connection choices; remote-only pairing fields.
- [ ] Test before saving paired hosts, store secrets securely, discover supported LAN services and scan/paste QR.
- [ ] Select model/provider and existing or new native workspace; import GitHub reference into sandbox.
- [ ] Show real sessions/capabilities/tools/previews/errors and cancel permissions safely.
- [ ] Verify full test suite and iOS app build; document experimental/runtime requirements.
