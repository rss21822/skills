# Worker execution envelope

外部workerへ何を送り、何が返り、実際にどのruntimeで動いたかを1件ごとに固定する正本。worker固有Skillは起動方法を持つ。本書は全worker共通の境界を持つ。

## 1. 外部送信と安全境界

承認済みLLM providerへのbounded prompt送信は、production公開・第三者への一般公開・法的連絡とは別分類。

- `approved-transfer`: 使用者が今回のprovider/account/model/content範囲を明示承認したLLM送信
- `blocked-permission`: provider利用、課金、install、path追加等の承認待ち
- `blocked-safety`: secret入力、production変更、一般公開、規約承諾、法的効力を持つ連絡等。承認だけでAI実行へ変えない

`approved-transfer`なしにprobe・handoff・reviewを送らない。

## 2. transferApproval

handoffごとに次を固定する。E0/D1〜D3の承認をD4/P0/D5/W0〜W2へ継承しない。D0 は外部 worker を起動せず、固定 probe は E0 に属する。

```yaml
transferApproval:
  approvalId: HUMAN-...
  provider: ...
  endpointOrChannel: ...
  accountOrBillingIdentity: ...
  authChannel: subscription|env-name-only|key-file-name-only
  requestedModel: ...
  allowedPaths:
    - path
  allowedContentSha256:
    - sha256
  deniedPatterns:
    - .env
    - '*secret*'
    - '*credential*'
    - '*.pem'
    - '*.key'
  maxRequestBytes: ...
  maxResponseBytes: ...
  costCap: ...
  expiresAt: ...
```

secret値、key prefix、token断片をhandoff・probe・evidenceへ出力しない。authは値でなくchannelとcredential identifierだけ記録する。

## 3. Class A / Class B

- Class A: approved project root内でfile読取・command実行可能。書込時はsandboxとinScopeを強制。
- Class B: text入出力のみ。local path、cwd、validator、evidenceへアクセス不能。

Class Bへpath一覧だけ渡すことは禁止。指示役がhash付きcontext bundleを生成し、bundle全文をpromptへinlineする。

### Context bundle

`scripts/build_context_bundle.py`をproject rootから、Skill scriptの絶対pathで実行する。

```powershell
# SKILL.md本文で展開済みの絶対pathを同じblockへliteralとして設定する。
$docsCreatorSkillDir = (Resolve-Path -LiteralPath '<expanded docs-creator skill path>').Path
$bundleBuilder = Join-Path $docsCreatorSkillDir 'scripts\build_context_bundle.py'
if (Get-Command python -ErrorAction SilentlyContinue) { $pythonExe='python'; $pythonPrefix=@() }
elseif (Get-Command py -ErrorAction SilentlyContinue) { $pythonExe='py'; $pythonPrefix=@('-3') }
else { throw 'Python interpreter not found' }
& $pythonExe @pythonPrefix $bundleBuilder --project-root (Get-Location).Path --output 'docs\handoffs\out\<id>_context.md' --include '<path1>' --include '<path2>' --max-bytes <approved-limit>
```

supporting reference内のplaceholderは自動展開されない。SKILL.md本文で得たpathを埋め、project側の同名scriptへfallbackしない。

規則:

1. explicit relative pathだけ。glob・親directory・project外・symlink escape禁止。
2. denied patternに一致したら生成前に停止。
3. manifestへpath、byte length、sha256を記録。
4. 各file本文をbyte-for-byte格納。
5. bundle自体のsha256とbyte lengthを記録。
6. provider上限または承認上限超過時は分割せずfail-closed。使用者へ再承認を求める。

## 4. Response envelope

Class B執筆は本文と報告を混ぜない。workerへ次の厳格JSONだけを要求する。

```json
{
  "schema_version": 1,
  "text": "任意の短い注記",
  "artifact": [
    {"path": "relative/path.md", "content": "正本へ転記する完全な本文"}
  ],
  "report": "正本へ入れない報告"
}
```

- JSON外の前置き、markdown fence、token footerを禁止する。
- local adapterまたは指示役がJSON parse後の`artifact[].content`をUTF-8化し、bytes/sha256を計算する。モデル申告hashを証拠にしない。
- expected path集合との完全一致、path正規化、重複0、空content 0を検査する。invalid JSON、欠落、余剰、truncationは失敗。
- raw response全体を`<id>_raw.md`へ保存する。parseしたcontentだけ正本へ転記し、転記後sha256を再計算してadapter計算値と一致させる。
- `text`、`report`、usage、telemetryは正本へ混ぜない。`finishReason == stop`相当がattestationに無ければ完了扱いにしない。

## 5. Execution attestation

宣言値と実測値を分ける。

```yaml
executionAttestation:
  worker:
  class:
  cliOrServerVersion:
  requestedModel:
  resolvedModel:
  requestedEffort:
  resolvedEffort:
  sandbox:
  approvalPolicy:
  networkRequested:
  networkObserved:
  authChannel:
  accountOrBillingIdentity:
  requestSha256:
  contextBundleSha256:
  responseSha256:
  finishReason:
  inputTokens:
  outputTokens:
  startedAt:
  finishedAt:
  exitCode:
```

resolved値を取得できないruntimeは、そのfieldを`unverifiable`としてgate前に明示する。`unverifiable`をrequested値と同一だと推測しない。exact model/versionが必須ならfail-closed。

## 6. Review

- gate reviewer: Class Aのみ。対象file・canonical source・validator・test・evidenceを自身で再検査。
- D4 gate reviewer の approved root は `audit-d4.md` の hash付き audit capsule。project root の自由探索、allowlist 外検索、過去 findings 閲覧を許可しない。
- Class B reviewer: context/evidence bundle範囲のsemantic reviewのみ。`supplemental`と記録し、Critical 0 / Major 0、D4合格、実装準備判定を単独で出さない。
- 指示役作成のcommand outputをClass Bへ渡す場合、command、cwd、exit code、stdout/stderr file hashをbundleへ含める。Class Bは実行したと主張しない。

## 7. Probe

probeは実プロジェクト内容を含まない固定文字列を使う。provider/account/model/cost承認後だけ送る。記録するのはsanitized request hash、response、version/model/finish reason/usage。credentialの存在確認はbooleanまたはsource nameだけ。値・prefixを保存しない。
