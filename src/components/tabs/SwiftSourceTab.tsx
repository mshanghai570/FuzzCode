import React, { useState } from 'react';
import { Code, Download, Copy, Check, FileCode, CheckCircle2 } from 'lucide-react';
import { SWIFT_PROJECT_FILES, downloadSwiftProjectZip, SwiftProjectFile } from '../../services/exportService';
import { fuzzAudio } from '../../services/audioService';

export const SwiftSourceTab: React.FC = () => {
  const [selectedFile, setSelectedFile] = useState<SwiftProjectFile>(SWIFT_PROJECT_FILES[0]);
  const [categoryFilter, setCategoryFilter] = useState<'all' | 'core' | 'ui' | 'tests' | 'docs'>('all');
  const [copied, setCopied] = useState(false);

  const filteredFiles = SWIFT_PROJECT_FILES.filter(f => 
    categoryFilter === 'all' ? true : f.category === categoryFilter
  );

  const handleCopyCode = () => {
    navigator.clipboard.writeText(selectedFile.content);
    setCopied(true);
    fuzzAudio.playSuccess();
    setTimeout(() => setCopied(false), 2000);
  };

  const handleDownloadZip = async () => {
    fuzzAudio.playStomp();
    await downloadSwiftProjectZip();
  };

  return (
    <div className="flex-1 flex flex-col h-full overflow-hidden bg-[#090a0d]">
      {/* Header */}
      <div className="flex items-center justify-between px-4 py-3 border-b border-[#181a24] bg-[#0d0e14]">
        <div>
          <h2 className="text-sm font-bold text-white uppercase tracking-wider font-mono">
            Native Swift Source Inspector
          </h2>
          <p className="text-[11px] text-slate-400">
            Exportable Xcode 15/16+ Swift 5.9 Project (iOS 17+)
          </p>
        </div>

        <button
          onClick={handleDownloadZip}
          className="flex items-center gap-1.5 px-3 py-1.5 text-xs font-semibold text-black bg-emerald-400 hover:bg-emerald-300 rounded-lg transition-colors cursor-pointer shadow-sm shadow-emerald-500/20"
        >
          <Download className="w-3.5 h-3.5" />
          <span>Export .ZIP</span>
        </button>
      </div>

      {/* Filter Tabs */}
      <div className="flex items-center gap-1 px-4 py-2 bg-[#10121a] border-b border-[#181a24] overflow-x-auto text-[11px] font-mono">
        {(['all', 'core', 'ui', 'tests', 'docs'] as const).map(cat => (
          <button
            key={cat}
            onClick={() => {
              fuzzAudio.playStomp();
              setCategoryFilter(cat);
            }}
            className={`px-2.5 py-1 rounded capitalize transition-colors cursor-pointer ${
              categoryFilter === cat
                ? 'bg-emerald-400 text-black font-bold'
                : 'text-slate-400 hover:text-white hover:bg-white/5'
            }`}
          >
            {cat}
          </button>
        ))}
      </div>

      {/* Split Viewer: File List & Code Editor */}
      <div className="flex-1 flex flex-col md:flex-row overflow-hidden">
        {/* File Navigator */}
        <div className="w-full md:w-64 border-b md:border-b-0 md:border-r border-[#181a24] bg-[#0c0d12] overflow-y-auto">
          {filteredFiles.map(file => {
            const isSelected = file.path === selectedFile.path;
            return (
              <button
                key={file.path}
                onClick={() => {
                  fuzzAudio.playStomp();
                  setSelectedFile(file);
                }}
                className={`w-full flex items-center gap-2 px-3 py-2 text-left text-xs font-mono transition-colors cursor-pointer ${
                  isSelected
                    ? 'bg-emerald-500/10 text-emerald-300 border-l-2 border-emerald-400'
                    : 'text-slate-400 hover:bg-white/5 hover:text-slate-200'
                }`}
              >
                <FileCode className="w-3.5 h-3.5 shrink-0 text-slate-500" />
                <span className="truncate">{file.path}</span>
              </button>
            );
          })}
        </div>

        {/* Code Content View */}
        <div className="flex-1 flex flex-col overflow-hidden bg-[#07080b]">
          {/* File Title Bar */}
          <div className="flex items-center justify-between px-4 py-2 border-b border-[#181a24] bg-[#0d0e14]">
            <span className="text-xs font-mono font-semibold text-slate-300 truncate">
              {selectedFile.path}
            </span>

            <button
              onClick={handleCopyCode}
              className="flex items-center gap-1 px-2.5 py-1 text-[11px] font-mono text-slate-300 bg-[#1a1d28] hover:bg-[#25293a] rounded transition-colors cursor-pointer"
            >
              {copied ? (
                <>
                  <Check className="w-3 h-3 text-emerald-400" />
                  <span className="text-emerald-400">Copied</span>
                </>
              ) : (
                <>
                  <Copy className="w-3 h-3" />
                  <span>Copy Swift</span>
                </>
              )}
            </button>
          </div>

          {/* Syntax Highlighted Code Viewer */}
          <div className="flex-1 overflow-auto p-4 font-mono text-xs text-slate-200 leading-relaxed">
            <pre>
              <code>{selectedFile.content}</code>
            </pre>
          </div>
        </div>
      </div>
    </div>
  );
};
