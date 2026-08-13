# Handoff {ID}b — {対象} 是正（{N}巡目 Critical n・Major n・Minor n）

| 項目 | 値 |
|---|---|
| handoffId | `{ID}b` |
| baseline | sha256 `{現行 hash}`。スナップショット `docs/handoffs/out/{ID}_pre_correction_*` |
| 照合記録 | `docs/handoffs/out/{ID}_review{N}.md`（{全文精読 / 該当節のみ精読で可}） |

## 方針（未確定事項が多い場合に明記する）

推測で閉じない。是正は次の2種に限る:

- **(A) 上流から構造として確定可能なものを閉じる**
- **(B) 確定不能なものは、実装者が独自決定も全面停止もしないよう、明示的な gate 付きレジスタへ変換する**

どちらでもない曖昧な状態を残さないことが判定基準。

## 是正指示

### Critical/Major {n} — {見出し}

{照合記録の指摘を、実行可能な単位へ分解して列挙する。
 照合者の言い回しをそのまま渡さず、「何をどう変えるか」に翻訳する}

1. …
2. …

### Minor — {見出し}

…

## inScope

- `{path}` のみ（または横断是正なら対象ファイルを全列挙）

## 制約

- 新規数値なし（識別子・field 名・token は数値ではないので可）
- Status は `Draft` を維持
- 上記に列挙した是正点に必要な最小限。無関係節の変更禁止
- 実施していない検証を書かない。検証語彙の自己使用禁止
- 報告に**変更前 → 変更後**と実測 sha256

## execution

model `{model}` / reasoningEffort `high` / sandbox `workspace-write` / approvalPolicy `never` / network `false`

## rollback

スナップショットから復元

---

## 是正 handoff を書くときの注意

**照合指摘をそのまま転送しない。** 照合者は「何が悪いか」を書くが、執筆モデルに要るのは「何をどう変えるか」。翻訳を挟まないと、執筆モデルが解釈で埋め、別の欠陥が入る。

**スナップショットを先に取る。** untracked ファイルには `git checkout` が効かないため、これが唯一の rollback 手段になる。

```bash
cp {target} docs/handoffs/out/{ID}_pre_correction_$(basename {target})
```

**巡が進むほど handoff は小さくする。** 3巡目で1ハンクだけの是正になるのは正常。大きいままなら、指摘の絞り込みが足りていない。

**契約側の誤りは契約を直す。** handoff の指示自体が間違っていた場合（範囲指定ミス等）、成果物を歪めず handoff を訂正して記録する。照合依頼にも「発注側の記載ミスを訂正した」と明記して、照合者が旧契約で判定しないようにする。
