---
name: cloudflare-redeploy-shortcut
description: Redeploy the current project to Cloudflare when the user asks for a redeploy, especially when the message is exactly or only `再デプロイ`. Use for Cloudflare Workers / Pages style redeploy requests where Codex should inspect the repo's existing deployment path and execute the safest existing redeploy workflow.
---

# Cloudflare Redeploy Shortcut

Use the repository's existing Cloudflare deployment path instead of inventing a new one.

## Workflow

1. Inspect the current repo for the active Cloudflare deployment method.
Look for `wrangler.jsonc`, `wrangler.toml`, `package.json`, and GitHub Actions workflows.

2. Prefer the safest existing redeploy path.
- If the repo already uses GitHub Actions for staging or production redeploy, prefer commit/push or workflow dispatch over ad hoc local deploys.
- If local Cloudflare deploy is known to fail in the current environment, do not retry the same broken path unless the user explicitly asks.

3. Infer the target environment from context.
- Reuse the environment named in the thread if one is already established.
- If the thread makes the target explicit, use that exact target.
- If the request is only `再デプロイ` and no target is established, inspect branch names, workflows, and recent deployment context before choosing.

4. Execute the redeploy end to end.
- Run the concrete deploy command or trigger the configured workflow.
- If a push is required, stage only the files needed for the redeploy request and avoid unrelated dirty files.
- Do not redeploy production when the established target is staging.

5. Verify the result.
- Check the deploy command output or GitHub Actions run result.
- Report the deployed environment, method, and any limitations on verification.

## Guardrails

- Keep the redeploy path aligned with the repo's existing Cloudflare setup.
- Prefer staging over production when the context is ambiguous.
- Treat `再デプロイ` as an execution request, not a planning request.
- When deployment depends on local auth or environment constraints, fall back to the repo's CI/CD path if available.