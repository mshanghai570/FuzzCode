import SwiftUI
import FuzzCodeCore

public struct ProvidersView: View {
    @State private var providers: [ProviderConfig] = []
    @State private var editingProvider: ProviderConfig?
    @State private var isCreatingNew = false
    @State private var testingProviderId: UUID?
    @State private var testResult: [UUID: String] = [:]
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                
                if providers.isEmpty {
                    emptyProvidersState
                } else {
                    providerList
                }
            }
            .navigationTitle("Endpoints")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { isCreatingNew = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(FuzzTheme.acidGreen)
                    }
                }
            }
            .sheet(isPresented: $isCreatingNew) {
                EndpointConfigSheet(provider: nil) { saved in
                    providers.append(saved)
                    StorageService.shared.saveProviders(providers)
                }
            }
            .sheet(item: $editingProvider) { config in
                EndpointConfigSheet(provider: config) { saved in
                    if let idx = providers.firstIndex(where: { $0.id == saved.id }) {
                        providers[idx] = saved
                    }
                    StorageService.shared.saveProviders(providers)
                }
            }
            .onAppear(perform: loadProviders)
        }
    }
    
    private var providerList: some View {
        List {
            ForEach($providers) { $provider in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(provider.displayName)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundColor(FuzzTheme.textPrimary)
                                
                                if !provider.isEnabled {
                                    Text("OFF")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(FuzzTheme.clippingRed)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(FuzzTheme.clippingRed.opacity(0.2))
                                        .cornerRadius(4)
                                }
                            }
                            
                            Text(provider.baseURLString)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(FuzzTheme.textMuted)
                                .lineLimit(1)
                            Text(provider.resolvedKind.displayName.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(FuzzTheme.electricPurple)
                        }
                        
                        Spacer()
                        
                        Toggle("", isOn: $provider.isEnabled)
                            .labelsHidden()
                            .tint(FuzzTheme.acidGreen)
                            .onChange(of: provider.isEnabled) { _ in
                                StorageService.shared.saveProviders(providers)
                            }
                    }
                    
                    HStack {
                        HStack(spacing: 4) {
                            Text("MODEL:")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(FuzzTheme.textMuted)
                            Text(provider.selectedModel)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(FuzzTheme.acidGreen)
                        }
                        
                        Spacer()
                        
                        if let res = testResult[provider.id] {
                            Text(res)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(res.contains("ms") ? FuzzTheme.acidGreen : FuzzTheme.clippingRed)
                        }
                        
                        Button(action: {
                            testConnection(for: provider)
                        }) {
                            HStack(spacing: 4) {
                                if testingProviderId == provider.id {
                                    ProgressView().scaleEffect(0.6)
                                } else {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 10))
                                }
                                Text("Ping")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                            }
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(FuzzTheme.acidGreen)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 8)
                .listRowBackground(FuzzTheme.surface)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        deleteProvider(provider)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    
                    Button {
                        duplicateProvider(provider)
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    .tint(FuzzTheme.electricPurple)
                    
                    Button {
                        editingProvider = provider
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
        }
        .scrollContentBackground(.hidden)
    }
    
    private var emptyProvidersState: some View {
        VStack(spacing: 16) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 40))
                .foregroundColor(FuzzTheme.acidGreen)
            
            Text("No Endpoints Configured")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(FuzzTheme.textPrimary)
            
            Text("Add an OpenAI-compatible endpoint (OpenAI, Groq, Ollama, Kilo, vLLM, OpenCode) with custom headers and models.")
                .font(.system(size: 13))
                .foregroundColor(FuzzTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            FuzzStompButton(title: "Add Compatible Endpoint", icon: "plus") {
                isCreatingNew = true
            }
        }
    }
    
    private func testConnection(for provider: ProviderConfig) {
        testingProviderId = provider.id
        testResult[provider.id] = nil
        Task {
            do {
                let adapter = try makeAIProvider(config: provider)
                let latency = try await adapter.testConnection()
                await MainActor.run {
                    self.testResult[provider.id] = "\(Int(latency))ms"
                    self.testingProviderId = nil
                    FuzzTheme.playSuccessFeedback()
                }
            } catch {
                await MainActor.run {
                    self.testResult[provider.id] = "Error"
                    self.testingProviderId = nil
                    FuzzTheme.playErrorFeedback()
                }
            }
        }
    }
    
    private func duplicateProvider(_ provider: ProviderConfig) {
        var copy = provider
        copy.id = UUID()
        copy.displayName = "\(provider.displayName) (Copy)"
        providers.append(copy)
        StorageService.shared.saveProviders(providers)
    }
    
    private func deleteProvider(_ provider: ProviderConfig) {
        providers.removeAll(where: { $0.id == provider.id })
        StorageService.shared.saveProviders(providers)
    }
    
    private func loadProviders() {
        providers = StorageService.shared.loadProviders()
    }
}

struct EndpointConfigSheet: View {
    let provider: ProviderConfig?
    let onSave: (ProviderConfig) -> Void
    @Environment(\.dismiss) var dismiss
    
    @State private var displayName: String = ""
    @State private var providerKind: ProviderKind = .custom
    @State private var baseURL: String = "https://api.openai.com/v1"
    @State private var apiKey: String = ""
    @State private var selectedModel: String = "gpt-4o"
    @State private var orgId: String = ""
    @State private var customPath: String = ""
    @State private var timeoutSeconds: Double = 30.0
    @State private var allowsInsecureHTTP: Bool = false
    @State private var discoveredModels: [ModelInfo] = []
    @State private var isDiscovering: Bool = false
    @State private var testStatusText: String?
    
    init(provider: ProviderConfig?, onSave: @escaping (ProviderConfig) -> Void) {
        self.provider = provider
        self.onSave = onSave
        _displayName = State(initialValue: provider?.displayName ?? "OpenAI Compatible")
        _providerKind = State(initialValue: provider?.resolvedKind ?? .custom)
        _baseURL = State(initialValue: provider?.baseURLString ?? (provider?.resolvedKind ?? .custom).defaultBaseURLString)
        _selectedModel = State(initialValue: provider?.selectedModel ?? "gpt-4o")
        _orgId = State(initialValue: provider?.organizationId ?? "")
        _customPath = State(initialValue: provider?.customApiPath ?? "")
        _timeoutSeconds = State(initialValue: provider?.timeoutSeconds ?? 30.0)
        _allowsInsecureHTTP = State(initialValue: provider?.allowsInsecureHTTP ?? false)
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                
                Form {
                    Section("Provider") {
                        Picker("Provider", selection: $providerKind) {
                            ForEach(ProviderKind.allCases, id: \.self) { kind in
                                Text(kind.displayName).tag(kind)
                            }
                        }
                        .onChange(of: providerKind) { _, newKind in
                            displayName = newKind.displayName
                            baseURL = newKind.defaultBaseURLString
                            selectedModel = newKind.defaultModel
                            discoveredModels = []
                        }
                    }
                    .listRowBackground(FuzzTheme.surface)

                    Section("Endpoint Target") {
                        TextField("Provider Display Name", text: $displayName)
                        TextField("Base URL (e.g. https://api.openai.com/v1)", text: $baseURL)
                        SecureField("API Key (stored in Keychain)", text: $apiKey)
                    }
                    .listRowBackground(FuzzTheme.surface)
                    
                    Section("Model Specification") {
                        HStack {
                            TextField("Model ID (e.g. gpt-4o, claude-3-5, llama3)", text: $selectedModel)
                            Button(isDiscovering ? "…" : "Discover") {
                                discoverModels()
                            }
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(FuzzTheme.acidGreen)
                            .disabled(isDiscovering)
                        }

                        if !modelChoices.isEmpty {
                            Picker("Available Models", selection: $selectedModel) {
                                ForEach(modelChoices) { model in
                                    Text(model.id).tag(model.id)
                                }
                            }
                        } else if testStatusText != nil {
                            Text(testStatusText ?? "")
                                .font(.caption)
                                .foregroundColor(FuzzTheme.textSecondary)
                        }
                    }
                    .listRowBackground(FuzzTheme.surface)
                    
                    Section("Advanced Parameters") {
                        TextField("Organization ID (Optional)", text: $orgId)
                        TextField("Custom API Path Override", text: $customPath)
                        HStack {
                            Text("Timeout: \(Int(timeoutSeconds))s")
                            Slider(value: $timeoutSeconds, in: 5...120, step: 5)
                                .tint(FuzzTheme.acidGreen)
                        }
                        Toggle("Allow Insecure HTTP (Local Dev)", isOn: $allowsInsecureHTTP)
                            .tint(FuzzTheme.clippingRed)
                    }
                    .listRowBackground(FuzzTheme.surface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(provider == nil ? "New Endpoint" : "Edit Endpoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveConfiguration()
                    }
                    .foregroundColor(FuzzTheme.acidGreen)
                }
            }
            .onAppear {
                if let prov = provider, let key = KeychainService.shared.get(key: "api_key_\(prov.id.uuidString)") {
                    apiKey = key
                }
            }
        }
    }
    
    private var modelChoices: [ModelInfo] {
        var seen = Set<String>()
        var choices = providerKind.curatedModels.map { ModelInfo(id: $0) }
        choices.forEach { seen.insert($0.id) }
        for model in discoveredModels where seen.insert(model.id).inserted {
            choices.append(model)
        }
        if !selectedModel.isEmpty, seen.insert(selectedModel).inserted {
            choices.insert(ModelInfo(id: selectedModel), at: 0)
        }
        return choices
    }

    private func discoverModels() {
        isDiscovering = true
        testStatusText = nil
        let tempConfig = ProviderConfig(
            displayName: displayName,
            baseURLString: baseURL,
            providerKind: providerKind,
            selectedModel: selectedModel,
            timeoutSeconds: timeoutSeconds,
            allowsInsecureHTTP: allowsInsecureHTTP
        )
        if !apiKey.isEmpty {
            KeychainService.shared.save(key: "api_key_\(tempConfig.id.uuidString)", secret: apiKey)
        }
        Task {
            do {
                let adapter = try makeAIProvider(config: tempConfig)
                let models = try await adapter.discoverModels()
                await MainActor.run {
                    self.discoveredModels = models
                    self.testStatusText = models.isEmpty ? "No models returned." : "\(models.count) models found."
                    self.isDiscovering = false
                    FuzzTheme.playSuccessFeedback()
                }
            } catch {
                await MainActor.run {
                    self.testStatusText = error.localizedDescription
                    self.isDiscovering = false
                    FuzzTheme.playErrorFeedback()
                }
            }
        }
    }
    
    private func saveConfiguration() {
        let configId = provider?.id ?? UUID()
        if !apiKey.isEmpty {
            KeychainService.shared.save(key: "api_key_\(configId.uuidString)", secret: apiKey)
        }
        let config = ProviderConfig(
            id: configId,
            displayName: displayName,
            baseURLString: baseURL,
            providerKind: providerKind,
            selectedModel: selectedModel,
            organizationId: orgId.isEmpty ? nil : orgId,
            customApiPath: customPath.isEmpty ? nil : customPath,
            timeoutSeconds: timeoutSeconds,
            allowsInsecureHTTP: allowsInsecureHTTP
        )
        onSave(config)
        dismiss()
    }
}
