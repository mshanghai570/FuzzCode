import SwiftUI
import FuzzCodeCore

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
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                
                if hosts.isEmpty {
                    emptyHostsState
                } else {
                    mainAgentConsole
                }
            }
            .navigationTitle("OpenCode Agent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showPairHostSheet = true }) {
                        Image(systemName: "link.badge.plus")
                            .foregroundColor(FuzzTheme.acidGreen)
                    }
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
                    selectedHost = host
                    StorageService.shared.saveHosts(hosts)
                })
            }
            .sheet(isPresented: $showNewSessionSheet) {
                NewSessionSheet(host: selectedHost, onCreated: { newSession in
                    sessions.insert(newSession, at: 0)
                    selectedSession = newSession
                })
            }
            .sheet(isPresented: $showDiffSheet) {
                if let git = activeGitStatus {
                    CodeDiffView(summary: git)
                }
            }
            .sheet(item: $permissionToResolve) { perm in
                PermissionApprovalSheet(request: perm) { decision in
                    resolvePermission(decision)
                }
            }
            .onAppear(perform: loadData)
        }
    }
    
    private var emptyHostsState: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.badge.wifi")
                .font(.system(size: 48))
                .foregroundColor(FuzzTheme.electricPurple)
            
            VStack(spacing: 8) {
                Text("NO OPENCODE HOST PAIRED")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(FuzzTheme.textPrimary)
                
                Text("OpenCode runs as an external coding agent companion on your Mac or development VM. FuzzCode controls it securely over authenticated HTTP/WebSocket.")
                    .font(.system(size: 13))
                    .foregroundColor(FuzzTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            FuzzStompButton(title: "Pair OpenCode Host", icon: "link") {
                showPairHostSheet = true
            }
        }
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
    
    private var hostStatusBar: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(hosts) { host in
                    Button(action: { selectedHost = host }) {
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
    }
    
    // MARK: - Actions
    
    private func sendAgentInstruction() {
        let text = instructionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, var session = selectedSession, let host = selectedHost else { return }
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
            let client = OpenCodeClient(hostConfig: host)
            let stream = await client.sendInstruction(sessionId: session.id, prompt: text)
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
        guard let perm = permissionToResolve, let session = selectedSession, let host = selectedHost else { return }
        permissionToResolve = nil
        Task {
            let client = OpenCodeClient(hostConfig: host)
            try? await client.resolvePermission(requestId: perm.id, decision: decision)
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
        guard let session = selectedSession, let host = selectedHost else { return }
        Task {
            let client = OpenCodeClient(hostConfig: host)
            try? await client.cancelTask(sessionId: session.id)
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
        guard let session = selectedSession, let host = selectedHost else { return }
        Task {
            let client = OpenCodeClient(hostConfig: host)
            if let git = try? await client.fetchGitStatus(sessionId: session.id) {
                await MainActor.run {
                    self.activeGitStatus = git
                    self.showDiffSheet = true
                }
            }
        }
    }
    
    private func loadData() {
        hosts = StorageService.shared.loadHosts()
        selectedHost = hosts.first
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
    let onPaired: (OpenCodeHostConfig) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var displayName = "MacBook Pro (OpenCode)"
    @State private var hostURL = "http://192.168.1.100:4096"
    @State private var token = ""
    @State private var isTesting = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                Form {
                    Section("Host Details") {
                        TextField("Host Display Name", text: $displayName)
                        TextField("Host URL (e.g. http://192.168.1.50:4096)", text: $hostURL)
                        SecureField("Companion Auth Token", text: $token)
                    }
                    .listRowBackground(FuzzTheme.surface)
                    
                    if let err = errorMessage {
                        Text(err).foregroundColor(FuzzTheme.clippingRed).font(.system(size: 12))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Pair OpenCode Host")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Pair") {
                        let tokenKey = "opencode_token_\(UUID().uuidString)"
                        KeychainService.shared.save(key: tokenKey, secret: token)
                        let newHost = OpenCodeHostConfig(
                            displayName: displayName,
                            hostURLString: hostURL,
                            authTokenKey: tokenKey,
                            isConnected: true
                        )
                        onPaired(newHost)
                        dismiss()
                    }
                    .foregroundColor(FuzzTheme.acidGreen)
                }
            }
        }
    }
}

struct NewSessionSheet: View {
    let host: OpenCodeHostConfig?
    let onCreated: (AgentSession) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var workspace = "/Users/dev/Projects/fuzzcode"
    @State private var initialPrompt = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                Form {
                    Section("Session Setup") {
                        TextField("Workspace Directory", text: $workspace)
                        TextField("Initial Goal / Task", text: $initialPrompt)
                    }
                    .listRowBackground(FuzzTheme.surface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New Agent Session")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Start") {
                        let session = AgentSession(
                            hostId: host?.id ?? UUID(),
                            title: initialPrompt.isEmpty ? "Workspace Session" : initialPrompt,
                            workspacePath: workspace
                        )
                        onCreated(session)
                        dismiss()
                    }
                    .foregroundColor(FuzzTheme.acidGreen)
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
