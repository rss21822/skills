# {{PROJECT}} — Human Actions

`[HUMAN]` は人間だけが実行する作業に限定する。AI実行候補は `[AI-ACTION]` として `AI_ACTIONS.md` に記録し、この台帳へ入れない。`Exec` は `human-only` 固定。`AI stop reason` は指示役が実行しない理由であり、実行主体ではない。`Actual evidence` と `Completed at` の両方が実在しない行を完了扱いにしない。

| ID | Action | Why human-only | Required evidence | Actual evidence | Owner | Due gate | Blocking | Exec | AI stop reason | Status | Completed at |
|---|---|---|---|---|---|---|---|---|---|---|---|
| H-001 | [HUMAN] Confirm project ownership and environment IDs | Dashboard/account permission | Screenshot or recorded IDs | — | Project owner | D2 | yes | `human-only` | `blocked-safety` | Open | — |
