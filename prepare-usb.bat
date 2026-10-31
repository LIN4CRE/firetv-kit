@echo off
setlocal
cd /d "%~dp0"
title Fire TV USB Toolkit Creator
cls

echo ==========================================================================
echo           FIRE TV SETUP KIT - USB DRIVE TOOLKIT CREATOR
echo ==========================================================================
echo.
echo Launching USB packager...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\prepare-usb.ps1"

echo.
pause
