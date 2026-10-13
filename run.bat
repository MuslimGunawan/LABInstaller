@echo off
title LABInstaller - Smart Installer for Windows
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0installer.ps1"
if %errorlevel% neq 0 (
    echo.
    echo Terjadi kesalahan saat menjalankan installer.
    pause
)

