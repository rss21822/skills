---
name: publish-roblox-private-staging
description: Autonomously build, publish, and verify a Roblox game in a private production-like staging Experience, including multi-Place Lobby/Match topology, isolated persistent services, scoped temporary credentials, rollback evidence, and external-client smoke testing. Use when the user wants an end-to-end private staging release without making the Production Experience public or modifying Production.
---

# Publish Roblox Private Staging

Create a live Roblox test environment that behaves like production while remaining isolated and non-public.

## Required reading

Before preparing or publishing anything, read [references/workflow.md](references/workflow.md).

If the repository is Cavalry Rivals, also read [references/cavalry-rivals.md](references/cavalry-rivals.md). Treat its current IDs as project-specific staging values, not universal defaults.

## Hard boundary

- `staging` means a separate private Experience with separate Place IDs and persistent-data namespaces.
- Never create, open, bind, publish, overwrite, activate, or change the audience of Production under this skill.
- Never make the staging Experience Public. Keep it Private unless the user explicitly authorizes a Limited playtester audience after reviewing the access implications.
- A clear request to use this skill for a project grants task-scoped authority to perform every necessary non-Production staging action end to end. This includes Dashboard changes within the private staging target, creating and deleting a least-privilege temporary publish key, publishing, verification, evidence updates, and a safe rollback to the recorded staging version when required.
- Do not pause for manifest approval, credential approval, deletion approval, publish approval, verification approval, evidence commit, or rollback approval. Resolve choices from authoritative repository, Studio, API, and Dashboard evidence and continue autonomously.
- Before the first mutation, internally freeze the exact Universe ID, Place IDs, artifact hashes, previous versions, audience, and publish order in the evidence record. Never guess an unresolved target. Exhaust safe discovery; if ambiguity remains, stop before mutation and report the blocker rather than asking the user to choose unless higher-priority instructions require input.
- Treat credentials as ephemeral. Never write API keys, cookies, reserved-server codes, or session tokens to the repository, logs, evidence, command history, or chat. Create the narrowest practical temporary key when needed, retain it only in process memory, delete it automatically after verification or abort, and confirm absence.
- Do not request confirmations unless a higher-priority system or safety rule requires one. If such a rule prevents an action, preserve completed work and report the exact blocked step.

## Default: upload to completion without checkpoints

- When invoked for publication (including a skill-only invocation with an unambiguous current project), proceed from discovery through upload of every in-scope staging Place and independent published-version verification in the same task. Do not stop at build completion, a prepared manifest, an open publish dialog, or completion of only one Place.
- Do not end with "ready to upload", "shall I publish?", or a request for "OK" / "アップロード実行" / "残りを実行". Progress messages are non-blocking updates, not approval gates.
- Prefer a working authenticated Studio publishing route or an already-authorized scoped publishing credential. New credential creation is not a prerequisite when Studio can complete the upload. If one route is unavailable, try safe authorized alternatives before reporting a blocker; never bypass tool-required confirmations or authentication controls.
- Keep upload completion distinct from external-client smoke completion. Attempt the required smoke automatically after upload. If it is blocked, finish with the confirmed Place versions and the precise outstanding runtime check; do not label the upload pending or request another approval merely to continue it.
- Stop only for a concrete unresolved target, failed validation, unavailable authorized access, a higher-priority confirmation requirement, or a failure that cannot be safely reconciled. Record completed steps and the exact blocker; never invent success or retry an ambiguous upload blindly.
- A request to edit, review, or explain this skill does not itself authorize a game upload.

## Completion evidence

A successful run proves all of the following separately:

1. Local candidate validation passed.
2. The exact Match and Lobby artifacts were published to the intended private staging Places.
3. Dashboard/version evidence matches the API or Studio responses.
4. A real Roblox client completed the required staging smoke flow.

Do not collapse these into one PASS. If the external client cannot run, report the publication as complete and runtime smoke as blocked or incomplete.
