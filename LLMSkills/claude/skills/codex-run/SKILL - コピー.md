---
name: codex-run
description: この環境（Windows/Git Bash）でClaudeからCodex CLIを実行する要領。Codexに文書作成・コードレビュー・診断・セカンドオピニオン・ピアレビューを頼まれたら使う。/codex:rescue サブエージェント経由が kimi-k2.6 誤ルーティングで起動不能なため、companion runtime を直接叩く回避手順を含む。「Codexに」「Codexで」「Codexレビュー」「Codex起動」「別視点」「セカンドオピニオン」等が出たら本スキルを参照。ただし `claude-roblox-mvp-buildout` または `claude-roblox-development-delivery` のT1製品実装では、同梱exact-pinned helperが優先し、本Skillのcompanion実装経路へ切り替えない。
---

# Codex 実行要領（この環境専用）

ClaudeからCodex CLIを動かす標準手順。Windows/Git Bash特有の罠を回避済み。

Roblox MVP/単一WPのT1製品実装は対象外。該当Skillのexact-pinned helperが正本で、失敗時も本経路へfallbackしない。本SkillはS1/S2文書作成・read-only review・一般診断、または上位Skillが明示的にcompanionを指定したjobで使う。

## 前提

- Codex CLI インストール済（npm global `@openai/codex`）
- 経路: `codex-companion.mjs task "<prompt>"` を**直接Bash実行**
- サブエージェント `codex:codex-rescue` は使わない → メインモデルfable-5時に **kimi-k2.6誤ルーティングで起動不能**（既知障害）。`Agent`の`model`上書きも無効。**直接companion一択。**

## 経路選択

- Codexにレビュー/実装/診断/研究を投げる → 下記コマンド1本
- サブエージェント試行は時間の無駄。最初から直接叩く。

## 実行コマンド（コピペ用）

**必ずPATH前置き。** `spawn("codex")`(app-server.mjs:188)がshell無し→Windowsで`.cmd`解決不能→ENOENT。実`codex.exe`のvendorディレクトリをPATH先頭に足して回避。

暗黙default禁止。先にexecution blockへ次を固定する。

- requested model / effort
- expected Codex CLI version / companion version
- sandbox `read-only|workspace-write`
- approvalPolicy `never`
- network `unattested-provider-required`
- auth channel `chatgpt-login`

companionはsandbox networkを指定・報告する引数を持たない。`network:false`を要求するhandoffではこのrouteを使わずBLOCKEDにする。`unattested-provider-required`を`false`と記録しない。

```bash
set -o pipefail
export PATH="/c/Users/ryufu/AppData/Roaming/npm/node_modules/@openai/codex/node_modules/@openai/codex-win32-x64/vendor/x86_64-pc-windows-msvc/bin:$PATH"
CODEX_EXE="/c/Users/ryufu/AppData/Roaming/npm/node_modules/@openai/codex/node_modules/@openai/codex-win32-x64/vendor/x86_64-pc-windows-msvc/bin/codex.exe"
COMPANION="C:/Users/ryufu/.claude/plugins/cache/openai-codex/codex/1.0.1/scripts/codex-companion.mjs"
EXPECTED_CODEX_VERSION="<能力プローブでpinした codex-cli x.y.z>"
EXPECTED_COMPANION_VERSION="1.0.1"
MODEL="<完全なmodel ID>"
EFFORT="<low|medium|high|xhigh>"
PROJECT_ROOT="<Git Bashで解決できるproject root>"
PROMPT_FILE="<Git Bashで解決できるhandoff.md絶対path>"
RAW_OUTPUT="<Git Bashで解決できるraw-output.txt絶対path>"

test "$("$CODEX_EXE" --version)" = "$EXPECTED_CODEX_VERSION" || { echo "Codex version mismatch" >&2; exit 1; }
test "$("$CODEX_EXE" login status)" = "Logged in using ChatGPT" || { echo "Codex auth mismatch" >&2; exit 1; }
test -f "$COMPANION" || { echo "companion missing" >&2; exit 1; }
case "$COMPANION" in *"/codex/$EXPECTED_COMPANION_VERSION/"*) ;; *) echo "companion version mismatch" >&2; exit 1;; esac
COMPANION_SHA256=$(sha256sum "$COMPANION" | awk '{print $1}')
test -f "$PROMPT_FILE" || { echo "prompt file missing" >&2; exit 1; }
cd "$PROJECT_ROOT" || exit 1

node "$COMPANION" task --fresh \
  --cwd "$(cygpath -w "$PWD")" \
  --prompt-file "$(cygpath -w "$PROMPT_FILE")" \
  --model "$MODEL" --effort "$EFFORT" \
  2>&1 | tee "$RAW_OUTPUT"
```

実装時だけ`task`へ`--write`追加し、resolved sandboxを`workspace-write`とする。レビュー・診断は付けず`read-only`。`--resume-last`は過去threadのmodel/contextを継ぐため、同じexecution pinが証明できる場合だけ使う。通常は`--fresh`。

**PATHは必ず `/c/...` POSIX形式。** `C:/...` はGit Bashが`:`区切りでドライブコロン誤分割→PATHに載らず失敗。

## 実行オプション

- **バックグラウンド必須**: レビュー/実装は数分かかる。`run_in_background: true` で起動。完了通知＋出力ファイルpathが返る。
- **読み取り専用**: レビュー/診断/研究 → `--write` を**付けない**（Codexはread-onlyサンドボックス）
- **書き込み**: 実装/修正依頼 → `task` の後に `--write` 追加
- **モデル指定**: 常に`--model <完全ID>`。implicit default禁止
- **effort指定**: 常に`--effort <値>`
- **継続**: 前回の続き → `task --resume-last`

## 依頼文の書き方

- 役割付与（例「対等なシニアエンジニアとして」）
- 対象ファイル・正本設計書を明示パスで列挙
- 出力形式指定（重大度ランク・ファイル:行・根拠引用）
- 「日本語で回答」明記
- レビューなら「コード修正するな、読み取りのみ」を明記

## 結果回収

1. 完了通知 `<task-notification status=completed>` を待つ
2. 通知内 `output-file` を `Read`
3. ファイル中 `[codex]` 行＝実行ログ。最終の平文ブロックがCodex回答本体
4. exit status、非空最終回答、意図したread/write modeを確認する
5. raw outputと別に`<id>_attestation.json`を保存する
6. 重大度順に整理してユーザーへ報告

attestation必須項目:

```json
{
  "requested": {
    "model": "<MODEL>",
    "effort": "<EFFORT>",
    "version": "<EXPECTED_CODEX_VERSION>",
    "sandbox": "read-only|workspace-write",
    "network": "unattested-provider-required",
    "auth_channel": "chatgpt-login"
  },
  "resolved": {
    "model": "<明示argumentが受理されたMODEL>",
    "effort": "<明示argumentが受理されたEFFORT>",
    "version": "<codex.exe --versionの実出力>",
    "companion": "1.0.1",
    "companion_sha256": "<shasum -a 256の実出力>",
    "sandbox": "read-only|workspace-write",
    "approvalPolicy": "never",
    "network": "unattested-provider-required",
    "auth_channel": "chatgpt-login"
  },
  "result": {"exit": 0, "raw_output": "<path>", "nonempty": true}
}
```

resolved model/effortの根拠はモデル自己申告ではなく、明示CLI argumentがエラーなく受理された事実。companion outputはmodel/effortを返さないため、これ以上の強い主張をしない。

## トラブルシュート

- `spawn codex ENOENT` → PATH前置き忘れ or `C:/`形式で書いた。`/c/`形式で再実行
- サブエージェント `There's an issue with the selected model (kimi-k2.6)` → 既知障害。サブエージェント諦め直接companion
- exit 1 即死 → 出力ファイルReadで原因確認（大抵ENOENT）
- codex.exe場所が変わった（バージョン更新等） → `find "$(npm root -g)/@openai/codex" -iname codex.exe` で再特定しPATH差替え
- `--help`等をtaskに渡すな → プロンプト扱いでCodex暴走。サブコマンドは`task`固定

## 恒久化（任意）

毎回PATH前置きが面倒なら、実`codex.exe`をPATH済みディレクトリへ配置 or `~/.bashrc` にexport追記。ただし依存exe群（codex-command-runner.exe等）が同居必須のため、vendorディレクトリごとPATHに足す方式が安全。
