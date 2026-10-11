import React from 'react';
import { X, ShieldAlert, Check, Ban, Terminal } from 'lucide-react';
import { PermissionRequest } from '../../types';
import { fuzzAudio } from '../../services/audioService';

interface PermissionModalProps {
  permission: PermissionRequest | null;
  isOpen: boolean;
  onClose: () => void;
  onDecision: (decision: 'allow_once' | 'allow_always' | 'deny') => void;
}

export const PermissionModal: React.FC<PermissionModalProps> = ({
  permission,
  isOpen,
  onClose,
  onDecision
}) => {
  if (!isOpen || !permission) return null;

  const handleAction = (decision: 'allow_once' | 'allow_always' | 'deny') => {
    if (decision === 'deny') {
      fuzzAudio.playAlert();
    } else {
      fuzzAudio.playSuccess();
    }
    onDecision(decision);
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md animate-in fade-in">
      <div className="w-full max-w-md rounded-2xl bg-[#0f1118] border border-amber-500/40 shadow-2xl overflow-hidden flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-4 border-b border-[#232736] bg-amber-950/20">
          <div className="flex items-center gap-2.5 text-amber-400">
            <ShieldAlert className="w-5 h-5 shrink-0" />
            <div>
              <h3 className="text-sm font-bold uppercase tracking-wider font-mono">
                Interactive Permission Gate
              </h3>
              <p className="text-[10px] text-amber-300/80">
                Agent requested execution authorization
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

        {/* Content */}
        <div className="p-5 space-y-4 text-xs">
          <div>
            <span className="text-[10px] font-mono font-bold text-slate-400 uppercase block mb-1">
              Tool Operation
            </span>
            <div className="flex items-center gap-2 text-white font-mono font-semibold">
              <Terminal className="w-4 h-4 text-purple-400" />
              <span>{permission.toolName}</span>
              <span className="text-[9px] uppercase px-1.5 py-0.5 rounded bg-amber-500/20 text-amber-400">
                {permission.riskLevel} Risk
              </span>
            </div>
          </div>

          <div>
            <span className="text-[10px] font-mono font-bold text-slate-400 uppercase block mb-1">
              Command / Target Payload
            </span>
            <div className="p-3 rounded-lg bg-[#07080a] border border-[#232736] font-mono text-[11px] text-emerald-300 break-all select-all">
              {permission.commandOrPath}
            </div>
          </div>

          {Object.keys(permission.fullParameters).length > 0 && (
            <div>
              <span className="text-[10px] font-mono font-bold text-slate-400 uppercase block mb-1">
                Context Parameters
              </span>
              <div className="p-2.5 rounded-lg bg-[#141620] border border-[#1f2330] space-y-1 font-mono text-[10px] text-slate-400">
                {Object.entries(permission.fullParameters).map(([k, v]) => (
                  <div key={k} className="flex justify-between">
                    <span className="text-slate-500">{k}:</span>
                    <span className="text-slate-300">{v}</span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>

        {/* Decision Actions */}
        <div className="grid grid-cols-2 gap-2 p-4 border-t border-[#1f2330] bg-[#141620]">
          <button
            onClick={() => handleAction('deny')}
            className="flex items-center justify-center gap-1.5 py-2 text-xs font-semibold text-red-400 bg-red-500/10 hover:bg-red-500/20 rounded-lg transition-colors cursor-pointer"
          >
            <Ban className="w-3.5 h-3.5" />
            <span>Deny Command</span>
          </button>

          <button
            onClick={() => handleAction('allow_once')}
            className="flex items-center justify-center gap-1.5 py-2 text-xs font-semibold text-black bg-emerald-400 hover:bg-emerald-300 rounded-lg transition-colors cursor-pointer shadow-sm shadow-emerald-500/20"
          >
            <Check className="w-3.5 h-3.5" />
            <span>Allow Execution</span>
          </button>
        </div>
      </div>
    </div>
  );
};
