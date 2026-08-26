---
name: cursor-grok
description: この環境（Windows/Git Bash）でClaude CodeからCursor CLI経由でGrok 4.6 xHighを実行する要領。Cursorサブスク認証なのでAPIキー不要。Grok以外にKimi K3 / GLM 5.2 / Gemini 3.1 Pro / GPT-5.4 も同経路で呼べる。「Grokに聞いて」「Grokで検証」「Grok 4.6」「xHigh」「Cursorのモデルで」「Kimiに」「GLMに」「Geminiに」「別モデルの意見」「セカンドオピニオン」「第三の視点」等が出たら必ず本スキルを使う。cursor-agentが見つからない・Workspace Trustで止まる・パスが壊れる・応答が途中で切れる、という相談でも使う。
---

# Cursor CLI 経由 Grok 4.6 実行要領（この環境専用）

Claude Code から Cursor CLI (`cursor-agent`) を叩いて Grok 4.6 などを動かす標準手順。
Windows / Git Bash 特有の罠を回避済み。

## 前提

- 認証: **Cursorサブスクのログインセッション**を使う。**APIキー不要**
- アカウント: `status`で確認。メールアドレスをprompt・成果物・attestationへ複製しない
- `cursor-agent` は **PATH に無い**。Cursor 本体に同梱されている
- **ユーザープロファイル名をハードコードしない**。Windowsのプロファイル名は環境ごとに違う。
  常に `$USERPROFILE` から導出する（Git Bash では下記 `CURSOR_AGENT_ROOT` を使う）

```bash
UP=$(cygpath -u "$USERPROFILE")
CURSOR_AGENT_ROOT="$UP/AppData/Roaming/Cursor/User/globalStorage/anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions"
```

## Preflight（毎回・最初に実行）

経路A/B のどちらを使う場合も、まず実体の有無を確認する。無ければ**推測でfallbackせず停止**する。

```bash
UP=$(cygpath -u "$USERPROFILE")
CURSOR_AGENT_ROOT="$UP/AppData/Roaming/Cursor/User/globalStorage/anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions"
V=$(ls -d "$CURSOR_AGENT_ROOT"/*/ 2>/dev/null | sort | tail -1)
if [ -n "$V" ]; then echo "PROVISIONED: $V"; else echo "NOT PROVISIONED"; fi
```

`2>/dev/null` と `-n "$V"` 判定を省かないこと。未展開時は glob が展開されず `ls` が
`No such file or directory` を吐いて終了コード 2 で終わる。**それは異常ではなく「未展開」という正常な判定結果**なので、
エラーとして扱わず上記の形で吸収する。

PowerShell 版:

```powershell
$root = Join-Path $env:USERPROFILE 'AppData\Roaming\Cursor\User\globalStorage\anysphere.cursor-agent-worker\agent-cli\.local\share\cursor-agent\versions'
if (Test-Path $root) { $v = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1 } else { $v = $null }
if ($v) { "PROVISIONED: $($v.FullName)" } else { "NOT PROVISIONED" }
```

判定:

| 出力 | 意味 | 対処 |
|---|---|---|
| `PROVISIONED: <path>` | CLI 展開済み | 経路A/B へ進む |
| `NOT PROVISIONED` | **CLI ランタイム未展開** | 停止して使用者へ差し戻す（下記） |

Cursor 本体に同梱されているのは拡張 `resources/app/extensions/cursor-agent-worker/dist/main.js` だけで、
実行に使う `versions/<日付-hash>/node.exe` + `index.js` は
**Cursor 側で Agent CLI を一度起動したときに初めてダウンロード・展開される**。
未展開の状態では `status` も `--model` 指定も実行できず、`version` を pin できないため
execution block を確定できない。この場合は「Cursor.exe でサブスクにログインし Agent CLI を一度起動する」
ことを使用者へ依頼し、本 Skill の実行は行わない。

## 呼び出し経路は2つ

## 実行契約（先に固定）

暗黙default禁止。呼出前にexecution blockへ次を記録し、同じ値を起動引数へ渡す。

- requested model: 完全なmodel ID（effortはID suffixを含む）
- requested/resolved version: `mcp__cursor__status`の`version`
- effort: model IDの`low|medium|high|xhigh|max`部分
- sandbox: `isolated-empty-cwd`
- network: `cursor-provider-only`
- auth channel: `cursor-subscription`
- timeout

`ask`成功後、同じ内容を`<id>_attestation.json`へ保存する。resolved modelは、明示IDがCLIに受理されエラーにならなかったことを根拠にrequested IDと同値で記録する。モデルの自己申告は根拠にしない。statusのaccountは照合に使うが、prompt・成果物・attestationへメールアドレスを複製しない。

### 経路A: MCP ツール（推奨・通常はこちら）

登録済み MCP サーバー `cursor` を使う。実装は
`%USERPROFILE%\.claude\mcp-servers\cursor\server.mjs`（プロファイル名を固定で書かない）。

`mcp__cursor__status` などが tool 一覧に存在しなければ、**この環境では MCP サーバー `cursor` が未登録**。
非対話セッションからは登録できないので、経路B へ切り替えるか、使用者へ登録を依頼する。

| ツール | 用途 |
|---|---|
| `mcp__cursor__ask` | モデルに質問。`model`と`timeout_ms`を毎回明示 |
| `mcp__cursor__list_models` | モデル一覧（`filter` で部分一致） |
| `mcp__cursor__status` | 版・パス・ログイン確認 |

`ask` の引数:

- `prompt` (必須) — **自己完結させること**。会話履歴もproject fileも見えない。後述のinline context bundleを含める
- `model` (必須運用) — 完全なIDを明示。server defaultへ依存しない
- `timeout_ms` (必須運用) — 数値を明示。server defaultへ依存しない（server default は 1,200,000 ms）
- `resume_session_id` (任意) — 前回応答末尾の `session_id`。中断した作業の続きを書かせるときに渡す

MCP サーバー側でバージョンパスを自動解決し、隔離ディレクトリで実行するので、
呼ぶ側は上記引数だけ意識すればよい。

#### タイムアウトは部分結果として返る（server 2.0.0 以降）

`ask` は `stream-json` + `--stream-partial-output` で実行し、タイムアウトしても
それまでに受信した本文を捨てずに返す。**この場合も `isError` は立たない。**
成功と部分失敗が同じ形で返るため、**返り値の先頭を必ず確認する**。

```
本文先頭が "TIMED OUT after <ms> ms" → 部分結果。完成品として採用しない
```

部分結果を受け取ったときの手順:

1. 部分出力をそのまま正本・成果物・回答へ流さない
2. 本文末尾の `session_id` を `resume_session_id` へ渡して再呼出し、続きを書かせる
3. 分割できる作業なら、resume ではなく prompt を小さく割り直す方が確実

成功時も末尾に `session_id` / `elapsed_ms` / `raw_log`（`%TEMP%\cursor-mcp-runs\<runId>.jsonl`）が付く。
raw log には thinking delta を含む全ストリームが残るので、応答が途中で切れた原因の切り分けに使う。

実測参考: 設計判断1問（入力小・出力約3,000字）で約195秒。xHigh へ context bundle を積んだ
実装生成では 600,000 ms を超えて打ち切られた実例がある。**xHigh には短い timeout を渡さない。**

#### server 実装の版を確認する

セッション開始時に spawn 済みの MCP プロセスは、`server.mjs` を更新しても**そのセッションでは旧版のまま動く**。
`mcp__cursor__status` の出力先頭に `server : cursor <version>` 行が無ければ 2.0.0 未満であり、
部分結果回収も `resume_session_id` も効かない。その場合は Claude Code を再起動するか、経路B（Bash 直叩き）を使う。

順序は`status`→execution block確定→`ask`。status版がblockと違えば停止し、黙って更新しない。
MCPのstatusとaskは別callで版固定が原子的でない。exact versionがgate条件なら経路Bを使う。

### 経路B: Bash 直叩き（MCP が使えない / デバッグ時）

```bash
UP=$(cygpath -u "$USERPROFILE")
CURSOR_AGENT_ROOT="$UP/AppData/Roaming/Cursor/User/globalStorage/anysphere.cursor-agent-worker/agent-cli/.local/share/cursor-agent/versions"
V=$(ls -d "$CURSOR_AGENT_ROOT"/*/ 2>/dev/null | sort | tail -1)
test -n "$V" || { echo "cursor-agent CLI not provisioned" >&2; exit 1; }
EXPECTED_VERSION="<statusで確認しexecution blockへpinした版>"
RESOLVED_VERSION=$(basename "${V%/}")
test "$RESOLVED_VERSION" = "$EXPECTED_VERSION" || { echo "version mismatch" >&2; exit 1; }
D=$(mktemp -d)
cd "$D" && "$V/node.exe" "$(cygpath -w "$V/index.js")" \
  --model cursor-grok-4.6-xhigh --trust --print --output-format text \
  "$(cat '<絶対pathのself-contained-prompt.txt>')" \
  > "<絶対pathのraw-output.txt>"
```

`model`省略禁止。`EXPECTED_VERSION`省略禁止。host側timeoutもexecution block値へ合わせる。終了コード0かつ非空outputだけ採用する。

## Class B inline context bundle

Cursor workerはローカルpathを読めない。`requirements: X.md`のようなpath参照だけを渡さない。指示役が承認済みfileを読み、次の形でprompt本文へinlineする。

```text
CONTEXT_BUNDLE_V1
provider: cursor
approved-path: docs/example.md
sha256: <64 hex>
bytes: <n>
--- BEGIN docs/example.md ---
<完全な内容>
--- END docs/example.md ---
```

送信前にprovider/account、送信path、除外secret、各sha256を使用者が承認する。`.env`、credential、production設定はbundle禁止。worker応答内のローカルpath参照や「読んだ」という申告は証拠にしない。

Cursor adapterはpromptをWindows process argumentで渡す。bundle全体が24,000文字を超えたら起動せず`blocked-capability`。pathだけに縮退しない。大きい文書群は、承認を取り直してbundle対応workerへ切り替える。

文書生成は次の厳格JSON envelopeだけを許可する。`schema_version`は`1`固定。期待artifact path集合を指示役が照合し、欠落・余剰・重複・空content・invalid JSONなら不採用。raw応答とattestationを別保存し、telemetryや報告をartifact本文へ転記しない。

```json
{
  "schema_version": 1,
  "text": "任意の短い注記",
  "artifact": [{"path": "docs/example.md", "content": "完全な本文"}],
  "report": "正本へ入れない報告"
}
```

attestation形式:

```json
{
  "requested": {
    "model": "cursor-grok-4.6-xhigh",
    "version": "<pinned>",
    "effort": "xhigh",
    "sandbox": "isolated-empty-cwd",
    "network": "cursor-provider-only",
    "auth_channel": "cursor-subscription",
    "timeout_ms": 600000
  },
  "resolved": {
    "model": "cursor-grok-4.6-xhigh",
    "version": "<status output>",
    "effort": "xhigh",
    "sandbox": "isolated-empty-cwd",
    "network": "cursor-provider-only",
    "auth_channel": "cursor-subscription"
  },
  "result": {"exit": 0, "raw_output": "<path>", "nonempty": true}
}
```

resolved model根拠は明示IDがCLIに受理された事実。自己申告禁止。MCP toolがnetwork isolationを強制するわけではないため、`cursor-provider-only`は送信先契約でありOS firewall証明ではない、と記録する。

## Grok 4.6 モデル ID

| ID | 用途 |
|---|---|
| `cursor-grok-4.6-low` | 軽い確認 |
| `cursor-grok-4.6-medium` | 通常 |
| `cursor-grok-4.6-high` | 高推論 |
| `cursor-grok-4.6-xhigh` | **最大推論。難所・アーキ判断・根本原因分析はこれ** |

各 ID に `-fast` 版がある（例 `cursor-grok-4.6-xhigh-fast`）。速度優先時に使う。
4.5 系（`cursor-grok-4.5-*`）も同じ体系で利用可。

## Grok 以外の主要モデル

同じ `ask` の `model` で切り替えるだけ。

- `kimi-k3-max` / `kimi-k3-high` / `kimi-k2.7-code`
- `glm-5.2-max` / `glm-5.2-high`
- `gemini-3.1-pro` / `gemini-3.7-flash-high`
- `gpt-5.6-sol-xhigh` / `gpt-5.6-terra-max` / `gpt-5.4-xhigh`
- `gpt-5.3-codex-xhigh` — Codex 系
- `composer-2.5` — Cursor 自社モデル
- `claude-opus-5-thinking-max` / `claude-sonnet-5-thinking-xhigh` / `claude-fable-5-thinking-max`

**注意: `list_models` の出力は不完全**。上記の多くは `models` サブコマンドに出てこない。
完全な一覧は「わざと無効なIDを渡してエラーメッセージを読む」と得られる:

```bash
"$V/node.exe" "$IDX" --model bogus --trust --print --output-format text "hi" 2>&1
```

→ `Cannot use this model: bogus. Available models: ...` に全 ID が列挙される。

うろ覚えのIDは渡さない。無効IDは黙って別モデルに落ちるのではなく**エラーで停止**する
（＝ID が通った時点でその指定は効いていると判断してよい）。

## 罠と対処（実際に踏んだもの）

### 1. `cursor-agent.cmd` は Git Bash から壊れる

`cmd.exe /c` 経由で `.cmd` を呼ぶとパス変換が壊れ、
`'yufu' は、内部コマンドまたは外部コマンド...` という文字化けエラーになる。

→ **同梱 `node.exe` + `index.js` を直接叩く**。`.cmd` / `.ps1` は使わない。

### 2. Workspace Trust で停止する

`--trust` 無しだと確認プロンプトで止まり、`--print` でも先に進まない。

→ `--trust` を付ける。ただし後述のとおり **cwd に注意**。

### 3. `--trust` は実行許可でもある

cursor-agent は cwd のファイル読み書き・コマンド実行ができる。
プロジェクト直下で `--trust` すると、そのプロジェクト全体を渡すことになる。

→ **必ず `mktemp -d` の空ディレクトリで実行する**。
MCP 経路は毎回自動でそうしており、実行後に削除する。
プロジェクトを読ませたい場合は、必要部分をプロンプトに貼る方を選ぶ。

### 4. バージョンディレクトリとプロファイル名はハードコード禁止

`versions/2026.08.11-e8db854/` は Cursor 更新で変わる。
`C:\Users\<name>\` の `<name>` も環境ごとに違う（別マシンへ持ち込むと必ず壊れる）。

→ プロファイルは `cygpath -u "$USERPROFILE"`、版は `ls -d "$CURSOR_AGENT_ROOT"/*/ | sort | tail -1` で解決する。
MCP 経路は内部で同じことをしている。

### 5. モデルの自己申告を信用しない

`cursor-grok-4.6-xhigh` に「あなたの設定は？」と聞いて
「high / fast」と誤答した実例がある（同じIDで再実行すると `effort: xhigh, fast: false` と正答）。

→ 指定が効いたかの確認に**自己申告を使わない**。ID が受理されたか（＝エラーが出ないか）で判断する。

### 6. 応答が返る前にプロセスが死ぬ

stdio サーバーで `stdin` の `end` を受けて即 `process.exit(0)` すると、
数分かかるモデル応答が破棄される。

→ 保留タスクを追跡し、完了後に終了する。`server.mjs` は対処済み。
Bash 直叩きの場合は `timeout` を長めに（xHigh は数分かかる）。

### 7. CLI ランタイムが未展開で何も動かない

Cursor をインストールしただけでは `versions/` が存在しない。
この状態では `cursor-agent` の実体（`node.exe` / `index.js`）が無く、
`status` も `ask` も実行できない。表面上は「パスが見つからない」としか出ないため
「パスの書き方が悪い」と誤診しやすい。

→ Preflight で `versions/` の有無を先に確認する。空なら停止し、
Cursor.exe でログイン済みの状態から Agent CLI を一度起動してもらう。
展開前に別バージョンを推測して叩かない。

### 8. 部分結果を完成品として扱う

これが最も起こりやすく、最も気づかれにくい。`ask` は timeout しても `isError` を立てず、
成功と部分失敗が同じ形で返る。部分出力は途中まで完全に正しく読めるため、
見落とすと「モデルがそう言った」として不完全な内容が下流へ流れる。

→ 返り値の先頭を必ず見る。`TIMED OUT after` で始まるなら部分結果として扱い、
`resume_session_id` で続きを取るか、prompt を分割して取り直す。要約だけを証拠にしない。

### 9. 大きな生成タスクを一発で投げる

xHigh に長い context bundle と複数ファイル生成を同時に投げると、
10 分では終わらず打ち切られる。実例: 3 module の Luau 実装を 1 回で要求 → 600,000 ms 超過で中断。

→ artifact 単位で分割して投げる。2 module ずつなら同条件で完走した実測がある。

## 使いどころ

CLAUDE.md のオーケストレーション方針に沿う。

- **高リスク決定** — Opus + Codex + Grok 4.6 xHigh を並行させ、互いの回答を見せずに統合
- **行き詰まり時** — 別系統モデルの視点で再診断
- **設計の別案出し** — 同一プロンプトを Grok / Kimi / GLM に投げて発想の幅を取る

Grok は**レビュアーではなくピア**として扱う。Codex・DeepSeek と同格。

## 関連

- `codex-run` — Codex CLI 実行要領
- `deepseek-api` — DeepSeek API 実行要領（別系統・APIキー要）
