<#
.SYNOPSIS
  作業完了後の自動シャットダウンを予約・発火・取消するヘルパー。

.DESCRIPTION
  auto-shutdown-on-complete スキル用。以下のモードを持つ。
    -Arm     予約を記録する（実際には落とさない）
    -Status  予約の有無を表示する
    -Disarm  予約を解除する
    -Fire    猶予つきシャットダウンを発行し、予約を解除する
    -Cancel  発行済みのシャットダウンタイマーを取り消す

  環境変数 CLAUDE_SHUTDOWN_DRYRUN=1 のとき、-Fire / -Cancel は実際の
  shutdown.exe を呼ばず、実行予定のコマンドをログに書くだけにする。
  スキルの挙動をテストしたいときに使う。
#>
[CmdletBinding()]
param(
    [switch]$Arm,
    [switch]$Status,
    [switch]$Disarm,
    [switch]$Fire,
    [switch]$Cancel,
    [int]$Delay = 360,
    [string]$Reason = ""
)

$ErrorActionPreference = 'Stop'

$stateDir  = Join-Path $env:USERPROFILE '.claude'
$stateFile = Join-Path $stateDir 'auto-shutdown.state'
$logFile   = Join-Path $stateDir 'auto-shutdown.log'
$dryRun    = ($env:CLAUDE_SHUTDOWN_DRYRUN -eq '1')

if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }

function Write-Log([string]$msg) {
    $line = "{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg
    Add-Content -Path $logFile -Value $line -Encoding UTF8
    Write-Output $line
}

if ($Arm) {
    $payload = [ordered]@{
        armed_at = (Get-Date -Format 'o')
        reason   = $Reason
        delay    = $Delay
    } | ConvertTo-Json
    Set-Content -Path $stateFile -Value $payload -Encoding UTF8
    Write-Log "ARMED: 作業完了後にシャットダウンを予約しました。理由/完了条件: $Reason"
    Write-Output "予約を解除するには: shutdown.ps1 -Disarm"
    exit 0
}

if ($Status) {
    if (Test-Path $stateFile) {
        Write-Output "ARMED"
        Get-Content -Path $stateFile -Raw
    } else {
        Write-Output "NOT_ARMED"
    }
    exit 0
}

if ($Disarm) {
    if (Test-Path $stateFile) {
        Remove-Item -Path $stateFile -Force
        Write-Log "DISARMED: シャットダウン予約を解除しました。"
    } else {
        Write-Output "予約はありません（NOT_ARMED）。"
    }
    exit 0
}

if ($Cancel) {
    if ($dryRun) {
        Write-Log "DRYRUN CANCEL: shutdown.exe /a は実行していません。"
    } else {
        try {
            & shutdown.exe /a 2>&1 | Out-Null
            Write-Log "CANCELLED: シャットダウンタイマーを取り消しました。"
        } catch {
            Write-Log "CANCEL: 取り消し対象のタイマーはありませんでした。"
        }
    }
    exit 0
}

if ($Fire) {
    if ($Delay -lt 0) { $Delay = 0 }
    $comment = "Claude Code: 作業完了により自動シャットダウン"
    if ($dryRun) {
        Write-Log "DRYRUN FIRE: shutdown.exe /s /t $Delay /c `"$comment`" を実行するところでした。"
    } else {
        & shutdown.exe /s /t $Delay /c $comment
        Write-Log "FIRED: $Delay 秒後にシャットダウンします。"
    }
    if (Test-Path $stateFile) { Remove-Item -Path $stateFile -Force }
    Write-Output ""
    Write-Output "取り消す場合はこのコマンドを実行してください: shutdown /a"
    exit 0
}

Write-Output @"
使い方:
  shutdown.ps1 -Arm -Reason "<完了条件>"   予約する
  shutdown.ps1 -Status                      予約の有無を確認する
  shutdown.ps1 -Disarm                      予約を解除する
  shutdown.ps1 -Fire [-Delay 360]           猶予つきで発火する（既定360秒=6分）
  shutdown.ps1 -Cancel                      発行済みタイマーを取り消す

CLAUDE_SHUTDOWN_DRYRUN=1 を設定すると、実際には電源を切らずログのみ記録します。
"@
exit 1
