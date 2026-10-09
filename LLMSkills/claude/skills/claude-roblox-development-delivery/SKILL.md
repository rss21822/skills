---
name: claude-roblox-development-delivery
description: 承認済みの単一Work Packageまたは局所的なRoblox修正を、bounded handoff、所有者指定worker、独立照合、必要なStudio実測、D6文書同期、Last Known Good記録まで閉じるdelivery workflow。既存の上位仕様・権限・委譲・rollback契約を継承し、弱めない。複数WPを通したMVP一式、ゲーム全体の構築、最終統合サイクルは明示的に対象外で、claude-roblox-mvp-buildoutへ送る。仕様未承認や製品判断を含む変更は実装せず、claude-roblox-dev-docs-creatorへ戻す。
---

# Roblox Single-WP Delivery

承認済みの単一WPまたは局所修正を、最小差分、独立検証、再現可能な証拠で閉じる。workerへ投げること自体ではなく、実装者の自己申告から独立して差分・テスト・Studio状態を照合することが中心である。

## 0. 適用範囲と上位契約

開始前に次を確定する。

1. **範囲**: 一度に1 WP、または同じ契約境界に収まる局所修正だけを扱う。複数WP、MVP全体、開始から決着までの通し実装、最終統合は `claude-roblox-mvp-buildout` へ送る。
2. **正本**: 承認済み仕様、WP、受け入れテスト、数値所有文書の版を記録する。未承認なら `claude-roblox-dev-docs-creator` へ戻す。
3. **継承**: 呼出元、プロジェクト、`claude-roblox-dev-docs-creator` が定める権限、D0〜D7、handoff、worker、証拠、rollback契約を継承する。本skillの例で上位契約を置換・緩和しない。競合時はD7へ進み、都合のよい側を選ばない。
4. **所有範囲**: repository、direct worktree、branch、変更許可path、凍結path、既存変更を固定する。ユーザーの既存変更を上書き、整形、stageしない。
5. **baseline**: HEAD、`git status --porcelain=v1 -z`の原文、所有pathと既存変更の台帳を保存する。開始時点がcommitで表せない場合は、差分、未追跡物、各SHA-256を束縛したimmutable snapshot IDを使う。

### 0.1 D5 handoff provenance — 最初に fail-closed 検証

`Approved` header や会話上の申告だけで開始しない。`claude-roblox-dev-docs-creator` が生成した `docs/evidence/d5/<D5-ID>_w0_handoff_package.json` を必須入力とし、同梱 schema と実ファイルから次を再計算する。

1. `d5Approval.id` が `DECISIONS.md` の人間本人による直接承認へ解決し、承認対象が `baselines.b1.id` / manifest hash と一致する。
2. `p0.startApprovalId` / `p0.contractApprovalId` / `d5Approval.id` が別 ID で、`postP0D4Records` の3系統記録が同じ `P0-CAND-n` を指し、各記録の Critical / Major が0。その候補と `baselines.b1` は `promotedFrom` と同一 file-set hash で結ばれる。
3. B1 content baseline と B2 post-sync baseline の manifest file SHA-256を再計算し、package が外側から束縛した値、parent関係、各 path / bytes / SHA-256と照合する。B1→B2 は formal header/change-history、運行記録の規定追記、最初のWP authorization、生成物だけを許し、その他の製品仕様bodyはbyte-identicalであることを確認する。
4. post-sync docs manifest / index の file set・version・statusがformal headerと一致する。
5. 対象WPの ID / path / SHA-256が package の `firstAuthorizedWp` と一致し、Status `Approved`、`Authorized by` が `d5Approval.id` を参照する。

package欠落、schema不一致、hash不一致、参照未解決、古いbaseline、許可外差分が1件でもあれば、code・Studio・OSへ副作用を起こさず `claude-roblox-dev-docs-creator` のD5同期へ戻す。package作成を本skill側で補完しない。

副作用前に creator 同梱validatorを**自分で**実行し、exit code 0以外を開始不可とする。

```powershell
$docsCreatorSkill = (Resolve-Path -LiteralPath 'C:/Users/ryufu/.claude/skills/claude-roblox-dev-docs-creator').Path
$projectRoot = (Get-Location).Path
if (Get-Command python -ErrorAction SilentlyContinue) { $pythonExe='python'; $pythonPrefix=@() }
elseif (Get-Command py -ErrorAction SilentlyContinue) { $pythonExe='py'; $pythonPrefix=@('-3') }
else { throw 'Python interpreter not found' }
& $pythonExe @pythonPrefix (Join-Path $docsCreatorSkill 'scripts\validate_d5_acceptance.py') --project-root $projectRoot --source-project-root $projectRoot --prefix '<PREFIX>' --package 'docs\evidence\d5\<D5-ID>_w0_handoff_package.json'
if ($LASTEXITCODE -ne 0) { throw 'D5/W0 provenance validation failed' }
```

## 1. workerと送信権限

**実施workerは所有者が今回指定する。既定worker、既定model、暗黙fallbackを置かない。** 指定時にworker、model ID、reasoning、sandbox、network、exact tool version、認証channel、account/billing identityを記録する。

workerへ渡す前に、送信先ごとに次の所有者明示承認を取る。

- prompt本文、repository、読取可能path、変更可能path。
- 除外するsecretと、共有Windows accountで理論上読めるlocal data。
- 送信先事業者、model、認証channel、account/billing identity。
- 今回のjob IDと承認時刻。worker変更時は承認を取り直す。

worker階層、露出gate、検証分担は [共通委譲契約](../claude-roblox-mvp-buildout/references/delegation-contract.md) を継承する。

### 1.1 Codexを指定された場合

- T1実装は、共通委譲契約が指定するexact-pinned `scripts/start_codex_job.ps1` helperだけを使う。
- helperを迂回したCLI直接起動、グローバル設定依存、package managerによる未pin版の導入、自動upgrade、未監査版へのfallbackは禁止する。
- helperのexact pin、署名、config隔離、送信承認gateのどれかが不成立なら `BLOCKED`。pinを書き換えたり、その場でinstallしたりしない。
- helperのDryRunとactualは別processで行い、actualは所有者が承認した送信・露出条件だけを渡す。

Codex以外を指定された場合も、そのworker階層に存在しない強制機構を「同等」とみなさない。T2/T3の許可範囲と依頼側再検査は共通委譲契約どおりとする。

## 2. WP workflow

```text
上位契約・baseline確認
  → bounded handoff
  → owner指定workerが実装
  → 依頼側が差分・testを再実行
  → 必要ならStudio実測
  → owner指定の別session/workerで独立照合
  → D6同期
  → owner承認済みcommit または immutable LKG snapshot
```

各段階の詳細:

- handoffとBLOCKED対応: [Handoff契約](references/handoff-contract.md)
- 独立照合: [独立照合](references/independent-review.md)
- Windows/現行Roblox Studio MCP: [Studio MCP](references/studio-mcp.md)
- 実測値、Evidence、PII: [Evidence](references/evidence.md)

handoffは正本の版、baseline commit/snapshot、in/out scope、受け入れテスト、pin済みcommand、owner指定worker、送信承認ID、commit方針を含める。許可外変更が必要なら実装せず、候補pathと理由だけ報告させる。

## 3. 依頼側の責務

依頼側は実装者と検証者を分ける。

- 正本を読み、単一WPのbounded handoffを書く。
- workerの最終報告を証拠にせず、開始前台帳とのdiffと許可外変更を自分で検査する。
- pin済みparser/linter/test/buildを自分で再実行する。
- Studioが必要なら、明示した `studio_id` とDataModelを使って実測する。
- 実装に参加していないowner指定session/workerへ独立照合を依頼する。
- D6同期とLKGを確認する。

依頼側も数値、hash、ID、版、URL、件数を創作しない。取得不能なら `[OPEN] blocking: yes|no` と取得責任者・時期・方法を記録する。

## 4. 独立再検査

少なくとも次を依頼側が実行し、生出力とexit codeを保存する。

```powershell
git status --short
git diff --stat
& <project-approved-test-command>
Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath <important-file> -Algorithm SHA256
```

build成果物は、同じHEAD/snapshotと入力から別pathへ2回生成し、サイズとSHA-256が一致することを確認する。実装workerの検証commandや抽出コードをそのまま独立再計算へ流用しない。

## 5. D6 — WP完了同期

WPは次を同じrevisionで更新・照合した場合だけ完了とする。

1. コードと自動テスト。
2. 必要なStudio実測とEvidence。
3. `PROGRESS`。
4. `CHANGELOG`。
5. 要件・WP・test・Evidenceを結ぶ `Traceability`。
6. 実装で具体化または影響を受けた仕様書。
7. Last Known Good commitまたはimmutable snapshot。

文書同期を「実装後の任意作業」にしない。影響仕様書の変更が製品契約を変えるなら、その場で編集を確定せずD7へ進む。

### 5.1 Last Known Good

commit、stage、pushは所有者がそれぞれ今回明示承認した場合だけ行う。独立照合PASSやhandoff完了はcommit承認の代替ではない。

- **commit承認あり**: 所有pathだけを完全列挙してstageし、LKG commit SHAを記録する。
- **commit承認なし**: HEAD、開始snapshot、所有差分、未追跡物一覧、変更後ファイルhash、test/Evidence hashをowner管理のimmutable snapshotへ保存し、LKG snapshot IDを記録する。

snapshotはrollback基準であり、commit済みと表現しない。push、publish、production書込は別承認である。

## 6. D7 — 契約競合とChange Request

コード、test、Studio実測、上位文書の間に契約競合を見つけたら、現在のWPを停止する。コード側を正本にして続行しない。

1. CRを作り、競合した契約、観測事実、選択肢、影響範囲を記録する。
2. 影響する仕様書、WP、test、`Traceability`、`PROGRESS`、`CHANGELOG`を更新対象として列挙する。
3. 承認された結論を上流正本へ取り込み、影響文書・test・traceabilityを同期する。
4. 影響範囲に対してD4監査を再実行する。
5. P0開始承認、D5実装開始承認のうち影響するgateを所有者から再取得する。major変更はD4、P0、D5すべてを再承認する。
6. 必要な再承認が証跡化されるまで、実装再開、Studio再検証、次WP着手をしない。

## 7. 並行編集とBLOCKED

ユーザーの並行編集は外部イベントとして台帳へ追記し、worker起因差分と分ける。勝手にcommitへ整理したり、既存変更をstageしたりしない。scope検査はworkerが変更したpathを判定対象にするが、重複編集で所有差分を安全に分離できなければ停止する。

同じ理由でBLOCKEDが反復する場合、値や権限を推測で補わない。不足する正本、承認、worker能力、送信権限を明示して所有者へ返す。独立照合が発散する場合も、上位契約の目的まで戻り、変更が必要ならD7を使う。
