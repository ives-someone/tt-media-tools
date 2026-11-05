@echo off
chcp 65001 >nul
REM ============================================================
REM TT_Media_Tools - environment manager launcher
REM Real logic lives in install.ps1 (easier to maintain).
REM Prefer PowerShell 7 (ANSI colors), fall back to 5.1.
REM ============================================================
where pwsh >nul 2>nul
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
)