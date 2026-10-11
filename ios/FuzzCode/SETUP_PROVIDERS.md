# OpenAI-Compatible Providers Setup Guide

FuzzCode connects directly to any OpenAI-compatible Chat Completions API.

---

## 1. OpenAI / Groq / Kilo
- **Base URL**:
  - OpenAI: `https://api.openai.com/v1`
  - Groq: `https://api.groq.com/openai/v1`
  - OpenRouter: `https://openrouter.ai/api/v1`
- **Model**: e.g., `gpt-4o`, `llama-3.3-70b-versatile`, `anthropic/claude-3.5-sonnet`
- **API Key**: Enter your key. FuzzCode stores it in the iOS Keychain.
- **Model Discovery**: Tap **Discover** to query the provider's `/v1/models` catalog automatically.

---

## 2. Local Models (Ollama, LM Studio, LocalAI)
When hosting models locally on your Mac or LAN:
- **Ollama**:
  - Ensure Ollama binds to LAN: `OLLAMA_HOST=0.0.0.0:11434 ollama serve`
  - In FuzzCode, enable **Allow Insecure HTTP (Local Dev)**.
  - Base URL: `http://192.168.1.xxx:11434/v1`
  - Model: e.g. `qwen2.5-coder:7b`, `deepseek-coder-v2`
- **LM Studio**:
  - Start Local Server on port `1234`.
  - Base URL: `http://192.168.1.xxx:1234/v1`

---

## 3. Using Your ChatGPT Subscription to Log into Codex

If you have a **ChatGPT Plus, Team, or Pro** subscription, FuzzCode allows you to authenticate directly with your ChatGPT account rather than paying per-token on the OpenAI Platform:

### How it Works:
1. Navigate to the **Endpoints** tab and tap **ChatGPT Codex**.
2. Select your subscription tier (**Plus**, **Pro**, **Team**, or **Enterprise**).
3. Authenticate via:
   - **OpenAI Account Sign-In (OAuth Flow)**: Authenticates via device authorization code.
   - **Session / Access Token**: Paste your ChatGPT session token from `chatgpt.com` cookies or CLI (`openai login`).
4. FuzzCode stores the token in the native **iOS Keychain** and configures the endpoint:
   - Base URL: `https://api.openai.com/v1`
   - Model: `chatgpt-4o-latest` / `o1` / `codex`
   - Header: `OpenAI-Beta: codex=v1`, `X-OpenAI-Subscription: plus`
5. Enable **Sync with OpenCode Coding Agent**:
   - Transmits your ChatGPT subscription token to the paired OpenCode companion daemon.
   - Autonomous agent tool loops (ripgrep, file_edit, execute_bash) execute using your unlimited ChatGPT subscription quota!
