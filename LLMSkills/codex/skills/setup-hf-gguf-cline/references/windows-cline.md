# Windows GGUF, llama.cpp, and Cline reference

## Contents

- Download and runtime decisions
- Launcher requirements
- Cline and MCP configuration
- Validation sequence
- Troubleshooting map
- Security constraints

## Download and runtime decisions

Use official sources:

- Hugging Face CLI: https://huggingface.co/docs/huggingface_hub/en/guides/cli
- llama.cpp releases: https://github.com/ggml-org/llama.cpp/releases
- llama.cpp server: https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
- llama.cpp function calling: https://github.com/ggml-org/llama.cpp/blob/master/docs/function-calling.md
- Cline OpenAI Compatible provider: https://docs.cline.bot/provider-config/openai-compatible

Download GGUF for llama.cpp. A Transformers `safetensors` repository is not directly interchangeable with a GGUF file. For split files such as `model-00001-of-00003.gguf`, download every part into one directory.

Inspect GPU names with:

```powershell
Get-CimInstance Win32_VideoController | Select-Object Name,AdapterRAM,DriverVersion
```

Inspect drive space with:

```powershell
Get-PSDrive -PSProvider FileSystem | Select-Object Name,Used,Free,Root
```

Use the official release asset appropriate to the detected backend. Do not guess an asset URL from an old version.

## Launcher requirements

Create a PowerShell launcher in the model directory. Use absolute paths and avoid relying on the current directory. A typical argument set is:

```powershell
$arguments = @(
    '-m', ('"' + $modelPath + '"'),
    '--alias', $modelAlias,
    '--host', '127.0.0.1',
    '--port', '8080',
    '--ctx-size', '32768',
    '--parallel', '1',
    '--jinja',
    '--flash-attn', 'on',
    '--metrics'
)
```

Run `llama-server.exe --help` before using the arguments. Remove unsupported flags rather than silently ignoring errors. Redirect stdout and stderr to separate log files and save the returned process ID.

Before restart, resolve the process ID from the known PID file and confirm its executable path is the intended `llama-server.exe`. Stop only that exact process. Verify that port `8080` is free before launching.

Use `--alias` so Cline receives a stable model ID rather than a full Windows path. Retrieve it from:

```powershell
Invoke-RestMethod 'http://127.0.0.1:8080/v1/models'
```

### Context size

Cline adds its system prompt, tool schemas, workspace context, history, and the user's message. A short user message can therefore require tens of thousands of tokens.

Start at `32768`. Increase to `65536`, `98304`, or another supported value only when:

- The model's `n_ctx_train` or documentation supports it.
- RAM/VRAM and KV cache fit.
- Startup logs confirm the requested `n_ctx_slot`.
- `/health` becomes `ok` and a real Cline request succeeds.

Use `--parallel 1` to avoid multiplying context memory for a single-user setup. Reducing KV cache precision saves memory but aggressive quantization can reduce tool-calling reliability.

### Tool calling

Start the server with `--jinja`. Inspect:

```powershell
Invoke-RestMethod 'http://127.0.0.1:8080/props'
```

Look for `chat_template_tool_use` or a known tool-aware template. If absent, use a model-specific official template when available. A generic ChatML override is only a fallback and must be tested.

An abliterated or reasoning model may chat well but still fail Cline tool calls. Treat tool-call success as a separate acceptance test.

## Cline and MCP configuration

Use the Cline UI for provider configuration. Values:

```text
Provider: OpenAI Compatible
Base URL: http://127.0.0.1:8080/v1
API Key: local
Model ID: value returned by /v1/models
Context Window: same as llama-server --ctx-size
Image Support: false unless a matching multimodal projector is loaded
```

Do not set Cline's context window above the server value. Create a new task after changing the context size because previous task history remains large.

For VS Code extension MCP settings, discover rather than assume:

```powershell
Get-ChildItem 'C:\Users\<user>\AppData\Roaming' -Recurse `
  -Filter cline_mcp_settings.json -ErrorAction SilentlyContinue
```

Common editor roots include `Code`, `Code - Insiders`, and `Cursor`. Preserve existing `mcpServers` entries and validate JSON after editing.

For text-only models, configure browser MCPs to omit image responses. Do not enable Playwright `vision` capability. Browser screenshots, pasted images, and image-bearing tool results can trigger a multimodal request even when the user typed only text.

## Validation sequence

Perform tests in this order:

1. Process exists and expected executable path matches.
2. Port is listening only on the intended address.
3. `/health` is `ok`, not loading/503.
4. `/v1/models` returns the configured model ID.
5. Plain text completion succeeds.
6. UTF-8 Japanese input and output succeed.
7. Function/tool call returns structured `tool_calls`.
8. Cline fresh task succeeds without MCP.
9. One MCP server initializes and lists tools.
10. One read-only MCP call succeeds.

## Troubleshooting map

### `[OPENAI] Connection error`

This label refers to Cline's OpenAI-compatible provider, not necessarily OpenAI cloud. Check the local server first:

```powershell
Get-Process llama-server -ErrorAction SilentlyContinue
Get-NetTCPConnection -LocalPort 8080 -ErrorAction SilentlyContinue
Invoke-RestMethod 'http://127.0.0.1:8080/health'
```

If Windows restarted, a manually started server is no longer running. Restart it or, only on request, configure a scoped logon task.

### `request (...) exceeds the available context size`

The entire Cline prompt exceeds `n_ctx`, not merely the visible user text. Increase server context within supported memory, start a fresh Cline task, remove unnecessary context, or reduce enabled tool schemas. Lowering only output tokens does not fix a prompt already larger than `n_ctx`.

### `image input is not supported ... provide the mmproj`

The request contains an image but the loaded model is text-only or lacks its projector. Disable Cline image support and omit image responses from MCP. If vision is required, obtain the exact matching multimodal model/projector pair and launch with the documented `--mmproj` option.

### MCP initializes but the model does not call it

Verify ordinary function calling first. Check `--jinja`, `/props`, model chat template, Cline tool support settings, and whether the model emits valid `tool_calls`. Reduce the number and complexity of MCP tools. Do not blame the MCP transport when the model never produced a tool call.

### Server stops, hangs, or returns 503

- 503 immediately after launch usually means model loading; wait and inspect logs.
- Process disappearance without a clean shutdown can indicate reboot, forced termination, or memory pressure.
- Reduce context, use `--parallel 1`, lower GPU offload if VRAM is insufficient, and retest.
- Cap output tokens to avoid runaway generation.

### Japanese becomes question marks or mojibake

Use UTF-8 for PowerShell input/output and HTTP JSON bodies:

```powershell
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
```

Use `ConvertTo-Json` and `Invoke-RestMethod` rather than manually concatenating JSON.

### Model ID mismatch or 404

Use the Base URL ending in `/v1`. Obtain the ID from `/v1/models`; do not assume the GGUF filename and server ID are identical when `--alias` is present.

## Security constraints

- Bind local servers to `127.0.0.1`.
- Do not expose llama.cpp through a public tunnel by default.
- Do not store Hugging Face tokens in scripts, JSON, Git, or logs.
- Leave Cline automatic approval disabled for destructive commands and MCP writes until the model is proven reliable.
- Confirm licenses and gated-model terms before downloading or redistributing weights.

