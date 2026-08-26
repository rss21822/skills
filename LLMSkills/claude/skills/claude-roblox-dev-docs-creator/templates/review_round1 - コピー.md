# 独立照合依頼 {ID} 1巡目 — {対象ファイル}

あなたは本文書の作成に関与していない**Class A gate照合者**。読み取り専用。対象file、正本、validator、test、evidenceを自分で再確認する。Class Bの場合、このtemplateを使わずsupplemental semantic reviewとして別記録にする。

対象: `{path}`（sha256 `{hash}`、{N}行）

正本: {上流文書と該当節を列挙}、規約 {document-system.md・trigger-matrix.md・テンプレート}

## 照合観点

1. **正本準拠** — 上流の転記が逐語で正確か。改変・欠落・創作がないか。{この文書固有の重点}
2. **独立再計算** — タグ集計（作成者申告: {FACT n / DECISION n / PROPOSAL n / OPEN yes n / no n}）を自分で数え直す。数値走査: {禁止している値の種類}が 0 件か。裸 `[OPEN]` が 0 件か
3. **`[DECISION]` 全行トレース** — 各出現に出所と人間承認記録が付いているか。`M` は evidence、`W` は URL と取得日、`U` は intake 項目へ遡れるか。`J` は判断理由・代替案・人間承認へ遡れるか。未承認提案や派生・写像を昇格していないか
4. **トリガ行の実質** — {trigger-matrix の要求項目} が実装可能な粒度で存在するか
5. **上流整合** — 上流の `[PROPOSAL]` を昇格していないか。所有境界（配達先 ≠ 数値所有先 ≠ 判断所有先）を侵していないか。二重正本がないか
6. **実装可能性** — 実装者がこの文書から作業へ落とせるか。未確定は独自決定ではなく gate へ誘導されているか

{以下は実測に依存する文書、または `[HUMAN]` 台帳を含む文書で使う}

7. **実測の妥当性** — 閾値ファイルのタイムスタンプが計測より前か。evidence に生出力が含まれているか（要約だけではないか）。判定が PASS/FAIL/INCONCLUSIVE の3値か（「概ね達成」のような中間表現がないか）。Studio 計測と実機の差が記録されているか
8. **実行主体の妥当性** — `[HUMAN]`がhuman-onlyか。`[AI-ACTION]`が別台帳・approval・evidenceを持つか。`blocked-safety`がAI実行へ寄っていないか

## 実行して確認すること

- validator を自分で実行する: `{command}`
- タグ・件数は自分で数える（申告値の検算）
- サンプル検査ではなく**全件**検査する
- **evidence の実在と中身を確認する**（パスが書かれているだけで中身が無い、要約しか無い、を見つける）
- **`J` 出所の分布を数える**（各 `J` 決定が人間承認へ遡れるか、未承認案が決定へ混入していないか重点確認する）
- 実行attestation（resolved model/version/finish reason/exit code）とbaselineを検証する

## 出力

観点別判定（PASS/FAIL ＋ 節参照根拠）、各所見の一意ID・監査track・Severity（Critical/Major/Minor/Observation）・Confidence・State tag、総合判定（承認可/差し戻し）。3軸を同じ欄へ混ぜない。

## execution

worker/class A、requested/resolved model、CLI/server version、read-only sandbox、network、request/response hash、finish reason、usage、exit codeをattestationへ保存する。

---

## 依頼を書くときの注意

**観点を列挙しないと形式検査に流れる。** 「レビューして」だけでは、テンプレート節の有無しか見ない。何を疑うべきかを渡す。

**申告値を渡して検算させる。** タグ集計や件数を「作成者はこう言っている」と添えると、照合者が数え直して食い違いを見つける。渡さないと数えない。

**未確定が多い文書では是正方針も渡す**（`review_roundN.md` の該当節を参照）。渡さないと「決めていないこと」を毎巡指摘される。
