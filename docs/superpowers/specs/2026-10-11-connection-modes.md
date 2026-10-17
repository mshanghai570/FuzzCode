# Three FuzzCode connection modes

Extend existing native integrations, preserving stored providers, host records, chat/MCP/RAG/skills, and the legacy OpenCode companion API. No third-party dependencies. iOS 17 minimum. Host configuration is optional and appears only for remote agents.

## Direct providers
Use AIProvider adapters for OpenAI, Anthropic, Gemini, OpenRouter, Groq, and custom OpenAI-compatible servers. Keep keys exclusively in Keychain, normalize native routes, use Gemini key headers, sanitize network/server errors, discover models, test connections, and stream text. Implement native tool requests for Anthropic and Gemini as well as existing compatible providers. Preserve existing custom headers and endpoint settings.

## Remote agents
Persist agent identity and protocol independently. Existing records default to the legacy OpenCode companion. New connections choose stock OpenCode HTTP, Codex app-server WebSocket, or ACP v1 over a WebSocket bridge (Claude Code/custom agents). Do not route all agents through OpenCode or invent native Claude HTTP APIs. Authenticate transport using Keychain credentials and ordinary system TLS validation. Cleartext requires explicit local development opt-in. Only mark connected after a successful protocol handshake. Negotiate capabilities, create actual remote sessions, stream events, approve permission requests, cancel turns, and resume sessions. Bonjour advertises only known service types; absence of discovery retains manual URL pairing. QR imports validated connection metadata with fresh local identity, never another device's Keychain reference; camera scanning has a paste fallback. Codex's upstream WebSocket transport remains experimental and requires a secured remote runtime.

## Native agent
Keep execution inside app-owned workspace directories. Use stable engine/session identities and selected provider IDs for restoration. Provide bounded file inventory/read/write and reviewed patches, rejecting symlink escapes and invalid/multi-file hunks without partial mutation. Persist user and assistant history, tool events and statuses. Cancellation must not authorize pending writes. Add real change previews against workspace baselines and GitHub REST import/browsing without git or shell binaries. Permission UI shows the proposed content/patch before approving mutation.

## Verification and status
Regression tests separately cover provider requests/credential redaction, remote routing/handshakes/session events/permission outcomes/QR validation, and sandbox/patch/native persistence/cancellation. Build the full iOS app. Report tested implementations separately from live-runtime, LAN, camera, device, and upstream experimental transport validation.
