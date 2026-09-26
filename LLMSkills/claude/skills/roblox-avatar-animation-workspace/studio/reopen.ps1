$w = Get-Process RobloxStudioBeta | Where-Object { $_.MainWindowTitle -like "*AnimSandbox*" }
$w | Stop-Process -Force
Start-Sleep -Seconds 3
$exe = (Get-Process RobloxStudioBeta | Select-Object -First 1 -ExpandProperty Path)
$place = Join-Path $env:USERPROFILE ".claude\skills\roblox-avatar-animation-workspace\studio\AnimSandbox.rbxlx"
Start-Process -FilePath $exe -ArgumentList @("-task","EditFile","-localPlaceFile","`"$place`"")
