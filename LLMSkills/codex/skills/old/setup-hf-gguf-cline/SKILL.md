---
name: setup-hf-gguf-cline
description: Download Hugging Face GGUF language models to Windows, run them through llama.cpp's OpenAI-compatible server, configure the Cline VS Code or Cursor extension, and verify chat, coding, tool calling, and optional MCP use. Use for Hugging Face model URLs, local GGUF deployment, llama-server setup, Cline OpenAI Compatible configuration, or errors involving connection refusal, context limits, image/mmproj input, tool calls, encoding, and server startup.
---

# Set up a Hugging Face GGUF model for Cline

Complete the workflow end to end. Prefer discovery and validation over hard-coded paths or model assumptions.

## 1. Establish inputs and constraints

Determine from the request or local machine:

- Hugging Face repository ID or model URL
- Exact GGUF filename; include every part for split GGUFs
- Destination directory
- Available disk, RAM, GPU, and VRAM
- Text-only or multimodal use
- Desired editor: VS Code or Cursor
- Whether coding tools or MCP tools must work

Use the user-selected destination. If none is given, ask before downloading multi-gigabyte files. Read the model card and license. Treat gated-model authentication as user-owned; never print or persist tokens in project files.

## 2. Inspect before changing

Check existing files, running processes, ports, and installations. Reuse a compatible `hf`, `llama-server.exe`, model file, and Cline installation. Preserve unrelated files and settings.

On Windows, inspect hardware and capacity with read-only PowerShell commands. Confirm free disk space exceeds the download size plus working headroom.

## 3. Download the model

Use the current `hf` CLI, not deprecated `huggingface-cli`.

1. Run `hf --help`.
2. Install `hf` from the official Hugging Face method only when missing.
3. For gated repositories, use `hf auth login` without exposing the token.
4. Preview size first:

```powershell
hf download OWNER/REPO MODEL.gguf --local-dir 'D:\Models\ModelName' --dry-run
```

5. Download to the exact destination:

```powershell
hf download OWNER/REPO MODEL.gguf --local-dir 'D:\Models\ModelName'
```

Download a matching `mmproj*.gguf` only for a multimodal model that documents it. Do not invent or mix projector files from another model.

## 4. Prepare llama.cpp

Use a recent official llama.cpp Windows release matching the machine backend. Prefer CUDA for supported NVIDIA GPUs, Vulkan or another documented backend when needed, and CPU as fallback.

Run `llama-server.exe --help` because options change. Create a start script in the model directory with absolute paths, logs, a PID file, and these baseline properties:

- Bind to `127.0.0.1`, not `0.0.0.0`.
- Use a stable port such as `8080` after verifying it is free.
- Set `--alias` to a short stable model ID for Cline.
- Set `--parallel 1` for one local Cline user unless concurrency is required.
- Enable `--jinja` for OpenAI-style tool calling.
- Start with `--ctx-size 32768`; raise only after checking model metadata and memory.
- Enable flash attention only when supported.
- Add `--mmproj` only for a matching multimodal projector.
- Add model-specific flags such as MTP/speculative decoding only when the model card or runtime confirms them.

Do not expose an unauthenticated llama.cpp endpoint beyond localhost. If remote access is explicitly requested, add authentication, firewall restrictions, and TLS before changing the bind address.

## 5. Validate the server before Cline

Start the server hidden, wait through model loading, then verify:

1. `GET http://127.0.0.1:8080/health` returns `{"status":"ok"}`.
2. `GET http://127.0.0.1:8080/v1/models` returns the expected model ID.
3. A short `/v1/chat/completions` request returns correct text.
4. When tools or MCP are required, `/props` exposes a tool-aware chat template and a test request returns `tool_calls`.

Run the bundled checker:

```powershell
powershell -ExecutionPolicy Bypass -File '<skill-dir>\scripts\test-openai-compatible.ps1' `
  -BaseUrl 'http://127.0.0.1:8080/v1' -ApiKey 'local'
```

Do not proceed to MCP until ordinary chat and tool calling pass.

## 6. Configure Cline

Install or reuse the official Cline extension. Configure through Cline's settings UI instead of editing undocumented extension databases:

- API Provider: `OpenAI Compatible`
- Base URL: `http://127.0.0.1:8080/v1`
- API Key: `local` or another non-secret placeholder when the local server has no key
- Model ID: exact value returned by `/v1/models`, preferably the `--alias`
- Context Window: exact server `--ctx-size`, never an optimistic model-card value
- Max Output Tokens: begin with `4096` or `8192`
- Image Support: off for text-only models
- Computer/Tool Use: enable only after the tool-call test passes

Use a fresh Cline task for the first test. Ask it to return a short exact phrase, then perform a small read-only coding task. Only then test file edits or commands.

## 7. Add MCP only after base validation

MCP depends on reliable tool calling. Keep the initial MCP tool set small. For Playwright with a text-only model, return structured snapshots and omit image responses:

```json
{
  "mcpServers": {
    "playwright": {
      "type": "stdio",
      "command": "npx",
      "timeout": 30,
      "args": ["-y", "@playwright/mcp@latest", "--image-responses", "omit"],
      "disabled": false
    }
  }
}
```

Locate Cline's actual MCP settings file rather than assuming a path. Reload the MCP server or editor, verify MCP initialization, then test one read-only navigation.

## 8. Verify persistence and handoff

Confirm the start script, PID, logs, port, health, model ID, actual context size, and Cline settings. Explain that a manually launched server stops after Windows restarts. Create auto-start only when the user explicitly requests it.

Report exact paths and results. Never claim completion from configuration alone; verify an actual Cline response.

## Detailed guidance

Read [references/windows-cline.md](references/windows-cline.md) when selecting a llama.cpp build, writing a launcher, configuring Cline/MCP paths, sizing context, or diagnosing failures.

