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
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: startNewConversation) {
                        Image(systemName: "square.and.pencil")
                            .foregroundColor(FuzzTheme.acidGreen)
                    }
                }
            }
            .sheet(isPresented: $showHistorySheet) {
                historySheet
            }
            .onAppear(perform: setupInitialState)
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
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(FuzzTheme.textPrimary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
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
            
            Spacer()
            
            Text(selectedProvider?.selectedModel ?? "No Model")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(FuzzTheme.electricPurple)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(FuzzTheme.surfaceRaised)
                .cornerRadius(6)
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
            .onChange(of: conversation.messages.count) { _ in
                if let lastId = conversation.messages.last?.id {
                    withAnimation {
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
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(FuzzTheme.textPrimary)
                
                Text("Chat directly with any OpenAI-compatible API endpoint with streaming tokens and markdown code blocks.")
                    .font(.system(size: 13))
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
                .font(.system(size: 11, weight: .medium))
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
                .font(.system(size: 12))
                .foregroundColor(FuzzTheme.clippingRed)
            Spacer()
            Button(action: { errorMessage = nil }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(FuzzTheme.clippingRed)
            }
        }
        .padding(10)
        .background(FuzzTheme.clippingRed.opacity(0.15))
        .cornerRadius(8)
        .padding(.horizontal, 16)
    }
    
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Type your prompt or instruction...", text: $inputText, axis: .vertical)
                .font(.system(size: 14))
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
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 38, height: 38)
                        .background(FuzzTheme.clippingRed)
                        .clipShape(Circle())
                }
            } else {
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 38, height: 38)
                        .background(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? FuzzTheme.textMuted : FuzzTheme.acidGreen)
                        .clipShape(Circle())
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || selectedProvider == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(FuzzTheme.surface)
    }
    
    // MARK: - Actions
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let provider = selectedProvider else { return }
        inputText = ""
        errorMessage = nil
        FuzzTheme.playStompFeedback()
        
        var conv = currentConversation ?? ChatConversation(
            title: String(text.prefix(30)),
            providerId: provider.id,
            modelId: provider.selectedModel
        )
        
        let userMsg = ChatMessage(role: .user, content: text)
        conv.messages.append(userMsg)
        
        let assistantMsgId = UUID()
        let assistantMsg = ChatMessage(id: assistantMsgId, role: .assistant, content: "", isStreaming: true)
        conv.messages.append(assistantMsg)
        self.currentConversation = conv
        
        isStreaming = true
        
        currentStreamTask = Task {
            do {
                let client = try OpenAIClient(config: provider)
                let stream = client.streamChatCompletion(messages: conv.messages.dropLast(), temperature: 0.7, systemPrompt: nil)
                
                var accumulated = ""
                for try await delta in stream {
                    accumulated += delta
                    await MainActor.run {
                        if var updated = self.currentConversation,
                           let index = updated.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                            updated.messages[index].content = accumulated
                            self.currentConversation = updated
                        }
                    }
                }
                
                await MainActor.run {
                    if var updated = self.currentConversation,
                       let index = updated.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        updated.messages[index].isStreaming = false
                        self.currentConversation = updated
                        self.saveCurrentConversation()
                    }
                    self.isStreaming = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isStreaming = false
                }
            }
        }
    }
    
    private func cancelGeneration() {
        currentStreamTask?.cancel()
        currentStreamTask = nil
        isStreaming = false
        if var conv = currentConversation, let lastIndex = conv.messages.indices.last {
            conv.messages[lastIndex].isStreaming = false
            currentConversation = conv
            saveCurrentConversation()
        }
    }
    
    private func startNewConversation() {
        cancelGeneration()
        guard let provider = selectedProvider else { return }
        let newConv = ChatConversation(title: "New Session", providerId: provider.id, modelId: provider.selectedModel)
        self.currentConversation = newConv
        self.conversations.insert(newConv, at: 0)
        StorageService.shared.saveConversations(conversations)
    }
    
    private func setupInitialState() {
        providers = StorageService.shared.loadProviders()
        selectedProvider = providers.first(where: { $0.isEnabled })
        conversations = StorageService.shared.loadConversations()
        if let first = conversations.first {
            currentConversation = first
        } else if let provider = selectedProvider {
            startNewConversation()
        }
    }
    
    private func saveCurrentConversation() {
        guard let conv = currentConversation else { return }
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
                            currentConversation = conv
                            showHistorySheet = false
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conv.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(FuzzTheme.textPrimary)
                                HStack {
                                    Text(conv.modelId)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(FuzzTheme.acidGreen)
                                    Spacer()
                                    Text("\(conv.messages.count) messages")
                                        .font(.system(size: 11))
                                        .foregroundColor(FuzzTheme.textMuted)
                                }
                            }
                        }
                        .listRowBackground(FuzzTheme.surface)
                    }
                    .onDelete { indices in
                        conversations.remove(atOffsets: indices)
                        StorageService.shared.saveConversations(conversations)
                        if let current = currentConversation, !conversations.contains(where: { $0.id == current.id }) {
                            currentConversation = conversations.first
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
                    .font(.system(size: 14))
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
                            .font(.system(size: 11))
                            .foregroundColor(FuzzTheme.acidGreen)
                        Text("ASSISTANT")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(FuzzTheme.textSecondary)
                        Spacer()
                        Button(action: {
                            UIPasteboard.general.string = message.content
                            FuzzTheme.playSuccessFeedback()
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11))
                                .foregroundColor(FuzzTheme.textMuted)
                        }
                    }
                    
                    Text(message.content.isEmpty && message.isStreaming ? "Thinking..." : message.content)
                        .font(.system(size: 14))
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
