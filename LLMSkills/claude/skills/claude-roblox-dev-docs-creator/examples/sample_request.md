# Sample invocation

```text
/claude-roblox-dev-docs-creator
新規Robloxゲーム。2v2の短ラウンド騎兵PvPで、モバイル最優先。馬と史実装備を収集するが性能非売。コンセプトから実装開始可能な文書体系を作成。
```

Expected behavior:

1. D0 asks only unanswered product/technical questions and records every D0-A01..A12/B01..B15 answer with value/status/source/evidence/approval metadata. Every normalized product/technical leaf is bound through `fieldSources`; free-form normalization equivalence is independently reviewed and covered by global human approval evidence.
2. GDD is produced and waits for explicit approval.
3. Mobile mounted controls trigger a Feasibility Gate.
4. Network, persistence, commerce, analytics, performance, assets, Multi-Place, physics, localization, LiveOps, and rights specs plus their machine-readable contracts are required.
5. Before initial D4, the sole proposed P0 closure inventory lives in `PROGRESS.md`; B0 freezes its historical bytes and P0-start approval matches that exact scope. P0 records closures in the P0-CAND `PROGRESS.md`, then post-P0 D4 requires zero inventory rows before B1.
6. D4 candidate → B0, P0 candidate → post-P0 D4 → B1, then human D5 approval → B2.
7. No implementation-ready claim before the validated W0 handoff package is sealed at D5.
