# Roblox市場分析 → ゲーム企画設計：Codex Skill

バージョン：1.0.0  
作成日：2026-09-17  
Skill名：`roblox-market-to-design`

## 何をするSkillか

Robloxの現在市場とジャンル史を調べ、競合の仕組みを分解し、自作ゲームの「何を維持・変更・削除・検証するか」を決めるためのSkillです。

市場データの収集だけでなく、初回体験、コアループ、ラウンドとセッション、低人数での成立、友人との遊び、SNSで伝わる見せ場、課金、継続運営、試作・実装への引き継ぎまで扱います。

汎用版 `content-market-to-design` とは別名の独立版です。両方を置けますが、Robloxの同じ依頼に対して両者の全工程を重複実行する必要はありません。汎用版を先に導入する必要もありません。

このパッケージは**調査と設計の実行手順**です。最新ランキングや特定ゲームの分析済みデータ、ヒット保証、Roblox Studioプラグインを含みません。

## Roblox専用にした点

| 分野 | このSkillで具体的に検討すること |
|---|---|
| 市場と歴史 | 長期定番・新興・同型比較・歴史的転換点・Roblox外の源流を比較する |
| 突出する価値 | 斬新さだけでなく、操作感、UI/UX、再戦の速さ、社会性、音・物理、自己表現、作り込みを評価する |
| 差別化と再定義 | モチーフ変更、機能追加、改善、構成変更、組み合わせ、引き算、目的・役割の再定義を区別する |
| プレイ構成 | 初回の意味ある操作、行動・ラウンド・マッチ・セッション、敗退後の待ち時間、再戦と途中参加を分解する |
| 少人数での成立 | 最初の1人、2人、最低成立人数、通常人数を分け、モード追加の人口分散も比較する |
| 友人・SNS | 一緒に入る理由、技能差、助け合い、見せる価値、本編から自然に発生する短尺の見せ場を設計する |
| 公開値と内部値 | Visits・CCU・DAU・継続率・売上を混同せず、非公開値を推測で埋めない |
| プラットフォーム仕様 | Discovery、Analytics、課金、価格、Teleport、性能、権利等を、必要な範囲で実行時に公式確認する |
| 課金・運営 | 買いたくなる理由、無料体験、公平感、限定モードと別Place化、通常時の再訪、制作・運営負荷を評価する |
| Codexへの引き継ぎ | 承認済み事項と未承認の提案を分け、試作、状態遷移、責務、計測、復旧、受け入れ条件へ落とす |

## 同梱物

```text
roblox-market-to-design/
├── SKILL.md
├── agents/
│   └── openai.yaml
├── assets/
│   ├── project-brief.template.md
│   ├── competitor-card.template.md
│   ├── research.schema.json
│   └── research.template.json
├── references/
│   ├── research-protocol.md
│   ├── roblox-design-lenses.md
│   ├── metrics-and-discovery.md
│   ├── differentiation-playbook.md
│   ├── monetization-and-feasibility.md
│   ├── validation-and-handoff.md
│   ├── output-contract.md
│   ├── official-sources.md
│   └── acceptance-tests.md
└── scripts/
    ├── validate_research.py
    └── render_dashboard.py
```

`SKILL.md` 単体でも基本手順を実行する構成です。テンプレート、詳しい分析軸、データ検証、HTML生成を使う場合はフォルダー全体を配置してください。

## インストール

### プロジェクト単位

ZIPを展開し、`roblox-market-to-design` フォルダーを次の場所へコピーします。

```text
<プロジェクトのルート>/.agents/skills/roblox-market-to-design/SKILL.md
```

階層を重ねすぎないようにします。例えば `.agents/skills/roblox-market-to-design/roblox-market-to-design/SKILL.md` にはしません。

### ユーザー共通

```text
macOS / Linux:
~/.agents/skills/roblox-market-to-design/

Windows側で動くCodex:
$HOME\.agents\skills\roblox-market-to-design\
```

`$HOME` はユーザーホームを表します。WSL内のCodexとWindows側のCodexではホームの場所が異なるため、実行している側へ配置します。既存の同名Skillは無断で上書きせず、退避・差分確認をしてください。

Codex CLI・IDE拡張では `/skills`、または入力欄の `$` から認識を確認できます。検出されない場合は配置を確認し、必要に応じてCodexを再起動します。製品ごとの画面は変更される場合があります。

配置・起動方法の確認元（2026-09-17）：OpenAI公式「Build skills」

```text
https://developers.openai.com/codex/skills/
確認時の転送先： https://learn.chatgpt.com/docs/build-skills
```

この配布物を受け取っただけでは、お使いのCodexへのインストールは完了しません。

## 最初の実行例

資料パスは実際に存在するものへ置き換えてください。企画を文章で直接渡しても使えます。入力テンプレートを全部埋める必要はありません。

```text
$roblox-market-to-design

制作中のRobloxゲームの企画は docs/project-brief.md にあります。
この資料を読み、モードfull、深度deepで実施してください。

まず、私の企画で決めるべき重要な設計項目を整理してください。
直近2年間の市場と、それ以前のジャンル史を調べ、
長期定番、新しい成功例、同型の比較対象、Roblox外の源流を比較してください。

特に検討したいのは、初回体験、ラウンド構成、敗退後の待ち時間、
再戦、最初の1人・2人での成立、友人と遊ぶ理由、SNSの見せ場です。
モチーフ変更と遊び方の再定義を分けて評価してください。

固定条件は維持し、暫定案は現状維持を含む代替案と比較してください。
公開情報から分からない継続率・売上・広告費は推測で埋めないでください。
重要な事実には出典を付け、反証と制作・運営負荷も示してください。

元の企画書とゲームコードはまだ変更しないでください。
成果物は research/roblox/my-project/ に作成し、
分析・設計判断・検証計画を参照できるローカルHTMLも生成してください。
```

出力先も例です。同じ場所に既存成果がある場合は、無断上書きせず別の実行フォルダーを使います。

## 用途別の指定

`mode`、`depth`、`focus` はこのSkillが依頼文から読む指定値で、Codex CLI固有の引数ではありません。

| 指定 | 用途 |
|---|---|
| `full` | 調査から設計、集客・運営、検証・引き継ぎまで |
| `research-only` | 自作企画未定。市場機会と検証までで、作品仕様を確定しない |
| `audit` | 既存案の重要判断へ絞ったレビュー |
| `refine` | 前回成果と新条件を読み、影響する部分だけ更新 |
| `standard` / `deep` | 調査の広さと深掘り量の目安。件数は水増ししない |

`focus` は `history / differentiation / core-loop / session / ftue / social / hooks / monetization / discovery / feasibility` から複数選べます。省略時は目的に必要な軸を選びます。

### 既存案のレビュー

```text
$roblox-market-to-design
モードaudit、深度deep。
入力は docs/game-spec.md。
focusは differentiation / session / social / feasibility。
コア操作は固定し、人数・試合構成・再戦導線は再検討してください。
改善案を採用済みにはせず、試作で確かめる順序まで示してください。
```

### 企画が未定の場合

```text
$roblox-market-to-design
モードresearch-only、深度deep。
対象はRobloxの協力サバイバルです。
現在の人気作品と歴史的源流を比較し、まだ届いていない需要を探してください。
競合が見つからないことと、需要があることを区別してください。
自作の仕様は確定せず、市場機会と最小の検証方法を示してください。
```

### 前回結果を更新する場合

```text
$roblox-market-to-design
モードrefine。前回成果は research/roblox/my-project/previous-run/ にあります。
D001の選択肢D001-O2を採用し、D003は保留します。
制作期間を短縮する条件を追加し、影響する判断と検証計画を見直してください。
既存IDと棄却理由を残し、JSON・Markdown・HTML・変更履歴を同期してください。
元のゲームコードは変更しないでください。
```

パスとIDは実際の前回成果に置き換えます。存在しないIDや未読の資料を引き継いだことにはしません。

## 生成されるもの

原則として、ブリーフ、市場と歴史、競合分析、設計判断、集客と運営、検証と引き継ぎの6種類のMarkdown、根拠をIDでつないだ `research.json`、調査ログ、変更履歴、`dashboard.html` を作ります。

ダッシュボードは閲覧専用です。検索とIDリンクで、提案から根拠・出典・テストへ移動できます。コメントを反映するときはCodexへ指示し、JSONを更新して再生成します。画面自体に編集・保存機能を装っていません。

「AIの推奨」と「ユーザーが承認した案」は別項目です。承認のない提案で元の仕様やコードを書き換えない手順にしています。

## Python補助ツール

任意です。Python 3.10以降の標準ライブラリのみを使い、追加パッケージの導入は不要です。PythonがなくてもSkill本体の調査・設計手順は利用できます。

```text
python "<skill-dir>/scripts/validate_research.py" "<run-dir>/research.json"
python "<skill-dir>/scripts/render_dashboard.py" "<run-dir>/research.json" --out "<run-dir>/dashboard.html"
```

`<skill-dir>` と `<run-dir>` は実際の場所へ置き換えます。既存HTMLは通常上書きしません。更新を許可された場合に限り、退避したうえで `--overwrite` を使えます。

検証器は構造・参照・欠損・承認などの整合性検査です。出典の実在、実際の閲覧、承認の真正性、企画の成功を確認するものではありません。任意のJSON Schemaへ対応する汎用エンジンでもありません。

## 実行環境と限界

Web調査にはCodex側の検索・閲覧機能と許可が必要です。実機検証には別途RobloxクライアントやStudio等へのアクセスが必要です。このSkillが機能・アカウント・権限を追加するわけではありません。

公式仕様は実行時に再確認します。固定の推薦攻略数値、普遍的な継続率の合格点、推定ヒット確率は持たせていません。非公開の競合データは未知として残します。

入力ブリーフ・未公開企画・認証情報を外部へ送らず、ゲーム参加、購入、広告、投稿、公開、プラグイン導入などは依頼・許可の範囲外で実施しません。

## この配布物で確認した範囲

作成環境で、次を実行しています。

- YAML形式、Skill名と起動文、JSON Schemaの形式、空のテンプレートと架空フィクスチャの検証。
- 必須項目、参照切れ、循環、非公開値への数値混入、欠損理由、承認不整合、不正URL、HTMLの文字列エスケープ、上書き防止など、**41件の構造・補助プログラム検査**。
- Chromiumで、生成HTMLの表示、検索、クリア、IDリンク、欠損表示、スクリプト注入防止、外部自動通信なし、320px・375px幅での横はみ出しなど、**16件のブラウザー検査**。
- Markdownの同梱参照、UTF-8、Python構文、ZIP構造・読み出しを確認。

ブラウザー環境が `file://` を制限していたため、HTMLの表示検査はPlaywrightの文書注入で行いました。ファイルのダブルクリックによる起動テストとは区別してください。

**実際のCodexによるSkill選択から市場調査完了までの通し実行、実在するRobloxゲームのプレイ検証は行っていません。** `acceptance-tests.md` は導入環境で試すためのケース集です。検査用の架空データや画像は配布パッケージに含めていません。
