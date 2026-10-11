import SwiftUI
import FuzzCodeCore

public struct HomeView: View {
    @Binding public var selectedTab: Int
    @State private var providers: [ProviderConfig] = []
    @State private var hosts: [OpenCodeHostConfig] = []
    @State private var conversations: [ChatConversation] = []
    @State private var activeSessions: [AgentSession] = []
    
    public init(selectedTab: Binding<Int>) {
        self._selectedTab = selectedTab
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        telemetryStrip
                        quickActionsGrid
                        activeSessionsSection
                        recentConversationsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
            .navigationTitle("FUZZCODE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        selectedTab = 4 // Settings
                    }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(FuzzTheme.textSecondary)
                    }
                }
            }
        }
        .onAppear {
            loadDashboardData()
        }
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("CONTROL CENTER")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(FuzzTheme.acidGreen)
            
            Text("A little distortion. A lot of control.")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(FuzzTheme.textPrimary)
        }
    }
    
    private var telemetryStrip: some View {
        HStack(spacing: 12) {
            telemetryCard(
                title: "PROVIDERS",
                value: "\(providers.filter { $0.isEnabled }.count) Active",
                icon: "cpu",
                tint: FuzzTheme.acidGreen
            )
            telemetryCard(
                title: "OPENCODE",
                value: hosts.first?.isConnected == true ? "Paired" : "Standby",
                icon: "terminal",
                tint: hosts.first?.isConnected == true ? FuzzTheme.acidGreen : FuzzTheme.electricPurple
            )
            telemetryCard(
                title: "SESSIONS",
                value: "\(activeSessions.count) Active",
                icon: "bolt.fill",
                tint: FuzzTheme.electricPurple
            )
        }
    }
    
    private func telemetryCard(title: String, value: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(tint)
                Spacer()
            }
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(FuzzTheme.textMuted)
            Text(value)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(FuzzTheme.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(FuzzTheme.surface)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(FuzzTheme.border, lineWidth: 1))
        )
    }
    
    private var quickActionsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("QUICK WORKFLOWS")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(FuzzTheme.textSecondary)
            
            HStack(spacing: 12) {
                actionButton(title: "New AI Chat", icon: "bubble.left.and.bubble.right.fill", color: FuzzTheme.acidGreen) {
                    selectedTab = 1
                }
                actionButton(title: "OpenCode Agent", icon: "terminal.fill", color: FuzzTheme.electricPurple) {
                    selectedTab = 2
                }
            }
            HStack(spacing: 12) {
                actionButton(title: "Endpoints", icon: "network", color: FuzzTheme.textSecondary) {
                    selectedTab = 3
                }
                actionButton(title: "Diff Review", icon: "arrow.triangle.pull", color: FuzzTheme.textSecondary) {
                    selectedTab = 2 // Agents tab handles live git diff
                }
            }
        }
    }
    
    private func actionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: {
            FuzzTheme.playStompFeedback()
            action()
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(FuzzTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(FuzzTheme.textMuted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(FuzzTheme.surfaceRaised)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(FuzzTheme.border, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
    
    private var activeSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ACTIVE AGENT SESSIONS")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(FuzzTheme.textSecondary)
                Spacer()
                Button("View All") { selectedTab = 2 }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FuzzTheme.acidGreen)
            }
            
            if activeSessions.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "circle.slash")
                        .font(.system(size: 24))
                        .foregroundColor(FuzzTheme.textMuted)
                    Text("No running agent sessions")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(FuzzTheme.textSecondary)
                    Text("Connect to an OpenCode host to dispatch tasks.")
                        .font(.system(size: 11))
                        .foregroundColor(FuzzTheme.textMuted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(FuzzTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FuzzTheme.border, lineWidth: 1))
                )
            } else {
                ForEach(activeSessions) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(session.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(FuzzTheme.textPrimary)
                            Text(session.workspacePath)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(FuzzTheme.textMuted)
                        }
                        Spacer()
                        Text(session.status.rawValue.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(FuzzTheme.acidGreen)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(FuzzTheme.surface)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(FuzzTheme.border, lineWidth: 1))
                    )
                }
            }
        }
    }
    
    private var recentConversationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("RECENT CONVERSATIONS")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(FuzzTheme.textSecondary)
                Spacer()
                Button("Chat") { selectedTab = 1 }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(FuzzTheme.acidGreen)
            }
            
            if conversations.isEmpty {
                Text("No recent conversations. Tap 'New AI Chat' to start.")
                    .font(.system(size: 12))
                    .foregroundColor(FuzzTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(conversations.prefix(3)) { conv in
                    Button(action: {
                        selectedTab = 1
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(conv.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(FuzzTheme.textPrimary)
                                    .lineLimit(1)
                                Text(conv.modelId)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(FuzzTheme.electricPurple)
                            }
                            Spacer()
                            Text(DateFormatter.localizedString(from: conv.updatedAt, dateStyle: .short, timeStyle: .none))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(FuzzTheme.textMuted)
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(FuzzTheme.surface)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(FuzzTheme.border, lineWidth: 1))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    
    private func loadDashboardData() {
        providers = StorageService.shared.loadProviders()
        hosts = StorageService.shared.loadHosts()
        conversations = StorageService.shared.loadConversations()
    }
}
