import React, { useState } from 'react';
import { Plus, Sliders, Play, Copy, Trash2, Edit3, CheckCircle2, AlertCircle, RefreshCw } from 'lucide-react';
import { ProviderConfig } from '../../types';
import { OpenAIService } from '../../services/openAiService';
import { fuzzAudio } from '../../services/audioService';

interface ProvidersTabProps {
  providers: ProviderConfig[];
  setProviders: React.Dispatch<React.SetStateAction<ProviderConfig[]>>;
  onOpenEndpointModal: (provider?: ProviderConfig) => void;
  onOpenChatGPTModal: () => void;
}

export const ProvidersTab: React.FC<ProvidersTabProps> = ({
  providers,
  setProviders,
  onOpenEndpointModal,
  onOpenChatGPTModal
}) => {
  const [testingId, setTestingId] = useState<string | null>(null);
  const [testResults, setTestResults] = useState<Record<string, { latency?: number; error?: string }>>({});

  const handleToggle = (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    fuzzAudio.playStomp();
    setProviders(prev => prev.map(p => p.id === id ? { ...p, isEnabled: !p.isEnabled } : p));
  };

  const handleDuplicate = (provider: ProviderConfig, e: React.MouseEvent) => {
    e.stopPropagation();
    fuzzAudio.playStomp();
    const copy: ProviderConfig = {
      ...provider,
      id: `provider_${Date.now()}`,
      displayName: `${provider.displayName} (Copy)`,
      createdAt: new Date().toISOString()
    };
    setProviders(prev => [...prev, copy]);
  };

  const handleDelete = (id: string, e: React.MouseEvent) => {
    e.stopPropagation();
    fuzzAudio.playStomp();
    setProviders(prev => prev.filter(p => p.id !== id));
  };

  const handleTestConnection = async (provider: ProviderConfig, e: React.MouseEvent) => {
    e.stopPropagation();
    setTestingId(provider.id);
    fuzzAudio.playStomp();

    try {
      const latency = await OpenAIService.testConnection(provider);
      setTestResults(prev => ({ ...prev, [provider.id]: { latency } }));
      fuzzAudio.playSuccess();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      setTestResults(prev => ({ ...prev, [provider.id]: { error: msg } }));
      fuzzAudio.playAlert();
    } finally {
      setTestingId(null);
    }
  };

  return (
    <div className="flex-1 flex flex-col h-full overflow-hidden bg-[#090a0d]">
      {/* Top Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-[#181a24] bg-[#0d0e14]">
        <div>
          <h2 className="text-sm font-bold text-white uppercase tracking-wider font-mono">
            Model Endpoints
          </h2>
          <p className="text-[11px] text-slate-400">
            OpenAI API & ChatGPT Subscription for Codex
          </p>
        </div>

        <div className="flex items-center gap-1.5">
          <button
            onClick={() => {
              fuzzAudio.playStomp();
              onOpenChatGPTModal();
            }}
            title="Use ChatGPT Subscription for Codex"
            className="flex items-center gap-1 px-2.5 py-1.5 text-xs font-semibold text-emerald-300 bg-emerald-500/15 hover:bg-emerald-500/25 border border-emerald-500/30 rounded-lg transition-colors cursor-pointer"
          >
            <span>ChatGPT Codex</span>
          </button>

          <button
            onClick={() => {
              fuzzAudio.playStomp();
              onOpenEndpointModal();
            }}
            className="flex items-center gap-1 px-3 py-1.5 text-xs font-semibold text-black bg-emerald-400 hover:bg-emerald-300 rounded-lg transition-colors cursor-pointer shadow-sm shadow-emerald-500/20"
          >
            <Plus className="w-3.5 h-3.5" />
            <span>Add</span>
          </button>
        </div>
      </div>

      {/* Endpoints List */}
      <div className="flex-1 overflow-y-auto p-4 space-y-3">
        {providers.length === 0 ? (
          <div className="text-center py-12">
            <Sliders className="w-10 h-10 text-slate-600 mx-auto mb-2" />
            <p className="text-xs text-slate-400">No endpoints configured.</p>
          </div>
        ) : (
          providers.map((p) => {
            const result = testResults[p.id];
            const isTesting = testingId === p.id;

            return (
              <div
                key={p.id}
                onClick={() => {
                  fuzzAudio.playStomp();
                  onOpenEndpointModal(p);
                }}
                className="p-3.5 rounded-xl bg-[#12141c] border border-[#1f2330] hover:border-[#2d3345] transition-all cursor-pointer space-y-2.5"
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <button
                      onClick={(e) => handleToggle(p.id, e)}
                      title={p.isEnabled ? 'Active' : 'Disabled'}
                      className={`w-3.5 h-3.5 rounded-full transition-colors cursor-pointer ${
                        p.isEnabled ? 'bg-emerald-400 shadow-[0_0_8px_#34d399]' : 'bg-slate-700'
                      }`}
                    />
                    <span className="text-xs font-bold text-white">
                      {p.displayName}
                    </span>
                    {!p.isEnabled && (
                      <span className="text-[9px] font-mono text-red-400 bg-red-500/10 px-1.5 py-0.2 rounded">
                        OFF
                      </span>
                    )}
                  </div>

                  <div className="flex items-center gap-1 text-slate-400">
                    <button
                      onClick={(e) => handleDuplicate(p, e)}
                      title="Duplicate Endpoint"
                      className="p-1 hover:text-white transition-colors cursor-pointer"
                    >
                      <Copy className="w-3.5 h-3.5" />
                    </button>
                    <button
                      onClick={(e) => handleDelete(p.id, e)}
                      title="Delete Endpoint"
                      className="p-1 hover:text-red-400 transition-colors cursor-pointer"
                    >
                      <Trash2 className="w-3.5 h-3.5" />
                    </button>
                  </div>
                </div>

                {/* Base URL & Model */}
                <div className="flex flex-col gap-1 text-[11px] font-mono">
                  <div className="text-slate-400 truncate">
                    {p.baseURLString}
                  </div>
                  <div className="flex items-center gap-2 text-slate-300 flex-wrap">
                    <span className="text-purple-400 font-semibold">{p.selectedModel}</span>
                    <span className="text-slate-600">·</span>
                    {p.authMethod === 'chatgpt_subscription' ? (
                      <>
                        <span className="text-emerald-400 font-bold uppercase">
                          ChatGPT {p.chatgptSession?.subscriptionTier || 'PLUS'}
                        </span>
                        <span className="text-slate-600">·</span>
                        <span className="text-emerald-300">Codex Engine</span>
                      </>
                    ) : (
                      <span className="text-slate-400">API Key</span>
                    )}
                    <span className="text-slate-600">·</span>
                    <span className="text-slate-500">{p.timeoutSeconds}s timeout</span>
                    {p.allowsInsecureHTTP && (
                      <>
                        <span className="text-slate-600">·</span>
                        <span className="text-amber-400">HTTP dev</span>
                      </>
                    )}
                  </div>
                </div>

                {/* Test Connection Bar */}
                <div className="flex items-center justify-between pt-2 border-t border-white/5">
                  <div className="text-[10px] font-mono">
                    {result?.latency !== undefined ? (
                      <span className="text-emerald-400 font-semibold flex items-center gap-1">
                        <CheckCircle2 className="w-3 h-3" /> {result.latency}ms ping
                      </span>
                    ) : result?.error ? (
                      <span className="text-red-400 flex items-center gap-1 truncate max-w-[180px]">
                        <AlertCircle className="w-3 h-3 shrink-0" /> {result.error}
                      </span>
                    ) : (
                      <span className="text-slate-500">Untested</span>
                    )}
                  </div>

                  <button
                    onClick={(e) => handleTestConnection(p, e)}
                    disabled={isTesting}
                    className="flex items-center gap-1 px-2.5 py-1 text-[10px] font-mono font-bold text-black bg-emerald-400 hover:bg-emerald-300 rounded transition-colors cursor-pointer"
                  >
                    {isTesting ? (
                      <RefreshCw className="w-3 h-3 animate-spin" />
                    ) : (
                      <Play className="w-3 h-3 fill-current" />
                    )}
                    <span>Test Ping</span>
                  </button>
                </div>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
};
