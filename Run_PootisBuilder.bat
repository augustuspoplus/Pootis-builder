@echo off
title Pootis Builder 2.0 — TF2 Map Creator
set "GODOT=C:\Users\steph\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
    echo ERROR: Godot 4.7.2 executable not found at:
    echo   %GODOT%
    pause
    exit /b 1
)
start "" "%GODOT%" --path "%~dp0godot"
