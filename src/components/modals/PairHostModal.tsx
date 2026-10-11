import React, { useState } from 'react';
import { X, Link, CheckCircle2, RefreshCw } from 'lucide-react';
import { OpenCodeHostConfig } from '../../types';
import { OpenCodeService } from '../../services/openCodeService';
import { fuzzAudio } from '../../services/audioService';

interface PairHostModalProps {
  isOpen: boolean;
  onClose: () => void;
  onPaired: (host: OpenCodeHostConfig) => void;
}

export const PairHostModal: React.FC<PairHostModalProps> = ({
  isOpen,
  onClose,
  onPaired
}) => {
  const [displayName, setDisplayName] = useState('MacBook Pro M3 (OpenCode)');
  const [hostURL, setHostURL] = useState('http://192.168.1.150:4096');
  const [authToken, setAuthToken] = useState('opencode_fuzz_companion_token');
  const [isVerifying, setIsVerifying] = useState(false);
  const [statusText, setStatusText] = useState<string | null>(null);

  if (!isOpen) return null;

  const handlePair = async () => {
    setIsVerifying(true);
    setStatusText('Testing connection to OpenCode daemon...');
    fuzzAudio.playStomp();

    const host: OpenCodeHostConfig = {
      id: `host_${Date.now()}`,
      displayName: displayName.trim() || 'OpenCode Host',
      hostURLString: hostURL.trim(),
      authToken: authToken.trim(),
      isConnected: true,
      currentWorkspace: '/Users/dev/Projects/FuzzCode',
      capabilities: [
        'sessions',
        'streaming',
        'tool_events',
        'cancellation',
        'file_diffs',
        'permission_requests',
        'project_selection',
        'git_status',
        'session_resumption'
      ],
      lastSeen: new Date().toISOString()
    };

    try {
      const health = await OpenCodeService.testHostHealth(host);
      host.agentVersion = health.version;
      fuzzAudio.playSuccess();
      onPaired(host);
      onClose();
    } catch {
      setStatusText('Connection failed. Verify OpenCode daemon is running on your LAN.');
      fuzzAudio.playAlert();
    } finally {
      setIsVerifying(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-sm animate-in fade-in">
      <div className="w-full max-w-md rounded-2xl bg-[#0f1118] border border-[#232736] shadow-2xl overflow-hidden flex flex-col">
        <div className="flex items-center justify-between px-5 py-3.5 border-b border-[#1f2330] bg-[#141620]">
          <div>
            <h3 className="text-sm font-bold text-white uppercase tracking-wider font-mono">
              Pair OpenCode Host
            </h3>
            <p className="text-[11px] text-slate-400">
              Connect to your external development machine companion
            </p>
          </div>
          <button
            onClick={() => { fuzzAudio.playStomp(); onClose(); }}
            className="text-slate-400 hover:text-white p-1 rounded-md transition-colors cursor-pointer"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="p-5 space-y-4 text-xs">
          <div>
            <label className="block text-[11px] font-mono font-bold text-slate-400 uppercase mb-1">
              Host Display Name
            </label>
            <input
              type="text"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              placeholder="e.g. MacBook Pro M3, Cloud VM"
              className="w-full px-3 py-2 rounded-lg bg-[#181a24] border border-[#2b3042] text-white focus:outline-none focus:border-emerald-400"
            />
          </div>

          <div>
            <label className="block text-[11px] font-mono font-bold text-slate-400 uppercase mb-1">
              Host URL (Local LAN or Tailscale)
            </label>
            <input
              type="text"
              value={hostURL}
              onChange={(e) => setHostURL(e.target.value)}
              placeholder="http://192.168.1.150:4096"
              className="w-full px-3 py-2 rounded-lg bg-[#181a24] border border-[#2b3042] text-white font-mono text-[11px] focus:outline-none focus:border-emerald-400"
            />
          </div>

          <div>
            <label className="block text-[11px] font-mono font-bold text-slate-400 uppercase mb-1">
              Companion Token (Stored in Keychain)
            </label>
            <input
              type="password"
              value={authToken}
              onChange={(e) => setAuthToken(e.target.value)}
              placeholder="your-secret-companion-token"
              className="w-full px-3 py-2 rounded-lg bg-[#181a24] border border-[#2b3042] text-white font-mono text-[11px] focus:outline-none focus:border-emerald-400"
            />
          </div>

          <div className="p-3 rounded-lg bg-[#13151f] border border-[#1e2230] text-[11px] text-slate-400 leading-relaxed">
            <span className="text-purple-400 font-bold font-mono">CLI Setup:</span> Run{' '}
            <code className="text-emerald-300 font-mono">opencode serve --port 4096</code> on your Mac to start the companion server.
          </div>

          {statusText && (
            <p className="text-[11px] font-mono text-amber-400">
              {statusText}
            </p>
          )}
        </div>

        <div className="flex items-center justify-end gap-2.5 px-5 py-3 border-t border-[#1f2330] bg-[#141620]">
          <button
            onClick={() => { fuzzAudio.playStomp(); onClose(); }}
            className="px-3.5 py-1.5 text-xs font-medium text-slate-300 hover:text-white bg-[#1a1d28] hover:bg-[#25293a] rounded-lg transition-colors cursor-pointer"
          >
            Cancel
          </button>
          <button
            onClick={handlePair}
            disabled={isVerifying}
            className="flex items-center gap-1.5 px-4 py-1.5 text-xs font-semibold text-black bg-emerald-400 hover:bg-emerald-300 rounded-lg transition-colors cursor-pointer shadow-sm shadow-emerald-500/20"
          >
            {isVerifying ? <RefreshCw className="w-3.5 h-3.5 animate-spin" /> : <Link className="w-3.5 h-3.5" />}
            <span>Pair & Verify</span>
          </button>
        </div>
      </div>
    </div>
  );
};
