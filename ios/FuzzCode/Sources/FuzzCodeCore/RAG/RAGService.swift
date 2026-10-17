import Foundation

/// High-performance native RAG and Prompt Engineering service in Swift.
/// Manages semantic chunking, keyword-weighted retrieval, and system prompt augmentation.
public actor RAGService {
    public static let shared = RAGService()
    
    private init() {}
    
    /// Returns curated prompt templates for iOS engineering and autonomous agents.
    public func promptTemplates() -> [PromptTemplate] {
        return [
            PromptTemplate(
                id: "tmpl_swift_concurrency",
                title: "Swift 6 Concurrency Specialist",
                category: "ios_swift",
                description: "Enforces actor isolation, Sendable value semantics, and zero race conditions.",
                content: """
                You are a senior native iOS software architect specializing in Swift 6 and SwiftUI.
                Rules:
                1. Strictly enforce actor isolation and Sendable semantics across concurrency boundaries.
                2. Design views with SwiftUI best practices, native haptics, and responsive layout.
                3. Never log raw credentials or secrets. Enforce Apple Keychain isolation.
                """
            ),
            PromptTemplate(
                id: "tmpl_opencode_agent",
                title: "Autonomous OpenCode Directive",
                category: "architecture",
                description: "Formulates plans, invokes terminal tools, and verifies tests on remote hosts.",
                content: """
                You are an autonomous OpenCode software engineer operating on a remote repository host.
                Rules:
                1. Plan tool calls methodically before modifying code or running bash commands.
                2. Always run unit tests after code edits to prevent regressions.
                3. Ground decisions against project architecture documentation and coding standards.
                """
            ),
            PromptTemplate(
                id: "tmpl_security_auditor",
                title: "Security & Credential Sentinel",
                category: "security",
                description: "Audits Keychain usage, redactions, TLS endpoints, and URL normalization.",
                content: """
                You are a security auditor for developer tools and mobile software.
                Rules:
                1. Inspect credential handling to ensure kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly.
                2. Verify URL normalization avoids route duplication or traversal exploits.
                3. Reject insecure non-HTTPS transport unless explicitly configured for local test loops.
                """
            )
        ]
    }
    
    /// Splits source content into semantic chunks (~120 tokens per chunk).
    public func chunkSource(_ source: RAGSource) -> [RAGChunk] {
        let paragraphs = source.content.components(separatedBy: "\n\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if paragraphs.isEmpty {
            let tokens = max(source.content.count / 4, 1)
            return [RAGChunk(id: "\(source.id)_chunk_0", sourceId: source.id, sourceTitle: source.title, content: source.content, tokens: tokens)]
        }
        
        return paragraphs.enumerated().map { index, para in
            let trimmed = para.trimmingCharacters(in: .whitespacesAndNewlines)
            let tokens = max(trimmed.count / 4, 1)
            return RAGChunk(id: "\(source.id)_chunk_\(index)", sourceId: source.id, sourceTitle: source.title, content: trimmed, tokens: tokens)
        }
    }
    
    /// Performs keyword and term-frequency retrieval across enabled sources.
    public func retrieve(query: String, sources: [RAGSource], config: RAGConfig) -> (augmentedContext: String, citations: [RetrievedCitation]) {
        guard config.isEnabled, config.topK > 0, config.maxContextTokens > 0,
              !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ("", [])
        }
        
        let enabled = sources.filter { $0.isEnabled }
        guard !enabled.isEmpty else { return ("", []) }
        
        let queryKeywords = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
        
        var scored: [(chunk: RAGChunk, score: Double)] = []
        for source in enabled {
            let chunks = chunkSource(source)
            for chunk in chunks {
                let contentLower = chunk.content.lowercased()
                var score = 0.0
                
                if contentLower.contains(query.lowercased()) {
                    score += 0.5
                }
                
                var hits = 0
                for kw in queryKeywords {
                    if contentLower.contains(kw) {
                        hits += 1
                        score += 0.2
                    }
                }
                if !queryKeywords.isEmpty {
                    score += (Double(hits) / Double(queryKeywords.count)) * 0.3
                }
                
                if score >= config.similarityThreshold {
                    scored.append((chunk, min(score, 1.0)))
                }
            }
        }
        
        scored.sort { $0.score > $1.score }
        // Skip chunks that cannot fit rather than exceeding the configured prompt budget.
        // Token counts are approximations (four characters per token), not model tokenization.
        var topChunks: [(chunk: RAGChunk, score: Double)] = []
        var usedTokens = 0
        for item in scored {
            guard topChunks.count < config.topK else { break }
            guard item.chunk.tokens <= config.maxContextTokens - usedTokens else { continue }
            topChunks.append(item)
            usedTokens += item.chunk.tokens
        }
        
        let citations = topChunks.map { item in
            RetrievedCitation(
                id: item.chunk.id,
                sourceTitle: item.chunk.sourceTitle,
                sourceType: "doc",
                snippet: String(item.chunk.content.prefix(140)),
                score: item.score
            )
        }
        
        let contextLines = topChunks.map { item in
            "[Source: \(item.chunk.sourceTitle) | Relevance: \(Int(item.score * 100))%]\n\(item.chunk.content)"
        }
        
        let augmented = contextLines.isEmpty ? "" : "<project_knowledge_base>\n" + contextLines.joined(separator: "\n\n") + "\n</project_knowledge_base>"
        return (augmented, citations)
    }
    
    /// Builds full system prompt combining custom directives and retrieved knowledge.
    public func buildSystemPrompt(
        basePrompt: String?,
        ragContext: String,
        skillContents: [(name: String, content: String)] = []
    ) -> String {
        var parts: [String] = []
        if let base = basePrompt, !base.isEmpty {
            parts.append(base)
        }
        if !ragContext.isEmpty {
            parts.append("## Verified Project Knowledge:\n\(ragContext)")
        }
        if !skillContents.isEmpty {
            let entries = skillContents.map { "[Skill: \($0.name)]\n\($0.content)" }
            parts.append("<selected_skills>\n\(entries.joined(separator: "\n\n"))\n</selected_skills>")
        }
        return parts.joined(separator: "\n\n")
    }
}
