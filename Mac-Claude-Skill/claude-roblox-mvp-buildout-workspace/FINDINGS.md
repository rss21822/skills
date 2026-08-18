# claude-roblox-mvp-buildout 評価記録

## 1. 過去評価の訂正

2026-08-16〜17のv1記述評価は、各eval/configurationを1回だけ実行した。`runs_per_configuration=3`と「3 runs each」は誤記だったため1へ修正した。

iteration-1:

- skillあり: micro 18/18 (100%)、macro平均100%。
- skillなし: micro 10/18 (55.56%)、macro平均58.41%。
- tokenはper-eval `timing.json`から復元した。合計はskillあり296,130、skillなし272,649。
- modelとskill pathは記録されていない。

iteration-2-fresh:

- skillあり: micro 20/20 (100%)、macro平均100%。
- skillなし: micro 14/20 (70.00%)、macro平均71.43%。
- time/tokenは未収集。JSONの0は測定値でなくsentinel。
- modelとskill pathは記録されていない。

1回/セルなので、ばらつき、速度差、token差、因果効果は推定できない。

## 2. v1評価を現在版へ流用しない理由

v1には現在の公式仕様と合わないassertionがあった。

- 「OS入力が常に必須」: 現行Studio公式は`StudioTestService`と`VirtualInput`を提供する。現在版skillはこれを先にprobeし、OS入力を承認付きfallbackにした。
- 「background CLIはprompt引数に`< /dev/null`必須」: 現行Codex CLIはprompt file全体を`codex exec -`のstdinへ渡す。stdin file/pipeのEOFで閉じる。
- global process count、wildcard process操作、全ModuleScriptの無差別`require`、canonical artifactの直接openは安全性と証拠同一性が不足していた。

したがってv1の100%は履歴であり、現在版skillの合格証明ではない。

## 3. 現在の評価定義

`evals/evals.json`をschema v2へ更新した。7件を非破壊の記述評価として定義した。

- 単発HUD診断で本skillを起動しないrouting。
- Scripted testing優先と個別承認gate。
- launch intentと確認済みrole/placeを分離し、clientを1台ずつ確認し、独立evidenceを操作直前に再検証するgate。
- repository/Git administration/TEMP外のlocal fixed trusted evidence root、物理分離したattested script tree、署名済みStudio inventory path、schema v7 manifest、期限付きrole/place・coordinate evidence。
- OS system Windows PowerShell 5.1 exact host、public actionごとのfresh process、SessionFile単位のcross-session bounded mutex、crash後のdurable pending-action journal、同一user writer不在を前提にしたStudio entry trust契約。
- session-only memory snapshotによるOS input/window・fullscreen captureと、low-level helperのdirect実行拒否。
- `codex exec -`の監査済みWindows PowerShell helper経路。Bashは同等helperが無いため`BLOCKED`。
- workspace-writeの子から隔離したphysical background証跡、direct worktree限定、signed Git/native `codex.exe`、trusted launcher directory、pinned `CODEX_HOME`、bounded worker/metadata schema v3。
- project Codex config/hooksとegress/auth overrideをfail-closedにし、未承認API key・ambient secretをpreflightやshell toolへ継承しない委譲契約。
- `codex-cli 0.147.0` exact pin、strict OpenAI config、network/TEMP無効、optional feature/shell profile/current-directory searchの固定disable契約。
- promptの単一hardlink・8 MiB上限、preflight各1 MiB、job stdout/stderr各64 MiBの容量境界。
- session manifest外processを操作しないこと。
- exact test artifactと起動前後hash。
- 新規ゲーム規則と既知欠陥waiverのowner権限。
- Remote payloadの型を実測するsilent failure診断。

これらは評価定義であり、現在版Skillを実行した結果ではない。forward runを行う場合は、exact prompt、model、Skill tree SHA-256、output、grader、反復数を新しい証跡へ保存する。記述評価はStudio、OS入力、capture、process close、commit、push、publishを実行してはならない。

## 4. まだ言えないこと

- 現在版skillで実際のRoblox MVPを通し構築した実績。
- Windows legacy Codex sandboxによるexact read-root隔離。`read-only`/`workspace-write`は同一OS accountのfull local readを許すため、actual委譲は専用secret-free account/VMまたはownerの明示的な全local読取露出承認を前提にする。
- Studio版ごとの`StudioTestService`/`VirtualInput`利用可否。
- OS入力fallbackの実機成功率。
- 複数回反復した評価の分散。
- 現在のschema v2定義に対するforward evalのpass率。
- 実端末、実ネットワーク、公開環境の品質。

現在版の完成判定は、Skill構文、PowerShell構文、静的安全検査、DryRun、非破壊forward評価の結果と、上記未検証範囲を分けて記録する。

## 5. 2026-08-18 完成版の静的・非破壊検証

完成版script SHA-256:

- `start_codex_job.ps1`: `2ff1ff4653637b363e1b4be7f1b41e2a21f262364a8499b55c3f4d8185b4c6e2`
- `codex_job_worker.ps1`: `2f6899f04fc5db37dac9386de6b55d491c5f61ca0da21e91e20f0b2414735f3a`
- `studio_session.ps1`: `5fd9256b5c5bc8736d59aad1e4a09273a7d78af0fd400a891968d30c13a64809`
- `studio_input.ps1`: `513d463b8aa389d5a3f21fadc7effe473aa5dc92ac2067e9b1126f96a198a923`
- `studio_capture.ps1`: `1aee7a07f77478a4d3f6b9309b2891ef4ee9658aed23fe316d8503fe201f2792`

確認結果:

- Windows PowerShell 5.1.26100.9168とPowerShell 7.6.4で5 scriptsのparser error 0。
- Markdown内PowerShell 14 blocksのparser error 0。
- Skill validator合格、workspace JSON 42/42 parse、eval schema v2・7件。
- strict UTF-8 12/12 files。旧schema v6、repo内evidence root、batch client、固定座標、low-level input/capture直接実行、Bash Codex実行例の残存0。
- fresh PS5 Preflight、Input DryRun、Capture DryRunとCodex helperの非実行回帰を確認。実Studio起動、OS入力、capture commit、WM_CLOSE、`codex exec` actualは実行していない。

残余前提は、Studio installation・trusted evidence・同梱scriptへ書ける同一OS userの別writerが不在であること、ownerがtrusted rootと入力fileを管理すること、巨大な誤配置trusted fileによる可用性低下余地である。schema v2 evalのforward run、実際のRoblox MVP通し構築、Studio版ごとのUI fallback成功率は未実証であり、完成版Skill自体の検証結果と混同しない。
