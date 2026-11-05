@echo off
rem TT_Media_Tools launcher: prefer PowerShell 7, fall back to Windows PowerShell 5.1
where pwsh >nul 2>nul
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0tt.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tt.ps1"
)