import { Cpu, Terminal, Zap, MessageSquare, Sliders, GitPullRequest, ArrowRight, ShieldCheck, FolderGit2, Network } from 'lucide-react';
import { ProviderConfig, OpenCodeHostConfig, ChatConversation, AgentSession } from '../../types';
import { fuzzAudio } from '../../services/audioService';

interface HomeTabProps {
  providers: ProviderConfig[];
  hosts: OpenCodeHostConfig[];
  conversations: ChatConversation[];
  sessions: AgentSession[];
  setActiveTab: (tab: string) => void;
  onOpenDiffReview: () => void;
  onOpenChatGPTModal?: () => void;
  onOpenGitHub?: () => void;
  onOpenMCP?: () => void;
  isGitHubConnected?: boolean;
  activeMCPCount?: number;
}

export const HomeTab: React.FC<HomeTabProps> = ({
  providers,
  hosts,
  conversations,
  sessions,
  setActiveTab,
  onOpenDiffReview,
  onOpenChatGPTModal,
  onOpenGitHub,
  onOpenMCP,
  isGitHubConnected,
  activeMCPCount = 0
}) => {
  const activeProvidersCount = providers.filter(p => p.isEnabled).length;
  const isHostConnected = hosts.some(h => h.isConnected);
  const activeSessionsCount = sessions.filter(s => s.status === 'running' || s.status === 'waiting_permission').length;

  return (
    <div className="flex-1 px-4 py-4 space-y-5 overflow-y-auto">
      {/* Editorial Header */}
      <div>
        <div className="text-[11px] font-mono font-bold text-emerald-400 tracking-wider">
          CONTROL CENTER
        </div>
        <h1 className="text-xl font-extrabold tracking-tight text-white mt-0.5">
          FUZZCODE
        </h1>
        <p className="text-xs text-slate-400 mt-0.5">
          A little distortion. A lot of control.
        </p>
      </div>

      {/* 3 Telemetry Cards */}
      <div className="grid grid-cols-3 gap-2.5">
        <div className="p-3 rounded-xl bg-[#11131a] border border-[#1e2230]">
          <div className="flex items-center justify-between text-emerald-400 mb-1.5">
            <Cpu className="w-3.5 h-3.5" />
          </div>
          <div className="text-[9px] font-mono font-bold text-slate-500 uppercase tracking-wider">
            PROVIDERS
          </div>
          <div className="text-xs font-bold text-white mt-0.5">
            {activeProvidersCount} Active
          </div>
        </div>

        <div className="p-3 rounded-xl bg-[#11131a] border border-[#1e2230]">
          <div className="flex items-center justify-between text-purple-400 mb-1.5">
            <Terminal className="w-3.5 h-3.5" />
          </div>
          <div className="text-[9px] font-mono font-bold text-slate-500 uppercase tracking-wider">
            OPENCODE
          </div>
          <div className="text-xs font-bold text-white mt-0.5">
            {isHostConnected ? 'Paired' : 'Standby'}
          </div>
        </div>

        <div className="p-3 rounded-xl bg-[#11131a] border border-[#1e2230]">
          <div className="flex items-center justify-between text-emerald-400 mb-1.5">
            <Zap className="w-3.5 h-3.5" />
          </div>
          <div className="text-[9px] font-mono font-bold text-slate-500 uppercase tracking-wider">
            SESSIONS
          </div>
          <div className="text-xs font-bold text-white mt-0.5">
            {activeSessionsCount} Active
          </div>
        </div>
      </div>

      {/* Quick Workflows Grid */}
      <div className="space-y-2">
        <div className="text-[11px] font-mono font-bold text-slate-400 uppercase tracking-wider">
          Quick Workflows
        </div>

        {/* ChatGPT Codex Feature Action */}
        {onOpenChatGPTModal && (
          <button
            onClick={() => { fuzzAudio.playStomp(); onOpenChatGPTModal(); }}
            className="w-full flex items-center justify-between p-3 rounded-xl bg-gradient-to-r from-emerald-950/40 to-[#151722] border border-emerald-500/30 hover:border-emerald-500/60 transition-all text-left group cursor-pointer"
          >
            <div className="flex items-center gap-2.5">
              <div className="w-7 h-7 rounded-lg bg-emerald-500/15 border border-emerald-500/30 flex items-center justify-center text-emerald-400">
                <Cpu className="w-4 h-4" />
              </div>
              <div>
                <span className="text-xs font-bold text-white block group-hover:text-emerald-300">
                  Log in with ChatGPT for Codex
                </span>
                <span className="text-[10px] text-slate-400 block">
                  Use ChatGPT Plus/Pro subscription for unlimited coding agent sessions
                </span>
              </div>
            </div>
            <ArrowRight className="w-3.5 h-3.5 text-slate-500 group-hover:text-emerald-400 transition-colors" />
          </button>
        )}

        <div className="grid grid-cols-2 gap-2">
          <button
            onClick={() => { fuzzAudio.playStomp(); setActiveTab('chat'); }}
            className="flex items-center justify-between p-3 rounded-xl bg-[#151722] border border-[#232736] hover:border-emerald-500/50 transition-all text-left group cursor-pointer"
          >
            <div className="flex items-center gap-2">
              <MessageSquare className="w-4 h-4 text-emerald-400" />
              <span className="text-xs font-semibold text-slate-200 group-hover:text-white">
                New AI Chat
              </span>
            </div>
            <ArrowRight className="w-3 h-3 text-slate-600 group-hover:text-emerald-400 transition-colors" />
          </button>

          <button
            onClick={() => { fuzzAudio.playStomp(); setActiveTab('agents'); }}
            className="flex items-center justify-between p-3 rounded-xl bg-[#151722] border border-[#232736] hover:border-purple-500/50 transition-all text-left group cursor-pointer"
          >
            <div className="flex items-center gap-2">
              <Terminal className="w-4 h-4 text-purple-400" />
              <span className="text-xs font-semibold text-slate-200 group-hover:text-white">
                OpenCode Agent
              </span>
            </div>
            <ArrowRight className="w-3 h-3 text-slate-600 group-hover:text-purple-400 transition-colors" />
          </button>

          <button
            onClick={() => { fuzzAudio.playStomp(); setActiveTab('providers'); }}
            className="flex items-center justify-between p-3 rounded-xl bg-[#151722] border border-[#232736] hover:border-emerald-500/50 transition-all text-left group cursor-pointer"
          >
            <div className="flex items-center gap-2">
              <Sliders className="w-4 h-4 text-slate-400" />
              <span className="text-xs font-semibold text-slate-200 group-hover:text-white">
                Endpoints
              </span>
            </div>
            <ArrowRight className="w-3 h-3 text-slate-600 group-hover:text-slate-300 transition-colors" />
          </button>

          <button
            onClick={() => { fuzzAudio.playStomp(); onOpenDiffReview(); }}
            className="flex items-center justify-between p-3 rounded-xl bg-[#151722] border border-[#232736] hover:border-emerald-500/50 transition-all text-left group cursor-pointer"
          >
            <div className="flex items-center gap-2">
              <GitPullRequest className="w-4 h-4 text-emerald-400" />
              <span className="text-xs font-semibold text-slate-200 group-hover:text-white">
                Diff Review
              </span>
            </div>
            <ArrowRight className="w-3 h-3 text-slate-600 group-hover:text-emerald-400 transition-colors" />
          </button>

          {onOpenGitHub && (
            <button
              onClick={() => { fuzzAudio.playStomp(); onOpenGitHub(); }}
              className="flex items-center justify-between p-3 rounded-xl bg-[#151722] border border-[#232736] hover:border-purple-500/50 transition-all text-left group cursor-pointer"
            >
              <div className="flex items-center gap-2">
                <FolderGit2 className="w-4 h-4 text-purple-400" />
                <span className="text-xs font-semibold text-slate-200 group-hover:text-white">
                  GitHub Repos
                </span>
              </div>
              <ArrowRight className="w-3 h-3 text-slate-600 group-hover:text-purple-400 transition-colors" />
            </button>
          )}

          {onOpenMCP && (
            <button
              onClick={() => { fuzzAudio.playStomp(); onOpenMCP(); }}
              className="flex items-center justify-between p-3 rounded-xl bg-[#151722] border border-[#232736] hover:border-emerald-500/50 transition-all text-left group cursor-pointer"
            >
              <div className="flex items-center gap-2">
                <Network className="w-4 h-4 text-emerald-400" />
                <span className="text-xs font-semibold text-slate-200 group-hover:text-white">
                  MCP Servers ({activeMCPCount})
                </span>
              </div>
              <ArrowRight className="w-3 h-3 text-slate-600 group-hover:text-emerald-400 transition-colors" />
            </button>
          )}
        </div>
      </div>

      {/* Active Agent Sessions */}
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <span className="text-[11px] font-mono font-bold text-slate-400 uppercase tracking-wider">
            Agent Sessions
          </span>
          <button
            onClick={() => { fuzzAudio.playStomp(); setActiveTab('agents'); }}
            className="text-[11px] font-medium text-emerald-400 hover:underline cursor-pointer"
          >
            Manage
          </button>
        </div>

        {sessions.length === 0 ? (
          <div className="p-4 rounded-xl bg-[#11131a] border border-[#1e2230] text-center">
            <p className="text-xs text-slate-400">No active coding sessions</p>
            <p className="text-[10px] text-slate-500 mt-1">Connect an OpenCode host to dispatch autonomous coding tasks.</p>
          </div>
        ) : (
          <div className="space-y-2">
            {sessions.slice(0, 2).map((s) => (
              <div
                key={s.id}
                onClick={() => { fuzzAudio.playStomp(); setActiveTab('agents'); }}
                className="p-3 rounded-xl bg-[#11131a] border border-[#1e2230] hover:border-[#2b3044] transition-all cursor-pointer flex items-center justify-between"
              >
                <div>
                  <div className="text-xs font-semibold text-white">{s.title}</div>
                  <div className="flex items-center gap-2 text-[10px] font-mono text-slate-500 mt-0.5 truncate max-w-[210px]">
                    <span className="truncate">{s.workspacePath}</span>
                    <span className="text-purple-400 bg-purple-500/10 px-1 rounded shrink-0">
                      RAG ({s.ragSources?.filter(sr => sr.isEnabled).length ?? 4})
                    </span>
                  </div>
                </div>
                <span className={`text-[10px] font-mono font-bold uppercase px-2 py-0.5 rounded ${
                  s.status === 'running' ? 'bg-emerald-500/20 text-emerald-400' :
                  s.status === 'waiting_permission' ? 'bg-amber-500/20 text-amber-400' :
                  'bg-slate-800 text-slate-400'
                }`}>
                  {s.status}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Recent AI Conversations */}
      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <span className="text-[11px] font-mono font-bold text-slate-400 uppercase tracking-wider">
            Recent Conversations
          </span>
          <button
            onClick={() => { fuzzAudio.playStomp(); setActiveTab('chat'); }}
            className="text-[11px] font-medium text-emerald-400 hover:underline cursor-pointer"
          >
            Open Chat
          </button>
        </div>

        {conversations.length === 0 ? (
          <div className="p-4 rounded-xl bg-[#11131a] border border-[#1e2230] text-center">
            <p className="text-xs text-slate-400">No chats yet</p>
          </div>
        ) : (
          <div className="space-y-2">
            {conversations.slice(0, 2).map((c) => (
              <div
                key={c.id}
                onClick={() => { fuzzAudio.playStomp(); setActiveTab('chat'); }}
                className="p-3 rounded-xl bg-[#11131a] border border-[#1e2230] hover:border-[#2b3044] transition-all cursor-pointer flex items-center justify-between"
              >
                <div className="truncate max-w-[220px]">
                  <div className="text-xs font-semibold text-white truncate">{c.title}</div>
                  <div className="flex items-center gap-2 text-[10px] font-mono mt-0.5">
                    <span className="text-purple-400">{c.modelId}</span>
                    <span className="text-emerald-400 bg-emerald-500/10 px-1 rounded">
                      RAG ({c.ragSources?.filter(sr => sr.isEnabled).length ?? 2})
                    </span>
                  </div>
                </div>
                <span className="text-[10px] font-mono text-slate-500">
                  {c.messages.length} msgs
                </span>
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Security Trust Marker */}
      <div className="flex items-center gap-2 p-3 rounded-xl bg-[#11131a] border border-[#1e2230] text-slate-400">
        <ShieldCheck className="w-4 h-4 text-emerald-400 shrink-0" />
        <span className="text-[11px] leading-tight">
          Credentials isolated in native Keychain. Zero plain-text leaks.
        </span>
      </div>
    </div>
  );
};
