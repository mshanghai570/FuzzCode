import React, { useState } from 'react';
import { X, GitBranch, GitPullRequest, FolderGit2, Star, CheckCircle2, ExternalLink, ShieldCheck, RefreshCw, Plus, Terminal } from 'lucide-react';
import { GitHubConfig, GitHubRepo, GitHubPullRequest } from '../../types';
import { GitHubService } from '../../services/githubService';
import { fuzzAudio } from '../../services/audioService';

interface GitHubConnectorModalProps {
  isOpen: boolean;
  onClose: () => void;
  config: GitHubConfig;
  onUpdateConfig: (config: GitHubConfig) => void;
  onLoadRepoIntoAgent: (repo: GitHubRepo) => void;
}

export const GitHubConnectorModal: React.FC<GitHubConnectorModalProps> = ({
  isOpen,
  onClose,
  config,
  onUpdateConfig,
  onLoadRepoIntoAgent
}) => {
  const [tokenInput, setTokenInput] = useState(config.token || '');
  const [isAuthenticating, setIsAuthenticating] = useState(false);
  const [activeTab, setActiveTab] = useState<'repos' | 'pulls' | 'auth'>('repos');
  const [repos, setRepos] = useState<GitHubRepo[]>([]);
  const [pulls, setPulls] = useState<GitHubPullRequest[]>([]);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedRepo, setSelectedRepo] = useState<GitHubRepo | null>(config.selectedRepo || null);

  React.useEffect(() => {
    if (config.isConnected) {
      GitHubService.fetchRepositories(config.token).then(setRepos);
      if (config.selectedRepo) {
        GitHubService.fetchPullRequests(config.selectedRepo.fullName, config.token).then(setPulls);
      }
    }
  }, [config.isConnected, config.selectedRepo]);

  if (!isOpen) return null;

  const handleConnect = async () => {
    setIsAuthenticating(true);
    fuzzAudio.playStomp();

    try {
      const { user, scopes } = await GitHubService.authenticate(tokenInput);
      const newConfig: GitHubConfig = {
        isConnected: true,
        token: tokenInput.trim(),
        user,
        scopes,
        connectedAt: new Date().toISOString()
      };
      onUpdateConfig(newConfig);

      const fetchedRepos = await GitHubService.fetchRepositories(tokenInput);
      setRepos(fetchedRepos);
      if (fetchedRepos.length > 0) {
        setSelectedRepo(fetchedRepos[0]);
        const fetchedPulls = await GitHubService.fetchPullRequests(fetchedRepos[0].fullName, tokenInput);
        setPulls(fetchedPulls);
      }

      setActiveTab('repos');
      fuzzAudio.playSuccess();
    } catch {
      fuzzAudio.playAlert();
    } finally {
      setIsAuthenticating(false);
    }
  };

  const handleDisconnect = () => {
    fuzzAudio.playAlert();
    onUpdateConfig({
      isConnected: false,
      token: '',
      scopes: []
    });
    setRepos([]);
    setPulls([]);
    setSelectedRepo(null);
  };

  const handleSelectRepo = (repo: GitHubRepo) => {
    fuzzAudio.playStomp();
    setSelectedRepo(repo);
    onUpdateConfig({
      ...config,
      selectedRepo: repo
    });
    GitHubService.fetchPullRequests(repo.fullName, config.token).then(setPulls);
  };

  const handleDispatchToAgent = (repo: GitHubRepo) => {
    fuzzAudio.playSuccess();
    onLoadRepoIntoAgent(repo);
    onClose();
  };

  const filteredRepos = repos.filter(r => 
    r.fullName.toLowerCase().includes(searchQuery.toLowerCase()) ||
    (r.description && r.description.toLowerCase().includes(searchQuery.toLowerCase()))
  );

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md animate-in fade-in">
      <div className="w-full max-w-2xl h-[88vh] rounded-2xl bg-[#0e1017] border border-[#232736] shadow-2xl overflow-hidden flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-[#1c1f2b] bg-[#12141c]">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl bg-purple-500/10 border border-purple-500/30 flex items-center justify-center text-purple-400">
              <FolderGit2 className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="text-sm font-bold text-white uppercase tracking-wider font-mono">
                  GitHub Connector
                </h3>
                {config.isConnected && (
                  <span className="text-[10px] font-mono font-bold text-emerald-400 bg-emerald-500/10 px-2 py-0.5 rounded">
                    Connected
                  </span>
                )}
              </div>
              <p className="text-[11px] text-slate-400">
                Grant full repository access to FuzzCode & OpenCode agents
              </p>
            </div>
          </div>

          <button
            onClick={() => { fuzzAudio.playStomp(); onClose(); }}
            className="text-slate-400 hover:text-white p-1 rounded-md transition-colors cursor-pointer"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Content Body */}
        {!config.isConnected ? (
          <div className="flex-1 p-6 overflow-y-auto space-y-5 text-xs">
            <div className="p-4 rounded-xl bg-[#141620] border border-[#232734] space-y-3">
              <div className="flex items-center gap-2 text-white font-semibold">
                <ShieldCheck className="w-4 h-4 text-emerald-400" />
                <span>Direct GitHub Authentication</span>
              </div>
              <p className="text-slate-400 leading-relaxed text-[11px]">
                Connect your GitHub account with a Personal Access Token (classic or fine-grained) with <code className="text-emerald-400 font-mono">repo</code>, <code className="text-emerald-400 font-mono">workflow</code>, and <code className="text-emerald-400 font-mono">read:user</code> scopes. Tokens are stored strictly in the native iOS Keychain.
              </p>
            </div>

            <div>
              <label className="block text-[11px] font-mono font-bold text-slate-400 uppercase mb-1.5">
                GitHub Personal Access Token
              </label>
              <input
                type="password"
                value={tokenInput}
                onChange={(e) => setTokenInput(e.target.value)}
                placeholder="ghp_••••••••••••••••••••••••••••••••"
                className="w-full px-3 py-2.5 rounded-lg bg-[#161822] border border-[#25293a] text-white font-mono text-[11px] focus:outline-none focus:border-purple-400"
              />
              <p className="text-[10px] text-slate-500 mt-1">
                Leave empty or type demo to explore with high-fidelity simulated repositories.
              </p>
            </div>

            <div className="p-3.5 rounded-xl bg-purple-950/20 border border-purple-500/20 space-y-1.5 text-[11px] text-purple-200">
              <span className="font-bold font-mono uppercase block text-[10px] text-purple-300">
                Granted Capabilities
              </span>
              <ul className="list-disc pl-4 space-y-1 text-slate-300">
                <li>Load repositories directly into remote OpenCode agent workspaces</li>
                <li>Inspect branches, issues, and commit trees on iPhone</li>
                <li>Stage and create Pull Requests directly from reviewed diffs</li>
              </ul>
            </div>

            <button
              onClick={handleConnect}
              disabled={isAuthenticating}
              className="w-full py-2.5 px-4 rounded-xl bg-purple-500 hover:bg-purple-400 text-white font-semibold text-xs transition-colors cursor-pointer flex items-center justify-center gap-2 shadow-sm shadow-purple-500/20"
            >
              {isAuthenticating ? <RefreshCw className="w-4 h-4 animate-spin" /> : <GitBranch className="w-4 h-4" />}
              <span>Grant Full GitHub Access</span>
            </button>
          </div>
        ) : (
          <div className="flex-1 flex flex-col overflow-hidden">
            {/* User Profile Bar */}
            <div className="flex items-center justify-between px-6 py-2.5 bg-[#12141c] border-b border-[#1c1f2b]">
              <div className="flex items-center gap-2.5">
                {config.user?.avatarUrl ? (
                  <img
                    src={config.user.avatarUrl}
                    alt={config.user.login}
                    className="w-7 h-7 rounded-full border border-purple-400/40"
                  />
                ) : (
                  <div className="w-7 h-7 rounded-full bg-purple-500/20 flex items-center justify-center text-purple-300 text-xs font-bold font-mono">
                    {config.user?.login.slice(0, 2).toUpperCase()}
                  </div>
                )}
                <div>
                  <span className="text-xs font-bold text-white block">
                    {config.user?.name} (@{config.user?.login})
                  </span>
                  <span className="text-[10px] font-mono text-slate-400">
                    {config.scopes.join(', ')}
                  </span>
                </div>
              </div>

              <div className="flex items-center gap-2">
                {/* Navigation subtabs */}
                <div className="flex items-center bg-[#1a1d28] p-0.5 rounded-lg border border-[#24293a] text-[11px] font-mono">
                  <button
                    onClick={() => { fuzzAudio.playStomp(); setActiveTab('repos'); }}
                    className={`px-2.5 py-1 rounded transition-colors cursor-pointer ${
                      activeTab === 'repos' ? 'bg-purple-500 text-white font-bold' : 'text-slate-400 hover:text-white'
                    }`}
                  >
                    Repos ({repos.length})
                  </button>
                  <button
                    onClick={() => { fuzzAudio.playStomp(); setActiveTab('pulls'); }}
                    className={`px-2.5 py-1 rounded transition-colors cursor-pointer ${
                      activeTab === 'pulls' ? 'bg-purple-500 text-white font-bold' : 'text-slate-400 hover:text-white'
                    }`}
                  >
                    Pull Requests
                  </button>
                </div>

                <button
                  onClick={handleDisconnect}
                  className="text-[11px] font-mono text-red-400 hover:text-red-300 p-1 cursor-pointer"
                >
                  Disconnect
                </button>
              </div>
            </div>

            {/* Repositories Tab */}
            {activeTab === 'repos' && (
              <div className="flex-1 flex flex-col overflow-hidden">
                {/* Search Bar */}
                <div className="p-3 border-b border-[#181a24] bg-[#0c0d12]">
                  <input
                    type="text"
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    placeholder="Search repositories..."
                    className="w-full px-3 py-1.5 rounded-lg bg-[#141620] border border-[#232736] text-xs text-white placeholder-slate-500 focus:outline-none"
                  />
                </div>

                <div className="flex-1 overflow-y-auto p-4 space-y-2.5">
                  {filteredRepos.map((repo) => {
                    const isSelected = selectedRepo?.id === repo.id;
                    return (
                      <div
                        key={repo.id}
                        onClick={() => handleSelectRepo(repo)}
                        className={`p-3 rounded-xl border transition-all cursor-pointer flex items-center justify-between ${
                          isSelected
                            ? 'bg-[#181a24] border-purple-500/60 shadow-sm'
                            : 'bg-[#12141c] border-[#1f2330] hover:border-[#2a3042]'
                        }`}
                      >
                        <div className="min-w-0 pr-3">
                          <div className="flex items-center gap-2">
                            <span className="text-xs font-bold text-white font-mono truncate">
                              {repo.fullName}
                            </span>
                            {repo.private && (
                              <span className="text-[9px] font-mono uppercase bg-slate-800 text-slate-400 px-1.5 py-0.2 rounded">
                                Private
                              </span>
                            )}
                          </div>
                          {repo.description && (
                            <p className="text-[11px] text-slate-400 mt-0.5 line-clamp-1">
                              {repo.description}
                            </p>
                          )}
                          <div className="flex items-center gap-3 text-[10px] font-mono text-slate-500 mt-1">
                            <span className="flex items-center gap-1">
                              <Star className="w-3 h-3 text-amber-400 fill-amber-400" />
                              {repo.stargazersCount}
                            </span>
                            <span>branch: {repo.defaultBranch}</span>
                            <span>{repo.openIssuesCount} issues</span>
                          </div>
                        </div>

                        <button
                          onClick={(e) => {
                            e.stopPropagation();
                            handleDispatchToAgent(repo);
                          }}
                          className="flex items-center gap-1 px-3 py-1.5 text-xs font-semibold text-black bg-emerald-400 hover:bg-emerald-300 rounded-lg transition-colors cursor-pointer shrink-0 shadow-sm shadow-emerald-500/20"
                        >
                          <Terminal className="w-3 h-3" />
                          <span>Load in Agent</span>
                        </button>
                      </div>
                    );
                  })}
                </div>
              </div>
            )}

            {/* Pull Requests Tab */}
            {activeTab === 'pulls' && (
              <div className="flex-1 overflow-y-auto p-4 space-y-3">
                <div className="text-[11px] font-mono text-slate-400">
                  Open PRs for <span className="text-white font-bold">{selectedRepo?.fullName || 'Active Repository'}</span>:
                </div>

                {pulls.map((pr) => (
                  <div
                    key={pr.id}
                    className="p-3.5 rounded-xl bg-[#12141c] border border-[#1f2330] space-y-2"
                  >
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <GitPullRequest className="w-3.5 h-3.5 text-emerald-400" />
                        <span className="text-xs font-bold text-white">
                          #{pr.number} {pr.title}
                        </span>
                      </div>
                      <span className={`text-[10px] font-mono font-bold uppercase px-1.5 py-0.5 rounded ${
                        pr.state === 'open' ? 'bg-emerald-500/20 text-emerald-400' : 'bg-purple-500/20 text-purple-300'
                      }`}>
                        {pr.state}
                      </span>
                    </div>

                    <div className="flex items-center justify-between text-[10px] font-mono text-slate-400">
                      <span>{pr.headBranch} → {pr.baseBranch}</span>
                      <div className="flex items-center gap-1.5">
                        <span className="text-emerald-400">+{pr.additions}</span>
                        <span className="text-red-400">-{pr.deletions}</span>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
};
