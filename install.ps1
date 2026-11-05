<#
============================================================
install.ps1
TT_Media_Tools 环境管理（由 install.bat 调用，也可直接运行）

职责：
  1. 把工具目录加入 / 移出【用户 PATH】
  2. 检查 ffprobe.exe 是否可用，缺失时给出下载指引
  3. 若用户把 ffprobe.exe 放在 tools\ 目录，自动把 tools\ 加入 PATH

版本：v2.1（2026-11-05）
  v2.0 加入 ffprobe 检测与 tools 目录支持
  v2.1 界面统一到 ui.ps1（标题块 + col_a_* + Arrow-Menu 单键菜单），
       去掉 Read-Host 回车交互；ui.ps1 缺失时降级为单键读取。
============================================================
#>

$ErrorActionPreference = 'Stop'

$ToolDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ToolsDir = Join-Path $ToolDir 'tools'
$ModulesDir = Join-Path $ToolDir 'modules'
$UiPath   = Join-Path $ToolDir 'modules\ui\ui.ps1'

# ------------------------------------------------------------
# 加载公共 UI 框架（缺失时降级，不影响核心功能）
# ------------------------------------------------------------
$HasUi = Test-Path -LiteralPath $UiPath
if ($HasUi) {
    . $UiPath
} else {
    # 降级：ui.ps1 缺失时（例如只下载了部分文件），提供与 ui.ps1 同名的基础函数，
    #       让下面的界面代码不必写两套分支，只是失去颜色而已。
    function col_a_title      { param([string]$T) $T }
    function col_a_subtitle   { param([string]$T) $T }
    function col_a_text       { param([string]$T) $T }
    function col_a_text_muted { param([string]$T) $T }
    function col_a_text_gray  { param([string]$T) $T }
    function col_a_success    { param([string]$T) $T }
    function col_a_warning    { param([string]$T) $T }
    function col_a_error      { param([string]$T) $T }
    function col_a_line       { param([string]$T) $T }
    function sep              { param([string]$Char = '=', [int]$Len = 60) $Char * $Len }
    function Clear-Screen     { Clear-Host }
}

function Show-Blank {
    if ($HasUi) { Write-Host } else { Write-Host '' }
}

function Wait-Key {
    param([string]$Message = '按任意键继续...')
    if ($HasUi) {
        Wait-AnyKey "`n  $(col_a_text_muted $Message)"
    } else {
        Write-Host ''
        Write-Host "  $Message"
        [void][Console]::ReadKey($true)
    }
}

# ------------------------------------------------------------
# PATH 辅助函数
# ------------------------------------------------------------
function Get-UserPath {
    [Environment]::GetEnvironmentVariable('PATH', 'User')
}

function Set-UserPath {
    param([string]$Value)
    [Environment]::SetEnvironmentVariable('PATH', $Value, 'User')
}

function Test-PathHas {
    param([string]$PathValue, [string]$Entry)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $false }
    $e = $Entry.TrimEnd('\')
    foreach ($item in ($PathValue -split ';')) {
        if ([string]::IsNullOrWhiteSpace($item)) { continue }
        if ($item.TrimEnd('\') -ieq $e) { return $true }
    }
    return $false
}

function Add-PathEntry {
    param([string]$Entry)
    $p = Get-UserPath
    if (Test-PathHas -PathValue $p -Entry $Entry) { return $false }
    $new = if ([string]::IsNullOrWhiteSpace($p)) { $Entry } else { $p.TrimEnd(';') + ';' + $Entry }
    Set-UserPath -Value $new
    return $true
}

function Remove-PathEntry {
    param([string]$Entry)
    $p = Get-UserPath
    if ([string]::IsNullOrWhiteSpace($p)) { return $false }
    $e = $Entry.TrimEnd('\')
    $kept = @()
    $removed = $false
    foreach ($item in ($p -split ';')) {
        if ([string]::IsNullOrWhiteSpace($item)) { continue }
        if ($item.TrimEnd('\') -ieq $e) { $removed = $true; continue }
        $kept += $item
    }
    if (-not $removed) { return $false }
    Set-UserPath -Value ($kept -join ';')
    return $true
}

# ------------------------------------------------------------
# ffprobe 检测
# ------------------------------------------------------------
function Get-FfprobeState {
    $cmd = Get-Command ffprobe.exe -ErrorAction SilentlyContinue
    if ($cmd) {
        return [PSCustomObject]@{ Source = 'path'; Detail = $cmd.Source }
    }
    $inTools = Join-Path $ToolsDir 'ffprobe.exe'
    if (Test-Path -LiteralPath $inTools) {
        if (Test-PathHas -PathValue (Get-UserPath) -Entry $ToolsDir) {
            return [PSCustomObject]@{ Source = 'pending'; Detail = '已在 tools\ 并加入 PATH，重开终端后生效' }
        }
        return [PSCustomObject]@{ Source = 'tools'; Detail = $inTools }
    }
    $inRoot = Join-Path $ToolDir 'ffprobe.exe'
    if (Test-Path -LiteralPath $inRoot) {
        return [PSCustomObject]@{ Source = 'tooldir'; Detail = $inRoot }
    }
    return [PSCustomObject]@{ Source = 'none'; Detail = '未找到' }
}

function Show-FfprobeAdvice {
    Write-Host "  $(col_a_line ('-' * 58))"
    Write-Host "  $(col_a_warning '未找到 ffprobe.exe —— 菜单 1 / 2 / 5 会用到它')"
    Show-Blank
    Write-Host "  $(col_a_text '获取方式（任选其一）：')"
    Write-Host "  $(col_a_text_muted '  a）下载单文件版：')"
    Write-Host "  $(col_a_text_muted '     https://www.gyan.dev/ffmpeg/builds/')"
    Write-Host "  $(col_a_text_muted '     选 ffmpeg-release-essentials.zip，取其中的 bin\ffprobe.exe')"
    Write-Host "  $(col_a_text_muted '  b）或用 winget：winget install Gyan.FFmpeg')"
    Show-Blank
    Write-Host "  $(col_a_text '放置位置（推荐）：')"
    Write-Host "  $(col_a_text_muted "     把 ffprobe.exe 放到  $ToolsDir")"
    Write-Host "  $(col_a_text_muted '     然后重新运行本菜单的第 1 项，会自动把 tools\ 加入 PATH')"
    Show-Blank
    Write-Host "  $(col_a_text_muted '注意：shared 版本的 ffprobe.exe 只有几百 KB，')"
    Write-Host "  $(col_a_text_muted '      必须连同 avcodec-*.dll 等一起放入 tools\，否则无法运行。')"
    Write-Host "  $(col_a_line ('-' * 58))"
}

# ------------------------------------------------------------
# 安装
# ------------------------------------------------------------
function Invoke-Install {
    Clear-Screen
    Write-Host ''
    Write-Host ''
    Write-Host "  $(col_a_title '安装 — 将本目录加入用户 PATH')"
    Write-Host "  $(col_a_line (sep))"
    Show-Blank

    $changed = @()

    if (Add-PathEntry -Entry $ToolDir) {
        Write-Host "  $(col_a_success '✓ 已加入用户 PATH：')$(col_a_text $ToolDir)"
        $changed += '工具目录'
    } else {
        Write-Host "  $(col_a_text_muted '· 工具目录已在用户 PATH 中，无需重复添加')"
    }

    # modules 目录：让 maxm.ps1 / top_finder.ps1 等能在任意目录直接执行（AI 驱动的命令依赖这一点）
    if (Add-PathEntry -Entry $ModulesDir) {
        Write-Host "  $(col_a_success '✓ 已把 modules 目录加入用户 PATH：')$(col_a_text $ModulesDir)"
        Write-Host "  $(col_a_text_muted '   这样可在任意文件夹直接执行 maxm.ps1 -Mode B 等命令')"
        $changed += 'modules 目录'
    } else {
        Write-Host "  $(col_a_text_muted '· modules 目录已在用户 PATH 中')"
    }

    $ff = Get-FfprobeState
    switch ($ff.Source) {
        'path' {
            Write-Host "  $(col_a_success '✓ ffprobe 可用：')$(col_a_text $ff.Detail)"
        }
        'tools' {
            if (Add-PathEntry -Entry $ToolsDir) {
                Write-Host "  $(col_a_success '✓ 发现 tools\ffprobe.exe，已把 tools\ 加入用户 PATH')"
                $changed += 'tools 目录'
            } else {
                Write-Host "  $(col_a_text_muted '· tools\ 已在用户 PATH 中')"
            }
        }
        'tooldir' {
            Write-Host "  $(col_a_success '✓ 工具目录内已有 ffprobe.exe（随工具目录一起生效）')"
        }
        default {
            Write-Host "  $(col_a_warning '· 尚未找到 ffprobe.exe')"
            Show-Blank
            Show-FfprobeAdvice
        }
    }

    $sysPath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    if (Test-PathHas -PathValue $sysPath -Entry $ToolDir) {
        Show-Blank
        Write-Host "  $(col_a_warning '注意：该目录同时存在于【系统 PATH】中')"
        Write-Host "  $(col_a_text_muted '       本脚本只改用户变量，系统变量请自行以管理员身份移除')"
    }

    Show-Blank
    Write-Host "  $(col_a_line (sep))"
    if ($changed.Count -gt 0) {
        Write-Host "  $(col_a_success '✅ 安装成功！')"
        Write-Host "  $(col_a_text ('  已修改：' + ($changed -join '、')))"
        Show-Blank
        Write-Host "  $(col_a_text '请【重新打开终端】后生效，之后在任意文件夹输入 tt 即可启动。')"
        Wait-Key '按任意键返回菜单...'
    } else {
        Write-Host "  $(col_a_text_muted '⚪ 无需变更（相关路径已配置）')"
        Wait-Key '按任意键返回菜单...'
    }
}

# ------------------------------------------------------------
# 卸载
# ------------------------------------------------------------
function Invoke-Uninstall {
    Clear-Screen
    Write-Host ''
    Write-Host ''
    Write-Host "  $(col_a_title '移除 — 从用户 PATH 中清除本目录')"
    Write-Host "  $(col_a_line (sep))"
    Show-Blank

    $removed = @()

    if (Remove-PathEntry -Entry $ToolDir) {
        Write-Host "  $(col_a_success '✓ 已从用户 PATH 移除工具目录')"
        $removed += '工具目录'
    } else {
        Write-Host "  $(col_a_text_muted '· 用户 PATH 中没有工具目录')"
    }

    if (Remove-PathEntry -Entry $ModulesDir) {
        Write-Host "  $(col_a_success '✓ 已从用户 PATH 移除 modules 目录')"
        $removed += 'modules 目录'
    }

    if (Test-Path -LiteralPath $ToolsDir) {
        if (Remove-PathEntry -Entry $ToolsDir) {
            Write-Host "  $(col_a_success '✓ 已从用户 PATH 移除 tools 目录')"
            $removed += 'tools 目录'
        }
    }

    Show-Blank
    Write-Host "  $(col_a_line (sep))"
    if ($removed.Count -gt 0) {
        Write-Host "  $(col_a_success '✅ 移除成功！')"
        Write-Host "  $(col_a_text ('  已移除：' + ($removed -join '、')))"
        Show-Blank
        Write-Host "  $(col_a_text '请【重新打开终端】后生效。')"
        Write-Host "  $(col_a_text_muted "  工具文件仍保留在：$ToolDir")"
    } else {
        Write-Host "  $(col_a_text_muted '⚪ 无需移除（用户 PATH 中没有本工具的路径）')"
    }
    Wait-Key '按任意键返回菜单...'
}

# ------------------------------------------------------------
# 单键读取（ui.ps1 缺失时的降级方案）
# ------------------------------------------------------------
function Read-SingleKey {
    $k = [Console]::ReadKey($true)
    return $k.KeyChar.ToString().ToUpper()
}

# ------------------------------------------------------------
# 主循环
# ------------------------------------------------------------
while ($true) {

    Clear-Screen
    Write-Host ''
    Write-Host "  $(col_a_title 'TT_Media_Tools — 环境管理')"
    Write-Host "  $(col_a_line (sep))"
    Show-Blank
    Write-Host "  $(col_a_text_muted '工具目录：')$(col_a_text $ToolDir)"

    $ff = Get-FfprobeState
    switch ($ff.Source) {
        'path'    { $ffLine = "$(col_a_success '已找到')  $(col_a_text $ff.Detail)" }
        'pending' { $ffLine = "$(col_a_text_muted '在 tools\ 内，重开终端后生效')" }
        'tools'   { $ffLine = "$(col_a_success '在 tools\ 目录内')  $(col_a_text_muted '（尚未加入 PATH）')" }
        'tooldir' { $ffLine = "$(col_a_success '在工具目录内')" }
        default   { $ffLine = "$(col_a_warning '未找到（菜单 1 / 2 / 5 需要）')" }
    }
    Write-Host "  $(col_a_text_muted 'ffprobe ：')$ffLine"
    Show-Blank
    Write-Host "  $(col_a_line (sep))"

    if (-not $HasUi) {
        Show-Blank
        Write-Host "  $(col_a_text_muted '[1] 安装    [2] 移除    [Q] 退出')"
        Write-Host ''
        Write-Host '  请按键（无需回车）：' -NoNewline
        $key = Read-SingleKey
        Write-Host $key
        switch ($key) {
            '1' { Invoke-Install; continue }
            '2' { Invoke-Uninstall; continue }
            'Q' { return }
            default { continue }
        }
    }

    # 有 ui.ps1 时用竖向菜单
    Show-Blank
    $menuLabels = @(
        '[1] 安装 — 将本目录加入用户 PATH',
        '[2] 移除 — 从用户 PATH 中清除本目录'
    )
    $pick = -1
    try {
        $pick = Arrow-Menu -Options $menuLabels -DefaultIndex 0 `
            -Footer1 "  $(col_a_text_muted '[↑↓]移动  [1-2]直达  [Enter]确认  [q/Esc]退出')"
    } catch [System.OperationCanceledException] {
        Write-Host ''
        Write-Host "  $(col_a_text_muted '已退出。')"
        return
    }

    switch ($pick) {
        0 { Invoke-Install }
        1 { Invoke-Uninstall }
        default { continue }
    }
}