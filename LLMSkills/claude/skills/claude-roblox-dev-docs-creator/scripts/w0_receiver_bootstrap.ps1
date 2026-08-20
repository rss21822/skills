[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('PREPARE', 'VALIDATE', 'ADMIT')]
    [string]$Phase,
    [Parameter(Mandatory = $true)][string]$ConfigPath,
    [Parameter(Mandatory = $true)][string]$ExpectedConfigSha256,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$PackagePath,
    [string]$LaunchChallengeOutputPath,
    [string]$LaunchChallengePath,
    [string]$AuthorizationEvidenceRoot,
    [string]$PrepareAttestationPath,
    [string]$PrepareSignaturePath,
    [string]$PrelaunchAssertionPath,
    [string]$PrelaunchSignaturePath,
    [string]$PostexecutionAttestationPath,
    [string]$PostexecutionSignaturePath,
    [string]$PresentationPath,
    [string]$HumanChallengePath,
    [string]$TranscriptPath,
    [string]$StatementPath,
    [string]$CapturePath,
    [string]$CaptureProvenancePath,
    [string]$RunAuthorizationPath,
    [string]$RunAdmissionAttestationPath,
    [string]$RunAdmissionSignaturePath,
    [string]$AdmitExecutionAttestationPath,
    [string]$AdmitExecutionSignaturePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:SuppliedParameterNames = @($PSBoundParameters.Keys)

$script:Utf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:JsonStringOptions = [System.Text.Json.JsonSerializerOptions]::new()
$script:JsonStringOptions.Encoder = [System.Text.Encodings.Web.JavaScriptEncoder]::UnsafeRelaxedJsonEscaping
if ($IsWindows -and -not ('W0NativeFileIdentity' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

public static class W0NativeFileIdentity {
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
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFileW(
        string fileName, uint desiredAccess, uint shareMode, IntPtr securityAttributes,
        uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GetFileInformationByHandle(
        SafeFileHandle handle, out BY_HANDLE_FILE_INFORMATION information);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandleW(
        SafeFileHandle handle, StringBuilder path, uint pathLength, uint flags);
    public static string Read(string path) {
        const uint FILE_READ_ATTRIBUTES = 0x80;
        const uint FILE_SHARE_ALL = 0x7;
        const uint OPEN_EXISTING = 3;
        const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
        using (var handle = CreateFileW(path, FILE_READ_ATTRIBUTES, FILE_SHARE_ALL,
                                        IntPtr.Zero, OPEN_EXISTING,
                                        FILE_FLAG_BACKUP_SEMANTICS, IntPtr.Zero)) {
            if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
            BY_HANDLE_FILE_INFORMATION info;
            if (!GetFileInformationByHandle(handle, out info))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            ulong fileId = ((ulong)info.FileIndexHigh << 32) | info.FileIndexLow;
            return info.VolumeSerialNumber.ToString("x8") + ":" + fileId.ToString("x16");
        }
    }
    public static uint ReadLinkCount(string path) {
        const uint FILE_READ_ATTRIBUTES = 0x80;
        const uint FILE_SHARE_ALL = 0x7;
        const uint OPEN_EXISTING = 3;
        const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
        using (var handle = CreateFileW(path, FILE_READ_ATTRIBUTES, FILE_SHARE_ALL,
                                        IntPtr.Zero, OPEN_EXISTING,
                                        FILE_FLAG_BACKUP_SEMANTICS, IntPtr.Zero)) {
            if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
            BY_HANDLE_FILE_INFORMATION info;
            if (!GetFileInformationByHandle(handle, out info))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            return info.NumberOfLinks;
        }
    }
    public static string ReadFinalPath(string path) {
        const uint FILE_READ_ATTRIBUTES = 0x80;
        const uint FILE_SHARE_ALL = 0x7;
        const uint OPEN_EXISTING = 3;
        const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
        using (var handle = CreateFileW(path, FILE_READ_ATTRIBUTES, FILE_SHARE_ALL,
                                        IntPtr.Zero, OPEN_EXISTING,
                                        FILE_FLAG_BACKUP_SEMANTICS, IntPtr.Zero)) {
            if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
            var buffer = new StringBuilder(32768);
            uint length = GetFinalPathNameByHandleW(handle, buffer, (uint)buffer.Capacity, 0);
            if (length == 0 || length >= buffer.Capacity)
                throw new Win32Exception(Marshal.GetLastWin32Error());
            return buffer.ToString();
        }
    }
}
'@
}

function Stop-W0([string]$Message) {
    throw [System.InvalidOperationException]::new("W0 STOP: $Message")
}

function Assert-JsonBoolean([object]$Value, [bool]$Expected, [string]$Label) {
    if ($Value -isnot [bool] -or [bool]$Value -ne $Expected) {
        Stop-W0 "$Label must be JSON boolean $($Expected.ToString().ToLowerInvariant())"
    }
}

function Assert-JsonInteger([object]$Value, [int64]$Expected, [string]$Label) {
    # ConvertFrom-Json materializes an integral JSON number as Int64.  Requiring
    # that exact CLR type rejects strings, booleans, and 0.0-style doubles
    # before any comparison/cast can coerce them.
    if ($Value -isnot [int64] -or [int64]$Value -ne $Expected) {
        Stop-W0 "$Label must be JSON integer $Expected"
    }
}

function Assert-JsonIntegerRange([object]$Value, [int64]$Minimum,
                                 [int64]$Maximum, [string]$Label) {
    if ($Value -isnot [int64] -or [int64]$Value -lt $Minimum -or
        [int64]$Value -gt $Maximum) {
        Stop-W0 "$Label must be a JSON integer in [$Minimum,$Maximum]"
    }
}

function Assert-JsonStringMinimum([object]$Value, [int]$Minimum, [string]$Label) {
    $count=0
    if ($Value -is [string]) {
        foreach($rune in ([string]$Value).EnumerateRunes()) { $count++ }
    }
    if ($Value -isnot [string] -or $count -lt $Minimum) {
        Stop-W0 "$Label must be a JSON string of at least $Minimum characters"
    }
}

function Assert-JsonFramedStringMinimum([object]$Value, [int]$Minimum,
                                        [string]$Label) {
    Assert-JsonStringMinimum $Value $Minimum $Label
    if (([string]$Value).Contains([char]0)) {
        Stop-W0 "$Label must not contain NUL in a NUL-delimited hash preimage"
    }
}

if ($PSVersionTable.PSVersion -lt [Version]'7.5') {
    Stop-W0 'bootstrap v1 requires PowerShell 7.5+ strict JSON DateKind support'
}

function Compare-CodePointString([string]$Left, [string]$Right) {
    $leftEnumerator = $Left.EnumerateRunes().GetEnumerator()
    $rightEnumerator = $Right.EnumerateRunes().GetEnumerator()
    while ($true) {
        $hasLeft = $leftEnumerator.MoveNext(); $hasRight = $rightEnumerator.MoveNext()
        if (-not $hasLeft -or -not $hasRight) {
            if ($hasLeft) { return 1 }; if ($hasRight) { return -1 }; return 0
        }
        if ($leftEnumerator.Current.Value -lt $rightEnumerator.Current.Value) { return -1 }
        if ($leftEnumerator.Current.Value -gt $rightEnumerator.Current.Value) { return 1 }
    }
}

function Sort-RecordsByCodePoint([object[]]$Records, [string]$Property) {
    [object[]]$ordered = @($Records)
    [Array]::Sort($ordered, [Comparison[object]]{
        param($left, $right)
        Compare-CodePointString ([string]$left[$Property]) ([string]$right[$Property])
    })
    return @($ordered)
}

function Get-Sha256Bytes([byte[]]$Bytes) {
    $hash = [System.Security.Cryptography.SHA256]::HashData($Bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-Sha256File([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try { $hash = $algorithm.ComputeHash($stream) }
        finally { $algorithm.Dispose() }
    }
    finally { $stream.Dispose() }
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

function ConvertTo-NormalizedPath([string]$Path, [bool]$MustExist = $true) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathFullyQualified($Path)) {
        Stop-W0 "absolute path required: $Path"
    }
    if (-not $IsWindows -or $Path -notmatch '^[A-Za-z]:[\\/]' -or
        $Path -match '^(?:\\\\[.?]\\|\\\\)' -or
        $Path.Substring(2).Contains(':')) {
        Stop-W0 "Windows drive path required; UNC/device/ADS paths are forbidden: $Path"
    }
    foreach($segment in ($Path.Substring(3) -split '[\\/]')) {
        $deviceStem=($segment -split '\.',2)[0]
        if ($segment.EndsWith('.') -or $segment.EndsWith(' ') -or
            $segment -match '~[0-9]+(?:\.|$)' -or
            $deviceStem -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') {
            Stop-W0 "device/trailing-dot/space/8.3 alias segment is forbidden: $Path"
        }
    }
    $full = [IO.Path]::GetFullPath($Path)
    if ($MustExist -and -not (Test-Path -LiteralPath $full)) {
        Stop-W0 "path does not exist: $full"
    }
    $check = if ($MustExist) { $full } else { [IO.Path]::GetDirectoryName($full) }
    if ([string]::IsNullOrWhiteSpace($check) -or -not (Test-Path -LiteralPath $check) -or
        (-not $MustExist -and -not (Test-Path -LiteralPath $check -PathType Container))) {
        Stop-W0 "path parent does not exist: $full"
    }
    $cursor = Get-Item -LiteralPath $check -Force
    while ($null -ne $cursor) {
        if (($cursor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Stop-W0 "reparse/junction path is forbidden: $($cursor.FullName)"
        }
        $parentPath = [IO.Path]::GetDirectoryName($cursor.FullName)
        if ([string]::IsNullOrWhiteSpace($parentPath) -or
            $parentPath -eq $cursor.FullName) { break }
        $cursor = Get-Item -LiteralPath $parentPath -Force
    }
    try { $finalCheck = [W0NativeFileIdentity]::ReadFinalPath($check) }
    catch { Stop-W0 "cannot resolve final path by handle for $check`: $($_.Exception.Message)" }
    if ($finalCheck.StartsWith('\\?\UNC\',[StringComparison]::OrdinalIgnoreCase)) {
        Stop-W0 "UNC final path is forbidden: $Path"
    }
    if ($finalCheck.StartsWith('\\?\',[StringComparison]::OrdinalIgnoreCase)) {
        $finalCheck=$finalCheck.Substring(4)
    }
    $resolved = if ($MustExist) { $finalCheck } else {
        [IO.Path]::Combine($finalCheck,[IO.Path]::GetFileName($full))
    }
    $normalized = $resolved.Replace('\', '/')
    if ($normalized -match '^[a-z]:') {
        $normalized = $normalized.Substring(0, 1).ToUpperInvariant() + $normalized.Substring(1)
    }
    if ($normalized.Length -gt 3) { $normalized = $normalized.TrimEnd('/') }
    return $normalized
}

function Test-Within([string]$Path, [string]$Root) {
    $pathNorm = (ConvertTo-NormalizedPath $Path $false).TrimEnd('/')
    $rootNorm = (ConvertTo-NormalizedPath $Root $true).TrimEnd('/')
    return $pathNorm.Equals($rootNorm, [StringComparison]::OrdinalIgnoreCase) -or
        $pathNorm.StartsWith($rootNorm + '/', [StringComparison]::OrdinalIgnoreCase)
}

function Assert-ExternalPath([string]$Path, [string[]]$Protected, [bool]$MustExist = $true) {
    $normalized = ConvertTo-NormalizedPath $Path $MustExist
    foreach ($root in $Protected) {
        if (Test-Within $normalized $root) { Stop-W0 "operator path is inside protected root: $normalized" }
        if ((Test-Path -LiteralPath $normalized -PathType Container) -and
            (Test-Within $root $normalized)) {
            Stop-W0 "operator directory contains protected root: $normalized"
        }
    }
    return $normalized
}

function Assert-NoDuplicateJson([System.Text.Json.JsonElement]$Element, [string]$Label) {
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $seen.Add($property.Name)) { Stop-W0 "$Label contains duplicate JSON key '$($property.Name)'" }
            Assert-NoDuplicateJson $property.Value $Label
        }
    }
    elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-NoDuplicateJson $item $Label }
    }
}

function Read-StrictJson([string]$Path, [bool]$Signed = $false) {
    $raw = [IO.File]::ReadAllBytes($Path)
    if ($raw.Length -ge 3 -and $raw[0] -eq 0xef -and $raw[1] -eq 0xbb -and $raw[2] -eq 0xbf) {
        Stop-W0 "JSON BOM is forbidden: $Path"
    }
    try { $text = $script:Utf8.GetString($raw) }
    catch { Stop-W0 "JSON is not strict UTF-8: $Path" }
    if ($Signed -and ($text.EndsWith("`n") -or $text.EndsWith("`r"))) {
        Stop-W0 "signed JSON must not have a terminal newline: $Path"
    }
    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.AllowTrailingCommas = $false
    $options.CommentHandling = [System.Text.Json.JsonCommentHandling]::Disallow
    try { $document = [System.Text.Json.JsonDocument]::Parse($text, $options) }
    catch { Stop-W0 "invalid strict JSON $Path`: $($_.Exception.Message)" }
    try { Assert-NoDuplicateJson $document.RootElement $Path }
    finally { $document.Dispose() }
    try { $value = $text | ConvertFrom-Json -AsHashtable -Depth 100 -DateKind String }
    catch { Stop-W0 "cannot materialize strict JSON $Path`: $($_.Exception.Message)" }
    if ($value -isnot [Collections.IDictionary]) { Stop-W0 "JSON root must be an object: $Path" }
    return $value
}

function ConvertTo-CanonicalJson([object]$Value) {
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [string]) {
        return [System.Text.Json.JsonSerializer]::Serialize([string]$Value, $script:JsonStringOptions)
    }
    if ($Value -is [Collections.IDictionary]) {
        [string[]]$keys = @($Value.Keys | ForEach-Object { [string]$_ })
        [Array]::Sort($keys, [Comparison[string]]{
            param($left, $right); Compare-CodePointString $left $right
        })
        $members = foreach ($key in $keys) {
            (ConvertTo-CanonicalJson $key) + ':' + (ConvertTo-CanonicalJson $Value[$key])
        }
        return '{' + ($members -join ',') + '}'
    }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = foreach ($item in $Value) { ConvertTo-CanonicalJson $item }
        return '[' + ($items -join ',') + ']'
    }
    if ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]) {
        return ([IFormattable]$Value).ToString($null, [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
        Stop-W0 'bootstrap canonical digests permit integers only; Python validates scoped decimals'
    }
    $map = [ordered]@{}
    foreach ($property in $Value.PSObject.Properties) { $map[$property.Name] = $property.Value }
    return ConvertTo-CanonicalJson $map
}

function ConvertTo-OrderedMinifiedJson([object]$Value) {
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
    if ($Value -is [string]) {
        return [System.Text.Json.JsonSerializer]::Serialize([string]$Value, $script:JsonStringOptions)
    }
    if ($Value -is [Collections.IDictionary]) {
        $members = foreach ($key in $Value.Keys) {
            (ConvertTo-OrderedMinifiedJson ([string]$key)) + ':' +
                (ConvertTo-OrderedMinifiedJson $Value[$key])
        }
        return '{' + ($members -join ',') + '}'
    }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = foreach ($item in $Value) { ConvertTo-OrderedMinifiedJson $item }
        return '[' + ($items -join ',') + ']'
    }
    if ($Value -is [byte] -or $Value -is [sbyte] -or $Value -is [int16] -or
        $Value -is [uint16] -or $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]) {
        return $Value.ToString($null, [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
        Stop-W0 'signed bootstrap records permit integers only; Python validates scoped decimals'
    }
    Stop-W0 "unsupported signed JSON value type $($Value.GetType().FullName)"
}

function Get-CanonicalBytes([object]$Value) {
    return $script:Utf8.GetBytes((ConvertTo-CanonicalJson $Value))
}

function Get-CanonicalSha256([object]$Value) {
    return Get-Sha256Bytes (Get-CanonicalBytes $Value)
}

function Assert-ExactKeys([Collections.IDictionary]$Value, [string[]]$Keys, [string]$Label) {
    $actual = @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    $expected = @($Keys | Sort-Object)
    if (($actual -join "`0") -cne ($expected -join "`0")) {
        Stop-W0 "$Label has unknown/missing fields"
    }
}

function Assert-ExactKeyOrder([Collections.IDictionary]$Value, [string[]]$Keys,
                              [string]$Label) {
    $actual = @($Value.Keys | ForEach-Object { [string]$_ })
    if (($actual -join "`0") -cne ($Keys -join "`0")) {
        Stop-W0 "$Label properties are not in fixed schema-required order"
    }
}

function Assert-ExactPhaseParameters([string]$CurrentPhase) {
    $common = @('Phase','ConfigPath','ExpectedConfigSha256','PackagePath','ProjectRoot')
    $specific = switch ($CurrentPhase) {
        'PREPARE' { @('LaunchChallengeOutputPath','AuthorizationEvidenceRoot') }
        'VALIDATE' { @('LaunchChallengePath','PrepareAttestationPath','PrepareSignaturePath',
                       'PrelaunchAssertionPath','PrelaunchSignaturePath',
                       'PostexecutionAttestationPath','PostexecutionSignaturePath') }
        'ADMIT' { @('LaunchChallengePath','PresentationPath','HumanChallengePath',
                    'TranscriptPath','StatementPath','CapturePath','CaptureProvenancePath',
                    'RunAuthorizationPath','RunAdmissionAttestationPath',
                    'RunAdmissionSignaturePath','AdmitExecutionAttestationPath',
                    'AdmitExecutionSignaturePath') }
    }
    $actual = @($script:SuppliedParameterNames | Sort-Object)
    $expected = @($common + $specific | Sort-Object)
    if (($actual -join "`0") -cne ($expected -join "`0")) {
        Stop-W0 "$CurrentPhase argv parameters do not exact-match phaseArgvTailGrammar"
    }
    $expectedTail = switch ($CurrentPhase) {
        'PREPARE' { @('-Phase','PREPARE','-ConfigPath',$ConfigPath,
            '-ExpectedConfigSha256',$ExpectedConfigSha256,'-PackagePath',$PackagePath,
            '-ProjectRoot',$ProjectRoot,'-LaunchChallengeOutputPath',$LaunchChallengeOutputPath,
            '-AuthorizationEvidenceRoot',$AuthorizationEvidenceRoot) }
        'VALIDATE' { @('-Phase','VALIDATE','-ConfigPath',$ConfigPath,
            '-ExpectedConfigSha256',$ExpectedConfigSha256,'-PackagePath',$PackagePath,
            '-ProjectRoot',$ProjectRoot,'-LaunchChallengePath',$LaunchChallengePath,
            '-PrepareAttestationPath',$PrepareAttestationPath,
            '-PrepareSignaturePath',$PrepareSignaturePath,
            '-PrelaunchAssertionPath',$PrelaunchAssertionPath,
            '-PrelaunchSignaturePath',$PrelaunchSignaturePath,
            '-PostexecutionAttestationPath',$PostexecutionAttestationPath,
            '-PostexecutionSignaturePath',$PostexecutionSignaturePath) }
        'ADMIT' { @('-Phase','ADMIT','-ConfigPath',$ConfigPath,
            '-ExpectedConfigSha256',$ExpectedConfigSha256,'-PackagePath',$PackagePath,
            '-ProjectRoot',$ProjectRoot,'-LaunchChallengePath',$LaunchChallengePath,
            '-PresentationPath',$PresentationPath,'-HumanChallengePath',$HumanChallengePath,
            '-TranscriptPath',$TranscriptPath,'-StatementPath',$StatementPath,
            '-CapturePath',$CapturePath,'-CaptureProvenancePath',$CaptureProvenancePath,
            '-RunAuthorizationPath',$RunAuthorizationPath,
            '-RunAdmissionAttestationPath',$RunAdmissionAttestationPath,
            '-RunAdmissionSignaturePath',$RunAdmissionSignaturePath,
            '-AdmitExecutionAttestationPath',$AdmitExecutionAttestationPath,
            '-AdmitExecutionSignaturePath',$AdmitExecutionSignaturePath) }
    }
    $rawArgs = @([Environment]::GetCommandLineArgs())
    $scriptIndex = -1
    for ($index = 0; $index -lt $rawArgs.Count; $index++) {
        try {
            if ((ConvertTo-NormalizedPath ([string]$rawArgs[$index]) $true) -ceq
                    (ConvertTo-NormalizedPath $PSCommandPath $true)) { $scriptIndex = $index }
        }
        catch { }
    }
    $actualTail = if ($scriptIndex -ge 0) {
        @($rawArgs | Select-Object -Skip ($scriptIndex + 1))
    } else { @() }
    if (($actualTail -join "`0") -cne ($expectedTail -join "`0")) {
        Stop-W0 "$CurrentPhase raw argv order/value does not exact-match phaseArgvTailGrammar"
    }
}

function Assert-ExpectedConfigHash {
    if ($ExpectedConfigSha256 -cnotmatch '^[0-9a-f]{64}$') {
        Stop-W0 'ExpectedConfigSha256 must be 64 lowercase hex'
    }
    $configAbsolute = ConvertTo-NormalizedPath $ConfigPath $true
    $actual = Get-Sha256File $configAbsolute
    if ($actual -cne $ExpectedConfigSha256) {
        Stop-W0 "operator-pinned config hash mismatch: $actual"
    }
}

function Get-TreeRecords([string]$Root) {
    $rootNorm = ConvertTo-NormalizedPath $Root $true
    $rootItem = Get-Item -LiteralPath $rootNorm -Force
    if (-not $rootItem.PSIsContainer) { Stop-W0 "tree root is not a directory: $rootNorm" }
    $stack = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
    $stack.Push([IO.DirectoryInfo]$rootItem)
    $records = [Collections.Generic.List[object]]::new()
    $identities = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    while ($stack.Count -gt 0) {
        $directory = $stack.Pop()
        foreach ($entry in $directory.EnumerateFileSystemInfos()) {
            if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                Stop-W0 "tree contains symlink/junction/reparse point: $($entry.FullName)"
            }
            if ($entry -is [IO.DirectoryInfo]) { $stack.Push($entry); continue }
            if ($entry -isnot [IO.FileInfo]) { Stop-W0 "tree contains special entry: $($entry.FullName)" }
            if ($IsWindows -and [W0NativeFileIdentity]::ReadLinkCount($entry.FullName) -ne 1) {
                Stop-W0 "tree contains a hardlinked file: $($entry.FullName)"
            }
            if (-not $identities.Add((Get-PathIdentity $entry.FullName))) {
                Stop-W0 "tree contains duplicate OS file identity: $($entry.FullName)"
            }
            $relative = [IO.Path]::GetRelativePath($rootNorm, $entry.FullName).Replace('\', '/')
            if ($relative.StartsWith('../') -or $relative -eq '..') { Stop-W0 'tree path escaped root' }
            $records.Add([ordered]@{
                path = $relative; bytes = [int64]$entry.Length
                sha256 = Get-Sha256File $entry.FullName
            })
        }
    }
    $ordered = $records.ToArray()
    [Array]::Sort($ordered, [Comparison[object]]{
        param($left, $right)
        return Compare-CodePointString ([string]$left.path) ([string]$right.path)
    })
    return @($ordered)
}

function Assert-TreePin([Collections.IDictionary]$Pin, [string[]]$Protected,
                        [string]$Label, [string]$RequiredRoot = '') {
    Assert-ExactKeys $Pin @('path','manifestFormat','manifestPath','manifestSha256','treeSha256') $Label
    if ($Pin.manifestFormat -cne 'canonical-library-tree-v1') { Stop-W0 "$Label manifestFormat" }
    $root = ConvertTo-NormalizedPath ([string]$Pin.path) $true
    if ($RequiredRoot -and $root -cne (ConvertTo-NormalizedPath $RequiredRoot $true)) {
        Stop-W0 "$Label path does not equal required root"
    }
    elseif (-not $RequiredRoot) { $root = Assert-ExternalPath $root $Protected $true }
    $manifest = Assert-ExternalPath ([string]$Pin.manifestPath) $Protected $true
    if (Test-Within $manifest $root) { Stop-W0 "$Label manifest is inside its tree" }
    if ((Get-Sha256File $manifest) -cne [string]$Pin.manifestSha256) { Stop-W0 "$Label manifest hash mismatch" }
    $manifestValue = Read-StrictJson $manifest
    Assert-ExactKeys $manifestValue @('files') "$Label manifest"
    $records = @(Get-TreeRecords $root)
    $canonical = Get-CanonicalBytes ([ordered]@{files=$records})
    $manifestBytes = [IO.File]::ReadAllBytes($manifest)
    if ($canonical.Length -ne $manifestBytes.Length -or
        (Get-Sha256Bytes $canonical) -cne (Get-Sha256Bytes $manifestBytes)) {
        Stop-W0 ("$Label manifest does not exact-cover tree: canonical=" +
            (Get-Sha256Bytes $canonical) + ", manifest=" +
            (Get-Sha256Bytes $manifestBytes) + ", canonicalBytes=" +
            $canonical.Length + ", manifestBytes=" + $manifestBytes.Length)
    }
    if ((Get-CanonicalSha256 $records) -cne [string]$Pin.treeSha256) { Stop-W0 "$Label tree hash mismatch" }
    return [ordered]@{root=$root; manifest=$manifest; records=$records}
}

function Assert-UniqueTreeRoots([object[]]$Pins, [string]$Label) {
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($pin in @($Pins)) {
        if ($null -eq $pin -or -not $seen.Add([string]$pin.root)) {
            Stop-W0 "$Label must contain unique normalized root paths"
        }
    }
}

function Assert-FilePin([Collections.IDictionary]$Pin, [string[]]$Protected,
                        [string]$Label, [string]$RequiredPath = '', [bool]$WithBytes = $false) {
    $keys = if ($WithBytes) { @('path','bytes','sha256') } else { @('path','sha256') }
    Assert-ExactKeys $Pin $keys $Label
    $path = if ($RequiredPath) { ConvertTo-NormalizedPath ([string]$Pin.path) $true } else {
        Assert-ExternalPath ([string]$Pin.path) $Protected $true
    }
    if ($RequiredPath -and $path -cne (ConvertTo-NormalizedPath $RequiredPath $true)) {
        Stop-W0 "$Label path does not equal required path"
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Stop-W0 "$Label is not a file" }
    if ((Get-Sha256File $path) -cne [string]$Pin.sha256) { Stop-W0 "$Label hash mismatch" }
    if ($WithBytes) {
        Assert-JsonIntegerRange $Pin.bytes 1 ([int64]::MaxValue) "$Label.bytes"
        if ((Get-Item -LiteralPath $path).Length -ne [int64]$Pin.bytes) {
            Stop-W0 "$Label byte count mismatch"
        }
    }
    return $path
}

function Get-PathIdentity([string]$Path) {
    $normalized = ConvertTo-NormalizedPath $Path $true
    if (-not $IsWindows) { Stop-W0 'W0 bootstrap v1 requires Windows volume/file identity support' }
    try { return 'windows-volume-file-id-v1:' + [W0NativeFileIdentity]::Read($normalized) }
    catch { Stop-W0 "cannot resolve OS file identity for $normalized`: $($_.Exception.Message)" }
}

function Get-JoinedSha256([string[]]$Values) {
    return Get-Sha256Bytes ($script:Utf8.GetBytes(($Values -join [char]0)))
}

function Get-ClosedEnvironment {
    $result = [ordered]@{}
    foreach ($name in @('SYSTEMROOT','WINDIR')) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($null -ne $value) { $result[$name] = $value }
    }
    return $result
}

function Get-EnvironmentSha256([Collections.IDictionary]$Environment) {
    $rows = @($Environment.Keys | ForEach-Object { [string]$_ } | Sort-Object | ForEach-Object {
        "$_=$($Environment[$_])"
    })
    return Get-JoinedSha256 $rows
}

function Read-StrictJsonText([string]$Text, [string]$Label) {
    try {
        $bytes = $script:Utf8.GetBytes($Text)
        $roundTrip = $script:Utf8.GetString($bytes)
        if ($roundTrip -cne $Text) { Stop-W0 "$Label is not strict UTF-8" }
        $options = [System.Text.Json.JsonDocumentOptions]::new()
        $options.AllowTrailingCommas = $false
        $options.CommentHandling = [System.Text.Json.JsonCommentHandling]::Disallow
        $document = [System.Text.Json.JsonDocument]::Parse($Text, $options)
        try { Assert-NoDuplicateJson $document.RootElement $Label }
        finally { $document.Dispose() }
        $value = $Text | ConvertFrom-Json -AsHashtable -Depth 100 -DateKind String
    }
    catch { Stop-W0 "$Label is invalid strict JSON: $($_.Exception.Message)" }
    if ($value -isnot [Collections.IDictionary]) { Stop-W0 "$Label root must be an object" }
    return $value
}

function ConvertFrom-DetachedSignatureBytes([byte[]]$Raw, [string]$Label) {
    $text = $script:Utf8.GetString($Raw)
    if ($text -notmatch '^[A-Za-z0-9+/]+={0,2}$' -or $text -match '\s') {
        Stop-W0 "detached signature must be base64 text without whitespace: $Label"
    }
    $remainder = $text.Length % 4
    if ($remainder -eq 1) { Stop-W0 "invalid base64 signature length: $Path" }
    if ($remainder -gt 1) { $text += '=' * (4 - $remainder) }
    try { return [Convert]::FromBase64String($text) }
    catch { Stop-W0 "invalid detached signature: $Label" }
}

function Read-DetachedSignature([string]$Path) {
    return ConvertFrom-DetachedSignatureBytes ([IO.File]::ReadAllBytes($Path)) $Path
}

function Read-VerifiedSignedJson([string]$JsonPath, [string]$SignaturePath,
                                [object]$Context, [string[]]$RequiredOrder,
                                [string]$Label) {
    $json = Assert-ExternalPath $JsonPath $Context.Protected $true
    $signature = Assert-ExternalPath $SignaturePath $Context.Protected $true
    if (-not (Test-Path -LiteralPath $json -PathType Leaf) -or
        -not (Test-Path -LiteralPath $signature -PathType Leaf)) {
        Stop-W0 "$Label JSON/signature must be files"
    }
    if ([W0NativeFileIdentity]::ReadLinkCount($json) -ne 1 -or
        [W0NativeFileIdentity]::ReadLinkCount($signature) -ne 1) {
        Stop-W0 "$Label JSON/signature hardlinks are forbidden"
    }
    $jsonIdentity=Get-PathIdentity $json
    $signatureIdentity=Get-PathIdentity $signature
    if ($json -ceq $signature -or $jsonIdentity -ceq $signatureIdentity) {
        Stop-W0 "$Label JSON/signature paths or identities collide"
    }
    $raw = [IO.File]::ReadAllBytes($json)
    $signatureRaw=[IO.File]::ReadAllBytes($signature)
    $jsonSha256=Get-Sha256Bytes $raw
    $signatureSha256=Get-Sha256Bytes $signatureRaw
    $value = Read-StrictJson $json $true
    Assert-ExactKeyOrder $value $RequiredOrder $Label
    $minified = $script:Utf8.GetBytes((ConvertTo-OrderedMinifiedJson $value))
    if ($minified.Length -ne $raw.Length -or
        (Get-Sha256Bytes $minified) -cne (Get-Sha256Bytes $raw)) {
        Stop-W0 "$Label signed bytes are not fixed-order minified UTF-8"
    }
    try {
        $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new(
            [IO.File]::ReadAllBytes($Context.Anchor))
        $rsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($certificate)
        if ($null -eq $rsa) { Stop-W0 "$Label trust anchor is not RSA" }
        try {
            $ok = $rsa.VerifyData(
                $raw, (ConvertFrom-DetachedSignatureBytes $signatureRaw $signature),
                [Security.Cryptography.HashAlgorithmName]::SHA256,
                [Security.Cryptography.RSASignaturePadding]::Pss)
        }
        finally { $rsa.Dispose(); $certificate.Dispose() }
    }
    catch { Stop-W0 "$Label RSA-PSS verification failed: $($_.Exception.Message)" }
    if (-not $ok) { Stop-W0 "$Label detached RSA-PSS signature is invalid" }
    if ((Get-PathIdentity $json) -cne $jsonIdentity -or
        (Get-PathIdentity $signature) -cne $signatureIdentity -or
        (Get-Sha256File $json) -cne $jsonSha256 -or
        (Get-Sha256File $signature) -cne $signatureSha256) {
        Stop-W0 "$Label JSON/signature changed during native verification"
    }
    return [ordered]@{
        Path=$json;SignaturePath=$signature;Value=$value;Sha256=$jsonSha256
        SignatureSha256=$signatureSha256;FileIdentity=$jsonIdentity
        SignatureFileIdentity=$signatureIdentity
    }
}

function ConvertTo-Time([object]$Value, [string]$Label) {
    $parsed = [DateTimeOffset]::MinValue
    if ($Value -isnot [string] -or
        $Value -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$' -or
        -not [DateTimeOffset]::TryParse(
        $Value, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind, [ref]$parsed)) {
        Stop-W0 "$Label must be a timezone timestamp"
    }
    return $parsed
}

function Get-ExternalReadSet([Collections.IDictionary]$Config, [string]$Project,
                             [string]$ConfigFile, [string]$Package,
                             [string]$TempRoot, [string]$ChallengeOutput) {
    $byPath = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    $byIdentity = [Collections.Generic.Dictionary[string,string]]::new([StringComparer]::OrdinalIgnoreCase)
    $challengeNormalized = ConvertTo-NormalizedPath $ChallengeOutput $false
    function Add-Record([string]$Absolute, [int64]$Bytes, [string]$Hash) {
        if ($IsWindows -and [W0NativeFileIdentity]::ReadLinkCount($Absolute) -ne 1) {
            Stop-W0 "read input contains a hardlinked file: $Absolute"
        }
        $identity = Get-PathIdentity $Absolute
        if ($byIdentity.ContainsKey($identity) -and
            -not $byIdentity[$identity].Equals($Absolute,[StringComparison]::OrdinalIgnoreCase)) {
            Stop-W0 "read input contains a hardlink/path alias: $Absolute"
        }
        $byIdentity[$identity]=$Absolute
        $byPath[$Absolute]=[ordered]@{path=$Absolute;bytes=$Bytes;sha256=$Hash}
    }
    function Add-One([string]$File) {
        $normalized = ConvertTo-NormalizedPath $File $true
        if ($normalized.Equals($challengeNormalized,[StringComparison]::OrdinalIgnoreCase)) { return }
        $item = Get-Item -LiteralPath $normalized -Force
        if ($item.PSIsContainer) {
            foreach ($record in Get-TreeRecords $normalized) {
                $absolute = ConvertTo-NormalizedPath (Join-Path $normalized $record.path) $true
                Add-Record $absolute ([int64]$record.bytes) ([string]$record.sha256)
            }
        }
        else {
            Add-Record $normalized ([int64]$item.Length) (Get-Sha256File $normalized)
        }
    }
    Add-One $Project
    Add-One $ConfigFile
    Add-One $Package
    Add-One $TempRoot
    function Walk([object]$Value) {
        if ($Value -is [Collections.IDictionary]) {
            foreach ($key in $Value.Keys) {
                $child = $Value[$key]
                if (($key -ceq 'path' -or $key -ceq 'manifestPath') -and
                    $child -is [string] -and [IO.Path]::IsPathFullyQualified($child) -and
                    (Test-Path -LiteralPath $child)) { Add-One $child }
                Walk $child
            }
        }
        elseif ($Value -is [Collections.IEnumerable] -and $Value -isnot [string]) {
            foreach ($child in $Value) { Walk $child }
        }
    }
    Walk $Config
    $keys = @($byPath.Keys); [Array]::Sort($keys, [Comparison[string]]{
        param($left, $right); Compare-CodePointString $left $right
    })
    return @($keys | ForEach-Object { $byPath[$_] })
}

function Read-And-ValidateConfig([string]$RawConfig, [string]$RawProject,
                                [string]$RawPackage) {
    $project = ConvertTo-NormalizedPath $RawProject $true
    if (-not (Test-Path -LiteralPath $project -PathType Container)) { Stop-W0 'project root is not a directory' }
    $configPath = ConvertTo-NormalizedPath $RawConfig $true
    $config = Read-StrictJson $configPath
    Assert-ExactKeys $config @('schemaVersion','d4RuntimePins','w0ValidatorRuntime','trustedRuntimeAdapters','signatureVerifiers') 'config'
    if ($config.schemaVersion -cne '1.0.0') { Stop-W0 'config schemaVersion' }
    $runtime = $config.w0ValidatorRuntime
    Assert-ExactKeys $runtime @(
        'id','installedSkillRoot','installedSkillReadClosure','pythonExecutable',
        'validatorEntrypoint','supportArtifacts','readOnlyLibraryRoots','gitExecutable',
        'gitRuntimeRoots','receiverBootstrap','immutableRuntimeAuthority') 'w0ValidatorRuntime'
    $skill = ConvertTo-NormalizedPath ([string]$runtime.installedSkillRoot) $true
    $package = ConvertTo-NormalizedPath $RawPackage $true
    if (-not (Test-Within $package $project)) { Stop-W0 'package must stay inside project root' }
    $protected = @($project, $skill)
    if (Test-Within $configPath $project -or Test-Within $configPath $skill) { Stop-W0 'config must be operator-external' }
    $skillPin = Assert-TreePin $runtime.installedSkillReadClosure $protected 'installedSkillReadClosure' $skill
    Assert-ExactKeys $runtime.pythonExecutable @('path','bytes','sha256','version','fixedArgs') 'pythonExecutable'
    $pythonBinaryPin = [ordered]@{path=$runtime.pythonExecutable.path;bytes=$runtime.pythonExecutable.bytes;sha256=$runtime.pythonExecutable.sha256}
    $python = Assert-FilePin $pythonBinaryPin $protected 'pythonExecutable' '' $true
    if (($runtime.pythonExecutable.fixedArgs -join "`0") -cne (@('-B','-S','-E','-X','utf8') -join "`0")) {
        Stop-W0 'python fixedArgs mismatch'
    }
    $pythonRoots = @($runtime.readOnlyLibraryRoots | ForEach-Object {
        Assert-TreePin $_ $protected 'python runtime root'
    })
    Assert-UniqueTreeRoots $pythonRoots 'readOnlyLibraryRoots'
    if (-not ($pythonRoots | Where-Object { Test-Within $python $_.root })) { Stop-W0 'python is outside pinned runtime roots' }
    if ($null -ne $runtime.gitExecutable -or @($runtime.gitRuntimeRoots).Count -ne 0) {
        Stop-W0 'lifecycle v1 is snapshot-only; Git pins must be null/empty'
    }
    Assert-ExactKeys $runtime.validatorEntrypoint @('path','sha256','copyPath') 'validatorEntrypoint'
    $entryPin = [ordered]@{path=$runtime.validatorEntrypoint.path;sha256=$runtime.validatorEntrypoint.sha256}
    $entry = Assert-FilePin $entryPin $protected 'validatorEntrypoint' (Join-Path $skill 'scripts/validate_d5_acceptance.py')
    $supports = @($runtime.supportArtifacts)
    if ($supports.Count -ne 3) { Stop-W0 'supportArtifacts must exact-cover three files' }
    $expectedSupport = @('scripts/gen_index.py','scripts/state_readiness.py','scripts/strict_json.py')
    $supportByCopy = [ordered]@{}
    foreach ($pin in $supports) {
        Assert-ExactKeys $pin @('path','sha256','copyPath') 'supportArtifact'
        if ($expectedSupport -cnotcontains [string]$pin.copyPath -or $supportByCopy.Contains([string]$pin.copyPath)) {
            Stop-W0 'supportArtifacts copyPath set mismatch'
        }
        $supportFilePin = [ordered]@{path=$pin.path;sha256=$pin.sha256}
        $supportByCopy[[string]$pin.copyPath] = Assert-FilePin $supportFilePin $protected 'supportArtifact' (Join-Path $skill ([string]$pin.copyPath))
    }
    if (@($supportByCopy.Keys).Count -ne 3) { Stop-W0 'supportArtifacts set mismatch' }
    $bootstrap = $runtime.receiverBootstrap
    Assert-ExactKeys $bootstrap @(
        'script','hostExecutable','hostVersion','hostFixedArgs','hostRuntimeRoots',
        'trustBoundary','threePhaseProtocol','phaseFlag','phaseValues',
        'phaseInvocationProtocol','phaseArgvTailGrammar') 'receiverBootstrap'
    if (($bootstrap.hostFixedArgs -join "`0") -cne
        (@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File') -join "`0") -or
        $bootstrap.trustBoundary -cne 'operator-pinned-powershell-os-host-and-bootstrap-v1' -or
        $bootstrap.threePhaseProtocol -cne 'prepare-validate-admit-continuous-lock-v1' -or
        $bootstrap.phaseFlag -cne '-Phase' -or
        ($bootstrap.phaseValues -join "`0") -cne (@('PREPARE','VALIDATE','ADMIT') -join "`0") -or
        $bootstrap.phaseInvocationProtocol -cne 'host-fixed-args-script-phase-first-absolute-named-paths-v1') {
        Stop-W0 'receiverBootstrap fixed protocol mismatch'
    }
    $expectedGrammar = [ordered]@{
        PREPARE=@('-ConfigPath','<ABS>','-ExpectedConfigSha256','<LOWER64HEX>',
                  '-PackagePath','<ABS>','-ProjectRoot','<ABS>',
                  '-LaunchChallengeOutputPath','<ABS>',
                  '-AuthorizationEvidenceRoot','<ABS>')
        VALIDATE=@('-ConfigPath','<ABS>','-ExpectedConfigSha256','<LOWER64HEX>',
                   '-PackagePath','<ABS>','-ProjectRoot','<ABS>',
                   '-LaunchChallengePath','<ABS>','-PrepareAttestationPath','<ABS>',
                   '-PrepareSignaturePath','<ABS>','-PrelaunchAssertionPath','<ABS>',
                   '-PrelaunchSignaturePath','<ABS>','-PostexecutionAttestationPath','<ABS>',
                   '-PostexecutionSignaturePath','<ABS>')
        ADMIT=@('-ConfigPath','<ABS>','-ExpectedConfigSha256','<LOWER64HEX>',
                '-PackagePath','<ABS>','-ProjectRoot','<ABS>',
                '-LaunchChallengePath','<ABS>','-PresentationPath','<ABS>',
                '-HumanChallengePath','<ABS>','-TranscriptPath','<ABS>',
                '-StatementPath','<ABS>','-CapturePath','<ABS>',
                '-CaptureProvenancePath','<ABS>','-RunAuthorizationPath','<ABS>',
                '-RunAdmissionAttestationPath','<ABS>',
                '-RunAdmissionSignaturePath','<ABS>',
                '-AdmitExecutionAttestationPath','<ABS>',
                '-AdmitExecutionSignaturePath','<ABS>')
    }
    if ((ConvertTo-CanonicalJson $bootstrap.phaseArgvTailGrammar) -cne
        (ConvertTo-CanonicalJson $expectedGrammar)) { Stop-W0 'phaseArgvTailGrammar mismatch' }
    $bootstrapScript = Assert-FilePin $bootstrap.script $protected 'receiverBootstrap.script' (Join-Path $skill 'scripts/w0_receiver_bootstrap.ps1')
    $hostBinary = Assert-FilePin $bootstrap.hostExecutable $protected 'receiverBootstrap.hostExecutable' '' $true
    $hostRoots = @($bootstrap.hostRuntimeRoots | ForEach-Object {
        Assert-TreePin $_ $protected 'PowerShell host runtime root'
    })
    Assert-UniqueTreeRoots $hostRoots 'hostRuntimeRoots'
    if (-not ($hostRoots | Where-Object { Test-Within $hostBinary $_.root })) { Stop-W0 'PowerShell host is outside pinned runtime roots' }
    if ((ConvertTo-NormalizedPath (Get-Process -Id $PID).Path $true) -cne $hostBinary) { Stop-W0 'bootstrap is not running under pinned host' }
    if ($PSVersionTable.PSVersion.ToString() -cne [string]$bootstrap.hostVersion) { Stop-W0 'PowerShell hostVersion mismatch' }
    if ((ConvertTo-NormalizedPath $PSCommandPath $true) -cne $bootstrapScript) { Stop-W0 'bootstrap script path mismatch' }
    $authority = $runtime.immutableRuntimeAuthority
    Assert-ExactKeys $authority @(
        'authority','verificationMode','keyId','trustAnchor','trustAnchorFormat',
        'prepareExecutionSchemaId','prelaunchSchemaId','postexecutionSchemaId',
        'runAuthorizationSchemaId','runAdmissionSchemaId','admitExecutionSchemaId',
        'detachedSignatureProtocol',
        'signedBytesSerialization','signatureEncoding','rsaPssSaltLength',
        'argvDigestProtocol','cwdDigestProtocol','envDigestProtocol',
        'projectTreeDigestProtocol','readInputDigestProtocol',
        'readInputIdentityDigestProtocol','assertionInputs','maxPrelaunchAgeSeconds',
        'maxAdmissionLifetimeSeconds','maxWorkerReadyLifetimeSeconds',
        'maxClockSkewSeconds') 'immutableRuntimeAuthority'
    if ($authority.verificationMode -cne 'receiver-native-rsa-pss-sha256' -or
        $authority.trustAnchorFormat -cne 'x509-der' -or
        $authority.detachedSignatureProtocol -cne 'raw-fixed-order-json-detached-rsa-pss-sha256-v1' -or
        $authority.signedBytesSerialization -cne 'fixed-property-order-minified-utf8-no-bom-no-newline-v1' -or
        $authority.signatureEncoding -cne 'base64-text-no-whitespace' -or
        $authority.rsaPssSaltLength -cne 'hash-length') {
        Stop-W0 'immutableRuntimeAuthority fixed crypto protocol mismatch'
    }
    if ($authority.admitExecutionSchemaId -cne
            'https://example.invalid/roblox-ai-development-os/w0-runtime-admit-execution-attestation.schema.json') {
        Stop-W0 'immutableRuntimeAuthority admitExecutionSchemaId mismatch'
    }
    $assertionInputs=$authority.assertionInputs
    Assert-ExactKeys $assertionInputs @(
        'pathSource','expectedConfigHashSource','challengeSource','challengeInputs',
        'prepareExecutionAvailability','prelaunchAvailability','postexecutionAvailability',
        'runAuthorizationAvailability','runAdmissionAvailability','admitExecutionAvailability',
        'admitPathSet') 'immutableRuntimeAuthority.assertionInputs'
    if ($assertionInputs.admitExecutionAvailability -cne
            'receipt-and-signature-paths-predeclared-and-absent-before-admit-created-by-authority-after-semantic-pass-token-consumption-and-suspended-worker-observation' -or
        ($assertionInputs.admitPathSet -join "`0") -cne
            (@('presentation','challenge','transcript','statement','capture','capture-provenance',
               'run-authorization','run-admission-attestation','run-admission-signature',
               'admit-execution-attestation','admit-execution-signature') -join "`0")) {
        Stop-W0 'immutableRuntimeAuthority ADMIT input/output contract mismatch'
    }
    Assert-JsonIntegerRange $authority.maxPrelaunchAgeSeconds 1 300 `
        'immutableRuntimeAuthority.maxPrelaunchAgeSeconds'
    Assert-JsonIntegerRange $authority.maxAdmissionLifetimeSeconds 1 60 `
        'immutableRuntimeAuthority.maxAdmissionLifetimeSeconds'
    Assert-JsonIntegerRange $authority.maxWorkerReadyLifetimeSeconds 1 60 `
        'immutableRuntimeAuthority.maxWorkerReadyLifetimeSeconds'
    Assert-JsonIntegerRange $authority.maxClockSkewSeconds 0 30 `
        'immutableRuntimeAuthority.maxClockSkewSeconds'
    $anchor = Assert-FilePin $authority.trustAnchor $protected 'immutableRuntimeAuthority.trustAnchor'
    $packageValue = Read-StrictJson $package
    if ($packageValue.acceptanceProvenanceMode -cne 'offline-pinned-signature-only-v1') {
        Stop-W0 'package acceptanceProvenanceMode must be offline signature only'
    }
    return [ordered]@{
        Config=$config; Runtime=$runtime; Authority=$authority; Project=$project;
        ConfigPath=$configPath; Package=$package; PackageValue=$packageValue; Skill=$skill;
        Protected=$protected; SkillPin=$skillPin; Python=$python; PythonRoots=$pythonRoots;
        Entry=$entry; Supports=$supportByCopy; Bootstrap=$bootstrap; BootstrapScript=$bootstrapScript;
        HostBinary=$hostBinary; HostRoots=$hostRoots; Anchor=$anchor
    }
}

$script:LaunchChallengeKeys = @(
    'schemaVersion','kind','id','runId','receiverNonce','preparedAt','expiresAt',
    'resolvedLaunchChallengePath','resolvedAuthorizationEvidenceRoot',
    'authorizationEvidenceRootIdentity','operatorExpectedConfigSha256','configSha256','packageSha256',
    'resolvedProjectRoot','projectRootIdentity','resolvedTempRoot','tempRootIdentity',
    'installedSkillReadClosureTreeSha256','pythonExecutableSha256',
    'validatorEntrypointSha256','supportArtifactSetSha256','projectInputTreeSha256',
    'tempCopySetSha256','readInputSetSha256','expectedArgvSha256','expectedCwdSha256',
    'expectedEnvSha256','bootstrapScriptSha256','bootstrapHostSha256','status','pythonStarted')
$script:PrepareKeys = @(
    'schemaVersion','kind','id','runId','receiverNonce','authoritySessionId','monitorSessionId',
    'operatorExpectedConfigSha256','configSha256','packageSha256','projectInputTreeSha256','installedSkillTreeSha256',
    'hostExecutableSha256','bootstrapScriptSha256','hostRuntimeClosureSha256',
    'argvSha256','cwdSha256','envSha256','inputIdentitySetSha256','loadedClosureSha256',
    'loadedClosureMatchesConfig','monitorStartedBeforeProcess','enforcementContinuous',
    'writePolicy','resolvedTempRoot','tempRootIdentity','resolvedLaunchChallengePath',
    'resolvedAuthorizationEvidenceRoot','authorizationEvidenceRootIdentity',
    'launchChallengeSha256','challengeFileIdentity','projectPackageSkillWriteCount',
    'pythonStarted','startedAt','completedAt','attestedAt','exitCode')
$script:PrelaunchKeys = @(
    'schemaVersion','kind','id','runId','receiverNonce','issuedAt','expiresAt',
    'resolvedPrepareExecutionAttestationPath','prepareExecutionAttestationSha256',
    'prepareExecutionAttestationFileIdentity','prepareAuthoritySessionId','prepareMonitorSessionId',
    'resolvedLaunchChallengePath','launchChallengeSha256','challengeFileIdentity',
    'resolvedAuthorizationEvidenceRoot','authorizationEvidenceRootIdentity',
    'postValidationEvidenceWritePolicy','operatorExpectedConfigSha256','configSha256','packageSha256','resolvedProjectRoot',
    'projectRootIdentity','resolvedConfigPath','configFileIdentity','resolvedPackagePath',
    'packageFileIdentity','resolvedTempRoot','tempRootIdentity','projectInputTreeSha256',
    'tempCopySetSha256','readInputSetSha256','readInputIdentitySetSha256',
    'expectedArgvSha256','expectedCwdSha256','expectedEnvSha256','authoritySessionId',
    'coverage','enforcementActive')
$script:PostexecutionKeys = @(
    'schemaVersion','kind','id','runId','receiverNonce','authoritySessionId',
    'prelaunchAssertionSha256','resolvedPrepareExecutionAttestationPath',
    'prepareExecutionAttestationSha256','prepareExecutionAttestationFileIdentity',
    'prepareAuthoritySessionId','prepareMonitorSessionId','resolvedLaunchChallengePath',
    'launchChallengeSha256','challengeFileIdentity','resolvedAuthorizationEvidenceRoot',
    'authorizationEvidenceRootIdentity','operatorExpectedConfigSha256','configSha256','packageSha256','resolvedProjectRoot',
    'projectRootIdentity','resolvedConfigPath','configFileIdentity','resolvedPackagePath',
    'packageFileIdentity','resolvedTempRoot','tempRootIdentity','projectInputTreeSha256',
    'tempCopySetSha256','readInputSetSha256','readInputIdentitySetSha256',
    'expectedArgvSha256','expectedCwdSha256','expectedEnvSha256','coverage',
    'loadedClosureSha256','argvSha256','cwdSha256','envSha256','loadedClosureMatchesConfig',
    'readInputClosureMatches','argvMatches','cwdMatches','envClosed','readOnly',
    'noWriteSwapAddMaintained','projectPackageSkillWriteCount',
    'authorizationEvidenceWriteCountAtPost','continuousLockRetainedForAdmit',
    'tempRetainedForAdmit','admitPhaseReady','startedAt','completedAt','attestedAt','exitCode')
$script:AdmissionKeys = @(
    'schemaVersion','kind','id','authoritySessionId','monitorSessionId','w0RunId',
    'operatorExpectedConfigSha256','configSha256','prelaunchAssertionSha256',
    'postexecutionAttestationSha256','lock','authorizationInputExtension','currentState',
    'runAuthorization','receiver','authorizationChronology','sideEffectsStarted',
    'oneTimeAdmission','admitExecutionReceiptOutputs','enforcement',
    'admissionLifetimeSeconds','admissionExpiresAt','verdict')
$script:AdmitExecutionKeys = @(
    'schemaVersion','kind','id','runId','receiverNonce','authoritySessionId','monitorSessionId',
    'operatorExpectedConfigSha256','configSha256','runAdmission','receiptOutputs','lock',
    'admitHost','semanticValidator','oneTimeAdmissionConsumption','workerReady',
    'workerReadyCapability','productSideEffectsStarted','projectPackageSkillWriteCount',
    'authorizationEvidenceWritePolicy','bootstrapState','attestedAt','verdict')

function Get-ExpectedValidatorInvocation([object]$Context, [string]$TempRoot) {
    $entryCopy = ConvertTo-NormalizedPath (
        (Join-Path $TempRoot ([string]$Context.Runtime.validatorEntrypoint.copyPath))) $true
    $argv = @($Context.Python) + @($Context.Runtime.pythonExecutable.fixedArgs) + @(
        $entryCopy, '--installed-skill-root', $Context.Skill,
        '--project-root', $Context.Project, '--source-project-root', $Context.Project,
        '--prefix', [string]$Context.PackageValue.prefix, '--package', $Context.Package,
        '--provenance-config', $Context.ConfigPath, '--json')
    $environment = Get-ClosedEnvironment
    return [ordered]@{
        Argv=$argv; Environment=$environment
        ArgvSha256=Get-JoinedSha256 $argv
        CwdSha256=Get-Sha256Bytes ($script:Utf8.GetBytes($TempRoot))
        EnvSha256=Get-EnvironmentSha256 $environment
    }
}

function Read-And-ValidateChallenge([object]$Context, [string]$RawChallengePath) {
    $challengePath = Assert-ExternalPath $RawChallengePath $Context.Protected $true
    $challenge = Read-StrictJson $challengePath
    Assert-ExactKeys $challenge $script:LaunchChallengeKeys 'launch challenge'
    Assert-JsonBoolean $challenge.pythonStarted $false 'launch challenge.pythonStarted'
    if ($challenge.schemaVersion -cne '1.0.0' -or
        $challenge.kind -cne 'w0-runtime-launch-challenge-v1' -or
        $challenge.status -cne 'prepared-awaiting-authority') {
        Stop-W0 'launch challenge fixed fields mismatch'
    }
    if ((ConvertTo-NormalizedPath ([string]$challenge.resolvedLaunchChallengePath) $true) -cne $challengePath) {
        Stop-W0 'launch challenge path self-binding mismatch'
    }
    $tempRoot = Assert-ExternalPath ([string]$challenge.resolvedTempRoot) $Context.Protected $true
    $authRoot = Assert-ExternalPath ([string]$challenge.resolvedAuthorizationEvidenceRoot) $Context.Protected $true
    if ((Get-PathIdentity $tempRoot) -cne [string]$challenge.tempRootIdentity -or
        (Get-PathIdentity $authRoot) -cne [string]$challenge.authorizationEvidenceRootIdentity -or
        (Get-PathIdentity $Context.Project) -cne [string]$challenge.projectRootIdentity) {
        Stop-W0 'launch challenge local OS identities changed'
    }
    $tempRecords = @(Get-TreeRecords $tempRoot)
    if ($tempRecords.Count -ne 4) { Stop-W0 'launch temp no longer has exact four-file closure' }
    $supportRecords = @(Sort-RecordsByCodePoint @($Context.Runtime.supportArtifacts | ForEach-Object {
        $path = Join-Path $tempRoot ([string]$_.copyPath)
        [ordered]@{copyPath=[string]$_.copyPath;bytes=(Get-Item $path).Length;sha256=Get-Sha256File $path}
    }) 'copyPath')
    $projectRecords = @(Get-TreeRecords $Context.Project)
    $readRecords = @(Get-ExternalReadSet $Context.Config $Context.Project $Context.ConfigPath $Context.Package $tempRoot $challengePath)
    $invocation = Get-ExpectedValidatorInvocation $Context $tempRoot
    $expected = [ordered]@{
        operatorExpectedConfigSha256=$ExpectedConfigSha256
        configSha256=Get-Sha256File $Context.ConfigPath
        packageSha256=Get-Sha256File $Context.Package
        resolvedProjectRoot=$Context.Project
        installedSkillReadClosureTreeSha256=[string]$Context.Runtime.installedSkillReadClosure.treeSha256
        pythonExecutableSha256=[string]$Context.Runtime.pythonExecutable.sha256
        validatorEntrypointSha256=[string]$Context.Runtime.validatorEntrypoint.sha256
        supportArtifactSetSha256=Get-CanonicalSha256 $supportRecords
        projectInputTreeSha256=Get-CanonicalSha256 ([ordered]@{files=$projectRecords})
        tempCopySetSha256=Get-CanonicalSha256 ([ordered]@{files=$tempRecords})
        readInputSetSha256=Get-CanonicalSha256 $readRecords
        expectedArgvSha256=$invocation.ArgvSha256
        expectedCwdSha256=$invocation.CwdSha256
        expectedEnvSha256=$invocation.EnvSha256
        bootstrapScriptSha256=Get-Sha256File $Context.BootstrapScript
        bootstrapHostSha256=Get-Sha256File $Context.HostBinary
    }
    foreach ($key in $expected.Keys) {
        if ([string]$challenge[$key] -cne [string]$expected[$key]) {
            Stop-W0 "launch challenge $key mismatch"
        }
    }
    $prepared = ConvertTo-Time $challenge.preparedAt 'challenge.preparedAt'
    $expires = ConvertTo-Time $challenge.expiresAt 'challenge.expiresAt'
    if ($prepared -ge $expires -or [DateTimeOffset]::UtcNow -gt $expires) {
        Stop-W0 'launch challenge expired or has invalid chronology'
    }
    return [ordered]@{
        Path=$challengePath; Value=$challenge; Sha256=Get-Sha256File $challengePath;
        TempRoot=$tempRoot; AuthorizationRoot=$authRoot; Invocation=$invocation
    }
}

function Assert-Value([object]$Actual, [object]$Expected, [string]$Label) {
    if ($Actual -is [Collections.IDictionary] -or
        ($Actual -is [Collections.IEnumerable] -and $Actual -isnot [string])) {
        if ((ConvertTo-CanonicalJson $Actual) -cne (ConvertTo-CanonicalJson $Expected)) {
            Stop-W0 "$Label mismatch"
        }
    }
    elseif ($Expected -is [bool]) {
        Assert-JsonBoolean $Actual ([bool]$Expected) $Label
    }
    elseif ($Expected -is [int64]) {
        Assert-JsonInteger $Actual ([int64]$Expected) $Label
    }
    elseif ($Expected -is [string]) {
        if ($Actual -isnot [string] -or [string]$Actual -cne [string]$Expected) {
            Stop-W0 "$Label mismatch"
        }
    }
    elseif ($Actual.GetType() -ne $Expected.GetType() -or $Actual -ne $Expected) {
        Stop-W0 "$Label mismatch"
    }
}

function Invoke-Prepare {
    Assert-ExactPhaseParameters 'PREPARE'
    Assert-ExpectedConfigHash
    if ([string]::IsNullOrWhiteSpace($LaunchChallengeOutputPath) -or
        [string]::IsNullOrWhiteSpace($AuthorizationEvidenceRoot)) {
        Stop-W0 'PREPARE requires LaunchChallengeOutputPath and AuthorizationEvidenceRoot'
    }
    $context = Read-And-ValidateConfig $ConfigPath $ProjectRoot $PackagePath
    $challengeOutput = Assert-ExternalPath $LaunchChallengeOutputPath $context.Protected $false
    if (Test-Path -LiteralPath $challengeOutput) { Stop-W0 'launch challenge output must not preexist' }
    $authRoot = Assert-ExternalPath $AuthorizationEvidenceRoot $context.Protected $true
    if (-not (Test-Path -LiteralPath $authRoot -PathType Container)) { Stop-W0 'authorization evidence root must be a directory' }
    foreach ($protectedRoot in $context.Protected) {
        if (Test-Within $protectedRoot $authRoot) {
            Stop-W0 'authorization evidence root must not contain a protected root'
        }
    }
    if (@(Get-ChildItem -LiteralPath $authRoot -Force).Count -ne 0) { Stop-W0 'authorization evidence root must initially be empty' }
    if (Test-Within $challengeOutput $authRoot) { Stop-W0 'challenge file must remain outside authorization evidence root' }
    $runId = ([Guid]::NewGuid().ToString('N') + [Guid]::NewGuid().ToString('N')).ToUpperInvariant()
    $nonceBytes = [byte[]]::new(32); [Security.Cryptography.RandomNumberGenerator]::Fill($nonceBytes)
    $nonce = [Convert]::ToHexString($nonceBytes).ToLowerInvariant()
    $tempParent = [IO.Path]::GetDirectoryName($challengeOutput)
    $tempRoot = Join-Path $tempParent ('.w0-runtime-' + $runId)
    if (Test-Path -LiteralPath $tempRoot) { Stop-W0 'fresh temp collision' }
    [IO.Directory]::CreateDirectory($tempRoot) | Out-Null
    $tempRoot = ConvertTo-NormalizedPath $tempRoot $true
    if ((Test-Within $tempRoot $context.Project) -or
        (Test-Within $tempRoot $context.Skill) -or
        (Test-Within $tempRoot $authRoot)) { Stop-W0 'fresh temp overlaps a protected root' }
    try {
        $copyPins = @($context.Runtime.validatorEntrypoint) + @($context.Runtime.supportArtifacts)
        $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($pin in $copyPins) {
            $copyPath = [string]$pin.copyPath
            if ([string]::IsNullOrWhiteSpace($copyPath) -or $copyPath.Contains('\') -or
                $copyPath.StartsWith('/') -or $copyPath.Contains('../') -or
                -not $seen.Add($copyPath)) { Stop-W0 'unsafe/colliding copyPath' }
            $source = ConvertTo-NormalizedPath ([string]$pin.path) $true
            if ((Get-Sha256File $source) -cne [string]$pin.sha256) { Stop-W0 "copy source pin changed: $copyPath" }
            $destination = Join-Path $tempRoot $copyPath
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
            [IO.File]::Copy($source, $destination, $false)
            if ((Get-Sha256File $destination) -cne [string]$pin.sha256) { Stop-W0 "temp copy hash mismatch: $copyPath" }
        }
        $tempRecords = @(Get-TreeRecords $tempRoot)
        if ($tempRecords.Count -ne 4) { Stop-W0 'prepared temp closure is not exactly four files' }
        $supportRecords = @(Sort-RecordsByCodePoint @($context.Runtime.supportArtifacts | ForEach-Object {
            $path = Join-Path $tempRoot ([string]$_.copyPath)
            [ordered]@{copyPath=[string]$_.copyPath;bytes=(Get-Item $path).Length;sha256=Get-Sha256File $path}
        }) 'copyPath')
        $environment = Get-ClosedEnvironment
        $entryCopy = Join-Path $tempRoot ([string]$context.Runtime.validatorEntrypoint.copyPath)
        $argv = @(
            $context.Python) + @($context.Runtime.pythonExecutable.fixedArgs) + @(
            (ConvertTo-NormalizedPath $entryCopy $true), '--installed-skill-root', $context.Skill,
            '--project-root', $context.Project, '--source-project-root', $context.Project,
            '--prefix', [string]$context.PackageValue.prefix, '--package', $context.Package,
            '--provenance-config', $context.ConfigPath, '--json')
        $projectRecords = @(Get-TreeRecords $context.Project)
        $readRecords = @(Get-ExternalReadSet $context.Config $context.Project $context.ConfigPath $context.Package $tempRoot $challengeOutput)
        $preparedAt = [DateTimeOffset]::UtcNow
        $expiresAt = $preparedAt.AddSeconds([int]$context.Authority.maxPrelaunchAgeSeconds)
        $challenge = [ordered]@{
            schemaVersion='1.0.0'; kind='w0-runtime-launch-challenge-v1'
            id=('W0-RUNTIME-CHALLENGE-' + $runId); runId=$runId; receiverNonce=$nonce
            preparedAt=$preparedAt.ToString('o'); expiresAt=$expiresAt.ToString('o')
            resolvedLaunchChallengePath=$challengeOutput
            resolvedAuthorizationEvidenceRoot=$authRoot
            authorizationEvidenceRootIdentity=Get-PathIdentity $authRoot
            operatorExpectedConfigSha256=$ExpectedConfigSha256
            configSha256=Get-Sha256File $context.ConfigPath
            packageSha256=Get-Sha256File $context.Package
            resolvedProjectRoot=$context.Project; projectRootIdentity=Get-PathIdentity $context.Project
            resolvedTempRoot=$tempRoot; tempRootIdentity=Get-PathIdentity $tempRoot
            installedSkillReadClosureTreeSha256=[string]$context.Runtime.installedSkillReadClosure.treeSha256
            pythonExecutableSha256=[string]$context.Runtime.pythonExecutable.sha256
            validatorEntrypointSha256=[string]$context.Runtime.validatorEntrypoint.sha256
            supportArtifactSetSha256=Get-CanonicalSha256 $supportRecords
            projectInputTreeSha256=Get-CanonicalSha256 ([ordered]@{files=$projectRecords})
            tempCopySetSha256=Get-CanonicalSha256 ([ordered]@{files=$tempRecords})
            readInputSetSha256=Get-CanonicalSha256 $readRecords
            expectedArgvSha256=Get-JoinedSha256 $argv
            expectedCwdSha256=Get-Sha256Bytes ($script:Utf8.GetBytes($tempRoot))
            expectedEnvSha256=Get-EnvironmentSha256 $environment
            bootstrapScriptSha256=Get-Sha256File $context.BootstrapScript
            bootstrapHostSha256=Get-Sha256File $context.HostBinary
            status='prepared-awaiting-authority'; pythonStarted=$false
        }
        $bytes = Get-CanonicalBytes $challenge
        [IO.File]::WriteAllBytes($challengeOutput, $bytes)
        [Console]::Out.WriteLine((ConvertTo-CanonicalJson $challenge))
    }
    catch {
        # Failure never grants authority. Preserve a prepared tree only after a
        # valid challenge exists; otherwise remove this fresh incomplete tree.
        if (-not (Test-Path -LiteralPath $challengeOutput)) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

function Invoke-PinnedValidator([object]$ChallengeContext, [object]$OverrideInvocation = $null) {
    $invocation = if ($null -ne $OverrideInvocation) { $OverrideInvocation } else {
        $ChallengeContext.Invocation
    }
    foreach ($path in @($ChallengeContext.TempRoot, $ConfigPath, $PackagePath)) {
        ConvertTo-NormalizedPath $path $true | Out-Null
    }
    if ((Get-Sha256File (ConvertTo-NormalizedPath $ConfigPath $true)) -cne $ExpectedConfigSha256) {
        Stop-W0 'config changed immediately before validator launch'
    }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = [string]$invocation.Argv[0]
    foreach ($argument in @($invocation.Argv | Select-Object -Skip 1)) {
        $info.ArgumentList.Add([string]$argument)
    }
    $info.WorkingDirectory = $ChallengeContext.TempRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.StandardOutputEncoding = $script:Utf8
    $info.StandardErrorEncoding = $script:Utf8
    $info.Environment.Clear()
    foreach ($name in $invocation.Environment.Keys) {
        $info.Environment[[string]$name] = [string]$invocation.Environment[$name]
    }
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $info
    try {
        $localStartedAt=[DateTimeOffset]::UtcNow
        if (-not $process.Start()) { Stop-W0 'pinned validator process did not start' }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit(600000)) {
            try { $process.Kill($true) } catch {}
            Stop-W0 'pinned validator timed out'
        }
        $localCompletedAt=[DateTimeOffset]::UtcNow
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        if ($script:Utf8.GetByteCount($stdout) -gt 1048576 -or
            $script:Utf8.GetByteCount($stderr) -gt 1048576) { Stop-W0 'validator output cap exceeded' }
        $value = Read-StrictJsonText $stdout 'validator stdout'
        Assert-JsonBoolean $value.pass $true 'validator stdout.pass'
        if ($process.ExitCode -ne 0) {
            Stop-W0 "validator did not PASS (exit $($process.ExitCode)): $stderr"
        }
        return [ordered]@{ExitCode=$process.ExitCode;Value=$value;Stdout=$stdout;Stderr=$stderr
            StartedAt=$localStartedAt;CompletedAt=$localCompletedAt}
    }
    finally { $process.Dispose() }
}

function Invoke-Validate {
    Assert-ExactPhaseParameters 'VALIDATE'
    Assert-ExpectedConfigHash
    $context = Read-And-ValidateConfig $ConfigPath $ProjectRoot $PackagePath
    $challengeContext = Read-And-ValidateChallenge $context $LaunchChallengePath
    $extraProtected = @($context.Protected + $challengeContext.TempRoot)
    $six = @($PrepareAttestationPath,$PrepareSignaturePath,$PrelaunchAssertionPath,
             $PrelaunchSignaturePath,$PostexecutionAttestationPath,$PostexecutionSignaturePath)
    if ($six.Count -ne (@($six | Sort-Object -Unique).Count)) { Stop-W0 'VALIDATE six paths must be distinct' }
    foreach ($path in @($six | Select-Object -First 4)) {
        Assert-ExternalPath $path $extraProtected $true | Out-Null
    }
    foreach ($path in @($six | Select-Object -Last 2)) {
        Assert-ExternalPath $path $extraProtected $false | Out-Null
        if (Test-Path -LiteralPath $path) { Stop-W0 'postexecution proof must be absent before launch' }
    }
    $prepare = Read-VerifiedSignedJson (
        $PrepareAttestationPath) $PrepareSignaturePath $context $script:PrepareKeys 'PREPARE attestation'
    $prelaunch = Read-VerifiedSignedJson (
        $PrelaunchAssertionPath) $PrelaunchSignaturePath $context $script:PrelaunchKeys 'prelaunch assertion'
    $challenge = $challengeContext.Value; $prep = $prepare.Value; $pre = $prelaunch.Value
    Assert-JsonBoolean $prep.loadedClosureMatchesConfig $true 'PREPARE.loadedClosureMatchesConfig'
    Assert-JsonBoolean $prep.monitorStartedBeforeProcess $true 'PREPARE.monitorStartedBeforeProcess'
    Assert-JsonBoolean $prep.enforcementContinuous $true 'PREPARE.enforcementContinuous'
    Assert-JsonInteger $prep.projectPackageSkillWriteCount 0 'PREPARE.projectPackageSkillWriteCount'
    Assert-JsonBoolean $prep.pythonStarted $false 'PREPARE.pythonStarted'
    Assert-JsonInteger $prep.exitCode 0 'PREPARE.exitCode'
    foreach($field in @('loadedClosureSha256','inputIdentitySetSha256','cwdSha256','envSha256')) {
        if ($prep[$field] -isnot [string] -or $prep[$field] -cnotmatch '^[0-9a-f]{64}$') {
            Stop-W0 "PREPARE.$field must be SHA-256"
        }
    }
    if ($prep.schemaVersion -cne '1.0.0' -or $prep.kind -cne 'w0-runtime-prepare-execution-v1' -or
        $prep.writePolicy -cne 'only-predeclared-fresh-temp-and-external-challenge-v1') {
        Stop-W0 'PREPARE attestation fixed facts are not passing'
    }
    $prepareArgv = Get-CanonicalHostArgv $context @(
        '-Phase','PREPARE','-ConfigPath',$context.ConfigPath,
        '-ExpectedConfigSha256',$ExpectedConfigSha256,'-PackagePath',$context.Package,
        '-ProjectRoot',$context.Project,'-LaunchChallengeOutputPath',$challengeContext.Path,
        '-AuthorizationEvidenceRoot',$challengeContext.AuthorizationRoot)
    $hostClosure = @(Sort-RecordsByCodePoint @($context.Bootstrap.hostRuntimeRoots | ForEach-Object {
        [ordered]@{path=[string]$_.path;treeSha256=[string]$_.treeSha256}
    }) 'path')
    $prepExpected = [ordered]@{
        runId=$challenge.runId;receiverNonce=$challenge.receiverNonce
        operatorExpectedConfigSha256=$ExpectedConfigSha256
        configSha256=$challenge.configSha256;packageSha256=$challenge.packageSha256
        projectInputTreeSha256=$challenge.projectInputTreeSha256
        installedSkillTreeSha256=$challenge.installedSkillReadClosureTreeSha256
        hostExecutableSha256=$challenge.bootstrapHostSha256
        bootstrapScriptSha256=$challenge.bootstrapScriptSha256
        hostRuntimeClosureSha256=Get-CanonicalSha256 $hostClosure
        argvSha256=Get-JoinedSha256 $prepareArgv
        resolvedTempRoot=$challengeContext.TempRoot;tempRootIdentity=$challenge.tempRootIdentity
        resolvedLaunchChallengePath=$challengeContext.Path
        resolvedAuthorizationEvidenceRoot=$challengeContext.AuthorizationRoot
        authorizationEvidenceRootIdentity=$challenge.authorizationEvidenceRootIdentity
        launchChallengeSha256=$challengeContext.Sha256
    }
    foreach ($key in $prepExpected.Keys) { Assert-Value $prep[$key] $prepExpected[$key] "PREPARE.$key" }
    foreach ($key in @('authoritySessionId','monitorSessionId','inputIdentitySetSha256',
                       'loadedClosureSha256','cwdSha256','envSha256','challengeFileIdentity')) {
        if ([string]::IsNullOrWhiteSpace([string]$prep[$key])) { Stop-W0 "PREPARE.$key is empty" }
    }
    $prepStart=ConvertTo-Time $prep.startedAt 'PREPARE.startedAt'
    $prepEnd=ConvertTo-Time $prep.completedAt 'PREPARE.completedAt'
    $prepAttested=ConvertTo-Time $prep.attestedAt 'PREPARE.attestedAt'
    if ($prepStart -gt $prepEnd -or $prepEnd -gt $prepAttested) { Stop-W0 'PREPARE chronology invalid' }

    Assert-JsonBoolean $pre.enforcementActive $true 'prelaunch.enforcementActive'
    if ($pre.schemaVersion -cne '1.0.0' -or $pre.kind -cne 'w0-runtime-prelaunch-v1' -or
        $pre.postValidationEvidenceWritePolicy -cne 'exact-external-run-authorization-chain-and-admission-only-v1' -or
        $pre.coverage -cne 'all-config-runtime-validator-project-and-package-read-inputs-no-write-swap-add') {
        Stop-W0 'prelaunch fixed facts are not passing'
    }
    $preExpected = [ordered]@{
        runId=$challenge.runId;receiverNonce=$challenge.receiverNonce
        resolvedPrepareExecutionAttestationPath=$prepare.Path
        prepareExecutionAttestationSha256=$prepare.Sha256
        prepareAuthoritySessionId=$prep.authoritySessionId
        prepareMonitorSessionId=$prep.monitorSessionId
        resolvedLaunchChallengePath=$challengeContext.Path
        launchChallengeSha256=$challengeContext.Sha256
        challengeFileIdentity=$prep.challengeFileIdentity
        resolvedAuthorizationEvidenceRoot=$challengeContext.AuthorizationRoot
        authorizationEvidenceRootIdentity=$challenge.authorizationEvidenceRootIdentity
        operatorExpectedConfigSha256=$ExpectedConfigSha256
        configSha256=$challenge.configSha256;packageSha256=$challenge.packageSha256
        resolvedProjectRoot=$context.Project;projectRootIdentity=$challenge.projectRootIdentity
        resolvedConfigPath=$context.ConfigPath;resolvedPackagePath=$context.Package
        resolvedTempRoot=$challengeContext.TempRoot;tempRootIdentity=$challenge.tempRootIdentity
        projectInputTreeSha256=$challenge.projectInputTreeSha256
        tempCopySetSha256=$challenge.tempCopySetSha256
        readInputSetSha256=$challenge.readInputSetSha256
        expectedArgvSha256=$challenge.expectedArgvSha256
        expectedCwdSha256=$challenge.expectedCwdSha256
        expectedEnvSha256=$challenge.expectedEnvSha256
        authoritySessionId=$prep.authoritySessionId
    }
    foreach ($key in $preExpected.Keys) { Assert-Value $pre[$key] $preExpected[$key] "prelaunch.$key" }
    foreach ($key in @('prepareExecutionAttestationFileIdentity','configFileIdentity',
                       'packageFileIdentity','readInputIdentitySetSha256')) {
        if ([string]::IsNullOrWhiteSpace([string]$pre[$key])) { Stop-W0 "prelaunch.$key is empty" }
    }
    $preIssued=ConvertTo-Time $pre.issuedAt 'prelaunch.issuedAt'
    $preExpires=ConvertTo-Time $pre.expiresAt 'prelaunch.expiresAt'
    if ($prepAttested -gt $preIssued -or $preIssued -ge $preExpires -or
        [DateTimeOffset]::UtcNow -gt $preExpires) { Stop-W0 'prelaunch chronology/expiry invalid' }

    # Revalidate every mutable byte and identity immediately before CreateProcess.
    $challengeContext = Read-And-ValidateChallenge $context $LaunchChallengePath
    if ((Get-Sha256File $PrepareAttestationPath) -cne $prepare.Sha256 -or
        (Get-Sha256File $PrelaunchAssertionPath) -cne $prelaunch.Sha256) {
        Stop-W0 'signed prelaunch inputs changed before CreateProcess'
    }
    $validatorResult = Invoke-PinnedValidator $challengeContext
    $waitUntil = [DateTimeOffset]::UtcNow.AddSeconds([int]$context.Authority.maxPrelaunchAgeSeconds)
    while ((-not (Test-Path -LiteralPath $PostexecutionAttestationPath) -or
            -not (Test-Path -LiteralPath $PostexecutionSignaturePath)) -and
           [DateTimeOffset]::UtcNow -lt $waitUntil) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $PostexecutionAttestationPath) -or
        -not (Test-Path -LiteralPath $PostexecutionSignaturePath)) {
        Stop-W0 'authority did not provide signed postexecution proof'
    }
    $post = Read-VerifiedSignedJson (
        $PostexecutionAttestationPath) $PostexecutionSignaturePath $context $script:PostexecutionKeys 'postexecution attestation'
    $postValue = $post.Value
    foreach($field in @('loadedClosureMatchesConfig','readInputClosureMatches','argvMatches',
                         'cwdMatches','envClosed','readOnly','noWriteSwapAddMaintained',
                         'continuousLockRetainedForAdmit','tempRetainedForAdmit','admitPhaseReady')) {
        Assert-JsonBoolean $postValue[$field] $true ("postexecution."+$field)
    }
    Assert-JsonInteger $postValue.projectPackageSkillWriteCount 0 `
        'postexecution.projectPackageSkillWriteCount'
    Assert-JsonInteger $postValue.authorizationEvidenceWriteCountAtPost 0 `
        'postexecution.authorizationEvidenceWriteCountAtPost'
    Assert-JsonInteger $postValue.exitCode 0 'postexecution.exitCode'
    if ($postValue.loadedClosureSha256 -isnot [string] -or
        $postValue.loadedClosureSha256 -cnotmatch '^[0-9a-f]{64}$') {
        Stop-W0 'postexecution.loadedClosureSha256 must be SHA-256'
    }
    if ($postValue.schemaVersion -cne '1.0.0' -or
        $postValue.kind -cne 'w0-runtime-postexecution-v1' -or
        $postValue.coverage -cne 'actual-loaded-process-and-read-input-identity-closure') {
        Stop-W0 'postexecution fixed facts are not passing'
    }
    $postExpected = [ordered]@{
        runId=$challenge.runId;receiverNonce=$challenge.receiverNonce
        authoritySessionId=$pre.authoritySessionId
        prelaunchAssertionSha256=$prelaunch.Sha256
        resolvedPrepareExecutionAttestationPath=$prepare.Path
        prepareExecutionAttestationSha256=$prepare.Sha256
        prepareExecutionAttestationFileIdentity=$pre.prepareExecutionAttestationFileIdentity
        prepareAuthoritySessionId=$prep.authoritySessionId
        prepareMonitorSessionId=$prep.monitorSessionId
        resolvedLaunchChallengePath=$challengeContext.Path
        launchChallengeSha256=$challengeContext.Sha256
        challengeFileIdentity=$pre.challengeFileIdentity
        resolvedAuthorizationEvidenceRoot=$challengeContext.AuthorizationRoot
        authorizationEvidenceRootIdentity=$challenge.authorizationEvidenceRootIdentity
        operatorExpectedConfigSha256=$ExpectedConfigSha256
        configSha256=$challenge.configSha256;packageSha256=$challenge.packageSha256
        resolvedProjectRoot=$context.Project;projectRootIdentity=$challenge.projectRootIdentity
        resolvedConfigPath=$context.ConfigPath;configFileIdentity=$pre.configFileIdentity
        resolvedPackagePath=$context.Package;packageFileIdentity=$pre.packageFileIdentity
        resolvedTempRoot=$challengeContext.TempRoot;tempRootIdentity=$challenge.tempRootIdentity
        projectInputTreeSha256=$challenge.projectInputTreeSha256
        tempCopySetSha256=$challenge.tempCopySetSha256
        readInputSetSha256=$challenge.readInputSetSha256
        readInputIdentitySetSha256=$pre.readInputIdentitySetSha256
        expectedArgvSha256=$challenge.expectedArgvSha256
        expectedCwdSha256=$challenge.expectedCwdSha256
        expectedEnvSha256=$challenge.expectedEnvSha256
        argvSha256=$challenge.expectedArgvSha256
        cwdSha256=$challenge.expectedCwdSha256
        envSha256=$challenge.expectedEnvSha256
    }
    foreach ($key in $postExpected.Keys) { Assert-Value $postValue[$key] $postExpected[$key] "postexecution.$key" }
    $postStart=ConvertTo-Time $postValue.startedAt 'postexecution.startedAt'
    $postEnd=ConvertTo-Time $postValue.completedAt 'postexecution.completedAt'
    $postAttested=ConvertTo-Time $postValue.attestedAt 'postexecution.attestedAt'
    if ($preIssued -gt $postStart -or $postStart -gt $postEnd -or
        $postEnd -gt $postAttested -or $postAttested -gt [DateTimeOffset]::UtcNow.AddSeconds(
            [int]$context.Authority.maxClockSkewSeconds)) { Stop-W0 'postexecution chronology invalid' }
    Read-And-ValidateChallenge $context $LaunchChallengePath | Out-Null
    # VALIDATE is deliberately not a W0 PASS.  It only records that the
    # continuous lock/temp state is ready for the separately authorized ADMIT
    # receipt path; PASS is reserved for post-receipt ADMIT below.
    [Console]::Out.WriteLine((ConvertTo-CanonicalJson ([ordered]@{
        status='validated-awaiting-admit';phase='VALIDATE';runId=$challenge.runId
        postexecutionSha256=$post.Sha256;tempRetained=$true;admitPhaseReady=$true
    })))
}

function Get-AuthorizationInputSets([string]$Root, [string[]]$ExcludedPaths,
                                    [Collections.Generic.HashSet[string]]$ForbiddenIdentities = $null) {
    $excluded = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $ExcludedPaths) { $excluded.Add((ConvertTo-NormalizedPath $path $false)) | Out-Null }
    $tree = @(Get-TreeRecords $Root)
    $records = [Collections.Generic.List[object]]::new()
    $identities = [Collections.Generic.List[object]]::new()
    $seenIdentities = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($row in $tree) {
        $path = ConvertTo-NormalizedPath (Join-Path $Root ([string]$row.path)) $true
        if ($excluded.Contains($path)) { continue }
        $records.Add([ordered]@{path=$path;bytes=[int64]$row.bytes;sha256=[string]$row.sha256})
        $identity = Get-PathIdentity $path
        if ($identity -cnotmatch '^windows-volume-file-id-v1:([0-9a-f]{8}):([0-9a-f]{16})$') {
            Stop-W0 "cannot split Windows volume/file identity: $path"
        }
        if (-not $seenIdentities.Add($identity)) {
            Stop-W0 "authorization input set contains a hardlink/path identity alias: $path"
        }
        if ($null -ne $ForbiddenIdentities -and $ForbiddenIdentities.Contains($identity)) {
            Stop-W0 "authorization input aliases locked project/runtime/read input: $path"
        }
        $identities.Add([ordered]@{
            path=$path;volumeIdentity=('windows-volume-serial-v1:' + $Matches[1])
            fileIdentity=('windows-file-id-v1:' + $Matches[2])
        })
    }
    $recordArray=$records.ToArray();$identityArray=$identities.ToArray()
    [Array]::Sort($recordArray,[Comparison[object]]{
        param($left,$right);Compare-CodePointString ([string]$left.path) ([string]$right.path)})
    [Array]::Sort($identityArray,[Comparison[object]]{
        param($left,$right);Compare-CodePointString ([string]$left.path) ([string]$right.path)})
    return [ordered]@{
        Records=@($recordArray);Identities=@($identityArray)
        ArtifactSetSha256=Get-CanonicalSha256 @($recordArray)
        IdentitySetSha256=Get-CanonicalSha256 @($identityArray)
    }
}

function Get-IdentitySetForRecords([object[]]$Records, [string]$Label) {
    $result=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($row in $Records) {
        $identity=Get-PathIdentity ([string]$row.path)
        if (-not $result.Add($identity)) { Stop-W0 "$Label contains a hardlink/path identity alias" }
    }
    return $result
}

function Get-IdentityRecordsForRecords([object[]]$Records, [string]$Label) {
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $rows=[Collections.Generic.List[object]]::new()
    foreach($row in $Records) {
        $path=ConvertTo-NormalizedPath ([string]$row.path) $true
        $identity=Get-PathIdentity $path
        if (-not $seen.Add($identity)) { Stop-W0 "$Label contains a hardlink/path identity alias" }
        if ($identity -cnotmatch '^windows-volume-file-id-v1:([0-9a-f]{8}):([0-9a-f]{16})$') {
            Stop-W0 "$Label identity is not splittable: $path"
        }
        $rows.Add([ordered]@{path=$path;volumeIdentity=('windows-volume-serial-v1:'+$Matches[1])
            fileIdentity=('windows-file-id-v1:'+$Matches[2])})
    }
    $array=$rows.ToArray()
    [Array]::Sort($array,[Comparison[object]]{
        param($left,$right);Compare-CodePointString ([string]$left.path) ([string]$right.path)})
    return @($array)
}

function Assert-IdentifiedFile([object]$Value, [string]$ExpectedPath,
                               [string]$ExpectedId = '', [string]$Label = 'artifact') {
    if ($Value -isnot [Collections.IDictionary]) { Stop-W0 "$Label must be an object" }
    $path = ConvertTo-NormalizedPath $ExpectedPath $true
    if ((ConvertTo-NormalizedPath ([string]$Value.path) $true) -cne $path -or
        [string]$Value.sha256 -cne (Get-Sha256File $path) -or
        [string]$Value.fileIdentity -cne (Get-PathIdentity $path)) {
        Stop-W0 "$Label path/hash/file identity mismatch"
    }
    if ($ExpectedId -and [string]$Value.id -cne $ExpectedId) { Stop-W0 "$Label id mismatch" }
}

function Get-AdmitInvocation([object]$Context, [object]$ChallengeContext) {
    $entryCopy = ConvertTo-NormalizedPath (
        (Join-Path $ChallengeContext.TempRoot ([string]$Context.Runtime.validatorEntrypoint.copyPath))) $true
    $argv = @($Context.Python) + @($Context.Runtime.pythonExecutable.fixedArgs) + @(
        $entryCopy,'--installed-skill-root',$Context.Skill,'--run-authorization',
        '--project-root',$Context.Project,'--package',$Context.Package,
        '--provenance-config',$Context.ConfigPath,
        '--expected-config-sha256',$ExpectedConfigSha256,
        '--launch-challenge',$ChallengeContext.Path,
        '--run-presentation',(ConvertTo-NormalizedPath $PresentationPath $true),
        '--run-human-challenge',(ConvertTo-NormalizedPath $HumanChallengePath $true),
        '--run-transcript',(ConvertTo-NormalizedPath $TranscriptPath $true),
        '--run-statement',(ConvertTo-NormalizedPath $StatementPath $true),
        '--run-capture',(ConvertTo-NormalizedPath $CapturePath $true),
        '--run-capture-provenance',(ConvertTo-NormalizedPath $CaptureProvenancePath $true),
        '--run-authorization-record',(ConvertTo-NormalizedPath $RunAuthorizationPath $true),
        '--run-admission',(ConvertTo-NormalizedPath $RunAdmissionAttestationPath $true),
        '--run-admission-signature',(ConvertTo-NormalizedPath $RunAdmissionSignaturePath $true),
        '--json')
    return [ordered]@{Argv=$argv;Environment=Get-ClosedEnvironment}
}

function Get-AdmitHostArgv([object]$Context) {
    return Get-CanonicalHostArgv $Context @(
        '-Phase','ADMIT','-ConfigPath',$Context.ConfigPath,
        '-ExpectedConfigSha256',$ExpectedConfigSha256,'-PackagePath',$Context.Package,
        '-ProjectRoot',$Context.Project,'-LaunchChallengePath',(ConvertTo-NormalizedPath $LaunchChallengePath $true),
        '-PresentationPath',(ConvertTo-NormalizedPath $PresentationPath $true),
        '-HumanChallengePath',(ConvertTo-NormalizedPath $HumanChallengePath $true),
        '-TranscriptPath',(ConvertTo-NormalizedPath $TranscriptPath $true),
        '-StatementPath',(ConvertTo-NormalizedPath $StatementPath $true),
        '-CapturePath',(ConvertTo-NormalizedPath $CapturePath $true),
        '-CaptureProvenancePath',(ConvertTo-NormalizedPath $CaptureProvenancePath $true),
        '-RunAuthorizationPath',(ConvertTo-NormalizedPath $RunAuthorizationPath $true),
        '-RunAdmissionAttestationPath',(ConvertTo-NormalizedPath $RunAdmissionAttestationPath $true),
        '-RunAdmissionSignaturePath',(ConvertTo-NormalizedPath $RunAdmissionSignaturePath $true),
        '-AdmitExecutionAttestationPath',(ConvertTo-NormalizedPath $AdmitExecutionAttestationPath $true),
        '-AdmitExecutionSignaturePath',(ConvertTo-NormalizedPath $AdmitExecutionSignaturePath $true))
}

function Get-CanonicalHostArgv([object]$Context, [object[]]$PhaseTail) {
    # Protocol argv is not Environment.GetCommandLineArgs(): on .NET that
    # begins with pwsh.dll and retains caller-specific slash/case spelling.
    # The authority observes the actual launch, resolves every path identity,
    # and signs this deterministic pinned-host canonical projection.
    return @($Context.HostBinary) + @($Context.Bootstrap.hostFixedArgs) +
        @($Context.BootstrapScript) + @($PhaseTail)
}

function Assert-AdmissionSemanticOrder([object]$AdmittedAt,
                                       [DateTimeOffset]$SemanticStartedAt) {
    $admitted=ConvertTo-Time $AdmittedAt 'run admission admittedAt'
    if ($admitted -gt $SemanticStartedAt) {
        Stop-W0 'run admission admittedAt must precede semantic validator start'
    }
}

function Merge-ReadRecords([object[]]$Sets) {
    $map=[Collections.Generic.Dictionary[string,object]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($set in $Sets) {
        foreach($row in @($set)) {
            $path=ConvertTo-NormalizedPath ([string]$row.path) $true
            $normalized=[ordered]@{path=$path;bytes=[int64]$row.bytes;sha256=[string]$row.sha256}
            if ($map.ContainsKey($path) -and
                (ConvertTo-CanonicalJson $map[$path]) -cne (ConvertTo-CanonicalJson $normalized)) {
                Stop-W0 "read input path has conflicting records: $path"
            }
            $map[$path]=$normalized
        }
    }
    [string[]]$keys=@($map.Keys)
    [Array]::Sort($keys,[Comparison[string]]{param($left,$right);Compare-CodePointString $left $right})
    return @($keys | ForEach-Object {$map[$_]})
}

function Get-AbsoluteTreeReadRecords([string]$Root) {
    $resolved=ConvertTo-NormalizedPath $Root $true
    return @(Get-TreeRecords $resolved | ForEach-Object {
        [ordered]@{
            path=ConvertTo-NormalizedPath (Join-Path $resolved ([string]$_.path)) $true
            bytes=[int64]$_.bytes;sha256=[string]$_.sha256
        }
    })
}

function Assert-ReceiptFreshIdentifiers([Collections.IDictionary]$Capability,
                                        [Collections.IDictionary]$Consumption,
                                        [Collections.IDictionary]$AdmissionToken,
                                        [Collections.IDictionary]$Challenge) {
    Assert-JsonStringMinimum $AdmissionToken.eventId 1 'run admission.oneTimeAdmission.eventId'
    Assert-JsonFramedStringMinimum $AdmissionToken.nonce 32 `
        'run admission.oneTimeAdmission.nonce'
    Assert-JsonStringMinimum $Consumption.consumptionEventId 1 `
        'receipt.oneTimeAdmissionConsumption.consumptionEventId'
    Assert-JsonStringMinimum $Capability.eventId 1 'receipt.workerReadyCapability.eventId'
    Assert-JsonFramedStringMinimum $Capability.nonce 32 'receipt.workerReadyCapability.nonce'
    if ($Consumption.consumptionEventId -ceq $AdmissionToken.eventId -or
        $Capability.eventId -ceq $Consumption.consumptionEventId -or
        $Capability.eventId -ceq $AdmissionToken.eventId -or
        $AdmissionToken.nonce -ceq $Challenge.receiverNonce -or
        $Capability.nonce -ceq $AdmissionToken.nonce -or
        $Capability.nonce -ceq $Challenge.receiverNonce) {
        Stop-W0 'receipt admission/capability event or nonce replay detected'
    }
}

function Assert-ReceiptChronology([DateTimeOffset]$SemanticEnd,
                                  [Collections.IDictionary]$Consumption,
                                  [Collections.IDictionary]$Worker,
                                  [Collections.IDictionary]$Capability,
                                  [object]$ReceiptAttestedAt,
                                  [object]$AdmissionExpiresAt,
                                  [object]$RunAuthorizationExpiresAt,
                                  [object]$TransferExpiresAt,
                                  [DateTimeOffset]$Now,
                                  [int64]$MaximumLifetimeSeconds,
                                  [int64]$MaximumClockSkewSeconds) {
    $consumedAt=ConvertTo-Time $Consumption.consumedAt 'receipt.consumedAt'
    $launchedAt=ConvertTo-Time $Worker.launchedAt 'receipt.worker.launchedAt'
    $observedAt=ConvertTo-Time $Worker.observedAt 'receipt.worker.observedAt'
    $issuedAt=ConvertTo-Time $Capability.issuedAt 'receipt.capability.issuedAt'
    $attestedAt=ConvertTo-Time $ReceiptAttestedAt 'receipt.attestedAt'
    $capExpires=ConvertTo-Time $Capability.expiresAt 'receipt.capability.expiresAt'
    $admissionExpires=ConvertTo-Time $AdmissionExpiresAt 'admission expiry'
    $runExpires=ConvertTo-Time $RunAuthorizationExpiresAt 'run authorization expiry'
    $transferExpires=ConvertTo-Time $TransferExpiresAt 'transfer expiry'
    $effective=$runExpires
    if ($transferExpires -lt $effective) {$effective=$transferExpires}
    if ($admissionExpires -lt $effective) {$effective=$admissionExpires}
    $capabilityDelta=$capExpires-$issuedAt
    Assert-JsonIntegerRange $Capability.lifetimeSeconds 1 60 `
        'receipt.workerReadyCapability.lifetimeSeconds'
    if ($SemanticEnd -gt $consumedAt -or $consumedAt -ge $admissionExpires -or
        $consumedAt -ge $launchedAt -or $launchedAt -gt $observedAt -or
        $observedAt -gt $issuedAt -or $issuedAt -gt $attestedAt -or
        $attestedAt -ge $capExpires -or $capExpires -gt $effective -or
        $capabilityDelta.Ticks % [TimeSpan]::TicksPerSecond -ne 0 -or
        [int64]$Capability.lifetimeSeconds -ne [int64]$capabilityDelta.TotalSeconds -or
        [int64]$Capability.lifetimeSeconds -gt $MaximumLifetimeSeconds -or
        $attestedAt -gt $Now.AddSeconds($MaximumClockSkewSeconds) -or
        $Now -ge $capExpires) {
        Stop-W0 'receipt/capability chronology or expiry mismatch'
    }
    return $capExpires
}

function Assert-AdmitExecutionReceipt([object]$Context,[object]$ChallengeContext,
                                      [object]$AdmissionSigned,[object]$SemanticResult,
                                      [object]$Invocation,[object]$FullReadRecords,
                                      [object]$FullIdentityRecords) {
    $signed=Read-VerifiedSignedJson $AdmitExecutionAttestationPath `
        $AdmitExecutionSignaturePath $Context $script:AdmitExecutionKeys `
        'ADMIT execution receipt'
    $value=$signed.Value;$challenge=$ChallengeContext.Value
    $Admission=$AdmissionSigned.Value
    Assert-JsonFramedStringMinimum $value.runId 16 'receipt.runId'
    Assert-JsonStringMinimum $value.receiverNonce 32 'receipt.receiverNonce'
    Assert-JsonStringMinimum $value.authoritySessionId 16 'receipt.authoritySessionId'
    Assert-JsonStringMinimum $value.monitorSessionId 16 'receipt.monitorSessionId'
    Assert-JsonBoolean $value.productSideEffectsStarted $false 'receipt.productSideEffectsStarted'
    Assert-JsonInteger $value.projectPackageSkillWriteCount 0 'receipt.projectPackageSkillWriteCount'
    if ($value.id -isnot [string] -or
        $value.id -cnotmatch '^W0-RUNTIME-ADMIT-[A-Z0-9][A-Z0-9._-]*$' -or
        $value.schemaVersion -cne '1.0.0' -or
        $value.kind -cne 'w0-runtime-admit-execution-v1' -or
        $value.runId -cne $challenge.runId -or $value.receiverNonce -cne $challenge.receiverNonce -or
        $value.authoritySessionId -cne $Admission.authoritySessionId -or
        $value.monitorSessionId -cne $Admission.monitorSessionId -or
        $value.operatorExpectedConfigSha256 -cne $ExpectedConfigSha256 -or
        $value.configSha256 -cne $ExpectedConfigSha256 -or
        $value.productSideEffectsStarted -ne $false -or
        [int]$value.projectPackageSkillWriteCount -ne 0 -or
        $value.authorizationEvidenceWritePolicy -cne
            'only-predeclared-admit-receipt-and-detached-signature-after-semantic-pass-v1' -or
        $value.verdict -cne 'ready-for-bootstrap-pass-and-one-scoped-first-effect') {
        Stop-W0 'ADMIT execution receipt fixed/config/session fields mismatch'
    }
    $outputs=$value.receiptOutputs
    Assert-ExactKeys $outputs @('attestationPath','detachedSignaturePath') 'receipt.receiptOutputs'
    Assert-ExactKeyOrder $outputs @('attestationPath','detachedSignaturePath') 'receipt.receiptOutputs'
    if ((ConvertTo-NormalizedPath ([string]$outputs.attestationPath) $true) -cne
            (ConvertTo-NormalizedPath $AdmitExecutionAttestationPath $true) -or
        (ConvertTo-NormalizedPath ([string]$outputs.detachedSignaturePath) $true) -cne
            (ConvertTo-NormalizedPath $AdmitExecutionSignaturePath $true)) {
        Stop-W0 'receipt output self-binding mismatch'
    }
    $runAdmission=$value.runAdmission
    Assert-ExactKeys $runAdmission @(
        'id','path','sha256','fileIdentity','detachedSignaturePath','detachedSignatureSha256',
        'detachedSignatureFileIdentity','scopeCoreSha256','oneTimeTokenSha256') 'receipt.runAdmission'
    Assert-ExactKeyOrder $runAdmission @(
        'id','path','sha256','fileIdentity','detachedSignaturePath','detachedSignatureSha256',
        'detachedSignatureFileIdentity','scopeCoreSha256','oneTimeTokenSha256') 'receipt.runAdmission'
    $admissionAuth=$Admission.runAuthorization
    $admissionToken=$Admission.oneTimeAdmission
    if ($runAdmission.id -cne $Admission.id -or
        (ConvertTo-NormalizedPath ([string]$runAdmission.path) $true) -cne
            $AdmissionSigned.Path -or
        $runAdmission.sha256 -cne $AdmissionSigned.Sha256 -or
        $runAdmission.fileIdentity -cne $AdmissionSigned.FileIdentity -or
        (ConvertTo-NormalizedPath ([string]$runAdmission.detachedSignaturePath) $true) -cne
            $AdmissionSigned.SignaturePath -or
        $runAdmission.detachedSignatureSha256 -cne $AdmissionSigned.SignatureSha256 -or
        $runAdmission.detachedSignatureFileIdentity -cne $AdmissionSigned.SignatureFileIdentity -or
        $runAdmission.scopeCoreSha256 -cne $admissionAuth.scopeCoreSha256 -or
        $runAdmission.oneTimeTokenSha256 -cne $admissionToken.tokenSha256) {
        Stop-W0 'receipt runAdmission bytes/identity/token mismatch'
    }
    $lock=$value.lock
    Assert-ExactKeys $lock @('noGapFrom','through','enforcementSessionId','enforcementActive') 'receipt.lock'
    Assert-ExactKeyOrder $lock @('noGapFrom','through','enforcementSessionId','enforcementActive') 'receipt.lock'
    Assert-JsonBoolean $lock.enforcementActive $true 'receipt.lock.enforcementActive'
    if ($lock.noGapFrom -cne 'prelaunch' -or
        $lock.through -cne 'bootstrap-pass-and-first-effect-release' -or
        $lock.enforcementSessionId -cne $Admission.monitorSessionId -or
        $lock.enforcementActive -ne $true) { Stop-W0 'receipt continuous lock mismatch' }

    $admitHost=$value.admitHost
    Assert-ExactKeys $admitHost @(
        'hostExecutableSha256','bootstrapScriptSha256','hostRuntimeClosureSha256',
        'loadedClosureSha256','argvSha256','cwdSha256','envSha256','loadedClosureMatchesConfig',
        'argvMatchesProtocol','cwdMatches','envClosed','monitorStartedBeforeProcess') 'receipt.admitHost'
    Assert-ExactKeyOrder $admitHost @(
        'hostExecutableSha256','bootstrapScriptSha256','hostRuntimeClosureSha256',
        'loadedClosureSha256','argvSha256','cwdSha256','envSha256','loadedClosureMatchesConfig',
        'argvMatchesProtocol','cwdMatches','envClosed','monitorStartedBeforeProcess') 'receipt.admitHost'
    foreach($field in @('loadedClosureMatchesConfig','argvMatchesProtocol','cwdMatches',
                         'envClosed','monitorStartedBeforeProcess')) {
        Assert-JsonBoolean $admitHost[$field] $true ("receipt.admitHost."+$field)
    }
    $hostClosure=@(Sort-RecordsByCodePoint @($Context.Bootstrap.hostRuntimeRoots | ForEach-Object {
        [ordered]@{path=[string]$_.path;treeSha256=[string]$_.treeSha256}}) 'path')
    if ($admitHost.hostExecutableSha256 -cne (Get-Sha256File $Context.HostBinary) -or
        $admitHost.bootstrapScriptSha256 -cne (Get-Sha256File $Context.BootstrapScript) -or
        $admitHost.hostRuntimeClosureSha256 -cne (Get-CanonicalSha256 $hostClosure) -or
        $admitHost.argvSha256 -cne (Get-JoinedSha256 (Get-AdmitHostArgv $Context)) -or
        $admitHost.cwdSha256 -cne (Get-Sha256Bytes ($script:Utf8.GetBytes(
            (ConvertTo-NormalizedPath (Get-Location).Path $true)))) -or
        $admitHost.envSha256 -cne (Get-EnvironmentSha256 (Get-ClosedEnvironment)) -or
        $admitHost.loadedClosureSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $admitHost.loadedClosureMatchesConfig -ne $true -or
        $admitHost.argvMatchesProtocol -ne $true -or
        $admitHost.cwdMatches -ne $true -or $admitHost.envClosed -ne $true -or
        $admitHost.monitorStartedBeforeProcess -ne $true) {
        Stop-W0 'receipt ADMIT host facts mismatch'
    }

    $semantic=$value.semanticValidator
    Assert-ExactKeys $semantic @(
        'pythonExecutableSha256','validatorEntrypointSha256','pythonRuntimeClosureSha256',
        'loadedClosureSha256','resolvedTempRoot','tempRootIdentity','tempCopySetSha256',
        'readInputSetSha256','readInputIdentitySetSha256','argvSha256','cwdSha256','envSha256',
        'loadedClosureMatchesConfig','tempCopySetMatches','readInputClosureMatches','argvMatches',
        'cwdMatches','envClosed','resultSha256','result','startedAt','completedAt','exitCode') `
        'receipt.semanticValidator'
    Assert-ExactKeyOrder $semantic @(
        'pythonExecutableSha256','validatorEntrypointSha256','pythonRuntimeClosureSha256',
        'loadedClosureSha256','resolvedTempRoot','tempRootIdentity','tempCopySetSha256',
        'readInputSetSha256','readInputIdentitySetSha256','argvSha256','cwdSha256','envSha256',
        'loadedClosureMatchesConfig','tempCopySetMatches','readInputClosureMatches','argvMatches',
        'cwdMatches','envClosed','resultSha256','result','startedAt','completedAt','exitCode') `
        'receipt.semanticValidator'
    Assert-ExactKeyOrder $semantic.result @(
        'pass','errors','mode','authorizationId','admissionId','oneTimeTokenSha256') `
        'receipt.semanticValidator.result'
    foreach($field in @('loadedClosureMatchesConfig','tempCopySetMatches',
                         'readInputClosureMatches','argvMatches','cwdMatches','envClosed')) {
        Assert-JsonBoolean $semantic[$field] $true ("receipt.semanticValidator."+$field)
    }
    Assert-JsonInteger $semantic.exitCode 0 'receipt.semanticValidator.exitCode'
    Assert-JsonBoolean $semantic.result.pass $true 'receipt.semanticValidator.result.pass'
    $pythonClosure=@(Sort-RecordsByCodePoint @($Context.Runtime.readOnlyLibraryRoots | ForEach-Object {
        [ordered]@{path=[string]$_.path;treeSha256=[string]$_.treeSha256}}) 'path')
    if ($semantic.pythonExecutableSha256 -cne [string]$Context.Runtime.pythonExecutable.sha256 -or
        $semantic.validatorEntrypointSha256 -cne [string]$Context.Runtime.validatorEntrypoint.sha256 -or
        $semantic.pythonRuntimeClosureSha256 -cne (Get-CanonicalSha256 $pythonClosure) -or
        $semantic.loadedClosureSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        (ConvertTo-NormalizedPath ([string]$semantic.resolvedTempRoot) $true) -cne
            $ChallengeContext.TempRoot -or
        $semantic.tempRootIdentity -cne (Get-PathIdentity $ChallengeContext.TempRoot) -or
        $semantic.tempCopySetSha256 -cne $challenge.tempCopySetSha256 -or
        $semantic.readInputSetSha256 -cne (Get-CanonicalSha256 $FullReadRecords) -or
        $semantic.readInputIdentitySetSha256 -cne (Get-CanonicalSha256 $FullIdentityRecords) -or
        $semantic.argvSha256 -cne (Get-JoinedSha256 $Invocation.Argv) -or
        $semantic.cwdSha256 -cne (Get-Sha256Bytes ($script:Utf8.GetBytes($ChallengeContext.TempRoot))) -or
        $semantic.envSha256 -cne (Get-EnvironmentSha256 $Invocation.Environment) -or
        $semantic.loadedClosureMatchesConfig -ne $true -or $semantic.tempCopySetMatches -ne $true -or
        $semantic.readInputClosureMatches -ne $true -or $semantic.argvMatches -ne $true -or
        $semantic.cwdMatches -ne $true -or $semantic.envClosed -ne $true -or
        [int]$semantic.exitCode -ne 0 -or
        (ConvertTo-CanonicalJson $semantic.result) -cne (ConvertTo-CanonicalJson $SemanticResult.Value) -or
        $semantic.resultSha256 -cne (Get-CanonicalSha256 $SemanticResult.Value)) {
        Stop-W0 'receipt semantic validator facts/result mismatch'
    }
    $semanticStart=ConvertTo-Time $semantic.startedAt 'receipt.semanticValidator.startedAt'
    $semanticEnd=ConvertTo-Time $semantic.completedAt 'receipt.semanticValidator.completedAt'
    Assert-AdmissionSemanticOrder $Admission.authorizationChronology.admittedAt $semanticStart
    if ($semanticStart -gt $SemanticResult.StartedAt -or
        $semanticEnd -lt $SemanticResult.CompletedAt -or $semanticStart -gt $semanticEnd) {
        Stop-W0 'receipt semantic validator chronology does not enclose actual process'
    }

    $consumption=$value.oneTimeAdmissionConsumption
    Assert-ExactKeys $consumption @(
        'registryAuthority','registryId','admissionEventId','consumptionEventId','tokenSha256',
        'admissionExpiresAt','consumedAt','consumed','atomic',
        'semanticPassCompletedBeforeConsumption','workerLaunchStartedAfterConsumption') `
        'receipt.oneTimeAdmissionConsumption'
    foreach($field in @('registryAuthority','registryId','admissionEventId','consumptionEventId')) {
        Assert-JsonStringMinimum $consumption[$field] 1 `
            ("receipt.oneTimeAdmissionConsumption."+$field)
    }
    Assert-ExactKeyOrder $consumption @(
        'registryAuthority','registryId','admissionEventId','consumptionEventId','tokenSha256',
        'admissionExpiresAt','consumedAt','consumed','atomic',
        'semanticPassCompletedBeforeConsumption','workerLaunchStartedAfterConsumption') `
        'receipt.oneTimeAdmissionConsumption'
    foreach($field in @('consumed','atomic','semanticPassCompletedBeforeConsumption',
                         'workerLaunchStartedAfterConsumption')) {
        Assert-JsonBoolean $consumption[$field] $true `
            ("receipt.oneTimeAdmissionConsumption."+$field)
    }
    if ($consumption.registryAuthority -cne $admissionToken.registryAuthority -or
        $consumption.registryId -cne $admissionToken.registryId -or
        $consumption.admissionEventId -cne $admissionToken.eventId -or
        [string]::IsNullOrWhiteSpace([string]$consumption.consumptionEventId) -or
        $consumption.consumptionEventId -ceq $admissionToken.eventId -or
        $consumption.tokenSha256 -cne $admissionToken.tokenSha256 -or
        $consumption.admissionExpiresAt -cne $Admission.admissionExpiresAt -or
        $consumption.consumed -ne $true -or $consumption.atomic -ne $true -or
        $consumption.semanticPassCompletedBeforeConsumption -ne $true -or
        $consumption.workerLaunchStartedAfterConsumption -ne $true) {
        Stop-W0 'receipt admission token consumption mismatch'
    }

    $worker=$value.workerReady
    Assert-ExactKeys $worker @(
        'skillId','skillVersion','skillPath','skillSha256','receiverSkillTreeSha256','workerId',
        'requestedModel','resolvedModel','provider','account','tool',
        'expectedLoadedProcessClosureSha256','actualLoadedProcessClosureSha256',
        'actualLoadedIdentitySha256','envelopeSha256','skillTreeMatchesAuthorization',
        'closureMatchesExpected','identityMatchesAuthorization','launchMode','workerProcessIdentity',
        'launchedAt','observedAt','productEntryExecuted') 'receipt.workerReady'
    Assert-ExactKeyOrder $worker @(
        'skillId','skillVersion','skillPath','skillSha256','receiverSkillTreeSha256','workerId',
        'requestedModel','resolvedModel','provider','account','tool',
        'expectedLoadedProcessClosureSha256','actualLoadedProcessClosureSha256',
        'actualLoadedIdentitySha256','envelopeSha256','skillTreeMatchesAuthorization',
        'closureMatchesExpected','identityMatchesAuthorization','launchMode','workerProcessIdentity',
        'launchedAt','observedAt','productEntryExecuted') 'receipt.workerReady'
    foreach($field in @('skillTreeMatchesAuthorization','closureMatchesExpected',
                         'identityMatchesAuthorization')) {
        Assert-JsonBoolean $worker[$field] $true ("receipt.workerReady."+$field)
    }
    Assert-JsonBoolean $worker.productEntryExecuted $false 'receipt.workerReady.productEntryExecuted'
    Assert-JsonFramedStringMinimum $worker.workerProcessIdentity 1 `
        'receipt.workerReady.workerProcessIdentity'
    $expectedReceiver=$Admission.receiver
    foreach($field in @('skillId','skillVersion','skillPath','workerId','requestedModel',
                         'resolvedModel','provider','account','tool')) {
        Assert-JsonStringMinimum $worker[$field] 1 ("receipt.workerReady."+$field)
    }
    foreach($pair in @(
        @('skillId','skillId'),@('skillVersion','skillVersion'),@('skillPath','skillPath'),
        @('skillSha256','skillSha256'),@('receiverSkillTreeSha256','receiverSkillTreeSha256'),
        @('workerId','workerId'),@('requestedModel','requestedModel'),@('resolvedModel','resolvedModel'),
        @('provider','provider'),@('account','account'),@('tool','tool'),
        @('expectedLoadedProcessClosureSha256','expectedLoadedProcessClosureSha256'),
        @('envelopeSha256','envelopeSha256'))) {
        Assert-Value $worker[$pair[0]] $expectedReceiver[$pair[1]] ("receipt.workerReady."+$pair[0])
    }
    $identityProjection=[ordered]@{
        skillSha256=$worker.skillSha256;receiverSkillTreeSha256=$worker.receiverSkillTreeSha256
        workerId=$worker.workerId;requestedModel=$worker.requestedModel;resolvedModel=$worker.resolvedModel
        provider=$worker.provider;account=$worker.account;tool=$worker.tool
        expectedLoadedProcessClosureSha256=$worker.expectedLoadedProcessClosureSha256
        actualLoadedProcessClosureSha256=$worker.actualLoadedProcessClosureSha256}
    if ($worker.expectedLoadedProcessClosureSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $worker.actualLoadedProcessClosureSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $worker.actualLoadedProcessClosureSha256 -cne $worker.expectedLoadedProcessClosureSha256 -or
        $worker.actualLoadedIdentitySha256 -cne (Get-CanonicalSha256 $identityProjection) -or
        $worker.skillTreeMatchesAuthorization -ne $true -or $worker.closureMatchesExpected -ne $true -or
        $worker.identityMatchesAuthorization -ne $true -or
        $worker.launchMode -cne 'authority-suspended-pre-entry-under-scope-enforcement-v1' -or
        [string]::IsNullOrWhiteSpace([string]$worker.workerProcessIdentity) -or
        $worker.productEntryExecuted -ne $false) { Stop-W0 'receipt assigned-worker identity/readiness mismatch' }

    $capability=$value.workerReadyCapability
    Assert-ExactKeys $capability @(
        'registryAuthority','eventId','nonce','capabilitySha256','issuedAt','lifetimeSeconds',
        'runAuthorizationExpiresAt','transferExpiresAt','admissionExpiresAt','effectiveExpiry',
        'expiresAt','globalNonreuse','consumed','consumptionPolicy') 'receipt.workerReadyCapability'
    Assert-ExactKeyOrder $capability @(
        'registryAuthority','eventId','nonce','capabilitySha256','issuedAt','lifetimeSeconds',
        'runAuthorizationExpiresAt','transferExpiresAt','admissionExpiresAt','effectiveExpiry',
        'expiresAt','globalNonreuse','consumed','consumptionPolicy') 'receipt.workerReadyCapability'
    Assert-JsonBoolean $capability.globalNonreuse $true 'receipt.workerReadyCapability.globalNonreuse'
    Assert-JsonBoolean $capability.consumed $false 'receipt.workerReadyCapability.consumed'
    Assert-JsonIntegerRange $capability.lifetimeSeconds 1 60 `
        'receipt.workerReadyCapability.lifetimeSeconds'
    Assert-JsonStringMinimum $capability.registryAuthority 1 `
        'receipt.workerReadyCapability.registryAuthority'
    Assert-JsonStringMinimum $capability.eventId 1 'receipt.workerReadyCapability.eventId'
    Assert-JsonFramedStringMinimum $capability.nonce 32 `
        'receipt.workerReadyCapability.nonce'
    $runAuth=Read-StrictJson $RunAuthorizationPath
    $runExpiry=[string]$runAuth.scopeCore.expiresAt
    $transferExpiry=[string]$runAuth.scopeCore.transfer.expiresAt
    $admissionExpiry=[string]$Admission.admissionExpiresAt
    $deadlineRows=@(
        [ordered]@{text=$runExpiry;time=ConvertTo-Time $runExpiry 'run authorization expiry'},
        [ordered]@{text=$transferExpiry;time=ConvertTo-Time $transferExpiry 'transfer expiry'},
        [ordered]@{text=$admissionExpiry;time=ConvertTo-Time $admissionExpiry 'admission expiry'})
    $effective=($deadlineRows | Sort-Object time | Select-Object -First 1)
    Assert-ReceiptFreshIdentifiers $capability $consumption $admissionToken $challenge
    $capabilityBytes=$script:Utf8.GetBytes(
        'W0-WORKER-READY-v1'+[char]0+[string]$value.id+[char]0+[string]$value.runId+[char]0+
        [string]$runAdmission.scopeCoreSha256+[char]0+[string]$worker.workerProcessIdentity+[char]0+
        [string]$capability.nonce)
    if ($capability.registryAuthority -cne $consumption.registryAuthority -or
        $capability.capabilitySha256 -cne (Get-Sha256Bytes $capabilityBytes) -or
        $capability.runAuthorizationExpiresAt -cne $runExpiry -or
        $capability.transferExpiresAt -cne $transferExpiry -or
        $capability.admissionExpiresAt -cne $admissionExpiry -or
        $capability.effectiveExpiry -cne $effective.text -or
        $capability.globalNonreuse -ne $true -or $capability.consumed -ne $false -or
        $capability.consumptionPolicy -cne
            'authority-atomic-consume-only-after-bootstrap-pass-before-one-scoped-first-effect-v1') {
        Stop-W0 'receipt worker-ready capability binding mismatch'
    }
    $capExpires=Assert-ReceiptChronology $semanticEnd $consumption $worker $capability `
        $value.attestedAt $Admission.admissionExpiresAt $runExpiry $transferExpiry `
        ([DateTimeOffset]::UtcNow) ([int64]$Context.Authority.maxWorkerReadyLifetimeSeconds) `
        ([int64]$Context.Authority.maxClockSkewSeconds)
    $bootstrapState=$value.bootstrapState
    Assert-ExactKeys $bootstrapState @(
        'semanticPassObserved','bootstrapWaitingForReceipt','bootstrapPassEmitted',
        'workerSuspendedBeforeProductEntry') 'receipt.bootstrapState'
    Assert-ExactKeyOrder $bootstrapState @(
        'semanticPassObserved','bootstrapWaitingForReceipt','bootstrapPassEmitted',
        'workerSuspendedBeforeProductEntry') 'receipt.bootstrapState'
    Assert-JsonBoolean $bootstrapState.semanticPassObserved $true `
        'receipt.bootstrapState.semanticPassObserved'
    Assert-JsonBoolean $bootstrapState.bootstrapWaitingForReceipt $true `
        'receipt.bootstrapState.bootstrapWaitingForReceipt'
    Assert-JsonBoolean $bootstrapState.bootstrapPassEmitted $false `
        'receipt.bootstrapState.bootstrapPassEmitted'
    Assert-JsonBoolean $bootstrapState.workerSuspendedBeforeProductEntry $true `
        'receipt.bootstrapState.workerSuspendedBeforeProductEntry'
    if ($bootstrapState.semanticPassObserved -ne $true -or
        $bootstrapState.bootstrapWaitingForReceipt -ne $true -or
        $bootstrapState.bootstrapPassEmitted -ne $false -or
        $bootstrapState.workerSuspendedBeforeProductEntry -ne $true) {
        Stop-W0 'receipt bootstrap pre-PASS state mismatch'
    }
    return [ordered]@{Signed=$signed;Value=$value;CapabilityExpiresAt=$capExpires}
}

function Invoke-Admit {
    Assert-ExactPhaseParameters 'ADMIT'
    Assert-ExpectedConfigHash
    $context = Read-And-ValidateConfig $ConfigPath $ProjectRoot $PackagePath
    $challengeContext = Read-And-ValidateChallenge $context $LaunchChallengePath
    $extraProtected = @($context.Protected + $challengeContext.TempRoot)
    $paths = @($PresentationPath,$HumanChallengePath,$TranscriptPath,$StatementPath,
               $CapturePath,$CaptureProvenancePath,$RunAuthorizationPath,
               $RunAdmissionAttestationPath,$RunAdmissionSignaturePath)
    $normalized = @($paths | ForEach-Object {
        Assert-ExternalPath $_ $extraProtected $true
    })
    $outputPaths=@($AdmitExecutionAttestationPath,$AdmitExecutionSignaturePath)
    $normalizedOutputs=@($outputPaths | ForEach-Object {
        $path=Assert-ExternalPath $_ $extraProtected $false
        if (Test-Path -LiteralPath $path) { Stop-W0 'ADMIT receipt outputs must be absent before semantic PASS' }
        $path
    })
    $pathSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $identitySet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($path in $normalized){$pathSet.Add($path)|Out-Null;$identitySet.Add((Get-PathIdentity $path))|Out-Null}
    foreach($path in $normalizedOutputs){$pathSet.Add($path)|Out-Null}
    if ($normalized.Count -ne 9 -or $normalizedOutputs.Count -ne 2 -or
        $pathSet.Count -ne 11 -or $identitySet.Count -ne 9) {
        Stop-W0 'ADMIT requires eleven distinct operator-external input/output paths'
    }
    foreach ($path in @($normalized + $normalizedOutputs)) {
        if (-not (Test-Within $path $challengeContext.AuthorizationRoot)) {
            Stop-W0 'every ADMIT input/output must stay inside the predeclared authorization evidence root'
        }
    }
    # Establish the signed trust root before following any path learned from
    # the authorization record.  The signed admission exact-binds the explicit
    # CLI authorization bytes and OS identity.
    $admission = Read-VerifiedSignedJson ($RunAdmissionAttestationPath) `
        $RunAdmissionSignaturePath $context $script:AdmissionKeys 'run admission attestation'
    $value = $admission.Value
    if ($value.schemaVersion -cne '1.0.0' -or $value.kind -cne 'w0-run-admission-v1' -or
        $value.id -isnot [string] -or
        $value.id -cnotmatch '^W0-RUN-ADMISSION-[A-Z0-9][A-Z0-9._-]*$' -or
        $value.operatorExpectedConfigSha256 -cne $ExpectedConfigSha256 -or
        $value.configSha256 -cne $ExpectedConfigSha256 -or
        $value.w0RunId -cne $challengeContext.Value.runId) {
        Stop-W0 'signed admission is for a different config/run or has invalid identity'
    }
    $earlyAuthorization=$value.runAuthorization
    Assert-ExactKeys $earlyAuthorization @(
        'id','path','sha256','fileIdentity','scopeCoreSha256','humanChain','capture',
        'provenanceVerification') 'run admission.runAuthorization'
    if ((ConvertTo-NormalizedPath ([string]$earlyAuthorization.path) $true) -cne
            (ConvertTo-NormalizedPath $RunAuthorizationPath $true) -or
        [string]$earlyAuthorization.sha256 -cne (Get-Sha256File $RunAuthorizationPath) -or
        [string]$earlyAuthorization.fileIdentity -cne (Get-PathIdentity $RunAuthorizationPath)) {
        Stop-W0 'signed admission does not bind explicit run authorization bytes/identity'
    }
    # The semantic ADMIT pass also reads the retained VALIDATE post proof and
    # the complete assigned receiver Skill tree.  They are outside the auth
    # root, so bind them explicitly into the continuously locked read closure.
    $authorizationPreview=Read-StrictJson $RunAuthorizationPath
    $postRef=$authorizationPreview.scopeCore.bootstrap.postexecutionAttestation
    Assert-ExactKeys $postRef @('path','sha256') `
        'run authorization postexecutionAttestation ref'
    $postPath=Assert-ExternalPath ([string]$postRef.path) $extraProtected $true
    if ((Test-Within $postPath $challengeContext.AuthorizationRoot) -or
        (Get-Sha256File $postPath) -cne [string]$postRef.sha256 -or
        [W0NativeFileIdentity]::ReadLinkCount($postPath) -ne 1) {
        Stop-W0 'retained postexecution attestation path/hash/identity scope mismatch'
    }
    $receiverSkillRaw=[string]$authorizationPreview.scopeCore.assignedReceiver.skill.path
    $receiverSkill=Assert-ExternalPath $receiverSkillRaw `
        @($extraProtected + $challengeContext.AuthorizationRoot) $true
    if (-not (Test-Path -LiteralPath $receiverSkill -PathType Leaf)) {
        Stop-W0 'assigned receiver Skill entrypoint is not a file'
    }
    $receiverRoot=Assert-ExternalPath ([IO.Path]::GetDirectoryName($receiverSkill)) `
        @($extraProtected + $challengeContext.AuthorizationRoot) $true
    $receiverRecords=@(Get-AbsoluteTreeReadRecords $receiverRoot)
    if ($receiverRecords.Count -lt 1) { Stop-W0 'assigned receiver Skill tree is empty' }
    $lockedRecords=@(Get-ExternalReadSet $context.Config $context.Project $context.ConfigPath `
        $context.Package $challengeContext.TempRoot $challengeContext.Path)
    $challengeInfo=Get-Item -LiteralPath $challengeContext.Path
    $postInfo=Get-Item -LiteralPath $postPath
    $lockedRecords=@(Merge-ReadRecords @(
        $lockedRecords,$receiverRecords,@(
            [ordered]@{path=$challengeContext.Path;bytes=[int64]$challengeInfo.Length;
                sha256=$challengeContext.Sha256},
            [ordered]@{path=$postPath;bytes=[int64]$postInfo.Length;
                sha256=[string]$postRef.sha256})))
    $forbiddenIdentities=Get-IdentitySetForRecords $lockedRecords 'locked bootstrap read set'
    foreach($directory in @($context.Project,$context.Skill,$challengeContext.TempRoot)) {
        $forbiddenIdentities.Add((Get-PathIdentity $directory))|Out-Null
    }
    if ($forbiddenIdentities.Contains((Get-PathIdentity $challengeContext.AuthorizationRoot))) {
        Stop-W0 'authorization root aliases a locked project/skill/temp/read identity'
    }
    foreach($path in $normalized) {
        if ($forbiddenIdentities.Contains((Get-PathIdentity $path))) {
            Stop-W0 'ADMIT input hardlink/identity-aliases a locked project/runtime/read input'
        }
    }
    if ($value.id -isnot [string] -or
        $value.id -cnotmatch '^W0-RUN-ADMISSION-[A-Z0-9][A-Z0-9._-]*$') {
        Stop-W0 'run admission.id pattern mismatch'
    }
    Assert-JsonStringMinimum $value.authoritySessionId 16 'run admission.authoritySessionId'
    Assert-JsonStringMinimum $value.monitorSessionId 16 'run admission.monitorSessionId'
    Assert-JsonFramedStringMinimum $value.w0RunId 16 'run admission.w0RunId'
    foreach($field in @('skillId','skillVersion','skillPath','workerId','requestedModel',
                         'resolvedModel','provider','account','tool')) {
        Assert-JsonStringMinimum $value.receiver[$field] 1 ("run admission.receiver."+$field)
    }
    if ($value.receiver.expectedLoadedProcessClosureSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $value.receiver.receiverSkillTreeSha256 -cnotmatch '^[0-9a-f]{64}$') {
        Stop-W0 'run admission receiver closure/tree digests must be SHA-256'
    }
    Assert-ExactKeyOrder $value.lock @(
        'noGapFrom','through','enforcementSessionId','enforcementActive') 'run admission.lock'
    Assert-ExactKeyOrder $value.authorizationInputExtension @(
        'resolvedRoot','rootIdentity','artifactSetSha256','artifactIdentitySetSha256',
        'proofSealingExclusions') 'run admission.authorizationInputExtension'
    Assert-ExactKeyOrder $value.currentState @(
        'resolvedProjectRoot','projectRootIdentity','projectInputTreeSha256','b2','w0Package',
        'firstWp') 'run admission.currentState'
    Assert-ExactKeyOrder $value.currentState.b2 @(
        'id','path','sha256','fileSetSha256','fileIdentity') 'run admission.currentState.b2'
    foreach($field in @('w0Package','firstWp')) {
        Assert-ExactKeyOrder $value.currentState[$field] @('id','path','sha256','fileIdentity') `
            ("run admission.currentState."+$field)
    }
    Assert-ExactKeyOrder $value.runAuthorization @(
        'id','path','sha256','fileIdentity','scopeCoreSha256','humanChain','capture',
        'provenanceVerification') 'run admission.runAuthorization'
    Assert-ExactKeyOrder $value.runAuthorization.humanChain @(
        'presentation','challenge','transcript','statement') 'run admission.runAuthorization.humanChain'
    foreach($field in @('presentation','challenge','transcript','statement')) {
        Assert-ExactKeyOrder $value.runAuthorization.humanChain[$field] @(
            'path','sha256','fileIdentity') ("run admission.runAuthorization.humanChain."+$field)
    }
    foreach($field in @('capture','provenanceVerification')) {
        Assert-ExactKeyOrder $value.runAuthorization[$field] @('id','path','sha256','fileIdentity') `
            ("run admission.runAuthorization."+$field)
    }
    Assert-ExactKeyOrder $value.receiver @(
        'skillId','skillVersion','skillPath','skillSha256','receiverSkillTreeSha256','workerId',
        'requestedModel','resolvedModel','provider','account','tool',
        'expectedLoadedProcessClosureSha256','envelopeSha256','authorityEnforcementReady',
        'workerLaunchPolicy') 'run admission.receiver'
    Assert-ExactKeyOrder $value.authorizationChronology @(
        'authorizedAt','admittedAt','authorizationExpiresAt') 'run admission.authorizationChronology'
    Assert-ExactKeyOrder $value.oneTimeAdmission @(
        'registryAuthority','registryId','eventId','nonce','tokenSha256','consumed',
        'consumptionPolicy') 'run admission.oneTimeAdmission'
    Assert-ExactKeyOrder $value.admitExecutionReceiptOutputs @(
        'attestationPath','detachedSignaturePath') 'run admission.admitExecutionReceiptOutputs'
    Assert-ExactKeyOrder $value.enforcement @(
        'pathScopeSha256','operationScopeSha256','transferScopeSha256','exactAllowedReadPaths',
        'exactAllowedWritePaths','exactFrozenPaths','exactOperations','exactDeniedOperations',
        'active') 'run admission.enforcement'
    Assert-ExactKeyOrder $value.enforcement.exactOperations @(
        'code','studio','os','network') 'run admission.enforcement.exactOperations'
    Assert-JsonBoolean $value.sideEffectsStarted $false 'run admission.sideEffectsStarted'
    if ($value.schemaVersion -cne '1.0.0' -or $value.kind -cne 'w0-run-admission-v1' -or
        $value.operatorExpectedConfigSha256 -cne $ExpectedConfigSha256 -or
        $value.configSha256 -cne $ExpectedConfigSha256 -or
        $value.w0RunId -cne $challengeContext.Value.runId -or
        $value.sideEffectsStarted -ne $false -or
        $value.verdict -cne 'ready-for-admit-semantic-pass-and-receipt') {
        Stop-W0 'run admission fixed/config/run fields mismatch'
    }
    $extension=$value.authorizationInputExtension
    if ($extension -isnot [Collections.IDictionary] -or
        (ConvertTo-NormalizedPath ([string]$extension.resolvedRoot) $true) -cne
            $challengeContext.AuthorizationRoot -or
        [string]$extension.rootIdentity -cne (Get-PathIdentity $challengeContext.AuthorizationRoot) -or
        ($extension.proofSealingExclusions -join "`0") -cne
            (@('w0-run-admission-attestation','w0-run-admission-detached-signature',
               'w0-runtime-admit-execution-attestation',
               'w0-runtime-admit-execution-detached-signature') -join "`0")) {
        Stop-W0 'run admission authorization input root/exclusions mismatch'
    }
    $sets=Get-AuthorizationInputSets $challengeContext.AuthorizationRoot @(
        $RunAdmissionAttestationPath,$RunAdmissionSignaturePath,
        $AdmitExecutionAttestationPath,$AdmitExecutionSignaturePath) $forbiddenIdentities
    if ([string]$extension.artifactSetSha256 -cne $sets.ArtifactSetSha256 -or
        [string]$extension.artifactIdentitySetSha256 -cne $sets.IdentitySetSha256) {
        Stop-W0 'run admission authorization input bytes/identity set mismatch'
    }
    if ([string]$value.currentState.resolvedProjectRoot -cne $context.Project -or
        [string]$value.currentState.projectRootIdentity -cne (Get-PathIdentity $context.Project) -or
        [string]$value.currentState.projectInputTreeSha256 -cne
            (Get-CanonicalSha256 ([ordered]@{files=@(Get-TreeRecords $context.Project)}))) {
        Stop-W0 'run admission current project root/tree/identity mismatch'
    }
    Assert-IdentifiedFile $value.currentState.w0Package $context.Package ([string]$context.PackageValue.packageId) 'run admission W0 package'
    $b2Path=Join-Path $context.Project ([string]$value.currentState.b2.path)
    Assert-IdentifiedFile $value.currentState.b2 $b2Path ([string]$value.currentState.b2.id) 'run admission B2 manifest'
    $wpPath=Join-Path $context.Project ([string]$value.currentState.firstWp.path)
    Assert-IdentifiedFile $value.currentState.firstWp $wpPath ([string]$value.currentState.firstWp.id) 'run admission first WP'
    Assert-IdentifiedFile $value.runAuthorization $RunAuthorizationPath ([string]$value.runAuthorization.id) 'run admission authorization record'
    $receiptOutputs=$value.admitExecutionReceiptOutputs
    Assert-ExactKeys $receiptOutputs @('attestationPath','detachedSignaturePath') 'run admission receipt outputs'
    if ((ConvertTo-NormalizedPath ([string]$receiptOutputs.attestationPath) $false) -cne
            (ConvertTo-NormalizedPath $AdmitExecutionAttestationPath $false) -or
        (ConvertTo-NormalizedPath ([string]$receiptOutputs.detachedSignaturePath) $false) -cne
            (ConvertTo-NormalizedPath $AdmitExecutionSignaturePath $false)) {
        Stop-W0 'run admission receipt output paths differ from ADMIT argv'
    }
    foreach ($pair in @(
            @($value.runAuthorization.humanChain.presentation,$PresentationPath,'presentation'),
            @($value.runAuthorization.humanChain.challenge,$HumanChallengePath,'challenge'),
            @($value.runAuthorization.humanChain.transcript,$TranscriptPath,'transcript'),
            @($value.runAuthorization.humanChain.statement,$StatementPath,'statement'),
            @($value.runAuthorization.capture,$CapturePath,'capture'),
            @($value.runAuthorization.provenanceVerification,$CaptureProvenancePath,'capture provenance'))) {
        Assert-IdentifiedFile $pair[0] $pair[1] '' ("run admission " + $pair[2])
    }
    Assert-JsonBoolean $value.lock.enforcementActive $true `
        'run admission.lock.enforcementActive'
    Assert-JsonBoolean $value.receiver.authorityEnforcementReady $true `
        'run admission.receiver.authorityEnforcementReady'
    Assert-JsonBoolean $value.oneTimeAdmission.consumed $false `
        'run admission.oneTimeAdmission.consumed'
    foreach($field in @('registryAuthority','registryId','eventId')) {
        Assert-JsonStringMinimum $value.oneTimeAdmission[$field] 1 `
            ("run admission.oneTimeAdmission."+$field)
    }
    Assert-JsonFramedStringMinimum $value.oneTimeAdmission.nonce 32 `
        'run admission.oneTimeAdmission.nonce'
    if ($value.oneTimeAdmission.nonce -ceq $challengeContext.Value.receiverNonce) {
        Stop-W0 'run admission nonce reuses launch challenge receiverNonce'
    }
    Assert-JsonBoolean $value.enforcement.active $true `
        'run admission.enforcement.active'
    Assert-JsonIntegerRange $value.admissionLifetimeSeconds 1 60 `
        'run admission.admissionLifetimeSeconds'
    $admittedAt=ConvertTo-Time $value.authorizationChronology.admittedAt 'run admission admittedAt'
    $admissionExpires=ConvertTo-Time $value.admissionExpiresAt 'run admission admissionExpiresAt'
    $admissionDelta=$admissionExpires-$admittedAt
    if ($admittedAt -ge $admissionExpires -or [DateTimeOffset]::UtcNow -gt $admissionExpires -or
        $admissionDelta.Ticks % [TimeSpan]::TicksPerSecond -ne 0 -or
        [int64]$value.admissionLifetimeSeconds -ne [int64]$admissionDelta.TotalSeconds -or
        [int64]$value.admissionLifetimeSeconds -lt 1 -or
        [int]$value.admissionLifetimeSeconds -gt [int]$context.Authority.maxAdmissionLifetimeSeconds) {
        Stop-W0 'run admission is expired or lifetime exceeds operator policy'
    }
    # Rehash all trusted bytes again immediately before the pinned semantic pass.
    Assert-ExpectedConfigHash
    Read-And-ValidateChallenge $context $LaunchChallengePath | Out-Null
    if ((Get-Sha256File $RunAdmissionAttestationPath) -cne $admission.Sha256 -or
        (Get-Sha256File $RunAdmissionSignaturePath) -cne $admission.SignatureSha256 -or
        (Get-PathIdentity $RunAdmissionAttestationPath) -cne $admission.FileIdentity -or
        (Get-PathIdentity $RunAdmissionSignaturePath) -cne $admission.SignatureFileIdentity -or
        [W0NativeFileIdentity]::ReadLinkCount($RunAdmissionAttestationPath) -ne 1 -or
        [W0NativeFileIdentity]::ReadLinkCount($RunAdmissionSignaturePath) -ne 1) {
        Stop-W0 'signed run admission/signature changed before semantic validation'
    }
    $invocation=Get-AdmitInvocation $context $challengeContext
    $result=Invoke-PinnedValidator $challengeContext $invocation
    Assert-JsonBoolean $result.Value.pass $true 'run authorization result.pass'
    if ($result.Value.mode -cne 'run-authorization') {
        Stop-W0 'pinned run-authorization semantic validator did not PASS'
    }
    # Authority may create exactly these two proof-sealing outputs only after
    # observing semantic PASS, token consumption, and suspended worker readiness.
    $waitUntil=$admissionExpires
    while ((-not (Test-Path -LiteralPath $AdmitExecutionAttestationPath) -or
            -not (Test-Path -LiteralPath $AdmitExecutionSignaturePath)) -and
           [DateTimeOffset]::UtcNow -lt $waitUntil) { Start-Sleep -Milliseconds 100 }
    if (-not (Test-Path -LiteralPath $AdmitExecutionAttestationPath) -or
        -not (Test-Path -LiteralPath $AdmitExecutionSignaturePath)) {
        Stop-W0 'authority did not provide signed ADMIT execution/worker-ready receipt before expiry'
    }
    foreach($path in @($AdmitExecutionAttestationPath,$AdmitExecutionSignaturePath)) {
        Assert-ExternalPath $path $extraProtected $true | Out-Null
    }
    $allPaths=@($normalized + @(
        ConvertTo-NormalizedPath $AdmitExecutionAttestationPath $true,
        ConvertTo-NormalizedPath $AdmitExecutionSignaturePath $true))
    $allPathSet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $allIdentitySet=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($path in $allPaths) {
        $allPathSet.Add($path)|Out-Null
        $identity=Get-PathIdentity $path
        if (-not $allIdentitySet.Add($identity) -or $forbiddenIdentities.Contains($identity)) {
            Stop-W0 'ADMIT input/receipt output aliases another or a locked read input'
        }
    }
    if ($allPathSet.Count -ne 11 -or $allIdentitySet.Count -ne 11) {
        Stop-W0 'ADMIT eleven-path identity closure mismatch'
    }
    $authReadSets=Get-AuthorizationInputSets $challengeContext.AuthorizationRoot @(
        $AdmitExecutionAttestationPath,$AdmitExecutionSignaturePath) $forbiddenIdentities
    $fullReadRecords=@(Merge-ReadRecords @($lockedRecords,$authReadSets.Records))
    $fullIdentityRecords=@(Get-IdentityRecordsForRecords $fullReadRecords 'ADMIT full read set')
    $receipt=Assert-AdmitExecutionReceipt $context $challengeContext $admission $result `
        $invocation $fullReadRecords $fullIdentityRecords
    if ([DateTimeOffset]::UtcNow -ge $receipt.CapabilityExpiresAt) {
        Stop-W0 'worker-ready capability expired before bootstrap PASS'
    }
    [Console]::Out.WriteLine((ConvertTo-CanonicalJson ([ordered]@{
        pass=$true;phase='ADMIT';runId=$challengeContext.Value.runId
        authorizationId=$result.Value.authorizationId;admissionId=$result.Value.admissionId
        oneTimeTokenSha256=$result.Value.oneTimeTokenSha256
        admitExecutionReceiptSha256=$receipt.Signed.Sha256
        workerReadyCapabilitySha256=$receipt.Value.workerReadyCapability.capabilitySha256
        continuousLockRequired=$true;sideEffectsMayStartOnlyAfterBootstrapPassAndAtomicCapabilityConsumption=$true
        tempRetainedUntilWorkerReady=$true;workerSuspendedBeforeProductEntry=$true
    })))
}

if ($Phase -ceq 'PREPARE') { Invoke-Prepare; exit 0 }
if ($Phase -ceq 'VALIDATE') { Invoke-Validate; exit 0 }
if ($Phase -ceq 'ADMIT') { Invoke-Admit; exit 0 }
Stop-W0 "unknown receiver bootstrap phase: $Phase"
