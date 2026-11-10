<#
.SYNOPSIS
    Emby NFO 扫描与元数据 CSV 导出（v3.0）
.DESCRIPTION
    递归扫描 Emby/Jellyfin 生成的 NFO，提取视频/音频流信息，导出 UTF-8 CSV。
    CSV 列与旧版完全一致，脚本名前缀逻辑保留（top_finder 依赖该命名规则）。

.PARAMETER NfoRoot
    扫描根目录，默认当前目录
.PARAMETER CsvName
    CSV 文件名，留空则按「是否开启同名视频匹配」自动生成带时间戳的名称

.NOTES
    v3.0 相对 v2.8 的改动：
    1、修正 param 块位置：旧版把 param() 写在函数定义之后，
       PowerShell 会把它当成名为 param 的命令执行（启动时报两条红字），
       参数绑定完全失效，-NfoRoot / -CsvName 传不进来，只能靠默认值碰巧可用。
    2、编码：旧版 ReadAllText 不指定编码，GBK 的 nfo 读成乱码，标题列全废。
       改为字节读取 + BOM/严格UTF-8/GB18030 探测。
    3、根节点：旧版只认 $xml.movie.title，剧集 nfo（<episodedetails>）与
       <tvshow> 的标题永远取不到，名称校验列恒为"（不一致）"。
       改为 movie / episodedetails / tvshow 依次探测。
    4、孤儿 nfo 判定：旧版只按"有无同名视频"判断，
       movie.nfo / tvshow.nfo / poster.nfo 这类附属文件会被列为"未找到同名视频"
       并有被删除的风险。改为复用 Test-ArtBaseName 词干白名单排除。
    5、交互与配色：裸 -ForegroundColor → col_a_*；裸 ReadKey 三问 → Select-Horizontal；
       cls 风格手绘标题 → Clear-Screen + 统一标题块。
    6、进度行：铺空格擦除 → ANSI 清行（ESC[K），长目录名不再因宽度估算误差残留。
    保留：进度条、P 暂停 / S 存半成品 / C 继续 / Q 存并退出、耗时统计、CSV 列结构。
    兼容：PowerShell 5.1 / 7.x。
#>

param(
    [string]$NfoRoot = $PWD.ProviderPath,
    [string]$CsvName = ""
)

# ========== 加载公共 UI 框架 ==========
. (Join-Path $PSScriptRoot "ui\ui.ps1")
. (Join-Path $PSScriptRoot "common.ps1")

# ========== 配置 ==========
$videoExtsPattern = @("*.mp4","*.mov","*.mkv","*.avi","*.flv","*.wmv","*.m4v","*.ts",
                      "*.mpg","*.mpeg","*.f4v","*.m2ts","*.mts","*.webm","*.rmvb")

# 附属文件白名单与 Test-ArtBaseName 已移至 common.ps1

# ========== nfo 编码探测 ==========
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

# ========== 标题块 ==========
Clear-Screen
Write-Host ""

$cwdDisplay = $PWD.ProviderPath
if ($cwdDisplay.Length -gt 78) {
    $cwdDisplay = $cwdDisplay.Substring(0, 38) + '…' + $cwdDisplay.Substring($cwdDisplay.Length - 38)
}

Write-Host "  $(col_a_title ('nfo_export.ps1 — NFO 元数据扫描导出'))"
Write-Host "  $(col_a_line (sep))"
Write-Host ""
Write-Host "  $(col_a_text_muted '处理目录：')$(col_a_text $cwdDisplay)"
Write-Host ""
Write-Host "  $(col_a_text_muted '递归扫描 nfo，提取时长/编码/分辨率/码率等信息导出 CSV，供 Excel 筛选排序')"
Write-Host "  $(col_a_text_muted '可选校验「文件名 vs 内部 title」，并处理找不到同名视频的孤立 nfo')"
Write-Host ""

# ========== 1. 扫描范围 ==========
Write-Host "  $(col_a_text ('扫描范围：'))"
Write-Host "  $(col_a_line (sep_weak))"

$recurseOpts = @(
    @{ Label = "[y]递归扫描子文件夹（推荐）"; Value = "recurse" }
    @{ Label = "[n]仅当前文件夹"; Value = "flat" }
    @{ Label = "[q/Esc]退出"; Value = "exit" }
)
$recurseResult = Select-Horizontal -Options $recurseOpts -Prompt "" -InitialIndex 0
if ($null -eq $recurseResult -or $recurseResult -eq 'exit') { exit 0 }
$DoRecurse = ($recurseResult -eq 'recurse')

if ($DoRecurse) { Write-Host "  $(col_a_success '✅  将递归扫描所有子文件夹')" }
else            { Write-Host "  $(col_a_warning '⚠  仅扫描当前文件夹（不含子目录）')" }

# ========== 2. 同名视频匹配 ==========
Write-Host ""
Write-Host "  $(col_a_text ('是否启用同名视频匹配？'))"
Write-Host "  $(col_a_text_muted '（开启后会逐 nfo 查找同名视频并读取真实文件大小，耗时明显增加）')"
Write-Host "  $(col_a_line (sep_weak))"

$matchOpts = @(
    @{ Label = "[n]关闭（推荐，速度最快）"; Value = "off" }
    @{ Label = "[y]开启（比对视频 + 输出文件大小）"; Value = "on" }
    @{ Label = "[q/Esc]退出"; Value = "exit" }
)
$matchResult = Select-Horizontal -Options $matchOpts -Prompt "" -InitialIndex 0
if ($null -eq $matchResult -or $matchResult -eq 'exit') { exit 0 }
$DoMatchVideo = ($matchResult -eq 'on')

Write-Host "  $(col_a_success ('→ 同名视频匹配：' + $(if ($DoMatchVideo) { '开启' } else { '关闭（跳过，速度最快）' })))"

# ========== 3. 生成 CSV 文件名 ==========
# 保持旧版前缀规则：nnfo_export_*.csv / nfo_export_onlynfo_*.csv（top_finder 依赖此命名）
if ([string]::IsNullOrWhiteSpace($CsvName)) {
    if ($DoMatchVideo) {
        $CsvName = "nfo_export_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    } else {
        $CsvName = "nfo_export_onlynfo_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    }
}

# ========== 4. 路径处理 ==========
try {
    $rootInfo = New-Object System.IO.DirectoryInfo($NfoRoot)
    if (-not $rootInfo.Exists) { throw "目录不存在: $NfoRoot" }
    $ValidRoot = $rootInfo.FullName
    $CsvPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($ValidRoot, $CsvName))
} catch {
    Write-Host "  $(col_a_error ('[错误] 路径处理失败: ' + $_.Exception.Message))"
    Wait-AnyKey "  按任意键退出..."
    exit 1
}

Write-Host ""
Write-Host "  $(col_a_text_muted '扫描根目录：')$(col_a_text $ValidRoot)"
Write-Host "  $(col_a_text_muted '输出文件：  ')$(col_a_text $CsvPath)"
Write-Host ""

# ========== 5. 枚举 NFO ==========
Write-Host "  $(col_a_text_muted '正在索引文件，请稍候...')"
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$searchOpt   = if ($DoRecurse) { [System.IO.SearchOption]::AllDirectories } else { [System.IO.SearchOption]::TopDirectoryOnly }
$nfoFilesAll = [System.IO.Directory]::GetFiles($ValidRoot, "*.nfo", $searchOpt)

$grouped   = $nfoFilesAll | Group-Object { Split-Path $_ -Parent }
$dirOrder  = @($grouped | ForEach-Object { $_.Name })
$dirCounts = @{}; foreach ($g in $grouped) { $dirCounts[$g.Name] = $g.Count }
$dirFiles  = @{}; foreach ($g in $grouped) { $dirFiles[$g.Name]  = @($g.Group) }

$totalNfo  = $nfoFilesAll.Count
$totalDirs = $dirOrder.Count
$processed = 0

$scopeText = if ($DoRecurse) { "（含子文件夹）" } else { "（仅当前文件夹）" }
Write-Host "  $(col_a_success "发现 NFO 文件数：$totalNfo（共 $totalDirs 个文件夹）$scopeText")"

if ($totalNfo -eq 0) {
    Write-Host "  $(col_a_warning '⚠  没有找到任何 nfo 文件，退出。')"
    Wait-AnyKey
    exit 0
}

Write-Host "  $(col_a_text_muted '运行中按 [P] 可暂停，并按需保存半成品')"
Write-Host ""

# ========== 6. 解析 NFO ==========
$rows = New-Object System.Collections.Generic.List[PSCustomObject]
$noFileinfoCount = 0
$parseErrorCount = 0

foreach ($dir in $dirOrder) {
    $completedDirs = ($dirOrder.IndexOf($dir) + 1)
    $dirNfos  = $dirFiles[$dir]
    $dirTotal = $dirCounts[$dir]
    $dirDone  = 0

    $dirName = Split-Path $dir -Leaf
    if ([string]::IsNullOrEmpty($dirName)) { $dirName = $dir }

    foreach ($nfoPath in $dirNfos) {
        $dirDone++
        $processed++

        # 进度行：固定显示目录名前 10 个字符，ANSI 清行避免残留
        $prefix = ("{0}/{1}（文件夹）  {2}/{3}（NFO）  [{4}/{5}] " -f `
            $completedDirs, $totalDirs, $processed, $totalNfo, $dirDone, $dirTotal)

        $fixedLimit = 10
        if ($dirName.Length -gt $fixedLimit) {
            $showName = $dirName.Substring(0, $fixedLimit) + "…"
        } else {
            $showName = $dirName
        }

        Write-Host ("`r  " + (col_a_text_muted ($prefix + $showName)) + "  $([char]27)[K") -NoNewline

        # 暂停 / 保存半成品
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.KeyChar -eq 'p' -or $key.KeyChar -eq 'P') {
                Write-Host ""
                Write-Host "  $(col_a_warning '[暂停] 已暂停。')"
                Write-Host "  $(col_a_text_muted '[S] 保存半成品 ｜ [C] 继续扫描 ｜ [Q] 保存并退出 ｜ Ctrl+C 直接中断')"
                $paused = $true
                while ($paused) {
                    Start-Sleep -Milliseconds 100
                    if ([Console]::KeyAvailable) {
                        $subKey = [Console]::ReadKey($true)
                        switch ($subKey.KeyChar) {
                            's' {
                                try {
                                    $partialContent = ($rows | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
                                    [System.IO.File]::WriteAllText($CsvPath, $partialContent, [System.Text.Encoding]::UTF8)
                                    Write-Host "  $(col_a_success "✅ 半成品已保存（$($rows.Count) 条）：$CsvPath")"
                                } catch {
                                    Write-Host "  $(col_a_error "❌ 保存失败：$($_.Exception.Message)")"
                                }
                            }
                            'c' {
                                $paused = $false
                                Write-Host "  $(col_a_success '[继续] 恢复扫描...')"
                                Write-Host ""
                            }
                            'q' {
                                try {
                                    $partialContent = ($rows | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
                                    [System.IO.File]::WriteAllText($CsvPath, $partialContent, [System.Text.Encoding]::UTF8)
                                    Write-Host "  $(col_a_success "✅ 已保存（$($rows.Count) 条），正在退出...")"
                                } catch { }
                                Wait-AnyKey "  按任意键退出..."
                                exit 0
                            }
                        }
                    }
                }
            }
        }

        try {
            # 编码探测后读取（兼容 GBK / UTF-16）
            $bytes = [System.IO.File]::ReadAllBytes($nfoPath)
            $enc = Get-NfoEncoding -Bytes $bytes
            if ($null -eq $enc) { $parseErrorCount++; continue }
            $nfoText = $enc.GetString($bytes)
            # 关键：带 BOM 的文件解码后首字符是 U+FEFF，
            # 直接交给 XmlDocument.LoadXml 会抛 "Data at the root level is invalid"
            $nfoText = $nfoText.TrimStart([char]0xFEFF)

            $xml = New-Object System.Xml.XmlDocument
            $xml.LoadXml($nfoText)

            $fi = $xml.SelectSingleNode("//fileinfo/streamdetails")
            if (-not $fi) { $noFileinfoCount++; continue }

            $v = $fi.SelectSingleNode("video")
            $a = $fi.SelectSingleNode("audio")

            # 时长
            $durSec = 0
            if ($v) {
                $secNode = $v.SelectSingleNode("durationinseconds")
                if ($secNode -and [double]::TryParse($secNode.InnerText, [ref]$durSec)) {
                } elseif ($v.duration -and [double]::TryParse($v.duration, [ref]$durSec)) {
                }
            }
            $totalSec = [int][Math]::Floor($durSec)
            $h  = [int]($totalSec / 3600)
            $rem = $totalSec % 3600
            $m  = [int]($rem / 60)
            $s  = [int]($rem % 60)
            $durationStr = "{0:D2}h{1:D2}m{2:D2}s" -f $h, $m, $s
            $durationSec = if ($totalSec -gt 0) { $totalSec } else { "-" }

            $width = 0; $height = 0
            if ($v -and $v.width)  { [int]::TryParse($v.width,  [ref]$width)  | Out-Null }
            if ($v -and $v.height) { [int]::TryParse($v.height, [ref]$height) | Out-Null }

            $vBit = 0; $aBit = 0
            if ($v -and $v.bitrate) { [long]::TryParse($v.bitrate, [ref]$vBit) | Out-Null }
            if ($a -and $a.bitrate) { [long]::TryParse($a.bitrate, [ref]$aBit) | Out-Null }

            $fpsVal = 0.0
            $fpsOut = "-"
            if ($v -and $v.framerate -and [double]::TryParse($v.framerate, [ref]$fpsVal)) {
                $fpsOut = [Math]::Round($fpsVal, 1)
            }

            $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($nfoPath)
            $parentDir = [System.IO.Path]::GetDirectoryName($nfoPath)

            # 同名视频匹配
            $videoPath  = "未检测"
            $fileSizeMB = "-"
            if ($DoMatchVideo) {
                $videoPath = "(未找到同名视频)"
                foreach ($ext in $videoExtsPattern) {
                    foreach ($c in [System.IO.Directory]::GetFiles($parentDir, $ext)) {
                        if ([System.IO.Path]::GetFileNameWithoutExtension($c) -eq $baseName) {
                            $videoPath = $c
                            try {
                                $realFile = New-Object System.IO.FileInfo($videoPath)
                                if ($realFile.Exists) {
                                    $b = $realFile.Length
                                    if ($b -ge 1MB)      { $fileSizeMB = [Math]::Round($b / 1MB, 2) }
                                    elseif ($b -ge 1KB)  { $fileSizeMB = [Math]::Round($b / 1KB, 2) }
                                    else                 { $fileSizeMB = $b }
                                }
                            } catch { }
                            break
                        }
                    }
                    if ($videoPath -ne "(未找到同名视频)") { break }
                }
            }

            $vBitrateKbps     = if ($vBit -gt 0) { [int][Math]::Round($vBit / 1024) } else { "-" }
            $aBitrateKbps     = if ($aBit -gt 0) { [int][Math]::Round($aBit / 1024) } else { "-" }
            $totalBitrateKbps = if (($vBit + $aBit) -gt 0) { [int][Math]::Round(($vBit + $aBit) / 1024) } else { "-" }

            # 根节点探测：movie / episodedetails / tvshow（旧版只认 movie）
            $rootNode = $null
            foreach ($tag in @('movie', 'episodedetails', 'tvshow')) {
                $node = $xml.SelectSingleNode("//$tag")
                if ($node) { $rootNode = $node; break }
            }
            $nfoTitle = if ($rootNode -and $rootNode.title) { $rootNode.title.ToString() } else { "" }
            $nfoTitleOut = if ([string]::IsNullOrEmpty($nfoTitle)) { "-" } else { $nfoTitle }
            $nameCheck = if ($baseName -eq $nfoTitle) { "一致" } else { "（不一致）" }

            $rows.Add([PSCustomObject]@{
                NFO内文件名校验 = $nameCheck
                NFO文件名        = $baseName
                NFO内标题名      = $nfoTitleOut
                文件大小_MB      = $fileSizeMB
                时长             = $durationStr
                时长_秒          = $durationSec
                视频编码         = if ($v -and $v.codec) { $v.codec } else { "-" }
                分辨率           = if ($width -gt 0 -and $height -gt 0) {
                    if ($width -lt $height) { "$height`x$width（竖屏）" } else { "$width`x$height" }
                } else { "-" }
                视频码率_kbps    = $vBitrateKbps
                音频码率_kbps    = $aBitrateKbps
                总码率_kbps      = $totalBitrateKbps
                帧率             = $fpsOut
                音频编码         = if ($a -and $a.codec) { $a.codec } else { "-" }
                声道             = if ($a -and $a.channels) { $a.channels } else { "-" }
                视频文件路径     = $videoPath
                NFO路径          = $nfoPath
            }) | Out-Null
        } catch {
            $parseErrorCount++
        }
    }
}

# ========== 7. 收尾 ==========
$finishText = ("{0}/{1}（文件夹）  {2}/{3}（NFO）  完成！" -f $totalDirs, $totalDirs, $totalNfo, $totalNfo)
Write-Host ("`r  " + (col_a_success $finishText) + "  $([char]27)[K")
Write-Host ""

$sw.Stop()
$elapsed = $sw.Elapsed

Write-Host "  $(col_a_line (sep))"
Write-Host "  $(col_a_success '扫描完成')"
Write-Host "  $(col_a_text_muted '  总 NFO 数：            ')$(col_a_text $totalNfo)"
Write-Host "  $(col_a_text_muted '  涉及文件夹数：         ')$(col_a_text $totalDirs)"
Write-Host "  $(col_a_text_muted '  解析成功：             ')$(col_a_success $rows.Count)"
Write-Host "  $(col_a_text_muted '  无 fileinfo 段：       ')$(col_a_warning $noFileinfoCount)"
Write-Host "  $(col_a_text_muted '  XML 解析/读取失败：    ')$(col_a_error $parseErrorCount)"
Write-Host "  $(col_a_line (sep))"

if ($rows.Count -eq 0) {
    Write-Host ""
    Write-Host "  $(col_a_error '❌  没有有效数据可导出，退出。')"
    Wait-AnyKey
    exit 0
}

# ========== 8. 导出 CSV ==========
try {
    $csvContent = ($rows | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
    [System.IO.File]::WriteAllText($CsvPath, $csvContent, [System.Text.Encoding]::UTF8)
    Write-Host ""
    Write-Host "  $(col_a_success '✅  CSV 已导出：')"
    Write-Host "  $(col_a_text $CsvPath)"
} catch {
    Write-Host ""
    Write-Host "  $(col_a_error ('[错误] CSV 导出失败: ' + $_.Exception.Message))"
    Wait-AnyKey "  按任意键退出..."
    exit 1
}

# ========== 9. 孤立 nfo 处理（仅开启同名视频匹配时） ==========
if ($DoMatchVideo) {
    $orphanAll = @($rows | Where-Object { $_.'视频文件路径' -eq '(未找到同名视频)' })

    # 白名单过滤：movie.nfo / tvshow.nfo / poster.nfo 等附属文件不是孤立文件
    $orphanNfos = @($orphanAll | Where-Object { -not (Test-ArtBaseName -BaseName $_.'NFO文件名') })
    $skippedByWhitelist = $orphanAll.Count - $orphanNfos.Count

    if ($orphanNfos.Count -gt 0) {
        Write-Host ""
        Write-Host "  $(col_a_warning "⚠  发现 $($orphanNfos.Count) 个 nfo 未找到同名视频：")"
        if ($skippedByWhitelist -gt 0) {
            Write-Host "  $(col_a_text_muted "（另有 $skippedByWhitelist 个附属/元数据 nfo 已按白名单排除，不参与清理）")"
        }
        Write-Host ""

        $showCount = [Math]::Min(10, $orphanNfos.Count)
        for ($i = 0; $i -lt $showCount; $i++) {
            Write-Host "  $(col_a_text_muted ("{0}. " -f ($i + 1)))$(col_a_text $orphanNfos[$i].'NFO路径')"
        }
        if ($orphanNfos.Count -gt $showCount) {
            Write-Host "  $(col_a_text_muted ("  … 还有 " + ($orphanNfos.Count - $showCount) + " 个未显示"))"
        }

        Write-Host ""
        Write-Host "  $(col_a_text ('孤立 nfo 处理：'))"
        Write-Host "  $(col_a_line (sep_weak))"

        $orphanOpts = @(
            @{ Label = "[d]删除"; Value = "delete" }
            @{ Label = "[s]仅导出列表 txt"; Value = "export" }
            @{ Label = "[n]跳过（推荐）"; Value = "skip" }
            @{ Label = "[q/Esc]退出"; Value = "exit" }
        )
        $orphanResult = Select-Horizontal -Options $orphanOpts -Prompt "" -InitialIndex 2

        if ($null -ne $orphanResult -and $orphanResult -eq 'delete') {
            Write-Host ""
            $deletedCount = 0
            $failCount = 0
            foreach ($o in $orphanNfos) {
                $nfoToDelete = $o.'NFO路径'
                try {
                    if ([System.IO.File]::Exists($nfoToDelete)) {
                        [System.IO.File]::Delete($nfoToDelete)
                        Write-Host "  $(col_a_success "🗑 已删除：$nfoToDelete")"
                        $deletedCount++
                    } else {
                        Write-Host "  $(col_a_warning "⚠ 文件不存在，跳过：$nfoToDelete")"
                    }
                } catch {
                    Write-Host "  $(col_a_error "❌ 删除失败：$nfoToDelete ($($_.Exception.Message))")"
                    $failCount++
                }
            }
            Write-Host ""
            Write-Host "  $(col_a_text ('清理完成：成功 '))$(col_a_success $deletedCount)$(col_a_text ' 个，失败 ')$(col_a_error $failCount)$(col_a_text ' 个')"
        }
        elseif ($null -ne $orphanResult -and $orphanResult -eq 'export') {
            $txtPath = [System.IO.Path]::Combine($ValidRoot, "未找到同名视频文件的nfo列表.txt")
            try {
                $txtLines = @($orphanNfos | ForEach-Object { $_.'NFO路径' })
                [System.IO.File]::WriteAllLines($txtPath, $txtLines, [System.Text.Encoding]::UTF8)
                Write-Host "  $(col_a_success "✅ 列表已导出（$($orphanNfos.Count) 条）：$txtPath")"
            } catch {
                Write-Host "  $(col_a_error "❌ 导出失败：$($_.Exception.Message)")"
            }
        }
        else {
            Write-Host "  $(col_a_text_muted '⚪  已跳过孤立 nfo 处理，保留全部文件。')"
        }
    }
    elseif ($skippedByWhitelist -gt 0) {
        Write-Host ""
        Write-Host "  $(col_a_success "✅  未发现需要清理的孤立 nfo（$skippedByWhitelist 个附属/元数据 nfo 已排除）")"
    }
}

# ========== 10. 结束 ==========
Write-Host ""
Write-Host "  $(col_a_line (sep))"
Write-Host "  $(col_a_success ("  本次耗时：{0}小时{1}分钟{2}秒" -f $elapsed.Hours, $elapsed.Minutes, $elapsed.Seconds))"
Write-Host "  $(col_a_line (sep))"
Write-Host ""
Wait-AnyKey "  按任意键退出..."
return