# Save a PNG of a Roblox Studio window, even when other windows cover it (PrintWindow).
# Use it to keep before/after screenshots for the report; screen_capture (MCP) only returns the image
# to the model. Windows only.
#
#   powershell -ExecutionPolicy Bypass -File capture_studio.ps1 -Out shot.png [-TitleLike "*MyPlace*"] [-Crop "0.38,0.13,0.996,0.944"]
#
# -TitleLike  wildcard on the Studio window title (the place file name appears in it); default: first Studio window
# -Crop       optional "x0,y0,x1,y1" as fractions of the window, to keep only the 3D viewport. Find the fractions
#             once for your Studio layout (open the uncropped PNG and read the viewport corners), then reuse them.
param([Parameter(Mandatory = $true)][string]$Out, [string]$TitleLike = "*", [string]$Crop = "")
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class StudioShot {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[StudioShot]::SetProcessDPIAware() | Out-Null
$p = Get-Process RobloxStudioBeta -ErrorAction SilentlyContinue |
  Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like $TitleLike } | Select-Object -First 1
if (-not $p) { Write-Error "no Studio window matching $TitleLike"; exit 1 }
if ([StudioShot]::IsIconic($p.MainWindowHandle)) {
  [StudioShot]::ShowWindow($p.MainWindowHandle, 4) | Out-Null   # restore without stealing focus; a minimised window prints as a title bar
  Start-Sleep -Milliseconds 800
}
$r = New-Object StudioShot+RECT
[StudioShot]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
$w = $r.Right - $r.Left; $h = $r.Bottom - $r.Top
$bmp = New-Object System.Drawing.Bitmap $w, $h
$g = [System.Drawing.Graphics]::FromImage($bmp)
$hdc = $g.GetHdc()
[StudioShot]::PrintWindow($p.MainWindowHandle, $hdc, 2) | Out-Null   # 2 = PW_RENDERFULLCONTENT (needed for the 3D viewport)
$g.ReleaseHdc($hdc); $g.Dispose()
if ($Crop -ne "") {
  $f = $Crop.Split(",") | ForEach-Object { [double]$_ }
  $rect = New-Object System.Drawing.Rectangle ([int]($w * $f[0])), ([int]($h * $f[1])), ([int]($w * ($f[2] - $f[0]))), ([int]($h * ($f[3] - $f[1])))
  $cropped = $bmp.Clone($rect, $bmp.PixelFormat)
  $bmp.Dispose(); $bmp = $cropped
}
$bmp.Save($Out, [System.Drawing.Imaging.ImageFormat]::Png)
"saved $Out ($($bmp.Width)x$($bmp.Height)) from '$($p.MainWindowTitle)'"
