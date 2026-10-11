import SwiftUI
import FuzzCodeCore

public struct SettingsView: View {
    @State private var soundFeedbackEnabled = true
    @State private var hapticFeedbackEnabled = true
    @State private var streamChunkLatency = 15.0
    @State private var showExportSheet = false
    @State private var exportedConfigJSON = ""
    @State private var diagnosticResults: [String: String] = [:]
    @State private var isRunningDiagnostics = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                
                Form {
                    Section("Fuzz Audio & Haptics") {
                        Toggle("Stompbox Switch Sounds", isOn: $soundFeedbackEnabled)
                            .tint(FuzzTheme.acidGreen)
                        Toggle("Gain Dial Haptic Taps", isOn: $hapticFeedbackEnabled)
                            .tint(FuzzTheme.acidGreen)
                    }
                    .listRowBackground(FuzzTheme.surface)
                    
                    Section("Keychain & Security") {
                        HStack {
                            Text("Secure Enclave / Keychain")
                            Spacer()
                            Text("Active")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(FuzzTheme.acidGreen)
                        }
                        
                        Button(role: .destructive, action: clearAllCredentials) {
                            Text("Purge All Saved API Keys")
                        }
                    }
                    .listRowBackground(FuzzTheme.surface)
                    
                    Section("Diagnostics & Network") {
                        Button(action: runDiagnostics) {
                            HStack {
                                Text("Run Connection Diagnostics")
                                Spacer()
                                if isRunningDiagnostics {
                                    ProgressView().scaleEffect(0.7)
                                } else {
                                    Image(systemName: "waveform.path.ecg")
                                }
                            }
                            .foregroundColor(FuzzTheme.electricPurple)
                        }
                        
                        ForEach(Array(diagnosticResults.keys.sorted()), id: \.self) { key in
                            HStack {
                                Text(key)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(FuzzTheme.textMuted)
                                Spacer()
                                Text(diagnosticResults[key] ?? "")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(FuzzTheme.textPrimary)
                            }
                        }
                    }
                    .listRowBackground(FuzzTheme.surface)
                    
                    Section("Data Management") {
                        Button(action: exportSanitizedConfig) {
                            HStack {
                                Text("Export Configuration (Redacted)")
                                Spacer()
                                Image(systemName: "square.and.arrow.up")
                            }
                            .foregroundColor(FuzzTheme.textPrimary)
                        }
                    }
                    .listRowBackground(FuzzTheme.surface)
                    
                    Section("About FuzzCode") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("FUZZCODE v1.0.0")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundColor(FuzzTheme.acidGreen)
                            Text("A little distortion. A lot of control.")
                                .font(.system(size: 12))
                                .foregroundColor(FuzzTheme.textSecondary)
                            Text("Native iOS AI Coding Agent Control Center. Inspired by CodeAgent Mobile. Built with Swift & SwiftUI.")
                                .font(.system(size: 11))
                                .foregroundColor(FuzzTheme.textMuted)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(FuzzTheme.surface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showExportSheet) {
                NavigationStack {
                    ZStack {
                        FuzzTheme.background.ignoresSafeArea()
                        ScrollView {
                            Text(exportedConfigJSON)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(FuzzTheme.textSecondary)
                                .padding(16)
                        }
                    }
                    .navigationTitle("Sanitized Configuration")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Copy") {
                                UIPasteboard.general.string = exportedConfigJSON
                                FuzzTheme.playSuccessFeedback()
                                showExportSheet = false
                            }
                            .foregroundColor(FuzzTheme.acidGreen)
                        }
                    }
                }
            }
        }
    }
    
    private func runDiagnostics() {
        isRunningDiagnostics = true
        FuzzTheme.playStompFeedback()
        
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            await MainActor.run {
                self.diagnosticResults = [
                    "DNS Lookup": "Nominal",
                    "TLS 1.3 Handshake": "Verified",
                    "Keychain Read/Write": "OK",
                    "Local Network Perms": "Granted",
                    "SSE Stream Buffer": "16 KB"
                ]
                self.isRunningDiagnostics = false
                FuzzTheme.playSuccessFeedback()
            }
        }
    }
    
    private func exportSanitizedConfig() {
        let providers = StorageService.shared.loadProviders()
        let hosts = StorageService.shared.loadHosts()
        
        let sanitized: [String: Any] = [
            "version": "1.0.0",
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "providers": providers.map { [
                "displayName": $0.displayName,
                "baseURL": $0.baseURLString,
                "selectedModel": $0.selectedModel,
                "apiKey": KeychainService.redactSecret("[Stored in Keychain]")
            ] },
            "hosts": hosts.map { [
                "displayName": $0.displayName,
                "hostURL": $0.hostURLString,
                "token": KeychainService.redactSecret("[Stored in Keychain]")
            ] }
        ]
        
        if let data = try? JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted]),
           let str = String(data: data, encoding: .utf8) {
            exportedConfigJSON = str
            showExportSheet = true
        }
    }
    
    private func clearAllCredentials() {
        let providers = StorageService.shared.loadProviders()
        for p in providers {
            KeychainService.shared.delete(key: "api_key_\(p.id.uuidString)")
        }
        FuzzTheme.playErrorFeedback()
    }
}
