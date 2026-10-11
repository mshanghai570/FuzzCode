import React, { useState } from 'react';
import { TopBar } from './components/TopBar';
import { PhoneFrame } from './components/PhoneFrame';
import { HomeTab } from './components/tabs/HomeTab';
import { ChatTab } from './components/tabs/ChatTab';
import { AgentsTab } from './components/tabs/AgentsTab';
import { ProvidersTab } from './components/tabs/ProvidersTab';
import { SettingsTab } from './components/tabs/SettingsTab';
import { SwiftSourceTab } from './components/tabs/SwiftSourceTab';
import { EndpointModal } from './components/modals/EndpointModal';
import { ChatGPTLoginModal } from './components/modals/ChatGPTLoginModal';
import { PairHostModal } from './components/modals/PairHostModal';
import { PermissionModal } from './components/modals/PermissionModal';
import { DiffModal } from './components/modals/DiffModal';
import { GitHubConnectorModal } from './components/modals/GitHubConnectorModal';
import { MCPConnectorModal } from './components/modals/MCPConnectorModal';
import { RAGPromptModal } from './components/modals/RAGPromptModal';
import {
  ProviderConfig,
  OpenCodeHostConfig,
  ChatConversation,
  AgentSession,
  PermissionRequest,
  GitHubConfig,
  GitHubRepo,
  MCPServerConfig,
  RAGConfig,
  RAGSource
} from './types';
import { OpenCodeService } from './services/openCodeService';
import { RAGService } from './services/ragService';
import { fuzzAudio } from './services/audioService';

export default function App() {
  const [viewMode, setViewMode] = useState<'phone' | 'wide'>('phone');
  const [activeTab, setActiveTab] = useState<string>('home');
  const [soundEnabled, setSoundEnabled] = useState<boolean>(true);

  // Initial Seed Providers
  const [providers, setProviders] = useState<ProviderConfig[]>([
    {
      id: 'prov_kilo_default',
      displayName: 'Kilo / OpenAI Compatible',
      baseURLString: 'https://api.openai.com/v1',
      selectedModel: 'gpt-4o',
      apiKey: '',
      customHeaders: [],
      timeoutSeconds: 30,
      isEnabled: true,
      allowsInsecureHTTP: false,
      createdAt: new Date().toISOString()
    },
    {
      id: 'prov_groq',
      displayName: 'Groq Cloud Engine',
      baseURLString: 'https://api.groq.com/openai/v1',
      selectedModel: 'llama-3.3-70b-versatile',
      apiKey: '',
      customHeaders: [],
      timeoutSeconds: 15,
      isEnabled: true,
      allowsInsecureHTTP: false,
      createdAt: new Date().toISOString()
    },
    {
      id: 'prov_ollama_local',
      displayName: 'Ollama Local (LAN)',
      baseURLString: 'http://192.168.1.50:11434/v1',
      selectedModel: 'qwen2.5-coder:7b',
      apiKey: '',
      customHeaders: [],
      timeoutSeconds: 45,
      isEnabled: false,
      allowsInsecureHTTP: true,
      createdAt: new Date().toISOString()
    }
  ]);

  // Initial Seed OpenCode Hosts
  const [hosts, setHosts] = useState<OpenCodeHostConfig[]>([
    {
      id: 'host_macbook_pro',
      displayName: 'MacBook Pro M3 Max (OpenCode)',
      hostURLString: 'http://192.168.1.150:4096',
      authToken: 'fuzz_auth_token_99x',
      isConnected: true,
      agentVersion: 'v0.14.2',
      currentWorkspace: '/Users/developer/Projects/FuzzCode',
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
    }
  ]);

  // Initial Seed Conversations with Prompt & RAG
  const [conversations, setConversations] = useState<ChatConversation[]>([
    {
      id: 'conv_1',
      title: 'Swift Actor Networking Architecture',
      providerId: 'prov_kilo_default',
      modelId: 'gpt-4o',
      updatedAt: new Date().toISOString(),
      systemPrompt: RAGService.getPromptTemplates()[0].content,
      ragConfig: RAGService.getDefaultRAGConfig(),
      ragSources: RAGService.getDefaultChatRAGSources(),
      messages: [
        {
          id: 'm1',
          role: 'user',
          content: 'How does FuzzCode isolate model providers from agent hosts?',
          timestamp: new Date().toISOString()
        },
        {
          id: 'm2',
          role: 'assistant',
          content: 'FuzzCode enforces a strict tripartite model-agent-host protocol hierarchy:\n\n1. **ModelProviderProtocol**: Manages direct token completions (`streamChatCompletion`).\n2. **CodingAgentProtocol**: Manages development loops, tool executions, and interactive permission gates.\n3. **ExecutionHostProtocol**: Manages authenticated network pairing without executing raw binaries on the iPhone.\n\nAll API keys and credentials are stored strictly in the iOS Keychain.',
          timestamp: new Date().toISOString(),
          retrievedCitations: [
            {
              id: 'c1',
              sourceTitle: 'FuzzCode Tripartite Architecture Spec',
              sourceType: 'doc',
              snippet: 'Separates Model Providers, Coding Agents, and Execution Hosts into independent protocols.',
              score: 0.94
            }
          ]
        }
      ]
    }
  ]);
  const [currentConversationId, setCurrentConversationId] = useState<string>('conv_1');

  // Initial Seed Agent Sessions with Project Prompt & RAG
  const [sessions, setSessions] = useState<AgentSession[]>([
    {
      id: 'session_auth_refactor',
      hostId: 'host_macbook_pro',
      title: 'Refactor URL Normalization & Add Tests',
      workspacePath: '/Users/developer/Projects/FuzzCode',
      status: 'waiting_permission',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      systemPrompt: RAGService.getPromptTemplates()[1].content,
      ragConfig: RAGService.getDefaultRAGConfig(),
      ragSources: RAGService.getDefaultProjectRAGSources(),
      pendingPermission: {
        id: 'perm_101',
        toolName: 'execute_bash',
        commandOrPath: 'swift test --filter EndpointNormalizationTests',
        fullParameters: {
          cwd: '/Users/developer/Projects/FuzzCode',
          shell: '/bin/zsh'
        },
        riskLevel: 'medium',
        requestedAt: new Date().toISOString()
      },
      messages: [
        {
          id: 'smsg_1',
          role: 'user',
          content: 'Audit OpenAI client URL resolution to ensure we never duplicate /v1.',
          timestamp: new Date().toISOString(),
          toolEvents: []
        },
        {
          id: 'smsg_2',
          role: 'assistant',
          content: 'Inspected `OpenAIClient.swift`. Replaced substring concatenation with path-suffix guard checks. Grounded against project RAG URL normalization specification. Requesting authorization to execute test suite.',
          timestamp: new Date().toISOString(),
          retrievedCitations: [
            {
              id: 'rc_1',
              sourceTitle: 'OpenAI URL Normalization Rules',
              sourceType: 'guideline',
              snippet: 'Never double append /v1 to base URL.',
              score: 0.98
            }
          ],
          toolEvents: [
            {
              id: 'tool_rag_init',
              toolName: 'rag_knowledge_retrieval',
              argumentsJSON: '{"query":"URL normalization guidelines","top_k":3}',
              outputSnippet: 'Retrieved 2 specs: OpenAI URL Normalization Rules, Tripartite Architecture Spec',
              status: 'success',
              startedAt: new Date().toISOString(),
              completedAt: new Date().toISOString()
            },
            {
              id: 'tool_rg_1',
              toolName: 'ripgrep',
              argumentsJSON: '{"pattern":"chat/completions"}',
              outputSnippet: 'Found 3 references across networking modules.',
              status: 'success',
              startedAt: new Date().toISOString(),
              completedAt: new Date().toISOString()
            },
            {
              id: 'tool_edit_1',
              toolName: 'file_edit',
              argumentsJSON: '{"file":"Sources/FuzzCodeCore/Networking/OpenAIClient.swift"}',
              outputSnippet: 'Replaced lines 48-62 with verified normalization.',
              status: 'success',
              startedAt: new Date().toISOString(),
              completedAt: new Date().toISOString()
            }
          ]
        }
      ]
    }
  ]);

  // GitHub Connector State
  const [githubConfig, setGithubConfig] = useState<GitHubConfig>({
    isConnected: false,
    scopes: ['repo', 'workflow']
  });
  const [isGitHubModalOpen, setIsGitHubModalOpen] = useState(false);

  // MCP Servers State
  const [mcpServers, setMcpServers] = useState<MCPServerConfig[]>([
    {
      id: 'mcp_postgres',
      name: 'PostgreSQL MCP Server',
      description: 'Database schema introspection and read-only querying',
      transport: 'sse',
      endpointURL: 'http://localhost:8080/sse',
      customHeaders: [],
      envVars: {},
      isEnabled: true,
      status: 'connected',
      lastPingMs: 19,
      discoveredTools: [
        {
          name: 'query',
          description: 'Execute a read-only SQL query against the Postgres database',
          inputSchema: {
            type: 'object',
            properties: {
              sql: { type: 'string', description: 'SQL query statement' }
            },
            required: ['sql']
          }
        },
        {
          name: 'list_tables',
          description: 'List all public schemas and database tables',
          inputSchema: { type: 'object' }
        }
      ],
      discoveredResources: []
    },
    {
      id: 'mcp_fs',
      name: 'Filesystem MCP Server',
      description: 'Local workspace file indexing and AST analysis',
      transport: 'stdio_remote',
      endpointURL: 'http://localhost:8081/sse',
      command: 'npx -y @modelcontextprotocol/server-filesystem /Users/developer/Projects',
      customHeaders: [],
      envVars: {},
      isEnabled: true,
      status: 'connected',
      lastPingMs: 14,
      discoveredTools: [
        {
          name: 'read_file',
          description: 'Read the complete contents of a file',
          inputSchema: {
            type: 'object',
            properties: { path: { type: 'string' } },
            required: ['path']
          }
        },
        {
          name: 'list_directory',
          description: 'List directory entries with metadata',
          inputSchema: {
            type: 'object',
            properties: { path: { type: 'string' } },
            required: ['path']
          }
        }
      ],
      discoveredResources: []
    }
  ]);
  const [isMCPModalOpen, setIsMCPModalOpen] = useState(false);

  // RAG Prompt Modal State
  const [isRAGModalOpen, setIsRAGModalOpen] = useState(false);
  const [ragScope, setRagScope] = useState<{
    type: 'chat' | 'project';
    id: string;
    title: string;
  }>({
    type: 'chat',
    id: 'conv_1',
    title: 'Chat: Swift Actor Networking Architecture'
  });

  // Modal State
  const [isEndpointModalOpen, setIsEndpointModalOpen] = useState(false);
  const [editingProvider, setEditingProvider] = useState<ProviderConfig | undefined>(undefined);
  const [isChatGPTModalOpen, setIsChatGPTModalOpen] = useState(false);
  const [isPairModalOpen, setIsPairModalOpen] = useState(false);
  const [isPermissionModalOpen, setIsPermissionModalOpen] = useState(false);
  const [activePermission, setActivePermission] = useState<PermissionRequest | null>(null);
  const [activePermissionSessionId, setActivePermissionSessionId] = useState<string>('');
  const [isDiffModalOpen, setIsDiffModalOpen] = useState(false);

  const gitSummary = OpenCodeService.getSampleGitStatus();

  const handleOpenEndpointModal = (provider?: ProviderConfig) => {
    setEditingProvider(provider);
    setIsEndpointModalOpen(true);
  };

  const handleSaveEndpoint = (config: ProviderConfig) => {
    setProviders(prev => {
      const idx = prev.findIndex(p => p.id === config.id);
      if (idx !== -1) {
        const copy = [...prev];
        copy[idx] = config;
        return copy;
      }
      return [...prev, config];
    });
  };

  const handleChatGPTLoginSuccess = (codexProvider: ProviderConfig, linkToOpenCode: boolean) => {
    // Add or update Codex provider
    setProviders(prev => [codexProvider, ...prev.map(p => ({ ...p, isEnabled: false }))]);
    
    // Link to OpenCode host if requested
    if (linkToOpenCode) {
      setHosts(prev => prev.map(h => ({
        ...h,
        useChatGPTSubscriptionForCodex: true,
        chatgptAccountEmail: codexProvider.chatgptSession?.accountEmail
      })));
    }

    // Automatically create a Codex chat conversation
    const codexChat: ChatConversation = {
      id: `conv_codex_${Date.now()}`,
      title: 'Codex Architecture Session',
      providerId: codexProvider.id,
      modelId: codexProvider.selectedModel,
      updatedAt: new Date().toISOString(),
      systemPrompt: RAGService.getPromptTemplates()[0].content,
      ragConfig: RAGService.getDefaultRAGConfig(),
      ragSources: RAGService.getDefaultChatRAGSources(),
      messages: [
        {
          id: `m_codex_init`,
          role: 'assistant',
          content: `🔐 Authenticated via **ChatGPT ${codexProvider.chatgptSession?.subscriptionTier.toUpperCase()}** (\`${codexProvider.chatgptSession?.accountEmail}\`).\n\nCodex coding engine is activated for both AI chat and OpenCode autonomous agent workflows with dedicated Prompt & RAG grounding. You can issue instructions with zero API token costs.`,
          timestamp: new Date().toISOString()
        }
      ]
    };
    setConversations(prev => [codexChat, ...prev]);
    setCurrentConversationId(codexChat.id);
  };

  const handleLoadRepoIntoAgent = (repo: GitHubRepo) => {
    setActiveTab('agents');
    const newSession: AgentSession = {
      id: `session_gh_${Date.now()}`,
      hostId: hosts[0]?.id || '',
      title: `GitHub: ${repo.fullName}`,
      workspacePath: `/workspace/${repo.name}`,
      status: 'idle',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      systemPrompt: `You are an autonomous OpenCode agent operating on repository ${repo.fullName}.\nBranch: ${repo.defaultBranch}.\nEnforce strict test verification before proposing changes.`,
      ragConfig: RAGService.getDefaultRAGConfig(),
      ragSources: [
        {
          id: `rag_repo_${repo.id}`,
          title: `Repo Spec: ${repo.fullName}`,
          type: 'doc',
          content: `Repository ${repo.fullName}: ${repo.description || 'Active code repository.'}\nDefault branch: ${repo.defaultBranch}\nOpen issues: ${repo.openIssuesCount}.`,
          tokens: 75,
          chunksCount: 1,
          isEnabled: true,
          addedAt: new Date().toISOString()
        },
        ...RAGService.getDefaultProjectRAGSources()
      ],
      messages: [
        {
          id: `msg_gh_${Date.now()}`,
          role: 'assistant',
          content: `Connected to GitHub repository **${repo.fullName}** on branch \`${repo.defaultBranch}\`.\n\nOpenCode agent workspace initialized at \`/workspace/${repo.name}\`. RAG knowledge base loaded with repository specifications. Ready to execute directives.`,
          timestamp: new Date().toISOString(),
          toolEvents: []
        }
      ]
    };
    setSessions(prev => [newSession, ...prev]);
  };

  const handleInspectPermission = (perm: PermissionRequest, sessionId: string) => {
    setActivePermission(perm);
    setActivePermissionSessionId(sessionId);
    setIsPermissionModalOpen(true);
  };

  const handlePermissionDecision = (decision: 'allow_once' | 'allow_always' | 'deny') => {
    setSessions(prev => prev.map(s => {
      if (s.id === activePermissionSessionId) {
        return {
          ...s,
          pendingPermission: undefined,
          status: decision === 'deny' ? 'idle' : 'completed',
          messages: [
            ...s.messages,
            {
              id: `msg_perm_res_${Date.now()}`,
              role: 'assistant',
              content: decision === 'deny'
                ? 'Developer denied command execution. Task aborted safely.'
                : 'Execution approved. Running `swift test`:\n\n```\nTest Suite \'EndpointNormalizationTests\' passed at 0.042s (8 tests, 0 failures).\n```\nTask completed successfully.',
              timestamp: new Date().toISOString(),
              toolEvents: decision === 'deny' ? [] : [
                {
                  id: `tool_exec_${Date.now()}`,
                  toolName: 'execute_bash',
                  argumentsJSON: JSON.stringify({ command: 'swift test' }),
                  outputSnippet: 'Tests passed 8/8 clean.',
                  status: 'success',
                  startedAt: new Date().toISOString(),
                  completedAt: new Date().toISOString()
                }
              ]
            }
          ]
        };
      }
      return s;
    }));
  };

  // Open RAG & Prompt configuration for Chat
  const handleOpenChatRAG = () => {
    const conv = conversations.find(c => c.id === currentConversationId) || conversations[0];
    setRagScope({
      type: 'chat',
      id: conv.id,
      title: `Chat: ${conv.title}`
    });
    setIsRAGModalOpen(true);
  };

  // Open RAG & Prompt configuration for Agent Project
  const handleOpenProjectRAG = (session: AgentSession) => {
    setRagScope({
      type: 'project',
      id: session.id,
      title: `Project: ${session.title}`
    });
    setIsRAGModalOpen(true);
  };

  const handleSaveRAGPrompt = (prompt: string) => {
    if (ragScope.type === 'chat') {
      setConversations(prev => prev.map(c => c.id === ragScope.id ? { ...c, systemPrompt: prompt } : c));
    } else {
      setSessions(prev => prev.map(s => s.id === ragScope.id ? { ...s, systemPrompt: prompt } : s));
    }
  };

  const handleSaveRAGConfig = (config: RAGConfig) => {
    if (ragScope.type === 'chat') {
      setConversations(prev => prev.map(c => c.id === ragScope.id ? { ...c, ragConfig: config } : c));
    } else {
      setSessions(prev => prev.map(s => s.id === ragScope.id ? { ...s, ragConfig: config } : s));
    }
  };

  const handleSaveRAGSources = (sources: RAGSource[]) => {
    if (ragScope.type === 'chat') {
      setConversations(prev => prev.map(c => c.id === ragScope.id ? { ...c, ragSources: sources } : c));
    } else {
      setSessions(prev => prev.map(s => s.id === ragScope.id ? { ...s, ragSources: sources } : s));
    }
  };

  // Resolve currently scoped RAG parameters
  const currentScopedChat = conversations.find(c => c.id === ragScope.id) || conversations[0];
  const currentScopedSession = sessions.find(s => s.id === ragScope.id) || sessions[0];
  const activePromptText = ragScope.type === 'chat'
    ? currentScopedChat?.systemPrompt || RAGService.getPromptTemplates()[0].content
    : currentScopedSession?.systemPrompt || RAGService.getPromptTemplates()[1].content;
  const activeRAGConfig = ragScope.type === 'chat'
    ? currentScopedChat?.ragConfig || RAGService.getDefaultRAGConfig()
    : currentScopedSession?.ragConfig || RAGService.getDefaultRAGConfig();
  const activeRAGSources = ragScope.type === 'chat'
    ? currentScopedChat?.ragSources || RAGService.getDefaultChatRAGSources()
    : currentScopedSession?.ragSources || RAGService.getDefaultProjectRAGSources();

  const renderActiveScreen = () => {
    switch (activeTab) {
      case 'home':
        return (
          <HomeTab
            providers={providers}
            hosts={hosts}
            conversations={conversations}
            sessions={sessions}
            setActiveTab={setActiveTab}
            onOpenDiffReview={() => setIsDiffModalOpen(true)}
            onOpenChatGPTModal={() => setIsChatGPTModalOpen(true)}
            onOpenGitHub={() => setIsGitHubModalOpen(true)}
            onOpenMCP={() => setIsMCPModalOpen(true)}
            isGitHubConnected={githubConfig.isConnected}
            activeMCPCount={mcpServers.filter(s => s.isEnabled).length}
          />
        );
      case 'chat':
        return (
          <ChatTab
            providers={providers}
            conversations={conversations}
            setConversations={setConversations}
            currentConversationId={currentConversationId}
            setCurrentConversationId={setCurrentConversationId}
            onOpenRAGPrompt={handleOpenChatRAG}
          />
        );
      case 'agents':
        return (
          <AgentsTab
            hosts={hosts}
            sessions={sessions}
            setSessions={setSessions}
            onOpenPairModal={() => setIsPairModalOpen(true)}
            onOpenDiffReview={() => setIsDiffModalOpen(true)}
            onInspectPermission={handleInspectPermission}
            onOpenGitHub={() => setIsGitHubModalOpen(true)}
            onOpenMCP={() => setIsMCPModalOpen(true)}
            onOpenRAGPrompt={handleOpenProjectRAG}
          />
        );
      case 'providers':
        return (
          <ProvidersTab
            providers={providers}
            setProviders={setProviders}
            onOpenEndpointModal={handleOpenEndpointModal}
            onOpenChatGPTModal={() => setIsChatGPTModalOpen(true)}
          />
        );
      case 'settings':
        return (
          <SettingsTab
            providers={providers}
            hosts={hosts}
            soundEnabled={soundEnabled}
            setSoundEnabled={setSoundEnabled}
            onClearCredentials={() => {
              setProviders(prev => prev.map(p => ({ ...p, apiKey: '' })));
              setHosts(prev => prev.map(h => ({ ...h, authToken: '' })));
              setGithubConfig({ isConnected: false, scopes: [] });
            }}
          />
        );
      case 'swift':
        return <SwiftSourceTab />;
      default:
        return null;
    }
  };

  return (
    <div className="min-h-screen bg-[#07080a] text-slate-100 flex flex-col font-sans selection:bg-emerald-500/30 selection:text-emerald-200">
      {/* 3-Zone Top Bar */}
      <TopBar
        viewMode={viewMode}
        setViewMode={setViewMode}
        soundEnabled={soundEnabled}
        setSoundEnabled={setSoundEnabled}
        activeTab={activeTab}
        setActiveTab={setActiveTab}
        onOpenGitHub={() => setIsGitHubModalOpen(true)}
        onOpenMCP={() => setIsMCPModalOpen(true)}
        isGitHubConnected={githubConfig.isConnected}
        activeMCPCount={mcpServers.filter(s => s.isEnabled).length}
      />

      {/* Main Workspace Canvas */}
      <main className="flex-1 flex flex-col items-center justify-center relative overflow-hidden">
        {viewMode === 'phone' ? (
          <PhoneFrame activeTab={activeTab} setActiveTab={setActiveTab}>
            {renderActiveScreen()}
          </PhoneFrame>
        ) : (
          <div className="w-full max-w-7xl h-[calc(100vh-65px)] p-6 flex flex-col">
            <div className="flex-1 rounded-2xl bg-[#0b0c10] border border-[#1f2330] overflow-hidden flex flex-col shadow-2xl">
              {renderActiveScreen()}
            </div>
          </div>
        )}
      </main>

      {/* Modals */}
      <EndpointModal
        isOpen={isEndpointModalOpen}
        provider={editingProvider}
        onClose={() => setIsEndpointModalOpen(false)}
        onSave={handleSaveEndpoint}
      />

      <ChatGPTLoginModal
        isOpen={isChatGPTModalOpen}
        onClose={() => setIsChatGPTModalOpen(false)}
        onSuccess={handleChatGPTLoginSuccess}
        hosts={hosts}
      />

      <GitHubConnectorModal
        isOpen={isGitHubModalOpen}
        onClose={() => setIsGitHubModalOpen(false)}
        config={githubConfig}
        onUpdateConfig={setGithubConfig}
        onLoadRepoIntoAgent={handleLoadRepoIntoAgent}
      />

      <MCPConnectorModal
        isOpen={isMCPModalOpen}
        onClose={() => setIsMCPModalOpen(false)}
        servers={mcpServers}
        onUpdateServers={setMcpServers}
      />

      <RAGPromptModal
        isOpen={isRAGModalOpen}
        onClose={() => setIsRAGModalOpen(false)}
        scopeTitle={ragScope.title}
        scopeType={ragScope.type}
        currentPrompt={activePromptText}
        onSavePrompt={handleSaveRAGPrompt}
        ragConfig={activeRAGConfig}
        onSaveRAGConfig={handleSaveRAGConfig}
        ragSources={activeRAGSources}
        onSaveRAGSources={handleSaveRAGSources}
      />

      <PairHostModal
        isOpen={isPairModalOpen}
        onClose={() => setIsPairModalOpen(false)}
        onPaired={(newHost) => setHosts(prev => [...prev, newHost])}
      />

      <PermissionModal
        isOpen={isPermissionModalOpen}
        permission={activePermission}
        onClose={() => setIsPermissionModalOpen(false)}
        onDecision={handlePermissionDecision}
      />

      <DiffModal
        isOpen={isDiffModalOpen}
        summary={gitSummary}
        onClose={() => setIsDiffModalOpen(false)}
        onSendFollowUp={(prompt) => {
          setActiveTab('agents');
          if (sessions[0]) {
            setSessions(prev => prev.map((s, idx) => idx === 0 ? {
              ...s,
              messages: [
                ...s.messages,
                {
                  id: `f_${Date.now()}`,
                  role: 'user',
                  content: prompt,
                  timestamp: new Date().toISOString(),
                  toolEvents: []
                }
              ]
            } : s));
          }
        }}
      />
    </div>
  );
}
