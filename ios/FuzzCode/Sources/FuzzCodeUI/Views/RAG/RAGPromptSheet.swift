import SwiftUI
import FuzzCodeCore

/// Native SwiftUI sheet for editing system prompt directives and managing RAG knowledge sources.
public struct RAGPromptSheet: View {
    @Binding public var promptText: String
    @Binding public var sources: [RAGSource]
    @Binding public var config: RAGConfig
    @Binding public var selectedSkillIDs: [UUID]
    public let availableSkills: [AgentSkill]
    public let scopeTitle: String
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTab = 0
    @State private var isAddingSource = false
    @State private var newTitle = ""
    @State private var newContent = ""
    @State private var testQuery = ""
    @State private var testCitations: [RetrievedCitation] = []
    
    public init(
        promptText: Binding<String>,
        sources: Binding<[RAGSource]>,
        config: Binding<RAGConfig>,
        availableSkills: [AgentSkill],
        selectedSkillIDs: Binding<[UUID]>,
        scopeTitle: String
    ) {
        self._promptText = promptText
        self._sources = sources
        self._config = config
        self.availableSkills = availableSkills
        self._selectedSkillIDs = selectedSkillIDs
        self.scopeTitle = scopeTitle
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Picker("Section", selection: $selectedTab) {
                        Text("Prompt").tag(0)
                        Text("Skills (\(selectedSkillIDs.count))").tag(1)
                        Text("RAG Sources (\(sources.filter { $0.isEnabled }.count))").tag(2)
                        Text("Test Search").tag(3)
                        Text("Tuning").tag(4)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    if selectedTab == 0 {
                        // Prompt Directives View
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("SYSTEM PROMPT / DIRECTIVE")
                                    .font(.caption2)
                                    .fontDesign(.monospaced)
                                    .fontWeight(.bold)
                                    .foregroundStyle(FuzzTheme.textSecondary)
                                
                                TextEditor(text: $promptText)
                                    .accessibilityLabel("System prompt") // [VERIFY] confirm label matches intent
                                    .frame(minHeight: 180)
                                    .padding(8)
                                    .background(FuzzTheme.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(.white)
                                    .fontDesign(.monospaced)
                                    .font(.caption)
                                
                                Text("QUICK PRESETS")
                                    .font(.caption2)
                                    .fontDesign(.monospaced)
                                    .fontWeight(.bold)
                                    .foregroundStyle(FuzzTheme.textSecondary)
                                    .padding(.top, 8)
                                
                                Button("Swift 6 Concurrency Specialist") {
                                    promptText = "You are an expert native iOS engineer specializing in Swift 6, SwiftUI, and Sendable concurrency."
                                    FuzzTheme.playStompFeedback()
                                }
                                .buttonStyle(.bordered)
                                .tint(FuzzTheme.acidGreen)
                                
                                Button("Autonomous OpenCode Agent") {
                                    promptText = "You are an autonomous OpenCode software engineer. Plan steps, invoke tools, and test changes before reporting."
                                    FuzzTheme.playStompFeedback()
                                }
                                .buttonStyle(.bordered)
                                .tint(FuzzTheme.electricPurple)
                            }
                            .padding(.horizontal)
                        }
                    } else if selectedTab == 1 {
                        List {
                            if availableSkills.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "sparkles")
                                        .font(.title2)
                                        .foregroundStyle(FuzzTheme.electricPurple)
                                    Text("No skills available")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Text("Create skills in Settings → Integrations → Skills, then select them for this conversation.")
                                        .font(.caption)
                                        .foregroundStyle(FuzzTheme.textSecondary)
                                        .multilineTextAlignment(.center)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28)
                                .listRowBackground(FuzzTheme.surface)
                            } else {
                                Section("Available Skills") {
                                    ForEach(availableSkills) { skill in
                                        Toggle(isOn: skillSelectionBinding(for: skill)) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(skill.name)
                                                    .font(.subheadline.weight(.semibold))
                                                    .foregroundStyle(.white)
                                                Text(skill.content)
                                                    .font(.caption)
                                                    .foregroundStyle(FuzzTheme.textSecondary)
                                                    .lineLimit(3)
                                            }
                                        }
                                        .tint(FuzzTheme.acidGreen)
                                        .listRowBackground(FuzzTheme.surface)
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    } else if selectedTab == 2 {
                        // RAG Knowledge Sources List
                        List {
                            Section {
                                ForEach($sources) { $source in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Toggle(isOn: $source.isEnabled) {
                                                Text(source.title)
                                                    .font(.subheadline)
                                                    .fontWeight(.bold)
                                                    .foregroundStyle(.white)
                                            }
                                            .tint(FuzzTheme.acidGreen)
                                        }
                                        if let path = source.filePath {
                                            Text(path)
                                                .font(.caption2)
                                                .fontDesign(.monospaced)
                                                .foregroundStyle(FuzzTheme.electricPurple)
                                        }
                                        Text(source.content)
                                            .font(.caption)
                                            .foregroundStyle(FuzzTheme.textSecondary)
                                            .lineLimit(2)
                                    }
                                    .padding(.vertical, 4)
                                    .listRowBackground(FuzzTheme.surface)
                                }
                                .onDelete { indexSet in
                                    sources.remove(atOffsets: indexSet)
                                }
                            } header: {
                                HStack {
                                    Text("Indexed Sources")
                                    Spacer()
                                    Button("+ Add Source") {
                                        isAddingSource = true
                                    }
                                    .foregroundStyle(FuzzTheme.acidGreen)
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                    } else if selectedTab == 3 {
                        // Test Search View
                        VStack(spacing: 12) {
                            HStack {
                                TextField("Enter test query...", text: $testQuery)
                                    .padding(10)
                                    .background(FuzzTheme.surface)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .foregroundStyle(.white)
                                
                                Button("Search") {
                                    runTestSearch()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(FuzzTheme.acidGreen)
                            }
                            .padding(.horizontal)
                            
                            List(testCitations) { citation in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(citation.sourceTitle)
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                        Spacer()
                                        Text("\(Int(citation.score * 100))% MATCH")
                                            .font(.caption2)
                                            .fontDesign(.monospaced)
                                            .foregroundStyle(FuzzTheme.acidGreen)
                                    }
                                    Text(citation.snippet)
                                        .font(.caption2)
                                        .fontDesign(.monospaced)
                                        .foregroundStyle(FuzzTheme.textSecondary)
                                }
                                .listRowBackground(FuzzTheme.surface)
                            }
                            .listStyle(.plain)
                        }
                    } else {
                        // Tuning View
                        Form {
                            Section("Retrieval Parameters") {
                                Toggle("Enable RAG", isOn: $config.isEnabled)
                                    .tint(FuzzTheme.acidGreen)
                                Stepper("Top-K Chunks: \(config.topK)", value: $config.topK, in: 1...8)
                                Stepper("Similarity Cutoff: \(Int(config.similarityThreshold * 100))%", value: $config.similarityThreshold, in: 0.0...0.8, step: 0.05)
                            }
                            .listRowBackground(FuzzTheme.surface)
                        }
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle(scopeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(FuzzTheme.acidGreen)
                }
            }
            .sheet(isPresented: $isAddingSource) {
                NavigationStack {
                    ZStack {
                        FuzzTheme.background.ignoresSafeArea()
                        Form {
                            Section("Source Info") {
                                TextField("Source Title", text: $newTitle)
                                    .foregroundStyle(.white)
                                TextEditor(text: $newContent)
                                    .accessibilityLabel("Source content") // [VERIFY] confirm label matches intent
                                    .frame(minHeight: 120)
                                    .foregroundStyle(.white)
                            }
                            .listRowBackground(FuzzTheme.surface)
                        }
                        .scrollContentBackground(.hidden)
                    }
                    .navigationTitle("Add RAG Source")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isAddingSource = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                let source = RAGSource(
                                    title: newTitle.isEmpty ? "Custom Document" : newTitle,
                                    type: .document,
                                    content: newContent,
                                    tokens: max(newContent.count / 4, 1)
                                )
                                sources.append(source)
                                isAddingSource = false
                                newTitle = ""
                                newContent = ""
                            }
                            .foregroundStyle(FuzzTheme.acidGreen)
                            .disabled(newContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
    }
    
    private func runTestSearch() {
        FuzzTheme.playStompFeedback()
        Task {
            let res = await RAGService.shared.retrieve(query: testQuery, sources: sources, config: config)
            await MainActor.run {
                self.testCitations = res.citations
            }
        }
    }

    private func skillSelectionBinding(for skill: AgentSkill) -> Binding<Bool> {
        Binding(
            get: { selectedSkillIDs.contains(skill.id) },
            set: { isSelected in
                if isSelected {
                    if !selectedSkillIDs.contains(skill.id) {
                        selectedSkillIDs.append(skill.id)
                    }
                } else {
                    selectedSkillIDs.removeAll { $0 == skill.id }
                }
            }
        )
    }
}
