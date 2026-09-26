# Cavalry Rivals staging profile

Read this only when operating in the Cavalry Rivals repository. Re-verify all mutable values before each publication.

## Repository sources of truth

- Project root: locate the active Git checkout; do not operate on OneDrive conflict copies or nested duplicate repositories.
- Lobby project: `projects/lobby.project.json`
- Match project: `projects/match.project.json`
- Staging binding: `config/generated/staging/EnvironmentConfig.luau`
- Automatic runner: `tests/run.luau`
- Latest staging evidence pattern: `docs/evidence/MVP-*_staging_release_*.md`
- Release policy: `docs/CAV_release_rollback_runbook.md`
- Toolchain registry: `docs/CAV_toolchain_spec.md`

## Current private staging identity

- Creator: Group `Cavalry_Rivals` (`307296784`)
- Universe: `10712517938`
- Lobby/start Place: `77674654746087`
- Match Place: `92770151675387`
- Environment attribute: `CAVEnvironment=staging`
- Place roles: Lobby=`CAVPlaceRole=Lobby`; Match=`CAVPlaceRole=Match`
- Persistent store: `CAV_STAGING_PLAYER_PROFILE_V1`
- Intended audience: Private
- Intended publish order: Match, then Lobby

These are staging values only. Do not reuse them as Production identifiers.

## Last recorded publication

Evidence file: `docs/evidence/MVP-013_staging_release_v13.md`

- source commit: `cc2cda916c7654858dd5d686ed6e7e489ed0bf29`
- Match artifact: `build/CAV_match_mvp_candidate_v13-staging.rbxlx`
- Match SHA-256: `8EB373D117C80C786354A53873FDBA6F1CE046B05219009C3944DA30F656B9D1`
- Match version: `21 -> 22`
- Lobby artifact: `build/CAV_lobby_mvp_candidate_v13-staging.rbxlx`
- Lobby SHA-256: `E81DF86C99ED83669358D6CD2D1CB7E101A06D806DD9A85C7D4085DD7B589958`
- Lobby version: `22 -> 23`
- publication responses: HTTP 200 for both Places

This record is historical, not permission to republish or a guarantee that the versions remain current. Read Dashboard state before a new release.

## Cavalry Rivals smoke flow

Run from the staging Lobby game page with an authorized account:

1. wait until Lobby state finishes loading;
2. start `Training Joust`;
3. verify one human plus the server-authoritative bot;
4. verify reserved-server teleport to the Match Place;
5. complete the joust and inspect Result/Charge Report;
6. test rematch once when requested;
7. return to Lobby;
8. verify profile/loadout/meta state reloads and no session-lock error appears.

After the solo smoke, four-human 2v2, cross-Lobby convergence, mobile, PC, and controller checks remain separate gates.

## Known historical blocker

The August 18, 2026 remote Administrator session could install the signed Roblox Player but the Player exited with Windows status `0xC0000409`. That run did not reach product assertions. Re-test on a normal interactive Roblox Player session; do not copy the old blocker forward without reproducing it.
