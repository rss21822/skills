[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoPath,

    [Parameter(Mandatory = $true)]
    [string]$PromptPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$CodexPath,

    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$Model = 'gpt-5.6',

    [ValidateSet('low', 'medium', 'high', 'xhigh')]
    [string]$ReasoningEffort = 'high',

    [ValidateSet('read-only', 'workspace-write')]
    [string]$Sandbox = 'workspace-write',

    [ValidateSet('never')]
    [string]$ApprovalPolicy = 'never',

    [switch]$AllowCodexApiKeyEnvironment,

    [switch]$AllowWindowsAccountReadExposure,

    [ValidateRange(10, 86400)]
    [int]$TimeoutSeconds = 3600,

    [switch]$Wait,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Microsoft.PowerShell.Core\Set-StrictMode -Version 2.0

$script:CodexJobOriginalPSModulePath = [Environment]::GetEnvironmentVariable('PSModulePath', 'Process')
$entryExpectedHost = [IO.Path]::Combine(
    [Environment]::SystemDirectory, 'WindowsPowerShell', 'v1.0', 'powershell.exe')
$entryCurrentHost = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
if ([IO.Path]::GetFullPath($entryCurrentHost) -ine [IO.Path]::GetFullPath($entryExpectedHost)) {
    throw "This security helper must run in the OS system Windows PowerShell host. expected=$entryExpectedHost actual=$entryCurrentHost"
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
        throw "This security helper must run in the OS system Windows PowerShell host. expected=$expectedHost actual=$currentHost"
    }
    $windowsDirectory = [IO.Directory]::GetParent([Environment]::SystemDirectory).FullName
    $gacRoot = [IO.Path]::GetFullPath([IO.Path]::Combine($windowsDirectory, 'Microsoft.Net', 'assembly', 'GAC_MSIL')).TrimEnd('\') + '\'
    $moduleRoot = [IO.Path]::GetFullPath([IO.Path]::Combine([IO.Path]::GetDirectoryName($expectedHost), 'Modules')).TrimEnd('\') + '\'

    $expectedModules = @{
        'Set-StrictMode' = 'Microsoft.PowerShell.Core'; 'Get-Command' = 'Microsoft.PowerShell.Core'
        'ForEach-Object' = 'Microsoft.PowerShell.Core'; 'Where-Object' = 'Microsoft.PowerShell.Core'; 'Out-Null' = 'Microsoft.PowerShell.Core'
        'Get-ChildItem' = 'Microsoft.PowerShell.Management'; 'Get-Content' = 'Microsoft.PowerShell.Management'
        'Get-Item' = 'Microsoft.PowerShell.Management'; 'Join-Path' = 'Microsoft.PowerShell.Management'
        'New-Item' = 'Microsoft.PowerShell.Management'; 'Remove-Item' = 'Microsoft.PowerShell.Management'
        'Resolve-Path' = 'Microsoft.PowerShell.Management'; 'Start-Process' = 'Microsoft.PowerShell.Management'
        'Test-Path' = 'Microsoft.PowerShell.Management'; 'Add-Member' = 'Microsoft.PowerShell.Utility'
        'Add-Type' = 'Microsoft.PowerShell.Utility'; 'ConvertFrom-Json' = 'Microsoft.PowerShell.Utility'
        'ConvertTo-Json' = 'Microsoft.PowerShell.Utility'; 'Get-Date' = 'Microsoft.PowerShell.Utility'
        'New-Object' = 'Microsoft.PowerShell.Utility'; 'Start-Sleep' = 'Microsoft.PowerShell.Utility'
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
        'Assert-GitBindingUnchanged', 'Assert-LocalFixedDrivePath', 'Assert-NoAmbientCodexHomeOverride',
        'Assert-NoAmbientEgressOverrides', 'Assert-NoAmbientSecretVariables', 'Assert-NoCodexHomeDelegationLayer',
        'Assert-NoReparseDirectoryAncestors', 'Assert-NoReparsePathComponents', 'Assert-NoUntrustedProjectCodexLayer',
        'Assert-SafeEvidenceDirectory', 'Assert-SafeGitConfigContractCurrent', 'Assert-SafeGitConfigHandleContract',
        'Assert-ScriptContractCurrent', 'Assert-ScriptDirectoryBoundary',
        'Get-BoundedAuthenticodeContract', 'Get-CanonicalPotentialDirectoryPath', 'Get-DeclaredGitAdminContract',
        'Get-EgressOverrideEnvironmentNames', 'Get-FinalDirectoryPath', 'Get-FinalExistingPath', 'Get-FinalFilePath',
        'Get-GitAdminPathContract', 'Get-GitBindingContract', 'Get-GitForWindowsSignatureContract',
        'Get-SafeGitConfigContract', 'Get-SafeGitConfigHandleContract',
        'Get-LocalFixedPathExecutableCandidates', 'Get-LocalFixedTempRoots', 'Get-NativeCodexCandidates',
        'Get-NormalizedPath', 'Get-OpenAICodexSignatureContract', 'Get-OpenFileHandleContract',
        'Get-OpenScriptHandleContract', 'Get-PromptIdentityContract', 'Get-ScriptFileContract', 'Get-Sha256Hex',
        'Get-TrustedChildTempDirectory', 'Get-TrustedCodexHomeContract', 'Get-TrustedCoreChildPath',
        'Get-TrustedLauncherContract', 'Get-TrustedSystemPowerShellContract', 'Get-TrustedWindowsDirectory',
        'Get-ValidatedPromptContract', 'Initialize-TrustedWindowsEnvironment', 'Invoke-NativeCapture',
        'Quote-NativeArgument', 'Read-JobMetadata', 'Read-StrictGitMarkerLine', 'Read-TrustedJobMetadata',
        'Remove-BlockedChildEnvironmentVariables', 'Resolve-DeclaredGitDirectory', 'Set-ObjectProperty',
        'Set-TrustedGitEnvironmentVariables', 'Test-CoreChildEnvironmentName', 'Test-PathsOverlap',
        'Test-PathWithin', 'Write-JobMetadata'
    )
    foreach ($name in $internalNames) {
        $ambient = @(Microsoft.PowerShell.Core\Get-Command -Name $name -ErrorAction SilentlyContinue)
        if ($ambient.Count -ne 0) { throw "Ambient command shadows an internal security helper: $name" }
    }
}

& ${function:Assert-TrustedEntryPowerShell}
$script:CodexJobOriginalProcessTempCandidates = @($env:TEMP, $env:TMP)
$script:CodexJobPromptMaxBytes = 8MB
$script:CodexJobEvidenceStreamMaxBytes = 64MB
$script:CodexJobPreflightStreamMaxBytes = 1MB
$script:CodexJobScriptMaxBytes = 4MB
$script:CodexJobGitConfigMaxBytes = 1MB
$script:CodexJobWorkerHandshakeSeconds = 120
$script:CodexJobShellInheritOverride = 'shell_environment_policy.inherit="core"'
$script:CodexJobShellDefaultExcludesOverride = 'shell_environment_policy.ignore_default_excludes=false'
$script:CodexJobShellExplicitExcludesOverride = 'shell_environment_policy.exclude=["CODEX_API_KEY","OPENAI_API_KEY","CODEX_ACCESS_TOKEN"]'
$script:CodexJobShellNoCurrentDirectoryOverride = 'shell_environment_policy.set.NoDefaultCurrentDirectoryInExePath="1"'
$script:CodexJobShellPathExtOverride = 'shell_environment_policy.set.PATHEXT=".EXE"'
$script:CodexJobAllowLoginShellOverride = 'allow_login_shell=false'
$script:CodexJobShellUseProfileOverride = 'shell_environment_policy.experimental_use_profile=false'
$script:CodexJobShellGitNoSystemConfigOverride = 'shell_environment_policy.set.GIT_CONFIG_NOSYSTEM="1"'
$script:CodexJobShellGitNoGlobalConfigOverride = 'shell_environment_policy.set.GIT_CONFIG_GLOBAL="NUL"'
$script:CodexJobShellGitNoPromptOverride = 'shell_environment_policy.set.GIT_TERMINAL_PROMPT="0"'
$script:CodexJobShellGitNoGcmInteractiveOverride = 'shell_environment_policy.set.GCM_INTERACTIVE="Never"'
$script:CodexJobSandboxNoNetworkOverride = 'sandbox_workspace_write.network_access=false'
$script:CodexJobSandboxNoTempOverride = 'sandbox_workspace_write.exclude_tmpdir_env_var=true'
$script:CodexJobSandboxNoSlashTempOverride = 'sandbox_workspace_write.exclude_slash_tmp=true'
$script:CodexJobModelProviderOverride = 'model_provider="openai"'
$script:CodexJobWebSearchOverride = 'web_search="disabled"'
$script:CodexJobSkillInstructionsOverride = 'skills.include_instructions=false'
$script:CodexJobBundledSkillsOverride = 'skills.bundled.enabled=false'
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
            throw "OutputDirectory must be disjoint from RepoPath and Git admin roots so a workspace-write child cannot forge job evidence: output=$full protected=$protected"
        }
    }

    $tempRoots = @(Get-LocalFixedTempRoots)
    foreach ($tempRoot in $tempRoots) {
        if (Test-PathWithin -Candidate $full -Parent $tempRoot) {
            throw "OutputDirectory must be outside writable temporary roots: $full"
        }
    }

    $nearest = $full
    while (-not (Test-Path -LiteralPath $nearest)) {
        $parent = [IO.Directory]::GetParent($nearest)
        if ($null -eq $parent) {
            throw "No existing ancestor was found for OutputDirectory: $full"
        }
        $nearest = $parent.FullName
    }
    if (-not (Test-Path -LiteralPath $nearest -PathType Container)) {
        throw "The nearest existing OutputDirectory ancestor is not a directory: $nearest"
    }
    Assert-NoReparseDirectoryAncestors -Path $nearest -Label 'OutputDirectory ancestor'

    $outputCanonical = Get-CanonicalPotentialDirectoryPath -Path $full
    foreach ($protected in $protectedPaths) {
        $protectedCanonical = Get-FinalDirectoryPath -Path $protected
        if (Test-PathsOverlap -First $outputCanonical -Second $protectedCanonical) {
            throw "OutputDirectory must be physically disjoint from RepoPath and Git admin roots: output=$outputCanonical protected=$protectedCanonical"
        }
    }
    foreach ($tempRoot in $tempRoots) {
        if (Test-Path -LiteralPath $tempRoot -PathType Container) {
            $tempCanonical = Get-FinalDirectoryPath -Path $tempRoot
            if (Test-PathWithin -Candidate $outputCanonical -Parent $tempCanonical) {
                throw "OutputDirectory resolves physically inside a writable temporary root: $outputCanonical"
            }
        }
    }
    return (Get-NormalizedPath -Path $nearest)
}

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
            throw "Ambient endpoint, proxy, custom-CA, or unapproved auth override is forbidden for Codex delegation: $name (value not logged). Unset it before retrying."
        }
    }
    foreach ($entry in @(Get-ChildItem Env:)) {
        if ($entry.Name -like 'OPENAI_*' -and -not [string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            throw "Ambient OPENAI_* authority/egress override is forbidden for Codex delegation: $($entry.Name) (value not logged)."
        }
    }
}

function Assert-NoAmbientCodexHomeOverride {
    if (-not [string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process'))) {
        throw 'Ambient CODEX_HOME is forbidden for delegated jobs (value not logged); the OS user-profile default is pinned explicitly.'
    }
}

function Assert-NoAmbientSecretVariables {
    foreach ($entry in @(Get-ChildItem Env:)) {
        if ($entry.Name -ieq 'CODEX_API_KEY' -and $AllowCodexApiKeyEnvironment) { continue }
        if ($entry.Name -match '(?i)(KEY|SECRET|TOKEN|PASSWORD|PASSWD|CREDENTIAL|PRIVATE)' -and
            -not [string]::IsNullOrWhiteSpace([string]$entry.Value)) {
            throw "Ambient secret-shaped environment variable is forbidden for delegated jobs: $($entry.Name) (value not logged)."
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
            throw "Project-local .codex/$leaf is forbidden for delegated jobs; move required instructions to AGENTS.md and remove this executable configuration layer."
        }
    }
}

function Assert-NoCodexHomeDelegationLayer {
    param([Parameter(Mandatory = $true)][string]$CodexHomePath)

    foreach ($leaf in @('config.toml', 'AGENTS.override.md', 'AGENTS.md')) {
        $path = [IO.Path]::Combine($CodexHomePath, $leaf)
        $null = Assert-NoReparsePathComponents -Path $path -Label "Pinned CODEX_HOME/$leaf" -AllowMissingTail
        if (Test-Path -LiteralPath $path) {
            throw "Pinned CODEX_HOME/$leaf is forbidden for delegated jobs; user-home config and instruction layers are not owner-approved input."
        }
    }
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
    return [pscustomobject]@{
        windows_directory = $windowsDirectory
        command_host = $trustedCmd
        temporary_directory = $trustedTemp
    }
}

$trustedBootstrapEnvironment = Initialize-TrustedWindowsEnvironment
Assert-NoAmbientEgressOverrides
Assert-NoAmbientCodexHomeOverride
if (-not [string]::IsNullOrWhiteSpace([string]$env:CODEX_API_KEY) -and -not $AllowCodexApiKeyEnvironment) {
    throw 'CODEX_API_KEY is present but was not explicitly authorized. Re-run with -AllowCodexApiKeyEnvironment to adopt that auth/billing identity (value will never be logged).'
}
Assert-NoAmbientSecretVariables

$bootstrapOriginalEnvironment = @{
    SystemRoot = [Environment]::GetEnvironmentVariable('SystemRoot', 'Process')
    WINDIR = [Environment]::GetEnvironmentVariable('WINDIR', 'Process')
    ComSpec = [Environment]::GetEnvironmentVariable('ComSpec', 'Process')
    TEMP = [Environment]::GetEnvironmentVariable('TEMP', 'Process')
    TMP = [Environment]::GetEnvironmentVariable('TMP', 'Process')
}
try {
    $env:SystemRoot = [string]$trustedBootstrapEnvironment.windows_directory
    $env:WINDIR = [string]$trustedBootstrapEnvironment.windows_directory
    $env:ComSpec = [string]$trustedBootstrapEnvironment.command_host
    $env:TEMP = [string]$trustedBootstrapEnvironment.temporary_directory
    $env:TMP = [string]$trustedBootstrapEnvironment.temporary_directory

if ('CodexJobAtomicFile' -as [type]) {
    throw 'A CodexJobAtomicFile type already exists; run this helper in a fresh trusted Windows PowerShell process.'
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class CodexJobAtomicFile
{
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool MoveFileEx(string existingFileName, string newFileName, int flags);
}
'@

if (('CodexJobPathNative' -as [type]) -or ('CodexJobByHandleFileInformation' -as [type])) {
    throw 'A Codex job path-native type already exists; run this helper in a fresh trusted Windows PowerShell process.'
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

[StructLayout(LayoutKind.Sequential)]
public struct CodexJobByHandleFileInformation
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

public static class CodexJobPathNative
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
        out CodexJobByHandleFileInformation fileInformation);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern uint GetSystemWindowsDirectoryW(StringBuilder buffer, uint size);
}
'@

if ('CodexJobPreflightBoundedWriteStream' -as [type]) {
    throw 'A CodexJobPreflightBoundedWriteStream type already exists; run this helper in a fresh trusted Windows PowerShell process.'
}
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

public sealed class CodexJobPreflightBoundedWriteStream : Stream
{
    private readonly Stream inner;
    private readonly long limit;
    private long bytesWritten;
    private volatile bool limitExceeded;

    public CodexJobPreflightBoundedWriteStream(Stream inner, long limit)
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
} finally {
    foreach ($bootstrapName in @('SystemRoot', 'WINDIR', 'ComSpec', 'TEMP', 'TMP')) {
        $originalValue = $bootstrapOriginalEnvironment[$bootstrapName]
        if ($null -eq $originalValue) {
            [Environment]::SetEnvironmentVariable($bootstrapName, $null, 'Process')
        } else {
            [Environment]::SetEnvironmentVariable($bootstrapName, [string]$originalValue, 'Process')
        }
    }
}

function Get-OpenFileHandleContract {
    param(
        [Parameter(Mandatory = $true)][IO.FileStream]$Stream,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $information = New-Object CodexJobByHandleFileInformation
    if (-not [CodexJobPathNative]::GetFileInformationByHandle($Stream.SafeFileHandle, [ref]$information)) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "$Label file identity query failed. win32_error=$errorCode"
    }

    $capacity = 32768
    $builder = New-Object Text.StringBuilder($capacity)
    $length = [CodexJobPathNative]::GetFinalPathNameByHandleW(
        $Stream.SafeFileHandle, $builder, [uint32]$capacity, [uint32]0)
    if ($length -eq 0) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "$Label handle canonicalization failed. win32_error=$errorCode"
    }
    if ($length -ge $capacity) {
        $capacity = [int]$length + 1
        $builder = New-Object Text.StringBuilder($capacity)
        $length = [CodexJobPathNative]::GetFinalPathNameByHandleW(
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

function Get-PromptIdentityContract {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = $null
    try {
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $identity = Get-OpenFileHandleContract -Stream $stream -Label 'PromptPath'
        return [pscustomobject]@{
            canonical_path = [string]$identity.canonical_path
            volume_serial = [string]$identity.volume_serial
            file_id = [string]$identity.file_id
            link_count = [uint32]$identity.link_count
            length_bytes = [long]$stream.Length
        }
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-OpenScriptHandleContract {
    param(
        [Parameter(Mandatory = $true)][IO.FileStream]$Stream,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $identity = Get-OpenFileHandleContract -Stream $Stream -Label $Label
    if ([uint32]$identity.link_count -ne 1) { throw "$Label must have exactly one hard link." }
    if ($Stream.Length -le 0 -or $Stream.Length -gt [long]$script:CodexJobScriptMaxBytes) {
        throw "$Label length must be between 1 and $($script:CodexJobScriptMaxBytes) bytes."
    }
    $Stream.Position = 0
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = (($algorithm.ComputeHash($Stream) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $algorithm.Dispose()
        $Stream.Position = 0
    }
    return [pscustomobject]@{
        path = Get-NormalizedPath -Path $Stream.Name
        canonical_path = [string]$identity.canonical_path
        volume_serial = [string]$identity.volume_serial
        file_id = [string]$identity.file_id
        link_count = [uint32]$identity.link_count
        length_bytes = [long]$Stream.Length
        sha256 = $hash
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
        return (Get-OpenScriptHandleContract -Stream $stream -Label $Label)
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
    $identity = Get-OpenFileHandleContract -Stream $Stream -Label 'Git config'
    if ([uint32]$identity.link_count -ne 1) { throw 'Git config must have exactly one hard link.' }
    if ($Stream.Length -le 0 -or $Stream.Length -gt [long]$script:CodexJobGitConfigMaxBytes) {
        throw "Git config length must be between 1 and $($script:CodexJobGitConfigMaxBytes) bytes."
    }
    if ((Get-NormalizedPath -Path $Stream.Name) -ine (Get-NormalizedPath -Path $ExpectedPath)) {
        throw 'Git config stream path differs from the expected direct .git/config path.'
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

function Assert-SafeGitConfigHandleContract {
    param(
        [Parameter(Mandatory = $true)][IO.FileStream]$Stream,
        [Parameter(Mandatory = $true)][psobject]$Expected
    )

    $current = Get-SafeGitConfigHandleContract -Stream $Stream -ExpectedPath ([string]$Expected.path)
    foreach ($property in @('path', 'canonical_path', 'volume_serial', 'file_id', 'link_count', 'length_bytes', 'sha256', 'contract')) {
        if ([string]$current.$property -ine [string]$Expected.$property) {
            throw "Git config integrity changed: $property"
        }
    }
}

function Assert-SafeGitConfigContractCurrent {
    param([Parameter(Mandatory = $true)][psobject]$Expected)

    $current = Get-SafeGitConfigContract -Path ([string]$Expected.path)
    foreach ($property in @('path', 'canonical_path', 'volume_serial', 'file_id', 'link_count', 'length_bytes', 'sha256', 'contract')) {
        if ([string]$current.$property -ine [string]$Expected.$property) {
            throw "Git config integrity changed: $property"
        }
    }
}

function Assert-ScriptDirectoryBoundary {
    param(
        [Parameter(Mandatory = $true)][string]$DirectoryPath,
        [Parameter(Mandatory = $true)][string[]]$ProtectedDirectories
    )

    Assert-LocalFixedDrivePath -Path $DirectoryPath -Label 'Script directory'
    $null = Assert-NoReparsePathComponents -Path $DirectoryPath -Label 'Script directory'
    if (-not (Test-Path -LiteralPath $DirectoryPath -PathType Container)) { throw 'Script directory is missing.' }
    $canonical = Get-FinalDirectoryPath -Path $DirectoryPath
    foreach ($boundary in @($ProtectedDirectories) + @(Get-LocalFixedTempRoots)) {
        Assert-LocalFixedDrivePath -Path $boundary -Label 'Script directory protected boundary'
        if (Test-PathsOverlap -First $DirectoryPath -Second $boundary) {
            throw "Script directory overlaps a repository, Git admin, evidence, or temp boundary: $boundary"
        }
        if (Test-Path -LiteralPath $boundary -PathType Container) {
            if (Test-PathsOverlap -First $canonical -Second (Get-FinalDirectoryPath -Path $boundary)) {
                throw "Script directory physically overlaps a repository, Git admin, evidence, or temp boundary: $boundary"
            }
        }
    }
    return $canonical
}

function Assert-ScriptContractCurrent {
    param(
        [Parameter(Mandatory = $true)][psobject]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $current = Get-ScriptFileContract -Path ([string]$Expected.path) -Label $Label
    foreach ($property in @('path', 'canonical_path', 'volume_serial', 'file_id', 'link_count', 'length_bytes', 'sha256')) {
        if ([string]$current.$property -ine [string]$Expected.$property) {
            throw "$Label integrity changed: $property"
        }
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
    $handle = [CodexJobPathNative]::CreateFileW(
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
        $length = [CodexJobPathNative]::GetFinalPathNameByHandleW($handle, $builder, [uint32]$capacity, [uint32]0)
        if ($length -eq 0) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "Directory canonicalization failed. path=$full win32_error=$errorCode"
        }
        if ($length -ge $capacity) {
            $capacity = [int]$length + 1
            $builder = New-Object Text.StringBuilder($capacity)
            $length = [CodexJobPathNative]::GetFinalPathNameByHandleW($handle, $builder, [uint32]$capacity, [uint32]0)
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
    $length = [CodexJobPathNative]::GetSystemWindowsDirectoryW($builder, [uint32]$capacity)
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
    $trustedModuleRoot = [IO.Path]::Combine($workingDirectory, 'Modules')
    Assert-NoReparseDirectoryAncestors -Path $trustedModuleRoot -Label 'System PowerShell module directory'
    $trustedModuleRoot = Get-FinalDirectoryPath -Path $trustedModuleRoot
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
$signature = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $env:SYSTEM_POWERSHELL_SIGNATURE_TARGET
if ($null -eq $signature.SignerCertificate) { throw 'No signer certificate.' }
[pscustomobject]@{
    status = $signature.Status.ToString()
    subject = $signature.SignerCertificate.Subject
    simple_name = $signature.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
    thumbprint = $signature.SignerCertificate.Thumbprint
} | Microsoft.PowerShell.Utility\ConvertTo-Json -Compress
'@
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($signatureScript))
    $capture = Invoke-NativeCapture -FilePath $canonical `
        -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand) `
        -WorkingDirectory $workingDirectory -TimeoutSeconds 15 `
        -EnvironmentVariables @{
            SYSTEM_POWERSHELL_SIGNATURE_TARGET = $canonical
            PSModulePath = $trustedModuleRoot
        }
    if ($capture.timed_out -or $capture.exit_code -ne 0) { throw 'Bounded System PowerShell Authenticode validation failed.' }
    try { $signature = $capture.stdout.Trim() | ConvertFrom-Json } catch { throw 'System PowerShell Authenticode validation returned invalid JSON.' }
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

function Get-CanonicalPotentialDirectoryPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    Assert-LocalFixedDrivePath -Path $Path -Label 'Potential directory path'
    $full = Get-NormalizedPath -Path $Path
    $null = Assert-NoReparsePathComponents -Path $full -Label 'Potential directory path' -AllowMissingTail
    $missingParts = New-Object 'System.Collections.Generic.Stack[string]'
    $cursor = $full
    while (-not (Test-Path -LiteralPath $cursor)) {
        $leaf = [IO.Path]::GetFileName($cursor)
        if ([string]::IsNullOrWhiteSpace($leaf)) {
            throw "Cannot find an existing ancestor for canonicalization: $full"
        }
        $missingParts.Push($leaf)
        $parent = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) {
            throw "Cannot find an existing ancestor for canonicalization: $full"
        }
        $cursor = $parent.FullName
    }
    if (-not (Test-Path -LiteralPath $cursor -PathType Container)) {
        throw "Canonicalization ancestor is not a directory: $cursor"
    }
    $canonical = Get-FinalDirectoryPath -Path $cursor
    while ($missingParts.Count -gt 0) {
        $canonical = Join-Path $canonical $missingParts.Pop()
    }
    return (Get-NormalizedPath -Path $canonical)
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
    $moved = [CodexJobAtomicFile]::MoveFileEx($temporaryPath, $Path, 0x1 -bor 0x8)
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

function Read-TrustedJobMetadata {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedJobId,
        [Parameter(Mandatory = $true)][string]$ExpectedRepoPath,
        [Parameter(Mandatory = $true)][string]$ExpectedPromptPath,
        [Parameter(Mandatory = $true)][string]$ExpectedCodexPath,
        [Parameter(Mandatory = $true)][string]$ExpectedPromptSha256,
        [Parameter(Mandatory = $true)][psobject]$ExpectedPromptContract,
        [Parameter(Mandatory = $true)][string]$ExpectedOutputDirectory,
        [Parameter(Mandatory = $true)][string]$ExpectedPromptCanonicalPath,
        [Parameter(Mandatory = $true)][string]$ExpectedCodexCanonicalPath,
        [Parameter(Mandatory = $true)][string]$ExpectedGitDirectory,
        [Parameter(Mandatory = $true)][string]$ExpectedGitDirectoryCanonicalPath,
        [Parameter(Mandatory = $true)][string]$ExpectedGitCommonDirectory,
        [Parameter(Mandatory = $true)][string]$ExpectedGitCommonDirectoryCanonicalPath,
        [Parameter(Mandatory = $true)][psobject]$ExpectedGitBindingContract,
        [Parameter(Mandatory = $true)][psobject]$ExpectedGitLauncherContract,
        [Parameter(Mandatory = $true)][psobject]$ExpectedCodexLauncherContract,
        [Parameter(Mandatory = $true)][psobject]$ExpectedCodexSignatureContract,
        [Parameter(Mandatory = $true)][string[]]$ExpectedCodexArguments,
        [Parameter(Mandatory = $true)][int]$ExpectedWorkerPid,
        [Parameter(Mandatory = $true)][string]$ExpectedWorkerStartedAtUtc,
        [Parameter(Mandatory = $true)][string]$ExpectedWorkerProcessPath
    )

    Assert-LocalFixedDrivePath -Path $Path -Label 'MetadataPath'
    $null = Assert-NoReparsePathComponents -Path $Path -Label 'MetadataPath'
    $value = Read-JobMetadata -Path $Path
    if ([int]$value.metadata_schema_version -ne 3) {
        throw 'Job metadata schema mismatch.'
    }
    foreach ($pathContract in @(
        [pscustomobject]@{ label = 'metadata_path'; value = [string]$value.metadata_path },
        [pscustomobject]@{ label = 'repo_path'; value = [string]$value.repo_path },
        [pscustomobject]@{ label = 'prompt_path'; value = [string]$value.prompt_path },
        [pscustomobject]@{ label = 'codex_path'; value = [string]$value.codex_path },
        [pscustomobject]@{ label = 'codex_home_path'; value = [string]$value.codex_home_path },
        [pscustomobject]@{ label = 'codex_home_canonical_path'; value = [string]$value.codex_home_canonical_path },
        [pscustomobject]@{ label = 'output_directory'; value = [string]$value.output_directory },
        [pscustomobject]@{ label = 'git_directory'; value = [string]$value.git_directory },
        [pscustomobject]@{ label = 'git_common_directory'; value = [string]$value.git_common_directory },
        [pscustomobject]@{ label = 'repo_canonical_path'; value = [string]$value.repo_canonical_path },
        [pscustomobject]@{ label = 'prompt_canonical_path'; value = [string]$value.prompt_canonical_path },
        [pscustomobject]@{ label = 'codex_canonical_path'; value = [string]$value.codex_canonical_path },
        [pscustomobject]@{ label = 'output_canonical_path'; value = [string]$value.output_canonical_path },
        [pscustomobject]@{ label = 'git_directory_canonical_path'; value = [string]$value.git_directory_canonical_path },
        [pscustomobject]@{ label = 'git_common_directory_canonical_path'; value = [string]$value.git_common_directory_canonical_path },
        [pscustomobject]@{ label = 'git_marker_path'; value = [string]$value.git_marker_path },
        [pscustomobject]@{ label = 'git_commondir_marker_path'; value = [string]$value.git_commondir_marker_path },
        [pscustomobject]@{ label = 'codex_working_directory'; value = [string]$value.codex_working_directory },
        [pscustomobject]@{ label = 'git_executable_path'; value = [string]$value.git_executable_path },
        [pscustomobject]@{ label = 'git_executable_canonical_path'; value = [string]$value.git_executable_canonical_path },
        [pscustomobject]@{ label = 'git_executable_working_directory'; value = [string]$value.git_executable_working_directory },
        [pscustomobject]@{ label = 'git_config_path'; value = [string]$value.git_config_path },
        [pscustomobject]@{ label = 'git_config_canonical_path'; value = [string]$value.git_config_canonical_path },
        [pscustomobject]@{ label = 'start_script_path'; value = [string]$value.start_script_path },
        [pscustomobject]@{ label = 'start_script_canonical_path'; value = [string]$value.start_script_canonical_path },
        [pscustomobject]@{ label = 'worker_script_path'; value = [string]$value.worker_script_path },
        [pscustomobject]@{ label = 'worker_script_canonical_path'; value = [string]$value.worker_script_canonical_path },
        [pscustomobject]@{ label = 'child_powershell_module_path'; value = [string]$value.child_powershell_module_path }
    )) {
        Assert-LocalFixedDrivePath -Path $pathContract.value -Label "Job metadata $($pathContract.label)"
        $null = Assert-NoReparsePathComponents -Path $pathContract.value `
            -Label "Job metadata $($pathContract.label)" -AllowMissingTail
    }
    foreach ($optionalCanonical in @([string]$value.git_marker_canonical_path, [string]$value.git_commondir_marker_canonical_path)) {
        if (-not [string]::IsNullOrWhiteSpace($optionalCanonical)) {
            Assert-LocalFixedDrivePath -Path $optionalCanonical -Label 'Job metadata Git marker canonical path'
        }
    }
    if ([string]$value.job_id -ne $ExpectedJobId) {
        throw 'Job metadata ID mismatch.'
    }
    if ((Get-NormalizedPath -Path ([string]$value.metadata_path)) -ine (Get-NormalizedPath -Path $Path)) {
        throw 'Job metadata path mismatch.'
    }
    if ((Get-NormalizedPath -Path ([string]$value.repo_path)) -ine (Get-NormalizedPath -Path $ExpectedRepoPath)) {
        throw 'Job metadata repository mismatch.'
    }
    if ((Get-NormalizedPath -Path ([string]$value.prompt_path)) -ine (Get-NormalizedPath -Path $ExpectedPromptPath)) {
        throw 'Job metadata prompt path mismatch.'
    }
    if ((Get-NormalizedPath -Path ([string]$value.codex_path)) -ine (Get-NormalizedPath -Path $ExpectedCodexPath)) {
        throw 'Job metadata Codex path mismatch.'
    }
    if ((Get-NormalizedPath -Path ([string]$value.codex_working_directory)) -ine (Get-NormalizedPath -Path ([string]$ExpectedCodexLauncherContract.working_directory)) -or
        (Get-NormalizedPath -Path ([string]$value.codex_home_path)) -ine (Get-NormalizedPath -Path ([string]$ExpectedCodexLauncherContract.codex_home_path)) -or
        (Get-NormalizedPath -Path ([string]$value.codex_home_canonical_path)) -ine (Get-NormalizedPath -Path ([string]$ExpectedCodexLauncherContract.codex_home_canonical_path)) -or
        [string]$value.codex_home_contract -cne [string]$ExpectedCodexLauncherContract.codex_home_contract -or
        [string]$value.auth_channel -cne [string]$ExpectedCodexLauncherContract.auth_channel -or
        [bool]$value.codex_api_key_environment_approved -ne [bool]$ExpectedCodexLauncherContract.codex_api_key_environment_approved -or
        [string]$value.child_executable_path -cne [string]$ExpectedCodexLauncherContract.child_executable_path -or
        [string]$value.child_executable_pathext -cne [string]$ExpectedCodexLauncherContract.child_executable_pathext -or
        [string]$value.child_no_default_current_directory -cne [string]$ExpectedCodexLauncherContract.child_no_default_current_directory -or
        [string]$value.child_powershell_module_path -ine [string]$ExpectedCodexLauncherContract.child_powershell_module_path -or
        [string]$value.codex_shell_psmodulepath_override -cne [string]$ExpectedCodexLauncherContract.codex_shell_psmodulepath_override -or
        [string]$value.codex_sha256 -ine [string]$ExpectedCodexLauncherContract.sha256 -or
        [string]$value.codex_signer_thumbprint -ine [string]$ExpectedCodexSignatureContract.thumbprint -or
        [string]$value.codex_signer_subject -cne [string]$ExpectedCodexSignatureContract.subject -or
        [string]$value.codex_product_version -cne [string]$ExpectedCodexSignatureContract.product_version -or
        [string]$value.codex_authenticode_status -ne 'Valid') {
        throw 'Job metadata Codex launcher trust mismatch.'
    }
    $expectedStartScript = $ExpectedCodexLauncherContract.start_script_contract
    $expectedWorkerScript = $ExpectedCodexLauncherContract.worker_script_contract
    Assert-ScriptContractCurrent -Expected $expectedStartScript -Label 'Start helper script'
    Assert-ScriptContractCurrent -Expected $expectedWorkerScript -Label 'Worker helper script'
    foreach ($scriptBinding in @(
        [pscustomobject]@{ prefix = 'start_script'; contract = $expectedStartScript },
        [pscustomobject]@{ prefix = 'worker_script'; contract = $expectedWorkerScript }
    )) {
        foreach ($property in @('path', 'canonical_path', 'volume_serial', 'file_id', 'link_count', 'length_bytes', 'sha256')) {
            $metadataProperty = '{0}_{1}' -f $scriptBinding.prefix, $property
            if ([string]$value.$metadataProperty -ine [string]$scriptBinding.contract.$property) {
                throw "Job metadata helper script integrity mismatch: $metadataProperty"
            }
        }
    }
    if ([string]$value.script_integrity_contract -cne 'local-fixed-nonreparse-disjoint;single-hard-link;handle-identity-and-sha256;worker-read-locked-through-handshake') {
        throw 'Job metadata helper script integrity contract mismatch.'
    }
    if ([string]$value.prompt_sha256 -ine $ExpectedPromptSha256) {
        throw 'Job metadata prompt hash mismatch.'
    }
    if ([long]$value.prompt_length_bytes -ne [long]$ExpectedPromptContract.length_bytes -or
        [long]$value.prompt_max_bytes -ne [long]$script:CodexJobPromptMaxBytes -or
        [string]$value.prompt_volume_serial -ine [string]$ExpectedPromptContract.volume_serial -or
        [string]$value.prompt_file_id -ine [string]$ExpectedPromptContract.file_id -or
        [uint32]$value.prompt_link_count -ne 1 -or
        [string]$value.prompt_contract -cne 'strict-utf8;single-hard-link;handle-identity-bound;max-8388608-bytes') {
        throw 'Job metadata prompt identity or size contract mismatch.'
    }
    if ([long]$value.stdout_max_bytes -ne [long]$script:CodexJobEvidenceStreamMaxBytes -or
        [long]$value.stderr_max_bytes -ne [long]$script:CodexJobEvidenceStreamMaxBytes -or
        [string]$value.evidence_stream_contract -cne 'bounded-67108864-bytes-per-stream;overflow-drained-and-job-failed') {
        throw 'Job metadata evidence stream limit contract mismatch.'
    }
    if ([long]$value.stdout_bytes_captured -lt 0 -or
        [long]$value.stdout_bytes_captured -gt [long]$script:CodexJobEvidenceStreamMaxBytes -or
        [long]$value.stderr_bytes_captured -lt 0 -or
        [long]$value.stderr_bytes_captured -gt [long]$script:CodexJobEvidenceStreamMaxBytes -or
        ([bool]$value.output_limit_exceeded -and
            -not ([bool]$value.stdout_output_limit_exceeded -or [bool]$value.stderr_output_limit_exceeded))) {
        throw 'Job metadata evidence byte counters or overflow flags are inconsistent.'
    }
    if ((Get-NormalizedPath -Path ([string]$value.output_directory)) -ine (Get-NormalizedPath -Path $ExpectedOutputDirectory)) {
        throw 'Job metadata evidence directory mismatch.'
    }
    if ([string]$value.evidence_boundary -ne 'local-fixed-disjoint-from-repo-git-admin-temp-and-reparse-ancestors') {
        throw 'Job metadata evidence boundary mismatch.'
    }
    if ([string]$value.storage_contract -ne 'local-ready-fixed-drives-only') {
        throw 'Job metadata storage contract mismatch.'
    }
    if ([string]$value.entry_powershell_contract -cne 'exact-os-system-WindowsPowerShell;pinned-PSHOME-modules;critical-first-resolved-builtin-cmdlets;fresh-NoProfile-NonInteractive-owner-entry') {
        throw 'Job metadata entry PowerShell provenance contract mismatch.'
    }
    if ([string]$value.filesystem_read_boundary -ne 'full-local-filesystem-on-Windows-legacy-sandbox' -or
        -not [bool]$value.windows_account_read_exposure_approved -or
        [string]$value.filesystem_read_authority_contract -ne 'explicit-owner-approval-required-before-worker-launch') {
        throw 'Job metadata Windows filesystem-read authority contract mismatch.'
    }
    if ([string]$value.network_environment_contract -ne 'fail-closed-known-egress-and-auth-overrides;positive-allowlist-child-environment;secret-shaped-ambient-fail-closed;rust-overrides-denied') {
        throw 'Job metadata network environment contract mismatch.'
    }
    if ([string]$value.shell_environment_contract -ne 'positive-core-process-environment;pinned-signed-git-path;no-current-directory-resolution;exe-only-pathext;pinned-system-powershell-modules;shell-inherit-core;login-shell-disabled;profile-disabled;default-secret-excludes-enabled;codex-api-key-explicitly-excluded' -or
        [string]$value.git_environment_contract -ne 'no-system-or-global-config;no-terminal-prompt;gcm-noninteractive;local-config-bounded-safe-allowlist-and-locked' -or
        [string]$value.preflight_capture_contract -ne 'bounded-1048576-bytes-per-stream;overflow-fail-closed') {
        throw 'Job metadata child environment or preflight capture contract mismatch.'
    }
    $recordedSandbox = [string]$value.sandbox
    if ($recordedSandbox -cnotin @('read-only', 'workspace-write')) {
        throw 'Job metadata sandbox value is unsupported.'
    }
    $expectedCodexSandboxContract = if ($recordedSandbox -ceq 'read-only') {
        'read-only;workspace-write-network-and-temp-overrides-not-applicable'
    } else {
        'workspace-write;network-and-temp-roots-disabled'
    }
    if ([string]$value.auth_identity_contract -cne 'auth-mode-only;owner-must-independently-confirm-account-and-billing-identity' -or
        [string]$value.codex_version -cne $script:CodexJobSupportedVersion -or
        [string]$value.codex_supported_version_contract -cne 'exact-codex-cli-0.147.0' -or
        [string]$value.codex_model_provider_override -cne $script:CodexJobModelProviderOverride -or
        [string]$value.codex_sandbox_contract -cne $expectedCodexSandboxContract -or
        [string]$value.codex_configuration_contract -ne 'strict-config;openai-provider;ignore-user-config;ignore-user-and-project-rules;project-config-and-hooks-absent;codex-home-config-and-instructions-absent;linked-worktrees-forbidden;web-search-disabled;skill-instructions-disabled;workspace-write-network-and-temp-roots-disabled-when-applicable;optional-surfaces-disabled-and-preflighted') {
        throw 'Job metadata Codex configuration contract mismatch.'
    }
    if ([string]$value.codex_web_search_override -cne $script:CodexJobWebSearchOverride -or
        [string]$value.codex_feature_preflight -cne 'passed-bounded-features-list-after-owner-authorization' -or
        [string]$value.codex_optional_surface_contract -cne 'fixed-disable-list;actual-only-bounded-features-list-after-owner-authorization;web-search-and-skill-instructions-disabled;no-app-plugin-memory-hook-mcp-browser-multi-agent-unified-exec-or-shell-snapshot-surfaces') {
        throw 'Job metadata optional surface contract mismatch.'
    }
    $recordedDisabledFeatures = @($value.codex_disabled_features | ForEach-Object { [string]$_ })
    if ($recordedDisabledFeatures.Count -ne $script:CodexJobDisabledFeatures.Count) {
        throw 'Job metadata disabled feature count mismatch.'
    }
    for ($featureIndex = 0; $featureIndex -lt $recordedDisabledFeatures.Count; $featureIndex++) {
        if ([string]$recordedDisabledFeatures[$featureIndex] -cne [string]$script:CodexJobDisabledFeatures[$featureIndex]) {
            throw "Job metadata disabled feature mismatch at index $featureIndex."
        }
    }
    if ((Get-NormalizedPath -Path ([string]$value.git_directory)) -ine (Get-NormalizedPath -Path $ExpectedGitDirectory) -or
        (Get-NormalizedPath -Path ([string]$value.git_common_directory)) -ine (Get-NormalizedPath -Path $ExpectedGitCommonDirectory)) {
        throw 'Job metadata Git admin path mismatch.'
    }
    foreach ($bindingProperty in @(
        'git_marker_path', 'git_marker_kind', 'git_marker_canonical_path', 'git_marker_length_bytes', 'git_marker_sha256',
        'git_commondir_marker_path', 'git_commondir_marker_kind', 'git_commondir_marker_canonical_path',
        'git_commondir_marker_length_bytes', 'git_commondir_marker_sha256'
    )) {
        if ([string]$value.$bindingProperty -cne [string]$ExpectedGitBindingContract.$bindingProperty) {
            throw "Job metadata Git binding mismatch: $bindingProperty"
        }
    }
    if ((Get-NormalizedPath -Path ([string]$value.git_executable_path)) -ine (Get-NormalizedPath -Path ([string]$ExpectedGitLauncherContract.path)) -or
        (Get-NormalizedPath -Path ([string]$value.git_executable_canonical_path)) -ine (Get-NormalizedPath -Path ([string]$ExpectedGitLauncherContract.canonical_path)) -or
        (Get-NormalizedPath -Path ([string]$value.git_executable_working_directory)) -ine (Get-NormalizedPath -Path ([string]$ExpectedGitLauncherContract.working_directory)) -or
        [string]$value.git_executable_sha256 -ine [string]$ExpectedGitLauncherContract.sha256 -or
        [string]$value.git_authenticode_status -ne 'Valid' -or
        [string]$value.git_signer_subject -cne [string]$ExpectedGitLauncherContract.signer_subject -or
        [string]$value.git_signer_thumbprint -ine [string]$ExpectedGitLauncherContract.signer_thumbprint -or
        [string]$value.git_product_version -cne [string]$ExpectedGitLauncherContract.product_version) {
        throw 'Job metadata Git executable trust mismatch.'
    }
    $expectedGitConfig = $ExpectedGitLauncherContract.git_config_contract
    Assert-SafeGitConfigContractCurrent -Expected $expectedGitConfig
    foreach ($property in @('path', 'canonical_path', 'volume_serial', 'file_id', 'link_count', 'length_bytes', 'sha256', 'contract')) {
        $metadataProperty = "git_config_$property"
        if ([string]$value.$metadataProperty -ine [string]$expectedGitConfig.$property) {
            throw "Job metadata Git config integrity mismatch: $metadataProperty"
        }
    }
    Assert-SafeEvidenceDirectory -Path ([string]$value.output_directory) -RepositoryPath $ExpectedRepoPath `
        -AdditionalProtectedPaths @($ExpectedGitDirectory, $ExpectedGitCommonDirectory) | Out-Null
    if ([string]$value.path_canonicalization -ne 'GetFinalPathNameByHandleW') {
        throw 'Job metadata path canonicalization contract mismatch.'
    }
    $currentRepoCanonical = Get-FinalDirectoryPath -Path $ExpectedRepoPath
    $currentOutputCanonical = Get-CanonicalPotentialDirectoryPath -Path ([string]$value.output_directory)
    $currentPromptIdentity = Get-PromptIdentityContract -Path $ExpectedPromptPath
    $currentPromptCanonical = [string]$currentPromptIdentity.canonical_path
    $currentCodexCanonical = Get-FinalFilePath -Path $ExpectedCodexPath
    $currentGitDirectoryCanonical = Get-FinalDirectoryPath -Path $ExpectedGitDirectory
    $currentGitCommonDirectoryCanonical = Get-FinalDirectoryPath -Path $ExpectedGitCommonDirectory
    if ((Get-NormalizedPath -Path ([string]$value.repo_canonical_path)) -ine $currentRepoCanonical) {
        throw 'Job metadata canonical repository path mismatch.'
    }
    if ((Get-NormalizedPath -Path ([string]$value.output_canonical_path)) -ine $currentOutputCanonical) {
        throw 'Job metadata canonical evidence path mismatch.'
    }
    if ((Get-NormalizedPath -Path ([string]$value.prompt_canonical_path)) -ine $currentPromptCanonical -or
        $currentPromptCanonical -ine (Get-NormalizedPath -Path $ExpectedPromptCanonicalPath) -or
        [string]$currentPromptIdentity.volume_serial -ine [string]$ExpectedPromptContract.volume_serial -or
        [string]$currentPromptIdentity.file_id -ine [string]$ExpectedPromptContract.file_id -or
        [uint32]$currentPromptIdentity.link_count -ne 1 -or
        [long]$currentPromptIdentity.length_bytes -ne [long]$ExpectedPromptContract.length_bytes) {
        throw 'Job metadata canonical prompt path mismatch.'
    }
    if ((Get-NormalizedPath -Path ([string]$value.codex_canonical_path)) -ine $currentCodexCanonical -or
        $currentCodexCanonical -ine (Get-NormalizedPath -Path $ExpectedCodexCanonicalPath)) {
        throw 'Job metadata canonical Codex path mismatch.'
    }
    if ((Get-NormalizedPath -Path ([string]$value.git_directory_canonical_path)) -ine $currentGitDirectoryCanonical -or
        $currentGitDirectoryCanonical -ine (Get-NormalizedPath -Path $ExpectedGitDirectoryCanonicalPath)) {
        throw 'Job metadata canonical Git directory mismatch.'
    }
    if ((Get-NormalizedPath -Path ([string]$value.git_common_directory_canonical_path)) -ine $currentGitCommonDirectoryCanonical -or
        $currentGitCommonDirectoryCanonical -ine (Get-NormalizedPath -Path $ExpectedGitCommonDirectoryCanonicalPath)) {
        throw 'Job metadata canonical Git common directory mismatch.'
    }
    Assert-GitBindingUnchanged -Expected $ExpectedGitBindingContract -RepositoryPath $ExpectedRepoPath `
        -GitDirectory $ExpectedGitDirectory -GitCommonDirectory $ExpectedGitCommonDirectory

    $allowedStates = @('starting', 'validating', 'running', 'completed', 'failed', 'timed_out_running', 'timed_out')
    if ([string]$value.state -notin $allowedStates) {
        throw "Job metadata has an invalid state: $($value.state)"
    }
    $arguments = @($value.codex_arguments)
    if ($arguments.Count -lt 2 -or [string]$arguments[0] -ne "--ask-for-approval=$($value.approval_policy)" -or [string]$arguments[1] -ne 'exec') {
        throw 'Job metadata argv contract mismatch.'
    }
    if ($arguments.Count -ne $ExpectedCodexArguments.Count) {
        throw 'Job metadata argv count mismatch.'
    }
    for ($argumentIndex = 0; $argumentIndex -lt $arguments.Count; $argumentIndex++) {
        if ([string]$arguments[$argumentIndex] -cne [string]$ExpectedCodexArguments[$argumentIndex]) {
            throw "Job metadata argv mismatch at index $argumentIndex."
        }
    }

    if ([string]$value.state -eq 'starting') {
        if ($null -ne $value.worker_pid -or $null -ne $value.worker_started_at_utc -or $null -ne $value.worker_process_path) {
            throw 'Starting metadata contains an incomplete or unexpected worker identity.'
        }
        return $value
    }

    if ([int]$value.worker_pid -ne $ExpectedWorkerPid) {
        throw 'Job metadata worker PID mismatch.'
    }
    $recordedWorkerStart = [DateTime]::MinValue
    $expectedWorkerStart = [DateTime]::MinValue
    $recordedStartValid = $false
    if ($value.worker_started_at_utc -is [DateTime]) {
        $recordedWorkerStart = [DateTime]$value.worker_started_at_utc
        $recordedStartValid = $true
    } else {
        $recordedStartValid = [DateTime]::TryParse(
            [string]$value.worker_started_at_utc,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind,
            [ref]$recordedWorkerStart
        )
    }
    if (-not $recordedStartValid -or -not [DateTime]::TryParse(
        $ExpectedWorkerStartedAtUtc,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$expectedWorkerStart
    )) {
        throw 'Job metadata worker start time is invalid.'
    }
    if ([Math]::Abs(($recordedWorkerStart.ToUniversalTime() - $expectedWorkerStart.ToUniversalTime()).TotalSeconds) -gt 2) {
        throw 'Job metadata worker start time mismatch.'
    }
    if ((Get-NormalizedPath -Path ([string]$value.worker_process_path)) -ine (Get-NormalizedPath -Path $ExpectedWorkerProcessPath)) {
        throw 'Job metadata worker executable mismatch.'
    }

    switch ([string]$value.state) {
        'validating' {
            if (-not [bool]$value.ok -or $null -ne $value.launcher_pid -or
                $null -ne $value.completed_at_utc -or [bool]$value.timeout_exceeded) {
                throw 'Validating metadata is internally inconsistent.'
            }
        }
        'running' {
            if ($null -eq $value.launcher_pid -or $null -ne $value.completed_at_utc -or
                [bool]$value.timeout_exceeded) {
                throw 'Running metadata is internally inconsistent.'
            }
        }
        'completed' {
            if (-not [bool]$value.ok -or [int]$value.exit_code -ne 0 -or $null -eq $value.completed_at_utc -or
                [bool]$value.output_limit_exceeded) {
                throw 'Completed metadata is internally inconsistent.'
            }
        }
        'timed_out_running' {
            if (-not [bool]$value.timeout_exceeded -or $null -ne $value.exit_code) {
                throw 'Timed-out-running metadata is internally inconsistent.'
            }
        }
        'timed_out' {
            if (-not [bool]$value.timeout_exceeded -or $null -eq $value.exit_code -or $null -eq $value.completed_at_utc) {
                throw 'Timed-out metadata is internally inconsistent.'
            }
        }
        'failed' {
            if ([bool]$value.ok -or $null -eq $value.completed_at_utc) {
                throw 'Failed metadata is internally inconsistent.'
            }
        }
        default {
            throw "Job metadata state is unsupported: $($value.state)"
        }
    }
    return $value
}

function Get-ValidatedPromptContract {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = $null
    try {
        # One non-writable, non-delete-sharing handle supplies canonical path,
        # identity, length, hash, UTF-8 validation, and BOM state.
        $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $identity = Get-OpenFileHandleContract -Stream $stream -Label 'PromptPath'
        if ([uint32]$identity.link_count -ne 1) {
            throw 'PromptPath must have exactly one hard link; linked files are forbidden from prompt egress.'
        }
        if ($stream.Length -eq 0) { throw 'Prompt file is empty.' }
        if ($stream.Length -gt [long]$script:CodexJobPromptMaxBytes) {
            throw "Prompt file exceeds the fixed $($script:CodexJobPromptMaxBytes)-byte safety limit."
        }

        $bytes = New-Object byte[] ([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($read -le 0) { throw 'Prompt handle ended before its recorded length.' }
            $offset += $read
        }
        $strictUtf8 = New-Object Text.UTF8Encoding($false, $true)
        try {
            $decoded = $strictUtf8.GetString($bytes)
        } catch [Text.DecoderFallbackException] {
            throw "PromptPath must contain valid UTF-8 bytes (UTF-8 BOM is allowed): $Path"
        }
        if ($decoded.IndexOf([char]0) -ge 0) {
            throw "PromptPath contains NUL characters and may be UTF-16 rather than UTF-8: $Path"
        }
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try {
            $hash = (($algorithm.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
        } finally {
            $algorithm.Dispose()
        }

        return [pscustomobject]@{
            canonical_path = [string]$identity.canonical_path
            volume_serial = [string]$identity.volume_serial
            file_id = [string]$identity.file_id
            link_count = [uint32]$identity.link_count
            length_bytes = [long]$stream.Length
            sha256 = $hash
            utf8_bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
        }
    } finally {
        if ($null -ne $stream) { $stream.Dispose() }
    }
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

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [ValidateRange(1, 300)][int]$TimeoutSeconds = 30,
        [hashtable]$EnvironmentVariables = @{}
    )

    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.WindowStyle = [Diagnostics.ProcessWindowStyle]::Hidden
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    $extension = [IO.Path]::GetExtension($FilePath).ToLowerInvariant()
    if ($extension -eq '.cmd') {
        # Internal deterministic timeout-regression seam only. Git, Codex, and
        # system-host production contracts below are native .exe-only.
        if ([IO.Path]::GetFileName($FilePath) -ine 'preflight-shim.cmd') {
            throw 'The .cmd capture path is reserved for the internal preflight-shim.cmd regression fixture.'
        }
        $commandInterpreter = [IO.Path]::Combine((Get-TrustedWindowsDirectory), 'System32', 'cmd.exe')
        Assert-LocalFixedDrivePath -Path $commandInterpreter -Label 'cmd.exe'
        if (-not (Test-Path -LiteralPath $commandInterpreter -PathType Leaf)) {
            throw 'cmd.exe is required to preflight a .cmd launcher.'
        }
        $startInfo.FileName = $commandInterpreter
        $tokens = New-Object 'System.Collections.Generic.List[string]'
        foreach ($argument in $Arguments) {
            if ($argument.Contains('"')) {
                throw 'A preflight argument contained a quote and cannot be safely passed through cmd.exe.'
            }
            $tokens.Add(('"{0}"' -f $argument))
        }
        $startInfo.Arguments = '/d /v:off /s /c ""%CODEX_PREFLIGHT_LAUNCHER_PATH%" {0}"' -f ($tokens -join ' ')
    } elseif ($extension -eq '.exe') {
        $startInfo.FileName = $FilePath
        $startInfo.Arguments = (($Arguments | ForEach-Object { Quote-NativeArgument -Value $_ }) -join ' ')
    } else {
        throw "Native capture supports only .exe and .cmd launchers: $FilePath"
    }
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
    Set-TrustedGitEnvironmentVariables -EnvironmentVariables $startInfo.EnvironmentVariables
    if ($extension -eq '.cmd') {
        $startInfo.EnvironmentVariables['CODEX_PREFLIGHT_LAUNCHER_PATH'] = $FilePath
    }
    # Caller-supplied values are added only after the ambient deny-by-default pass.
    # Call sites use this solely for non-secret targets and the pinned CODEX_HOME;
    # CODEX_API_KEY is never passed to any preflight child.
    foreach ($environmentName in $EnvironmentVariables.Keys) {
        if ([string]$environmentName -ieq 'CODEX_API_KEY') {
            throw 'CODEX_API_KEY is forbidden for native preflight children.'
        }
        $startInfo.EnvironmentVariables[[string]$environmentName] = [string]$EnvironmentVariables[$environmentName]
    }

    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    $stdoutTask = $null
    $stderrTask = $null
    $stdoutBuffer = $null
    $stderrBuffer = $null
    $stdoutCapture = $null
    $stderrCapture = $null
    $stdoutEncoding = [Text.Encoding]::UTF8
    $stderrEncoding = [Text.Encoding]::UTF8
    $processStarted = $false
    $processTimedOut = $false
    $captureIncomplete = $false
    $killAttempted = $false
    $killSucceeded = $false
    $captureErrors = New-Object 'System.Collections.Generic.List[string]'

    $waitMilliseconds = $TimeoutSeconds * 1000
    $isTestShim = [IO.Path]::GetFileName($FilePath) -ieq 'preflight-shim.cmd'
    $injectKillFailure = $isTestShim -and $env:CLAUDE_ROBLOX_CODEX_PREFLIGHT_TEST_FAULT -eq 'kill-fail'

    try {
        if (-not $process.Start()) {
            throw "Process.Start returned false: $FilePath"
        }
        $processStarted = $true
        $stdoutEncoding = $process.StandardOutput.CurrentEncoding
        $stderrEncoding = $process.StandardError.CurrentEncoding
        $stdoutBuffer = New-Object IO.MemoryStream
        $stderrBuffer = New-Object IO.MemoryStream
        $stdoutCapture = New-Object CodexJobPreflightBoundedWriteStream -ArgumentList @(
            $stdoutBuffer, ([long]$script:CodexJobPreflightStreamMaxBytes)
        )
        $stderrCapture = New-Object CodexJobPreflightBoundedWriteStream -ArgumentList @(
            $stderrBuffer, ([long]$script:CodexJobPreflightStreamMaxBytes)
        )
        $stdoutTask = $process.StandardOutput.BaseStream.CopyToAsync($stdoutCapture)
        $stderrTask = $process.StandardError.BaseStream.CopyToAsync($stderrCapture)
        $exited = $process.WaitForExit($waitMilliseconds)
        if (-not $exited) {
            $processTimedOut = $true
            # This is only a stuck read-only --version/login/git preflight.
            # The actual Codex job is owned by codex_job_worker.ps1 and is never killed on timeout.
            $killAttempted = $true
            try {
                if ($injectKillFailure) {
                    throw 'Injected test-only preflight Kill failure.'
                }
                $process.Kill()
                $killSucceeded = $true
            } catch {
                $captureErrors.Add("preflight kill failed: $($_.Exception.Message)")
            }
            # Never use the unbounded WaitForExit overload. A .cmd descendant may
            # retain process or pipe handles even after the wrapper is killed.
            try { $null = $process.WaitForExit(1000) } catch {
                $captureErrors.Add("post-kill wait failed: $($_.Exception.Message)")
            }
        }

        # Give redirected readers one shared, bounded deadline. If a descendant
        # inherited either pipe, close our reader instead of blocking forever.
        $drainDeadline = [DateTime]::UtcNow.AddSeconds(2)
        foreach ($entry in @(
            [pscustomobject]@{ name = 'stdout'; task = $stdoutTask; reader = $process.StandardOutput },
            [pscustomobject]@{ name = 'stderr'; task = $stderrTask; reader = $process.StandardError }
        )) {
            if ($null -eq $entry.task) {
                continue
            }
            if (-not $entry.task.IsCompleted) {
                $remaining = [int][Math]::Max(0, ($drainDeadline - [DateTime]::UtcNow).TotalMilliseconds)
                if ($remaining -gt 0) {
                    try { $null = $entry.task.Wait($remaining) } catch { }
                }
            }
            if (-not $entry.task.IsCompleted) {
                $captureIncomplete = $true
                $captureErrors.Add("$($entry.name) capture exceeded the bounded drain deadline")
                try { $entry.reader.Dispose() } catch { }
            }
        }

        $stdout = ''
        $stderr = ''
        if ($null -ne $stdoutTask -and $stdoutTask.IsCompleted) {
            try {
                $null = $stdoutTask.GetAwaiter().GetResult()
                $stdout = $stdoutEncoding.GetString($stdoutBuffer.ToArray())
            } catch {
                $captureIncomplete = $true
                $captureErrors.Add("stdout capture failed: $($_.Exception.Message)")
            }
        }
        if ($null -ne $stderrTask -and $stderrTask.IsCompleted) {
            try {
                $null = $stderrTask.GetAwaiter().GetResult()
                $stderr = $stderrEncoding.GetString($stderrBuffer.ToArray())
            } catch {
                $captureIncomplete = $true
                $captureErrors.Add("stderr capture failed: $($_.Exception.Message)")
            }
        }
        if (($null -ne $stdoutCapture -and $stdoutCapture.LimitExceeded) -or
            ($null -ne $stderrCapture -and $stderrCapture.LimitExceeded)) {
            $captureIncomplete = $true
            $captureErrors.Add("preflight output exceeded the fixed $($script:CodexJobPreflightStreamMaxBytes)-byte per-stream limit")
        }

        $hasExited = $false
        $exitCode = $null
        try {
            $hasExited = $process.HasExited
            if ($hasExited) { $exitCode = $process.ExitCode }
        } catch {
            $captureErrors.Add("exit status read failed: $($_.Exception.Message)")
        }
        return [pscustomobject]@{
            exit_code = $exitCode
            stdout = $stdout
            stderr = $stderr
            timed_out = ($processTimedOut -or $captureIncomplete)
            process_timed_out = $processTimedOut
            capture_incomplete = $captureIncomplete
            kill_attempted = $killAttempted
            kill_succeeded = $killSucceeded
            process_still_running = (-not $hasExited)
            capture_error = ($captureErrors -join '; ')
        }
    } finally {
        if ($processStarted) {
            if ($null -ne $stdoutTask -and -not $stdoutTask.IsCompleted) {
                try { $process.StandardOutput.Dispose() } catch { }
            }
            if ($null -ne $stderrTask -and -not $stderrTask.IsCompleted) {
                try { $process.StandardError.Dispose() } catch { }
            }
        }
        foreach ($stream in @($stdoutCapture, $stderrCapture, $stdoutBuffer, $stderrBuffer)) {
            if ($null -ne $stream) { try { $stream.Dispose() } catch { } }
        }
        $process.Dispose()
    }
}

function Get-LocalFixedPathExecutableCandidates {
    param([Parameter(Mandatory = $true)][string]$FileName)

    if ([IO.Path]::GetFileName($FileName) -cne $FileName) {
        throw 'PATH candidate filename must be a leaf name.'
    }
    $found = New-Object 'System.Collections.Generic.List[string]'
    foreach ($rawEntry in @([string]$env:PATH -split ';')) {
        if ([string]::IsNullOrWhiteSpace($rawEntry)) { continue }
        $entry = [Environment]::ExpandEnvironmentVariables($rawEntry.Trim().Trim('"'))
        try {
            Assert-LocalFixedDrivePath -Path $entry -Label 'PATH directory'
            $directory = Get-NormalizedPath -Path $entry
            Assert-NoReparseDirectoryAncestors -Path $directory -Label 'PATH directory'
            $candidate = [IO.Path]::Combine($directory, $FileName)
            $null = Assert-NoReparsePathComponents -Path $candidate -Label 'PATH executable candidate' -AllowMissingTail
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $candidate = Get-NormalizedPath -Path $candidate
                if ($candidate -notin @($found)) { $found.Add($candidate) }
            }
        } catch {
            # Relative, UNC, device, mapped-network, missing, and reparse PATH entries are never probed beyond a safe component.
        }
    }
    return @($found.ToArray())
}

function Get-NativeCodexCandidates {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        Assert-LocalFixedDrivePath -Path $RequestedPath -Label 'CodexPath'
        $null = Assert-NoReparsePathComponents -Path $RequestedPath -Label 'CodexPath'
        $resolved = (Resolve-Path -LiteralPath $RequestedPath).Path
        Assert-LocalFixedDrivePath -Path $resolved -Label 'Resolved CodexPath'
        $extension = [IO.Path]::GetExtension($resolved)
        if ($extension -ine '.exe') {
            throw 'CodexPath must point to a native codex.exe; script and .cmd launchers are forbidden.'
        }
        $null = Get-FinalFilePath -Path $resolved
        return @($resolved)
    }

    $found = New-Object 'System.Collections.Generic.List[string]'
    foreach ($candidatePath in @(Get-LocalFixedPathExecutableCandidates -FileName 'codex.exe')) {
        try {
            $resolvedCandidate = (Resolve-Path -LiteralPath $candidatePath).Path
            Assert-LocalFixedDrivePath -Path $resolvedCandidate -Label 'Resolved Codex launcher'
            $null = Get-FinalFilePath -Path $resolvedCandidate
            if (-not $found.Contains($resolvedCandidate)) { $found.Add($resolvedCandidate) }
        } catch {
            # Unsafe PATH candidates are never invoked.
        }
    }
    foreach ($npmShimPath in @(Get-LocalFixedPathExecutableCandidates -FileName 'codex.cmd')) {
        try {
            $npmRoot = [IO.Path]::GetDirectoryName($npmShimPath)
            Assert-NoReparseDirectoryAncestors -Path $npmRoot -Label 'Discovered npm Codex directory'
            $vendorCandidate = [IO.Path]::Combine(
                $npmRoot, 'node_modules', '@openai', 'codex', 'node_modules', '@openai', 'codex-win32-x64',
                'vendor', 'x86_64-pc-windows-msvc', 'bin', 'codex.exe'
            )
            Assert-LocalFixedDrivePath -Path $vendorCandidate -Label 'Discovered npm vendor codex.exe'
            $null = Assert-NoReparsePathComponents -Path $vendorCandidate -Label 'Discovered npm vendor codex.exe' -AllowMissingTail
            if (Test-Path -LiteralPath $vendorCandidate -PathType Leaf) {
                $resolvedVendor = (Resolve-Path -LiteralPath $vendorCandidate).Path
                $null = Get-FinalFilePath -Path $resolvedVendor
                if (-not $found.Contains($resolvedVendor)) { $found.Add($resolvedVendor) }
            }
        } catch {
            # A shim is never executed; unsafe or incomplete npm layouts are skipped.
        }
    }
    if ($found.Count -eq 0) {
        throw 'No native codex.exe launcher found. Pass -CodexPath with an absolute signed codex.exe path.'
    }
    return @($found.ToArray())
}

function Get-GitAdminPathContract {
    param(
        [Parameter(Mandatory = $true)][string]$GitExecutable,
        [Parameter(Mandatory = $true)][string]$RepositoryPath,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ((Get-Sha256Hex -Path $GitExecutable) -ine $ExpectedSha256) { throw 'Git executable changed before admin preflight.' }
    $result = Invoke-NativeCapture -FilePath $GitExecutable -Arguments $Arguments -WorkingDirectory $WorkingDirectory
    if ($result.timed_out) {
        throw "$Label preflight timed out."
    }
    if ($result.exit_code -ne 0) {
        throw "$Label preflight failed: $($result.stderr.Trim())"
    }
    $reported = $result.stdout.Trim()
    if ([string]::IsNullOrWhiteSpace($reported) -or $reported.IndexOfAny(@([char]10, [char]13)) -ge 0) {
        throw "$Label preflight returned an empty or multi-line path."
    }
    Assert-LocalFixedDrivePath -Path $reported -Label "Git-reported $Label"
    $null = Assert-NoReparsePathComponents -Path $reported -Label "Git-reported $Label"
    $resolved = (Resolve-Path -LiteralPath $reported).Path
    Assert-LocalFixedDrivePath -Path $resolved -Label "Resolved $Label"
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) {
        throw "$Label is not a directory: $resolved"
    }
    Assert-NoReparseDirectoryAncestors -Path $resolved -Label $Label
    $canonical = Get-FinalDirectoryPath -Path $resolved
    return [pscustomobject]@{
        path = Get-NormalizedPath -Path $resolved
        canonical_path = $canonical
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
            throw 'The .git directory does not match Git --absolute-git-dir.'
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
    param(
        [Parameter(Mandatory = $true)][psobject]$Expected,
        [Parameter(Mandatory = $true)][string]$RepositoryPath,
        [Parameter(Mandatory = $true)][string]$GitDirectory,
        [Parameter(Mandatory = $true)][string]$GitCommonDirectory
    )

    $current = Get-GitBindingContract -RepositoryPath $RepositoryPath -GitDirectory $GitDirectory -GitCommonDirectory $GitCommonDirectory
    foreach ($property in @(
        'git_marker_path', 'git_marker_kind', 'git_marker_canonical_path', 'git_marker_length_bytes', 'git_marker_sha256',
        'git_commondir_marker_path', 'git_commondir_marker_kind', 'git_commondir_marker_canonical_path',
        'git_commondir_marker_length_bytes', 'git_commondir_marker_sha256'
    )) {
        if ([string]$current.$property -cne [string]$Expected.$property) {
            throw "Git administrative binding changed: $property"
        }
    }
}

function Read-StrictGitMarkerLine {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    Assert-LocalFixedDrivePath -Path $Path -Label $Label
    $null = Assert-NoReparsePathComponents -Path $Path -Label $Label
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
    $item = Get-Item -LiteralPath $Path -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Label must not be a reparse point." }
    if ($item.Length -lt 1 -or $item.Length -gt 4096) { throw "$Label has an invalid byte length." }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $utf8 = New-Object Text.UTF8Encoding($false, $true)
    try { $text = $utf8.GetString($bytes) } catch { throw "$Label is not strict UTF-8." }
    $line = $text.TrimEnd([char]13, [char]10)
    if ([string]::IsNullOrWhiteSpace($line) -or $line.IndexOfAny(@([char]0, [char]10, [char]13)) -ge 0) {
        throw "$Label must contain exactly one non-empty line."
    }
    return $line
}

function Resolve-DeclaredGitDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$DeclaredPath,
        [Parameter(Mandatory = $true)][string]$BaseDirectory,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ([IO.Path]::IsPathRooted($DeclaredPath)) {
        Assert-LocalFixedDrivePath -Path $DeclaredPath -Label $Label
        $candidate = $DeclaredPath
    } else {
        if ($DeclaredPath.IndexOf(':') -ge 0) { throw "$Label relative path contains a forbidden colon." }
        $candidate = [IO.Path]::GetFullPath([IO.Path]::Combine($BaseDirectory, $DeclaredPath))
        Assert-LocalFixedDrivePath -Path $candidate -Label $Label
    }
    $null = Assert-NoReparsePathComponents -Path $candidate -Label $Label
    $resolved = (Resolve-Path -LiteralPath $candidate).Path
    Assert-LocalFixedDrivePath -Path $resolved -Label "Resolved $Label"
    if (-not (Test-Path -LiteralPath $resolved -PathType Container)) { throw "$Label is not a directory." }
    Assert-NoReparseDirectoryAncestors -Path $resolved -Label $Label
    return [pscustomobject]@{
        path = Get-NormalizedPath -Path $resolved
        canonical_path = Get-FinalDirectoryPath -Path $resolved
    }
}

function Get-DeclaredGitAdminContract {
    param([Parameter(Mandatory = $true)][string]$RepositoryPath)

    $markerPath = Join-Path $RepositoryPath '.git'
    Assert-LocalFixedDrivePath -Path $markerPath -Label 'Git marker path'
    $null = Assert-NoReparsePathComponents -Path $markerPath -Label 'Git marker path' -AllowMissingTail
    if (Test-Path -LiteralPath $markerPath -PathType Container) {
        $markerKind = 'directory'
        $gitDirectoryContract = Resolve-DeclaredGitDirectory -DeclaredPath $markerPath -BaseDirectory $RepositoryPath -Label 'Declared Git directory'
    } elseif (Test-Path -LiteralPath $markerPath -PathType Leaf) {
        throw 'Linked Git worktrees are forbidden because Codex hook discovery can consult the primary worktree outside RepoPath.'
    } else {
        throw 'RepoPath has no direct .git marker.'
    }

    $commondirMarker = Join-Path ([string]$gitDirectoryContract.path) 'commondir'
    Assert-LocalFixedDrivePath -Path $commondirMarker -Label 'Git commondir marker path'
    $null = Assert-NoReparsePathComponents -Path $commondirMarker -Label 'Git commondir marker path' -AllowMissingTail
    if (Test-Path -LiteralPath $commondirMarker -PathType Leaf) {
        $commonLine = Read-StrictGitMarkerLine -Path $commondirMarker -Label 'Git commondir marker'
        $commonDirectoryContract = Resolve-DeclaredGitDirectory -DeclaredPath $commonLine `
            -BaseDirectory ([string]$gitDirectoryContract.path) -Label 'Declared Git common directory'
    } elseif (Test-Path -LiteralPath $commondirMarker) {
        throw 'Git commondir marker exists but is not a file.'
    } else {
        $commonDirectoryContract = $gitDirectoryContract
    }

    return [pscustomobject]@{
        git_marker_kind = $markerKind
        git_directory = [string]$gitDirectoryContract.path
        git_directory_canonical_path = [string]$gitDirectoryContract.canonical_path
        git_common_directory = [string]$commonDirectoryContract.path
        git_common_directory_canonical_path = [string]$commonDirectoryContract.canonical_path
    }
}

function Get-TrustedLauncherContract {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label,
        [Parameter(Mandatory = $true)][string[]]$ProtectedDirectories,
        [Parameter(Mandatory = $true)][string]$EvidenceDirectory
    )

    Assert-LocalFixedDrivePath -Path $Path -Label $Label
    $null = Assert-NoReparsePathComponents -Path $Path -Label $Label
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    Assert-LocalFixedDrivePath -Path $resolved -Label "Resolved $Label"
    if ([IO.Path]::GetExtension($resolved) -ine '.exe') { throw "$Label must be a native .exe; script and .cmd launchers are forbidden." }
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "$Label is not a file." }
    $item = Get-Item -LiteralPath $resolved -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Label must not be a reparse point." }
    $launcherDirectory = [IO.Path]::GetDirectoryName($resolved)
    Assert-NoReparseDirectoryAncestors -Path $launcherDirectory -Label "$Label directory"
    $canonical = Get-FinalFilePath -Path $resolved
    $canonicalDirectory = Get-FinalDirectoryPath -Path $launcherDirectory
    if ([IO.Path]::GetDirectoryName($canonical) -ine $canonicalDirectory) { throw "$Label file and directory canonical paths disagree." }

    $allBoundaries = New-Object 'System.Collections.Generic.List[string]'
    foreach ($boundary in @($ProtectedDirectories) + @(Get-LocalFixedTempRoots)) {
        Assert-LocalFixedDrivePath -Path $boundary -Label 'Launcher boundary'
        $normalizedBoundary = Get-NormalizedPath -Path $boundary
        if ($normalizedBoundary -notin @($allBoundaries)) { $allBoundaries.Add($normalizedBoundary) }
    }
    Assert-LocalFixedDrivePath -Path $EvidenceDirectory -Label 'EvidenceDirectory'
    $evidenceNormalized = Get-NormalizedPath -Path $EvidenceDirectory
    if ($evidenceNormalized -notin @($allBoundaries)) { $allBoundaries.Add($evidenceNormalized) }

    foreach ($boundary in $allBoundaries) {
        if (Test-PathsOverlap -First $launcherDirectory -Second $boundary) {
            throw "$Label directory overlaps a repository, Git admin, temp, or evidence boundary: $boundary"
        }
        $boundaryCanonical = if (Test-Path -LiteralPath $boundary -PathType Container) {
            Get-FinalDirectoryPath -Path $boundary
        } else {
            Get-CanonicalPotentialDirectoryPath -Path $boundary
        }
        if (Test-PathsOverlap -First $canonicalDirectory -Second $boundaryCanonical) {
            throw "$Label directory physically overlaps a protected boundary: $boundaryCanonical"
        }
    }

    return [pscustomobject]@{
        path = $canonical
        canonical_path = $canonical
        working_directory = $canonicalDirectory
        sha256 = Get-Sha256Hex -Path $canonical
    }
}

function Get-TrustedCodexHomeContract {
    param(
        [Parameter(Mandatory = $true)][string[]]$ProtectedDirectories,
        [Parameter(Mandatory = $true)][string]$EvidenceDirectory
    )

    $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    Assert-LocalFixedDrivePath -Path $userProfile -Label 'OS user profile'
    Assert-NoReparseDirectoryAncestors -Path $userProfile -Label 'OS user profile'
    $path = [IO.Path]::Combine($userProfile, '.codex')
    Assert-NoReparseDirectoryAncestors -Path $path -Label 'Pinned Codex home'
    $canonical = Get-FinalDirectoryPath -Path $path
    foreach ($boundary in @($ProtectedDirectories) + @(Get-LocalFixedTempRoots) + @($EvidenceDirectory)) {
        Assert-LocalFixedDrivePath -Path $boundary -Label 'Codex home boundary'
        $boundaryNormalized = Get-NormalizedPath -Path $boundary
        if (Test-PathsOverlap -First $path -Second $boundaryNormalized) {
            throw 'Pinned Codex home overlaps a repository, Git admin, temp, or evidence boundary.'
        }
        $boundaryCanonical = if (Test-Path -LiteralPath $boundaryNormalized -PathType Container) {
            Get-FinalDirectoryPath -Path $boundaryNormalized
        } else {
            Get-CanonicalPotentialDirectoryPath -Path $boundaryNormalized
        }
        if (Test-PathsOverlap -First $canonical -Second $boundaryCanonical) {
            throw 'Pinned Codex home physically overlaps a protected boundary.'
        }
    }
    return [pscustomobject]@{
        path = $canonical
        canonical_path = $canonical
        contract = 'os-user-profile-default;ambient-codex-home-forbidden;local-fixed-nonreparse-disjoint'
    }
}

function Get-BoundedAuthenticodeContract {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Label
    )

    $systemPowerShell = Get-TrustedSystemPowerShellContract
    $powerShellPath = [string]$systemPowerShell.path
    $powerShellDirectory = [string]$systemPowerShell.working_directory
    $trustedModuleRoot = [IO.Path]::Combine($powerShellDirectory, 'Modules')
    Assert-NoReparseDirectoryAncestors -Path $trustedModuleRoot -Label 'Authenticode child module directory'
    $trustedModuleRoot = Get-FinalDirectoryPath -Path $trustedModuleRoot
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
$signature = Microsoft.PowerShell.Security\Get-AuthenticodeSignature -LiteralPath $env:AUTHENTICODE_TARGET
if ($null -eq $signature.SignerCertificate) { throw 'No signer certificate.' }
$versionInfo = [Diagnostics.FileVersionInfo]::GetVersionInfo($env:AUTHENTICODE_TARGET)
$result = [pscustomobject]@{
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
}
$result | Microsoft.PowerShell.Utility\ConvertTo-Json -Compress
'@
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($signatureScript))
    $capture = Invoke-NativeCapture -FilePath $powerShellPath `
        -Arguments @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $encodedCommand) `
        -WorkingDirectory $powerShellDirectory -TimeoutSeconds 15 `
        -EnvironmentVariables @{
            AUTHENTICODE_TARGET = $Path
            PSModulePath = $trustedModuleRoot
        }
    if ($capture.timed_out) { throw "$Label Authenticode validation timed out: $($capture.capture_error)" }
    if ($capture.exit_code -ne 0) { throw "$Label Authenticode validation failed: $($capture.stderr.Trim())" }
    try { $contract = $capture.stdout.Trim() | ConvertFrom-Json } catch { throw "$Label Authenticode validation returned invalid JSON." }
    if ([string]$contract.status -ne 'Valid') { throw "$Label Authenticode status is not Valid: $($contract.status)" }
    if ([string]::IsNullOrWhiteSpace([string]$contract.thumbprint)) { throw "$Label signer thumbprint is empty." }
    if ([string]::IsNullOrWhiteSpace([string]$contract.product_version)) { throw "$Label product/file version is empty." }
    return $contract
}

function Get-OpenAICodexSignatureContract {
    param([Parameter(Mandatory = $true)][string]$Path)

    $contract = Get-BoundedAuthenticodeContract -Path $Path -Label 'Codex'
    if ([string]$contract.simple_name -cne 'OpenAI OpCo, LLC' -or
        [string]$contract.subject -notmatch '(?:^|, )O="OpenAI OpCo, LLC"(?:,|$)') {
        throw "Codex signer is not the OpenAI OpCo, LLC allowlist identity: $($contract.subject)"
    }
    return $contract
}

function Get-GitForWindowsSignatureContract {
    param([Parameter(Mandatory = $true)][string]$Path)

    $contract = Get-BoundedAuthenticodeContract -Path $Path -Label 'Git'
    if ([string]$contract.simple_name -cne 'Johannes Schindelin' -or
        [string]$contract.subject -notmatch '(?:^|, )O=Johannes Schindelin(?:,|$)') {
        throw "Git signer is outside the Git for Windows publisher allowlist: $($contract.subject)"
    }
    return $contract
}

$childPowerShellModulePath = Get-FinalDirectoryPath -Path $entryTrustedModuleRoot
$escapedChildPowerShellModulePath = $childPowerShellModulePath.Replace('\', '\\').Replace('"', '\"')
$codexShellPSModulePathOverride = 'shell_environment_policy.set.PSModulePath="' + $escapedChildPowerShellModulePath + '"'

Assert-LocalFixedDrivePath -Path $RepoPath -Label 'RepoPath'
Assert-LocalFixedDrivePath -Path $PromptPath -Label 'PromptPath'
Assert-LocalFixedDrivePath -Path $OutputDirectory -Label 'OutputDirectory'
$null = Assert-NoReparsePathComponents -Path $RepoPath -Label 'RepoPath'
$null = Assert-NoReparsePathComponents -Path $PromptPath -Label 'PromptPath'
$null = Assert-NoReparsePathComponents -Path $OutputDirectory -Label 'OutputDirectory' -AllowMissingTail
if (-not [string]::IsNullOrWhiteSpace($CodexPath)) {
    Assert-LocalFixedDrivePath -Path $CodexPath -Label 'CodexPath'
    $null = Assert-NoReparsePathComponents -Path $CodexPath -Label 'CodexPath'
}

$repo = (Resolve-Path -LiteralPath $RepoPath).Path
$prompt = (Resolve-Path -LiteralPath $PromptPath).Path
Assert-LocalFixedDrivePath -Path $repo -Label 'Resolved RepoPath'
Assert-LocalFixedDrivePath -Path $prompt -Label 'Resolved PromptPath'
$requestedOutputDirectory = Get-NormalizedPath -Path $OutputDirectory

if (-not (Test-Path -LiteralPath $repo -PathType Container)) {
    throw "RepoPath is not a directory: $repo"
}
Assert-NoUntrustedProjectCodexLayer -RepositoryPath $repo
if (-not (Test-Path -LiteralPath $prompt -PathType Leaf)) {
    throw "PromptPath is not a file: $prompt"
}
$promptContract = Get-ValidatedPromptContract -Path $prompt
$promptLengthBytes = [long]$promptContract.length_bytes
$promptSha256 = [string]$promptContract.sha256
$promptHasUtf8Bom = [bool]$promptContract.utf8_bom
$promptCanonicalPath = [string]$promptContract.canonical_path
$promptVolumeSerial = [string]$promptContract.volume_serial
$promptFileId = [string]$promptContract.file_id
$promptLinkCount = [uint32]$promptContract.link_count
$nearestExistingOutputAncestor = Assert-SafeEvidenceDirectory -Path $requestedOutputDirectory -RepositoryPath $repo
$repoCanonicalPath = Get-FinalDirectoryPath -Path $repo
$outputCanonicalPath = Get-CanonicalPotentialDirectoryPath -Path $requestedOutputDirectory
if (Test-Path -LiteralPath $requestedOutputDirectory) {
    if (-not (Test-Path -LiteralPath $requestedOutputDirectory -PathType Container)) {
        throw "OutputDirectory exists but is not a directory: $requestedOutputDirectory"
    }
    $outputDirectoryItem = Get-Item -LiteralPath $requestedOutputDirectory -Force
    if (($outputDirectoryItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "OutputDirectory must not be a reparse point: $requestedOutputDirectory"
    }
}

$declaredGitAdmin = Get-DeclaredGitAdminContract -RepositoryPath $repo
if ([string]$declaredGitAdmin.git_marker_kind -ne 'directory') {
    throw 'Linked Git worktrees are forbidden because Codex hook discovery can consult the primary worktree outside RepoPath.'
}
if ([string]$declaredGitAdmin.git_directory_canonical_path -ine [string]$declaredGitAdmin.git_common_directory_canonical_path) {
    throw 'Split Git common directories are forbidden even when RepoPath has a direct .git directory.'
}
$gitLauncherContract = $null
$gitSignatureContract = $null
$gitCandidateErrors = New-Object 'System.Collections.Generic.List[string]'
foreach ($gitCandidate in @(Get-LocalFixedPathExecutableCandidates -FileName 'git.exe')) {
    try {
        $candidateGitLauncherContract = Get-TrustedLauncherContract -Path $gitCandidate -Label 'Git executable' `
            -ProtectedDirectories @($repo, [string]$declaredGitAdmin.git_directory, [string]$declaredGitAdmin.git_common_directory) `
            -EvidenceDirectory $requestedOutputDirectory
        $candidateGitSignatureContract = Get-GitForWindowsSignatureContract -Path ([string]$candidateGitLauncherContract.path)
        $gitLauncherContract = $candidateGitLauncherContract
        $gitSignatureContract = $candidateGitSignatureContract
        break
    } catch {
        $gitCandidateErrors.Add("${gitCandidate}: $($_.Exception.Message)")
    }
}
if ($null -eq $gitLauncherContract) {
    throw "No trusted native git.exe was found on local fixed PATH entries: $($gitCandidateErrors -join '; ')"
}
$gitExecutable = [string]$gitLauncherContract.path
$gitExecutableCanonicalPath = [string]$gitLauncherContract.canonical_path
$gitExecutableWorkingDirectory = [string]$gitLauncherContract.working_directory
$gitExecutableSha256 = [string]$gitLauncherContract.sha256
$gitSignerSubject = [string]$gitSignatureContract.subject
$gitSignerThumbprint = [string]$gitSignatureContract.thumbprint
$gitProductVersion = [string]$gitSignatureContract.product_version
Set-ObjectProperty -Object $gitLauncherContract -Name 'signer_subject' -Value $gitSignerSubject
Set-ObjectProperty -Object $gitLauncherContract -Name 'signer_thumbprint' -Value $gitSignerThumbprint
Set-ObjectProperty -Object $gitLauncherContract -Name 'product_version' -Value $gitProductVersion
$codexCandidates = @(Get-NativeCodexCandidates -RequestedPath $CodexPath)

$gitConfigPath = [IO.Path]::Combine([string]$declaredGitAdmin.git_directory, 'config')
Assert-LocalFixedDrivePath -Path $gitConfigPath -Label 'Git config path'
$null = Assert-NoReparsePathComponents -Path $gitConfigPath -Label 'Git config path'
$gitConfigPreflightHandle = $null
try {
    # The untrusted repository config is parsed and locked before any unsandboxed
    # `git -C` process can load it. FileShare.Read denies write/delete replacement.
    $gitConfigPreflightHandle = [IO.File]::Open(
        $gitConfigPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $gitConfigContract = Get-SafeGitConfigHandleContract `
        -Stream $gitConfigPreflightHandle -ExpectedPath $gitConfigPath

    if ((Get-Sha256Hex -Path $gitExecutable) -ine $gitExecutableSha256) { throw 'Git executable changed before root preflight.' }
    $gitResult = Invoke-NativeCapture -FilePath $gitExecutable -Arguments @('-C', $repo, 'rev-parse', '--show-toplevel') `
        -WorkingDirectory $gitExecutableWorkingDirectory
    $gitRoot = $gitResult.stdout.Trim()
    if ($gitResult.timed_out) {
        throw 'Git root preflight timed out.'
    }
    if ($gitResult.exit_code -ne 0) {
        throw "Git root preflight failed: $($gitResult.stderr.Trim())"
    }
    Assert-LocalFixedDrivePath -Path $gitRoot -Label 'Git-reported worktree root'
    $gitRootCanonicalPath = Get-FinalDirectoryPath -Path $gitRoot
    if ($gitRootCanonicalPath -ine $repoCanonicalPath) {
        throw "RepoPath must be the exact Git root. expected=$gitRoot actual=$repo"
    }

    $gitDirContract = Get-GitAdminPathContract -GitExecutable $gitExecutable -RepositoryPath $repo `
        -WorkingDirectory $gitExecutableWorkingDirectory -ExpectedSha256 $gitExecutableSha256 `
        -Arguments @('-C', $repo, 'rev-parse', '--absolute-git-dir') -Label 'Git directory'
    $gitCommonDirContract = Get-GitAdminPathContract -GitExecutable $gitExecutable -RepositoryPath $repo `
        -WorkingDirectory $gitExecutableWorkingDirectory -ExpectedSha256 $gitExecutableSha256 `
        -Arguments @('-C', $repo, 'rev-parse', '--path-format=absolute', '--git-common-dir') -Label 'Git common directory'
    $gitDirectory = [string]$gitDirContract.path
    $gitDirectoryCanonicalPath = [string]$gitDirContract.canonical_path
    $gitCommonDirectory = [string]$gitCommonDirContract.path
    $gitCommonDirectoryCanonicalPath = [string]$gitCommonDirContract.canonical_path
    if ($gitDirectoryCanonicalPath -ine [string]$declaredGitAdmin.git_directory_canonical_path -or
        $gitCommonDirectoryCanonicalPath -ine [string]$declaredGitAdmin.git_common_directory_canonical_path) {
        throw 'Bounded Git preflight disagrees with the directly parsed .git/commondir administrative binding.'
    }
    $gitBindingContract = Get-GitBindingContract -RepositoryPath $repo -GitDirectory $gitDirectory -GitCommonDirectory $gitCommonDirectory
} finally {
    if ($null -ne $gitConfigPreflightHandle) { $gitConfigPreflightHandle.Dispose() }
}
Set-ObjectProperty -Object $gitLauncherContract -Name 'git_config_contract' -Value $gitConfigContract
$null = Assert-SafeEvidenceDirectory -Path $requestedOutputDirectory -RepositoryPath $repo `
    -AdditionalProtectedPaths @($gitDirectory, $gitCommonDirectory)
$codexHomeContract = Get-TrustedCodexHomeContract `
    -ProtectedDirectories @($repo, $gitDirectory, $gitCommonDirectory) -EvidenceDirectory $requestedOutputDirectory
$codexHomePath = [string]$codexHomeContract.path
$codexHomeCanonicalPath = [string]$codexHomeContract.canonical_path
$codexHomeStorageContract = [string]$codexHomeContract.contract
Assert-NoCodexHomeDelegationLayer -CodexHomePath $codexHomePath

$codexExecutable = $null
$codexVersion = $null
$codexLauncherContract = $null
$codexSignatureContract = $null
$codexCandidateErrors = New-Object 'System.Collections.Generic.List[string]'
foreach ($candidatePath in $codexCandidates) {
    try {
        $candidateLauncherContract = Get-TrustedLauncherContract -Path $candidatePath -Label 'Codex executable' `
            -ProtectedDirectories @($repo, $gitDirectory, $gitCommonDirectory) -EvidenceDirectory $requestedOutputDirectory
        $candidateSignatureContract = Get-OpenAICodexSignatureContract -Path ([string]$candidateLauncherContract.path)
        if ((Get-Sha256Hex -Path ([string]$candidateLauncherContract.path)) -ine [string]$candidateLauncherContract.sha256) {
            throw 'Codex executable changed before version preflight.'
        }
        # `--version` is the sole Codex subprocess allowed during DryRun/WhatIf;
        # it does not load the Codex config/state graph in the pinned 0.147.0 binary.
        $versionResult = Invoke-NativeCapture -FilePath ([string]$candidateLauncherContract.path) `
            -Arguments @('--version') -WorkingDirectory ([string]$candidateLauncherContract.working_directory) `
            -EnvironmentVariables @{ PSModulePath = $childPowerShellModulePath }
        $candidateVersion = (($versionResult.stdout, $versionResult.stderr) -join [Environment]::NewLine).Trim()
        if (-not $versionResult.timed_out -and $versionResult.exit_code -eq 0 -and -not [string]::IsNullOrWhiteSpace($candidateVersion)) {
            $codexExecutable = [string]$candidateLauncherContract.path
            $codexLauncherContract = $candidateLauncherContract
            $codexSignatureContract = $candidateSignatureContract
            $codexVersion = $candidateVersion
            break
        }
        $candidateExit = if ($versionResult.timed_out) { 'timed out' } else { "exited $($versionResult.exit_code)" }
        $codexCandidateErrors.Add("$candidatePath $candidateExit`: $candidateVersion")
    } catch {
        $codexCandidateErrors.Add("${candidatePath}: $($_.Exception.Message)")
    }
}
if ([string]::IsNullOrWhiteSpace($codexExecutable)) {
    throw "Codex CLI preflight failed for every native launcher: $($codexCandidateErrors -join '; ')"
}
if ([string]$codexVersion -cne $script:CodexJobSupportedVersion) {
    throw "Unsupported Codex CLI version. expected=$($script:CodexJobSupportedVersion) actual=$codexVersion"
}
$codexCanonicalPath = [string]$codexLauncherContract.canonical_path
$codexWorkingDirectory = [string]$codexLauncherContract.working_directory
$codexSha256 = [string]$codexLauncherContract.sha256
$codexSignerSubject = [string]$codexSignatureContract.subject
$codexSignerThumbprint = [string]$codexSignatureContract.thumbprint
$codexProductVersion = [string]$codexSignatureContract.product_version
$featurePreflightArguments = New-Object 'System.Collections.Generic.List[string]'
foreach ($featureArgument in @(
    '-c', $script:CodexJobShellInheritOverride,
    '-c', $script:CodexJobShellDefaultExcludesOverride,
    '-c', $script:CodexJobShellExplicitExcludesOverride,
    '-c', $script:CodexJobShellNoCurrentDirectoryOverride,
    '-c', $script:CodexJobShellPathExtOverride,
    '-c', $codexShellPSModulePathOverride,
    '-c', $script:CodexJobAllowLoginShellOverride,
    '-c', $script:CodexJobShellUseProfileOverride,
    '-c', $script:CodexJobShellGitNoSystemConfigOverride,
    '-c', $script:CodexJobShellGitNoGlobalConfigOverride,
    '-c', $script:CodexJobShellGitNoPromptOverride,
    '-c', $script:CodexJobShellGitNoGcmInteractiveOverride,
    '-c', $script:CodexJobSandboxNoNetworkOverride,
    '-c', $script:CodexJobSandboxNoTempOverride,
    '-c', $script:CodexJobSandboxNoSlashTempOverride,
    '-c', $script:CodexJobModelProviderOverride,
    '-c', $script:CodexJobWebSearchOverride,
    '-c', $script:CodexJobSkillInstructionsOverride,
    '-c', $script:CodexJobBundledSkillsOverride
)) {
    $featurePreflightArguments.Add([string]$featureArgument)
}
foreach ($featureName in $script:CodexJobDisabledFeatures) {
    $featurePreflightArguments.Add('--disable')
    $featurePreflightArguments.Add([string]$featureName)
}
$featurePreflightArguments.Add('features')
$featurePreflightArguments.Add('list')
$featurePreflight = 'pending-actual-launch;DryRun-does-not-load-Codex-config'
$childExecutablePath = Get-TrustedCoreChildPath -AdditionalDirectories @($gitExecutableWorkingDirectory)
$childExecutablePathExt = '.EXE'
$childNoDefaultCurrentDirectory = '1'
Set-ObjectProperty -Object $codexLauncherContract -Name 'codex_home_path' -Value $codexHomePath
Set-ObjectProperty -Object $codexLauncherContract -Name 'codex_home_canonical_path' -Value $codexHomeCanonicalPath
Set-ObjectProperty -Object $codexLauncherContract -Name 'codex_home_contract' -Value $codexHomeStorageContract

if (-not [string]::IsNullOrWhiteSpace($env:CODEX_API_KEY)) {
    $authChannel = 'codex-api-key-environment'
    $authPreflight = 'CODEX_API_KEY auth channel present; auth mode only; value and account identity not logged or proven'
} else {
    $authChannel = 'pinned-codex-home-login-status'
    $authPreflight = 'pending-actual-launch;DryRun-does-not-load-Codex-config;account-identity-not-proven'
}
Set-ObjectProperty -Object $codexLauncherContract -Name 'auth_channel' -Value $authChannel
Set-ObjectProperty -Object $codexLauncherContract -Name 'codex_api_key_environment_approved' -Value ([bool]$AllowCodexApiKeyEnvironment)
Set-ObjectProperty -Object $codexLauncherContract -Name 'child_executable_path' -Value $childExecutablePath
Set-ObjectProperty -Object $codexLauncherContract -Name 'child_executable_pathext' -Value $childExecutablePathExt
Set-ObjectProperty -Object $codexLauncherContract -Name 'child_no_default_current_directory' -Value $childNoDefaultCurrentDirectory
Set-ObjectProperty -Object $codexLauncherContract -Name 'child_powershell_module_path' -Value $childPowerShellModulePath
Set-ObjectProperty -Object $codexLauncherContract -Name 'codex_shell_psmodulepath_override' -Value $codexShellPSModulePathOverride

$startScriptPath = [string]$PSCommandPath
$workerScriptPath = Join-Path $PSScriptRoot 'codex_job_worker.ps1'
Assert-LocalFixedDrivePath -Path $startScriptPath -Label 'Start helper script path'
$null = Assert-NoReparsePathComponents -Path $startScriptPath -Label 'Start helper script path'
Assert-LocalFixedDrivePath -Path $workerScriptPath -Label 'Worker script path'
$null = Assert-NoReparsePathComponents -Path $workerScriptPath -Label 'Worker script path'
if (-not (Test-Path -LiteralPath $startScriptPath -PathType Leaf)) {
    throw "Codex start helper is missing: $startScriptPath"
}
if (-not (Test-Path -LiteralPath $workerScriptPath -PathType Leaf)) {
    throw "Codex job worker is missing: $workerScriptPath"
}
$startScriptPath = (Resolve-Path -LiteralPath $startScriptPath).Path
$workerScriptPath = (Resolve-Path -LiteralPath $workerScriptPath).Path
$protectedScriptBoundaries = @($repo, $gitDirectory, $gitCommonDirectory, $requestedOutputDirectory)
$startScriptDirectoryCanonical = Assert-ScriptDirectoryBoundary `
    -DirectoryPath ([IO.Path]::GetDirectoryName($startScriptPath)) -ProtectedDirectories $protectedScriptBoundaries
$workerScriptDirectoryCanonical = Assert-ScriptDirectoryBoundary `
    -DirectoryPath ([IO.Path]::GetDirectoryName($workerScriptPath)) -ProtectedDirectories $protectedScriptBoundaries
if ($startScriptDirectoryCanonical -ine $workerScriptDirectoryCanonical) {
    throw 'Start and worker helper scripts must share one trusted physical scripts directory.'
}
$startScriptContract = Get-ScriptFileContract -Path $startScriptPath -Label 'Start helper script'
$workerScriptHandle = $null
$gitConfigJobHandle = $null
try {
    # FileShare.Read forbids write/delete replacement until the worker has loaded,
    # self-verified, and published its handshake metadata.
    $workerScriptHandle = [IO.File]::Open(
        $workerScriptPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $workerScriptContract = Get-OpenScriptHandleContract -Stream $workerScriptHandle -Label 'Worker helper script'
    $gitConfigJobHandle = [IO.File]::Open(
        [string]$gitConfigContract.path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    Assert-SafeGitConfigHandleContract -Stream $gitConfigJobHandle -Expected $gitConfigContract
    Set-ObjectProperty -Object $codexLauncherContract -Name 'start_script_contract' -Value $startScriptContract
    Set-ObjectProperty -Object $codexLauncherContract -Name 'worker_script_contract' -Value $workerScriptContract

$workerHostContract = Get-TrustedSystemPowerShellContract
$windowsPowerShell = [string]$workerHostContract.path
$workerWorkingDirectory = [string]$workerHostContract.working_directory
$workerHostSha256 = [string]$workerHostContract.sha256
$workerHostSignerSubject = [string]$workerHostContract.signer_subject
$workerHostSignerThumbprint = [string]$workerHostContract.signer_thumbprint

$jobId = '{0}-{1}' -f (Get-Date -Format 'yyyyMMddTHHmmssfff'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$stdoutPath = Join-Path $requestedOutputDirectory "$jobId.stdout.jsonl"
$stderrPath = Join-Path $requestedOutputDirectory "$jobId.stderr.log"
$metadataPath = Join-Path $requestedOutputDirectory "$jobId.job.json"
$disabledFeatureArguments = New-Object 'System.Collections.Generic.List[string]'
foreach ($featureName in $script:CodexJobDisabledFeatures) {
    $disabledFeatureArguments.Add('--disable')
    $disabledFeatureArguments.Add([string]$featureName)
}
$codexArguments = @(
    "--ask-for-approval=$ApprovalPolicy",
    'exec'
) + @($disabledFeatureArguments.ToArray()) + @(
    '--ignore-user-config',
    '--ignore-rules',
    '--strict-config',
    '--ephemeral',
    '--json',
    "--model=$Model",
    '-c',
    "model_reasoning_effort=$ReasoningEffort",
    '-c',
    $script:CodexJobShellInheritOverride,
    '-c',
    $script:CodexJobShellDefaultExcludesOverride,
    '-c',
    $script:CodexJobShellExplicitExcludesOverride,
    '-c',
    $script:CodexJobShellNoCurrentDirectoryOverride,
    '-c',
    $script:CodexJobShellPathExtOverride,
    '-c',
    $codexShellPSModulePathOverride,
    '-c',
    $script:CodexJobAllowLoginShellOverride,
    '-c',
    $script:CodexJobShellUseProfileOverride,
    '-c',
    $script:CodexJobShellGitNoSystemConfigOverride,
    '-c',
    $script:CodexJobShellGitNoGlobalConfigOverride,
    '-c',
    $script:CodexJobShellGitNoPromptOverride,
    '-c',
    $script:CodexJobShellGitNoGcmInteractiveOverride,
    '-c',
    $script:CodexJobSandboxNoNetworkOverride,
    '-c',
    $script:CodexJobSandboxNoTempOverride,
    '-c',
    $script:CodexJobSandboxNoSlashTempOverride,
    '-c',
    $script:CodexJobModelProviderOverride,
    '-c',
    $script:CodexJobWebSearchOverride,
    '-c',
    $script:CodexJobSkillInstructionsOverride,
    '-c',
    $script:CodexJobBundledSkillsOverride,
    "--sandbox=$Sandbox",
    '-C',
    $repo,
    '-'
)
$codexSandboxContract = if ($Sandbox -ceq 'read-only') {
    'read-only;workspace-write-network-and-temp-overrides-not-applicable'
} else {
    'workspace-write;network-and-temp-roots-disabled'
}
$codexConfigurationContract = 'strict-config;openai-provider;ignore-user-config;ignore-user-and-project-rules;project-config-and-hooks-absent;codex-home-config-and-instructions-absent;linked-worktrees-forbidden;web-search-disabled;skill-instructions-disabled;workspace-write-network-and-temp-roots-disabled-when-applicable;optional-surfaces-disabled-and-preflighted'

$plan = [pscustomobject]@{
    ok = $true
    dry_run = [bool]$DryRun
    metadata_schema_version = 3
    job_id = $jobId
    repo_path = $repo
    prompt_path = $prompt
    prompt_length_bytes = $promptLengthBytes
    prompt_max_bytes = $script:CodexJobPromptMaxBytes
    prompt_sha256 = $promptSha256
    prompt_encoding = 'utf-8'
    prompt_utf8_bom = $promptHasUtf8Bom
    prompt_canonical_path = $promptCanonicalPath
    prompt_volume_serial = $promptVolumeSerial
    prompt_file_id = $promptFileId
    prompt_link_count = $promptLinkCount
    prompt_contract = 'strict-utf8;single-hard-link;handle-identity-bound;max-8388608-bytes'
    codex_path = $codexExecutable
    codex_canonical_path = $codexCanonicalPath
    codex_working_directory = $codexWorkingDirectory
    codex_sha256 = $codexSha256
    codex_authenticode_status = 'Valid'
    codex_signer_subject = $codexSignerSubject
    codex_signer_thumbprint = $codexSignerThumbprint
    codex_product_version = $codexProductVersion
    codex_home_path = $codexHomePath
    codex_home_canonical_path = $codexHomeCanonicalPath
    codex_home_contract = $codexHomeStorageContract
    codex_version = $codexVersion
    codex_supported_version_contract = 'exact-codex-cli-0.147.0'
    codex_model_provider_override = $script:CodexJobModelProviderOverride
    codex_sandbox_contract = $codexSandboxContract
    codex_arguments = $codexArguments
    codex_disabled_features = @($script:CodexJobDisabledFeatures)
    codex_web_search_override = $script:CodexJobWebSearchOverride
    codex_feature_preflight = $featurePreflight
    codex_optional_surface_contract = 'fixed-disable-list;actual-only-bounded-features-list-after-owner-authorization;web-search-and-skill-instructions-disabled;no-app-plugin-memory-hook-mcp-browser-multi-agent-unified-exec-or-shell-snapshot-surfaces'
    auth_preflight = $authPreflight
    auth_channel = $authChannel
    auth_identity_contract = 'auth-mode-only;owner-must-independently-confirm-account-and-billing-identity'
    codex_api_key_environment_approved = [bool]$AllowCodexApiKeyEnvironment
    child_executable_path = $childExecutablePath
    child_executable_pathext = $childExecutablePathExt
    child_no_default_current_directory = $childNoDefaultCurrentDirectory
    child_powershell_module_path = $childPowerShellModulePath
    codex_shell_psmodulepath_override = $codexShellPSModulePathOverride
    model = $Model
    reasoning_effort = $ReasoningEffort
    sandbox = $Sandbox
    approval_policy = $ApprovalPolicy
    stdin_mode = 'byte-preserving-prompt-file-to-codex-exec-dash'
    stdout_path = $stdoutPath
    stderr_path = $stderrPath
    stdout_max_bytes = $script:CodexJobEvidenceStreamMaxBytes
    stderr_max_bytes = $script:CodexJobEvidenceStreamMaxBytes
    evidence_stream_contract = 'bounded-67108864-bytes-per-stream;overflow-drained-and-job-failed'
    metadata_path = $metadataPath
    output_directory = $requestedOutputDirectory
    nearest_existing_output_ancestor = $nearestExistingOutputAncestor
    evidence_boundary = 'local-fixed-disjoint-from-repo-git-admin-temp-and-reparse-ancestors'
    storage_contract = 'local-ready-fixed-drives-only'
    filesystem_read_boundary = 'full-local-filesystem-on-Windows-legacy-sandbox'
    windows_account_read_exposure_approved = [bool]$AllowWindowsAccountReadExposure
    filesystem_read_authority_contract = 'explicit-owner-approval-required-before-worker-launch'
    network_environment_contract = 'fail-closed-known-egress-and-auth-overrides;positive-allowlist-child-environment;secret-shaped-ambient-fail-closed;rust-overrides-denied'
    shell_environment_contract = 'positive-core-process-environment;pinned-signed-git-path;no-current-directory-resolution;exe-only-pathext;pinned-system-powershell-modules;shell-inherit-core;login-shell-disabled;profile-disabled;default-secret-excludes-enabled;codex-api-key-explicitly-excluded'
    git_environment_contract = 'no-system-or-global-config;no-terminal-prompt;gcm-noninteractive;local-config-bounded-safe-allowlist-and-locked'
    preflight_capture_contract = 'bounded-1048576-bytes-per-stream;overflow-fail-closed'
    codex_configuration_contract = $codexConfigurationContract
    repo_canonical_path = $repoCanonicalPath
    git_directory = $gitDirectory
    git_directory_canonical_path = $gitDirectoryCanonicalPath
    git_common_directory = $gitCommonDirectory
    git_common_directory_canonical_path = $gitCommonDirectoryCanonicalPath
    git_marker_path = $gitBindingContract.git_marker_path
    git_marker_kind = $gitBindingContract.git_marker_kind
    git_marker_canonical_path = $gitBindingContract.git_marker_canonical_path
    git_marker_length_bytes = $gitBindingContract.git_marker_length_bytes
    git_marker_sha256 = $gitBindingContract.git_marker_sha256
    git_commondir_marker_path = $gitBindingContract.git_commondir_marker_path
    git_commondir_marker_kind = $gitBindingContract.git_commondir_marker_kind
    git_commondir_marker_canonical_path = $gitBindingContract.git_commondir_marker_canonical_path
    git_commondir_marker_length_bytes = $gitBindingContract.git_commondir_marker_length_bytes
    git_commondir_marker_sha256 = $gitBindingContract.git_commondir_marker_sha256
    git_executable_path = $gitExecutable
    git_executable_canonical_path = $gitExecutableCanonicalPath
    git_executable_working_directory = $gitExecutableWorkingDirectory
    git_executable_sha256 = $gitExecutableSha256
    git_authenticode_status = 'Valid'
    git_signer_subject = $gitSignerSubject
    git_signer_thumbprint = $gitSignerThumbprint
    git_product_version = $gitProductVersion
    git_config_path = [string]$gitConfigContract.path
    git_config_canonical_path = [string]$gitConfigContract.canonical_path
    git_config_volume_serial = [string]$gitConfigContract.volume_serial
    git_config_file_id = [string]$gitConfigContract.file_id
    git_config_link_count = [uint32]$gitConfigContract.link_count
    git_config_length_bytes = [long]$gitConfigContract.length_bytes
    git_config_sha256 = [string]$gitConfigContract.sha256
    git_config_contract = [string]$gitConfigContract.contract
    output_canonical_path = $outputCanonicalPath
    path_canonicalization = 'GetFinalPathNameByHandleW'
    start_script_path = [string]$startScriptContract.path
    start_script_canonical_path = [string]$startScriptContract.canonical_path
    start_script_volume_serial = [string]$startScriptContract.volume_serial
    start_script_file_id = [string]$startScriptContract.file_id
    start_script_link_count = [uint32]$startScriptContract.link_count
    start_script_length_bytes = [long]$startScriptContract.length_bytes
    start_script_sha256 = [string]$startScriptContract.sha256
    worker_script_path = [string]$workerScriptContract.path
    worker_script_canonical_path = [string]$workerScriptContract.canonical_path
    worker_script_volume_serial = [string]$workerScriptContract.volume_serial
    worker_script_file_id = [string]$workerScriptContract.file_id
    worker_script_link_count = [uint32]$workerScriptContract.link_count
    worker_script_length_bytes = [long]$workerScriptContract.length_bytes
    worker_script_sha256 = [string]$workerScriptContract.sha256
    script_integrity_contract = 'local-fixed-nonreparse-disjoint;single-hard-link;handle-identity-and-sha256;worker-read-locked-through-handshake'
    worker_host_path = $windowsPowerShell
    worker_working_directory = $workerWorkingDirectory
    worker_host_sha256 = $workerHostSha256
    worker_host_signer_subject = $workerHostSignerSubject
    worker_host_signer_thumbprint = $workerHostSignerThumbprint
    entry_powershell_contract = 'exact-os-system-WindowsPowerShell;pinned-PSHOME-modules;critical-first-resolved-builtin-cmdlets;fresh-NoProfile-NonInteractive-owner-entry'
    wait = [bool]$Wait
    timeout_seconds = $TimeoutSeconds
}

if ($DryRun -or -not $PSCmdlet.ShouldProcess($repo, "Start Codex job $jobId")) {
    $plan
    return
}
if (-not $AllowWindowsAccountReadExposure) {
    throw 'Delegated Codex on the Windows legacy sandbox can read the full local filesystem visible to this OS account. Actual launch requires explicit owner approval via -AllowWindowsAccountReadExposure; use a dedicated secret-free account or VM when that exposure is unacceptable.'
}

if ((Get-Sha256Hex -Path $codexExecutable) -ine $codexSha256) {
    throw 'Codex executable changed before actual-only feature/auth preflight.'
}
Assert-NoCodexHomeDelegationLayer -CodexHomePath $codexHomePath
$featureResult = Invoke-NativeCapture -FilePath $codexExecutable `
    -Arguments @($featurePreflightArguments.ToArray()) -WorkingDirectory $codexWorkingDirectory `
    -EnvironmentVariables @{ CODEX_HOME = $codexHomePath; PSModulePath = $childPowerShellModulePath }
if ($featureResult.timed_out) {
    throw "Codex feature contract preflight timed out or exceeded its output cap: $($featureResult.capture_error)"
}
if ($featureResult.exit_code -ne 0) {
    throw "Codex feature contract preflight failed: $($featureResult.stderr.Trim())"
}
if (-not [string]::IsNullOrWhiteSpace([string]$featureResult.stderr)) {
    throw "Codex feature/config contract preflight emitted an unexpected warning: $($featureResult.stderr.Trim())"
}
foreach ($featureName in $script:CodexJobDisabledFeatures) {
    $listedFeatureName = if ($featureName -ceq 'codex_hooks') { 'hooks' } else { $featureName }
    if ([string]$featureResult.stdout -notmatch "(?m)^$([regex]::Escape($listedFeatureName))\s+.*\s+false\s*$") {
        throw "Required Codex feature is unavailable or was not disabled by this CLI version: $featureName"
    }
}
$featurePreflight = 'passed-bounded-features-list-after-owner-authorization'

if ($authChannel -eq 'pinned-codex-home-login-status') {
    Assert-NoCodexHomeDelegationLayer -CodexHomePath $codexHomePath
    $authResult = Invoke-NativeCapture -FilePath $codexExecutable -Arguments @('login', 'status') `
        -WorkingDirectory $codexWorkingDirectory `
        -EnvironmentVariables @{ CODEX_HOME = $codexHomePath; PSModulePath = $childPowerShellModulePath }
    $authOutput = (($authResult.stdout, $authResult.stderr) -join [Environment]::NewLine).Trim()
    if ($authResult.timed_out) { throw 'Codex authentication preflight timed out.' }
    if ($authResult.exit_code -ne 0) { throw "Codex authentication preflight failed: $authOutput" }
    $authPreflight = if ([string]::IsNullOrWhiteSpace($authOutput)) {
        'Codex login status exited 0 with no output; auth mode only; account identity not proven'
    } else {
        "Auth mode preflight only (account/billing identity not proven): $authOutput"
    }
}

if (-not (Test-Path -LiteralPath $requestedOutputDirectory)) {
    $null = New-Item -ItemType Directory -Path $requestedOutputDirectory -Force
}
$outputDirectory = (Resolve-Path -LiteralPath $requestedOutputDirectory).Path
$null = Assert-SafeEvidenceDirectory -Path $outputDirectory -RepositoryPath $repo `
    -AdditionalProtectedPaths @($gitDirectory, $gitCommonDirectory)
$createdOutputCanonicalPath = Get-FinalDirectoryPath -Path $outputDirectory
if ($createdOutputCanonicalPath -ine $outputCanonicalPath) {
    throw "OutputDirectory canonical target changed during creation. expected=$outputCanonicalPath actual=$createdOutputCanonicalPath"
}

$stdoutPath = Join-Path $outputDirectory "$jobId.stdout.jsonl"
$stderrPath = Join-Path $outputDirectory "$jobId.stderr.log"
$metadataPath = Join-Path $outputDirectory "$jobId.job.json"
foreach ($path in @($stdoutPath, $stderrPath, $metadataPath)) {
    if (Test-Path -LiteralPath $path) {
        throw "Refusing to overwrite an existing job artifact: $path"
    }
}

$metadata = [pscustomobject]@{
    metadata_schema_version = 3
    ok = $true
    state = 'starting'
    job_id = $jobId
    pid = $null
    started_at_utc = $null
    completed_at_utc = $null
    timed_out_at_utc = $null
    timeout_exceeded = $false
    exit_code = $null
    error = $null
    repo_path = $repo
    prompt_path = $prompt
    prompt_length_bytes = $promptLengthBytes
    prompt_max_bytes = $script:CodexJobPromptMaxBytes
    prompt_sha256 = $promptSha256
    prompt_encoding = 'utf-8'
    prompt_utf8_bom = $promptHasUtf8Bom
    prompt_canonical_path = $promptCanonicalPath
    prompt_volume_serial = $promptVolumeSerial
    prompt_file_id = $promptFileId
    prompt_link_count = $promptLinkCount
    prompt_contract = 'strict-utf8;single-hard-link;handle-identity-bound;max-8388608-bytes'
    codex_path = $codexExecutable
    codex_canonical_path = $codexCanonicalPath
    codex_working_directory = $codexWorkingDirectory
    codex_sha256 = $codexSha256
    codex_authenticode_status = 'Valid'
    codex_signer_subject = $codexSignerSubject
    codex_signer_thumbprint = $codexSignerThumbprint
    codex_product_version = $codexProductVersion
    codex_home_path = $codexHomePath
    codex_home_canonical_path = $codexHomeCanonicalPath
    codex_home_contract = $codexHomeStorageContract
    codex_version = $codexVersion
    codex_supported_version_contract = 'exact-codex-cli-0.147.0'
    codex_model_provider_override = $script:CodexJobModelProviderOverride
    codex_sandbox_contract = $codexSandboxContract
    codex_arguments = $codexArguments
    codex_disabled_features = @($script:CodexJobDisabledFeatures)
    codex_web_search_override = $script:CodexJobWebSearchOverride
    codex_feature_preflight = $featurePreflight
    codex_optional_surface_contract = 'fixed-disable-list;actual-only-bounded-features-list-after-owner-authorization;web-search-and-skill-instructions-disabled;no-app-plugin-memory-hook-mcp-browser-multi-agent-unified-exec-or-shell-snapshot-surfaces'
    codex_launcher_kind = [IO.Path]::GetExtension($codexExecutable).TrimStart('.').ToLowerInvariant()
    codex_pid = $null
    codex_started_at_utc = $null
    codex_process_path = $null
    launcher_pid = $null
    launcher_started_at_utc = $null
    launcher_process_path = $null
    launcher_pid_semantics = 'Native codex.exe PID; the worker waits this process directly.'
    auth_preflight = $authPreflight
    auth_channel = $authChannel
    auth_identity_contract = 'auth-mode-only;owner-must-independently-confirm-account-and-billing-identity'
    codex_api_key_environment_approved = [bool]$AllowCodexApiKeyEnvironment
    child_executable_path = $childExecutablePath
    child_executable_pathext = $childExecutablePathExt
    child_no_default_current_directory = $childNoDefaultCurrentDirectory
    child_powershell_module_path = $childPowerShellModulePath
    codex_shell_psmodulepath_override = $codexShellPSModulePathOverride
    model = $Model
    reasoning_effort = $ReasoningEffort
    sandbox = $Sandbox
    approval_policy = $ApprovalPolicy
    stdin_mode = 'byte-preserving-prompt-file-to-codex-exec-dash'
    stdout_path = $stdoutPath
    stderr_path = $stderrPath
    stdout_max_bytes = $script:CodexJobEvidenceStreamMaxBytes
    stderr_max_bytes = $script:CodexJobEvidenceStreamMaxBytes
    evidence_stream_contract = 'bounded-67108864-bytes-per-stream;overflow-drained-and-job-failed'
    stdout_bytes_captured = 0
    stderr_bytes_captured = 0
    stdout_output_limit_exceeded = $false
    stderr_output_limit_exceeded = $false
    output_limit_exceeded = $false
    metadata_path = $metadataPath
    output_directory = $outputDirectory
    nearest_existing_output_ancestor = $nearestExistingOutputAncestor
    evidence_boundary = 'local-fixed-disjoint-from-repo-git-admin-temp-and-reparse-ancestors'
    storage_contract = 'local-ready-fixed-drives-only'
    filesystem_read_boundary = 'full-local-filesystem-on-Windows-legacy-sandbox'
    windows_account_read_exposure_approved = [bool]$AllowWindowsAccountReadExposure
    filesystem_read_authority_contract = 'explicit-owner-approval-required-before-worker-launch'
    network_environment_contract = 'fail-closed-known-egress-and-auth-overrides;positive-allowlist-child-environment;secret-shaped-ambient-fail-closed;rust-overrides-denied'
    shell_environment_contract = 'positive-core-process-environment;pinned-signed-git-path;no-current-directory-resolution;exe-only-pathext;pinned-system-powershell-modules;shell-inherit-core;login-shell-disabled;profile-disabled;default-secret-excludes-enabled;codex-api-key-explicitly-excluded'
    git_environment_contract = 'no-system-or-global-config;no-terminal-prompt;gcm-noninteractive;local-config-bounded-safe-allowlist-and-locked'
    preflight_capture_contract = 'bounded-1048576-bytes-per-stream;overflow-fail-closed'
    codex_configuration_contract = $codexConfigurationContract
    repo_canonical_path = $repoCanonicalPath
    git_directory = $gitDirectory
    git_directory_canonical_path = $gitDirectoryCanonicalPath
    git_common_directory = $gitCommonDirectory
    git_common_directory_canonical_path = $gitCommonDirectoryCanonicalPath
    git_marker_path = $gitBindingContract.git_marker_path
    git_marker_kind = $gitBindingContract.git_marker_kind
    git_marker_canonical_path = $gitBindingContract.git_marker_canonical_path
    git_marker_length_bytes = $gitBindingContract.git_marker_length_bytes
    git_marker_sha256 = $gitBindingContract.git_marker_sha256
    git_commondir_marker_path = $gitBindingContract.git_commondir_marker_path
    git_commondir_marker_kind = $gitBindingContract.git_commondir_marker_kind
    git_commondir_marker_canonical_path = $gitBindingContract.git_commondir_marker_canonical_path
    git_commondir_marker_length_bytes = $gitBindingContract.git_commondir_marker_length_bytes
    git_commondir_marker_sha256 = $gitBindingContract.git_commondir_marker_sha256
    git_executable_path = $gitExecutable
    git_executable_canonical_path = $gitExecutableCanonicalPath
    git_executable_working_directory = $gitExecutableWorkingDirectory
    git_executable_sha256 = $gitExecutableSha256
    git_authenticode_status = 'Valid'
    git_signer_subject = $gitSignerSubject
    git_signer_thumbprint = $gitSignerThumbprint
    git_product_version = $gitProductVersion
    git_config_path = [string]$gitConfigContract.path
    git_config_canonical_path = [string]$gitConfigContract.canonical_path
    git_config_volume_serial = [string]$gitConfigContract.volume_serial
    git_config_file_id = [string]$gitConfigContract.file_id
    git_config_link_count = [uint32]$gitConfigContract.link_count
    git_config_length_bytes = [long]$gitConfigContract.length_bytes
    git_config_sha256 = [string]$gitConfigContract.sha256
    git_config_contract = [string]$gitConfigContract.contract
    output_canonical_path = $createdOutputCanonicalPath
    path_canonicalization = 'GetFinalPathNameByHandleW'
    start_script_path = [string]$startScriptContract.path
    start_script_canonical_path = [string]$startScriptContract.canonical_path
    start_script_volume_serial = [string]$startScriptContract.volume_serial
    start_script_file_id = [string]$startScriptContract.file_id
    start_script_link_count = [uint32]$startScriptContract.link_count
    start_script_length_bytes = [long]$startScriptContract.length_bytes
    start_script_sha256 = [string]$startScriptContract.sha256
    worker_script_path = [string]$workerScriptContract.path
    worker_script_canonical_path = [string]$workerScriptContract.canonical_path
    worker_script_volume_serial = [string]$workerScriptContract.volume_serial
    worker_script_file_id = [string]$workerScriptContract.file_id
    worker_script_link_count = [uint32]$workerScriptContract.link_count
    worker_script_length_bytes = [long]$workerScriptContract.length_bytes
    worker_script_sha256 = [string]$workerScriptContract.sha256
    script_integrity_contract = 'local-fixed-nonreparse-disjoint;single-hard-link;handle-identity-and-sha256;worker-read-locked-through-handshake'
    worker_host_path = $windowsPowerShell
    worker_working_directory = $workerWorkingDirectory
    worker_host_sha256 = $workerHostSha256
    worker_host_signer_subject = $workerHostSignerSubject
    worker_host_signer_thumbprint = $workerHostSignerThumbprint
    entry_powershell_contract = 'exact-os-system-WindowsPowerShell;pinned-PSHOME-modules;critical-first-resolved-builtin-cmdlets;fresh-NoProfile-NonInteractive-owner-entry'
    worker_recovery_left_live_launcher = $false
    worker_pid = $null
    worker_started_at_utc = $null
    worker_process_path = $null
    worker_exit_code = $null
    timeout_seconds = $TimeoutSeconds
    created_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    updated_at_utc = $null
}
Write-JobMetadata -Path $metadataPath -Value $metadata

$workerProcess = $null
try {
    if ((Get-Sha256Hex -Path $gitExecutable) -ine $gitExecutableSha256) { throw 'Git executable changed before worker launch.' }
    if ((Get-Sha256Hex -Path $codexExecutable) -ine $codexSha256) { throw 'Codex executable changed before worker launch.' }
    $currentWorkerHostContract = Get-TrustedSystemPowerShellContract
    if ([string]$currentWorkerHostContract.sha256 -ine $workerHostSha256 -or
        [string]$currentWorkerHostContract.signer_thumbprint -ine $workerHostSignerThumbprint) {
        throw 'System PowerShell worker host changed before launch.'
    }
    Assert-GitBindingUnchanged -Expected $gitBindingContract -RepositoryPath $repo `
        -GitDirectory $gitDirectory -GitCommonDirectory $gitCommonDirectory
    $workerArgumentList = @(
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $workerScriptPath,
        '-MetadataPath',
        $metadataPath
    )
    $workerArgumentText = (($workerArgumentList | ForEach-Object { Quote-NativeArgument -Value $_ }) -join ' ')
    $savedProcessTemp = $env:TEMP
    $savedProcessTmp = $env:TMP
    $savedProcessSystemRoot = $env:SystemRoot
    $savedProcessWindir = $env:WINDIR
    $savedProcessComSpec = $env:ComSpec
    $savedProcessCodexHome = $env:CODEX_HOME
    $savedProcessPath = $env:PATH
    $savedProcessPathExt = $env:PATHEXT
    $savedNoDefaultCurrentDirectory = $env:NoDefaultCurrentDirectoryInExePath
    $savedGitConfigNoSystem = $env:GIT_CONFIG_NOSYSTEM
    $savedGitConfigGlobal = $env:GIT_CONFIG_GLOBAL
    $savedGitTerminalPrompt = $env:GIT_TERMINAL_PROMPT
    $savedGcmInteractive = $env:GCM_INTERACTIVE
    $approvedCodexApiKey = $(if ($authChannel -eq 'codex-api-key-environment') { [string]$env:CODEX_API_KEY } else { $null })
    $savedBlockedEnvironment = @{}
    try {
        $workerChildTemp = Get-TrustedChildTempDirectory
        $workerWindowsDirectory = Get-TrustedWindowsDirectory
        $env:TEMP = $workerChildTemp
        $env:TMP = $workerChildTemp
        $env:SystemRoot = $workerWindowsDirectory
        $env:WINDIR = $workerWindowsDirectory
        $env:ComSpec = [IO.Path]::Combine($workerWindowsDirectory, 'System32', 'cmd.exe')
        foreach ($entry in @(Get-ChildItem Env:)) {
            if (-not (Test-CoreChildEnvironmentName -Name ([string]$entry.Name))) {
                $savedBlockedEnvironment[$entry.Name] = [string]$entry.Value
                [Environment]::SetEnvironmentVariable($entry.Name, $null, 'Process')
            }
        }
        $env:PATH = $childExecutablePath
        $env:PATHEXT = $childExecutablePathExt
        $env:NoDefaultCurrentDirectoryInExePath = $childNoDefaultCurrentDirectory
        $env:PSModulePath = $childPowerShellModulePath
        $env:GIT_CONFIG_NOSYSTEM = '1'
        $env:GIT_CONFIG_GLOBAL = 'NUL'
        $env:GIT_TERMINAL_PROMPT = '0'
        $env:GCM_INTERACTIVE = 'Never'
        $env:CODEX_HOME = $codexHomePath
        if ($authChannel -eq 'codex-api-key-environment') {
            $env:CODEX_API_KEY = $approvedCodexApiKey
        }
        $workerProcess = Start-Process -FilePath $windowsPowerShell `
            -ArgumentList $workerArgumentText `
            -WorkingDirectory $workerWorkingDirectory `
            -WindowStyle Hidden `
            -PassThru
    } finally {
        if ($null -eq $savedProcessTemp) { Remove-Item Env:TEMP -ErrorAction SilentlyContinue } else { $env:TEMP = $savedProcessTemp }
        if ($null -eq $savedProcessTmp) { Remove-Item Env:TMP -ErrorAction SilentlyContinue } else { $env:TMP = $savedProcessTmp }
        if ($null -eq $savedProcessSystemRoot) { Remove-Item Env:SystemRoot -ErrorAction SilentlyContinue } else { $env:SystemRoot = $savedProcessSystemRoot }
        if ($null -eq $savedProcessWindir) { Remove-Item Env:WINDIR -ErrorAction SilentlyContinue } else { $env:WINDIR = $savedProcessWindir }
        if ($null -eq $savedProcessComSpec) { Remove-Item Env:ComSpec -ErrorAction SilentlyContinue } else { $env:ComSpec = $savedProcessComSpec }
        if ($null -eq $savedProcessCodexHome) { Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue } else { $env:CODEX_HOME = $savedProcessCodexHome }
        if ($null -eq $savedProcessPath) { Remove-Item Env:PATH -ErrorAction SilentlyContinue } else { $env:PATH = $savedProcessPath }
        if ($null -eq $savedProcessPathExt) { Remove-Item Env:PATHEXT -ErrorAction SilentlyContinue } else { $env:PATHEXT = $savedProcessPathExt }
        if ($null -eq $savedNoDefaultCurrentDirectory) { Remove-Item Env:NoDefaultCurrentDirectoryInExePath -ErrorAction SilentlyContinue } else { $env:NoDefaultCurrentDirectoryInExePath = $savedNoDefaultCurrentDirectory }
        if ($null -eq $savedGitConfigNoSystem) { Remove-Item Env:GIT_CONFIG_NOSYSTEM -ErrorAction SilentlyContinue } else { $env:GIT_CONFIG_NOSYSTEM = $savedGitConfigNoSystem }
        if ($null -eq $savedGitConfigGlobal) { Remove-Item Env:GIT_CONFIG_GLOBAL -ErrorAction SilentlyContinue } else { $env:GIT_CONFIG_GLOBAL = $savedGitConfigGlobal }
        if ($null -eq $savedGitTerminalPrompt) { Remove-Item Env:GIT_TERMINAL_PROMPT -ErrorAction SilentlyContinue } else { $env:GIT_TERMINAL_PROMPT = $savedGitTerminalPrompt }
        if ($null -eq $savedGcmInteractive) { Remove-Item Env:GCM_INTERACTIVE -ErrorAction SilentlyContinue } else { $env:GCM_INTERACTIVE = $savedGcmInteractive }
        foreach ($savedName in @($savedBlockedEnvironment.Keys)) {
            [Environment]::SetEnvironmentVariable([string]$savedName, [string]$savedBlockedEnvironment[$savedName], 'Process')
        }
    }
} catch {
    Set-ObjectProperty -Object $metadata -Name 'ok' -Value $false
    Set-ObjectProperty -Object $metadata -Name 'state' -Value 'failed'
    Set-ObjectProperty -Object $metadata -Name 'error' -Value ("Worker launch failed: {0}" -f $_.Exception.Message)
    Set-ObjectProperty -Object $metadata -Name 'completed_at_utc' -Value ((Get-Date).ToUniversalTime().ToString('o'))
    Write-JobMetadata -Path $metadataPath -Value $metadata
    throw "Codex worker launch failed. metadata=$metadataPath error=$($_.Exception.Message)"
}

$workerProcess.Refresh()
$expectedWorkerPid = $workerProcess.Id
$expectedWorkerStartedAtUtc = $workerProcess.StartTime.ToUniversalTime().ToString('o')
$expectedWorkerProcessPath = $windowsPowerShell
try {
    $expectedWorkerProcessPath = $workerProcess.MainModule.FileName
} catch {
    # The configured absolute host path remains the expected fallback.
}

$handshakeDeadline = (Get-Date).ToUniversalTime().AddSeconds($script:CodexJobWorkerHandshakeSeconds)
$current = $null
while ((Get-Date).ToUniversalTime() -lt $handshakeDeadline) {
    Start-Sleep -Milliseconds 100
    $current = Read-TrustedJobMetadata -Path $metadataPath -ExpectedJobId $jobId -ExpectedRepoPath $repo `
        -ExpectedPromptPath $prompt -ExpectedCodexPath $codexExecutable `
        -ExpectedPromptSha256 $promptSha256 -ExpectedPromptContract $promptContract `
        -ExpectedOutputDirectory $outputDirectory `
        -ExpectedPromptCanonicalPath $promptCanonicalPath -ExpectedCodexCanonicalPath $codexCanonicalPath `
        -ExpectedGitDirectory $gitDirectory -ExpectedGitDirectoryCanonicalPath $gitDirectoryCanonicalPath `
        -ExpectedGitCommonDirectory $gitCommonDirectory -ExpectedGitCommonDirectoryCanonicalPath $gitCommonDirectoryCanonicalPath `
        -ExpectedGitBindingContract $gitBindingContract `
        -ExpectedGitLauncherContract $gitLauncherContract -ExpectedCodexLauncherContract $codexLauncherContract `
        -ExpectedCodexSignatureContract $codexSignatureContract `
        -ExpectedCodexArguments $codexArguments `
        -ExpectedWorkerPid $expectedWorkerPid -ExpectedWorkerStartedAtUtc $expectedWorkerStartedAtUtc `
        -ExpectedWorkerProcessPath $expectedWorkerProcessPath
    if ($current.state -notin @('starting', 'validating')) {
        break
    }
    $workerProcess.Refresh()
    if ($workerProcess.HasExited) {
        Set-ObjectProperty -Object $current -Name 'ok' -Value $false
        Set-ObjectProperty -Object $current -Name 'state' -Value 'failed'
        Set-ObjectProperty -Object $current -Name 'worker_pid' -Value $workerProcess.Id
        Set-ObjectProperty -Object $current -Name 'worker_started_at_utc' -Value $expectedWorkerStartedAtUtc
        Set-ObjectProperty -Object $current -Name 'worker_process_path' -Value $expectedWorkerProcessPath
        Set-ObjectProperty -Object $current -Name 'worker_exit_code' -Value $workerProcess.ExitCode
        Set-ObjectProperty -Object $current -Name 'completed_at_utc' -Value ((Get-Date).ToUniversalTime().ToString('o'))
        Set-ObjectProperty -Object $current -Name 'error' -Value 'Worker exited before reporting Codex launch status.'
        Write-JobMetadata -Path $metadataPath -Value $current
        break
    }
}

if ($null -eq $current) {
    $current = Read-TrustedJobMetadata -Path $metadataPath -ExpectedJobId $jobId -ExpectedRepoPath $repo `
        -ExpectedPromptPath $prompt -ExpectedCodexPath $codexExecutable `
        -ExpectedPromptSha256 $promptSha256 -ExpectedPromptContract $promptContract `
        -ExpectedOutputDirectory $outputDirectory `
        -ExpectedPromptCanonicalPath $promptCanonicalPath -ExpectedCodexCanonicalPath $codexCanonicalPath `
        -ExpectedGitDirectory $gitDirectory -ExpectedGitDirectoryCanonicalPath $gitDirectoryCanonicalPath `
        -ExpectedGitCommonDirectory $gitCommonDirectory -ExpectedGitCommonDirectoryCanonicalPath $gitCommonDirectoryCanonicalPath `
        -ExpectedGitBindingContract $gitBindingContract `
        -ExpectedGitLauncherContract $gitLauncherContract -ExpectedCodexLauncherContract $codexLauncherContract `
        -ExpectedCodexSignatureContract $codexSignatureContract `
        -ExpectedCodexArguments $codexArguments `
        -ExpectedWorkerPid $expectedWorkerPid -ExpectedWorkerStartedAtUtc $expectedWorkerStartedAtUtc `
        -ExpectedWorkerProcessPath $expectedWorkerProcessPath
}
if ($current.state -in @('starting', 'validating')) {
    throw "Codex worker did not complete its ownership/validation handshake within $($script:CodexJobWorkerHandshakeSeconds) seconds; no process was killed. state=$($current.state) worker_pid=$($workerProcess.Id) metadata=$metadataPath"
}
if ($current.state -eq 'failed') {
    throw "Codex job failed during startup. metadata=$metadataPath error=$($current.error)"
}

if (-not $Wait) {
    $current
    return
}

$monitorDeadline = (Get-Date).ToUniversalTime().AddSeconds(
    $TimeoutSeconds + $script:CodexJobWorkerHandshakeSeconds + 15)
while ($true) {
    $current = Read-TrustedJobMetadata -Path $metadataPath -ExpectedJobId $jobId -ExpectedRepoPath $repo `
        -ExpectedPromptPath $prompt -ExpectedCodexPath $codexExecutable `
        -ExpectedPromptSha256 $promptSha256 -ExpectedPromptContract $promptContract `
        -ExpectedOutputDirectory $outputDirectory `
        -ExpectedPromptCanonicalPath $promptCanonicalPath -ExpectedCodexCanonicalPath $codexCanonicalPath `
        -ExpectedGitDirectory $gitDirectory -ExpectedGitDirectoryCanonicalPath $gitDirectoryCanonicalPath `
        -ExpectedGitCommonDirectory $gitCommonDirectory -ExpectedGitCommonDirectoryCanonicalPath $gitCommonDirectoryCanonicalPath `
        -ExpectedGitBindingContract $gitBindingContract `
        -ExpectedGitLauncherContract $gitLauncherContract -ExpectedCodexLauncherContract $codexLauncherContract `
        -ExpectedCodexSignatureContract $codexSignatureContract `
        -ExpectedCodexArguments $codexArguments `
        -ExpectedWorkerPid $expectedWorkerPid -ExpectedWorkerStartedAtUtc $expectedWorkerStartedAtUtc `
        -ExpectedWorkerProcessPath $expectedWorkerProcessPath
    switch ($current.state) {
        'completed' {
            $current
            return
        }
        'failed' {
            throw "Codex job failed. exit_code=$($current.exit_code) stderr=$stderrPath metadata=$metadataPath"
        }
        'timed_out_running' {
            if ([bool]$current.worker_recovery_left_live_launcher) {
                throw "Codex launcher remained alive after bounded worker error recovery; the worker exited and no process was killed. launcher_pid=$($current.launcher_pid) worker_pid=$($current.worker_pid) metadata=$metadataPath"
            }
            throw "Codex job exceeded timeout and remains running under its worker. launcher_pid=$($current.launcher_pid) worker_pid=$($current.worker_pid) metadata=$metadataPath"
        }
        'timed_out' {
            throw "Codex job exceeded timeout before it exited. exit_code=$($current.exit_code) metadata=$metadataPath"
        }
    }

    $workerProcess.Refresh()
    if ($workerProcess.HasExited) {
        Start-Sleep -Milliseconds 100
        $current = Read-TrustedJobMetadata -Path $metadataPath -ExpectedJobId $jobId -ExpectedRepoPath $repo `
            -ExpectedPromptPath $prompt -ExpectedCodexPath $codexExecutable `
            -ExpectedPromptSha256 $promptSha256 -ExpectedPromptContract $promptContract `
            -ExpectedOutputDirectory $outputDirectory `
            -ExpectedPromptCanonicalPath $promptCanonicalPath -ExpectedCodexCanonicalPath $codexCanonicalPath `
            -ExpectedGitDirectory $gitDirectory -ExpectedGitDirectoryCanonicalPath $gitDirectoryCanonicalPath `
            -ExpectedGitCommonDirectory $gitCommonDirectory -ExpectedGitCommonDirectoryCanonicalPath $gitCommonDirectoryCanonicalPath `
            -ExpectedGitBindingContract $gitBindingContract `
            -ExpectedGitLauncherContract $gitLauncherContract -ExpectedCodexLauncherContract $codexLauncherContract `
            -ExpectedCodexSignatureContract $codexSignatureContract `
            -ExpectedCodexArguments $codexArguments `
            -ExpectedWorkerPid $expectedWorkerPid -ExpectedWorkerStartedAtUtc $expectedWorkerStartedAtUtc `
            -ExpectedWorkerProcessPath $expectedWorkerProcessPath
        if ($current.state -notin @('completed', 'failed', 'timed_out')) {
            Set-ObjectProperty -Object $current -Name 'ok' -Value $false
            Set-ObjectProperty -Object $current -Name 'state' -Value 'failed'
            Set-ObjectProperty -Object $current -Name 'worker_exit_code' -Value $workerProcess.ExitCode
            Set-ObjectProperty -Object $current -Name 'completed_at_utc' -Value ((Get-Date).ToUniversalTime().ToString('o'))
            Set-ObjectProperty -Object $current -Name 'error' -Value 'Worker exited without writing a terminal state.'
            Write-JobMetadata -Path $metadataPath -Value $current
            throw "Codex worker exited without a terminal state. metadata=$metadataPath"
        }
        continue
    }

    if ((Get-Date).ToUniversalTime() -gt $monitorDeadline) {
        throw "Codex worker did not publish its timeout transition on schedule; no process was killed. worker_pid=$($current.worker_pid) metadata=$metadataPath"
    }
    Start-Sleep -Milliseconds 200
}
} finally {
    if ($null -ne $gitConfigJobHandle) { $gitConfigJobHandle.Dispose() }
    if ($null -ne $workerScriptHandle) { $workerScriptHandle.Dispose() }
}
} finally {
    [Environment]::SetEnvironmentVariable('PSModulePath', $script:CodexJobOriginalPSModulePath, 'Process')
}
