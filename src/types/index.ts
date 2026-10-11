export interface HTTPHeaderField {
  id: string;
  key: string;
  value: string;
}

export type ProviderAuthMethod = 'api_key' | 'chatgpt_subscription';

export interface ChatGPTSession {
  accountEmail?: string;
  subscriptionTier: 'plus' | 'pro' | 'team' | 'enterprise';
  accessToken: string;
  refreshToken?: string;
  expiresAt?: string;
  sessionStatus: 'active' | 'expired' | 'unauthenticated';
}

export interface ProviderConfig {
  id: string;
  displayName: string;
  baseURLString: string;
  selectedModel: string;
  apiKey: string;
  authMethod?: ProviderAuthMethod;
  chatgptSession?: ChatGPTSession;
  isCodexOptimized?: boolean;
  customHeaders: HTTPHeaderField[];
  organizationId?: string;
  projectId?: string;
  customApiPath?: string;
  timeoutSeconds: number;
  isEnabled: boolean;
  allowsInsecureHTTP: boolean;
  createdAt: string;
  lastTestedAt?: string;
  lastLatencyMs?: number;
}

export interface ModelInfo {
  id: string;
  ownedBy?: string;
}

export interface RetrievedCitation {
  id: string;
  sourceTitle: string;
  sourceType: string;
  snippet: string;
  score: number;
}

export interface ChatMessage {
  id: string;
  role: 'system' | 'user' | 'assistant';
  content: string;
  timestamp: string;
  isStreaming?: boolean;
  retrievedCitations?: RetrievedCitation[];
}

export type RAGSourceType = 'file' | 'doc' | 'snippet' | 'url' | 'guideline';

export interface RAGChunk {
  id: string;
  sourceId: string;
  sourceTitle: string;
  content: string;
  tokens: number;
  score?: number;
}

export interface RAGSource {
  id: string;
  title: string;
  type: RAGSourceType;
  content: string;
  filePath?: string;
  tokens: number;
  chunksCount: number;
  isEnabled: boolean;
  addedAt: string;
}

export interface RAGConfig {
  isEnabled: boolean;
  topK: number;
  similarityThreshold: number;
  maxContextTokens: number;
  injectMode: 'system' | 'user_prefix';
}

export interface PromptTemplate {
  id: string;
  title: string;
  description: string;
  content: string;
  category: 'ios_swift' | 'security' | 'architecture' | 'debugging' | 'custom';
}

export interface ChatConversation {
  id: string;
  title: string;
  providerId: string;
  modelId: string;
  messages: ChatMessage[];
  updatedAt: string;
  systemPrompt?: string;
  ragConfig?: RAGConfig;
  ragSources?: RAGSource[];
}

export type AgentCapability = 
  | 'sessions' 
  | 'streaming' 
  | 'tool_events' 
  | 'cancellation' 
  | 'file_diffs' 
  | 'permission_requests' 
  | 'project_selection' 
  | 'git_status' 
  | 'session_resumption';

export interface OpenCodeHostConfig {
  id: string;
  displayName: string;
  hostURLString: string;
  authToken: string;
  isConnected: boolean;
  osVersion?: string;
  agentVersion?: string;
  currentWorkspace?: string;
  capabilities: AgentCapability[];
  useChatGPTSubscriptionForCodex?: boolean;
  chatgptAccountEmail?: string;
  lastSeen?: string;
}

export interface AgentToolEvent {
  id: string;
  toolName: string;
  argumentsJSON: string;
  outputSnippet?: string;
  status: 'pending' | 'running' | 'success' | 'failed' | 'denied';
  startedAt: string;
  completedAt?: string;
}

export interface PermissionRequest {
  id: string;
  toolName: string;
  commandOrPath: string;
  fullParameters: Record<string, string>;
  riskLevel: 'low' | 'medium' | 'high' | 'destructive';
  requestedAt: string;
}

export interface AgentSessionMessage {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  timestamp: string;
  toolEvents: AgentToolEvent[];
  retrievedCitations?: RetrievedCitation[];
}

export interface AgentSession {
  id: string;
  hostId: string;
  title: string;
  workspacePath: string;
  status: 'idle' | 'running' | 'waiting_permission' | 'completed' | 'cancelled' | 'failed';
  createdAt: string;
  updatedAt: string;
  messages: AgentSessionMessage[];
  pendingPermission?: PermissionRequest;
  systemPrompt?: string;
  ragConfig?: RAGConfig;
  ragSources?: RAGSource[];
}

export interface GitFileDiff {
  id: string;
  filePath: string;
  status: 'modified' | 'added' | 'deleted' | 'renamed' | 'untracked';
  additions: number;
  deletions: number;
  patch: string;
}

export interface GitStatusSummary {
  branch: string;
  ahead: number;
  behind: number;
  changedFiles: GitFileDiff[];
}

// GitHub Connector Types
export interface GitHubUser {
  login: string;
  name: string;
  avatarUrl: string;
  htmlUrl: string;
  publicRepos: number;
  totalPrivateRepos: number;
}

export interface GitHubRepo {
  id: number;
  name: string;
  fullName: string;
  private: boolean;
  defaultBranch: string;
  description: string | null;
  htmlUrl: string;
  stargazersCount: number;
  updatedAt: string;
  openIssuesCount: number;
}

export interface GitHubPullRequest {
  id: number;
  number: number;
  title: string;
  state: 'open' | 'closed' | 'merged';
  user: string;
  headBranch: string;
  baseBranch: string;
  createdAt: string;
  additions: number;
  deletions: number;
}

export interface GitHubConfig {
  isConnected: boolean;
  token?: string;
  user?: GitHubUser;
  selectedRepo?: GitHubRepo;
  scopes: string[];
  connectedAt?: string;
}

// Model Context Protocol (MCP) Connector Types
export type MCPTransportType = 'sse' | 'websocket' | 'stdio_remote';

export interface MCPToolParameterProperty {
  type: string;
  description?: string;
  enum?: string[];
}

export interface MCPTool {
  name: string;
  description: string;
  inputSchema: {
    type: 'object';
    properties?: Record<string, MCPToolParameterProperty>;
    required?: string[];
  };
}

export interface MCPResource {
  uri: string;
  name: string;
  description?: string;
  mimeType?: string;
}

export interface MCPServerConfig {
  id: string;
  name: string;
  description?: string;
  transport: MCPTransportType;
  endpointURL: string;
  command?: string;
  authToken?: string;
  customHeaders: HTTPHeaderField[];
  envVars: Record<string, string>;
  isEnabled: boolean;
  discoveredTools: MCPTool[];
  discoveredResources: MCPResource[];
  status: 'connected' | 'disconnected' | 'error';
  lastPingMs?: number;
  lastError?: string;
}
