# Roblox Studio and Creator Workflows

Read only the sections relevant to the current task.

## Open and identify a Place

1. Resolve the intended Rojo project or binary Place from repository evidence. Do not guess among similarly named candidates.
2. Build to a new candidate path when source changed or the existing artifact is open. If the change is source-only and more than one Studio check is expected, set up *Rojo live sync* instead and skip the per-change build.
3. Launch the absolute `rbxl` or `rbxlx` path directly. A visible Studio window is appropriate because later MCP or Computer Use steps interact with it.
4. List connected Studio instances and choose the ID whose name matches the exact artifact. Re-list after launch if registration is delayed.
5. Check Studio mode before each operation. Use Edit for persistent hierarchy inspection and Play for runtime behavior.

## Rojo live sync

Use this as the default verification loop when the source is Rojo-managed and the task needs more than one Studio check. It removes both the per-change build and the Studio relaunch. Reserve a built Place for verifying the artifact itself and for the final deliverable.

### 1. Resolve which binary actually runs

`rojo --version` reports whichever install `PATH` resolves first, which is not necessarily the one the project pins.

```bash
type -a rojo                      # list every candidate
~/.rokit/bin/rojo --version       # toolchain shim, run from the project root
```

The shim reads the toolchain manifest in the current directory, so run it from the project root or it resolves a different version. If two candidates appear, call the shim by path for the rest of the session rather than changing the user's `PATH` mid-task.

A CLI older than the Studio plugin fails at connect with `attempt to index number with 'protocolVersion'`. The plugin auto-updates, so the CLI is the side that falls behind.

### 2. Check the port

The default is 34872. If it is occupied, identify the owner before doing anything to it — it is often another project's live session.

```bash
netstat -ano | grep 34872
curl -s http://localhost:34872/api/rojo    # projectName tells you whose session it is
```

Use `--port` to move aside. Stop another session only when the user says to.

### 3. Start and verify the server

A listening log does not prove the right binary or project started. Check the API.

```bash
cd <project root> && ~/.rokit/bin/rojo serve <project file> --port 34872   # background
curl -s http://localhost:34872/api/rojo
```

Confirm `serverVersion` and `projectName` match expectations. Rojo 7.7 answers in msgpack, so the response looks partly binary; the two fields are still readable. Rojo 7.6 answers in plain JSON. Garbled output is not by itself a failure.

### 4. Connect

Connect is a Studio GUI action and cannot be issued through MCP. The plugin usually raises its own prompt per Studio window once a server is reachable (`Project '<name>' is serving at localhost:<port>. Would you like to connect?`). Click `Connect` with Computer Use, or hand the user the host and port.

Connect a **scratch** Place. Sync rewrites the mapped subtrees in the open DataModel; if that Place is the canonical artifact and anyone saves it, the file stops matching `rojo build` output and any recorded hash becomes wrong.

### 5. Confirm the sync landed

Check the tree and that extensions produced the intended classes.

```
mcp__Roblox_Studio__search_game_tree(path: "ServerScriptService", max_depth: 3)
```

`*.server.luau` becomes `Script`, `*.client.luau` becomes `LocalScript`, plain `*.luau` becomes `ModuleScript`. An empty mapped folder means the session is not connected.

### 6. Do not trust `require` in Edit after a sync

Rojo replaces `Source` on the existing `ModuleScript`. A module already required in the Edit DataModel stays cached, so `require` keeps returning the pre-sync table.

Measured on a live session: after editing one constant in a source file, the synced `Source` showed the new value about two seconds later while `require` in the same Edit DataModel still returned the old one. Starting Play, which builds a fresh DataModel, returned the new value.

Therefore:

- To prove a sync arrived, read `.Source` and match on the changed text.
- To observe behavior or constants, start Play. Do not conclude "sync is broken" from a stale `require`.

### Sync failure triage

| Observed | Cause | Action |
|---|---|---|
| `attempt to index number with 'protocolVersion'` | CLI older than the Studio plugin | Re-resolve the binary per step 1 and restart the server |
| `os error 10048` / bind failure | Port already bound | Identify the owner, then use another port |
| Connected but mapped folders are empty | Not synced, or a different Place is connected | Check which Studio window holds the session |
| `.Source` updated but `require` unchanged | Module cached in the Edit DataModel | Expected. Verify in Play |
| Canonical Place no longer matches its recorded hash | It was connected and saved from Studio | Rebuild it with `rojo build` while Studio is closed |

## Close a Place without saving

Do this yourself whenever an open Place blocks the next step — most often `rojo build` failing because Studio holds the file. Closing without saving is correct when the tracked source is authoritative: a live-synced DataModel and any test-only mutation are reproducible, and saving would diverge the file from `rojo build` output.

### Bringing the right window forward

This is where the procedure usually fails.

- **Never use `open_application` for this.** It opens a *new* Studio start-screen window and gives it focus. Beyond not switching windows, that stolen focus silently breaks simulated keyboard input into the Place you were testing — a character that stops responding to `W` after a Computer Use step is usually this, not a game bug.
- Clicking the taskbar, desktop, Start menu, or a file manager is refused unless the session was granted exactly `File Explorer`. That grant is click-only; typing into the shell stays blocked.
- Prefer the reverse move: close windows you no longer need until the target is the only Studio window left. One window makes both focus and keyboard injection unambiguous.
- Confirm the target from the title bar, which carries the full Place path.

### Procedure

1. List Studio instances and note the id and name of the one to close, so you can prove it disappears.
2. Take an **unscaled** screenshot and read the coordinates from it.
3. Confirm the title bar path matches the Place you intend to close.
4. Close the window (its `X`, or `File` / `ファイル` → close). Wait, then screenshot.
5. If a save prompt appears, choose **don't save** (`保存しない`). Do not press `Ctrl+S`, and do not click `Save to Roblox` / `Roblox に保存`, which publishes.
6. Prove the close from state, not from the click:

   ```bash
   ls <artifacts dir>/<place>.lock    # must be absent
   ```

   and re-list Studio instances — the id must be gone. Only then rebuild.

If the lock persists after the window is gone, Studio is still shutting down; wait and re-check before treating it as a failure.

### When not to close

Do not close a Place whose DataModel holds work with no source mapping — instances built by hand, imported models, or anything generated at runtime that the project does not reproduce. Save it first (*Save a Place to disk*), or leave it open and build to a candidate filename instead.

## Give a new Place ground before judging a fall

A Place produced from a Rojo project contains only the mapped subtrees, so there is usually no baseplate. The character spawns over nothing, falls, dies, respawns, and falls again.

**Read the console before adding anything.** In practice the more common cause is not a missing baseplate but a server script that aborts before it builds the arena. A single startup error can leave the world empty, the remotes uncreated, and the client blocked on `WaitForChild` — and dropping in a baseplate would hide all of it behind a floor. Fix the initialization error first, then Play again.

Symptoms worth separating:

| Observed | Likely cause | Action |
|---|---|---|
| Console shows an error from a server script during startup | Initialization aborted before world build | Fix the error; do not add ground |
| Console clean, `Humanoid:GetState()` is `Freefall`, `Position.Y` falling, no ground instance in `Workspace` | Genuinely no baseplate | Insert the baseplate |
| Character stands but nothing responds | Focus stolen from the Studio window | See *Close a Place without saving* → bringing the right window forward |

To insert the ground, use the asset-insert MCP tool with the asset id rather than browsing the Toolbox through the GUI:

```
insert_asset(assetId: "9261840032", assetName: "Grass base plate")
```

Then apply the imported-asset rule from the main skill: inspect descendants for `Script`, `LocalScript`, and `ModuleScript`, remove untrusted executable content, and keep only what the test needs. Play again and confirm the character reaches a standing state (`Running`) at a stable `Position.Y` before drawing any conclusion about gameplay.

Treat the baseplate as test scaffolding. Do not save it into a Place whose ground is supposed to come from the project, and remove it when the real world build is fixed.

## Edit inspection

Inspect the actual built artifact, not only source files.

- Confirm required services, folders, Remotes, scripts, models, Tools, Handles, attributes, and Place role or environment bindings.
- Count meaningful descendants when completeness matters, such as MeshParts, Motor6Ds, scripts, attachments, or UI controls.
- Check imported assets for `Script`, `LocalScript`, and `ModuleScript` descendants and for unexpected executable content.
- Do not mutate the Place merely to make an inspection pass.

## Play verification

1. Start Play and wait for the correct Client and Server DataModels.
2. Inspect console output before interpreting a frozen UI. Initialization may have stopped earlier on a service, configuration, or admission gate.
3. Use real UI, keyboard, mouse, touch, or controller input through Studio MCP when validating usability.
4. Measure the corresponding server-owned state and client presentation. Examples include unit position and speed, active gait and joints, equipped Tool count, attack declaration and adjudication, UI phase, and Remote payload receipt.
5. Capture a screenshot when appearance, camera framing, UI, or readability is part of the requirement.

When a production entry requires an unavailable platform service, an isolated harness may start the exact production composition for local behavior testing only if all of these are true:

- The limitation is identified and disclosed.
- The entry is disabled only in the in-memory test session.
- The harness uses the real product modules and contracts rather than reimplementing them.
- The test does not claim to prove the unavailable platform boundary.
- The entry and other temporary changes are restored after Play.

## Multi-Place and published services

- Roblox Studio playtesting does not perform real TeleportService transfers. Verify cross-Place Lobby-to-Match behavior only in a published development or staging Experience through the Roblox client.
- An unpublished local Place can fail before a Studio-only branch if it constructs MemoryStore, DataStore, MessagingService, or another published service during startup. Treat the first console failure as the current blocker; do not infer later code executed.
- A local preview may prove assignment creation, UI transitions, gameplay composition, or arrival validation independently. Label each proven boundary precisely.
- Never publish or alter a live Universe without explicit authorization.

## Creator Dashboard and browser settings

- Prefer a purpose-built API, connector, or CLI for stable structured changes.
- Use the in-app Browser when an authenticated web session is required; use Chrome when the task specifically depends on existing Chrome state or extensions.
- Inspect the current page and selected Experience, Universe, and Place before changing settings.
- Make the smallest requested mutation, then verify the persisted value or confirmation receipt.
- Do not expose credentials, access codes, cookies, or private identifiers in logs or evidence.

## Save a Place to disk

Use this whenever a Place must survive the current Studio process. Saving to a local file is not publishing.

### Why the GUI is required

Both in-process paths are unavailable, verified by measurement:

```
game:Save()      -> "Save is not a valid member of DataModel"
typeof(plugin)   -> "nil"          -- MCP script execution is not a plugin context
```

`SaveToRoblox` variants publish and are out of scope for a local save.

### Procedure

1. Verify the session is interactive before any GUI action.

   ```powershell
   quser                                   # STATE must be Active, not Disc
   Get-Process -Name RobloxStudioBeta | Select-Object Id, SessionId, MainWindowTitle
   ```

   Match the target window by the Place path in `MainWindowTitle` when several Studio processes are running.

2. Take an **unscaled** screenshot. Read every coordinate from it. A scaled capture uses a different coordinate frame, and hard-coded coordinates break across Studio versions, window positions, DPI settings, and UI languages.
3. Click `File` / `ファイル`, wait about two seconds, then screenshot the opened menu.
4. Read the item position from that second screenshot and click `Save to File` / `ファイルに保存`. `Save to Roblox` / `Roblox に保存` publishes and is adjacent in the same menu.
5. Handle any dialog (first save, save-as, overwrite confirmation) the same way: screenshot, locate, click. Confirm the path shown in the dialog before accepting an overwrite.
6. Prove the result from the filesystem.

   ```powershell
   $p = '<place path>'
   $f = Get-Item $p
   "path : $($f.FullName)"
   "bytes: $($f.Length)"
   "mtime: $($f.LastWriteTime)"
   "sha256: " + (Get-FileHash -Path $p -Algorithm SHA256).Hash
   "age_seconds: " + [math]::Round(((Get-Date) - $f.LastWriteTime).TotalSeconds, 1)
   ```

A closed menu is not evidence. Only a refreshed `mtime` with a plausible `age_seconds` is.

Reference measurement from a successful run:

```
path : C:\Users\Administrator\AppData\Local\ClaudeRobloxMvpEvidence\places\RCR_qa_01.rbxlx
bytes: 1786267
mtime: 08/21/2026 07:34:23
sha256: 5184F3B14897468182B0043A45E63ED7A5E5FBF5296021A877E98AA0B7FD3340
age_seconds: 14.7
```

### Failure triage

| Observed message | Cause | Action |
|---|---|---|
| `desktopCapturer returned no screen sources` | Desktop session is `Disc`; no screen exists | Report the blocker and request reconnection. Do not switch sessions. |
| `blocked by UIPI` | Studio runs elevated; lower-integrity input cannot reach it | Report and request a manual `Ctrl+S`. Do not restart Studio; the unsaved DataModel would be lost. |
| Menu opens but the wrong item reacts | Reused coordinates | Re-read positions from the opened-menu screenshot. |
| `mtime` unchanged | The save never executed | Treat as failure and repeat the procedure. Do not claim a save because a click was issued. |

### What a save does not replace

A saved Place is convenience, not the source of truth. Keep tracked source and any documented restore procedure authoritative, and do not skip source verification because the binary was saved.

## Cleanup checklist

- Stop Play.
- Restore disabled scripts, temporary attributes, mock services, injected instances, and client listeners.
- Revert any probe edit made only to prove a live sync, and confirm it is gone from both the source tree and the synced `Source`.
- Stop the `rojo serve` session when the task is done, and leave the connected scratch Place unsaved. Produce the canonical artifact with `rojo build` while Studio is closed, then record its hash. Close the Place yourself (*Close a Place without saving*) rather than waiting on the user.
- Remove any baseplate inserted as scaffolding, and any other imported asset kept only for the test.
- Leave binary artifacts unsaved when all mutations were test-only. When real work exists only in the DataModel, save the Place first (*Save a Place to disk*) and record path, bytes, SHA-256, and save time.
- Re-run relevant source tests and build checks after implementation changes.
- Record exact artifact identity and distinguish local, Studio, published-staging, and production evidence.
