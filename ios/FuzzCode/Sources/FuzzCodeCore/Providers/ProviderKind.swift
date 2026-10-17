import Foundation

/// Direct AI provider families supported by FuzzCode.
/// `.custom` preserves the original generic OpenAI-compatible endpoint behavior.
public enum ProviderKind: String, Codable, CaseIterable, Sendable {
    case openai = "openai"
    case anthropic = "anthropic"
    case gemini = "gemini"
    case openRouter = "openrouter"
    case groq = "groq"
    case custom = "custom"

    public var displayName: String {
        switch self {
        case .openai: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .gemini: return "Google Gemini"
        case .openRouter: return "OpenRouter"
        case .groq: return "Groq"
        case .custom: return "Custom (OpenAI-compatible)"
        }
    }

    public var defaultBaseURLString: String {
        switch self {
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com"
        case .gemini: return "https://generativelanguage.googleapis.com"
        case .openRouter: return "https://openrouter.ai/api/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .custom: return "https://api.openai.com/v1"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openai: return "gpt-4o"
        case .anthropic: return "claude-sonnet-4-5"
        case .gemini: return "gemini-2.0-flash"
        case .openRouter: return "openrouter/auto"
        case .groq: return "llama-3.3-70b-versatile"
        case .custom: return "gpt-4o"
        }
    }

    /// Curated model ids used as a fallback when `/models` discovery is unavailable.
    public var curatedModels: [String] {
        switch self {
        case .openai:
            return ["gpt-4o", "gpt-4o-mini", "o3-mini", "gpt-4.1", "gpt-4.1-mini"]
        case .anthropic:
            return ["claude-sonnet-4-5", "claude-opus-4-1", "claude-haiku-4-5", "claude-3-5-haiku-latest"]
        case .gemini:
            return ["gemini-2.0-flash", "gemini-2.5-pro", "gemini-2.5-flash", "gemini-1.5-pro"]
        case .openRouter:
            return ["openrouter/auto", "anthropic/claude-sonnet-4", "openai/gpt-4o", "google/gemini-2.0-flash-001"]
        case .groq:
            return ["llama-3.3-70b-versatile", "llama-3.1-8b-instant", "mixtral-8x7b-32768", "gemma2-9b-it"]
        case .custom:
            return []
        }
    }

    /// Whether chat completions use the OpenAI request/response shape.
    public var isOpenAICompatible: Bool {
        switch self {
        case .openai, .openRouter, .groq, .custom:
            return true
        case .anthropic, .gemini:
            return false
        }
    }

    /// Whether agentic tool-calling is implemented for this kind in FuzzCode.
    public var supportsNativeToolLoop: Bool { true }
}
