import SwiftUI
import FuzzCodeCore

/// Native SwiftUI sheet for editing system prompt directives and managing RAG knowledge sources.
public struct RAGPromptSheet: View {
    @Binding public var promptText: String
    @Binding public var sources: [RAGSource]
    @Binding public var config: RAGConfig
    public let scopeTitle: String
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTab = 0
    @State private var isAddingSource = false
    @State private var newTitle = ""
    @State private var newContent = ""
    @State private var testQuery = ""
    @State private var testCitations: [RetrievedCitation] = []
    
    public init(promptText: Binding<String>, sources: Binding<[RAGSource]>, config: Binding<RAGConfig>, scopeTitle: String) {
        self._promptText = promptText
        self._sources = sources
        self._config = config
        self.scopeTitle = scopeTitle
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.charcoalBlack.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    Picker("Section", selection: $selectedTab) {
                        Text("Prompt").tag(0)
                        Text("RAG Sources (\(sources.filter { $0.isEnabled }.count))").tag(1)
                        Text("Test Search").tag(2)
                        Text("Tuning").tag(3)
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
                                    .foregroundStyle(FuzzTheme.mutedSlate)
                                
                                TextEditor(text: $promptText)
                                    .frame(minHeight: 180)
                                    .padding(8)
                                    .background(FuzzTheme.darkPedalBase)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(.white)
                                    .fontDesign(.monospaced)
                                    .font(.caption)
                                
                                Text("QUICK PRESETS")
                                    .font(.caption2)
                                    .fontDesign(.monospaced)
                                    .fontWeight(.bold)
                                    .foregroundStyle(FuzzTheme.mutedSlate)
                                    .padding(.top, 8)
                                
                                Button("Swift 6 Concurrency Specialist") {
                                    promptText = "You are an expert native iOS engineer specializing in Swift 6, SwiftUI, and Sendable concurrency."
                                    FuzzTheme.hapticClick()
                                }
                                .buttonStyle(.bordered)
                                .tint(FuzzTheme.acidGreen)
                                
                                Button("Autonomous OpenCode Agent") {
                                    promptText = "You are an autonomous OpenCode software engineer. Plan steps, invoke tools, and test changes before reporting."
                                    FuzzTheme.hapticClick()
                                }
                                .buttonStyle(.bordered)
                                .tint(FuzzTheme.electricPurple)
                            }
                            .padding(.horizontal)
                        }
                    } else if selectedTab == 1 {
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
                                            .foregroundStyle(FuzzTheme.mutedSlate)
                                            .lineLimit(2)
                                    }
                                    .padding(.vertical, 4)
                                    .listRowBackground(FuzzTheme.darkPedalBase)
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
                    } else if selectedTab == 2 {
                        // Test Search View
                        VStack(spacing: 12) {
                            HStack {
                                TextField("Enter test query...", text: $testQuery)
                                    .padding(10)
                                    .background(FuzzTheme.darkPedalBase)
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
                                        .foregroundStyle(FuzzTheme.mutedSlate)
                                }
                                .listRowBackground(FuzzTheme.darkPedalBase)
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
                            .listRowBackground(FuzzTheme.darkPedalBase)
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
                        FuzzTheme.charcoalBlack.ignoresSafeArea()
                        Form {
                            Section("Source Info") {
                                TextField("Source Title", text: $newTitle)
                                    .foregroundStyle(.white)
                                TextEditor(text: $newContent)
                                    .frame(minHeight: 120)
                                    .foregroundStyle(.white)
                            }
                            .listRowBackground(FuzzTheme.darkPedalBase)
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
                        }
                    }
                }
            }
        }
    }
    
    private func runTestSearch() {
        FuzzTheme.hapticClick()
        Task {
            let res = await RAGService.shared.retrieve(query: testQuery, sources: sources, config: config)
            await MainActor.run {
                self.testCitations = res.citations
            }
        }
    }
}
