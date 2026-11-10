<#
============================================================
modules\common.ps1
TT_Media_Tools 业务公共逻辑（无 UI、无副作用）
============================================================

用途：
    集中各业务模块重复的常量与判定函数，避免 time_add /
    time_clear / nfo_sync_clean / nfo_export 各自复制一份白名单。

设计原则：
    1、只定义常量与函数，不写交互、不清屏、不输出；
    2、不依赖 ui.ps1，供业务模块 dot-source；
    3、变量与函数名沿用各模块原有命名，替换时调用点零改动。

加载方式（业务模块内，放在 ui.ps1 之后）：
    . (Join-Path $PSScriptRoot "ui\ui.ps1")
    . (Join-Path $PSScriptRoot "common.ps1")

版本：v1.0（2026-11-11）
#>

# ========== 视频 / 附属文件扩展名 ==========
$videoExts = @('mp4','mov','mkv','avi','flv','wmv','m4v','ts','mpg','mpeg','f4v','m2ts','mts','webm','rmvb')
$artExts   = @('jpg','jpeg','png','webp','nfo')

# ========== 附属文件词干白名单（与 time_add.ps1 v5.34 口径一致）==========
# 判定对象一律是 BaseName（不含扩展名），扩展名由调用方各自筛好
# 形态① 无连字符标准命名：poster / poster1 / poster (2)
# 形态② 无连字符元数据：movie / tvshow / season01
# 形态③ 带连字符的视频配图：AAA-poster / AAA-fanart1 / AAA (2020)-thumb
$artStemList  = @('poster','fanart','cover','folder','thumb','banner','clearart','clearlogo',
                  'logo','landscape','backdrop','background','disc','discart','cdart','default')
$metaStemList = @('movie','tvshow','season')
$stemTail     = '([ _-]?\(?\d+\)?)?$'          # 允许 2 / -2 / _2 / " (2)"

$artBareRegex     = '^(' + ($artStemList  -join '|') + ')' + $stemTail
$metaBareRegex    = '^(' + ($metaStemList -join '|') + ')' + $stemTail
$artPrefixedRegex = '.+-(' + (($artStemList + $metaStemList) -join '|') + ')' + $stemTail

<#
.SYNOPSIS
    判定 BaseName 是否为 Emby/Jellyfin 附属文件（配图或元数据）。

.DESCRIPTION
    用于孤立文件检测：poster.jpg / poster1.nfo / movie.nfo / season01.nfo /
    AAA-poster.jpg 这类文件即使没有同名视频，也不应被当作孤立文件清理。

.PARAMETER BaseName
    不含扩展名的文件名（调用方自己负责按扩展名筛选）。

.OUTPUTS
    [bool] 命中白名单返回 $true，否则 $false。

.EXAMPLE
    PS> Test-ArtBaseName -BaseName "poster"
    True

.EXAMPLE
    PS> Test-ArtBaseName -BaseName "myvideo-poster"
    True

.EXAMPLE
    PS> Test-ArtBaseName -BaseName "myvideo"
    False
#>
function Test-ArtBaseName {
    param([string]$BaseName)
    if ([string]::IsNullOrEmpty($BaseName)) { return $false }
    if ($BaseName -match $artBareRegex)     { return $true }   # poster.nfo / poster.jpg
    if ($BaseName -match $metaBareRegex)    { return $true }   # movie.nfo / tvshow.nfo / season01.nfo
    if ($BaseName -match $artPrefixedRegex) { return $true }   # AAA-poster.jpg
    return $false
}

# ========== nfo 编码探测 ==========
# 返回 Encoding；无 BOM 且非合法 UTF-8 时尝试 GB18030；
# 系统缺少 GB18030 代码页时返回 $null，调用方据此跳过该文件，绝不用错误编码写盘。
# 无 BOM 的 UTF-16 用 XML 首字节 "<"（0x3C）判别，避免把 UTF-16 nfo 当 UTF-8/GBK 解码。
function Get-NfoEncoding {
    param([byte[]]$Bytes)

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode
    }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return [System.Text.Encoding]::BigEndianUnicode
    }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return (New-Object System.Text.UTF8Encoding($true))
    }

    # 无 BOM 的 UTF-16：XML 首字节是 0x3C（"<"），其后跟 0x00
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0x3C -and $Bytes[1] -eq 0x00) {
        return [System.Text.Encoding]::Unicode
    }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0x00 -and $Bytes[1] -eq 0x3C) {
        return [System.Text.Encoding]::BigEndianUnicode
    }

    try {
        $strict = New-Object System.Text.UTF8Encoding($false, $true)
        $null = $strict.GetString($Bytes)
        return (New-Object System.Text.UTF8Encoding($false))
    } catch {
        try {
            return [System.Text.Encoding]::GetEncoding(936)
        } catch {
            return $null
        }
    }
}

# ========== XML 标题转义 ==========
# SecurityElement::Escape 处理 & < > " '，再把 $ 替换为 $$，
# 防止后续 -replace 把 $ 当作分组引用吞字符。
function Format-SafeXmlTitle {
    param([string]$Title)
    return [System.Security.SecurityElement]::Escape($Title).Replace('$', '$$')
}