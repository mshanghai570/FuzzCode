# OpenCode Companion Setup Guide

OpenCode runs as an external server companion on your development machine (Mac, Linux, or Cloud VM). FuzzCode on your iPhone connects to it over your local network or a secure tunnel (e.g. Tailscale, Cloudflare Tunnel).

---

## 1. Starting the OpenCode Companion Server

On your Mac or dev machine, launch the OpenCode companion daemon:

```bash
# Install or update opencode
npm install -g opencode

# Start the companion HTTP & WebSocket server on your LAN
opencode serve --port 4096 --token "your-secret-fuzz-token"
```

The server will bind to `0.0.0.0:4096` and display your local IP (e.g. `http://192.168.1.150:4096`).

---

## 2. Pairing in FuzzCode

1. Open **FuzzCode** on your iPhone.
2. Navigate to the **Agents** tab.
3. Tap the **Link Host** button (`+`).
4. Enter:
   - **Host Name**: e.g., `MacBook Pro M3 Max`
   - **Host URL**: e.g., `http://192.168.1.150:4096` (or `https://opencode.yourdomain.ts.net` via Tailscale)
   - **Token**: `your-secret-fuzz-token`
5. Tap **Pair**. FuzzCode will verify health via `GET /api/v1/health` and store the token safely in your iOS Keychain.

---

## 3. Remote Execution Safety & Permissions

- When OpenCode attempts to execute potentially destructive shell commands (e.g. `npm install`, `rm -rf`, `git commit`), FuzzCode displays an interactive **Permission Gate**.
- You can inspect the exact command and arguments before tapping **Allow Once** or **Deny**.
- Git diffs can be viewed at any time by tapping **Diffs** in the top bar.
