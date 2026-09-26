# Private staging publication workflow

Use this workflow for production-like Roblox testing without Production exposure.

## 1. Establish the target and execution boundary

Verify that the requested target is a dedicated staging Experience, not Production. Invocation for a project authorizes discovery, local builds, validation, and read-only inspection without further questions; cloud mutations wait for the single release confirmation in section 4. Resolve from repository-owned configuration or Creator Dashboard evidence (read through Claude in Chrome or the built-in browser):

- creator or Group ID;
- staging Universe ID;
- start/Lobby Place ID;
- Match and other Place IDs;
- environment marker;
- DataStore, MemoryStore queue, MessagingService topic, analytics, and receipt namespaces;
- current audience and collaborator access;
- current published Place versions;
- known-good rollback artifacts or versions.

Stop if any ID is guessed, a staging resource aliases Production, the target audience is Public, or the rollback target is unknown.

For a multi-Place game, verify the Lobby is the start Place and Match direct access is restricted as intended. A Private Experience is playable only by its owner or users with Edit permission. Keep it Private during this workflow; Limited audience is out of scope unless the user's original request explicitly includes it.

## 2. Prepare a production-like but isolated binding

Keep runtime behavior production-like while resources remain staging-only:

- use separate Universe and Place IDs;
- use a staging-only persistent store name and queue/topic namespaces;
- set explicit environment and Place-role markers in the built artifacts;
- use the same Lobby-to-reserved-Match topology as production;
- hide development purchase shortcuts and fail closed when real product configuration is absent;
- do not copy Production secrets, DataStore names, product IDs, or traffic settings.

Review every environment-specific value before building. A build labeled `staging` is not sufficient evidence if its embedded IDs point elsewhere.

## 3. Freeze and validate the candidate

Record the source commit and dirty-worktree state (`git status`, `git rev-parse HEAD`). Preserve unrelated user changes.

Run the repository's registered validation path. At minimum, validate:

- every Rojo project build required by the product;
- compilation of product Luau sources;
- the full automatic suite;
- environment-binding tests;
- Studio Edit mapping for each published Place (Studio MCP: `search_game_tree`, `inspect_instance`, `script_read`);
- role/environment attributes, entries, RemoteEvents, and configuration tree.

Build separate immutable artifacts for each Place role. Compute SHA-256 hashes (`sha256sum`, or `certutil -hashfile <path> SHA256` on Windows) and file sizes. Do not publish an artifact that changed after hashing.

## 4. Freeze the release manifest and confirm once

Before publishing, prepare and internally verify an evidence record containing:

- environment and creator;
- source commit;
- artifact paths and SHA-256 hashes;
- Universe and Place IDs;
- previous published versions;
- intended publish order;
- publishing route (Studio or Open Cloud);
- audience and Studio API Access state, plus any Dashboard setting change you intend to make;
- known-good rollback targets;
- local and Studio validation results;
- pending human/runtime checks.

Do not include credentials or reserved-server access codes.

Then ask the user once in chat, showing a compact version of the manifest: target names and IDs, artifact hashes, previous versions, order, route, setting changes, and that the audience stays Private. Wait for a clear yes. An explicit instruction earlier in the current conversation to publish this build to the private staging target without further confirmation also counts; print the manifest anyway. The approval covers only the listed actions.

## 5. Select an authorized publishing route

Recompute hashes and recheck target identity immediately before each publish; abort rather than guess if either changed unexpectedly.

### Preferred: authenticated Studio

Authenticated Studio `Publish to Roblox As...` needs no API key. Open the frozen candidate artifact in Studio, confirm with Studio MCP (`list_roblox_studios`, `get_studio_state`, `inspect_instance`) that the loaded world's role/environment markers and embedded sources match the candidate, then drive the dialog with Computer Use:

1. `request_access` for Roblox Studio, then take a fresh screenshot.
2. Open `File > Publish to Roblox As...`, select the staging creator, Experience, and target Place.
3. Zoom into the dialog and verify the creator, Experience name, and Place name/ID against the manifest before clicking Overwrite.
4. Wait for completion and read the resulting state; record what the dialog reported.

Do not claim a binary file was uploaded when publishing the Studio data model. If Studio is signed out or the dialog shows an unexpected target, stop that route rather than signing in or picking a different target.

### Alternative: Open Cloud Place Publishing

Use only a temporary API key that the user created, restricted to the target staging Experience with `universe-places` Write permission and the shortest practical lifetime. The user exposes it as an environment variable (for example `ROBLOX_STAGING_PUBLISH_KEY`) before starting the session. Check only that it is set, never its value:

```bash
[ -n "${ROBLOX_STAGING_PUBLISH_KEY:-}" ] && echo "key set" || echo "key missing"
```

The current documented endpoint is:

```text
POST https://apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions?versionType=Published
```

Send the file with the key referenced by variable, without `-v` or any option that prints request headers:

```bash
curl -sS -X POST \
  "https://apis.roblox.com/universes/v1/${UNIVERSE_ID}/places/${PLACE_ID}/versions?versionType=Published" \
  -H "x-api-key: ${ROBLOX_STAGING_PUBLISH_KEY}" \
  -H "Content-Type: application/xml" \
  --data-binary @"${ARTIFACT}" \
  -w '\nHTTP %{http_code}\n'
```

Use `Content-Type: application/xml` for `.rbxlx` and `application/octet-stream` for `.rbxl`. A success response includes `versionNumber`. Recheck the official Roblox Place Publishing guide if the endpoint or permissions appear to have changed. Never read the key from a file into chat, write it to disk, or pass it on a command line that is logged in evidence.

## 6. Publish in dependency-safe order

For Lobby-to-Match topology:

1. publish Match first;
2. verify the response and new Match version;
3. publish Lobby/start Place second;
4. verify the response and new Lobby version.

This avoids exposing a new Lobby that routes into an old Match build. Do not continue to Lobby after a Match publish failure or ambiguous response. Reconcile an ambiguous result from Dashboard/version history before retrying; blind retry may create extra versions.

After approval, continue automatically from Match upload to Lobby and any other in-scope Place uploads, and cloud verification. Neither opening the publish dialog nor successfully uploading Match is a handoff point.

## 7. Verify the cloud state

After publication, read (without changing) in Creator Dashboard:

- confirm both new versions;
- confirm creator, Universe, and Place identity;
- confirm the Experience remains Private;
- confirm Studio API Access has the approved state;
- confirm Match direct access and maximum-player settings;
- open the Experience page with the authorized owner/test account and confirm the Play action;
- record UTC timestamps and published version numbers.

If a Dashboard setting differs from the approved state, change it only if that change was listed in the approved manifest; otherwise report it and ask.

If Open Cloud was used, tell the user the exact key name to delete after cloud verification or an aborted attempt. When browser access is available, confirm afterward that the key is absent from the key list. Key deletion does not replace publication verification.

## 8. Run an external-client smoke

Use the Roblox Player, not Studio, because TeleportService, reserved servers, MemoryStore, and live persistence need a published environment. Launch it from the staging Experience page, then drive it with Computer Use (`request_access` for the Roblox Player app). Save screenshots with `save_to_disk` as evidence, and read client/server output from the in-game Developer Console when available.

For a multi-Place combat game, minimally verify:

1. owner enters the Lobby start Place;
2. authoritative profile/loadout/meta state becomes ready;
3. Training or equivalent solo mode queues successfully;
4. the client teleports to a reserved Match Place;
5. match role/environment/build identity are correct;
6. one match reaches Result;
7. rematch behavior is checked if in scope;
8. Return sends the player to Lobby;
9. profile/session state survives the round trip without duplicate lock or reward;
10. server/client logs show no release-blocking errors.

Record client version, device/OS, account role, start/end times, Place versions, and observed result. A Player crash, login limitation, or remote-desktop incompatibility is an environment blocker, not proof of a game defect or a PASS. If the Player asks for sign-in, ask the user to sign in; never enter credentials.

## 9. Decision and rollback

Use separate decisions:

- `LOCAL PASS/FAIL`;
- `PUBLISHED PASS/FAIL/AMBIGUOUS`;
- `EXTERNAL SMOKE PASS/FAIL/BLOCKED`.

Never call the release fully verified unless all required classes pass. If a release-blocking failure is directly attributable to the new build and the exact known-good private-staging target is recorded, prepare the rollback (restore the recorded versions or republish the exact known-good artifacts in Match-then-Lobby-safe order), show the failure evidence and rollback plan, and ask the user once before executing it. After approval, execute and verify the rollback independently. If attribution or rollback identity is ambiguous, do not mutate further; preserve evidence and report `AMBIGUOUS`.

Update the evidence record with every decision. Commit or push it only when the user asks.

Production publication is a different workflow and requires a separate explicit request plus production-specific identifiers and compliance/commerce/persistence gates. This skill never expands a private-staging request into Production or Public access.
