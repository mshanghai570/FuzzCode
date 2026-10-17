# Provider-Neutral Skills Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users maintain persistent `SKILL.md` instructions in Settings and explicitly choose which skills to include in each conversation, regardless of model provider.

**Architecture:** Store skills as provider-neutral instruction documents in a core model and `StorageService`. Persist selected skill IDs on each conversation and append only selected skill content to the system prompt alongside existing project context.

**Tech Stack:** Swift 5.9+, SwiftUI, Foundation, XCTest, iOS 17.

**Spec:** `docs/superpowers/specs/2026-10-11-native-integrations-design.md`

**Prerequisite:** Complete `docs/superpowers/plans/2026-10-11-native-settings-integrations.md` first; this plan adds the Skills route to its `IntegrationsView`.

## Global Constraints

- The iOS deployment target is iOS 17.0.
- FuzzCode uses pure native iOS frameworks and has zero third-party runtime dependencies.
- Skills are opt-in per conversation and provider-neutral prompt instructions, not executable plugins.
- Saved skills persist until edited or deleted.
- Never include unselected skills in a model request.

---

### Task 1: Define and persist skill documents

**Files:**
- Create: `ios/FuzzCode/Sources/FuzzCodeCore/Models/AgentSkill.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/Persistence/StorageService.swift`
- Create: `ios/FuzzCode/Tests/FuzzCodeTests/AgentSkillPersistenceTests.swift`

**Interfaces:**
- `AgentSkill: Identifiable, Codable, Equatable, Sendable` has `id: UUID`, `name: String`, `content: String`, and `updatedAt: Date`.
- `StorageService.saveSkills(_ skills: [AgentSkill]) throws` and `loadSkills() throws -> [AgentSkill]` persist to `skills.json`.
- The storage directory injection from the Settings integrations plan is used for isolated tests. A missing file returns `[]`; malformed data and write failures throw.

- [ ] **Step 1: Write model and storage tests**

Using a temporary directory, test skill JSON round-trip, preservation of literal `SKILL.md` content including Markdown front matter and code fences, empty-list behavior when no file exists, and thrown decode/write errors.

- [ ] **Step 2: Run the focused test**

Run: `cd ios/FuzzCode && swift test --filter AgentSkillPersistenceTests`
Expected: compilation fails because `AgentSkill` and its storage accessors are not defined.

- [ ] **Step 3: Implement the Codable model and accessors**

Create the four-field model with a public initializer. Add typed `saveSkills`/`loadSkills` accessors for `skills.json`; return `[]` only when the file is absent and propagate decode/write errors.

- [ ] **Step 4: Run the focused test**

Run: `cd ios/FuzzCode && swift test --filter AgentSkillPersistenceTests`
Expected: all serialization and default tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeCore/Models/AgentSkill.swift ios/FuzzCode/Sources/FuzzCodeCore/Persistence/StorageService.swift ios/FuzzCode/Tests/FuzzCodeTests/AgentSkillPersistenceTests.swift
git commit -m "feat: persist provider-neutral skills"
```

### Task 2: Build the Settings skills library

**Files:**
- Create: `ios/FuzzCode/Sources/FuzzCodeUI/Views/Settings/SkillsLibraryView.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeUI/Views/Settings/IntegrationsView.swift`
- Test: `ios/FuzzCode/Tests/FuzzCodeTests/AgentSkillPersistenceTests.swift`

**Interfaces:**
- `SkillsLibraryView` loads and saves `[AgentSkill]` through `StorageService`.
- Users can create, edit, and delete one named skill document; the editor accepts raw Markdown content representing `SKILL.md`.
- Failed loads/saves show an error and do not silently discard the user's current edits.

- [ ] **Step 1: Add an Integrations route**

Add a “Skills” row in `IntegrationsView` that presents `SkillsLibraryView`. Keep the library in the existing Settings → Integrations area rather than adding a second Settings entry.

- [ ] **Step 2: Implement list and editor state**

Display saved skill names, an add button, and swipe-to-delete. Present a sheet with a name text field and multiline Markdown editor. Save creates a UUID-backed skill or updates the existing skill's name/content and timestamp. Disable Save when the trimmed name or content is empty. Persist immediately after save and delete.

- [ ] **Step 3: Verify document preservation**

Add a round-trip test using content with front matter (`---`), headings, and fenced code. Confirm the exact content string is preserved without parsing or rewriting.

- [ ] **Step 4: Run tests and build**

Run: `cd ios/FuzzCode && swift test --filter AgentSkillPersistenceTests && xcodebuild -project FuzzCode.xcodeproj -scheme FuzzCode -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: tests and app build pass.

- [ ] **Step 5: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeUI/Views/Settings/IntegrationsView.swift ios/FuzzCode/Sources/FuzzCodeUI/Views/Settings/SkillsLibraryView.swift ios/FuzzCode/Tests/FuzzCodeTests/AgentSkillPersistenceTests.swift
git commit -m "feat: manage skills in settings"
```

### Task 3: Persist opt-in skill selection per conversation

**Files:**
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/Models/ProviderModels.swift`
- Modify: `ios/FuzzCode/Tests/FuzzCodeTests/ConversationPersistenceTests.swift`

**Interfaces:**
- Add optional `selectedSkillIDs: [UUID]?` to `ChatConversation`; nil decodes older conversation files as no selected skills.

- [ ] **Step 1: Write backward-compatibility tests**

Extend `testExistingConversationDecodesWithoutContextFields` to remove `selectedSkillIDs` as well as the existing optional context fields. Add a round-trip assertion for two selected IDs.

- [ ] **Step 2: Run conversation tests**

Run: `cd ios/FuzzCode && swift test --filter ConversationPersistenceTests`
Expected: the new property assertion fails until implemented.

- [ ] **Step 3: Add the optional property**

Add `selectedSkillIDs: [UUID]?` to `ChatConversation` and initialize it to nil. Keep existing decoding compatibility by making the stored property optional.

- [ ] **Step 4: Run conversation tests**

Run: `cd ios/FuzzCode && swift test --filter ConversationPersistenceTests`
Expected: legacy decode and new selection round-trip pass.

- [ ] **Step 5: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeCore/Models/ProviderModels.swift ios/FuzzCode/Tests/FuzzCodeTests/ConversationPersistenceTests.swift
git commit -m "feat: save conversation skill selection"
```

### Task 4: Compose selected skills into every provider request

**Files:**
- Modify: `ios/FuzzCode/Sources/FuzzCodeCore/RAG/RAGService.swift`
- Create: `ios/FuzzCode/Tests/FuzzCodeTests/SkillPromptTests.swift`

**Interfaces:**
- Extend `buildSystemPrompt(basePrompt:ragContext:skillContents:)` with `skillContents: [(name: String, content: String)] = []`.
- Selected skill content is appended as a clearly delimited `<selected_skills>` section. Existing callers that omit `skillContents` retain their output.

- [ ] **Step 1: Write prompt composition tests**

Test that no selected skills adds no skills section, selected skills include the exact name and body, and two selected skills are both included. Also assert existing base prompt and RAG context are preserved.

- [ ] **Step 2: Run the focused tests**

Run: `cd ios/FuzzCode && swift test --filter SkillPromptTests`
Expected: compilation fails because the extended method does not exist.

- [ ] **Step 3: Implement prompt composition**

Add the defaulted parameter and append:

```swift
if !skillContents.isEmpty {
    let entries = skillContents.map { "[Skill: \($0.name)]\n\($0.content)" }
    parts.append("<selected_skills>\n\(entries.joined(separator: "\n\n"))\n</selected_skills>")
}
```

- [ ] **Step 4: Run prompt and RAG tests**

Run: `cd ios/FuzzCode && swift test --filter SkillPromptTests && swift test --filter RAGServiceTests`
Expected: selected skill tests and existing project-context tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeCore/RAG/RAGService.swift ios/FuzzCode/Tests/FuzzCodeTests/SkillPromptTests.swift
git commit -m "feat: compose selected skills into prompts"
```

### Task 5: Select skills per chat and prove provider-neutral use

**Files:**
- Modify: `ios/FuzzCode/Sources/FuzzCodeUI/Views/Chat/ChatView.swift`
- Modify: `ios/FuzzCode/Sources/FuzzCodeUI/Views/RAG/RAGPromptSheet.swift`
- Modify: `ios/FuzzCode/Tests/FuzzCodeTests/ConversationPersistenceTests.swift`

**Interfaces:**
- `ChatView` loads the global skill library and passes selected skill documents to `RAGService.buildSystemPrompt`.
- The project-context sheet gains a Skills selection section and binds selections by skill UUID. It appears before requests are composed and works for every configured provider using `OpenAIClient`.

- [ ] **Step 1: Add chat selection state and restoration**

Load saved skills in `setupInitialState`. On `selectConversation`, restore `selectedSkillIDs ?? []`; on `startNewConversation`, start with no selected skills. Save selections through the existing conversation save path.

- [ ] **Step 2: Add explicit skill selection UI**

Extend `RAGPromptSheet` with bindings for available skills and selected IDs. Render one toggle per saved skill with name and preview. Ensure selecting/deselecting affects only the current conversation.

- [ ] **Step 3: Pass selected documents into prompt composition**

In `sendMessage`, resolve IDs against the saved skill library, then pass the resulting `(name, content)` values to `buildSystemPrompt`. Unknown/deleted IDs are ignored and removed when next saving the conversation. Do not attach the global library or unselected documents.

- [ ] **Step 4: Verify app and relevant tests**

Run: `cd ios/FuzzCode && swift test --filter 'SkillPromptTests|ConversationPersistenceTests' && xcodebuild -project FuzzCode.xcodeproj -scheme FuzzCode -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build`
Expected: both test suites and the app build pass; the same composed system message is used irrespective of selected OpenAI-compatible provider.

- [ ] **Step 5: Commit**

```bash
git add ios/FuzzCode/Sources/FuzzCodeUI/Views/Chat/ChatView.swift ios/FuzzCode/Sources/FuzzCodeUI/Views/RAG/RAGPromptSheet.swift ios/FuzzCode/Tests/FuzzCodeTests/ConversationPersistenceTests.swift
git commit -m "feat: select skills per conversation"
```
