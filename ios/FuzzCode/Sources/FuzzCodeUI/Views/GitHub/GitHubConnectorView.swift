import SwiftUI
import FuzzCodeCore

/// Native SwiftUI view for GitHub direct connector and repository management.
public struct GitHubConnectorView: View {
    @Binding public var config: GitHubConfig
    @Environment(\.dismiss) var dismiss
    
    @State private var tokenInput = ""
    @State private var isAuthenticating = false
    @State private var repos: [GitHubRepo] = []
    @State private var pulls: [GitHubPullRequest] = []
    @State private var selectedTab = 0
    @State private var errorMessage: String?
    
    public init(config: Binding<GitHubConfig>) {
        self._config = config
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.charcoalBlack.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    if config.isConnected, let user = config.user {
                        // Connected Profile Header
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable()
                                    .frame(width: 44, height: 44)
                                    .foregroundStyle(FuzzTheme.electricPurple)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(user.name)
                                        .font(.subheadline)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                    Text("@\(user.login)")
                                        .font(.caption)
                                        .fontDesign(.monospaced)
                                        .foregroundStyle(FuzzTheme.mutedSlate)
                                }
                                
                                Spacer()
                                
                                Button("Disconnect") {
                                    FuzzTheme.hapticAlert()
                                    config.isConnected = false
                                    config.user = nil
                                    repos.removeAll()
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(FuzzTheme.saturatedRed)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(FuzzTheme.saturatedRed.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            
                            HStack(spacing: 16) {
                                Label("\(user.publicRepos) Public", systemImage: "folder")
                                Label("\(user.totalPrivateRepos) Private", systemImage: "lock.shield")
                                Spacer()
                                Label("Full Access", systemImage: "checkmark.seal.fill")
                                    .foregroundStyle(FuzzTheme.acidGreen)
                            }
                            .font(.caption2)
                            .fontDesign(.monospaced)
                            .foregroundStyle(FuzzTheme.mutedSlate)
                        }
                        .padding()
                        .background(FuzzTheme.darkPedalBase)
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundStyle(FuzzTheme.subtleBorder),
                            alignment: .bottom
                        )
                        
                        // Tab Selector
                        Picker("View", selection: $selectedTab) {
                            Text("Repositories").tag(0)
                            Text("Pull Requests").tag(1)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        
                        // Content List
                        List {
                            if selectedTab == 0 {
                                ForEach(repos) { repo in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(repo.fullName)
                                                .font(.subheadline)
                                                .fontWeight(.bold)
                                                .foregroundStyle(.white)
                                            Spacer()
                                            if repo.isPrivate {
                                                Image(systemName: "lock.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(FuzzTheme.mutedSlate)
                                            }
                                        }
                                        if let desc = repo.repoDescription {
                                            Text(desc)
                                                .font(.caption)
                                                .foregroundStyle(FuzzTheme.mutedSlate)
                                                .lineLimit(2)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .listRowBackground(FuzzTheme.darkPedalBase)
                                }
                            } else {
                                ForEach(pulls) { pr in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text("#\(pr.number) \(pr.title)")
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                                .foregroundStyle(.white)
                                            Spacer()
                                            Text(pr.state.uppercased())
                                                .font(.caption2)
                                                .fontDesign(.monospaced)
                                                .fontWeight(.bold)
                                                .foregroundStyle(FuzzTheme.acidGreen)
                                        }
                                        Text("\(pr.headBranch) -> \(pr.baseBranch)")
                                            .font(.caption2)
                                            .fontDesign(.monospaced)
                                            .foregroundStyle(FuzzTheme.electricPurple)
                                    }
                                    .padding(.vertical, 4)
                                    .listRowBackground(FuzzTheme.darkPedalBase)
                                }
                            }
                        }
                        .listStyle(.plain)
                    } else {
                        // Unconnected Login Screen
                        ScrollView {
                            VStack(spacing: 20) {
                                Image(systemName: "arrow.triangle.branch")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 48, height: 48)
                                    .foregroundStyle(FuzzTheme.electricPurple)
                                    .padding(.top, 40)
                                
                                VStack(spacing: 6) {
                                    Text("Connect Direct to GitHub")
                                        .font(.title3)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white)
                                    Text("Grants full repo access, branch switching, and PR management to your FuzzCode coding agents.")
                                        .font(.footnote)
                                        .foregroundStyle(FuzzTheme.mutedSlate)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("PERSONAL ACCESS TOKEN")
                                        .font(.caption2)
                                        .fontDesign(.monospaced)
                                        .fontWeight(.bold)
                                        .foregroundStyle(FuzzTheme.mutedSlate)
                                    
                                    SecureField("ghp_xxxxxxxxxxxxxxxxxxxx", text: $tokenInput)
                                        .padding(12)
                                        .background(FuzzTheme.darkPedalBase)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(FuzzTheme.subtleBorder, lineWidth: 1)
                                        )
                                        .foregroundStyle(.white)
                                        .fontDesign(.monospaced)
                                }
                                .padding(.horizontal)
                                
                                Button {
                                    authenticateGitHub()
                                } label: {
                                    HStack {
                                        if isAuthenticating {
                                            ProgressView()
                                                .tint(.black)
                                        } else {
                                            Text("Connect GitHub Account")
                                                .fontWeight(.bold)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(FuzzTheme.acidGreen)
                                    .foregroundStyle(.black)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                                .padding(.horizontal)
                                .disabled(tokenInput.isEmpty || isAuthenticating)
                            }
                        }
                    }
                }
            }
            .navigationTitle("GitHub Connector")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(FuzzTheme.acidGreen)
                }
            }
        }
    }
    
    private func authenticateGitHub() {
        FuzzTheme.hapticClick()
        isAuthenticating = true
        errorMessage = nil
        
        Task {
            let client = GitHubClient(token: tokenInput)
            do {
                let (user, scopes) = try await client.authenticate()
                let fetchedRepos = try await client.fetchRepositories()
                await MainActor.run {
                    config.isConnected = true
                    config.user = user
                    config.scopes = scopes
                    config.connectedAt = Date()
                    self.repos = fetchedRepos
                    self.isAuthenticating = false
                    FuzzTheme.hapticSuccess()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isAuthenticating = false
                    FuzzTheme.hapticAlert()
                }
            }
        }
    }
}
