# 実測値とEvidence

このワークフローで最も壊れやすいのは「測っていない値を書いてしまうこと」。一度創作値が入ると、それ以降の検証がすべて無意味になる。

## 実測しないなら書かない

hash・ID・バージョン・URL・errno・件数は、実際に取得したものだけを書く。取得できないなら `[OPEN] blocking: yes|no` として残し、誰がいつ取得するかを書く。

```markdown
> **[OPEN] blocking: no** — <値の名前>は現時点で未取得。<誰が><いつ><どうやって>取得し、<どこへ>登録する。取得前に値を創作またはplaceholder化しない。
```

`blocking: yes` なら進捗記録のblocker欄へも登録する。片方だけだと追跡が切れる。

実運用の例: 5つのツールの期待バイナリhashが未取得だった。placeholderを入れず `[OPEN] blocking: no` として、セットアップ工程で実測してから登録した。照合はこれを「P0開始を妨げない」と判定した。正直に未取得と書いたから、正しく判定できた。

## 値の取得と受け渡し

Claudeが実測し、FACTとしてhandoffへ渡す。Codexは渡された値だけを使う。

```powershell
(Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath '<file>' -Algorithm SHA256).Hash
& '<exact-tool-path>' --version
# API照会はhandoffでnetworkと送信先を承認した場合だけ、承認済みclientで実行する。
```

ツールのバイナリhashを取るときは、**実際に実行されるバイナリ**を測る。ラッパーやランチャーではない。実運用で、`~/.rokit/bin/` 配下の5つのツール名がすべて同一のランチャー（同じhash）で、実体は別ディレクトリにあった。ランチャーをhashしても、実体は拘束されない。

```powershell
$toolRoot = (Microsoft.PowerShell.Management\Resolve-Path -LiteralPath '<pinned-tool-storage>').Path
Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $toolRoot -File -Recurse | ForEach-Object {
  [pscustomobject]@{
    RelativePath = [IO.Path]::GetRelativePath($toolRoot, $_.FullName)
    Sha256 = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  }
}
```

## Evidenceの記録

テスト実行の証跡は、後から独立に検証できる形で残す。含めるもの:

- 対象commit または未commit識別子
- 実行環境（OS・ツールバージョン・Studioバージョン）
- 入力のhash（fixture・config・artifact）
- 出力（生ログと、そのhash）
- 判定結果（各項目のPASS/FAIL）
- 実行時刻

生ログは改変せず保存し、hashを取る。要約だけを残すと、後から「本当にそう出ていたか」を確認できない。

## PII

プレイヤーIDやサーバーのジョブIDは生のまま保存しない。ドメイン分離したハッシュにする。

- saltは実行時に生成し、artifactへ保存しない
- ドメイン文字列を含めて、他用途のhashと衝突しないようにする
- 固定のalias（`PLAYER-1` 等）で代用しない — 匿名化になっていないうえ、同一性の証明にもならない

実運用で、固定aliasだけを記録していたEvidenceが照合で差し戻された。ハッシュに変えて再実行した。

## 決定論

同じ入力から同じ出力が出ることを確認する。2回実行してhashが一致すれば、生成に非決定的要素が混ざっていない。

```powershell
& <exact-generate-command> -Output '<fresh-path-a>'
if ($LASTEXITCODE -ne 0) { throw 'First generation failed.' }
& <exact-generate-command> -Output '<fresh-path-b>'
if ($LASTEXITCODE -ne 0) { throw 'Second generation failed.' }
$hashA = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath '<fresh-path-a>' -Algorithm SHA256).Hash
$hashB = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath '<fresh-path-b>' -Algorithm SHA256).Hash
if ($hashA -cne $hashB) { throw 'Non-deterministic output.' }
```

一致しないなら、時刻・乱数・イテレーション順序・絶対パスのいずれかが混ざっている。

## 不変性の記録

「変えてはいけないもの」は、hashを記録して各段階で照合する。golden fixture、承認済み設定、生成物のcontentHashなど。

所有者が今回commitを明示承認した場合は、commitメッセージにも実測値を書く。未承認時は同じ情報をimmutable LKG snapshot metadataへ記録し、stage/commitしない。

```
- config/data-registry.resolved.json: contentHash a7f2aedf…（独立3経路で再計算一致）
- 3 build決定論(2連続hash一致): Lobby 5cf0507b… / Run 7e5ef039… / StudioTest dac1fc73…
```
