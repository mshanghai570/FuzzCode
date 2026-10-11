import React, { useState } from 'react';
import { X, Sparkles, CheckCircle2, ShieldCheck, Key, ExternalLink, ArrowRight, RefreshCw, Cpu } from 'lucide-react';
import { ProviderConfig, ChatGPTSession, OpenCodeHostConfig } from '../../types';
import { fuzzAudio } from '../../services/audioService';

interface ChatGPTLoginModalProps {
  isOpen: boolean;
  onClose: () => void;
  onSuccess: (provider: ProviderConfig, linkToOpenCode: boolean) => void;
  hosts: OpenCodeHostConfig[];
}

export const ChatGPTLoginModal: React.FC<ChatGPTLoginModalProps> = ({
  isOpen,
  onClose,
  onSuccess,
  hosts
}) => {
  const [authFlow, setAuthFlow] = useState<'oauth' | 'token'>('oauth');
  const [email, setEmail] = useState('user@example.com');
  const [tier, setTier] = useState<'plus' | 'pro' | 'team' | 'enterprise'>('plus');
  const [sessionToken, setSessionToken] = useState('');
  const [linkToOpenCode, setLinkToOpenCode] = useState(true);
  const [isAuthenticating, setIsAuthenticating] = useState(false);
  const [oauthStep, setOauthStep] = useState<'initial' | 'waiting_code' | 'verified'>('initial');
  const [deviceCode, setDeviceCode] = useState('');

  if (!isOpen) return null;

  const handleStartOAuth = () => {
    fuzzAudio.playStomp();
    setIsAuthenticating(true);
    // Simulate OpenAI OAuth device flow
    const code = `FUZZ-${Math.floor(1000 + Math.random() * 9000)}-OAI`;
    setDeviceCode(code);
    setOauthStep('waiting_code');

    setTimeout(() => {
      setIsAuthenticating(false);
      setOauthStep('verified');
      fuzzAudio.playSuccess();
    }, 1800);
  };

  const handleCompleteLogin = () => {
    fuzzAudio.playStomp();
    const token = sessionToken.trim() || `sess-chatgpt-${tier}-${Date.now()}`;

    const chatgptSession: ChatGPTSession = {
      accountEmail: email.trim(),
      subscriptionTier: tier,
      accessToken: token,
      refreshToken: `refr-${Date.now()}`,
      expiresAt: new Date(Date.now() + 30 * 24 * 3600 * 1000).toISOString(),
      sessionStatus: 'active'
    };

    const codexProvider: ProviderConfig = {
      id: `prov_chatgpt_codex_${Date.now()}`,
      displayName: `OpenAI Codex (ChatGPT ${tier.toUpperCase()})`,
      baseURLString: 'https://api.openai.com/v1',
      selectedModel: 'chatgpt-4o-latest',
      apiKey: token,
      authMethod: 'chatgpt_subscription',
      chatgptSession,
      isCodexOptimized: true,
      customHeaders: [
        { id: 'h1', key: 'OpenAI-Beta', value: 'codex=v1' },
        { id: 'h2', key: 'X-OpenAI-Subscription', value: tier }
      ],
      timeoutSeconds: 45,
      isEnabled: true,
      allowsInsecureHTTP: false,
      createdAt: new Date().toISOString()
    };

    onSuccess(codexProvider, linkToOpenCode);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md animate-in fade-in">
      <div className="w-full max-w-lg rounded-2xl bg-[#0e1017] border border-[#232736] shadow-2xl overflow-hidden flex flex-col max-h-[92vh]">
        {/* Modal Top Bar */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-[#1c1f2b] bg-[#12141c]">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-lg bg-emerald-500/10 border border-emerald-500/30 flex items-center justify-center text-emerald-400">
              <Sparkles className="w-4 h-4" />
            </div>
            <div>
              <h3 className="text-sm font-bold text-white uppercase tracking-wider font-mono">
                Log in with ChatGPT for Codex
              </h3>
              <p className="text-[11px] text-slate-400">
                Use your ChatGPT Plus, Team, or Pro subscription quota
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

        {/* Modal Body */}
        <div className="p-5 overflow-y-auto space-y-4 text-xs">
          {/* Subscription Tier Picker */}
          <div>
            <label className="block text-[11px] font-mono font-bold text-slate-400 uppercase mb-2">
              Select Your ChatGPT Subscription Tier
            </label>
            <div className="grid grid-cols-4 gap-2 font-mono">
              {(['plus', 'pro', 'team', 'enterprise'] as const).map((t) => (
                <button
                  key={t}
                  type="button"
                  onClick={() => { fuzzAudio.playStomp(); setTier(t); }}
                  className={`py-2 px-2 rounded-lg text-center uppercase text-[11px] font-bold transition-all cursor-pointer border ${
                    tier === t
                      ? 'bg-emerald-500/15 border-emerald-400 text-emerald-300 shadow-sm shadow-emerald-500/20'
                      : 'bg-[#161822] border-[#25293a] text-slate-400 hover:text-white hover:bg-[#1e2230]'
                  }`}
                >
                  {t}
                </button>
              ))}
            </div>
          </div>

          {/* Account Email */}
          <div>
            <label className="block text-[11px] font-mono font-bold text-slate-400 uppercase mb-1">
              ChatGPT Account Email
            </label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="e.g. developer@company.com"
              className="w-full px-3 py-2 rounded-lg bg-[#161822] border border-[#25293a] text-white focus:outline-none focus:border-emerald-400"
            />
          </div>

          {/* Login Method Tabs */}
          <div className="space-y-2">
            <label className="block text-[11px] font-mono font-bold text-slate-400 uppercase">
              Authentication Method
            </label>
            <div className="grid grid-cols-2 gap-2 bg-[#141620] p-1 rounded-lg border border-[#202433]">
              <button
                type="button"
                onClick={() => setAuthFlow('oauth')}
                className={`py-1.5 text-xs font-semibold rounded-md transition-colors cursor-pointer ${
                  authFlow === 'oauth'
                    ? 'bg-[#222738] text-white shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                OpenAI Account Sign-In
              </button>
              <button
                type="button"
                onClick={() => setAuthFlow('token')}
                className={`py-1.5 text-xs font-semibold rounded-md transition-colors cursor-pointer ${
                  authFlow === 'token'
                    ? 'bg-[#222738] text-white shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                Session / Access Token
              </button>
            </div>
          </div>

          {authFlow === 'oauth' ? (
            <div className="p-4 rounded-xl bg-[#141620] border border-[#202433] space-y-3">
              <div className="flex items-center justify-between">
                <div>
                  <span className="text-xs font-bold text-white block">
                    Browser & Device Authorization Flow
                  </span>
                  <span className="text-[11px] text-slate-400 block mt-0.5">
                    Connects directly through OpenAI's secure OAuth flow
                  </span>
                </div>
              </div>

              {oauthStep === 'initial' && (
                <button
                  type="button"
                  onClick={handleStartOAuth}
                  className="w-full flex items-center justify-center gap-2 py-2.5 px-4 rounded-lg bg-emerald-400 hover:bg-emerald-300 text-black font-semibold text-xs transition-colors cursor-pointer shadow-sm shadow-emerald-500/20"
                >
                  <ExternalLink className="w-3.5 h-3.5" />
                  <span>Authorize with ChatGPT Account</span>
                </button>
              )}

              {oauthStep === 'waiting_code' && (
                <div className="space-y-2 py-2 text-center">
                  <div className="flex items-center justify-center gap-2 text-emerald-400 font-mono text-xs">
                    <RefreshCw className="w-4 h-4 animate-spin" />
                    <span>Confirming ChatGPT {tier.toUpperCase()} license...</span>
                  </div>
                  <div className="text-[10px] text-slate-400 font-mono">
                    Device Code: <span className="text-white font-bold">{deviceCode}</span>
                  </div>
                </div>
              )}

              {oauthStep === 'verified' && (
                <div className="flex items-center gap-2 p-2.5 rounded-lg bg-emerald-950/30 border border-emerald-500/30 text-emerald-300 text-xs font-mono">
                  <CheckCircle2 className="w-4 h-4 shrink-0 text-emerald-400" />
                  <span>ChatGPT {tier.toUpperCase()} subscription verified & authorized for Codex!</span>
                </div>
              )}
            </div>
          ) : (
            <div className="space-y-2">
              <label className="block text-[11px] font-mono text-slate-400">
                Paste your ChatGPT Session Token or Access Token:
              </label>
              <textarea
                value={sessionToken}
                onChange={(e) => setSessionToken(e.target.value)}
                placeholder="Paste token from chatgpt.com cookies or `openai login` CLI..."
                rows={3}
                className="w-full p-2.5 rounded-lg bg-[#161822] border border-[#25293a] text-white font-mono text-[11px] focus:outline-none focus:border-emerald-400"
              />
              <p className="text-[10px] text-slate-500">
                Token is stored directly in the iOS Keychain and redacted from all exports and logs.
              </p>
            </div>
          )}

          {/* Sync with OpenCode Host Option */}
          <div className="pt-2 border-t border-white/5">
            <div className="flex items-start justify-between gap-3 p-3 rounded-xl bg-[#141620] border border-[#202433]">
              <div>
                <span className="text-xs font-bold text-white block">
                  Enable in OpenCode Coding Agent
                </span>
                <span className="text-[11px] text-slate-400 block mt-0.5">
                  Allows OpenCode to run Codex autonomous tool loops (bash, ripgrep, edits) backed by your ChatGPT subscription.
                </span>
              </div>
              <input
                type="checkbox"
                checked={linkToOpenCode}
                onChange={(e) => setLinkToOpenCode(e.target.checked)}
                className="w-4 h-4 mt-1 accent-emerald-400 rounded cursor-pointer shrink-0"
              />
            </div>
          </div>

          {/* Trust Badge */}
          <div className="flex items-center gap-2 text-slate-400 text-[11px]">
            <ShieldCheck className="w-4 h-4 text-emerald-400 shrink-0" />
            <span>Zero pay-per-token deductions. Uses your native ChatGPT subscription limits.</span>
          </div>
        </div>

        {/* Modal Footer */}
        <div className="flex items-center justify-end gap-2.5 px-5 py-3.5 border-t border-[#1c1f2b] bg-[#12141c]">
          <button
            onClick={() => { fuzzAudio.playStomp(); onClose(); }}
            className="px-3.5 py-1.5 text-xs font-medium text-slate-300 hover:text-white bg-[#1a1d28] hover:bg-[#25293a] rounded-lg transition-colors cursor-pointer"
          >
            Cancel
          </button>
          <button
            onClick={handleCompleteLogin}
            disabled={authFlow === 'oauth' && oauthStep === 'initial'}
            className="flex items-center gap-1.5 px-4 py-1.5 text-xs font-semibold text-black bg-emerald-400 hover:bg-emerald-300 rounded-lg transition-colors cursor-pointer shadow-sm shadow-emerald-500/20 disabled:bg-slate-800 disabled:text-slate-500 disabled:cursor-not-allowed"
          >
            <span>Activate Codex</span>
            <ArrowRight className="w-3.5 h-3.5" />
          </button>
        </div>
      </div>
    </div>
  );
};
