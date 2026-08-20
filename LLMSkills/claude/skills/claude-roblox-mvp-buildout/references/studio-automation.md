# Studio実機セッションの構築と操作

Studioの公式scripted testingを優先する。ここで示すOS自動化は、公式機能では対象経路を再現できず、操作ごとの所有者承認がある場合だけ使うfallbackである。

## 1. Fail-closed条件

- session外のprocessへ、前面化、入力、capture、closeをしない。
- PIDだけでなく、start time、Windows session、canonical executable path、署名、exact main HWND、独立role/place handshakeを照合する。
- OS入力、全画面capture、process close、desktop session切替は、今回のrunの操作ごとに別々の所有者明示承認を取る。承認ID・対象・時刻・範囲を証跡へ残す。identity/role/place/foreground検査は承認の代替ではなく、承認と検査の両方が必要である。強制終了と`tscon`は自動実行しない。
- Studio・Codexの証跡は、repository、Git administration directory、OS TEMPと物理的に分離した、所有者管理のlocal fixed drive上へ置く。UNC、mapped/removable drive、junction、symlink、SUBST等のaliasは使わない。
- Studioへ進む前に、委譲したCodex jobがすべてterminal stateへ到達したことを確認する。workspace writerへtrusted evidence rootを渡さない。
- 同じOS userでStudio installation、同梱script、trusted evidenceを変更できる別processが動いていないことをownerが確認する。scriptは既存ACLを変更せず、同一userの悪性writerを完全には隔離しない。
- run directoryと証跡fileは毎回新しい名前で作る。既存証跡を`-Force`で上書きしない。上書きが本当に必要なら、対象fileごとの所有者承認を別途記録する。
- `-DryRun`は引数とplanの確認であり、live target、foreground、gameplayの成功証明ではない。

公式のscripted testingを先に確認する。

- https://create.roblox.com/docs/studio/testing-modes#scripted-testing
- 参照日: 2026-08-17

## 2. capabilityとtrust boundaryのプリフライト

Claude CodeはSKILL本文で展開済みの`${CLAUDE_SKILL_DIR}`を、同じshell block内でliteralとして`$skillDir`へ設定する。これはOS環境変数ではないため、`$env:CLAUDE_SKILL_DIR`は使わない。

以下のPowerShell blockは、OS system directoryのMicrosoft署名Windows PowerShell 5.1 exact hostから起動した使い捨てcontrollerの`-NoProfile -NonInteractive` bodyとして実行する。controllerは`PSModulePath`をsystem built-in module directoryへ固定し、**1 actionごとに別の新しいOS PowerShell process**で`studio_session.ps1`を起動する。同じprocessで2 actionを直列実行すると型freshness gateが2回目を拒否するため、同梱scriptをcontroller内へ直接dot-source/`&`実行しない。各例の`$powershellHost`呼び出しを省略・統合しない。各childの`-ExecutionPolicy Bypass`はexact attested scriptを起動する当該processだけに適用する。同梱scriptもsecurity-critical cmdletのcommand type/module provenanceを副作用前に確認し、shadowingがあれば停止する。証拠JSONはmodule-qualified builtin cmdletでparseする。

所有者が、正規のStudio installation inventoryからexact executableを選び、署名・版・pathを承認する。leaf名だけで探索して採用しない。証跡rootは事前に所有者が作成し、agentは次のread-only actionで境界を検証する。

```powershell
$skillDir = '<SKILL.md本文で展開済みの絶対path>'
$powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
$env:PSModulePath = [IO.Path]::Combine([IO.Path]::GetDirectoryName($powershellHost), 'Modules')
$sessionHostArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-OutputFormat','XML','-File',(Join-Path $skillDir 'scripts\studio_session.ps1'))
$repositoryRoot = 'C:\work\my-roblox-game'
$evidenceRoot = 'D:\RobloxMvpEvidence'
$studioExe = 'C:\Program Files (x86)\Roblox\Versions\version-<approved>\RobloxStudioBeta.exe'
$preflightId = [guid]::NewGuid().ToString('N')
$prospectiveSession = Join-Path $evidenceRoot "preflight-$preflightId.json"

$trust = & $powershellHost @sessionHostArgs '-Action' 'Preflight' `
  '-SessionFile' $prospectiveSession '-RepositoryRoot' $repositoryRoot `
  '-TrustedEvidenceRoot' $evidenceRoot '-StudioExecutablePath' $studioExe '-DryRun'
if ($LASTEXITCODE -ne 0) { throw "Fresh Preflight process failed with exit code $LASTEXITCODE." }
if (-not [bool]$trust.ok) { throw 'Studio trust-boundary preflight failed.' }
```

`RepositoryRoot`は直接`.git` markerを持つexact worktree rootでなければならない。scriptはworktree、gitdir、common-dir、TEMP、evidence rootのphysical canonical分離、local fixed drive、reparse-free祖先、Studio inventory path、Authenticodeの`Valid`状態、Roblox Corporationの署名主体、SHA-256、thumbprint、product versionを確認する。確認不能ならleaf名やPATHへfallbackせず`BLOCKED`とする。

このほか、Studio MCPのinstance列挙、server/client Luau実行、console取得、`StudioTestService`、`UserInputService:CreateVirtualInput()`、対話desktop、空き容量を副作用なしでprobeする。同梱helperとcontrollerはOS system directoryのWindows PowerShell 5.1 exact hostだけを許可し、PowerShell 7とportable/copy hostは副作用前にfail-closedする。公式機能でmulti-clientと入力を再現できるなら、以下のOS経路は使わない。

## 3. run専用artifactと共通引数

決定論buildで一致したcanonical artifactをStudioから直接開かない。プリフライト後に、予測困難な新規run directoryをfail-if-existsで作り、通常copyを置く。hard linkは使わない。

```powershell
$evidenceRoot = '<preflight済みroot>'
$repositoryRoot = '<exact Git root>'
$studioExe = '<approved signed Studio exe>'
$runId = [guid]::NewGuid().ToString('N')
$runDir = Join-Path $evidenceRoot "run-$runId"
if (Test-Path -LiteralPath $runDir) { throw 'Refusing to reuse an evidence run directory.' }
$null = New-Item -ItemType Directory -Path $runDir -ErrorAction Stop

$canonical = (Resolve-Path -LiteralPath (Join-Path $repositoryRoot 'build\mvp.rbxlx')).Path
$testPlace = Join-Path $runDir 'mvp-tested.rbxlx'
Copy-Item -LiteralPath $canonical -Destination $testPlace -ErrorAction Stop
$preHash = (Get-FileHash -LiteralPath $testPlace -Algorithm SHA256).Hash.ToLowerInvariant()
(Get-Item -LiteralPath $testPlace).IsReadOnly = $true

$sessionFile = Join-Path $runDir 'studio-session.json'
$sessionArgs = @(
  '-SessionFile', $sessionFile,
  '-RepositoryRoot', $repositoryRoot,
  '-TrustedEvidenceRoot', $evidenceRoot,
  '-StudioExecutablePath', $studioExe
)

```

すべての`studio_session.ps1` actionへarrayの`@sessionArgs`を渡す。caller-supplied root/pathをmanifestだけから復元しない。Claude Codeのshell call間で変数やfunctionが残ると仮定しない。以下の各実行blockは、同じ4つのowner-verified literalから`$skillDir`、`$powershellHost`、`$sessionHostArgs`、`$sessionArgs`をそのblock内で再構築する。block内に複数actionがある場合も、各`& $powershellHost`は別OS processである。

同じcanonical `SessionFile`に対するactionは、script内のbounded interprocess mutexでread/effect/write全体を直列化する。lock timeoutまたはabandoned lockはfail-closedであり、並行実行を再試行して二重入力・二重launchを起こさない。別process起動は並行実行の許可ではない。

actualのexternal-effect action（Open/Start/AddClients/Input/Capture/Cleanup）は、外部副作用の直前にtrusted rootへschema v1 durable pending-action journalを新規作成し、成功completionをmanifestへ保存した後だけ削除する。Confirm等のmanifest-only更新にjournalは使わない。journalはaction ID/type/time、SessionFile、ownership ID、事前manifest SHA、target intent、caller PID/Windows session/SID/hostを束縛する。process crash後にjournalが残っていれば、Confirmを含む後続のactual state-changing actionは自動再試行せず停止する。`List`でjournalとowned PIDを読み、Studio/MCP/log/manifestを手動照合して、未所有candidateや部分完了を解消した証跡を残してからownerがjournalを処理する。journalが残ったまま「失敗したから何も起きなかった」と推定しない。

external-effect callがstructured successを返さず終了した場合も即時再試行しない。fresh `List`で`pendingActionJournal`とmanifestの`lastCompletedExternalAction`（action ID、target/result binding、completion時刻）を確認する。journalが消えてcompletionだけが残る場合は、effectとmanifest commitが完了して応答だけ失われた可能性があるため、同じinput/launch/capture/closeを再送しない。

## 4. schema v7 owned session

### 4.1 Open

```powershell
$skillDir = '<SKILL.md本文で展開済みの絶対path>'
$powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
$env:PSModulePath = [IO.Path]::Combine([IO.Path]::GetDirectoryName($powershellHost), 'Modules')
$sessionHostArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-OutputFormat','XML','-File',(Join-Path $skillDir 'scripts\studio_session.ps1'))
$runDir = '<今回のunique trusted run directory>'
$testPlace = Join-Path $runDir 'mvp-tested.rbxlx'
$sessionArgs = @('-SessionFile',(Join-Path $runDir 'studio-session.json'),'-RepositoryRoot','<exact Git root>','-TrustedEvidenceRoot','<preflight済みroot>','-StudioExecutablePath','<approved signed Studio exe>')
$plan = & $powershellHost @sessionHostArgs '-Action' 'Open' @sessionArgs '-PlacePath' $testPlace '-DryRun'
if ($LASTEXITCODE -ne 0 -or -not [bool]$plan.ok) { throw 'Fresh Open DryRun process failed.' }
$opened = & $powershellHost @sessionHostArgs '-Action' 'Open' @sessionArgs '-PlacePath' $testPlace
if ($LASTEXITCODE -ne 0 -or -not [bool]$opened.ok) { throw 'Fresh Open process failed.' }
```

実行はread-only test copyを開く承認後だけ行う。Studioは承認済みexecutableのdirectoryをworking directoryとして起動される。新規PIDをlaunch前後差分から一意に結び付けられない場合は失敗する。返る`edit`は`launchIntent`だけを持つ未確認candidateであり、titleやprocess数はrole/placeの証明ではない。

schema v7 manifestは、runの`ownershipId`、physical repository/Git/evidence/script roots、Studio path・SHA・signer・version、Studio version directory、session/input/capture scriptのpath・SHA・file identity、place path・SHA、place evidence、およびowned processごとのPID/start/session/path/launch intent/role evidenceを保持する。rootにはpending journal schema versionと最後にcommit済みのexternal action bindingも保持する。script/Studio directoryはrepository、Git administration、TEMP、evidenceから物理分離する。manifestだけを根拠にforeign processを所有扱いしない。

### 4.2 role/place handshake

対象instanceを明示したStudio MCPまたは権威log probeから、UTF-8 JSONを新規fileとして保存する。manifestを写して証拠を捏造しない。schema version 1の必須項目は次のとおり。

- `evidenceType: "roblox-studio-role-handshake"`
- `source: "studio-mcp" | "studio-log-handshake"`
- strict UTCの`observedAtUtc`、run内で一意な`eventId`と`probeId`、JSON booleanの`verified:true`
- `ownershipId`、JSON integerの`pid`/`sessionId`、`startTimeUtc`、`executablePath`
- `launchIntent`と、それと一致する`observedRole`
- 対象instanceが独立観測した`observedPlaceSha256`または`observedBuildSha256`

observed place/build SHAはopened artifact SHAと一致しなければならない。`source`文字列は暗号学的な出所証明ではないため、probe command、instance selector、元log/eventも保持する。独立観測できなければ`BLOCKED`とする。

```powershell
$skillDir = '<SKILL.md本文で展開済みの絶対path>'
$powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
$env:PSModulePath = [IO.Path]::Combine([IO.Path]::GetDirectoryName($powershellHost), 'Modules')
$sessionHostArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-OutputFormat','XML','-File',(Join-Path $skillDir 'scripts\studio_session.ps1'))
$runDir = '<今回のunique trusted run directory>'
$sessionArgs = @('-SessionFile',(Join-Path $runDir 'studio-session.json'),'-RepositoryRoot','<exact Git root>','-TrustedEvidenceRoot','<preflight済みroot>','-StudioExecutablePath','<approved signed Studio exe>')
$inventory = & $powershellHost @sessionHostArgs '-Action' 'List' @sessionArgs
if ($LASTEXITCODE -ne 0 -or -not [bool]$inventory.ok) { throw 'Fresh List process failed.' }
$edit = $inventory.data.processes | Where-Object launchIntent -CEQ 'edit' | Select-Object -First 1
$editEvidence = (Resolve-Path -LiteralPath (Join-Path $runDir 'edit-handshake-01.json')).Path
$editEvidenceSha = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $editEvidence -Algorithm SHA256).Hash

$plan = & $powershellHost @sessionHostArgs '-Action' 'Confirm' @sessionArgs `
  '-ConfirmPid' ([int]$edit.pid) '-EvidenceFile' $editEvidence `
  '-EvidenceSha256' $editEvidenceSha '-ConfirmPlace' '-DryRun'
if ($LASTEXITCODE -ne 0 -or -not [bool]$plan.ok) { throw 'Fresh Confirm DryRun process failed.' }
$confirmed = & $powershellHost @sessionHostArgs '-Action' 'Confirm' @sessionArgs `
  '-ConfirmPid' ([int]$edit.pid) '-EvidenceFile' $editEvidence `
  '-EvidenceSha256' $editEvidenceSha '-ConfirmPlace'
if ($LASTEXITCODE -ne 0 -or -not [bool]$confirmed.ok) { throw 'Fresh Confirm process failed.' }
```

role/place evidenceの有効期間は観測から10分である。長いrunでは、有効期限前に同じPIDを新しくprobeし、別のimmutable JSON path、より新しい`observedAtUtc`、新しい`eventId`/`probeId`で`Confirm`を再実行する。editのplace更新には再度`-ConfirmPlace`を付ける。既存fileのbyte変更や古い証拠の再利用は拒否される。

### 4.3 serverを1台開始

通常は現在版で確認したshortcutを使う。default経路でも当該Start操作への所有者明示承認が必要である。承認を証跡へ記録してからDryRunし、actual直前に同じ対象のidentity/role/placeを再検証する。`-AllowOsInput`は承認済みであるという呼出側assertionにすぎず、承認そのものを作らない。

```powershell
$skillDir = '<SKILL.md本文で展開済みの絶対path>'
$powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
$env:PSModulePath = [IO.Path]::Combine([IO.Path]::GetDirectoryName($powershellHost), 'Modules')
$sessionHostArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-OutputFormat','XML','-File',(Join-Path $skillDir 'scripts\studio_session.ps1'))
$runDir = '<今回のunique trusted run directory>'
$sessionArgs = @('-SessionFile',(Join-Path $runDir 'studio-session.json'),'-RepositoryRoot','<exact Git root>','-TrustedEvidenceRoot','<preflight済みroot>','-StudioExecutablePath','<approved signed Studio exe>')
$inventory = & $powershellHost @sessionHostArgs '-Action' 'List' @sessionArgs
if ($LASTEXITCODE -ne 0 -or -not [bool]$inventory.ok) { throw 'Fresh List process failed.' }
$editPid = [int](($inventory.data.processes | Where-Object launchIntent -CEQ 'edit' | Select-Object -First 1).pid)
$plan = & $powershellHost @sessionHostArgs '-Action' 'Start' @sessionArgs '-EditPid' $editPid '-DryRun'
if ($LASTEXITCODE -ne 0 -or -not [bool]$plan.ok) { throw 'Fresh Start DryRun process failed.' }
$serverCandidate = & $powershellHost @sessionHostArgs '-Action' 'Start' @sessionArgs `
  '-EditPid' $editPid '-AllowOsInput'
if ($LASTEXITCODE -ne 0 -or -not [bool]$serverCandidate.ok) { throw 'Fresh Start process failed.' }
```

返るserver candidateを、`launchIntent:"server"`、`observedRole:"server"`、artifact SHAを持つ新しい独立handshakeでConfirmする。Start前のtopologyは確認済みedit 1件、server/client 0件でなければならない。

shortcutが現在版で使えずmenu fallbackが必要な場合だけ、同じrunのedit window captureから`viewport`、`startMenu`、`startItem`を測り、後述のcoordinate evidenceとそのSHAを一緒に渡す。固定値を再利用しない。popupが別top-level HWNDになるStudio版ではexact-main-HWND gateが安全側に拒否するため、推測で緩めず`BLOCKED`とする。

### 4.4 座標証拠とclient追加

AddClientsは、確認済みserverの現在のexact main windowをcaptureし、同じ画像から`testMenu`と`addClient`を測る。window layoutが変わるたびに取り直す。

```powershell
$skillDir = '<SKILL.md本文で展開済みの絶対path>'
$powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
$env:PSModulePath = [IO.Path]::Combine([IO.Path]::GetDirectoryName($powershellHost), 'Modules')
$sessionHostArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-OutputFormat','XML','-File',(Join-Path $skillDir 'scripts\studio_session.ps1'))
$runDir = '<今回のunique trusted run directory>'
$evidenceRoot = '<preflight済みroot>'
$sessionArgs = @('-SessionFile',(Join-Path $runDir 'studio-session.json'),'-RepositoryRoot','<exact Git root>','-TrustedEvidenceRoot',$evidenceRoot,'-StudioExecutablePath','<approved signed Studio exe>')
function ConvertFrom-JsonPreservingStrings { param([string]$Json); return Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $Json }
$inventory = & $powershellHost @sessionHostArgs '-Action' 'List' @sessionArgs
if ($LASTEXITCODE -ne 0 -or -not [bool]$inventory.ok) { throw 'Fresh List process failed.' }
$server = $inventory.data.processes | Where-Object launchIntent -CEQ 'server' | Select-Object -First 1
if (-not [bool]$server.valid -or -not [bool]$server.roleEvidenceValid -or
    -not [bool]$inventory.data.placeEvidenceValid) { throw 'Server role/place evidence is invalid.' }

$menuPng = Join-Path $runDir 'server-menu-01.png'
$capturePlan = & $powershellHost @sessionHostArgs '-Action' 'Capture' @sessionArgs `
  '-TargetPid' ([int]$server.pid) '-OutFile' $menuPng '-RequireForeground' `
  '-PrintWindowTimeoutSeconds' '15' '-DryRun'
if ($LASTEXITCODE -ne 0) { throw 'Fresh Window Capture DryRun process failed.' }
if (-not [bool]$capturePlan.ok -or [bool]$capturePlan.data.outputWritten) { throw 'Window capture DryRun failed.' }
$captureDispatch = & $powershellHost @sessionHostArgs '-Action' 'Capture' @sessionArgs `
  '-TargetPid' ([int]$server.pid) '-OutFile' $menuPng '-RequireForeground' `
  '-PrintWindowTimeoutSeconds' '15'
if ($LASTEXITCODE -ne 0) { throw 'Fresh Window Capture process failed.' }
$capture = $captureDispatch.data.capture
if (-not [bool]$captureDispatch.ok -or [string]$captureDispatch.data.operation -cne 'captured' -or
    -not [bool]$captureDispatch.data.outputWritten -or [string]::IsNullOrWhiteSpace([string]$capture.OutputSha256)) {
  throw 'Window capture did not return a committed hashed PNG.'
}
$captureJson = Microsoft.PowerShell.Utility\ConvertTo-Json -InputObject $capture -Depth 8
$captureResultFile = Join-Path $runDir 'server-menu-01.capture.json'
if (Test-Path -LiteralPath $captureResultFile) { throw 'Refusing to overwrite capture metadata.' }
[IO.File]::WriteAllText($captureResultFile, $captureJson, [Text.UTF8Encoding]::new($false))
$captureResultSha = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $captureResultFile -Algorithm SHA256).Hash.ToLowerInvariant()
```

画像をoperatorまたはMCPが確認し、current runで測った2点を、新規`server-menu-measured-points.json`の`testMenu:{x,y}`と`addClient:{x,y}`へJSON integerとして保存する。次のblockで、そのfileとcapture resultからschema version 1のcoordinate evidenceを新規作成する。

```powershell
$skillDir = '<SKILL.md本文で展開済みの絶対path>'
$powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
$env:PSModulePath = [IO.Path]::Combine([IO.Path]::GetDirectoryName($powershellHost), 'Modules')
$sessionHostArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-OutputFormat','XML','-File',(Join-Path $skillDir 'scripts\studio_session.ps1'))
$runDir = '<今回のunique trusted run directory>'
$sessionArgs = @('-SessionFile',(Join-Path $runDir 'studio-session.json'),'-RepositoryRoot','<exact Git root>','-TrustedEvidenceRoot','<preflight済みroot>','-StudioExecutablePath','<approved signed Studio exe>')
function ConvertFrom-JsonPreservingStrings { param([string]$Json); return Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $Json }
$inventory = & $powershellHost @sessionHostArgs '-Action' 'List' @sessionArgs
if ($LASTEXITCODE -ne 0 -or -not [bool]$inventory.ok) { throw 'Fresh List process failed.' }
$server = $inventory.data.processes | Where-Object launchIntent -CEQ 'server' | Select-Object -First 1
$captureResultFile = Join-Path $runDir 'server-menu-01.capture.json'
$capture = ConvertFrom-JsonPreservingStrings -Json ([IO.File]::ReadAllText($captureResultFile, [Text.UTF8Encoding]::new($false,$true)))
$measurementFile = Join-Path $runDir 'server-menu-measured-points.json'
$measured = ConvertFrom-JsonPreservingStrings -Json ([IO.File]::ReadAllText($measurementFile, [Text.UTF8Encoding]::new($false,$true)))
$testMenuX=[int]$measured.testMenu.x; $testMenuY=[int]$measured.testMenu.y
$addClientX=[int]$measured.addClient.x; $addClientY=[int]$measured.addClient.y
$coordinate = [ordered]@{
  schemaVersion = 1
  evidenceType = 'roblox-studio-coordinate-measurement'
  source = 'operator-reviewed-capture'
  observedAtUtc = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
  eventId = "coord-$([guid]::NewGuid().ToString('N'))"
  probeId = "probe-$([guid]::NewGuid().ToString('N'))"
  verified = $true
  runId = [string]$inventory.data.ownershipId
  pid = [int]$server.pid
  startTimeUtc = [string]$server.startTimeUtc
  sessionId = [int]$server.sessionId
  executablePath = [string]$server.executablePath
  mainWindowHandle = [int64]$capture.WindowHandle
  capturePath = [string]$capture.OutFile
  captureSha256 = ([string]$capture.OutputSha256).ToLowerInvariant()
  capturedAtUtc = [string]$capture.CapturedAtUtc
  points = [ordered]@{
    testMenu = [ordered]@{ x = [int]$testMenuX; y = [int]$testMenuY }
    addClient = [ordered]@{ x = [int]$addClientX; y = [int]$addClientY }
  }
}
$coordinateFile = Join-Path $runDir 'server-menu-coordinates-01.json'
if (Test-Path -LiteralPath $coordinateFile) { throw 'Refusing to overwrite coordinate evidence.' }
$coordinateJson = Microsoft.PowerShell.Utility\ConvertTo-Json -InputObject $coordinate -Depth 8
[IO.File]::WriteAllText($coordinateFile, $coordinateJson, [Text.UTF8Encoding]::new($false))
$coordinateSha = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $coordinateFile -Algorithm SHA256).Hash
```

coordinate evidenceはcaptureから5分以内だけ有効で、run ID、PID/start/session/path、current exact main HWND、PNG path/SHA/format/dimensions、現在のwindow dimensions、渡したpoint集合と一致しなければならない。PNGは同じsessionの`Action Capture`がそのrunへ新規生成した上限制約済みfileだけを使い、外部画像、既存画像、同一user writerが変更可能な画像をdecode対象にしない。

```powershell
$skillDir = '<SKILL.md本文で展開済みの絶対path>'
$powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
$env:PSModulePath = [IO.Path]::Combine([IO.Path]::GetDirectoryName($powershellHost), 'Modules')
$sessionHostArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-OutputFormat','XML','-File',(Join-Path $skillDir 'scripts\studio_session.ps1'))
$runDir = '<今回のunique trusted run directory>'
$sessionArgs = @('-SessionFile',(Join-Path $runDir 'studio-session.json'),'-RepositoryRoot','<exact Git root>','-TrustedEvidenceRoot','<preflight済みroot>','-StudioExecutablePath','<approved signed Studio exe>')
function ConvertFrom-JsonPreservingStrings { param([string]$Json); return Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $Json }
$inventory = & $powershellHost @sessionHostArgs '-Action' 'List' @sessionArgs
if ($LASTEXITCODE -ne 0 -or -not [bool]$inventory.ok) { throw 'Fresh List process failed.' }
$server = $inventory.data.processes | Where-Object launchIntent -CEQ 'server' | Select-Object -First 1
$coordinateFile = Join-Path $runDir 'server-menu-coordinates-01.json'
$coordinateDoc = ConvertFrom-JsonPreservingStrings -Json ([IO.File]::ReadAllText($coordinateFile, [Text.UTF8Encoding]::new($false,$true)))
$coordinateSha = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $coordinateFile -Algorithm SHA256).Hash
$testMenuX=[int]$coordinateDoc.points.testMenu.x; $testMenuY=[int]$coordinateDoc.points.testMenu.y
$addClientX=[int]$coordinateDoc.points.addClient.x; $addClientY=[int]$coordinateDoc.points.addClient.y
$plan = & $powershellHost @sessionHostArgs '-Action' 'AddClients' @sessionArgs `
  '-ServerPid' ([int]$server.pid) '-Clients' '1' `
  '-TestMenuX' $testMenuX '-TestMenuY' $testMenuY `
  '-AddClientX' $addClientX '-AddClientY' $addClientY `
  '-CoordinateEvidenceFile' $coordinateFile '-CoordinateEvidenceSha256' $coordinateSha '-DryRun'
if ($LASTEXITCODE -ne 0 -or -not [bool]$plan.ok) { throw 'Fresh AddClients DryRun process failed.' }

$clientCandidate = & $powershellHost @sessionHostArgs '-Action' 'AddClients' @sessionArgs `
  '-ServerPid' ([int]$server.pid) '-Clients' '1' `
  '-TestMenuX' $testMenuX '-TestMenuY' $testMenuY `
  '-AddClientX' $addClientX '-AddClientY' $addClientY `
  '-CoordinateEvidenceFile' $coordinateFile '-CoordinateEvidenceSha256' $coordinateSha `
  '-AllowOsInput'
if ($LASTEXITCODE -ne 0 -or -not [bool]$clientCandidate.ok) { throw 'Fresh AddClients process failed.' }
```

1 callは1 candidateだけを作る。そのcandidateをartifact SHA付きの独立handshakeでConfirmし、`List`で全client evidenceが有効と確認してから、次の1台へ進む。想定人数まで「capture/計測（layout変化時）→1台追加→Confirm」を繰り返す。process作成はjoin成功ではないため、serverのauthoritative rosterから`PID ↔ client:N ↔ player`対応表を作る。

## 5. 状態・ログ・入力

画面だけで合格にしない。

1. 正しいserver/client consoleへ無条件probeが届くことを確認する。
2. server構造化eventを取得し、直後にserver DataModelから権威状態を直接読む。
3. 対象clientのPlayerGui実体と表示値を直接読む。
4. run/test/event ID、artifact SHA、timestamp、PID/role/player対応で3観測を相関する。

OS入力前は、その操作への所有者明示承認を証跡で確認したうえでauthoritative rosterを再照会し、`server PID → TargetPid → client:N → player ID/name`、join event ID、観測時刻、artifact SHAを保存する。session helperはprocess roleを検証するがplayer参加も承認も証明しない。承認または現在状態の対応を確認できなければ`BLOCKED`とする。

```powershell
$skillDir = '<SKILL.md本文で展開済みの絶対path>'
$powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
$env:PSModulePath = [IO.Path]::Combine([IO.Path]::GetDirectoryName($powershellHost), 'Modules')
$sessionHostArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-OutputFormat','XML','-File',(Join-Path $skillDir 'scripts\studio_session.ps1'))
$runDir = '<今回のunique trusted run directory>'
$sessionArgs = @('-SessionFile',(Join-Path $runDir 'studio-session.json'),'-RepositoryRoot','<exact Git root>','-TrustedEvidenceRoot','<preflight済みroot>','-StudioExecutablePath','<approved signed Studio exe>')
$inventory = & $powershellHost @sessionHostArgs '-Action' 'List' @sessionArgs
if ($LASTEXITCODE -ne 0 -or -not [bool]$inventory.ok) { throw 'Fresh List process failed.' }
$client = $inventory.data.processes | Where-Object launchIntent -CEQ 'client:1' | Select-Object -First 1
$actions = '<approved action grammar from the current test case>'
$inputPlan = & $powershellHost @sessionHostArgs '-Action' 'Input' @sessionArgs `
  '-TargetPid' ([int]$client.pid) '-InputActions' $actions '-DryRun'
if ($LASTEXITCODE -ne 0) { throw 'Fresh Input DryRun process failed.' }
if (-not [bool]$inputPlan.ok -or [bool]$inputPlan.data.osInputDispatched) { throw 'Input DryRun failed.' }
$inputDispatch = & $powershellHost @sessionHostArgs '-Action' 'Input' @sessionArgs `
  '-TargetPid' ([int]$client.pid) '-InputActions' $actions '-AllowOsInput'
if ($LASTEXITCODE -ne 0) { throw 'Fresh Input process failed.' }
if (-not [bool]$inputDispatch.ok -or -not [bool]$inputDispatch.data.osInputDispatched) { throw 'Input dispatch failed.' }
```

`studio_input.ps1`をoperatorから直接呼ばない。session Inputはexactly one confirmed server、target client、全client role evidence、place evidence、live PID/start/session/pathを直前に再検証する。確認済み証拠の最短expiryを内部`InputDeadlineUtc`として渡し、action planの保守上限が期限内に収まらない場合は送信前に拒否する。actual helperも各action直前に残り時間を確認する。拒否されたらrole/place/coordinate evidenceをrefreshして最初からplanし直す。各action直前にはexact main HWND = foreground HWNDとowner PIDも照合し、同一PIDのmodalへ送らない。

action grammar:

- `press:KEY[:MS]`（既定100ms、1..2000ms）
- `wait:MS`（1..600000ms）
- `click`（exact main window中央）または`click:X:Y`（同window矩形相対、X/Yは0以上）
- `absclick:X:Y`（Windows virtual-screen座標、負値可）

空token、余分field、未知key、別callまで保持されるkey-down状態を拒否する。最大1000 action、合計duration 1800000ms。dispatch成功は入力送信だけを示す。直後にinput event、server state、対象client UIを再照会し、同時操作を検証済みにしない。

## 6. capture

Window captureを基本とし、必ず`studio_session.ps1 -Action Capture`を使う。low-level `studio_capture.ps1`のpath実行はDryRunを含め拒否され、sessionが検証済みbyte snapshotだけをmemory dispatchする。Window modeはowned PID identityとfresh role/place evidenceを直前に再検証する。FullScreen modeも同じmanifest/trusted rootと明示同意に束縛する。両modeとも、dimension 8192、9,437,184 pixels、raw/decoded PNG 36 MiBまでで、1..60秒のhidden worker deadlineを持つ。timeout時に終了対象になるのはcapture workerだけで、Studioは終了しない。結果の`OutputSha256`、`OutputBytes`、`CapturedAtUtc`を証跡へ保存する。

既存fileは原則FAILにし、新名を使う。画像だけでrole、place、gameplayを主張しない。Window capture前に`List`でidentity/role/place evidenceを再検証する。`RequireForeground`を付けても同PID modalはrole証明にならない。

Full-screenは全monitorと機密情報を含みうる。今回の明示同意と機密window非表示を記録した場合だけ使う。

```powershell
$skillDir = '<SKILL.md本文で展開済みの絶対path>'
$powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
$env:PSModulePath = [IO.Path]::Combine([IO.Path]::GetDirectoryName($powershellHost), 'Modules')
$sessionHostArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-OutputFormat','XML','-File',(Join-Path $skillDir 'scripts\studio_session.ps1'))
$runDir = '<今回のunique trusted run directory>'
$sessionArgs = @('-SessionFile',(Join-Path $runDir 'studio-session.json'),'-RepositoryRoot','<exact Git root>','-TrustedEvidenceRoot','<preflight済みroot>','-StudioExecutablePath','<approved signed Studio exe>')
$desktopPng = Join-Path $runDir 'desktop-consented-01.png'
$desktopPlan = & $powershellHost @sessionHostArgs '-Action' 'Capture' @sessionArgs `
  '-FullScreen' '-AllowFullScreenCapture' '-FullScreenTimeoutSeconds' '15' `
  '-OutFile' $desktopPng '-DryRun'
if ($LASTEXITCODE -ne 0) { throw 'Fresh FullScreen Capture DryRun process failed.' }
if (-not [bool]$desktopPlan.ok -or [bool]$desktopPlan.data.outputWritten) { throw 'Full-screen DryRun failed.' }
$desktopDispatch = & $powershellHost @sessionHostArgs '-Action' 'Capture' @sessionArgs `
  '-FullScreen' '-AllowFullScreenCapture' '-FullScreenTimeoutSeconds' '15' `
  '-OutFile' $desktopPng
if ($LASTEXITCODE -ne 0) { throw 'Fresh FullScreen Capture process failed.' }
$desktopCapture = $desktopDispatch.data.capture
if (-not [bool]$desktopDispatch.ok -or [string]$desktopDispatch.data.operation -cne 'captured' -or
    -not [bool]$desktopDispatch.data.outputWritten) { throw 'Full-screen capture did not commit.' }
$desktopJson = Microsoft.PowerShell.Utility\ConvertTo-Json -InputObject $desktopCapture -Depth 8
$desktopResultFile = Join-Path $runDir 'desktop-consented-01.capture.json'
if (Test-Path -LiteralPath $desktopResultFile) { throw 'Refusing to overwrite capture metadata.' }
[IO.File]::WriteAllText($desktopResultFile, $desktopJson, [Text.UTF8Encoding]::new($false))
$desktopResultSha = (Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $desktopResultFile -Algorithm SHA256).Hash.ToLowerInvariant()
```

PNG pixel原点は`(0,0)`、OS virtual-screen原点は負値を取りうる。absolute inputへ変換するときだけ次を使う。

```text
osX = imageX + OriginX
osY = imageY + OriginY
```

## 7. clipboardと後始末

clipboardの読取・上書き・貼付は自動実行しない。lossless backup/restore、機密値の非記録、target bindingを保証する専用helperがないため、MCP/test harnessで代替できなければ`BLOCKED`とする。

まずpreviewする。

```powershell
$skillDir = '<SKILL.md本文で展開済みの絶対path>'
$powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
$env:PSModulePath = [IO.Path]::Combine([IO.Path]::GetDirectoryName($powershellHost), 'Modules')
$sessionHostArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-OutputFormat','XML','-File',(Join-Path $skillDir 'scripts\studio_session.ps1'))
$runDir = '<今回のunique trusted run directory>'
$sessionArgs = @('-SessionFile',(Join-Path $runDir 'studio-session.json'),'-RepositoryRoot','<exact Git root>','-TrustedEvidenceRoot','<preflight済みroot>','-StudioExecutablePath','<approved signed Studio exe>')
$preview = & $powershellHost @sessionHostArgs '-Action' 'Cleanup' @sessionArgs '-WhatIf'
if ($LASTEXITCODE -ne 0 -or -not [bool]$preview.ok) { throw 'Fresh Cleanup preview process failed.' }
```

process closeの対象PID一覧を提示し、今回のCleanupだけに有効な所有者個別明示承認を証跡へ保存した後だけ実行する。`-Force`は非対話実行を選ぶ呼出側assertionであり、承認そのものでもidentity再検証の代替でもない。actual直前にfresh `List`とrole/place evidenceを取り直す。対話`-Confirm`はこの自動経路では使わない。

```powershell
$skillDir = '<SKILL.md本文で展開済みの絶対path>'
$powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
$env:PSModulePath = [IO.Path]::Combine([IO.Path]::GetDirectoryName($powershellHost), 'Modules')
$sessionHostArgs = @('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-OutputFormat','XML','-File',(Join-Path $skillDir 'scripts\studio_session.ps1'))
$runDir = '<今回のunique trusted run directory>'
$sessionArgs = @('-SessionFile',(Join-Path $runDir 'studio-session.json'),'-RepositoryRoot','<exact Git root>','-TrustedEvidenceRoot','<preflight済みroot>','-StudioExecutablePath','<approved signed Studio exe>')
$closed = & $powershellHost @sessionHostArgs '-Action' 'Cleanup' @sessionArgs '-Force'
if ($LASTEXITCODE -ne 0 -or -not [bool]$closed.ok) { throw 'Fresh Cleanup process failed.' }
```

scriptは、fresh role/place evidence、exact identity、cached/current main HWND、HWND ownerが直前にも一致するowned processだけへ`WM_CLOSE`を送る。強制killしない。未確認、期限切れ、証拠改変、identity不一致には触れず報告する。他processへ対象を広げない。

最後にtest artifact SHA-256を再計測する。消失、byte変更、別path openがあればrun全体のartifact同一性主張をFAILにし、新しいcopyと新しいsessionでやり直す。

## 8. 症状別の確認順

- input無反応: scripted testing可否 → evidence freshness → roster mapping → interactive desktop → exact main HWND = foreground HWND → dispatch → server受理event。
- menu拒否: current exact-main-window capture → 5分以内のcoordinate evidence → popup HWND形態。別top-level popupなら自動経路は`BLOCKED`。
- client不成立: 1 dispatchのPID差分 → candidate identity → role handshake → authoritative join roster。
- state不変: input受理event → server権威状態 → guard/rejection reason。
- HUD不変: 正しいclient出力 → wire上の値と型 → 表示中PlayerGui instance。
- error 0件: serverと全owned clientについて、検索範囲、offset/event ID、実数を記録したか確認。
- evidence期限切れ: 新しいprobe/new file/new eventId・probeIdでConfirm refresh。既存fileを編集しない。
- artifact hash変化: runを無効化し、新copy・新sessionで再試験。
