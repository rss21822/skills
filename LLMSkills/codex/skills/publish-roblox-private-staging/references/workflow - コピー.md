# Private staging publication workflow

Use this workflow for production-like Roblox testing without Production exposure.

## 1. Establish the target and execution boundary

Verify that the requested target is a dedicated staging Experience, not Production. Invocation for a project is task-scoped authorization for the full private-staging workflow; do not add approval checkpoints. Resolve from repository-owned configuration or Creator Dashboard evidence:

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

Record the source commit and dirty-worktree state. Preserve unrelated user changes.

Run the repository's registered validation path. At minimum, validate:

- every Rojo project build required by the product;
- compilation of product Luau sources;
- the full automatic suite;
- environment-binding tests;
- Studio Edit mapping for each published Place;
- role/environment attributes, entries, RemoteEvents, and configuration tree.

Build separate immutable artifacts for each Place role. Compute SHA-256 hashes and file sizes. Do not publish an artifact that changed after hashing.

## 4. Freeze the release manifest and rollback target

Before publishing, prepare and internally verify an evidence record containing:

- environment and creator;
- source commit;
- artifact paths and SHA-256 hashes;
- Universe and Place IDs;
- previous published versions;
- intended publish order;
- audience and Studio API Access state;
- known-good rollback targets;
- local and Studio validation results;
- pending human/runtime checks.

Do not include credentials or reserved-server access codes.

## 5. Obtain scoped publish credentials

Do not ask the user to approve the manifest or publish step. The original request to use this skill is authorization for mutations confined to the resolved private staging target. Recompute hashes and recheck target identity immediately before sending the publish request; abort rather than guess if either changed unexpectedly.

For Open Cloud Place Publishing, use a temporary API key restricted to the target staging Experience with `universe-places` Write permission. Prefer the shortest practical lifetime. Keep the key in process memory or a temporary environment variable only; never echo it.

The current documented endpoint is:

```text
POST https://apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions?versionType=Published
```

Use `Content-Type: application/xml` for `.rbxlx` and `application/octet-stream` for `.rbxl`. A success response includes `versionNumber`. Recheck the official Roblox Place Publishing guide if the endpoint or permissions appear to have changed.

Studio `Publish to Roblox As...` is an acceptable alternative when an artifact contains unsupported Place Publishing API instance types or the user chooses manual publication. Verify the target Place before clicking Overwrite.

## 6. Publish in dependency-safe order

For Lobby-to-Match topology:

1. publish Match first;
2. verify the response and new Match version;
3. publish Lobby/start Place second;
4. verify the response and new Lobby version.

This avoids exposing a new Lobby that routes into an old Match build. Do not continue to Lobby after a Match publish failure or ambiguous response. Reconcile an ambiguous result from Dashboard/version history before retrying; blind retry may create extra versions.

## 7. Verify the cloud state

After publication:

- confirm both new versions in Creator Dashboard;
- confirm creator, Universe, and Place identity;
- confirm the Experience remains Private;
- confirm Studio API Access has the approved state;
- confirm Match direct access and maximum-player settings;
- open the Experience page with the authorized owner/test account and confirm the Play action;
- record UTC timestamps and published version numbers.

Delete the temporary API key automatically after cloud verification or an aborted attempt, then confirm it is absent. Key deletion does not replace publication verification.

## 8. Run an external-client smoke

Use the Roblox Player, not Studio, because TeleportService, reserved servers, MemoryStore, and live persistence need a published environment.

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

Record client version, device/OS, account role, start/end times, Place versions, and observed result. A Player crash, login limitation, or remote-desktop incompatibility is an environment blocker, not proof of a game defect or a PASS.

## 9. Decision and rollback

Use separate decisions:

- `LOCAL PASS/FAIL`;
- `PUBLISHED PASS/FAIL/AMBIGUOUS`;
- `EXTERNAL SMOKE PASS/FAIL/BLOCKED`.

Never call the release fully verified unless all required classes pass. If a release-blocking failure is directly attributable to the new build and the exact known-good private-staging target is recorded, stop new staging joins where supported and restore the recorded versions or republish the exact known-good artifacts in Match-then-Lobby-safe order without another confirmation. Verify the rollback independently. If attribution or rollback identity is ambiguous, do not mutate further; preserve evidence and report `AMBIGUOUS`.

Production publication is a different workflow and requires a separate explicit request plus production-specific identifiers and compliance/commerce/persistence gates. This skill never expands a private-staging request into Production or Public access.
