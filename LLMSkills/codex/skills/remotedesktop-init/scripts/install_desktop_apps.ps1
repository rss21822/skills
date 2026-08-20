[CmdletBinding()]
param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

function Write-Result {
    param(
        [string]$Name,
        [ValidateSet('installed', 'already installed', 'failed')]
        [string]$Status,
        [string]$Detail = ''
    )

    if ($Detail) {
        Write-Output ("[{0}] {1}: {2}" -f $Status, $Name, $Detail)
    } else {
        Write-Output ("[{0}] {1}" -f $Status, $Name)
    }
}

function Test-ExecutableInstalled {
    param([string]$Name)

    switch ($Name) {
        'Claude Desktop' {
            return (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'AnthropicClaude\claude.exe'))
        }
        'GitHub Desktop' {
            return (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'GitHubDesktop\GitHubDesktop.exe'))
        }
        'Cursor' {
            return (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Programs\cursor\Cursor.exe'))
        }
        'Git for Windows' {
            return [bool](
                (Get-Command git.exe -ErrorAction SilentlyContinue) -or
                (Test-Path -LiteralPath (Join-Path ${env:ProgramFiles} 'Git\cmd\git.exe')) -or
                (Test-Path -LiteralPath (Join-Path ${env:LOCALAPPDATA} 'Programs\Git\cmd\git.exe'))
            )
        }
        'Roblox Studio' {
            $roots = @(
                (Join-Path ${env:ProgramFiles(x86)} 'Roblox\Versions'),
                (Join-Path $env:LOCALAPPDATA 'Roblox\Versions')
            )
            foreach ($root in $roots) {
                if (Test-Path -LiteralPath $root) {
                    $studio = Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
                        ForEach-Object { Join-Path $_.FullName 'RobloxStudioBeta.exe' } |
                        Where-Object { Test-Path -LiteralPath $_ } |
                        Select-Object -First 1
                    if ($studio) { return $true }
                }
            }
            return $false
        }
    }

    return $false
}

function Install-RobloxFromOfficialSource {
    $tempRoot = Join-Path $env:TEMP ("RemoteDesktop-init-" + [guid]::NewGuid().ToString('N'))
    $installer = Join-Path $tempRoot 'RobloxStudioInstaller.exe'

    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    try {
        Write-Output 'Roblox Studio winget verification was stale; using the official Roblox installer.'
        Invoke-WebRequest -Uri 'https://setup.rbxcdn.com/RobloxStudioInstaller.exe' -OutFile $installer -UseBasicParsing

        $signature = Get-AuthenticodeSignature -FilePath $installer
        $signer = $signature.SignerCertificate
        if ($signature.Status -ne 'Valid' -or -not $signer -or $signer.Subject -notmatch 'Roblox Corporation') {
            throw 'The downloaded Roblox installer did not have a valid Roblox Corporation signature.'
        }

        $process = Start-Process -FilePath $installer -Wait -PassThru
        if ($process.ExitCode -ne 0) {
            throw "The official Roblox installer exited with code $($process.ExitCode)."
        }
    } finally {
        if (Test-Path -LiteralPath $tempRoot) {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
    throw 'winget is not available. Install or enable App Installer, then run this skill again.'
}

$packages = @(
    [pscustomobject]@{ Name = 'Claude Desktop'; Id = 'Anthropic.Claude' },
    [pscustomobject]@{ Name = 'GitHub Desktop'; Id = 'GitHub.GitHubDesktop' },
    [pscustomobject]@{ Name = 'Roblox Studio'; Id = 'Roblox.RobloxStudio' },
    [pscustomobject]@{ Name = 'Cursor'; Id = 'Anysphere.Cursor' },
    [pscustomobject]@{ Name = 'Git for Windows'; Id = 'Git.Git' }
)

foreach ($package in $packages) {
    try {
        if (Test-ExecutableInstalled -Name $package.Name) {
            Write-Result -Name $package.Name -Status 'already installed'
            continue
        }

        if ($DryRun) {
            Write-Result -Name $package.Name -Status 'installed' -Detail 'dry run; no changes made'
            continue
        }

        $arguments = @(
            'install', '--id', $package.Id, '--exact', '--source', 'winget',
            '--accept-source-agreements', '--accept-package-agreements'
        )
        $output = (& winget.exe @arguments 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0 -and $package.Id -eq 'Roblox.RobloxStudio' -and $output -match 'hash does not match') {
            Install-RobloxFromOfficialSource
            $exitCode = 0
        }

        if ($exitCode -ne 0) {
            throw ($output.Trim())
        }

        if (-not (Test-ExecutableInstalled -Name $package.Name)) {
            throw 'The installer completed, but the expected executable was not found.'
        }

        Write-Result -Name $package.Name -Status 'installed'
    } catch {
        Write-Result -Name $package.Name -Status 'failed' -Detail $_.Exception.Message
    }
}

Write-Output 'Verification complete. Account sign-in, if needed, is a separate manual first-run step.'
