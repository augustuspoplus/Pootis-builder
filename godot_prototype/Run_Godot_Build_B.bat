@echo off
setlocal
for /f "delims=" %%I in ('powershell -NoProfile -Command "(Get-ChildItem \"$env:LOCALAPPDATA\Microsoft\WinGet\Packages\" -Recurse -Filter \"Godot_v4*win64.exe\" | Where-Object { $_.Name -notlike \"*console*\" } | Select-Object -First 1).FullName"') do set "GODOT=%%I"
if "%GODOT%"=="" (
    echo Godot 4 not found in WinGet Packages.
    pause
    exit /b 1
)
echo Launching Pootis Builder — Build B (Godot 4 Prototype)...
start "" "%GODOT%" --path "%~dp0." --resolution 1600x950
