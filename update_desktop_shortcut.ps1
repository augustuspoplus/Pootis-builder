$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$godotProj = Join-Path $repoRoot "godot"
$iconPath = Join-Path $repoRoot "assets\PootisBuilder.ico"
$godotExe = "C:\Users\steph\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"

if (-not (Test-Path $godotExe)) {
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($cmd) { $godotExe = $cmd.Source }
}

$desktopDir = [Environment]::GetFolderPath("Desktop")
$lnkPath = Join-Path $desktopDir "Pootis Builder 2.0.lnk"

$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut($lnkPath)
$sc.TargetPath = $godotExe
$sc.Arguments = "--path `"$godotProj`""
$sc.WorkingDirectory = $godotProj
$sc.Description = "Pootis Builder 2.0 - Valve-Grade TF2 Map Creator (Godot 4 + C++20)"
if (Test-Path $iconPath) {
    $sc.IconLocation = "$iconPath,0"
}
$sc.Save()

Write-Host "Updated Desktop shortcut: $lnkPath" -ForegroundColor Cyan
