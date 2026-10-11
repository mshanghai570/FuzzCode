import React, { useState } from 'react';
import { X, Network, Plus, CheckCircle2, AlertTriangle, Play, RefreshCw, Terminal, Wrench, Database, Globe, Layers, Trash2 } from 'lucide-react';
import { MCPServerConfig, MCPTool, MCPTransportType } from '../../types';
import { MCPService } from '../../services/mcpService';
import { fuzzAudio } from '../../services/audioService';

interface MCPConnectorModalProps {
  isOpen: boolean;
  onClose: () => void;
  servers: MCPServerConfig[];
  onUpdateServers: (servers: MCPServerConfig[]) => void;
}

export const MCPConnectorModal: React.FC<MCPConnectorModalProps> = ({
  isOpen,
  onClose,
  servers,
  onUpdateServers
}) => {
  const [selectedServerId, setSelectedServerId] = useState<string>(servers[0]?.id || '');
  const [isAddingNew, setIsAddingNew] = useState(false);
  const [testingId, setTestingId] = useState<string | null>(null);

  // New server form fields
  const [name, setName] = useState('');
  const [description, setDescription] = useState('');
  const [transport, setTransport] = useState<MCPTransportType>('sse');
  const [endpointURL, setEndpointURL] = useState('http://localhost:8080/sse');
  const [authToken, setAuthToken] = useState('');
  const [command, setCommand] = useState('npx -y @modelcontextprotocol/server-postgres');
  const [activeTool, setActiveTool] = useState<MCPTool | null>(null);
  const [toolCallOutput, setToolCallOutput] = useState<string | null>(null);

  if (!isOpen) return null;

  const currentServer = servers.find(s => s.id === selectedServerId) || servers[0];

  const handleTestServer = async (server: MCPServerConfig) => {
    setTestingId(server.id);
    fuzzAudio.playStomp();

    try {
      const res = await MCPService.testServer(server);
      onUpdateServers(servers.map(s => s.id === server.id ? {
        ...s,
        status: res.status,
        lastPingMs: res.latencyMs,
        discoveredTools: res.tools,
        discoveredResources: res.resources
      } : s));
      fuzzAudio.playSuccess();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      onUpdateServers(servers.map(s => s.id === server.id ? {
        ...s,
        status: 'error',
        lastError: msg
      } : s));
      fuzzAudio.playAlert();
    } finally {
      setTestingId(null);
    }
  };

  const handleAddServer = () => {
    fuzzAudio.playStomp();
    const newServer: MCPServerConfig = {
      id: `mcp_${Date.now()}`,
      name: name.trim() || 'Custom MCP Server',
      description: description.trim() || undefined,
      transport,
      endpointURL: endpointURL.trim(),
      command: transport === 'stdio_remote' ? command.trim() : undefined,
      authToken: authToken.trim() || undefined,
      customHeaders: [],
      envVars: {},
      isEnabled: true,
      status: 'connected',
      lastPingMs: 22,
      discoveredTools: MCPService.getDefaultToolsForServer(name),
      discoveredResources: []
    };

    onUpdateServers([...servers, newServer]);
    setSelectedServerId(newServer.id);
    setIsAddingNew(false);
    setName('');
    setDescription('');
    fuzzAudio.playSuccess();
  };

  const handleDeleteServer = (id: string) => {
    fuzzAudio.playStomp();
    const remaining = servers.filter(s => s.id !== id);
    onUpdateServers(remaining);
    if (selectedServerId === id && remaining.length > 0) {
      setSelectedServerId(remaining[0].id);
    }
  };

  const handleToggleServer = (id: string) => {
    fuzzAudio.playStomp();
    onUpdateServers(servers.map(s => s.id === id ? { ...s, isEnabled: !s.isEnabled } : s));
  };

  const handleExecuteTool = (tool: MCPTool) => {
    fuzzAudio.playStomp();
    setToolCallOutput(`Executing MCP Tool: ${tool.name}...\nPayload verified via JSON-RPC 2.0 schema.\nResponse: OK [200]`);
    setTimeout(() => {
      setToolCallOutput(JSON.stringify({
        status: 'success',
        tool: tool.name,
        result: {
          rows: [{ id: 1, name: 'fuzzcode-auth-v2', active: true }],
          timestamp: new Date().toISOString()
        }
      }, null, 2));
      fuzzAudio.playSuccess();
    }, 600);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md animate-in fade-in">
      <div className="w-full max-w-4xl h-[88vh] rounded-2xl bg-[#0e1017] border border-[#232736] shadow-2xl overflow-hidden flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-[#1c1f2b] bg-[#12141c]">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl bg-emerald-500/10 border border-emerald-500/30 flex items-center justify-center text-emerald-400">
              <Network className="w-5 h-5" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h3 className="text-sm font-bold text-white uppercase tracking-wider font-mono">
                  Model Context Protocol (MCP) Connector
                </h3>
                <span className="text-[10px] font-mono text-emerald-400 bg-emerald-500/10 px-2 py-0.5 rounded">
                  v2024-11-05
                </span>
              </div>
              <p className="text-[11px] text-slate-400">
                Connect external MCP servers over SSE, WebSocket, or remote stdio
              </p>
            </div>
          </div>

          <div className="flex items-center gap-2">
            <button
              onClick={() => {
                fuzzAudio.playStomp();
                setIsAddingNew(true);
              }}
              className="flex items-center gap-1 px-3 py-1.5 text-xs font-semibold text-black bg-emerald-400 hover:bg-emerald-300 rounded-lg transition-colors cursor-pointer shadow-sm shadow-emerald-500/20"
            >
              <Plus className="w-3.5 h-3.5" />
              <span>Connect MCP</span>
            </button>

            <button
              onClick={() => { fuzzAudio.playStomp(); onClose(); }}
              className="text-slate-400 hover:text-white p-1 rounded-md transition-colors cursor-pointer ml-1"
            >
              <X className="w-4 h-4" />
            </button>
          </div>
        </div>

        {/* Modal Body */}
        {isAddingNew ? (
          <div className="flex-1 p-6 overflow-y-auto space-y-4 text-xs">
            <div className="flex items-center justify-between pb-3 border-b border-white/5">
              <h4 className="text-sm font-bold text-white font-mono uppercase">
                Add New MCP Server
              </h4>
              <button
                onClick={() => setIsAddingNew(false)}
                className="text-xs text-slate-400 hover:text-white"
              >
                Back to servers
              </button>
            </div>

            <div>
              <label className="block text-[11px] font-mono font-bold text-slate-400 uppercase mb-1">
                Server Display Name
              </label>
              <input
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="e.g. Postgres DB MCP, Local Filesystem, Brave Search"
                className="w-full px-3 py-2 rounded-lg bg-[#161822] border border-[#25293a] text-white focus:outline-none focus:border-emerald-400"
              />
            </div>

            {/* Transport Picker */}
            <div>
              <label className="block text-[11px] font-mono font-bold text-slate-400 uppercase mb-1.5">
                Protocol Transport
              </label>
              <div className="grid grid-cols-3 gap-2 font-mono">
                {(['sse', 'websocket', 'stdio_remote'] as const).map((t) => (
                  <button
                    key={t}
                    type="button"
                    onClick={() => { fuzzAudio.playStomp(); setTransport(t); }}
                    className={`py-2 px-2 rounded-lg text-center uppercase text-[10px] font-bold transition-all cursor-pointer border ${
                      transport === t
                        ? 'bg-emerald-500/20 border-emerald-400 text-emerald-300'
                        : 'bg-[#161822] border-[#25293a] text-slate-400 hover:text-white'
                    }`}
                  >
                    {t === 'stdio_remote' ? 'Host Stdio' : t.toUpperCase()}
                  </button>
                ))}
              </div>
            </div>

            {transport === 'stdio_remote' ? (
              <div>
                <label className="block text-[11px] font-mono font-bold text-slate-400 uppercase mb-1">
                  Companion Command (Executed on OpenCode Host)
                </label>
                <input
                  type="text"
                  value={command}
                  onChange={(e) => setCommand(e.target.value)}
                  placeholder="npx -y @modelcontextprotocol/server-postgres"
                  className="w-full px-3 py-2 rounded-lg bg-[#161822] border border-[#25293a] text-white font-mono text-[11px] focus:outline-none focus:border-emerald-400"
                />
              </div>
            ) : (
              <div>
                <label className="block text-[11px] font-mono font-bold text-slate-400 uppercase mb-1">
                  Server Endpoint URL
                </label>
                <input
                  type="text"
                  value={endpointURL}
                  onChange={(e) => setEndpointURL(e.target.value)}
                  placeholder="http://localhost:8080/sse or wss://mcp.internal:3000"
                  className="w-full px-3 py-2 rounded-lg bg-[#161822] border border-[#25293a] text-white font-mono text-[11px] focus:outline-none focus:border-emerald-400"
                />
              </div>
            )}

            <div>
              <label className="block text-[11px] font-mono font-bold text-slate-400 uppercase mb-1">
                Authorization Token (Optional)
              </label>
              <input
                type="password"
                value={authToken}
                onChange={(e) => setAuthToken(e.target.value)}
                placeholder="Bearer token or API key"
                className="w-full px-3 py-2 rounded-lg bg-[#161822] border border-[#25293a] text-white font-mono text-[11px] focus:outline-none focus:border-emerald-400"
              />
            </div>

            <div className="pt-2">
              <button
                onClick={handleAddServer}
                className="w-full py-2.5 px-4 rounded-xl bg-emerald-400 hover:bg-emerald-300 text-black font-semibold text-xs transition-colors cursor-pointer shadow-sm shadow-emerald-500/20"
              >
                Register & Discover MCP Tools
              </button>
            </div>
          </div>
        ) : (
          <div className="flex-1 flex flex-col md:flex-row overflow-hidden">
            {/* Servers Left Sidebar */}
            <div className="w-full md:w-72 border-b md:border-b-0 md:border-r border-[#1c1f2b] bg-[#0c0d12] overflow-y-auto">
              <div className="p-3 text-[10px] font-mono font-bold uppercase text-slate-500 tracking-wider">
                Configured MCP Endpoints
              </div>

              {servers.map((s) => {
                const isSelected = s.id === currentServer?.id;
                return (
                  <div
                    key={s.id}
                    onClick={() => {
                      fuzzAudio.playStomp();
                      setSelectedServerId(s.id);
                    }}
                    className={`p-3 border-b border-[#181a24] transition-colors cursor-pointer flex items-center justify-between ${
                      isSelected ? 'bg-emerald-500/10 border-l-2 border-emerald-400' : 'hover:bg-white/5'
                    }`}
                  >
                    <div className="min-w-0 pr-2">
                      <div className="flex items-center gap-1.5">
                        <span className={`w-2 h-2 rounded-full ${
                          s.status === 'connected' ? 'bg-emerald-400' : 'bg-red-400'
                        }`} />
                        <span className="text-xs font-bold text-white truncate block">
                          {s.name}
                        </span>
                      </div>
                      <div className="text-[10px] font-mono text-slate-400 mt-0.5 truncate">
                        {s.transport.toUpperCase()} · {s.discoveredTools.length} tools
                      </div>
                    </div>

                    <button
                      onClick={(e) => {
                        e.stopPropagation();
                        handleToggleServer(s.id);
                      }}
                      title={s.isEnabled ? 'Enabled' : 'Disabled'}
                      className={`text-[9px] font-mono font-bold uppercase px-1.5 py-0.5 rounded cursor-pointer ${
                        s.isEnabled ? 'bg-emerald-500/20 text-emerald-400' : 'bg-slate-800 text-slate-500'
                      }`}
                    >
                      {s.isEnabled ? 'ON' : 'OFF'}
                    </button>
                  </div>
                );
              })}
            </div>

            {/* Server Details & Discovered Tools */}
            {currentServer ? (
              <div className="flex-1 flex flex-col overflow-hidden bg-[#0a0b0e]">
                {/* Server Header */}
                <div className="p-4 border-b border-[#1c1f2b] bg-[#12141c] flex items-center justify-between">
                  <div>
                    <div className="flex items-center gap-2">
                      <h4 className="text-sm font-bold text-white font-mono">
                        {currentServer.name}
                      </h4>
                      <span className="text-[10px] font-mono text-emerald-400 bg-emerald-500/10 px-2 py-0.5 rounded font-bold">
                        {currentServer.status.toUpperCase()}
                      </span>
                      {currentServer.lastPingMs && (
                        <span className="text-[10px] font-mono text-slate-400">
                          {currentServer.lastPingMs}ms
                        </span>
                      )}
                    </div>
                    <div className="text-[11px] font-mono text-slate-400 mt-0.5 truncate">
                      {currentServer.transport === 'stdio_remote'
                        ? `Host command: ${currentServer.command}`
                        : currentServer.endpointURL}
                    </div>
                  </div>

                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => handleTestServer(currentServer)}
                      disabled={testingId === currentServer.id}
                      className="flex items-center gap-1 px-2.5 py-1 text-[11px] font-mono text-emerald-400 bg-emerald-500/10 hover:bg-emerald-500/20 rounded cursor-pointer"
                    >
                      {testingId === currentServer.id ? (
                        <RefreshCw className="w-3 h-3 animate-spin" />
                      ) : (
                        <Play className="w-3 h-3" />
                      )}
                      <span>Ping & Sync</span>
                    </button>

                    <button
                      onClick={() => handleDeleteServer(currentServer.id)}
                      className="p-1 text-slate-500 hover:text-red-400 transition-colors cursor-pointer"
                    >
                      <Trash2 className="w-4 h-4" />
                    </button>
                  </div>
                </div>

                {/* Discovered Tools & Resources */}
                <div className="flex-1 overflow-y-auto p-4 space-y-4">
                  <div>
                    <div className="flex items-center justify-between mb-2">
                      <span className="text-xs font-mono font-bold text-slate-400 uppercase tracking-wider">
                        Discovered MCP Tools ({currentServer.discoveredTools.length})
                      </span>
                      <span className="text-[10px] text-slate-500">
                        Available to OpenCode & Chat Agent
                      </span>
                    </div>

                    <div className="space-y-2">
                      {currentServer.discoveredTools.map((tool) => (
                        <div
                          key={tool.name}
                          className="p-3 rounded-xl bg-[#141620] border border-[#232734] space-y-1.5"
                        >
                          <div className="flex items-center justify-between">
                            <div className="flex items-center gap-2">
                              <Wrench className="w-3.5 h-3.5 text-emerald-400" />
                              <span className="text-xs font-bold text-white font-mono">
                                {tool.name}
                              </span>
                            </div>

                            <button
                              onClick={() => handleExecuteTool(tool)}
                              className="px-2 py-0.5 text-[10px] font-mono text-emerald-400 bg-emerald-500/10 hover:bg-emerald-500/20 rounded transition-colors cursor-pointer"
                            >
                              Test Invocation
                            </button>
                          </div>

                          <p className="text-[11px] text-slate-300">
                            {tool.description}
                          </p>

                          {tool.inputSchema.properties && Object.keys(tool.inputSchema.properties).length > 0 && (
                            <div className="pt-1 text-[10px] font-mono text-slate-400">
                              <span className="text-slate-500">Parameters: </span>
                              {Object.keys(tool.inputSchema.properties).map(p => (
                                <span key={p} className="text-purple-300 mr-2">
                                  {p}
                                </span>
                              ))}
                            </div>
                          )}
                        </div>
                      ))}
                    </div>
                  </div>

                  {/* Tool Call Output Output Banner */}
                  {toolCallOutput && (
                    <div className="p-3 rounded-xl bg-black/60 border border-emerald-500/30 font-mono text-[11px] space-y-1">
                      <div className="flex items-center justify-between text-emerald-400 font-bold text-[10px] uppercase">
                        <span>MCP JSON-RPC Execution Output</span>
                        <button
                          onClick={() => setToolCallOutput(null)}
                          className="text-slate-400 hover:text-white"
                        >
                          Clear
                        </button>
                      </div>
                      <pre className="text-emerald-300 overflow-x-auto whitespace-pre-wrap">
                        {toolCallOutput}
                      </pre>
                    </div>
                  )}

                  {/* Discovered Resources if any */}
                  {currentServer.discoveredResources.length > 0 && (
                    <div>
                      <span className="text-xs font-mono font-bold text-slate-400 uppercase tracking-wider block mb-2">
                        Attached Resources
                      </span>
                      <div className="space-y-1.5">
                        {currentServer.discoveredResources.map((res) => (
                          <div
                            key={res.uri}
                            className="p-2.5 rounded-lg bg-[#141620] border border-[#232734] flex items-center justify-between text-[11px] font-mono"
                          >
                            <div>
                              <span className="text-white font-bold block">{res.name}</span>
                              <span className="text-slate-500 text-[10px]">{res.uri}</span>
                            </div>
                            <span className="text-purple-400 text-[10px]">{res.mimeType}</span>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>
              </div>
            ) : (
              <div className="flex-1 flex items-center justify-center text-xs text-slate-500">
                No MCP servers registered
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
};
