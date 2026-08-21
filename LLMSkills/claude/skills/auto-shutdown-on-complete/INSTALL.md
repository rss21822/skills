# Claude Code へのインストール

このフォルダ（`auto-shutdown-on-complete/`）をそのまま以下に置く。

| スコープ | 置き場所 |
|---|---|
| 全プロジェクトで使う（推奨） | `%USERPROFILE%\.claude\skills\auto-shutdown-on-complete\` |
| 特定プロジェクトだけ | `<プロジェクト>\.claude\skills\auto-shutdown-on-complete\` |

Git Bash なら:

```bash
mkdir -p ~/.claude/skills
unzip auto-shutdown-on-complete-claude-code.zip -d ~/.claude/skills/
ls ~/.claude/skills/auto-shutdown-on-complete/SKILL.md
```

置いたあと Claude Code を再起動すれば `/auto-shutdown-on-complete` で呼べる。

## 動作確認（電源は切れない）

```bash
CLAUDE_SHUTDOWN_DRYRUN=1 powershell.exe -NoProfile -ExecutionPolicy Bypass \
  -File "$HOME/.claude/skills/auto-shutdown-on-complete/scripts/shutdown.ps1" -Fire
```

`DRYRUN FIRE: shutdown.exe /s /t 360 ...` とログに出れば正常。
DRYRUN を外して初めて実際に電源が切れる。

## 実運用での最初の1回

いきなり本番作業で試さず、軽いタスクで「終わったらPC落として」と言って、
6分の猶予中に `shutdown /a` が効くことを確認しておくと安心。
