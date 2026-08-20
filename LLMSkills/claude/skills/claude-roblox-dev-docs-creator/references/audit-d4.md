# D4 受入監査の実行手順

本書は **D4 監査をどう走らせるか**を所有する。**D4 の定義**（3系統の責務名・合格条件・出口語彙）は `phase-definitions.md` §7 が所有する。両者を混ぜない。

監査の起動機構（同一セッションで実行しない理由）は SKILL.md §4 stage router が所有する。

## 0. この工程の性質

- **findings-only / read-only。正本文書を一切修正しない**
- 初回 D4 の出口語彙は `D4合格 / P0着手資格あり（人間P0開始承認待ち）` または `D4不合格 / D0〜D3是正へ`
- post-P0 D4 の出口語彙は `post-P0 D4合格 / B1昇格可 / D5提示可能` または `post-P0 D4不合格 / P0是正へ`
- **`実装に入れる` / `implementation ready` は使わない**（D5 前のため）

自分が書いた文書を監査する場合も、**経緯を知らない読者として**評価する。clean-room 観点の比重が高いのはそのため。

実運用で、一見よく整備された文書群から次が見つかった。

- ルートの必須3ファイルが削除されていて30箇所以上の参照が切れていた（この状態では最初のテストが定義上必ず失敗する）
- ツールチェーンが Windows 専用 API を前提にしていたが開発機は macOS だった
- 12個の決定ペアが定義されているのに、実際に有効化できる仕組みは3個分しかなかった
- 素材の制作主体を AI に割り当てているのに、AI が 3D モデルを作る手段がどこにも定義されていなかった

いずれも通読では気づきにくく、実装を始めてから詰まる類のもの。

## 1. 指示役が audit capsule を作る

repo 全体の探索と clean-context 監査を同じ主体にさせない。

### 1.1 指示役だけが行う repo preflight

指示役は監査者を起動する前に project root で次を実行し、生出力を `docs/evidence/d4/<candidate-id>/preflight/` へ保存する。

```bash
git status --short --untracked-files=all
git log --oneline -5
rg --files -g "!.git/**"
```

文書・machine-readable instance・関連 validator/evidence の所在は `rg --files` の全 inventory から確定し、`docs/` を決め打ちしない。`rg` が無い場合だけ同等の read-only inventory command を使い、command 名・cwd・exit code を保存する。削除された参照先があれば、指示役が `git show HEAD:<path>` の生出力を保存する。**監査者へ project root の自由探索を許可しない。**

### 1.2 明示 allowlist

指示役はまず `d4_audit_policy_manifest.schema.json` に従い、実際にinstalledされたskillのpolicy componentとrequired validator scripts／全local importsをrehashし、built-in compilerが出すlane別check ID/argv/cwd/exitとprompt compilation ruleをmanifestへ固定する。validatorはinstalled skill rootから同じ値を再導出し、project copyや任意commandを信用しない。監査実行用code/schema/configはsanitized root内`_policy_runtime/`へimmutable copyし、installed hashとexact一致させる。監査者はinstalled skill rootを読まず、このcopyとoperator-pinned Python executable/stdlibのclosed read-only runtime allowlistだけを使う。次に `schemas/d4_audit_capsule.schema.json` に適合する JSON を `templates/d4_audit_capsule.json` から生成する。各入力には元の project-relative `sourcePath`、sanitized root 内の immutable copy を指す `capsulePath`、`bytes`、`sha256`、`role` を記録する。candidate ID／manifest path／manifest hash／file-set hash、sanitized root、runtime allowlist digest、3件以上の repo preflight argv と生出力 hash、policy ref、固定 deny category、candidate stageからfilterしたlane別 `requiredAuditCommands`（track／global-unique check ID／exact argv／cwd／expected exit）も同じ JSON に閉じる。D4-CANDは`all|initial`、P0-CANDは`all|post-p0`だけを選び、callerのmode申告だけを信用しない。role は次の4種。

- `canonical`: formal documents、operating files、machine-readable contract instances
- `validation`: 対応 schema、lint/validator config、実行を許可する validator/test と version/hash
- `evidence`: canonical が明示参照する生 evidence
- `repo-fact`: preflight の tree/status/log、削除参照先の抽出など、指示役が保存した read-only 出力

`validation` / `evidence` / `repo-fact` は製品判断の正本ではない。監査者が正本として引用しないよう role を保つ。

initial D4 では、candidate の canonical operating file `PROGRESS.md` にある **Proposed P0 closure inventory** も `canonical` role で渡す。各未決を source ID/path で一意に照合するこの台帳は candidate と同じ file set に含まれ、B0 昇格時に不変固定される。D4 合格後、`p0_start_handoff.md` はその B0 内 section と historical file hash を参照し、製品内容の変更範囲を同じ inventory 行だけへ限定して人間本人へ提示する。これに固定の P0 検証・記録・管理WP・candidate固定手続だけを加えて初めて P0 開始承認を得る。別紙の未署名 inventory を作って二重正本にしない。

監査者へ渡さないもの: 会話履歴、worker 名、迷った経緯、期待判定、E0 capability probe、handoff 会話、過去の findings / audit 出力、自己評価。deny 対象を単に manifest から落とすだけでなく、capsule root 外を読めない read-only scope にする。

capsule を schema 検証し、policyをinstalled sourceから再導出し、全 `capsulePath` が `sanitizedRoot` 配下にあり、記録した bytes/hash が実 bytes と一致し、`canonical` の `sourcePath` 集合が candidate manifest の canonical file set を完全に覆い、check/argv setがpolicyの該当lane/modeとexact一致することを確認してから固定する。3系統へ**同じ candidate manifest、policy、capsule path/hash**を渡す。監査者は allowlist の explicit file と、その lane の request が列挙する required argv だけを読み・実行し、repo-wide `git status` / `find` / `git show`、glob 展開、親 directory 探索をしない。repo 状態は `repo-fact` の生出力を検算対象にする。

### 「壊れている」と「まだ作っていない」を分ける

**コードや成果物が無いこと自体は欠陥ではない。** 実装未着手なら正常。ここを間違えると、正常な状態が大量の重大指摘として返る。

| 状況 | 扱い |
|---|---|
| `scripts/build.sh` が無い。実装未着手 | **正常**。観察として1行記録する程度 |
| 文書が「`scripts/verify.ps1` を唯一の検証入口とする」と規定し、そのOSが実環境と違う | **欠陥**。手段が実行不能 |
| `src/` が空 | **正常** |
| テストが root `CLAUDE.md` を検査するが、どの文書もその内容を所有していない | **欠陥**。仕様の穴であって未実装ではない |

見分け方: **実装すれば解消するなら正常。実装しても解消しない（何を作ればいいか決まらない）なら欠陥。**

## 2. 3系統を並列で走らせる

同じ audit capsule から3系統を同時実行する。各 lane では、まず `templates/d4_audit_request.json` のclosed `requestCore`だけを、unique lane run、track、candidate/capsule/policy/runtime ref、fixed purpose/write/context/deny、policy-filtered check IDsと共にcanonical JSON化して固定する。installed policy components・該当checklist・findings template・fixed safety contract・canonical requestCoreを定義順に結合し、**orchestratorが明示送信する全role text/attachment descriptors**のprompt bytesを作る。そのprompt path/hashを最後にouter request wrapperへ加えてouter request hashを固定し、promptへouter wrapper/hashを入れない。provider内部の非公開implicit frameはartifactへ捏造せずexternal runtime authorityの境界とする。external provenanceはactual submitted prompt hashとouter request hashの両方を束縛する。任意prompt、追加message、前会話、prompt省略はgate inputにならない。`D4-CAND-*` の `mode` は必ず `full`。`P0-CAND-*` は §6 に従い `delta` または `full` だが、同capsuleの3 laneで一致させ、どちらもB0 historical source、candidate全canonical set、machine diff、dependency closure、candidate由来の全機械checkを渡す。`mode`で入力やcheckを削らず、full escalation条件を見落としたdeltaは監査findingにしてpassさせない。各 lane へ他監査者の出力を**渡さず**、互いの所見・期待判定・過去巡も見せない。責務名と担当範囲は `phase-definitions.md` §7 が所有する。

| 観点 | 見るもの |
|---|---|
| 整合性 | 二重正本、参照切れ、版の不一致、状態タグの残存、変更伝播の欠落 |
| clean-room | 過去の会話を知らない AI が、D5 authorization 後に最初の candidate WP を追加製品判断なしで W0 へ受け渡し、W0 provenance/permission gate後だけ開始できるか |
| Roblox readiness | サーバー権威、Remote 検証、永続化、課金、性能予算、モバイル入力、公開・復旧 |

**clean-room は特に効く。** 「この文書を初めて読む人が着手できるか」は、書いた本人には見えない。過去所見を先に渡すと追認へ誘導されるため、独立出力の保存前には見せない。

各監査には、指摘を根拠付きで Critical / Major / Minor に分けて出させる。**監査者に修正させない。** 指摘と修正を同じ主体がやると指摘が甘くなる。

各 raw response は `templates/d4_findings.md` の field／Coverage／Commands／Execution facts を埋めて無編集保存する。worker 完了後、指示役は `templates/d4_auditor_attestation.json` から lane ごとの attestation を作り、`schemas/d4_auditor_attestation.schema.json` で検証する。attestation は unique lane run／runtime execution／clean session ID、Class A、検証済み resolved model、clean context、read-only sanitized root、同じ capsule、実際に検査した capsule copies、required commandの**完全一致集合**と生出力、structured request artifact、**保存済み raw response の実 hash**、時刻、正常な `finishReason: stop` を束縛する。次にoperator管理の外部configへpinされたruntime queryまたはsignatureを検証し、同じactual factsを`provenance_verification`へ束縛する。local attestation文字列だけではlaneを合格にしない。3 laneのrun／execution／session、request／response／attestation／provenance IDとpathはすべて相互に異ならなければならない。raw response へ未来の attestation/provenance hash を後書きせず、循環参照を作らない。

独立出力・attestation を全て保存した後だけ、指示役が重複所見を根本原因単位へ統合する。反証・severity 変更は capsule 内の根拠を示し、元出力を上書きしない。3系統のうち1つでも Critical / Major を残したまま、多数決で合格にしない。summary の自己申告件数だけを信用せず、`## Findings` の Severity／Status から件数と open Critical/Major を再導出する。

raw report の対象欄は監査時の `D4-CAND-n` または `P0-CAND-n` と candidate manifest hash を記す。合格後に B0/B1 へ昇格しても raw report の対象名を編集しない。昇格 baseline の3件の `auditRecords` が raw response path/hash、全 lane 共通の capsule path/hash、lane 固有の attestation path/hash、external provenance path/hash、candidate baseline ref を同時に束縛する。昇格記録側が `promotedFrom` と candidate manifest hash を束縛し、candidate と baseline の **file-set hash** が一致することを検証する。ID 等が異なる2 manifest 自体の hash 一致は要求しない。

保存先は `docs/audits/<PREFIX>_d4_<lane>_<candidate-id>_r<N>.md`。3 lane と全 run を別 file へ無編集保存する。BROWNFIELD Repository Audit、handoff、correction note と混在させない。

詳しい観点は `audit-dimensions.md`。

## 3. 過剰厳密化を見分ける

AI 生成の設計文書には、目的に対して手段が過大になる傾向がある。**この監査で最も価値のある判断がここ。**

**兆候**: 実装がまだ存在しない段階で、そのコードの詳細（データ構造のフィールド、ハンドルの扱い、プロセス制御の手順）まで文書が決めている。1つの目的のために何十行もの検証手順が書かれている。手段が特定 OS や API に強く依存している。

**判定方法**: その仕組みが**何を保証するためにあるか**を1〜3個に言語化する。次に、その目的が手段の1割程度のコストで達成できないかを考える。達成できるなら過剰。

実例: ある文書は「lint の標準ライブラリが固定され、CI がネットワークに依存しない決定論」を保証するために、OS 固有のサンドボックス機構・ファイルディスクリプタ継承の遮断証明・プロセスグループの終了確認まで規定していた。目的3点は「設定ファイルのハッシュ一致・ツールのバージョンとバイナリハッシュ照合・CI コマンド列に取得コマンドを含めない契約」で達成できた。

**ただし勝手に削らない。** 過剰厳密化は指摘として報告し、簡素化の是非はユーザーが決める。統制を落とす判断だから。

## 4. 所見を報告する

**所見の件数は品質ではない。** 読む側が必要とするのは「何から手を付けるか」。症状を並べるほどその判断は難しくなる。

報告を書く前に、所見を**根本原因ごとにまとめる**。実運用で、116行の文書群に対して重大所見12件を出したことがある。うち11件は1つの構造的原因（正本境界が宣言だけで機能しておらず、ID 参照が実際には解決していない）の症状だった。値の矛盾を個別に直しても再発する。この場合、根本1件＋その症状として11件を束ねるほうが、読み手は正しく動ける。

報告の分量は対象に見合わせる。小さな文書群に長大な報告を返すと、重要な指摘が埋もれる。

**監査結果は状態記録であって正本ではない。** この位置づけを報告書自身に書く。矛盾したときは各正本が優先する。

含めるもの（節の順序と番号は `findings-report.md` の構成に合わせる）:

- 総評 — 2〜4文。初回は `D4合格 / P0着手資格あり（人間P0開始承認待ち）` または `D4不合格 / D0〜D3是正へ`、post-P0 は `post-P0 D4合格 / B1昇格可 / D5提示可能` または `post-P0 D4不合格 / P0是正へ` の結論
- 重大所見（対処が必須）— 根拠、影響、対処方針
- 軽微所見（D0〜D3 是正候補。D4 では直さない）
- 観察（対処不要、記録のみ）
- ギャップマップ — 標準的な文書体系に対して何が存在し、何が分散所有され、何が欠落しているか
- **決定要求** — ユーザーが決めないと進めない項目。選択肢と推奨を添える
- 実行環境実測 — 文書が前提とする OS・ツール・バージョンと実環境の照合結果を `[FACT]` で

未決は `[OPEN blocking: yes|no]` として残す。`blocking: yes` なら進捗記録の blocker 欄にも登録する。**片方だけだと追跡が切れる。**

書式は `findings-report.md`。

## 5. initial D4 の差し戻し

initial D4 は正本文書を編集しない。**Critical または Major が1件でもあれば `D4不合格 / D0〜D3是正へ`** と判定し、根拠・影響・修正方向を findings として返す。指示役が監査本文を保存し、執筆役へ `templates/correction_handoff.md` で是正を発注する。post-P0 は §6 の別規則を使う。

initial D4 の是正後は新しい immutable `D4-CAND-(n+1)` と capsule を作る。**initial D4 の再監査は毎回 fresh clean context の3系統 full audit。** 過去 findings、差分、前回 PASS 観点を渡さず、residual-only にしない。post-P0 の再監査は §6 のcandidate-derived delta／full escalationをfresh 3系統で再実行する。文書単位照合の2巡目以降だけが residual-only。

3系統すべて Critical = 0 / Major = 0 で監査条件を満たした `D4-CAND-n` だけ、同一 file-set hash の **B0** へ昇格し、`D4合格 / P0着手資格あり（人間P0開始承認待ち）` と返す。これは P0 作業の資格判定であり、P0 を開始するには B0 を対象とした別の人間本人承認が要る。**この語彙は D5 の「W0引渡し可能」と異なる。**

初回 D4 で P0 対象の未決が残ること自体を欠陥にしない。ただし各未決が `PROGRESS.md` § Proposed P0 closure inventory に source ID/path で一意登録され、正確に境界づけた P0 closure question/scope・owner・closure evidence/pass rule・影響正本を持ち、W0 実装を前提にせず P0 内で閉じられることを検査する。Gate 1 が承認した intake/GDD を変える項目は P0 inventory に入れず、D0/D1 から new Gate 1 route へ戻す。代替案と推奨はこの固定された問いを入力に P0 の CR 起草で作る。これ以外の blocking open/proposal/assumption は Major 以上。post-P0 D4 では残数 0 に加え、B0 historical inventory の全 ID が candidate `PROGRESS.md` の Completed record、actual evidence、影響正本の post-change hash へ一対一で解決されることを独立再計算する。

修正方向として**独立文書の安易な新設を勧めない**。標準文書が無いように見えても既存正本が機能を分担していないか確認し、所有者がいればそこへの改訂、いなければ新設を提案する。D4 自身はどちらも実行しない。

## 6. post-P0 D4 差分再監査

P0 は B0 の canonical 内容を変更するため、P0 完了だけでは D5 へ進めない。

1. B0 を parent とする immutable `P0-CAND-n` を固定する
2. B0 / candidate の manifest と機械生成 diff を作る
3. changed canonical file、そこから到達する下流参照、test/WP/traceability、machine-readable instance、index/manifest を dependency closure として allowlist 化する
4. fresh clean context の3系統が B0→candidate の差分と closure を検査する。過去 D4 findings は渡さない
5. 各系統 Critical = 0 / Major = 0 なら、同一 file-set hash の B1 へ昇格し、`post-P0 D4合格 / B1昇格可 / D5提示可能` と返す

いずれかの系統に Critical / Major があれば P0 改訂役へ差し戻す。是正後は B0 を同じ parent とする新しい `P0-CAND-(n+1)` を固定し、監査者へ過去 findings を渡さず3系統を fresh context で再実行する。旧 candidate / raw report は上書きしない。再実行も次の escalation 条件に従い、条件に該当しなければ B0→新 candidate の delta D4、該当すれば full D4 とする。文書単位の residual-only は使わない。

差分監査は residual-only 是正照合ではない。**B0 と candidate の意味差分を独立に検査する D4 gate**。最初に approved intake bytes、そこから再導出したrequired specs bytes、GDD bytes/path/revision、Gate 1 scope/record/capture/provenance refs が B0 と candidate で完全一致することを再計算する。不一致は P0 の許可範囲外であり full D4 によって追認しない。現 candidate を不合格にし、D0/D1 → unique new Gate 1 → D1.5/D2/D3 → new initial D4/B0 へ戻す。これらが一致し、なお次のいずれかなら差分範囲を限定できないため full D4 へ昇格する。

- canonical owner / precedence / trigger 判定の変更
- approved intake／required specs／GDD を変えない D2/D3 の Non-Goals、製品判断、D/F、security boundary の変更
- first candidate WP の開始契約・gate topology の変更
- dependency closure が欠落・循環し、全影響先を列挙不能
- allowlist 外変更、manifest/hash 不一致、validator warning/note

B1 成立前は `D5提示可能` と書かない。

## 7. 監査が発散したら

再監査のたびに新しい重大指摘が出続けるなら発散している。実運用で3巡（Major 6→3→5）発散した。

原因はほぼ**「実装前に実装詳細を文書で完全に閉じようとしている」**。実際に書いてみないと分からないことを先に決めようとすると終わらない。

対処は §3 と同じ。目的まで戻り、手段を簡素化する案をユーザーと執筆役へ出す。この判断をした後、指摘は 3→1→0 と単調に収束した。

逆に、指摘が実害（テストが定義上必ず落ちる、pin が実効を持たない、存在しないオプションへの依存）を指しているなら、巡が増えても健全。根拠を保ったまま差し戻す。

文書単位照合の巡ごとのスコープ規約は `review-protocol.md` が所有する。D4 gate は §5 の fresh/full、post-P0 は §6 の B0→candidate delta / full escalation 規則を優先する。
