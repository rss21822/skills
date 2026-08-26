# Roblox Studio and Creator Workflows

Read only the sections relevant to the current task.

## Open and identify a Place

1. Resolve the intended Rojo project or binary Place from repository evidence. Do not guess among similarly named candidates.
2. Build to a new candidate path when source changed or the existing artifact is open.
3. Launch the absolute `rbxl` or `rbxlx` path directly. A visible Studio window is appropriate because later MCP or Computer Use steps interact with it.
4. List connected Studio instances and choose the ID whose name matches the exact artifact. Re-list after launch if registration is delayed.
5. Check Studio mode before each operation. Use Edit for persistent hierarchy inspection and Play for runtime behavior.

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
- Leave binary artifacts unsaved when all mutations were test-only. When real work exists only in the DataModel, save the Place first (*Save a Place to disk*) and record path, bytes, SHA-256, and save time.
- Re-run relevant source tests and build checks after implementation changes.
- Record exact artifact identity and distinguish local, Studio, published-staging, and production evidence.
