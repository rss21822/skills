<#
.SYNOPSIS
  Roblox Studio のテストプロセスを、JSON 所有マニフェスト単位で安全に管理する。

.DESCRIPTION
  プロセス名の総数や「最新プロセス」を所有権の根拠にしない。Open/Start/
  AddClients の各操作直前に Roblox Studio の PID 集合を採取し、その操作後に
  新しく出現した単一 PID は未確認候補として SessionFile に登録するだけに留める。
  Confirm で独立証拠を照合した後にのみ入力元・終了対象として扱う。PID、開始時刻、
  Windows セッション ID、実行ファイル完全パス、所有 ID、証拠SHAを毎回再検証する。

  OS入力とCleanupは、今回のexact actionごとのowner明示承認と、effect直前のidentity
  再検証を両方必要とする。-AllowOsInput/-Forceは承認済みというcaller assertionであり、
  承認そのものやidentity再検証の代替ではない。Cleanup は -Force が必須で、
  PowerShell の -WhatIf/-Confirm に対応する。
  Stop-Process -Force や tscon は実行しない。

  Confirm の証拠 JSON は、このスクリプトから独立した MCP/権威ログが作る外部契約である。
  このスクリプトが検証できるのは JSON のidentity束縛、place hash、ファイルSHA-256だけで、
  証拠生成元の意味的な正しさそのものは保証しない。未確認候補は Cleanup でも閉じない。

  schemaVersion 7 は、caller-supplied exact Git root、Git administration roots、repo/TEMP
  外の canonical TrustedEvidenceRoot、single-link Place/Session/Evidence files、および署名済み
  Studio inventory pathを束縛する。さらにsession/input/capture各scriptのcanonical path、
  SHA-256、file identityを固定し、scripts rootとStudio version directoryがrepo/Git/evidence/
  TEMPから物理的に分離されていることを毎action検証する。input helperは再検証した正確な
  byte snapshotだけをmemory dispatchし、直接実行を拒否する。role/place evidence の有効期間は10分で、継続時は同一
  identityに対する、より新しいeventId/probeIdを持つ別のimmutable JSON fileでConfirmを更新する。
  全role evidenceはopened place/build SHA-256を観測しなければならない。OS input planは必要な
  全証拠の最短expiryまでに保守的な実行上限が収まらなければ、DryRunを含めて拒否する。
  Capture は公開session actionだけを許可する。window modeはowned PID identityとfresh role/place
  evidenceを再検証し、full-screen modeはTargetPidを受けずcurrent-runの明示同意を必須とする。
  どちらもcapture helperのpathを直接実行せず、manifest一致のmemory snapshotだけをdispatchする。
  Open/Start/AddClients/Input/Capture/Cleanup のactual external effectは、SessionFile隣接の
  schemaVersion 1 pending-action journalをCreateNew+exclusive+write-throughで先に永続化する。
  成功completionをschemaVersion 7 manifestへ保存して再読検証した後だけjournalを削除する。
  crash等でjournalが残ればactual mutationを全て拒否し、ownerのmanual reconcileを要求する。
  Preflight/List/DryRun/WhatIfは副作用なしで残存journal状態をstructured resultへ報告できる。
  各public Actionは必ず新しいOS System32 Windows PowerShell 5.1プロセスから1回だけ呼ぶ。
  DryRunとactualを同じPowerShell hostで連続実行してはならず、それぞれ別のfresh hostを使う。

.EXAMPLE
  $powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
  $repo = 'C:\work\game'
  $trusted = 'D:\RobloxMvpEvidence'
  $studio = 'C:\Program Files (x86)\Roblox\Versions\version-x\RobloxStudioBeta.exe'
  # Fresh exact System32 Windows PowerShell 5.1 with -NoProfile -NonInteractive is required;
  # every entry script also rejects ambient critical-command shadowing before security checks.
  # RepositoryRoot, TrustedEvidenceRoot, SessionFile, and the exact approved Studio path
  # are caller-supplied on every action; never trust root paths asserted only by a manifest.
  & $powershellHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat XML `
    -File '<SKILL.md本文で展開済みの絶対path>\scripts\studio_session.ps1' -Action Preflight `
    -SessionFile 'D:\RobloxMvpEvidence\preflight-session.json' `
    -RepositoryRoot $repo -TrustedEvidenceRoot $trusted -StudioExecutablePath $studio
  # After Preflight, the owner creates run-guid with fail-if-exists semantics and copies
  # the place as a normal file (never a hard link).
  # actualの前に、同一argsへ-DryRunを付けた別fresh childを先行する。
  $session = 'D:\RobloxMvpEvidence\run-guid\studio-session.json'
  & $powershellHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat XML `
    -File '<SKILL.md本文で展開済みの絶対path>\scripts\studio_session.ps1' -Action Open -SessionFile $session `
    -RepositoryRoot $repo -TrustedEvidenceRoot $trusted -StudioExecutablePath $studio `
    -PlacePath 'D:\RobloxMvpEvidence\run-guid\MVP.rbxlx'

.EXAMPLE
  $powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
  # Independent evidence JSON schemaVersion=1 must bind source/observedAtUtc/eventId/
  # probeId/verified plus ownershipId/pid/startTimeUtc/sessionId/executablePath,
  # launchIntent and observedRole. Every role binds observedPlaceSha256 or
  # observedBuildSha256; edit -ConfirmPlace also promotes it to the root place handshake.
  # actualの前に、同一argsへ-DryRunを付けた別fresh childを先行する。
  & $powershellHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat XML `
    -File '<SKILL.md本文で展開済みの絶対path>\scripts\studio_session.ps1' -Action Confirm -SessionFile $session `
    -RepositoryRoot $repo -TrustedEvidenceRoot $trusted -StudioExecutablePath $studio `
    -ConfirmPid 1234 -EvidenceFile 'D:\RobloxMvpEvidence\run-guid\edit.json' `
    -EvidenceSha256 '<64-hex>' -ConfirmPlace

.EXAMPLE
  $powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
  # ownerが今回のexact Start/targetへのOS入力を個別承認し、そのapproval IDをrun evidenceへ
  # 保存した後だけactualする。identity再検証は別の必須gate。
  # actualの前に、同一argsへ-DryRunを付けた別fresh childを先行する。
  & $powershellHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat XML `
    -File '<SKILL.md本文で展開済みの絶対path>\scripts\studio_session.ps1' -Action Start -SessionFile $session `
    -RepositoryRoot $repo -TrustedEvidenceRoot $trusted -StudioExecutablePath $studio `
    -EditPid 1234 -AllowOsInput

.EXAMPLE
  $powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
  # ownerが今回のexact AddClients/targetへのOS入力を個別承認し、そのapproval IDをrun evidenceへ
  # 保存した後だけactualする。identity再検証は別の必須gate。
  # actualの前に、同一argsへ-DryRunを付けた別fresh childを先行する。
  & $powershellHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat XML `
    -File '<SKILL.md本文で展開済みの絶対path>\scripts\studio_session.ps1' -Action AddClients -SessionFile $session `
    -RepositoryRoot $repo -TrustedEvidenceRoot $trusted -StudioExecutablePath $studio `
    -ServerPid 5678 -Clients 1 -TestMenuX $testMenuX -TestMenuY $testMenuY `
    -AddClientX $addClientX -AddClientY $addClientY `
    -CoordinateEvidenceFile $coordinateEvidence -CoordinateEvidenceSha256 $coordinateSha `
    -AllowOsInput
  # Confirm this one candidate independently before calling AddClients again.

.EXAMPLE
  $powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
  # Window capture accepts only an owned PID with fresh role and place evidence.
  & $powershellHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat XML `
    -File '<SKILL.md本文で展開済みの絶対path>\scripts\studio_session.ps1' -Action Capture -SessionFile $session `
    -RepositoryRoot $repo -TrustedEvidenceRoot $trusted -StudioExecutablePath $studio `
    -TargetPid 9012 -OutFile 'D:\RobloxMvpEvidence\run-guid\client-1.png' -DryRun

.EXAMPLE
  $powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
  # Full-screen capture has no target PID and requires current-run explicit consent.
  & $powershellHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat XML `
    -File '<SKILL.md本文で展開済みの絶対path>\scripts\studio_session.ps1' -Action Capture -SessionFile $session `
    -RepositoryRoot $repo -TrustedEvidenceRoot $trusted -StudioExecutablePath $studio `
    -FullScreen -AllowFullScreenCapture `
    -OutFile 'D:\RobloxMvpEvidence\run-guid\virtual-screen.png' -DryRun

.EXAMPLE
  $powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
  # ownerが今回のCleanupとexact target PID listを個別承認し、そのapproval IDをrun evidenceへ
  # 保存した後だけactualする。-Forceやownership記録だけでは承認にならない。
  # actualの前に、同一argsへ-DryRunを付けた別fresh childを先行する。
  & $powershellHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat XML `
    -File '<SKILL.md本文で展開済みの絶対path>\scripts\studio_session.ps1' -Action Cleanup -SessionFile $session `
    -RepositoryRoot $repo -TrustedEvidenceRoot $trusted -StudioExecutablePath $studio `
    -Force

.EXAMPLE
  $powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
  & $powershellHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat XML `
    -File '<SKILL.md本文で展開済みの絶対path>\scripts\studio_session.ps1' -Action Cleanup -SessionFile $session `
    -RepositoryRoot $repo -TrustedEvidenceRoot $trusted -StudioExecutablePath $studio -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('Preflight', 'Open', 'Confirm', 'Start', 'AddClients', 'Input', 'Capture', 'List', 'Cleanup')]
  [string]$Action,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$SessionFile,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$RepositoryRoot,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$TrustedEvidenceRoot,

  [string]$PlacePath,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$StudioExecutablePath,

  [ValidateRange(0, 2147483647)]
  [int]$EditPid = 0,

  [ValidateRange(0, 2147483647)]
  [int]$ServerPid = 0,

  [ValidateRange(0, 2147483647)]
  [int]$KeepPid = 0,

  [ValidateRange(0, 2147483647)]
  [int]$ConfirmPid = 0,

  [ValidateRange(0, 2147483647)]
  [int]$TargetPid = 0,

  [ValidateLength(1, 65535)]
  [string]$InputActions,

  [string]$OutFile,

  [switch]$FullScreen,
  [switch]$AllowFullScreenCapture,
  [switch]$RequireForeground,
  [switch]$AllowMinimized,
  [switch]$CaptureForce,

  [ValidateRange(1, 60)]
  [int]$PrintWindowTimeoutSeconds = 15,

  [ValidateRange(1, 60)]
  [int]$FullScreenTimeoutSeconds = 15,

  [string]$EvidenceFile,

  [ValidatePattern('^[0-9a-fA-F]{64}$')]
  [string]$EvidenceSha256,

  [string]$CoordinateEvidenceFile,

  [ValidatePattern('^[0-9a-fA-F]{64}$')]
  [string]$CoordinateEvidenceSha256,

  [ValidateSet(1)]
  [int]$Clients = 1,

  [ValidatePattern('^[A-Za-z0-9_]+$')]
  [string]$StartKey = 'F7',

  [ValidateRange(0, 100000)] [int]$ViewportX = 0,
  [ValidateRange(0, 100000)] [int]$ViewportY = 0,
  [ValidateRange(0, 100000)] [int]$TestMenuX = 0,
  [ValidateRange(0, 100000)] [int]$TestMenuY = 0,
  [ValidateRange(0, 100000)] [int]$AddClientX = 0,
  [ValidateRange(0, 100000)] [int]$AddClientY = 0,
  [ValidateRange(0, 100000)] [int]$StartMenuX = 0,
  [ValidateRange(0, 100000)] [int]$StartMenuY = 0,
  [ValidateRange(0, 100000)] [int]$StartItemX = 0,
  [ValidateRange(0, 100000)] [int]$StartItemY = 0,

  [ValidateRange(1, 1800)]
  [int]$TimeoutSeconds = 150,

  [ValidateScript({
    if ($_ -cne 'RobloxStudioBeta') {
      throw "ProcessName is fixed to the literal 'RobloxStudioBeta'; wildcards and overrides are forbidden."
    }
    $true
  })]
  [string]$ProcessName = 'RobloxStudioBeta',

  [switch]$ConfirmPlace,
  [switch]$AllowOsInput,
  [switch]$Force,
  [switch]$DryRun
)

$null = Microsoft.PowerShell.Core\Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:InvocationBoundParameters = @{} + $PSBoundParameters

# Bootstrap command discovery from the OS-owned Windows PowerShell tree only. This is
# intentionally done with .NET APIs before the first Get-Command/module autoload.
$entryExpectedHostPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine(
  [Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe'))
$entryExpectedHomePath = [System.IO.Path]::GetDirectoryName($entryExpectedHostPath)
$entryCurrentHostPath = [System.IO.Path]::GetFullPath(
  [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
if ([string]$PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1 -or
    -not [StringComparer]::OrdinalIgnoreCase.Equals($entryCurrentHostPath, $entryExpectedHostPath) -or
    -not [StringComparer]::OrdinalIgnoreCase.Equals(
      [System.IO.Path]::GetFullPath($PSHOME), $entryExpectedHomePath)) {
  throw "studio_session.ps1 requires the exact OS System32 Windows PowerShell 5.1 host: $entryExpectedHostPath"
}
$entryTrustedModuleRoot = [System.IO.Path]::GetFullPath(
  [System.IO.Path]::Combine($entryExpectedHomePath, 'Modules'))
foreach ($entryBootstrapPath in @(
  $entryExpectedHomePath, $entryExpectedHostPath, $entryTrustedModuleRoot
)) {
  $entryDriveRoot = [System.IO.Path]::GetPathRoot($entryBootstrapPath)
  $entryDrive = [System.IO.DriveInfo]::new($entryDriveRoot)
  if ($entryDrive.DriveType -ne [System.IO.DriveType]::Fixed -or -not $entryDrive.IsReady) {
    throw 'The System32 Windows PowerShell bootstrap tree must be on a ready local Fixed drive.'
  }
  $entryCursor = $entryDriveRoot
  foreach ($entrySegment in @($entryBootstrapPath.Substring($entryDriveRoot.Length).Split(
    [char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries))) {
    $entryCursor = [System.IO.Path]::Combine($entryCursor, $entrySegment)
    if (-not [System.IO.File]::Exists($entryCursor) -and
        -not [System.IO.Directory]::Exists($entryCursor)) {
      throw "Windows PowerShell bootstrap path component is missing: $entryCursor"
    }
    if (([System.IO.File]::GetAttributes($entryCursor) -band
        [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Windows PowerShell bootstrap path crosses a reparse point: $entryCursor"
    }
  }
}
[Environment]::SetEnvironmentVariable('PSModulePath', $entryTrustedModuleRoot, 'Process')

function Assert-TrustedSessionEntryFilePath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$TrustedRoot,
    [Parameter(Mandatory = $true)][string]$Label
  )

  if ($Path.StartsWith('\\', [StringComparison]::Ordinal) -or
      $Path -notmatch '^[A-Za-z]:[\\/]') {
    throw "$Label must use absolute local-drive syntax."
  }
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $rootPath = [System.IO.Path]::GetFullPath($TrustedRoot).TrimEnd([char[]]@('\', '/'))
  $rootPrefix = $rootPath + [System.IO.Path]::DirectorySeparatorChar
  if (-not $fullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "$Label escaped its trusted PowerShell root: $fullPath"
  }
  $driveRoot = [System.IO.Path]::GetPathRoot($fullPath)
  $drive = [System.IO.DriveInfo]::new($driveRoot)
  if ($drive.DriveType -ne [System.IO.DriveType]::Fixed -or -not $drive.IsReady) {
    throw "$Label must be on a ready local Fixed drive."
  }
  $cursor = $driveRoot
  $segments = @($fullPath.Substring($driveRoot.Length).Split(
    [char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries))
  for ($index = 0; $index -lt $segments.Count; $index++) {
    $cursor = [System.IO.Path]::Combine($cursor, $segments[$index])
    if (-not [System.IO.File]::Exists($cursor) -and -not [System.IO.Directory]::Exists($cursor)) {
      throw "$Label path component does not exist: $cursor"
    }
    $attributes = [System.IO.File]::GetAttributes($cursor)
    if (($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "$Label path crosses a reparse point: $cursor"
    }
    if ($index -lt ($segments.Count - 1) -and
        -not [System.IO.Directory]::Exists($cursor)) {
      throw "$Label path component is not a directory: $cursor"
    }
  }
  if (-not [System.IO.File]::Exists($fullPath)) {
    throw "$Label must resolve to an existing file: $fullPath"
  }
  return $fullPath
}

function Assert-NoAmbientCriticalCommandShadowing {
  $expected = @(
    @('Add-Type', 'Microsoft.PowerShell.Utility'),
    @('ConvertFrom-Json', 'Microsoft.PowerShell.Utility'),
    @('ConvertTo-Json', 'Microsoft.PowerShell.Utility'),
    @('ForEach-Object', 'Microsoft.PowerShell.Core'),
    @('Get-AuthenticodeSignature', 'Microsoft.PowerShell.Security'),
    @('Get-Command', 'Microsoft.PowerShell.Core'),
    @('Get-Content', 'Microsoft.PowerShell.Management'),
    @('Group-Object', 'Microsoft.PowerShell.Utility'),
    @('Get-Item', 'Microsoft.PowerShell.Management'),
    @('Get-Location', 'Microsoft.PowerShell.Management'),
    @('Get-Process', 'Microsoft.PowerShell.Management'),
    @('Join-Path', 'Microsoft.PowerShell.Management'),
    @('New-Object', 'Microsoft.PowerShell.Utility'),
    @('Remove-Item', 'Microsoft.PowerShell.Management'),
    @('Select-Object', 'Microsoft.PowerShell.Utility'),
    @('Set-Content', 'Microsoft.PowerShell.Management'),
    @('Split-Path', 'Microsoft.PowerShell.Management'),
    @('Start-Process', 'Microsoft.PowerShell.Management'),
    @('Start-Sleep', 'Microsoft.PowerShell.Utility'),
    @('Test-Path', 'Microsoft.PowerShell.Management'),
    @('Where-Object', 'Microsoft.PowerShell.Core'),
    @('Write-Output', 'Microsoft.PowerShell.Utility'),
    @('Write-Warning', 'Microsoft.PowerShell.Utility')
  )
  $psHomePath = [System.IO.Path]::GetFullPath($PSHOME).TrimEnd([char[]]@('\', '/'))
  $psHomePrefix = $psHomePath + [System.IO.Path]::DirectorySeparatorChar
  $moduleRootPrefix = [System.IO.Path]::GetFullPath(
    [System.IO.Path]::Combine($psHomePath, 'Modules')).TrimEnd([char[]]@('\', '/')) +
    [System.IO.Path]::DirectorySeparatorChar
  $isDesktopEngine = [string]$PSVersionTable.PSEdition -ceq 'Desktop'
  if ($isDesktopEngine) {
    $windowsDirectory = [System.IO.Directory]::GetParent([Environment]::SystemDirectory).FullName
    $trustedDllPrefixes = @(
      [System.IO.Path]::GetFullPath([System.IO.Path]::Combine(
        $windowsDirectory, 'Microsoft.Net', 'assembly', 'GAC_MSIL')).TrimEnd([char[]]@('\', '/')) +
        [System.IO.Path]::DirectorySeparatorChar
    )
  } else {
    $trustedDllPrefixes = @($psHomePrefix)
  }
  $expectedAssemblyNames = @{
    'Microsoft.PowerShell.Core' = 'System.Management.Automation'
    'Microsoft.PowerShell.Management' = 'Microsoft.PowerShell.Commands.Management'
    'Microsoft.PowerShell.Security' = 'Microsoft.PowerShell.Security'
    'Microsoft.PowerShell.Utility' = 'Microsoft.PowerShell.Commands.Utility'
  }
  $validatedPowerShellFiles = @{}

  foreach ($entry in $expected) {
    $resolved = @(Microsoft.PowerShell.Core\Get-Command -Name $entry[0] -All -ErrorAction Stop)
    $resolvedDll = if ($resolved.Count -gt 0) { [string]$resolved[0].DLL } else { '' }
    $resolvedModulePath = if ($resolved.Count -gt 0 -and $null -ne $resolved[0].Module) {
      [string]$resolved[0].Module.Path
    } else { '' }
    $dllTrusted = $false
    if (-not [string]::IsNullOrWhiteSpace($resolvedDll)) {
      $resolvedDllFull = [System.IO.Path]::GetFullPath($resolvedDll)
      foreach ($trustedDllPrefix in $trustedDllPrefixes) {
        if ($resolvedDllFull.StartsWith($trustedDllPrefix, [StringComparison]::OrdinalIgnoreCase)) {
          $dllTrusted = $true
          break
        }
      }
    }
    $modulePathTrusted = if ([string]$entry[1] -ceq 'Microsoft.PowerShell.Core') {
      [string]::IsNullOrWhiteSpace($resolvedModulePath)
    } elseif (-not [string]::IsNullOrWhiteSpace($resolvedModulePath)) {
      [System.IO.Path]::GetFullPath($resolvedModulePath).StartsWith(
        $moduleRootPrefix, [StringComparison]::OrdinalIgnoreCase)
    } else { $false }
    if ($resolved.Count -eq 0 -or $resolved[0].CommandType -ne [System.Management.Automation.CommandTypes]::Cmdlet -or
        [string]$resolved[0].ModuleName -cne [string]$entry[1] -or
        -not $dllTrusted -or -not $modulePathTrusted) {
      throw "Ambient command shadowing is forbidden for '$($entry[0])'; expected first resolution to the trusted $($entry[1]) cmdlet from PSHOME/GAC."
    }

    if (-not $validatedPowerShellFiles.ContainsKey($resolvedDllFull)) {
      $dllTrustRoot = if ($isDesktopEngine) {
        $trustedDllPrefixes[0].TrimEnd([char[]]@('\', '/'))
      } else { $psHomePath }
      $resolvedDllFull = Assert-TrustedSessionEntryFilePath -Path $resolvedDllFull `
        -TrustedRoot $dllTrustRoot -Label "Critical cmdlet DLL for $($entry[0])"
      $assemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($resolvedDllFull)
      $assemblyToken = [BitConverter]::ToString($assemblyName.GetPublicKeyToken()).Replace('-', '').ToLowerInvariant()
      if ([string]$assemblyName.Name -cne [string]$expectedAssemblyNames[[string]$entry[1]] -or
          $assemblyToken -cne '31bf3856ad364e35') {
        throw "Critical cmdlet DLL assembly identity is untrusted for '$($entry[0])'."
      }
      $dllItem = Microsoft.PowerShell.Management\Get-Item -LiteralPath $resolvedDllFull -Force -ErrorAction Stop
      $dllLinkProperty = $dllItem.PSObject.Properties['LinkType']
      $dllLinkType = if ($null -ne $dllLinkProperty) { [string]$dllLinkProperty.Value } else { '' }
      if (-not $isDesktopEngine -and -not [string]::IsNullOrWhiteSpace($dllLinkType)) {
        throw "PowerShell 7 critical cmdlet DLL hard links/symbolic links are forbidden: $resolvedDllFull"
      }
      $dllSignature = Microsoft.PowerShell.Security\Get-AuthenticodeSignature `
        -LiteralPath $resolvedDllFull -ErrorAction Stop
      $dllSigner = if ($null -ne $dllSignature.SignerCertificate) {
        [string]$dllSignature.SignerCertificate.Subject
      } else { '' }
      if ([string]$dllSignature.Status -cne 'Valid' -or
          $dllSigner -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {
        throw "Critical cmdlet DLL must have a valid Microsoft signature: $resolvedDllFull"
      }
      $validatedPowerShellFiles[$resolvedDllFull] = $true
    }

    if (-not [string]::IsNullOrWhiteSpace($resolvedModulePath) -and
        -not $validatedPowerShellFiles.ContainsKey($resolvedModulePath)) {
      $resolvedModulePath = Assert-TrustedSessionEntryFilePath -Path $resolvedModulePath `
        -TrustedRoot $moduleRootPrefix.TrimEnd([char[]]@('\', '/')) `
        -Label "Critical cmdlet module manifest for $($entry[0])"
      if ([System.IO.Path]::GetFileName($resolvedModulePath) -cne "$($entry[1]).psd1") {
        throw "Critical cmdlet module manifest leaf is untrusted for '$($entry[0])'."
      }
      $moduleItem = Microsoft.PowerShell.Management\Get-Item -LiteralPath $resolvedModulePath -Force -ErrorAction Stop
      $moduleLinkProperty = $moduleItem.PSObject.Properties['LinkType']
      $moduleLinkType = if ($null -ne $moduleLinkProperty) { [string]$moduleLinkProperty.Value } else { '' }
      if (-not $isDesktopEngine -and -not [string]::IsNullOrWhiteSpace($moduleLinkType)) {
        throw "PowerShell 7 critical module manifest hard links/symbolic links are forbidden: $resolvedModulePath"
      }
      $moduleSignature = Microsoft.PowerShell.Security\Get-AuthenticodeSignature `
        -LiteralPath $resolvedModulePath -ErrorAction Stop
      $moduleSigner = if ($null -ne $moduleSignature.SignerCertificate) {
        [string]$moduleSignature.SignerCertificate.Subject
      } else { '' }
      if ([string]$moduleSignature.Status -cne 'Valid' -or
          $moduleSigner -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {
        throw "Critical cmdlet module manifest must have a valid Microsoft signature: $resolvedModulePath"
      }
      $validatedPowerShellFiles[$resolvedModulePath] = $true
    }
  }

  $currentHostPath = [System.IO.Path]::GetFullPath(
    [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
  $expectedHostPath = if ($isDesktopEngine) {
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine(
      [Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe'))
  } else {
    [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($psHomePath, 'pwsh.exe'))
  }
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals($currentHostPath, $expectedHostPath)) {
    throw "A fresh exact PowerShell host is required; expected '$expectedHostPath', actual '$currentHostPath'."
  }
  $currentHostPath = Assert-TrustedSessionEntryFilePath -Path $currentHostPath `
    -TrustedRoot $psHomePath -Label 'Exact PowerShell host'
  $hostItem = Microsoft.PowerShell.Management\Get-Item -LiteralPath $currentHostPath -Force -ErrorAction Stop
  $psHomeItem = Microsoft.PowerShell.Management\Get-Item -LiteralPath $psHomePath -Force -ErrorAction Stop
  if (($hostItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
      ($psHomeItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'The exact PowerShell host and PSHOME must not be reparse points.'
  }
  $hostSignature = Microsoft.PowerShell.Security\Get-AuthenticodeSignature `
    -LiteralPath $currentHostPath -ErrorAction Stop
  $hostSignerSubject = if ($null -ne $hostSignature.SignerCertificate) {
    [string]$hostSignature.SignerCertificate.Subject
  } else { '' }
  if ([string]$hostSignature.Status -cne 'Valid' -or
      $hostSignerSubject -notmatch '(?:^|,\s*)O=Microsoft Corporation(?:,|$)') {
    throw 'The exact PowerShell host must have a currently valid Microsoft Corporation Authenticode signature.'
  }
}

Assert-NoAmbientCriticalCommandShadowing

function Assert-FreshStudioAutomationTypeNamespace {
  param([Parameter(Mandatory = $true)][string[]]$TypeNames)
  foreach ($typeName in $TypeNames) {
    if ($null -ne ($typeName -as [type])) {
      throw "A preexisting '$typeName' type is forbidden; run this action in a fresh exact System32 Windows PowerShell 5.1 host."
    }
  }
}

Assert-FreshStudioAutomationTypeNamespace -TypeNames @('StudioPathSafe', 'StudioSessionSafe')

$engineVersion = [version]$PSVersionTable.PSVersion
$isWindowsPowerShell51 = $engineVersion.Major -eq 5 -and $engineVersion.Minor -eq 1
if (-not $isWindowsPowerShell51) {
  throw 'studio_session.ps1 requires the exact OS System32 Windows PowerShell 5.1 host.'
}

$script:ExpectedProcessName = 'RobloxStudioBeta'
$script:ExpectedExecutableLeaf = 'RobloxStudioBeta.exe'
  $script:ManifestSchemaVersion = 7
  $script:PendingActionJournalSchemaVersion = 1
  $script:ExternalActionCompletionSchemaVersion = 1
  $script:ActivePendingActionJournal = $null
  $script:CompletedExternalAction = $null
  $script:PendingActionJournalStatus = $null
$script:EvidenceFreshnessMinutes = 10
$script:EvidenceFutureSkewMinutes = 2
$script:CoordinateEvidenceFreshnessMinutes = 5
$script:MaxCoordinateCaptureBytes = 37748736
$script:MaxCoordinateCaptureDimension = 8192
$script:MaxCoordinateCapturePixels = 9437184
$script:InputScript = [System.IO.Path]::Combine($PSScriptRoot, 'studio_input.ps1')
$script:CaptureScript = [System.IO.Path]::Combine($PSScriptRoot, 'studio_capture.ps1')

if ($env:OS -ne 'Windows_NT') {
  throw 'studio_session.ps1 requires an interactive Windows desktop.'
}

function Assert-EarlyLocalCompilerTemp {
  # Add-Type may invoke a compiler before the full trust-boundary initialization.
  # Validate its process TEMP/TMP without resolving a whole descendant through a link.
  $values = @(@(
    [Environment]::GetEnvironmentVariable('TEMP', 'Process'),
    [Environment]::GetEnvironmentVariable('TMP', 'Process')
  ) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Select-Object -Unique)
  if ($values.Count -eq 0) { $values = @([System.IO.Path]::GetTempPath()) }
  foreach ($value in $values) {
    $text = [string]$value
    if ($text.StartsWith('\\', [StringComparison]::Ordinal) -or $text -notmatch '^[A-Za-z]:[\\/]') {
      throw 'Process TEMP/TMP must use absolute local-drive syntax before Add-Type.'
    }
    $full = [System.IO.Path]::GetFullPath($text)
    $root = [System.IO.Path]::GetPathRoot($full)
    $drive = [System.IO.DriveInfo]::new($root)
    if ($drive.DriveType -ne [System.IO.DriveType]::Fixed) {
      throw "Process TEMP/TMP must be on a local Fixed drive; '$root' is $($drive.DriveType)."
    }
    if (-not $drive.IsReady) { throw "Process TEMP/TMP Fixed drive '$root' is not ready." }
    $cursor = $root
    $item = Get-Item -LiteralPath $root -Force -ErrorAction Stop
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "Process TEMP/TMP drive root must not be a reparse point: $root"
    }
    foreach ($segment in @($full.Substring($root.Length).Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries))) {
      $cursor = Join-Path $cursor $segment
      $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Process TEMP/TMP must not traverse a reparse point: $cursor"
      }
      $cursor = $item.FullName
    }
    if (-not $item.PSIsContainer) { throw "Process TEMP/TMP must be an existing directory: $full" }
  }
}

Assert-EarlyLocalCompilerTemp

function Assert-AbsoluteLiteralPath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Label,
    [switch]$MustExist,
    [switch]$Leaf,
    [switch]$AllowAlias
  )

  # Reject UNC/device syntax before any filesystem probe. Every security boundary in this
  # script is intentionally limited to a directly attached local fixed drive.
  if ($Path.StartsWith('\\', [StringComparison]::Ordinal) -or
      $Path -notmatch '^[A-Za-z]:[\\/]') {
    throw "$Label must be an absolute local drive path; UNC, device, mapped-provider, and relative paths are forbidden."
  }
  if ([System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Path)) {
    throw "$Label must be literal; wildcard characters are forbidden."
  }
  $inputComparison = $Path.Replace('/', '\')
  if ($inputComparison.Length -gt 3) { $inputComparison = $inputComparison.TrimEnd('\') }
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $fullComparison = $fullPath
  if ($fullComparison.Length -gt 3) { $fullComparison = $fullComparison.TrimEnd('\') }
  if (-not $AllowAlias -and
      -not [StringComparer]::OrdinalIgnoreCase.Equals($inputComparison, $fullComparison)) {
    throw "$Label must already use its normalized long path; short-name, dot-segment, and alternate-separator aliases are forbidden."
  }
  if ($fullPath.Substring(2).Contains(':')) {
    throw "$Label must not use an alternate data stream."
  }
  $driveRoot = [System.IO.Path]::GetPathRoot($fullPath)
  try {
    $drive = [System.IO.DriveInfo]::new($driveRoot)
    $driveType = $drive.DriveType
    if ($driveType -ne [System.IO.DriveType]::Fixed) {
      throw "$Label must reside on a ready local Fixed drive; '$driveRoot' is $($drive.DriveType)."
    }
    if (-not $drive.IsReady) {
      throw "$Label local Fixed drive '$driveRoot' is not ready."
    }
  } catch {
    throw "$Label drive validation failed for '$driveRoot': $($_.Exception.Message)"
  }
  # Walk from the local drive root one component at a time. Inspect a reparse point
  # itself before ever probing a descendant, so a junction to UNC cannot cause SMB I/O.
  $relative = $fullPath.Substring($driveRoot.Length)
  $segments = @($relative.Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries))
  $currentPath = $driveRoot
  $finalItem = Get-Item -LiteralPath $driveRoot -Force -ErrorAction Stop
  for ($segmentIndex = 0; $segmentIndex -lt $segments.Count; $segmentIndex++) {
    $candidatePath = Join-Path $currentPath $segments[$segmentIndex]
    try {
      $candidateItem = Get-Item -LiteralPath $candidatePath -Force -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
      if ($MustExist -or $segmentIndex -lt ($segments.Count - 1)) {
        throw "$Label does not exist or has a missing parent: $candidatePath"
      }
      $finalItem = $null
      break
    }
    if (($candidateItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "$Label path crosses a reparse point: $($candidateItem.FullName)"
    }
    if ($segmentIndex -lt ($segments.Count - 1) -and -not $candidateItem.PSIsContainer) {
      throw "$Label path component is not a directory: $($candidateItem.FullName)"
    }
    $currentPath = $candidateItem.FullName
    $finalItem = $candidateItem
  }
  if ($MustExist -and $null -eq $finalItem) { throw "$Label does not exist: $fullPath" }
  if ($Leaf -and $null -ne $finalItem -and $finalItem.PSIsContainer) {
    throw "$Label must be an existing file: $fullPath"
  }
  if ($AllowAlias -and $null -ne $finalItem) {
    return [System.IO.Path]::GetFullPath($finalItem.FullName)
  }
  return $fullPath
}

Add-Type @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class StudioPathSafe {
  [StructLayout(LayoutKind.Sequential)]
  private struct BY_HANDLE_FILE_INFORMATION {
    public uint FileAttributes;
    public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
    public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
    public uint VolumeSerialNumber;
    public uint FileSizeHigh;
    public uint FileSizeLow;
    public uint NumberOfLinks;
    public uint FileIndexHigh;
    public uint FileIndexLow;
  }

  private const uint FILE_READ_ATTRIBUTES = 0x0080;
  private const uint FILE_SHARE_READ = 0x00000001;
  private const uint FILE_SHARE_WRITE = 0x00000002;
  private const uint FILE_SHARE_DELETE = 0x00000004;
  private const uint OPEN_EXISTING = 3;
  private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
  private const uint FILE_NAME_NORMALIZED = 0x0;
  private const uint VOLUME_NAME_DOS = 0x0;

  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  private static extern SafeFileHandle CreateFileW(
    string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
    uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  private static extern uint GetFinalPathNameByHandleW(
    SafeFileHandle file, StringBuilder path, uint pathLength, uint flags);

  [DllImport("kernel32.dll", SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  private static extern bool GetFileInformationByHandle(
    SafeFileHandle file, out BY_HANDLE_FILE_INFORMATION information);

  public static string FinalPathOf(string path, bool directory) {
    uint flags = directory ? FILE_FLAG_BACKUP_SEMANTICS : 0;
    using (SafeFileHandle handle = CreateFileW(
      path, FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      IntPtr.Zero, OPEN_EXISTING, flags, IntPtr.Zero)) {
      if (handle.IsInvalid) {
        throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateFileW failed for canonical path validation");
      }
      var buffer = new StringBuilder(512);
      uint length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
      if (length == 0) {
        throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFinalPathNameByHandleW failed");
      }
      if (length >= buffer.Capacity) {
        buffer = new StringBuilder(checked((int)length + 1));
        length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, FILE_NAME_NORMALIZED | VOLUME_NAME_DOS);
        if (length == 0 || length >= buffer.Capacity) {
          throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFinalPathNameByHandleW failed after resizing");
        }
      }
      string finalPath = buffer.ToString();
      if (finalPath.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase)) {
        return @"\\" + finalPath.Substring(8);
      }
      if (finalPath.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase)) {
        return finalPath.Substring(4);
      }
      return finalPath;
    }
  }

  public static uint HardLinkCount(string path) {
    using (SafeFileHandle handle = CreateFileW(
      path, FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero)) {
      if (handle.IsInvalid) {
        throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateFileW failed for hard-link validation");
      }
      BY_HANDLE_FILE_INFORMATION information;
      if (!GetFileInformationByHandle(handle, out information)) {
        throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFileInformationByHandle failed");
      }
      return information.NumberOfLinks;
    }
  }

  public static string FileIdentityOfHandle(SafeFileHandle handle) {
    if (handle == null || handle.IsInvalid) {
      throw new ArgumentException("A valid file handle is required", "handle");
    }
    BY_HANDLE_FILE_INFORMATION information;
    if (!GetFileInformationByHandle(handle, out information)) {
      throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFileInformationByHandle failed for file identity");
    }
    return String.Format(
      System.Globalization.CultureInfo.InvariantCulture,
      "{0:X8}:{1:X8}:{2:X8}:{3}",
      information.VolumeSerialNumber,
      information.FileIndexHigh,
      information.FileIndexLow,
      information.NumberOfLinks);
  }

  public static string FileIdentity(string path) {
    using (SafeFileHandle handle = CreateFileW(
      path, FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
      IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero)) {
      if (handle.IsInvalid) {
        throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateFileW failed for file identity");
      }
      return FileIdentityOfHandle(handle);
    }
  }
}
'@

function Get-NormalizedPathForComparison {
  param([Parameter(Mandatory = $true)][string]$Path)

  $normalized = [System.IO.Path]::GetFullPath($Path)
  $root = [System.IO.Path]::GetPathRoot($normalized)
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals($normalized, $root)) {
    $normalized = $normalized.TrimEnd([char[]]@('\', '/'))
  }
  return $normalized
}

function Get-CanonicalExistingPath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Label,
    [switch]$Leaf,
    [switch]$AllowAlias
  )

  $lexical = Assert-AbsoluteLiteralPath -Path $Path -Label $Label -MustExist `
    -Leaf:$Leaf -AllowAlias:$AllowAlias
  $currentItem = Get-Item -LiteralPath $lexical -Force -ErrorAction Stop
  if (($currentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "$Label became a reparse point after validation: $lexical"
  }
  $isDirectory = [bool]$currentItem.PSIsContainer
  $physical = Get-NormalizedPathForComparison -Path ([StudioPathSafe]::FinalPathOf($lexical, $isDirectory))
  $lexicalNormalized = Get-NormalizedPathForComparison -Path $lexical
  if (-not $AllowAlias -and
      -not [StringComparer]::OrdinalIgnoreCase.Equals($lexicalNormalized, $physical)) {
    throw "$Label must use its canonical physical path; aliases are forbidden. Canonical path: $physical"
  }
  if (-not $isDirectory) {
    $linkCount = [StudioPathSafe]::HardLinkCount($physical)
    if ($linkCount -ne 1) {
      throw "$Label must have exactly one NTFS directory entry; hard-linked files are forbidden (links=$linkCount)."
    }
  }
  return $physical
}

function Get-CanonicalProspectiveFilePath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Label
  )

  $lexical = Assert-AbsoluteLiteralPath -Path $Path -Label $Label -Leaf
  try { $existingItem = Get-Item -LiteralPath $lexical -Force -ErrorAction Stop }
  catch [System.Management.Automation.ItemNotFoundException] { $existingItem = $null }
  if ($null -ne $existingItem) { return Get-CanonicalExistingPath -Path $lexical -Label $Label -Leaf }
  $parent = Split-Path -Parent $lexical
  $canonicalParent = Get-CanonicalExistingPath -Path $parent -Label "$Label parent"
  $canonical = Get-NormalizedPathForComparison -Path (Join-Path $canonicalParent ([System.IO.Path]::GetFileName($lexical)))
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
      (Get-NormalizedPathForComparison -Path $lexical), $canonical)) {
    throw "$Label must use a canonical physical parent path; aliases are forbidden. Canonical path: $canonical"
  }
  return $canonical
}

function Get-Sha256HexOfFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Label
  )

  $stream = $null
  $hasher = $null
  try {
    $stream = [System.IO.File]::Open(
      $Path,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::Read)
    $initialLength = [int64]$stream.Length
    $hasher = [Security.Cryptography.SHA256]::Create()
    $hashBytes = $hasher.ComputeHash($stream)
    if ($stream.Length -ne $initialLength) { throw "$Label length changed while hashing." }
    return [BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()
  } finally {
    if ($null -ne $hasher) { $hasher.Dispose() }
    if ($null -ne $stream) { $stream.Dispose() }
  }
}

function Get-Sha256HexOfUtf8String {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

  $hasher = [Security.Cryptography.SHA256]::Create()
  try {
    $bytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes($Value)
    return [BitConverter]::ToString($hasher.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
  } finally {
    $hasher.Dispose()
  }
}

function Test-PathWithinRoot {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Root,
    [switch]$AllowEqual
  )

  $candidate = Get-NormalizedPathForComparison -Path $Path
  $boundary = Get-NormalizedPathForComparison -Path $Root
  if ($AllowEqual -and [StringComparer]::OrdinalIgnoreCase.Equals($candidate, $boundary)) {
    return $true
  }
  $prefix = if ($boundary.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
    $boundary
  } else {
    $boundary + [System.IO.Path]::DirectorySeparatorChar
  }
  return $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Test-PathsOverlap {
  param(
    [Parameter(Mandatory = $true)][string]$First,
    [Parameter(Mandatory = $true)][string]$Second
  )

  return (Test-PathWithinRoot -Path $First -Root $Second -AllowEqual) -or
    (Test-PathWithinRoot -Path $Second -Root $First -AllowEqual)
}

function Read-BoundedStrictUtf8TextFile {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Label,
    [ValidateRange(1, 65536)][int]$MaximumBytes = 4096
  )

  $canonical = Get-CanonicalExistingPath -Path $Path -Label $Label -Leaf
  $bytes = [System.IO.File]::ReadAllBytes($canonical)
  if ($bytes.Length -le 0 -or $bytes.Length -gt $MaximumBytes) {
    throw "$Label must be between 1 byte and $MaximumBytes bytes."
  }
  try {
    return [Text.UTF8Encoding]::new($false, $true).GetString($bytes).Trim()
  } catch {
    throw "$Label must be strict UTF-8."
  }
}

function Get-ValidatedGitRoot {
  param([Parameter(Mandatory = $true)][string]$Path)

  $canonical = Get-CanonicalExistingPath -Path $Path -Label 'RepositoryRoot'
  if (-not (Test-Path -LiteralPath $canonical -PathType Container)) {
    throw 'RepositoryRoot must be an existing directory.'
  }
  # Do not execute PATH-resolved git here: command lookup and a hung helper would weaken the
  # boundary. An exact root is identified by its direct .git marker. Worktree gitdir files are
  # parsed as data and their target is required to be a canonical local directory.
  $administrationRoots = [System.Collections.Generic.List[string]]::new()
  $marker = Join-Path $canonical '.git'
  try { $markerItem = Get-Item -LiteralPath $marker -Force -ErrorAction Stop }
  catch [System.Management.Automation.ItemNotFoundException] { $markerItem = $null }
  if ($null -ne $markerItem -and
      ($markerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'RepositoryRoot .git marker must not be a reparse point.'
  }
  if ($null -ne $markerItem -and $markerItem.PSIsContainer) {
    $gitDirectory = Get-CanonicalExistingPath -Path $marker -Label 'RepositoryRoot .git directory'
    $administrationRoots.Add($gitDirectory)
  } elseif ($null -ne $markerItem -and -not $markerItem.PSIsContainer) {
    $markerText = Read-BoundedStrictUtf8TextFile -Path $marker -Label 'RepositoryRoot .git file'
    if ($markerText -notmatch '^gitdir:\s*(.+)$') {
      throw 'RepositoryRoot .git file must contain one gitdir directive.'
    }
    $gitDirectoryText = [string]$Matches[1]
    if ($gitDirectoryText -match '[\x00-\x1F\x7F]' -or
        [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($gitDirectoryText)) {
      throw 'RepositoryRoot .git gitdir value contains forbidden characters.'
    }
    $gitDirectoryPath = if ([System.IO.Path]::IsPathRooted($gitDirectoryText)) {
      $gitDirectoryText
    } else {
      Join-Path $canonical $gitDirectoryText
    }
    $gitDirectory = Get-CanonicalExistingPath -Path $gitDirectoryPath -Label 'RepositoryRoot gitdir target'
    if (-not (Test-Path -LiteralPath $gitDirectory -PathType Container)) {
      throw 'RepositoryRoot gitdir target must be an existing directory.'
    }
    $administrationRoots.Add($gitDirectory)
  } else {
    throw 'RepositoryRoot must be the exact Git worktree root containing a direct .git marker.'
  }

  $commonDirMarker = Join-Path $gitDirectory 'commondir'
  try { $commonDirMarkerItem = Get-Item -LiteralPath $commonDirMarker -Force -ErrorAction Stop }
  catch [System.Management.Automation.ItemNotFoundException] { $commonDirMarkerItem = $null }
  if ($null -ne $commonDirMarkerItem -and
      ($commonDirMarkerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'RepositoryRoot Git commondir marker must not be a reparse point.'
  }
  if ($null -ne $commonDirMarkerItem -and -not $commonDirMarkerItem.PSIsContainer) {
    $commonDirText = Read-BoundedStrictUtf8TextFile -Path $commonDirMarker `
      -Label 'RepositoryRoot Git commondir file'
    if ([string]::IsNullOrWhiteSpace($commonDirText) -or
        $commonDirText -match '[\x00-\x1F\x7F]' -or
        [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($commonDirText)) {
      throw 'RepositoryRoot Git commondir contains a forbidden path.'
    }
    $commonDirPath = if ([System.IO.Path]::IsPathRooted($commonDirText)) {
      $commonDirText
    } else {
      Join-Path $gitDirectory $commonDirText
    }
    $commonDir = Get-CanonicalExistingPath -Path $commonDirPath -Label 'RepositoryRoot Git common directory'
    if (-not (Test-Path -LiteralPath $commonDir -PathType Container)) {
      throw 'RepositoryRoot Git common directory must be an existing directory.'
    }
    if (-not $administrationRoots.Contains($commonDir)) { $administrationRoots.Add($commonDir) }
  }

  return [pscustomobject][ordered]@{
    worktreeRoot = $canonical
    administrationRoots = $administrationRoots.ToArray()
  }
}

function Get-KnownTempPhysicalPaths {
  $candidates = [System.Collections.Generic.List[string]]::new()
  foreach ($candidate in @(
    [System.IO.Path]::GetTempPath(),
    [Environment]::GetEnvironmentVariable('TEMP', 'Process'),
    [Environment]::GetEnvironmentVariable('TMP', 'Process'),
    [Environment]::GetEnvironmentVariable('TEMP', 'User'),
    [Environment]::GetEnvironmentVariable('TMP', 'User'),
    [Environment]::GetEnvironmentVariable('TEMP', 'Machine'),
    [Environment]::GetEnvironmentVariable('TMP', 'Machine'),
    $(if (-not [string]::IsNullOrWhiteSpace($env:SystemRoot)) {
      ([string]$env:SystemRoot).TrimEnd([char[]]@('\', '/')) + '\Temp'
    })
  )) {
    if ([string]::IsNullOrWhiteSpace([string]$candidate)) { continue }
    try {
      # Validate syntax and local Fixed-drive placement before Test-Path or a handle open;
      # hostile TEMP environment values must never trigger an SMB/provider probe.
      $candidateText = [string]$candidate
      if ($candidateText.StartsWith('\\', [StringComparison]::Ordinal) -or
          $candidateText -notmatch '^[A-Za-z]:[\\/]' -or
          [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($candidateText)) {
        throw 'Known TEMP root must use local-drive literal syntax.'
      }
      # Reuse the component-by-component lstat walk. A non-existing or reparse TEMP
      # root is not silently ignored because its physical overlap cannot be proven.
      $physical = Get-CanonicalExistingPath -Path $candidateText -Label 'Known TEMP root' -AllowAlias
      $physicalItem = Get-Item -LiteralPath $physical -Force -ErrorAction Stop
      if (-not $physicalItem.PSIsContainer) { throw "Known TEMP root is not a directory: $physical" }
      if (-not $candidates.Contains($physical)) { $candidates.Add($physical) }
    } catch {
      throw "Cannot resolve a known TEMP root safely ('$candidate'): $($_.Exception.Message)"
    }
  }
  return $candidates.ToArray()
}

function Get-ApprovedStudioVersionsRoots {
  $roots = [System.Collections.Generic.List[string]]::new()
  foreach ($base in @(
    [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData),
    [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFilesX86),
    [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
  )) {
    if ([string]::IsNullOrWhiteSpace([string]$base)) { continue }
    if ([string]$base -notmatch '^[A-Za-z]:[\\/]') { continue }
    try {
      $safeBase = Assert-AbsoluteLiteralPath -Path ([string]$base) `
        -Label 'Roblox inventory known-folder base'
    } catch {
      continue
    }
    $candidate = Join-Path $safeBase 'Roblox\Versions'
    try {
      # Never probe the full descendant before verifying every local ancestor.
      $canonical = Get-CanonicalExistingPath -Path $candidate -Label 'Approved Roblox Versions root'
    } catch {
      continue
    }
    $canonicalItem = Get-Item -LiteralPath $canonical -Force -ErrorAction Stop
    if (-not $canonicalItem.PSIsContainer) { continue }
    if (-not $roots.Contains($canonical)) { $roots.Add($canonical) }
  }
  return $roots.ToArray()
}

function Assert-StudioExecutableInventoryPath {
  param([Parameter(Mandatory = $true)][string]$CanonicalPath)

  if ([System.IO.Path]::GetFileName($CanonicalPath) -cne $script:ExpectedExecutableLeaf) {
    throw "StudioExecutablePath must name the exact executable '$script:ExpectedExecutableLeaf'."
  }
  $versionDirectory = Split-Path -Parent $CanonicalPath
  $versionLeaf = Split-Path -Leaf $versionDirectory
  if ($versionLeaf -cnotmatch '^version-[A-Za-z0-9._-]{1,128}$') {
    throw 'StudioExecutablePath must be the direct RobloxStudioBeta.exe child of a version-* inventory directory.'
  }
  $versionsRoot = Get-NormalizedPathForComparison -Path (Split-Path -Parent $versionDirectory)
  $approvedRoots = @(Get-ApprovedStudioVersionsRoots)
  if ($approvedRoots.Count -eq 0 -or
      @($approvedRoots | Where-Object {
        [StringComparer]::OrdinalIgnoreCase.Equals($_, $versionsRoot)
      }).Count -ne 1) {
    throw "StudioExecutablePath is outside the approved LocalAppData/Program Files Roblox Versions inventory: $CanonicalPath"
  }
}

function Invoke-BoundedStudioAttestationWorker {
  param(
    [Parameter(Mandatory = $true)][string]$CanonicalPath,
    [ValidateRange(1, 60)][int]$TimeoutSeconds = 15
  )

  $currentHostPath = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
  $hostLeaf = [System.IO.Path]::GetFileName($currentHostPath)
  if ($hostLeaf -cne 'powershell.exe') {
    throw "Cannot run the bounded signature worker from unsupported host '$hostLeaf'."
  }
  $pathPayload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($CanonicalPath))
  $workerSource = @"
`$null = Microsoft.PowerShell.Core\Set-StrictMode -Version 2.0
`$ErrorActionPreference = 'Stop'
try {
  `$expectedCommands = @(
    @('Get-AuthenticodeSignature', 'Microsoft.PowerShell.Security'),
    @('Get-Location', 'Microsoft.PowerShell.Management'),
    @('ConvertTo-Json', 'Microsoft.PowerShell.Utility')
  )
  foreach (`$entry in `$expectedCommands) {
    `$resolved = @(Microsoft.PowerShell.Core\Get-Command -Name `$entry[0] -All -ErrorAction Stop)
    if (`$resolved.Count -eq 0 -or
        `$resolved[0].CommandType -ne [System.Management.Automation.CommandTypes]::Cmdlet -or
        [string]`$resolved[0].ModuleName -cne [string]`$entry[1]) {
      throw "Signature worker command provenance failed for '`$(`$entry[0])'."
    }
  }
  `$path = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$pathPayload'))
  `$signature = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath `$path
  `$certificate = `$signature.SignerCertificate
  `$hashStream = `$null
  `$hashAlgorithm = `$null
  try {
    `$hashStream = [IO.File]::Open(`$path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    `$hashLength = [int64]`$hashStream.Length
    `$hashAlgorithm = [Security.Cryptography.SHA256]::Create()
    `$hashBytes = `$hashAlgorithm.ComputeHash(`$hashStream)
    if (`$hashStream.Length -ne `$hashLength) { throw 'Studio executable length changed during worker hashing.' }
    `$hash = [BitConverter]::ToString(`$hashBytes).Replace('-', '').ToLowerInvariant()
  } finally {
    if (`$null -ne `$hashAlgorithm) { `$hashAlgorithm.Dispose() }
    if (`$null -ne `$hashStream) { `$hashStream.Dispose() }
  }
  `$version = [Diagnostics.FileVersionInfo]::GetVersionInfo(`$path).ProductVersion
  [pscustomobject][ordered]@{
    ok = `$true
    status = [string]`$signature.Status
    subject = if (`$null -eq `$certificate) { `$null } else { [string]`$certificate.Subject }
    thumbprint = if (`$null -eq `$certificate) { `$null } else { [string]`$certificate.Thumbprint }
    sha256 = `$hash
    productVersion = [string]`$version
    workingDirectory = (Microsoft.PowerShell.Management\Get-Location).Path
  } | Microsoft.PowerShell.Utility\ConvertTo-Json -Compress
} catch {
  [pscustomobject][ordered]@{
    ok = `$false
    status = 'Error'
    subject = `$null
    thumbprint = `$null
    sha256 = `$null
    productVersion = `$null
    workingDirectory = (Microsoft.PowerShell.Management\Get-Location).Path
    error = `$_.Exception.Message
  } | Microsoft.PowerShell.Utility\ConvertTo-Json -Compress
}
"@
  $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($workerSource))
  $startInfo = [Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $currentHostPath
  $startInfo.WorkingDirectory = Split-Path -Parent $currentHostPath
  $startInfo.Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encodedCommand"
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $systemModulePath = Get-CanonicalExistingPath -Path (Join-Path $PSHOME 'Modules') `
    -Label 'PowerShell system module directory'
  $systemModulePathItem = Get-Item -LiteralPath $systemModulePath -Force -ErrorAction Stop
  if (-not $systemModulePathItem.PSIsContainer -or
      ($systemModulePathItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'PowerShell system module directory must be an existing non-reparse directory.'
  }
  $startInfo.EnvironmentVariables['PSModulePath'] = $systemModulePathItem.FullName
  $process = [Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  $stdoutTask = $null
  $stderrTask = $null
  $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
  try {
    if (-not $process.Start()) { throw 'Failed to start hidden Studio signature worker.' }
    $workerPid = [int]$process.Id
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $remainingMs = [Math]::Max(1, [int][Math]::Ceiling(($deadline - [datetime]::UtcNow).TotalMilliseconds))
    if (-not $process.WaitForExit($remainingMs)) {
      if (-not $process.HasExited) { $process.Kill() }
      $null = $process.WaitForExit(5000)
      throw "Studio executable attestation timed out after $TimeoutSeconds seconds; only hidden worker PID $workerPid was terminated."
    }
    $remainingMs = [Math]::Max(1, [int][Math]::Ceiling(($deadline - [datetime]::UtcNow).TotalMilliseconds))
    $tasks = [Threading.Tasks.Task[]]@($stdoutTask, $stderrTask)
    if (-not [Threading.Tasks.Task]::WaitAll($tasks, $remainingMs)) {
      $process.StandardOutput.Dispose()
      $process.StandardError.Dispose()
      throw "Studio executable attestation streams did not close within the $TimeoutSeconds-second common deadline."
    }
    if ($stdoutTask.IsFaulted -or $stdoutTask.IsCanceled -or
        $stderrTask.IsFaulted -or $stderrTask.IsCanceled) {
      throw 'Studio executable attestation stream reader failed.'
    }
    $stdout = $stdoutTask.Result.Trim()
    $stderr = $stderrTask.Result.Trim()
    if ($stdout.Length -gt 16384 -or $stderr.Length -gt 16384) {
      throw 'Studio executable attestation worker output exceeded 16 KiB.'
    }
    if ($process.ExitCode -ne 0) {
      throw "Studio executable attestation worker failed (exit=$($process.ExitCode)): $stderr $stdout"
    }
    return $stdout
  } finally {
    if ($null -ne $process) {
      try {
        if (-not $process.HasExited) {
          $process.Kill()
          $null = $process.WaitForExit(5000)
        }
      } catch { }
      $process.Dispose()
    }
  }
}

function Get-StudioExecutableAttestation {
  param([Parameter(Mandatory = $true)][string]$CanonicalPath)

  Assert-StudioExecutableInventoryPath -CanonicalPath $CanonicalPath
  $json = Invoke-BoundedStudioAttestationWorker -CanonicalPath $CanonicalPath
  try { $attestation = Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $json } catch {
    throw "Studio executable attestation worker returned invalid JSON: $($_.Exception.Message)"
  }
  foreach ($name in @('ok', 'status', 'subject', 'thumbprint', 'sha256', 'productVersion', 'workingDirectory')) {
    if ($attestation.PSObject.Properties.Name -notcontains $name) {
      throw "Studio executable attestation is missing '$name'."
    }
  }
  if ($attestation.ok -isnot [bool] -or -not [bool]$attestation.ok -or
      [string]$attestation.status -cne 'Valid') {
    throw "Studio executable Authenticode status must be Valid; got '$($attestation.status)'."
  }
  $expectedWorkerDirectory = Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
      [string]$attestation.workingDirectory, $expectedWorkerDirectory)) {
    throw 'Studio executable attestation worker did not run from the fixed PowerShell host directory.'
  }
  $subject = [string]$attestation.subject
  if ($subject.Length -gt 2048 -or
      $subject -notmatch '(?i)(^|,\s*)CN=Roblox Corporation(,|$)' -or
      $subject -notmatch '(?i)(^|,\s*)O=Roblox Corporation(,|$)') {
    throw "Studio executable signer subject must contain exact CN and O attributes for Roblox Corporation; got '$subject'."
  }
  $thumbprint = ([string]$attestation.thumbprint).Replace(' ', '').ToUpperInvariant()
  if ($thumbprint -cnotmatch '^[0-9A-F]{40,128}$') {
    throw 'Studio executable signer thumbprint is invalid.'
  }
  $hash = ([string]$attestation.sha256).ToLowerInvariant()
  if ($hash -cnotmatch '^[0-9a-f]{64}$') {
    throw 'Studio executable SHA-256 is invalid.'
  }
  $productVersion = [string]$attestation.productVersion
  if ([string]::IsNullOrWhiteSpace($productVersion) -or $productVersion.Length -gt 256 -or
      $productVersion -match '[\x00-\x1F\x7F]') {
    throw 'Studio executable ProductVersion is missing or invalid.'
  }
  return [pscustomobject][ordered]@{
    sha256 = $hash
    signerSubject = $subject
    signerThumbprint = $thumbprint
    productVersion = $productVersion
  }
}

function Assert-StudioAttestationMatchesManifest {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)]$Attestation
  )

  if ([string]$Attestation.sha256 -cne [string]$Manifest.executableSha256 -or
      [string]$Attestation.signerSubject -cne [string]$Manifest.executableSignerSubject -or
      [string]$Attestation.signerThumbprint -cne [string]$Manifest.executableSignerThumbprint -or
      [string]$Attestation.productVersion -cne [string]$Manifest.executableProductVersion) {
    throw 'Studio executable attestation no longer matches the manifest inventory record.'
  }
}

function Get-TrustedScriptSnapshot {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Label,
    [switch]$IncludeText
  )

  $canonical = Get-CanonicalExistingPath -Path $Path -Label $Label -Leaf
  if ([System.IO.Path]::GetExtension($canonical) -cne '.ps1') {
    throw "$Label must be a .ps1 file."
  }
  $stream = $null
  $sha256 = $null
  try {
    $stream = [System.IO.File]::Open(
      $canonical,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::Read)
    $length = [int64]$stream.Length
    if ($length -le 0 -or $length -gt 4194304) {
      throw "$Label must be between 1 byte and 4 MiB."
    }
    $identity = [StudioPathSafe]::FileIdentityOfHandle($stream.SafeFileHandle)
    if ($identity -cnotmatch '^[0-9A-F]{8}:[0-9A-F]{8}:[0-9A-F]{8}:1$') {
      throw "$Label must have one stable NTFS identity and exactly one hard link; got '$identity'."
    }
    $bytes = [byte[]]::new([int]$length)
    $offset = 0
    while ($offset -lt $bytes.Length) {
      $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
      if ($read -le 0) { throw "$Label ended before its recorded length." }
      $offset += $read
    }
    if ($stream.Length -ne $length) { throw "$Label length changed while it was being attested." }
    $sha256 = [Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)
    $hash = [BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()
    $text = $null
    if ($IncludeText) {
      $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
      if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    }
    return [pscustomobject][ordered]@{
      path = $canonical
      sha256 = $hash
      fileIdentity = $identity
      length = $length
      text = $text
    }
  } finally {
    if ($null -ne $sha256) { $sha256.Dispose() }
    if ($null -ne $stream) { $stream.Dispose() }
  }
}

function Assert-RootDisjointFromBoundaries {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][string[]]$Boundaries
  )

  foreach ($boundary in $Boundaries) {
    if (Test-PathsOverlap -First $Root -Second $boundary) {
      throw "$Label must be physically disjoint from protected/writeable boundary: $boundary"
    }
  }
}

$repositoryBoundary = Get-ValidatedGitRoot -Path $RepositoryRoot
$script:RepositoryRootPath = [string]$repositoryBoundary.worktreeRoot
$script:RepositoryAdministrationRoots = @($repositoryBoundary.administrationRoots)
$script:TrustedEvidenceRootPath = Get-CanonicalExistingPath -Path $TrustedEvidenceRoot -Label 'TrustedEvidenceRoot'
if (-not (Test-Path -LiteralPath $script:TrustedEvidenceRootPath -PathType Container)) {
  throw 'TrustedEvidenceRoot must be an existing directory.'
}
if (Test-PathsOverlap -First $script:TrustedEvidenceRootPath -Second $script:RepositoryRootPath) {
  throw 'TrustedEvidenceRoot and RepositoryRoot must be physically disjoint.'
}
foreach ($administrationRoot in $script:RepositoryAdministrationRoots) {
  if (Test-PathsOverlap -First $script:TrustedEvidenceRootPath -Second $administrationRoot) {
    throw "TrustedEvidenceRoot must be physically disjoint from Git administration root: $administrationRoot"
  }
}
$script:KnownTempRoots = @(Get-KnownTempPhysicalPaths)
foreach ($tempRoot in $script:KnownTempRoots) {
  if (Test-PathsOverlap -First $script:TrustedEvidenceRootPath -Second $tempRoot) {
    throw "TrustedEvidenceRoot must be physically disjoint from every known TEMP root: $tempRoot"
  }
}

$script:ScriptsRootPath = Get-CanonicalExistingPath -Path $PSScriptRoot -Label 'Skill scripts root'
$script:SessionScriptAttestation = Get-TrustedScriptSnapshot -Path $PSCommandPath -Label 'studio_session.ps1'
$script:InputScriptAttestation = Get-TrustedScriptSnapshot -Path $script:InputScript -Label 'studio_input.ps1'
$script:CaptureScriptAttestation = Get-TrustedScriptSnapshot -Path $script:CaptureScript -Label 'studio_capture.ps1'
$script:InputScript = [string]$script:InputScriptAttestation.path
$script:CaptureScript = [string]$script:CaptureScriptAttestation.path
foreach ($scriptAttestation in @(
    $script:SessionScriptAttestation,
    $script:InputScriptAttestation,
    $script:CaptureScriptAttestation
  )) {
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
      (Split-Path -Parent ([string]$scriptAttestation.path)), $script:ScriptsRootPath)) {
    throw 'All trusted Studio automation scripts must be direct children of one canonical scripts root.'
  }
}
$script:ScriptWriteBoundaries = @(
  $script:RepositoryRootPath
  @($script:RepositoryAdministrationRoots)
  $script:TrustedEvidenceRootPath
  @($script:KnownTempRoots)
)
Assert-RootDisjointFromBoundaries -Root $script:ScriptsRootPath -Label 'Skill scripts root' -Boundaries $script:ScriptWriteBoundaries

$script:SessionFilePath = Get-CanonicalProspectiveFilePath -Path $SessionFile -Label 'SessionFile'
if ([System.IO.Path]::GetExtension($script:SessionFilePath) -ine '.json') {
  throw 'SessionFile must have the .json extension.'
}
if (-not (Test-PathWithinRoot -Path $script:SessionFilePath -Root $script:TrustedEvidenceRootPath)) {
  throw 'SessionFile must be a descendant of TrustedEvidenceRoot.'
}
$pendingActionJournalParent = Get-CanonicalExistingPath `
  -Path (Split-Path -Parent $script:SessionFilePath) `
  -Label 'Pending action journal parent'
$script:PendingActionJournalPath = Get-NormalizedPathForComparison -Path (
  Join-Path $pendingActionJournalParent (
    [System.IO.Path]::GetFileName($script:SessionFilePath) + '.pending-action.json'))
if (-not (Test-PathWithinRoot `
    -Path $script:PendingActionJournalPath -Root $script:TrustedEvidenceRootPath)) {
  throw 'Pending action journal must be adjacent to SessionFile inside TrustedEvidenceRoot.'
}
$script:ApprovedStudioExecutablePath = Get-CanonicalExistingPath -Path $StudioExecutablePath `
  -Label 'StudioExecutablePath' -Leaf
$script:ApprovedStudioExecutableAttestation = Get-StudioExecutableAttestation `
  -CanonicalPath $script:ApprovedStudioExecutablePath
$script:ApprovedStudioVersionDirectory = Get-CanonicalExistingPath -Path (Split-Path -Parent $script:ApprovedStudioExecutablePath) -Label 'Approved Studio version directory'
Assert-RootDisjointFromBoundaries -Root $script:ApprovedStudioVersionDirectory -Label 'Approved Studio version directory' -Boundaries (@($script:ScriptWriteBoundaries) + @($script:ScriptsRootPath))

Add-Type @'
using System;
using System.Text;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public static class StudioSessionSafe {
  public delegate bool EnumProc(IntPtr h, IntPtr p);

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [DllImport("user32.dll", SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool PostMessageW(IntPtr h, uint msg, IntPtr w, IntPtr l);

  [DllImport("user32.dll", SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool EnumWindows(EnumProc cb, IntPtr p);

  [DllImport("user32.dll", SetLastError = true)]
  public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);

  [DllImport("user32.dll", SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool IsWindowVisible(IntPtr h);

  [DllImport("user32.dll", SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool IsWindow(IntPtr h);

  [DllImport("user32.dll", SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool GetWindowRect(IntPtr h, out RECT rect);

  [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetWindowTextLengthW", SetLastError = true)]
  public static extern int GetWindowTextLength(IntPtr h);

  [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetWindowTextW", SetLastError = true)]
  public static extern int GetWindowText(IntPtr h, StringBuilder sb, int max);

  public static List<IntPtr> VisibleWindows(uint targetPid) {
    var found = new List<IntPtr>();
    if (!EnumWindows(delegate(IntPtr h, IntPtr p) {
      uint pid;
      GetWindowThreadProcessId(h, out pid);
      if (pid == targetPid && IsWindowVisible(h)) found.Add(h);
      return true;
    }, IntPtr.Zero)) {
      throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "EnumWindows failed");
    }
    return found;
  }

  public static string TitleOf(IntPtr h) {
    int length = GetWindowTextLength(h);
    var sb = new StringBuilder(Math.Max(length + 1, 2));
    GetWindowText(h, sb, sb.Capacity);
    return sb.ToString();
  }
}
'@

function Assert-CoordinateContracts {
  $startMenu = @($StartMenuX, $StartMenuY, $StartItemX, $StartItemY)
  $startMenuSpecified = @($startMenu | Where-Object { $_ -gt 0 }).Count
  if ($startMenuSpecified -ne 0 -and $startMenuSpecified -ne 4) {
    throw 'Start menu coordinates are all-or-none: specify all four of StartMenuX/StartMenuY/StartItemX/StartItemY, or leave all four at 0.'
  }

  if ($Action -eq 'Start') {
    $viewport = @($ViewportX, $ViewportY)
    $viewportSpecified = @($viewport | Where-Object { $_ -gt 0 }).Count
    if ($viewportSpecified -ne 0 -and $viewportSpecified -ne 2) {
      throw 'ViewportX and ViewportY are all-or-none. Leave both at 0 for target-window center click, or pass current-run positive coordinates for both.'
    }
  }

  if ($Action -eq 'AddClients') {
    $clientMenu = @($TestMenuX, $TestMenuY, $AddClientX, $AddClientY)
    if (@($clientMenu | Where-Object { $_ -le 0 }).Count -ne 0) {
      throw 'TestMenuX/TestMenuY/AddClientX/AddClientY must all be positive for AddClients.'
    }
  }
}

function Assert-ActionParameterContracts {
  if ($Action -notin @('Preflight', 'Open') -and -not [string]::IsNullOrWhiteSpace($PlacePath)) {
    throw 'PlacePath is valid only with -Action Preflight or Open.'
  }
  if ($Action -ne 'Start' -and $EditPid -ne 0) { throw 'EditPid is valid only with -Action Start.' }
  if ($Action -ne 'AddClients' -and $ServerPid -ne 0) { throw 'ServerPid is valid only with -Action AddClients.' }
  if ($Action -ne 'Cleanup' -and $KeepPid -ne 0) { throw 'KeepPid is valid only with -Action Cleanup.' }
  if ($Action -ne 'Confirm' -and
      ($ConfirmPid -ne 0 -or -not [string]::IsNullOrWhiteSpace($EvidenceFile) -or
       -not [string]::IsNullOrWhiteSpace($EvidenceSha256) -or $ConfirmPlace)) {
    throw 'ConfirmPid/EvidenceFile/EvidenceSha256/ConfirmPlace are valid only with -Action Confirm.'
  }
  if ($AllowOsInput -and $Action -notin @('Start', 'AddClients', 'Input')) {
    throw 'AllowOsInput is valid only with -Action Start, AddClients, or Input.'
  }
  if ($Force -and $Action -ne 'Cleanup') {
    throw 'Force is valid only with -Action Cleanup.'
  }
  if ($Action -notin @('Input', 'Capture') -and
      ($TargetPid -ne 0 -or -not [string]::IsNullOrWhiteSpace($InputActions))) {
    throw 'TargetPid is valid only with -Action Input or window Capture; InputActions is valid only with Input.'
  }
  if ($Action -eq 'Capture' -and -not [string]::IsNullOrWhiteSpace($InputActions)) {
    throw 'InputActions is valid only with -Action Input.'
  }
  $captureParameterNames = @(
    'OutFile', 'FullScreen', 'AllowFullScreenCapture', 'RequireForeground',
    'AllowMinimized', 'CaptureForce', 'PrintWindowTimeoutSeconds',
    'FullScreenTimeoutSeconds'
  )
  $captureParameterSpecified = @($captureParameterNames | Where-Object {
    $script:InvocationBoundParameters.ContainsKey($_)
  }).Count -gt 0
  if ($Action -ne 'Capture' -and $captureParameterSpecified) {
    throw 'Capture output/mode/consent/timeout parameters are valid only with -Action Capture.'
  }
  if ($Action -eq 'Capture') {
    if ([string]::IsNullOrWhiteSpace($OutFile)) { throw 'Capture requires -OutFile.' }
    if ($FullScreen) {
      if ($TargetPid -ne 0) { throw 'FullScreen Capture does not accept -TargetPid.' }
      if (-not $AllowFullScreenCapture) {
        throw 'FullScreen Capture requires explicit -AllowFullScreenCapture for this run, including DryRun.'
      }
      if ($script:InvocationBoundParameters.ContainsKey('RequireForeground') -or
          $script:InvocationBoundParameters.ContainsKey('AllowMinimized') -or
          $script:InvocationBoundParameters.ContainsKey('PrintWindowTimeoutSeconds')) {
        throw 'RequireForeground/AllowMinimized/PrintWindowTimeoutSeconds are valid only for window Capture.'
      }
    } else {
      if ($TargetPid -le 0) { throw 'Window Capture requires -TargetPid.' }
      if ($script:InvocationBoundParameters.ContainsKey('AllowFullScreenCapture') -or
          $script:InvocationBoundParameters.ContainsKey('FullScreenTimeoutSeconds')) {
        throw 'AllowFullScreenCapture/FullScreenTimeoutSeconds require -FullScreen.'
      }
    }
  }
  $coordinateEvidenceSpecified = -not [string]::IsNullOrWhiteSpace($CoordinateEvidenceFile) -or
    -not [string]::IsNullOrWhiteSpace($CoordinateEvidenceSha256)
  $coordinateEvidenceRequired = $Action -eq 'AddClients' -or
    ($Action -eq 'Start' -and ($ViewportX -gt 0 -or $StartMenuX -gt 0))
  if ($coordinateEvidenceRequired -and
      ([string]::IsNullOrWhiteSpace($CoordinateEvidenceFile) -or
       [string]::IsNullOrWhiteSpace($CoordinateEvidenceSha256))) {
    throw 'Current-run nonzero coordinates require both -CoordinateEvidenceFile and -CoordinateEvidenceSha256.'
  }
  if (-not $coordinateEvidenceRequired -and $coordinateEvidenceSpecified) {
    throw 'Coordinate evidence is accepted only for AddClients or Start with current-run nonzero coordinates.'
  }
  $startOnlyCoordinates = @($ViewportX, $ViewportY, $StartMenuX, $StartMenuY, $StartItemX, $StartItemY)
  if ($Action -ne 'Start' -and
      @($startOnlyCoordinates | Where-Object { $_ -ne 0 }).Count -ne 0) {
    throw 'Viewport and Start menu coordinates are valid only with -Action Start.'
  }
  $addClientOnlyCoordinates = @($TestMenuX, $TestMenuY, $AddClientX, $AddClientY)
  if ($Action -ne 'AddClients' -and
      @($addClientOnlyCoordinates | Where-Object { $_ -ne 0 }).Count -ne 0) {
    throw 'Test/AddClient coordinates are valid only with -Action AddClients.'
  }
}

function ConvertFrom-StrictEvidenceUtc {
  param(
    [Parameter(Mandatory = $true)][string]$Value,
    [Parameter(Mandatory = $true)][string]$Label
  )

  if ($Value -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$') {
    throw "$Label must use strict UTC round-trip format yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'."
  }
  $parsed = [datetime]::MinValue
  $style = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
  if (-not [datetime]::TryParseExact(
      $Value,
      "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",
      [Globalization.CultureInfo]::InvariantCulture,
      $style,
      [ref]$parsed
    )) {
    throw "$Label is not a valid strict UTC timestamp."
  }
  return $parsed
}

function Assert-EvidenceFreshness {
  param(
    [Parameter(Mandatory = $true)][datetime]$ObservedAtUtc,
    [Parameter(Mandatory = $true)][datetime]$AcquiredAtUtc,
    [Parameter(Mandatory = $true)][datetime]$NowUtc
  )

  if ($ObservedAtUtc -lt $AcquiredAtUtc) {
    throw 'Evidence observedAtUtc predates candidate acquisition.'
  }
  if ($ObservedAtUtc -gt $NowUtc.AddMinutes($script:EvidenceFutureSkewMinutes)) {
    throw "Evidence observedAtUtc is more than $script:EvidenceFutureSkewMinutes minutes in the future."
  }
  if ($ObservedAtUtc -lt $NowUtc.AddMinutes(-$script:EvidenceFreshnessMinutes)) {
    throw "Evidence expired; observedAtUtc must be within the last $script:EvidenceFreshnessMinutes minutes. Refresh it with a new independent event/probe."
  }
}

function Assert-StoredEvidenceMetadata {
  param(
    [Parameter(Mandatory = $true)][string]$ObservedAtUtc,
    [Parameter(Mandatory = $true)][string]$EventId,
    [Parameter(Mandatory = $true)][string]$ProbeId,
    [Parameter(Mandatory = $true)][string]$Label
  )

  $null = ConvertFrom-StrictEvidenceUtc -Value $ObservedAtUtc -Label "$Label observedAtUtc"
  Assert-EvidenceIdentifier -Value $EventId -Label "$Label eventId"
  Assert-EvidenceIdentifier -Value $ProbeId -Label "$Label probeId"
}

function Assert-NewerEvidenceRefresh {
  param(
    [Parameter(Mandatory = $true)]$Document,
    [Parameter(Mandatory = $true)][string]$ExistingObservedAtUtc,
    [Parameter(Mandatory = $true)][string]$ExistingEventId,
    [Parameter(Mandatory = $true)][string]$ExistingProbeId,
    [Parameter(Mandatory = $true)][string]$Label
  )

  $newObserved = ConvertFrom-StrictEvidenceUtc -Value ([string]$Document.observedAtUtc) -Label "$Label new observedAtUtc"
  $oldObserved = ConvertFrom-StrictEvidenceUtc -Value $ExistingObservedAtUtc -Label "$Label stored observedAtUtc"
  if ($newObserved -le $oldObserved) {
    throw "$Label refresh evidence must have an observedAtUtc later than the stored observation."
  }
  if ([string]$Document.eventId -ceq $ExistingEventId) {
    throw "$Label refresh evidence must use a new eventId."
  }
  if ([string]$Document.probeId -ceq $ExistingProbeId) {
    throw "$Label refresh evidence must use a new probeId."
  }
}

function Assert-EvidenceDocumentMatchesStoredMetadata {
  param(
    [Parameter(Mandatory = $true)]$Document,
    [Parameter(Mandatory = $true)][string]$ObservedAtUtc,
    [Parameter(Mandatory = $true)][string]$EventId,
    [Parameter(Mandatory = $true)][string]$ProbeId,
    [Parameter(Mandatory = $true)][string]$Label
  )

  if ([string]$Document.observedAtUtc -cne $ObservedAtUtc -or
      [string]$Document.eventId -cne $EventId -or
      [string]$Document.probeId -cne $ProbeId) {
    throw "$Label stored observation metadata does not match its immutable evidence document."
  }
}

function New-Manifest {
  param(
    [string]$ResolvedPlacePath,
    [string]$PlaceSha256,
    [string]$ResolvedStudioExecutablePath,
    [Parameter(Mandatory = $true)]$ExecutableAttestation,
    [string]$ResolvedRepositoryRoot,
    [string]$ResolvedTrustedEvidenceRoot
  )

  [pscustomobject][ordered]@{
    schemaVersion   = $script:ManifestSchemaVersion
    ownershipId    = [guid]::NewGuid().ToString('D')
    createdAtUtc   = [datetime]::UtcNow.ToString('o')
    updatedAtUtc   = [datetime]::UtcNow.ToString('o')
    repositoryRoot = $ResolvedRepositoryRoot
    repositoryAdministrationRoots = @($script:RepositoryAdministrationRoots)
    trustedEvidenceRoot = $ResolvedTrustedEvidenceRoot
    scriptsRoot = $script:ScriptsRootPath
    sessionScriptPath = [string]$script:SessionScriptAttestation.path
    sessionScriptSha256 = [string]$script:SessionScriptAttestation.sha256
    sessionScriptFileIdentity = [string]$script:SessionScriptAttestation.fileIdentity
    inputScriptPath = [string]$script:InputScriptAttestation.path
    inputScriptSha256 = [string]$script:InputScriptAttestation.sha256
    inputScriptFileIdentity = [string]$script:InputScriptAttestation.fileIdentity
    captureScriptPath = [string]$script:CaptureScriptAttestation.path
    captureScriptSha256 = [string]$script:CaptureScriptAttestation.sha256
    captureScriptFileIdentity = [string]$script:CaptureScriptAttestation.fileIdentity
    processName    = $script:ExpectedProcessName
    executablePath = $ResolvedStudioExecutablePath
    studioVersionDirectory = $script:ApprovedStudioVersionDirectory
    executableSha256 = [string]$ExecutableAttestation.sha256
    executableSignerSubject = [string]$ExecutableAttestation.signerSubject
    executableSignerThumbprint = [string]$ExecutableAttestation.signerThumbprint
    executableProductVersion = [string]$ExecutableAttestation.productVersion
    placePath      = $ResolvedPlacePath
    placeSha256    = $PlaceSha256
    placeHandshakeVerified = $false
    placeEvidencePath = $null
    placeEvidenceSha256 = $null
    placeVerifiedAtUtc = $null
    placeEvidenceObservedAtUtc = $null
    placeEvidenceEventId = $null
    placeEvidenceProbeId = $null
    pendingActionJournalSchemaVersion = $script:PendingActionJournalSchemaVersion
    lastCompletedExternalAction = $null
    ownedProcesses = @()
  }
}

function Assert-ManifestShape {
  param([Parameter(Mandatory = $true)]$Manifest)

  foreach ($name in @(
    'schemaVersion', 'ownershipId', 'createdAtUtc', 'updatedAtUtc', 'processName',
    'repositoryRoot', 'repositoryAdministrationRoots', 'trustedEvidenceRoot',
    'scriptsRoot', 'sessionScriptPath', 'sessionScriptSha256', 'sessionScriptFileIdentity',
    'inputScriptPath', 'inputScriptSha256', 'inputScriptFileIdentity',
    'captureScriptPath', 'captureScriptSha256', 'captureScriptFileIdentity',
    'executablePath', 'executableSha256',
    'executableSignerSubject', 'executableSignerThumbprint', 'executableProductVersion',
    'studioVersionDirectory',
    'placePath', 'placeSha256',
    'placeHandshakeVerified', 'placeEvidencePath', 'placeEvidenceSha256',
    'placeVerifiedAtUtc', 'placeEvidenceObservedAtUtc', 'placeEvidenceEventId',
    'placeEvidenceProbeId', 'pendingActionJournalSchemaVersion',
    'lastCompletedExternalAction', 'ownedProcesses'
  )) {
    if ($Manifest.PSObject.Properties.Name -notcontains $name) {
      throw "Session manifest is missing required property '$name': $script:SessionFilePath"
    }
  }

  if ([int]$Manifest.schemaVersion -ne $script:ManifestSchemaVersion) {
    throw "Unsupported session manifest schemaVersion '$($Manifest.schemaVersion)'."
  }
  if ([int]$Manifest.pendingActionJournalSchemaVersion -ne
      $script:PendingActionJournalSchemaVersion) {
    throw 'Session manifest pendingActionJournalSchemaVersion is unsupported.'
  }
  $ownershipGuid = [guid]::Empty
  if (-not [guid]::TryParse([string]$Manifest.ownershipId, [ref]$ownershipGuid)) {
    throw 'Session manifest ownershipId is not a valid GUID.'
  }
  if ([string]$Manifest.processName -cne $script:ExpectedProcessName) {
    throw "Session manifest processName must be exactly '$script:ExpectedProcessName'."
  }
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
      [string]$Manifest.repositoryRoot, $script:RepositoryRootPath)) {
    throw 'Session manifest repositoryRoot does not match caller-supplied RepositoryRoot.'
  }
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
      [string]$Manifest.trustedEvidenceRoot, $script:TrustedEvidenceRootPath)) {
    throw 'Session manifest trustedEvidenceRoot does not match caller-supplied TrustedEvidenceRoot.'
  }
  $manifestAdministrationRoots = @($Manifest.repositoryAdministrationRoots)
  if ($manifestAdministrationRoots.Count -ne $script:RepositoryAdministrationRoots.Count) {
    throw 'Session manifest Git administration roots do not match the caller-validated repository boundary.'
  }
  foreach ($administrationRoot in $manifestAdministrationRoots) {
    if ($administrationRoot -isnot [string] -or
        @($script:RepositoryAdministrationRoots | Where-Object {
          [StringComparer]::OrdinalIgnoreCase.Equals([string]$_, [string]$administrationRoot)
        }).Count -ne 1) {
      throw 'Session manifest contains an unexpected Git administration root.'
    }
    $canonicalAdministrationRoot = Get-CanonicalExistingPath -Path ([string]$administrationRoot) `
      -Label 'Manifest Git administration root'
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
        $canonicalAdministrationRoot, [string]$administrationRoot) -or
        (Test-PathsOverlap -First $canonicalAdministrationRoot -Second $script:TrustedEvidenceRootPath)) {
      throw 'Session manifest Git administration root is noncanonical or overlaps TrustedEvidenceRoot.'
    }
  }
  $manifestRepositoryRoot = Get-CanonicalExistingPath -Path ([string]$Manifest.repositoryRoot) `
    -Label 'Manifest repositoryRoot'
  $manifestTrustedRoot = Get-CanonicalExistingPath -Path ([string]$Manifest.trustedEvidenceRoot) `
    -Label 'Manifest trustedEvidenceRoot'
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals($manifestRepositoryRoot, $script:RepositoryRootPath) -or
      -not [StringComparer]::OrdinalIgnoreCase.Equals($manifestTrustedRoot, $script:TrustedEvidenceRootPath)) {
    throw 'Session manifest root paths no longer resolve to the caller-validated physical roots.'
  }
  if (Test-PathsOverlap -First $manifestRepositoryRoot -Second $manifestTrustedRoot) {
    throw 'Session manifest repositoryRoot and trustedEvidenceRoot must remain physically disjoint.'
  }
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
      [string]$Manifest.scriptsRoot, $script:ScriptsRootPath)) {
    throw 'Session manifest scriptsRoot does not match the current protected skill installation.'
  }
  $scriptBindings = @(
    [pscustomobject]@{
      label = 'session'; path = [string]$Manifest.sessionScriptPath
      sha256 = [string]$Manifest.sessionScriptSha256
      fileIdentity = [string]$Manifest.sessionScriptFileIdentity
      current = $script:SessionScriptAttestation
    },
    [pscustomobject]@{
      label = 'input'; path = [string]$Manifest.inputScriptPath
      sha256 = [string]$Manifest.inputScriptSha256
      fileIdentity = [string]$Manifest.inputScriptFileIdentity
      current = $script:InputScriptAttestation
    },
    [pscustomobject]@{
      label = 'capture'; path = [string]$Manifest.captureScriptPath
      sha256 = [string]$Manifest.captureScriptSha256
      fileIdentity = [string]$Manifest.captureScriptFileIdentity
      current = $script:CaptureScriptAttestation
    }
  )
  foreach ($binding in $scriptBindings) {
    $freshBinding = Get-TrustedScriptSnapshot -Path $binding.path `
      -Label "Manifest $($binding.label) script"
    if ($binding.sha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $binding.fileIdentity -cnotmatch '^[0-9A-F]{8}:[0-9A-F]{8}:[0-9A-F]{8}:1$' -or
        -not [StringComparer]::OrdinalIgnoreCase.Equals($binding.path, [string]$binding.current.path) -or
        $binding.sha256 -cne [string]$binding.current.sha256 -or
        $binding.fileIdentity -cne [string]$binding.current.fileIdentity -or
        -not [StringComparer]::OrdinalIgnoreCase.Equals($binding.path, [string]$freshBinding.path) -or
        $binding.sha256 -cne [string]$freshBinding.sha256 -or
        $binding.fileIdentity -cne [string]$freshBinding.fileIdentity) {
      throw "Session manifest $($binding.label) script path/hash/file identity no longer matches the protected installation."
    }
  }
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
      [string]$Manifest.studioVersionDirectory, $script:ApprovedStudioVersionDirectory)) {
    throw 'Session manifest Studio version directory does not match the caller-approved protected inventory directory.'
  }
  $currentStudioVersionDirectory = Get-CanonicalExistingPath `
    -Path ([string]$Manifest.studioVersionDirectory) -Label 'Manifest Studio version directory'
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
      $currentStudioVersionDirectory, $script:ApprovedStudioVersionDirectory)) {
    throw 'Session manifest Studio version directory no longer resolves to the caller-approved physical directory.'
  }
  Assert-RootDisjointFromBoundaries -Root $currentStudioVersionDirectory `
    -Label 'Manifest Studio version directory' `
    -Boundaries (@($script:ScriptWriteBoundaries) + @($script:ScriptsRootPath))
  if (-not [string]::IsNullOrWhiteSpace([string]$Manifest.executablePath) -and
      [System.IO.Path]::GetFileName([string]$Manifest.executablePath) -cne $script:ExpectedExecutableLeaf) {
    throw "Session manifest executablePath must end in the exact filename '$script:ExpectedExecutableLeaf'."
  }
  if (-not [string]::IsNullOrWhiteSpace([string]$Manifest.placeSha256) -and
      [string]$Manifest.placeSha256 -cnotmatch '^[0-9a-f]{64}$') {
    throw 'Session manifest placeSha256 must be a lowercase SHA-256 digest.'
  }
  if (-not [string]::IsNullOrWhiteSpace([string]$Manifest.placePath)) {
    $manifestPlacePath = Get-CanonicalExistingPath -Path ([string]$Manifest.placePath) `
      -Label 'Manifest placePath' -Leaf
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals($manifestPlacePath, [string]$Manifest.placePath) -or
        -not (Test-PathWithinRoot -Path $manifestPlacePath -Root $manifestTrustedRoot)) {
      throw 'Session manifest placePath must remain a canonical descendant of TrustedEvidenceRoot.'
    }
    $currentPlaceHash = Get-Sha256HexOfFile -Path $manifestPlacePath -Label 'Manifest placePath'
    if ($currentPlaceHash -cne [string]$Manifest.placeSha256) {
      throw 'Session manifest place artifact bytes changed after Open.'
    }
  }
  if (-not [string]::IsNullOrWhiteSpace([string]$Manifest.executablePath)) {
    $manifestExecutablePath = Get-CanonicalExistingPath -Path ([string]$Manifest.executablePath) `
      -Label 'Manifest executablePath' -Leaf
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
        $manifestExecutablePath, [string]$Manifest.executablePath)) {
      throw 'Session manifest executablePath no longer names the recorded canonical file.'
    }
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
        $manifestExecutablePath, $script:ApprovedStudioExecutablePath)) {
      throw 'Session manifest executablePath does not match caller-supplied approved StudioExecutablePath.'
    }
    if ([string]$Manifest.executableSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$Manifest.executableSignerThumbprint -cnotmatch '^[0-9A-F]{40,128}$' -or
        [string]::IsNullOrWhiteSpace([string]$Manifest.executableSignerSubject) -or
        [string]::IsNullOrWhiteSpace([string]$Manifest.executableProductVersion)) {
      throw 'Session manifest executable attestation fields are missing or malformed.'
    }
    Assert-StudioAttestationMatchesManifest -Manifest $Manifest `
      -Attestation $script:ApprovedStudioExecutableAttestation
  }
  if ($Manifest.placeHandshakeVerified -isnot [bool]) {
    throw 'Session manifest placeHandshakeVerified must be a JSON boolean.'
  }
  if ([bool]$Manifest.placeHandshakeVerified) {
    if ([string]::IsNullOrWhiteSpace([string]$Manifest.placeEvidencePath) -or
        [string]$Manifest.placeEvidenceSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]::IsNullOrWhiteSpace([string]$Manifest.placeVerifiedAtUtc) -or
        [string]::IsNullOrWhiteSpace([string]$Manifest.placeEvidenceObservedAtUtc) -or
        [string]::IsNullOrWhiteSpace([string]$Manifest.placeEvidenceEventId) -or
        [string]::IsNullOrWhiteSpace([string]$Manifest.placeEvidenceProbeId)) {
      throw 'Verified place handshake requires evidence path, SHA-256, timestamps, eventId, and probeId.'
    }
    if (-not [System.IO.Path]::IsPathRooted([string]$Manifest.placeEvidencePath) -or
        [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters([string]$Manifest.placeEvidencePath)) {
      throw 'Verified place evidence path must be absolute and literal.'
    }
    $canonicalPlaceEvidence = Get-CanonicalProspectiveFilePath `
      -Path ([string]$Manifest.placeEvidencePath) -Label 'Verified place evidence'
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
        $canonicalPlaceEvidence, [string]$Manifest.placeEvidencePath) -or
        -not (Test-PathWithinRoot -Path $canonicalPlaceEvidence -Root $manifestTrustedRoot)) {
      throw 'Verified place evidence must remain a canonical descendant of TrustedEvidenceRoot.'
    }
    $parsedPlaceVerificationTime = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$Manifest.placeVerifiedAtUtc, [ref]$parsedPlaceVerificationTime)) {
      throw 'Verified place timestamp is invalid.'
    }
    Assert-StoredEvidenceMetadata -ObservedAtUtc ([string]$Manifest.placeEvidenceObservedAtUtc) `
      -EventId ([string]$Manifest.placeEvidenceEventId) `
      -ProbeId ([string]$Manifest.placeEvidenceProbeId) -Label 'Verified place evidence'
  } elseif (-not [string]::IsNullOrWhiteSpace([string]$Manifest.placeEvidencePath) -or
            -not [string]::IsNullOrWhiteSpace([string]$Manifest.placeEvidenceSha256) -or
            -not [string]::IsNullOrWhiteSpace([string]$Manifest.placeVerifiedAtUtc) -or
            -not [string]::IsNullOrWhiteSpace([string]$Manifest.placeEvidenceObservedAtUtc) -or
            -not [string]::IsNullOrWhiteSpace([string]$Manifest.placeEvidenceEventId) -or
            -not [string]::IsNullOrWhiteSpace([string]$Manifest.placeEvidenceProbeId)) {
    throw 'Unverified place handshake must not contain verification evidence fields.'
  }

  foreach ($record in @($Manifest.ownedProcesses)) {
    foreach ($name in @(
      'pid', 'startTimeUtc', 'sessionId', 'executablePath', 'role', 'launchIntent', 'roleVerified',
      'roleEvidencePath', 'roleEvidenceSha256', 'roleVerifiedAtUtc',
      'roleEvidenceObservedAtUtc', 'roleEvidenceEventId', 'roleEvidenceProbeId',
      'ownershipId', 'acquiredAtUtc'
    )) {
      if ($record.PSObject.Properties.Name -notcontains $name) {
        throw "Owned process record is missing required property '$name'."
      }
    }
    if ([string]$record.ownershipId -cne [string]$Manifest.ownershipId) {
      throw "Owned process PID $($record.pid) has a foreign ownershipId."
    }
    if ([System.IO.Path]::GetFileName([string]$record.executablePath) -cne $script:ExpectedExecutableLeaf) {
      throw "Owned process PID $($record.pid) does not name $script:ExpectedExecutableLeaf."
    }
    if ([int]$record.pid -le 0 -or [int]$record.sessionId -lt 0) {
      throw 'Owned process records require a positive PID and non-negative Windows sessionId.'
    }
    $parsedTime = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$record.startTimeUtc, [ref]$parsedTime)) {
      throw "Owned process PID $($record.pid) has an invalid startTimeUtc."
    }
    if ([string]$record.role -cnotmatch '^(edit|server|client:[1-8])$') {
      throw "Owned process PID $($record.pid) has invalid role '$($record.role)'."
    }
    if ([string]$record.launchIntent -cne [string]$record.role) {
      throw "Owned process PID $($record.pid) launchIntent must exactly equal its candidate role value."
    }
    if ($record.roleVerified -isnot [bool]) {
      throw "Owned process PID $($record.pid) roleVerified must be a JSON boolean."
    }
    if ([bool]$record.roleVerified) {
      if ([string]::IsNullOrWhiteSpace([string]$record.roleEvidencePath) -or
          [string]$record.roleEvidenceSha256 -cnotmatch '^[0-9a-f]{64}$' -or
          [string]::IsNullOrWhiteSpace([string]$record.roleVerifiedAtUtc) -or
          [string]::IsNullOrWhiteSpace([string]$record.roleEvidenceObservedAtUtc) -or
          [string]::IsNullOrWhiteSpace([string]$record.roleEvidenceEventId) -or
          [string]::IsNullOrWhiteSpace([string]$record.roleEvidenceProbeId)) {
        throw "Verified role for PID $($record.pid) requires evidence path, SHA-256, timestamps, eventId, and probeId."
      }
      if (-not [System.IO.Path]::IsPathRooted([string]$record.roleEvidencePath) -or
          [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters([string]$record.roleEvidencePath)) {
        throw "Verified role evidence path for PID $($record.pid) must be absolute and literal."
      }
      $canonicalRoleEvidence = Get-CanonicalProspectiveFilePath `
        -Path ([string]$record.roleEvidencePath) `
        -Label "Verified role evidence PID $($record.pid)"
      if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
          $canonicalRoleEvidence, [string]$record.roleEvidencePath) -or
          -not (Test-PathWithinRoot -Path $canonicalRoleEvidence -Root $manifestTrustedRoot)) {
        throw "Verified role evidence for PID $($record.pid) must remain a canonical descendant of TrustedEvidenceRoot."
      }
      $parsedRoleVerificationTime = [datetime]::MinValue
      if (-not [datetime]::TryParse([string]$record.roleVerifiedAtUtc, [ref]$parsedRoleVerificationTime)) {
        throw "Verified role timestamp for PID $($record.pid) is invalid."
      }
      Assert-StoredEvidenceMetadata -ObservedAtUtc ([string]$record.roleEvidenceObservedAtUtc) `
        -EventId ([string]$record.roleEvidenceEventId) `
        -ProbeId ([string]$record.roleEvidenceProbeId) -Label "Verified role PID $($record.pid)"
    } elseif (-not [string]::IsNullOrWhiteSpace([string]$record.roleEvidencePath) -or
              -not [string]::IsNullOrWhiteSpace([string]$record.roleEvidenceSha256) -or
              -not [string]::IsNullOrWhiteSpace([string]$record.roleVerifiedAtUtc) -or
              -not [string]::IsNullOrWhiteSpace([string]$record.roleEvidenceObservedAtUtc) -or
              -not [string]::IsNullOrWhiteSpace([string]$record.roleEvidenceEventId) -or
              -not [string]::IsNullOrWhiteSpace([string]$record.roleEvidenceProbeId)) {
      throw "Unverified role for PID $($record.pid) must not contain verification evidence fields."
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Manifest.executablePath) -and
        -not [StringComparer]::OrdinalIgnoreCase.Equals([string]$record.executablePath, [string]$Manifest.executablePath)) {
      throw "Owned process PID $($record.pid) uses a different executablePath than the session root."
    }
  }

  $duplicatePids = @($Manifest.ownedProcesses | Group-Object pid | Where-Object { $_.Count -gt 1 })
  if ($duplicatePids.Count -ne 0) {
    throw "Session manifest contains duplicate PID records: $($duplicatePids.Name -join ', ')."
  }
  $duplicateRoles = @($Manifest.ownedProcesses | Group-Object role | Where-Object { $_.Count -gt 1 })
  if ($duplicateRoles.Count -ne 0) {
    throw "Session manifest contains duplicate role records: $($duplicateRoles.Name -join ', ')."
  }
  if ([bool]$Manifest.placeHandshakeVerified) {
    $verifiedEditRecords = @($Manifest.ownedProcesses | Where-Object {
      [string]$_.role -ceq 'edit' -and [bool]$_.roleVerified
    })
    if ($verifiedEditRecords.Count -ne 1) {
      throw 'Verified place handshake requires exactly one role-verified edit record.'
    }
  }

  $completion = $Manifest.lastCompletedExternalAction
  if ($null -ne $completion) {
    foreach ($name in @(
        'schemaVersion', 'actionId', 'action', 'completedAtUtc', 'ownershipId',
        'journalPath', 'pendingJournalSha256', 'manifestSha256BeforeAction',
        'targetIntent', 'resultBinding', 'resultBindingSha256'
      )) {
      if ($completion.PSObject.Properties.Name -notcontains $name) {
        throw "lastCompletedExternalAction is missing required property '$name'."
      }
    }
    if ([int]$completion.schemaVersion -ne $script:ExternalActionCompletionSchemaVersion) {
      throw 'lastCompletedExternalAction schemaVersion is unsupported.'
    }
    $completionActionId = [guid]::Empty
    if (-not [guid]::TryParse([string]$completion.actionId, [ref]$completionActionId)) {
      throw 'lastCompletedExternalAction actionId must be a GUID.'
    }
    if ([string]$completion.action -cnotmatch '^(Open|Start|AddClients|Input|Capture|Cleanup)$') {
      throw 'lastCompletedExternalAction action is unsupported.'
    }
    $null = ConvertFrom-StrictEvidenceUtc -Value ([string]$completion.completedAtUtc) `
      -Label 'lastCompletedExternalAction completedAtUtc'
    if ([string]$completion.ownershipId -cne [string]$Manifest.ownershipId) {
      throw 'lastCompletedExternalAction ownershipId does not match the manifest.'
    }
    $completionJournalPath = Get-NormalizedPathForComparison -Path ([string]$completion.journalPath)
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
        $completionJournalPath, $script:PendingActionJournalPath) -or
        -not (Test-PathWithinRoot -Path $completionJournalPath -Root $manifestTrustedRoot)) {
      throw 'lastCompletedExternalAction journalPath does not match the trusted SessionFile journal path.'
    }
    # While an external action is being committed, this process intentionally holds the
    # pending marker with FileShare.None. Reopening that path here would deadlock/fail the
    # normal Save-Manifest path. Its lexical/canonical parent was fixed at initialization,
    # and the exact file identity remains bound through the active lease. When no owned
    # lease exists, it is safe to perform the normal prospective canonical check.
    if ($null -ne $script:ActivePendingActionJournal) {
      if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
          [string]$script:ActivePendingActionJournal.path, $completionJournalPath)) {
        throw 'lastCompletedExternalAction journalPath does not match the active journal lease path.'
      }
      if ([string]$script:ActivePendingActionJournal.document.actionId -cne
          [string]$completion.actionId) {
        # Cleanup may durably save a partially reconciled process list before it can
        # declare the current external action complete. In that one intermediate state,
        # the manifest still carries the prior completion while the new marker owns the
        # same fixed journal pathname. Permit only a strictly older completion.
        $priorCompletedAt = ConvertFrom-StrictEvidenceUtc `
          -Value ([string]$completion.completedAtUtc) `
          -Label 'prior lastCompletedExternalAction completedAtUtc'
        $activeCreatedAt = ConvertFrom-StrictEvidenceUtc `
          -Value ([string]$script:ActivePendingActionJournal.document.createdAtUtc) `
          -Label 'active pending-action journal createdAtUtc'
        if ($priorCompletedAt -ge $activeCreatedAt) {
          throw 'A nonmatching lastCompletedExternalAction is not older than the active journal.'
        }
      }
    } else {
      $completionJournalPath = Get-CanonicalProspectiveFilePath `
        -Path $completionJournalPath -Label 'lastCompletedExternalAction journalPath'
    }
    if ([string]$completion.pendingJournalSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$completion.manifestSha256BeforeAction -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$completion.resultBindingSha256 -cnotmatch '^[0-9a-f]{64}$') {
      throw 'lastCompletedExternalAction SHA-256 fields are malformed.'
    }
    if ($completion.targetIntent -isnot [pscustomobject] -or
        $completion.resultBinding -isnot [pscustomobject] -or
        @($completion.targetIntent.PSObject.Properties).Count -eq 0 -or
        @($completion.resultBinding.PSObject.Properties).Count -eq 0) {
      throw 'lastCompletedExternalAction requires targetIntent and resultBinding objects.'
    }
    $completionTargetJson = $completion.targetIntent | ConvertTo-Json -Compress -Depth 6
    $completionResultJson = $completion.resultBinding | ConvertTo-Json -Compress -Depth 6
    if ($completionTargetJson.Length -gt 32768 -or $completionResultJson.Length -gt 32768) {
      throw 'lastCompletedExternalAction target/result binding exceeds the 32 KiB bound.'
    }
    if ((Get-Sha256HexOfUtf8String -Value $completionResultJson) -cne
        [string]$completion.resultBindingSha256) {
      throw 'lastCompletedExternalAction resultBindingSha256 does not match resultBinding.'
    }
  }
}

function ConvertFrom-ManifestJsonStrict {
  param([Parameter(Mandatory = $true)][string]$Json)

  $convertFromJson = Get-Command -Name 'Microsoft.PowerShell.Utility\ConvertFrom-Json' -CommandType Cmdlet -ErrorAction Stop
  if ($convertFromJson.Parameters.ContainsKey('DateKind')) {
    # PowerShell 7.5+ otherwise converts ISO strings to DateTime. That silently
    # localizes `[string]$record.startTimeUtc` and breaks strict identity/evidence binding.
    return Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $Json -DateKind String
  }
  # The startup engine gate permits this fallback only on Windows PowerShell 5.1,
  # whose ConvertFrom-Json preserves ISO timestamps as strings.
  return Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $Json
}

function Read-Manifest {
  $canonicalSession = Get-CanonicalExistingPath -Path $script:SessionFilePath -Label 'SessionFile' -Leaf
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals($canonicalSession, $script:SessionFilePath) -or
      -not (Test-PathWithinRoot -Path $canonicalSession -Root $script:TrustedEvidenceRootPath)) {
    throw 'SessionFile no longer resolves to its canonical path inside TrustedEvidenceRoot.'
  }
  if (-not (Test-Path -LiteralPath $script:SessionFilePath -PathType Leaf)) {
    throw "SessionFile does not exist: $script:SessionFilePath"
  }
  try {
    $manifestJson = Get-Content -Raw -LiteralPath $script:SessionFilePath -Encoding UTF8
    $manifest = ConvertFrom-ManifestJsonStrict -Json $manifestJson
  } catch {
    throw "Cannot read valid JSON from SessionFile '$script:SessionFilePath': $($_.Exception.Message)"
  }
  Assert-ManifestShape $manifest
  return $manifest
}

function Save-Manifest {
  param([Parameter(Mandatory = $true)]$Manifest)

  Assert-ManifestShape $Manifest
  $canonicalSession = Get-CanonicalProspectiveFilePath -Path $script:SessionFilePath -Label 'SessionFile'
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals($canonicalSession, $script:SessionFilePath) -or
      -not (Test-PathWithinRoot -Path $canonicalSession -Root $script:TrustedEvidenceRootPath)) {
    throw 'SessionFile no longer resolves to its canonical path inside TrustedEvidenceRoot.'
  }
  $directory = Split-Path -Parent $script:SessionFilePath
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    throw "SessionFile parent directory does not exist: $directory"
  }

  $Manifest.updatedAtUtc = [datetime]::UtcNow.ToString('o')
  $temp = Join-Path $directory ('.{0}.{1}.tmp' -f ([System.IO.Path]::GetFileName($script:SessionFilePath)), [guid]::NewGuid().ToString('N'))
  $tempStream = $null
  try {
    $json = $Manifest | ConvertTo-Json -Depth 8
    $encoding = [System.Text.UTF8Encoding]::new($false, $true)
    $bytes = $encoding.GetBytes($json)
    if ($bytes.Length -le 0 -or $bytes.Length -gt 1048576) {
      throw 'Serialized SessionFile must contain 1..1048576 UTF-8 bytes.'
    }
    $expectedHash = Get-Sha256HexOfUtf8String -Value $json
    $tempStream = [System.IO.FileStream]::new(
      $temp,
      [System.IO.FileMode]::CreateNew,
      [System.IO.FileAccess]::Write,
      [System.IO.FileShare]::None,
      4096,
      [System.IO.FileOptions]::WriteThrough)
    $tempStream.Write($bytes, 0, $bytes.Length)
    $tempStream.Flush($true)
    if ($tempStream.Length -ne $bytes.Length) {
      throw 'SessionFile temporary durable length does not match the intended bytes.'
    }
    $tempStream.Dispose()
    $tempStream = $null
    if (Test-Path -LiteralPath $script:SessionFilePath -PathType Leaf) {
      [System.IO.File]::Replace($temp, $script:SessionFilePath, $null)
    } else {
      [System.IO.File]::Move($temp, $script:SessionFilePath)
    }
    $committedSession = Get-CanonicalExistingPath -Path $script:SessionFilePath `
      -Label 'Committed SessionFile' -Leaf
    $committedHash = Get-Sha256HexOfFile -Path $committedSession -Label 'Committed SessionFile'
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
        $committedSession, $script:SessionFilePath) -or
        $committedHash -cne $expectedHash) {
      throw 'Committed SessionFile path/hash does not match the durably written manifest bytes.'
    }
  } finally {
    if ($null -ne $tempStream) { $tempStream.Dispose() }
    if (Test-Path -LiteralPath $temp -PathType Leaf) {
      Remove-Item -LiteralPath $temp -Force
    }
  }
}

function Get-PendingActionJournalStatus {
  $status = [ordered]@{
    schemaVersion = $script:PendingActionJournalSchemaVersion
    path = $script:PendingActionJournalPath
    exists = $false
    valid = $true
    reason = 'absent'
    sha256 = $null
    fileIdentity = $null
    manifestMatchesPreAction = $null
    document = $null
  }

  if (-not [System.IO.File]::Exists($script:PendingActionJournalPath) -and
      -not [System.IO.Directory]::Exists($script:PendingActionJournalPath)) {
    return [pscustomobject]$status
  }
  $status.exists = $true
  $status.valid = $false
  try {
    if ([System.IO.Directory]::Exists($script:PendingActionJournalPath)) {
      throw 'The pending-action journal path is a directory, not a file.'
    }
    $canonical = Get-CanonicalExistingPath -Path $script:PendingActionJournalPath `
      -Label 'Pending action journal' -Leaf
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
        $canonical, $script:PendingActionJournalPath) -or
        -not (Test-PathWithinRoot -Path $canonical -Root $script:TrustedEvidenceRootPath)) {
      throw 'Pending-action journal escaped its canonical TrustedEvidenceRoot path.'
    }

    $stream = $null
    $hasher = $null
    try {
      $stream = [System.IO.File]::Open(
        $canonical, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
        [System.IO.FileShare]::Read)
      if ($stream.Length -le 0 -or $stream.Length -gt 65536L) {
        throw 'Pending-action journal must contain 1..65536 bytes.'
      }
      $identity = [StudioPathSafe]::FileIdentityOfHandle($stream.SafeFileHandle)
      if ($identity -cnotmatch '^[0-9A-F]{8}:[0-9A-F]{8}:[0-9A-F]{8}:1$') {
        throw 'Pending-action journal must have one stable NTFS directory entry.'
      }
      $bytes = [byte[]]::new([int]$stream.Length)
      $offset = 0
      while ($offset -lt $bytes.Length) {
        $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
        if ($read -le 0) { throw 'Pending-action journal ended before its declared length.' }
        $offset += $read
      }
      if ($stream.ReadByte() -ne -1 -or $stream.Length -ne $bytes.Length) {
        throw 'Pending-action journal length changed while reading.'
      }
      $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
      $json = $utf8.GetString($bytes)
      $hasher = [Security.Cryptography.SHA256]::Create()
      $journalHash = [BitConverter]::ToString($hasher.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    } finally {
      if ($null -ne $hasher) { $hasher.Dispose() }
      if ($null -ne $stream) { $stream.Dispose() }
    }

    $document = ConvertFrom-ManifestJsonStrict -Json $json
    $requiredNames = @(
      'schemaVersion', 'state', 'actionId', 'action', 'createdAtUtc',
      'sessionFile', 'ownershipId', 'manifestSchemaVersion', 'manifestSha256',
      'targetIntent', 'callerPid', 'callerWindowsSessionId', 'callerSid',
      'hostPath', 'journalFileIdentity'
    )
    if (@($document.PSObject.Properties).Count -ne $requiredNames.Count) {
      throw 'Pending-action journal contains an unexpected property set.'
    }
    foreach ($name in $requiredNames) {
      if ($document.PSObject.Properties.Name -notcontains $name) {
        throw "Pending-action journal is missing required property '$name'."
      }
    }
    if ([int]$document.schemaVersion -ne $script:PendingActionJournalSchemaVersion -or
        [string]$document.state -cne 'pending') {
      throw 'Pending-action journal schema/state is unsupported.'
    }
    $actionId = [guid]::Empty
    $ownershipId = [guid]::Empty
    if (-not [guid]::TryParse([string]$document.actionId, [ref]$actionId) -or
        -not [guid]::TryParse([string]$document.ownershipId, [ref]$ownershipId)) {
      throw 'Pending-action journal actionId and ownershipId must be GUIDs.'
    }
    if ([string]$document.action -cnotmatch '^(Open|Start|AddClients|Input|Capture|Cleanup)$') {
      throw 'Pending-action journal action is unsupported.'
    }
    $null = ConvertFrom-StrictEvidenceUtc -Value ([string]$document.createdAtUtc) `
      -Label 'Pending-action journal createdAtUtc'
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
        [string]$document.sessionFile, $script:SessionFilePath) -or
        [int]$document.manifestSchemaVersion -ne $script:ManifestSchemaVersion -or
        [string]$document.manifestSha256 -cnotmatch '^[0-9a-f]{64}$') {
      throw 'Pending-action journal manifest/session binding is invalid.'
    }
    if ($document.targetIntent -isnot [pscustomobject] -or
        @($document.targetIntent.PSObject.Properties).Count -eq 0 -or
        ($document.targetIntent | ConvertTo-Json -Compress -Depth 6).Length -gt 32768) {
      throw 'Pending-action journal targetIntent must be a bounded JSON object.'
    }
    $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ([int]$document.callerPid -le 0 -or [int]$document.callerWindowsSessionId -lt 0 -or
        [string]$document.callerSid -cne $currentSid -or
        -not [StringComparer]::OrdinalIgnoreCase.Equals(
          [string]$document.hostPath, $entryExpectedHostPath) -or
        [string]$document.journalFileIdentity -cne $identity) {
      throw 'Pending-action journal caller/host/file identity binding is invalid.'
    }

    $manifestMatches = $false
    if ([System.IO.File]::Exists($script:SessionFilePath)) {
      try {
        $manifestMatches = (Get-Sha256HexOfFile -Path $script:SessionFilePath `
          -Label 'Pending action pre-state SessionFile') -ceq [string]$document.manifestSha256
      } catch {
        $manifestMatches = $false
      }
    }
    $status.valid = $true
    $status.reason = 'manual-reconcile-required'
    $status.sha256 = $journalHash
    $status.fileIdentity = $identity
    $status.manifestMatchesPreAction = [bool]$manifestMatches
    $status.document = $document
  } catch {
    $status.reason = "invalid-pending-journal: $($_.Exception.Message)"
  }
  return [pscustomobject]$status
}

function New-PendingActionJournal {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)]$TargetIntent
  )

  if ($null -ne $script:ActivePendingActionJournal) {
    throw 'This invocation already owns a pending-action journal lease.'
  }
  if ([System.IO.File]::Exists($script:PendingActionJournalPath) -or
      [System.IO.Directory]::Exists($script:PendingActionJournalPath)) {
    throw "A pending-action journal already exists and requires manual reconciliation: $script:PendingActionJournalPath"
  }
  Assert-ManifestShape $Manifest
  $targetJson = $TargetIntent | ConvertTo-Json -Compress -Depth 6
  if ($TargetIntent -isnot [pscustomobject] -or $targetJson.Length -gt 32768) {
    throw 'Pending-action targetIntent must be a bounded JSON object.'
  }
  $manifestHash = Get-Sha256HexOfFile -Path $script:SessionFilePath `
    -Label 'Pending action pre-state SessionFile'
  $lease = $null
  try {
    $lease = [System.IO.FileStream]::new(
      $script:PendingActionJournalPath,
      [System.IO.FileMode]::CreateNew,
      [System.IO.FileAccess]::ReadWrite,
      [System.IO.FileShare]::None,
      4096,
      [System.IO.FileOptions]::WriteThrough)
    $journalIdentity = [StudioPathSafe]::FileIdentityOfHandle($lease.SafeFileHandle)
    if ($journalIdentity -cnotmatch '^[0-9A-F]{8}:[0-9A-F]{8}:[0-9A-F]{8}:1$') {
      throw 'New pending-action journal did not receive a unique single-link file identity.'
    }
    $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
    $document = [pscustomobject][ordered]@{
      schemaVersion = $script:PendingActionJournalSchemaVersion
      state = 'pending'
      actionId = [guid]::NewGuid().ToString('D')
      action = $Action
      createdAtUtc = [datetime]::UtcNow.ToString('o')
      sessionFile = $script:SessionFilePath
      ownershipId = [string]$Manifest.ownershipId
      manifestSchemaVersion = $script:ManifestSchemaVersion
      manifestSha256 = $manifestHash
      targetIntent = $TargetIntent
      callerPid = [int]$currentProcess.Id
      callerWindowsSessionId = [int]$currentProcess.SessionId
      callerSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
      hostPath = $entryExpectedHostPath
      journalFileIdentity = $journalIdentity
    }
    $json = $document | ConvertTo-Json -Compress -Depth 7
    $encoding = [System.Text.UTF8Encoding]::new($false, $true)
    $bytes = $encoding.GetBytes($json)
    if ($bytes.Length -le 0 -or $bytes.Length -gt 65536) {
      throw 'Pending-action journal exceeds the 65536-byte durability bound.'
    }
    $lease.Write($bytes, 0, $bytes.Length)
    $lease.Flush($true)
    if ($lease.Length -ne $bytes.Length) {
      throw 'Pending-action journal durable length does not match the intended bytes.'
    }
    $journalHash = Get-Sha256HexOfUtf8String -Value $json
    $journal = [pscustomobject][ordered]@{
      document = $document
      path = $script:PendingActionJournalPath
      sha256 = $journalHash
      fileIdentity = $journalIdentity
      byteLength = [int64]$bytes.Length
      lease = $lease
    }
    $script:ActivePendingActionJournal = $journal
    $script:PendingActionJournalStatus = [pscustomobject][ordered]@{
      schemaVersion = $script:PendingActionJournalSchemaVersion
      path = $script:PendingActionJournalPath
      exists = $true
      valid = $true
      reason = 'active-in-this-invocation'
      sha256 = $journalHash
      fileIdentity = $journalIdentity
      manifestMatchesPreAction = $true
      document = $document
    }
    return $journal
  } catch {
    if ($null -ne $lease) { $lease.Dispose() }
    throw "Cannot create a durable pending-action journal; no external action may continue: $($_.Exception.Message)"
  }
}

function Set-ManifestExternalActionCompletion {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)]$Journal,
    [Parameter(Mandatory = $true)]$ResultBinding
  )

  $resultJson = $ResultBinding | ConvertTo-Json -Compress -Depth 6
  if ($ResultBinding -isnot [pscustomobject] -or $resultJson.Length -gt 32768) {
    throw 'External-action resultBinding must be a bounded JSON object.'
  }
  $completion = [pscustomobject][ordered]@{
    schemaVersion = $script:ExternalActionCompletionSchemaVersion
    actionId = [string]$Journal.document.actionId
    action = [string]$Journal.document.action
    completedAtUtc = [datetime]::UtcNow.ToString('o')
    ownershipId = [string]$Manifest.ownershipId
    journalPath = [string]$Journal.path
    pendingJournalSha256 = [string]$Journal.sha256
    manifestSha256BeforeAction = [string]$Journal.document.manifestSha256
    targetIntent = $Journal.document.targetIntent
    resultBinding = $ResultBinding
    resultBindingSha256 = Get-Sha256HexOfUtf8String -Value $resultJson
  }
  $Manifest.lastCompletedExternalAction = $completion
  return $completion
}

function Complete-PendingActionJournal {
  param([Parameter(Mandatory = $true)]$Journal)

  if ($null -eq $script:ActivePendingActionJournal -or
      [string]$script:ActivePendingActionJournal.document.actionId -cne
      [string]$Journal.document.actionId) {
    throw 'Pending-action completion does not match the journal lease owned by this invocation.'
  }
  $savedManifest = Read-Manifest
  $completion = $savedManifest.lastCompletedExternalAction
  if ($null -eq $completion -or
      [string]$completion.actionId -cne [string]$Journal.document.actionId -or
      [string]$completion.pendingJournalSha256 -cne [string]$Journal.sha256 -or
      [string]$completion.manifestSha256BeforeAction -cne [string]$Journal.document.manifestSha256) {
    throw 'The durably saved manifest does not contain the matching external-action completion record.'
  }

  $lease = $Journal.lease
  if ($null -eq $lease -or -not $lease.CanRead -or -not $lease.CanWrite) {
    throw 'Pending-action journal lease is unavailable at completion.'
  }
  $lease.Flush($true)
  if ([StudioPathSafe]::FileIdentityOfHandle($lease.SafeFileHandle) -cne
      [string]$Journal.fileIdentity -or $lease.Length -ne [int64]$Journal.byteLength) {
    throw 'Pending-action journal identity/length changed before completion.'
  }
  $lease.Position = 0
  $hasher = [Security.Cryptography.SHA256]::Create()
  try {
    $leasedHash = [BitConverter]::ToString($hasher.ComputeHash($lease)).Replace('-', '').ToLowerInvariant()
  } finally {
    $hasher.Dispose()
  }
  if ($leasedHash -cne [string]$Journal.sha256) {
    throw 'Pending-action journal bytes changed before completion.'
  }
  $lease.Dispose()
  $Journal.lease = $null

  $canonical = Get-CanonicalExistingPath -Path $Journal.path `
    -Label 'Completed pending-action journal' -Leaf
  $freshIdentity = [StudioPathSafe]::FileIdentity($canonical)
  $freshHash = Get-Sha256HexOfFile -Path $canonical -Label 'Completed pending-action journal'
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals($canonical, [string]$Journal.path) -or
      $freshIdentity -cne [string]$Journal.fileIdentity -or
      $freshHash -cne [string]$Journal.sha256) {
    throw 'Pending-action journal path/identity/hash changed before deletion.'
  }
  try {
    [System.IO.File]::Delete($canonical)
  } catch {
    throw "The completed pending-action journal could not be deleted; manual reconciliation remains required: $($_.Exception.Message)"
  }
  if ([System.IO.File]::Exists($canonical) -or [System.IO.Directory]::Exists($canonical)) {
    throw 'The completed pending-action journal still exists after deletion; manual reconciliation remains required.'
  }

  $script:ActivePendingActionJournal = $null
  $script:CompletedExternalAction = $completion
  $script:PendingActionJournalStatus = [pscustomobject][ordered]@{
    schemaVersion = $script:PendingActionJournalSchemaVersion
    path = $script:PendingActionJournalPath
    exists = $false
    valid = $true
    reason = 'completed-and-cleared'
    sha256 = $null
    fileIdentity = $null
    manifestMatchesPreAction = $null
    document = $null
  }
}

function Get-StudioSnapshots {
  $snapshots = [System.Collections.Generic.List[object]]::new()
  foreach ($process in @(Get-Process -Name $script:ExpectedProcessName -ErrorAction SilentlyContinue)) {
    try {
      if ($process.HasExited) { continue }
      $path = [string]$process.Path
      if ([string]::IsNullOrWhiteSpace($path)) {
        throw "Executable path is unavailable for PID $($process.Id)."
      }
      $fullPath = Get-CanonicalExistingPath -Path $path -Label "Studio PID $($process.Id) executable" -Leaf
      if ([System.IO.Path]::GetFileName($fullPath) -cne $script:ExpectedExecutableLeaf) {
        throw "PID $($process.Id) is not $script:ExpectedExecutableLeaf (path: $fullPath)."
      }

      $snapshots.Add([pscustomobject][ordered]@{
        pid            = [int]$process.Id
        startTimeUtc   = $process.StartTime.ToUniversalTime().ToString('o')
        sessionId      = [int]$process.SessionId
        executablePath = $fullPath
        process        = $process
      })
    } catch {
      throw "Cannot safely inspect Roblox Studio PID $($process.Id): $($_.Exception.Message)"
    }
  }
  return $snapshots.ToArray()
}

function Test-RecordIdentity {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)]$Record
  )

  $snapshot = @(Get-StudioSnapshots | Where-Object { $_.pid -eq [int]$Record.pid }) | Select-Object -First 1
  if ($null -eq $snapshot) {
    return [pscustomobject]@{ valid = $false; reason = 'process-not-running'; snapshot = $null }
  }

  $sameStart = [string]$snapshot.startTimeUtc -ceq [string]$Record.startTimeUtc
  $sameSession = [int]$snapshot.sessionId -eq [int]$Record.sessionId
  $samePath = [StringComparer]::OrdinalIgnoreCase.Equals([string]$snapshot.executablePath, [string]$Record.executablePath)
  $sameOwner = [string]$Record.ownershipId -ceq [string]$Manifest.ownershipId
  $sameLeaf = [System.IO.Path]::GetFileName([string]$snapshot.executablePath) -ceq $script:ExpectedExecutableLeaf
  $sameRootPath = [string]::IsNullOrWhiteSpace([string]$Manifest.executablePath) -or
    [StringComparer]::OrdinalIgnoreCase.Equals([string]$snapshot.executablePath, [string]$Manifest.executablePath)

  if (-not ($sameStart -and $sameSession -and $samePath -and $sameOwner -and $sameLeaf -and $sameRootPath)) {
    return [pscustomobject]@{ valid = $false; reason = 'identity-mismatch'; snapshot = $snapshot }
  }
  return [pscustomobject]@{ valid = $true; reason = $null; snapshot = $snapshot }
}

function Test-CloseWindowBinding {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)]$Record,
    [Parameter(Mandatory = $true)][IntPtr]$CachedMainWindowHandle
  )

  $identity = Test-RecordIdentity -Manifest $Manifest -Record $Record
  if (-not $identity.valid) {
    return [pscustomobject]@{ valid = $false; reason = "identity-$($identity.reason)"; handle = [IntPtr]::Zero }
  }
  try {
    $identity.snapshot.process.Refresh()
    $currentMainWindowHandle = [IntPtr]$identity.snapshot.process.MainWindowHandle
  } catch {
    return [pscustomobject]@{ valid = $false; reason = "main-window-refresh-failed: $($_.Exception.Message)"; handle = [IntPtr]::Zero }
  }
  if ($CachedMainWindowHandle -eq [IntPtr]::Zero) {
    return [pscustomobject]@{ valid = $false; reason = 'cached-main-window-handle-zero'; handle = [IntPtr]::Zero }
  }
  if ($currentMainWindowHandle -eq [IntPtr]::Zero) {
    return [pscustomobject]@{ valid = $false; reason = 'current-main-window-handle-zero'; handle = [IntPtr]::Zero }
  }
  if ($currentMainWindowHandle -ne $CachedMainWindowHandle) {
    return [pscustomobject]@{
      valid = $false
      reason = "main-window-handle-changed: cached=$($CachedMainWindowHandle.ToInt64()), current=$($currentMainWindowHandle.ToInt64())"
      handle = [IntPtr]::Zero
    }
  }
  if (-not [StudioSessionSafe]::IsWindow($currentMainWindowHandle)) {
    return [pscustomobject]@{ valid = $false; reason = 'main-window-handle-is-not-a-window'; handle = [IntPtr]::Zero }
  }
  $windowOwnerPid = [uint32]0
  $windowThreadId = [StudioSessionSafe]::GetWindowThreadProcessId($currentMainWindowHandle, [ref]$windowOwnerPid)
  if ($windowThreadId -eq 0 -or [int64]$windowOwnerPid -ne [int]$Record.pid) {
    return [pscustomobject]@{
      valid = $false
      reason = "main-window-owner-mismatch: thread=$windowThreadId, owner=$windowOwnerPid, expected=$($Record.pid)"
      handle = [IntPtr]::Zero
    }
  }
  return [pscustomobject]@{ valid = $true; reason = $null; handle = $currentMainWindowHandle }
}

function Get-OwnedRecord {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)][int]$ProcessId,
    [string]$RequiredRole
  )

  $ownedMatches = @($Manifest.ownedProcesses | Where-Object { [int]$_.pid -eq $ProcessId })
  if ($ownedMatches.Count -ne 1) {
    throw "PID $ProcessId is not uniquely owned by SessionFile '$script:SessionFilePath'."
  }
  $record = $ownedMatches[0]
  if ($RequiredRole -and [string]$record.role -cne $RequiredRole) {
    throw "PID $ProcessId has role '$($record.role)', expected '$RequiredRole'."
  }
  $identity = Test-RecordIdentity -Manifest $Manifest -Record $record
  if (-not $identity.valid) {
    throw "PID $ProcessId failed ownership validation: $($identity.reason)."
  }
  return [pscustomobject]@{ record = $record; snapshot = $identity.snapshot }
}

function Assert-EvidenceIdentifier {
  param(
    [Parameter(Mandatory = $true)]$Value,
    [Parameter(Mandatory = $true)][string]$Label
  )

  if ($Value -isnot [string] -or $Value.Length -lt 1 -or $Value.Length -gt 128) {
    throw "EvidenceFile $Label must be a string of 1..128 characters."
  }
  if ($Value -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$') {
    throw "EvidenceFile $Label contains forbidden characters."
  }
}

function Assert-EvidenceValueTree {
  param(
    $Value,
    [Parameter(Mandatory = $true)][string]$Label,
    [int]$Depth = 0
  )

  if ($Depth -gt 12) { throw "EvidenceFile $Label exceeds maximum nesting depth 12." }
  if ($null -eq $Value) { return }
  if ($Value -is [string]) {
    if ($Value.Length -gt 16384 -or $Value -match '[\x00-\x1F\x7F]') {
      throw "EvidenceFile $Label contains an overlong or control-character string."
    }
    return
  }
  if ($Value -is [pscustomobject]) {
    $properties = @($Value.PSObject.Properties)
    if ($properties.Count -gt 128) { throw "EvidenceFile $Label has too many properties." }
    foreach ($property in $properties) {
      if ($property.Name.Length -lt 1 -or $property.Name.Length -gt 128 -or
          $property.Name -match '[\x00-\x1F\x7F]') {
        throw "EvidenceFile $Label has an invalid property name."
      }
      $null = Assert-EvidenceValueTree -Value $property.Value -Label "$Label.$($property.Name)" -Depth ($Depth + 1)
    }
    return
  }
  if ($Value -is [System.Collections.IEnumerable]) {
    $items = @($Value)
    if ($items.Count -gt 1024) { throw "EvidenceFile $Label has too many array items." }
    for ($index = 0; $index -lt $items.Count; $index++) {
      $null = Assert-EvidenceValueTree -Value $items[$index] -Label "${Label}[$index]" -Depth ($Depth + 1)
    }
    return
  }
  if ($Value -isnot [bool] -and $Value -isnot [byte] -and $Value -isnot [int16] -and
      $Value -isnot [int] -and $Value -isnot [int64] -and $Value -isnot [single] -and
      $Value -isnot [double] -and $Value -isnot [decimal]) {
    throw "EvidenceFile $Label contains unsupported value type '$($Value.GetType().FullName)'."
  }
}

function Read-ValidatedEvidence {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)]$Record,
    [Parameter(Mandatory = $true)][string]$EvidencePath,
    [Parameter(Mandatory = $true)][string]$ExpectedSha256,
    [switch]$RequirePlace
  )

  # EvidenceFile must be produced independently by MCP/authoritative logging. This function
  # verifies its immutable bytes and identity bindings; it does not manufacture role evidence.
  $resolvedEvidence = Get-CanonicalExistingPath -Path $EvidencePath -Label 'EvidenceFile' -Leaf
  if (-not (Test-PathWithinRoot -Path $resolvedEvidence -Root $script:TrustedEvidenceRootPath)) {
    throw 'EvidenceFile must be a canonical descendant of TrustedEvidenceRoot.'
  }
  if ([System.IO.Path]::GetExtension($resolvedEvidence) -ine '.json') {
    throw 'EvidenceFile must be a JSON file.'
  }
  if ([StringComparer]::OrdinalIgnoreCase.Equals($resolvedEvidence, $script:SessionFilePath)) {
    throw 'EvidenceFile must not be the SessionFile itself.'
  }
  $evidenceBytes = [System.IO.File]::ReadAllBytes($resolvedEvidence)
  if ($evidenceBytes.Length -le 0 -or $evidenceBytes.Length -gt 1048576) {
    throw 'EvidenceFile size must be between 1 byte and 1 MiB.'
  }
  $expectedHash = $ExpectedSha256.ToLowerInvariant()
  $sha256 = [System.Security.Cryptography.SHA256]::Create()
  try {
    $actualHashBytes = $sha256.ComputeHash($evidenceBytes)
  } finally {
    $sha256.Dispose()
  }
  $actualHash = [BitConverter]::ToString($actualHashBytes).Replace('-', '').ToLowerInvariant()
  if ($actualHash -cne $expectedHash) {
    throw "EvidenceFile SHA-256 mismatch: expected $expectedHash, actual $actualHash."
  }

  try {
    $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $evidenceJson = $strictUtf8.GetString($evidenceBytes)
    if ($evidenceJson.Length -gt 0 -and $evidenceJson[0] -eq [char]0xFEFF) {
      $evidenceJson = $evidenceJson.Substring(1)
    }
    $convertFromJson = Get-Command -Name 'Microsoft.PowerShell.Utility\ConvertFrom-Json' -CommandType Cmdlet -ErrorAction Stop
    if ($convertFromJson.Parameters.ContainsKey('DateKind')) {
      $evidence = Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $evidenceJson -DateKind String
    } else {
      $evidence = Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $evidenceJson
    }
  } catch {
    throw "EvidenceFile is not strict UTF-8 JSON: $($_.Exception.Message)"
  }
  $null = Assert-EvidenceValueTree -Value $evidence -Label '$'
  foreach ($name in @(
    'schemaVersion', 'evidenceType', 'source', 'observedAtUtc', 'eventId', 'probeId',
    'verified', 'ownershipId', 'pid', 'startTimeUtc', 'sessionId', 'executablePath',
    'launchIntent', 'observedRole'
  )) {
    if ($evidence.PSObject.Properties.Name -notcontains $name) {
      throw "EvidenceFile is missing required property '$name'."
    }
  }

  if ($evidence.schemaVersion -isnot [int] -and $evidence.schemaVersion -isnot [long]) {
    throw 'EvidenceFile schemaVersion must be a JSON integer.'
  }
  if ([int64]$evidence.schemaVersion -ne 1) {
    throw 'EvidenceFile schemaVersion must be exactly 1.'
  }
  if ($evidence.evidenceType -isnot [string] -or
      [string]$evidence.evidenceType -cne 'roblox-studio-role-handshake') {
    throw "EvidenceFile evidenceType must be exactly 'roblox-studio-role-handshake'."
  }
  if ($evidence.source -isnot [string] -or
      [string]$evidence.source -cnotin @('studio-mcp', 'studio-log-handshake')) {
    throw "EvidenceFile source must be 'studio-mcp' or 'studio-log-handshake'."
  }
  Assert-EvidenceIdentifier -Value $evidence.eventId -Label 'eventId'
  Assert-EvidenceIdentifier -Value $evidence.probeId -Label 'probeId'
  if ($evidence.verified -isnot [bool] -or -not [bool]$evidence.verified) {
    throw 'EvidenceFile verified must be the JSON boolean true.'
  }

  if ($evidence.observedAtUtc -isnot [string] -or
      [string]$evidence.observedAtUtc -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$') {
    throw "EvidenceFile observedAtUtc must use strict UTC round-trip format yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'."
  }
  $observedAtUtc = ConvertFrom-StrictEvidenceUtc -Value ([string]$evidence.observedAtUtc) `
    -Label 'EvidenceFile observedAtUtc'
  $acquiredAtUtc = [datetime]::Parse([string]$Record.acquiredAtUtc).ToUniversalTime()
  Assert-EvidenceFreshness -ObservedAtUtc $observedAtUtc -AcquiredAtUtc $acquiredAtUtc `
    -NowUtc ([datetime]::UtcNow)

  if ($evidence.pid -isnot [int] -and $evidence.pid -isnot [long]) {
    throw 'EvidenceFile pid must be a JSON integer.'
  }
  if ($evidence.sessionId -isnot [int] -and $evidence.sessionId -isnot [long]) {
    throw 'EvidenceFile sessionId must be a JSON integer.'
  }
  foreach ($stringField in @('ownershipId', 'startTimeUtc', 'executablePath', 'launchIntent', 'observedRole')) {
    $value = $evidence.$stringField
    if ($value -isnot [string] -or $value.Length -lt 1 -or $value.Length -gt 2048 -or
        $value -match '[\x00-\x1F\x7F]') {
      throw "EvidenceFile $stringField must be a bounded non-control string."
    }
  }
  if ([string]$evidence.ownershipId -cne [string]$Manifest.ownershipId -or
      [int64]$evidence.pid -ne [int]$Record.pid -or
      [string]$evidence.startTimeUtc -cne [string]$Record.startTimeUtc -or
      [int64]$evidence.sessionId -ne [int]$Record.sessionId -or
      -not [StringComparer]::OrdinalIgnoreCase.Equals([string]$evidence.executablePath, [string]$Record.executablePath) -or
      [string]$evidence.launchIntent -cne [string]$Record.launchIntent -or
      [string]$evidence.observedRole -cne [string]$Record.launchIntent) {
    throw "EvidenceFile does not match the owned PID identity and launch-intent role for PID $($Record.pid)."
  }

  if ($evidence.PSObject.Properties.Name -contains 'details') {
    $detailsJson = $evidence.details | ConvertTo-Json -Depth 8 -Compress
    if ([string]::IsNullOrWhiteSpace($detailsJson) -or $detailsJson.Length -gt 16384) {
      throw 'EvidenceFile details must serialize to at most 16 KiB.'
    }
  }

  $hasObservedPlace = $evidence.PSObject.Properties.Name -contains 'observedPlaceSha256'
  $hasObservedBuild = $evidence.PSObject.Properties.Name -contains 'observedBuildSha256'
  if (($hasObservedPlace -and ($evidence.observedPlaceSha256 -isnot [string] -or
        [string]$evidence.observedPlaceSha256 -cne [string]$Manifest.placeSha256)) -or
      ($hasObservedBuild -and ($evidence.observedBuildSha256 -isnot [string] -or
        [string]$evidence.observedBuildSha256 -cne [string]$Manifest.placeSha256))) {
    throw 'EvidenceFile observed place/build SHA-256 contradicts the opened place artifact.'
  }
  if (-not $hasObservedPlace -and -not $hasObservedBuild) {
    throw 'Every role handshake requires observedPlaceSha256 or observedBuildSha256 matching the opened artifact.'
  }

  if ($RequirePlace) {
    if ([string]$Record.role -cne 'edit') {
      throw 'Place confirmation is only valid for the edit-role process.'
    }
  }

  return [pscustomobject]@{
    path     = $resolvedEvidence
    sha256   = $actualHash
    document = $evidence
    observedAtUtc = $observedAtUtc
    expiresAtUtc = $observedAtUtc.AddMinutes($script:EvidenceFreshnessMinutes).ToString('o')
  }
}

function Read-StrictCoordinatePngHeader {
  param([Parameter(Mandatory = $true)][System.IO.Stream]$Stream)

  if (-not $Stream.CanRead -or -not $Stream.CanSeek -or $Stream.Length -lt 33) {
    throw 'Coordinate evidence PNG is too short for a complete PNG signature and IHDR.'
  }
  $header = [byte[]]::new(33)
  $Stream.Position = 0
  $offset = 0
  while ($offset -lt $header.Length) {
    $read = $Stream.Read($header, $offset, $header.Length - $offset)
    if ($read -le 0) { throw 'Coordinate evidence PNG ended during its fixed header.' }
    $offset += $read
  }
  $signature = [byte[]](137, 80, 78, 71, 13, 10, 26, 10)
  for ($index = 0; $index -lt $signature.Length; $index++) {
    if ($header[$index] -ne $signature[$index]) {
      throw 'Coordinate evidence capture does not have the exact PNG signature.'
    }
  }
  if ($header[8] -ne 0 -or $header[9] -ne 0 -or $header[10] -ne 0 -or $header[11] -ne 13 -or
      $header[12] -ne 73 -or $header[13] -ne 72 -or $header[14] -ne 68 -or $header[15] -ne 82) {
    throw 'Coordinate evidence PNG must begin with one exact 13-byte IHDR chunk.'
  }

  [uint32]$width = ([uint32]$header[16] -shl 24) -bor ([uint32]$header[17] -shl 16) -bor `
    ([uint32]$header[18] -shl 8) -bor [uint32]$header[19]
  [uint32]$height = ([uint32]$header[20] -shl 24) -bor ([uint32]$header[21] -shl 16) -bor `
    ([uint32]$header[22] -shl 8) -bor [uint32]$header[23]
  $bitDepth = [int]$header[24]
  $colorType = [int]$header[25]
  $validDepths = switch ($colorType) {
    0 { @(1, 2, 4, 8, 16) }
    2 { @(8, 16) }
    3 { @(1, 2, 4, 8) }
    4 { @(8, 16) }
    6 { @(8, 16) }
    default { @() }
  }
  if ($validDepths -notcontains $bitDepth -or $header[26] -ne 0 -or
      $header[27] -ne 0 -or $header[28] -notin @(0, 1)) {
    throw 'Coordinate evidence PNG IHDR has an invalid color/bit-depth/compression/filter/interlace contract.'
  }
  if ($width -eq 0 -or $height -eq 0 -or
      $width -gt $script:MaxCoordinateCaptureDimension -or
      $height -gt $script:MaxCoordinateCaptureDimension -or
      ([uint64]$width * [uint64]$height) -gt [uint64]$script:MaxCoordinateCapturePixels) {
    throw "Coordinate evidence PNG IHDR dimensions are outside the bounded contract: ${width}x${height}."
  }

  [uint32]$crc = [uint32]::MaxValue
  for ($index = 12; $index -le 28; $index++) {
    $crc = [uint32]($crc -bxor [uint32]$header[$index])
    for ($bit = 0; $bit -lt 8; $bit++) {
      if (($crc -band 1) -ne 0) {
        $crc = [uint32](([uint32]($crc -shr 1)) -bxor [uint32]3988292384)
      } else {
        $crc = [uint32]($crc -shr 1)
      }
    }
  }
  $crc = [uint32]($crc -bxor [uint32]::MaxValue)
  [uint32]$storedCrc = ([uint32]$header[29] -shl 24) -bor ([uint32]$header[30] -shl 16) -bor `
    ([uint32]$header[31] -shl 8) -bor [uint32]$header[32]
  if ($crc -ne $storedCrc) {
    throw 'Coordinate evidence PNG IHDR CRC is invalid.'
  }
  $Stream.Position = 0
  return [pscustomobject]@{ width = [int]$width; height = [int]$height }
}

function Read-ValidatedCoordinateEvidence {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)]$Record,
    [Parameter(Mandatory = $true)]$Snapshot,
    [Parameter(Mandatory = $true)][System.Collections.IDictionary]$ExpectedPoints,
    [Parameter(Mandatory = $true)][string]$CoordinateEvidencePath,
    [Parameter(Mandatory = $true)][string]$ExpectedSha256
  )

  $resolvedEvidence = Get-CanonicalExistingPath -Path $CoordinateEvidencePath `
    -Label 'CoordinateEvidenceFile' -Leaf
  if (-not (Test-PathWithinRoot -Path $resolvedEvidence -Root $script:TrustedEvidenceRootPath)) {
    throw 'CoordinateEvidenceFile must be a canonical descendant of TrustedEvidenceRoot.'
  }
  if ([System.IO.Path]::GetExtension($resolvedEvidence) -ine '.json') {
    throw 'CoordinateEvidenceFile must be JSON.'
  }
  if ([StringComparer]::OrdinalIgnoreCase.Equals($resolvedEvidence, $script:SessionFilePath)) {
    throw 'CoordinateEvidenceFile must not be the SessionFile.'
  }
  $bytes = [System.IO.File]::ReadAllBytes($resolvedEvidence)
  if ($bytes.Length -le 0 -or $bytes.Length -gt 1048576) {
    throw 'CoordinateEvidenceFile size must be between 1 byte and 1 MiB.'
  }
  $hasher = [Security.Cryptography.SHA256]::Create()
  try { $actualHashBytes = $hasher.ComputeHash($bytes) } finally { $hasher.Dispose() }
  $actualHash = [BitConverter]::ToString($actualHashBytes).Replace('-', '').ToLowerInvariant()
  if ($actualHash -cne $ExpectedSha256.ToLowerInvariant()) {
    throw "CoordinateEvidenceFile SHA-256 mismatch: expected $($ExpectedSha256.ToLowerInvariant()), actual $actualHash."
  }
  try {
    $json = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    $convertFromJson = Get-Command -Name 'Microsoft.PowerShell.Utility\ConvertFrom-Json' -CommandType Cmdlet -ErrorAction Stop
    if ($convertFromJson.Parameters.ContainsKey('DateKind')) {
      $document = Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $json -DateKind String
    } else {
      $document = Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $json
    }
  } catch {
    throw "CoordinateEvidenceFile is not strict UTF-8 JSON: $($_.Exception.Message)"
  }
  $null = Assert-EvidenceValueTree -Value $document -Label '$'
  foreach ($name in @(
    'schemaVersion', 'evidenceType', 'source', 'observedAtUtc', 'eventId', 'probeId',
    'verified', 'runId', 'pid', 'startTimeUtc', 'sessionId', 'executablePath',
    'mainWindowHandle', 'capturePath', 'captureSha256', 'capturedAtUtc', 'points'
  )) {
    if ($document.PSObject.Properties.Name -notcontains $name) {
      throw "CoordinateEvidenceFile is missing required property '$name'."
    }
  }
  if (($document.schemaVersion -isnot [int] -and $document.schemaVersion -isnot [long]) -or
      [int64]$document.schemaVersion -ne 1) {
    throw 'CoordinateEvidenceFile schemaVersion must be the JSON integer 1.'
  }
  if ($document.evidenceType -isnot [string] -or
      [string]$document.evidenceType -cne 'roblox-studio-coordinate-measurement') {
    throw "CoordinateEvidenceFile evidenceType must be exactly 'roblox-studio-coordinate-measurement'."
  }
  if ($document.source -isnot [string] -or
      [string]$document.source -cnotin @('studio-mcp', 'operator-reviewed-capture')) {
    throw "CoordinateEvidenceFile source must be 'studio-mcp' or 'operator-reviewed-capture'."
  }
  if ($document.verified -isnot [bool] -or -not [bool]$document.verified) {
    throw 'CoordinateEvidenceFile verified must be the JSON boolean true.'
  }
  Assert-EvidenceIdentifier -Value $document.eventId -Label 'coordinate eventId'
  Assert-EvidenceIdentifier -Value $document.probeId -Label 'coordinate probeId'
  $observed = ConvertFrom-StrictEvidenceUtc -Value ([string]$document.observedAtUtc) `
    -Label 'CoordinateEvidenceFile observedAtUtc'
  $captured = ConvertFrom-StrictEvidenceUtc -Value ([string]$document.capturedAtUtc) `
    -Label 'CoordinateEvidenceFile capturedAtUtc'
  $now = [datetime]::UtcNow
  $acquired = [datetime]::Parse([string]$Record.acquiredAtUtc).ToUniversalTime()
  if ($captured -lt $acquired -or $captured -gt $observed -or
      $observed -gt $now.AddMinutes($script:EvidenceFutureSkewMinutes) -or
      $captured -lt $now.AddMinutes(-$script:CoordinateEvidenceFreshnessMinutes)) {
    throw "Coordinate evidence/capture must follow candidate acquisition, be ordered capturedAtUtc <= observedAtUtc, and be within the last $script:CoordinateEvidenceFreshnessMinutes minutes."
  }
  foreach ($numberField in @('pid', 'sessionId', 'mainWindowHandle')) {
    if ($document.$numberField -isnot [int] -and $document.$numberField -isnot [long]) {
      throw "CoordinateEvidenceFile $numberField must be a JSON integer."
    }
  }
  if ([string]$document.runId -cne [string]$Manifest.ownershipId -or
      [int64]$document.pid -ne [int]$Record.pid -or
      [string]$document.startTimeUtc -cne [string]$Record.startTimeUtc -or
      [int64]$document.sessionId -ne [int]$Record.sessionId -or
      -not [StringComparer]::OrdinalIgnoreCase.Equals(
        [string]$document.executablePath, [string]$Record.executablePath)) {
    throw 'CoordinateEvidenceFile does not match the session run and exact process identity.'
  }
  $Snapshot.process.Refresh()
  $currentMainWindow = [IntPtr]$Snapshot.process.MainWindowHandle
  if ($currentMainWindow -eq [IntPtr]::Zero -or
      [int64]$document.mainWindowHandle -ne $currentMainWindow.ToInt64() -or
      -not [StudioSessionSafe]::IsWindow($currentMainWindow)) {
    throw 'CoordinateEvidenceFile mainWindowHandle is zero, stale, or different from the current exact main HWND.'
  }
  [uint32]$windowOwnerPid = 0
  $windowThread = [StudioSessionSafe]::GetWindowThreadProcessId($currentMainWindow, [ref]$windowOwnerPid)
  if ($windowThread -eq 0 -or [int]$windowOwnerPid -ne [int]$Record.pid) {
    throw 'CoordinateEvidenceFile mainWindowHandle is not currently owned by the exact target PID.'
  }

  $capturePath = Get-CanonicalExistingPath -Path ([string]$document.capturePath) `
    -Label 'Coordinate evidence capturePath' -Leaf
  if (-not (Test-PathWithinRoot -Path $capturePath -Root $script:TrustedEvidenceRootPath) -or
      [System.IO.Path]::GetExtension($capturePath) -ine '.png') {
    throw 'Coordinate evidence capturePath must be a canonical PNG descendant of TrustedEvidenceRoot.'
  }
  if ($document.captureSha256 -isnot [string] -or
      [string]$document.captureSha256 -cnotmatch '^[0-9a-f]{64}$') {
    throw 'CoordinateEvidenceFile captureSha256 must be a lowercase SHA-256 digest.'
  }
  $captureItem = Get-Item -LiteralPath $capturePath -Force
  if ($captureItem.Length -le 0 -or $captureItem.Length -gt $script:MaxCoordinateCaptureBytes) {
    throw "Coordinate evidence capture PNG must be 1..$script:MaxCoordinateCaptureBytes bytes."
  }
  $captureStream = $null
  $captureImage = $null
  try {
    $captureStream = [System.IO.File]::Open(
      $capturePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::Read)
    if ($captureStream.Length -ne [int64]$captureItem.Length -or
        $captureStream.Length -le 0 -or
        $captureStream.Length -gt $script:MaxCoordinateCaptureBytes) {
      throw 'Coordinate evidence capture PNG length changed before its read lease was acquired.'
    }
    $pngHeader = Read-StrictCoordinatePngHeader -Stream $captureStream
    $captureHashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
    try {
      $captureStream.Position = 0
      $captureHash = [BitConverter]::ToString(
        $captureHashAlgorithm.ComputeHash($captureStream)).Replace('-', '').ToLowerInvariant()
    } finally {
      $captureHashAlgorithm.Dispose()
    }
    if ($captureHash -cne [string]$document.captureSha256) {
      throw 'Coordinate evidence capture PNG SHA-256 no longer matches.'
    }
    Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    $captureStream.Position = 0
    $captureImage = [Drawing.Image]::FromStream($captureStream, $true, $true)
    $captureWidth = [int]$captureImage.Width
    $captureHeight = [int]$captureImage.Height
    if ($captureImage.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Png.Guid -or
        $captureWidth -ne [int]$pngHeader.width -or
        $captureHeight -ne [int]$pngHeader.height) {
      throw 'Coordinate evidence capture is not a bounded valid PNG.'
    }
  } finally {
    if ($null -ne $captureImage) { $captureImage.Dispose() }
    if ($null -ne $captureStream) { $captureStream.Dispose() }
  }
  $currentRect = New-Object StudioSessionSafe+RECT
  if (-not [StudioSessionSafe]::GetWindowRect($currentMainWindow, [ref]$currentRect)) {
    throw 'Coordinate evidence target GetWindowRect failed.'
  }
  $currentWidth = [int]($currentRect.Right - $currentRect.Left)
  $currentHeight = [int]($currentRect.Bottom - $currentRect.Top)
  if ($currentWidth -ne $captureWidth -or $currentHeight -ne $captureHeight) {
    throw "Coordinate evidence capture dimensions ${captureWidth}x${captureHeight} do not match current exact main window ${currentWidth}x${currentHeight}."
  }

  if ($null -eq $document.points -or $document.points -isnot [psobject]) {
    throw 'CoordinateEvidenceFile points must be a JSON object.'
  }
  $actualPointNames = @($document.points.PSObject.Properties.Name)
  $expectedPointNames = @($ExpectedPoints.Keys)
  if ($actualPointNames.Count -ne $expectedPointNames.Count) {
    throw 'CoordinateEvidenceFile points does not have the exact required point set.'
  }
  foreach ($pointName in $expectedPointNames) {
    if ($actualPointNames -cnotcontains [string]$pointName) {
      throw "CoordinateEvidenceFile is missing exact point '$pointName'."
    }
    $point = $document.points.PSObject.Properties[[string]$pointName].Value
    $pointProperties = @($point.PSObject.Properties.Name)
    if ($pointProperties.Count -ne 2 -or $pointProperties -cnotcontains 'x' -or
        $pointProperties -cnotcontains 'y' -or
        ($point.x -isnot [int] -and $point.x -isnot [long]) -or
        ($point.y -isnot [int] -and $point.y -isnot [long]) -or
        [int64]$point.x -ne [int]$ExpectedPoints[$pointName].x -or
        [int64]$point.y -ne [int]$ExpectedPoints[$pointName].y -or
        [int64]$point.x -lt 0 -or [int64]$point.x -ge $captureWidth -or
        [int64]$point.y -lt 0 -or [int64]$point.y -ge $captureHeight) {
      throw "CoordinateEvidenceFile point '$pointName' does not exactly match the supplied X/Y."
    }
  }

  return [pscustomobject][ordered]@{
    path = $resolvedEvidence
    sha256 = $actualHash
    source = [string]$document.source
    eventId = [string]$document.eventId
    probeId = [string]$document.probeId
    observedAtUtc = [string]$document.observedAtUtc
    capturedAtUtc = [string]$document.capturedAtUtc
    expiresAtUtc = $captured.AddMinutes($script:CoordinateEvidenceFreshnessMinutes).ToString('o')
    capturePath = $capturePath
    captureSha256 = $captureHash
    captureWidth = $captureWidth
    captureHeight = $captureHeight
    mainWindowHandle = $currentMainWindow.ToInt64()
    points = $document.points
  }
}

function Test-RoleVerification {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)]$Record
  )

  if (-not [bool]$Record.roleVerified) {
    return [pscustomobject]@{ valid = $false; reason = 'role-not-confirmed'; expiresAtUtc = $null }
  }
  try {
    $validated = Read-ValidatedEvidence -Manifest $Manifest -Record $Record `
      -EvidencePath ([string]$Record.roleEvidencePath) `
      -ExpectedSha256 ([string]$Record.roleEvidenceSha256)
    Assert-EvidenceDocumentMatchesStoredMetadata -Document $validated.document `
      -ObservedAtUtc ([string]$Record.roleEvidenceObservedAtUtc) `
      -EventId ([string]$Record.roleEvidenceEventId) `
      -ProbeId ([string]$Record.roleEvidenceProbeId) -Label "Role PID $($Record.pid)"
    return [pscustomobject]@{ valid = $true; reason = $null; expiresAtUtc = $validated.expiresAtUtc }
  } catch {
    return [pscustomobject]@{ valid = $false; reason = "role-evidence-invalid: $($_.Exception.Message)"; expiresAtUtc = $null }
  }
}

function Test-PlaceVerification {
  param([Parameter(Mandatory = $true)]$Manifest)

  if (-not [bool]$Manifest.placeHandshakeVerified) {
    return [pscustomobject]@{ valid = $false; reason = 'place-not-confirmed'; expiresAtUtc = $null }
  }
  $editRecords = @($Manifest.ownedProcesses | Where-Object { [string]$_.role -ceq 'edit' })
  if ($editRecords.Count -ne 1) {
    return [pscustomobject]@{ valid = $false; reason = 'edit-record-not-unique'; expiresAtUtc = $null }
  }
  try {
    $validated = Read-ValidatedEvidence -Manifest $Manifest -Record $editRecords[0] `
      -EvidencePath ([string]$Manifest.placeEvidencePath) `
      -ExpectedSha256 ([string]$Manifest.placeEvidenceSha256) -RequirePlace
    Assert-EvidenceDocumentMatchesStoredMetadata -Document $validated.document `
      -ObservedAtUtc ([string]$Manifest.placeEvidenceObservedAtUtc) `
      -EventId ([string]$Manifest.placeEvidenceEventId) `
      -ProbeId ([string]$Manifest.placeEvidenceProbeId) -Label 'Place handshake'
    return [pscustomobject]@{ valid = $true; reason = $null; expiresAtUtc = $validated.expiresAtUtc }
  } catch {
    return [pscustomobject]@{ valid = $false; reason = "place-evidence-invalid: $($_.Exception.Message)"; expiresAtUtc = $null }
  }
}

function Get-ConfirmedClientTopology {
  param([Parameter(Mandatory = $true)]$Manifest)

  $clientRecords = @($Manifest.ownedProcesses | Where-Object {
    [string]$_.role -clike 'client:*'
  })
  $indices = [System.Collections.Generic.HashSet[int]]::new()
  $evidenceExpiries = [System.Collections.Generic.List[string]]::new()
  $maxIndex = 0
  foreach ($record in $clientRecords) {
    $match = [regex]::Match([string]$record.role, '^client:([1-8])$', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
    if (-not $match.Success) {
      throw "AddClients found an invalid client role '$($record.role)'; supported roles are client:1 through client:8."
    }
    $index = [int]$match.Groups[1].Value
    if (-not $indices.Add($index)) {
      throw "AddClients found duplicate client role index $index."
    }
    $verification = Test-RoleVerification -Manifest $Manifest -Record $record
    if (-not $verification.valid) {
      throw "AddClients requires every existing client candidate to be independently confirmed before another dispatch; PID $($record.pid) failed: $($verification.reason)."
    }
    $evidenceExpiries.Add([string]$verification.expiresAtUtc)
    if ($index -gt $maxIndex) { $maxIndex = $index }
  }
  $nextIndex = $maxIndex + 1
  return [pscustomobject]@{
    existingCount = $clientRecords.Count
    maxIndex      = $maxIndex
    nextIndex     = $nextIndex
    evidenceExpiresAtUtc = @($evidenceExpiries.ToArray())
  }
}

function Get-NextConfirmedClientIndex {
  param([Parameter(Mandatory = $true)]$Manifest)

  $topology = Get-ConfirmedClientTopology -Manifest $Manifest
  if ([int]$topology.nextIndex -gt 8) {
    throw 'AddClients cannot dispatch another client because the highest confirmed client role is already client:8.'
  }
  $nextRole = 'client:{0}' -f $topology.nextIndex
  if (@($Manifest.ownedProcesses | Where-Object { [string]$_.role -ceq $nextRole }).Count -ne 0) {
    throw "AddClients planned role '$nextRole' is already present in the manifest."
  }
  return [pscustomobject]@{
    existingCount = [int]$topology.existingCount
    nextIndex     = [int]$topology.nextIndex
    nextRole      = $nextRole
    clientEvidenceExpiresAtUtc = @($topology.evidenceExpiresAtUtc)
  }
}

function Assert-StartTopology {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)][int]$RequiredEditPid
  )

  $editRecords = @($Manifest.ownedProcesses | Where-Object { [string]$_.role -ceq 'edit' })
  $nonEditRecords = @($Manifest.ownedProcesses | Where-Object { [string]$_.role -cne 'edit' })
  if ($editRecords.Count -ne 1 -or [int]$editRecords[0].pid -ne $RequiredEditPid) {
    throw "Start requires exactly one owned edit record and it must be PID $RequiredEditPid."
  }
  if ($nonEditRecords.Count -ne 0) {
    $roles = @($nonEditRecords | ForEach-Object { [string]$_.role }) -join ', '
    throw "Start requires no existing server/client records; found: $roles. Clean up and reconcile the prior test session first."
  }
}

function Get-ConfirmedServer {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)][string]$Context
  )

  $serverRecords = @($Manifest.ownedProcesses | Where-Object { [string]$_.role -ceq 'server' })
  if ($serverRecords.Count -ne 1) {
    throw "$Context requires exactly one owned server record."
  }
  $server = Get-OwnedRecord -Manifest $Manifest -ProcessId ([int]$serverRecords[0].pid) -RequiredRole 'server'
  $verification = Test-RoleVerification -Manifest $Manifest -Record $server.record
  if (-not $verification.valid) {
    throw "$Context requires a confirmed server-role handshake: $($verification.reason)."
  }
  return [pscustomobject]@{
    record       = $server.record
    snapshot     = $server.snapshot
    verification = $verification
  }
}

function Assert-AllOwnedRecordsValid {
  param([Parameter(Mandatory = $true)]$Manifest)

  foreach ($record in @($Manifest.ownedProcesses)) {
    $identity = Test-RecordIdentity -Manifest $Manifest -Record $record
    if (-not $identity.valid) {
      throw "Owned PID $($record.pid) failed identity validation: $($identity.reason). Run Cleanup deliberately before continuing."
    }
  }
}

function Register-OwnedSnapshot {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)]$Snapshot,
    [Parameter(Mandatory = $true)][string]$Role
  )

  if (@($Manifest.ownedProcesses | Where-Object { [int]$_.pid -eq [int]$Snapshot.pid }).Count -ne 0) {
    throw "PID $($Snapshot.pid) is already present in the session manifest."
  }
  if ([System.IO.Path]::GetFileName([string]$Snapshot.executablePath) -cne $script:ExpectedExecutableLeaf) {
    throw "Refusing to own PID $($Snapshot.pid): executable is not $script:ExpectedExecutableLeaf."
  }

  if ([string]::IsNullOrWhiteSpace([string]$Manifest.executablePath)) {
    $Manifest.executablePath = [string]$Snapshot.executablePath
  } elseif (-not [StringComparer]::OrdinalIgnoreCase.Equals([string]$Manifest.executablePath, [string]$Snapshot.executablePath)) {
    throw "Refusing to mix Studio executables. Expected '$($Manifest.executablePath)', got '$($Snapshot.executablePath)'."
  }

  $record = [pscustomobject][ordered]@{
    pid            = [int]$Snapshot.pid
    startTimeUtc   = [string]$Snapshot.startTimeUtc
    sessionId      = [int]$Snapshot.sessionId
    executablePath = [string]$Snapshot.executablePath
    role           = $Role
    launchIntent   = $Role
    roleVerified   = $false
    roleEvidencePath = $null
    roleEvidenceSha256 = $null
    roleVerifiedAtUtc = $null
    roleEvidenceObservedAtUtc = $null
    roleEvidenceEventId = $null
    roleEvidenceProbeId = $null
    ownershipId    = [string]$Manifest.ownershipId
    acquiredAtUtc  = [datetime]::UtcNow.ToString('o')
  }
  $Manifest.ownedProcesses = @($Manifest.ownedProcesses) + @($record)
  return $record
}

function Wait-NewStudioSnapshot {
  param(
    [Parameter(Mandatory = $true)][int[]]$BeforePids,
    [Parameter(Mandatory = $true)][datetime]$TriggeredAtUtc,
    [Parameter(Mandatory = $true)][int]$RequiredSessionId,
    [string]$RequiredExecutablePath,
    [Parameter(Mandatory = $true)][string]$ExpectedRole
  )

  $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
  $stablePid = 0
  $stablePolls = 0
  while ([datetime]::UtcNow -lt $deadline) {
    $newSnapshots = @(Get-StudioSnapshots | Where-Object {
      $BeforePids -notcontains [int]$_.pid -and
      [int]$_.sessionId -eq $RequiredSessionId -and
      ([datetime]::Parse([string]$_.startTimeUtc).ToUniversalTime() -ge $TriggeredAtUtc.AddSeconds(-2))
    })

    if ($RequiredExecutablePath) {
      $newSnapshots = @($newSnapshots | Where-Object {
        [StringComparer]::OrdinalIgnoreCase.Equals([string]$_.executablePath, $RequiredExecutablePath)
      })
    }

    if ($newSnapshots.Count -gt 1) {
      throw "Ambiguous $ExpectedRole launch: $($newSnapshots.Count) new Studio PIDs appeared; none were added to the ownership manifest."
    }
    if ($newSnapshots.Count -eq 1) {
      if ($stablePid -eq [int]$newSnapshots[0].pid) {
        $stablePolls++
      } else {
        $stablePid = [int]$newSnapshots[0].pid
        $stablePolls = 1
      }
      if ($stablePolls -ge 3) {
        return $newSnapshots[0]
      }
    } else {
      $stablePid = 0
      $stablePolls = 0
    }
    Start-Sleep -Milliseconds 250
  }

  throw "Timed out after $TimeoutSeconds seconds waiting for one new Studio process for role '$ExpectedRole'. No PID was added to the ownership manifest."
}

function Get-VerifiedInputHelperSnapshot {
  param([Parameter(Mandatory = $true)]$Manifest)

  $currentScriptsRoot = Get-CanonicalExistingPath -Path $script:ScriptsRootPath `
    -Label 'Current skill scripts root'
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
      $currentScriptsRoot, [string]$Manifest.scriptsRoot)) {
    throw 'Input helper dispatch rejected because the skill scripts root identity changed.'
  }
  Assert-RootDisjointFromBoundaries -Root $currentScriptsRoot `
    -Label 'Current skill scripts root' -Boundaries $script:ScriptWriteBoundaries

  $fresh = Get-TrustedScriptSnapshot -Path ([string]$Manifest.inputScriptPath) `
    -Label 'studio_input.ps1 immediately before dispatch' -IncludeText
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
      [string]$fresh.path, [string]$Manifest.inputScriptPath) -or
      [string]$fresh.sha256 -cne [string]$Manifest.inputScriptSha256 -or
      [string]$fresh.fileIdentity -cne [string]$Manifest.inputScriptFileIdentity) {
    throw 'Input helper path/hash/file identity changed after the session manifest was created; no helper bytes were executed.'
  }

  try {
    $scriptBlock = [scriptblock]::Create([string]$fresh.text)
  } catch {
    throw "Verified studio_input.ps1 bytes could not be parsed: $($_.Exception.Message)"
  }
  return [pscustomobject][ordered]@{
    scriptBlock = $scriptBlock
    path = [string]$fresh.path
    sha256 = [string]$fresh.sha256
    fileIdentity = [string]$fresh.fileIdentity
    length = [int64]$fresh.length
  }
}

function Get-VerifiedCaptureHelperSnapshot {
  param([Parameter(Mandatory = $true)]$Manifest)

  $currentScriptsRoot = Get-CanonicalExistingPath -Path $script:ScriptsRootPath `
    -Label 'Current skill scripts root before capture'
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
      $currentScriptsRoot, [string]$Manifest.scriptsRoot)) {
    throw 'Capture helper dispatch rejected because the skill scripts root identity changed.'
  }
  Assert-RootDisjointFromBoundaries -Root $currentScriptsRoot `
    -Label 'Current skill scripts root before capture' -Boundaries $script:ScriptWriteBoundaries

  $fresh = Get-TrustedScriptSnapshot -Path ([string]$Manifest.captureScriptPath) `
    -Label 'studio_capture.ps1 immediately before dispatch' -IncludeText
  if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
      [string]$fresh.path, [string]$Manifest.captureScriptPath) -or
      [string]$fresh.sha256 -cne [string]$Manifest.captureScriptSha256 -or
      [string]$fresh.fileIdentity -cne [string]$Manifest.captureScriptFileIdentity) {
    throw 'Capture helper path/hash/file identity changed after the session manifest was created; no helper bytes were executed.'
  }
  try {
    $scriptBlock = [scriptblock]::Create([string]$fresh.text)
  } catch {
    throw "Verified studio_capture.ps1 bytes could not be parsed: $($_.Exception.Message)"
  }
  return [pscustomobject][ordered]@{
    scriptBlock = $scriptBlock
    path = [string]$fresh.path
    sha256 = [string]$fresh.sha256
    fileIdentity = [string]$fresh.fileIdentity
    length = [int64]$fresh.length
  }
}

function Invoke-StudioInput {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)]$TargetSnapshot,
    [Parameter(Mandatory = $true)][string]$Actions,
    [Parameter(Mandatory = $true)][string]$InputDeadlineUtc
  )

  $TargetPid = [int]$TargetSnapshot.pid

  if (-not $AllowOsInput) {
    throw 'OS input dispatch requires explicit -AllowOsInput.'
  }

  # Read the helper under a non-write-sharing handle, bind the exact bytes to the
  # manifest identity, and invoke that verified memory snapshot. Never execute a
  # mutable path after attestation: path-based invocation has a check/use race.
  $helper = Get-VerifiedInputHelperSnapshot -Manifest $Manifest
  $inputScriptBlock = $helper.scriptBlock

  try {
    $output = @(& $inputScriptBlock -ProcId $TargetPid `
      -ExpectedExecutablePath ([string]$TargetSnapshot.executablePath) `
      -ExpectedSessionId ([int]$TargetSnapshot.sessionId) `
      -ExpectedStartTimeUtc ([string]$TargetSnapshot.startTimeUtc) `
      -VerifiedHelperPath ([string]$helper.path) `
      -VerifiedHelperSha256 ([string]$helper.sha256) `
      -VerifiedHelperFileIdentity ([string]$helper.fileIdentity) `
      -VerifiedInMemoryDispatch `
      -InputDeadlineUtc $InputDeadlineUtc `
      -Actions $Actions -AllowOsInput -ErrorAction Stop)
  } catch {
    throw "studio_input.ps1 failed for PID ${TargetPid}: $($_.Exception.Message)"
  }
  if (-not $?) {
    throw "studio_input.ps1 returned failure for PID $TargetPid."
  }
  if ($output.Count -eq 0) {
    throw "studio_input.ps1 returned no result for PID $TargetPid."
  }
  foreach ($item in $output) {
    if ($null -ne $item -and $item.PSObject.Properties.Name -contains 'ok' -and -not [bool]$item.ok) {
      throw "studio_input.ps1 reported ok=false for PID $TargetPid."
    }
    if ($null -ne $item -and $item.PSObject.Properties.Name -contains 'Success' -and -not [bool]$item.Success) {
      throw "studio_input.ps1 reported Success=false for PID $TargetPid."
    }
  }
  return $output
}

function Invoke-StudioInputDryRun {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    [Parameter(Mandatory = $true)]$TargetSnapshot,
    [Parameter(Mandatory = $true)][string]$Actions,
    [Parameter(Mandatory = $true)][string]$InputDeadlineUtc
  )

  $targetPid = [int]$TargetSnapshot.pid
  $helper = Get-VerifiedInputHelperSnapshot -Manifest $Manifest
  $inputScriptBlock = $helper.scriptBlock
  try {
    $output = @(& $inputScriptBlock -ProcId $targetPid `
      -ExpectedExecutablePath ([string]$TargetSnapshot.executablePath) `
      -ExpectedSessionId ([int]$TargetSnapshot.sessionId) `
      -ExpectedStartTimeUtc ([string]$TargetSnapshot.startTimeUtc) `
      -VerifiedHelperPath ([string]$helper.path) `
      -VerifiedHelperSha256 ([string]$helper.sha256) `
      -VerifiedHelperFileIdentity ([string]$helper.fileIdentity) `
      -VerifiedInMemoryDispatch `
      -InputDeadlineUtc $InputDeadlineUtc `
      -Actions $Actions -DryRun -ErrorAction Stop)
  } catch {
    throw "studio_input.ps1 DryRun failed for PID ${targetPid}: $($_.Exception.Message)"
  }
  if (-not $? -or $output.Count -eq 0) {
    throw "studio_input.ps1 DryRun returned no successful result for PID $targetPid."
  }
  $structuredResults = @($output | Where-Object {
    $null -ne $_ -and $_.PSObject.Properties.Name -contains 'Success' -and
    $_.PSObject.Properties.Name -contains 'DryRun'
  })
  if ($structuredResults.Count -ne 1) {
    throw "studio_input.ps1 DryRun must return exactly one structured result for PID $targetPid."
  }
  if (-not [bool]$structuredResults[0].Success -or -not [bool]$structuredResults[0].DryRun) {
    throw "studio_input.ps1 DryRun returned an unsuccessful or non-DryRun result for PID $targetPid."
  }
  return $output
}

function Invoke-StudioCapture {
  param(
    [Parameter(Mandatory = $true)]$Manifest,
    $TargetSnapshot,
    [Parameter(Mandatory = $true)][bool]$FullScreenMode
  )

  $helper = Get-VerifiedCaptureHelperSnapshot -Manifest $Manifest
  $captureScriptBlock = $helper.scriptBlock
  $captureDryRun = [bool]$DryRun -or [bool]$WhatIfPreference
  $captureArguments = @{
    RepositoryRoot = $script:RepositoryRootPath
    TrustedEvidenceRoot = $script:TrustedEvidenceRootPath
    OutFile = $OutFile
    ExpectedScriptPath = [string]$helper.path
    ExpectedScriptSha256 = [string]$helper.sha256
    ExpectedScriptFileIdentity = [string]$helper.fileIdentity
    VerifiedInMemoryDispatch = $true
    Force = [bool]$CaptureForce
    DryRun = $captureDryRun
  }
  if ($FullScreenMode) {
    $captureArguments.FullScreen = $true
    $captureArguments.AllowFullScreenCapture = $true
    $captureArguments.FullScreenTimeoutSeconds = $FullScreenTimeoutSeconds
  } else {
    if ($null -eq $TargetSnapshot) { throw 'Window capture requires a verified target snapshot.' }
    $captureArguments.ProcId = [int]$TargetSnapshot.pid
    $captureArguments.ExpectedSessionId = [int]$TargetSnapshot.sessionId
    $captureArguments.ExpectedProcessName = $script:ExpectedProcessName
    $captureArguments.ExpectedExecutablePath = [string]$TargetSnapshot.executablePath
    $captureArguments.ExpectedStartTimeUtc = [string]$TargetSnapshot.startTimeUtc
    $captureArguments.RequireForeground = [bool]$RequireForeground
    $captureArguments.AllowMinimized = [bool]$AllowMinimized
    $captureArguments.PrintWindowTimeoutSeconds = $PrintWindowTimeoutSeconds
  }

  try {
    $rawOutput = @(& $captureScriptBlock @captureArguments -ErrorAction Stop)
  } catch {
    throw "studio_capture.ps1 failed: $($_.Exception.Message)"
  }
  $jsonOutput = @($rawOutput | Where-Object { $_ -is [string] -and -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($jsonOutput.Count -ne 1) {
    throw "studio_capture.ps1 must return exactly one JSON result; got $($jsonOutput.Count)."
  }
  try { $result = ConvertFrom-ManifestJsonStrict -Json ([string]$jsonOutput[0]) } catch {
    throw "studio_capture.ps1 returned invalid JSON: $($_.Exception.Message)"
  }
  foreach ($name in @(
      'Ok', 'Status', 'DryRun', 'Mode', 'OutFile', 'OutputWritten',
      'OutputSha256', 'OutputBytes', 'CapturedAtUtc',
      'RepositoryRoot', 'TrustedEvidenceRoot',
      'CaptureScriptPath', 'CaptureScriptSha256', 'CaptureScriptFileIdentity',
      'VerifiedInMemoryDispatch'
    )) {
    if ($result.PSObject.Properties.Name -notcontains $name) {
      throw "studio_capture.ps1 result is missing '$name'."
    }
  }
  if ($result.Ok -isnot [bool] -or -not [bool]$result.Ok -or
      $result.DryRun -isnot [bool] -or [bool]$result.DryRun -ne $captureDryRun -or
      $result.VerifiedInMemoryDispatch -isnot [bool] -or -not [bool]$result.VerifiedInMemoryDispatch -or
      [string]$result.CaptureScriptSha256 -cne [string]$helper.sha256 -or
      [string]$result.CaptureScriptFileIdentity -cne [string]$helper.fileIdentity -or
      -not [StringComparer]::OrdinalIgnoreCase.Equals(
        [string]$result.CaptureScriptPath, [string]$helper.path) -or
      -not [StringComparer]::OrdinalIgnoreCase.Equals(
        [string]$result.RepositoryRoot, $script:RepositoryRootPath) -or
      -not [StringComparer]::OrdinalIgnoreCase.Equals(
        [string]$result.TrustedEvidenceRoot, $script:TrustedEvidenceRootPath) -or
      -not [StringComparer]::OrdinalIgnoreCase.Equals([string]$result.OutFile, $OutFile) -or
      [string]$result.Mode -cne $(if ($FullScreenMode) { 'FullScreen' } else { 'Window' })) {
    throw 'studio_capture.ps1 result did not preserve the verified helper binding or DryRun contract.'
  }
  if ($result.OutputWritten -isnot [bool]) {
    throw 'studio_capture.ps1 OutputWritten must be a JSON boolean.'
  }
  if ($captureDryRun) {
    if ([string]$result.Status -cne 'Validated' -or [bool]$result.OutputWritten -or
        $null -ne $result.OutputSha256 -or $null -ne $result.OutputBytes -or
        $null -ne $result.CapturedAtUtc) {
      throw 'studio_capture.ps1 DryRun result falsely claimed a committed capture.'
    }
  } else {
    if ([string]$result.Status -cne 'Captured' -or -not [bool]$result.OutputWritten -or
        [string]$result.OutputSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [int64]$result.OutputBytes -le 0 -or [int64]$result.OutputBytes -gt 37748736L -or
        [string]::IsNullOrWhiteSpace([string]$result.CapturedAtUtc)) {
      throw 'studio_capture.ps1 actual result did not prove one bounded committed PNG.'
    }
    $null = ConvertFrom-StrictEvidenceUtc -Value ([string]$result.CapturedAtUtc) `
      -Label 'Capture result CapturedAtUtc'
    $committedCapturePath = Get-CanonicalExistingPath -Path ([string]$result.OutFile) `
      -Label 'Committed capture result' -Leaf
    if (-not (Test-PathWithinRoot -Path $committedCapturePath -Root $script:TrustedEvidenceRootPath) -or
        [System.IO.Path]::GetExtension($committedCapturePath) -ine '.png') {
      throw 'Committed capture result escaped TrustedEvidenceRoot or is not PNG.'
    }
    $committedCaptureItem = Get-Item -LiteralPath $committedCapturePath -Force -ErrorAction Stop
    $committedCaptureHash = Get-Sha256HexOfFile -Path $committedCapturePath `
      -Label 'Committed capture result'
    if ([int64]$committedCaptureItem.Length -ne [int64]$result.OutputBytes -or
        $committedCaptureHash -cne [string]$result.OutputSha256) {
      throw 'Committed capture result bytes/hash changed before session acceptance.'
    }
  }
  if ($FullScreenMode) {
    if ($result.PSObject.Properties.Name -notcontains 'PrivacyConsentAsserted' -or
        $result.PrivacyConsentAsserted -isnot [bool] -or
        -not [bool]$result.PrivacyConsentAsserted) {
      throw 'FullScreen capture result did not preserve explicit privacy consent.'
    }
  } else {
    foreach ($name in @('Pid', 'SessionId', 'ExecutablePath', 'ProcessStartTimeUtc')) {
      if ($result.PSObject.Properties.Name -notcontains $name) {
        throw "Window capture result is missing target identity field '$name'."
      }
    }
    if ([int]$result.Pid -ne [int]$TargetSnapshot.pid -or
        [int]$result.SessionId -ne [int]$TargetSnapshot.sessionId -or
        -not [StringComparer]::OrdinalIgnoreCase.Equals(
          [string]$result.ExecutablePath, [string]$TargetSnapshot.executablePath) -or
        [string]$result.ProcessStartTimeUtc -cne [string]$TargetSnapshot.startTimeUtc) {
      throw 'Window capture result target identity does not match the owned manifest snapshot.'
    }
  }
  return $result
}

function Get-MinimumInputEvidenceDeadline {
  param(
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$EvidenceExpiresAtUtc,
    [Parameter(Mandatory = $true)][string]$Context
  )

  $values = @($EvidenceExpiresAtUtc | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  if ($values.Count -eq 0) {
    throw "$Context has no independently verified evidence deadline."
  }

  $deadline = [datetime]::MaxValue
  foreach ($value in $values) {
    $parsed = ConvertFrom-StrictEvidenceUtc -Value ([string]$value) -Label "$Context evidence expiry"
    if ($parsed -lt $deadline) { $deadline = $parsed }
  }
  if ($deadline -le [datetime]::UtcNow) {
    throw "$Context evidence has already expired; refresh every required handshake before validating or dispatching input."
  }
  return $deadline.ToString('o')
}

function Get-WindowReport {
  param([Parameter(Mandatory = $true)][int]$ProcessId)

  $windows = [System.Collections.Generic.List[object]]::new()
  foreach ($handle in [StudioSessionSafe]::VisibleWindows([uint32]$ProcessId)) {
    $windows.Add([pscustomobject]@{
      handle = $handle.ToInt64()
      title  = [StudioSessionSafe]::TitleOf($handle)
    })
  }
  return $windows.ToArray()
}

function New-StructuredResult {
  param(
    [Parameter(Mandatory = $true)][bool]$Ok,
    [Parameter(Mandatory = $true)]$Data
  )

  [pscustomobject][ordered]@{
    ok             = $Ok
    action         = $Action
    dryRun         = [bool]$DryRun
    whatIf         = [bool]$WhatIfPreference
    sessionFile    = $script:SessionFilePath
    repositoryRoot = $script:RepositoryRootPath
    trustedEvidenceRoot = $script:TrustedEvidenceRootPath
    manifestSchemaVersion = $script:ManifestSchemaVersion
    pendingActionJournalSchemaVersion = $script:PendingActionJournalSchemaVersion
    pendingActionJournal = $script:PendingActionJournalStatus
    completedExternalAction = $script:CompletedExternalAction
    evidenceFreshnessMinutes = $script:EvidenceFreshnessMinutes
    coordinateEvidenceFreshnessMinutes = $script:CoordinateEvidenceFreshnessMinutes
    generatedAtUtc = [datetime]::UtcNow.ToString('o')
    data           = $Data
  }
}

Assert-CoordinateContracts
Assert-ActionParameterContracts

$sessionLockHashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
try {
  $sessionLockHashBytes = $sessionLockHashAlgorithm.ComputeHash(
    [System.Text.Encoding]::UTF8.GetBytes($script:SessionFilePath.ToUpperInvariant()))
  $sessionLockHash = [BitConverter]::ToString($sessionLockHashBytes).Replace('-', '').ToLowerInvariant()
} finally {
  $sessionLockHashAlgorithm.Dispose()
}
$sessionLockUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
if ($null -eq $sessionLockUserSid -or
    [string]$sessionLockUserSid.Value -cnotmatch '^S-1-(?:[0-9]+-){1,14}[0-9]+$') {
  throw 'Cannot establish a stable current-user SID for the cross-session SessionFile action lock.'
}
$sessionMutexName = "Global\RobloxMvpStudioSession_$($sessionLockUserSid.Value)_$sessionLockHash"
$sessionMutexSecurity = [System.Security.AccessControl.MutexSecurity]::new()
$sessionMutexSecurity.SetAccessRuleProtection($true, $false)
$sessionMutexSecurity.SetOwner($sessionLockUserSid)
$sessionMutexSecurity.AddAccessRule([System.Security.AccessControl.MutexAccessRule]::new(
  $sessionLockUserSid, [System.Security.AccessControl.MutexRights]::FullControl,
  [System.Security.AccessControl.AccessControlType]::Allow))
$sessionLockSystemSid = [System.Security.Principal.SecurityIdentifier]::new(
  [System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
$sessionMutexSecurity.AddAccessRule([System.Security.AccessControl.MutexAccessRule]::new(
  $sessionLockSystemSid, [System.Security.AccessControl.MutexRights]::FullControl,
  [System.Security.AccessControl.AccessControlType]::Allow))
$sessionMutexCreatedNew = $false
try {
  $sessionMutex = [System.Threading.Mutex]::new(
    $false, $sessionMutexName, [ref]$sessionMutexCreatedNew, $sessionMutexSecurity)
} catch {
  throw "Cannot create/open the required cross-session Global SessionFile action lock; local fallback is forbidden: $($_.Exception.Message)"
}
$sessionMutexAcquired = $false
try {
  try {
    $sessionMutexAcquired = $sessionMutex.WaitOne([TimeSpan]::FromSeconds(30))
  } catch [System.Threading.AbandonedMutexException] {
    # WaitOne grants the abandoned mutex to this thread. Release it in finally, but do
    # not continue because the prior action may have stopped between an OS effect and
    # its manifest update.
    $sessionMutexAcquired = $true
    throw 'The SessionFile action lock was abandoned. Session state may be incomplete; inspect owned processes/evidence manually before any retry.'
  }
  if (-not $sessionMutexAcquired) {
    throw 'Timed out after 30 seconds waiting for the SessionFile action lock. Another fresh-host action is still active; no action was dispatched.'
  }

  $script:PendingActionJournalStatus = Get-PendingActionJournalStatus
  $actualMutatingActions = @('Open', 'Confirm', 'Start', 'AddClients', 'Input', 'Capture', 'Cleanup')
  $isPlanOnlyInvocation = [bool]$DryRun -or [bool]$WhatIfPreference
  if ([bool]$script:PendingActionJournalStatus.exists -and
      $actualMutatingActions -contains $Action -and -not $isPlanOnlyInvocation) {
    $pendingActionLabel = if ($null -ne $script:PendingActionJournalStatus.document) {
      "action=$($script:PendingActionJournalStatus.document.action), actionId=$($script:PendingActionJournalStatus.document.actionId)"
    } else {
      [string]$script:PendingActionJournalStatus.reason
    }
    throw "A durable pending-action journal requires manual reconciliation before any actual mutation ($pendingActionLabel): $script:PendingActionJournalPath"
  }

switch ($Action) {
  'Preflight' {
    if (-not [string]::IsNullOrWhiteSpace($PlacePath)) {
      $preflightPlace = Get-CanonicalExistingPath -Path $PlacePath -Label 'PlacePath' -Leaf
      if (-not (Test-PathWithinRoot -Path $preflightPlace -Root $script:TrustedEvidenceRootPath)) {
        throw 'Preflight PlacePath must be a canonical descendant of TrustedEvidenceRoot.'
      }
      if ([System.IO.Path]::GetExtension($preflightPlace) -notin @('.rbxl', '.rbxlx')) {
        throw 'Preflight PlacePath must be a .rbxl or .rbxlx file.'
      }
      $preflightPlaceHash = Get-Sha256HexOfFile -Path $preflightPlace -Label 'Preflight PlacePath'
    } else {
      $preflightPlace = $null
      $preflightPlaceHash = $null
    }
    New-StructuredResult -Ok $true -Data ([pscustomobject]@{
      operation = 'validated-trust-boundary'
      repositoryRoot = $script:RepositoryRootPath
      repositoryAdministrationRoots = @($script:RepositoryAdministrationRoots)
      trustedEvidenceRoot = $script:TrustedEvidenceRootPath
      prospectiveSessionFile = $script:SessionFilePath
      pendingActionJournalPath = $script:PendingActionJournalPath
      pendingActionJournalSchemaVersion = $script:PendingActionJournalSchemaVersion
      approvedStudioExecutablePath = $script:ApprovedStudioExecutablePath
      approvedStudioVersionDirectory = $script:ApprovedStudioVersionDirectory
      executableSha256 = [string]$script:ApprovedStudioExecutableAttestation.sha256
      executableSignerSubject = [string]$script:ApprovedStudioExecutableAttestation.signerSubject
      executableSignerThumbprint = [string]$script:ApprovedStudioExecutableAttestation.signerThumbprint
      executableProductVersion = [string]$script:ApprovedStudioExecutableAttestation.productVersion
      scriptsRoot = $script:ScriptsRootPath
      sessionScriptPath = [string]$script:SessionScriptAttestation.path
      sessionScriptSha256 = [string]$script:SessionScriptAttestation.sha256
      sessionScriptFileIdentity = [string]$script:SessionScriptAttestation.fileIdentity
      inputScriptPath = [string]$script:InputScriptAttestation.path
      inputScriptSha256 = [string]$script:InputScriptAttestation.sha256
      inputScriptFileIdentity = [string]$script:InputScriptAttestation.fileIdentity
      captureScriptPath = [string]$script:CaptureScriptAttestation.path
      captureScriptSha256 = [string]$script:CaptureScriptAttestation.sha256
      captureScriptFileIdentity = [string]$script:CaptureScriptAttestation.fileIdentity
      placePath = $preflightPlace
      placeSha256 = $preflightPlaceHash
      sideEffectsPerformed = $false
      next = 'Provision a new unpredictable run directory inside TrustedEvidenceRoot with fail-if-exists semantics; copy the test artifact there, then call Open with paths under that directory.'
    })
  }

  'Open' {
    if ([string]::IsNullOrWhiteSpace($PlacePath)) {
      throw 'Open requires -PlacePath.'
    }
    $resolvedPlace = Get-CanonicalExistingPath -Path $PlacePath -Label 'PlacePath' -Leaf
    if (-not (Test-PathWithinRoot -Path $resolvedPlace -Root $script:TrustedEvidenceRootPath)) {
      throw 'PlacePath must be a canonical descendant of TrustedEvidenceRoot.'
    }
    if ([System.IO.Path]::GetExtension($resolvedPlace) -notin @('.rbxl', '.rbxlx')) {
      throw 'PlacePath must be a .rbxl or .rbxlx file.'
    }
    $placeHash = Get-Sha256HexOfFile -Path $resolvedPlace -Label 'Open PlacePath'
    $resolvedStudioExecutable = $script:ApprovedStudioExecutablePath
    $executableAttestation = $script:ApprovedStudioExecutableAttestation

    if (Test-Path -LiteralPath $script:SessionFilePath) {
      $priorManifest = Read-Manifest
      if (@($priorManifest.ownedProcesses).Count -ne 0) {
        throw 'Open requires a new or empty SessionFile; the existing manifest still owns processes.'
      }
    }
    $manifest = New-Manifest -ResolvedPlacePath $resolvedPlace -PlaceSha256 $placeHash `
      -ResolvedStudioExecutablePath $resolvedStudioExecutable `
      -ExecutableAttestation $executableAttestation `
      -ResolvedRepositoryRoot $script:RepositoryRootPath `
      -ResolvedTrustedEvidenceRoot $script:TrustedEvidenceRootPath

    if ($DryRun -or [bool]$WhatIfPreference) {
      New-StructuredResult -Ok $true -Data ([pscustomobject]@{
        operation   = $(if ([bool]$WhatIfPreference) { 'whatif-open-place' } else { 'would-open-place' })
        placePath   = $resolvedPlace
        placeSha256 = $placeHash
        executablePath = $resolvedStudioExecutable
        studioVersionDirectory = $script:ApprovedStudioVersionDirectory
        executableSha256 = [string]$executableAttestation.sha256
        executableSignerSubject = [string]$executableAttestation.signerSubject
        executableSignerThumbprint = [string]$executableAttestation.signerThumbprint
        executableProductVersion = [string]$executableAttestation.productVersion
        repositoryRoot = $script:RepositoryRootPath
        repositoryAdministrationRoots = @($script:RepositoryAdministrationRoots)
        trustedEvidenceRoot = $script:TrustedEvidenceRootPath
        scriptsRoot = $script:ScriptsRootPath
        sessionScriptPath = [string]$script:SessionScriptAttestation.path
        sessionScriptSha256 = [string]$script:SessionScriptAttestation.sha256
        sessionScriptFileIdentity = [string]$script:SessionScriptAttestation.fileIdentity
        inputScriptPath = [string]$script:InputScriptAttestation.path
        inputScriptSha256 = [string]$script:InputScriptAttestation.sha256
        inputScriptFileIdentity = [string]$script:InputScriptAttestation.fileIdentity
        captureScriptPath = [string]$script:CaptureScriptAttestation.path
        captureScriptSha256 = [string]$script:CaptureScriptAttestation.sha256
        captureScriptFileIdentity = [string]$script:CaptureScriptAttestation.fileIdentity
        manifestSchemaVersion = $script:ManifestSchemaVersion
        evidenceFreshnessMinutes = $script:EvidenceFreshnessMinutes
        ownershipId = $manifest.ownershipId
        placeHandshakeVerified = $false
      })
      break
    }

    Save-Manifest $manifest
    $studioWorkingDirectory = Get-CanonicalExistingPath `
      -Path (Split-Path -Parent $resolvedStudioExecutable) `
      -Label 'Studio executable working directory'
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals(
        $studioWorkingDirectory, $script:ApprovedStudioVersionDirectory)) {
      throw 'Studio executable working directory must remain canonical immediately before launch.'
    }
    Assert-RootDisjointFromBoundaries -Root $studioWorkingDirectory `
      -Label 'Studio executable working directory immediately before launch' `
      -Boundaries (@($script:ScriptWriteBoundaries) + @($script:ScriptsRootPath))
    Assert-StudioExecutableInventoryPath -CanonicalPath $resolvedStudioExecutable
    $prelaunchAttestation = Get-StudioExecutableAttestation -CanonicalPath $resolvedStudioExecutable
    Assert-StudioAttestationMatchesManifest -Manifest $manifest -Attestation $prelaunchAttestation
    $openJournal = New-PendingActionJournal -Manifest $manifest -TargetIntent (
      [pscustomobject][ordered]@{
        kind = 'launch-process'
        launchIntent = 'edit'
        executablePath = $resolvedStudioExecutable
        placePath = $resolvedPlace
        placeSha256 = $placeHash
      })
    $beforePids = @(Get-StudioSnapshots | ForEach-Object { [int]$_.pid })
    $triggeredAt = [datetime]::UtcNow
    $quotedPlaceArgument = '"{0}"' -f $resolvedPlace
    $launchProcess = Start-Process -FilePath $resolvedStudioExecutable `
      -WorkingDirectory $studioWorkingDirectory -ArgumentList $quotedPlaceArgument -PassThru
    $requiredSessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    $editSnapshot = Wait-NewStudioSnapshot -BeforePids $beforePids -TriggeredAtUtc $triggeredAt `
      -RequiredSessionId $requiredSessionId -RequiredExecutablePath $resolvedStudioExecutable -ExpectedRole 'edit'
    $postlaunchAttestation = Get-StudioExecutableAttestation -CanonicalPath ([string]$editSnapshot.executablePath)
    Assert-StudioAttestationMatchesManifest -Manifest $manifest -Attestation $postlaunchAttestation

    if ($null -ne $launchProcess -and $launchProcess.ProcessName -ceq $script:ExpectedProcessName -and
        [int]$launchProcess.Id -ne [int]$editSnapshot.pid) {
      throw "Start-Process returned Studio PID $($launchProcess.Id), but launch correlation found PID $($editSnapshot.pid); neither PID was added to the manifest."
    }

    $record = Register-OwnedSnapshot -Manifest $manifest -Snapshot $editSnapshot -Role 'edit'
    $openCompletion = Set-ManifestExternalActionCompletion -Manifest $manifest `
      -Journal $openJournal -ResultBinding ([pscustomobject][ordered]@{
        candidatePid = [int]$record.pid
        launchIntent = 'edit'
        startTimeUtc = [string]$record.startTimeUtc
        sessionId = [int]$record.sessionId
        executablePath = [string]$record.executablePath
        placeSha256 = $placeHash
      })
    Save-Manifest $manifest
    Complete-PendingActionJournal -Journal $openJournal
    New-StructuredResult -Ok $true -Data ([pscustomobject]@{
      ownershipId = $manifest.ownershipId
      process      = $record
      windows      = @(Get-WindowReport -ProcessId $record.pid)
      placePath    = $resolvedPlace
      placeSha256  = $placeHash
      externalActionCompletion = $openCompletion
      placeHandshakeVerified = $false
      titleContainsPlaceName = ([string]$editSnapshot.process.MainWindowTitle).IndexOf(
        [System.IO.Path]::GetFileNameWithoutExtension($resolvedPlace),
        [StringComparison]::OrdinalIgnoreCase
      ) -ge 0
      next         = 'Confirm the loaded place independently and record an MCP/log handshake; title observation alone is not proof. Confirm no modal dialog before OS input.'
    })
  }

  'Confirm' {
    if ($ConfirmPid -le 0) { throw 'Confirm requires -ConfirmPid.' }
    if ([string]::IsNullOrWhiteSpace($EvidenceFile)) { throw 'Confirm requires -EvidenceFile.' }
    if ([string]::IsNullOrWhiteSpace($EvidenceSha256)) { throw 'Confirm requires -EvidenceSha256.' }

    $manifest = Read-Manifest
    $owned = Get-OwnedRecord -Manifest $manifest -ProcessId $ConfirmPid
    $evidence = Read-ValidatedEvidence -Manifest $manifest -Record $owned.record `
      -EvidencePath $EvidenceFile -ExpectedSha256 $EvidenceSha256 -RequirePlace:$ConfirmPlace

    $sameRolePath = [bool]$owned.record.roleVerified -and
      [StringComparer]::OrdinalIgnoreCase.Equals(
        [string]$owned.record.roleEvidencePath, [string]$evidence.path)
    if ($sameRolePath -and
        [string]$owned.record.roleEvidenceSha256 -cne [string]$evidence.sha256) {
      throw 'Role evidence bytes changed at an existing audit path; refresh requires a new immutable file path.'
    }
    $sameRoleEvidence = $sameRolePath -and
      [string]$owned.record.roleEvidenceSha256 -ceq [string]$evidence.sha256
    $roleRefresh = [bool]$owned.record.roleVerified -and -not $sameRoleEvidence
    if ($roleRefresh) {
      Assert-NewerEvidenceRefresh -Document $evidence.document `
        -ExistingObservedAtUtc ([string]$owned.record.roleEvidenceObservedAtUtc) `
        -ExistingEventId ([string]$owned.record.roleEvidenceEventId) `
        -ExistingProbeId ([string]$owned.record.roleEvidenceProbeId) `
        -Label "PID $ConfirmPid role"
    }

    $samePlacePath = $ConfirmPlace -and [bool]$manifest.placeHandshakeVerified -and
      [StringComparer]::OrdinalIgnoreCase.Equals(
        [string]$manifest.placeEvidencePath, [string]$evidence.path)
    if ($samePlacePath -and
        [string]$manifest.placeEvidenceSha256 -cne [string]$evidence.sha256) {
      throw 'Place evidence bytes changed at an existing audit path; refresh requires a new immutable file path.'
    }
    $samePlaceEvidence = $samePlacePath -and
      [string]$manifest.placeEvidenceSha256 -ceq [string]$evidence.sha256
    $placeRefresh = $ConfirmPlace -and [bool]$manifest.placeHandshakeVerified -and -not $samePlaceEvidence
    if ($placeRefresh) {
      Assert-NewerEvidenceRefresh -Document $evidence.document `
        -ExistingObservedAtUtc ([string]$manifest.placeEvidenceObservedAtUtc) `
        -ExistingEventId ([string]$manifest.placeEvidenceEventId) `
        -ExistingProbeId ([string]$manifest.placeEvidenceProbeId) `
        -Label 'place handshake'
    }

    if ($DryRun -or [bool]$WhatIfPreference) {
      New-StructuredResult -Ok $true -Data ([pscustomobject]@{
        operation = $(if ([bool]$WhatIfPreference) { 'whatif-confirm-handshake' } else { 'would-confirm-handshake' })
        pid = $ConfirmPid
        role = [string]$owned.record.role
        launchIntent = [string]$owned.record.launchIntent
        evidencePath = [string]$evidence.path
        evidenceSha256 = [string]$evidence.sha256
        evidenceType = [string]$evidence.document.evidenceType
        source = [string]$evidence.document.source
        observedAtUtc = [string]$evidence.document.observedAtUtc
        eventId = [string]$evidence.document.eventId
        probeId = [string]$evidence.document.probeId
        observedRole = [string]$evidence.document.observedRole
        confirmPlace = [bool]$ConfirmPlace
        roleRefresh = [bool]$roleRefresh
        placeRefresh = [bool]$placeRefresh
        evidenceExpiresAtUtc = [string]$evidence.expiresAtUtc
        evidenceFreshnessMinutes = $script:EvidenceFreshnessMinutes
      })
      break
    }

    $verifiedAt = [datetime]::UtcNow.ToString('o')
    if (-not [bool]$owned.record.roleVerified -or $roleRefresh) {
      $owned.record.roleVerified = $true
      $owned.record.roleEvidencePath = [string]$evidence.path
      $owned.record.roleEvidenceSha256 = [string]$evidence.sha256
      $owned.record.roleVerifiedAtUtc = $verifiedAt
      $owned.record.roleEvidenceObservedAtUtc = [string]$evidence.document.observedAtUtc
      $owned.record.roleEvidenceEventId = [string]$evidence.document.eventId
      $owned.record.roleEvidenceProbeId = [string]$evidence.document.probeId
    }
    if ($ConfirmPlace -and (-not [bool]$manifest.placeHandshakeVerified -or $placeRefresh)) {
      $manifest.placeHandshakeVerified = $true
      $manifest.placeEvidencePath = [string]$evidence.path
      $manifest.placeEvidenceSha256 = [string]$evidence.sha256
      $manifest.placeVerifiedAtUtc = $verifiedAt
      $manifest.placeEvidenceObservedAtUtc = [string]$evidence.document.observedAtUtc
      $manifest.placeEvidenceEventId = [string]$evidence.document.eventId
      $manifest.placeEvidenceProbeId = [string]$evidence.document.probeId
    }
    Save-Manifest $manifest

    New-StructuredResult -Ok $true -Data ([pscustomobject]@{
      pid = $ConfirmPid
      role = [string]$owned.record.role
      launchIntent = [string]$owned.record.launchIntent
      roleVerified = $true
      evidencePath = [string]$evidence.path
      evidenceSha256 = [string]$evidence.sha256
      evidenceType = [string]$evidence.document.evidenceType
      source = [string]$evidence.document.source
      observedAtUtc = [string]$evidence.document.observedAtUtc
      eventId = [string]$evidence.document.eventId
      probeId = [string]$evidence.document.probeId
      observedRole = [string]$evidence.document.observedRole
      roleRefresh = [bool]$roleRefresh
      placeRefresh = [bool]$placeRefresh
      evidenceExpiresAtUtc = [string]$evidence.expiresAtUtc
      evidenceFreshnessMinutes = $script:EvidenceFreshnessMinutes
      placeHandshakeVerified = [bool]$manifest.placeHandshakeVerified
    })
  }

  'Start' {
    if ($EditPid -le 0) { throw 'Start requires -EditPid.' }
    $manifest = Read-Manifest
    Assert-AllOwnedRecordsValid $manifest
    Assert-StartTopology -Manifest $manifest -RequiredEditPid $EditPid
    $edit = Get-OwnedRecord -Manifest $manifest -ProcessId $EditPid -RequiredRole 'edit'
    $editVerification = Test-RoleVerification -Manifest $manifest -Record $edit.record
    if (-not $editVerification.valid) {
      throw "Start requires a confirmed edit-role handshake: $($editVerification.reason)."
    }
    $placeVerification = Test-PlaceVerification -Manifest $manifest
    if (-not $placeVerification.valid) {
      throw "Start requires a confirmed place handshake: $($placeVerification.reason)."
    }
    $startCoordinatePoints = [ordered]@{}
    if ($ViewportX -gt 0) {
      $startCoordinatePoints['viewport'] = [pscustomobject]@{ x = $ViewportX; y = $ViewportY }
    }
    if ($StartMenuX -gt 0) {
      $startCoordinatePoints['startMenu'] = [pscustomobject]@{ x = $StartMenuX; y = $StartMenuY }
      $startCoordinatePoints['startItem'] = [pscustomobject]@{ x = $StartItemX; y = $StartItemY }
    }
    $startCoordinateEvidence = if ($startCoordinatePoints.Count -gt 0) {
      Read-ValidatedCoordinateEvidence -Manifest $manifest -Record $edit.record `
        -Snapshot $edit.snapshot -ExpectedPoints $startCoordinatePoints `
        -CoordinateEvidencePath $CoordinateEvidenceFile `
        -ExpectedSha256 $CoordinateEvidenceSha256
    } else { $null }
    $useMenu = $StartMenuX -gt 0
    $viewportAction = if ($ViewportX -eq 0 -and $ViewportY -eq 0) { 'click' } else { "click:${ViewportX}:${ViewportY}" }
    $actions = if ($useMenu) {
      "${viewportAction},wait:600,click:${StartMenuX}:${StartMenuY},wait:1000,click:${StartItemX}:${StartItemY},wait:1500"
    } else {
      "${viewportAction},wait:600,press:${StartKey}:120"
    }
    $startEvidenceExpiries = @(
      [string]$editVerification.expiresAtUtc
      [string]$placeVerification.expiresAtUtc
      if ($null -ne $startCoordinateEvidence) { [string]$startCoordinateEvidence.expiresAtUtc }
    )
    $inputDeadlineUtc = Get-MinimumInputEvidenceDeadline `
      -EvidenceExpiresAtUtc $startEvidenceExpiries -Context 'Start input plan'

    if ($DryRun -or [bool]$WhatIfPreference) {
      $inputPlan = @(Invoke-StudioInputDryRun -Manifest $manifest -TargetSnapshot $edit.snapshot `
        -Actions $actions -InputDeadlineUtc $inputDeadlineUtc)
      New-StructuredResult -Ok $true -Data ([pscustomobject]@{
        operation = $(if ([bool]$WhatIfPreference) { 'whatif-start-server' } else { 'would-start-server' })
        editPid   = $EditPid
        inputMode = $(if ($useMenu) { 'menu' } else { 'shortcut' })
        actions   = $actions
        launchIntent = 'server'
        roleVerified = $false
        editRoleVerified = $true
        placeHandshakeVerified = $true
        coordinateEvidence = $startCoordinateEvidence
        inputEvidenceDeadlineUtc = $inputDeadlineUtc
        inputPlan = $inputPlan
      })
      break
    }

    if (-not $AllowOsInput) {
      throw 'Start actual execution requires explicit -AllowOsInput.'
    }

    # Re-read identity and independent evidence immediately before establishing the
    # launch-difference baseline. A prior successful gate is not reusable here.
    $manifest = Read-Manifest
    Assert-AllOwnedRecordsValid $manifest
    Assert-StartTopology -Manifest $manifest -RequiredEditPid $EditPid
    $edit = Get-OwnedRecord -Manifest $manifest -ProcessId $EditPid -RequiredRole 'edit'
    $editVerification = Test-RoleVerification -Manifest $manifest -Record $edit.record
    if (-not $editVerification.valid) {
      throw "Edit role evidence became invalid before server input: $($editVerification.reason)."
    }
    $placeVerification = Test-PlaceVerification -Manifest $manifest
    if (-not $placeVerification.valid) {
      throw "Place evidence became invalid before server input: $($placeVerification.reason)."
    }
    $startCoordinateEvidence = if ($startCoordinatePoints.Count -gt 0) {
      Read-ValidatedCoordinateEvidence -Manifest $manifest -Record $edit.record `
        -Snapshot $edit.snapshot -ExpectedPoints $startCoordinatePoints `
        -CoordinateEvidencePath $CoordinateEvidenceFile `
        -ExpectedSha256 $CoordinateEvidenceSha256
    } else { $null }
    $startEvidenceExpiries = @(
      [string]$editVerification.expiresAtUtc
      [string]$placeVerification.expiresAtUtc
      if ($null -ne $startCoordinateEvidence) { [string]$startCoordinateEvidence.expiresAtUtc }
    )
    $inputDeadlineUtc = Get-MinimumInputEvidenceDeadline `
      -EvidenceExpiresAtUtc $startEvidenceExpiries -Context 'Start input dispatch'
    $inputPlan = @(Invoke-StudioInputDryRun -Manifest $manifest -TargetSnapshot $edit.snapshot `
      -Actions $actions -InputDeadlineUtc $inputDeadlineUtc)
    $startJournal = New-PendingActionJournal -Manifest $manifest -TargetIntent (
      [pscustomobject][ordered]@{
        kind = 'os-input-spawn'
        sourcePid = [int]$EditPid
        sourceRole = 'edit'
        launchIntent = 'server'
        inputActionsSha256 = Get-Sha256HexOfUtf8String -Value $actions
        inputEvidenceDeadlineUtc = $inputDeadlineUtc
      })
    $beforePids = @(Get-StudioSnapshots | ForEach-Object { [int]$_.pid })
    $triggeredAt = [datetime]::UtcNow
    $dispatch = @(Invoke-StudioInput -Manifest $manifest -TargetSnapshot $edit.snapshot `
      -Actions $actions -InputDeadlineUtc $inputDeadlineUtc)
    $serverSnapshot = Wait-NewStudioSnapshot -BeforePids $beforePids -TriggeredAtUtc $triggeredAt `
      -RequiredSessionId ([int]$edit.snapshot.sessionId) `
      -RequiredExecutablePath ([string]$edit.snapshot.executablePath) -ExpectedRole 'server'
    $serverAttestation = Get-StudioExecutableAttestation -CanonicalPath ([string]$serverSnapshot.executablePath)
    Assert-StudioAttestationMatchesManifest -Manifest $manifest -Attestation $serverAttestation
    $record = Register-OwnedSnapshot -Manifest $manifest -Snapshot $serverSnapshot -Role 'server'
    $startCompletion = Set-ManifestExternalActionCompletion -Manifest $manifest `
      -Journal $startJournal -ResultBinding ([pscustomobject][ordered]@{
        candidatePid = [int]$record.pid
        launchIntent = 'server'
        parentEditPid = [int]$EditPid
        startTimeUtc = [string]$record.startTimeUtc
        sessionId = [int]$record.sessionId
        executablePath = [string]$record.executablePath
        inputActionsSha256 = Get-Sha256HexOfUtf8String -Value $actions
      })
    Save-Manifest $manifest
    Complete-PendingActionJournal -Journal $startJournal

    New-StructuredResult -Ok $true -Data ([pscustomobject]@{
      candidateProcess = $record
      launchIntent  = 'server'
      roleVerified  = $false
      inputDispatch = $dispatch
      inputPlan     = $inputPlan
      inputEvidenceDeadlineUtc = $inputDeadlineUtc
      coordinateEvidence = $startCoordinateEvidence
      externalActionCompletion = $startCompletion
      parentEditPid = $EditPid
      next           = 'Verify the server role with an independent MCP/log handshake before relying on it.'
    })
  }

  'AddClients' {
    if ($ServerPid -le 0) { throw 'AddClients requires -ServerPid.' }
    $manifest = Read-Manifest
    Assert-AllOwnedRecordsValid $manifest
    $server = Get-OwnedRecord -Manifest $manifest -ProcessId $ServerPid -RequiredRole 'server'
    $serverVerification = Test-RoleVerification -Manifest $manifest -Record $server.record
    if (-not $serverVerification.valid) {
      throw "AddClients requires a confirmed server-role handshake: $($serverVerification.reason)."
    }
    $placeVerification = Test-PlaceVerification -Manifest $manifest
    if (-not $placeVerification.valid) {
      throw "AddClients requires a confirmed place handshake: $($placeVerification.reason)."
    }
    $clientCoordinatePoints = [ordered]@{
      testMenu = [pscustomobject]@{ x = $TestMenuX; y = $TestMenuY }
      addClient = [pscustomobject]@{ x = $AddClientX; y = $AddClientY }
    }
    $clientCoordinateEvidence = Read-ValidatedCoordinateEvidence -Manifest $manifest `
      -Record $server.record -Snapshot $server.snapshot `
      -ExpectedPoints $clientCoordinatePoints `
      -CoordinateEvidencePath $CoordinateEvidenceFile `
      -ExpectedSha256 $CoordinateEvidenceSha256
    $clientPlan = Get-NextConfirmedClientIndex -Manifest $manifest
    $actions = "click:${TestMenuX}:${TestMenuY},wait:1000,click:${AddClientX}:${AddClientY},wait:1500"
    $clientEvidenceExpiries = @(
      [string]$serverVerification.expiresAtUtc
      [string]$placeVerification.expiresAtUtc
      [string]$clientCoordinateEvidence.expiresAtUtc
      @($clientPlan.clientEvidenceExpiresAtUtc)
    )
    $inputDeadlineUtc = Get-MinimumInputEvidenceDeadline `
      -EvidenceExpiresAtUtc $clientEvidenceExpiries -Context 'AddClients input plan'

    if ($DryRun -or [bool]$WhatIfPreference) {
      $inputPlan = @(Invoke-StudioInputDryRun -Manifest $manifest -TargetSnapshot $server.snapshot `
        -Actions $actions -InputDeadlineUtc $inputDeadlineUtc)
      New-StructuredResult -Ok $true -Data ([pscustomobject]@{
        operation = $(if ([bool]$WhatIfPreference) { 'whatif-add-clients' } else { 'would-add-clients' })
        serverPid = $ServerPid
        clients   = $Clients
        actions   = $actions
        launchIntent = 'client'
        roleVerified = $false
        serverRoleVerified = $true
        placeHandshakeVerified = $true
        existingClientsVerified = $clientPlan.existingCount
        plannedRole = $clientPlan.nextRole
        coordinateEvidence = $clientCoordinateEvidence
        inputEvidenceDeadlineUtc = $inputDeadlineUtc
        inputPlan = $inputPlan
      })
      break
    }

    if (-not $AllowOsInput) {
      throw 'AddClients actual execution requires explicit -AllowOsInput.'
    }

    # Re-read every identity and evidence file immediately before the one allowed
    # dispatch. The returned candidate must be Confirmed externally before the next call.
    $manifest = Read-Manifest
    Assert-AllOwnedRecordsValid $manifest
    $server = Get-OwnedRecord -Manifest $manifest -ProcessId $ServerPid -RequiredRole 'server'
    $serverVerification = Test-RoleVerification -Manifest $manifest -Record $server.record
    if (-not $serverVerification.valid) {
      throw "Server role evidence became invalid before client input: $($serverVerification.reason)."
    }
    $clientPlan = Get-NextConfirmedClientIndex -Manifest $manifest
    $role = [string]$clientPlan.nextRole
    $placeVerification = Test-PlaceVerification -Manifest $manifest
    if (-not $placeVerification.valid) {
      throw "Place evidence became invalid before client input: $($placeVerification.reason)."
    }
    $clientCoordinateEvidence = Read-ValidatedCoordinateEvidence -Manifest $manifest `
      -Record $server.record -Snapshot $server.snapshot `
      -ExpectedPoints $clientCoordinatePoints `
      -CoordinateEvidencePath $CoordinateEvidenceFile `
      -ExpectedSha256 $CoordinateEvidenceSha256
    $clientEvidenceExpiries = @(
      [string]$serverVerification.expiresAtUtc
      [string]$placeVerification.expiresAtUtc
      [string]$clientCoordinateEvidence.expiresAtUtc
      @($clientPlan.clientEvidenceExpiresAtUtc)
    )
    $inputDeadlineUtc = Get-MinimumInputEvidenceDeadline `
      -EvidenceExpiresAtUtc $clientEvidenceExpiries -Context 'AddClients input dispatch'
    $inputPlan = @(Invoke-StudioInputDryRun -Manifest $manifest -TargetSnapshot $server.snapshot `
      -Actions $actions -InputDeadlineUtc $inputDeadlineUtc)
    $addClientJournal = New-PendingActionJournal -Manifest $manifest -TargetIntent (
      [pscustomobject][ordered]@{
        kind = 'os-input-spawn'
        sourcePid = [int]$ServerPid
        sourceRole = 'server'
        launchIntent = $role
        inputActionsSha256 = Get-Sha256HexOfUtf8String -Value $actions
        inputEvidenceDeadlineUtc = $inputDeadlineUtc
      })
    $beforePids = @(Get-StudioSnapshots | ForEach-Object { [int]$_.pid })
    $triggeredAt = [datetime]::UtcNow
    $dispatch = @(Invoke-StudioInput -Manifest $manifest -TargetSnapshot $server.snapshot `
      -Actions $actions -InputDeadlineUtc $inputDeadlineUtc)
    $clientSnapshot = Wait-NewStudioSnapshot -BeforePids $beforePids -TriggeredAtUtc $triggeredAt `
      -RequiredSessionId ([int]$server.snapshot.sessionId) `
      -RequiredExecutablePath ([string]$server.snapshot.executablePath) -ExpectedRole 'client'
    $clientAttestation = Get-StudioExecutableAttestation -CanonicalPath ([string]$clientSnapshot.executablePath)
    Assert-StudioAttestationMatchesManifest -Manifest $manifest -Attestation $clientAttestation
    $record = Register-OwnedSnapshot -Manifest $manifest -Snapshot $clientSnapshot -Role $role
    $addClientCompletion = Set-ManifestExternalActionCompletion -Manifest $manifest `
      -Journal $addClientJournal -ResultBinding ([pscustomobject][ordered]@{
        candidatePid = [int]$record.pid
        launchIntent = $role
        parentServerPid = [int]$ServerPid
        startTimeUtc = [string]$record.startTimeUtc
        sessionId = [int]$record.sessionId
        executablePath = [string]$record.executablePath
        inputActionsSha256 = Get-Sha256HexOfUtf8String -Value $actions
      })
    Save-Manifest $manifest
    Complete-PendingActionJournal -Journal $addClientJournal

    New-StructuredResult -Ok $true -Data ([pscustomobject]@{
      serverPid       = $ServerPid
      candidateProcess = $record
      candidateProcesses = @($record)
      launchIntent    = 'client'
      roleVerified    = $false
      inputDispatch   = $dispatch
      inputDispatches = @([pscustomobject]@{ index = 1; output = $dispatch })
      inputPlan       = $inputPlan
      inputEvidenceDeadlineUtc = $inputDeadlineUtc
      coordinateEvidence = $clientCoordinateEvidence
      externalActionCompletion = $addClientCompletion
      next            = 'Confirm this one client with independent MCP/log evidence before calling AddClients again. Process creation alone is not acceptance evidence.'
    })
  }

  'Input' {
    if ($TargetPid -le 0) { throw 'Input requires -TargetPid.' }
    if ([string]::IsNullOrWhiteSpace($InputActions)) { throw 'Input requires -InputActions.' }
    $planOnly = [bool]$DryRun -or [bool]$WhatIfPreference
    if (-not $planOnly -and -not $AllowOsInput) {
      throw 'Input actual execution requires explicit -AllowOsInput.'
    }

    # Keep this gate immediately adjacent to the helper call. Do not reuse an earlier
    # verification result: evidence files and PID identity are re-read for every dispatch.
    $manifest = Read-Manifest
    Assert-AllOwnedRecordsValid $manifest
    $target = Get-OwnedRecord -Manifest $manifest -ProcessId $TargetPid
    if ([string]$target.record.launchIntent -cnotmatch '^client:[1-8]$') {
      throw "Input target PID $TargetPid must have a client:* launchIntent."
    }
    $targetRoleVerification = Test-RoleVerification -Manifest $manifest -Record $target.record
    if (-not $targetRoleVerification.valid) {
      throw "Input requires a confirmed client-role handshake: $($targetRoleVerification.reason)."
    }
    $server = Get-ConfirmedServer -Manifest $manifest -Context 'Input'
    $clientTopology = Get-ConfirmedClientTopology -Manifest $manifest
    $inputPlaceVerification = Test-PlaceVerification -Manifest $manifest
    if (-not $inputPlaceVerification.valid) {
      throw "Input requires a confirmed place handshake: $($inputPlaceVerification.reason)."
    }
    $inputEvidenceExpiries = @(
      [string]$targetRoleVerification.expiresAtUtc
      [string]$server.verification.expiresAtUtc
      [string]$inputPlaceVerification.expiresAtUtc
      @($clientTopology.evidenceExpiresAtUtc)
    )
    $inputDeadlineUtc = Get-MinimumInputEvidenceDeadline `
      -EvidenceExpiresAtUtc $inputEvidenceExpiries -Context 'Client Input plan'
    $inputResult = @(Invoke-StudioInputDryRun -Manifest $manifest -TargetSnapshot $target.snapshot `
      -Actions $InputActions -InputDeadlineUtc $inputDeadlineUtc)

    if ($planOnly) {
      New-StructuredResult -Ok $true -Data ([pscustomobject]@{
        operation = $(if ([bool]$WhatIfPreference) { 'whatif-validate-client-input-plan' } else { 'validated-client-input-plan' })
        targetPid = $TargetPid
        serverPid = [int]$server.record.pid
        launchIntent = [string]$target.record.launchIntent
        roleVerified = $true
        serverRoleVerified = $true
        confirmedClientCount = [int]$clientTopology.existingCount
        placeHandshakeVerified = $true
        osInputDispatched = $false
        inputEvidenceDeadlineUtc = $inputDeadlineUtc
        inputResult = $inputResult
      })
      break
    }

    $inputPlan = $inputResult
    $inputJournal = New-PendingActionJournal -Manifest $manifest -TargetIntent (
      [pscustomobject][ordered]@{
        kind = 'os-input'
        targetPid = [int]$TargetPid
        targetRole = [string]$target.record.launchIntent
        serverPid = [int]$server.record.pid
        inputActionsSha256 = Get-Sha256HexOfUtf8String -Value $InputActions
        inputEvidenceDeadlineUtc = $inputDeadlineUtc
      })
    $inputResult = @(Invoke-StudioInput -Manifest $manifest -TargetSnapshot $target.snapshot `
      -Actions $InputActions -InputDeadlineUtc $inputDeadlineUtc)
    $inputCompletion = Set-ManifestExternalActionCompletion -Manifest $manifest `
      -Journal $inputJournal -ResultBinding ([pscustomobject][ordered]@{
        targetPid = [int]$TargetPid
        targetRole = [string]$target.record.launchIntent
        serverPid = [int]$server.record.pid
        osInputDispatched = $true
        helperResultCount = [int]$inputResult.Count
        inputActionsSha256 = Get-Sha256HexOfUtf8String -Value $InputActions
      })
    Save-Manifest $manifest
    Complete-PendingActionJournal -Journal $inputJournal
    New-StructuredResult -Ok $true -Data ([pscustomobject]@{
      operation = 'dispatched-client-input'
      targetPid = $TargetPid
      serverPid = [int]$server.record.pid
      launchIntent = [string]$target.record.launchIntent
      roleVerified = $true
      serverRoleVerified = $true
      confirmedClientCount = [int]$clientTopology.existingCount
      placeHandshakeVerified = $true
      osInputDispatched = $true
      inputEvidenceDeadlineUtc = $inputDeadlineUtc
      inputPlan = $inputPlan
      inputResult = $inputResult
      externalActionCompletion = $inputCompletion
    })
  }

  'Capture' {
    # Capture is deliberately session-only. The helper is never path-executed: this
    # action verifies manifest authority, then dispatches one attested memory snapshot.
    $manifest = Read-Manifest
    $captureTarget = $null
    $captureRoleVerification = $null
    $capturePlaceVerification = $null
    $captureEvidenceDeadlineUtc = $null
    if (-not $FullScreen) {
      Assert-AllOwnedRecordsValid $manifest
      $captureTarget = Get-OwnedRecord -Manifest $manifest -ProcessId $TargetPid
      $captureRoleVerification = Test-RoleVerification -Manifest $manifest -Record $captureTarget.record
      if (-not $captureRoleVerification.valid) {
        throw "Window Capture requires a fresh confirmed owned-role handshake: $($captureRoleVerification.reason)."
      }
      $capturePlaceVerification = Test-PlaceVerification -Manifest $manifest
      if (-not $capturePlaceVerification.valid) {
        throw "Window Capture requires a fresh confirmed place handshake: $($capturePlaceVerification.reason)."
      }
      $captureEvidenceDeadlineUtc = Get-MinimumInputEvidenceDeadline `
        -EvidenceExpiresAtUtc @(
          [string]$captureRoleVerification.expiresAtUtc,
          [string]$capturePlaceVerification.expiresAtUtc
        ) -Context 'Window Capture'
      $captureDeadline = ConvertFrom-StrictEvidenceUtc -Value $captureEvidenceDeadlineUtc `
        -Label 'Window Capture evidence expiry'
      $captureBudgetSeconds = [int64]$PrintWindowTimeoutSeconds + 30L
      if ([datetime]::UtcNow.AddSeconds($captureBudgetSeconds) -ge $captureDeadline) {
        throw "Window Capture cannot finish inside the evidence window; refresh role/place evidence (budget=${captureBudgetSeconds}s, expiry=$captureEvidenceDeadlineUtc)."
      }
    }

    $captureOutputIntentPath = Get-CanonicalProspectiveFilePath `
      -Path $OutFile -Label 'Capture OutFile'
    if (-not [StringComparer]::OrdinalIgnoreCase.Equals($captureOutputIntentPath, $OutFile) -or
        -not (Test-PathWithinRoot `
          -Path $captureOutputIntentPath -Root $script:TrustedEvidenceRootPath) -or
        [System.IO.Path]::GetExtension($captureOutputIntentPath) -ine '.png') {
      throw 'Capture OutFile must be a canonical .png descendant of TrustedEvidenceRoot.'
    }
    $captureJournal = $null
    $captureCompletion = $null
    if (-not $DryRun -and -not [bool]$WhatIfPreference) {
      $captureJournal = New-PendingActionJournal -Manifest $manifest -TargetIntent (
        [pscustomobject][ordered]@{
          kind = 'capture'
          mode = $(if ($FullScreen) { 'FullScreen' } else { 'Window' })
          targetPid = $(if ($null -eq $captureTarget) { $null } else { [int]$captureTarget.record.pid })
          targetRole = $(if ($null -eq $captureTarget) { $null } else { [string]$captureTarget.record.launchIntent })
          outFile = $captureOutputIntentPath
          overwriteConsent = [bool]$CaptureForce
          fullScreenConsent = [bool]$AllowFullScreenCapture
        })
    }
    $captureResult = Invoke-StudioCapture -Manifest $manifest `
      -TargetSnapshot $(if ($null -eq $captureTarget) { $null } else { $captureTarget.snapshot }) `
      -FullScreenMode ([bool]$FullScreen)
    if ($null -ne $captureJournal) {
      $captureCompletion = Set-ManifestExternalActionCompletion -Manifest $manifest `
        -Journal $captureJournal -ResultBinding ([pscustomobject][ordered]@{
          mode = [string]$captureResult.Mode
          targetPid = $(if ($null -eq $captureTarget) { $null } else { [int]$captureTarget.record.pid })
          outFile = [string]$captureResult.OutFile
          outputSha256 = [string]$captureResult.OutputSha256
          outputBytes = [int64]$captureResult.OutputBytes
          capturedAtUtc = [string]$captureResult.CapturedAtUtc
        })
      Save-Manifest $manifest
      Complete-PendingActionJournal -Journal $captureJournal
    }
    New-StructuredResult -Ok $true -Data ([pscustomobject][ordered]@{
      operation = $(if ([bool]$WhatIfPreference) {
        'whatif-capture'
      } elseif ($DryRun) {
        'validated-capture-plan'
      } else {
        'captured'
      })
      mode = $(if ($FullScreen) { 'FullScreen' } else { 'Window' })
      targetPid = $(if ($null -eq $captureTarget) { $null } else { [int]$captureTarget.record.pid })
      launchIntent = $(if ($null -eq $captureTarget) { $null } else { [string]$captureTarget.record.launchIntent })
      roleVerified = $(if ($null -eq $captureTarget) { $null } else { $true })
      placeHandshakeVerified = $(if ($null -eq $captureTarget) { $null } else { $true })
      roleEvidenceExpiresAtUtc = $(if ($null -eq $captureRoleVerification) { $null } else { [string]$captureRoleVerification.expiresAtUtc })
      placeEvidenceExpiresAtUtc = $(if ($null -eq $capturePlaceVerification) { $null } else { [string]$capturePlaceVerification.expiresAtUtc })
      captureEvidenceDeadlineUtc = $captureEvidenceDeadlineUtc
      fullScreenConsentAsserted = [bool]$AllowFullScreenCapture
      outputWritten = [bool]$captureResult.OutputWritten
      captureScriptPath = [string]$captureResult.CaptureScriptPath
      captureScriptSha256 = [string]$captureResult.CaptureScriptSha256
      captureScriptFileIdentity = [string]$captureResult.CaptureScriptFileIdentity
      externalActionCompletion = $captureCompletion
      capture = $captureResult
    })
  }

  'List' {
    $manifest = Read-Manifest
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($record in @($manifest.ownedProcesses)) {
      $identity = Test-RecordIdentity -Manifest $manifest -Record $record
      $roleVerification = Test-RoleVerification -Manifest $manifest -Record $record
      $windows = if ($identity.valid) { @(Get-WindowReport -ProcessId ([int]$record.pid)) } else { @() }
      $items.Add([pscustomobject]@{
        pid            = [int]$record.pid
        role           = [string]$record.role
        launchIntent   = [string]$record.launchIntent
        roleVerified   = [bool]$record.roleVerified
        roleEvidenceValid = [bool]$roleVerification.valid
        roleEvidenceReason = $roleVerification.reason
        roleEvidencePath = [string]$record.roleEvidencePath
        roleEvidenceSha256 = [string]$record.roleEvidenceSha256
        roleEvidenceObservedAtUtc = [string]$record.roleEvidenceObservedAtUtc
        roleEvidenceEventId = [string]$record.roleEvidenceEventId
        roleEvidenceProbeId = [string]$record.roleEvidenceProbeId
        roleEvidenceExpiresAtUtc = $roleVerification.expiresAtUtc
        startTimeUtc   = [string]$record.startTimeUtc
        sessionId      = [int]$record.sessionId
        executablePath = [string]$record.executablePath
        valid          = [bool]$identity.valid
        reason         = $identity.reason
        windows        = $windows
      })
    }
    $placeVerification = Test-PlaceVerification -Manifest $manifest
    New-StructuredResult -Ok $true -Data ([pscustomobject]@{
      ownershipId = $manifest.ownershipId
      repositoryRoot = $manifest.repositoryRoot
      repositoryAdministrationRoots = @($manifest.repositoryAdministrationRoots)
      trustedEvidenceRoot = $manifest.trustedEvidenceRoot
      scriptsRoot = $manifest.scriptsRoot
      sessionScriptPath = $manifest.sessionScriptPath
      sessionScriptSha256 = $manifest.sessionScriptSha256
      sessionScriptFileIdentity = $manifest.sessionScriptFileIdentity
      inputScriptPath = $manifest.inputScriptPath
      inputScriptSha256 = $manifest.inputScriptSha256
      inputScriptFileIdentity = $manifest.inputScriptFileIdentity
      captureScriptPath = $manifest.captureScriptPath
      captureScriptSha256 = $manifest.captureScriptSha256
      captureScriptFileIdentity = $manifest.captureScriptFileIdentity
      studioVersionDirectory = $manifest.studioVersionDirectory
      placePath   = $manifest.placePath
      placeSha256 = $manifest.placeSha256
      placeHandshakeVerified = [bool]$manifest.placeHandshakeVerified
      placeEvidenceValid = [bool]$placeVerification.valid
      placeEvidenceReason = $placeVerification.reason
      placeEvidencePath = [string]$manifest.placeEvidencePath
      placeEvidenceSha256 = [string]$manifest.placeEvidenceSha256
      placeEvidenceObservedAtUtc = [string]$manifest.placeEvidenceObservedAtUtc
      placeEvidenceEventId = [string]$manifest.placeEvidenceEventId
      placeEvidenceProbeId = [string]$manifest.placeEvidenceProbeId
      placeEvidenceExpiresAtUtc = $placeVerification.expiresAtUtc
      evidenceFreshnessMinutes = $script:EvidenceFreshnessMinutes
      executableSha256 = [string]$manifest.executableSha256
      executableSignerSubject = [string]$manifest.executableSignerSubject
      executableSignerThumbprint = [string]$manifest.executableSignerThumbprint
      executableProductVersion = [string]$manifest.executableProductVersion
      pendingActionJournalPath = $script:PendingActionJournalPath
      pendingActionJournalSchemaVersion = $script:PendingActionJournalSchemaVersion
      pendingActionJournal = $script:PendingActionJournalStatus
      lastCompletedExternalAction = $manifest.lastCompletedExternalAction
      processes   = $items.ToArray()
    })
  }

  'Cleanup' {
    $manifest = Read-Manifest
    if (-not $DryRun -and -not $Force -and -not [bool]$WhatIfPreference) {
      throw 'Cleanup refuses to close windows without explicit -Force. Use -WhatIf to preview.'
    }
    if ($KeepPid -gt 0) {
      $null = Get-OwnedRecord -Manifest $manifest -ProcessId $KeepPid
    }

    $verified = [System.Collections.Generic.List[object]]::new()
    $unverified = [System.Collections.Generic.List[object]]::new()
    $stale = [System.Collections.Generic.List[object]]::new()
    # -Force authorizes close requests only for independently confirmed records. A live
    # unverified candidate may be an unrelated Studio and must remain untouched.
    foreach ($record in @($manifest.ownedProcesses)) {
      $identity = Test-RecordIdentity -Manifest $manifest -Record $record
      if ($identity.valid) {
        $roleVerification = Test-RoleVerification -Manifest $manifest -Record $record
        if ($roleVerification.valid -and [string]$record.role -ceq 'edit') {
          $editPlaceVerification = Test-PlaceVerification -Manifest $manifest
          if (-not $editPlaceVerification.valid) {
            $roleVerification = [pscustomobject]@{ valid = $false; reason = "edit-place-evidence-invalid: $($editPlaceVerification.reason)" }
          }
        }
        if ($roleVerification.valid) {
          $verified.Add([pscustomobject]@{ record = $record; snapshot = $identity.snapshot })
        } else {
          $unverified.Add([pscustomobject]@{ record = $record; reason = $roleVerification.reason })
        }
      } else {
        $stale.Add([pscustomobject]@{ record = $record; reason = $identity.reason })
      }
    }
    $targets = @($verified | Where-Object { [int]$_.record.pid -ne $KeepPid })

    if ($DryRun -or [bool]$WhatIfPreference) {
      if ([bool]$WhatIfPreference) {
        foreach ($target in $targets) {
          $processId = [int]$target.record.pid
          $description = "role=$($target.record.role), start=$($target.record.startTimeUtc), path=$($target.record.executablePath)"
          $null = $PSCmdlet.ShouldProcess("owned Roblox Studio PID $processId ($description)", 'Post WM_CLOSE')
        }
      }
      New-StructuredResult -Ok $true -Data ([pscustomobject]@{
        operation = $(if ([bool]$WhatIfPreference) { 'whatif-cleanup-owned-processes' } else { 'would-cleanup-owned-processes' })
        targetPids = @($targets | ForEach-Object { [int]$_.record.pid })
        keepPid = $KeepPid
        staleRecords = $stale.ToArray()
        unverifiedRecords = $unverified.ToArray()
        unverifiedPolicy = 'Unverified live candidates are never closed. Identify and close them manually outside this script; rerun Cleanup only after they exit to prune stale records.'
        forceRequiredForExecution = $true
      })
      break
    }

    $cleanupJournal = New-PendingActionJournal -Manifest $manifest -TargetIntent (
      [pscustomobject][ordered]@{
        kind = 'window-close-and-manifest-prune'
        targetPids = @($targets | ForEach-Object { [int]$_.record.pid })
        keepPid = [int]$KeepPid
        stalePids = @($stale | ForEach-Object { [int]$_.record.pid })
        forceConsent = [bool]$Force
      })
    $requested = [System.Collections.Generic.List[object]]::new()
    $declined = [System.Collections.Generic.List[int]]::new()
    $runtimeSkipped = [System.Collections.Generic.List[object]]::new()
    $postFailures = [System.Collections.Generic.List[string]]::new()
    foreach ($target in $targets) {
      $processId = [int]$target.record.pid
      $description = "role=$($target.record.role), start=$($target.record.startTimeUtc), path=$($target.record.executablePath)"
      if ($PSCmdlet.ShouldProcess("owned Roblox Studio PID $processId ($description)", 'Post WM_CLOSE')) {
        $freshIdentity = Test-RecordIdentity -Manifest $manifest -Record $target.record
        if (-not $freshIdentity.valid) {
          $postFailures.Add("PID $processId failed ownership revalidation immediately before WM_CLOSE ($($freshIdentity.reason))")
          continue
        }
        $cachedMainWindowHandle = [IntPtr]$freshIdentity.snapshot.process.MainWindowHandle
        $freshRoleVerification = Test-RoleVerification -Manifest $manifest -Record $target.record
        if ($freshRoleVerification.valid -and [string]$target.record.role -ceq 'edit') {
          $freshPlaceVerification = Test-PlaceVerification -Manifest $manifest
          if (-not $freshPlaceVerification.valid) {
            $freshRoleVerification = [pscustomobject]@{ valid = $false; reason = "edit-place-evidence-invalid: $($freshPlaceVerification.reason)" }
          }
        }
        if (-not $freshRoleVerification.valid) {
          $runtimeSkipped.Add([pscustomobject]@{ record = $target.record; reason = $freshRoleVerification.reason })
          continue
        }
        $closeBinding = Test-CloseWindowBinding -Manifest $manifest -Record $target.record `
          -CachedMainWindowHandle $cachedMainWindowHandle
        if (-not $closeBinding.valid) {
          $postFailures.Add("PID $processId failed final HWND binding validation ($($closeBinding.reason))")
          continue
        }
        if (-not [StudioSessionSafe]::PostMessageW($closeBinding.handle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)) {
          $postFailures.Add("PostMessageW failed for PID $processId (Win32=$([Runtime.InteropServices.Marshal]::GetLastWin32Error()))")
          continue
        }
        $requested.Add($target)
      } else {
        $declined.Add($processId)
      }
    }

    $deadline = [datetime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ($requested.Count -gt 0 -and [datetime]::UtcNow -lt $deadline) {
      $stillRunning = @($requested | Where-Object {
        (Test-RecordIdentity -Manifest $manifest -Record $_.record).valid
      })
      if ($stillRunning.Count -eq 0) { break }
      Start-Sleep -Milliseconds 500
    }

    $timedOut = [System.Collections.Generic.List[int]]::new()
    foreach ($item in $requested) {
      if ((Test-RecordIdentity -Manifest $manifest -Record $item.record).valid) {
        $timedOut.Add([int]$item.record.pid)
      }
    }

    $retained = [System.Collections.Generic.List[object]]::new()
    foreach ($record in @($manifest.ownedProcesses)) {
      $wasStale = @($stale | Where-Object { [int]$_.record.pid -eq [int]$record.pid }).Count -gt 0
      $stillOwned = (Test-RecordIdentity -Manifest $manifest -Record $record).valid
      if (-not $wasStale -and $stillOwned) {
        $retained.Add($record)
      }
    }
    $manifest.ownedProcesses = $retained.ToArray()
    Save-Manifest $manifest

    if ($postFailures.Count -gt 0) {
      throw "Cleanup could not request every owned window to close: $($postFailures -join '; '). Manifest was updated without targeting foreign processes."
    }
    if ($timedOut.Count -gt 0) {
      throw "Timed out waiting for owned PID(s) $($timedOut -join ', ') to close. No force termination was attempted."
    }

    $cleanupCompletion = Set-ManifestExternalActionCompletion -Manifest $manifest `
      -Journal $cleanupJournal -ResultBinding ([pscustomobject][ordered]@{
        requestedPids = @($requested | ForEach-Object { [int]$_.record.pid })
        declinedPids = @($declined.ToArray())
        keepPid = [int]$KeepPid
        prunedStalePids = @($stale | ForEach-Object { [int]$_.record.pid })
        remainingPids = @($manifest.ownedProcesses | ForEach-Object { [int]$_.pid })
      })
    Save-Manifest $manifest
    Complete-PendingActionJournal -Journal $cleanupJournal

    New-StructuredResult -Ok $true -Data ([pscustomobject]@{
      requestedPids = @($requested | ForEach-Object { [int]$_.record.pid })
      declinedPids  = $declined.ToArray()
      keepPid       = $KeepPid
      prunedStale   = $stale.ToArray()
      unverifiedRecords = @($unverified.ToArray()) + @($runtimeSkipped.ToArray())
      remaining     = @($manifest.ownedProcesses)
      externalActionCompletion = $cleanupCompletion
      next          = 'Any unverified live candidate remains open and in the manifest. Resolve it manually; after it exits, rerun Cleanup to prune the stale record.'
    })
  }
}
} finally {
  if ($null -ne $script:ActivePendingActionJournal -and
      $null -ne $script:ActivePendingActionJournal.lease) {
    try {
      $script:ActivePendingActionJournal.lease.Dispose()
      $script:ActivePendingActionJournal.lease = $null
    } catch {
      Write-Warning "Failed to release the pending-action journal lease; its durable marker was intentionally retained: $($_.Exception.Message)"
    }
  }
  if ($sessionMutexAcquired) {
    try {
      $sessionMutex.ReleaseMutex()
    } catch {
      Write-Warning "Failed to release the SessionFile action lock cleanly: $($_.Exception.Message)"
    }
  }
  $sessionMutex.Dispose()
}
