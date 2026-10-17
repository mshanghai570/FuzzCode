import SwiftUI
import CoreImage
import FuzzCodeCore
#if canImport(UIKit)
import UIKit
#endif

public struct AgentsView: View {
    @State private var hosts: [OpenCodeHostConfig] = []
    @State private var selectedHost: OpenCodeHostConfig?
    @State private var sessions: [AgentSession] = []
    @State private var selectedSession: AgentSession?
    
    @State private var showNewSessionSheet = false
    @State private var showPairHostSheet = false
    @State private var showDiffSheet = false
    @State private var activeGitStatus: GitStatusSummary?
    @State private var instructionInput: String = ""
    @State private var isExecutingTask: Bool = false
    @State private var permissionToResolve: PermissionRequest?
    @State private var showProviderConnectSheet = false
    @State private var showAgentPickerSheet = false
    @State private var showProviderSelectionSheet = false
    @State private var enabledProviders: [ProviderConfig] = []
    @State private var selectedProviderID: UUID?
    @State private var providerSetupError: String?
    @State private var showResumeSheet = false
    @State private var showQRSheet = false
    @State private var nativeEngine: NativeAgentEngine?
    @State private var nativeEngineID: UUID?
    @State private var activeNativeWorkspace: WorkspaceManager?
    @State private var showPublishReview = false
    @State private var publishBranch = "fuzzcode/change"
    @State private var publishCommitMessage = "Changes from FuzzCode"
    @State private var publishPullRequestTitle = "Changes from FuzzCode"
    @State private var publishPullRequestBody = "Reviewed in FuzzCode."
    @State private var publishError: String?
    @State private var isPublishing = false
    @State private var remoteConnection: (any AgentConnection)?
    @State private var negotiatedCapabilities: Set<AgentCapability> = []
    @State private var resumedSessions: [AgentSession] = []
    @State private var resumeError: String?
    @FocusState private var instructionFocused: Bool
    private let permissionBridge = PermissionBridge()
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                
                if selectedSession == nil {
                    connectionSelectionState
                } else {
                    mainAgentConsole
                }
            }
            .navigationTitle("Coding Agents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showAgentPickerSheet = true }) {
                        Image(systemName: "link.badge.plus")
                            .foregroundColor(FuzzTheme.acidGreen)
                    }
                    .accessibilityLabel("Add connection")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showNewSessionSheet = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(FuzzTheme.acidGreen)
                    }
                }
            }
            .sheet(isPresented: $showPairHostSheet) {
                PairHostSheet(onPaired: { host in
                    hosts.append(host)
                    StorageService.shared.saveHosts(hosts)
                    selectHost(host)
                    showNewSessionSheet = true
                })
            }
            .sheet(isPresented: $showProviderConnectSheet) {
                EndpointConfigSheet(provider: nil) { saved in
                    var stored = StorageService.shared.loadProviders()
                    stored.append(saved)
                    StorageService.shared.saveProviders(stored)
                    enabledProviders = stored.filter(\.isEnabled)
                }
            }
            .sheet(isPresented: $showAgentPickerSheet) {
                AgentPickerSheet(onPaired: { host in
                    hosts.append(host)
                    StorageService.shared.saveHosts(hosts)
                    selectHost(host)
                    showAgentPickerSheet = false
                    showNewSessionSheet = true
                })
            }
            .sheet(isPresented: $showProviderSelectionSheet) {
                NativeProviderSelectionSheet(providers: enabledProviders, errorMessage: providerSetupError) { provider in
                    showProviderSelectionSheet = false
                    startNativeAgent(provider: provider)
                }
            }
            .sheet(isPresented: $showResumeSheet) {
                ResumeSessionSheet(sessions: resumedSessions, errorMessage: resumeError) { session in
                    selectedSession = session
                    showResumeSheet = false
                }
            }
            .sheet(isPresented: $showQRSheet) {
                if let host = selectedHost {
                    QRShareSheet(host: host) { imported in
                        hosts.append(imported)
                        StorageService.shared.saveHosts(hosts)
                        selectHost(imported)
                        showQRSheet = false
                    }
                }
            }
            .sheet(isPresented: $showNewSessionSheet) {
                let connection = activeConnection()
                NewSessionSheet(
                    defaultWorkspace: selectedHost?.currentWorkspace ?? "",
                    fallbackHostId: selectedHost?.id ?? nativeEngineID ?? UUID(),
                    createSession: connection.map { conn in
                        { workspace, prompt in
                            try await conn.createSession(workspacePath: workspace, prompt: prompt)
                        }
                    },
                    onCreated: { newSession in
                        sessions.insert(newSession, at: 0)
                        selectedSession = newSession
                    }
                )
            }
            .sheet(isPresented: $showDiffSheet) {
                if let git = activeGitStatus {
                    CodeDiffView(summary: git)
                }
            }
            .sheet(isPresented: $showPublishReview) {
                publishReviewSheet
            }
            .sheet(item: $permissionToResolve) { perm in
                PermissionApprovalSheet(request: perm) { decision in
                    resolvePermission(decision)
                }
            }
            .onAppear(perform: loadData)
        }
    }
    
    private var connectionSelectionState: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "cpu")
                    .font(.system(size: 44))
                    .foregroundColor(FuzzTheme.acidGreen)
                    .padding(.top, 24)

                VStack(spacing: 8) {
                    Text("CHOOSE A CONNECTION")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(FuzzTheme.textPrimary)

                    Text("Chat with an AI provider directly, connect a remote coding agent, or run the on-device FuzzCode agent. Pairing is optional.")
                        .font(.system(size: 13))
                        .foregroundColor(FuzzTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                connectionCard(
                    title: "Connect AI Provider",
                    detail: "OpenAI, Anthropic, Gemini, OpenRouter, Groq, or custom",
                    symbol: "key.fill"
                ) {
                    showProviderConnectSheet = true
                }

                connectionCard(
                    title: "Code with an API key",
                    detail: "Choose a provider and model; files stay in the app sandbox",
                    symbol: "key.fill"
                ) {
                    beginNativeAgentSetup()
                }

                ForEach(hosts) { host in
                    connectionCard(
                        title: host.displayName,
                        detail: "Remote \(host.resolvedKind.displayName) · \(host.resolvedProtocol.displayName)",
                        symbol: "server.rack"
                    ) {
                        selectHost(host)
                        showNewSessionSheet = true
                    }
                }

                connectionCard(
                    title: "Add remote runtime (advanced)",
                    detail: "OpenCode server, Codex app-server, or ACP WebSocket bridge",
                    symbol: "plus"
                ) {
                    showAgentPickerSheet = true
                }
            }
            .padding(.bottom, 24)
        }
    }

    private func connectionCard(title: String, detail: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundColor(FuzzTheme.acidGreen)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(FuzzTheme.textPrimary)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(FuzzTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(FuzzTheme.textMuted)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(FuzzTheme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(FuzzTheme.border, lineWidth: 1))
            )
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
    }
    
    private var mainAgentConsole: some View {
        VStack(spacing: 0) {
            hostStatusBar
            
            if let session = selectedSession {
                sessionDetailView(session)
            } else {
                noSessionSelectedView
            }
            
            agentInstructionInputBar
        }
    }
    
    private var activeCapabilities: [AgentCapability] {
        if let nativeID = nativeEngineID, selectedSession?.hostId == nativeID {
            return [.sessions, .streaming, .toolEvents, .cancellation, .fileDiffs, .permissionRequests, .sessionResumption]
        }
        if !negotiatedCapabilities.isEmpty {
            return negotiatedCapabilities.sorted { $0.rawValue < $1.rawValue }
        }
        return selectedHost?.capabilities ?? []
    }

    private var hostStatusBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
            Menu {
                ForEach(hosts) { host in
                    Button(action: { selectHost(host) }) {
                        Text(host.displayName)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(selectedHost?.isConnected == true ? FuzzTheme.acidGreen : FuzzTheme.electricPurple)
                        .frame(width: 8, height: 8)
                    Text(selectedHost?.displayName ?? "Select Host")
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

            Button(action: { resumeSessions() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 11))
                    Text("Sessions")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(FuzzTheme.electricPurple)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(FuzzTheme.surfaceRaised)
                .cornerRadius(6)
            }
            .accessibilityLabel("Resume session")

            if selectedHost != nil {
                Button(action: { showQRSheet = true }) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 11))
                        .foregroundColor(FuzzTheme.acidGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(FuzzTheme.surfaceRaised)
                        .cornerRadius(6)
                }
                .accessibilityLabel("Share pairing QR code")
            }

            Button(action: {
                fetchSessionGitDiff()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.pull")
                        .font(.system(size: 11))
                    Text("Diffs")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(FuzzTheme.acidGreen)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(FuzzTheme.surfaceRaised)
                .cornerRadius(6)
            }

            if nativeEngine != nil {
                Button("Publish") { fetchSessionGitDiffForPublish() }
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(FuzzTheme.warningAmber)
                    .accessibilityHint("Review all changes before creating a GitHub branch and pull request")
            }
            }

            if !activeCapabilities.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(activeCapabilities, id: \.self) { cap in
                            Text(cap.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(FuzzTheme.textSecondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(FuzzTheme.surfaceRaised)
                                .cornerRadius(4)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .accessibilityLabel("Agent capabilities")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(FuzzTheme.surface.opacity(0.8))
    }
    
    private func sessionDetailView(_ session: AgentSession) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Workspace banner
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WORKSPACE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(FuzzTheme.textMuted)
                        Text(session.workspacePath)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(FuzzTheme.textPrimary)
                    }
                    Spacer()
                    Text(session.status.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(statusColor(session.status))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(FuzzTheme.surface)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(FuzzTheme.border, lineWidth: 1))
                )
                
                // Pending permission banner if any
                if let perm = session.pendingPermission {
                    permissionAlertCard(perm)
                }
                
                // Timeline of messages & tool events
                ForEach(session.messages) { msg in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(msg.role == .user ? "INSTRUCTION" : "AGENT")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(msg.role == .user ? FuzzTheme.electricPurple : FuzzTheme.acidGreen)
                            Spacer()
                        }
                        Text(msg.content)
                            .font(.system(size: 13))
                            .foregroundColor(FuzzTheme.textPrimary)
                        
                        // Tool executions under this message
                        ForEach(msg.toolEvents) { tool in
                            toolEventRow(tool)
                        }
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(FuzzTheme.surfaceRaised)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(FuzzTheme.border, lineWidth: 1))
                    )
                }
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func permissionAlertCard(_ perm: PermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.shield.fill")
                    .foregroundColor(FuzzTheme.warningAmber)
                Text("PERMISSION REQUIRED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(FuzzTheme.warningAmber)
                Spacer()
            }
            Text("Tool: \(perm.toolName)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(FuzzTheme.textPrimary)
            Text(perm.commandOrPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(FuzzTheme.textSecondary)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.4))
                .cornerRadius(6)
            
            HStack(spacing: 8) {
                Button("Inspect & Resolve") {
                    permissionToResolve = perm
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(FuzzTheme.acidGreen)
                .cornerRadius(6)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(FuzzTheme.warningAmber.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(FuzzTheme.warningAmber.opacity(0.4), lineWidth: 1))
        )
    }
    
    private func toolEventRow(_ tool: AgentToolEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: toolIcon(tool.toolName))
                .font(.system(size: 11))
                .foregroundColor(FuzzTheme.electricPurple)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.toolName)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(FuzzTheme.textPrimary)
                if let out = tool.outputSnippet {
                    Text(out)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(FuzzTheme.textMuted)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(tool.status.rawValue.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(tool.status == .success ? FuzzTheme.acidGreen : FuzzTheme.textMuted)
        }
        .padding(8)
        .background(FuzzTheme.surface.opacity(0.6))
        .cornerRadius(6)
    }
    
    private var noSessionSelectedView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 36))
                .foregroundColor(FuzzTheme.textMuted)
            Text("No Active Session")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(FuzzTheme.textSecondary)
            Button("Start New Session") {
                showNewSessionSheet = true
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(FuzzTheme.acidGreen)
            Spacer()
        }
    }
    
    private var agentInstructionInputBar: some View {
        HStack(spacing: 8) {
            TextField("Give agent instructions (e.g. refactor auth)", text: $instructionInput)
                .focused($instructionFocused)
                .font(.system(size: 13))
                .foregroundColor(FuzzTheme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(FuzzTheme.surfaceRaised)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(FuzzTheme.border, lineWidth: 1))
                )
            
            if isExecutingTask {
                Button(action: cancelCurrentTask) {
                    Image(systemName: "stop.fill")
                        .foregroundColor(.black)
                        .frame(width: 34, height: 34)
                        .background(FuzzTheme.clippingRed)
                        .clipShape(Circle())
                }
            } else {
                Button(action: sendAgentInstruction) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.black)
                        .frame(width: 34, height: 34)
                        .background(instructionInput.isEmpty ? FuzzTheme.textMuted : FuzzTheme.acidGreen)
                        .clipShape(Circle())
                }
                .disabled(instructionInput.isEmpty || selectedSession == nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(FuzzTheme.surface)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(action: { instructionFocused = false }) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .foregroundColor(FuzzTheme.acidGreen)
                }
                .accessibilityLabel("Dismiss keyboard")
            }
        }
    }

    // MARK: - Actions
    
    private func activeConnection() -> (any AgentConnection)? {
        if let native = nativeEngine, let nativeID = nativeEngineID, selectedSession?.hostId == nativeID {
            return native
        }
        return remoteConnection
    }

    /// Builds the correct agent adapter for the host via the factory, preserving a
    /// stable connection identity so actor-backed transports keep their session state.
    private func selectHost(_ host: OpenCodeHostConfig?) {
        selectedHost = host
        guard let host else {
            remoteConnection = nil
            negotiatedCapabilities = []
            return
        }
        remoteConnection = try? makeRemoteAgentConnection(host: host)
        negotiatedCapabilities = Set(host.capabilities)
        nativeEngine = nil
        nativeEngineID = nil
        activeNativeWorkspace = nil
        selectedSession = nil
    }

    private func beginNativeAgentSetup() {
        enabledProviders = StorageService.shared.loadProviders().filter(\.isEnabled)
        providerSetupError = nil
        guard !enabledProviders.isEmpty else {
            showProviderConnectSheet = true
            return
        }
        if let configured = NativeAgentEngine.configuredProvider(from: enabledProviders, selectedProviderID: selectedProviderID) {
            startNativeAgent(provider: configured)
        } else {
            showProviderSelectionSheet = true
        }
    }

    private func startNativeAgent(provider requested: ProviderConfig) {
        providerSetupError = nil
        enabledProviders = StorageService.shared.loadProviders().filter(\.isEnabled)
        guard let config = NativeAgentEngine.configuredProvider(from: enabledProviders, selectedProviderID: requested.id) else {
            providerSetupError = "That provider is no longer enabled. Choose an enabled provider and try again."
            showProviderSelectionSheet = true
            return
        }
        selectedProviderID = config.id
        Task {
            do {
                let adapter = try makeAIProvider(config: config)
                let githubConfig = try? StorageService.shared.loadGitHubConfig()
                let workspaceId = githubConfig?.selectedRepo.map { "github-\($0.id)" } ?? UUID().uuidString
                let workspace = try WorkspaceManager(root: WorkspaceManager.defaultRoot(workspaceId: workspaceId))
                let bridge = permissionBridge
                let engine = NativeAgentEngine(provider: adapter, workspace: workspace) { request in
                    await bridge.request(request)
                }
                _ = try await engine.connect()
                let engineID = await engine.id
                let session = try await engine.createSession(workspacePath: "native:\(workspaceId)")
                await MainActor.run {
                    self.selectedHost = nil
                    self.remoteConnection = nil
                    self.negotiatedCapabilities = []
                    self.nativeEngine = engine
                    self.nativeEngineID = engineID
                    self.activeNativeWorkspace = workspace
                    self.selectedSession = session
                }
            } catch {
                await MainActor.run {
                    self.providerSetupError = error.localizedDescription
                    self.enabledProviders = StorageService.shared.loadProviders().filter(\.isEnabled)
                    self.showProviderSelectionSheet = true
                }
            }
        }
    }

    private func resumeSessions() {
        resumeError = nil
        resumedSessions = []
        Task {
            if let native = nativeEngine, let nativeID = nativeEngineID, selectedSession?.hostId == nativeID {
                let sessions = (try? await native.listSessions()) ?? []
                await MainActor.run {
                    self.resumedSessions = sessions
                    self.showResumeSheet = true
                }
                return
            }
            guard let host = selectedHost else { return }
            let connection: (any AgentConnection)?
            if let remoteConnection {
                connection = remoteConnection
            } else {
                connection = try? makeRemoteAgentConnection(host: host)
            }
            guard let connection else {
                await MainActor.run {
                    self.resumeError = AgentConnectionError.transportFailed("Invalid endpoint for \(host.displayName).").localizedDescription
                    self.showResumeSheet = true
                }
                return
            }
            do {
                let sessions = try await connection.listSessions()
                await MainActor.run {
                    self.resumedSessions = sessions
                    self.showResumeSheet = true
                }
            } catch {
                await MainActor.run {
                    self.resumeError = error.localizedDescription
                    self.showResumeSheet = true
                }
            }
        }
    }

    private func sendAgentInstruction() {
        let text = instructionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var session = selectedSession, let connection = activeConnection() else { return }
        instructionFocused = false
        instructionInput = ""
        FuzzTheme.playStompFeedback()
        
        let userMessage = AgentSessionMessage(role: .user, content: text)
        session.messages.append(userMessage)
        session.status = .running
        self.selectedSession = session
        self.isExecutingTask = true
        
        let agentMsgId = UUID().uuidString
        let agentMsg = AgentSessionMessage(id: agentMsgId, role: .assistant, content: "Starting execution...")
        session.messages.append(agentMsg)
        self.selectedSession = session
        
        Task {
            let stream = await connection.sendInstruction(sessionId: session.id, prompt: text)
            do {
                for try await event in stream {
                    await MainActor.run {
                        handleAgentEvent(event, agentMsgId: agentMsgId)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isExecutingTask = false
                }
            }
            await MainActor.run {
                self.isExecutingTask = false
            }
        }
    }
    
    private func handleAgentEvent(_ event: AgentEvent, agentMsgId: String) {
        guard var session = selectedSession else { return }
        switch event {
        case .textDelta(let delta):
            if let index = session.messages.firstIndex(where: { $0.id == agentMsgId }) {
                session.messages[index].content += delta
            }
        case .toolStarted(let tool):
            if let index = session.messages.firstIndex(where: { $0.id == agentMsgId }) {
                session.messages[index].toolEvents.append(tool)
            }
        case .permissionRequested(let perm):
            session.pendingPermission = perm
            session.status = .waitingPermission
            FuzzTheme.playErrorFeedback()
        case .statusChanged(let newStatus):
            session.status = newStatus
        case .gitUpdated(let git):
            self.activeGitStatus = git
        case .finished:
            session.status = .completed
            self.isExecutingTask = false
            FuzzTheme.playSuccessFeedback()
        default:
            break
        }
        self.selectedSession = session
    }
    
    private func resolvePermission(_ decision: PermissionDecision) {
        guard let perm = permissionToResolve, selectedSession != nil else { return }
        permissionToResolve = nil
        Task {
            await permissionBridge.resolve(decision)
            if let connection = activeConnection() {
                try? await connection.resolvePermission(requestId: perm.id, decision: decision, rationale: nil)
            }
            await MainActor.run {
                if var s = self.selectedSession {
                    s.pendingPermission = nil
                    s.status = .running
                    self.selectedSession = s
                }
            }
        }
    }

    private func cancelCurrentTask() {
        guard let session = selectedSession, let connection = activeConnection() else { return }
        Task {
            try? await connection.cancelTask(sessionId: session.id)
            await MainActor.run {
                self.isExecutingTask = false
                if var s = self.selectedSession {
                    s.status = .cancelled
                    self.selectedSession = s
                }
            }
        }
    }

    private func fetchSessionGitDiff() {
        guard let session = selectedSession, let connection = activeConnection() else { return }
        Task {
            if let git = try? await connection.fetchGitStatus(sessionId: session.id) {
                await MainActor.run {
                    self.activeGitStatus = git
                    self.showDiffSheet = true
                }
            }
        }
    }

    private func fetchSessionGitDiffForPublish() {
        guard let session = selectedSession, let connection = activeConnection() else { return }
        Task {
            do {
                let summary = try await connection.fetchGitStatus(sessionId: session.id)
                await MainActor.run { activeGitStatus = summary; showPublishReview = true }
            } catch {
                await MainActor.run { publishError = error.localizedDescription }
            }
        }
    }

    private var publishReviewSheet: some View {
        NavigationStack {
            Form {
                if let summary = activeGitStatus {
                    Section("Changes to publish") {
                        Text("\(summary.changedFiles.count) files · +\(summary.changedFiles.reduce(0) { $0 + $1.additions }) / -\(summary.changedFiles.reduce(0) { $0 + $1.deletions })")
                        ForEach(summary.changedFiles) { change in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(change.filePath).font(.caption.monospaced())
                                Text(change.patch).font(.caption2.monospaced()).textSelection(.enabled)
                            }
                        }
                    }
                }
                Section("Branch and pull request") {
                    TextField("Branch name", text: $publishBranch)
                    TextField("Commit message", text: $publishCommitMessage)
                    TextField("Pull request title", text: $publishPullRequestTitle)
                    TextField("Pull request description", text: $publishPullRequestBody, axis: .vertical)
                }
                if let publishError { Section { Text(publishError).foregroundStyle(.red) } }
                Section {
                    Button(isPublishing ? "Publishing…" : "Approve diff and publish") { publishReviewedChanges() }
                        .disabled(isPublishing || activeGitStatus?.changedFiles.isEmpty != false)
                } footer: {
                    Text("This creates a branch, a commit, and a pull request on GitHub. The complete diff above is the exact set approved.")
                }
            }
            .navigationTitle("Review GitHub Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showPublishReview = false } } }
        }
    }

    private func publishReviewedChanges() {
        let githubConfig = try? StorageService.shared.loadGitHubConfig()
        guard let summary = activeGitStatus, let workspace = activeNativeWorkspace,
              let repo = githubConfig?.selectedRepo,
              let slash = repo.fullName.firstIndex(of: "/"),
              let token = KeychainService.shared.get(key: githubConfig?.keychainTokenKey ?? "fuzzcode_github_token") else {
            publishError = "Connect GitHub and import a repository before publishing."
            return
        }
        let approvedSummary = summary
        isPublishing = true
        publishError = nil
        Task {
            do {
                guard try workspace.changeSummary() == approvedSummary else { throw GitHubClientError.reviewRequired }
                let changes = try workspace.reviewedChanges()
                guard changes.count == approvedSummary.changedFiles.count else { throw GitHubClientError.reviewRequired }
                let client = GitHubClient(token: token)
                let result = try await client.publishChanges(
                    owner: String(repo.fullName[..<slash]),
                    repo: String(repo.fullName[repo.fullName.index(after: slash)...]),
                    baseBranch: repo.defaultBranch,
                    branchName: publishBranch,
                    commitMessage: publishCommitMessage,
                    pullRequestTitle: publishPullRequestTitle,
                    pullRequestBody: publishPullRequestBody,
                    changes: changes,
                    reviewApproved: true)
                await MainActor.run {
                    publishError = "Pull request #\(result.pullRequest.number) created."
                    isPublishing = false
                }
            } catch {
                await MainActor.run {
                    publishError = "Could not publish reviewed changes: \(error.localizedDescription)"
                    isPublishing = false
                }
            }
        }
    }
    
    private func loadData() {
        hosts = StorageService.shared.loadHosts()
        enabledProviders = StorageService.shared.loadProviders().filter(\.isEnabled)
        selectedProviderID = nil
        selectHost(nil)
    }
    
    private func statusColor(_ status: SessionStatus) -> Color {
        switch status {
        case .running: return FuzzTheme.acidGreen
        case .waitingPermission: return FuzzTheme.warningAmber
        case .completed: return FuzzTheme.electricPurple
        case .cancelled, .failed: return FuzzTheme.clippingRed
        default: return FuzzTheme.textMuted
        }
    }
    
    private func toolIcon(_ toolName: String) -> String {
        switch toolName.lowercased() {
        case "bash", "execute_command": return "terminal"
        case "file_edit", "write_to_file": return "square.and.pencil"
        case "ripgrep", "search": return "magnifyingglass"
        default: return "wrench"
        }
    }
}

// Subviews
struct PairHostSheet: View {
    let title: String
    let kind: AgentConnectionKind
    let defaultPort: Int?
    let capabilities: [AgentCapability]
    let onPaired: (OpenCodeHostConfig) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var displayName: String
    @State private var hostURL: String
    @State private var token = ""
    @State private var username = ""
    @State private var selectedProtocol: RemoteAgentProtocol
    @State private var allowsInsecure: Bool
    @State private var isTesting = false
    @State private var testSucceeded = false
    @State private var negotiated: Set<AgentCapability> = []
    @State private var errorMessage: String?
    @State private var tokenKey = "agent_token_\(UUID().uuidString)"

    init(
        title: String = "Pair Agent Host",
        kind: AgentConnectionKind = .opencode,
        initialName: String = "MacBook Pro (OpenCode)",
        initialHostURL: String? = nil,
        initialProtocol: RemoteAgentProtocol? = nil,
        defaultPort: Int? = 4096,
        capabilities: [AgentCapability] = [.sessions, .streaming, .toolEvents, .cancellation, .fileDiffs, .permissionRequests, .gitStatus],
        allowsInsecureTransport: Bool = false,
        onPaired: @escaping (OpenCodeHostConfig) -> Void
    ) {
        self.title = title
        self.kind = kind
        self.defaultPort = defaultPort
        self.capabilities = capabilities
        self.onPaired = onPaired
        let proto = initialProtocol ?? .recommended(for: kind)
        _displayName = State(initialValue: initialName)
        _selectedProtocol = State(initialValue: proto)
        _allowsInsecure = State(initialValue: allowsInsecureTransport)
        _hostURL = State(initialValue: initialHostURL ?? Self.defaultURL(for: proto, port: defaultPort))
    }

    static func defaultURL(for proto: RemoteAgentProtocol, port: Int?) -> String {
        let resolvedPort = port ?? (proto.isWebSocket ? 8765 : 4096)
        let scheme: String
        switch proto {
        case .legacyOpenCode: scheme = "http"
        case .openCodeHTTP: scheme = "https"
        case .codexAppServer, .acpWebSocket: scheme = "wss"
        }
        return "\(scheme)://192.168.1.100:\(resolvedPort)"
    }

    private var protocolOptions: [RemoteAgentProtocol] {
        switch kind {
        case .opencode: return [.openCodeHTTP, .legacyOpenCode]
        case .codex: return [.codexAppServer, .acpWebSocket]
        case .claudeCode: return [.acpWebSocket, .codexAppServer]
        case .customACP: return [.acpWebSocket, .openCodeHTTP]
        case .native: return [.acpWebSocket]
        }
    }

    private var composedHost: OpenCodeHostConfig {
        OpenCodeHostConfig(
            displayName: displayName,
            hostURLString: hostURL,
            authTokenKey: tokenKey,
            isConnected: testSucceeded,
            capabilities: negotiated.isEmpty ? capabilities : Array(negotiated),
            agentKind: kind,
            remoteProtocol: selectedProtocol,
            allowsInsecureTransport: allowsInsecure ? true : nil,
            username: selectedProtocol == .openCodeHTTP && !username.isEmpty ? username : nil
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                Form {
                    Section("Agent") {
                        LabeledContent("Type", value: kind.displayName)
                        if protocolOptions.count > 1 {
                            Picker("Transport", selection: $selectedProtocol) {
                                ForEach(protocolOptions, id: \.self) { proto in
                                    Text(proto.displayName).tag(proto)
                                }
                            }
                        } else {
                            LabeledContent("Transport", value: selectedProtocol.displayName)
                        }
                        Text(selectedProtocol.isWebSocket
                             ? "Uses a persistent WebSocket JSON-RPC session."
                             : "Uses an authenticated HTTP API.")
                            .font(.caption)
                            .foregroundColor(FuzzTheme.textMuted)
                    }
                    .listRowBackground(FuzzTheme.surface)

                    Section("Host Details") {
                        TextField("Host Display Name", text: $displayName)
                        TextField(selectedProtocol.isWebSocket ? "Endpoint (e.g. wss://host:8765)" : "Endpoint (e.g. https://host:4096)", text: $hostURL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if selectedProtocol == .openCodeHTTP {
                            TextField("Username (optional)", text: $username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        SecureField("Auth Token", text: $token)
                        Toggle("Allow insecure local transport", isOn: $allowsInsecure)
                        if allowsInsecure {
                            Text("Cleartext sends the token unencrypted. Only enable on a trusted LAN.")
                                .font(.caption)
                                .foregroundColor(FuzzTheme.warningAmber)
                        }
                    }
                    .listRowBackground(FuzzTheme.surface)

                    Section("Verification") {
                        Button {
                            runTest()
                        } label: {
                            HStack {
                                if isTesting { ProgressView().controlSize(.small) }
                                Text(isTesting ? "Testing…" : "Test Connection")
                            }
                        }
                        .disabled(isTesting)
                        if testSucceeded {
                            Label("Connected - \(negotiated.count) capabilities negotiated", systemImage: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundColor(FuzzTheme.acidGreen)
                        }
                        if let err = errorMessage {
                            Text(err)
                                .foregroundColor(FuzzTheme.clippingRed)
                                .font(.system(size: 12))
                        }
                        if !testSucceeded && errorMessage != nil {
                            Button("Save Anyway") { save(force: true) }
                                .foregroundColor(FuzzTheme.warningAmber)
                        }
                    }
                    .listRowBackground(FuzzTheme.surface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .foregroundColor(FuzzTheme.acidGreen)
                }
            }
        }
    }

    private func runTest() {
        guard !isTesting else { return }
        isTesting = true
        errorMessage = nil
        testSucceeded = false
        let host = composedHost
        KeychainService.shared.save(key: tokenKey, secret: token)
        Task {
            do {
                let connection = try makeRemoteAgentConnection(host: host)
                let metadata = try await connection.connect()
                await MainActor.run {
                    self.negotiated = Set(metadata.capabilities)
                    self.testSucceeded = true
                    self.isTesting = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isTesting = false
                }
            }
        }
    }

    private func save(force: Bool = false) {
        guard testSucceeded || force else {
            errorMessage = "Test the connection first, or tap Save Anyway."
            return
        }
        KeychainService.shared.save(key: tokenKey, secret: token)
        onPaired(composedHost)
        dismiss()
    }
}

struct NewSessionSheet: View {
    let defaultWorkspace: String
    let fallbackHostId: UUID
    let createSession: ((String, String?) async throws -> AgentSession)?
    let onCreated: (AgentSession) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var workspace: String
    @State private var initialPrompt = ""
    @State private var isCreating = false
    @State private var errorMessage: String?

    init(
        defaultWorkspace: String = "",
        fallbackHostId: UUID = UUID(),
        createSession: ((String, String?) async throws -> AgentSession)? = nil,
        onCreated: @escaping (AgentSession) -> Void
    ) {
        self.defaultWorkspace = defaultWorkspace
        self.fallbackHostId = fallbackHostId
        self.createSession = createSession
        self.onCreated = onCreated
        _workspace = State(initialValue: defaultWorkspace.isEmpty ? "/workspace" : defaultWorkspace)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                Form {
                    Section("Session Setup") {
                        TextField("Workspace Directory", text: $workspace)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Initial Goal / Task", text: $initialPrompt)
                    }
                    .listRowBackground(FuzzTheme.surface)

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundColor(FuzzTheme.clippingRed)
                            .font(.system(size: 12))
                            .listRowBackground(FuzzTheme.surface)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Agent Session")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        start()
                    } label: {
                        if isCreating { ProgressView().controlSize(.small) } else { Text("Start") }
                    }
                    .disabled(isCreating)
                    .foregroundColor(FuzzTheme.acidGreen)
                }
            }
        }
    }

    private func start() {
        let directory = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        let goal = initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let createSession else {
            onCreated(AgentSession(hostId: fallbackHostId,
                                   title: goal.isEmpty ? "Workspace Session" : goal,
                                   workspacePath: directory))
            dismiss()
            return
        }
        isCreating = true
        errorMessage = nil
        Task {
            do {
                let session = try await createSession(directory, goal.isEmpty ? nil : goal)
                await MainActor.run {
                    self.isCreating = false
                    onCreated(session)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.isCreating = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct PermissionApprovalSheet: View {
    let request: PermissionRequest
    let onDecision: (PermissionDecision) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                VStack(spacing: 20) {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 40))
                        .foregroundColor(FuzzTheme.warningAmber)
                    
                    Text("Interactive Permission Gate")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(FuzzTheme.textPrimary)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COMMAND / ACTION:")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(FuzzTheme.textMuted)
                        Text(request.commandOrPath)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(FuzzTheme.acidGreen)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(FuzzTheme.surfaceRaised)
                            .cornerRadius(8)
                    }
                    
                    HStack(spacing: 12) {
                        Button("Deny") {
                            onDecision(.deny)
                            dismiss()
                        }
                        .foregroundColor(FuzzTheme.clippingRed)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(FuzzTheme.surfaceRaised)
                        .cornerRadius(8)
                        
                        Button("Allow Once") {
                            onDecision(.allowOnce)
                            dismiss()
                        }
                        .foregroundColor(.black)
                        .font(.system(size: 13, weight: .bold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(FuzzTheme.acidGreen)
                        .cornerRadius(8)
                    }
                }
                .padding(24)
            }
            .navigationTitle("Security Gate")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Connection selection

/// Bridges native-engine permission requests to the SwiftUI approval sheet.
actor PermissionBridge {
    private var continuation: CheckedContinuation<PermissionDecision, Never>?

    func request(_ request: PermissionRequest) async -> PermissionDecision {
        await withCheckedContinuation { cont in
            continuation = cont
        }
    }

    func resolve(_ decision: PermissionDecision) {
        continuation?.resume(returning: decision)
        continuation = nil
    }
}

struct NativeProviderSelectionSheet: View {
    let providers: [ProviderConfig]
    let errorMessage: String?
    let onSelect: (ProviderConfig) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                        Text("Check the provider API key and model endpoint, then retry.")
                            .font(.caption)
                    }
                }
                Section {
                    ForEach(providers) { provider in
                        Button {
                            onSelect(provider)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(provider.displayName).font(.headline)
                                    Spacer()
                                    Text(provider.resolvedKind.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(provider.selectedModel).font(.caption.monospaced())
                                Text(provider.baseURLString)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Direct API provider")
                } footer: {
                    Text("The API key authenticates directly to this model provider. FuzzCode runs the coding tools in its sandbox; this is not an ACP or OpenCode server connection.")
                }
            }
            .navigationTitle("Choose Provider")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct AgentPickerSheet: View {
    let onPaired: (OpenCodeHostConfig) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var selectedDescriptor: RemoteAgentDescriptor?
    @State private var selectedProtocol: RemoteAgentProtocol?
    @State private var showManualPair = false
    @State private var discovered: [DiscoveredAgent] = []
    @State private var isScanning = false
    @State private var pendingDiscovered: DiscoveredAgent?

    var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                List {
                    Section("Advanced · Remote Runtime") {
                        Text("Connect to a running agent server using its server credential. Provider API keys belong in the direct provider setup and are never treated as ACP credentials.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        ForEach(RemoteAgentDescriptor.all, id: \.id) { descriptor in
                            Button(action: {
                                selectedDescriptor = descriptor
                                selectedProtocol = .recommended(for: descriptor.kind)
                                pendingDiscovered = nil
                                showManualPair = true
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(descriptor.kind.displayName)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundColor(FuzzTheme.textPrimary)
                                        if descriptor.isExperimental {
                                            Text("EXPERIMENTAL")
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                .foregroundColor(FuzzTheme.warningAmber)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(FuzzTheme.warningAmber.opacity(0.15))
                                                .cornerRadius(4)
                                        }
                                    }
                                    Text(descriptor.notes)
                                        .font(.system(size: 11))
                                        .foregroundColor(FuzzTheme.textSecondary)
                                }
                            }
                            .listRowBackground(FuzzTheme.surface)
                        }
                    }

                    Section("LAN Discovery (Experimental)") {
                        Button(action: scanLAN) {
                            HStack {
                                Image(systemName: "wifi")
                                    .foregroundColor(FuzzTheme.acidGreen)
                                Text(isScanning ? "Scanning…" : "Scan Local Network")
                                    .foregroundColor(FuzzTheme.textPrimary)
                            }
                        }
                        .listRowBackground(FuzzTheme.surface)
                        .disabled(isScanning)
                        ForEach(discovered) { agent in
                            Button(action: {
                                selectedDescriptor = RemoteAgentDescriptor.all.first { $0.kind == agent.kind } ?? .opencode
                                selectedProtocol = agent.transport
                                pendingDiscovered = agent
                                showManualPair = true
                            }) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(FuzzTheme.textPrimary)
                                    Text(agent.urlString)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(FuzzTheme.textSecondary)
                                }
                            }
                            .listRowBackground(FuzzTheme.surface)
                        }
                        if !isScanning && discovered.isEmpty {
                            Text("No agents advertised yet. Most runtimes need manual pairing.")
                                .font(.caption)
                                .foregroundColor(FuzzTheme.textMuted)
                                .listRowBackground(FuzzTheme.surface)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Connect Coding Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showManualPair) {
                if let descriptor = selectedDescriptor {
                    let discovered = pendingDiscovered
                    PairHostSheet(
                        title: "Pair \(descriptor.kind.displayName)",
                        kind: descriptor.kind,
                        initialName: pendingDiscovered?.name ?? "\(descriptor.kind.displayName) Host",
                        initialHostURL: pendingDiscovered?.urlString,
                        initialProtocol: selectedProtocol ?? .recommended(for: descriptor.kind),
                        defaultPort: pendingDiscovered?.port ?? descriptor.defaultPort,
                        capabilities: Array(descriptor.capabilities),
                        allowsInsecureTransport: discovered.map { isCleartext($0.urlString) } ?? false,
                        onPaired: onPaired
                    )
                }
            }
        }
    }

    private func isCleartext(_ urlString: String) -> Bool {
        guard let scheme = URL(string: urlString)?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "ws"
    }

    private func scanLAN() {
        isScanning = true
        discovered = []
        Task {
            let agents = await AgentLANDiscovery().browse()
            await MainActor.run {
                self.discovered = agents
                self.isScanning = false
            }
        }
    }
}

struct ResumeSessionSheet: View {
    let sessions: [AgentSession]
    let errorMessage: String?
    let onSelect: (AgentSession) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                List {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(FuzzTheme.clippingRed)
                            .listRowBackground(FuzzTheme.surface)
                    }
                    if sessions.isEmpty && errorMessage == nil {
                        Text("No existing sessions found on this connection.")
                            .font(.caption)
                            .foregroundColor(FuzzTheme.textSecondary)
                            .listRowBackground(FuzzTheme.surface)
                    }
                    ForEach(sessions) { session in
                        Button(action: { onSelect(session) }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(FuzzTheme.textPrimary)
                                HStack {
                                    Text(session.status.rawValue.uppercased())
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(FuzzTheme.electricPurple)
                                    Spacer()
                                    Text("\(session.messages.count) messages")
                                        .font(.caption)
                                        .foregroundColor(FuzzTheme.textMuted)
                                }
                            }
                        }
                        .listRowBackground(FuzzTheme.surface)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Resume Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(FuzzTheme.acidGreen)
                }
            }
        }
    }
}

struct QRShareSheet: View {
    let host: OpenCodeHostConfig
    let onImport: (OpenCodeHostConfig) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var importText = ""
    @State private var importError: String?
    @State private var importToken = ""
    @State private var allowsInsecure = false
    @State private var pendingHost: OpenCodeHostConfig?

    private var qrImage: UIImage? {
        guard let data = try? JSONEncoder().encode(AgentPairingPayload(host: host)),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 18) {
                        Text("Scan on another device, or paste a shared payload below to import. The payload carries connection metadata only - tokens stay in your Keychain and are never embedded.")
                            .font(.caption)
                            .foregroundColor(FuzzTheme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)

                        if let qrImage {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 220, height: 220)
                                .padding(12)
                                .background(Color.white)
                                .cornerRadius(12)
                                .accessibilityLabel("Pairing QR code")
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("IMPORT PAYLOAD")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(FuzzTheme.textMuted)
                            TextEditor(text: $importText)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(minHeight: 90)
                                .padding(8)
                                .background(FuzzTheme.surfaceRaised)
                                .cornerRadius(8)
                            Toggle("Allow insecure local transport", isOn: $allowsInsecure)
                                .font(.caption)
                                .foregroundColor(FuzzTheme.textSecondary)
                            if let importError {
                                Text(importError)
                                    .font(.caption)
                                    .foregroundColor(FuzzTheme.clippingRed)
                            }
                            if let pendingHost {
                                Text("Token for \(pendingHost.displayName)")
                                    .font(.caption)
                                    .foregroundColor(FuzzTheme.textSecondary)
                                SecureField("Auth Token", text: $importToken)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .padding(8)
                                    .background(FuzzTheme.surfaceRaised)
                                    .cornerRadius(8)
                                Button("Add Host") {
                                    KeychainService.shared.save(key: pendingHost.authTokenKey, secret: importToken)
                                    onImport(pendingHost)
                                    dismiss()
                                }
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(FuzzTheme.acidGreen)
                                .cornerRadius(8)
                            } else {
                                Button("Decode Payload") {
                                    decodePayload()
                                }
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(FuzzTheme.acidGreen)
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle("Pairing QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
            }
        }
    }

    private func decodePayload() {
        importError = nil
        let trimmed = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            importError = "Paste a pairing payload first."
            return
        }
        do {
            pendingHost = try AgentPairingPayload.decode(trimmed, allowsInsecureTransport: allowsInsecure)
        } catch {
            importError = error.localizedDescription
        }
    }
}
