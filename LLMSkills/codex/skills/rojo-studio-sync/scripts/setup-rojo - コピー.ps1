[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectRoot,

    [ValidateRange(1, 65535)]
    [int]$Port = 34872
)

$ErrorActionPreference = "Stop"
$version = "7.7.0"
$projectRootPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$projectFile = Join-Path $projectRootPath "default.project.json"
$rokitFile = Join-Path $projectRootPath "rokit.toml"

if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
    throw "default.project.json not found: $projectFile"
}
if (-not (Test-Path -LiteralPath $rokitFile -PathType Leaf)) {
    throw "rokit.toml not found: $rokitFile"
}

Get-Content -LiteralPath $projectFile -Raw | ConvertFrom-Json | Out-Null

$rokitContent = Get-Content -LiteralPath $rokitFile -Raw
if ($rokitContent -match '(?m)^rojo\s*=') {
    $rokitContent = $rokitContent -replace '(?m)^rojo\s*=\s*"[^"]+"', "rojo = `"rojo-rbx/rojo@$version`""
} elseif ($rokitContent -match '(?m)^\[tools\]\s*$') {
    $rokitContent = $rokitContent -replace '(?m)^\[tools\]\s*$', "[tools]`r`nrojo = `"rojo-rbx/rojo@$version`""
} else {
    $rokitContent += "`r`n[tools]`r`nrojo = `"rojo-rbx/rojo@$version`"`r`n"
}
Set-Content -LiteralPath $rokitFile -Value $rokitContent -Encoding utf8

$listeners = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
foreach ($listener in $listeners) {
    $process = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
    if (-not $process -or $process.ProcessName -ne "rojo") {
        throw "Port $Port is occupied by a non-Rojo process."
    }
    Stop-Process -Id $process.Id -Force
}

Push-Location $projectRootPath
try {
    rokit install
    $rojo = Join-Path $env:USERPROFILE ".rokit\bin\rojo.exe"
    if (-not (Test-Path -LiteralPath $rojo -PathType Leaf)) {
        throw "Rokit Rojo shim not found: $rojo"
    }

    $actualVersion = (& $rojo --version).Trim()
    if ($actualVersion -ne "Rojo $version") {
        throw "Expected Rojo $version, got $actualVersion"
    }

    $tempDir = Join-Path $projectRootPath ".tmp"
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    $stdout = Join-Path $tempDir "rojo-serve.stdout.log"
    $stderr = Join-Path $tempDir "rojo-serve.stderr.log"

    $server = Start-Process -FilePath $rojo `
        -ArgumentList @("serve", "default.project.json", "--port", "$Port", "--color", "never") `
        -WorkingDirectory $projectRootPath `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -WindowStyle Hidden `
        -PassThru

    Start-Sleep -Seconds 2
    if ($server.HasExited) {
        $errorText = Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
        throw "Rojo server exited. $errorText"
    }

    $response = Invoke-WebRequest -UseBasicParsing -Uri "http://localhost:$Port/api/rojo"
    if ($response.StatusCode -ne 200) {
        throw "Rojo endpoint returned HTTP $($response.StatusCode)"
    }

    $buildFile = Join-Path $tempDir "rojo-verify.rbxlx"
    & $rojo build default.project.json --output $buildFile | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $buildFile)) {
        throw "Rojo build verification failed."
    }

    [pscustomobject]@{
        Version = $actualVersion
        Port = $Port
        ProcessId = $server.Id
        HttpStatus = $response.StatusCode
        BuildFile = $buildFile
        BuildBytes = (Get-Item -LiteralPath $buildFile).Length
    }
} finally {
    Pop-Location
}
