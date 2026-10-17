import SwiftUI
import FuzzCodeCore

public struct SkillsLibraryView: View {
    @State private var skills: [AgentSkill] = []
    @State private var hasLoadedSkills = false
    @State private var isLoading = false
    @State private var hasLocalChanges = false
    @State private var loadError: String?
    @State private var saveError: String?
    @State private var editorSkill: AgentSkill?
    @State private var isCreatingSkill = false
    @State private var skillPendingDeletion: AgentSkill?

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()

                List {
                    if let loadError {
                        Section {
                            storageError(
                                title: "Skills couldn't be loaded",
                                message: loadError,
                                buttonTitle: "Retry Load",
                                action: loadSkills
                            )
                        }
                        .listRowBackground(FuzzTheme.surface)
                    }

                    if let saveError {
                        Section {
                            storageError(
                                title: "Skill changes weren't saved; they remain available here",
                                message: saveError,
                                buttonTitle: "Retry Save",
                                action: retrySave
                            )
                        }
                        .listRowBackground(FuzzTheme.surface)
                    }

                    Section {
                        if isLoading && !hasLoadedSkills {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(FuzzTheme.acidGreen)
                                Text("Loading skills…")
                                    .foregroundStyle(FuzzTheme.textSecondary)
                            }
                            .accessibilityElement(children: .combine)
                        } else if hasLoadedSkills && skills.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("No skills saved")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(FuzzTheme.textPrimary)
                                Text("Add a Markdown skill document to keep reusable instructions here.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(FuzzTheme.textSecondary)
                            }
                            .padding(.vertical, 5)
                        } else {
                            ForEach(sortedSkills) { skill in
                                Button {
                                    editorSkill = skill
                                    isCreatingSkill = false
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(skill.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(FuzzTheme.textPrimary)
                                        Text(skill.content)
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(FuzzTheme.textSecondary)
                                            .lineLimit(2)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Skill: \(skill.name)")
                                .accessibilityValue("Markdown skill document")
                                .accessibilityHint("Opens this skill for editing")
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        skillPendingDeletion = skill
                                    } label: {
                                        Label("Delete \(skill.name)", systemImage: "trash")
                                    }
                                    .accessibilityLabel("Delete skill \(skill.name)")
                                }
                            }
                        }
                    } header: {
                        Text("Saved Skills")
                            .fontDesign(.monospaced)
                            .foregroundStyle(FuzzTheme.textSecondary)
                    }
                    .listRowBackground(FuzzTheme.surface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Skills")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorSkill = nil
                        isCreatingSkill = true
                    } label: {
                        Label("Add Skill", systemImage: "plus")
                            .foregroundStyle(FuzzTheme.acidGreen)
                    }
                    .accessibilityLabel("Add skill")
                    .disabled(!hasLoadedSkills)
                }
            }
            .onAppear(perform: loadSkills)
            .sheet(isPresented: $isCreatingSkill) {
                SkillEditorView(skill: nil, onSave: { name, content in
                    saveSkill(id: nil, name: name, content: content)
                })
            }
            .sheet(item: $editorSkill) { skill in
                SkillEditorView(skill: skill, onSave: { name, content in
                    saveSkill(id: skill.id, name: name, content: content)
                })
            }
            .confirmationDialog(
                "Delete skill?",
                isPresented: Binding(
                    get: { skillPendingDeletion != nil },
                    set: { if !$0 { skillPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let skillPendingDeletion {
                    Button("Delete \(skillPendingDeletion.name)", role: .destructive) {
                        deleteSkill(skillPendingDeletion)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes the saved skill document.")
            }
        }
    }

    private var sortedSkills: [AgentSkill] {
        skills.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func storageError(
        title: String,
        message: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(FuzzTheme.warningAmber)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(FuzzTheme.textSecondary)
            Button(buttonTitle, action: action)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(FuzzTheme.acidGreen)
        }
        .padding(.vertical, 4)
    }

    private func loadSkills() {
        guard !isCreatingSkill, editorSkill == nil, !hasLocalChanges else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            skills = try StorageService.shared.loadSkills()
            hasLoadedSkills = true
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func saveSkill(id: UUID?, name: String, content: String) -> String? {
        let skill = AgentSkill(
            id: id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content
        )
        var updatedSkills = skills
        if let index = updatedSkills.firstIndex(where: { $0.id == skill.id }) {
            updatedSkills[index] = skill
        } else {
            updatedSkills.append(skill)
        }

        do {
            try StorageService.shared.saveSkills(updatedSkills)
            skills = updatedSkills
            hasLocalChanges = false
            saveError = nil
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    private func deleteSkill(_ skill: AgentSkill) {
        skillPendingDeletion = nil
        skills.removeAll { $0.id == skill.id }
        hasLocalChanges = true
        persistCurrentSkills()
    }

    private func retrySave() {
        persistCurrentSkills()
    }

    private func persistCurrentSkills() {
        do {
            try StorageService.shared.saveSkills(skills)
            hasLocalChanges = false
            saveError = nil
        } catch {
            hasLocalChanges = true
            saveError = error.localizedDescription
        }
    }
}

private struct SkillEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var content: String
    @State private var hasUnsavedEdits = false
    @State private var saveError: String?
    @State private var isSaving = false
    @State private var isConfirmingDiscard = false

    private let isNewSkill: Bool
    private let onSave: (String, String) -> String?

    init(skill: AgentSkill?, onSave: @escaping (String, String) -> String?) {
        _name = State(initialValue: skill?.name ?? "")
        _content = State(initialValue: skill?.content ?? "")
        isNewSkill = skill == nil
        self.onSave = onSave
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(FuzzTheme.textSecondary)
                            TextField("Skill name", text: $name, prompt: Text("e.g. Swift conventions"))
                                .font(.system(size: 15))
                                .foregroundStyle(FuzzTheme.textPrimary)
                                .padding(12)
                                .background(FuzzTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                                .accessibilityLabel("Skill name")
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("SKILL.md content")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(FuzzTheme.textSecondary)
                            TextEditor(text: $content)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundStyle(FuzzTheme.textPrimary)
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .frame(minHeight: 280)
                                .background(FuzzTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(FuzzTheme.textMuted.opacity(0.35), lineWidth: 1)
                                }
                                .accessibilityLabel("Skill Markdown content")
                                .accessibilityHint("Enter raw SKILL.md Markdown. Whitespace is preserved.")
                        }

                        if let saveError {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Skill changes weren't saved")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(FuzzTheme.warningAmber)
                                Text(saveError)
                                    .font(.system(size: 12))
                                    .foregroundStyle(FuzzTheme.textSecondary)
                                Text("Your edits are still here. Tap Retry Save or continue editing.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(FuzzTheme.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(FuzzTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(isNewSkill ? "New Skill" : "Edit Skill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: requestCancel)
                        .foregroundStyle(FuzzTheme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .tint(FuzzTheme.acidGreen)
                                .accessibilityLabel("Saving skill")
                        } else {
                            Text(saveError == nil ? "Save" : "Retry Save")
                                .foregroundStyle(FuzzTheme.acidGreen)
                        }
                    }
                    .disabled(!canSave)
                    .accessibilityLabel(saveError == nil ? "Save skill" : "Retry saving skill")
                }
            }
            .onChange(of: name) { _, _ in hasUnsavedEdits = true }
            .onChange(of: content) { _, _ in hasUnsavedEdits = true }
            .interactiveDismissDisabled(hasUnsavedEdits)
            .confirmationDialog(
                "Discard unsaved changes?",
                isPresented: $isConfirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) {
                    dismiss()
                }
                Button("Continue Editing", role: .cancel) {}
            } message: {
                Text("Your skill edits have not been saved.")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func requestCancel() {
        if hasUnsavedEdits {
            isConfirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }

        if let error = onSave(name, content) {
            saveError = error
        } else {
            saveError = nil
            hasUnsavedEdits = false
            dismiss()
        }
    }
}
