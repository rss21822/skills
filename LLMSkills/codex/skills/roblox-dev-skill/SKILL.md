---
name: roblox-dev-skill
description: Implement, debug, and verify Roblox games end to end from a local workspace using Luau or Rojo, Roblox Studio MCP, direct rbxl or rbxlx launches, Computer Use, and browser-based Creator settings. Use for Roblox gameplay, Place, UI, asset, Studio QA, and configuration work; do not use for concept-only game design or documentation.
---

# Roblox Development

Complete the user's scoped Roblox change as far as the available local and interactive tools allow. Do not stop merely because a required step uses Roblox Studio or a web UI.

## Choose the authoritative surface

- Inspect repository instructions, `git status`, Rojo project files, Place topology, and existing Studio instances before editing.
- Prefer tracked Luau, model JSON, and Rojo project files as source of truth. Treat generated `rbxl` or `rbxlx` files as build artifacts unless the user explicitly makes a binary Place the source of truth.
- Preserve unrelated work. Never overwrite an artifact currently open in Studio; build to a distinct candidate filename.
- Use direct Studio edits only when the task requires binary-only content or no mapped source exists. Synchronize intentional edits back to the repository when a source mapping exists.

## Use the most capable in-scope tool

1. Use local search, patching, tests, and Rojo builds for source-controlled work.
2. Use Roblox Studio MCP for DataModel inspection, exact instance properties, Luau execution, Play control, simulated player input, console output, and screenshots.
3. Launch a local `rbxl` or `rbxlx` directly when the built artifact itself must be verified, then select the exact Studio instance ID rather than relying on window focus.
4. When an OS-level dialog or Studio control is unavailable through MCP, invoke the available Computer Use skill and operate the UI. Restore focus and re-inspect state after GUI actions.
5. When Creator Dashboard or another web setting is necessary, invoke the available in-app Browser or Chrome skill. Prefer an authenticated connector or API when it provides the same operation more reliably.

Read [references/studio-workflows.md](references/studio-workflows.md) whenever the task opens a Place, performs Studio Play verification, changes Creator settings, or investigates a Studio-only failure.

## Implement and verify the real path

- Follow existing server-authority, Remote, persistence, matchmaking, and client-presentation boundaries. Do not replace a product path with a local shortcut merely because it is easier to test.
- For imported Toolbox or Creator Store assets, inspect descendants and source containers. Remove untrusted scripts, record provenance or attribution, and retain only the content needed by the game.
- Validate in layers appropriate to the change: source compile or unit tests, Rojo build, Studio Edit inspection, Studio Play behavior, actual user input, and authoritative server/client state.
- Exercise the user's interaction rather than only calling an internal function. Pair observable input with state evidence such as motion, animation state, Remote receipt, server adjudication, UI phase, or persistence record.
- Distinguish a Studio simulation from a real platform path. TeleportService and some published services require a published Experience and Roblox client; never report an isolated harness as a successful cross-Place transfer.

## External-change boundary

- Local implementation and local Studio testing are allowed when they are within the user's requested project.
- Publishing, changing live Creator settings, creating credentials, spending currency, or affecting production data requires explicit authorization for that external mutation.
- If private staging publication is explicitly requested and the dedicated staging skill is available, use it rather than improvising a production-like workflow.
- Before a browser mutation, inspect the current setting and exact target. Afterward, verify the saved value or platform receipt.

## Finish cleanly

- Stop Play sessions and restore any entry script, attribute, mock, or test instrumentation changed only for verification. Do not save test-only mutations into the Place.
- Report which exact artifact and Studio instance were tested, what input was performed, and what authoritative evidence resulted.
- Audit every requested requirement. State partial failures plainly; passing asset presence does not prove usability, and passing Studio does not prove published multi-Place behavior.
