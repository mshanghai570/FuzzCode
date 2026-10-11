import { RAGSource, RAGChunk, RAGConfig, PromptTemplate, RetrievedCitation } from '../types';

export class RAGService {
  /**
   * Default Prompt Templates for Chat Conversations and Agent Projects
   */
  public static getPromptTemplates(): PromptTemplate[] {
    return [
      {
        id: 'tmpl_swift_concurrency',
        title: 'Swift 6 & iOS Concurrency Specialist',
        category: 'ios_swift',
        description: 'Enforces Swift 6 strict concurrency, Sendable conformance, and native Apple security practices.',
        content: `You are an expert native iOS software engineer specializing in Swift 6, SwiftUI, and modern concurrency.
Guidelines:
1. Always enforce actor isolation, Sendable conformance, and thread-safe data flow.
2. Avoid web-based wrappers or non-native abstractions. Target iOS 17+.
3. Treat Keychain security with highest rigor (kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly).
4. Provide idiomatic, clean SwiftUI view code with sensory feedback (haptics, tactile controls).`
      },
      {
        id: 'tmpl_opencode_autonomous',
        title: 'OpenCode Autonomous Agent Directive',
        category: 'architecture',
        description: 'Optimized for autonomous tool execution, terminal testing, and git diff management.',
        content: `You are an autonomous OpenCode software engineer operating directly on remote repository hosts.
Directives:
1. Formulate step-by-step plans before invoking filesystem or bash tools.
2. Always run unit tests after making code changes before reporting success.
3. Keep git patches minimal and focused. Never introduce regression bugs.
4. Flag high-risk actions (e.g. destructive file deletes or network calls) for explicit developer authorization.`
      },
      {
        id: 'tmpl_security_auditor',
        title: 'Security Auditor & Secret Sentinel',
        category: 'security',
        description: 'Audits network payloads, credential handling, Keychain sanitization, and URL normalization.',
        content: `You are a cybersecurity auditor for mobile and developer tools.
Guidelines:
1. Never log raw API keys, bearer tokens, or session secrets. Always redact credentials.
2. Audit URL normalization to prevent double /v1 routes and path traversal exploits.
3. Reject insecure plain HTTP transport unless explicitly flagged for trusted development loopbacks.
4. Audit third-party dependencies and verify checksum integrity.`
      },
      {
        id: 'tmpl_clean_refactor',
        title: 'Clean Architecture & Refactoring Purist',
        category: 'debugging',
        description: 'Focuses on protocol-oriented programming, modularity, and high-coverage XCTest suites.',
        content: `You are a principal engineer committed to Clean Architecture and maintainability.
Guidelines:
1. Separate Model Providers, Coding Agents, and Execution Hosts into independent protocols.
2. Maintain strong decoupling between networking, business logic, and SwiftUI presentation.
3. Write thorough unit tests for every critical normalization, parsing, and state transition logic.`
      }
    ];
  }

  /**
   * Default Initial RAG Knowledge Base Sources for Projects
   */
  public static getDefaultProjectRAGSources(): RAGSource[] {
    return [
      {
        id: 'rag_arch_spec',
        title: 'FuzzCode Tripartite Architecture Spec',
        type: 'doc',
        filePath: 'ARCHITECTURE.md',
        content: `Tripartite Architecture Specification:
1. Model Providers: Supply raw token completions via OpenAI-compatible endpoints (Kilo, Groq, Ollama). Decoupled from agent tools.
2. Coding Agents: Autonomous runtimes (OpenCode) that execute tools (bash, ripgrep, file_edit), request interactive permissions, and maintain sessions.
3. Execution Hosts: Remote developer environments (Mac, Linux, Cloud VM) pairing with the iPhone over TLS or secure tunnel. The iPhone does not run macOS CLI binaries locally.`,
        tokens: 140,
        chunksCount: 1,
        isEnabled: true,
        addedAt: new Date().toISOString()
      },
      {
        id: 'rag_swift_concurrency',
        title: 'Swift 6 Actor Isolation & Sendable Rules',
        type: 'guideline',
        filePath: 'Sources/FuzzCodeCore/Architecture/Protocols.swift',
        content: `Swift 6 Strict Concurrency Rules:
- All core protocols (ModelProviderProtocol, CodingAgentProtocol, ExecutionHostProtocol) must conform to Sendable.
- Networking clients (OpenAIClient, OpenCodeClient, GitHubClient, MCPClient) are declared as 'actor' to protect internal session state.
- Data structures passed across async boundaries (ProviderConfig, AgentSession, GitFileDiff) must be value types (structs) conforming to Sendable.
- Never use mutable static variables without synchronized protection.`,
        tokens: 135,
        chunksCount: 1,
        isEnabled: true,
        addedAt: new Date().toISOString()
      },
      {
        id: 'rag_url_norm_rules',
        title: 'OpenAI URL Normalization Rules',
        type: 'guideline',
        filePath: 'Sources/FuzzCodeCore/Networking/OpenAIClient.swift',
        content: `URL Normalization Guidelines:
- If base URL ends with '/v1', append 'chat/completions'.
- If base URL ends with '/chat/completions', use as-is without modification.
- If base URL has custom api path (e.g. '/api/generate'), respect custom path.
- In all other cases, append 'v1/chat/completions'.
- Never double append '/v1' (e.g. prevent 'https://api.groq.com/openai/v1/v1/chat/completions').`,
        tokens: 110,
        chunksCount: 1,
        isEnabled: true,
        addedAt: new Date().toISOString()
      },
      {
        id: 'rag_keychain_policy',
        title: 'Apple Keychain Zero-Leak Policy',
        type: 'guideline',
        filePath: 'Sources/FuzzCodeCore/Security/KeychainService.swift',
        content: `Keychain Security Policy:
- Store credentials with kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly.
- Redact secrets in logs and diagnostic exporters (show prefix + '••••' + suffix).
- Never serialize API keys or auth tokens to disk inside unencrypted JSON files or UserDefaults.`,
        tokens: 85,
        chunksCount: 1,
        isEnabled: true,
        addedAt: new Date().toISOString()
      }
    ];
  }

  /**
   * Default Initial RAG Knowledge Base Sources for Chat
   */
  public static getDefaultChatRAGSources(): RAGSource[] {
    return [
      {
        id: 'rag_chat_style',
        title: 'FuzzCode Sensory & Audio Identity',
        type: 'doc',
        content: `Sensory Identity:
- FuzzCode draws inspiration from vintage 3PDT guitar fuzz stompboxes (Big Muff, Tone Bender, Fuzz Face).
- Palette: Deep Charcoal (#07080a, #0b0c10), Acid Green (#22c55e), Electric Purple (#8b5cf6), Muted Slate (#64748b).
- Audio: Tactile 3PDT mechanical stomp clicks on mode switches and critical actions.`,
        tokens: 95,
        chunksCount: 1,
        isEnabled: true,
        addedAt: new Date().toISOString()
      },
      {
        id: 'rag_chat_shortcuts',
        title: 'OpenCode CLI Server Protocol Reference',
        type: 'doc',
        content: `OpenCode Companion Server:
- Default port: 4096 (or configured companion port).
- Standard REST & WebSocket endpoints:
  GET /api/v1/health -> { status: "ok", version: "v0.14.2" }
  POST /api/v1/sessions -> Creates session attached to local git workspace.
  POST /api/v1/sessions/:id/prompt -> Streams tool execution events and permission checks.`,
        tokens: 105,
        chunksCount: 1,
        isEnabled: true,
        addedAt: new Date().toISOString()
      }
    ];
  }

  /**
   * Creates an active RAG configuration with defaults
   */
  public static getDefaultRAGConfig(): RAGConfig {
    return {
      isEnabled: true,
      topK: 3,
      similarityThreshold: 0.15,
      maxContextTokens: 1500,
      injectMode: 'system'
    };
  }

  /**
   * Splits a source text into manageable semantic chunks (~120-250 tokens each)
   */
  public static chunkSource(source: RAGSource): RAGChunk[] {
    const rawContent = source.content.trim();
    if (!rawContent) return [];

    // Split on double newlines or major headings
    const rawParagraphs = rawContent.split(/\n\s*\n+/).filter(p => p.trim().length > 0);
    const chunks: RAGChunk[] = [];

    rawParagraphs.forEach((para, index) => {
      const trimmed = para.trim();
      const tokens = Math.max(Math.round(trimmed.length / 4), 1);
      chunks.push({
        id: `${source.id}_chunk_${index}`,
        sourceId: source.id,
        sourceTitle: source.title,
        content: trimmed,
        tokens
      });
    });

    if (chunks.length === 0) {
      chunks.push({
        id: `${source.id}_chunk_0`,
        sourceId: source.id,
        sourceTitle: source.title,
        content: rawContent,
        tokens: Math.max(Math.round(rawContent.length / 4), 1)
      });
    }

    return chunks;
  }

  /**
   * Performs semantic retrieval over enabled RAG sources given a query.
   * Uses token overlap + BM25-style keyword weighting for fast, local in-browser search.
   */
  public static retrieve(
    query: string,
    sources: RAGSource[],
    config: RAGConfig
  ): {
    augmentedContext: string;
    citations: RetrievedCitation[];
  } {
    if (!config.isEnabled || !query.trim() || sources.length === 0) {
      return { augmentedContext: '', citations: [] };
    }

    const enabledSources = sources.filter(s => s.isEnabled);
    if (enabledSources.length === 0) {
      return { augmentedContext: '', citations: [] };
    }

    // Tokenize query into normalized keywords
    const queryTokens = query
      .toLowerCase()
      .replace(/[^\w\s]/g, ' ')
      .split(/\s+/)
      .filter(w => w.length > 2 && !STOP_WORDS.has(w));

    // Flatten all chunks from enabled sources
    const allChunks: RAGChunk[] = [];
    for (const source of enabledSources) {
      const chunks = this.chunkSource(source);
      allChunks.push(...chunks);
    }

    // Score each chunk
    const scoredChunks: (RAGChunk & { score: number })[] = [];

    for (const chunk of allChunks) {
      const chunkLower = chunk.content.toLowerCase();
      let score = 0;

      // Exact substring boost
      if (chunkLower.includes(query.toLowerCase())) {
        score += 0.6;
      }

      // Keyword hits & frequencies
      let matchedTokens = 0;
      for (const qToken of queryTokens) {
        if (chunkLower.includes(qToken)) {
          matchedTokens++;
          // Term frequency bonus
          const matches = (chunkLower.match(new RegExp(qToken, 'g')) || []).length;
          score += 0.15 + Math.min(matches * 0.05, 0.2);
        }
      }

      if (queryTokens.length > 0) {
        score += (matchedTokens / queryTokens.length) * 0.4;
      }

      // Title match boost
      if (chunk.sourceTitle.toLowerCase().includes(query.toLowerCase())) {
        score += 0.3;
      }

      // Normalize score between 0 and 1
      const normalizedScore = Math.min(Math.round(score * 100) / 100, 1.0);

      if (normalizedScore >= config.similarityThreshold || queryTokens.length === 0) {
        scoredChunks.push({
          ...chunk,
          score: normalizedScore || 0.35
        });
      }
    }

    // Sort descending by score
    scoredChunks.sort((a, b) => b.score - a.score);

    // Take topK up to maxContextTokens
    const selected = scoredChunks.slice(0, config.topK);
    let currentTokens = 0;
    const finalChunks: (RAGChunk & { score: number })[] = [];

    for (const chunk of selected) {
      if (currentTokens + chunk.tokens <= config.maxContextTokens) {
        finalChunks.push(chunk);
        currentTokens += chunk.tokens;
      }
    }

    if (finalChunks.length === 0) {
      return { augmentedContext: '', citations: [] };
    }

    // Format citations
    const citations: RetrievedCitation[] = finalChunks.map(c => ({
      id: c.id,
      sourceTitle: c.sourceTitle,
      sourceType: 'doc',
      snippet: c.content.length > 140 ? `${c.content.slice(0, 140)}...` : c.content,
      score: c.score
    }));

    // Format context block
    const augmentedContext = [
      '<project_knowledge_base>',
      ...finalChunks.map(c => `[Source: ${c.sourceTitle} | Relevance: ${(c.score * 100).toFixed(0)}%]\n${c.content}`),
      '</project_knowledge_base>'
    ].join('\n\n');

    return { augmentedContext, citations };
  }

  /**
   * Builds an augmented system prompt with RAG context and custom directive
   */
  public static buildFullSystemPrompt(
    basePrompt: string | undefined,
    ragContext: string
  ): string {
    const parts: string[] = [];
    if (basePrompt && basePrompt.trim()) {
      parts.push(basePrompt.trim());
    }
    if (ragContext && ragContext.trim()) {
      parts.push(
        `## Context Knowledge Base:\nUse the following verified project knowledge to guide your decisions and code output:\n\n${ragContext}`
      );
    }
    return parts.join('\n\n');
  }
}

const STOP_WORDS = new Set([
  'the', 'and', 'for', 'with', 'that', 'this', 'from', 'have', 'what', 'how',
  'can', 'you', 'will', 'are', 'was', 'were', 'been', 'about', 'into', 'some'
]);
