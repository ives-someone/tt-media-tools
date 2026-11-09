@echo off
rem TT_Media_Tools launcher: prefer PowerShell 7, fall back to Windows PowerShell 5.1
rem 探针：tt.ps1 带“网络下载”标记时先解除，之后直接输入 tt 也能运行；
rem 已经解锁过则只做一次 Get-Item -Stream，几乎无开销
powershell -NoProfile -ExecutionPolicy Bypass -Command "if (Get-Item -LiteralPath '%~dp0tt.ps1' -Stream Zone.Identifier -ErrorAction SilentlyContinue) { Unblock-File -LiteralPath '%~dp0tt.ps1' }" >nul 2>nul
where pwsh >nul 2>nul
if %errorlevel%==0 (
    pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0tt.ps1"
) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tt.ps1"
)