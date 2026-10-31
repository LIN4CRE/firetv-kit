@echo off
setlocal
cd /d "%~dp0"
title Fire TV Ultimate Setup Kit
cls

echo ==========================================================================
echo        FIRE TV ULTIMATE SETUP KIT (Stremio * SmartTube * TiviMate)
echo ==========================================================================
echo.
echo Launching automated setup engine...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\setup.ps1"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [!] Setup exited with an error code: %ERRORLEVEL%
    pause
)
