---
name: roblox-dev-skill
description: Implement, debug, and verify Roblox games end to end from a local workspace using Luau or Rojo, Roblox Studio MCP, direct rbxl or rbxlx launches, Computer Use, and browser-based Creator settings. Use for Roblox gameplay, Place, UI, asset, Studio QA, and configuration work; do not use for concept-only game design or documentation.
---

# Roblox Development

Complete the user's scoped Roblox change as far as the available local and interactive tools allow. Do not stop merely because a required step uses Roblox Studio or a web UI.

## Choose the authoritative surface

- Inspect repository instructions, `git status`, Rojo project files, Place topology, and existing Studio instances before editing.
- Prefer tracked Luau, model JSON, and Rojo project files as source of truth. Treat generated `rbxl` or `rbxlx` files as build artifacts unless the user explicitly makes a binary Place the source of truth.
- Preserve unrelated work. Never overwrite an artifact currently open in Studio; build to a distinct candidate filename. Prefer live sync over accumulating candidate builds when the change is source-only.
- Use direct Studio edits only when the task requires binary-only content or no mapped source exists. Synchronize intentional edits back to the repository when a source mapping exists.

## Use the most capable in-scope tool

1. Use local search, patching, tests, and Rojo builds for source-controlled work. When the source is Rojo-managed and the task needs more than one Studio check, keep a connected `rojo serve` session instead of building a candidate Place per change. See *Iterate with Rojo live sync*.
2. Use Roblox Studio MCP for DataModel inspection, exact instance properties, Luau execution, Play control, simulated player input, console output, and screenshots.
3. Launch a local `rbxl` or `rbxlx` directly when the built artifact itself must be verified, then select the exact Studio instance ID rather than relying on window focus.
4. When an OS-level dialog or Studio control is unavailable through MCP, invoke the available Computer Use skill and operate the UI. Restore focus and re-inspect state after GUI actions. **Saving a Place is one of these controls**: `game:Save()` does not exist on `DataModel` and MCP script execution has no `plugin` global, so File → Save to File through the GUI is the only path. See *Save a Place to disk* below.
5. When Creator Dashboard or another web setting is necessary, invoke the available in-app Browser or Chrome skill. Prefer an authenticated connector or API when it provides the same operation more reliably.

Read [references/studio-workflows.md](references/studio-workflows.md) whenever the task opens a Place, performs Studio Play verification, changes Creator settings, or investigates a Studio-only failure.

## Implement and verify the real path

- Follow existing server-authority, Remote, persistence, matchmaking, and client-presentation boundaries. Do not replace a product path with a local shortcut merely because it is easier to test.
- For imported Toolbox or Creator Store assets, inspect descendants and source containers. Remove untrusted scripts, record provenance or attribution, and retain only the content needed by the game.
- Validate in layers appropriate to the change: source compile or unit tests, Rojo build, Studio Edit inspection, Studio Play behavior, actual user input, and authoritative server/client state.
- Exercise the user's interaction rather than only calling an internal function. Pair observable input with state evidence such as motion, animation state, Remote receipt, server adjudication, UI phase, or persistence record.
- Distinguish a Studio simulation from a real platform path. TeleportService and some published services require a published Experience and Roblox client; never report an isolated harness as a successful cross-Place transfer.

## Iterate with Rojo live sync

A connected `rojo serve` session removes the per-change build and Studio relaunch from the verification loop. Prefer it whenever the source is Rojo-managed and you expect to check behavior in Studio more than once. Build a Place only to verify the artifact itself or to produce a deliverable, and keep that build as the canonical artifact.

Three failure modes make this unreliable when ignored. Read [references/studio-workflows.md](references/studio-workflows.md) before the first connect.

- **The `rojo` that runs may not be the one you checked.** More than one install can sit on `PATH`. A CLI older than the Studio plugin fails at connect on a protocol mismatch. Resolve the binary explicitly and confirm the running server reports the expected version and project before asking for a connection.
- **Connect a scratch Place, not the canonical artifact.** Sync rewrites the mapped subtrees in the open DataModel. Saving a connected canonical Place diverges the file from `rojo build` output and invalidates any recorded hash.
- **Edit-mode `require` keeps returning the pre-sync module.** Confirm a sync landed by reading `.Source`, and verify values in Play, which builds a fresh DataModel.

## Save a Place to disk

Whenever the work requires a saved Place, perform the save yourself through the Studio GUI. Saving to a local file is not publishing and stays inside the local-testing boundary.

Save when unsaved DataModel state is the only copy of real work: modules applied through MCP, a world built at runtime, imported or generated instances, or any run that will outlive the current Studio process. Do not save a Place whose only changes are test-only mutations; that rule from *Finish cleanly* still holds.

1. Confirm the desktop session is interactive. If `quser` reports `Disc`, no screen exists, screen capture fails with `desktopCapturer returned no screen sources`, and input cannot land. Report the blocker and ask the user to reconnect rather than switching sessions yourself.
2. Take an **unscaled** screenshot and read the menu coordinates from it. Coordinates from a scaled capture do not map to click coordinates. Never reuse hard-coded coordinates; they shift with Studio version, window position, DPI, and UI language.
3. Confirm the target window by its title bar path, then click `File` (`ファイル`), wait, and screenshot again.
4. Read the item position from the **opened menu** screenshot, then click `Save to File` (`ファイルに保存`). Do not click `Save to Roblox` (`Roblox に保存`); it publishes and sits adjacent in the same menu.
5. Prove the save from the file, not from the closed menu. Read `Length`, `LastWriteTime`, and SHA-256, and confirm the timestamp matches this action.

```powershell
$p = '<place path>'
$f = Get-Item $p
"bytes: $($f.Length)"; "mtime: $($f.LastWriteTime)"
"sha256: " + (Get-FileHash -Path $p -Algorithm SHA256).Hash
"age_seconds: " + [math]::Round(((Get-Date) - $f.LastWriteTime).TotalSeconds, 1)
```

If input is rejected with `blocked by UIPI`, Studio is running elevated and the lower-integrity input path cannot reach it. Report it and ask for a manual `Ctrl+S`. Do not restart Studio to work around it; that discards the unsaved DataModel you were trying to preserve.

## External-change boundary

- Local implementation and local Studio testing are allowed when they are within the user's requested project.
- Publishing, changing live Creator settings, creating credentials, spending currency, or affecting production data requires explicit authorization for that external mutation.
- If private staging publication is explicitly requested and the dedicated staging skill is available, use it rather than improvising a production-like workflow.
- Before a browser mutation, inspect the current setting and exact target. Afterward, verify the saved value or platform receipt.

## Finish cleanly

- Stop Play sessions and restore any entry script, attribute, mock, or test instrumentation changed only for verification. Do not save test-only mutations into the Place. Revert probe edits made only to prove a live sync, and stop a `rojo serve` session you started.
- Decide explicitly whether the Place must be saved. If it must, save it through the GUI path above and record the path, byte size, SHA-256, and save time. If it could not be saved, say why and state whether the work is reproducible from tracked source.
- Report which exact artifact and Studio instance were tested, what input was performed, and what authoritative evidence resulted.
- Audit every requested requirement. State partial failures plainly; passing asset presence does not prove usability, and passing Studio does not prove published multi-Place behavior.
