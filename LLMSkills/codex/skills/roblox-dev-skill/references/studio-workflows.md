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

## Cleanup checklist

- Stop Play.
- Restore disabled scripts, temporary attributes, mock services, injected instances, and client listeners.
- Leave binary artifacts unsaved when all mutations were test-only.
- Re-run relevant source tests and build checks after implementation changes.
- Record exact artifact identity and distinguish local, Studio, published-staging, and production evidence.
