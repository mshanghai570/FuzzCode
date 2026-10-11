import React, { useState } from 'react';
import { X, GitBranch, Plus, Minus, FileCode, Check, Send } from 'lucide-react';
import { GitStatusSummary, GitFileDiff } from '../../types';
import { fuzzAudio } from '../../services/audioService';

interface DiffModalProps {
  summary: GitStatusSummary;
  isOpen: boolean;
  onClose: () => void;
  onSendFollowUp: (prompt: string) => void;
}

export const DiffModal: React.FC<DiffModalProps> = ({
  summary,
  isOpen,
  onClose,
  onSendFollowUp
}) => {
  const [selectedFile, setSelectedFile] = useState<GitFileDiff>(summary.changedFiles[0]);
  const [diffViewMode, setDiffViewMode] = useState<'unified' | 'split'>('unified');
  const [followUpText, setFollowUpText] = useState('');

  if (!isOpen) return null;

  const totalAdditions = summary.changedFiles.reduce((acc, f) => acc + f.additions, 0);
  const totalDeletions = summary.changedFiles.reduce((acc, f) => acc + f.deletions, 0);

  const handleSendFollowUp = () => {
    if (!followUpText.trim()) return;
    fuzzAudio.playStomp();
    onSendFollowUp(`Concerning diff in ${selectedFile.filePath}: ${followUpText}`);
    setFollowUpText('');
    onClose();
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md animate-in fade-in">
      <div className="w-full max-w-4xl h-[85vh] rounded-2xl bg-[#0b0c10] border border-[#232736] shadow-2xl overflow-hidden flex flex-col">
        {/* Top Header */}
        <div className="flex items-center justify-between px-6 py-3.5 border-b border-[#181a24] bg-[#12141c]">
          <div className="flex items-center gap-3">
            <GitBranch className="w-4 h-4 text-purple-400" />
            <div>
              <div className="flex items-center gap-2">
                <span className="text-xs font-mono font-bold text-white">{summary.branch}</span>
                <span className="text-[10px] font-mono text-emerald-400 font-bold">+{totalAdditions}</span>
                <span className="text-[10px] font-mono text-red-400 font-bold">-{totalDeletions}</span>
              </div>
              <span className="text-[10px] text-slate-400 block mt-0.5">
                {summary.changedFiles.length} changed files in working tree
              </span>
            </div>
          </div>

          <div className="flex items-center gap-3">
            <div className="flex items-center bg-[#1b1e2a] rounded-lg p-0.5 border border-[#262c3e] text-[10px] font-mono">
              <button
                onClick={() => setDiffViewMode('unified')}
                className={`px-2.5 py-1 rounded transition-colors cursor-pointer ${
                  diffViewMode === 'unified' ? 'bg-emerald-400 text-black font-bold' : 'text-slate-400 hover:text-white'
                }`}
              >
                Unified
              </button>
              <button
                onClick={() => setDiffViewMode('split')}
                className={`px-2.5 py-1 rounded transition-colors cursor-pointer ${
                  diffViewMode === 'split' ? 'bg-emerald-400 text-black font-bold' : 'text-slate-400 hover:text-white'
                }`}
              >
                Split
              </button>
            </div>

            <button
              onClick={() => { fuzzAudio.playStomp(); onClose(); }}
              className="text-slate-400 hover:text-white p-1 rounded-md transition-colors cursor-pointer"
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        </div>

        {/* Body Split */}
        <div className="flex-1 flex flex-col md:flex-row overflow-hidden">
          {/* File Selector */}
          <div className="w-full md:w-72 border-b md:border-b-0 md:border-r border-[#181a24] bg-[#0e1017] overflow-y-auto">
            {summary.changedFiles.map((file) => {
              const isSelected = file.id === selectedFile.id;
              return (
                <button
                  key={file.id}
                  onClick={() => {
                    fuzzAudio.playStomp();
                    setSelectedFile(file);
                  }}
                  className={`w-full flex items-center justify-between p-3 text-left transition-colors cursor-pointer ${
                    isSelected ? 'bg-emerald-500/10 border-l-2 border-emerald-400' : 'hover:bg-white/5'
                  }`}
                >
                  <div className="truncate pr-2">
                    <span className="text-xs font-mono text-white block truncate">
                      {file.filePath.split('/').pop()}
                    </span>
                    <span className="text-[10px] font-mono text-slate-500 truncate block">
                      {file.filePath}
                    </span>
                  </div>
                  <div className="flex items-center gap-1.5 shrink-0 text-[10px] font-mono">
                    <span className="text-emerald-400 font-bold">+{file.additions}</span>
                    <span className="text-red-400 font-bold">-{file.deletions}</span>
                  </div>
                </button>
              );
            })}
          </div>

          {/* Diff Patch Display */}
          <div className="flex-1 flex flex-col overflow-hidden bg-[#07080b]">
            <div className="flex-1 overflow-auto p-3 font-mono text-xs leading-5">
              {selectedFile.patch.split('\n').map((line, idx) => {
                const isAdd = line.startsWith('+') && !line.startsWith('+++');
                const isDel = line.startsWith('-') && !line.startsWith('---');
                const isHeader = line.startsWith('@@');

                return (
                  <div
                    key={idx}
                    className={`px-3 py-0.5 select-text ${
                      isAdd ? 'bg-emerald-950/30 text-emerald-300' :
                      isDel ? 'bg-red-950/30 text-red-300' :
                      isHeader ? 'bg-purple-950/20 text-purple-400 font-bold' :
                      'text-slate-400'
                    }`}
                  >
                    {line}
                  </div>
                );
              })}
            </div>

            {/* Follow-up Prompt Bar */}
            <div className="p-3 border-t border-[#181a24] bg-[#0e1017] flex items-center gap-2">
              <input
                type="text"
                value={followUpText}
                onChange={(e) => setFollowUpText(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter') handleSendFollowUp(); }}
                placeholder={`Ask agent to adjust ${selectedFile.filePath.split('/').pop()}...`}
                className="flex-1 bg-[#161822] border border-[#232736] rounded-xl px-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none"
              />
              <button
                onClick={handleSendFollowUp}
                disabled={!followUpText.trim()}
                className="flex items-center gap-1 px-3 py-1.5 text-xs font-semibold text-black bg-emerald-400 hover:bg-emerald-300 rounded-xl transition-colors cursor-pointer disabled:bg-slate-800 disabled:text-slate-500"
              >
                <Send className="w-3.5 h-3.5" />
                <span>Send</span>
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
