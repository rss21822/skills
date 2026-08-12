---
name: claude-roblox-development-delivery
description: Roblox開発をFable（指示）とCodex CLI（実装）の分業で進めるワークフロー。Fableがbounded handoffを書き、Codex（gpt-5.6-sol / reasoning high）が実装し、別Codex sessionが独立照合し、Roblox Studio MCPで実機検証してからcommitする。Robloxのコード実装・Luau・Rojo・.rbxlx・Studio確認・Codexへの実装依頼・handoff発行・独立レビュー・Evidence記録・Studio Playでの動作確認のいずれかが話に出たら必ずこのskillを使う。ユーザーが「Codexで実装して」「Studioで確認して」「rbxlxを作って」と言った場合はもちろん、Robloxプロジェクトで単に「実装して」「直して」と言われた場合も対象。
---

# Roblox Codex Delivery

FableとCodexの分業でRobloxを開発する。Fableは指示と検証、Codexは実装。**このskillの価値の中心は「AIに自分の仕事を検証させる構造」**であり、Codexに投げること自体ではない。実運用で、この構造は偽clean経路・見せかけPASSのテスト・実効性のないバージョンpin・存在しないCLIオプションへの依存といった、実装だけでは絶対に見つからない欠陥を捕まえた。

## 0. 開始ゲート

作業前に2つ宣言する。ここを飛ばすと、後から「どのモデルが何をしたか」を再構成できなくなる。

**モデル宣言**: このsessionのモデルをユーザーへ伝える。自己モデルを確実に検証する手段はない（`/model`で切り替えてもsystem promptは旧情報のまま残る）。だから「宣言」であって「検証」ではない。宣言と実態の乖離に後から気づいたら、進捗ファイルへ訂正行を追加する（既存行は上書きしない）。

**Codex pin確認**: グローバル既定は本skillのpinと異なることが多い。起動ごとの明示が必須。

```bash
codex --version   # 未導入なら npm install -g @openai/codex@latest
```

Codexは `gpt-5.6-sol` / reasoning `high` で起動する。既定値への暗黙依存はhandoff違反として扱う。

**プロジェクト側に既存の規約があるなら、それが優先。** 設計文書に handoff 契約や役割境界が既に定義されているなら、このskillはそれを置き換えない。skillは手順の骨格であって正本ではない。規約が無いプロジェクト（新規、引き継ぎ、小規模）では、skillがそのまま規約として機能する。

## 1. ワークフロー

```
正本を読む → handoff発行 → Codex実装 → Fableが検証
  → 別session独立照合 → 差し戻しなら是正 → 承認可 → commit
                                    ↓
                         Studio確認が要るなら実機検証を挟む
```

各段階の詳細は必要になった時点で参照する。

- handoffの書き方とCodexがBLOCKEDを返したときの対処 → `references/handoff-contract.md`
- 独立照合の起動と、照合が発散したときの判断 → `references/independent-review.md`
- .rbxlx作成からStudio Play検証まで → `references/studio-mcp.md`
- 実測値・Evidence・PII → `references/evidence.md`

## 2. Codexの起動

```bash
cat handoff.md | codex exec \
  --model gpt-5.6-sol \
  -c model_reasoning_effort="high" \
  -s workspace-write \
  -o /path/to/last-message.md \
  - 2>&1 | tail -10
```

数分〜十数分かかるので `run_in_background: true` で起動し、完了通知を待つ。最終メッセージは `-o` のファイルに入る。

読取レビューは `-s read-only`。ネットワークが要る作業（`rokit install` 等）だけ `-c sandbox_workspace_write.network_access=true` を足す。既定ではネットワークは遮断されている。

**Codexサンドボックスの制約**: 内側で `sandbox-exec` は使えない（`sandbox_apply: Operation not permitted`、exit 71）。入れ子サンドボックスを前提にした検証設計は成立しないので、そういう要求が正本にあれば実行主体を外に出す。

## 3. Fableがやること・やらないこと

Fableは**コードを書かない**。書くのはhandoffと、検証・記録・判断。これは能力の問題ではなく、実装者と検証者を分けるための構造上の役割分担。

Fableの仕事:
- 正本（設計文書）を読み、実装可能な単位へ分解する
- handoffを書く（必須項目を満たす。`references/handoff-contract.md`）
- Codexの報告を鵜呑みにせず、自分でも検証コマンドを走らせる
- 別sessionへ独立照合を発注し、結果を記録として保存する
- Studio検証を実施する（MCP経由）
- 承認可になったらcommitする

Fableがやらないこと:
- 数値・hash・ID・バージョンの創作（実測しないなら `[OPEN]` として残す）
- 設計文書の直接編集（文書追従もCodexの仕事。ユーザーの明示指示がある場合は例外だが、その差分も照合対象として記録する）
- 自分の実装を自分でレビューして「照合済み」と記録すること

## 4. 検証は自分でも走らせる

Codexの最終報告は要約であり、証拠ではない。報告を受けたら、少なくとも次は自分で実行する。

```bash
git status --short          # 変更範囲がhandoffのinScope内か
git diff --stat             # 想定外のファイルが混ざっていないか
<プロジェクトの検証コマンド>  # CI・lint・build
shasum -a 256 <重要ファイル>  # 不変であるべきものが不変か
```

実運用で、Codexの報告と実態が食い違ったことはなかった。それでも走らせるのは、食い違いが起きたときに気づける唯一の手段だから。

## 5. commitのタイミング

**handoffが承認可になるたびにcommitする。** 溜めない。

未commitの変更が積み上がると、baseline（どの状態からの差分か）が識別できなくなる。作業ツリーが変更を含むとき、単なる `git diff` のhashでは足りない。handoffごとにcommitしてclean HEADを維持すれば、baselineは常にcommit hashで一意に決まる。

commitメッセージには、何を実装したかに加えて**独立照合の結果**を書く。後から「これは検証済みか」を追跡できる。

```
feat: <実装内容>

- <主要な成果物と、それが満たす契約>
- <実測値: hash、件数、テスト結果>

独立照合N巡(<記録path>)、最終承認可(全指摘0)。
```

## 6. ユーザーの並行編集

ユーザーが同じリポジトリを同時に編集していることがある。Codexがそれを「スコープ外の変更」として検出し、作業を止めることがある。

これは正しい振る舞いだが、放置すると無限ループになる。Fable側で個別commitへ整理し、handoffには「scope判定はCodex起因の変更のみで行う。ユーザーの並行編集は報告のみでBLOCKEDにしない」と明記する。

## 7. 詰まったときの判断

**Codexが同じ理由で3回以上BLOCKEDを返す** → handoffの情報が足りない。追加で当てずっぽうを書かず、何が欠けているかをユーザーへ確認する。

**独立照合が巡を重ねるごとに新しいMajorを出す** → 発散している。指摘が実害を指しているか、形式的厳密さを求めているかを見分ける。後者なら、正本が要求する「目的」まで戻り、手段を簡素化する提案をユーザーへ出す。判断基準は `references/independent-review.md`。

**実装前に実装詳細を文書で完全に閉じようとしている** → これが発散の典型的な原因。実際に書いてみないと分からないことを文書で先に決めようとすると終わらない。目的（決定論・pin・非依存性など）だけ固定し、手段は実装から確定させる。
