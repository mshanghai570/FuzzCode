import SwiftUI
import FuzzCodeCore

/// Native SwiftUI view for managing Model Context Protocol (MCP) servers and tools.
public struct MCPConnectorView: View {
    @Binding public var servers: [MCPServerConfig]
    @Environment(\.dismiss) var dismiss
    
    @State private var isShowingEditor = false
    @State private var editingServerID: UUID?
    @State private var newName = ""
    @State private var newURL = "http://localhost:8080/sse"
    @State private var newTransport: MCPTransportType = .streamableHTTP
    @State private var bearerToken = ""
    @State private var editorError: String?
    @State private var operationError: String?
    @State private var testingServerId: UUID?
    
    public init(servers: Binding<[MCPServerConfig]>) {
        self._servers = servers
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                
                List {
                    Section {
                        ForEach($servers) { $server in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Circle()
                                        .frame(width: 8, height: 8)
                                        .foregroundStyle(server.isConnected ? FuzzTheme.acidGreen : FuzzTheme.clippingRed)
                                    
                                    Text(server.name)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                    
                                    Spacer()
                                    
                                    Text(server.transport.rawValue.uppercased())
                                        .font(.caption2)
                                        .fontDesign(.monospaced)
                                        .fontWeight(.bold)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(FuzzTheme.electricPurple.opacity(0.2))
                                        .foregroundStyle(FuzzTheme.electricPurple)
                                        .clipShape(Capsule())
                                }
                                
                                Text(server.endpointURLString)
                                    .font(.caption2)
                                    .fontDesign(.monospaced)
                                    .foregroundStyle(FuzzTheme.textSecondary)
                                
                                if !server.discoveredTools.isEmpty {
                                    HStack(spacing: 6) {
                                        Image(systemName: "wrench.and.screwdriver")
                                            .font(.caption2)
                                            .foregroundStyle(FuzzTheme.acidGreen)
                                        Text("\(server.discoveredTools.count) Tools Available")
                                            .font(.caption2)
                                            .fontDesign(.monospaced)
                                            .foregroundStyle(FuzzTheme.acidGreen)
                                    }
                                }

                                HStack {
                                    if let ms = server.lastPingMs {
                                        Text("\(Int(ms))ms")
                                            .font(.caption2)
                                            .fontDesign(.monospaced)
                                            .foregroundStyle(FuzzTheme.textSecondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Button(
                                        testingServerId == server.id
                                            ? "Testing..."
                                            : (supportsHTTP(server.transport) ? "Test Connection" : "Unsupported")
                                    ) {
                                        testServer(server)
                                    }
                                    .disabled(testingServerId == server.id || !supportsHTTP(server.transport))
                                    .font(.caption2)
                                    .fontDesign(.monospaced)
                                    .foregroundStyle(supportsHTTP(server.transport) ? FuzzTheme.acidGreen : FuzzTheme.textMuted)
                                }

                                if let error = server.lastError {
                                    Text(error)
                                        .font(.caption2)
                                        .foregroundStyle(FuzzTheme.clippingRed)
                                } else if !supportsHTTP(server.transport) {
                                    Text("This transport is not supported on iOS.")
                                        .font(.caption2)
                                        .foregroundStyle(FuzzTheme.warningAmber)
                                }

                                Button("Edit Server") { editServer(server) }
                                    .font(.caption2)
                                    .fontDesign(.monospaced)
                                    .foregroundStyle(FuzzTheme.textSecondary)
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(FuzzTheme.surface)
                        }
                        .onDelete { indexSet in
                            removeServers(at: indexSet)
                        }
                    } header: {
                        Text("Active MCP Servers")
                            .fontDesign(.monospaced)
                            .foregroundStyle(FuzzTheme.textSecondary)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("MCP Connectors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(FuzzTheme.acidGreen)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        prepareNewServer()
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(FuzzTheme.acidGreen)
                    }
                }
            }
            .alert("MCP Connector", isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )) {
                Button("OK", role: .cancel) { operationError = nil }
            } message: {
                Text(operationError ?? "")
            }
            .sheet(isPresented: $isShowingEditor) {
                NavigationStack {
                    ZStack {
                        FuzzTheme.background.ignoresSafeArea()
                        
                        Form {
                            Section("Server Details") {
                                TextField("Server Name", text: $newName)
                                    .foregroundStyle(.white)
                                TextField("Endpoint URL", text: $newURL)
                                    .fontDesign(.monospaced)
                                    .foregroundStyle(.white)
                                SecureField("Bearer token (optional)", text: $bearerToken)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                if editingServerID != nil {
                                    Text("Leave the token blank to keep the saved credential.")
                                        .font(.caption)
                                        .foregroundStyle(FuzzTheme.textSecondary)
                                }
                                Picker("Transport", selection: $newTransport) {
                                    Text("Streamable HTTP").tag(MCPTransportType.streamableHTTP)
                                    Text("Legacy HTTP + SSE").tag(MCPTransportType.sse)
                                    if newTransport == .websocket {
                                        Text("WebSocket (unsupported)").tag(MCPTransportType.websocket)
                                    } else if newTransport == .stdioRemote {
                                        Text("Stdio Remote (unsupported)").tag(MCPTransportType.stdioRemote)
                                    }
                                }
                            }
                            .listRowBackground(FuzzTheme.surface)

                            if let editorError {
                                Section {
                                    Text(editorError)
                                        .foregroundStyle(FuzzTheme.clippingRed)
                                }
                                .listRowBackground(FuzzTheme.surface)
                            }
                        }
                        .scrollContentBackground(.hidden)
                    }
                    .navigationTitle(editingServerID == nil ? "Add MCP Server" : "Edit MCP Server")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isShowingEditor = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                saveEditedServer()
                            }
                            .foregroundStyle(FuzzTheme.acidGreen)
                            .disabled(newURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
        }
    }
    
    private func prepareNewServer() {
        editingServerID = nil
        newName = ""
        newURL = "http://localhost:8080/"
        newTransport = .streamableHTTP
        bearerToken = ""
        editorError = nil
        isShowingEditor = true
    }

    private func editServer(_ server: MCPServerConfig) {
        editingServerID = server.id
        newName = server.name
        newURL = server.endpointURLString
        newTransport = server.transport
        bearerToken = ""
        editorError = nil
        isShowingEditor = true
    }

    private func saveEditedServer() {
        let normalizedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedURL = newURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let serverID = editingServerID ?? UUID()
        let credentialKey = "mcp.server.\(serverID.uuidString).bearer"
        let existingServer = servers.first { $0.id == serverID }
        let token = bearerToken.trimmingCharacters(in: .whitespacesAndNewlines)
        var authTokenKey = existingServer?.authTokenKey
        var replacedCredentialKey: String?

        if !token.isEmpty {
            switch KeychainService.shared.save(key: credentialKey, secret: token) {
            case .success:
                replacedCredentialKey = authTokenKey == credentialKey ? nil : authTokenKey
                authTokenKey = credentialKey
            case .failure(let error):
                editorError = "The bearer token could not be saved: \(error.localizedDescription)"
                return
            }
        }

        var config = existingServer ?? MCPServerConfig(
            id: serverID,
            name: normalizedName.isEmpty ? "Custom MCP Server" : normalizedName,
            transport: newTransport,
            endpointURLString: normalizedURL
        )
        config.name = normalizedName.isEmpty ? "Custom MCP Server" : normalizedName
        config.transport = newTransport
        config.endpointURLString = normalizedURL
        config.authTokenKey = authTokenKey
        config.markUnverified()

        if let index = servers.firstIndex(where: { $0.id == serverID }) {
            servers[index] = config
        } else {
            servers.append(config)
        }
        if let replacedCredentialKey, !KeychainService.shared.delete(key: replacedCredentialKey) {
            operationError = "The new credential was saved, but the previous Keychain credential couldn't be removed."
        }
        isShowingEditor = false
    }

    private func removeServers(at offsets: IndexSet) {
        let selectedServers = offsets.map { servers[$0] }
        var removableIDs: [UUID] = []
        var failedNames: [String] = []
        for server in selectedServers {
            if let key = server.authTokenKey, !KeychainService.shared.delete(key: key) {
                failedNames.append(server.name)
            } else {
                removableIDs.append(server.id)
            }
        }
        servers.removeAll { removableIDs.contains($0.id) }
        if !failedNames.isEmpty {
            operationError = "Credentials couldn't be removed for: \(failedNames.joined(separator: ", ")). Those servers were kept."
        }
    }

    private func safeErrorDescription(_ error: Error, for server: MCPServerConfig) -> String {
        let credentialKeys = [server.authTokenKey].compactMap { $0 } + server.customHeaders.map(\.value)
        let secrets = credentialKeys.compactMap { KeychainService.shared.get(key: $0) }.filter { !$0.isEmpty }
        return secrets.reduce(error.localizedDescription) { message, secret in
            message.replacingOccurrences(of: secret, with: "[redacted]")
        }
    }

    private func supportsHTTP(_ transport: MCPTransportType) -> Bool {
        transport == .streamableHTTP || transport == .sse
    }

    private func testServer(_ server: MCPServerConfig) {
        guard supportsHTTP(server.transport) else { return }
        FuzzTheme.playStompFeedback()
        testingServerId = server.id
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index].markUnverified()
        }
        Task {
            let client = MCPClient(config: server)
            do {
                let (tools, res, latency) = try await client.initializeAndDiscover()
                await MainActor.run {
                    if let idx = servers.firstIndex(where: { $0.id == server.id }) {
                        servers[idx].isConnected = true
                        servers[idx].lastPingMs = latency
                        servers[idx].discoveredTools = tools
                        servers[idx].discoveredResources = res
                        servers[idx].lastError = nil
                    }
                    testingServerId = nil
                    FuzzTheme.playSuccessFeedback()
                }
            } catch {
                await MainActor.run {
                    if let idx = servers.firstIndex(where: { $0.id == server.id }) {
                        servers[idx].markUnverified()
                        servers[idx].isConnected = false
                        servers[idx].lastError = safeErrorDescription(error, for: server)
                    }
                    testingServerId = nil
                    FuzzTheme.playErrorFeedback()
                }
            }
        }

    }
}
