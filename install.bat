@echo off
chcp 65001 >nul
REM ============================================================
REM TT_Media_Tools - environment manager launcher
REM Real logic lives in install.ps1 (easier to maintain).
REM Prefer PowerShell 7 (ANSI colors), fall back to 5.1.
REM ============================================================
REM 先解除 install.ps1 自身的“网络下载”标记（MOTW）：
REM 从 GitHub 下载 zip 解压后，RemoteSigned 会拒绝加载未签名脚本
powershell -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath '%~dp0install.ps1' -ErrorAction SilentlyContinue" >nul 2>nul
where pwsh >nul 2>nul
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1"
)