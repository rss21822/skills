---
name: rojo-studio-sync
description: Configure and restart Rojo 7.7 for a Roblox project, pin the Rokit tool version, validate default.project.json, verify the Rojo HTTP endpoint and build output, and optionally inspect synchronization in Roblox Studio through its MCP tools. Use when asked to set up Rojo, reconnect Studio, repeat the localhost Rojo configuration, fix a stale Rojo server, or confirm that local src content is synchronized.
---

# Rojo Studio Sync

Configure the current Roblox project for Rojo 7.7 and verify the complete local-to-Studio path.

## Run

1. Confirm the working directory contains `default.project.json` and `rokit.toml`.
2. Run:

```powershell
& "$env:USERPROFILE\.codex\skills\rojo-studio-sync\scripts\setup-rojo.ps1" `
  -ProjectRoot (Get-Location).Path
```

3. Report the version, port, PID, HTTP status, and build result.
4. Tell the user to connect the Studio Rojo 7.7 plugin to host `localhost` and port `34872`.

Use `-Port` only when the requested port differs. Keep version `7.7.0`; this skill is version-specific.

## Verify Studio

When Roblox Studio MCP tools are available:

1. Call `list_roblox_studios`.
2. Set the intended instance active before inspection.
3. Confirm Edit mode.
4. Read `default.project.json`.
5. Inspect each mapped Studio service and compare its children with the local paths.
6. Check that the Studio Rojo plugin is version 7.7.

Do not claim Studio synchronization from the HTTP check alone. Distinguish:

- Server ready: Rojo process listens and `/api/rojo` returns HTTP 200.
- Build valid: `rojo build` succeeds.
- Studio synchronized: mapped instances are present in the active Studio DataModel.

## Rojo 7.7 Notes

Treat `/api/rojo` as a binary response. Do not parse it as JSON. An HTTP 200 response is the readiness check.

Do not stop every Rojo process. Stop only the Rojo process listening on the selected port.
