[CmdletBinding()]
param(
    [ValidateSet('ask', 'status', 'models')]
    [string]$Action = 'ask',

    [string]$Prompt,

    [string]$Model = 'cursor-grok-4.6-xhigh',

    [ValidateRange(1, 3600)]
    [int]$TimeoutSeconds = 600,

    [string]$Filter,

    [string]$OutFile
)

$ErrorActionPreference = 'Stop'

function Resolve-CursorAgent {
    $agentRoot = if ($env:CURSOR_AGENT_ROOT) {
        $env:CURSOR_AGENT_ROOT
    }
    else {
        Join-Path $env:APPDATA 'Cursor\User\globalStorage\anysphere.cursor-agent-worker\agent-cli\.local\share\cursor-agent\versions'
    }

    if (-not (Test-Path -LiteralPath $agentRoot -PathType Container)) {
        throw "Cursor-agent versions directory was not found: $agentRoot"
    }

    $versionDir = Get-ChildItem -LiteralPath $agentRoot -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'index.js') -PathType Leaf } |
        Sort-Object Name -Descending |
        Select-Object -First 1

    if (-not $versionDir) {
        throw "No cursor-agent version containing index.js was found under: $agentRoot"
    }

    $indexPath = Join-Path $versionDir.FullName 'index.js'
    $bundledNode = Join-Path $versionDir.FullName 'node.exe'
    $nodePath = if (Test-Path -LiteralPath $bundledNode -PathType Leaf) {
        $bundledNode
    }
    else {
        (Get-Command node -ErrorAction Stop).Source
    }

    [pscustomobject]@{
        Version = $versionDir.Name
        Index   = $indexPath
        Node    = $nodePath
    }
}

function Invoke-AgentProcess {
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$Agent,

        [Parameter(Mandatory)]
        [string[]]$Arguments,

        [Parameter(Mandatory)]
        [string]$WorkingDirectory,

        [Parameter(Mandatory)]
        [int]$Timeout
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Agent.Node
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)

    $startInfo.ArgumentList.Add($Agent.Index)
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) {
        throw 'Failed to start cursor-agent.'
    }

    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($Timeout * 1000)) {
        try { $process.Kill($true) } catch { }
        throw "cursor-agent timed out after $Timeout seconds."
    }

    $stdout = $stdoutTask.GetAwaiter().GetResult().Trim()
    $stderr = $stderrTask.GetAwaiter().GetResult().Trim()
    if ($process.ExitCode -ne 0) {
        $detail = if ($stderr) { $stderr } elseif ($stdout) { $stdout } else { 'No error output.' }
        throw "cursor-agent exited with code $($process.ExitCode): $detail"
    }

    if ($stdout) { return $stdout }
    return $stderr
}

$agent = Resolve-CursorAgent
$tempDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-cursor-agent-" + [guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($tempDirectory) | Out-Null

try {
    switch ($Action) {
        'status' {
            $result = Invoke-AgentProcess -Agent $agent -Arguments @('status') -WorkingDirectory $tempDirectory -Timeout $TimeoutSeconds
            $result = "version: $($agent.Version)`nindex:   $($agent.Index)`nnode:    $($agent.Node)`n`n$result"
        }
        'models' {
            $result = Invoke-AgentProcess -Agent $agent -Arguments @('models') -WorkingDirectory $tempDirectory -Timeout $TimeoutSeconds
            if ($Filter) {
                $matches = $result -split "`r?`n" | Where-Object { $_ -like "*$Filter*" }
                $result = if ($matches) { $matches -join "`n" } else { "No models matched '$Filter'." }
            }
        }
        'ask' {
            if ([string]::IsNullOrWhiteSpace($Prompt)) {
                throw "-Prompt is required when -Action is 'ask'."
            }
            $arguments = @('--model', $Model, '--trust', '--print', '--output-format', 'text', $Prompt)
            $result = Invoke-AgentProcess -Agent $agent -Arguments $arguments -WorkingDirectory $tempDirectory -Timeout $TimeoutSeconds
        }
    }

    if ($OutFile) {
        $resolvedOutFile = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutFile)
        $parent = Split-Path -Parent $resolvedOutFile
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            [System.IO.Directory]::CreateDirectory($parent) | Out-Null
        }
        [System.IO.File]::WriteAllText($resolvedOutFile, $result + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
        Write-Information "Saved response to: $resolvedOutFile" -InformationAction Continue
    }

    $result
}
finally {
    if (Test-Path -LiteralPath $tempDirectory) {
        Remove-Item -LiteralPath $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
