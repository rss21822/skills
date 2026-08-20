---
name: deepseek-api
description: DeepSeek APIへ明示的にpinしたリクエストを送り、応答・artifact・実行attestationをfail-closedで保存する。Roblox/Luauの実装生成、レビュー、デバッグ、設計相談、別モデルの意見、DeepSeek v4-pro/v4-flash、認証診断で使う。正本経路はproject cwdから絶対パスで起動するds_ask.py。MCPは互換adapterのみ。
---

# DeepSeek API

## 正本経路

`scripts/ds_ask.py` v2.0.0のみ正本。**project rootをcwd**にし、scriptは絶対パスで起動する。`python scripts/ds_ask.py`は禁止。skill cwdではproject globとproject-local keyを解決できない。

```bash
cd "<project-root>"
python "C:/Users/ryufu/.claude/skills/deepseek-api/scripts/ds_ask.py" \
  --prompt-file "docs/handoffs/in/<id>.md" \
  --files "docs/**/*.md" \
  --system-preset plain \
  --model deepseek-v4-pro \
  --effort high \
  --max-tokens 16000 \
  --expect-client-version 2.0.0 \
  --sandbox text-only \
  --network deepseek-api-only \
  --auth-channel env \
  --out "docs/handoffs/out/<id>_raw.md" \
  --attestation-out "docs/handoffs/out/<id>_attestation.json"
```

暗黙default禁止。毎回、次をexecution blockと起動引数で一致させる。

- requested model / effort
- thinking / max tokens
- client version `2.0.0`
- sandbox `text-only`
- network `deepseek-api-only`
- auth channel `env|home-file|repo-file|cwd-file`
- output / attestation path

`resolved.model`、finish reason、token usage、実際のauth channelはattestationから読む。モデル自己申告を使わない。

## 認証preflight

選んだauth channelだけを確認する。fallbackしない。値・長さ・prefix・file pathは表示しない。

```bash
cd "<project-root>"
python "C:/Users/ryufu/.claude/skills/deepseek-api/scripts/ds_ask.py" \
  --check \
  --model deepseek-v4-pro \
  --effort high \
  --max-tokens 16 \
  --expect-client-version 2.0.0 \
  --sandbox text-only \
  --network deepseek-api-only \
  --auth-channel env \
  --attestation-out "docs/handoffs/out/D0_deepseek_check.json"
```

channel:

- `env`: `DEEPSEEK_API_KEY`
- `home-file`: `~/.deepseek/api_key`
- `repo-file`: `<git-root>/.deepseek/api_key`
- `cwd-file`: `<cwd>/.deepseek/api_key`

チャット・prompt・attestationへkeyを入れない。配置手順は`references/setup.md`。

## Class B契約

DeepSeekはtext-only Class B。ローカルpathを読めない。`--files`はローカルwrapperが内容を読み、path label付きでpromptへinlineするだけ。workerへ「`X.md`を読め」とpathだけ渡すのは禁止。

`claude-roblox-dev-docs-creator`から呼ぶ場合、先に同Skillの`scripts/build_context_bundle.py`で承認済みsourceだけをbundle化する。DeepSeekには生成した`<id>_context.md`を唯一の`--files`入力として渡し、original source globを再展開しない。sidecarのbundle/source hashを`transferApproval`と照合してから送る。これでCursor経路と同じcontext bytesを使う。

各inline fileへproject相対path・sha256・byte数を付す。未一致glob、project cwd外、上限超過、deny対象、読取失敗が1件でもあれば送信前にnonzero停止する。

送信前に対象path、provider/account、除外secret、content sha256、cost上限の人間承認を得る。globは承認済みpathだけ。`.env`、credential、production設定を含む広域glob禁止。大きいbundleは先に`--dry-run`。

```bash
python "C:/Users/ryufu/.claude/skills/deepseek-api/scripts/ds_ask.py" \
  --prompt-file "docs/handoffs/in/<id>.md" \
  --files "docs/game_gdd.md" \
  --files "docs/specs/approved_source.md" \
  --model deepseek-v4-pro --effort high --max-tokens 16000 \
  --expect-client-version 2.0.0 --sandbox text-only \
  --network deepseek-api-only --auth-channel env \
  --out "docs/handoffs/out/<id>_raw.md" \
  --attestation-out "docs/handoffs/out/<id>_attestation.json" \
  --dry-run
```

dry-runは既定でprompt本文を表示しない。明示的に必要な場合だけ`--show-prompt-preview`。

## 複数artifact出力

正本文書生成ではJSON envelopeを要求する。promptにも次のschemaと例を書く。

```json
{
  "schema_version": 1,
  "text": "任意の短い注記",
  "artifact": [
    {"path": "docs/example.md", "content": "正本へ転記する完全な本文"}
  ],
  "report": "artifactとは分離した最終報告"
}
```

起動時に`--json --expect-artifact "docs/example.md"`を指定する。複数ならrepeat。`schema_version != 1`、期待pathとの差、重複、空content、invalid JSON、空応答、`finish_reason != stop`、resolved model欠落はexit nonzero。失敗時、成果物outputを書かない。

`--show-reasoning`はartifact modeで禁止。reasoningを正本文へ混入させない。

## MCP互換adapter

`mcp__deepseek__ask`は既存利用者向け互換経路。新規運行ではCLIを使う。MCP利用時も全引数を明示する。

- `model`, `thinking`, `effort`, `max_tokens`
- `expect_client_version: "2.0.0"`
- `sandbox: "text-only"`
- `network: "deepseek-api-only"`
- `auth_channel: "env"`
- `expected_artifact`

MCPはenv keyのみ。file channel非対応。返却は`structuredContent`内の`text` / `artifact` / `report` / `finish_reason` / `model` / `tokens` / `thinking` / `max_tokens` / `auth_source` / `attestation`。token telemetryを`text`やartifact本文へ付加しない。finish reason・artifact集合はCLI同様fail-closed。

## preset

- `luau-impl`: 実装下書き
- `luau-review`: コードレビュー
- `design`: 代替設計
- `plain`: 文書作成・汎用

内容は`references/prompts.md`。DeepSeek出力は下書き。Roblox API、Server/Client境界、行根拠を自分で検証してから採用する。

## 失敗時

- 401: 同じauth channelで`--check`。別channelへ黙ってfallbackしない
- 402: 残高不足。停止
- 429: 並列数削減
- timeout: `--timeout`調整。途中出力を採用しない
- `finish_reason != stop`: max tokensまたは依頼粒度を修正し再実行
- artifact mismatch: prompt schemaと`--expect-artifact`を一致させる。手でfooter/preambleを削らない

API詳細は`references/api.md`。
