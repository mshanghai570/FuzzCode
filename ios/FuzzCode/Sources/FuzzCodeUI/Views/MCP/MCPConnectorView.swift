import SwiftUI
import FuzzCodeCore

/// Native SwiftUI view for managing Model Context Protocol (MCP) servers and tools.
public struct MCPConnectorView: View {
    @Binding public var servers: [MCPServerConfig]
    @Environment(\.dismiss) var dismiss
    
    @State private var isAddingServer = false
    @State private var newName = ""
    @State private var newURL = "http://localhost:8080/sse"
    @State private var newTransport: MCPTransportType = .sse
    @State private var testingServerId: UUID?
    
    public init(servers: Binding<[MCPServerConfig]>) {
        self._servers = servers
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.charcoalBlack.ignoresSafeArea()
                
                List {
                    Section {
                        ForEach($servers) { $server in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Circle()
                                        .frame(width: 8, height: 8)
                                        .foregroundStyle(server.isConnected ? FuzzTheme.acidGreen : FuzzTheme.saturatedRed)
                                    
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
                                    .foregroundStyle(FuzzTheme.mutedSlate)
                                
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
                                            .foregroundStyle(FuzzTheme.mutedSlate)
                                    }
                                    
                                    Spacer()
                                    
                                    Button("Test Ping") {
                                        testServer(server)
                                    }
                                    .font(.caption2)
                                    .fontDesign(.monospaced)
                                    .foregroundStyle(FuzzTheme.acidGreen)
                                }
                            }
                            .padding(.vertical, 4)
                            .listRowBackground(FuzzTheme.darkPedalBase)
                        }
                        .onDelete { indexSet in
                            servers.remove(atOffsets: indexSet)
                        }
                    } header: {
                        Text("Active MCP Servers")
                            .fontDesign(.monospaced)
                            .foregroundStyle(FuzzTheme.mutedSlate)
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
                        isAddingServer = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(FuzzTheme.acidGreen)
                    }
                }
            }
            .sheet(isPresented: $isAddingServer) {
                NavigationStack {
                    ZStack {
                        FuzzTheme.charcoalBlack.ignoresSafeArea()
                        
                        Form {
                            Section("Server Details") {
                                TextField("Server Name", text: $newName)
                                    .foregroundStyle(.white)
                                TextField("Endpoint URL", text: $newURL)
                                    .fontDesign(.monospaced)
                                    .foregroundStyle(.white)
                                Picker("Transport", selection: $newTransport) {
                                    Text("SSE").tag(MCPTransportType.sse)
                                    Text("WebSocket").tag(MCPTransportType.websocket)
                                    Text("Stdio Remote").tag(MCPTransportType.stdioRemote)
                                }
                            }
                            .listRowBackground(FuzzTheme.darkPedalBase)
                        }
                        .scrollContentBackground(.hidden)
                    }
                    .navigationTitle("Add MCP Server")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isAddingServer = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                let newConfig = MCPServerConfig(
                                    name: newName.isEmpty ? "Custom MCP Server" : newName,
                                    transport: newTransport,
                                    endpointURLString: newURL,
                                    isConnected: true,
                                    lastPingMs: 25
                                )
                                servers.append(newConfig)
                                isAddingServer = false
                                newName = ""
                            }
                            .foregroundStyle(FuzzTheme.acidGreen)
                        }
                    }
                }
            }
        }
    }
    
    private func testServer(_ server: MCPServerConfig) {
        FuzzTheme.hapticClick()
        testingServerId = server.id
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
                    }
                    testingServerId = nil
                    FuzzTheme.hapticSuccess()
                }
            } catch {
                await MainActor.run {
                    if let idx = servers.firstIndex(where: { $0.id == server.id }) {
                        servers[idx].isConnected = false
                        servers[idx].lastError = error.localizedDescription
                    }
                    testingServerId = nil
                    FuzzTheme.hapticAlert()
                }
            }
        }
    }
}
