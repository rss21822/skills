# 実装委譲の契約

WPを外部LLMへ委譲するときの最小契約。実装者の自己申告は証拠ではない。依頼側が差分と検証を再実行する。

## 目次

- [0. 実施workerの指定と階層](#0-実施workerの指定と階層)
- [1. 起動前検査](#1-起動前検査)
- [2. Codex CLIの起動](#2-codex-cliの起動)
- [3. 指示文の必須項目](#3-指示文の必須項目)
- [4. 常設禁止条項](#4-常設禁止条項)
- [5. 検証の分担](#5-検証の分担)
- [6. 安全なmodule smoke](#6-安全なmodule-smoke)
- [7. 調査委譲](#7-調査委譲)
- [8. 受領と契約違反](#8-受領と契約違反)

## 0. 実施workerの指定と階層

**実施workerは所有者が指定する。** 既定値で黙って始めない。指定が無ければ、§2.2のプリフライト結果を添えて訊く。

**ただし、workerによって「何が自動で強制されるか」が違う。** ここが本skillで最も誤解されやすい点である。委譲先を替えることは、model を替えることではなく、**強制機構ごと替える**ことを意味する。指定を受け付ける代わりに、階層と適用範囲を明示する。

| 階層 | worker | 強制機構 | 実装役 | 調査・照合役 |
|---|---|---|---|---|
| **T1 attested** | Codex CLI（同梱helper経由） | 署名検証・`CODEX_HOME` pin・config隔離・egress override拒否・露出gate・version exact pin | **可**（`workspace-write`の無人実装はここだけ） | 可（`read-only`） |
| **T2 in-session** | Claudeサブエージェント | 無し（指示役と同一trust boundary。第三者egressは無い） | 条件付き可（§0.2） | 可 |
| **T3 external text** | Cursor CLI経由（Grok/Kimi/GLM/Gemini）、DeepSeek 等 | 無し。repository読取も不可 | **不可**（§0.3） | 可（文脈をinlineで渡す） |

### 0.1 T1 — attested 経路（exact pin が利用可能な場合）

同梱helperが§1〜§2の契約を機械的に強制する。**この強制はCodex固有であり、他workerへ移らない。** 署名主体（OpenAI OpCo, LLC）、`codex.exe` native限定、`--ignore-user-config`、`--strict-config`、pinned version `codex-cli 0.147.0`——いずれもCodexという実体に紐づく。

T1 は強制機構が最も強いが、**worker 指定前の暗黙の既定値ではない。** `codex --version` が
exact pin と一致しなければ T1 を利用可能候補から外し、pinを弱めたり未監査版へ書き換えたりせず、
T2/T3 の適用範囲を示して所有者へ worker 指定を求める。T3 は §0.3 のとおり原則実装不可。

**無人で`workspace-write`を与えてよいのはT1だけ。** 他階層で同等の保証を主張しない。

### 0.2 T2 — サブエージェント

第三者へprompt・repository内容を送らない点はT1より露出が小さい。一方、§2が固定する機構（署名・config層拒否・環境allowlist・stream上限・metadata schema）は**一つも存在しない**。

採用する場合、失われる保証を所有者へ明示し、代わりに次を人手で満たす。

- 許可パスの完全列挙と凍結パスをpromptへ明記する（§3）。強制はされないので、**§5の依頼側再検査が唯一の防壁になる**
- 開始前台帳との差分検査を、T1のとき以上に厳密に行う
- 2回buildのSHA-256照合を依頼側が必ず自分で取る
- 「helperが止めてくれるはず」を前提にしない

**T2をこのskillの合格証拠に使う場合、強制機構が無いことを証跡へ記録する。** 記録しないと、後からT1と同等の保証があったと誤読される。

### 0.3 T3 — 実装役にしない

理由は好みではなく能力である。

- **repositoryを読めない。** Cursor CLI経由のworkerは隔離された空ディレクトリで実行される（`cursor-grok` skill）。既存コードを読めない実装者に最小差分は書けない
- **テキストしか返さない。** 複数ファイルの差分を人手で転記することになり、転記段階で誰も検査していない改変が入りうる
- **sandboxもegress制御も無い。** §1-9の露出承認に対応する機構が存在しない

**T3が有用な局面はある。** §7の調査委譲、実装の照合、§6で症状の原因候補を挙げさせる用途——いずれも文脈をpromptへinlineで渡せば成立し、repository書込を要さない。**別系統のmodelを照合に当てると、実装modelの盲点が外から見える**ので、T1実装＋T3照合は積極的に組んでよい。

単一ファイルの局所修正に限ってT3を実装役にしたい場合は、所有者の個別承認を取り、生出力を証跡へ保存してから逐語転記し、転記前後のSHA-256を残す。**この手順を踏まない転記は実装者の成果物として扱わない。**

### 0.4 送信先の承認はworkerごとに取り直す

§1-9の露出承認は「Codexへ送ってよいか」ではなく「**この委譲先へ送ってよいか**」である。委譲先が変われば送信先事業者・認証channel・billing identity・データ所在が変わるため、**承認は自動的に引き継がれない**。

- T1: OpenAI
- T3 Cursor経由: Anysphere に加え、背後のmodel提供事業者（xAI / Moonshot / Zhipu / Google 等）
- T3 DeepSeek: DeepSeek

worker名・送信先・model ID・認証channelを証跡へ書き、**今回のjobについて所有者が承認した記録**を残す。前回の承認を流用しない。

### 0.5 途中で替えない

WP単位では最初に決めたworkerで通す。替えると、指摘の解釈も差分の前提も変わる。替えるなら証跡へ理由と、替えた時点で完了しているWPの範囲を書く。

## 1. 起動前検査

1. リポジトリroot、branch、HEAD、`git status --porcelain=v1 -z`を記録する。
2. 開始前からある変更と今回の所有パスを分ける。
3. 所有者が指定したworkerの階層（§0）、版、認証、採用model IDを確認する。指定が無ければ確認してから進む。
4. promptをファイルへ保存し、レビューしてから渡す。
5. `--skip-git-repo-check`は使わない。検証済みのGit rootを`-C`へ渡す。
6. 実装に必要な最小sandboxを選ぶ。分析だけなら`read-only`、実装なら`workspace-write`。
7. linked worktreeは使わず、`.git`がdirectoryであるdirect worktreeだけを使う。main worktree側のproject設定やhookが暗黙に発見される構成は委譲前に停止する。
8. promptはUTF-8の通常file、8 MiB以下、単一hardlink、reparseなしとする。機密fileへのhardlinkをpromptとして渡さない。
9. **指定workerの送信先へ**送信してよいprompt、repository、読取path、除外secret、account、modelをownerが承認した証跡を残す（送信先はworkerごとに違う。§0.4）。以下はT1（Codex/OpenAI）の場合の具体条件で、他階層では対応する機構が無いことを§0.2/§0.3のとおり記録する。Windowsのlegacy `read-only`/`workspace-write` sandboxは同じOS accountで読める全filesystemの読取を狭めない。無関係なsecretを持たない専用OS account/VMを使う。共有accountしか使えない場合は、読取可能な全local dataの理論上の開示をownerが今回明示承認しなければ委譲しない。

helperのDryRun/WhatIfはこの露出をplanへ表示するだけで起動しない。actualは承認証跡を確認した呼び出しだけが`-AllowWindowsAccountReadExposure`を付ける。switchが無ければhelperはworker起動前に停止し、workerもmetadataの承認値を再検証する。このswitchはfilesystemの読取を狭める機構ではなく、残る露出を受け入れたというauthority assertionである。

## 2. Codex CLIの起動

**本節はT1専用**（§0.1）。ここに書かれた署名検証・config隔離・環境allowlist・stream上限・metadata契約は同梱helperがCodexに対して強制するものであり、**T2/T3へは適用されない。他workerを使うとき本節を満たしたと書かない。**

OpenAI公式の非対話モードでは、prompt全体をstdinから渡すとき`codex exec -`を使う。`-`がEOFまで読んで終了するため、prompt引数と`< /dev/null`を併用する旧手順は使わない。

参照日: 2026-08-17

- https://developers.openai.com/codex/noninteractive/
- https://developers.openai.com/codex/cli/reference/

### PowerShell（同期・推奨）

以下のblockは、OS system directoryのMicrosoft署名Windows PowerShell 5.1 exact hostから起動し、`PSModulePath`をsystem built-in module directoryだけへ固定した使い捨て`-NoProfile -NonInteractive` controllerのbodyとして実行する。`Invoke-FreshCodexHelper`はDryRunとactualをそれぞれ別の新しいOS PowerShell processで起動する。同じprocess内でhelper scriptを2回直接実行したり、dot-sourceしたりしない。PowerShell 7、portable/copy host、profile/function/aliasを持つ既存sessionから同梱scriptを直接`&`実行しない。helper自身もsecurity-critical cmdletのcommand type/module provenanceを副作用前に検証し、shadowingがあれば停止する。各childの`-ExecutionPolicy Bypass`はexact attested scriptを起動する当該processだけに適用し、script trustの代わりにしない。

PowerShellでは同梱helperだけを公開起動経路にする。helperはraw pathをfilesystem probeより前にlocal ready fixed driveへ限定し、Git worktree/gitdir/common-dir、TEMP、evidence root、launcher directory、同梱script directoryをphysical canonical pathで分離する。linked worktree、UNC、device path、mapped/removable drive、reparse componentを拒否する。worker scriptは単一hardlink、canonical path、file identity、SHA-256をmetadataへ束縛し、起動handshakeまで変更・削除共有なしのhandleで保持し、worker自身も`$PSCommandPath`から再検証する。GitはGit for Windows publisherの有効なAuthenticode署名、CodexはOpenAI OpCo, LLCの有効なAuthenticode署名を要求し、path、SHA-256、thumbprint、product versionを固定する。Codexはnative `codex.exe`だけを許可し、`.cmd`/script wrapperを拒否する。launcher directoryをOS working directoryとして使い、repositoryはCLIの`-C`だけで渡す。

任意のGit起動より前に、direct `.git` directoryと`.git/config`をfilesystemから検証する。split common-dir、`config.worktree`、include/includeIf、外部path・command surfaceを拒否する。local configはstrict UTF-8、1 MiB以下、単一hardlink、file identity、SHA-256、安全key allowlistへ限定し、Git/Codex jobの生存中は変更・削除共有なしのhandleで保持する。system/global Git configは無効化し、workerも同じconfig contractを再検証する。

Git/Codexのpreflightは各30秒、出力は各stream 1 MiB、署名検査とpipe drainも期限付きで、故障launcherを無期限に待たない。DryRun/WhatIfはconfig-freeなversion/path/plan検証だけを行い、Codex config loaderを起動する認証・feature検査は`pending_actual_preflight`として報告する。これは`CODEX_HOME/memories`等をDryRunで作成させないためである。認証・feature検査はdata/read-exposure authority gate後のactualで初めて実行する。workerは同じphysical path・hash・署名・working directory・prompt bytes・Git bindingを再検証する。actual jobのstdout/stderr証跡は各64 MiBまでとし、超過後はpipeをdrainしながらjobを失敗扱いにする。actual jobはtimeout時も自動killしない。

helperはOS user profileから得たlocal-fixed/non-reparse `CODEX_HOME`を固定し、ambient `CODEX_HOME`を拒否する。`CODEX_SQLITE_HOME`、proxy、CA、base URL、token endpoint、organization/project等のegress・auth override、secretらしい環境変数、Rust診断overrideは拒否またはpositive allowlistから除去する。`CODEX_HOME/config.toml`、`AGENTS.md`、`AGENTS.override.md`等のuser instruction/config層も拒否する。preflight childへAPI keyを渡さない。Codex childはpositive allowlist環境で起動し、shell tool環境にはdefault secret除外を有効にしたcore policyをCLI設定で固定する。repositoryの`.codex/config.toml`とproject hookは存在してはならず、`--ignore-user-config`と`--ignore-rules`を固定する。

このhelperは監査済み`codex-cli 0.147.0`へexact pinする。upgrade時はflag/config/feature契約を再監査してpinを更新するまで`BLOCKED`とする。actualは`--strict-config`、`model_provider="openai"`、web search/skill instruction/bundled skill無効、network/TEMP write無効を固定する。apps、plugins、tool suggestion、memories、hooks、MCP app、browser/computer/image、multi-agent、unified exec、shell snapshot等の委譲に不要なoptional surfaceも固定disable listで止め、actual-only bounded feature preflightで名前を確認する。unknown config warningは成功扱いにしない。

Codex childとshell toolの`PATH`はattested Git directoryとtrusted OS directoriesだけにし、`PATHEXT=.EXE`、`NoDefaultCurrentDirectoryInExePath=1`、login shell/profile無効を固定する。両方の`PSModulePath`もexact system Windows PowerShell Modules directoryだけへ固定し、current directoryやuser module/profileから同名commandを探索しない。shell環境ではGit system/global config、terminal prompt、credential-manager interactionも無効化する。

ambient `CODEX_API_KEY`を採用するとaccount/billing identityが変わる。値の存在だけでは承認とみなさない。所有者が今回のjobで明示承認した場合だけ、同じ引数のDryRunとactualの両方へ`-AllowCodexApiKeyEnvironment`を付ける。値自体はmetadataやログへ保存せず、Codexが起動するshell toolへも渡さない。承認が無い場合、ambient keyが存在すればhelperは停止する。

`codex login status`は認証mode/成立だけのpreflightで、account名、organization、project、billing ownerを技術的に証明しない。所有者がCodex外の信頼できる画面または管理経路でaccount/billing identityを確認し、今回の承認証跡へ記録する。helperの成功だけからaccount identityを推定しない。

PATHからnative `codex.exe`を発見できない場合だけ、ownerが確認したabsolute native executableを`CodexPath`へ渡す。npmの`codex.cmd`や任意の`node.exe`へfallbackしない。発見できてもplanのexact path/hash/signature/versionを確認する。

```powershell
$skillDir = '<SKILL.md本文で展開済みの絶対path>'
$powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
$env:PSModulePath = [IO.Path]::Combine([IO.Path]::GetDirectoryName($powershellHost), 'Modules')
$helperScript = Join-Path $skillDir 'scripts\start_codex_job.ps1'
function Invoke-FreshCodexHelper {
  param([string[]]$Arguments)
  $value = & $powershellHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat XML -File $helperScript @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Fresh Codex helper process failed with exit code $LASTEXITCODE." }
  return $value
}
$jobId = [guid]::NewGuid().ToString('N')
$jobArgs = @(
  '-RepoPath', 'C:\work\my-roblox-game',
  '-PromptPath', 'C:\work\prompts\wp-03.md',
  '-OutputDirectory', (Join-Path $env:LOCALAPPDATA "ClaudeRobloxMvpEvidence\codex-jobs\$jobId"),
  '-Model', 'gpt-5.6', '-ReasoningEffort', 'high', '-Sandbox', 'workspace-write'
)
$plan = Invoke-FreshCodexHelper ($jobArgs + @('-DryRun'))
if (-not [bool]$plan.ok -or -not [bool]$plan.dry_run) { throw 'Codex DryRun failed.' }
$result = Invoke-FreshCodexHelper ($jobArgs + @(
  '-Wait', '-TimeoutSeconds', '1800', '-AllowWindowsAccountReadExposure'
))
if (-not [bool]$result.ok -or [string]$result.state -cne 'completed' -or
    [int]$result.exit_code -ne 0 -or [bool]$result.output_limit_exceeded) {
  throw 'Codex job did not reach completed/exit 0.'
}
```

### Bash（未対応）

このSkillはBashからのCodex委譲を自動実行しない。PowerShell helperが固定する署名、physical evidence boundary、`CODEX_HOME` instruction層、strict config、optional feature、shell/profile、Git config、network/TEMP、容量・timeout契約を同等に実装した監査済みhelperが無いため、手作業の`codex exec`例へ弱めず`BLOCKED`とする。Bash移植が必要なら別作業としてhelperを実装・監査し、このSkillの合格証拠には採用しない。

### PowerShell（非同期・高度な並列時だけ）

通常は前節の同期経路を使う。並列化が必要な場合だけ、同梱helperが有効なUTF-8 promptファイルのbytesを`codex exec -`のstdinへ渡してEOFを閉じ、hidden workerがstdout/stderr、PID、終了コード、状態遷移を保存する。`workspace-write`の子プロセスが証跡を改変できないよう、RepoPathとoutput ancestorのreparse pointを拒否し、Windows handleから得たphysical canonical pathでもoutputがGit repository、Git administration directory、OS temporary directoryの外にあることを確認する。

```powershell
$skillDir = '<SKILL.md本文で展開済みの絶対path>'
$powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
$env:PSModulePath = [IO.Path]::Combine([IO.Path]::GetDirectoryName($powershellHost), 'Modules')
$helperScript = Join-Path $skillDir 'scripts\start_codex_job.ps1'
function Invoke-FreshCodexHelper {
  param([string[]]$Arguments)
  $value = & $powershellHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat XML -File $helperScript @Arguments
  if ($LASTEXITCODE -ne 0) { throw "Fresh Codex helper process failed with exit code $LASTEXITCODE." }
  return $value
}
$asyncJobId = [guid]::NewGuid().ToString('N')
$jobArgs = @(
  '-RepoPath', 'C:\work\my-roblox-game',
  '-PromptPath', 'C:\work\prompts\wp-03.md',
  '-OutputDirectory', (Join-Path $env:LOCALAPPDATA "ClaudeRobloxMvpEvidence\codex-jobs\$asyncJobId"),
  '-Model', 'gpt-5.6', '-ReasoningEffort', 'high', '-Sandbox', 'workspace-write'
)
$plan = Invoke-FreshCodexHelper ($jobArgs + @('-DryRun'))
if (-not [bool]$plan.ok -or -not [bool]$plan.dry_run) { throw 'Codex DryRun failed.' }
$started = Invoke-FreshCodexHelper ($jobArgs + @(
  '-TimeoutSeconds', '1800', '-AllowWindowsAccountReadExposure'
))
$monitorDeadline = [datetime]::UtcNow.AddSeconds(1830)
do {
  $metadata = Microsoft.PowerShell.Management\Get-Content -Raw -LiteralPath $started.metadata_path | Microsoft.PowerShell.Utility\ConvertFrom-Json
  if ([string]$metadata.state -in @('completed', 'failed', 'timed_out_running', 'timed_out')) { break }
  Start-Sleep -Seconds 2
} while ([datetime]::UtcNow -lt $monitorDeadline)
if ([string]$metadata.state -notin @('completed', 'failed', 'timed_out_running', 'timed_out')) {
  throw "Bounded monitor expired; report worker/launcher PID and metadata path without killing the job."
}
if (-not [bool]$metadata.ok -or [string]$metadata.state -cne 'completed' -or
    [int]$metadata.exit_code -ne 0 -or [bool]$metadata.output_limit_exceeded) {
  throw "Async Codex job did not reach completed/exit 0; inspect metadata and retained process PID."
}
```

repository、Git administration directory、OS TEMP内、またはjunction/SUBST/8.3 alias等で物理的にそれらへ解決されるpathを`OutputDirectory`にしない。UNC、device path、mapped/removable driveも使わない。metadata schema version 3のphysical root、Git marker/commondir bytes、Git/Codex launcher contract、pinned `CODEX_HOME`、auth/environment/config contract、prompt length/SHA-256/hardlink identity、stream上限と実byte数を保存する。通常は`-Wait`と有限の`-TimeoutSeconds`を使い、返されたmetadataの`state`が`completed`かつexit code 0、`output_limit_exceeded=false`であることを要求する。並列起動のため`-Wait`を外す場合も、metadataとworker PIDを保持してterminal stateまで監視する。`failed`、`timed_out_running`、`timed_out`、stream上限超過は合格にしない。timeoutを超えたプロセスをhelperは自動強制終了せず、まずPIDと証跡pathを報告する。呼び出し側もmetadataだけを信用せず、worker終了後にstdout JSONL、stderr、実diffを確認する。

helperは既存directoryのACLを変更しない。同一OS userで動く別processは残るtrust boundaryである。ownerが事前に用意したACL保護directoryを使い、同じuserの別writerが動いていないことを確認する。これを保証できないmetadataは合格証拠にしない。

## 3. 指示文の必須項目

promptへ次を明記する。

```text
目的:
正本の仕様パス・版・数値ID:
開始HEAD:
変更してよいパス（完全列挙）:
凍結パス:
期待する最小差分:
受け入れテストIDと期待値:
pinされたbuild/parser/linterコマンド:
必要な構造化ログ:
禁止事項:
報告形式:
```

「必要なら周辺も直す」を書かない。許可外の変更が必要なら、変更せず理由と候補パスだけ報告させる。

## 4. 常設禁止条項

すべての委譲promptへ入れる。

- 正本に無いゲーム規則、閾値、時間、距離、倍率、人数を創作しない。
- Tier 0数値や既知欠陥の扱いを独断で決めない。
- 許可外ファイルを作成、削除、改名、移動、整形しない。
- `*.project.json`、lockfile、生成規則を許可なく変えない。
- 行頭が`(`で始まる型cast代入を書かない。

```lua
-- 禁止
(value :: SomeType).Property = nextValue

-- 使用
local typedValue = value :: SomeType
typedValue.Property = nextValue
```

- 無差別の`require`、client専用moduleのserver load、server専用moduleのclient loadをしない。
- 実行していない検証を、実行済み・合格と書かない。
- commit、push、publish、Studio操作をしない。ただしpromptで個別に承認した操作は除く。
- 失敗を握り潰さない。実行command、exit code、末尾出力、未実施理由を報告する。

## 5. 検証の分担

実装者へ実行させるもの:

- 許可パス内の差分確認。
- pinされたparser/linter。
- 同じ入力から別パスへ2回buildし、サイズとSHA-256一致。
- 対象テスト。
- 未実施・失敗の明記。

依頼側が必ず再実行するもの:

- 開始前台帳との差分と許可外変更の検査。
- 数値IDと実装値の照合。
- parser/linter。
- 依頼側自身のbuildとSHA-256照合。
- smoke manifestと節目の実機テスト。
- 実装者が示したcommand/結果の再現。

Rojo build成功はDataModel梱包の成功であり、Luau parseやmodule loadを証明しない。

## 6. 安全なmodule smoke

全ModuleScriptを列挙して同一セッションで`pcall(require)`しない。副作用、無限yield、client/server文脈違い、module cacheが受け入れ結果を汚す。

1. まず静的parser/linterを通す。
2. WPごとに`shared`、`server`、`client`の明示manifestを作る。manifestにmodule path、想定文脈、期待return型、許容副作用を書く。
3. server manifestはserver、client manifestは対象client、sharedは両方でsmokeする。
4. 1 moduleごとに開始・成功・失敗を記録する。外側のwatchdogで全体timeoutを設ける。
5. timeoutまたは副作用が出たら、その使い捨てセッションを破棄する。成功扱いにしない。
6. smoke後にStudioを再起動し、新しいセッションで受け入れテストを行う。

manifest外を「load可能」と主張しない。entrypointを通常起動して初めて見える経路は、実機受け入れで確認する。

## 7. 調査委譲

**全階層で使える。** repository書込を要さないため、T3（外部テキストworker）が最も活きる局面でもある。T3へ出すときは対象コード・ログ・実測値をpromptへinlineで渡す——向こうはrepositoryを読めない（§0.3）。

根本原因の調査だけを投げる場合はread-only sandboxにし（T1のみ機構として強制される。他階層は書込を与えない運用で担保する）、次を要求する。

- 確認済み命題と未確認命題を分離する。
- 根本原因が一意に決まるかを回答する。
- 決まらない場合は修正せず、次に測る最小probeを提案する。
- 推測、観測、仕様事実を別欄にする。

## 8. 受領と契約違反

受領時は報告より実diffを先に読む。許可外変更、数値創作、未実施検証の合格宣言があれば、その成果を受け入れない。

ユーザーの既存変更を巻き戻さない。契約違反部分だけを新しい最小差分で直すか、所有者へ判断を求める。
