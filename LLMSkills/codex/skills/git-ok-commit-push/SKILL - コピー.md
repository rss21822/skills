---
name: git-ok-commit-push
description: Commit and push the current git project after the user replies with exactly `OK`. Use when the active repository is already clear from prior context, the user wants Codex to finalize the current project's diff, and the response should stage, commit, and push the current branch non-interactively.
---

# Git Ok Commit Push

Commit the already-understood project's current diff and push it when the user replies with exactly `OK`.
Use this only when the target repository is unambiguous from the current conversation.

## Preconditions

- Treat `OK` as approval to finalize only the current project you have been working in.
- Require a clear repository root from recent context or from the current working tree.
- Stop and ask if multiple repositories are in scope or the intended repository is ambiguous.
- Stop and report instead of guessing if the directory is not a git repository.
- Stop and report if there are no local changes to commit.
- Stop and ask if the branch has no configured upstream and pushing would require choosing a remote or branch name.

## Workflow

1. Resolve the repository root for the active project.
2. Inspect the working tree with `git status --short`, `git branch --show-current`, and a compact diff summary.
3. Confirm that the observed changes match the work just completed in this conversation.
4. Stage the repository changes for that project.
5. Write a concise commit message based on the completed work.
6. Run a non-interactive commit.
7. Push the current branch to its existing upstream.
8. Report the commit hash, branch, and push result.

## Commit Message Rules

- Summarize the user-visible or code-visible change, not the conversation.
- Prefer one short imperative subject line.
- Reuse the task scope from the current conversation when it is clear.
- Avoid generic messages such as `update`, `fix stuff`, or `changes`.

## Safety Rules

- Do not include changes from a different repository.
- Do not amend, force-push, or rewrite history unless the user explicitly asks.
- Do not open an editor; use fully non-interactive git commands.
- If unrelated local changes are present in the same repository, use judgment:
  include them only when they are clearly part of the work the user just approved;
  otherwise stop and ask before committing.
- If push fails because of authentication, remote policy, or conflicts, report the exact blocker and stop.

## Response Shape

After completing the workflow, report:

- Repository root
- Branch name
- Commit hash and subject
- Push destination or failure reason
