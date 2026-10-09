---
name: remotedesktop-init
description: Install and verify Claude Desktop, GitHub Desktop, Roblox Studio, Cursor, and Git on a Windows desktop. Use when the user asks to initialize a remote or new Windows workstation with these development tools, or asks to install any of this toolset.
---

# RemoteDesktop-init

Install the standard Windows desktop toolset with the bundled script, then report the result for every application.

## Workflow

1. Confirm that the request is for a Windows desktop and explain that GitHub means GitHub Desktop. Do not substitute GitHub CLI.
2. Run `scripts/install_desktop_apps.ps1` from this skill directory.
   Use `-DryRun` only for testing the workflow; omit it for the real installation.
3. Allow the script to complete the non-interactive package steps. Do not ask the user for passwords or account credentials.
4. If Windows elevation, an installer dialog, a license prompt, or a browser/account sign-in requires user action, stop at that point and tell the user exactly what to click or enter. Resume only after the user confirms that the action is complete.
5. Report each package as installed, already installed, or failed, including the reason for any failure. Do not claim completion from a successful download alone; use the script's executable verification.
6. If the user asks to open the applications, launch them separately after installation. Installation alone must not trigger account sign-in.

## Package mapping

- Claude Desktop: `Anthropic.Claude`
- GitHub Desktop: `GitHub.GitHubDesktop`
- Roblox Studio: `Roblox.RobloxStudio`
- Cursor: `Anysphere.Cursor`
- Git for Windows: `Git.Git`

The script uses exact package IDs and accepts only the configured winget source agreements. Roblox Studio has a known failure mode where the winget manifest hash can lag behind the official installer; in that case the script downloads `https://setup.rbxcdn.com/RobloxStudioInstaller.exe`, requires a valid Authenticode signature from Roblox Corporation, runs it, and verifies the installed Studio executable.

## Manual-input policy

Pause and notify the user when an action cannot be completed safely without them, especially UAC approval, an installer prompt, or first-run authentication. Installation does not require signing in to Claude, GitHub, Roblox, Cursor, or any other account. Never attempt to infer or store credentials.
