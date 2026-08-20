# P0 の承認記録と状態検査

本書は P0 工程の2つを所有する。

1. **承認記録の構造**（内訳の正本一元化・決定 ID・委任下の承認）
2. **`check_p0_state.py` の検査内容と設定**

承認タグそのものの定義（`[DECISION]` / `[AI-APPROVED]` の作成主体）は `quality-gates.md` 第2部が所有する。本書はその**運用**を扱う。

---

# 第1部 — 承認記録・委任・正本の一元化

P0 は選択の記録が多い。Change Request 1件で6群の選択を確定することもある。**記録の構造を間違えると、後から選択を変えたときに片側更新が起きる。**

P0 開始承認は `templates/p0_start_handoff.md` で人間本人へ B0 と許可 scope を提示し、`DECISIONS.md` に記録する。P0 内の個別選択承認とは別記録、D5 承認とも別 ID。P0 完了後は `P0-CAND-n` を固定し、B0→candidate の D4 差分再監査合格後に同一 **file-set hash** で B1 へ昇格する。

## 1. 承認内訳の正本は1箇所

### 原則

**「何を承認したか」の正本は `DECISIONS.md` の記録1件に集約する。** 人間本人の直接承認は `[DECISION]`、委任AIの工程内承認は `[AI-APPROVED]` とし、他の文書からは参照だけを置く。

```
DECISIONS.md の承認記録（正本）
  ├─ 選択内訳を全件記載
  ├─ 人間直接承認: [DECISION]
  ├─ 委任AI: [AI-APPROVED] + 委任元の人間 [DECISION] 参照
  └─ 本文に「選択内訳の正本は本記録である」と書く

Work Packages       → 「D-n に基づく」と参照
Toolchain           → 「D-n を参照」と参照
CR ヘッダ           → P0内のStatusと承認記録ID（formal document Statusではない）
人間作業台帳        → 人間本人が行った作業だけを記録。AI行使を完了扱いにしない
PROGRESS            → 現在 stage と実施の事実、B0 に固定した P0 closure question/scope。P0 で作る選択内訳は書かない
```

### なぜ複製が危険か

選択が6群あると、複製先が4文書あれば24箇所になる。1つ変えたとき、残り23箇所を全部直せる保証はない。実際に P0 では「状態値の片側更新」が3回再発した。

### 照合での確認

「**選択内訳を正本と宣言している承認記録が1箇所だけか**」「承認主体に応じて `[DECISION]` と `[AI-APPROVED]` が分離されているか」を照合依頼に書く。

---

## 2. 決定 ID の扱い

### 完全修飾する

同じ `D-n` 体系を複数の文書が独立に使っていると、裸の参照が誤った決定へ解決される。実プロジェクトでは `D-9` が3つの別物を指し、裸参照33件が最終監査まで残って人間の決裁事項へ回った。

**参照は常に完全修飾する。** ID 本体の形式は上流の体系定義が正本なので変えない。足すのは「どの文書の D-n か」を伴わせる規約だけ。

### P0 で新設する決定の採番

P0 では承認のたびに決定が増える。**既存の採番と衝突しない次番を採る。** 番号を予約する場合は、**予約だけで済ませず実際に行を起票する**（実プロジェクトでは「採番候補」と書いただけで台帳に行が無く、照合で Minor になった）。

### fallback の扱い

決定に対応する fallback（`F-n`）を作るかどうかは判断が要る。**未指示で作らない。** fallback 不要なら、根拠つき `Not applicable` を正本または設定へ明示してから validator を再実行する。warning / note を残したまま P0 PASS にしない。

---

## 3. 委任

### 委任を記録する

Owner が「以降は AI が承認判断してよい」と委任した場合、委任そのものを人間の `[DECISION]` として記録する。記録には**対象範囲、期限、取消条件、対象外**を明記する。

```
対象:   P0 の指定された文書承認を [AI-APPROVED] として記録する判断

対象外: production の Universe／Place、ID、DataStore、Open Cloud、商品、
        Secrets、権限、binding、publish settings への接触
        全環境の publish、production activation、商品 ID 作成、
        Secrets 設定、Group 権限変更、production DataStore 変更
        commit／push、Gate 1、D5、formal document の Status／Last approved 昇格
        （上流 skill が [HUMAN] 操作として定める全項目）
```

**委任されたのはP0工程内の `[AI-APPROVED]` 判断であって、外部状態を変える権限ではない。** ここを曖昧にすると、AI が publish や商品 ID に手を出す余地ができる。

### 人間専権とAI承認をタグで分離する

`[HUMAN]` は人間だけが実行するため、委任を理由に「または委任されたAI」を足さない。人間承認gateは人間のまま維持する。AIが行使できるP0工程内範囲は `[AI-APPROVED]` 記録側へだけ書き、委任元の人間 `[DECISION]` を参照する。

正本を全文検索し、次の衝突を検査する:

- AI行使を `[DECISION]` と呼んでいないか
- `[HUMAN]` 行をAIがCompletedにする経路がないか
- `[AI-APPROVED]` をGate 1、D5、formal document昇格、commit、外部状態変更へ流用していないか

**委任の内容を複製せず参照で表す**のが要点。範囲と対象外の正本は委任 `[DECISION]` 1箇所に置く。

### 委任下で承認する側の作法

- **判断材料を実測してから承認する**（→ `p0-gate-design.md` §5）
- **委任の範囲外を判断しない**。実測を必要とする決定、承認済み `[DECISION]` の変更を伴うものは、材料を揃えて Owner へ返す
- 承認記録を `[AI-APPROVED]` とし、**委任の人間 `[DECISION]` IDを参照**する。「AI が承認した」だけでは根拠が辿れない
- `[PROPOSAL]` を `[DECISION]` へ変えない。formal documentの `Status`／`Last approved` も変えない
- 承認の性質を書き分ける: **「照合の承認可」「P0管理WPのVerified」「P0の `[AI-APPROVED]`」「人間D5承認」は別の事象**

---

## 4. 人間作業台帳の同期

### 行を消さない

台帳は「未完了の `[HUMAN]` 作業を集約する」と定義されがちだが、**完了行を消すと監査追跡が切れる**。`Completed` のまま残し、収録規則の側に「完了行を残す理由（監査追跡・gate 充足証明）」を書く。

### closure evidence 欄も同期する

行を `Completed` にする便で、**evidence 欄も現況へ同期する**。承認した時点では「実改訂=未」が正しくても、後の便で完了したら追随させる。追随しないと台帳が失効値になる（→ `p0-rework-catalog.md` D-1）。

過去の記述を消さず、時制を限定して現況を追記する形が安全。

### 起票しない判断も記録する

委任経路の `[AI-APPROVED]` は人間作業台帳へ起票せず、進捗記録へ残す。台帳は `[HUMAN]` 専権作業の集約であり、AI行使は該当しない。既存の人間作業行をAI行使で `Completed` にしてはならない。

---

## 5. 記録の三層

P0 の記録は3層に分かれる。**混ぜない。**

| 層 | 文書 | 内容 | 性質 |
|---|---|---|---|
| 承認 | `DECISIONS.md` | 何を承認したか。`[DECISION]`／`[AI-APPROVED]` と選択内訳 | **正本** |
| 実績 | `CHANGELOG.md` | いつ何を変えたか | 履歴。過去を改変しない |
| 現況 | `PROGRESS.md` | 今どこにいるか、次に何をするか、B0 に固定した Proposed P0 closure inventory と P0-CAND 上の closure 状態 | 現在の宣言。実測で変動する repo fact の複製は保持しない |

現況層に「未 push N commit」のような実測で変動する repo fact を複製すると必ず失効する。**実測コマンドの結果を正とする**と書く（→ `p0-rework-catalog.md` D-1）。一方、phase、blocker、closure inventory の status は `PROGRESS.md` が所有する明示的な運行状態なので、stage 遷移と同じ便で更新する。

履歴層に旧値が残るのは正しい。**現況値へ上書きするのは過去の改変**であり誤り。時制を限定し、現在値の正本がどこかを示すのが正しい是正。

---

# 第2部 — `check_p0_state.py`（跨文書の状態検査）

**文書内の整合は既存 lint が見る。本 script が見るのは文書をまたぐ不整合。** 実プロジェクトで独立照合が2巡かけて発見した型を機械化した。

project rootをcurrent directoryにして実行する。checkerはproject内の相対pathではなく、読み込んだP0 Skill配下のscriptを絶対pathで指定する。

```powershell
# SKILL.mdで`${CLAUDE_SKILL_DIR}`展開値から設定済みの変数を受け取る。
if ([string]::IsNullOrWhiteSpace($p0SkillDir)) { throw 'p0SkillDir was not initialized from SKILL.md' }
$p0SkillDir = (Resolve-Path -LiteralPath $p0SkillDir).Path
$p0Checker = Join-Path $p0SkillDir 'scripts\check_p0_state.py'
if (-not (Test-Path -LiteralPath $p0Checker -PathType Leaf)) { throw "P0 checker not found: $p0Checker" }
if (Get-Command python -ErrorAction SilentlyContinue) {
    $pythonExe = 'python'; $pythonPrefix = @()
} elseif (Get-Command py -ErrorAction SilentlyContinue) {
    $pythonExe = 'py'; $pythonPrefix = @('-3')
} else {
    throw 'Python interpreter not found (tried: python, py -3)'
}
& $pythonExe @pythonPrefix $p0Checker --project-root (Get-Location).Path --prefix CAV
& $pythonExe @pythonPrefix $p0Checker --project-root (Get-Location).Path --prefix CAV --json
& $pythonExe @pythonPrefix $p0Checker --list-rules
& $pythonExe @pythonPrefix $p0Checker --project-root (Get-Location).Path --prefix CAV --only wp-status-cross-doc
```

supporting reference本文では`${CLAUDE_SKILL_DIR}`が展開されない。SKILL.md本文で展開・解決済みの`$p0SkillDir`を渡す。OS環境変数を参照しない。checker実在を確認し、`Get-Location`がproject rootでない場合は実行しない。

設定は `.claude/p0-check.json`（既定）または `--config`。文書名の `{PREFIX}` は `--prefix` で置換される。

**設定が無い項目は検査せず note を出す。note が出ている観点は「検査して問題なし」ではなく「検査していない」。warning / note が1件でも P0 checker は PASS ではなく exit 1。** 検査しない規則は設定の `rules` で明示的に無効化し、理由を P0 evidence に残す。

exit code は次のとおり。**設定不備は検査結果ではなく設定の誤りなので、finding ではなく exit 2 で落とす。**

| exit | 意味 |
|---|---|
| 0 | error 0 / warning 0 / note 0。P0 checker PASS |
| 1 | error・warning・note のいずれかあり（検査は成立したが gate FAIL） |
| 2 | 設定不備。未知の設定キー／rule 名、`--config` の指す設定が無い、`wp_status_mirrors`・`status_vocabulary`・`git_fact_docs` が空 |

**指定した文書が存在しない場合は exit 1（error finding）** になる。設定は正しいが対象が無い、という状態を区別するため。検査しない意図なら `rules` で当該 rule を明示的に `false` にする。

---

## rule 1: `wp-status-cross-doc`

**何を見るか**: Work Package の Status が、唯一正本（`work_packages` の各 WP 詳細節）と、それを写した同文書 index・運行記録（`PROGRESS` 等）で食い違っていないか。

**なぜ要るか**: 同文書 index と詳細節の drift は lint が見られるが、`PROGRESS` との跨文書不一致は見られない。詳細節と index が同じ旧値でも `PROGRESS` だけ進んだ型を実際に Major として見逃した。handoff の inScope に正本を入れ忘れるとこの形になる（→ `p0-rework-catalog.md` C-1）。

**検出の仕方**: 詳細節だけから ID → Status の正本 map を作る。同文書 index は `status-index-drift`、跨文書 mirror は本 rule で次の3形式と突き合わせる。

- 表の Status 列（**ID が先頭セルにある行だけ**。説明セルに ID を含む別種の表を WP 行と誤認しないため）
- `- ... Status: X` の箇条書き
- 散文の `Status は \`X\`` という明示形。**状態語が出るだけの説明文は拾わない**（状態遷移を記述した履歴で大量に誤検出するため）。ID は marker 直前のものへ帰属させる

**履歴は除外する**: `history_markers` のいずれかを含む行は現況の宣言ではないので飛ばす。履歴行に旧値が残るのは正しい。

**設定**:

```json
{
  "wp_status_source": "docs/{PREFIX}_work_packages.md",
  "wp_status_mirrors": ["PROGRESS.md"],
  "wp_id_pattern": "WP-[A-Z0-9]+-\\d+[A-Z]?",
  "status_field": "Status",
  "status_vocabulary": ["Proposed", "Approved", "In progress", "Verified", "Superseded"],
  "history_markers": ["記録時点", "時点では", "時点の", "当時", "だった", "であった", "旧値"]
}
```

**Status の語彙は architect の Work Package template が正本**（`Proposed` / `Approved` / `In progress` / `Verified` / `Superseded`）。ここで勝手に増減すると、語彙外の値が黙って検査対象から外れる。

checker が index 行を source map として採用してはならない。詳細節欠落・重複 Status・語彙外 Status は error。index / `PROGRESS` の値を正本へ逆流させず、詳細節を基準に同期する。

**実績**: 実プロジェクトで照合1巡目が Major と判定した箇所を、同じ行番号で検出することを確認済み。是正後は 0 件。

---

## rule 2: `git-current-facts`

**何を見るか**: 現況として宣言された commit hash・未 push 件数が実測と合っているか。

**なぜ要るか**: 「未 push N commit」型は commit のたびに失効する。実プロジェクトでは**3回連続で再発**し、毎回「全文走査した」と報告された後に照合で発見された。

**走査範囲**: **最初の `##` 見出しより前**（現況が宣言されるヘッダ区間）だけ。それ以降は履歴節であり、旧値が残っているのが正しい。

**検出する形**:

- `未 push N 件` / `未 push N commit` → 実測 `git rev-list --count <remote>..HEAD` と比較
- `origin/main = <hash>` / `origin/main は <hash>` → 実測と比較
- `HEAD = <hash>` → 実測と比較

**根本対処は形式を変えること**: 件数と hash を保持せず「実測コマンドの結果を正とする」と書けば二度と失効しない。本規則はその移行が済むまでの検出網である。保持してよいのは意図的なスナップショット（Last Known Good Commit のような「その時点で検証した」宣言）だけ。

**設定**: `git_fact_docs`（既定 `["PROGRESS.md"]`。空だと exit 2）、`git_remote_ref`（Git運用時の比較対象）。この規則はGit remoteを使うプロジェクトだけ有効化する。snapshot-only／未Git化／remote未設定のプロジェクトは `rules.git-current-facts: false` を明示し、理由とsnapshot baseline evidenceをP0記録へ残す。snapshotを許す全体規則と矛盾するため、存在しない `origin/main` をP0必須条件にしない。

---

## rule 3: `open-evidence`

**何を見るか**: `[OPEN]` に closure evidence と Owner が書かれているか。

**なぜ要るか**: 閉じる条件と担当が読めない open は放置される。**いつ閉じられるか誰にも分からない**まま下流が積み上がる。

**対象**: 生きた open だけ。**closure record や履歴行が open marker に言及しているだけのもの**は対象外（marker が行頭またはセル頭にあるものだけを見る）。閉じた open を毎回鳴らすと無視されるようになる。

**severity**: 散文形式は `error`、表のセルに収めた open は `warn`。どちらも「閉じる条件が読めない」点は同じだが、**表形式まで error にすると既存文書で鳴り続けて無視される**ため分けている。

**設定**: `open_docs`（**未設定だと無効**）、`open_pattern`、`open_required_terms`（既定 `["closure evidence", "Owner"]`）。

---

## rule 4: `decision-ref`

**何を見るか**: 参照された決定 ID が決定記録に存在するか。

**なぜ要るか**: **採番を予約しただけで起票していない**ことがある。実プロジェクトでは「採番候補 D-120」と書いただけで台帳に行が無く、照合で Minor になった。参照の綴り間違いも拾う。

**severity**: `warn`（決定記録の見出し書式が多様で、抽出漏れの可能性があるため）。

**裸参照は対象外**: 修飾のない `D-n` は docs-creator の lint 規則 `bare-decision-id` が担当する。ここで二重に鳴らすと本規則の信号が埋もれる。本規則が見るのは「修飾はあるが解決しない」参照であり、**番号だけ一致して修飾が違う**場合は名前空間衝突の兆候として別メッセージで報告する。

**設定**: `decision_record`、`decision_heading_pattern`、`decision_ref_pattern`、`decision_ref_docs`（**未設定だと無効**）。

---

## 設定例（実プロジェクト）

```json
{
  "wp_status_source": "docs/{PREFIX}_work_packages.md",
  "wp_status_mirrors": ["PROGRESS.md"],
  "open_docs": ["docs/{PREFIX}_toolchain_spec.md", "docs/{PREFIX}_work_packages.md"],
  "decision_ref_docs": ["PROGRESS.md", "docs/{PREFIX}_toolchain_spec.md", "HUMAN_ACTIONS.md"]
}
```

`open_docs` と `decision_ref_docs` は**プロジェクトごとに列挙が要る**。空のままだと該当規則が無効になり、note でその旨が出る。

---

## 他の検査との関係

| 検査 | 見るもの |
|---|---|
| architect の `validate_docs.py` / `validate_traceability.py` | 文書体系の形式・要件トレース |
| docs-creator の `lint_docs.py` | 文書内の定型欠陥（裸 `[OPEN]`、失効前提句、値の二重正本、索引ドリフト） |
| **本 script** | **文書をまたぐ状態不一致・現況値の失効・open の evidence・決定参照** |

3つとも走らせる。**照合へ出す前に**走らせるのが要点で、人間の目を機械で足りることに使わせない。
