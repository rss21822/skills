<#
studio_input.ps1 - SendInput で、指定した Roblox Studio プロセスだけへ入力する。

安全条件:
  - 全アクションを副作用より前に構文・型・個数・範囲検証する。
  - session manifest の PID、セッション、実行ファイル絶対パス、UTC 開始 ticks を初回から再検証する。
  - 非 DryRun は -AllowOsInput による明示許可がなければ、foreground 変更より前に停止する。
  - 初回および各アクション直前に foreground window の所有 PID を検証する。
  - session が渡す evidence deadline 内に全planが収まり、各global input直前にも期限内であることを検証する。
  - click/absclick はクリック地点の window 所有 PID も検証する。
  - Win32 API の失敗は成功扱いせず、残留キー/ボタンを best-effort 解放して失敗終了する。

座標:
  click:X:Y     現在前面にある対象ウィンドウの window 矩形相対。X/Y は 0 以上。
  click         現在前面にある対象ウィンドウの中央。
  absclick:X:Y  Windows の仮想スクリーン座標。左/上側モニターでは負値を許容する。
                画像座標は capture が報告した仮想スクリーン原点を加算して渡す。
  press:KEY:MS  キーを押し、MS 後に解放する。MS 省略時は 100、最大 2000。
  wait:MS       MS 待つ。

このhelperはstudio_session.ps1がmanifestで固定したバイト列をメモリ実行する内部入口であり、
operatorによる直接実行（DryRunを含む）を拒否する。plan検証もsessionの Start/AddClients/Input
-DryRunから行う。現在のPIDからidentityや期限を再生成してはならない。

DryRun は manifest の path/session/start-time 形式と action plan を検証する。
プロセス/foreground 検証と OS 入力は行わない。
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$Actions,

  [Parameter(Mandatory = $true)]
  [ValidateRange(1, [int]::MaxValue)]
  [int]$ProcId,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$ExpectedExecutablePath,

  [Parameter(Mandatory = $true)]
  [ValidateRange(0, [int]::MaxValue)]
  [int]$ExpectedSessionId,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$ExpectedStartTimeUtc,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$InputDeadlineUtc,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$VerifiedHelperPath,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-f]{64}$')]
  [string]$VerifiedHelperSha256,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9A-F]{8}:[0-9A-F]{8}:[0-9A-F]{8}:1$')]
  [string]$VerifiedHelperFileIdentity,

  [switch]$VerifiedInMemoryDispatch,

  [switch]$AllowOsInput,

  [switch]$DryRun
)

$null = Microsoft.PowerShell.Core\Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

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
  throw "studio_input.ps1 requires the exact OS System32 Windows PowerShell 5.1 host: $entryExpectedHostPath"
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

function Assert-TrustedInputEntryFilePath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$TrustedRoot,
    [Parameter(Mandatory = $true)][string]$Label
  )
  if ($Path.StartsWith('\\', [StringComparison]::Ordinal) -or
      $Path -notmatch '^[A-Za-z]:[\\/]') { throw "$Label must use absolute local-drive syntax." }
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $rootPath = [System.IO.Path]::GetFullPath($TrustedRoot).TrimEnd([char[]]@('\', '/'))
  if (-not $fullPath.StartsWith(
      $rootPath + [System.IO.Path]::DirectorySeparatorChar,
      [StringComparison]::OrdinalIgnoreCase)) {
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
    if (([System.IO.File]::GetAttributes($cursor) -band
        [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "$Label path crosses a reparse point: $cursor"
    }
    if ($index -lt ($segments.Count - 1) -and -not [System.IO.Directory]::Exists($cursor)) {
      throw "$Label path component is not a directory: $cursor"
    }
  }
  if (-not [System.IO.File]::Exists($fullPath)) {
    throw "$Label must resolve to an existing file: $fullPath"
  }
  return $fullPath
}

function Assert-NoAmbientInputCommandShadowing {
  $expected = @(
    @('Add-Type', 'Microsoft.PowerShell.Utility'),
    @('Get-AuthenticodeSignature', 'Microsoft.PowerShell.Security'),
    @('Get-Command', 'Microsoft.PowerShell.Core'),
    @('Get-Item', 'Microsoft.PowerShell.Management'),
    @('Get-Process', 'Microsoft.PowerShell.Management'),
    @('New-Object', 'Microsoft.PowerShell.Utility'),
    @('Resolve-Path', 'Microsoft.PowerShell.Management'),
    @('Select-Object', 'Microsoft.PowerShell.Utility'),
    @('Start-Sleep', 'Microsoft.PowerShell.Utility'),
    @('Where-Object', 'Microsoft.PowerShell.Core'),
    @('Write-Output', 'Microsoft.PowerShell.Utility')
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
    if ($resolved.Count -eq 0 -or
        $resolved[0].CommandType -ne [System.Management.Automation.CommandTypes]::Cmdlet -or
        [string]$resolved[0].ModuleName -cne [string]$entry[1] -or
        -not $dllTrusted -or -not $modulePathTrusted) {
      throw "Ambient command shadowing is forbidden for '$($entry[0])'; expected first resolution to the trusted $($entry[1]) cmdlet from PSHOME/GAC."
    }

    if (-not $validatedPowerShellFiles.ContainsKey($resolvedDllFull)) {
      $resolvedDllFull = Assert-TrustedInputEntryFilePath -Path $resolvedDllFull `
        -TrustedRoot $trustedDllPrefixes[0].TrimEnd([char[]]@('\', '/')) `
        -Label "Critical cmdlet DLL for $($entry[0])"
      $assemblyName = [System.Reflection.AssemblyName]::GetAssemblyName($resolvedDllFull)
      $assemblyToken = [BitConverter]::ToString($assemblyName.GetPublicKeyToken()).Replace('-', '').ToLowerInvariant()
      if ([string]$assemblyName.Name -cne [string]$expectedAssemblyNames[[string]$entry[1]] -or
          $assemblyToken -cne '31bf3856ad364e35') {
        throw "Critical cmdlet DLL assembly identity is untrusted for '$($entry[0])'."
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
      $resolvedModulePath = Assert-TrustedInputEntryFilePath -Path $resolvedModulePath `
        -TrustedRoot $moduleRootPrefix.TrimEnd([char[]]@('\', '/')) `
        -Label "Critical cmdlet module manifest for $($entry[0])"
      if ([System.IO.Path]::GetFileName($resolvedModulePath) -cne "$($entry[1]).psd1") {
        throw "Critical cmdlet module manifest leaf is untrusted for '$($entry[0])'."
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
  $currentHostPath = Assert-TrustedInputEntryFilePath -Path $currentHostPath `
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

Assert-NoAmbientInputCommandShadowing

if ($null -ne ('StudioInput' -as [type])) {
  throw "A preexisting 'StudioInput' type is forbidden; run this action in a fresh exact System32 Windows PowerShell 5.1 host."
}

$dispatchSourceFile = [string]$MyInvocation.MyCommand.ScriptBlock.File
if (-not $VerifiedInMemoryDispatch.IsPresent -or
    -not [string]::IsNullOrEmpty($dispatchSourceFile)) {
  throw 'studio_input.ps1 accepts only a verified in-memory dispatch from studio_session.ps1; direct file execution is forbidden.'
}
if ($VerifiedHelperPath.StartsWith('\', [StringComparison]::Ordinal) -or
    $VerifiedHelperPath -notmatch '^[A-Za-z]:[\\/]' -or
    [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($VerifiedHelperPath) -or
    [System.IO.Path]::GetFileName($VerifiedHelperPath) -cne 'studio_input.ps1') {
  throw 'VerifiedHelperPath must be the absolute literal studio_input.ps1 path attested by the session manifest.'
}

$maxActionCount = 1000
$maxPressDurationMs = 2000
$maxWaitDurationMs = 600000
$maxTotalDurationMs = 1800000
$inputPlanFixedOverheadMs = 15000L
$inputPlanPerActionOverheadMs = 250L
$inputPlanPerClickOverheadMs = 300L
$maxRelativeCoordinate = 100000
$maxAbsoluteCoordinateMagnitude = 1000000
$requiredProcessFileName = 'RobloxStudioBeta.exe'

$vkMap = @{}
foreach ($ch in [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZ') { $vkMap["$ch"] = [int][char]$ch }
foreach ($d in 0..9) { $vkMap["$d"] = 0x30 + $d }
foreach ($f in 1..12) { $vkMap["F$f"] = 0x6F + $f }
$vkMap['SPACE'] = 0x20
$vkMap['ENTER'] = 0x0D
$vkMap['ESC'] = 0x1B
$vkMap['TAB'] = 0x09
$vkMap['SHIFT'] = 0xA0
$vkMap['RSHIFT'] = 0xA1
$vkMap['CTRL'] = 0x11
$vkMap['ALT'] = 0x12
$vkMap['LEFT'] = 0x25
$vkMap['UP'] = 0x26
$vkMap['RIGHT'] = 0x27
$vkMap['DOWN'] = 0x28
$vkMap['BACKSPACE'] = 0x08
$vkMap['DELETE'] = 0x2E
$vkMap['INSERT'] = 0x2D
$vkMap['HOME'] = 0x24
$vkMap['END'] = 0x23
$vkMap['PGUP'] = 0x21
$vkMap['PGDN'] = 0x22

$extKeys = @('LEFT', 'UP', 'RIGHT', 'DOWN', 'DELETE', 'INSERT', 'HOME', 'END', 'PGUP', 'PGDN')

function ConvertTo-StrictInt {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Label,
    [Parameter(Mandatory = $true)][int]$Minimum,
    [Parameter(Mandatory = $true)][int]$Maximum
  )
  if ([string]::IsNullOrWhiteSpace($Text)) { throw "$Label must not be empty" }
  $value = 0
  $ok = [int]::TryParse(
    $Text.Trim(),
    [System.Globalization.NumberStyles]::Integer,
    [System.Globalization.CultureInfo]::InvariantCulture,
    [ref]$value
  )
  if (-not $ok) { throw "$Label must be an invariant Int32; got '$Text'" }
  if ($value -lt $Minimum -or $value -gt $Maximum) {
    throw "$Label must be in [$Minimum,$Maximum]; got $value"
  }
  return $value
}

function New-ActionPlan {
  param([Parameter(Mandatory = $true)][string]$ActionText)

  if ([string]::IsNullOrWhiteSpace($ActionText)) { throw 'Actions must contain at least one action' }
  $rawTokens = @($ActionText.Split([char]',', [System.StringSplitOptions]::None))
  if ($rawTokens.Count -gt $maxActionCount) {
    throw "Actions exceeds the maximum of $maxActionCount actions"
  }

  $plan = New-Object 'System.Collections.Generic.List[object]'
  $totalDurationMs = 0L
  for ($index = 0; $index -lt $rawTokens.Count; $index++) {
    $raw = $rawTokens[$index].Trim()
    if ([string]::IsNullOrWhiteSpace($raw)) { throw "action[$index] is empty" }
    $parts = @($raw.Split([char]':', [System.StringSplitOptions]::None))
    for ($partIndex = 0; $partIndex -lt $parts.Count; $partIndex++) {
      $parts[$partIndex] = $parts[$partIndex].Trim()
    }
    $kind = $parts[0].ToLowerInvariant()

    switch ($kind) {
      'press' {
        if ($parts.Count -ne 2 -and $parts.Count -ne 3) {
          throw "action[$index] 'press' requires KEY and optional MS"
        }
        $key = $parts[1].ToUpperInvariant()
        if ([string]::IsNullOrWhiteSpace($key) -or -not $vkMap.ContainsKey($key)) {
          throw "action[$index] has unknown key '$($parts[1])'"
        }
        $durationMs = 100
        if ($parts.Count -eq 3) {
          $durationMs = ConvertTo-StrictInt -Text $parts[2] -Label "action[$index] press duration" -Minimum 1 -Maximum $maxPressDurationMs
        }
        $totalDurationMs += $durationMs
        $plan.Add([pscustomobject]@{ Index=$index; Kind=$kind; Key=$key; DurationMs=$durationMs; X=$null; Y=$null; Raw=$raw })
        break
      }
      'wait' {
        if ($parts.Count -ne 2) { throw "action[$index] 'wait' requires exactly MS" }
        $durationMs = ConvertTo-StrictInt -Text $parts[1] -Label "action[$index] wait duration" -Minimum 1 -Maximum $maxWaitDurationMs
        $totalDurationMs += $durationMs
        $plan.Add([pscustomobject]@{ Index=$index; Kind=$kind; Key=$null; DurationMs=$durationMs; X=$null; Y=$null; Raw=$raw })
        break
      }
      'click' {
        if ($parts.Count -ne 1 -and $parts.Count -ne 3) {
          throw "action[$index] 'click' accepts no coordinates or exactly X:Y"
        }
        $x = $null
        $y = $null
        if ($parts.Count -eq 3) {
          $x = ConvertTo-StrictInt -Text $parts[1] -Label "action[$index] click X" -Minimum 0 -Maximum $maxRelativeCoordinate
          $y = ConvertTo-StrictInt -Text $parts[2] -Label "action[$index] click Y" -Minimum 0 -Maximum $maxRelativeCoordinate
        }
        $plan.Add([pscustomobject]@{ Index=$index; Kind=$kind; Key=$null; DurationMs=0; X=$x; Y=$y; Raw=$raw })
        break
      }
      'absclick' {
        if ($parts.Count -ne 3) {
          throw "action[$index] 'absclick' requires exactly X:Y in virtual-screen coordinates"
        }
        $x = ConvertTo-StrictInt -Text $parts[1] -Label "action[$index] absclick X" -Minimum (-$maxAbsoluteCoordinateMagnitude) -Maximum $maxAbsoluteCoordinateMagnitude
        $y = ConvertTo-StrictInt -Text $parts[2] -Label "action[$index] absclick Y" -Minimum (-$maxAbsoluteCoordinateMagnitude) -Maximum $maxAbsoluteCoordinateMagnitude
        $plan.Add([pscustomobject]@{ Index=$index; Kind=$kind; Key=$null; DurationMs=0; X=$x; Y=$y; Raw=$raw })
        break
      }
      default { throw "action[$index] has unknown kind '$($parts[0])'" }
    }
  }

  if ($totalDurationMs -gt $maxTotalDurationMs) {
    throw "Actions requests $totalDurationMs ms of waiting; maximum is $maxTotalDurationMs ms"
  }
  return @($plan.ToArray())
}

if ([string]::IsNullOrWhiteSpace($ExpectedExecutablePath) -or
    [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($ExpectedExecutablePath) -or
    $ExpectedExecutablePath.StartsWith('\\', [StringComparison]::Ordinal) -or
    $ExpectedExecutablePath -notmatch '^[A-Za-z]:[\\/]') {
  throw 'ExpectedExecutablePath must be a non-empty absolute local-drive literal path without wildcards, UNC, device, or provider syntax'
}
$expectedInputComparison = $ExpectedExecutablePath.Replace('/', '\')
if ($expectedInputComparison.Length -gt 3) { $expectedInputComparison = $expectedInputComparison.TrimEnd('\') }
$expectedExecutableFullPath = [System.IO.Path]::GetFullPath($ExpectedExecutablePath)
$expectedFullComparison = $expectedExecutableFullPath
if ($expectedFullComparison.Length -gt 3) { $expectedFullComparison = $expectedFullComparison.TrimEnd('\') }
if (-not [string]::Equals(
    $expectedInputComparison, $expectedFullComparison, [StringComparison]::OrdinalIgnoreCase)) {
  throw 'ExpectedExecutablePath must already use its normalized long path; aliases and dot segments are forbidden'
}
if ($expectedExecutableFullPath.Substring(2).Contains(':')) {
  throw 'ExpectedExecutablePath must not use an alternate data stream'
}
$expectedDriveRoot = [System.IO.Path]::GetPathRoot($expectedExecutableFullPath)
$expectedDrive = [System.IO.DriveInfo]::new($expectedDriveRoot)
$expectedDriveType = $expectedDrive.DriveType
if ($expectedDriveType -ne [System.IO.DriveType]::Fixed) {
  throw "ExpectedExecutablePath must be on a local Fixed drive; '$expectedDriveRoot' is $expectedDriveType"
}
if (-not $expectedDrive.IsReady) {
  throw "ExpectedExecutablePath Fixed drive '$expectedDriveRoot' is not ready"
}

# Inspect each local component itself before touching a descendant. Resolve-Path on the
# full value could otherwise traverse a junction into UNC/network I/O before rejection.
try {
  $executableItem = Get-Item -LiteralPath $expectedDriveRoot -Force -ErrorAction Stop
} catch {
  throw "ExpectedExecutablePath drive root cannot be inspected safely: $($_.Exception.Message)"
}
if (($executableItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
  throw "ExpectedExecutablePath drive root must not be a reparse point: $expectedDriveRoot"
}
$relativeExecutablePath = $expectedExecutableFullPath.Substring($expectedDriveRoot.Length)
$executableCursor = $expectedDriveRoot
foreach ($segment in @($relativeExecutablePath.Split([char[]]@('\', '/'), [System.StringSplitOptions]::RemoveEmptyEntries))) {
  $executableCursor = [System.IO.Path]::Combine($executableCursor, $segment)
  try {
    $executableItem = Get-Item -LiteralPath $executableCursor -Force -ErrorAction Stop
  } catch {
    throw "ExpectedExecutablePath must be an existing locally inspectable file: $executableCursor"
  }
  if (($executableItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "ExpectedExecutablePath traverses a reparse point: $executableCursor"
  }
}
if ($executableItem.PSIsContainer) {
  throw 'ExpectedExecutablePath must resolve to a file, not a directory'
}
$ExpectedExecutablePath = [System.IO.Path]::GetFullPath($executableItem.FullName)
if (-not [string]::Equals(
    $ExpectedExecutablePath, $expectedExecutableFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'ExpectedExecutablePath must already use its canonical local file path'
}
if (-not [string]::Equals(
    [System.IO.Path]::GetFileName($ExpectedExecutablePath),
    $requiredProcessFileName,
    [System.StringComparison]::OrdinalIgnoreCase)) {
  throw "ExpectedExecutablePath leaf must be exactly '$requiredProcessFileName'"
}

$expectedStartTimeValue = [DateTime]::MinValue
$startTimeParsed = [DateTime]::TryParseExact(
  $ExpectedStartTimeUtc,
  'o',
  [System.Globalization.CultureInfo]::InvariantCulture,
  [System.Globalization.DateTimeStyles]::RoundtripKind,
  [ref]$expectedStartTimeValue
)
if (-not $startTimeParsed -or
    -not $ExpectedStartTimeUtc.EndsWith('Z', [System.StringComparison]::Ordinal) -or
    $expectedStartTimeValue.Kind -ne [DateTimeKind]::Utc) {
  throw "ExpectedStartTimeUtc must be UTC round-trip ISO 8601 with seven fractional digits and Z (example: 2026-08-18T05:00:00.1234567Z)"
}
$expectedStartTimeUtcValue = $expectedStartTimeValue.ToUniversalTime()
$ExpectedStartTimeUtc = $expectedStartTimeUtcValue.ToString('o')

$inputDeadlineValue = [datetime]::MinValue
$deadlineParsed = $InputDeadlineUtc -cmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$' -and [DateTime]::TryParseExact(
  $InputDeadlineUtc,
  "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",
  [System.Globalization.CultureInfo]::InvariantCulture,
  ([System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal),
  [ref]$inputDeadlineValue
)
if (-not $deadlineParsed -or $inputDeadlineValue.Kind -ne [DateTimeKind]::Utc) {
  throw "InputDeadlineUtc must be strict UTC round-trip ISO 8601 with seven fractional digits and Z"
}
$InputDeadlineUtc = $inputDeadlineValue.ToString('o')

$callerSessionId = [int](Get-Process -Id $PID -ErrorAction Stop).SessionId
if ($ExpectedSessionId -ne $callerSessionId) {
  throw "ExpectedSessionId $ExpectedSessionId differs from the current input desktop session $callerSessionId"
}

$plan = @(New-ActionPlan -ActionText $Actions)
$estimatedMaximumDurationMs = $inputPlanFixedOverheadMs + ($inputPlanPerActionOverheadMs * [long]$plan.Count)
$remainingPlanDurationMs = [long[]]::new($plan.Count)
$runningRemainingMs = 0L
for ($planIndex = $plan.Count - 1; $planIndex -ge 0; $planIndex--) {
  $plannedAction = $plan[$planIndex]
  $runningRemainingMs += $inputPlanPerActionOverheadMs + [long]$plannedAction.DurationMs
  if ($plannedAction.Kind -ceq 'click' -or $plannedAction.Kind -ceq 'absclick') {
    $runningRemainingMs += $inputPlanPerClickOverheadMs
  }
  $remainingPlanDurationMs[$planIndex] = $runningRemainingMs
}
foreach ($plannedAction in $plan) {
  $estimatedMaximumDurationMs += [long]$plannedAction.DurationMs
  if ($plannedAction.Kind -ceq 'click' -or $plannedAction.Kind -ceq 'absclick') {
    $estimatedMaximumDurationMs += $inputPlanPerClickOverheadMs
  }
}
$deadlineValidationUtc = [DateTime]::UtcNow
if ($deadlineValidationUtc.AddMilliseconds($estimatedMaximumDurationMs) -ge $inputDeadlineValue) {
  $remainingMs = [Math]::Max(0L, [long]($inputDeadlineValue - $deadlineValidationUtc).TotalMilliseconds)
  throw "Input plan cannot finish inside the verified evidence window: estimated maximum ${estimatedMaximumDurationMs}ms, remaining ${remainingMs}ms. Refresh all required evidence and retry."
}
if ($DryRun) {
  [pscustomobject]@{
    ResultType='StudioInputResult'; Success=$true; DryRun=$true; TargetValidationPerformed=$false
    ProcId=$ProcId; ExpectedSessionId=$ExpectedSessionId; ExpectedProcessName=$requiredProcessFileName
    ExpectedExecutablePath=$ExpectedExecutablePath
    VerifiedHelperPath=$VerifiedHelperPath; VerifiedHelperSha256=$VerifiedHelperSha256
    VerifiedHelperFileIdentity=$VerifiedHelperFileIdentity; VerifiedInMemoryDispatch=$true
    ExpectedStartTimeUtc=$ExpectedStartTimeUtc; ExpectedStartTimeTicks=$expectedStartTimeUtcValue.Ticks
    ActualStartTimeUtc=$null; ActualStartTimeTicks=$null
    CoordinateSystem='Windows virtual-screen coordinates; negative X/Y are valid for absclick'
    OsInputAuthorized=$false
    InputDeadlineUtc=$InputDeadlineUtc
    EstimatedMaximumDurationMs=$estimatedMaximumDurationMs
    EvidenceRemainingMsAtValidation=[long]($inputDeadlineValue-$deadlineValidationUtc).TotalMilliseconds
    ActionsRequested=$plan.Count; ActionsCompleted=0; Plan=@($plan)
    TimestampUtc=[DateTime]::UtcNow.ToString('o')
  }
  return
}

if (-not $AllowOsInput) {
  throw 'Non-DryRun execution requires explicit -AllowOsInput authorization; no foreground change or input was performed'
}

if ($env:OS -ne 'Windows_NT') { throw 'studio_input.ps1 requires Windows' }

function Assert-InputCompilerTempSafety {
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
      $cursor = [System.IO.Path]::Combine($cursor, $segment)
      $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
      if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Process TEMP/TMP must not traverse a reparse point: $cursor"
      }
      $cursor = $item.FullName
    }
    if (-not $item.PSIsContainer) { throw "Process TEMP/TMP must be an existing directory: $full" }
  }
}

Assert-InputCompilerTempSafety

Add-Type @'
using System;
using System.Runtime.InteropServices;
public class StudioInput {
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", SetLastError=true)] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint mapType);
  [DllImport("user32.dll", SetLastError=true)] public static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool GetCursorPos(out POINT p);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll", SetLastError=true)] public static extern bool ShowWindowAsync(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
  [DllImport("user32.dll", SetLastError=true)] public static extern IntPtr WindowFromPoint(POINT p);
  [StructLayout(LayoutKind.Sequential)] public struct INPUT { public uint type; public InputUnion U; }
  [StructLayout(LayoutKind.Explicit)] public struct InputUnion {
    [FieldOffset(0)] public KEYBDINPUT ki; [FieldOffset(0)] public MOUSEINPUT mi;
  }
  [StructLayout(LayoutKind.Sequential)] public struct KEYBDINPUT {
    public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo;
  }
  [StructLayout(LayoutKind.Sequential)] public struct MOUSEINPUT {
    public int dx; public int dy; public uint mouseData; public uint dwFlags; public uint time; public IntPtr dwExtraInfo;
  }
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  public static uint KeyScan(ushort scan, bool up, bool ext) {
    INPUT[] arr = new INPUT[1]; arr[0].type = 1; arr[0].U.ki.wVk = 0; arr[0].U.ki.wScan = scan;
    arr[0].U.ki.dwFlags = (uint)(8 | (up ? 2 : 0) | (ext ? 1 : 0));
    return SendInput(1, arr, Marshal.SizeOf(typeof(INPUT)));
  }
  public static uint MouseButton(bool up) {
    INPUT[] arr = new INPUT[1]; arr[0].type = 0; arr[0].U.mi.dwFlags = (uint)(up ? 4 : 2);
    return SendInput(1, arr, Marshal.SizeOf(typeof(INPUT)));
  }
  public static int LastError() { return Marshal.GetLastWin32Error(); }
}
'@

function Assert-InputDeadline {
  param(
    [Parameter(Mandatory = $true)][string]$Label,
    [ValidateRange(0, [long]::MaxValue)][long]$RequiredRemainingMs = 0
  )

  $now = [datetime]::UtcNow
  if ($now.AddMilliseconds($RequiredRemainingMs) -ge $inputDeadlineValue) {
    $remainingMs = [Math]::Max(0L, [long]($inputDeadlineValue - $now).TotalMilliseconds)
    throw "$Label cannot remain inside InputDeadlineUtc $InputDeadlineUtc; required ${RequiredRemainingMs}ms, remaining ${remainingMs}ms. Refresh session evidence before any more OS input."
  }
}

function Wait-WithinInputDeadline {
  param(
    [Parameter(Mandatory = $true)][ValidateRange(1, 600000)][int]$DurationMs,
    [Parameter(Mandatory = $true)][string]$Label
  )

  $stopwatch = [Diagnostics.Stopwatch]::StartNew()
  while ($stopwatch.ElapsedMilliseconds -lt $DurationMs) {
    Assert-InputDeadline -Label $Label -RequiredRemainingMs 50
    $remaining = $DurationMs - [int]$stopwatch.ElapsedMilliseconds
    Start-Sleep -Milliseconds ([Math]::Min(50, $remaining))
  }
}

function Get-ValidatedTargetProcess {
  $candidate = Get-Process -Id $ProcId -ErrorAction Stop
  if ([int]$candidate.SessionId -ne $ExpectedSessionId) {
    throw "target PID $ProcId is outside expected session $ExpectedSessionId"
  }
  $candidateStartTimeUtc = $candidate.StartTime.ToUniversalTime()
  if ($candidateStartTimeUtc.Ticks -ne $expectedStartTimeUtcValue.Ticks) {
    throw "target PID $ProcId start time mismatch: expected $ExpectedStartTimeUtc (ticks=$($expectedStartTimeUtcValue.Ticks)), actual $($candidateStartTimeUtc.ToString('o')) (ticks=$($candidateStartTimeUtc.Ticks)); possible PID reuse"
  }
  try { $actualPath = $candidate.Path } catch {
    throw "cannot read executable path for PID ${ProcId}: $($_.Exception.Message)"
  }
  if ([string]::IsNullOrWhiteSpace($actualPath)) { throw "executable path for PID $ProcId is empty" }
  $actualPath = [System.IO.Path]::GetFullPath($actualPath)
  $actualLeaf = [System.IO.Path]::GetFileName($actualPath)
  if (-not [string]::Equals($actualLeaf, $requiredProcessFileName, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "PID $ProcId executable is '$actualLeaf', expected '$requiredProcessFileName'"
  }
  $expectedBaseName = [System.IO.Path]::GetFileNameWithoutExtension($requiredProcessFileName)
  if (-not [string]::Equals($candidate.ProcessName, $expectedBaseName, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "PID $ProcId process name is '$($candidate.ProcessName)', expected '$expectedBaseName'"
  }
  if (-not [string]::Equals($actualPath, $ExpectedExecutablePath, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "PID $ProcId executable path is '$actualPath', expected '$ExpectedExecutablePath'"
  }
  return $candidate
}

$targetProcess = Get-ValidatedTargetProcess
if ($targetProcess.MainWindowHandle -eq [IntPtr]::Zero) { throw "target PID $ProcId has no main window" }
$actualTargetStartTimeUtc = $targetProcess.StartTime.ToUniversalTime()
$targetExecutablePath = [System.IO.Path]::GetFullPath($targetProcess.Path)
$targetMainWindowHandle = $targetProcess.MainWindowHandle

function Assert-TargetIdentity {
  $candidate = Get-ValidatedTargetProcess
  return $candidate
}

function Get-WindowOwnerPid {
  param([Parameter(Mandatory = $true)][IntPtr]$WindowHandle)
  if ($WindowHandle -eq [IntPtr]::Zero) { throw 'window handle is zero' }
  $ownerPid = [uint32]0
  $threadId = [StudioInput]::GetWindowThreadProcessId($WindowHandle, [ref]$ownerPid)
  if ($threadId -eq 0 -or $ownerPid -eq 0) {
    throw "GetWindowThreadProcessId failed (win32=$([StudioInput]::LastError()))"
  }
  return [int64]$ownerPid
}

function Assert-CurrentTargetMainWindow {
  $candidate = Assert-TargetIdentity
  $currentMainWindowHandle = [IntPtr]$candidate.MainWindowHandle
  if ($currentMainWindowHandle -eq [IntPtr]::Zero) {
    throw "target PID $ProcId currently has no main window"
  }
  if ($currentMainWindowHandle -ne $targetMainWindowHandle) {
    throw "target PID $ProcId main window changed from cached HWND $($targetMainWindowHandle.ToInt64()) to $($currentMainWindowHandle.ToInt64()); input aborted"
  }
  if (-not [StudioInput]::IsWindowVisible($currentMainWindowHandle)) {
    throw "target main HWND $($currentMainWindowHandle.ToInt64()) is not visible; input aborted"
  }
  $ownerPid = Get-WindowOwnerPid -WindowHandle $currentMainWindowHandle
  if ($ownerPid -ne $ProcId) {
    throw "target main HWND $($currentMainWindowHandle.ToInt64()) belongs to PID $ownerPid, expected $ProcId; input aborted"
  }
  return $currentMainWindowHandle
}

function Assert-ForegroundOwned {
  $currentMainWindowHandle = Assert-CurrentTargetMainWindow
  $foreground = [StudioInput]::GetForegroundWindow()
  if ($foreground -eq [IntPtr]::Zero) { throw 'GetForegroundWindow returned zero' }
  if ($foreground -ne $currentMainWindowHandle) {
    throw "foreground HWND $($foreground.ToInt64()) is not the exact target main HWND $($currentMainWindowHandle.ToInt64()); modal, dialog, child, and alternate same-PID windows are forbidden"
  }
  $ownerPid = Get-WindowOwnerPid -WindowHandle $foreground
  if ($ownerPid -ne $ProcId) { throw "foreground PID is $ownerPid, expected $ProcId; input aborted" }
  return [pscustomobject]@{ Handle=$foreground; OwnerPid=$ownerPid }
}

function Wait-WhileGlobalInputHeld {
  param(
    [Parameter(Mandatory = $true)][ValidateRange(1, 2000)][int]$DurationMs,
    [Parameter(Mandatory = $true)][string]$Label
  )

  $stopwatch = [Diagnostics.Stopwatch]::StartNew()
  try {
    while ($stopwatch.ElapsedMilliseconds -lt $DurationMs) {
      Assert-InputDeadline -Label "$Label held-input wait" -RequiredRemainingMs 50
      [void](Assert-ForegroundOwned)
      $remaining = $DurationMs - [int]$stopwatch.ElapsedMilliseconds
      if ($remaining -le 0) { break }
      Start-Sleep -Milliseconds ([Math]::Min(25, $remaining))
    }
    [void](Assert-ForegroundOwned)
  } catch {
    throw "$Label lost exact target foreground while global input was held: $($_.Exception.Message)"
  } finally {
    $stopwatch.Stop()
  }
}

function Get-StrictWindowRect {
  param([Parameter(Mandatory = $true)][IntPtr]$WindowHandle)
  $rect = New-Object StudioInput+RECT
  if (-not [StudioInput]::GetWindowRect($WindowHandle, [ref]$rect)) {
    throw "GetWindowRect failed (win32=$([StudioInput]::LastError()))"
  }
  if ($rect.R -le $rect.L -or $rect.B -le $rect.T) {
    throw "window has invalid rect $($rect.L),$($rect.T),$($rect.R),$($rect.B)"
  }
  return $rect
}

function Get-VirtualScreenRect {
  $left = [StudioInput]::GetSystemMetrics(76); $top = [StudioInput]::GetSystemMetrics(77)
  $width = [StudioInput]::GetSystemMetrics(78); $height = [StudioInput]::GetSystemMetrics(79)
  if ($width -le 0 -or $height -le 0) {
    throw "GetSystemMetrics returned invalid virtual screen ${left},${top},${width},${height}"
  }
  return [pscustomobject]@{ L=$left; T=$top; R=$left+$width; B=$top+$height; Width=$width; Height=$height }
}

function Assert-PointInVirtualScreen {
  param([int]$X, [int]$Y, $VirtualScreen, [string]$Label)
  if ($X -lt $VirtualScreen.L -or $X -ge $VirtualScreen.R -or
      $Y -lt $VirtualScreen.T -or $Y -ge $VirtualScreen.B) {
    throw "$Label coordinate $X,$Y is outside virtual screen $($VirtualScreen.L),$($VirtualScreen.T),$($VirtualScreen.R),$($VirtualScreen.B)"
  }
}

function Assert-PointOwnedByTarget {
  param([int]$X, [int]$Y, [string]$Label)
  $foregroundInfo = Assert-ForegroundOwned
  $point = New-Object StudioInput+POINT
  $point.X = $X; $point.Y = $Y
  $pointWindow = [StudioInput]::WindowFromPoint($point)
  if ($pointWindow -eq [IntPtr]::Zero) { throw "$Label point $X,$Y has no owning window" }
  $rootWindow = [StudioInput]::GetAncestor($pointWindow, 2) # GA_ROOT
  if ($rootWindow -eq [IntPtr]::Zero) {
    throw "$Label point $X,$Y root-window lookup failed (win32=$([StudioInput]::LastError()))"
  }
  if ($rootWindow -ne [IntPtr]$foregroundInfo.Handle) {
    throw "$Label point $X,$Y resolves to root HWND $($rootWindow.ToInt64()), expected exact target main HWND $(([IntPtr]$foregroundInfo.Handle).ToInt64())"
  }
  $rootOwnerPid = Get-WindowOwnerPid -WindowHandle $rootWindow
  if ($rootOwnerPid -ne $ProcId) { throw "$Label point $X,$Y root belongs to PID $rootOwnerPid, expected $ProcId" }
}

function Acquire-TargetForeground {
  $currentMainWindowHandle = Assert-CurrentTargetMainWindow
  # ShowWindowAsync avoids a synchronous cross-thread call into a hung Studio UI.
  # A false return means the async operation was not successfully started. Only
  # minimized windows need a restore request; every queued request is verified after it.
  if ([StudioInput]::IsIconic($currentMainWindowHandle)) {
    $restoreQueued = [StudioInput]::ShowWindowAsync($currentMainWindowHandle, 9)
    if (-not $restoreQueued) {
      throw "ShowWindowAsync failed to queue restore for target main HWND $($currentMainWindowHandle.ToInt64())"
    }
    Start-Sleep -Milliseconds 200
    $currentMainWindowHandle = Assert-CurrentTargetMainWindow
    if ([StudioInput]::IsIconic($currentMainWindowHandle)) {
      throw "target main HWND $($currentMainWindowHandle.ToInt64()) remained minimized after asynchronous restore request"
    }
  }
  $attemptErrors = New-Object 'System.Collections.Generic.List[string]'

  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try {
      $currentMainWindowHandle = Assert-CurrentTargetMainWindow
      $foreground = [StudioInput]::GetForegroundWindow()
      if ($foreground -eq $currentMainWindowHandle -and
          (Get-WindowOwnerPid -WindowHandle $foreground) -eq $ProcId) { return }

      $setResult = [StudioInput]::SetForegroundWindow($currentMainWindowHandle)
      if (-not $setResult) {
        $attemptErrors.Add("attempt $attempt direct SetForegroundWindow failed (win32=$([StudioInput]::LastError()))")
      }
      Start-Sleep -Milliseconds 250
      $foreground = [StudioInput]::GetForegroundWindow()
      if ($foreground -eq $currentMainWindowHandle -and
          (Get-WindowOwnerPid -WindowHandle $foreground) -eq $ProcId) { return }
      if ($foreground -eq [IntPtr]::Zero) { $attemptErrors.Add("attempt $attempt foreground handle was zero"); continue }

      $foregroundOwnerPid = [uint32]0
      $foregroundThread = [StudioInput]::GetWindowThreadProcessId($foreground, [ref]$foregroundOwnerPid)
      $currentThread = [StudioInput]::GetCurrentThreadId()
      if ($foregroundThread -eq 0) { $attemptErrors.Add("attempt $attempt could not resolve foreground thread"); continue }
      $attached = $false
      if ($foregroundThread -ne $currentThread) {
        $attached = [StudioInput]::AttachThreadInput($currentThread, $foregroundThread, $true)
        if (-not $attached) {
          $attemptErrors.Add("attempt $attempt AttachThreadInput failed (win32=$([StudioInput]::LastError()))")
          continue
        }
      }
      try {
        $currentMainWindowHandle = Assert-CurrentTargetMainWindow
        $setResult = [StudioInput]::SetForegroundWindow($currentMainWindowHandle)
        if (-not $setResult) {
          $attemptErrors.Add("attempt $attempt attached SetForegroundWindow failed (win32=$([StudioInput]::LastError()))")
        }
      } finally {
        if ($attached -and -not [StudioInput]::AttachThreadInput($currentThread, $foregroundThread, $false)) {
          throw "AttachThreadInput detach failed (win32=$([StudioInput]::LastError()))"
        }
      }
      Start-Sleep -Milliseconds 300
      $foreground = [StudioInput]::GetForegroundWindow()
      if ($foreground -eq $currentMainWindowHandle -and
          (Get-WindowOwnerPid -WindowHandle $foreground) -eq $ProcId) { return }
      $actualHandle = if ($foreground -eq [IntPtr]::Zero) { 0 } else { $foreground.ToInt64() }
      $attemptErrors.Add("attempt $attempt foreground HWND $actualHandle did not equal exact target main HWND $($currentMainWindowHandle.ToInt64()) after SetForegroundWindow")
    } catch {
      # AttachThreadInput を解除できない状態で再試行すると、別 window へ入力する危険がある。
      if ($_.Exception.Message -like 'AttachThreadInput detach failed*') { throw }
      $attemptErrors.Add("attempt ${attempt}: $($_.Exception.Message)")
    }
  }
  try { [void](Assert-ForegroundOwned) } catch {
    $attemptErrors.Add($_.Exception.Message)
    throw "could not acquire target foreground: $($attemptErrors -join '; ')"
  }
}

function Send-KeyStrict {
  param([string]$Key, [bool]$Release)
  $scan = [uint16][StudioInput]::MapVirtualKey([uint32]$vkMap[$Key], 0)
  if ($scan -eq 0) { throw "MapVirtualKey returned zero for $Key" }
  $sent = [StudioInput]::KeyScan($scan, $Release, ($extKeys -contains $Key))
  if ($sent -ne 1) {
    throw "SendInput key=$Key release=$Release sent=$sent/1 (win32=$([StudioInput]::LastError()))"
  }
}

function Release-KeyBestEffort {
  param([string]$Key)
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    try { Send-KeyStrict -Key $Key -Release $true; return $true } catch {
      if ($attempt -lt 3) { Start-Sleep -Milliseconds 20 }
    }
  }
  return $false
}

function Release-MouseBestEffort {
  for ($attempt = 1; $attempt -le 3; $attempt++) {
    $sent = [StudioInput]::MouseButton($true)
    if ($sent -eq 1) { return $true }
    if ($attempt -lt 3) { Start-Sleep -Milliseconds 20 }
  }
  return $false
}

$virtualScreen = Get-VirtualScreenRect
$targetMainWindowHandle = Assert-CurrentTargetMainWindow
$initialRect = Get-StrictWindowRect -WindowHandle $targetMainWindowHandle

# OS 入力や foreground 変更より前に、全 action の動的座標も検証する。
foreach ($action in $plan) {
  if ($action.Kind -eq 'absclick') {
    Assert-PointInVirtualScreen -X $action.X -Y $action.Y -VirtualScreen $virtualScreen -Label "action[$($action.Index)] absclick"
  } elseif ($action.Kind -eq 'click' -and $null -ne $action.X) {
    $initialWidth = $initialRect.R - $initialRect.L; $initialHeight = $initialRect.B - $initialRect.T
    if ($action.X -ge $initialWidth -or $action.Y -ge $initialHeight) {
      throw "action[$($action.Index)] click offset $($action.X),$($action.Y) is outside initial window size ${initialWidth}x${initialHeight}"
    }
    Assert-PointInVirtualScreen -X ($initialRect.L+$action.X) -Y ($initialRect.T+$action.Y) -VirtualScreen $virtualScreen -Label "action[$($action.Index)] click"
  }
}

Assert-InputDeadline -Label 'foreground acquisition' `
  -RequiredRemainingMs ($remainingPlanDurationMs[0] + 5000L)
Acquire-TargetForeground
[void](Assert-ForegroundOwned)
Assert-InputDeadline -Label 'input plan after foreground acquisition' `
  -RequiredRemainingMs ($remainingPlanDurationMs[0] + 2000L)

$heldKeys = @{}
$mouseDown = $false
$actionsCompleted = 0
$operationError = $null
$cleanupFailures = New-Object 'System.Collections.Generic.List[string]'
$lastRect = $initialRect

try {
  foreach ($action in $plan) {
    Assert-InputDeadline -Label "action[$($action.Index)] $($action.Kind)" `
      -RequiredRemainingMs ($remainingPlanDurationMs[[int]$action.Index] + 2000L)
    $foregroundInfo = Assert-ForegroundOwned
    switch ($action.Kind) {
      'press' {
        Assert-InputDeadline -Label "action[$($action.Index)] key-down" `
          -RequiredRemainingMs ([long]$action.DurationMs + 500L)
        Send-KeyStrict -Key $action.Key -Release $false
        $heldKeys[$action.Key] = $true
        try {
          Wait-WhileGlobalInputHeld -DurationMs $action.DurationMs `
            -Label "press:$($action.Key)"
          Send-KeyStrict -Key $action.Key -Release $true
          [void]$heldKeys.Remove($action.Key)
        } catch {
          $releaseRecovered = Release-KeyBestEffort -Key $action.Key
          if ($releaseRecovered) { [void]$heldKeys.Remove($action.Key) }
          throw "press release failed for $($action.Key); compensating release succeeded=$releaseRecovered; $($_.Exception.Message)"
        }
      }
      'wait' {
        Wait-WithinInputDeadline -DurationMs $action.DurationMs `
          -Label "action[$($action.Index)] wait"
      }
      { $_ -eq 'click' -or $_ -eq 'absclick' } {
        if ($action.Kind -eq 'click') {
          $lastRect = Get-StrictWindowRect -WindowHandle $foregroundInfo.Handle
          $windowWidth = $lastRect.R - $lastRect.L; $windowHeight = $lastRect.B - $lastRect.T
          if ($null -ne $action.X) {
            if ($action.X -ge $windowWidth -or $action.Y -ge $windowHeight) {
              throw "action[$($action.Index)] click offset $($action.X),$($action.Y) is outside current window size ${windowWidth}x${windowHeight}"
            }
            $clickX = $lastRect.L + $action.X; $clickY = $lastRect.T + $action.Y
          } else {
            $clickX = $lastRect.L + [int][Math]::Floor($windowWidth / 2.0)
            $clickY = $lastRect.T + [int][Math]::Floor($windowHeight / 2.0)
          }
        } else {
          $clickX = $action.X; $clickY = $action.Y
        }

        Assert-PointInVirtualScreen -X $clickX -Y $clickY -VirtualScreen $virtualScreen -Label "action[$($action.Index)] $($action.Kind)"
        Assert-PointOwnedByTarget -X $clickX -Y $clickY -Label "action[$($action.Index)] $($action.Kind)"
        Assert-InputDeadline -Label "action[$($action.Index)] cursor move" -RequiredRemainingMs 1000
        if (-not [StudioInput]::SetCursorPos($clickX, $clickY)) {
          throw "SetCursorPos failed at $clickX,$clickY (win32=$([StudioInput]::LastError()))"
        }
        $actualCursor = New-Object StudioInput+POINT
        if (-not [StudioInput]::GetCursorPos([ref]$actualCursor)) {
          throw "GetCursorPos failed after SetCursorPos (win32=$([StudioInput]::LastError()))"
        }
        if ($actualCursor.X -ne $clickX -or $actualCursor.Y -ne $clickY) {
          throw "cursor landed at $($actualCursor.X),$($actualCursor.Y), expected $clickX,$clickY"
        }
        Assert-PointOwnedByTarget -X $clickX -Y $clickY -Label "action[$($action.Index)] $($action.Kind) after cursor move"
        Assert-InputDeadline -Label "action[$($action.Index)] mouse-down" -RequiredRemainingMs 500
        $mouseSent = [StudioInput]::MouseButton($false)
        if ($mouseSent -ne 1) {
          throw "SendInput mouse-down sent=$mouseSent/1 (win32=$([StudioInput]::LastError()))"
        }
        $mouseDown = $true
        try {
          Wait-WhileGlobalInputHeld -DurationMs 120 -Label 'left mouse click'
          $mouseSent = [StudioInput]::MouseButton($true)
          if ($mouseSent -ne 1) {
            throw "SendInput mouse-up sent=$mouseSent/1 (win32=$([StudioInput]::LastError()))"
          }
          $mouseDown = $false
        } catch {
          $releaseRecovered = Release-MouseBestEffort
          if ($releaseRecovered) { $mouseDown = $false }
          throw "mouse-up failed; compensating release succeeded=$releaseRecovered; $($_.Exception.Message)"
        }
        Start-Sleep -Milliseconds 150
      }
    }
    $actionsCompleted++
  }
} catch {
  $operationError = $_
} finally {
  if ($mouseDown) {
    if (Release-MouseBestEffort) { $mouseDown = $false }
    else { $cleanupFailures.Add('left mouse button release failed after 3 attempts') }
  }
  foreach ($key in @($heldKeys.Keys)) {
    if (Release-KeyBestEffort -Key $key) { [void]$heldKeys.Remove($key) }
    else { $cleanupFailures.Add("key release failed after 3 attempts: $key") }
  }
}

$finalForegroundPid = $null
try {
  $finalForegroundHandle = [StudioInput]::GetForegroundWindow()
  if ($finalForegroundHandle -ne [IntPtr]::Zero) {
    $finalForegroundPid = Get-WindowOwnerPid -WindowHandle $finalForegroundHandle
  }
} catch { $cleanupFailures.Add("could not read final foreground owner: $($_.Exception.Message)") }

$succeeded = ($null -eq $operationError -and $cleanupFailures.Count -eq 0 -and $heldKeys.Count -eq 0 -and -not $mouseDown)
$result = [pscustomobject]@{
  ResultType='StudioInputResult'; Success=$succeeded; DryRun=$false; TargetValidationPerformed=$true
  ProcId=$ProcId; SessionId=$ExpectedSessionId
  ExpectedStartTimeUtc=$ExpectedStartTimeUtc; ExpectedStartTimeTicks=$expectedStartTimeUtcValue.Ticks
  ActualStartTimeUtc=$actualTargetStartTimeUtc.ToString('o'); ActualStartTimeTicks=$actualTargetStartTimeUtc.Ticks
  ProcessName=$requiredProcessFileName; ExecutablePath=$targetExecutablePath; OsInputAuthorized=$true
  VerifiedHelperPath=$VerifiedHelperPath; VerifiedHelperSha256=$VerifiedHelperSha256
  VerifiedHelperFileIdentity=$VerifiedHelperFileIdentity; VerifiedInMemoryDispatch=$true
  InputDeadlineUtc=$InputDeadlineUtc; EstimatedMaximumDurationMs=$estimatedMaximumDurationMs
  InitialWindowRect="$($initialRect.L),$($initialRect.T),$($initialRect.R),$($initialRect.B)"
  LastWindowRect="$($lastRect.L),$($lastRect.T),$($lastRect.R),$($lastRect.B)"
  VirtualScreenRect="$($virtualScreen.L),$($virtualScreen.T),$($virtualScreen.R),$($virtualScreen.B)"
  CoordinateSystem='Windows virtual-screen coordinates; negative X/Y are valid for absclick'
  ActionsRequested=$plan.Count; ActionsCompleted=$actionsCompleted; FinalForegroundPid=$finalForegroundPid
  HeldKeysRemaining=@($heldKeys.Keys); MouseButtonRemainingDown=$mouseDown
  CleanupFailures=@($cleanupFailures.ToArray())
  Error=if ($null -ne $operationError) { $operationError.Exception.Message } else { $null }
  TimestampUtc=[DateTime]::UtcNow.ToString('o')
}
Write-Output $result
if (-not $succeeded) {
  $failureParts = New-Object 'System.Collections.Generic.List[string]'
  if ($null -ne $operationError) { $failureParts.Add($operationError.Exception.Message) }
  foreach ($failure in $cleanupFailures) { $failureParts.Add($failure) }
  if ($heldKeys.Count -gt 0) { $failureParts.Add("held keys remain: $(@($heldKeys.Keys) -join ',')") }
  if ($mouseDown) { $failureParts.Add('left mouse button may remain down') }
  throw "studio input failed: $($failureParts -join '; ')"
}
