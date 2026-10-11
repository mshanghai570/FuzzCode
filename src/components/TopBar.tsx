import React from 'react';
import { Download, Volume2, VolumeX, Smartphone, Monitor } from 'lucide-react';
import { fuzzAudio } from '../services/audioService';
import { downloadSwiftProjectZip } from '../services/exportService';

interface TopBarProps {
  viewMode: 'phone' | 'wide';
  setViewMode: (mode: 'phone' | 'wide') => void;
  soundEnabled: boolean;
  setSoundEnabled: (enabled: boolean) => void;
  activeTab: string;
  setActiveTab: (tab: string) => void;
  onOpenGitHub: () => void;
  onOpenMCP: () => void;
  isGitHubConnected: boolean;
  activeMCPCount: number;
}

export const TopBar: React.FC<TopBarProps> = ({
  viewMode,
  setViewMode,
  soundEnabled,
  setSoundEnabled,
  activeTab,
  setActiveTab,
  onOpenGitHub,
  onOpenMCP,
  isGitHubConnected,
  activeMCPCount
}) => {
  const toggleSound = () => {
    const next = !soundEnabled;
    fuzzAudio.soundEnabled = next;
    setSoundEnabled(next);
    if (next) fuzzAudio.playStomp();
  };

  const handleExport = async () => {
    fuzzAudio.playStomp();
    await downloadSwiftProjectZip();
  };

  return (
    <header className="flex items-center justify-between gap-6 px-6 py-3.5 border-b border-[#1f232e] bg-[#0b0c0f] text-slate-200">
      {/* Zone 1: Single text element wordmark */}
      <div className="flex items-center gap-3">
        <button
          onClick={() => {
            fuzzAudio.playStomp();
            setActiveTab('home');
          }}
          className="text-left group cursor-pointer"
        >
          <span className="text-lg font-extrabold tracking-tight text-white whitespace-nowrap shrink-0 group-hover:text-emerald-400 transition-colors">
            FUZZCODE
          </span>
        </button>
      </div>

      {/* Zone 2: 4–5 clean single-line navigation links + Connector Badges */}
      <nav className="hidden md:flex items-center gap-5 text-sm font-medium text-slate-400">
        <button
          onClick={() => { fuzzAudio.playStomp(); setActiveTab('home'); }}
          className={`hover:text-white transition-colors whitespace-nowrap shrink-0 cursor-pointer ${activeTab === 'home' ? 'text-emerald-400' : ''}`}
        >
          Overview
        </button>
        <button
          onClick={() => { fuzzAudio.playStomp(); setActiveTab('chat'); }}
          className={`hover:text-white transition-colors whitespace-nowrap shrink-0 cursor-pointer ${activeTab === 'chat' ? 'text-emerald-400' : ''}`}
        >
          Model Chat
        </button>
        <button
          onClick={() => { fuzzAudio.playStomp(); setActiveTab('agents'); }}
          className={`hover:text-white transition-colors whitespace-nowrap shrink-0 cursor-pointer ${activeTab === 'agents' ? 'text-emerald-400' : ''}`}
        >
          OpenCode Agent
        </button>
        <button
          onClick={() => { fuzzAudio.playStomp(); setActiveTab('providers'); }}
          className={`hover:text-white transition-colors whitespace-nowrap shrink-0 cursor-pointer ${activeTab === 'providers' ? 'text-emerald-400' : ''}`}
        >
          Endpoints
        </button>
        <button
          onClick={() => { fuzzAudio.playStomp(); setActiveTab('swift'); }}
          className={`hover:text-white transition-colors whitespace-nowrap shrink-0 cursor-pointer ${activeTab === 'swift' ? 'text-emerald-400' : ''}`}
        >
          Swift Source
        </button>
      </nav>

      {/* Zone 3: Connectors & Primary action controls */}
      <div className="flex items-center gap-2.5 shrink-0">
        {/* GitHub Connector Button */}
        <button
          onClick={() => {
            fuzzAudio.playStomp();
            onOpenGitHub();
          }}
          title="GitHub Connector"
          className={`flex items-center gap-1.5 px-2.5 py-1 text-xs font-semibold rounded-lg border transition-all cursor-pointer ${
            isGitHubConnected
              ? 'bg-purple-500/15 border-purple-500/40 text-purple-300'
              : 'bg-[#151720] border-[#232734] text-slate-400 hover:text-white'
          }`}
        >
          <span className="w-1.5 h-1.5 rounded-full bg-purple-400" />
          <span>GitHub</span>
        </button>

        {/* MCP Connector Button */}
        <button
          onClick={() => {
            fuzzAudio.playStomp();
            onOpenMCP();
          }}
          title="Model Context Protocol (MCP) Connector"
          className="flex items-center gap-1.5 px-2.5 py-1 text-xs font-semibold rounded-lg border bg-emerald-500/15 border-emerald-500/30 text-emerald-300 hover:bg-emerald-500/25 transition-all cursor-pointer"
        >
          <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" />
          <span>MCP ({activeMCPCount})</span>
        </button>

        {/* Device Frame Viewport Toggle */}
        <div className="flex items-center bg-[#151720] border border-[#232734] rounded-lg p-0.5 ml-1">
          <button
            onClick={() => { fuzzAudio.playStomp(); setViewMode('phone'); }}
            title="iPhone 16 Pro Simulator"
            className={`p-1.5 rounded-md transition-colors cursor-pointer ${
              viewMode === 'phone' ? 'bg-[#252a3a] text-emerald-400' : 'text-slate-400 hover:text-white'
            }`}
          >
            <Smartphone className="w-4 h-4" />
          </button>
          <button
            onClick={() => { fuzzAudio.playStomp(); setViewMode('wide'); }}
            title="Workstation Expanded View"
            className={`p-1.5 rounded-md transition-colors cursor-pointer ${
              viewMode === 'wide' ? 'bg-[#252a3a] text-emerald-400' : 'text-slate-400 hover:text-white'
            }`}
          >
            <Monitor className="w-4 h-4" />
          </button>
        </div>

        {/* Fuzz Stomp Sound Effect Toggle */}
        <button
          onClick={toggleSound}
          title={soundEnabled ? 'Fuzz Pedal Audio: On' : 'Fuzz Pedal Audio: Muted'}
          className={`p-2 rounded-lg border border-[#232734] bg-[#151720] transition-colors cursor-pointer ${
            soundEnabled ? 'text-emerald-400' : 'text-slate-500 hover:text-slate-400'
          }`}
        >
          {soundEnabled ? <Volume2 className="w-4 h-4" /> : <VolumeX className="w-4 h-4" />}
        </button>

        {/* Primary CTA: Export Native Swift Project */}
        <button
          onClick={handleExport}
          className="flex items-center gap-2 px-3.5 py-1.5 text-xs font-semibold text-black bg-emerald-400 hover:bg-emerald-300 rounded-lg shadow-sm shadow-emerald-500/20 transition-all cursor-pointer whitespace-nowrap shrink-0 active:scale-95"
        >
          <Download className="w-3.5 h-3.5" />
          <span>Export Swift (.zip)</span>
        </button>
      </div>
    </header>
  );
};
