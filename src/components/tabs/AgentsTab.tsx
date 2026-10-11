import React, { useState } from 'react';
import { Terminal, Plus, ShieldAlert, GitBranch, ArrowRight, Play, Square, CheckCircle2, XCircle, Wrench, Search, FileEdit, Link, FolderGit2, Network, Sparkles, BookOpen } from 'lucide-react';
import { OpenCodeHostConfig, AgentSession, PermissionRequest, AgentToolEvent } from '../../types';
import { OpenCodeService } from '../../services/openCodeService';
import { RAGService } from '../../services/ragService';
import { fuzzAudio } from '../../services/audioService';

interface AgentsTabProps {
  hosts: OpenCodeHostConfig[];
  sessions: AgentSession[];
  setSessions: React.Dispatch<React.SetStateAction<AgentSession[]>>;
  onOpenPairModal: () => void;
  onOpenDiffReview: () => void;
  onInspectPermission: (perm: PermissionRequest, sessionId: string) => void;
  onOpenGitHub?: () => void;
  onOpenMCP?: () => void;
  onOpenRAGPrompt?: (session: AgentSession) => void;
}

export const AgentsTab: React.FC<AgentsTabProps> = ({
  hosts,
  sessions,
  setSessions,
  onOpenPairModal,
  onOpenDiffReview,
  onInspectPermission,
  onOpenGitHub,
  onOpenMCP,
  onOpenRAGPrompt
}) => {
  const [selectedSessionId, setSelectedSessionId] = useState<string>(sessions[0]?.id || '');
  const [instructionInput, setInstructionInput] = useState('');
  const [isRunning, setIsRunning] = useState(false);

  const activeHost = hosts[0];
  const activeSession = sessions.find(s => s.id === selectedSessionId) || sessions[0];

  const handleCreateNewSession = () => {
    fuzzAudio.playStomp();
    const newSession: AgentSession = {
      id: `session_${Date.now()}`,
      hostId: activeHost?.id || '',
      title: 'Optimize API Client & Tests',
      workspacePath: activeHost?.currentWorkspace || '/Users/dev/Projects/FuzzCode',
      status: 'idle',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      systemPrompt: RAGService.getPromptTemplates()[1].content,
      ragConfig: RAGService.getDefaultRAGConfig(),
      ragSources: RAGService.getDefaultProjectRAGSources(),
      messages: [
        {
          id: `msg_${Date.now()}`,
          role: 'assistant',
          content: 'OpenCode session initialized. Ready for developer directives.',
          timestamp: new Date().toISOString(),
          toolEvents: []
        }
      ]
    };
    setSessions(prev => [newSession, ...prev]);
    setSelectedSessionId(newSession.id);
  };

  const handleSendAgentInstruction = async () => {
    const text = instructionInput.trim();
    if (!text || isRunning || !activeSession) return;

    setInstructionInput('');
    setIsRunning(true);
    fuzzAudio.playStomp();

    // RAG Knowledge Base Retrieval for project
    const ragSources = activeSession.ragSources || RAGService.getDefaultProjectRAGSources();
    const ragConfig = activeSession.ragConfig || RAGService.getDefaultRAGConfig();
    const ragRes = RAGService.retrieve(text, ragSources, ragConfig);

    const initialToolEvents: AgentToolEvent[] = [];
    if (ragRes.citations.length > 0) {
      initialToolEvents.push({
        id: `tool_rag_${Date.now()}`,
        toolName: 'rag_knowledge_retrieval',
        argumentsJSON: JSON.stringify({ query: text, matched_sources: ragRes.citations.length }),
        outputSnippet: `Grounded in ${ragRes.citations.length} docs: ${ragRes.citations.map(c => c.sourceTitle).join(', ')}`,
        status: 'success',
        startedAt: new Date().toISOString(),
        completedAt: new Date().toISOString()
      });
    }

    // Append user instruction
    setSessions(prev => prev.map(s => {
      if (s.id === activeSession.id) {
        return {
          ...s,
          status: 'running',
          messages: [
            ...s.messages,
            {
              id: `msg_${Date.now()}_u`,
              role: 'user',
              content: text,
              timestamp: new Date().toISOString(),
              toolEvents: []
            },
            {
              id: `msg_${Date.now()}_a`,
              role: 'assistant',
              content: '',
              timestamp: new Date().toISOString(),
              toolEvents: initialToolEvents,
              retrievedCitations: ragRes.citations.length > 0 ? ragRes.citations : undefined
            }
          ]
        };
      }
      return s;
    }));

    await OpenCodeService.executeAgentPrompt(
      activeSession,
      text,
      {
        onTextDelta: (delta) => {
          setSessions(prev => prev.map(s => {
            if (s.id === activeSession.id) {
              const msgs = [...s.messages];
              const last = msgs[msgs.length - 1];
              if (last && last.role === 'assistant') {
                last.content += delta;
              }
              return { ...s, messages: msgs };
            }
            return s;
          }));
        },
        onToolStarted: (tool) => {
          fuzzAudio.playStomp();
          setSessions(prev => prev.map(s => {
            if (s.id === activeSession.id) {
              const msgs = [...s.messages];
              const last = msgs[msgs.length - 1];
              if (last && last.role === 'assistant') {
                last.toolEvents = [...last.toolEvents, tool];
              }
              return { ...s, messages: msgs };
            }
            return s;
          }));
        },
        onToolFinished: (toolId, output, success) => {
          setSessions(prev => prev.map(s => {
            if (s.id === activeSession.id) {
              const msgs = [...s.messages];
              const last = msgs[msgs.length - 1];
              if (last && last.role === 'assistant') {
                last.toolEvents = last.toolEvents.map(t => t.id === toolId ? {
                  ...t,
                  status: success ? 'success' : 'failed',
                  outputSnippet: output,
                  completedAt: new Date().toISOString()
                } : t);
              }
              return { ...s, messages: msgs };
            }
            return s;
          }));
        },
        onPermissionNeeded: (perm) => {
          fuzzAudio.playAlert();
          setSessions(prev => prev.map(s => {
            if (s.id === activeSession.id) {
              return {
                ...s,
                status: 'waiting_permission',
                pendingPermission: perm
              };
            }
            return s;
          }));
          setIsRunning(false);
          onInspectPermission(perm, activeSession.id);
        },
        onFinished: () => {
          fuzzAudio.playSuccess();
          setIsRunning(false);
          setSessions(prev => prev.map(s => s.id === activeSession.id ? { ...s, status: 'completed' } : s));
        }
      }
    );
  };

  const handleCancelTask = () => {
    fuzzAudio.playStomp();
    setIsRunning(false);
    setSessions(prev => prev.map(s => s.id === activeSession?.id ? { ...s, status: 'cancelled' } : s));
  };

  return (
    <div className="flex-1 flex flex-col h-full overflow-hidden bg-[#090a0d]">
      {/* Top Bar: Host Status & Quick Actions */}
      <div className="flex items-center justify-between px-4 py-2.5 border-b border-[#181a24] bg-[#0d0e14]">
        <div className="flex items-center gap-2">
          <span className={`w-2 h-2 rounded-full ${activeHost?.isConnected ? 'bg-emerald-400' : 'bg-purple-400'}`} />
          <div className="text-xs font-semibold text-white truncate max-w-[150px]">
            {activeHost?.displayName || 'No Host Paired'}
          </div>
          <span className="text-[10px] font-mono text-slate-400">
            {activeHost?.agentVersion || 'v0.14.2'}
          </span>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => { fuzzAudio.playStomp(); onOpenDiffReview(); }}
            title="Inspect Git Diffs"
            className="flex items-center gap-1 px-2 py-1 text-[11px] font-mono text-emerald-400 bg-emerald-500/10 hover:bg-emerald-500/20 rounded-md transition-colors cursor-pointer"
          >
            <GitBranch className="w-3.5 h-3.5" />
            <span>Diffs</span>
          </button>

          <button
            onClick={onOpenPairModal}
            title="Pair OpenCode Host"
            className="p-1 text-slate-400 hover:text-white transition-colors cursor-pointer"
          >
            <Link className="w-4 h-4" />
          </button>
        </div>
      </div>

      {/* Session Workspace Header */}
      {activeSession && (
        <div className="px-4 py-2 bg-[#10121a] border-b border-[#181a24] flex items-center justify-between text-xs">
          <div className="truncate max-w-[200px]">
            <span className="text-[10px] font-mono text-slate-500 uppercase mr-1.5">Workspace</span>
            <span className="font-mono text-slate-300 text-[11px]">{activeSession.workspacePath}</span>
            {activeHost?.useChatGPTSubscriptionForCodex && (
              <span className="text-[10px] font-mono text-emerald-400 block mt-0.5 font-semibold">
                Codex Engine · ChatGPT Subscription
              </span>
            )}
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={() => {
                fuzzAudio.playStomp();
                if (onOpenRAGPrompt && activeSession) onOpenRAGPrompt(activeSession);
              }}
              title="Configure Project Directives & RAG Knowledge Base"
              className="flex items-center gap-1.5 px-2 py-0.5 text-[10px] font-mono rounded-lg border bg-[#141624] border-purple-500/30 text-purple-300 hover:border-purple-500/60 transition-colors cursor-pointer"
            >
              <Sparkles className="w-3 h-3 text-purple-400" />
              <span>Project RAG</span>
              <span className="text-[9px] bg-purple-500/20 text-purple-300 px-1 rounded font-bold">
                {activeSession.ragSources?.filter(s => s.isEnabled).length ?? 4}
              </span>
            </button>

            <span className={`text-[10px] font-mono font-bold uppercase px-2 py-0.5 rounded ${
              activeSession.status === 'running' ? 'bg-emerald-500/20 text-emerald-400' :
              activeSession.status === 'waiting_permission' ? 'bg-amber-500/20 text-amber-400' :
              activeSession.status === 'completed' ? 'bg-purple-500/20 text-purple-400' :
              'bg-slate-800 text-slate-400'
            }`}>
              {activeSession.status}
            </span>
          </div>
        </div>
      )}

      {/* Interactive Permission Request Banner if pending */}
      {activeSession?.pendingPermission && (
        <div className="mx-4 my-2 p-3 rounded-xl bg-amber-950/30 border border-amber-500/40 text-xs text-amber-200">
          <div className="flex items-center gap-2 mb-1.5">
            <ShieldAlert className="w-4 h-4 text-amber-400 shrink-0" />
            <span className="font-mono font-bold uppercase text-[10px] text-amber-400 tracking-wider">
              Permission Required
            </span>
          </div>
          <div className="text-[11px] font-mono text-slate-200 bg-black/40 p-2 rounded border border-white/5 truncate mb-2">
            $ {activeSession.pendingPermission.commandOrPath}
          </div>
          <button
            onClick={() => {
              fuzzAudio.playStomp();
              onInspectPermission(activeSession.pendingPermission!, activeSession.id);
            }}
            className="w-full py-1.5 text-xs font-semibold text-black bg-amber-400 hover:bg-amber-300 rounded-lg transition-colors cursor-pointer"
          >
            Review & Resolve Permission
          </button>
        </div>
      )}

      {/* Timeline of Messages & Tool Executions */}
      <div className="flex-1 overflow-y-auto px-4 py-3 space-y-3">
        {(!activeSession || activeSession.messages.length === 0) ? (
          <div className="h-full flex flex-col items-center justify-center text-center p-6">
            <Terminal className="w-10 h-10 text-purple-400 mb-2" />
            <div className="text-xs font-bold text-white uppercase tracking-wider font-mono">
              OpenCode Autonomous Runtime
            </div>
            <p className="text-xs text-slate-400 mt-1 max-w-xs">
              No sessions active. Create a session to run coding agent tasks.
            </p>
            <button
              onClick={handleCreateNewSession}
              className="mt-4 px-4 py-2 text-xs font-semibold text-black bg-emerald-400 rounded-lg cursor-pointer"
            >
              Start Session
            </button>
          </div>
        ) : (
          activeSession.messages.map((msg) => (
            <div key={msg.id} className="space-y-2">
              <div
                className={`p-3 rounded-xl text-xs leading-relaxed ${
                  msg.role === 'user'
                    ? 'bg-[#1b202e] border border-[#262e42] text-white'
                    : 'bg-[#12141c] border border-[#1f2330] text-slate-200'
                }`}
              >
                <div className="flex items-center justify-between text-[10px] font-mono font-bold mb-1.5">
                  <span className={msg.role === 'user' ? 'text-purple-400' : 'text-emerald-400'}>
                    {msg.role === 'user' ? 'USER DIRECTIVE' : 'OPENCODE AGENT'}
                  </span>
                </div>
                <div className="whitespace-pre-wrap">{msg.content}</div>

                {/* Tool Executions Under This Message */}
                {msg.toolEvents.length > 0 && (
                  <div className="mt-3 pt-2.5 border-t border-white/5 space-y-1.5">
                    <span className="text-[10px] font-mono font-bold text-slate-400 uppercase tracking-wider">
                      Tool Activity
                    </span>
                    {msg.toolEvents.map((tool) => (
                      <div
                        key={tool.id}
                        className="flex items-start gap-2 p-2 rounded-lg bg-[#07080b] border border-[#1f2330] text-[11px] font-mono"
                      >
                        {tool.toolName === 'execute_bash' ? (
                          <Terminal className="w-3.5 h-3.5 text-purple-400 shrink-0 mt-0.5" />
                        ) : tool.toolName === 'rag_knowledge_retrieval' ? (
                          <BookOpen className="w-3.5 h-3.5 text-emerald-400 shrink-0 mt-0.5" />
                        ) : tool.toolName === 'ripgrep' ? (
                          <Search className="w-3.5 h-3.5 text-blue-400 shrink-0 mt-0.5" />
                        ) : (
                          <FileEdit className="w-3.5 h-3.5 text-emerald-400 shrink-0 mt-0.5" />
                        )}
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center justify-between">
                            <span className="font-bold text-white">{tool.toolName}</span>
                            <span className={`text-[9px] font-bold uppercase ${
                              tool.status === 'success' ? 'text-emerald-400' :
                              tool.status === 'running' ? 'text-amber-400 animate-pulse' :
                              'text-red-400'
                            }`}>
                              {tool.status}
                            </span>
                          </div>
                          {tool.outputSnippet && (
                            <div className="text-slate-400 text-[10px] truncate mt-0.5">
                              {tool.outputSnippet}
                            </div>
                          )}
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          ))
        )}
      </div>

      {/* Instruction Input Bar */}
      <div className="p-3 border-t border-[#181a24] bg-[#0c0d12]">
        <div className="flex items-center gap-2 bg-[#151722] border border-[#232736] rounded-2xl px-3 py-1.5">
          <input
            type="text"
            value={instructionInput}
            onChange={(e) => setInstructionInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter') handleSendAgentInstruction();
            }}
            placeholder="Instruct OpenCode (e.g. Add unit tests)..."
            className="flex-1 bg-transparent text-xs text-white placeholder-slate-500 focus:outline-none py-1.5"
          />

          {isRunning ? (
            <button
              onClick={handleCancelTask}
              title="Cancel Task"
              className="w-8 h-8 rounded-full bg-red-500 hover:bg-red-400 text-black flex items-center justify-center transition-all cursor-pointer shrink-0"
            >
              <Square className="w-3.5 h-3.5 fill-current" />
            </button>
          ) : (
            <button
              onClick={handleSendAgentInstruction}
              disabled={!instructionInput.trim()}
              title="Dispatch to Agent"
              className={`w-8 h-8 rounded-full flex items-center justify-center transition-all cursor-pointer shrink-0 ${
                instructionInput.trim()
                  ? 'bg-purple-500 hover:bg-purple-400 text-white shadow-sm shadow-purple-500/20'
                  : 'bg-slate-800 text-slate-500 cursor-not-allowed'
              }`}
            >
              <Play className="w-3.5 h-3.5 fill-current" />
            </button>
          )}
        </div>
      </div>
    </div>
  );
};
