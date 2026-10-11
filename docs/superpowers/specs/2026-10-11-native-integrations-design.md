# Native Integrations Design

## Goal

Make the native FuzzCode iOS app's MCP, GitHub, skills, and Codex/ChatGPT integration discoverable and useful without claiming capabilities that are not actually connected. Keep provider inference, agent execution, and remote execution boundaries intact.

## User-facing behavior

- Settings provides entry points to manage MCP servers, GitHub, and a persistent skills library. Existing connector views should be reused where possible.
- MCP server configuration persists across launches. A successful handshake discovers actual tools and resources; failures remain visible as errors and must not appear as successful connections.
- During chat, enabled connected MCP servers can make their discovered tools available to the selected model when the provider supports tool calling. Before any MCP tool is executed, show the requested server, tool, and arguments and require explicit user approval. Denial prevents execution. Tool results and errors are shown in the conversation. Providers without compatible tool calling continue ordinary chat without MCP tools.
- GitHub uses the existing connector and client, with credentials stored in Keychain. Connected users can browse their repositories and pull requests. Repository context is not silently injected into model prompts; adding it to chat is a separate explicit user action.
- Skills are manually added, edited, and removed in Settings. Each skill is stored as a title and `SKILL.md` content, persists locally across launches, and is available for any configured model provider. Skills are opt-in per conversation; only selected skill content is included in that conversation's system context. No automatic matching or provider-specific skill execution is implied.
- Codex sign-in is a separate provider authentication option. It must use an official supported authorization flow and store tokens in Keychain. Do not collect a ChatGPT password or present an unsupported subscription-token workaround as official login. If no supported public flow is available for this iOS use case, show that limitation and keep API-key authentication available.

## Architecture and data flow

Add a Settings integration hub that presents MCP, GitHub, and Skills management. It owns or loads persisted integration state and opens focused management screens. Keep each connector's networking in its core client/service; SwiftUI views handle configuration, status, and user approval.

Persist non-secret MCP server configuration, discovered metadata, GitHub profile metadata, and skill content through `StorageService`. Store GitHub credentials and any supported Codex OAuth credentials only in `KeychainService`; persisted models contain Keychain lookup references, not token values.

For MCP-enabled chat, the chat coordinator builds a request from the current conversation, selected skills, and discovered tools. A provider-neutral tool-calling interface translates supported provider responses into pending tool requests. The UI pauses for approval, invokes `MCPClient.callTool` only after approval, appends the result, and resumes the model turn with the tool result. Every hop is cancellable and surfaced in the chat transcript. MCP tools are not forwarded to remote agent runtimes in this phase.

GitHub connection state is independently manageable from MCP. Repository and pull request lists come from the existing GitHub client after authenticated requests. Selecting a repository for a conversation is explicit; only user-selected content is sent to a model.

## Staged delivery

1. **Surface and persist integrations:** Add Settings navigation; make MCP and GitHub management reachable; persist their non-secret state; implement the persistent skills manager and per-conversation skill selection/injection.
2. **Make MCP real in chat:** Correct protocol initialization/session handling and discovery; expose provider tool calling for supported APIs; implement approval, execution, result continuation, cancellation, and error display.
3. **Complete GitHub use:** Persist secure authentication, restore connection state safely, load repositories and pull requests, and offer explicit repository context selection for chat.
4. **Codex authentication:** Verify current official authorization support for native iOS. Implement only a supported flow; otherwise expose a clear unavailable state and preserve API-key use.

Each stage should build and test independently. Do not describe later-stage functionality as working until its stage is complete and verified.

## Security and error handling

- Never persist secrets outside Keychain or include them in diagnostics, logs, or exported configuration.
- Treat MCP tool execution and GitHub data access as external side effects. MCP calls require per-call approval; GitHub context requires explicit selection.
- Validate endpoint URLs and HTTP status codes. Surface transport, authorization, protocol, and tool errors; do not use cached or fabricated tools to claim a live connection.
- Redact credentials from displayed server configuration and error messages.
- ChatGPT/Codex sign-in must use the verified supported OAuth flow, secure token storage, and explicit authentication errors. No password collection.

## Validation

- Unit tests cover persistence and backward-compatible decoding of MCP, GitHub, and skill models; secret references remain separate from serialized state.
- MCP client tests use a controllable URL protocol/mock server to verify initialization, tool/resource discovery, session headers, tool invocation, HTTP/JSON-RPC errors, and no success fallback on failure.
- Chat tests verify selected skills are included for any provider, unselected skills are excluded, tool requests pause pending approval, denied calls never reach the server, approved calls append results and continue, and unsupported providers remain usable without tools.
- GitHub tests verify authenticated profile/repository/PR requests, persistence and disconnect behavior, and explicit-only context inclusion.
- Build the iOS app and run the targeted core/UI test suites after each stage.
- Codex authorization tests and UI are gated on confirming a supported official native flow.

## Assumptions and open constraint

“Skills for all providers” means provider-neutral `SKILL.md` instructions supplied as conversation context, not executable provider-specific plugins. Saved skills persist until edited or deleted, but each conversation must opt in to selected skills.

Official ChatGPT subscription authorization for Codex may not be available to third-party native clients. This must be checked against current official documentation before implementing or advertising that sign-in path.
