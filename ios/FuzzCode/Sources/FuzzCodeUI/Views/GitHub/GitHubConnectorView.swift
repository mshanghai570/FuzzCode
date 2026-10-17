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
    @State private var isImportingRepository = false
    
    public init(config: Binding<GitHubConfig>) {
        self._config = config
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                FuzzTheme.background.ignoresSafeArea()
                
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
                                        .foregroundStyle(FuzzTheme.textSecondary)
                                }
                                
                                Spacer()
                                
                                Button("Disconnect") {
                                    FuzzTheme.playErrorFeedback()
                                    config.isConnected = false
                                    config.user = nil
                                    repos.removeAll()
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(FuzzTheme.clippingRed)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(FuzzTheme.clippingRed.opacity(0.15))
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
                            .foregroundStyle(FuzzTheme.textSecondary)
                        }
                        .padding()
                        .background(FuzzTheme.surface)
                        .overlay(
                            Rectangle()
                                .frame(height: 1)
                                .foregroundStyle(FuzzTheme.border),
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
                                                    .foregroundStyle(FuzzTheme.textSecondary)
                                            }
                                        }
                                        if let desc = repo.repoDescription {
                                            Text(desc)
                                                .font(.caption)
                                                .foregroundStyle(FuzzTheme.textSecondary)
                                                .lineLimit(2)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .listRowBackground(FuzzTheme.surface)
                                    .swipeActions(edge: .trailing) {
                                        Button("Import") { importRepository(repo) }
                                            .tint(FuzzTheme.acidGreen)
                                            .disabled(isImportingRepository)
                                    }
                                    .accessibilityHint("Swipe left to import this repository into a local sandboxed workspace")
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
                                    .listRowBackground(FuzzTheme.surface)
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
                                        .foregroundStyle(FuzzTheme.textSecondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                }
                                
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("PERSONAL ACCESS TOKEN")
                                        .font(.caption2)
                                        .fontDesign(.monospaced)
                                        .fontWeight(.bold)
                                        .foregroundStyle(FuzzTheme.textSecondary)
                                    
                                    SecureField("ghp_xxxxxxxxxxxxxxxxxxxx", text: $tokenInput)
                                        .padding(12)
                                        .background(FuzzTheme.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(FuzzTheme.border, lineWidth: 1)
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
    
    private func importRepository(_ repo: GitHubRepo) {
        guard let token = KeychainService.shared.get(key: config.keychainTokenKey) else {
            errorMessage = "The GitHub token is missing from Keychain. Reconnect GitHub before importing."
            return
        }
        guard let separator = repo.fullName.firstIndex(of: "/") else { return }
        isImportingRepository = true
        Task {
            do {
                let workspaceID = "github-\(repo.id)"
                let workspace = try WorkspaceManager(root: WorkspaceManager.defaultRoot(workspaceId: workspaceID))
                let client = GitHubClient(token: token)
                _ = try await client.importRepository(owner: String(repo.fullName[..<separator]),
                                                      repo: String(repo.fullName[repo.fullName.index(after: separator)...]),
                                                      branch: repo.defaultBranch, into: workspace)
                await MainActor.run {
                    config.selectedRepo = repo
                    errorMessage = "Imported \(repo.fullName) into a sandboxed workspace."
                    isImportingRepository = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Repository import failed: \(error.localizedDescription)"
                    isImportingRepository = false
                }
            }
        }
    }

    private func authenticateGitHub() {
        FuzzTheme.playStompFeedback()
        isAuthenticating = true
        errorMessage = nil
        
        Task {
            let client = GitHubClient(token: tokenInput)
            do {
                let (user, scopes) = try await client.authenticate()
                let fetchedRepos = try await client.fetchRepositories()
                await MainActor.run {
                    let credentialKey = config.keychainTokenKey
                    switch KeychainService.shared.save(key: credentialKey, secret: tokenInput) {
                    case .success:
                        config.isConnected = true
                        config.user = user
                        config.scopes = scopes
                        config.connectedAt = Date()
                        self.repos = fetchedRepos
                        self.tokenInput = ""
                        self.isAuthenticating = false
                        FuzzTheme.playSuccessFeedback()
                    case .failure(let error):
                        self.errorMessage = "GitHub authenticated, but the token could not be saved securely: \(error.localizedDescription)"
                        self.isAuthenticating = false
                        FuzzTheme.playErrorFeedback()
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isAuthenticating = false
                    FuzzTheme.playErrorFeedback()
                }
            }
        }
    }
}
