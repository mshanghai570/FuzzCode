import React, { useState } from 'react';
import { X, Search, Sliders, CheckCircle2, AlertTriangle, RefreshCw } from 'lucide-react';
import { ProviderConfig, ModelInfo } from '../../types';
import { OpenAIService } from '../../services/openAiService';
import { fuzzAudio } from '../../services/audioService';

interface EndpointModalProps {
  provider?: ProviderConfig;
  isOpen: boolean;
  onClose: () => void;
  onSave: (provider: ProviderConfig) => void;
}

export const EndpointModal: React.FC<EndpointModalProps> = ({
  provider,
  isOpen,
  onClose,
  onSave
}) => {
  const [displayName, setDisplayName] = useState(provider?.displayName || 'OpenAI Compatible');
  const [baseURL, setBaseURL] = useState(provider?.baseURLString || 'https://api.openai.com/v1');
  const [apiKey, setApiKey] = useState(provider?.apiKey || '');
  const [selectedModel, setSelectedModel] = useState(provider?.selectedModel || 'gpt-4o');
  const [organizationId, setOrganizationId] = useState(provider?.organizationId || '');
  const [customApiPath, setCustomApiPath] = useState(provider?.customApiPath || '');
  const [timeoutSeconds, setTimeoutSeconds] = useState(provider?.timeoutSeconds || 30);
  const [allowsInsecureHTTP, setAllowsInsecureHTTP] = useState(provider?.allowsInsecureHTTP || false);

  const [authMethod, setAuthMethod] = useState<'api_key' | 'chatgpt_subscription'>(provider?.authMethod || 'api_key');
  const [subscriptionTier, setSubscriptionTier] = useState<'plus' | 'pro' | 'team' | 'enterprise'>(
    provider?.chatgptSession?.subscriptionTier || 'plus'
  );
  const [isCodexOptimized, setIsCodexOptimized] = useState(provider?.isCodexOptimized ?? false);

  const [isDiscovering, setIsDiscovering] = useState(false);
  const [discoveredModels, setDiscoveredModels] = useState<ModelInfo[]>([]);
  const [discoveryError, setDiscoveryError] = useState<string | null>(null);

  if (!isOpen) return null;

  const handleDiscover = async () => {
    setIsDiscovering(true);
    setDiscoveryError(null);
    fuzzAudio.playStomp();

    const tempConfig: ProviderConfig = {
      id: provider?.id || `prov_${Date.now()}`,
      displayName,
      baseURLString: baseURL,
      selectedModel,
      apiKey,
      authMethod,
      chatgptSession: authMethod === 'chatgpt_subscription' ? {
        subscriptionTier,
        accessToken: apiKey,
        sessionStatus: 'active'
      } : undefined,
      customHeaders: [],
      timeoutSeconds,
      isEnabled: true,
      allowsInsecureHTTP,
      createdAt: new Date().toISOString()
    };

    try {
      const models = await OpenAIService.discoverModels(tempConfig);
      setDiscoveredModels(models);
      if (models.length > 0) {
        setSelectedModel(models[0].id);
      }
      fuzzAudio.playSuccess();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      setDiscoveryError(msg);
      fuzzAudio.playAlert();
    } finally {
      setIsDiscovering(false);
    }
  };

  const handleSave = () => {
    fuzzAudio.playStomp();
    const isSub = authMethod === 'chatgpt_subscription';
    const config: ProviderConfig = {
      id: provider?.id || `prov_${Date.now()}`,
      displayName: displayName.trim() || (isSub ? `OpenAI Codex (${subscriptionTier.toUpperCase()})` : 'Custom Endpoint'),
      baseURLString: baseURL.trim(),
      selectedModel: selectedModel.trim() || (isSub ? 'chatgpt-4o-latest' : 'gpt-4o'),
      apiKey: apiKey.trim(),
      authMethod,
      chatgptSession: isSub ? {
        accountEmail: provider?.chatgptSession?.accountEmail || 'user@chatgpt.subscription',
        subscriptionTier,
        accessToken: apiKey.trim(),
        sessionStatus: 'active'
      } : undefined,
      isCodexOptimized: isSub || isCodexOptimized,
      customHeaders: provider?.customHeaders || (isSub ? [
        { id: 'h1', key: 'OpenAI-Beta', value: 'codex=v1' },
        { id: 'h2', key: 'X-OpenAI-Subscription', value: subscriptionTier }
      ] : []),
      organizationId: organizationId.trim() || undefined,
      customApiPath: customApiPath.trim() || undefined,
      timeoutSeconds,
      isEnabled: provider ? provider.isEnabled : true,
      allowsInsecureHTTP,
      createdAt: provider?.createdAt || new Date().toISOString()
    };
    onSave(config);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm animate-in fade-in">
      <div className="w-full max-w-lg rounded-2xl bg-[#0f1118] border border-[#232736] shadow-2xl overflow-hidden flex flex-col max-h-[90vh]">
        {/* Modal Header */}
        <div className="flex items-center justify-between px-5 py-3.5 border-b border-[#1f2330] bg-[#141620]">
          <div>
            <h3 className="text-sm font-bold text-white uppercase tracking-wider font-mono">
              {provider ? 'Edit Model Endpoint' : 'New OpenAI-Compatible Endpoint'}
            </h3>
            <p className="text-[11px] text-slate-400">
              Configure arbitrary base URL, API key, and streaming parameters
            </p>
          </div>
          <button
            onClick={() => { fuzzAudio.playStomp(); onClose(); }}
            className="text-slate-400 hover:text-white p-1 rounded-md transition-colors cursor-pointer"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Modal Body */}
        <div className="p-5 overflow-y-auto space-y-4 text-xs">
          {/* Display Name */}
          <div>
            <label className="block text-[11px] font-mono font-bold text-slate-400 uppercase mb-1">
              Provider Display Name
            </label>
            <input
              type="text"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              placeholder="e.g. Groq Cloud, Ollama Local, Kilo Endpoint"
              className="w-full px-3 py-2 rounded-lg bg-[#181a24] border border-[#2b3042] text-white focus:outline-none focus:border-emerald-400"
            />
          </div>

          {/* Base URL */}
          <div>
            <label className="block text-[11px] font-mono font-bold text-slate-400 uppercase mb-1">
              Base URL
            </label>
            <input
              type="text"
              value={baseURL}
              onChange={(e) => setBaseURL(e.target.value)}
              placeholder="https://api.openai.com/v1"
              className="w-full px-3 py-2 rounded-lg bg-[#181a24] border border-[#2b3042] text-white font-mono text-[11px] focus:outline-none focus:border-emerald-400"
            />
            <p className="text-[10px] text-slate-500 mt-1">
              FuzzCode normalizes base URLs automatically without duplicating /v1 routes.
            </p>
          </div>

          {/* Auth Method Selector */}
          <div>
            <label className="block text-[11px] font-mono font-bold text-slate-400 uppercase mb-1.5">
              Authentication Method
            </label>
            <div className="grid grid-cols-2 gap-2 bg-[#141620] p-1 rounded-lg border border-[#202433]">
              <button
                type="button"
                onClick={() => {
                  fuzzAudio.playStomp();
                  setAuthMethod('api_key');
                }}
                className={`py-1.5 text-xs font-semibold rounded-md transition-colors cursor-pointer ${
                  authMethod === 'api_key'
                    ? 'bg-[#222738] text-white shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                API Key (OpenAI Platform)
              </button>
              <button
                type="button"
                onClick={() => {
                  fuzzAudio.playStomp();
                  setAuthMethod('chatgpt_subscription');
                  if (!displayName.includes('ChatGPT') && !displayName.includes('Codex')) {
                    setDisplayName('OpenAI Codex (ChatGPT Subscription)');
                  }
                  if (selectedModel === 'gpt-4o') {
                    setSelectedModel('chatgpt-4o-latest');
                  }
                }}
                className={`py-1.5 text-xs font-semibold rounded-md transition-colors cursor-pointer ${
                  authMethod === 'chatgpt_subscription'
                    ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                ChatGPT Subscription (Codex)
              </button>
            </div>
          </div>

          {authMethod === 'chatgpt_subscription' && (
            <div className="p-3 rounded-xl bg-[#141620] border border-emerald-500/20 space-y-2">
              <div className="flex items-center justify-between">
                <span className="text-[11px] font-mono font-bold text-emerald-400 uppercase">
                  Subscription Tier
                </span>
                <span className="text-[10px] text-slate-400">Unlimited Codex Reasoning</span>
              </div>
              <div className="grid grid-cols-4 gap-1.5 font-mono">
                {(['plus', 'pro', 'team', 'enterprise'] as const).map((t) => (
                  <button
                    key={t}
                    type="button"
                    onClick={() => { fuzzAudio.playStomp(); setSubscriptionTier(t); }}
                    className={`py-1 rounded text-center uppercase text-[10px] font-bold transition-all cursor-pointer border ${
                      subscriptionTier === t
                        ? 'bg-emerald-500/20 border-emerald-400 text-emerald-300'
                        : 'bg-[#181a24] border-[#25293a] text-slate-400 hover:text-white'
                    }`}
                  >
                    {t}
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* API Key / Access Token */}
          <div>
            <label className="block text-[11px] font-mono font-bold text-slate-400 uppercase mb-1">
              {authMethod === 'chatgpt_subscription'
                ? 'ChatGPT Access / Session Token'
                : 'API Key (Stored in iOS Keychain)'}
            </label>
            <input
              type="password"
              value={apiKey}
              onChange={(e) => setApiKey(e.target.value)}
              placeholder={authMethod === 'chatgpt_subscription' ? 'sess-chatgpt-token...' : 'sk-proj-••••••••'}
              className="w-full px-3 py-2 rounded-lg bg-[#181a24] border border-[#2b3042] text-white font-mono text-[11px] focus:outline-none focus:border-emerald-400"
            />
            <p className="text-[10px] text-slate-500 mt-1">
              {authMethod === 'chatgpt_subscription'
                ? 'Uses your ChatGPT subscription quota for Codex completions without API billing.'
                : 'Leave blank to test with simulated inference in preview.'}
            </p>
          </div>

          {/* Model Specification & Discovery */}
          <div>
            <div className="flex items-center justify-between mb-1">
              <label className="text-[11px] font-mono font-bold text-slate-400 uppercase">
                Model Identifier
              </label>
              <button
                type="button"
                onClick={handleDiscover}
                disabled={isDiscovering}
                className="flex items-center gap-1 text-[10px] font-mono text-emerald-400 hover:text-emerald-300 cursor-pointer"
              >
                {isDiscovering ? <RefreshCw className="w-3 h-3 animate-spin" /> : <Search className="w-3 h-3" />}
                <span>Discover Models</span>
              </button>
            </div>

            <input
              type="text"
              value={selectedModel}
              onChange={(e) => setSelectedModel(e.target.value)}
              placeholder="gpt-4o, llama-3.3-70b, claude-3-5-sonnet"
              className="w-full px-3 py-2 rounded-lg bg-[#181a24] border border-[#2b3042] text-white font-mono text-[11px] focus:outline-none focus:border-emerald-400"
            />

            {discoveredModels.length > 0 && (
              <div className="mt-2 p-2 rounded-lg bg-[#141620] border border-[#232734]">
                <span className="text-[10px] font-mono text-slate-400 uppercase block mb-1">
                  Discovered from endpoint:
                </span>
                <select
                  value={selectedModel}
                  onChange={(e) => setSelectedModel(e.target.value)}
                  className="w-full p-1.5 rounded bg-[#1f2230] text-xs text-white border border-[#2f354a] font-mono focus:outline-none"
                >
                  {discoveredModels.map(m => (
                    <option key={m.id} value={m.id}>{m.id}</option>
                  ))}
                </select>
              </div>
            )}

            {discoveryError && (
              <p className="text-[10px] text-amber-400 mt-1">
                {discoveryError} (You can enter model manually)
              </p>
            )}
          </div>

          {/* Advanced: Timeout & Insecure HTTP */}
          <div className="pt-2 border-t border-white/5 space-y-3">
            <div className="flex items-center justify-between">
              <div>
                <span className="text-xs font-semibold text-white">Connection Timeout</span>
                <span className="text-[10px] text-slate-500 block">Seconds before aborting request</span>
              </div>
              <span className="font-mono text-xs font-bold text-emerald-400">{timeoutSeconds}s</span>
            </div>
            <input
              type="range"
              min="5"
              max="120"
              step="5"
              value={timeoutSeconds}
              onChange={(e) => setTimeoutSeconds(Number(e.target.value))}
              className="w-full accent-emerald-400 cursor-pointer"
            />

            <div className="flex items-center justify-between pt-1">
              <div>
                <span className="text-xs font-semibold text-white">Allow Insecure HTTP</span>
                <span className="text-[10px] text-slate-500 block">For trusted local LAN (Ollama, LM Studio)</span>
              </div>
              <input
                type="checkbox"
                checked={allowsInsecureHTTP}
                onChange={(e) => setAllowsInsecureHTTP(e.target.checked)}
                className="w-4 h-4 accent-red-400 rounded cursor-pointer"
              />
            </div>
          </div>
        </div>

        {/* Modal Footer */}
        <div className="flex items-center justify-end gap-2.5 px-5 py-3 border-t border-[#1f2330] bg-[#141620]">
          <button
            onClick={() => { fuzzAudio.playStomp(); onClose(); }}
            className="px-3.5 py-1.5 text-xs font-medium text-slate-300 hover:text-white bg-[#1a1d28] hover:bg-[#25293a] rounded-lg transition-colors cursor-pointer"
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            className="px-4 py-1.5 text-xs font-semibold text-black bg-emerald-400 hover:bg-emerald-300 rounded-lg transition-colors cursor-pointer shadow-sm shadow-emerald-500/20"
          >
            Save Endpoint
          </button>
        </div>
      </div>
    </div>
  );
};
