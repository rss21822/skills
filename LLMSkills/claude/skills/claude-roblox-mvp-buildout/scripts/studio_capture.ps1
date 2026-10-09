<#
.SYNOPSIS
Captures one verified Studio window, or the Windows virtual screen after explicit consent.

.DESCRIPTION
Window mode binds the capture to an exact process identity: PID, Windows session ID,
process name, executable path, manifest-recorded process start time, HWND,
and HWND owner PID. The window must be visible. Minimized windows and foreground
requirements are opt-in because PrintWindow can legitimately capture a background
window. PrintWindow runs only inside a hidden PowerShell child with a bounded deadline
(15 seconds by default, configurable to 1..60). A timeout terminates only that child;
the target Studio process is never a termination target.

Capture allocation is capped at 8192 pixels per dimension, 9,437,184 total pixels,
and 36 MiB for both raw 32-bpp storage and decoded PNG bytes. This admits common 4K
captures but deliberately rejects 8K and oversized multi-monitor surfaces.

  Full-screen mode also runs CopyFromScreen only in a hidden bounded worker (15 seconds
  by default, configurable with -FullScreenTimeoutSeconds). It captures every monitor
  in the Windows virtual screen and can include
passwords, messages, notifications, and unrelated applications. Supplying
-AllowFullScreenCapture is an assertion that the user explicitly approved this capture
for the current run and that sensitive windows were hidden first. The script cannot
verify that human authorization; callers must retain it in their evidence ledger.

  Both modes require OutFile beneath a caller-supplied canonical local-fixed
  TrustedEvidenceRoot and write PNG only. The PNG is encoded and verified in the destination directory,
then committed with an atomic same-directory move/replace. A failure before atomic commit
never publishes the temporary image; a post-commit boundary/hash verification failure can
leave the committed PNG for manual quarantine. Existing files require -Force.

This file is an internal helper and rejects direct file execution, including DryRun.
studio_session.ps1 first validates manifest ownership and fresh role/place evidence for
window mode, holds and hashes the exact helper bytes, and dispatches only that memory
snapshot. RepositoryRoot must be the caller-supplied exact Git worktree root. The helper
rechecks its canonical path/SHA-256/single-link identity and requires its scripts root to
remain physically disjoint from the repository, Git administration roots,
TrustedEvidenceRoot, and every known TEMP root. Invoke the public session action from a
fresh exact OS System32 Windows PowerShell 5.1 host with -NoProfile -NonInteractive; ambient critical-command
shadowing is rejected before path, process, worker, or commit checks.

Coordinates in the PNG are zero-based bitmap coordinates. Convert a bitmap point to an
OS virtual-screen point with: AbsoluteX = BitmapX + OriginX and
AbsoluteY = BitmapY + OriginY. OriginX/OriginY may be negative on multi-monitor systems.

.EXAMPLE
# This image is visual context, not proof of role, place, or gameplay success.
$powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
# actualの前に、同一argsへ-DryRunを付けた別fresh childを先行する。
& $powershellHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat XML `
  -File '<SKILL.md本文で展開済みの絶対path>\scripts\studio_session.ps1' -Action Capture -SessionFile $session `
  -RepositoryRoot $repo -TrustedEvidenceRoot $trusted -StudioExecutablePath $studio `
  -TargetPid 1234 -OutFile 'D:\RobloxMvpEvidence\run-guid\studio-window.png'

.EXAMPLE
$powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
# actualの前に、同一argsへ-DryRunを付けた別fresh childを先行する。
& $powershellHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat XML `
  -File '<SKILL.md本文で展開済みの絶対path>\scripts\studio_session.ps1' -Action Capture -SessionFile $session `
  -RepositoryRoot $repo -TrustedEvidenceRoot $trusted -StudioExecutablePath $studio `
  -FullScreen -AllowFullScreenCapture `
  -OutFile 'D:\RobloxMvpEvidence\run-guid\virtual-screen.png'

.EXAMPLE
$powershellHost = [IO.Path]::Combine([Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
& $powershellHost -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -OutputFormat XML `
  -File '<SKILL.md本文で展開済みの絶対path>\scripts\studio_session.ps1' -Action Capture -SessionFile $session -DryRun `
  -RepositoryRoot $repo -TrustedEvidenceRoot $trusted -StudioExecutablePath $studio `
  -FullScreen -AllowFullScreenCapture `
  -OutFile 'D:\RobloxMvpEvidence\run-guid\virtual-screen.png'
#>
[CmdletBinding(DefaultParameterSetName = 'Window')]
param(
  [Parameter(Mandatory = $true, ParameterSetName = 'Window')]
  [ValidateRange(1, [int]::MaxValue)]
  [int]$ProcId,

  [Parameter(Mandatory = $true, ParameterSetName = 'Window')]
  [ValidateRange(0, [int]::MaxValue)]
  [int]$ExpectedSessionId,

  [Parameter(Mandatory = $true, ParameterSetName = 'Window')]
  [ValidateNotNullOrEmpty()]
  [string]$ExpectedProcessName,

  [Parameter(Mandatory = $true, ParameterSetName = 'Window')]
  [ValidateNotNullOrEmpty()]
  [string]$ExpectedExecutablePath,

  [Parameter(Mandatory = $true, ParameterSetName = 'Window')]
  [DateTimeOffset]$ExpectedStartTimeUtc,

  [Parameter(ParameterSetName = 'Window')]
  [switch]$RequireForeground,

  [Parameter(ParameterSetName = 'Window')]
  [switch]$AllowMinimized,

  [Parameter(ParameterSetName = 'Window')]
  [ValidateRange(1, 60)]
  [int]$PrintWindowTimeoutSeconds = 15,

  [Parameter(Mandatory = $true, ParameterSetName = 'FullScreen')]
  [switch]$FullScreen,

  [Parameter(Mandatory = $true, ParameterSetName = 'FullScreen')]
  [switch]$AllowFullScreenCapture,

  [Parameter(ParameterSetName = 'FullScreen')]
  [ValidateRange(1, 60)]
  [int]$FullScreenTimeoutSeconds = 15,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$OutFile,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$TrustedEvidenceRoot,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$RepositoryRoot,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string]$ExpectedScriptPath,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9a-f]{64}$')]
  [string]$ExpectedScriptSha256,

  [Parameter(Mandatory = $true)]
  [ValidatePattern('^[0-9A-F]{8}:[0-9A-F]{8}:[0-9A-F]{8}:1$')]
  [string]$ExpectedScriptFileIdentity,

  [switch]$VerifiedInMemoryDispatch,

  [switch]$Force,
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
  throw "studio_capture.ps1 requires the exact OS System32 Windows PowerShell 5.1 host: $entryExpectedHostPath"
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

function Assert-TrustedCaptureEntryFilePath {
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

function Assert-NoAmbientCaptureCommandShadowing {
  $expected = @(
    @('Add-Type', 'Microsoft.PowerShell.Utility'),
    @('ConvertFrom-Json', 'Microsoft.PowerShell.Utility'),
    @('ConvertTo-Json', 'Microsoft.PowerShell.Utility'),
    @('Get-AuthenticodeSignature', 'Microsoft.PowerShell.Security'),
    @('Get-Command', 'Microsoft.PowerShell.Core'),
    @('Get-Item', 'Microsoft.PowerShell.Management'),
    @('Get-Process', 'Microsoft.PowerShell.Management'),
    @('Join-Path', 'Microsoft.PowerShell.Management'),
    @('New-Object', 'Microsoft.PowerShell.Utility'),
    @('Remove-Item', 'Microsoft.PowerShell.Management'),
    @('Select-Object', 'Microsoft.PowerShell.Utility'),
    @('Split-Path', 'Microsoft.PowerShell.Management'),
    @('Test-Path', 'Microsoft.PowerShell.Management'),
    @('Where-Object', 'Microsoft.PowerShell.Core'),
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
    if ($resolved.Count -eq 0 -or
        $resolved[0].CommandType -ne [System.Management.Automation.CommandTypes]::Cmdlet -or
        [string]$resolved[0].ModuleName -cne [string]$entry[1] -or
        -not $dllTrusted -or -not $modulePathTrusted) {
      throw "Ambient command shadowing is forbidden for '$($entry[0])'; expected first resolution to the trusted $($entry[1]) cmdlet from PSHOME/GAC."
    }

    if (-not $validatedPowerShellFiles.ContainsKey($resolvedDllFull)) {
      $resolvedDllFull = Assert-TrustedCaptureEntryFilePath -Path $resolvedDllFull `
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
      $resolvedModulePath = Assert-TrustedCaptureEntryFilePath -Path $resolvedModulePath `
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
  $currentHostPath = Assert-TrustedCaptureEntryFilePath -Path $currentHostPath `
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

Assert-NoAmbientCaptureCommandShadowing

if ($null -ne ('RobloxMvpStudioCaptureNative' -as [type])) {
  throw "A preexisting 'RobloxMvpStudioCaptureNative' type is forbidden; run this action in a fresh exact System32 Windows PowerShell 5.1 host."
}

$captureDispatchSourceFile = [string]$MyInvocation.MyCommand.ScriptBlock.File
if (-not $VerifiedInMemoryDispatch.IsPresent -or
    -not [string]::IsNullOrEmpty($captureDispatchSourceFile)) {
  throw 'studio_capture.ps1 accepts only a verified in-memory dispatch from studio_session.ps1; direct file execution is forbidden.'
}
$script:MaxCaptureDimension = 8192
$script:MaxCapturePixels = 9437184
$script:MaxCaptureRawBytes = 37748736
$script:MaxCapturePngBytes = 37748736
$script:MaxCaptureBase64Chars = 50331648
$script:MaxWorkerProtocolHeaderChars = 128

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
  throw 'studio_capture.ps1 requires Windows.'
}

function Assert-CaptureCompilerTempSafety {
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

Assert-CaptureCompilerTempSafety

Add-Type -AssemblyName System.Windows.Forms, System.Drawing -ErrorAction Stop

Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class RobloxMvpStudioCaptureNative {
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
  private const uint FILE_SHARE_READ = 0x1;
  private const uint FILE_SHARE_WRITE = 0x2;
  private const uint FILE_SHARE_DELETE = 0x4;
  private const uint OPEN_EXISTING = 3;
  private const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;

  [StructLayout(LayoutKind.Sequential)]
  public struct RECT {
    public int Left;
    public int Top;
    public int Right;
    public int Bottom;
  }

  [DllImport("user32.dll", SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

  [DllImport("user32.dll", SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool IsWindow(IntPtr hWnd);

  [DllImport("user32.dll", SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool IsWindowVisible(IntPtr hWnd);

  [DllImport("user32.dll", SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool IsIconic(IntPtr hWnd);

  [DllImport("user32.dll")]
  public static extern IntPtr GetForegroundWindow();

  [DllImport("user32.dll", SetLastError = true)]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  private static extern SafeFileHandle CreateFileW(string fileName, uint desiredAccess,
    uint shareMode, IntPtr securityAttributes, uint creationDisposition,
    uint flagsAndAttributes, IntPtr templateFile);

  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  private static extern uint GetFinalPathNameByHandleW(SafeFileHandle file,
    StringBuilder path, uint pathLength, uint flags);

  [DllImport("kernel32.dll", SetLastError = true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  private static extern bool GetFileInformationByHandle(SafeFileHandle file,
    out BY_HANDLE_FILE_INFORMATION information);

  public static string FinalPathOf(string path, bool directory) {
    uint flags = directory ? FILE_FLAG_BACKUP_SEMANTICS : 0;
    using (SafeFileHandle handle = CreateFileW(path, FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, IntPtr.Zero,
      OPEN_EXISTING, flags, IntPtr.Zero)) {
      if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateFileW failed");
      var buffer = new StringBuilder(512);
      uint length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
      if (length == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFinalPathNameByHandleW failed");
      if (length >= buffer.Capacity) {
        buffer = new StringBuilder(checked((int)length + 1));
        length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
        if (length == 0 || length >= buffer.Capacity) throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFinalPathNameByHandleW failed after resizing");
      }
      string result = buffer.ToString();
      if (result.StartsWith(@"\\?\UNC\", StringComparison.OrdinalIgnoreCase)) return @"\\" + result.Substring(8);
      if (result.StartsWith(@"\\?\", StringComparison.OrdinalIgnoreCase)) return result.Substring(4);
      return result;
    }
  }

  public static uint HardLinkCount(string path) {
    using (SafeFileHandle handle = CreateFileW(path, FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, IntPtr.Zero,
      OPEN_EXISTING, 0, IntPtr.Zero)) {
      if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateFileW failed for hard-link validation");
      BY_HANDLE_FILE_INFORMATION information;
      if (!GetFileInformationByHandle(handle, out information)) throw new Win32Exception(Marshal.GetLastWin32Error(), "GetFileInformationByHandle failed");
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
    using (SafeFileHandle handle = CreateFileW(path, FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, IntPtr.Zero,
      OPEN_EXISTING, 0, IntPtr.Zero)) {
      if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateFileW failed for file identity");
      return FileIdentityOfHandle(handle);
    }
  }
}
'@ -ErrorAction Stop

function Test-ContainsWildcard {
  param([Parameter(Mandatory = $true)][string]$Value)
  return [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($Value)
}

function Get-NormalizedCapturePath {
  param([Parameter(Mandatory = $true)][string]$Path)

  $normalized = [System.IO.Path]::GetFullPath($Path)
  $root = [System.IO.Path]::GetPathRoot($normalized)
  if (-not [string]::Equals($normalized, $root, [StringComparison]::OrdinalIgnoreCase)) {
    $normalized = $normalized.TrimEnd([char[]]@('\', '/'))
  }
  return $normalized
}

function Assert-LocalFixedLiteralPathSyntax {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Label,
    [switch]$AllowAlias
  )

  if ([string]::IsNullOrWhiteSpace($Path)) { throw "$Label must not be empty or whitespace." }
  if ($Path.StartsWith('\\', [StringComparison]::Ordinal) -or
      $Path -notmatch '^[A-Za-z]:[\\/]') {
    throw "$Label must be an absolute local drive path; UNC, device, mapped-provider, and relative paths are forbidden."
  }
  if (Test-ContainsWildcard -Value $Path) { throw "$Label must be literal; wildcards are forbidden." }
  $inputComparison = $Path.Replace('/', '\')
  if ($inputComparison.Length -gt 3) { $inputComparison = $inputComparison.TrimEnd('\') }
  try { $fullPath = Get-NormalizedCapturePath -Path $Path } catch {
    throw "$Label is invalid: $($_.Exception.Message)"
  }
  $fullComparison = $fullPath
  if ($fullComparison.Length -gt 3) { $fullComparison = $fullComparison.TrimEnd('\') }
  if (-not $AllowAlias -and
      -not [string]::Equals($inputComparison, $fullComparison, [StringComparison]::OrdinalIgnoreCase)) {
    throw "$Label must already use its normalized long path; aliases and dot segments are forbidden."
  }
  if ($fullPath.Substring(2).Contains(':')) { throw "$Label must not use an alternate data stream." }
  $driveRoot = [System.IO.Path]::GetPathRoot($fullPath)
  try {
    $drive = [System.IO.DriveInfo]::new($driveRoot)
    $driveType = $drive.DriveType
    if ($driveType -ne [System.IO.DriveType]::Fixed) {
      throw "$Label must reside on a local Fixed drive; '$driveRoot' is $driveType."
    }
    if (-not $drive.IsReady) { throw "$Label local Fixed drive '$driveRoot' is not ready." }
  } catch {
    throw "$Label drive validation failed for '$driveRoot': $($_.Exception.Message)"
  }
  return $fullPath
}

function Assert-CapturePathNoReparseAncestors {
  param(
    [Parameter(Mandatory = $true)][string]$ExistingPath,
    [Parameter(Mandatory = $true)][string]$Label
  )

  $cursor = Get-Item -LiteralPath $ExistingPath -Force -ErrorAction Stop
  while ($null -ne $cursor) {
    if (($cursor.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "$Label path must not traverse a reparse point: $($cursor.FullName)"
    }
    $cursor = if ($cursor -is [System.IO.FileInfo]) { $cursor.Directory } else { $cursor.Parent }
  }
}

function Get-CaptureExistingItemWithoutReparseTraversal {
  param(
    [Parameter(Mandatory = $true)][string]$CanonicalLexicalPath,
    [Parameter(Mandatory = $true)][string]$Label
  )

  # Inspect each local path component itself before touching any descendant. Calling
  # Test-Path on the whole value first could traverse a junction into UNC/network I/O.
  $driveRoot = [System.IO.Path]::GetPathRoot($CanonicalLexicalPath)
  try {
    $cursorItem = Get-Item -LiteralPath $driveRoot -Force -ErrorAction Stop
  } catch {
    throw "$Label drive root cannot be inspected safely: $($_.Exception.Message)"
  }
  if (($cursorItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "$Label drive root must not be a reparse point: $driveRoot"
  }

  $relative = $CanonicalLexicalPath.Substring($driveRoot.Length)
  if ([string]::IsNullOrEmpty($relative)) { return $cursorItem }
  $cursorPath = $driveRoot
  foreach ($segment in @($relative.Split([char[]]@('\', '/'), [System.StringSplitOptions]::RemoveEmptyEntries))) {
    $cursorPath = [System.IO.Path]::Combine($cursorPath, $segment)
    try {
      $cursorItem = Get-Item -LiteralPath $cursorPath -Force -ErrorAction Stop
    } catch {
      throw "$Label does not exist or cannot be inspected safely: $cursorPath"
    }
    if (($cursorItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "$Label path must not traverse a reparse point: $cursorPath"
    }
  }
  return $cursorItem
}

function Resolve-CanonicalCaptureExistingPath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Label,
    [switch]$Leaf,
    [switch]$AllowAlias
  )

  $lexical = Assert-LocalFixedLiteralPathSyntax -Path $Path -Label $Label -AllowAlias:$AllowAlias
  $item = Get-CaptureExistingItemWithoutReparseTraversal `
    -CanonicalLexicalPath $lexical -Label $Label
  if ($Leaf -and $item.PSIsContainer) {
    throw "$Label must be an existing file: $lexical"
  }
  $isDirectory = [bool]$item.PSIsContainer
  $physical = Get-NormalizedCapturePath -Path (
    [RobloxMvpStudioCaptureNative]::FinalPathOf($lexical, $isDirectory))
  if (-not $AllowAlias -and
      -not [string]::Equals($lexical, $physical, [StringComparison]::OrdinalIgnoreCase)) {
    throw "$Label must use its canonical physical path; aliases are forbidden. Canonical path: $physical"
  }
  if (-not $isDirectory) {
    $linkCount = [RobloxMvpStudioCaptureNative]::HardLinkCount($physical)
    if ($linkCount -ne 1) {
      throw "$Label must have exactly one directory entry; hard-linked files are forbidden (links=$linkCount)."
    }
  }
  return $physical
}

function Test-CapturePathWithinRoot {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Root,
    [switch]$AllowEqual
  )

  $candidate = Get-NormalizedCapturePath -Path $Path
  $boundary = Get-NormalizedCapturePath -Path $Root
  if ($AllowEqual -and [string]::Equals($candidate, $boundary, [StringComparison]::OrdinalIgnoreCase)) {
    return $true
  }
  $prefix = if ($boundary.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
    $boundary
  } else {
    $boundary + [System.IO.Path]::DirectorySeparatorChar
  }
  return $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Test-CapturePathsOverlap {
  param(
    [Parameter(Mandatory = $true)][string]$First,
    [Parameter(Mandatory = $true)][string]$Second
  )

  return (Test-CapturePathWithinRoot -Path $First -Root $Second -AllowEqual) -or
    (Test-CapturePathWithinRoot -Path $Second -Root $First -AllowEqual)
}

function Read-CaptureBoundedStrictUtf8Text {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Label,
    [ValidateRange(1, 65536)][int]$MaximumBytes = 4096
  )

  $canonical = Resolve-CanonicalCaptureExistingPath -Path $Path -Label $Label -Leaf
  $bytes = [System.IO.File]::ReadAllBytes($canonical)
  if ($bytes.Length -le 0 -or $bytes.Length -gt $MaximumBytes) {
    throw "$Label must be between 1 byte and $MaximumBytes bytes."
  }
  try {
    $text = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    return $text.Trim()
  } catch {
    throw "$Label must be strict UTF-8."
  }
}

function Get-CaptureValidatedGitBoundary {
  param([Parameter(Mandatory = $true)][string]$Path)

  $worktree = Resolve-CanonicalCaptureExistingPath -Path $Path -Label 'RepositoryRoot'
  $worktreeItem = Get-Item -LiteralPath $worktree -Force -ErrorAction Stop
  if (-not $worktreeItem.PSIsContainer) { throw 'RepositoryRoot must be an existing directory.' }

  $administrationRoots = [System.Collections.Generic.List[string]]::new()
  $marker = Join-Path $worktree '.git'
  try { $markerItem = Get-Item -LiteralPath $marker -Force -ErrorAction Stop }
  catch [System.Management.Automation.ItemNotFoundException] { $markerItem = $null }
  if ($null -eq $markerItem) {
    throw 'RepositoryRoot must be the exact Git worktree root containing a direct .git marker.'
  }
  if (($markerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'RepositoryRoot .git marker must not be a reparse point.'
  }
  if ($markerItem.PSIsContainer) {
    $gitDirectory = Resolve-CanonicalCaptureExistingPath -Path $marker `
      -Label 'RepositoryRoot .git directory'
  } else {
    $markerText = Read-CaptureBoundedStrictUtf8Text -Path $marker -Label 'RepositoryRoot .git file'
    if ($markerText -notmatch '^gitdir:\s*(.+)$') {
      throw 'RepositoryRoot .git file must contain one gitdir directive.'
    }
    $gitDirectoryText = [string]$Matches[1]
    if ($gitDirectoryText -match '[\x00-\x1F\x7F]' -or
        (Test-ContainsWildcard -Value $gitDirectoryText)) {
      throw 'RepositoryRoot .git gitdir value contains forbidden characters.'
    }
    $gitDirectoryPath = if ([System.IO.Path]::IsPathRooted($gitDirectoryText)) {
      $gitDirectoryText
    } else {
      [System.IO.Path]::GetFullPath((Join-Path $worktree $gitDirectoryText))
    }
    $gitDirectory = Resolve-CanonicalCaptureExistingPath -Path $gitDirectoryPath `
      -Label 'RepositoryRoot gitdir target'
  }
  $gitDirectoryItem = Get-Item -LiteralPath $gitDirectory -Force -ErrorAction Stop
  if (-not $gitDirectoryItem.PSIsContainer) {
    throw 'RepositoryRoot Git administration path must be an existing directory.'
  }
  $administrationRoots.Add($gitDirectory)

  $commonMarker = Join-Path $gitDirectory 'commondir'
  try { $commonItem = Get-Item -LiteralPath $commonMarker -Force -ErrorAction Stop }
  catch [System.Management.Automation.ItemNotFoundException] { $commonItem = $null }
  if ($null -ne $commonItem) {
    if (($commonItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $commonItem.PSIsContainer) {
      throw 'RepositoryRoot Git commondir marker must be a regular file, not a directory or reparse point.'
    }
    $commonText = Read-CaptureBoundedStrictUtf8Text -Path $commonMarker `
      -Label 'RepositoryRoot Git commondir file'
    if ([string]::IsNullOrWhiteSpace($commonText) -or
        $commonText -match '[\x00-\x1F\x7F]' -or
        (Test-ContainsWildcard -Value $commonText)) {
      throw 'RepositoryRoot Git commondir contains a forbidden path.'
    }
    $commonPath = if ([System.IO.Path]::IsPathRooted($commonText)) {
      $commonText
    } else {
      [System.IO.Path]::GetFullPath((Join-Path $gitDirectory $commonText))
    }
    $commonDirectory = Resolve-CanonicalCaptureExistingPath -Path $commonPath `
      -Label 'RepositoryRoot Git common directory'
    $commonDirectoryItem = Get-Item -LiteralPath $commonDirectory -Force -ErrorAction Stop
    if (-not $commonDirectoryItem.PSIsContainer) {
      throw 'RepositoryRoot Git common directory must be an existing directory.'
    }
    if (-not $administrationRoots.Contains($commonDirectory)) {
      $administrationRoots.Add($commonDirectory)
    }
  }

  return [pscustomobject][ordered]@{
    WorktreeRoot = $worktree
    AdministrationRoots = $administrationRoots.ToArray()
  }
}

function Get-CaptureKnownTempRoots {
  $roots = [System.Collections.Generic.List[string]]::new()
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
    $candidateText = [string]$candidate
    if ($candidateText.StartsWith('\', [StringComparison]::Ordinal) -or
        $candidateText -notmatch '^[A-Za-z]:[\\/]' -or
        (Test-ContainsWildcard -Value $candidateText)) {
      throw "Known TEMP root must use local-drive literal syntax: $candidateText"
    }
    $physical = Resolve-CanonicalCaptureExistingPath -Path $candidateText `
      -Label 'Known TEMP root' -AllowAlias
    $physicalItem = Get-Item -LiteralPath $physical -Force -ErrorAction Stop
    if (-not $physicalItem.PSIsContainer) { throw "Known TEMP root is not a directory: $physical" }
    if (-not $roots.Contains($physical)) { $roots.Add($physical) }
  }
  return $roots.ToArray()
}

function Get-CaptureScriptSnapshot {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Label
  )

  $canonical = Resolve-CanonicalCaptureExistingPath -Path $Path -Label $Label -Leaf
  if ([System.IO.Path]::GetExtension($canonical) -cne '.ps1') { throw "$Label must be a .ps1 file." }
  $stream = $null
  $hasher = $null
  try {
    $stream = [System.IO.File]::Open(
      $canonical,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::Read)
    $length = [int64]$stream.Length
    if ($length -le 0 -or $length -gt 4194304) { throw "$Label must be between 1 byte and 4 MiB." }
    $identity = [RobloxMvpStudioCaptureNative]::FileIdentityOfHandle($stream.SafeFileHandle)
    if ($identity -cnotmatch '^[0-9A-F]{8}:[0-9A-F]{8}:[0-9A-F]{8}:1$') {
      throw "$Label must have one stable file identity and exactly one hard link; got '$identity'."
    }
    $hasher = [Security.Cryptography.SHA256]::Create()
    $hashBytes = $hasher.ComputeHash($stream)
    if ($stream.Length -ne $length) { throw "$Label length changed while it was attested." }
    return [pscustomobject][ordered]@{
      Path = $canonical
      Sha256 = [BitConverter]::ToString($hashBytes).Replace('-', '').ToLowerInvariant()
      FileIdentity = $identity
      Length = $length
    }
  } finally {
    if ($null -ne $hasher) { $hasher.Dispose() }
    if ($null -ne $stream) { $stream.Dispose() }
  }
}

function Get-CaptureSha256Hex {
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

function Assert-OutputDirectoryBoundary {
  param([Parameter(Mandatory = $true)][string]$Directory)

  $canonical = Resolve-CanonicalCaptureExistingPath -Path $Directory -Label 'OutFile parent directory'
  if (-not [string]::Equals($canonical, $Directory, [StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-CapturePathWithinRoot -Path $canonical -Root $script:TrustedEvidenceRootPath -AllowEqual)) {
    throw 'OutFile parent directory must remain canonical and inside TrustedEvidenceRoot.'
  }
}

function Resolve-OutputPath {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][bool]$AllowReplace
  )

  $fullPath = Assert-LocalFixedLiteralPathSyntax -Path $Path -Label 'OutFile'

  if (-not [string]::Equals([System.IO.Path]::GetExtension($fullPath), '.png', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutFile must use the .png extension.'
  }

  $directory = [System.IO.Path]::GetDirectoryName($fullPath)
  if ([string]::IsNullOrWhiteSpace($directory)) {
    throw "OutFile parent directory does not exist: $directory"
  }
  Assert-OutputDirectoryBoundary -Directory $directory
  $canonicalFullPath = Get-NormalizedCapturePath -Path (Join-Path $directory ([System.IO.Path]::GetFileName($fullPath)))
  if (-not [string]::Equals($canonicalFullPath, $fullPath, [StringComparison]::OrdinalIgnoreCase) -or
      -not (Test-CapturePathWithinRoot -Path $canonicalFullPath -Root $script:TrustedEvidenceRootPath)) {
    throw 'OutFile must be a canonical descendant of TrustedEvidenceRoot.'
  }

  $item = $null
  try {
    $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
  } catch [System.Management.Automation.ItemNotFoundException] {
    $item = $null
  }
  $exists = $null -ne $item
  if ($exists) {
    if ($item.PSIsContainer) {
      throw "OutFile points to a directory: $fullPath"
    }
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw "OutFile must not be a reparse point: $fullPath"
    }
    $existingCanonical = Resolve-CanonicalCaptureExistingPath -Path $fullPath -Label 'OutFile' -Leaf
    if (-not [string]::Equals($existingCanonical, $fullPath, [StringComparison]::OrdinalIgnoreCase)) {
      throw 'Existing OutFile must use its canonical physical path.'
    }
    if (-not $AllowReplace) {
      throw "OutFile already exists; pass -Force to replace it atomically: $fullPath"
    }
  }

  return [pscustomobject]@{
    FullPath = $fullPath
    Existed = [bool]$exists
  }
}

function Resolve-ExpectedExecutablePath {
  param([Parameter(Mandatory = $true)][string]$Path)

  return Resolve-CanonicalCaptureExistingPath -Path $Path `
    -Label 'ExpectedExecutablePath' -Leaf
}

function Resolve-ExpectedProcessBaseName {
  param([Parameter(Mandatory = $true)][string]$Name)

  if ([string]::IsNullOrWhiteSpace($Name)) {
    throw 'ExpectedProcessName must not be empty or whitespace.'
  }
  if (Test-ContainsWildcard -Value $Name) {
    throw 'ExpectedProcessName must be exact; wildcard characters are not allowed.'
  }
  if (-not [string]::Equals([System.IO.Path]::GetFileName($Name), $Name, [StringComparison]::Ordinal)) {
    throw 'ExpectedProcessName must be a file name, not a path.'
  }

  $baseName = if ([string]::Equals([System.IO.Path]::GetExtension($Name), '.exe', [StringComparison]::OrdinalIgnoreCase)) {
    [System.IO.Path]::GetFileNameWithoutExtension($Name)
  } else {
    $Name
  }
  if ([string]::IsNullOrWhiteSpace($baseName)) {
    throw 'ExpectedProcessName has no process base name.'
  }
  return $baseName
}

function Get-WindowOwnerPid {
  param([Parameter(Mandatory = $true)][IntPtr]$WindowHandle)

  [uint32]$ownerPid = 0
  $threadId = [RobloxMvpStudioCaptureNative]::GetWindowThreadProcessId($WindowHandle, [ref]$ownerPid)
  if ($threadId -eq 0 -or $ownerPid -eq 0) {
    $lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw "GetWindowThreadProcessId failed for HWND $WindowHandle (Win32Error=$lastError)."
  }
  return [int]$ownerPid
}

function Get-WindowRectStrict {
  param([Parameter(Mandatory = $true)][IntPtr]$WindowHandle)

  $rect = New-Object RobloxMvpStudioCaptureNative+RECT
  if (-not [RobloxMvpStudioCaptureNative]::GetWindowRect($WindowHandle, [ref]$rect)) {
    $lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
    throw "GetWindowRect failed for HWND $WindowHandle (Win32Error=$lastError)."
  }
  $width = $rect.Right - $rect.Left
  $height = $rect.Bottom - $rect.Top
  if ($width -le 0 -or $height -le 0) {
    throw "Window rectangle is invalid: left=$($rect.Left), top=$($rect.Top), right=$($rect.Right), bottom=$($rect.Bottom)."
  }
  return [pscustomobject]@{
    Left = [int]$rect.Left
    Top = [int]$rect.Top
    Right = [int]$rect.Right
    Bottom = [int]$rect.Bottom
    Width = [int]$width
    Height = [int]$height
  }
}

function Assert-CaptureDimensions {
  param(
    [Parameter(Mandatory = $true)][int]$Width,
    [Parameter(Mandatory = $true)][int]$Height,
    [Parameter(Mandatory = $true)][string]$Label
  )

  if ($Width -le 0 -or $Height -le 0) {
    throw "$Label dimensions must be positive; got ${Width}x${Height}."
  }
  if ($Width -gt $script:MaxCaptureDimension -or $Height -gt $script:MaxCaptureDimension) {
    throw "$Label exceeds the per-dimension limit $script:MaxCaptureDimension; got ${Width}x${Height}."
  }
  $pixelCount = [int64]$Width * [int64]$Height
  if ($pixelCount -gt $script:MaxCapturePixels) {
    throw "$Label exceeds the pixel limit $script:MaxCapturePixels; got $pixelCount pixels (${Width}x${Height})."
  }
  $rawBytes = $pixelCount * 4L
  if ($rawBytes -gt $script:MaxCaptureRawBytes) {
    throw "$Label exceeds the 32-bpp raw-byte limit $script:MaxCaptureRawBytes; got $rawBytes bytes."
  }
  return [pscustomobject]@{
    Width = $Width
    Height = $Height
    PixelCount = $pixelCount
    RawBytes = $rawBytes
  }
}

function Get-ForegroundState {
  param(
    [Parameter(Mandatory = $true)][IntPtr]$MainWindowHandle,
    [Parameter(Mandatory = $true)][int]$TargetPid
  )

  $foregroundHandle = [RobloxMvpStudioCaptureNative]::GetForegroundWindow()
  $foregroundPid = 0
  if ($foregroundHandle -ne [IntPtr]::Zero) {
    $foregroundPid = Get-WindowOwnerPid -WindowHandle $foregroundHandle
  }
  return [pscustomobject]@{
    Handle = $foregroundHandle
    Pid = [int]$foregroundPid
    IsTargetProcess = ($foregroundPid -eq $TargetPid)
    IsMainWindow = ($foregroundHandle -eq $MainWindowHandle)
  }
}

function Assert-WindowTarget {
  param(
    [Parameter(Mandatory = $true)][int]$TargetPid,
    [Parameter(Mandatory = $true)][int]$SessionId,
    [Parameter(Mandatory = $true)][string]$ProcessBaseName,
    [Parameter(Mandatory = $true)][string]$ExecutablePath,
    [Parameter(Mandatory = $true)][bool]$MinimizedAllowed,
    [Parameter(Mandatory = $true)][bool]$ForegroundRequired,
    [Parameter()][Nullable[long]]$RequiredStartTimeUtcTicks,
    [Parameter()][Nullable[long]]$RequiredWindowHandle
  )

  try {
    $process = Get-Process -Id $TargetPid -ErrorAction Stop
  } catch {
    throw "Target process $TargetPid was not found: $($_.Exception.Message)"
  }

  if ($process.HasExited) {
    throw "Target process $TargetPid has exited."
  }
  if ($process.SessionId -ne $SessionId) {
    throw "Target session mismatch: expected $SessionId, actual $($process.SessionId)."
  }
  if (-not [string]::Equals($process.ProcessName, $ProcessBaseName, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Target process-name mismatch: expected '$ProcessBaseName', actual '$($process.ProcessName)'."
  }

  try {
    $actualExecutablePath = [System.IO.Path]::GetFullPath($process.MainModule.FileName)
  } catch {
    throw "Cannot read executable path for process ${TargetPid}: $($_.Exception.Message)"
  }
  if (-not [string]::Equals($actualExecutablePath, $ExecutablePath, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Target executable mismatch: expected '$ExecutablePath', actual '$actualExecutablePath'."
  }

  try {
    $startTimeUtc = $process.StartTime.ToUniversalTime()
  } catch {
    throw "Cannot read start time for process ${TargetPid}: $($_.Exception.Message)"
  }
  if ($null -ne $RequiredStartTimeUtcTicks -and $startTimeUtc.Ticks -ne [long]$RequiredStartTimeUtcTicks) {
    throw "Target process identity changed: expected start ticks $([long]$RequiredStartTimeUtcTicks), actual $($startTimeUtc.Ticks)."
  }

  $windowHandle = $process.MainWindowHandle
  if ($windowHandle -eq [IntPtr]::Zero) {
    throw "Target process $TargetPid has no main window."
  }
  if ($null -ne $RequiredWindowHandle -and $windowHandle.ToInt64() -ne [long]$RequiredWindowHandle) {
    throw "Target main HWND changed: expected $([long]$RequiredWindowHandle), actual $($windowHandle.ToInt64())."
  }
  if (-not [RobloxMvpStudioCaptureNative]::IsWindow($windowHandle)) {
    throw "Target HWND $windowHandle is not a valid window."
  }
  $ownerPid = Get-WindowOwnerPid -WindowHandle $windowHandle
  if ($ownerPid -ne $TargetPid) {
    throw "Target HWND owner mismatch: expected PID $TargetPid, actual PID $ownerPid."
  }
  if (-not [RobloxMvpStudioCaptureNative]::IsWindowVisible($windowHandle)) {
    throw "Target HWND $windowHandle is not visible."
  }

  $isMinimized = [RobloxMvpStudioCaptureNative]::IsIconic($windowHandle)
  if ($isMinimized -and -not $MinimizedAllowed) {
    throw 'Target window is minimized; restore it or pass -AllowMinimized explicitly.'
  }

  $foreground = Get-ForegroundState -MainWindowHandle $windowHandle -TargetPid $TargetPid
  if ($ForegroundRequired -and -not $foreground.IsMainWindow) {
    throw "Target main window is not the exact foreground HWND; foreground PID is $($foreground.Pid), foreground HWND is $($foreground.Handle). Same-process modal windows do not satisfy -RequireForeground."
  }

  $rect = Get-WindowRectStrict -WindowHandle $windowHandle
  return [pscustomobject]@{
    Process = $process
    ExecutablePath = $actualExecutablePath
    StartTimeUtc = $startTimeUtc
    WindowHandle = $windowHandle
    WindowRect = $rect
    IsVisible = $true
    IsMinimized = [bool]$isMinimized
    Foreground = $foreground
  }
}

function Assert-WindowSnapshotStable {
  param(
    [Parameter(Mandatory = $true)]$InitialTarget,
    [Parameter(Mandatory = $true)][int]$TargetPid,
    [Parameter(Mandatory = $true)][int]$SessionId,
    [Parameter(Mandatory = $true)][string]$ProcessBaseName,
    [Parameter(Mandatory = $true)][string]$ExecutablePath,
    [Parameter(Mandatory = $true)][bool]$MinimizedAllowed,
    [Parameter(Mandatory = $true)][bool]$ForegroundRequired
  )

  $current = Assert-WindowTarget -TargetPid $TargetPid -SessionId $SessionId `
    -ProcessBaseName $ProcessBaseName -ExecutablePath $ExecutablePath `
    -MinimizedAllowed $MinimizedAllowed -ForegroundRequired $ForegroundRequired `
    -RequiredStartTimeUtcTicks $InitialTarget.StartTimeUtc.Ticks `
    -RequiredWindowHandle $InitialTarget.WindowHandle.ToInt64()

  $before = $InitialTarget.WindowRect
  $after = $current.WindowRect
  if ($before.Left -ne $after.Left -or $before.Top -ne $after.Top -or
      $before.Right -ne $after.Right -or $before.Bottom -ne $after.Bottom) {
    throw 'Target window moved or resized during capture; no output was committed.'
  }
  if ($InitialTarget.IsMinimized -ne $current.IsMinimized) {
    throw 'Target window minimized state changed during capture; no output was committed.'
  }
}

function Save-VerifiedPngAtomically {
  param(
    [Parameter(Mandatory = $true)][System.Drawing.Bitmap]$Bitmap,
    [Parameter(Mandatory = $true)][string]$DestinationPath,
    [Parameter(Mandatory = $true)][bool]$ReplaceExisting,
    [Parameter()][scriptblock]$BeforeCommit
  )

  $directory = [System.IO.Path]::GetDirectoryName($DestinationPath)
  Assert-OutputDirectoryBoundary -Directory $directory
  $leaf = [System.IO.Path]::GetFileName($DestinationPath)
  $temporaryPath = [System.IO.Path]::Combine(
    $directory,
    ".$leaf.$([Guid]::NewGuid().ToString('N')).capture.tmp"
  )
  $temporaryExists = $false

  try {
    $stream = $null
    try {
      $stream = [System.IO.FileStream]::new(
        $temporaryPath,
        [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write,
        [System.IO.FileShare]::None
      )
      $temporaryExists = $true
      $Bitmap.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
      $stream.Flush($true)
    } finally {
      if ($null -ne $stream) { $stream.Dispose() }
    }
    $temporaryItem = Get-Item -LiteralPath $temporaryPath -Force -ErrorAction Stop
    if ($temporaryItem.Length -le 0 -or $temporaryItem.Length -gt $script:MaxCapturePngBytes) {
      throw "Encoded temporary PNG length $($temporaryItem.Length) violates the bounded PNG contract $script:MaxCapturePngBytes."
    }

    $verifiedImage = $null
    try {
      $verifiedImage = [System.Drawing.Image]::FromFile($temporaryPath)
      if ($verifiedImage.Width -ne $Bitmap.Width -or $verifiedImage.Height -ne $Bitmap.Height) {
        throw "Encoded PNG dimensions changed: expected $($Bitmap.Width)x$($Bitmap.Height), actual $($verifiedImage.Width)x$($verifiedImage.Height)."
      }
    } finally {
      if ($null -ne $verifiedImage) { $verifiedImage.Dispose() }
    }

    if ($null -ne $BeforeCommit) {
      $null = & $BeforeCommit
    }
    Assert-OutputDirectoryBoundary -Directory $directory

    if ($ReplaceExisting) {
      if (-not (Test-Path -LiteralPath $DestinationPath -PathType Leaf)) {
        throw 'OutFile changed after validation; expected an existing file before atomic replace.'
      }
      $destinationItem = Get-Item -LiteralPath $DestinationPath -Force -ErrorAction Stop
      if (($destinationItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'OutFile became a reparse point after validation; refusing replacement.'
      }
      [System.IO.File]::Replace($temporaryPath, $DestinationPath, $null, $true)
    } else {
      if (Test-Path -LiteralPath $DestinationPath) {
        throw 'OutFile appeared after validation; refusing to overwrite it.'
      }
      [System.IO.File]::Move($temporaryPath, $DestinationPath)
    }
    $temporaryExists = $false

    $committed = Get-Item -LiteralPath $DestinationPath -Force -ErrorAction Stop
    if ($committed.PSIsContainer -or $committed.Length -le 0 -or
        $committed.Length -gt $script:MaxCapturePngBytes) {
      throw "Committed PNG is invalid: $DestinationPath"
    }
    Assert-OutputDirectoryBoundary -Directory $directory
    $committedCanonical = Resolve-CanonicalCaptureExistingPath -Path $DestinationPath `
      -Label 'Committed OutFile' -Leaf
    if (-not [string]::Equals($committedCanonical, $DestinationPath, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-CapturePathWithinRoot -Path $committedCanonical -Root $script:TrustedEvidenceRootPath)) {
      throw 'Committed PNG escaped its canonical TrustedEvidenceRoot boundary before hashing.'
    }
    $committedHash = Get-CaptureSha256Hex -Path $committedCanonical -Label 'Committed PNG'
    return [pscustomobject]@{
      Path = $committedCanonical
      Length = [int64]$committed.Length
      Sha256 = $committedHash
    }
  } finally {
    if ($temporaryExists -and (Test-Path -LiteralPath $temporaryPath)) {
      Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
  }
}

function Invoke-HiddenPowerShellWorker {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptText,
    [Parameter(Mandatory = $true)][ValidateRange(1, 60)][int]$TimeoutSeconds,
    [Parameter(Mandatory = $true)][int]$ForbiddenProcessId
  )

  $currentProcess = [System.Diagnostics.Process]::GetCurrentProcess()
  $workerExecutable = [System.IO.Path]::GetFullPath($currentProcess.MainModule.FileName)
  $workerLeaf = [System.IO.Path]::GetFileName($workerExecutable)
  if ($workerLeaf -cne 'powershell.exe') {
    throw "Capture worker requires a PowerShell host executable, got '$workerExecutable'."
  }
  $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($ScriptText))
  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $workerExecutable
  $startInfo.WorkingDirectory = [System.IO.Path]::GetDirectoryName($workerExecutable)
  $startInfo.Arguments = "-NoLogo -NoProfile -NonInteractive -EncodedCommand $encodedCommand"
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $systemModulePath = Resolve-CanonicalCaptureExistingPath `
    -Path ([System.IO.Path]::Combine($PSHOME, 'Modules')) `
    -Label 'Capture worker system module directory'
  $systemModulePathItem = Get-Item -LiteralPath $systemModulePath -Force -ErrorAction Stop
  if (-not $systemModulePathItem.PSIsContainer -or
      ($systemModulePathItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'Capture worker system module directory must be an existing non-reparse directory.'
  }
  $startInfo.EnvironmentVariables['PSModulePath'] = $systemModulePathItem.FullName

  $worker = [System.Diagnostics.Process]::new()
  $worker.StartInfo = $startInfo
  $startedAt = [datetime]::UtcNow
  $deadlineUtc = $startedAt.AddSeconds($TimeoutSeconds)
  $stdoutTask = $null
  $stderrTask = $null
  $stdoutReader = $null
  $stderrReader = $null
  try {
    if (-not $worker.Start()) {
      throw 'PowerShell capture worker did not start.'
    }
    if ([int]$worker.Id -eq $ForbiddenProcessId) {
      throw "Capture worker PID unexpectedly equals protected Studio PID $ForbiddenProcessId; refusing any termination action."
    }
    $stdoutReader = $worker.StandardOutput
    $stderrReader = $worker.StandardError
    $stdoutTask = $stdoutReader.ReadToEndAsync()
    $stderrTask = $stderrReader.ReadToEndAsync()
    $timeoutMilliseconds = [int][Math]::Max(0, ($deadlineUtc - [datetime]::UtcNow).TotalMilliseconds)
    if (-not $worker.WaitForExit($timeoutMilliseconds)) {
      # Kill only the dedicated child represented by this Process handle. Never call
      # Stop-Process, and never target the protected caller/Studio PID.
      if ([int]$worker.Id -eq $ForbiddenProcessId) {
        throw "Capture worker timeout identity collision with protected PID $ForbiddenProcessId; worker was not terminated."
      }
      try {
        $worker.Kill()
      } catch {
        throw "Capture worker timed out after $TimeoutSeconds seconds and worker termination failed: $($_.Exception.Message)"
      }
      if (-not $worker.WaitForExit(5000)) {
        throw "Capture worker timed out after $TimeoutSeconds seconds and did not exit within 5 seconds after worker-only termination."
      }
      throw "Capture worker timed out after $TimeoutSeconds seconds; only dedicated worker PID $($worker.Id) was terminated. Protected PID $ForbiddenProcessId was not terminated."
    }

    # A successfully exited worker can leave inherited pipe handles in a descendant.
    # Drain both readers only inside the original common deadline.
    $pipeMilliseconds = [int][Math]::Max(0, ($deadlineUtc - [datetime]::UtcNow).TotalMilliseconds)
    $pipesCompleted = $false
    if ($pipeMilliseconds -gt 0) {
      try {
        $pipesCompleted = [Threading.Tasks.Task]::WaitAll(
          [Threading.Tasks.Task[]]@($stdoutTask, $stderrTask),
          $pipeMilliseconds
        )
      } catch {
        throw "Capture worker pipe read failed inside bounded deadline: $($_.Exception.Message)"
      }
    }
    if (-not $pipesCompleted) {
      try { $stdoutReader.Dispose() } catch {}
      try { $stderrReader.Dispose() } catch {}
      throw "Capture worker exited but stdout/stderr did not close within the common $TimeoutSeconds-second deadline; pipe readers were closed."
    }
    if (-not $stdoutTask.IsCompleted -or $stdoutTask.IsCanceled -or $stdoutTask.IsFaulted -or
        -not $stderrTask.IsCompleted -or $stderrTask.IsCanceled -or $stderrTask.IsFaulted) {
      throw 'Capture worker pipe tasks did not complete successfully inside the bounded deadline.'
    }
    $standardOutput = [string]$stdoutTask.Result
    $standardError = [string]$stderrTask.Result
    return [pscustomobject]@{
      WorkerPid = [int]$worker.Id
      ExitCode = [int]$worker.ExitCode
      StandardOutput = [string]$standardOutput
      StandardError = [string]$standardError
      ElapsedMilliseconds = [int][Math]::Min([int]::MaxValue, ([datetime]::UtcNow - $startedAt).TotalMilliseconds)
    }
  } finally {
    if ($null -ne $stdoutReader) { try { $stdoutReader.Dispose() } catch {} }
    if ($null -ne $stderrReader) { try { $stderrReader.Dispose() } catch {} }
    if ($null -ne $worker) {
      try {
        if (-not $worker.HasExited -and [int]$worker.Id -ne $ForbiddenProcessId) {
          $worker.Kill()
          [void]$worker.WaitForExit(5000)
        }
      } catch {
        # The primary bounded-worker error is preserved. This best-effort path still
        # holds a handle to the dedicated child and never addresses the Studio PID.
      }
      $worker.Dispose()
    }
  }
}

function Invoke-PrintWindowStrict {
  param(
    [Parameter(Mandatory = $true)][IntPtr]$WindowHandle,
    [Parameter(Mandatory = $true)][System.Drawing.Bitmap]$Bitmap,
    [Parameter(Mandatory = $true)][System.Drawing.Graphics]$Graphics,
    [Parameter(Mandatory = $true)][ValidateRange(1, 60)][int]$TimeoutSeconds,
    [Parameter(Mandatory = $true)][int]$TargetProcessId
  )

  $payload = [pscustomobject]@{
    WindowHandle = $WindowHandle.ToInt64()
    Width = $Bitmap.Width
    Height = $Bitmap.Height
    TargetProcessId = $TargetProcessId
    MaxDimension = $script:MaxCaptureDimension
    MaxPixels = $script:MaxCapturePixels
    MaxRawBytes = $script:MaxCaptureRawBytes
    MaxPngBytes = $script:MaxCapturePngBytes
  } | ConvertTo-Json -Compress
  $payloadBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
  $workerTemplate = @'
$null = Microsoft.PowerShell.Core\Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$expectedCommands = @(
  @('Add-Type', 'Microsoft.PowerShell.Utility'),
  @('ConvertFrom-Json', 'Microsoft.PowerShell.Utility')
)
foreach ($entry in $expectedCommands) {
  $resolved = @(Microsoft.PowerShell.Core\Get-Command -Name $entry[0] -All -ErrorAction Stop)
  if ($resolved.Count -eq 0 -or
      $resolved[0].CommandType -ne [System.Management.Automation.CommandTypes]::Cmdlet -or
      [string]$resolved[0].ModuleName -cne [string]$entry[1]) {
    throw "Capture worker command provenance failed for '$($entry[0])'."
  }
}
if ($null -ne ('RobloxMvpPrintWindowWorkerNative' -as [type])) {
  throw "A preexisting 'RobloxMvpPrintWindowWorkerNative' type is forbidden in the dedicated capture worker."
}
Microsoft.PowerShell.Utility\Add-Type -AssemblyName System.Drawing -ErrorAction Stop
Microsoft.PowerShell.Utility\Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class RobloxMvpPrintWindowWorkerNative {
  [DllImport("user32.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
  [DllImport("user32.dll", SetLastError=true)] [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll", SetLastError=true)]
  public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
}
"@ -ErrorAction Stop
try {
  $payloadJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD_BASE64__'))
  $payload = Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $payloadJson
  $width = [int]$payload.Width
  $height = [int]$payload.Height
  if ($width -le 0 -or $height -le 0 -or
      $width -gt [int]$payload.MaxDimension -or $height -gt [int]$payload.MaxDimension) {
    throw "Worker capture dimensions are outside the bounded contract: ${width}x${height}."
  }
  $pixelCount = [int64]$width * [int64]$height
  $rawBytes = $pixelCount * 4L
  if ($pixelCount -gt [int64]$payload.MaxPixels -or $rawBytes -gt [int64]$payload.MaxRawBytes) {
    throw "Worker capture allocation exceeds bounded pixel/raw-byte contract: pixels=$pixelCount rawBytes=$rawBytes."
  }
  $windowHandle = [IntPtr][int64]$payload.WindowHandle
  if (-not [RobloxMvpPrintWindowWorkerNative]::IsWindow($windowHandle)) {
    throw 'Target HWND is no longer a window before PrintWindow.'
  }
  [uint32]$ownerPid = 0
  $threadId = [RobloxMvpPrintWindowWorkerNative]::GetWindowThreadProcessId($windowHandle, [ref]$ownerPid)
  if ($threadId -eq 0 -or [int64]$ownerPid -ne [int64]$payload.TargetProcessId) {
    throw "Target HWND owner changed before PrintWindow: thread=$threadId owner=$ownerPid expected=$($payload.TargetProcessId)."
  }
  $bitmap = $null
  $graphics = $null
  $memory = $null
  try {
    $bitmap = [Drawing.Bitmap]::new($width, $height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $successfulFlag = $null
    $lastError = 0
    foreach ($flag in [uint32[]]@(2, 0)) {
      if ($flag -eq 0) { $graphics.Clear([Drawing.Color]::Transparent) }
      $hdc = [IntPtr]::Zero
      try {
        $hdc = $graphics.GetHdc()
        if ($hdc -eq [IntPtr]::Zero) { throw 'Graphics.GetHdc returned a null HDC.' }
        $ok = [RobloxMvpPrintWindowWorkerNative]::PrintWindow($windowHandle, $hdc, $flag)
        $lastError = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
      } finally {
        if ($hdc -ne [IntPtr]::Zero) { $graphics.ReleaseHdc($hdc) }
      }
      if ($ok) { $successfulFlag = [int]$flag; break }
    }
    if ($null -eq $successfulFlag) {
      throw "PrintWindow failed with both flags (last Win32Error=$lastError)."
    }
    $memory = [IO.MemoryStream]::new()
    $bitmap.Save($memory, [Drawing.Imaging.ImageFormat]::Png)
    $pngBytes = $memory.ToArray()
    if ($pngBytes.Length -le 0 -or $pngBytes.Length -gt [int]$payload.MaxPngBytes) {
      throw "Worker PNG length $($pngBytes.Length) violates bounded PNG contract."
    }
    $pngBase64 = [Convert]::ToBase64String($pngBytes)
    [Console]::Out.Write(("OK:{0}:{1}:{2}`n" -f $successfulFlag, $bitmap.Width, $bitmap.Height))
    [Console]::Out.Write($pngBase64)
  } finally {
    if ($null -ne $memory) { $memory.Dispose() }
    if ($null -ne $graphics) { $graphics.Dispose() }
    if ($null -ne $bitmap) { $bitmap.Dispose() }
  }
} catch {
  $errorBytes = [Text.Encoding]::UTF8.GetBytes($_.Exception.Message)
  [Console]::Out.Write("ERROR`n")
  [Console]::Out.Write([Convert]::ToBase64String($errorBytes))
}
'@
  $workerScript = $workerTemplate.Replace('__PAYLOAD_BASE64__', $payloadBase64)
  $workerResult = Invoke-HiddenPowerShellWorker -ScriptText $workerScript `
    -TimeoutSeconds $TimeoutSeconds -ForbiddenProcessId $TargetProcessId

  $maxProtocolChars = [int64]$script:MaxWorkerProtocolHeaderChars + 1L + [int64]$script:MaxCaptureBase64Chars
  if ([int64]$workerResult.StandardOutput.Length -gt $maxProtocolChars) {
    throw "PrintWindow worker protocol exceeds the bounded character limit $maxProtocolChars."
  }
  $separator = $workerResult.StandardOutput.IndexOf("`n", [StringComparison]::Ordinal)
  if ($separator -lt 0 -or $separator -gt $script:MaxWorkerProtocolHeaderChars) {
    $stderr = if ($workerResult.StandardError.Length -gt 2000) { $workerResult.StandardError.Substring(0, 2000) } else { $workerResult.StandardError }
    throw "PrintWindow worker returned no bounded protocol header (exit=$($workerResult.ExitCode), stderr=$stderr)."
  }
  $header = $workerResult.StandardOutput.Substring(0, $separator).TrimEnd("`r")
  $body = $workerResult.StandardOutput.Substring($separator + 1).Trim()
  if ($header -eq 'ERROR') {
    try { $workerMessage = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($body)) }
    catch { $workerMessage = 'Worker returned an invalid error payload.' }
    throw "PrintWindow worker failed: $workerMessage"
  }
  if ($header -cnotmatch '^OK:(0|2):([1-9][0-9]*):([1-9][0-9]*)$') {
    throw "PrintWindow worker returned an invalid protocol header: '$header'."
  }
  $flag = [int]$Matches[1]
  $reportedWidth = [int]$Matches[2]
  $reportedHeight = [int]$Matches[3]
  if ($reportedWidth -ne $Bitmap.Width -or $reportedHeight -ne $Bitmap.Height) {
    throw "PrintWindow worker dimensions changed: expected $($Bitmap.Width)x$($Bitmap.Height), got ${reportedWidth}x${reportedHeight}."
  }

  if ($body.Length -le 0 -or $body.Length -gt $script:MaxCaptureBase64Chars -or ($body.Length % 4) -ne 0) {
    throw "PrintWindow worker base64 length $($body.Length) violates the bounded protocol contract."
  }
  $padding = if ($body.EndsWith('==', [StringComparison]::Ordinal)) { 2 } elseif ($body.EndsWith('=', [StringComparison]::Ordinal)) { 1 } else { 0 }
  $estimatedDecodedBytes = ([int64]($body.Length / 4) * 3L) - $padding
  if ($estimatedDecodedBytes -le 0 -or $estimatedDecodedBytes -gt $script:MaxCapturePngBytes) {
    throw "PrintWindow worker decoded-length estimate $estimatedDecodedBytes exceeds the bounded PNG contract."
  }
  try { $pngBytes = [Convert]::FromBase64String($body) }
  catch { throw "PrintWindow worker returned invalid PNG base64: $($_.Exception.Message)" }
  if ($pngBytes.Length -le 0 -or $pngBytes.Length -gt $script:MaxCapturePngBytes) {
    throw "PrintWindow worker decoded PNG length $($pngBytes.Length) violates the bounded PNG contract."
  }
  $memory = $null
  $workerImage = $null
  try {
    $memory = [IO.MemoryStream]::new($pngBytes, $false)
    $workerImage = [Drawing.Image]::FromStream($memory, $true, $true)
    if ($workerImage.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Png.Guid -or
        $workerImage.Width -ne $Bitmap.Width -or $workerImage.Height -ne $Bitmap.Height) {
      throw 'PrintWindow worker image is not a dimension-matched PNG.'
    }
    $Graphics.Clear([Drawing.Color]::Transparent)
    $Graphics.DrawImageUnscaled($workerImage, 0, 0)
  } finally {
    if ($null -ne $workerImage) { $workerImage.Dispose() }
    if ($null -ne $memory) { $memory.Dispose() }
  }
  return $flag
}

function Invoke-FullScreenCaptureStrict {
  param(
    [Parameter(Mandatory = $true)][int]$OriginX,
    [Parameter(Mandatory = $true)][int]$OriginY,
    [Parameter(Mandatory = $true)][System.Drawing.Bitmap]$Bitmap,
    [Parameter(Mandatory = $true)][System.Drawing.Graphics]$Graphics,
    [Parameter(Mandatory = $true)][ValidateRange(1, 60)][int]$TimeoutSeconds
  )

  $payload = [pscustomobject]@{
    OriginX = $OriginX
    OriginY = $OriginY
    Width = $Bitmap.Width
    Height = $Bitmap.Height
    MaxDimension = $script:MaxCaptureDimension
    MaxPixels = $script:MaxCapturePixels
    MaxRawBytes = $script:MaxCaptureRawBytes
    MaxPngBytes = $script:MaxCapturePngBytes
  } | ConvertTo-Json -Compress
  $payloadBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
  $workerTemplate = @'
$null = Microsoft.PowerShell.Core\Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$expectedCommands = @(
  @('Add-Type', 'Microsoft.PowerShell.Utility'),
  @('ConvertFrom-Json', 'Microsoft.PowerShell.Utility')
)
foreach ($entry in $expectedCommands) {
  $resolved = @(Microsoft.PowerShell.Core\Get-Command -Name $entry[0] -All -ErrorAction Stop)
  if ($resolved.Count -eq 0 -or
      $resolved[0].CommandType -ne [System.Management.Automation.CommandTypes]::Cmdlet -or
      [string]$resolved[0].ModuleName -cne [string]$entry[1]) {
    throw "Capture worker command provenance failed for '$($entry[0])'."
  }
}
Microsoft.PowerShell.Utility\Add-Type -AssemblyName System.Drawing -ErrorAction Stop
try {
  $payloadJson = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('__PAYLOAD_BASE64__'))
  $payload = Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $payloadJson
  $width = [int]$payload.Width
  $height = [int]$payload.Height
  if ($width -le 0 -or $height -le 0 -or
      $width -gt [int]$payload.MaxDimension -or $height -gt [int]$payload.MaxDimension) {
    throw "Worker capture dimensions are outside the bounded contract: ${width}x${height}."
  }
  $pixelCount = [int64]$width * [int64]$height
  $rawBytes = $pixelCount * 4L
  if ($pixelCount -gt [int64]$payload.MaxPixels -or $rawBytes -gt [int64]$payload.MaxRawBytes) {
    throw "Worker capture allocation exceeds bounded pixel/raw-byte contract: pixels=$pixelCount rawBytes=$rawBytes."
  }
  $bitmap = $null
  $graphics = $null
  $memory = $null
  try {
    $bitmap = [Drawing.Bitmap]::new($width, $height, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen(
      [int]$payload.OriginX, [int]$payload.OriginY, 0, 0, $bitmap.Size,
      [Drawing.CopyPixelOperation]::SourceCopy)
    $memory = [IO.MemoryStream]::new()
    $bitmap.Save($memory, [Drawing.Imaging.ImageFormat]::Png)
    $pngBytes = $memory.ToArray()
    if ($pngBytes.Length -le 0 -or $pngBytes.Length -gt [int]$payload.MaxPngBytes) {
      throw "Worker PNG length $($pngBytes.Length) violates bounded PNG contract."
    }
    [Console]::Out.Write(("OK:screen:{0}:{1}`n" -f $width, $height))
    [Console]::Out.Write([Convert]::ToBase64String($pngBytes))
  } finally {
    if ($null -ne $memory) { $memory.Dispose() }
    if ($null -ne $graphics) { $graphics.Dispose() }
    if ($null -ne $bitmap) { $bitmap.Dispose() }
  }
} catch {
  $errorBytes = [Text.Encoding]::UTF8.GetBytes($_.Exception.Message)
  [Console]::Out.Write("ERROR`n")
  [Console]::Out.Write([Convert]::ToBase64String($errorBytes))
}
'@
  $workerScript = $workerTemplate.Replace('__PAYLOAD_BASE64__', $payloadBase64)
  $protectedPid = [System.Diagnostics.Process]::GetCurrentProcess().Id
  $workerResult = Invoke-HiddenPowerShellWorker -ScriptText $workerScript `
    -TimeoutSeconds $TimeoutSeconds -ForbiddenProcessId $protectedPid

  $maxProtocolChars = [int64]$script:MaxWorkerProtocolHeaderChars + 1L + [int64]$script:MaxCaptureBase64Chars
  if ([int64]$workerResult.StandardOutput.Length -gt $maxProtocolChars) {
    throw "Full-screen worker protocol exceeds the bounded character limit $maxProtocolChars."
  }
  $separator = $workerResult.StandardOutput.IndexOf("`n", [StringComparison]::Ordinal)
  if ($separator -lt 0 -or $separator -gt $script:MaxWorkerProtocolHeaderChars) {
    $stderr = if ($workerResult.StandardError.Length -gt 2000) { $workerResult.StandardError.Substring(0, 2000) } else { $workerResult.StandardError }
    throw "Full-screen worker returned no bounded protocol header (exit=$($workerResult.ExitCode), stderr=$stderr)."
  }
  $header = $workerResult.StandardOutput.Substring(0, $separator).TrimEnd("`r")
  $body = $workerResult.StandardOutput.Substring($separator + 1).Trim()
  if ($header -eq 'ERROR') {
    try { $workerMessage = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($body)) }
    catch { $workerMessage = 'Worker returned an invalid error payload.' }
    throw "Full-screen worker failed: $workerMessage"
  }
  $headerMatch = [regex]::Match($header, '^OK:screen:([1-9][0-9]*):([1-9][0-9]*)$', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
  if (-not $headerMatch.Success) {
    throw "Full-screen worker returned an invalid protocol header: '$header'."
  }
  $reportedWidth = [int]$headerMatch.Groups[1].Value
  $reportedHeight = [int]$headerMatch.Groups[2].Value
  if ($reportedWidth -ne $Bitmap.Width -or $reportedHeight -ne $Bitmap.Height) {
    throw "Full-screen worker dimensions changed: expected $($Bitmap.Width)x$($Bitmap.Height), got ${reportedWidth}x${reportedHeight}."
  }
  if ($body.Length -le 0 -or $body.Length -gt $script:MaxCaptureBase64Chars -or ($body.Length % 4) -ne 0) {
    throw "Full-screen worker base64 length $($body.Length) violates the bounded protocol contract."
  }
  $padding = if ($body.EndsWith('==', [StringComparison]::Ordinal)) { 2 } elseif ($body.EndsWith('=', [StringComparison]::Ordinal)) { 1 } else { 0 }
  $estimatedDecodedBytes = ([int64]($body.Length / 4) * 3L) - $padding
  if ($estimatedDecodedBytes -le 0 -or $estimatedDecodedBytes -gt $script:MaxCapturePngBytes) {
    throw "Full-screen worker decoded-length estimate $estimatedDecodedBytes exceeds the bounded PNG contract."
  }
  try { $pngBytes = [Convert]::FromBase64String($body) }
  catch { throw "Full-screen worker returned invalid PNG base64: $($_.Exception.Message)" }
  if ($pngBytes.Length -le 0 -or $pngBytes.Length -gt $script:MaxCapturePngBytes) {
    throw "Full-screen worker decoded PNG length $($pngBytes.Length) violates the bounded PNG contract."
  }
  $memory = $null
  $workerImage = $null
  try {
    $memory = [IO.MemoryStream]::new($pngBytes, $false)
    $workerImage = [Drawing.Image]::FromStream($memory, $true, $true)
    if ($workerImage.RawFormat.Guid -ne [Drawing.Imaging.ImageFormat]::Png.Guid -or
        $workerImage.Width -ne $Bitmap.Width -or $workerImage.Height -ne $Bitmap.Height) {
      throw 'Full-screen worker image is not a dimension-matched PNG.'
    }
    $Graphics.Clear([Drawing.Color]::Transparent)
    $Graphics.DrawImageUnscaled($workerImage, 0, 0)
  } finally {
    if ($null -ne $workerImage) { $workerImage.Dispose() }
    if ($null -ne $memory) { $memory.Dispose() }
  }
  return [pscustomobject]@{
    WorkerPid = $workerResult.WorkerPid
    ElapsedMilliseconds = $workerResult.ElapsedMilliseconds
  }
}

$script:RepositoryBoundary = Get-CaptureValidatedGitBoundary -Path $RepositoryRoot
$script:RepositoryRootPath = [string]$script:RepositoryBoundary.WorktreeRoot
$script:RepositoryAdministrationRoots = @($script:RepositoryBoundary.AdministrationRoots)
$script:TrustedEvidenceRootPath = Resolve-CanonicalCaptureExistingPath `
  -Path $TrustedEvidenceRoot -Label 'TrustedEvidenceRoot'
if (-not (Test-Path -LiteralPath $script:TrustedEvidenceRootPath -PathType Container)) {
  throw 'TrustedEvidenceRoot must be an existing directory.'
}
if (Test-CapturePathsOverlap -First $script:TrustedEvidenceRootPath -Second $script:RepositoryRootPath) {
  throw 'TrustedEvidenceRoot and RepositoryRoot must be physically disjoint.'
}
foreach ($gitAdministrationRoot in $script:RepositoryAdministrationRoots) {
  if (Test-CapturePathsOverlap -First $script:TrustedEvidenceRootPath -Second $gitAdministrationRoot) {
    throw "TrustedEvidenceRoot must be physically disjoint from Git administration root: $gitAdministrationRoot"
  }
}
$script:KnownTempRoots = @(Get-CaptureKnownTempRoots)
foreach ($tempRoot in $script:KnownTempRoots) {
  if (Test-CapturePathsOverlap -First $script:TrustedEvidenceRootPath -Second $tempRoot) {
    throw "TrustedEvidenceRoot must be physically disjoint from every known TEMP root: $tempRoot"
  }
}

$expectedCaptureScriptPath = Resolve-CanonicalCaptureExistingPath -Path $ExpectedScriptPath `
  -Label 'ExpectedScriptPath' -Leaf
$script:ScriptsRootPath = Resolve-CanonicalCaptureExistingPath `
  -Path (Split-Path -Parent $expectedCaptureScriptPath) -Label 'Capture scripts root'
$script:CaptureScriptAttestation = Get-CaptureScriptSnapshot -Path $expectedCaptureScriptPath `
  -Label 'studio_capture.ps1 immediately after memory dispatch'
if ([System.IO.Path]::GetFileName($expectedCaptureScriptPath) -cne 'studio_capture.ps1' -or
    -not [string]::Equals(
      [string]$script:CaptureScriptAttestation.Path, $expectedCaptureScriptPath,
      [StringComparison]::OrdinalIgnoreCase) -or
    [string]$script:CaptureScriptAttestation.Sha256 -cne $ExpectedScriptSha256 -or
    [string]$script:CaptureScriptAttestation.FileIdentity -cne $ExpectedScriptFileIdentity) {
  throw 'studio_capture.ps1 path/hash/file identity does not match the caller-approved Preflight attestation.'
}
$captureWriteBoundaries = @(
  $script:RepositoryRootPath
  @($script:RepositoryAdministrationRoots)
  $script:TrustedEvidenceRootPath
  @($script:KnownTempRoots)
)
foreach ($boundary in $captureWriteBoundaries) {
  if (Test-CapturePathsOverlap -First $script:ScriptsRootPath -Second $boundary) {
    throw "Capture scripts root must be physically disjoint from repository, Git, evidence, and TEMP boundaries: $boundary"
  }
}
$output = Resolve-OutputPath -Path $OutFile -AllowReplace $Force.IsPresent
$virtualBounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
if ($virtualBounds.Width -le 0 -or $virtualBounds.Height -le 0) {
  throw "Windows reported invalid virtual-screen bounds: $virtualBounds"
}

if ($PSCmdlet.ParameterSetName -eq 'FullScreen') {
  if (-not $FullScreen.IsPresent -or -not $AllowFullScreenCapture.IsPresent) {
    throw '-FullScreen requires -AllowFullScreenCapture after explicit user consent.'
  }

  if (-not $DryRun.IsPresent) {
    Write-Warning 'FULL-SCREEN PRIVACY: -AllowFullScreenCapture asserts explicit user consent for this run and that sensitive windows on every monitor were hidden.'
  }

  $captureDimensions = Assert-CaptureDimensions -Width $virtualBounds.Width `
    -Height $virtualBounds.Height -Label 'Virtual-screen capture'

  $fullScreenWorkerPid = $null
  $fullScreenWorkerElapsedMilliseconds = $null
  $fullScreenCommit = $null
  $fullScreenCapturedAtUtc = $null
  if (-not $DryRun.IsPresent) {
    $bitmap = $null
    $graphics = $null
    try {
      $bitmap = [System.Drawing.Bitmap]::new(
        $virtualBounds.Width,
        $virtualBounds.Height,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
      )
      $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
      if ($null -eq $graphics) {
        throw 'Graphics.FromImage returned null.'
      }
      $fullScreenWorker = Invoke-FullScreenCaptureStrict `
        -OriginX ([int]$virtualBounds.Left) -OriginY ([int]$virtualBounds.Top) `
        -Bitmap $bitmap -Graphics $graphics -TimeoutSeconds $FullScreenTimeoutSeconds
      $fullScreenWorkerPid = [int]$fullScreenWorker.WorkerPid
      $fullScreenWorkerElapsedMilliseconds = [int]$fullScreenWorker.ElapsedMilliseconds
      $fullScreenCommit = Save-VerifiedPngAtomically -Bitmap $bitmap -DestinationPath $output.FullPath `
        -ReplaceExisting $output.Existed
      $fullScreenCapturedAtUtc = [datetime]::UtcNow.ToString('o')
    } finally {
      if ($null -ne $graphics) { $graphics.Dispose() }
      if ($null -ne $bitmap) { $bitmap.Dispose() }
    }
  }

  $result = [pscustomobject][ordered]@{
    Ok = $true
    Status = $(if ($DryRun.IsPresent) { 'Validated' } else { 'Captured' })
    Mode = 'FullScreen'
    DryRun = $DryRun.IsPresent
    OutputWritten = (-not $DryRun.IsPresent)
    ReplacedExisting = ($output.Existed -and -not $DryRun.IsPresent)
    WouldReplaceExisting = $output.Existed
    OutFile = $output.FullPath
    OutputSha256 = $(if ($null -eq $fullScreenCommit) { $null } else { [string]$fullScreenCommit.Sha256 })
    OutputBytes = $(if ($null -eq $fullScreenCommit) { $null } else { [int64]$fullScreenCommit.Length })
    CapturedAtUtc = $fullScreenCapturedAtUtc
    GeneratedAtUtc = [datetime]::UtcNow.ToString('o')
    RepositoryRoot = $script:RepositoryRootPath
    RepositoryAdministrationRoots = @($script:RepositoryAdministrationRoots)
    TrustedEvidenceRoot = $script:TrustedEvidenceRootPath
    ScriptsRoot = $script:ScriptsRootPath
    CaptureScriptPath = [string]$script:CaptureScriptAttestation.Path
    CaptureScriptSha256 = [string]$script:CaptureScriptAttestation.Sha256
    CaptureScriptFileIdentity = [string]$script:CaptureScriptAttestation.FileIdentity
    VerifiedInMemoryDispatch = $true
    PrivacyConsentAsserted = $AllowFullScreenCapture.IsPresent
    CaptureScope = 'All monitors and all visible content in the Windows virtual screen'
    SessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    OriginX = [int]$virtualBounds.Left
    OriginY = [int]$virtualBounds.Top
    Width = [int]$virtualBounds.Width
    Height = [int]$virtualBounds.Height
    VirtualScreenOriginX = [int]$virtualBounds.Left
    VirtualScreenOriginY = [int]$virtualBounds.Top
    VirtualScreenWidth = [int]$virtualBounds.Width
    VirtualScreenHeight = [int]$virtualBounds.Height
    CoordinateContract = 'AbsoluteX=BitmapX+OriginX; AbsoluteY=BitmapY+OriginY'
    CapturePixelCount = $captureDimensions.PixelCount
    CaptureRawBytes = $captureDimensions.RawBytes
    CaptureTimeoutSeconds = $FullScreenTimeoutSeconds
    CaptureWorkerPid = $fullScreenWorkerPid
    CaptureWorkerElapsedMilliseconds = $fullScreenWorkerElapsedMilliseconds
    MaxCaptureDimension = $script:MaxCaptureDimension
    MaxCapturePixels = $script:MaxCapturePixels
    MaxCaptureRawBytes = $script:MaxCaptureRawBytes
    MaxCapturePngBytes = $script:MaxCapturePngBytes
    MaxCaptureBase64Chars = $script:MaxCaptureBase64Chars
  }
  $result | ConvertTo-Json -Compress -Depth 3
  return
}

$expectedBaseName = Resolve-ExpectedProcessBaseName -Name $ExpectedProcessName
$expectedExePath = Resolve-ExpectedExecutablePath -Path $ExpectedExecutablePath
$expectedStudioVersionDirectory = Resolve-CanonicalCaptureExistingPath `
  -Path (Split-Path -Parent $expectedExePath) -Label 'Expected Studio version directory'
foreach ($boundary in @($captureWriteBoundaries) + @($script:ScriptsRootPath)) {
  if (Test-CapturePathsOverlap -First $expectedStudioVersionDirectory -Second $boundary) {
    throw "Expected Studio version directory must be physically disjoint from scripts/repository/Git/evidence/TEMP boundaries: $boundary"
  }
}
if (-not [string]::Equals($expectedBaseName, 'RobloxStudioBeta', [StringComparison]::OrdinalIgnoreCase)) {
  throw "ExpectedProcessName must identify Roblox Studio exactly: 'RobloxStudioBeta' or 'RobloxStudioBeta.exe'."
}
if (-not [string]::Equals([System.IO.Path]::GetFileName($expectedExePath), 'RobloxStudioBeta.exe', [StringComparison]::OrdinalIgnoreCase)) {
  throw "ExpectedExecutablePath must end in RobloxStudioBeta.exe: $expectedExePath"
}
$captureSessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
if ($ExpectedSessionId -ne $captureSessionId) {
  throw "ExpectedSessionId $ExpectedSessionId is not the capture process session $captureSessionId. Cross-session capture is forbidden."
}
$initialTarget = Assert-WindowTarget -TargetPid $ProcId -SessionId $ExpectedSessionId `
  -ProcessBaseName $expectedBaseName -ExecutablePath $expectedExePath `
  -MinimizedAllowed $AllowMinimized.IsPresent -ForegroundRequired $RequireForeground.IsPresent `
  -RequiredStartTimeUtcTicks $ExpectedStartTimeUtc.UtcDateTime.Ticks
$captureDimensions = Assert-CaptureDimensions -Width $initialTarget.WindowRect.Width `
  -Height $initialTarget.WindowRect.Height -Label 'Studio-window capture'

$printWindowFlag = $null
$windowCommit = $null
$windowCapturedAtUtc = $null
if (-not $DryRun.IsPresent) {
  $bitmap = $null
  $graphics = $null
  try {
    $bitmap = [System.Drawing.Bitmap]::new(
      $initialTarget.WindowRect.Width,
      $initialTarget.WindowRect.Height,
      [System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    )
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    if ($null -eq $graphics) {
      throw 'Graphics.FromImage returned null.'
    }
    $printWindowFlag = Invoke-PrintWindowStrict -WindowHandle $initialTarget.WindowHandle `
      -Bitmap $bitmap -Graphics $graphics -TimeoutSeconds $PrintWindowTimeoutSeconds `
      -TargetProcessId $ProcId

    $stabilityCheck = {
      Assert-WindowSnapshotStable -InitialTarget $initialTarget -TargetPid $ProcId `
        -SessionId $ExpectedSessionId -ProcessBaseName $expectedBaseName `
        -ExecutablePath $expectedExePath -MinimizedAllowed $AllowMinimized.IsPresent `
        -ForegroundRequired $RequireForeground.IsPresent
    }
    $windowCommit = Save-VerifiedPngAtomically -Bitmap $bitmap -DestinationPath $output.FullPath `
      -ReplaceExisting $output.Existed -BeforeCommit $stabilityCheck
    $windowCapturedAtUtc = [datetime]::UtcNow.ToString('o')
  } finally {
    if ($null -ne $graphics) { $graphics.Dispose() }
    if ($null -ne $bitmap) { $bitmap.Dispose() }
  }
}

$result = [pscustomobject][ordered]@{
  Ok = $true
  Status = $(if ($DryRun.IsPresent) { 'Validated' } else { 'Captured' })
  Mode = 'Window'
  DryRun = $DryRun.IsPresent
  OutputWritten = (-not $DryRun.IsPresent)
  ReplacedExisting = ($output.Existed -and -not $DryRun.IsPresent)
  WouldReplaceExisting = $output.Existed
  OutFile = $output.FullPath
  OutputSha256 = $(if ($null -eq $windowCommit) { $null } else { [string]$windowCommit.Sha256 })
  OutputBytes = $(if ($null -eq $windowCommit) { $null } else { [int64]$windowCommit.Length })
  CapturedAtUtc = $windowCapturedAtUtc
  GeneratedAtUtc = [datetime]::UtcNow.ToString('o')
  RepositoryRoot = $script:RepositoryRootPath
  RepositoryAdministrationRoots = @($script:RepositoryAdministrationRoots)
  TrustedEvidenceRoot = $script:TrustedEvidenceRootPath
  ScriptsRoot = $script:ScriptsRootPath
  CaptureScriptPath = [string]$script:CaptureScriptAttestation.Path
  CaptureScriptSha256 = [string]$script:CaptureScriptAttestation.Sha256
  CaptureScriptFileIdentity = [string]$script:CaptureScriptAttestation.FileIdentity
  VerifiedInMemoryDispatch = $true
  Pid = $ProcId
  SessionId = $initialTarget.Process.SessionId
  ProcessName = $initialTarget.Process.ProcessName
  ExecutablePath = $initialTarget.ExecutablePath
  ProcessStartTimeUtc = $initialTarget.StartTimeUtc.ToString('o')
  WindowHandle = $initialTarget.WindowHandle.ToInt64()
  IsVisible = $initialTarget.IsVisible
  IsMinimized = $initialTarget.IsMinimized
  ForegroundRequired = $RequireForeground.IsPresent
  IsForegroundProcess = $initialTarget.Foreground.IsTargetProcess
  IsMainWindowForeground = $initialTarget.Foreground.IsMainWindow
  ForegroundPid = $initialTarget.Foreground.Pid
  PrintWindowFlag = $printWindowFlag
  PrintWindowTimeoutSeconds = $PrintWindowTimeoutSeconds
  OriginX = $initialTarget.WindowRect.Left
  OriginY = $initialTarget.WindowRect.Top
  Width = $initialTarget.WindowRect.Width
  Height = $initialTarget.WindowRect.Height
  VirtualScreenOriginX = [int]$virtualBounds.Left
  VirtualScreenOriginY = [int]$virtualBounds.Top
  VirtualScreenWidth = [int]$virtualBounds.Width
  VirtualScreenHeight = [int]$virtualBounds.Height
  CoordinateContract = 'AbsoluteX=BitmapX+OriginX; AbsoluteY=BitmapY+OriginY'
  CapturePixelCount = $captureDimensions.PixelCount
  CaptureRawBytes = $captureDimensions.RawBytes
  MaxCaptureDimension = $script:MaxCaptureDimension
  MaxCapturePixels = $script:MaxCapturePixels
  MaxCaptureRawBytes = $script:MaxCaptureRawBytes
  MaxCapturePngBytes = $script:MaxCapturePngBytes
  MaxCaptureBase64Chars = $script:MaxCaptureBase64Chars
}
$result | ConvertTo-Json -Compress -Depth 3
