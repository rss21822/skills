---
name: claude-roblox-mvp-buildout
description: 承認済みのRoblox仕様・データ定義・Work Packageから、MVPの通し実装、決定論ビルド、Studioの実機マルチクライアント検証、証跡作成までを行う。ユーザーが「MVPまで作る」「通しで実装して実機検証する」など、完成までの一連の作業を明示的に依頼した場合だけ使う。単発の不具合診断、HUDだけの修正、1つのWork Packageだけの実装には使わない。仕様が未承認なら先に仕様作成へ戻す。
---

# Roblox MVP 通し運行

承認済み仕様から、同一性を証明できる「実際に遊べるMVP」を作る。速さより、権限境界、再現性、実測証拠を優先する。

## 0. 適用範囲

- 明示的に承認された通し実装・ビルド・実機検証にだけ使う。
- 単発診断や1つのWPは `claude-roblox-development-delivery` へ回す。
- 数値定義、詳細設計、WP、受け入れテストが未承認なら `claude-roblox-dev-docs-creator` へ戻す。
- 本skillは公開を許可しない。Publish、外部配布、pushは所有者の別承認が必要。

## 1. 先に固定する権限

開始時に、実行IDと次の承認状態を証跡へ記録する。曖昧なら安全な作業だけ続け、該当操作は止める。

- 編集してよいリポジトリ、Worktree、パス、WP。
- OS入力注入、全画面キャプチャ、Studioプロセス終了、強制終了、デスクトップセッション切替、commit、push、publishの各可否。
- Codex/OpenAIへ送信してよいprompt・repository・path範囲、除外するsecret、model、認証channel、account/billing identity。Windowsの`read-only`/`workspace-write`は書込権限の差であり、同じOS accountで読めるローカルfileの読取・model送信範囲を狭めない。自動委譲は無関係なsecretを持たない専用OS account/VMで行う。共有accountしか使えない場合は、読取可能な全local dataの理論上の開示を所有者が今回明示承認しなければ`BLOCKED`とする。ambient `CODEX_API_KEY`は今回のjobへの所有者承認なしに採用しない。
- 全画面キャプチャ前は、機密ウィンドウを隠したことと今回の明示同意を確認する。
- `tscon` 等のセッション切替は自動実行しない。必要性だけ報告し、個別承認を待つ。
- 既知欠陥の受け入れ、MVP範囲からの除外、新しいゲーム規則、新しいTier 0数値は所有者だけが決める。提案はできるが、承認前のWPは未完了とする。

## 2. 開始ゲート

### 2.1 仕様とGitの基準点

次を取得し、[証跡テンプレート](references/evidence-template.md)へ記録する。

1. 数値所有文書、詳細設計、実装計画、WP、テストIDのパス・版・承認者。
2. `git rev-parse --show-toplevel`、branch、HEAD。
3. `git status --porcelain=v1 -z` の原文保存先と、開始前からある変更の台帳。
4. 今回所有するパスと、凍結するパス。

既存変更を上書き、整形、stageしない。commitが承認されても、所有パスだけを明示列挙してstageする。

### 2.2 能力のプリフライト

副作用を起こす前に、次を読み取り専用で確認する。

- OS、対話デスクトップ、PowerShell版、デスクトップセッションID。
- `RobloxStudioBeta.exe` の正規パスとStudio版。
- Studio MCPの列挙、Luau実行、コンソール取得。
- `StudioTestService` と `UserInputService:CreateVirtualInput()` の利用可否。
- Git、pinされたビルダ、Luau parser/linter、Codex CLIの版と認証。

不足を勝手にインストール、再接続、セッション切替して直さない。利用不能な検証は「未検証」に落とし、完了条件に必須なら停止する。

同梱security helperは、OS system directoryのMicrosoft署名Windows PowerShell 5.1 exact hostだけを許可する。`PSModulePath`をsystem built-in modulesだけへ固定し、1回のpublic helper invocationごとに別の新しい`-NoProfile -NonInteractive` processを使う。PowerShell 7、portable/copy host、同一processでの2回目呼び出しは副作用前にfail-closedする。

### 2.3 決定論ビルド

ビルダと依存版をpinする。同じHEAD・同じ入力から別の一時パスへ2回ビルドし、SHA-256とサイズが一致することを確認する。不一致なら実機検証へ進まない。

ビルド成功は梱包成功だけを示す。Luau構文、`require`、サーバー/クライアント実行は別に検証する。

## 3. WP運行

各WPを次の順で閉じる。

1. WPの許可パス、凍結領域、正本の数値ID、受け入れテスト、必要ログを固定する。
2. 委譲する場合は [委譲契約](references/delegation-contract.md) を使う。実装者の報告を証拠にしない。
3. 自分で開始前台帳との差分、許可外変更、数値の出所、構造変更を検査する。
4. pinしたparser/linterで静的検査する。
5. 2回ビルドのSHA-256一致を取り直す。
6. 明示したserver/client/sharedのsmoke manifestだけを、使い捨てStudioセッションでtimeout付きロードする。全ModuleScriptの無差別`require`は禁止する。
7. smokeセッションを終了し、新しい受け入れセッションを作る。module cacheや副作用を引き継がない。
8. 節目の実機テストを行い、独立した権威状態照会とクライアントUI照会をログへ対応付ける。
9. 証跡を更新する。commitは所有者が承認した場合だけ、所有パスを明示して行う。

節目は少なくとも、最初の入力→権威状態、最初の複数プレイヤー経路、最終統合の3点とする。

## 4. 実機検証

詳細は、実行前に [Studio自動化](references/studio-automation.md) を読む。

入力手段は次の順で選ぶ。

1. 現行Studioで利用可能なら `StudioTestService` と `VirtualInput` を使う。
2. それで対象経路を再現できない場合だけ、明示承認のうえ `scripts/studio_session.ps1 -Action Input` を使う。`studio_input.ps1`を直接呼ばず、確認済みclient role/place evidenceを直前に再検証する。
3. OS入力は対象PID・開始時刻・実行ファイル・セッション・exact main HWND・foreground HWNDが一致したときだけ送る。同一PIDのmodalへ送らない。同時操作を検証したことにしない。

Studioプロセスは、`scripts/studio_session.ps1` が候補として獲得し、独立handshake証拠でroleとartifactを確認した所有PIDだけを扱う。launch intentだけでroleやplaceを確定しない。他のStudioや他アプリを最小化・終了しない。

Studioのmanifest、handshake、coordinate/capture証拠、test artifactは、repository、Git administration directory、OS TEMPから物理的に分離したowner管理のlocal fixed `TrustedEvidenceRoot`へ置く。全actionへcaller-supplied exact Git root、trusted root、owner-approved signed Studio executable pathを渡す。同じSessionFileのactionはcross-session bounded interprocess lockで直列化し、timeout/abandoned lockは再試行せず停止する。外部副作用前のdurable pending-action journalが残った異常runも、自動再試行せずPID・manifest・outputを手動照合する。role/place evidenceは最大10分、coordinate evidenceはcaptureから最大5分で、期限切れなら新しいimmutable file・event/probeでrefreshする。同じOS userの別writerがStudio installation、同梱script、trusted evidenceを変更できる状態では実行しない。

画面取得は`scripts/studio_session.ps1 -Action Capture`だけを使い、対象ウィンドウを基本とする。low-level capture helperをpath実行しない。全画面は明示同意後だけ使い、仮想スクリーン原点を記録する。画像座標とOS座標を混同しない。

## 5. 証拠の作り方

構造化イベントログだけで合格にしない。各重要な主張を、次の独立した観測と組にする。

- サーバーの権威状態を直接読む。
- 対象クライアントのPlayer/UI実体を直接読む。
- 必要な場合だけ、対象ウィンドウ画像または録画を残す。

すべてを実行ID、テストID、build SHA-256、HEAD、Studio版、timestamp、event ID、PID/role/player対応表で相関させる。エラー0件や棄却0件は、検索範囲と件数を実際に数えた場合だけ証拠にする。

最終検証では、完成ビルドを複製した専用のテストartifactを保持し、可能ならread-only化する。canonical artifactをStudioで直接開かない。起動前後のSHA-256を比較し、変化したartifactの結果は無効にする。

## 6. 予想外の挙動

推測で直さない。

1. 無条件probeを出し、正しいserver/client出力を見ていることを証明する。
2. 症状を実測値とテストIDだけで書く。
3. 走行中セッションの権威状態、入力受理、wire上の値と型、UI実体を読み取る。
4. まだ一意に決まらない値だけ、一時診断ログで測る。
5. 原因が決まってから最小修正し、影響する出口条件を再実測する。

同じ症状で診断→修正→再実測を2巡して値が動かなければ変更を止める。所有者へ、範囲除外、既知欠陥の受け入れ、追加調査の選択を求める。依存しないWPだけは続行できる。

既知の候補は [Roblox実行時pitfalls](references/roblox-pitfalls.md) を参照する。各項目を現在版で再現せず、恒久仕様として断定しない。

## 7. 完了条件

次がすべて揃った場合だけ「MVP完成」と言う。

- 承認済み全WPとテストIDが合格している。
- 想定人数で、開始→主要操作→決着→終了→次ラウンド成立の全サイクルを通している。
- 主要規則を、構造化ログと独立した権威状態/UI照会の両方で確認している。
- 最終2回ビルドが一致し、そのSHA-256と同じ専用artifactを検証した。
- テストartifactの起動前後SHA-256が一致している。
- 実測したエラー件数、棄却件数、再試行回数を記録している。
- 暫定値、運行判断、観察事項、未検証事項、所有者承認を列挙している。
- 開始前の既存変更を混ぜていない。

ローカル同一PCの検証だけでは、実端末のタッチ、実ネットワーク、性能、同時入力、公開環境を保証しない。実施していない検証は明示して完了範囲から外す。

## 8. 同梱資材

- [委譲契約](references/delegation-contract.md): Codex CLI起動、実装契約、smoke manifest。
- [Studio自動化](references/studio-automation.md): 能力確認、セッションmanifest、入力、捕捉、後始末。
- [Roblox実行時pitfalls](references/roblox-pitfalls.md): version付き再現候補。
- [証跡テンプレート](references/evidence-template.md): 実行ごとの必須記録。

Claude Codeがこの本文へ展開した絶対path `${CLAUDE_SKILL_DIR}` を覚え、同梱scriptを呼ぶ各shell blockの先頭でshell文法に合うliteralとして `$skillDir` へ再設定する。これは環境変数ではないため、`$env:CLAUDE_SKILL_DIR` を参照しない。supporting referenceには置換されないので、reference中の `$skillDir` は必ずこの展開済み値から設定してから使う。公開起動経路はOS system Windows PowerShell 5.1 exact hostの新しい`-NoProfile -NonInteractive -ExecutionPolicy Bypass` processだけとし、`PSModulePath`をsystem built-in module directoryへ固定する。DryRunとactual、Listと次actionを含め、同梱helperの各invocationを別processへ分ける。profile/function/aliasを持つ既存shellからscriptを直接`&`実行しない。最初に `-DryRun` で引数と実行planを確認し、実操作は必要な個別承認後だけ行う。`-DryRun` がlive targetやgameplayを検証したとはみなさない。
