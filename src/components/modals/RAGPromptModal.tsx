import React, { useState } from 'react';
import { X, Sparkles, BookOpen, Plus, Trash2, CheckCircle2, Sliders, Search, ArrowRight, FileText, Code2, Link, ShieldAlert, Cpu } from 'lucide-react';
import { RAGSource, RAGConfig, PromptTemplate, RAGSourceType, RetrievedCitation } from '../../types';
import { RAGService } from '../../services/ragService';
import { fuzzAudio } from '../../services/audioService';

interface RAGPromptModalProps {
  isOpen: boolean;
  onClose: () => void;
  scopeTitle: string; // e.g. "Chat: Swift Concurrency" or "Project: OpenCode Agent"
  scopeType: 'chat' | 'project';
  currentPrompt: string;
  onSavePrompt: (prompt: string) => void;
  ragConfig: RAGConfig;
  onSaveRAGConfig: (config: RAGConfig) => void;
  ragSources: RAGSource[];
  onSaveRAGSources: (sources: RAGSource[]) => void;
}

export const RAGPromptModal: React.FC<RAGPromptModalProps> = ({
  isOpen,
  onClose,
  scopeTitle,
  scopeType,
  currentPrompt,
  onSavePrompt,
  ragConfig,
  onSaveRAGConfig,
  ragSources,
  onSaveRAGSources
}) => {
  const [activeTab, setActiveTab] = useState<'prompt' | 'rag_sources' | 'test_search' | 'settings'>('prompt');
  const [promptText, setPromptText] = useState(currentPrompt);
  const [sources, setSources] = useState<RAGSource[]>(ragSources);
  const [config, setConfig] = useState<RAGConfig>(ragConfig);

  // New source form states
  const [isAddingSource, setIsAddingSource] = useState(false);
  const [newTitle, setNewTitle] = useState('');
  const [newType, setNewType] = useState<RAGSourceType>('doc');
  const [newContent, setNewContent] = useState('');
  const [newFilePath, setNewFilePath] = useState('');

  // Test retrieval search
  const [testQuery, setTestQuery] = useState('');
  const [testResults, setTestResults] = useState<{
    citations: RetrievedCitation[];
    augmentedContext: string;
  } | null>(null);

  const templates = RAGService.getPromptTemplates();

  React.useEffect(() => {
    setPromptText(currentPrompt);
    setSources(ragSources);
    setConfig(ragConfig);
  }, [currentPrompt, ragSources, ragConfig, isOpen]);

  if (!isOpen) return null;

  const handleApplyTemplate = (tmpl: PromptTemplate) => {
    fuzzAudio.playStomp();
    setPromptText(tmpl.content);
  };

  const handleToggleSource = (id: string) => {
    fuzzAudio.playStomp();
    const updated = sources.map(s => s.id === id ? { ...s, isEnabled: !s.isEnabled } : s);
    setSources(updated);
  };

  const handleDeleteSource = (id: string) => {
    fuzzAudio.playAlert();
    const updated = sources.filter(s => s.id !== id);
    setSources(updated);
  };

  const handleAddSource = () => {
    if (!newTitle.trim() || !newContent.trim()) return;
    fuzzAudio.playSuccess();

    const tokens = Math.max(Math.round(newContent.length / 4), 1);
    const newSource: RAGSource = {
      id: `rag_${Date.now()}`,
      title: newTitle.trim(),
      type: newType,
      content: newContent.trim(),
      filePath: newFilePath.trim() || undefined,
      tokens,
      chunksCount: Math.ceil(tokens / 120),
      isEnabled: true,
      addedAt: new Date().toISOString()
    };

    setSources(prev => [...prev, newSource]);
    setIsAddingSource(false);
    setNewTitle('');
    setNewContent('');
    setNewFilePath('');
  };

  const handleRunTestSearch = () => {
    fuzzAudio.playStomp();
    const res = RAGService.retrieve(testQuery, sources, config);
    setTestResults(res);
  };

  const handleSaveAndClose = () => {
    fuzzAudio.playSuccess();
    onSavePrompt(promptText);
    onSaveRAGConfig(config);
    onSaveRAGSources(sources);
    onClose();
  };

  const totalTokens = sources.reduce((acc, s) => acc + (s.isEnabled ? s.tokens : 0), 0);
  const enabledCount = sources.filter(s => s.isEnabled).length;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md">
      <div className="w-full max-w-2xl bg-[#0d0e14] border border-[#232736] rounded-2xl shadow-2xl overflow-hidden flex flex-col max-h-[90vh]">
        {/* Header */}
        <div className="flex items-center justify-between px-5 py-3.5 border-b border-[#1d212d] bg-[#090a0f]">
          <div className="flex items-center gap-2.5">
            <div className="w-7 h-7 rounded-lg bg-emerald-500/15 border border-emerald-500/30 flex items-center justify-center text-emerald-400">
              <Sparkles className="w-4 h-4" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="text-sm font-bold text-white tracking-wide">
                  Prompt & RAG Knowledge Base
                </h3>
                <span className="text-[10px] font-mono px-2 py-0.5 rounded bg-[#181a24] text-emerald-400 border border-[#232736] uppercase">
                  {scopeType}
                </span>
              </div>
              <p className="text-[11px] font-mono text-slate-400 truncate max-w-sm">
                {scopeTitle}
              </p>
            </div>
          </div>

          <button
            onClick={onClose}
            className="p-1.5 text-slate-400 hover:text-white rounded-lg hover:bg-white/5 transition-colors cursor-pointer"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Navigation Tabs */}
        <div className="flex items-center gap-1 px-5 py-2 border-b border-[#1d212d] bg-[#0c0d12] text-xs font-mono overflow-x-auto">
          <button
            onClick={() => { fuzzAudio.playStomp(); setActiveTab('prompt'); }}
            className={`px-3 py-1.5 rounded-lg transition-colors cursor-pointer flex items-center gap-1.5 ${
              activeTab === 'prompt'
                ? 'bg-emerald-400 text-black font-bold'
                : 'text-slate-400 hover:text-white hover:bg-white/5'
            }`}
          >
            <Sparkles className="w-3.5 h-3.5" />
            <span>Directives</span>
          </button>

          <button
            onClick={() => { fuzzAudio.playStomp(); setActiveTab('rag_sources'); }}
            className={`px-3 py-1.5 rounded-lg transition-colors cursor-pointer flex items-center gap-1.5 ${
              activeTab === 'rag_sources'
                ? 'bg-emerald-400 text-black font-bold'
                : 'text-slate-400 hover:text-white hover:bg-white/5'
            }`}
          >
            <BookOpen className="w-3.5 h-3.5" />
            <span>RAG Sources ({enabledCount}/{sources.length})</span>
          </button>

          <button
            onClick={() => { fuzzAudio.playStomp(); setActiveTab('test_search'); }}
            className={`px-3 py-1.5 rounded-lg transition-colors cursor-pointer flex items-center gap-1.5 ${
              activeTab === 'test_search'
                ? 'bg-emerald-400 text-black font-bold'
                : 'text-slate-400 hover:text-white hover:bg-white/5'
            }`}
          >
            <Search className="w-3.5 h-3.5" />
            <span>Test Retrieval</span>
          </button>

          <button
            onClick={() => { fuzzAudio.playStomp(); setActiveTab('settings'); }}
            className={`px-3 py-1.5 rounded-lg transition-colors cursor-pointer flex items-center gap-1.5 ${
              activeTab === 'settings'
                ? 'bg-emerald-400 text-black font-bold'
                : 'text-slate-400 hover:text-white hover:bg-white/5'
            }`}
          >
            <Sliders className="w-3.5 h-3.5" />
            <span>RAG Tuning</span>
          </button>
        </div>

        {/* Tab Body */}
        <div className="flex-1 overflow-y-auto p-5 space-y-4 text-xs">
          {/* TAB 1: SYSTEM PROMPT DIRECTIVES */}
          {activeTab === 'prompt' && (
            <div className="space-y-4">
              <div>
                <div className="flex items-center justify-between mb-1.5">
                  <label className="text-[11px] font-mono font-bold text-slate-300 uppercase tracking-wider">
                    System Prompt / Custom Directives
                  </label>
                  <span className="text-[10px] font-mono text-slate-500">
                    ~{Math.round(promptText.length / 4)} tokens
                  </span>
                </div>
                <textarea
                  value={promptText}
                  onChange={(e) => setPromptText(e.target.value)}
                  rows={7}
                  placeholder="Enter system prompt instructions, persona rules, or coding conventions..."
                  className="w-full p-3 rounded-xl bg-[#141620] border border-[#232736] text-white font-mono text-xs focus:outline-none focus:border-emerald-500/60 leading-relaxed resize-none"
                />
              </div>

              {/* Template Presets */}
              <div>
                <div className="text-[11px] font-mono font-bold text-slate-400 uppercase tracking-wider mb-2">
                  Apply Preset Directive
                </div>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
                  {templates.map((tmpl) => (
                    <button
                      key={tmpl.id}
                      onClick={() => handleApplyTemplate(tmpl)}
                      className="p-2.5 rounded-xl bg-[#12141c] border border-[#1f2330] hover:border-emerald-500/50 text-left transition-all group cursor-pointer"
                    >
                      <div className="font-semibold text-white group-hover:text-emerald-300 flex items-center justify-between">
                        <span>{tmpl.title}</span>
                        <ArrowRight className="w-3 h-3 text-slate-600 group-hover:text-emerald-400 transition-colors" />
                      </div>
                      <p className="text-[10px] text-slate-400 mt-1 line-clamp-2">
                        {tmpl.description}
                      </p>
                    </button>
                  ))}
                </div>
              </div>
            </div>
          )}

          {/* TAB 2: RAG SOURCES LIST & ADD */}
          {activeTab === 'rag_sources' && (
            <div className="space-y-4">
              {/* Header metrics & Add button */}
              <div className="flex items-center justify-between p-3 rounded-xl bg-[#12141c] border border-[#1f2330]">
                <div>
                  <div className="flex items-center gap-2">
                    <span className="font-bold text-white">Active RAG Index</span>
                    <span className={`w-2 h-2 rounded-full ${config.isEnabled ? 'bg-emerald-400' : 'bg-slate-600'}`} />
                  </div>
                  <div className="text-[11px] font-mono text-slate-400 mt-0.5">
                    {enabledCount} sources enabled · ~{totalTokens} total tokens indexed
                  </div>
                </div>

                <div className="flex items-center gap-2">
                  <button
                    onClick={() => {
                      fuzzAudio.playStomp();
                      setConfig(prev => ({ ...prev, isEnabled: !prev.isEnabled }));
                    }}
                    className={`px-2.5 py-1 text-[11px] font-mono rounded-lg transition-colors cursor-pointer ${
                      config.isEnabled
                        ? 'bg-emerald-500/20 text-emerald-400 border border-emerald-500/30'
                        : 'bg-slate-800 text-slate-400'
                    }`}
                  >
                    {config.isEnabled ? 'RAG Active' : 'RAG Paused'}
                  </button>

                  <button
                    onClick={() => { fuzzAudio.playStomp(); setIsAddingSource(!isAddingSource); }}
                    className="flex items-center gap-1 px-3 py-1 text-xs font-semibold text-black bg-emerald-400 hover:bg-emerald-300 rounded-lg transition-colors cursor-pointer"
                  >
                    <Plus className="w-3.5 h-3.5" />
                    <span>Add Source</span>
                  </button>
                </div>
              </div>

              {/* Add Source Drawer Form */}
              {isAddingSource && (
                <div className="p-4 rounded-xl bg-[#141724] border border-emerald-500/40 space-y-3">
                  <div className="flex items-center justify-between">
                    <span className="font-bold text-white font-mono text-xs uppercase tracking-wider">
                      Add New Knowledge Source
                    </span>
                    <button
                      onClick={() => setIsAddingSource(false)}
                      className="text-slate-400 hover:text-white"
                    >
                      <X className="w-3.5 h-3.5" />
                    </button>
                  </div>

                  <div className="grid grid-cols-2 gap-2">
                    <div>
                      <label className="text-[10px] font-mono text-slate-400 block mb-1">
                        SOURCE TITLE
                      </label>
                      <input
                        type="text"
                        value={newTitle}
                        onChange={(e) => setNewTitle(e.target.value)}
                        placeholder="e.g. API Specification, Guidelines"
                        className="w-full px-2.5 py-1.5 rounded-lg bg-[#0c0d12] border border-[#232736] text-white text-xs focus:outline-none focus:border-emerald-500"
                      />
                    </div>

                    <div>
                      <label className="text-[10px] font-mono text-slate-400 block mb-1">
                        TYPE
                      </label>
                      <select
                        value={newType}
                        onChange={(e) => setNewType(e.target.value as RAGSourceType)}
                        className="w-full px-2.5 py-1.5 rounded-lg bg-[#0c0d12] border border-[#232736] text-white text-xs focus:outline-none focus:border-emerald-500 font-mono"
                      >
                        <option value="doc">Markdown Document</option>
                        <option value="guideline">Engineering Guideline</option>
                        <option value="snippet">Code Snippet</option>
                        <option value="file">Workspace File</option>
                        <option value="url">External Spec / URL</option>
                      </select>
                    </div>
                  </div>

                  <div>
                    <label className="text-[10px] font-mono text-slate-400 block mb-1">
                      FILE PATH OR REFERENCE (OPTIONAL)
                    </label>
                    <input
                      type="text"
                      value={newFilePath}
                      onChange={(e) => setNewFilePath(e.target.value)}
                      placeholder="e.g. Sources/FuzzCodeCore/Networking/OpenAIClient.swift"
                      className="w-full px-2.5 py-1.5 rounded-lg bg-[#0c0d12] border border-[#232736] text-white text-xs font-mono focus:outline-none focus:border-emerald-500"
                    />
                  </div>

                  <div>
                    <label className="text-[10px] font-mono text-slate-400 block mb-1">
                      KNOWLEDGE CONTENT
                    </label>
                    <textarea
                      value={newContent}
                      onChange={(e) => setNewContent(e.target.value)}
                      rows={5}
                      placeholder="Paste guidelines, design architecture rules, API signatures, or reference text..."
                      className="w-full p-2.5 rounded-lg bg-[#0c0d12] border border-[#232736] text-white font-mono text-xs focus:outline-none focus:border-emerald-500 resize-none"
                    />
                  </div>

                  <div className="flex justify-end gap-2">
                    <button
                      onClick={() => setIsAddingSource(false)}
                      className="px-3 py-1 text-slate-400 hover:text-white"
                    >
                      Cancel
                    </button>
                    <button
                      onClick={handleAddSource}
                      disabled={!newTitle.trim() || !newContent.trim()}
                      className="px-4 py-1.5 text-xs font-semibold text-black bg-emerald-400 rounded-lg hover:bg-emerald-300 disabled:opacity-50 cursor-pointer"
                    >
                      Index Source
                    </button>
                  </div>
                </div>
              )}

              {/* Source List */}
              <div className="space-y-2">
                {sources.map((source) => (
                  <div
                    key={source.id}
                    className={`p-3 rounded-xl border transition-all ${
                      source.isEnabled
                        ? 'bg-[#12141c] border-[#222736]'
                        : 'bg-[#0e0f15] border-[#181a24] opacity-60'
                    }`}
                  >
                    <div className="flex items-start justify-between gap-3">
                      <div className="flex items-start gap-2.5 flex-1 min-w-0">
                        <input
                          type="checkbox"
                          checked={source.isEnabled}
                          onChange={() => handleToggleSource(source.id)}
                          className="mt-1 accent-emerald-500 cursor-pointer"
                        />
                        <div className="flex-1 min-w-0">
                          <div className="flex items-center gap-2">
                            <span className="font-bold text-white truncate">
                              {source.title}
                            </span>
                            <span className="text-[9px] font-mono uppercase px-1.5 py-0.5 rounded bg-[#1c202d] text-emerald-400 border border-white/5">
                              {source.type}
                            </span>
                          </div>
                          {source.filePath && (
                            <div className="text-[10px] font-mono text-purple-400 truncate mt-0.5">
                              {source.filePath}
                            </div>
                          )}
                          <p className="text-[11px] text-slate-400 mt-1 line-clamp-2 leading-relaxed">
                            {source.content}
                          </p>
                          <div className="text-[10px] font-mono text-slate-500 mt-1">
                            ~{source.tokens} tokens · {source.chunksCount} chunk{source.chunksCount > 1 ? 's' : ''}
                          </div>
                        </div>
                      </div>

                      <button
                        onClick={() => handleDeleteSource(source.id)}
                        className="text-slate-500 hover:text-red-400 p-1 cursor-pointer transition-colors"
                      >
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* TAB 3: TEST RETRIEVAL SEARCH */}
          {activeTab === 'test_search' && (
            <div className="space-y-4">
              <p className="text-[11px] text-slate-400 leading-relaxed">
                Test how the RAG engine matches queries against your indexed knowledge base in real time.
              </p>

              <div className="flex gap-2">
                <input
                  type="text"
                  value={testQuery}
                  onChange={(e) => setTestQuery(e.target.value)}
                  onKeyDown={(e) => { if (e.key === 'Enter') handleRunTestSearch(); }}
                  placeholder="Ask a question (e.g. How to handle URL normalization?)..."
                  className="flex-1 px-3 py-2 rounded-xl bg-[#141620] border border-[#232736] text-white font-mono text-xs focus:outline-none focus:border-emerald-500"
                />
                <button
                  onClick={handleRunTestSearch}
                  disabled={!testQuery.trim()}
                  className="px-4 py-2 font-semibold text-black bg-emerald-400 hover:bg-emerald-300 rounded-xl transition-colors cursor-pointer disabled:opacity-50"
                >
                  Retrieve
                </button>
              </div>

              {testResults && (
                <div className="space-y-3 pt-2">
                  <div className="text-[11px] font-mono font-bold text-slate-300 uppercase tracking-wider">
                    Retrieved Chunks ({testResults.citations.length} hits)
                  </div>

                  {testResults.citations.length === 0 ? (
                    <div className="p-4 rounded-xl bg-[#12141c] border border-[#1f2330] text-center text-slate-500 font-mono">
                      No chunks surpassed the similarity threshold ({config.similarityThreshold}). Try lowering the threshold in RAG Tuning.
                    </div>
                  ) : (
                    testResults.citations.map((c, i) => (
                      <div
                        key={c.id || i}
                        className="p-3 rounded-xl bg-[#12141c] border border-emerald-500/30 space-y-1.5"
                      >
                        <div className="flex items-center justify-between text-xs">
                          <span className="font-bold text-white font-mono">
                            {c.sourceTitle}
                          </span>
                          <span className="font-mono text-emerald-400 font-bold text-[10px]">
                            {(c.score * 100).toFixed(0)}% MATCH
                          </span>
                        </div>
                        <p className="text-[11px] font-mono text-slate-300 leading-relaxed whitespace-pre-wrap bg-black/40 p-2 rounded border border-white/5">
                          {c.snippet}
                        </p>
                      </div>
                    ))
                  )}
                </div>
              )}
            </div>
          )}

          {/* TAB 4: RAG TUNING SETTINGS */}
          {activeTab === 'settings' && (
            <div className="space-y-4">
              <div className="p-3.5 rounded-xl bg-[#12141c] border border-[#1f2330] space-y-3">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="font-bold text-white">Top-K Chunks to Retrieve</div>
                    <div className="text-[11px] text-slate-400">Maximum chunks injected into model context</div>
                  </div>
                  <span className="font-mono font-bold text-emerald-400">{config.topK}</span>
                </div>
                <input
                  type="range"
                  min="1"
                  max="8"
                  value={config.topK}
                  onChange={(e) => setConfig({ ...config, topK: parseInt(e.target.value) })}
                  className="w-full accent-emerald-400"
                />
              </div>

              <div className="p-3.5 rounded-xl bg-[#12141c] border border-[#1f2330] space-y-3">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="font-bold text-white">Similarity Threshold</div>
                    <div className="text-[11px] text-slate-400">Minimum relevance score required for chunk inclusion</div>
                  </div>
                  <span className="font-mono font-bold text-emerald-400">
                    {(config.similarityThreshold * 100).toFixed(0)}%
                  </span>
                </div>
                <input
                  type="range"
                  min="0"
                  max="0.8"
                  step="0.05"
                  value={config.similarityThreshold}
                  onChange={(e) => setConfig({ ...config, similarityThreshold: parseFloat(e.target.value) })}
                  className="w-full accent-emerald-400"
                />
              </div>

              <div className="p-3.5 rounded-xl bg-[#12141c] border border-[#1f2330] space-y-3">
                <div className="flex items-center justify-between">
                  <div>
                    <div className="font-bold text-white">Max Context Tokens</div>
                    <div className="text-[11px] text-slate-400">Token budget ceiling reserved for knowledge injection</div>
                  </div>
                  <span className="font-mono font-bold text-emerald-400">{config.maxContextTokens}</span>
                </div>
                <input
                  type="range"
                  min="500"
                  max="4000"
                  step="250"
                  value={config.maxContextTokens}
                  onChange={(e) => setConfig({ ...config, maxContextTokens: parseInt(e.target.value) })}
                  className="w-full accent-emerald-400"
                />
              </div>
            </div>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-between px-5 py-3 border-t border-[#1d212d] bg-[#090a0f]">
          <span className="text-[11px] font-mono text-slate-500">
            {enabledCount} RAG sources active · {totalTokens} tokens
          </span>

          <div className="flex items-center gap-2">
            <button
              onClick={onClose}
              className="px-3 py-1.5 text-xs text-slate-400 hover:text-white cursor-pointer"
            >
              Cancel
            </button>
            <button
              onClick={handleSaveAndClose}
              className="px-4 py-1.5 text-xs font-bold text-black bg-emerald-400 hover:bg-emerald-300 rounded-lg transition-colors cursor-pointer shadow-sm shadow-emerald-500/20"
            >
              Apply Directives & RAG
            </button>
          </div>
        </div>
      </div>
    </div>
  );
};
