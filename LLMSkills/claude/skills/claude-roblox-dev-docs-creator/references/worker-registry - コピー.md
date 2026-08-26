# 作業実施 LLM（worker）の選択と運用

指示役、執筆役、gate照合役を分ける。使用者がworkerを指定し、指定が無ければprobe結果を示して訊く。

共通の外部送信・context・response・attestation契約は`execution-envelope.md`が正本。

## 0. 責務名（named role）と worker の関係

**責務名は固定プラグイン名でも特定モデルの識別子でもない。** 使用者が選定した worker が、delegation packet を受け取ってその責務を assume する。**役割は責務名、実行主体は worker。**

| 責務名 | 担当 | やってはいけないこと |
|---|---|---|
| `product-gdd-writer` | 承認済み intake からの GDD | 自分の提案を自分で承認する / 実装内部を定義する |
| `repository-auditor` | brownfield の read-only 監査 | source 編集 / refactor |
| `system-architect` | module、state、interface、topology | balance や製品意図を所有する |
| `data-economy-writer` | balance、経済、式、Config 検算 | UI 設計 / network trust の定義 |
| `ui-input-writer` | UI 状態、flow、端末入力、accessibility | サーバー権威規則を発明する |
| `platform-security-writer` | network、persistence、commerce、policy、analytics 基盤 | GDD の決定を変更する |
| `dev-process-writer` | phase plan、WP、test、workflow、runbook | gameplay scope を黙って変える |
| `sub-spec-writer` | 1つの triggered domain 仕様または変更要求 | 二重正本を作る |
| `consistency-auditor` | 文書間の矛盾 | 文書を編集する |
| `roblox-readiness-auditor` | production / platform の完備性 | 文書を編集する |
| `clean-room-auditor` | 会話前提なしの handoff 試験 | 欠けた決定を埋める |

**責務名が確保できない場合は blocker として停止する。** 指示役を正本執筆の fallback にしない。writer の self-audit を独立監査の代わりにしない。監査役は、その出力を検査する対象の writer と**別の主体**でなければならず、read-only を維持する。

### 並行化してよい組み合わせ

GDD 承認後に安全に並行できるのは `system-architect` / `data-economy-writer` / `ui-input-writer` / `platform-security-writer`。**並行後、D3 の前に指示役が interface 突合を1巡行う。**

並行させてはいけないもの:

- 製品承認前の GDD と architecture
- 同じ未解決リスクに対する architecture と feasibility
- 同一ファイルを編集する writer と auditor
- 同一の正本数値表を複数 worker が所有すること

### delegation packet の必須項目

1. モードと現在の phase
2. 承認済み入力と revision ID
3. 正確な出力ファイル
4. 正本境界
5. 許可される状態タグ
6. do-not-change 一覧
7. 必須検査
8. 返却形式（変更点 / 求める決定 / blocking / 下流影響）

**指示役は、作業開始前に各責務名へ割り当てた worker を記録する。** worker はこの packet を受け取ってから role を assume する。handoff の必須項目は SKILL.md §8 が所有し、本節はその role 割り当て部分を所有する。

## 1. Class

| Class | 能力 | 執筆 | gate照合 |
|---|---|---|---|
| A | approved rootのfile読取・command実行。許可時のみfile書込 | 可 | read-onlyで可 |
| B | text入出力のみ。local path/cwd/file/commandなし | hash付きinline context＋response envelope必須 | 不可。supplemental semantic reviewのみ |

Class Bを「別セッションだから独立照合可能」と扱わない。validator、test、全file、evidenceを自身で再検査できないため、Critical 0 / Major 0／D4合格を単独で出せない。

## 2. 候補とcanonical route

| worker | Class | canonical route |
|---|---|---|
| Codex CLI（D1〜D3文書／D4監査） | A | `codex-run` Skillのcompanion。raw `codex exec`禁止 |
| Codex CLI（W0〜W2製品実装） | A | `claude-roblox-mvp-buildout`のexact-pinned T1 helper。single-WP deliveryも同契約を継承 |
| Claude subagent | A | fresh context、approved root、read/write scopeを明示 |
| Cursor CLI系 | B | `cursor-grok` Skill。隔離cwd、inline contextのみ |
| DeepSeek | B | `deepseek-api` SkillのPython CLI。MCPは互換adapterであり正本経路ではない |

routeは起動直前に各Skillを読み、実在tool/schema/versionをprobeする。表の記述を可用性保証にしない。

stageを跨いでCodex routeを混ぜない。D1〜D4のcompanion承認をP0/D5/W0〜W2 helperへ継承せず、W0〜W2 helperが不成立でもcompanionへfallbackしない。D0 は指示役による intake で外部 worker を起動しない。

## 3. Probe

外部worker probeも送信。次を先に使用者承認:

- provider、endpoint/channel、account/billing identity、auth channel
- requested model、cost cap
- project内容を一切含めない固定probeを送ること

この承認も `execution-envelope.md` §2 のjob固有 `transferApproval` として、closed scope digest、current human message evidence、expiry、single-use消費を固定する。単なる approval ID や過去probeの同意を使い回さない。

credential値・prefixを表示または保存しない。probe結果はsanitized request/response hash、CLI/server version、requested/resolved model、finish reason、usage、exit codeを保存する。

## 4. Class B context

Class Bへlocal path一覧だけ渡すことは禁止。

1. `scripts/build_context_bundle.py`でexplicit allowlistからbundleを生成。
2. path/bytes/sha256 manifestとbundle attestationを検査。
3. `transferApproval`のallowed paths/hashes/max bytesと一致確認。
4. bundle全文をpromptへinline。
5. size超過、deny match、hash不一致なら送信せず停止。

Cursorはbundle全文をpromptへ直接inlineする。DeepSeek CLIは生成済みbundle fileを唯一の`--files`入力にし、original source globを再展開しない。どちらもsidecarの同じbundle/source hashをattestationへ結ぶ。

GDD、通常handoff、是正、reviewの全てに適用する。

## 5. Class B artifact転記

`execution-envelope.md`のresponse envelopeを使い、artifactとreportを分離する。

1. raw response全体を`docs/handoffs/out/<id>_raw.md`へ保存しsha256記録。
2. `finishReason == stop`、厳格JSON parse、expected artifact path集合、重複・空content 0を検証。
3. parse後の`artifact[].content`をUTF-8化し、localでbytes/sha256を計算してから正本へ転記。
4. 正本sha256を再計算しlocal計算値と一致確認。
5. report/usage/footer/前置きは正本へ混ぜず、last-messageとして保存。

不一致・truncation・空artifactは失敗。指示役が補完しない。新handoffを発行する。

## 6. 選択制約

- 執筆役とgate照合役は別session。
- gate照合役はClass A。
- 指示役は正本文書本文を書かない。
- worker全滅時、指示役へfallbackしない。`blocked-capability`として再指定を求める。
- 使用者が「任せる」と明示した場合だけ指示役が選び、理由を記録する。
- E0/D1〜D3のworker・送信承認をD4/P0/D5/W0〜W2へ継承しない。D0 に外部 worker 承認は存在しない。
- Class BはMVP実装のT3相当。製品codeの無人workspace-writeへ昇格させない。

## 7. 毎jobの記録

`E0_capability_probe.md`と各handoffに次を保存:

- worker/class/route/role
- 選択者とapproval ID
- job固有 `transferApproval`。closed scope hash、current human messageのinteraction/message/actor/timeとstatement path/hash、単回消費、expiryを含み、送信直前に再照合する。IDだけ・過去jobからの再利用・scope変更は不可
- request/context bundle/response/artifact hash
- requested/resolved model、effort、CLI/server version
- sandbox、approval policy、requested/observed network
- auth channel/account identity（secret値なし）
- finish reason、usage、exit code、時刻
- external provenance verification mode、operator-pinned verifier/authority/key ID、fresh nonce/query IDまたはsignature verdict。secret/key bytesは記録しない

requested値だけの記録はattestationにならない。resolved値を取得不能なら`unverifiable`。exact pin必須jobでは停止する。locally authored execution/session/model文字列も独立証明にならないため、D4 Class A attestationは外部runtime queryまたはpinned signatureの`provenance_verification`を持たなければbaselineへ昇格できない。

`transferApproval`はcurrent human interactionをtrust rootにした**単一jobのruntime consent**であり、後続baseline/W0の歴史的真正性証明には使わない。current message bytesを直接照合できない経路では、同じscopeを対象とする外部署名済み証拠を用意するか、そのsendを停止する。

worker変更は`DECISIONS.md`へ追記し、既に作成済みartifact範囲を記録する。
