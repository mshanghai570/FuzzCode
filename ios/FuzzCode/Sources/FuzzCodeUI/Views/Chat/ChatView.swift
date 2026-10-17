import SwiftUI
import FuzzCodeCore

public struct ChatView: View {
    @State private var providers: [ProviderConfig] = []
    @State private var selectedProvider: ProviderConfig?
    @State private var conversations: [ChatConversation] = []
    @State private var currentConversation: ChatConversation?
    
    @State private var inputText: String = ""
    @State private var isStreaming: Bool = false
    @State private var currentStreamTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var showHistorySheet: Bool = false
    @State private var showContextSheet = false
    @State private var systemPrompt = ""
    @State private var ragSources: [RAGSource] = []
    @State private var ragConfig = RAGConfig()
    @State private var availableSkills: [AgentSkill] = []
    @State private var selectedSkillIDs: [UUID] = []
    @State private var skillLibraryLoadedSuccessfully = false
    @State private var citations: [RetrievedCitation] = []
    @State private var activeStreamID: UUID?
    @State private var availableModels: [ModelInfo] = []
    @State private var isLoadingModels = false
    @FocusState private var inputFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    providerAndModelBar
                    
                    if let conv = currentConversation, !conv.messages.isEmpty {
                        messageList(conv)
                    } else {
                        emptyChatState
                    }
                    
                    if let error = errorMessage {
                        errorBanner(error)
                    }
                    if !citations.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(citations) { citation in
                                    Label(citation.sourceTitle, systemImage: "doc.text")
                                        .font(.caption)
                                        .padding(8)
                                        .background(FuzzTheme.surfaceRaised, in: Capsule())
                                }
                            }
                            .padding(.horizontal)
                        }
                        .accessibilityLabel("Project sources used for this response")
                    }
                    
                    inputBar
                }
            }
            .navigationTitle(currentConversation?.title ?? "AI Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showHistorySheet = true }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(FuzzTheme.textSecondary)
                    }
                    .accessibilityLabel("Conversation history") // [VERIFY] confirm label matches intent
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Project context", systemImage: "text.book.closed") {
                        showContextSheet = true
                    }
                    .disabled(isStreaming || currentConversation == nil)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: startNewConversation) {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(FuzzTheme.acidGreen)
                    }
                    .accessibilityLabel("New conversation") // [VERIFY] confirm label matches intent
                }
            }
            .sheet(isPresented: $showHistorySheet) {
                historySheet
            }
            .sheet(isPresented: $showContextSheet, onDismiss: saveContext) {
                RAGPromptSheet(promptText: $systemPrompt, sources: $ragSources,
                               config: $ragConfig, availableSkills: availableSkills,
                               selectedSkillIDs: $selectedSkillIDs, scopeTitle: "Project Context")
            }
            .onAppear(perform: setupInitialState)
            .onChange(of: selectedProvider?.id) {
                availableModels = []
                refreshModels()
            }
        }
    }
    
    private var providerAndModelBar: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(providers.filter { $0.isEnabled }) { provider in
                    Button(action: {
                        self.selectedProvider = provider
                        if var conv = currentConversation {
                            conv.providerId = provider.id
                            conv.modelId = provider.selectedModel
                            self.currentConversation = conv
                            saveCurrentConversation()
                        }
                    }) {
                        Text(provider.displayName)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(FuzzTheme.acidGreen)
                        .frame(width: 8, height: 8)
                    Text(selectedProvider?.displayName ?? "Select Provider")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundColor(FuzzTheme.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(FuzzTheme.textMuted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(FuzzTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(FuzzTheme.border, lineWidth: 1))
                )
            }
            .disabled(isStreaming)
            
            Spacer()

            Menu {
                if isLoadingModels {
                    Text("Loading models…")
                }
                ForEach(modelOptions) { model in
                    Button(action: { selectModel(model.id) }) {
                        Text(model.id)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selectedProvider?.selectedModel ?? "No Model")
                        .font(.caption.monospaced().weight(.medium))
                        .foregroundColor(FuzzTheme.electricPurple)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(FuzzTheme.textMuted)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(FuzzTheme.surfaceRaised)
                .cornerRadius(6)
            }
            .disabled(isStreaming || selectedProvider == nil)
            .accessibilityLabel("Select model")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(FuzzTheme.surface.opacity(0.8))
    }
    
    private func messageList(_ conversation: ChatConversation) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(conversation.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: conversation.messages.last?.content) {
                if let lastId = conversation.messages.last?.id {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                        proxy.scrollTo(lastId, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    private var emptyChatState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform.path")
                .font(.system(size: 40))
                .foregroundColor(FuzzTheme.acidGreen.opacity(0.8))
            
            VStack(spacing: 6) {
                Text("FUZZCODE INFERENCE")
                    .font(.subheadline.monospaced().weight(.bold))
                    .foregroundColor(FuzzTheme.textPrimary)
                
                Text("Chat directly with any OpenAI-compatible API endpoint with streaming tokens and markdown code blocks.")
                    .font(.subheadline)
                    .foregroundColor(FuzzTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            HStack(spacing: 8) {
                suggestionChip("Explain this regex pattern")
                suggestionChip("Write a Swift actor wrapper")
            }
            Spacer()
        }
    }
    
    private func suggestionChip(_ text: String) -> some View {
        Button(action: {
            inputText = text
        }) {
            Text(text)
                .font(.caption.weight(.medium))
                .foregroundColor(FuzzTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(FuzzTheme.surfaceRaised)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(FuzzTheme.border, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }
    
    private func errorBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(FuzzTheme.clippingRed)
            Text(msg)
                .font(.caption)
                .foregroundColor(FuzzTheme.clippingRed)
            Spacer()
            Button(action: { errorMessage = nil }) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(FuzzTheme.clippingRed)
            }
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Dismiss error") // [VERIFY] confirm label matches intent
        }
        .padding(10)
        .background(FuzzTheme.clippingRed.opacity(0.15))
        .cornerRadius(8)
        .padding(.horizontal, 16)
    }
    
    private var modelOptions: [ModelInfo] {
        var seen = Set<String>()
        var options: [ModelInfo] = []
        if let current = selectedProvider?.selectedModel, !current.isEmpty {
            options.append(ModelInfo(id: current))
            seen.insert(current)
        }
        if let kindModels = selectedProvider?.resolvedKind.curatedModels {
            for id in kindModels where seen.insert(id).inserted {
                options.append(ModelInfo(id: id))
            }
        }
        for model in availableModels where seen.insert(model.id).inserted {
            options.append(model)
        }
        return options
    }

    private func selectModel(_ modelId: String) {
        guard var provider = selectedProvider else { return }
        provider.selectedModel = modelId
        selectedProvider = provider
        var stored = StorageService.shared.loadProviders()
        if let index = stored.firstIndex(where: { $0.id == provider.id }) {
            stored[index] = provider
            StorageService.shared.saveProviders(stored)
            providers = stored
        }
        if var conv = currentConversation {
            conv.modelId = modelId
            currentConversation = conv
            saveCurrentConversation()
        }
    }

    private func refreshModels() {
        guard let provider = selectedProvider, !isStreaming else { return }
        isLoadingModels = true
        Task {
            var discovered: [ModelInfo] = []
            do {
                let adapter = try makeAIProvider(config: provider)
                discovered = try await adapter.discoverModels()
            } catch {
                discovered = []
            }
            await MainActor.run {
                self.availableModels = discovered
                self.isLoadingModels = false
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Type your prompt or instruction...", text: $inputText, axis: .vertical)
                .focused($inputFocused)
                .font(.body)
                .foregroundColor(FuzzTheme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(FuzzTheme.surfaceRaised)
                        .overlay(RoundedRectangle(cornerRadius: 20).stroke(FuzzTheme.border, lineWidth: 1))
                )
                .lineLimit(1...5)
            
            if isStreaming {
                Button(action: cancelGeneration) {
                    Image(systemName: "stop.fill")
                        .font(.caption.weight(.bold))
                        .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                        .background(FuzzTheme.clippingRed)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Stop response") // [VERIFY] confirm label matches intent
            } else {
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundColor(.black)
                        .frame(width: 44, height: 44)
                        .background(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? FuzzTheme.textMuted : FuzzTheme.acidGreen)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Send message") // [VERIFY] confirm label matches intent
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedProvider == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FuzzTheme.surface)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(action: { inputFocused = false }) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .foregroundColor(FuzzTheme.acidGreen)
                }
                .accessibilityLabel("Dismiss keyboard")
            }
        }
    }
    
    // MARK: - Actions
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isStreaming, !text.isEmpty, let provider = selectedProvider, provider.isEnabled else { return }
        saveContext()
        inputText = ""
        errorMessage = nil
        citations = []
        FuzzTheme.playStompFeedback()

        var conv = currentConversation ?? ChatConversation(
            title: String(text.prefix(30)), providerId: provider.id, modelId: provider.selectedModel)
        conv.providerId = provider.id
        conv.modelId = provider.selectedModel
        if conv.messages.isEmpty { conv.title = String(text.prefix(30)) }
        conv.messages.append(ChatMessage(role: .user, content: text))
        let requestMessages = conv.messages
        let assistantID = UUID()
        conv.messages.append(ChatMessage(id: assistantID, role: .assistant, content: "", isStreaming: true))
        currentConversation = conv
        saveCurrentConversation()
        isStreaming = true
        let streamID = UUID()
        activeStreamID = streamID
        let prompt = systemPrompt
        let sources = ragSources
        let config = ragConfig
        let selectedSkills = availableSkills
            .filter { selectedSkillIDs.contains($0.id) }
            .map { (name: $0.name, content: $0.content) }

        currentStreamTask = Task { @MainActor in
            do {
                let retrieved = await RAGService.shared.retrieve(query: text, sources: sources, config: config)
                try Task.checkCancellation()
                guard activeStreamID == streamID else { return }
                citations = retrieved.citations
                let augmentedPrompt = await RAGService.shared.buildSystemPrompt(
                    basePrompt: prompt, ragContext: retrieved.augmentedContext,
                    skillContents: selectedSkills)
                try Task.checkCancellation()
                let adapter = try makeAIProvider(config: provider)
                let stream = await adapter.streamChat(messages: requestMessages, systemPrompt: augmentedPrompt)
                for try await delta in stream {
                    try Task.checkCancellation()
                    guard activeStreamID == streamID,
                          var updated = currentConversation,
                          let index = updated.messages.firstIndex(where: { $0.id == assistantID }) else { return }
                    updated.messages[index].content += delta
                    currentConversation = updated
                }
            } catch {
                guard activeStreamID == streamID else { return }
                if !Task.isCancelled { errorMessage = error.localizedDescription }
            }
            guard activeStreamID == streamID else { return }
            finishGeneration()
        }
    }

    private func finishGeneration() {
        if var conv = currentConversation, let index = conv.messages.indices.last {
            conv.messages[index].isStreaming = false
            currentConversation = conv
            saveCurrentConversation()
        }
        activeStreamID = nil
        currentStreamTask = nil
        isStreaming = false
    }

    private func cancelGeneration() {
        guard isStreaming || currentStreamTask != nil else { return }
        activeStreamID = nil
        currentStreamTask?.cancel()
        finishGeneration()
    }

    private func saveContext() {
        guard var conv = currentConversation else { return }
        conv.systemPrompt = systemPrompt
        conv.ragSources = ragSources
        conv.ragConfig = ragConfig
        conv.selectedSkillIDs = selectedSkillIDs
        currentConversation = conv
        saveCurrentConversation()
    }

    private func selectConversation(_ conversation: ChatConversation) {
        cancelGeneration()
        var restored = conversations.first(where: { $0.id == conversation.id }) ?? conversation
        for index in restored.messages.indices { restored.messages[index].isStreaming = false }
        currentConversation = restored
        selectedProvider = providers.first { $0.id == restored.providerId && $0.isEnabled }
        systemPrompt = restored.systemPrompt ?? ""
        ragSources = restored.ragSources ?? []
        ragConfig = restored.ragConfig ?? RAGConfig()
        selectedSkillIDs = restored.selectedSkillIDs ?? []
        citations = []
        errorMessage = nil
        saveCurrentConversation()
    }

    private func startNewConversation() {
        cancelGeneration()
        systemPrompt = ""
        ragSources = []
        ragConfig = RAGConfig()
        selectedSkillIDs = []
        citations = []
        errorMessage = nil
        currentConversation = nil
        guard let provider = selectedProvider else { return }
        let newConv = ChatConversation(title: "New Session", providerId: provider.id,
                                       modelId: provider.selectedModel, selectedSkillIDs: [])
        self.currentConversation = newConv
        self.conversations.insert(newConv, at: 0)
        StorageService.shared.saveConversations(conversations)
    }
    
    private func setupInitialState() {
        providers = StorageService.shared.loadProviders()
        guard !isStreaming else { return }
        conversations = StorageService.shared.loadConversations().sorted { $0.updatedAt > $1.updatedAt }
        var skillLoadError: String?
        do {
            availableSkills = try StorageService.shared.loadSkills()
            skillLibraryLoadedSuccessfully = true
        } catch {
            skillLibraryLoadedSuccessfully = false
            skillLoadError = "Unable to load saved skills: \(error.localizedDescription)"
        }
        if let currentID = currentConversation?.id,
           let saved = conversations.first(where: { $0.id == currentID }) {
            selectConversation(saved)
        } else if let first = conversations.first {
            selectConversation(first)
        } else {
            selectedProvider = providers.first(where: { $0.isEnabled })
            startNewConversation()
        }
        if let skillLoadError { errorMessage = skillLoadError }
        refreshModels()
    }

    private func saveCurrentConversation() {
        guard var conv = currentConversation else { return }
        if skillLibraryLoadedSuccessfully {
            let availableSkillIDs = Set(availableSkills.map(\.id))
            selectedSkillIDs = selectedSkillIDs.filter { availableSkillIDs.contains($0) }
        }
        conv.selectedSkillIDs = selectedSkillIDs
        conv.updatedAt = Date()
        currentConversation = conv
        if let index = conversations.firstIndex(where: { $0.id == conv.id }) {
            conversations[index] = conv
        } else {
            conversations.insert(conv, at: 0)
        }
        StorageService.shared.saveConversations(conversations)
    }
    
    private var historySheet: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                List {
                    ForEach(conversations) { conv in
                        Button(action: {
                            selectConversation(conv)
                            showHistorySheet = false
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conv.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundColor(FuzzTheme.textPrimary)
                                HStack {
                                    Text(conv.modelId)
                                        .font(.caption.monospaced())
                                        .foregroundColor(FuzzTheme.acidGreen)
                                    Spacer()
                                    Text("\(conv.messages.count) messages")
                                        .font(.caption)
                                        .foregroundColor(FuzzTheme.textMuted)
                                }
                            }
                        }
                        .listRowBackground(FuzzTheme.surface)
                    }
                    .onDelete { indices in
                        cancelGeneration()
                        conversations.remove(atOffsets: indices)
                        StorageService.shared.saveConversations(conversations)
                        if let current = currentConversation, !conversations.contains(where: { $0.id == current.id }) {
                            if let next = conversations.first { selectConversation(next) }
                            else { startNewConversation() }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Conversation History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showHistorySheet = false }
                        .foregroundColor(FuzzTheme.acidGreen)
                }
            }
        }
    }
}

public struct MessageRow: View {
    public let message: ChatMessage
    
    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .user {
                Spacer(minLength: 40)
                Text(message.content)
                    .font(.body)
                    .foregroundColor(FuzzTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(FuzzTheme.surfaceRaised)
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(FuzzTheme.border, lineWidth: 1))
                    )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(FuzzTheme.acidGreen)
                        Text("ASSISTANT")
                            .font(.caption2.monospaced().weight(.bold))
                            .foregroundColor(FuzzTheme.textSecondary)
                        Spacer()
                        Button(action: {
                            UIPasteboard.general.string = message.content
                            FuzzTheme.playSuccessFeedback()
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption)
                                .foregroundColor(FuzzTheme.textMuted)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Copy response") // [VERIFY] confirm label matches intent
                    }
                    
                    Text(message.content.isEmpty && message.isStreaming ? "Thinking..." : message.content)
                        .font(.body)
                        .foregroundColor(FuzzTheme.textPrimary)
                        .textSelection(.enabled)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(FuzzTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(FuzzTheme.border, lineWidth: 1))
                )
                Spacer(minLength: 40)
            }
        }
    }
}
