import SwiftUI
import FuzzCodeCore

public struct IntegrationsView: View {
    private enum Connector: String, Identifiable {
        case mcp
        case github
        case skills

        var id: String { rawValue }
    }

    @State private var mcpServers: [MCPServerConfig] = []
    @State private var githubConfig = GitHubConfig()
    @State private var isMCPLoaded = false
    @State private var isGitHubLoaded = false
    @State private var hasAttemptedInitialLoad = false
    @State private var mcpLoadError: String?
    @State private var githubLoadError: String?
    @State private var mcpSaveError: String?
    @State private var githubSaveError: String?
    @State private var activeConnector: Connector?
    @State private var connectorToPersist: Connector?

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()

                List {
                    Section {
                        connectorRow(
                            title: "MCP Servers",
                            detail: isMCPLoaded ? "\(mcpServers.count) configured" : "Configuration unavailable",
                            symbol: "network",
                            isEnabled: isMCPLoaded
                        ) {
                            present(.mcp)
                        }

                        connectorRow(
                            title: "GitHub",
                            detail: isGitHubLoaded ? "Manage GitHub connection" : "Configuration unavailable",
                            symbol: "chevron.left.forwardslash.chevron.right",
                            isEnabled: isGitHubLoaded
                        ) {
                            present(.github)
                        }
                    } header: {
                        Text("Connectors")
                            .fontDesign(.monospaced)
                            .foregroundStyle(FuzzTheme.textSecondary)
                    }
                    .listRowBackground(FuzzTheme.surface)

                    Section {
                        connectorRow(
                            title: "Skills",
                            detail: "Manage reusable Markdown instructions",
                            symbol: "text.book.closed",
                            isEnabled: true
                        ) {
                            present(.skills)
                        }
                    } header: {
                        Text("Library")
                            .fontDesign(.monospaced)
                            .foregroundStyle(FuzzTheme.textSecondary)
                    }
                    .listRowBackground(FuzzTheme.surface)

                    if mcpLoadError != nil || githubLoadError != nil ||
                        mcpSaveError != nil || githubSaveError != nil {
                        Section("Configuration") {
                            if let mcpLoadError {
                                storageErrorRow(
                                    title: "MCP configuration couldn't be loaded",
                                    message: mcpLoadError,
                                    buttonTitle: "Retry MCP Load",
                                    action: loadMCPServers
                                )
                            }

                            if let githubLoadError {
                                storageErrorRow(
                                    title: "GitHub configuration couldn't be loaded",
                                    message: githubLoadError,
                                    buttonTitle: "Retry GitHub Load",
                                    action: loadGitHubConfig
                                )
                            }

                            if let mcpSaveError {
                                storageErrorRow(
                                    title: "MCP changes weren't saved; they remain available in this screen",
                                    message: mcpSaveError,
                                    buttonTitle: "Retry MCP Save",
                                    action: saveMCPServers
                                )
                            }

                            if let githubSaveError {
                                storageErrorRow(
                                    title: "GitHub changes weren't saved; they remain available in this screen",
                                    message: githubSaveError,
                                    buttonTitle: "Retry GitHub Save",
                                    action: saveGitHubConfig
                                )
                            }
                        }
                        .listRowBackground(FuzzTheme.surface)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Integrations")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                guard !hasAttemptedInitialLoad else { return }
                hasAttemptedInitialLoad = true
                loadMCPServers()
                loadGitHubConfig()
            }
            .sheet(item: $activeConnector, onDismiss: persistPresentedConnector) { connector in
                switch connector {
                case .mcp:
                    MCPConnectorView(servers: $mcpServers)
                case .github:
                    GitHubConnectorView(config: $githubConfig)
                case .skills:
                    SkillsLibraryView()
                }
            }
        }
    }

    private func connectorRow(
        title: String,
        detail: String,
        symbol: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(FuzzTheme.electricPurple)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FuzzTheme.textPrimary)
                    Text(detail)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(FuzzTheme.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FuzzTheme.textMuted)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.65)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityHint("Opens \(title) settings")
    }

    private func storageErrorRow(
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

    private func present(_ connector: Connector) {
        connectorToPersist = connector
        activeConnector = connector
    }

    private func loadMCPServers() {
        do {
            mcpServers = try StorageService.shared.loadMCPServers().map { server in
                var server = server
                server.markUnverified()
                return server
            }
            isMCPLoaded = true
            mcpLoadError = nil
        } catch {
            isMCPLoaded = false
            mcpLoadError = error.localizedDescription
        }
    }

    private func loadGitHubConfig() {
        do {
            githubConfig = try StorageService.shared.loadGitHubConfig()
            isGitHubLoaded = true
            githubLoadError = nil
        } catch {
            isGitHubLoaded = false
            githubLoadError = error.localizedDescription
        }
    }

    private func persistPresentedConnector() {
        defer { connectorToPersist = nil }

        switch connectorToPersist {
        case .mcp:
            saveMCPServers()
        case .github:
            saveGitHubConfig()
        case .skills:
            break
        case nil:
            break
        }
    }

    private func saveMCPServers() {
        do {
            try StorageService.shared.saveMCPServers(mcpServers)
            mcpSaveError = nil
        } catch {
            mcpSaveError = error.localizedDescription
        }
    }

    private func saveGitHubConfig() {
        do {
            try StorageService.shared.saveGitHubConfig(githubConfig)
            githubSaveError = nil
        } catch {
            githubSaveError = error.localizedDescription
        }
    }
}
