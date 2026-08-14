# Handoff {ID} — {CR-ID} の起草（{対象の一言}）

> **これは差分雛形。** 基本の必須項目（`objective`／`dataIds`／`acceptance`／`commands`／`execution`／`rollback` と常設条項）は `claude-roblox-dev-docs-creator` の `templates/handoff.md` が正本。そちらを土台にして本書の P0 固有部分を重ねる。本書だけで発行すると必須項目が欠ける。

| 項目 | 値 |
|---|---|
| handoffId | `{ID}` |
| phase | P0（contracts/bootstrap） |
| 実装モデル | {model} |
| baseline | commit `{hash}`（作業ツリー clean） |
| 起票根拠 | {どの open／決定から来たか。open の所在を file:節 で示す} |

## 0. 目的と、この便が起草に留まる理由

`docs/handoffs/{CR-ID}_{slug}.md` を **Status `Proposed`** で新規起草する。対象は {何を決めるか}。

**本便は起草のみ。正本の改訂も承認も行わない。** 理由: {なぜ分けるか。例: 複数 Spec にまたがる採用判断なので、判断材料を揃えてから決裁するのが順序として正しい}

## 1. 起草前に読むもの（この順で）

1. {open の所在}
2. {人間作業台帳の該当行}
3. {関係する正本を、依存の上流から順に}
4. {現行 Work Packages の該当 WP。割当提案の根拠になる}
5. 体裁の先例として `docs/handoffs/{直近の CR}.md`

## 2. CR に含める内容

1. **Problem**: 現状の事実。**既存文書からの転記**にし、新たな対象を作らない
2. **論点の分解**: 「◯◯をどうするか」が単一の問いでないなら、**分けて提示する**。分解自体が価値であり、論点を漏らさない
3. **選択肢**: 各論点に最低2案。**現行文書の実記述から根拠3点以上**で比較し、推奨を明示する。根拠を示せない案を創作しない
4. **既存決定との衝突確認**: 各案が承認済み `[DECISION]` に触れるかを確認する。触れるなら「選択するには追加設計が必要」と書き、**何を決めれば選択可能になるか**を列挙する
5. **影響 inventory**: 改訂対象の文書・WP・**欄**を列挙する。closure evidence が要求する欄（`Create` だけでなく `Objective`／`Public interfaces`／`Automatic tests`）を漏らさない
6. **closure 経路**: 承認 → 実改訂 → 一致確認 → closure、の時点と条件。**承認だけでは closure しない**ことを明記
7. **Approval gate**: `[OPEN blocking: yes]`。承認者は「`[HUMAN]` Project Owner、または{委任決定 ID}に基づき委任された AI」

## 3. 制約

- **値を創作しない**（rate・payload・閾値・Remote 名・schema の field）。本 CR が扱うのは{割当／方式}であって値ではない
- 関係正本を**1バイトも変更しない**（起草便のため。baseline sha256 で不変を証明）
- `src/`・`projects/`・`config/`・`contracts/`・`tests/` を作成しない
- 裸 `[OPEN]` 禁止（`blocking: yes|no`・理由・closure evidence・Owner を併記）。決定 ID 完全修飾。二重正本禁止
- **未確定を確定として書かない。** 材料が足りない論点は「決めるには何が要るか」を書いて止める

## 4. inScope

`docs/handoffs/{CR-ID}_{slug}.md`（新規）／`PROGRESS.md`（Current handoff、`[FACT]`）／`CHANGELOG.md`

## 5. 報告

作成パス、実測 sha256（**不変対象を含む**）、`git status --short`、論点分解の要約と各論点の推奨、validator と lint の実出力（baseline 悪化不可）。実施していない検証を書かない。commit・push 禁止。起草できない論点があれば明記する。
