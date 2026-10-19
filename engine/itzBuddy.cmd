@echo off
:: ============================================================
::  itzBuddy Optimization Suite - launcher
::  Double-click this file. It asks for admin rights and starts
::  the interactive menu (itzBuddy.ps1) with the right settings.
:: ============================================================
setlocal
title itzBuddy Optimization Suite
cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator rights...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

if not exist "%~dp0itzBuddy.ps1" (
    echo ERROR: itzBuddy.ps1 not found next to this file.
    echo Extract the WHOLE folder from the ZIP before running.
    pause
    exit /b 1
)

:: Unblock files that Windows marked as "downloaded from the internet"
powershell -NoProfile -Command "Get-ChildItem -LiteralPath '%~dp0' -Recurse | Unblock-File" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0itzBuddy.ps1" %*
endlocal
