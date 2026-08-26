# Windows / Roblox Studio MCP 実測手順

ローカルsourceから検証専用placeを決定論buildし、Windows版Studioで開き、現在のRoblox Studio MCP契約で実測する。workerの自己申告や画像だけで合格にしない。

契約照合日: 2026-08-19。tool schemaは更新されうるため、各runで実行時schemaを再確認する。

## 1. 前提と不変条件

- canonical artifactを直接Studioで開かない。同じ入力から別pathへ2回buildし、SHA-256一致を確認した後、検証専用copyを使う。
- Studio executableは、所有者が承認したabsolute path、Roblox Corporation署名、版、SHA-256を記録する。PATHやleaf名だけで選ばない。
- 最初の `list_roblox_studios` だけは選択前なので `studio_id` を持たない。それ以外の**全Roblox Studio MCP call**へ、同じ検証対象の明示的 `studio_id` を渡す。
- active-windowを暗黙選択する旧APIは使わない。現在のtool namespaceは `mcp__Roblox_Studio__*`。
- 実行時に公開されるtool schemaを最優先する。schemaと本書が競合したら呼出を止め、契約を更新する。
- Play開始前に初期state、Camera/Device Simulator設定、test作成Instance、性能/scene session handleを記録し、`finally`で復元・Disposeする。

## 2. Windowsで2回build

プロジェクトでpinされたRojo executableとproject fileだけを使う。未pin、`latest`、自動installへfallbackしない。

```powershell
$repo = (Microsoft.PowerShell.Management\Resolve-Path -LiteralPath 'C:\work\my-roblox-game').Path
$project = Microsoft.PowerShell.Management\Join-Path $repo '<Place>.project.json'
$runId = [guid]::NewGuid().ToString('N')
$buildRoot = Microsoft.PowerShell.Management\Join-Path $repo "artifacts\studio-validation-$runId"
$null = Microsoft.PowerShell.Management\New-Item -ItemType Directory -Path $buildRoot -ErrorAction Stop
$buildA = Microsoft.PowerShell.Management\Join-Path $buildRoot 'build-a.rbxlx'
$buildB = Microsoft.PowerShell.Management\Join-Path $buildRoot 'build-b.rbxlx'

& '<exact-pinned-rojo.exe>' build $project --output $buildA
if ($LASTEXITCODE -ne 0) { throw 'First Rojo build failed.' }
& '<exact-pinned-rojo.exe>' build $project --output $buildB
if ($LASTEXITCODE -ne 0) { throw 'Second Rojo build failed.' }

$hashA = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $buildA -Algorithm SHA256).Hash.ToLowerInvariant()
$hashB = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $buildB -Algorithm SHA256).Hash.ToLowerInvariant()
if ($hashA -cne $hashB) { throw 'Non-deterministic build; do not open Studio.' }
```

開始時点で既存変更がある場合、build入力はLKG commitまたはimmutable snapshot IDへ束縛する。build成功はLuau構文・require・runtime成功を意味しない。

## 3. Windowsで検証artifactを開く

build Aをcanonical結果として保持し、別copyをStudioへ渡す。

```powershell
$testArtifact = Microsoft.PowerShell.Management\Join-Path $buildRoot 'tested-copy.rbxlx'
Microsoft.PowerShell.Management\Copy-Item -LiteralPath $buildA -Destination $testArtifact -ErrorAction Stop
$prePlayHash = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $testArtifact -Algorithm SHA256).Hash.ToLowerInvariant()
$studioExe = 'C:\Program Files (x86)\Roblox\Versions\version-<owner-approved>\RobloxStudioBeta.exe'
$expectedStudioSha256 = '<owner-approved-64-hex>'
$expectedSignerThumbprint = '<owner-approved-certificate-thumbprint>'
$studioSha256 = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $studioExe -Algorithm SHA256).Hash.ToLowerInvariant()
$studioSignature = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $studioExe
if ($studioSha256 -cne $expectedStudioSha256 -or
    $studioSignature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
    $studioSignature.SignerCertificate.Thumbprint -cne $expectedSignerThumbprint) {
  throw 'Studio executable does not match the owner-approved identity.'
}
if ($testArtifact.Contains('"')) { throw 'Artifact path contains an unsupported quote.' }
$studioArgument = '"' + $testArtifact + '"'
$studioProcess = Microsoft.PowerShell.Management\Start-Process -FilePath $studioExe `
  -ArgumentList @($studioArgument) -WorkingDirectory (Microsoft.PowerShell.Management\Split-Path -Parent $studioExe) -PassThru
```

Studioはユーザーが操作する可視アプリなのでhidden起動しない。固定sleepで成功扱いにせず、次節のbounded pollingを使う。

## 4. `studio_id` を束縛する

1. `mcp__Roblox_Studio__list_roblox_studios {}` を呼ぶ。
2. 返った各 `id` / `name` と、今回開いたartifact、起動PID、観測時刻を対応付ける。
3. 候補が0件なら5秒間隔・最大7回、計35秒だけ再列挙する。
4. `name`（place ID/file nameを含む）で意図した候補を選び、候補が1件でも、最初の変更系call前に `id` / `name` を所有者へ提示して対象確認を取る。
5. 複数候補から一意に識別できなければ変更系callを実行しない。候補一覧を提示して確認する。
6. 確認済みIDを `$studio_id` 相当のrun記録へ固定し、以後の全callで同じ値を明示する。並び順や「最後に開いた」で選ばない。

対象選択後の最初のcall:

```text
mcp__Roblox_Studio__get_studio_state { studio_id: "<studio-id>" }
```

初期stateとAvailable DataModelsを証跡へ保存する。別IDの応答が混じったrunは無効。

## 5. Play開始とbounded state polling

```text
mcp__Roblox_Studio__start_stop_play {
  studio_id: "<studio-id>",
  is_start: true
}
```

このrunがPlayを開始したかを記録する。続いて同じIDへ `get_studio_state` を5秒間隔・最大18回、計90秒だけ呼ぶ。`Play`かつ必要な`Client`/`Server` DataModelが利用可能になれば次へ進む。

90秒後もreadyでなければ `BLOCKED_STUDIO_NOT_READY`。無期限poll、別Studioへの切替、手動Playを実行済み扱いすることは禁止する。所有者が手動操作を選ぶ場合は別の明示操作として記録し、その後IDとstateを最初から再検証する。

## 6. DataModelを明示して実測する

`execute_luau` は `studio_id`、`datamodel_type`、`code`を毎回渡す。返却値は `result = ...` ではなくLuauの明示的 `return` で返す。

```text
mcp__Roblox_Studio__execute_luau {
  studio_id: "<studio-id>",
  datamodel_type: "Server",
  code: "return { placeId = game.PlaceId, gameId = game.GameId, studioVersion = version() }"
}

mcp__Roblox_Studio__execute_luau {
  studio_id: "<studio-id>",
  datamodel_type: "Client",
  code: "return { playerGuiChildren = #game:GetService('Players').LocalPlayer.PlayerGui:GetChildren() }"
}
```

`Edit`照会が必要なら `datamodel_type: "Edit"` を明記する。Client/ServerがAvailable DataModelsに無い状態で推測実行しない。

console回収も同じ対象を明示する。

```text
mcp__Roblox_Studio__get_console_output { studio_id: "<studio-id>" }
```

consoleが空でもerror 0件とはみなさない。必要ならServer/Clientそれぞれで `LogService:GetLogHistory()` を `execute_luau` から明示的に返し、検索範囲・総件数・error/warning件数を保存する。

game treeを使う場合も対象を省略しない。

```text
mcp__Roblox_Studio__search_game_tree {
  studio_id: "<studio-id>",
  datamodel_type: "Server",
  path: "game.ServerScriptService",
  max_depth: 4
}
```

実際のtool schemaに追加必須fieldがあればそれも渡す。

## 7. `screen_capture` はEdit-time補助証拠

現行 `screen_capture` は**Edit-time screen専用**である。Play中のruntime UI captureとして使わない。`get_studio_state`で同じStudioが`Edit`であることを確認してから、一意な `capture_id` と同じ `studio_id` を渡す。

```text
mcp__Roblox_Studio__screen_capture {
  studio_id: "<studio-id>",
  capture_id: "<run-id>-<test-id>-01"
}
```

返却画像、capture ID、時刻、対象stateを保存する。画像だけでserver権威状態、DataModel、数値、入力受理をPASSにしない。runtime生成UIはClient `execute_luau` のPlayerGui実体・表示値で検証し、このEdit-time captureで代用しない。

## 8. `finally` cleanup

開始後の成功・失敗・timeoutに関係なく、同じ `$studio_id` に対して次を行う。cleanup自体も証跡へ残す。

1. このrunが作成したperformance/scene/device session・connection・taskを明示的に`Dispose`/disconnect/cancelする。
2. run IDで所有を証明できる一時Instanceだけを削除する。既存Instanceを名前だけで削除しない。
3. Camera、Device Simulator、scaling、orientationなどをPlay前に記録した値へ戻す。復元不能ならrunをPASSにしない。
4. このrunがPlayを開始した場合だけ停止する。

```text
mcp__Roblox_Studio__start_stop_play {
  studio_id: "<studio-id>",
  is_start: false
}
```

5. 同じIDの `get_studio_state` を5秒間隔・最大12回、計60秒だけpollし、`Edit`を確認する。timeoutなら `BLOCKED_CLEANUP`。
6. 最終console/stateを回収し、一時object・session handle・Simulator設定が復元済みであることを独立照会する。

Play停止が失敗しても別Studioへ停止callを送らない。ユーザー所有のStudioプロセスを勝手に終了しない。

## 9. artifact同一性とEvidence

Studioを閉じた後、またはfile handleが解放された時点で検証copyのSHA-256を再計測する。pre/post hashが違えば、そのartifactでの同一性主張はFAIL。canonical build Aを再buildして同じhashが再現しても、変更された検証copyの結果を無条件に有効化しない。

Evidenceには最低限、LKG commit/snapshot ID、build A/B hash、test artifact pre/post hash、Studio executable版/hash、`studio_id`/name、初期・最終state、各tool callの必須引数、Luau全文とraw返却、console件数、capture ID、cleanup結果を含める。
