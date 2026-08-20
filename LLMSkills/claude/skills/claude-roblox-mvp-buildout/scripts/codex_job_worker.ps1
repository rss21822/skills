[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$MetadataPath
)

$ErrorActionPreference = 'Stop'
Microsoft.PowerShell.Core\Set-StrictMode -Version 2.0

$script:CodexJobOriginalPSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Process')
$entryExpectedHost = [IO.Path]::Combine(
    [Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
$entryCurrentHost = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if ([IO.Path]::GetFullPath($entryCurrentHost) -ine [IO.Path]::GetFullPath($entryExpectedHost)) {
    throw "Worker must run in the OS system Windows PowerShell host. expected=$entryExpectedHost actual=$entryCurrentHost"
}
$entryTrustedModuleRoot = [IO.Path]::Combine([IO.Path]::GetDirectoryName($entryExpectedHost), 'Modules')
$entryTrustedModuleItem = [IO.DirectoryInfo]::new($entryTrustedModuleRoot)
if (-not $entryTrustedModuleItem.Exists -or
    ($entryTrustedModuleItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'The OS system Windows PowerShell module directory is missing or a reparse point.'
}
[Environment]::SetEnvironmentVariable('PSModulePath', $entryTrustedModuleRoot, 'Process')
try {

function Assert-TrustedEntryPowerShell {
    $expectedHost = [IO.Path]::Combine(
        [Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
    $currentHost = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ([IO.Path]::GetFullPath($currentHost) -ine [IO.Path]::GetFullPath($expectedHost)) {
        throw "Worker must run in the OS system Windows PowerShell host. expected=$expectedHost actual=$currentHost"
    }
    $windowsDirectory = [IO.Directory]::GetParent([Environment]::SystemDirectory).FullName
    $gacRoot = [IO.Path]::GetFullPath([IO.Path]::Combine($windowsDirectory, 'Microsoft.Net', 'assembly', 'GAC_MSIL')).TrimEnd('\') + '\'
    $moduleRoot = [IO.Path]::GetFullPath([IO.Path]::Combine([IO.Path]::GetDirectoryName($expectedHost), 'Modules')).TrimEnd('\') + '\'

    $expectedModules = @{
        'Set-StrictMode' = 'Microsoft.PowerShell.Core'; 'Get-Command' = 'Microsoft.PowerShell.Core'
        'ForEach-Object' = 'Microsoft.PowerShell.Core'; 'Where-Object' = 'Microsoft.PowerShell.Core'
        'Get-ChildItem' = 'Microsoft.PowerShell.Management'; 'Get-Content' = 'Microsoft.PowerShell.Management'
        'Get-Item' = 'Microsoft.PowerShell.Management'; 'Join-Path' = 'Microsoft.PowerShell.Management'
        'Remove-Item' = 'Microsoft.PowerShell.Management'; 'Resolve-Path' = 'Microsoft.PowerShell.Management'
        'Test-Path' = 'Microsoft.PowerShell.Management'; 'Add-Member' = 'Microsoft.PowerShell.Utility'
        'Add-Type' = 'Microsoft.PowerShell.Utility'; 'ConvertFrom-Json' = 'Microsoft.PowerShell.Utility'
        'ConvertTo-Json' = 'Microsoft.PowerShell.Utility'; 'Get-Date' = 'Microsoft.PowerShell.Utility'
        'New-Object' = 'Microsoft.PowerShell.Utility'
    }
    foreach ($name in $expectedModules.Keys) {
        $resolved = @(Microsoft.PowerShell.Core\Get-Command -Name $name -ErrorAction Stop)
        $resolvedDll = if ($resolved.Count -eq 1) { [string]$resolved[0].DLL } else { '' }
        $resolvedModulePath = if ($resolved.Count -eq 1 -and $null -ne $resolved[0].Module) { [string]$resolved[0].Module.Path } else { '' }
        if ($resolved.Count -ne 1 -or $resolved[0].CommandType -ne [Management.Automation.CommandTypes]::Cmdlet -or
            [string]$resolved[0].ModuleName -cne [string]$expectedModules[$name] -or
            -not ([IO.Path]::GetFullPath($resolvedDll).StartsWith($gacRoot, [StringComparison]::OrdinalIgnoreCase)) -or
            ([string]$expectedModules[$name] -cne 'Microsoft.PowerShell.Core' -and
                -not ([IO.Path]::GetFullPath($resolvedModulePath).StartsWith($moduleRoot, [StringComparison]::OrdinalIgnoreCase)))) {
            throw "Critical PowerShell command provenance is untrusted: $name"
        }
    }
    $internalNames = @(
        'Assert-GitBindingUnchanged', 'Assert-JobContract', 'Assert-LocalFixedDrivePath',
        'Assert-NoAmbientEgressOverrides', 'Assert-NoCodexHomeDelegationLayer',
        'Assert-NoReparseDirectoryAncestors', 'Assert-NoReparsePathComponents',
        'Assert-NoUnexpectedAmbientSecretVariables', 'Assert-NoUntrustedProjectCodexLayer',
        'Assert-RecordedCodexHomeContract', 'Assert-RecordedLauncherTrust', 'Assert-RecordedScriptTrust',
        'Assert-SafeGitConfigContractCurrent',
        'Assert-SafeEvidenceDirectory', 'Get-EgressOverrideEnvironmentNames', 'Get-FinalDirectoryPath',
        'Get-FinalExistingPath', 'Get-FinalFilePath', 'Get-GitBindingContract', 'Get-LocalFixedTempRoots',
        'Get-NormalizedPath', 'Get-OpenWorkerFileHandleContract', 'Get-SafeGitConfigContract',
        'Get-SafeGitConfigHandleContract', 'Get-ScriptFileContract', 'Get-Sha256Hex',
        'Get-TrustedChildTempDirectory', 'Get-TrustedCoreChildPath', 'Get-TrustedSystemPowerShellContract',
        'Get-TrustedWindowsDirectory', 'Get-WorkerCodexSignatureContract', 'Initialize-TrustedWindowsEnvironment',
        'Invoke-WorkerAuthenticodeCapture', 'New-CodexStartInfo', 'Open-ValidatedGitConfigStream', 'Open-ValidatedPromptStream',
        'Quote-NativeArgument', 'Read-JobMetadata', 'Remove-BlockedChildEnvironmentVariables',
        'Set-ObjectProperty', 'Set-TrustedGitEnvironmentVariables', 'Test-CoreChildEnvironmentName',
        'Test-PathsOverlap', 'Test-PathWithin', 'Write-JobMetadata'
    )
    foreach ($name in $internalNames) {
        $ambient = @(Microsoft.PowerShell.Core\Get-Command -Name $name -ErrorAction SilentlyContinue)
        if ($ambient.Count -ne 0) { throw "Ambient command shadows an internal security helper: $name" }
    }
}

& ${function:Assert-TrustedEntryPowerShell}
$script:CodexJobWorkerSelfPath = [string]$PSCommandPath
$script:CodexJobOriginalProcessTempCandidates = @($env:TEMP, $env:TMP)
$script:CodexJobPromptMaxBytes = 8MB
$script:CodexJobEvidenceStreamMaxBytes = 64MB
$script:CodexJobScriptMaxBytes = 4MB
$script:CodexJobGitConfigMaxBytes = 1MB
$script:CodexJobWebSearchOverride = 'web_search="disabled"'
$script:CodexJobModelProviderOverride = 'model_provider="openai"'
$script:CodexJobSupportedVersion = 'codex-cli 0.147.0'
$script:CodexJobDisabledFeatures = @(
    'apps', 'plugins', 'tool_suggest', 'memories', 'codex_hooks', 'unified_exec', 'shell_snapshot',
    'remote_plugin', 'plugin_sharing', 'recommended_plugins',
    'skill_mcp_dependency_install', 'tool_call_mcp_elicitation', 'enable_mcp_apps',
    'external_agent_memory_import', 'auth_elicitation', 'skill_search',
    'browser_use', 'browser_use_external', 'browser_use_full_cdp_access',
    'in_app_browser', 'computer_use', 'image_generation', 'standalone_web_search',
    'multi_agent', 'multi_agent_v2', 'in_app_updates', 'workspace_dependencies'
)

function Set-ObjectProperty {
    param(
        [Parameter(Mandatory = $true)][psobject]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        $Value
    )

    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Get-EgressOverrideEnvironmentNames {
    return @(
        'OPENAI_BASE_URL', 'OPENAI_API_BASE', 'AZURE_OPENAI_ENDPOINT', 'AZURE_OPENAI_BASE_URL',
        'HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY',
        'SSL_CERT_FILE', 'SSL_CERT_DIR', 'NODE_EXTRA_CA_CERTS', 'REQUESTS_CA_BUNDLE', 'CURL_CA_BUNDLE',
        'CODEX_REFRESH_TOKEN_URL_OVERRIDE', 'CODEX_REVOKE_TOKEN_URL_OVERRIDE',
        'CODEX_APP_SERVER_LOGIN_CLIENT_ID', 'CODEX_ACCESS_TOKEN', 'OPENAI_API_KEY'
    )
}

function Assert-NoAmbientEgressOverrides {
    foreach ($name in @(Get-EgressOverrideEnvironmentNames)) {
        if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process'))) {
            throw "Ambient endpoint, proxy, custom-CA, or unapproved auth override is forbidden for Codex delegation: $name (value not logged)."
        }
    }
    foreach ($entry in @(Get-ChildItem Env:)) {
        if ($entry.Name -like 'OPENAI_*' -and -not [string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            throw "Ambient OPENAI_* authority/egress override is forbidden for Codex delegation: $($entry.Name) (value not logged)."
        }
    }
}

function Assert-NoUnexpectedAmbientSecretVariables {
    foreach ($entry in @(Get-ChildItem Env:)) {
        if ($entry.Name -ieq 'CODEX_API_KEY') { continue }
        if ($entry.Name -match '(?i)(KEY|SECRET|TOKEN|PASSWORD|PASSWD|CREDENTIAL|PRIVATE)' -and
            -not [string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            throw "Unexpected secret-shaped worker environment variable is forbidden: $($entry.Name) (value not logged)."
        }
    }
}

function Test-CoreChildEnvironmentName {
    param([Parameter(Mandatory = $true)][string]$Name)

    return $Name -in @(
        'SystemRoot', 'WINDIR', 'ComSpec', 'SystemDrive', 'TEMP', 'TMP',
        'OS', 'USERPROFILE', 'HOMEDRIVE', 'HOMEPATH',
        'USERNAME', 'USERDOMAIN', 'USERDOMAIN_ROAMINGPROFILE', 'LOGONSERVER',
        'APPDATA', 'LOCALAPPDATA', 'PROGRAMDATA', 'ProgramFiles', 'ProgramFiles(x86)',
        'ProgramW6432', 'CommonProgramFiles', 'CommonProgramFiles(x86)', 'CommonProgramW6432',
        'PROCESSOR_ARCHITECTURE', 'PROCESSOR_IDENTIFIER', 'PROCESSOR_LEVEL',
        'PROCESSOR_REVISION', 'NUMBER_OF_PROCESSORS'
    )
}

function Remove-BlockedChildEnvironmentVariables {
    param([Parameter(Mandatory = $true)]$EnvironmentVariables)

    foreach ($keyObject in @($EnvironmentVariables.Keys)) {
        $key = [string]$keyObject
        if (-not (Test-CoreChildEnvironmentName -Name $key)) {
            $null = $EnvironmentVariables.Remove($key)
        }
    }
}

function Set-TrustedGitEnvironmentVariables {
    param([Parameter(Mandatory = $true)]$EnvironmentVariables)

    $EnvironmentVariables['GIT_CONFIG_NOSYSTEM'] = '1'
    $EnvironmentVariables['GIT_CONFIG_GLOBAL'] = 'NUL'
    $EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $EnvironmentVariables['GCM_INTERACTIVE'] = 'Never'
}

function Assert-NoUntrustedProjectCodexLayer {
    param([Parameter(Mandatory = $true)][string]$RepositoryPath)

    foreach ($leaf in @('config.toml', 'hooks.json')) {
        $path = [IO.Path]::Combine($RepositoryPath, '.codex', $leaf)
        $null = Assert-NoReparsePathComponents -Path $path -Label "Project .codex/$leaf" -AllowMissingTail
        if (Test-Path -LiteralPath $path) {
            throw "Project-local .codex/$leaf is forbidden for delegated jobs."
        }
    }
}

function Assert-NoCodexHomeDelegationLayer {
    param([Parameter(Mandatory = $true)][string]$CodexHomePath)

    foreach ($leaf in @('config.toml', 'AGENTS.override.md', 'AGENTS.md')) {
        $path = [IO.Path]::Combine($CodexHomePath, $leaf)
        $null = Assert-NoReparsePathComponents -Path $path -Label "Pinned CODEX_HOME/$leaf" -AllowMissingTail
        if (Test-Path -LiteralPath $path) {
            throw "Pinned CODEX_HOME/$leaf is forbidden for delegated jobs."
        }
    }
}

function Assert-LocalFixedDrivePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "$Label must not be empty."
    }
    if ($Path -notmatch '^[A-Za-z]:[\\/]') {
        throw "$Label must use drive-letter local path syntax; UNC, device, and provider paths are forbidden: $Path"
    }
    if ($Path.Substring(2).IndexOf(':') -ge 0) {
        throw "$Label must not contain an alternate data stream or extra colon: $Path"
    }

    $driveName = $Path.Substring(0, 1)
    try {
        $drive = New-Object IO.DriveInfo -ArgumentList @($driveName)
        $driveType = $drive.DriveType
    } catch {
        throw "$Label drive could not be inspected without probing the path: $driveName`: $($_.Exception.Message)"
    }
    if ($driveType -ne [IO.DriveType]::Fixed) {
        throw "$Label must be on a local fixed drive; drive $driveName is $driveType."
    }
    try {
        if (-not $drive.IsReady) {
            throw "$Label drive is not ready: $driveName"
        }
    } catch {
        throw "$Label fixed drive readiness check failed: $driveName`: $($_.Exception.Message)"
    }
}

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    Assert-LocalFixedDrivePath -Path $Path -Label 'Path'
    $full = [IO.Path]::GetFullPath($Path)
    $root = [IO.Path]::GetPathRoot($full)
    if ($full -ieq $root) {
        return $root
    }
    return $full.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Test-PathsOverlap {
    param(
        [Parameter(Mandatory = $true)][string]$First,
        [Parameter(Mandatory = $true)][string]$Second
    )

    return ((Test-PathWithin -Candidate $First -Parent $Second) -or (Test-PathWithin -Candidate $Second -Parent $First))
}

function Get-LocalFixedTempRoots {
    $candidates = New-Object 'System.Collections.Generic.List[string]'
    foreach ($candidate in @($script:CodexJobOriginalProcessTempCandidates) + @($env:TEMP, $env:TMP)) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) { $candidates.Add($candidate) }
    }
    foreach ($target in @([EnvironmentVariableTarget]::User, [EnvironmentVariableTarget]::Machine)) {
        foreach ($name in @('TEMP', 'TMP')) {
            try {
                $candidate = [Environment]::GetEnvironmentVariable($name, $target)
                if (-not [string]::IsNullOrWhiteSpace($candidate)) {
                    $candidates.Add([Environment]::ExpandEnvironmentVariables($candidate))
                }
            } catch { }
        }
    }
    try { $candidates.Add([IO.Path]::Combine((Get-TrustedWindowsDirectory), 'Temp')) } catch { }
    try {
        $runtimeTemp = [IO.Path]::GetTempPath()
        if (-not [string]::IsNullOrWhiteSpace($runtimeTemp)) { $candidates.Add($runtimeTemp) }
    } catch {
        # An unsafe or malformed ambient temp is ignored; it is never probed.
    }

    $roots = New-Object 'System.Collections.Generic.List[string]'
    foreach ($candidate in $candidates) {
        try {
            Assert-LocalFixedDrivePath -Path $candidate -Label 'Ambient temporary root'
            $normalized = Get-NormalizedPath -Path $candidate
            $null = Assert-NoReparsePathComponents -Path $normalized -Label 'Ambient temporary root' -AllowMissingTail
            if ($normalized -notin @($roots)) { $roots.Add($normalized) }
        } catch {
            # UNC, mapped-network, device, unready, and malformed temp paths are skipped before Test-Path.
        }
    }
    return @($roots.ToArray())
}

function Get-TrustedChildTempDirectory {
    foreach ($candidate in @(Get-LocalFixedTempRoots)) {
        try {
            Assert-NoReparseDirectoryAncestors -Path $candidate -Label 'Child temporary directory'
            if (Test-Path -LiteralPath $candidate -PathType Container) {
                return (Get-FinalDirectoryPath -Path $candidate)
            }
        } catch { }
    }
    throw 'No trusted local fixed temporary directory is available for child processes.'
}

function Test-PathWithin {
    param(
        [Parameter(Mandatory = $true)][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Parent
    )

    $candidateFull = Get-NormalizedPath -Path $Candidate
    $parentFull = Get-NormalizedPath -Path $Parent
    if ($candidateFull.Equals($parentFull, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $prefix = $parentFull
    if (-not $prefix.EndsWith([IO.Path]::DirectorySeparatorChar.ToString())) {
        $prefix += [IO.Path]::DirectorySeparatorChar
    }
    return $candidateFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-NoReparsePathComponents {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label,
        [switch]$AllowMissingTail
    )

    Assert-LocalFixedDrivePath -Path $Path -Label $Label
    $full = Get-NormalizedPath -Path $Path
    $root = [IO.Path]::GetPathRoot($full)
    $cursor = $root
    $relative = $full.Substring($root.Length)
    foreach ($component in @($relative -split '[\\/]' | Where-Object { $_.Length -gt 0 })) {
        $cursor = [IO.Path]::Combine($cursor, $component)
        try {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        } catch {
            if ($AllowMissingTail) { return $full }
            throw "$Label path component cannot be inspected without traversal: $cursor"
        }
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Label must not be or traverse a reparse-point path component: $cursor"
        }
    }
    return $full
}

function Assert-NoReparseDirectoryAncestors {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $full = Assert-NoReparsePathComponents -Path $Path -Label $Label
    $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
    if (-not $item.PSIsContainer) { throw "$Label is not an existing directory: $full" }
}

function Initialize-TrustedWindowsEnvironment {
    # Bootstrap Add-Type without trusting ambient SystemRoot/WINDIR. The CLR obtains
    # SystemDirectory from the OS; GetSystemWindowsDirectoryW is authoritative once loaded.
    $systemDirectory = [Environment]::SystemDirectory
    Assert-LocalFixedDrivePath -Path $systemDirectory -Label 'OS system directory bootstrap'
    Assert-NoReparseDirectoryAncestors -Path $systemDirectory -Label 'OS system directory bootstrap'
    if (-not (Test-Path -LiteralPath $systemDirectory -PathType Container)) {
        throw 'OS system directory bootstrap is missing.'
    }
    $windowsDirectory = [IO.Directory]::GetParent((Get-NormalizedPath -Path $systemDirectory)).FullName
    Assert-NoReparseDirectoryAncestors -Path $windowsDirectory -Label 'OS Windows directory bootstrap'
    $trustedCmd = [IO.Path]::Combine($systemDirectory, 'cmd.exe')
    $null = Assert-NoReparsePathComponents -Path $trustedCmd -Label 'OS command host bootstrap'
    if (-not (Test-Path -LiteralPath $trustedCmd -PathType Leaf)) {
        throw 'OS command host bootstrap is missing.'
    }
    $trustedTemp = [IO.Path]::Combine($windowsDirectory, 'Temp')
    Assert-LocalFixedDrivePath -Path $trustedTemp -Label 'OS temporary directory bootstrap'
    Assert-NoReparseDirectoryAncestors -Path $trustedTemp -Label 'OS temporary directory bootstrap'
    if (-not (Test-Path -LiteralPath $trustedTemp -PathType Container)) {
        throw 'OS temporary directory bootstrap is missing.'
    }
    $env:SystemRoot = $windowsDirectory
    $env:WINDIR = $windowsDirectory
    $env:ComSpec = $trustedCmd
    $env:TEMP = $trustedTemp
    $env:TMP = $trustedTemp
}

Initialize-TrustedWindowsEnvironment
Assert-NoAmbientEgressOverrides
Assert-NoUnexpectedAmbientSecretVariables

function Assert-SafeEvidenceDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RepositoryPath,
        [string[]]$AdditionalProtectedPaths = @()
    )

    Assert-LocalFixedDrivePath -Path $Path -Label 'OutputDirectory'
    Assert-LocalFixedDrivePath -Path $RepositoryPath -Label 'RepoPath'
    $full = Get-NormalizedPath -Path $Path
    $null = Assert-NoReparsePathComponents -Path $full -Label 'OutputDirectory' -AllowMissingTail
    $protectedPaths = New-Object 'System.Collections.Generic.List[string]'
    foreach ($protectedCandidate in @($RepositoryPath) + @($AdditionalProtectedPaths)) {
        Assert-LocalFixedDrivePath -Path $protectedCandidate -Label 'Protected repository/admin path'
        $protected = Get-NormalizedPath -Path $protectedCandidate
        if ($protected -notin @($protectedPaths)) { $protectedPaths.Add($protected) }
    }
    foreach ($protected in $protectedPaths) {
        Assert-NoReparseDirectoryAncestors -Path $protected -Label 'Protected repository/admin path'
        if (Test-PathsOverlap -First $full -Second $protected) {
            throw 'Evidence directory overlaps RepoPath or a Git admin root.'
        }
    }
    $tempRoots = @(Get-LocalFixedTempRoots)
    foreach ($candidateTemp in $tempRoots) {
        if (Test-PathWithin -Candidate $full -Parent $candidateTemp) {
            throw 'Evidence directory is inside a writable temporary root.'
        }
    }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        throw 'Evidence directory does not exist.'
    }
    Assert-NoReparseDirectoryAncestors -Path $full -Label 'Evidence directory'

    $outputCanonical = Get-FinalDirectoryPath -Path $full
    foreach ($protected in $protectedPaths) {
        $protectedCanonical = Get-FinalDirectoryPath -Path $protected
        if (Test-PathsOverlap -First $outputCanonical -Second $protectedCanonical) {
            throw 'Evidence directory physically overlaps RepoPath or a Git admin root.'
        }
    }
    foreach ($candidateTemp in $tempRoots) {
        if (Test-Path -LiteralPath $candidateTemp -PathType Container) {
            $tempCanonical = Get-FinalDirectoryPath -Path $candidateTemp
            if (Test-PathWithin -Candidate $outputCanonical -Parent $tempCanonical) {
                throw 'Evidence directory resolves physically inside a writable temporary root.'
            }
        }
    }
}

if ('CodexJobWorkerAtomicFile' -as [type]) {
    throw 'A CodexJobWorkerAtomicFile type already exists; the worker requires a fresh trusted Windows PowerShell process.'
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class CodexJobWorkerAtomicFile
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool MoveFileEx(string existingFileName, string newFileName, int flags);
}
'@

if (('CodexJobWorkerPathNative' -as [type]) -or ('CodexJobWorkerByHandleFileInformation' -as [type])) {
    throw 'A Codex worker path-native type already exists; the worker requires a fresh trusted Windows PowerShell process.'
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

[StructLayout(LayoutKind.Sequential)]
public struct CodexJobWorkerByHandleFileInformation
{
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

public static class CodexJobWorkerPathNative
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern SafeFileHandle CreateFileW(
        string fileName,
        uint desiredAccess,
        uint shareMode,
        IntPtr securityAttributes,
        uint creationDisposition,
        uint flagsAndAttributes,
        IntPtr templateFile);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint GetFinalPathNameByHandleW(
        SafeFileHandle file,
        StringBuilder filePath,
        uint filePathSize,
        uint flags);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetFileInformationByHandle(
        SafeFileHandle file,
        out CodexJobWorkerByHandleFileInformation fileInformation);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint GetSystemWindowsDirectoryW(StringBuilder buffer, uint size);
}
'@

if ('CodexJobWorkerBoundedWriteStream' -as [type]) {
    throw 'A CodexJobWorkerBoundedWriteStream type already exists; the worker requires a fresh trusted Windows PowerShell process.'
}
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

public sealed class CodexJobWorkerBoundedWriteStream : Stream
{
    private readonly Stream inner;
    private readonly long limit;
    private long bytesWritten;
    private volatile bool limitExceeded;

    public CodexJobWorkerBoundedWriteStream(Stream inner, long limit)
    {
        if (inner == null) throw new ArgumentNullException("inner");
        if (!inner.CanWrite) throw new ArgumentException("Inner stream must be writable.", "inner");
        if (limit < 0) throw new ArgumentOutOfRangeException("limit");
        this.inner = inner;
        this.limit = limit;
    }

    public long BytesWritten { get { return Interlocked.Read(ref bytesWritten); } }
    public bool LimitExceeded { get { return limitExceeded; } }
    public override bool CanRead { get { return false; } }
    public override bool CanSeek { get { return false; } }
    public override bool CanWrite { get { return true; } }
    public override long Length { get { return BytesWritten; } }
    public override long Position { get { return BytesWritten; } set { throw new NotSupportedException(); } }

    public override void Flush() { inner.Flush(); }
    public override Task FlushAsync(CancellationToken cancellationToken) { return inner.FlushAsync(cancellationToken); }
    public override int Read(byte[] buffer, int offset, int count) { throw new NotSupportedException(); }
    public override long Seek(long offset, SeekOrigin origin) { throw new NotSupportedException(); }
    public override void SetLength(long value) { throw new NotSupportedException(); }

    public override void Write(byte[] buffer, int offset, int count)
    {
        if (buffer == null) throw new ArgumentNullException("buffer");
        if (offset < 0 || count < 0 || buffer.Length - offset < count) throw new ArgumentOutOfRangeException();
        long remaining = limit - BytesWritten;
        int accepted = remaining <= 0 ? 0 : (int)Math.Min((long)count, remaining);
        if (accepted > 0)
        {
            inner.Write(buffer, offset, accepted);
            Interlocked.Add(ref bytesWritten, accepted);
        }
        if (accepted < count) limitExceeded = true;
    }

    public override Task WriteAsync(byte[] buffer, int offset, int count, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Write(buffer, offset, count);
        return Task.FromResult(0);
    }
}
'@

function Get-OpenWorkerFileHandleContract {
    param(
        [Parameter(Mandatory = $true)][IO.FileStream]$Stream,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $information = New-Object CodexJobWorkerByHandleFileInformation
    if (-not [CodexJobWorkerPathNative]::GetFileInformationByHandle($Stream.SafeFileHandle, [ref]$information)) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "$Label file identity query failed. win32_error=$errorCode"
    }

    $capacity = 32768
    $builder = New-Object Text.StringBuilder($capacity)
    $length = [CodexJobWorkerPathNative]::GetFinalPathNameByHandleW(
        $Stream.SafeFileHandle, $builder, [uint32]$capacity, [uint32]0)
    if ($length -eq 0) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "$Label handle canonicalization failed. win32_error=$errorCode"
    }
    if ($length -ge $capacity) {
        $capacity = [int]$length + 1
        $builder = New-Object Text.StringBuilder($capacity)
        $length = [CodexJobWorkerPathNative]::GetFinalPathNameByHandleW(
            $Stream.SafeFileHandle, $builder, [uint32]$capacity, [uint32]0)
        if ($length -eq 0 -or $length -ge $capacity) {
            throw "$Label handle canonicalization returned an invalid length."
        }
    }
    $final = $builder.ToString()
    if ($final.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase)) {
        $final = '\\' + $final.Substring(8)
    } elseif ($final.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        $final = $final.Substring(4)
    }
    Assert-LocalFixedDrivePath -Path $final -Label "$Label physical canonical path"

    return [pscustomobject]@{
        canonical_path = Get-NormalizedPath -Path $final
        volume_serial = ('{0:x8}' -f ([uint32]$information.VolumeSerialNumber))
        file_id = ('{0:x8}{1:x8}' -f ([uint32]$information.FileIndexHigh), ([uint32]$information.FileIndexLow))
        link_count = [uint32]$information.NumberOfLinks
    }
}

function Get-ScriptFileContract {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $identity = Get-OpenWorkerFileHandleContract -Stream $stream -Label $Label
        if ([uint32]$identity.link_count -ne 1) { throw "$Label must have exactly one hard link." }
        if ($stream.Length -le 0 -or $stream.Length -gt [long]$script:CodexJobScriptMaxBytes) {
            throw "$Label length is outside the fixed script safety limit."
        }
        $stream.Position = 0
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try {
            $hash = (($algorithm.ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) -join '')
        } finally {
            $algorithm.Dispose()
        }
        return [pscustomobject]@{
            path = Get-NormalizedPath -Path $stream.Name
            canonical_path = [string]$identity.canonical_path
            volume_serial = [string]$identity.volume_serial
            file_id = [string]$identity.file_id
            link_count = [uint32]$identity.link_count
            length_bytes = [long]$stream.Length
            sha256 = $hash
        }
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-SafeGitConfigHandleContract {
    param(
        [Parameter(Mandatory = $true)][IO.FileStream]$Stream,
        [Parameter(Mandatory = $true)][string]$ExpectedPath
    )

    $worktreeConfigPath = [IO.Path]::Combine([IO.Path]::GetDirectoryName($ExpectedPath), 'config.worktree')
    $null = Assert-NoReparsePathComponents -Path $worktreeConfigPath -Label 'Git worktree config path' -AllowMissingTail
    if (Test-Path -LiteralPath $worktreeConfigPath) {
        throw 'Git config.worktree is forbidden for delegated jobs.'
    }
    $identity = Get-OpenWorkerFileHandleContract -Stream $Stream -Label 'Git config'
    if ([uint32]$identity.link_count -ne 1) { throw 'Git config must have exactly one hard link.' }
    if ($Stream.Length -le 0 -or $Stream.Length -gt [long]$script:CodexJobGitConfigMaxBytes) {
        throw 'Git config length is outside the fixed safety limit.'
    }
    if ((Get-NormalizedPath -Path $Stream.Name) -ine (Get-NormalizedPath -Path $ExpectedPath)) {
        throw 'Git config stream path differs from the recorded direct .git/config path.'
    }

    $bytes = New-Object byte[] ([int]$Stream.Length)
    $Stream.Position = 0
    $offset = 0
    while ($offset -lt $bytes.Length) {
        $read = $Stream.Read($bytes, $offset, $bytes.Length - $offset)
        if ($read -le 0) { throw 'Git config ended before its recorded length.' }
        $offset += $read
    }
    if ($Stream.ReadByte() -ne -1) { throw 'Git config grew while its locked handle was being validated.' }
    $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
    try { $text = $strictUtf8.GetString($bytes) } catch { throw 'Git config must be strict UTF-8.' }
    if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
    if ($text.IndexOf([char]0) -ge 0) { throw 'Git config must not contain NUL bytes.' }

    $allowedKeys = @{
        core = @('repositoryformatversion', 'filemode', 'bare', 'logallrefupdates', 'symlinks', 'ignorecase', 'precomposeunicode', 'protecthfs', 'protectntfs')
        user = @('name', 'email')
        remote = @('url', 'pushurl', 'fetch', 'tagopt', 'mirror', 'prune', 'prunetags', 'skipdefaultupdate')
        branch = @('remote', 'pushremote', 'merge', 'rebase', 'description')
        init = @('defaultbranch')
        pull = @('rebase', 'ff', 'octopus', 'twohead')
        push = @('default', 'followtags', 'autosetupremote')
        fetch = @('prune', 'prunetags', 'recursesubmodules', 'writecommitgraph', 'parallel')
        submodule = @('url', 'active', 'branch', 'ignore', 'shallow')
        status = @('showuntrackedfiles', 'submodulesummary', 'renames', 'relativepaths', 'short')
        color = @('ui')
        extensions = @('objectformat', 'refstorage')
    }
    $section = $null
    foreach ($rawLine in @($text -split "`n", -1)) {
        $line = $rawLine.TrimEnd("`r").Trim()
        if ($line.Length -eq 0 -or $line.StartsWith('#') -or $line.StartsWith(';')) { continue }
        if ($line.EndsWith('\')) { throw 'Git config line continuations are forbidden by the bounded parser.' }
        if ($line.StartsWith('[')) {
            if ($line -notmatch '^\[([A-Za-z][A-Za-z0-9.-]*)(?:\s+"(?:[^"\\]|\\.)*")?\]$') {
                throw 'Git config has an unsupported section header (content not logged).'
            }
            $section = $Matches[1].ToLowerInvariant()
            if (-not $allowedKeys.ContainsKey($section)) {
                throw "Git config section is outside the safe allowlist: $section"
            }
            continue
        }
        if ([string]::IsNullOrWhiteSpace($section) -or
            $line -notmatch '^([A-Za-z][A-Za-z0-9-]*)\s*(?:=.*)?$') {
            throw 'Git config has an unsupported key/value line (content not logged).'
        }
        $key = $Matches[1].ToLowerInvariant()
        if ($key -notin @($allowedKeys[$section])) {
            throw "Git config key is outside the safe allowlist: $section.$key"
        }
    }

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { $hash = (($algorithm.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '') } finally { $algorithm.Dispose() }
    $Stream.Position = 0
    return [pscustomobject]@{
        path = Get-NormalizedPath -Path $Stream.Name
        canonical_path = [string]$identity.canonical_path
        volume_serial = [string]$identity.volume_serial
        file_id = [string]$identity.file_id
        link_count = [uint32]$identity.link_count
        length_bytes = [long]$Stream.Length
        sha256 = $hash
        contract = 'bounded-1048576-byte-strict-utf8;single-hard-link;safe-section-key-allowlist;no-includes-external-command-or-config-worktree'
    }
}

function Get-SafeGitConfigContract {
    param([Parameter(Mandatory = $true)][string]$Path)

    Assert-LocalFixedDrivePath -Path $Path -Label 'Git config path'
    $null = Assert-NoReparsePathComponents -Path $Path -Label 'Git config path'
    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        return (Get-SafeGitConfigHandleContract -Stream $stream -ExpectedPath $Path)
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Assert-SafeGitConfigContractCurrent {
    param([Parameter(Mandatory = $true)][psobject]$Job)

    $current = Get-SafeGitConfigContract -Path ([string]$Job.git_config_path)
    foreach ($property in @('path', 'canonical_path', 'volume_serial', 'file_id', 'link_count', 'length_bytes', 'sha256', 'contract')) {
        $metadataProperty = "git_config_$property"
        if ([string]$current.$property -ine [string]$Job.$metadataProperty) {
            throw "Recorded Git config integrity changed: $metadataProperty"
        }
    }
}

function Open-ValidatedGitConfigStream {
    param([Parameter(Mandatory = $true)][psobject]$Job)

    foreach ($property in @('git_config_path', 'git_config_canonical_path', 'git_config_volume_serial', 'git_config_file_id',
        'git_config_link_count', 'git_config_length_bytes', 'git_config_sha256', 'git_config_contract')) {
        if ($null -eq $Job.PSObject.Properties[$property]) { throw "Metadata is missing required property: $property" }
    }
    $stream = $null
    try {
        $stream = [IO.File]::Open(
            [string]$Job.git_config_path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $current = Get-SafeGitConfigHandleContract -Stream $stream -ExpectedPath ([string]$Job.git_config_path)
        foreach ($property in @('path', 'canonical_path', 'volume_serial', 'file_id', 'link_count', 'length_bytes', 'sha256', 'contract')) {
            $metadataProperty = "git_config_$property"
            if ([string]$current.$property -ine [string]$Job.$metadataProperty) {
                throw "Recorded Git config integrity changed before lock acquisition: $metadataProperty"
            }
        }
        return $stream
    } catch {
        if ($null -ne $stream) { $stream.Dispose() }
        throw
    }
}

function Assert-RecordedScriptTrust {
    param([Parameter(Mandatory = $true)][psobject]$Job)

    $scriptDirectories = New-Object 'System.Collections.Generic.List[string]'
    foreach ($prefix in @('start_script', 'worker_script')) {
        $pathProperty = "${prefix}_path"
        $path = [string]$Job.$pathProperty
        Assert-LocalFixedDrivePath -Path $path -Label "$prefix path"
        $null = Assert-NoReparsePathComponents -Path $path -Label "$prefix path"
        $current = Get-ScriptFileContract -Path $path -Label $prefix
        foreach ($property in @('path', 'canonical_path', 'volume_serial', 'file_id', 'link_count', 'length_bytes', 'sha256')) {
            $metadataProperty = '{0}_{1}' -f $prefix, $property
            if ([string]$current.$property -ine [string]$Job.$metadataProperty) {
                throw "Recorded helper script integrity changed: $metadataProperty"
            }
        }
        $directory = [IO.Path]::GetDirectoryName($path)
        Assert-NoReparseDirectoryAncestors -Path $directory -Label "$prefix directory"
        $canonicalDirectory = Get-FinalDirectoryPath -Path $directory
        if ($canonicalDirectory -notin @($scriptDirectories)) { $scriptDirectories.Add($canonicalDirectory) }
    }
    if ($scriptDirectories.Count -ne 1) { throw 'Start and worker scripts no longer share one physical directory.' }
    if ((Get-NormalizedPath -Path $script:CodexJobWorkerSelfPath) -ine (Get-NormalizedPath -Path ([string]$Job.worker_script_path))) {
        throw 'The executing worker path differs from its recorded contract.'
    }
    foreach ($boundary in @(
        [string]$Job.repo_path, [string]$Job.git_directory, [string]$Job.git_common_directory,
        [string]$Job.output_directory
    ) + @(Get-LocalFixedTempRoots)) {
        Assert-LocalFixedDrivePath -Path $boundary -Label 'Script protected boundary'
        if (Test-PathsOverlap -First $scriptDirectories[0] -Second (Get-NormalizedPath -Path $boundary)) {
            throw 'Helper script directory overlaps a repository, Git admin, evidence, or temp boundary.'
        }
        if (Test-Path -LiteralPath $boundary -PathType Container) {
            if (Test-PathsOverlap -First $scriptDirectories[0] -Second (Get-FinalDirectoryPath -Path $boundary)) {
                throw 'Helper script directory physically overlaps a protected boundary.'
            }
        }
    }
    if ([string]$Job.script_integrity_contract -cne 'local-fixed-nonreparse-disjoint;single-hard-link;handle-identity-and-sha256;worker-read-locked-through-handshake') {
        throw 'Metadata has an unsupported helper script integrity contract.'
    }
}

function Get-FinalExistingPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('Container', 'Leaf')][string]$PathType
    )

    Assert-LocalFixedDrivePath -Path $Path -Label 'Canonicalization path'
    $full = Get-NormalizedPath -Path $Path
    $null = Assert-NoReparsePathComponents -Path $full -Label 'Canonicalization path'
    if (-not (Test-Path -LiteralPath $full -PathType $PathType)) {
        throw "Cannot canonicalize a missing $PathType path: $full"
    }
    $openFlags = if ($PathType -eq 'Container') { [uint32]0x02000000 } else { [uint32]0 }
    $handle = [CodexJobWorkerPathNative]::CreateFileW(
        $full,
        [uint32]0,
        [uint32]7,
        [IntPtr]::Zero,
        [uint32]3,
        $openFlags,
        [IntPtr]::Zero
    )
    if ($handle.IsInvalid) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        $handle.Dispose()
        throw "Directory canonicalization open failed. path=$full win32_error=$errorCode"
    }
    try {
        $capacity = 32768
        $builder = New-Object Text.StringBuilder($capacity)
        $length = [CodexJobWorkerPathNative]::GetFinalPathNameByHandleW($handle, $builder, [uint32]$capacity, [uint32]0)
        if ($length -eq 0) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Directory canonicalization failed. path=$full win32_error=$errorCode"
        }
        if ($length -ge $capacity) {
            $capacity = [int]$length + 1
            $builder = New-Object Text.StringBuilder($capacity)
            $length = [CodexJobWorkerPathNative]::GetFinalPathNameByHandleW($handle, $builder, [uint32]$capacity, [uint32]0)
            if ($length -eq 0 -or $length -ge $capacity) {
                throw "Directory canonicalization returned an invalid length: $full"
            }
        }
        $final = $builder.ToString()
    } finally {
        $handle.Dispose()
    }
    if ($final.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase)) {
        $final = '\\' + $final.Substring(8)
    } elseif ($final.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        $final = $final.Substring(4)
    }
    Assert-LocalFixedDrivePath -Path $final -Label 'Physical canonical path'
    return (Get-NormalizedPath -Path $final)
}

function Get-FinalDirectoryPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FinalExistingPath -Path $Path -PathType 'Container')
}

function Get-FinalFilePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FinalExistingPath -Path $Path -PathType 'Leaf')
}

function Get-TrustedWindowsDirectory {
    $capacity = 32768
    $builder = New-Object Text.StringBuilder($capacity)
    $length = [CodexJobWorkerPathNative]::GetSystemWindowsDirectoryW($builder, [uint32]$capacity)
    if ($length -eq 0 -or $length -ge $capacity) { throw 'GetSystemWindowsDirectoryW failed or returned an invalid length.' }
    $reported = $builder.ToString()
    Assert-LocalFixedDrivePath -Path $reported -Label 'System Windows directory'
    $null = Assert-NoReparsePathComponents -Path $reported -Label 'System Windows directory'
    $resolved = (Resolve-Path -LiteralPath $reported).Path
    Assert-NoReparseDirectoryAncestors -Path $resolved -Label 'System Windows directory'
    return (Get-FinalDirectoryPath -Path $resolved)
}

function Get-TrustedCoreChildPath {
    param([string[]]$AdditionalDirectories = @())

    $windowsDirectory = Get-TrustedWindowsDirectory
    $systemDirectory = [IO.Path]::Combine($windowsDirectory, 'System32')
    $powerShellDirectory = [IO.Path]::Combine($systemDirectory, 'WindowsPowerShell', 'v1.0')
    $ordered = New-Object 'System.Collections.Generic.List[string]'
    foreach ($candidate in @($AdditionalDirectories) + @($systemDirectory, $windowsDirectory, $powerShellDirectory)) {
        Assert-LocalFixedDrivePath -Path $candidate -Label 'Trusted child PATH directory'
        $null = Assert-NoReparsePathComponents -Path $candidate -Label 'Trusted child PATH directory'
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
            throw "Trusted child PATH directory is missing: $candidate"
        }
        $canonical = Get-FinalDirectoryPath -Path $candidate
        if ($canonical -notin @($ordered)) { $ordered.Add($canonical) }
    }
    return ($ordered -join ';')
}

function Invoke-WorkerAuthenticodeCapture {
    param(
        [Parameter(Mandatory = $true)][string]$PowerShellPath,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $signatureScript = @'
$ErrorActionPreference = 'Stop'
$moduleRoot = [IO.Path]::GetFullPath([IO.Path]::Combine($PSHOME, 'Modules')).TrimEnd('\') + '\'
$expectedModules = @{
    'Get-AuthenticodeSignature' = 'Microsoft.PowerShell.Security'
    'ConvertTo-Json' = 'Microsoft.PowerShell.Utility'
}
foreach ($name in $expectedModules.Keys) {
    $resolved = @(Microsoft.PowerShell.Core\Get-Command -Name $name -ErrorAction Stop)
    $modulePath = if ($resolved.Count -eq 1 -and $null -ne $resolved[0].Module) { [string]$resolved[0].Module.Path } else { '' }
    if ($resolved.Count -ne 1 -or $resolved[0].CommandType -ne [Management.Automation.CommandTypes]::Cmdlet -or
        [string]$resolved[0].ModuleName -cne [string]$expectedModules[$name] -or
        -not ([IO.Path]::GetFullPath($modulePath).StartsWith($moduleRoot, [StringComparison]::OrdinalIgnoreCase))) {
        throw "Authenticode child command provenance is untrusted: $name"
    }
}
$signature = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $env:WORKER_AUTHENTICODE_TARGET
if ($null -eq $signature.SignerCertificate) { throw 'No signer certificate.' }
$versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($env:WORKER_AUTHENTICODE_TARGET)
[pscustomobject]@{
    status = $signature.Status.ToString()
    subject = $signature.SignerCertificate.Subject
    simple_name = $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
    thumbprint = $signature.SignerCertificate.Thumbprint
    product_version = $(if (-not [string]::IsNullOrWhiteSpace($versionInfo.ProductVersion)) {
        $versionInfo.ProductVersion
    } elseif (-not [string]::IsNullOrWhiteSpace($versionInfo.FileVersion)) {
        $versionInfo.FileVersion
    } else {
        $versionInfo.ProductVersionRaw.ToString()
    })
} | Microsoft.PowerShell.Utility\ConvertTo-Json -Compress
'@
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($signatureScript))
    $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand)
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $PowerShellPath
    $startInfo.Arguments = (($arguments | ForEach-Object { Quote-NativeArgument -Value $_ }) -join ' ')
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $trustedChildTemp = Get-TrustedChildTempDirectory
    $trustedWindowsDirectory = Get-TrustedWindowsDirectory
    $startInfo.EnvironmentVariables['TEMP'] = $trustedChildTemp
    $startInfo.EnvironmentVariables['TMP'] = $trustedChildTemp
    $startInfo.EnvironmentVariables['SystemRoot'] = $trustedWindowsDirectory
    $startInfo.EnvironmentVariables['WINDIR'] = $trustedWindowsDirectory
    $startInfo.EnvironmentVariables['ComSpec'] = [IO.Path]::Combine($trustedWindowsDirectory, 'System32', 'cmd.exe')
    Remove-BlockedChildEnvironmentVariables -EnvironmentVariables $startInfo.EnvironmentVariables
    $startInfo.EnvironmentVariables['PATH'] = Get-TrustedCoreChildPath
    $startInfo.EnvironmentVariables['PATHEXT'] = '.EXE'
    $startInfo.EnvironmentVariables['NoDefaultCurrentDirectoryInExePath'] = '1'
    $trustedModuleRoot = [IO.Path]::Combine($WorkingDirectory, 'Modules')
    Assert-NoReparseDirectoryAncestors -Path $trustedModuleRoot -Label 'Authenticode child module directory'
    $startInfo.EnvironmentVariables['PSModulePath'] = Get-FinalDirectoryPath -Path $trustedModuleRoot
    Set-TrustedGitEnvironmentVariables -EnvironmentVariables $startInfo.EnvironmentVariables
    $startInfo.EnvironmentVariables['WORKER_AUTHENTICODE_TARGET'] = $TargetPath
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw "$Label Authenticode Process.Start returned false." }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(15000)) {
            try { $process.Kill() } catch { }
            try { $null = $process.WaitForExit(1000) } catch { }
            try { $process.StandardOutput.Dispose() } catch { }
            try { $process.StandardError.Dispose() } catch { }
            throw "$Label Authenticode validation timed out."
        }
        $deadline = [DateTime]::UtcNow.AddSeconds(2)
        foreach ($task in @($stdoutTask, $stderrTask)) {
            if (-not $task.IsCompleted) {
                $remaining = [int][Math]::Max(0, ($deadline - [DateTime]::UtcNow).TotalMilliseconds)
                if ($remaining -gt 0) { try { $null = $task.Wait($remaining) } catch { } }
            }
        }
        if (-not $stdoutTask.IsCompleted -or -not $stderrTask.IsCompleted) {
            try { $process.StandardOutput.Dispose() } catch { }
            try { $process.StandardError.Dispose() } catch { }
            throw "$Label Authenticode output capture exceeded its deadline."
        }
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw "$Label Authenticode child failed: $stderr" }
        try { return ($stdout.Trim() | ConvertFrom-Json) } catch { throw "$Label Authenticode child returned invalid JSON." }
    } finally {
        $process.Dispose()
    }
}

function Get-TrustedSystemPowerShellContract {
    $windowsDirectory = Get-TrustedWindowsDirectory
    $path = [IO.Path]::Combine($windowsDirectory, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe')
    Assert-LocalFixedDrivePath -Path $path -Label 'System PowerShell host'
    $null = Assert-NoReparsePathComponents -Path $path -Label 'System PowerShell host'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'System PowerShell host is missing.' }
    $item = Get-Item -LiteralPath $path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'System PowerShell host must not be a reparse point.' }
    $directory = [IO.Path]::GetDirectoryName($path)
    Assert-NoReparseDirectoryAncestors -Path $directory -Label 'System PowerShell directory'
    $canonical = Get-FinalFilePath -Path $path
    $workingDirectory = Get-FinalDirectoryPath -Path $directory
    $signature = Invoke-WorkerAuthenticodeCapture -PowerShellPath $canonical -WorkingDirectory $workingDirectory `
        -TargetPath $canonical -Label 'System PowerShell'
    if ([string]$signature.status -ne 'Valid' -or [string]$signature.simple_name -cne 'Microsoft Windows' -or
        [string]$signature.subject -notmatch '(?:^|, )O=Microsoft Corporation(?:,|$)') {
        throw "System PowerShell signer is outside the Microsoft Windows allowlist: $($signature.subject)"
    }
    return [pscustomobject]@{
        path = $canonical
        working_directory = $workingDirectory
        sha256 = Get-Sha256Hex -Path $canonical
        signer_subject = [string]$signature.subject
        signer_thumbprint = [string]$signature.thumbprint
    }
}

function Write-JobMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][psobject]$Value
    )

    Set-ObjectProperty -Object $Value -Name 'updated_at_utc' -Value ((Get-Date).ToUniversalTime().ToString('o'))
    $json = $Value | ConvertTo-Json -Depth 8
    $temporaryPath = '{0}.{1}.tmp' -f $Path, ([guid]::NewGuid().ToString('N'))
    $encoding = New-Object Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($temporaryPath, $json, $encoding)
    $moved = [CodexJobWorkerAtomicFile]::MoveFileEx($temporaryPath, $Path, 0x1 -bor 0x8)
    if (-not $moved) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        throw "Atomic metadata update failed. path=$Path win32_error=$errorCode"
    }
}

function Read-JobMetadata {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json)
}

function Get-Sha256Hex {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $algorithm.ComputeHash($stream)
        return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

function Open-ValidatedPromptStream {
    param([Parameter(Mandatory = $true)][psobject]$Job)

    $path = [string]$Job.prompt_path
    Assert-LocalFixedDrivePath -Path $path -Label 'PromptPath'
    $stream = $null
    try {
        # FileShare.Read denies concurrent writers and delete/replace while the exact
        # handle is validated and later copied to Codex stdin.
        $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $identity = Get-OpenWorkerFileHandleContract -Stream $stream -Label 'PromptPath'
        if ([string]$identity.canonical_path -ine (Get-NormalizedPath -Path ([string]$Job.prompt_canonical_path))) {
            throw 'Prompt canonical path changed at handle-open time.'
        }
        if ([string]$identity.volume_serial -ine [string]$Job.prompt_volume_serial -or
            [string]$identity.file_id -ine [string]$Job.prompt_file_id) {
            throw 'Prompt file identity changed after job creation.'
        }
        if ([uint32]$identity.link_count -ne 1 -or [uint32]$Job.prompt_link_count -ne 1) {
            throw 'Prompt must retain exactly one hard link.'
        }
        if ($stream.Length -ne [long]$Job.prompt_length_bytes) {
            throw 'Prompt handle length changed after job creation.'
        }
        if ([long]$Job.prompt_max_bytes -ne [long]$script:CodexJobPromptMaxBytes -or
            $stream.Length -gt [long]$script:CodexJobPromptMaxBytes) {
            throw 'Prompt exceeds or changed its fixed size contract.'
        }

        $stream.Position = 0
        $bytes = New-Object byte[] ([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($read -le 0) { throw 'Prompt handle ended before its recorded length.' }
            $offset += $read
        }
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try {
            $hash = (($algorithm.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
        } finally {
            $algorithm.Dispose()
        }
        if ($hash -ine [string]$Job.prompt_sha256) { throw 'Prompt handle hash changed after job creation.' }
        if ([string]$Job.prompt_encoding -ne 'utf-8') { throw 'Recorded prompt encoding must be utf-8.' }
        $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
        try { $decoded = $strictUtf8.GetString($bytes) } catch [Text.DecoderFallbackException] {
            throw 'Prompt handle is not valid UTF-8.'
        }
        if ($decoded.IndexOf([char]0) -ge 0) { throw 'Prompt handle contains NUL characters.' }
        $hasUtf8Bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        if ($hasUtf8Bom -ne [bool]$Job.prompt_utf8_bom) { throw 'Prompt handle UTF-8 BOM state changed.' }
        $stream.Position = 0
        return $stream
    } catch {
        if ($null -ne $stream) { $stream.Dispose() }
        throw
    }
}

function Get-GitBindingContract {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryPath,
        [Parameter(Mandatory = $true)][string]$GitDirectory,
        [Parameter(Mandatory = $true)][string]$GitCommonDirectory
    )

    $markerPath = Join-Path $RepositoryPath '.git'
    Assert-LocalFixedDrivePath -Path $markerPath -Label 'Git marker path'
    $null = Assert-NoReparsePathComponents -Path $markerPath -Label 'Git marker path' -AllowMissingTail
    $markerKind = $null
    $markerCanonicalPath = $null
    $markerLength = $null
    $markerHash = $null
    if (Test-Path -LiteralPath $markerPath -PathType Container) {
        $markerKind = 'directory'
        Assert-NoReparseDirectoryAncestors -Path $markerPath -Label 'Git marker directory'
        $markerCanonicalPath = Get-FinalDirectoryPath -Path $markerPath
        if ($markerCanonicalPath -ine (Get-FinalDirectoryPath -Path $GitDirectory)) {
            throw 'The .git directory does not match the recorded Git directory.'
        }
    } elseif (Test-Path -LiteralPath $markerPath -PathType Leaf) {
        $markerKind = 'file'
        $markerItem = Get-Item -LiteralPath $markerPath -Force
        if (($markerItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'The .git marker file must not be a reparse point.'
        }
        $markerCanonicalPath = Get-FinalFilePath -Path $markerPath
        $markerLength = [long]$markerItem.Length
        $markerHash = Get-Sha256Hex -Path $markerPath
    } else {
        throw 'The repository has no direct .git file or directory marker.'
    }

    $commondirMarkerPath = Join-Path $GitDirectory 'commondir'
    Assert-LocalFixedDrivePath -Path $commondirMarkerPath -Label 'Git commondir marker path'
    $null = Assert-NoReparsePathComponents -Path $commondirMarkerPath -Label 'Git commondir marker path' -AllowMissingTail
    $commondirMarkerKind = 'absent'
    $commondirMarkerCanonicalPath = $null
    $commondirMarkerLength = $null
    $commondirMarkerHash = $null
    if (Test-Path -LiteralPath $commondirMarkerPath) {
        if (-not (Test-Path -LiteralPath $commondirMarkerPath -PathType Leaf)) {
            throw 'Git commondir marker exists but is not a file.'
        }
        $commondirItem = Get-Item -LiteralPath $commondirMarkerPath -Force
        if (($commondirItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'The Git commondir marker must not be a reparse point.'
        }
        $commondirMarkerKind = 'file'
        $commondirMarkerCanonicalPath = Get-FinalFilePath -Path $commondirMarkerPath
        $commondirMarkerLength = [long]$commondirItem.Length
        $commondirMarkerHash = Get-Sha256Hex -Path $commondirMarkerPath
    } elseif ((Get-FinalDirectoryPath -Path $GitDirectory) -ine (Get-FinalDirectoryPath -Path $GitCommonDirectory)) {
        throw 'A split Git common directory requires a direct commondir marker file.'
    }

    return [pscustomobject]@{
        git_marker_path = Get-NormalizedPath -Path $markerPath
        git_marker_kind = $markerKind
        git_marker_canonical_path = $markerCanonicalPath
        git_marker_length_bytes = $markerLength
        git_marker_sha256 = $markerHash
        git_commondir_marker_path = Get-NormalizedPath -Path $commondirMarkerPath
        git_commondir_marker_kind = $commondirMarkerKind
        git_commondir_marker_canonical_path = $commondirMarkerCanonicalPath
        git_commondir_marker_length_bytes = $commondirMarkerLength
        git_commondir_marker_sha256 = $commondirMarkerHash
    }
}

function Assert-GitBindingUnchanged {
    param([Parameter(Mandatory = $true)][psobject]$Job)

    $current = Get-GitBindingContract -RepositoryPath ([string]$Job.repo_path) `
        -GitDirectory ([string]$Job.git_directory) -GitCommonDirectory ([string]$Job.git_common_directory)
    foreach ($property in @(
        'git_marker_path', 'git_marker_kind', 'git_marker_canonical_path', 'git_marker_length_bytes', 'git_marker_sha256',
        'git_commondir_marker_path', 'git_commondir_marker_kind', 'git_commondir_marker_canonical_path',
        'git_commondir_marker_length_bytes', 'git_commondir_marker_sha256'
    )) {
        if ([string]$current.$property -cne [string]$Job.$property) {
            throw "Git administrative binding changed: $property"
        }
    }
}

function Quote-NativeArgument {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') {
        return $Value
    }

    $builder = New-Object Text.StringBuilder
    $null = $builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes += 1
            continue
        }
        if ($character -eq '"') {
            if ($backslashes -gt 0) {
                $null = $builder.Append((('\' * ($backslashes * 2)) -join ''))
            }
            $null = $builder.Append('\"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            $null = $builder.Append((('\' * $backslashes) -join ''))
            $backslashes = 0
        }
        $null = $builder.Append($character)
    }
    if ($backslashes -gt 0) {
        $null = $builder.Append((('\' * ($backslashes * 2)) -join ''))
    }
    $null = $builder.Append('"')
    return $builder.ToString()
}

function New-CodexStartInfo {
    param([Parameter(Mandatory = $true)][psobject]$Job)

    $arguments = @($Job.codex_arguments | ForEach-Object { [string]$_ })
    $expectedChildPowerShellModulePath = Get-FinalDirectoryPath -Path $entryTrustedModuleRoot
    $escapedChildPowerShellModulePath = $expectedChildPowerShellModulePath.Replace('\', '\\').Replace('"', '\"')
    $expectedShellPSModulePathOverride = 'shell_environment_policy.set.PSModulePath="' + $escapedChildPowerShellModulePath + '"'
    $disabledFeatureArguments = New-Object 'System.Collections.Generic.List[string]'
    foreach ($featureName in $script:CodexJobDisabledFeatures) {
        $disabledFeatureArguments.Add('--disable')
        $disabledFeatureArguments.Add([string]$featureName)
    }
    $expectedArguments = @(
        "--ask-for-approval=$($Job.approval_policy)",
        'exec'
    ) + @($disabledFeatureArguments.ToArray()) + @(
        '--ignore-user-config',
        '--ignore-rules',
        '--strict-config',
        '--ephemeral',
        '--json',
        "--model=$($Job.model)",
        '-c',
        "model_reasoning_effort=$($Job.reasoning_effort)",
        '-c',
        'shell_environment_policy.inherit="core"',
        '-c',
        'shell_environment_policy.ignore_default_excludes=false',
        '-c',
        'shell_environment_policy.exclude=["CODEX_API_KEY","OPENAI_API_KEY","CODEX_ACCESS_TOKEN"]',
        '-c',
        'shell_environment_policy.set.NoDefaultCurrentDirectoryInExePath="1"',
        '-c',
        'shell_environment_policy.set.PATHEXT=".EXE"',
        '-c',
        $expectedShellPSModulePathOverride,
        '-c',
        'allow_login_shell=false',
        '-c',
        'shell_environment_policy.experimental_use_profile=false',
        '-c',
        'shell_environment_policy.set.GIT_CONFIG_NOSYSTEM="1"',
        '-c',
        'shell_environment_policy.set.GIT_CONFIG_GLOBAL="NUL"',
        '-c',
        'shell_environment_policy.set.GIT_TERMINAL_PROMPT="0"',
        '-c',
        'shell_environment_policy.set.GCM_INTERACTIVE="Never"',
        '-c',
        'sandbox_workspace_write.network_access=false',
        '-c',
        'sandbox_workspace_write.exclude_tmpdir_env_var=true',
        '-c',
        'sandbox_workspace_write.exclude_slash_tmp=true',
        '-c',
        'model_provider="openai"',
        '-c',
        'web_search="disabled"',
        '-c',
        'skills.include_instructions=false',
        '-c',
        'skills.bundled.enabled=false',
        "--sandbox=$($Job.sandbox)",
        '-C',
        [string]$Job.repo_path,
        '-'
    )
    if ($arguments.Count -ne $expectedArguments.Count) {
        throw 'Refusing to launch: Codex argv count differs from the fixed delegation contract.'
    }
    for ($argumentIndex = 0; $argumentIndex -lt $arguments.Count; $argumentIndex++) {
        if ([string]$arguments[$argumentIndex] -cne [string]$expectedArguments[$argumentIndex]) {
            throw "Refusing to launch: Codex argv differs from the fixed delegation contract at index $argumentIndex."
        }
    }

    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.WorkingDirectory = [string]$Job.codex_working_directory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $trustedChildTemp = Get-TrustedChildTempDirectory
    $trustedWindowsDirectory = Get-TrustedWindowsDirectory
    $startInfo.EnvironmentVariables['TEMP'] = $trustedChildTemp
    $startInfo.EnvironmentVariables['TMP'] = $trustedChildTemp
    $startInfo.EnvironmentVariables['SystemRoot'] = $trustedWindowsDirectory
    $startInfo.EnvironmentVariables['WINDIR'] = $trustedWindowsDirectory
    $startInfo.EnvironmentVariables['ComSpec'] = [IO.Path]::Combine($trustedWindowsDirectory, 'System32', 'cmd.exe')
    Remove-BlockedChildEnvironmentVariables -EnvironmentVariables $startInfo.EnvironmentVariables
    $expectedChildPath = Get-TrustedCoreChildPath -AdditionalDirectories @([string]$Job.git_executable_working_directory)
    if ([string]$Job.child_executable_path -cne $expectedChildPath -or
        [string]$Job.child_executable_pathext -cne '.EXE' -or
        [string]$Job.child_no_default_current_directory -cne '1') {
        throw 'Recorded child executable search path changed or is unsupported.'
    }
    $startInfo.EnvironmentVariables['PATH'] = $expectedChildPath
    $startInfo.EnvironmentVariables['PATHEXT'] = '.EXE'
    $startInfo.EnvironmentVariables['NoDefaultCurrentDirectoryInExePath'] = '1'
    $startInfo.EnvironmentVariables['PSModulePath'] = $expectedChildPowerShellModulePath
    Set-TrustedGitEnvironmentVariables -EnvironmentVariables $startInfo.EnvironmentVariables
    $startInfo.EnvironmentVariables['CODEX_HOME'] = [string]$Job.codex_home_path
    if ([string]$Job.auth_channel -eq 'codex-api-key-environment') {
        if (-not [bool]$Job.codex_api_key_environment_approved -or
            [string]::IsNullOrWhiteSpace([string]$env:CODEX_API_KEY)) {
            throw 'Approved CODEX_API_KEY is unavailable for the Codex launcher.'
        }
        $startInfo.EnvironmentVariables['CODEX_API_KEY'] = [string]$env:CODEX_API_KEY
    }

    $launcherExtension = [IO.Path]::GetExtension([string]$Job.codex_path).ToLowerInvariant()
    if ($launcherExtension -ne '.exe') { throw "Unsupported Codex launcher extension: $launcherExtension" }
    $startInfo.FileName = [string]$Job.codex_path
    $startInfo.Arguments = (($arguments | ForEach-Object { Quote-NativeArgument -Value $_ }) -join ' ')
    return $startInfo
}

function Assert-RecordedLauncherTrust {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$CanonicalPath,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string[]]$ProtectedDirectories,
        [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
        [Parameter(Mandatory = $true)][string]$Label
    )

    foreach ($contractPath in @($Path, $CanonicalPath, $WorkingDirectory)) {
        Assert-LocalFixedDrivePath -Path $contractPath -Label "$Label contract path"
    }
    if ([IO.Path]::GetExtension($Path) -ine '.exe') { throw "$Label must be a native .exe." }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing." }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Label must not be a reparse point." }
    $directory = [IO.Path]::GetDirectoryName($Path)
    Assert-NoReparseDirectoryAncestors -Path $directory -Label "$Label directory"
    $currentCanonical = Get-FinalFilePath -Path $Path
    $currentDirectory = Get-FinalDirectoryPath -Path $directory
    if ($currentCanonical -ine (Get-NormalizedPath -Path $CanonicalPath) -or
        $currentDirectory -ine (Get-NormalizedPath -Path $WorkingDirectory) -or
        [IO.Path]::GetDirectoryName($currentCanonical) -ine $currentDirectory) {
        throw "$Label canonical path or working directory changed."
    }

    foreach ($boundary in @($ProtectedDirectories) + @($EvidenceDirectory) + @(Get-LocalFixedTempRoots)) {
        Assert-LocalFixedDrivePath -Path $boundary -Label 'Launcher boundary'
        if (Test-PathsOverlap -First $currentDirectory -Second $boundary) {
            throw "$Label directory overlaps a protected boundary."
        }
        if (Test-Path -LiteralPath $boundary -PathType Container) {
            $boundaryCanonical = Get-FinalDirectoryPath -Path $boundary
            if (Test-PathsOverlap -First $currentDirectory -Second $boundaryCanonical) {
                throw "$Label directory physically overlaps a protected boundary."
            }
        }
    }
    if ((Get-Sha256Hex -Path $currentCanonical) -ine $ExpectedSha256) { throw "$Label SHA-256 changed." }
}

function Assert-RecordedCodexHomeContract {
    param([Parameter(Mandatory = $true)][psobject]$Job)

    $path = Get-NormalizedPath -Path ([string]$Job.codex_home_path)
    Assert-NoReparseDirectoryAncestors -Path $path -Label 'Pinned Codex home'
    $canonical = Get-FinalDirectoryPath -Path $path
    if ($canonical -ine (Get-NormalizedPath -Path ([string]$Job.codex_home_canonical_path)) -or
        [string]$Job.codex_home_contract -ne 'os-user-profile-default;ambient-codex-home-forbidden;local-fixed-nonreparse-disjoint') {
        throw 'Pinned Codex home canonical/storage contract changed.'
    }
    $defaultPath = [IO.Path]::Combine([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile), '.codex')
    $defaultCanonical = Get-FinalDirectoryPath -Path $defaultPath
    if ($canonical -ine $defaultCanonical) { throw 'Pinned Codex home is not the OS user-profile default.' }
    if ((Get-NormalizedPath -Path ([string]$env:CODEX_HOME)) -ine $path) {
        throw 'Worker CODEX_HOME does not match its pinned metadata contract.'
    }
    foreach ($boundary in @(
        [string]$Job.repo_path, [string]$Job.git_directory, [string]$Job.git_common_directory,
        [string]$Job.output_directory
    ) + @(Get-LocalFixedTempRoots)) {
        if (Test-PathsOverlap -First $path -Second (Get-NormalizedPath -Path $boundary)) {
            throw 'Pinned Codex home overlaps a repository, Git admin, evidence, or temp boundary.'
        }
        if (Test-Path -LiteralPath $boundary -PathType Container) {
            if (Test-PathsOverlap -First $canonical -Second (Get-FinalDirectoryPath -Path $boundary)) {
                throw 'Pinned Codex home physically overlaps a protected boundary.'
            }
        }
    }
}

function Get-WorkerCodexSignatureContract {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Label = 'Codex'
    )

    $systemPowerShell = Get-TrustedSystemPowerShellContract
    return (Invoke-WorkerAuthenticodeCapture -PowerShellPath ([string]$systemPowerShell.path) `
        -WorkingDirectory ([string]$systemPowerShell.working_directory) -TargetPath $Path -Label $Label)
}

function Assert-JobContract {
    param([Parameter(Mandatory = $true)][psobject]$Job)

    foreach ($property in @(
        'metadata_schema_version', 'job_id', 'repo_path', 'prompt_path', 'prompt_length_bytes', 'prompt_max_bytes',
        'prompt_sha256', 'prompt_encoding', 'prompt_utf8_bom', 'prompt_canonical_path',
        'prompt_volume_serial', 'prompt_file_id', 'prompt_link_count', 'prompt_contract',
        'codex_path', 'codex_arguments', 'codex_disabled_features', 'codex_web_search_override', 'codex_feature_preflight', 'codex_optional_surface_contract',
        'stdout_path', 'stderr_path', 'metadata_path',
        'codex_canonical_path', 'codex_working_directory', 'codex_sha256', 'codex_authenticode_status',
        'codex_signer_subject', 'codex_signer_thumbprint', 'codex_product_version',
        'codex_home_path', 'codex_home_canonical_path', 'codex_home_contract', 'codex_version',
        'codex_supported_version_contract', 'codex_model_provider_override', 'codex_sandbox_contract', 'auth_channel', 'auth_identity_contract',
        'codex_api_key_environment_approved', 'child_executable_path', 'child_executable_pathext', 'child_no_default_current_directory',
        'child_powershell_module_path', 'codex_shell_psmodulepath_override',
        'output_directory', 'evidence_boundary', 'storage_contract', 'filesystem_read_boundary',
        'windows_account_read_exposure_approved', 'filesystem_read_authority_contract', 'network_environment_contract',
        'shell_environment_contract', 'git_environment_contract', 'preflight_capture_contract',
        'codex_configuration_contract', 'stdout_max_bytes', 'stderr_max_bytes', 'evidence_stream_contract',
        'stdout_bytes_captured', 'stderr_bytes_captured', 'stdout_output_limit_exceeded',
        'stderr_output_limit_exceeded', 'output_limit_exceeded',
        'repo_canonical_path', 'git_directory', 'git_directory_canonical_path',
        'git_common_directory', 'git_common_directory_canonical_path',
        'git_marker_path', 'git_marker_kind', 'git_marker_canonical_path', 'git_marker_length_bytes', 'git_marker_sha256',
        'git_commondir_marker_path', 'git_commondir_marker_kind', 'git_commondir_marker_canonical_path',
        'git_commondir_marker_length_bytes', 'git_commondir_marker_sha256',
        'git_executable_path', 'git_executable_canonical_path', 'git_executable_working_directory', 'git_executable_sha256',
        'git_authenticode_status', 'git_signer_subject', 'git_signer_thumbprint', 'git_product_version',
        'git_config_path', 'git_config_canonical_path', 'git_config_volume_serial', 'git_config_file_id',
        'git_config_link_count', 'git_config_length_bytes', 'git_config_sha256', 'git_config_contract',
        'start_script_path', 'start_script_canonical_path', 'start_script_volume_serial', 'start_script_file_id',
        'start_script_link_count', 'start_script_length_bytes', 'start_script_sha256',
        'worker_script_path', 'worker_script_canonical_path', 'worker_script_volume_serial', 'worker_script_file_id',
        'worker_script_link_count', 'worker_script_length_bytes', 'worker_script_sha256', 'script_integrity_contract',
        'worker_host_path', 'worker_working_directory', 'worker_host_sha256', 'entry_powershell_contract',
        'worker_host_signer_subject', 'worker_host_signer_thumbprint',
        'output_canonical_path', 'path_canonicalization',
        'approval_policy', 'model', 'reasoning_effort', 'sandbox', 'timeout_seconds', 'state',
        'worker_recovery_left_live_launcher'
    )) {
        if ($null -eq $Job.PSObject.Properties[$property]) {
            throw "Metadata is missing required property: $property"
        }
    }
    if ([int]$Job.metadata_schema_version -ne 3) {
        throw 'Metadata schema version is unsupported.'
    }
    if ([string]$Job.state -cne 'validating' -or [bool]$Job.worker_recovery_left_live_launcher) {
        throw 'Worker prelaunch metadata state is unsupported.'
    }
    if ([string]$Job.approval_policy -cne 'never') {
        throw 'Recorded approval policy must be never.'
    }
    if ([string]$Job.sandbox -notin @('read-only', 'workspace-write')) {
        throw 'Recorded sandbox mode is unsupported.'
    }
    if ([string]$Job.reasoning_effort -notin @('low', 'medium', 'high', 'xhigh')) {
        throw 'Recorded reasoning effort is unsupported.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Job.model) -or
        [string]$Job.model -notmatch '^[A-Za-z0-9._-]+$') {
        throw 'Recorded model name is unsupported.'
    }
    foreach ($pathProperty in @(
        'repo_path', 'prompt_path', 'codex_path', 'stdout_path', 'stderr_path', 'metadata_path',
        'output_directory', 'repo_canonical_path', 'prompt_canonical_path', 'codex_canonical_path',
        'codex_home_path', 'codex_home_canonical_path',
        'output_canonical_path', 'git_directory', 'git_directory_canonical_path',
        'git_common_directory', 'git_common_directory_canonical_path',
        'git_marker_path', 'git_commondir_marker_path', 'codex_working_directory',
        'git_executable_path', 'git_executable_canonical_path', 'git_executable_working_directory',
        'git_config_path', 'git_config_canonical_path',
        'worker_host_path', 'worker_working_directory', 'child_powershell_module_path'
    )) {
        $value = [string]$Job.$pathProperty
        Assert-LocalFixedDrivePath -Path $value -Label "Metadata $pathProperty"
        $null = Assert-NoReparsePathComponents -Path $value -Label "Metadata $pathProperty" -AllowMissingTail
    }
    foreach ($optionalCanonical in @([string]$Job.git_marker_canonical_path, [string]$Job.git_commondir_marker_canonical_path)) {
        if (-not [string]::IsNullOrWhiteSpace($optionalCanonical)) {
            Assert-LocalFixedDrivePath -Path $optionalCanonical -Label 'Metadata Git marker canonical path'
        }
    }
    if (([IO.Path]::GetFullPath([string]$Job.metadata_path)) -ine ([IO.Path]::GetFullPath($MetadataPath))) {
        throw 'MetadataPath does not match the path recorded in the job.'
    }
    $outputDirectory = Get-NormalizedPath -Path ([string]$Job.output_directory)
    if ([string]$Job.evidence_boundary -ne 'local-fixed-disjoint-from-repo-git-admin-temp-and-reparse-ancestors') {
        throw 'Metadata has an unsupported evidence boundary.'
    }
    if ([string]$Job.storage_contract -ne 'local-ready-fixed-drives-only') {
        throw 'Metadata has an unsupported storage contract.'
    }
    if ([string]$Job.entry_powershell_contract -cne 'exact-os-system-WindowsPowerShell;pinned-PSHOME-modules;critical-first-resolved-builtin-cmdlets;fresh-NoProfile-NonInteractive-owner-entry') {
        throw 'Metadata has an unsupported entry PowerShell provenance contract.'
    }
    if ([string]$Job.filesystem_read_boundary -ne 'full-local-filesystem-on-Windows-legacy-sandbox' -or
        -not [bool]$Job.windows_account_read_exposure_approved -or
        [string]$Job.filesystem_read_authority_contract -ne 'explicit-owner-approval-required-before-worker-launch') {
        throw 'Metadata lacks explicit approval for the Windows full-account filesystem-read boundary.'
    }
    if ([string]$Job.network_environment_contract -ne 'fail-closed-known-egress-and-auth-overrides;positive-allowlist-child-environment;secret-shaped-ambient-fail-closed;rust-overrides-denied') {
        throw 'Metadata has an unsupported network environment contract.'
    }
    if ([string]$Job.shell_environment_contract -ne 'positive-core-process-environment;pinned-signed-git-path;no-current-directory-resolution;exe-only-pathext;pinned-system-powershell-modules;shell-inherit-core;login-shell-disabled;profile-disabled;default-secret-excludes-enabled;codex-api-key-explicitly-excluded' -or
        [string]$Job.git_environment_contract -ne 'no-system-or-global-config;no-terminal-prompt;gcm-noninteractive;local-config-bounded-safe-allowlist-and-locked' -or
        [string]$Job.preflight_capture_contract -ne 'bounded-1048576-bytes-per-stream;overflow-fail-closed') {
        throw 'Metadata has an unsupported child environment or preflight capture contract.'
    }
    $expectedChildPath = Get-TrustedCoreChildPath -AdditionalDirectories @([string]$Job.git_executable_working_directory)
    $expectedChildPowerShellModulePath = Get-FinalDirectoryPath -Path $entryTrustedModuleRoot
    $escapedChildPowerShellModulePath = $expectedChildPowerShellModulePath.Replace('\', '\\').Replace('"', '\"')
    $expectedShellPSModulePathOverride = 'shell_environment_policy.set.PSModulePath="' + $escapedChildPowerShellModulePath + '"'
    if ([string]$Job.child_executable_path -cne $expectedChildPath -or
        [string]$Job.child_executable_pathext -cne '.EXE' -or
        [string]$Job.child_no_default_current_directory -cne '1' -or
        [string]$Job.child_powershell_module_path -ine $expectedChildPowerShellModulePath -or
        [string]$Job.codex_shell_psmodulepath_override -cne $expectedShellPSModulePathOverride) {
        throw 'Metadata has an unsupported child executable search path contract.'
    }
    $expectedCodexSandboxContract = if ([string]$Job.sandbox -ceq 'read-only') {
        'read-only;workspace-write-network-and-temp-overrides-not-applicable'
    } else {
        'workspace-write;network-and-temp-roots-disabled'
    }
    if ([string]$Job.auth_identity_contract -cne 'auth-mode-only;owner-must-independently-confirm-account-and-billing-identity' -or
        [string]$Job.codex_version -cne $script:CodexJobSupportedVersion -or
        [string]$Job.codex_supported_version_contract -cne 'exact-codex-cli-0.147.0' -or
        [string]$Job.codex_model_provider_override -cne $script:CodexJobModelProviderOverride -or
        [string]$Job.codex_sandbox_contract -cne $expectedCodexSandboxContract -or
        [string]$Job.codex_configuration_contract -ne 'strict-config;openai-provider;ignore-user-config;ignore-user-and-project-rules;project-config-and-hooks-absent;codex-home-config-and-instructions-absent;linked-worktrees-forbidden;web-search-disabled;skill-instructions-disabled;workspace-write-network-and-temp-roots-disabled-when-applicable;optional-surfaces-disabled-and-preflighted') {
        throw 'Metadata has an unsupported Codex configuration contract.'
    }
    if ([string]$Job.codex_web_search_override -cne $script:CodexJobWebSearchOverride -or
        [string]$Job.codex_feature_preflight -cne 'passed-bounded-features-list-after-owner-authorization' -or
        [string]$Job.codex_optional_surface_contract -cne 'fixed-disable-list;actual-only-bounded-features-list-after-owner-authorization;web-search-and-skill-instructions-disabled;no-app-plugin-memory-hook-mcp-browser-multi-agent-unified-exec-or-shell-snapshot-surfaces') {
        throw 'Metadata has an unsupported optional surface contract.'
    }
    $recordedDisabledFeatures = @($Job.codex_disabled_features | ForEach-Object { [string]$_ })
    if ($recordedDisabledFeatures.Count -ne $script:CodexJobDisabledFeatures.Count) {
        throw 'Metadata disabled feature count is unsupported.'
    }
    for ($featureIndex = 0; $featureIndex -lt $recordedDisabledFeatures.Count; $featureIndex++) {
        if ([string]$recordedDisabledFeatures[$featureIndex] -cne [string]$script:CodexJobDisabledFeatures[$featureIndex]) {
            throw "Metadata disabled feature differs at index $featureIndex."
        }
    }
    if ([string]$Job.git_marker_kind -ne 'directory') {
        throw 'Linked Git worktrees are forbidden for delegated Codex jobs.'
    }
    if ((Get-NormalizedPath -Path ([string]$Job.git_directory_canonical_path)) -ine
        (Get-NormalizedPath -Path ([string]$Job.git_common_directory_canonical_path))) {
        throw 'Split Git common directories are forbidden for delegated Codex jobs.'
    }
    $expectedGitConfigPath = Get-NormalizedPath -Path ([IO.Path]::Combine([string]$Job.git_directory, 'config'))
    if ((Get-NormalizedPath -Path ([string]$Job.git_config_path)) -ine $expectedGitConfigPath -or
        [string]$Job.git_config_contract -cne 'bounded-1048576-byte-strict-utf8;single-hard-link;safe-section-key-allowlist;no-includes-external-command-or-config-worktree' -or
        [uint32]$Job.git_config_link_count -ne 1 -or [long]$Job.git_config_length_bytes -le 0 -or
        [long]$Job.git_config_length_bytes -gt [long]$script:CodexJobGitConfigMaxBytes -or
        [string]$Job.git_config_sha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw 'Metadata has an unsupported direct Git config safety contract.'
    }
    if ([long]$Job.prompt_max_bytes -ne [long]$script:CodexJobPromptMaxBytes -or
        [long]$Job.prompt_length_bytes -le 0 -or
        [long]$Job.prompt_length_bytes -gt [long]$script:CodexJobPromptMaxBytes -or
        [uint32]$Job.prompt_link_count -ne 1 -or
        [string]$Job.prompt_contract -cne 'strict-utf8;single-hard-link;handle-identity-bound;max-8388608-bytes') {
        throw 'Metadata has an unsupported prompt identity or size contract.'
    }
    if ([long]$Job.stdout_max_bytes -ne [long]$script:CodexJobEvidenceStreamMaxBytes -or
        [long]$Job.stderr_max_bytes -ne [long]$script:CodexJobEvidenceStreamMaxBytes -or
        [string]$Job.evidence_stream_contract -cne 'bounded-67108864-bytes-per-stream;overflow-drained-and-job-failed') {
        throw 'Metadata has an unsupported evidence stream size contract.'
    }
    if ([long]$Job.stdout_bytes_captured -ne 0 -or [long]$Job.stderr_bytes_captured -ne 0 -or
        [bool]$Job.stdout_output_limit_exceeded -or [bool]$Job.stderr_output_limit_exceeded -or
        [bool]$Job.output_limit_exceeded) {
        throw 'Starting metadata contains unexpected evidence bytes or overflow state.'
    }
    Assert-NoUntrustedProjectCodexLayer -RepositoryPath ([string]$Job.repo_path)
    Assert-RecordedCodexHomeContract -Job $Job
    Assert-NoCodexHomeDelegationLayer -CodexHomePath ([string]$Job.codex_home_path)
    if ([string]$env:NoDefaultCurrentDirectoryInExePath -cne '1' -or
        (Get-FinalDirectoryPath -Path ([string]$env:PSModulePath)) -ine $expectedChildPowerShellModulePath -or
        [string]$env:GIT_CONFIG_NOSYSTEM -cne '1' -or
        [string]$env:GIT_CONFIG_GLOBAL -cne 'NUL' -or
        [string]$env:GIT_TERMINAL_PROMPT -cne '0' -or
        [string]$env:GCM_INTERACTIVE -cne 'Never') {
        throw 'Worker executable-resolution or Git configuration environment differs from metadata contract.'
    }
    if ([string]$Job.auth_channel -eq 'codex-api-key-environment') {
        if (-not [bool]$Job.codex_api_key_environment_approved -or [string]::IsNullOrWhiteSpace([string]$env:CODEX_API_KEY)) {
            throw 'Recorded CODEX_API_KEY auth channel is unavailable or lacks explicit approval.'
        }
    } elseif ([string]$Job.auth_channel -eq 'pinned-codex-home-login-status') {
        if ([bool]$Job.codex_api_key_environment_approved -or -not [string]::IsNullOrWhiteSpace([string]$env:CODEX_API_KEY)) {
            throw 'Unexpected CODEX_API_KEY changed the recorded auth channel.'
        }
    } else {
        throw 'Metadata has an unsupported authentication channel.'
    }
    foreach ($artifactPath in @([string]$Job.stdout_path, [string]$Job.stderr_path, [string]$Job.metadata_path)) {
        if ((Get-NormalizedPath -Path ([IO.Path]::GetDirectoryName($artifactPath))) -ine $outputDirectory) {
            throw 'Every job artifact must be directly inside the recorded evidence directory.'
        }
    }
    Assert-SafeEvidenceDirectory -Path $outputDirectory -RepositoryPath ([string]$Job.repo_path) `
        -AdditionalProtectedPaths @([string]$Job.git_directory, [string]$Job.git_common_directory)
    Assert-RecordedScriptTrust -Job $Job
    if ([string]$Job.path_canonicalization -ne 'GetFinalPathNameByHandleW') {
        throw 'Metadata has an unsupported path canonicalization contract.'
    }
    $currentRepoCanonical = Get-FinalDirectoryPath -Path ([string]$Job.repo_path)
    $currentOutputCanonical = Get-FinalDirectoryPath -Path $outputDirectory
    $currentPromptCanonical = Get-FinalFilePath -Path ([string]$Job.prompt_path)
    $currentCodexCanonical = Get-FinalFilePath -Path ([string]$Job.codex_path)
    Assert-NoReparseDirectoryAncestors -Path ([string]$Job.git_directory) -Label 'Git directory'
    Assert-NoReparseDirectoryAncestors -Path ([string]$Job.git_common_directory) -Label 'Git common directory'
    $currentGitDirectoryCanonical = Get-FinalDirectoryPath -Path ([string]$Job.git_directory)
    $currentGitCommonDirectoryCanonical = Get-FinalDirectoryPath -Path ([string]$Job.git_common_directory)
    if ((Get-NormalizedPath -Path ([string]$Job.repo_canonical_path)) -ine $currentRepoCanonical) {
        throw 'Canonical repository path changed after job creation.'
    }
    if ((Get-NormalizedPath -Path ([string]$Job.output_canonical_path)) -ine $currentOutputCanonical) {
        throw 'Canonical evidence path changed after job creation.'
    }
    if ((Get-NormalizedPath -Path ([string]$Job.prompt_canonical_path)) -ine $currentPromptCanonical) {
        throw 'Canonical prompt path changed after job creation.'
    }
    if ((Get-NormalizedPath -Path ([string]$Job.codex_canonical_path)) -ine $currentCodexCanonical) {
        throw 'Canonical Codex path changed after job creation.'
    }
    if ((Get-NormalizedPath -Path ([string]$Job.git_directory_canonical_path)) -ine $currentGitDirectoryCanonical) {
        throw 'Canonical Git directory changed after job creation.'
    }
    if ((Get-NormalizedPath -Path ([string]$Job.git_common_directory_canonical_path)) -ine $currentGitCommonDirectoryCanonical) {
        throw 'Canonical Git common directory changed after job creation.'
    }
    Assert-GitBindingUnchanged -Job $Job
    Assert-SafeGitConfigContractCurrent -Job $Job
    Assert-RecordedLauncherTrust -Path ([string]$Job.git_executable_path) `
        -CanonicalPath ([string]$Job.git_executable_canonical_path) `
        -WorkingDirectory ([string]$Job.git_executable_working_directory) `
        -ExpectedSha256 ([string]$Job.git_executable_sha256) `
        -ProtectedDirectories @([string]$Job.repo_path, [string]$Job.git_directory, [string]$Job.git_common_directory) `
        -EvidenceDirectory $outputDirectory -Label 'Git executable'
    $gitSignature = Get-WorkerCodexSignatureContract -Path ([string]$Job.git_executable_path) -Label 'Git'
    if ([string]$gitSignature.status -ne 'Valid' -or [string]$Job.git_authenticode_status -ne 'Valid' -or
        [string]$gitSignature.simple_name -cne 'Johannes Schindelin' -or
        [string]$gitSignature.subject -notmatch '(?:^|, )O=Johannes Schindelin(?:,|$)' -or
        [string]$gitSignature.subject -cne [string]$Job.git_signer_subject -or
        [string]$gitSignature.thumbprint -ine [string]$Job.git_signer_thumbprint -or
        [string]$gitSignature.product_version -cne [string]$Job.git_product_version) {
        throw 'Git Authenticode publisher or product contract changed.'
    }
    Assert-RecordedLauncherTrust -Path ([string]$Job.codex_path) `
        -CanonicalPath ([string]$Job.codex_canonical_path) `
        -WorkingDirectory ([string]$Job.codex_working_directory) `
        -ExpectedSha256 ([string]$Job.codex_sha256) `
        -ProtectedDirectories @([string]$Job.repo_path, [string]$Job.git_directory, [string]$Job.git_common_directory) `
        -EvidenceDirectory $outputDirectory -Label 'Codex executable'
    $signature = Get-WorkerCodexSignatureContract -Path ([string]$Job.codex_path)
    if ([string]$signature.status -ne 'Valid' -or [string]$Job.codex_authenticode_status -ne 'Valid' -or
        [string]$signature.simple_name -cne 'OpenAI OpCo, LLC' -or
        [string]$signature.subject -notmatch '(?:^|, )O="OpenAI OpCo, LLC"(?:,|$)' -or
        [string]$signature.subject -cne [string]$Job.codex_signer_subject -or
        [string]$signature.thumbprint -ine [string]$Job.codex_signer_thumbprint -or
        [string]$signature.product_version -cne [string]$Job.codex_product_version) {
        throw 'Codex Authenticode signer or product contract changed.'
    }
    if ((Get-NormalizedPath -Path ([string]$Job.worker_working_directory)) -ine (Get-NormalizedPath -Path ([Environment]::CurrentDirectory))) {
        throw 'Worker OS working directory does not match its trusted metadata contract.'
    }
    $currentWorkerHostContract = Get-TrustedSystemPowerShellContract
    $currentWorkerHost = Get-FinalFilePath -Path ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
    if ($currentWorkerHost -ine (Get-NormalizedPath -Path ([string]$Job.worker_host_path)) -or
        [string]$currentWorkerHostContract.path -ine $currentWorkerHost -or
        [string]$currentWorkerHostContract.sha256 -ine [string]$Job.worker_host_sha256 -or
        [string]$currentWorkerHostContract.signer_subject -cne [string]$Job.worker_host_signer_subject -or
        [string]$currentWorkerHostContract.signer_thumbprint -ine [string]$Job.worker_host_signer_thumbprint) {
        throw 'Worker executable does not match its trusted metadata contract.'
    }
    if (-not (Test-Path -LiteralPath ([string]$Job.repo_path) -PathType Container)) {
        throw 'Recorded repository path no longer exists.'
    }
    if (-not (Test-Path -LiteralPath ([string]$Job.prompt_path) -PathType Leaf)) {
        throw 'Recorded prompt path no longer exists.'
    }
    if (-not (Test-Path -LiteralPath ([string]$Job.codex_path) -PathType Leaf)) {
        throw 'Recorded Codex launcher no longer exists.'
    }
    if ([int]$Job.timeout_seconds -lt 10 -or [int]$Job.timeout_seconds -gt 86400) {
        throw 'Recorded timeout is outside the supported range.'
    }
}

$metadata = $null
$codexProcess = $null
$codexStarted = $false
$stdoutStream = $null
$stderrStream = $null
$stdoutCaptureStream = $null
$stderrCaptureStream = $null
$gitConfigStream = $null
$promptStream = $null
$standardInputStream = $null
$standardOutputStream = $null
$standardErrorStream = $null
$inputTask = $null
$outputTask = $null
$errorTask = $null
$inputClosed = $false
$outputTaskObserved = $false
$errorTaskObserved = $false
$outputFallback = $false
$errorFallback = $false
$transportError = $false
$transportErrorPublished = $false
$outputLimitExceeded = $false
$timeoutExceeded = $false
$exitCode = $null

try {
    Assert-LocalFixedDrivePath -Path $MetadataPath -Label 'MetadataPath'
    $MetadataPath = Get-NormalizedPath -Path $MetadataPath
    $null = Assert-NoReparsePathComponents -Path $MetadataPath -Label 'MetadataPath'
    if (-not (Test-Path -LiteralPath $MetadataPath -PathType Leaf)) {
        throw "Metadata file does not exist: $MetadataPath"
    }

    $metadata = Read-JobMetadata -Path $MetadataPath
    if ([int]$metadata.metadata_schema_version -ne 3 -or [string]$metadata.state -cne 'starting') {
        throw 'Worker received metadata in an unsupported initial state.'
    }
    $workerProcess = [Diagnostics.Process]::GetCurrentProcess()
    Set-ObjectProperty -Object $metadata -Name 'worker_pid' -Value $PID
    Set-ObjectProperty -Object $metadata -Name 'worker_started_at_utc' -Value ($workerProcess.StartTime.ToUniversalTime().ToString('o'))
    Set-ObjectProperty -Object $metadata -Name 'worker_process_path' -Value $workerProcess.MainModule.FileName
    Set-ObjectProperty -Object $metadata -Name 'worker_exit_code' -Value $null
    Set-ObjectProperty -Object $metadata -Name 'state' -Value 'validating'
    Set-ObjectProperty -Object $metadata -Name 'ok' -Value $true
    Write-JobMetadata -Path $MetadataPath -Value $metadata
    Assert-JobContract -Job $metadata
    # Keep repository-local Git configuration immutable for the complete Codex
    # lifetime while still allowing Git/Codex read access.
    $gitConfigStream = Open-ValidatedGitConfigStream -Job $metadata
    $promptStream = Open-ValidatedPromptStream -Job $metadata

    $stdoutStream = [IO.File]::Open(
        [string]$metadata.stdout_path,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::Read
    )
    $stderrStream = [IO.File]::Open(
        [string]$metadata.stderr_path,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::Read
    )
    $stdoutCaptureStream = New-Object CodexJobWorkerBoundedWriteStream -ArgumentList @(
        $stdoutStream, ([long]$metadata.stdout_max_bytes)
    )
    $stderrCaptureStream = New-Object CodexJobWorkerBoundedWriteStream -ArgumentList @(
        $stderrStream, ([long]$metadata.stderr_max_bytes)
    )
    $startInfo = New-CodexStartInfo -Job $metadata
    Assert-NoUntrustedProjectCodexLayer -RepositoryPath ([string]$metadata.repo_path)
    Assert-RecordedCodexHomeContract -Job $metadata
    Assert-NoCodexHomeDelegationLayer -CodexHomePath ([string]$metadata.codex_home_path)
    Assert-RecordedScriptTrust -Job $metadata
    if ((Get-Sha256Hex -Path ([string]$metadata.codex_path)) -ine [string]$metadata.codex_sha256) {
        throw 'Codex executable changed immediately before Process.Start.'
    }
    $codexProcess = New-Object Diagnostics.Process
    $codexProcess.StartInfo = $startInfo
    if (-not $codexProcess.Start()) {
        throw 'Process.Start returned false for the Codex launcher.'
    }
    $codexStarted = $true

    $codexProcess.Refresh()
    $codexProcessPath = $startInfo.FileName
    try {
        $codexProcessPath = $codexProcess.MainModule.FileName
    } catch {
        # StartInfo.FileName remains an auditable fallback.
    }
    $launcherStartedAtUtc = $codexProcess.StartTime.ToUniversalTime().ToString('o')
    Set-ObjectProperty -Object $metadata -Name 'pid' -Value $codexProcess.Id
    Set-ObjectProperty -Object $metadata -Name 'started_at_utc' -Value $launcherStartedAtUtc
    Set-ObjectProperty -Object $metadata -Name 'codex_pid' -Value $codexProcess.Id
    Set-ObjectProperty -Object $metadata -Name 'codex_started_at_utc' -Value $launcherStartedAtUtc
    Set-ObjectProperty -Object $metadata -Name 'codex_process_path' -Value $codexProcessPath
    Set-ObjectProperty -Object $metadata -Name 'launcher_pid' -Value $codexProcess.Id
    Set-ObjectProperty -Object $metadata -Name 'launcher_started_at_utc' -Value $launcherStartedAtUtc
    Set-ObjectProperty -Object $metadata -Name 'launcher_process_path' -Value $codexProcessPath

    # Start every pipe transfer before writing running metadata. If metadata
    # publication fails, recovery can still finish the authorized prompt and EOF.
    $standardInputStream = $codexProcess.StandardInput.BaseStream
    $standardOutputStream = $codexProcess.StandardOutput.BaseStream
    $standardErrorStream = $codexProcess.StandardError.BaseStream
    $inputTask = $promptStream.CopyToAsync($standardInputStream)
    $outputTask = $standardOutputStream.CopyToAsync($stdoutCaptureStream)
    $errorTask = $standardErrorStream.CopyToAsync($stderrCaptureStream)

    Set-ObjectProperty -Object $metadata -Name 'ok' -Value $true
    Set-ObjectProperty -Object $metadata -Name 'state' -Value 'running'
    Write-JobMetadata -Path $MetadataPath -Value $metadata

    $deadline = [DateTime]::UtcNow.AddSeconds([int]$metadata.timeout_seconds)
    while (-not $codexProcess.WaitForExit(100)) {
        if (-not $inputClosed -and $null -ne $inputTask -and $inputTask.IsCompleted) {
            try {
                $inputTask.GetAwaiter().GetResult()
                $standardInputStream.Flush()
            } catch {
                $transportError = $true
                Set-ObjectProperty -Object $metadata -Name 'stdin_copy_error' -Value $_.Exception.Message
            } finally {
                try { $codexProcess.StandardInput.Close() } catch { }
                $inputClosed = $true
            }
        }

        if ($null -ne $outputTask -and -not $outputTaskObserved -and $outputTask.IsCompleted) {
            try {
                $outputTask.GetAwaiter().GetResult()
                $outputTaskObserved = $true
            } catch {
                $transportError = $true
                Set-ObjectProperty -Object $metadata -Name 'stdout_copy_error' -Value $_.Exception.Message
                if (-not $outputFallback) {
                    $outputFallback = $true
                    $outputTask = $standardOutputStream.CopyToAsync([IO.Stream]::Null)
                    $outputTaskObserved = $false
                } else {
                    $outputTask = $null
                    $outputTaskObserved = $true
                    try { $standardOutputStream.Dispose() } catch { }
                }
            }
        }
        if ($null -ne $errorTask -and -not $errorTaskObserved -and $errorTask.IsCompleted) {
            try {
                $errorTask.GetAwaiter().GetResult()
                $errorTaskObserved = $true
            } catch {
                $transportError = $true
                Set-ObjectProperty -Object $metadata -Name 'stderr_copy_error' -Value $_.Exception.Message
                if (-not $errorFallback) {
                    $errorFallback = $true
                    $errorTask = $standardErrorStream.CopyToAsync([IO.Stream]::Null)
                    $errorTaskObserved = $false
                } else {
                    $errorTask = $null
                    $errorTaskObserved = $true
                    try { $standardErrorStream.Dispose() } catch { }
                }
            }
        }
        $limitStateChanged = $false
        if ($null -ne $stdoutCaptureStream -and $stdoutCaptureStream.LimitExceeded -and
            -not [bool]$metadata.stdout_output_limit_exceeded) {
            Set-ObjectProperty -Object $metadata -Name 'stdout_output_limit_exceeded' -Value $true
            $limitStateChanged = $true
        }
        if ($null -ne $stderrCaptureStream -and $stderrCaptureStream.LimitExceeded -and
            -not [bool]$metadata.stderr_output_limit_exceeded) {
            Set-ObjectProperty -Object $metadata -Name 'stderr_output_limit_exceeded' -Value $true
            $limitStateChanged = $true
        }
        if ($limitStateChanged) {
            $outputLimitExceeded = $true
            $transportError = $true
            Set-ObjectProperty -Object $metadata -Name 'ok' -Value $false
            Set-ObjectProperty -Object $metadata -Name 'output_limit_exceeded' -Value $true
            Set-ObjectProperty -Object $metadata -Name 'transport_error' -Value $true
            Set-ObjectProperty -Object $metadata -Name 'stdout_bytes_captured' -Value ([long]$stdoutCaptureStream.BytesWritten)
            Set-ObjectProperty -Object $metadata -Name 'stderr_bytes_captured' -Value ([long]$stderrCaptureStream.BytesWritten)
            Write-JobMetadata -Path $MetadataPath -Value $metadata
        }
        if ($transportError -and -not $transportErrorPublished) {
            $transportErrorPublished = $true
            Set-ObjectProperty -Object $metadata -Name 'ok' -Value $false
            Set-ObjectProperty -Object $metadata -Name 'transport_error' -Value $true
            Write-JobMetadata -Path $MetadataPath -Value $metadata
        }

        if (-not $timeoutExceeded -and [DateTime]::UtcNow -ge $deadline) {
            $timeoutExceeded = $true
            Set-ObjectProperty -Object $metadata -Name 'ok' -Value $false
            Set-ObjectProperty -Object $metadata -Name 'state' -Value 'timed_out_running'
            Set-ObjectProperty -Object $metadata -Name 'timeout_exceeded' -Value $true
            Set-ObjectProperty -Object $metadata -Name 'timed_out_at_utc' -Value ([DateTime]::UtcNow.ToString('o'))
            Write-JobMetadata -Path $MetadataPath -Value $metadata
        }
    }

    $codexProcess.WaitForExit()
    $codexProcess.Refresh()
    $exitCode = $codexProcess.ExitCode
    if (-not $inputClosed) {
        try {
            if ($null -ne $inputTask -and -not $inputTask.IsCompleted) {
                try { $null = $inputTask.Wait(2000) } catch { }
            }
            if ($null -ne $inputTask -and $inputTask.IsCompleted) {
                $inputTask.GetAwaiter().GetResult()
            } elseif ($null -ne $inputTask) {
                throw 'stdin copy did not complete within 2 seconds after launcher exit.'
            }
            if ($null -ne $standardInputStream) { $standardInputStream.Flush() }
        } catch {
            $transportError = $true
            Set-ObjectProperty -Object $metadata -Name 'stdin_copy_error' -Value $_.Exception.Message
        } finally {
            try { $codexProcess.StandardInput.Close() } catch { }
            $inputClosed = $true
        }
    }

    if ($null -ne $outputTask) {
        try {
            if (-not $outputTask.IsCompleted) {
                try { $null = $outputTask.Wait(2000) } catch { }
            }
            if ($outputTask.IsCompleted) {
                $outputTask.GetAwaiter().GetResult()
            } else {
                throw 'stdout drain did not complete within 2 seconds after launcher exit.'
            }
        } catch {
            $transportError = $true
            Set-ObjectProperty -Object $metadata -Name 'stdout_copy_error' -Value $_.Exception.Message
            if (-not $outputTask.IsCompleted) {
                try { $standardOutputStream.Dispose() } catch { }
            } elseif (-not $outputFallback) {
                try {
                    $finalOutputDrain = $standardOutputStream.CopyToAsync([IO.Stream]::Null)
                    if (-not $finalOutputDrain.IsCompleted) { try { $null = $finalOutputDrain.Wait(2000) } catch { } }
                    if ($finalOutputDrain.IsCompleted) { $finalOutputDrain.GetAwaiter().GetResult() }
                } catch { }
            }
            try { $standardOutputStream.Dispose() } catch { }
        }
    }
    if ($null -ne $errorTask) {
        try {
            if (-not $errorTask.IsCompleted) {
                try { $null = $errorTask.Wait(2000) } catch { }
            }
            if ($errorTask.IsCompleted) {
                $errorTask.GetAwaiter().GetResult()
            } else {
                throw 'stderr drain did not complete within 2 seconds after launcher exit.'
            }
        } catch {
            $transportError = $true
            Set-ObjectProperty -Object $metadata -Name 'stderr_copy_error' -Value $_.Exception.Message
            if (-not $errorTask.IsCompleted) {
                try { $standardErrorStream.Dispose() } catch { }
            } elseif (-not $errorFallback) {
                try {
                    $finalErrorDrain = $standardErrorStream.CopyToAsync([IO.Stream]::Null)
                    if (-not $finalErrorDrain.IsCompleted) { try { $null = $finalErrorDrain.Wait(2000) } catch { } }
                    if ($finalErrorDrain.IsCompleted) { $finalErrorDrain.GetAwaiter().GetResult() }
                } catch { }
            }
            try { $standardErrorStream.Dispose() } catch { }
        }
    }
    if ($null -ne $stdoutStream) { try { $stdoutStream.Flush() } catch { $transportError = $true } }
    if ($null -ne $stderrStream) { try { $stderrStream.Flush() } catch { $transportError = $true } }

    if (($null -ne $stdoutCaptureStream -and $stdoutCaptureStream.LimitExceeded) -or
        ($null -ne $stderrCaptureStream -and $stderrCaptureStream.LimitExceeded)) {
        $outputLimitExceeded = $true
        $transportError = $true
        Set-ObjectProperty -Object $metadata -Name 'output_limit_exceeded' -Value $true
        Set-ObjectProperty -Object $metadata -Name 'stdout_output_limit_exceeded' -Value `
            ([bool]($null -ne $stdoutCaptureStream -and $stdoutCaptureStream.LimitExceeded))
        Set-ObjectProperty -Object $metadata -Name 'stderr_output_limit_exceeded' -Value `
            ([bool]($null -ne $stderrCaptureStream -and $stderrCaptureStream.LimitExceeded))
    }
    if ($null -ne $stdoutCaptureStream) {
        Set-ObjectProperty -Object $metadata -Name 'stdout_bytes_captured' -Value ([long]$stdoutCaptureStream.BytesWritten)
    }
    if ($null -ne $stderrCaptureStream) {
        Set-ObjectProperty -Object $metadata -Name 'stderr_bytes_captured' -Value ([long]$stderrCaptureStream.BytesWritten)
    }

    Set-ObjectProperty -Object $metadata -Name 'exit_code' -Value $exitCode
    Set-ObjectProperty -Object $metadata -Name 'completed_at_utc' -Value ([DateTime]::UtcNow.ToString('o'))
    Set-ObjectProperty -Object $metadata -Name 'worker_exit_code' -Value $(if ($timeoutExceeded -or $transportError -or $exitCode -ne 0) { 1 } else { 0 })
    if ($timeoutExceeded) {
        Set-ObjectProperty -Object $metadata -Name 'ok' -Value $false
        Set-ObjectProperty -Object $metadata -Name 'state' -Value 'timed_out'
    } elseif ($exitCode -eq 0 -and -not $transportError) {
        Set-ObjectProperty -Object $metadata -Name 'ok' -Value $true
        Set-ObjectProperty -Object $metadata -Name 'state' -Value 'completed'
    } else {
        Set-ObjectProperty -Object $metadata -Name 'ok' -Value $false
        Set-ObjectProperty -Object $metadata -Name 'state' -Value 'failed'
    }
    Write-JobMetadata -Path $MetadataPath -Value $metadata
} catch {
    $workerError = $_.Exception.Message
    $recoveryLeftLiveLauncher = $false

    if ($codexStarted) {
        # Establish pipe readers first so the child cannot block on full stdout/stderr.
        try {
            if ($null -eq $standardOutputStream) { $standardOutputStream = $codexProcess.StandardOutput.BaseStream }
            if ($null -eq $outputTask -or $outputTask.IsFaulted -or $outputTask.IsCanceled) {
                if ($null -ne $outputTask) { try { $outputTask.GetAwaiter().GetResult() } catch { } }
                $outputTask = $standardOutputStream.CopyToAsync([IO.Stream]::Null)
                $outputFallback = $true
            }
        } catch {
            $workerError = '{0}; stdout recovery error: {1}' -f $workerError, $_.Exception.Message
        }
        try {
            if ($null -eq $standardErrorStream) { $standardErrorStream = $codexProcess.StandardError.BaseStream }
            if ($null -eq $errorTask -or $errorTask.IsFaulted -or $errorTask.IsCanceled) {
                if ($null -ne $errorTask) { try { $errorTask.GetAwaiter().GetResult() } catch { } }
                $errorTask = $standardErrorStream.CopyToAsync([IO.Stream]::Null)
                $errorFallback = $true
            }
        } catch {
            $workerError = '{0}; stderr recovery error: {1}' -f $workerError, $_.Exception.Message
        }

        # Complete the authorized prompt when possible, but always send EOF within
        # two seconds so `codex exec -` cannot deadlock on recovery.
        try {
            if ($null -eq $standardInputStream) { $standardInputStream = $codexProcess.StandardInput.BaseStream }
            if ($null -eq $inputTask -and $null -ne $promptStream) {
                $inputTask = $promptStream.CopyToAsync($standardInputStream)
            }
            if ($null -ne $inputTask -and -not $inputTask.IsCompleted) {
                try { $null = $inputTask.Wait(2000) } catch { }
            }
            if ($null -ne $inputTask -and $inputTask.IsCompleted) {
                try { $inputTask.GetAwaiter().GetResult() } catch {
                    $workerError = '{0}; stdin recovery copy error: {1}' -f $workerError, $_.Exception.Message
                }
            } elseif ($null -ne $inputTask) {
                $workerError = '{0}; stdin recovery copy exceeded 2 seconds' -f $workerError
            }
        } catch {
            $workerError = '{0}; stdin recovery setup error: {1}' -f $workerError, $_.Exception.Message
        } finally {
            try { $codexProcess.StandardInput.Close() } catch { }
            $inputClosed = $true
        }

        $recoveryDeadline = [DateTime]::UtcNow.AddSeconds(5)
        while (-not $codexProcess.WaitForExit(100) -and [DateTime]::UtcNow -lt $recoveryDeadline) {
            if ($null -ne $outputTask -and $outputTask.IsFaulted -and -not $outputFallback) {
                try { $outputTask.GetAwaiter().GetResult() } catch { }
                try {
                    $outputTask = $standardOutputStream.CopyToAsync([IO.Stream]::Null)
                    $outputFallback = $true
                } catch { }
            }
            if ($null -ne $errorTask -and $errorTask.IsFaulted -and -not $errorFallback) {
                try { $errorTask.GetAwaiter().GetResult() } catch { }
                try {
                    $errorTask = $standardErrorStream.CopyToAsync([IO.Stream]::Null)
                    $errorFallback = $true
                } catch { }
            }
        }

        if ($codexProcess.HasExited) {
            try {
                $codexProcess.WaitForExit()
                $codexProcess.Refresh()
                $exitCode = $codexProcess.ExitCode
                if ($null -ne $outputTask -and $outputTask.IsCompleted) { try { $outputTask.GetAwaiter().GetResult() } catch { } }
                if ($null -ne $errorTask -and $errorTask.IsCompleted) { try { $errorTask.GetAwaiter().GetResult() } catch { } }
            } catch {
                $workerError = '{0}; recovery completion error: {1}' -f $workerError, $_.Exception.Message
            }
        } else {
            $recoveryLeftLiveLauncher = $true
            $workerError = '{0}; launcher remained alive after bounded 5-second recovery; no process was killed' -f $workerError
        }
    }

    if ($null -ne $metadata) {
        try {
            Set-ObjectProperty -Object $metadata -Name 'ok' -Value $false
            Set-ObjectProperty -Object $metadata -Name 'error' -Value $workerError
            Set-ObjectProperty -Object $metadata -Name 'worker_exit_code' -Value 1
            if ($null -ne $stdoutCaptureStream) {
                Set-ObjectProperty -Object $metadata -Name 'stdout_bytes_captured' -Value ([long]$stdoutCaptureStream.BytesWritten)
                Set-ObjectProperty -Object $metadata -Name 'stdout_output_limit_exceeded' -Value ([bool]$stdoutCaptureStream.LimitExceeded)
            }
            if ($null -ne $stderrCaptureStream) {
                Set-ObjectProperty -Object $metadata -Name 'stderr_bytes_captured' -Value ([long]$stderrCaptureStream.BytesWritten)
                Set-ObjectProperty -Object $metadata -Name 'stderr_output_limit_exceeded' -Value ([bool]$stderrCaptureStream.LimitExceeded)
            }
            if (($null -ne $stdoutCaptureStream -and $stdoutCaptureStream.LimitExceeded) -or
                ($null -ne $stderrCaptureStream -and $stderrCaptureStream.LimitExceeded)) {
                Set-ObjectProperty -Object $metadata -Name 'output_limit_exceeded' -Value $true
                Set-ObjectProperty -Object $metadata -Name 'transport_error' -Value $true
            }
            if ($recoveryLeftLiveLauncher) {
                Set-ObjectProperty -Object $metadata -Name 'state' -Value 'timed_out_running'
                Set-ObjectProperty -Object $metadata -Name 'timeout_exceeded' -Value $true
                Set-ObjectProperty -Object $metadata -Name 'timed_out_at_utc' -Value ([DateTime]::UtcNow.ToString('o'))
                Set-ObjectProperty -Object $metadata -Name 'worker_recovery_left_live_launcher' -Value $true
                Set-ObjectProperty -Object $metadata -Name 'exit_code' -Value $null
                Set-ObjectProperty -Object $metadata -Name 'completed_at_utc' -Value $null
            } else {
                Set-ObjectProperty -Object $metadata -Name 'state' -Value 'failed'
                Set-ObjectProperty -Object $metadata -Name 'completed_at_utc' -Value ([DateTime]::UtcNow.ToString('o'))
                if ($null -ne $exitCode) {
                    Set-ObjectProperty -Object $metadata -Name 'exit_code' -Value $exitCode
                }
            }
            Write-JobMetadata -Path $MetadataPath -Value $metadata
        } catch {
            # The parent can detect an exited worker with stale metadata.
        }
    }
    exit 1
} finally {
    foreach ($stream in @(
        $gitConfigStream, $promptStream, $standardInputStream, $standardOutputStream, $standardErrorStream,
        $stdoutCaptureStream, $stderrCaptureStream, $stdoutStream, $stderrStream
    )) {
        if ($null -ne $stream) {
            try { $stream.Dispose() } catch { }
        }
    }
    if ($null -ne $codexProcess) {
        $codexProcess.Dispose()
    }
}

if ($timeoutExceeded -or $transportError -or ($null -ne $exitCode -and $exitCode -ne 0)) {
    exit 1
}
exit 0
} finally {
    [Environment]::SetEnvironmentVariable('PSModulePath', $script:CodexJobOriginalPSModulePath, 'Process')
}
