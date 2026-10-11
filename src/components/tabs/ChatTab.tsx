import React, { useState, useRef, useEffect } from 'react';
import { Send, Square, Plus, Copy, Check, ChevronDown, ChevronRight, Sparkles, AlertTriangle, BookOpen } from 'lucide-react';
import { ProviderConfig, ChatConversation, ChatMessage } from '../../types';
import { OpenAIService } from '../../services/openAiService';
import { RAGService } from '../../services/ragService';
import { fuzzAudio } from '../../services/audioService';

interface ChatTabProps {
  providers: ProviderConfig[];
  conversations: ChatConversation[];
  setConversations: React.Dispatch<React.SetStateAction<ChatConversation[]>>;
  currentConversationId: string;
  setCurrentConversationId: (id: string) => void;
  onOpenRAGPrompt: () => void;
}

export const ChatTab: React.FC<ChatTabProps> = ({
  providers,
  conversations,
  setConversations,
  currentConversationId,
  setCurrentConversationId,
  onOpenRAGPrompt
}) => {
  const [inputText, setInputText] = useState('');
  const [isStreaming, setIsStreaming] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [copiedIndex, setCopiedIndex] = useState<number | null>(null);
  const [expandedCitations, setExpandedCitations] = useState<Record<string, boolean>>({});
  const abortControllerRef = useRef<AbortController | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  const activeProvider = providers.find(p => p.isEnabled) || providers[0];
  const currentConversation = conversations.find(c => c.id === currentConversationId) || conversations[0];

  useEffect(() => {
    scrollRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [currentConversation?.messages, isStreaming]);

  const handleStartNewChat = () => {
    fuzzAudio.playStomp();
    const newConv: ChatConversation = {
      id: `conv_${Date.now()}`,
      title: 'New Conversation',
      providerId: activeProvider?.id || '',
      modelId: activeProvider?.selectedModel || 'gpt-4o',
      messages: [],
      updatedAt: new Date().toISOString(),
      systemPrompt: 'You are an expert iOS & Swift AI coding assistant operating inside FuzzCode.',
      ragConfig: RAGService.getDefaultRAGConfig(),
      ragSources: RAGService.getDefaultChatRAGSources()
    };
    setConversations(prev => [newConv, ...prev]);
    setCurrentConversationId(newConv.id);
  };

  const handleSendMessage = async () => {
    const text = inputText.trim();
    if (!text || isStreaming || !activeProvider) return;

    setInputText('');
    setErrorMessage(null);
    fuzzAudio.playStomp();

    // RAG Knowledge Base Retrieval
    const ragSources = currentConversation?.ragSources || RAGService.getDefaultChatRAGSources();
    const ragConfig = currentConversation?.ragConfig || RAGService.getDefaultRAGConfig();
    const ragResult = RAGService.retrieve(text, ragSources, ragConfig);

    const userMessage: ChatMessage = {
      id: `msg_${Date.now()}_u`,
      role: 'user',
      content: text,
      timestamp: new Date().toISOString()
    };

    const assistantMsgId = `msg_${Date.now()}_a`;
    const initialAssistantMessage: ChatMessage = {
      id: assistantMsgId,
      role: 'assistant',
      content: '',
      timestamp: new Date().toISOString(),
      isStreaming: true,
      retrievedCitations: ragResult.citations.length > 0 ? ragResult.citations : undefined
    };

    // Update conversation with user message and empty streaming assistant bubble
    setConversations(prev => prev.map(c => {
      if (c.id === currentConversation.id) {
        return {
          ...c,
          title: c.messages.length === 0 ? text.slice(0, 30) : c.title,
          messages: [...c.messages, userMessage, initialAssistantMessage]
        };
      }
      return c;
    }));

    setIsStreaming(true);
    abortControllerRef.current = new AbortController();

    // Augment system prompt with RAG context
    const fullSystemPrompt = RAGService.buildFullSystemPrompt(
      currentConversation.systemPrompt,
      ragResult.augmentedContext
    );

    const outboundMessages: ChatMessage[] = [
      {
        id: `sys_${Date.now()}`,
        role: 'system',
        content: fullSystemPrompt,
        timestamp: new Date().toISOString()
      },
      ...currentConversation.messages.filter(m => m.role !== 'system'),
      userMessage
    ];

    try {
      await OpenAIService.streamChat(
        activeProvider,
        outboundMessages,
        (delta) => {
          setConversations(prev => prev.map(c => {
            if (c.id === currentConversation.id) {
              const msgs = [...c.messages];
              const target = msgs.find(m => m.id === assistantMsgId);
              if (target) {
                target.content += delta;
              }
              return { ...c, messages: msgs };
            }
            return c;
          }));
        },
        abortControllerRef.current.signal
      );

      fuzzAudio.playSuccess();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      if (!abortControllerRef.current?.signal.aborted) {
        setErrorMessage(msg);
        fuzzAudio.playAlert();
      }
    } finally {
      setIsStreaming(false);
      setConversations(prev => prev.map(c => {
        if (c.id === currentConversation.id) {
          const msgs = c.messages.map(m => m.id === assistantMsgId ? { ...m, isStreaming: false } : m);
          return { ...c, messages: msgs };
        }
        return c;
      }));
    }
  };

  const handleCancelStreaming = () => {
    if (abortControllerRef.current) {
      abortControllerRef.current.abort();
      abortControllerRef.current = null;
    }
    setIsStreaming(false);
    fuzzAudio.playStomp();
  };

  const toggleCitationExpand = (msgId: string) => {
    setExpandedCitations(prev => ({ ...prev, [msgId]: !prev[msgId] }));
  };

  const copyToClipboard = (content: string, index: number) => {
    navigator.clipboard.writeText(content);
    setCopiedIndex(index);
    fuzzAudio.playSuccess();
    setTimeout(() => setCopiedIndex(null), 2000);
  };

  return (
    <div className="flex-1 flex flex-col h-full overflow-hidden bg-[#090a0d]">
      {/* Top Controls: Provider selector & New Chat & RAG Prompt */}
      <div className="flex items-center justify-between px-4 py-2.5 border-b border-[#181a24] bg-[#0d0e14]">
        <div className="flex items-center gap-2">
          <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse" />
          <div className="text-xs font-semibold text-white">
            {activeProvider ? activeProvider.displayName : 'No Provider'}
          </div>
          <span className="text-[10px] font-mono text-purple-400 bg-purple-500/10 px-1.5 py-0.5 rounded">
            {activeProvider?.selectedModel || 'gpt-4o'}
          </span>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => { fuzzAudio.playStomp(); onOpenRAGPrompt(); }}
            title="Configure Directives & RAG Knowledge Base"
            className="flex items-center gap-1.5 px-2.5 py-1 text-[11px] font-mono rounded-lg border bg-[#141622] border-emerald-500/30 text-emerald-300 hover:border-emerald-500/60 transition-colors cursor-pointer"
          >
            <Sparkles className="w-3.5 h-3.5 text-emerald-400" />
            <span className="hidden sm:inline">RAG & Prompt</span>
            <span className="text-[10px] bg-emerald-500/20 text-emerald-400 px-1.5 py-0.2 rounded font-bold">
              {currentConversation?.ragSources?.filter(s => s.isEnabled).length ?? 2}
            </span>
          </button>

          <button
            onClick={handleStartNewChat}
            title="Start New Conversation"
            className="flex items-center gap-1 px-2.5 py-1 text-[11px] font-medium text-emerald-400 bg-emerald-500/10 hover:bg-emerald-500/20 rounded-md transition-colors cursor-pointer"
          >
            <Plus className="w-3.5 h-3.5" />
            <span>New Chat</span>
          </button>
        </div>
      </div>

      {/* Messages Canvas */}
      <div className="flex-1 overflow-y-auto px-4 py-4 space-y-4">
        {(!currentConversation || currentConversation.messages.length === 0) ? (
          <div className="h-full flex flex-col items-center justify-center text-center px-4 py-12">
            <div className="w-12 h-12 rounded-2xl bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center text-emerald-400 mb-3 shadow-lg shadow-emerald-500/5">
              <Sparkles className="w-6 h-6" />
            </div>
            <h3 className="text-sm font-bold text-white uppercase tracking-wider font-mono">
              FuzzCode Model Chat
            </h3>
            <p className="text-xs text-slate-400 max-w-xs mt-1">
              Stream completions directly from any OpenAI-compatible API endpoint with custom prompt directives and RAG knowledge retrieval.
            </p>
            <div className="flex flex-wrap gap-1.5 justify-center mt-5">
              {[
                'Explain how URL normalization works in Swift',
                'Write a SwiftUI FuzzKnob dial component'
              ].map((suggestion, idx) => (
                <button
                  key={idx}
                  onClick={() => {
                    setInputText(suggestion);
                    fuzzAudio.playStomp();
                  }}
                  className="text-[11px] text-slate-300 bg-[#141620] hover:bg-[#1e2230] border border-[#232736] px-3 py-1.5 rounded-full transition-colors cursor-pointer text-left"
                >
                  {suggestion}
                </button>
              ))}
            </div>
          </div>
        ) : (
          currentConversation.messages.map((msg, index) => (
            <div
              key={msg.id || index}
              className={`flex flex-col ${msg.role === 'user' ? 'items-end' : 'items-start'}`}
            >
              <div
                className={`max-w-[90%] rounded-2xl p-3.5 text-xs leading-relaxed ${
                  msg.role === 'user'
                    ? 'bg-[#1e2333] text-white border border-[#2d344d]'
                    : 'bg-[#12141c] text-slate-200 border border-[#1f2330]'
                }`}
              >
                {/* Assistant Header */}
                {msg.role === 'assistant' && (
                  <div className="flex items-center justify-between gap-4 mb-2 pb-1.5 border-b border-white/5">
                    <span className="text-[10px] font-mono font-bold text-emerald-400 uppercase tracking-wider">
                      FuzzCode Assistant
                    </span>
                    <button
                      onClick={() => copyToClipboard(msg.content, index)}
                      className="text-slate-500 hover:text-slate-300 transition-colors cursor-pointer"
                      title="Copy response"
                    >
                      {copiedIndex === index ? (
                        <Check className="w-3.5 h-3.5 text-emerald-400" />
                      ) : (
                        <Copy className="w-3.5 h-3.5" />
                      )}
                    </button>
                  </div>
                )}

                {/* Retrieved RAG Citations */}
                {msg.retrievedCitations && msg.retrievedCitations.length > 0 && (
                  <div className="mb-2.5 pb-2 border-b border-white/5">
                    <button
                      onClick={() => toggleCitationExpand(msg.id)}
                      className="w-full flex items-center justify-between text-[10px] font-mono text-emerald-400 hover:text-emerald-300 py-0.5 cursor-pointer"
                    >
                      <div className="flex items-center gap-1.5">
                        <BookOpen className="w-3.5 h-3.5 text-emerald-400" />
                        <span className="font-bold">
                          Grounded in {msg.retrievedCitations.length} Knowledge Source{msg.retrievedCitations.length > 1 ? 's' : ''}
                        </span>
                      </div>
                      {expandedCitations[msg.id] ? (
                        <ChevronDown className="w-3.5 h-3.5 text-emerald-400" />
                      ) : (
                        <ChevronRight className="w-3.5 h-3.5 text-emerald-400" />
                      )}
                    </button>

                    {expandedCitations[msg.id] && (
                      <div className="mt-2 space-y-1.5 pt-1 font-mono text-[10px]">
                        {msg.retrievedCitations.map((c, ci) => (
                          <div key={ci} className="p-2 rounded bg-black/40 border border-emerald-500/20">
                            <div className="flex items-center justify-between text-slate-300 mb-0.5 font-bold">
                              <span>{c.sourceTitle}</span>
                              <span className="text-emerald-400">{(c.score * 100).toFixed(0)}% match</span>
                            </div>
                            <p className="text-slate-400 text-[10px] leading-relaxed">
                              {c.snippet}
                            </p>
                          </div>
                        ))}
                      </div>
                    )}
                  </div>
                )}

                {/* Formatted Content */}
                <div className="whitespace-pre-wrap font-sans break-words">
                  {msg.content.length === 0 && msg.isStreaming ? (
                    <span className="text-slate-500 italic flex items-center gap-1.5">
                      <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-ping" />
                      Streaming tokens...
                    </span>
                  ) : (
                    renderFormattedMessage(msg.content)
                  )}
                </div>
              </div>
            </div>
          ))
        )}
        <div ref={scrollRef} />
      </div>

      {/* Error Banner */}
      {errorMessage && (
        <div className="mx-4 mb-2 p-2.5 rounded-lg bg-red-950/40 border border-red-500/30 flex items-center justify-between text-xs text-red-300">
          <div className="flex items-center gap-2">
            <AlertTriangle className="w-4 h-4 text-red-400 shrink-0" />
            <span className="line-clamp-1">{errorMessage}</span>
          </div>
          <button
            onClick={() => setErrorMessage(null)}
            className="text-[10px] font-bold uppercase text-red-400 hover:text-red-200 cursor-pointer ml-2"
          >
            Dismiss
          </button>
        </div>
      )}

      {/* Prompt Input Bar */}
      <div className="p-3 border-t border-[#181a24] bg-[#0c0d12]">
        <div className="flex items-center gap-2 bg-[#151722] border border-[#232736] rounded-2xl px-3 py-1.5 focus-within:border-emerald-500/50 transition-colors">
          <textarea
            value={inputText}
            onChange={(e) => setInputText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault();
                handleSendMessage();
              }
            }}
            placeholder="Type your instruction or prompt..."
            rows={1}
            className="flex-1 bg-transparent text-xs text-white placeholder-slate-500 focus:outline-none resize-none py-1.5 max-h-24"
          />

          {isStreaming ? (
            <button
              onClick={handleCancelStreaming}
              title="Stop Generation"
              className="w-8 h-8 rounded-full bg-red-500 hover:bg-red-400 text-black flex items-center justify-center transition-all cursor-pointer shrink-0 active:scale-95"
            >
              <Square className="w-3.5 h-3.5 fill-current" />
            </button>
          ) : (
            <button
              onClick={handleSendMessage}
              disabled={!inputText.trim()}
              title="Send Prompt"
              className={`w-8 h-8 rounded-full flex items-center justify-center transition-all cursor-pointer shrink-0 active:scale-95 ${
                inputText.trim()
                  ? 'bg-emerald-400 hover:bg-emerald-300 text-black shadow-sm shadow-emerald-500/20'
                  : 'bg-slate-800 text-slate-500 cursor-not-allowed'
              }`}
            >
              <Send className="w-3.5 h-3.5" />
            </button>
          )}
        </div>
      </div>
    </div>
  );
};

// Formats basic markdown code blocks and backticks
function renderFormattedMessage(content: string) {
  const parts = content.split(/(```[\s\S]*?```)/g);
  return parts.map((part, idx) => {
    if (part.startsWith('```') && part.endsWith('```')) {
      const firstLineBreak = part.indexOf('\n');
      const lang = firstLineBreak !== -1 ? part.slice(3, firstLineBreak).trim() : '';
      const code = firstLineBreak !== -1 ? part.slice(firstLineBreak + 1, -3) : part.slice(3, -3);
      return (
        <div key={idx} className="my-2 rounded-lg bg-[#07080a] border border-[#232734] overflow-hidden text-[11px] font-mono">
          {lang && (
            <div className="flex items-center justify-between px-3 py-1 bg-[#12141c] border-b border-[#232734] text-[9px] text-slate-400 uppercase tracking-wider">
              <span>{lang}</span>
            </div>
          )}
          <pre className="p-3 overflow-x-auto text-emerald-300">
            <code>{code}</code>
          </pre>
        </div>
      );
    }
    return <span key={idx}>{part}</span>;
  });
}
