<#
.SYNOPSIS
    Emby NFO 扫描与元数据 CSV 导出脚本
.DESCRIPTION
    递归扫描 Emby/Jellyfin 生成的 NFO 文件，提取视频/音频流信息（时长、编码、分辨率、码率等），
    导出为 UTF-8 CSV。码率统一 kbps（整数）、文件大小统一 MB（纯数字）、帧率保留 1 位小数、
    时长新增纯秒数列；新增 NFO 内文件名校验列（严格比对文件名与 <title>，原文一字不差才判一致）；
    单位写在列标题、单元格纯数字，方便 Excel 筛选排序。
.PARAMETER NfoRoot
    扫描根目录，默认当前目录
.PARAMETER CsvName
    CSV 文件名，默认带时间戳
.NOTES
    版本: v2.4（基于 v1.8 基线）
    兼容: PowerShell 2.0 / 5.1 / 7
    特性: UNC/超长路径支持、纯 XML 解析不依赖 ffprobe、字段缺失不中断、
          实时进度显示、递归开关（默认递归，可仅扫当前目录）、
          同名视频匹配时附加读取真实文件大小、全程耗时统计

    ── 修改记录 ──
    v1.0  初版骨架，Get-ChildItem 递归，时长用 duration 显示"X分"
    v1.1  改用 .NET Directory::GetFiles + Queue 枚举，修复 UNC/超长路径
    v1.2  试验 durationinseconds 节点，因未判空+格式化崩溃导致全批失败
    v1.3  加诊断日志，定位真因：{0:D2} 格式符收到 double 类型抛异常
    v1.4  修复：totalSec/m/s 强制 [int] 转整数，时长正常显示 00h00m12s
    v1.5  加同名视频匹配开关（默认 N 跳过，提速）；占位符改"未检测"；
          分辨率加竖屏对调（width<height 时输出 高x宽（竖屏））；保留 NFO路径列
    v1.6  按文件夹分组枚举，单行覆盖刷新进度条，显示 X/XX（文件夹）X/XX（NFO）
    v1.7  加递归扫描开关（默认 Y 递归，输入 N 仅扫当前文件夹）
    v1.8  同名视频匹配开启时附加读取真实文件大小；新增全程耗时统计
    v2.1  文件大小统一 MB（纯数字）；码率统一 kbps（÷1024，纯数字）
    v2.2  码率改为整数；帧率保留 1 位小数；新增「时长_秒」列（放在原时长列右侧）
    v2.3  列名改清楚（NFO文件名 / NFO内标题名）；新增「NFO内文件名校验」列
          置顶为第一列，原文严格比对文件名与 <title>，一致写"一致"，
          不同写"（不一致）"，不加 Trim、不排空格换行、不转换大小写
    v2.4  新增中途暂停/保存半成品功能：运行中按 P 暂停，暂停态按 S 保存当前
          已解析数据到 CSV（覆盖写入），按 C 继续扫描，按 Q 保存并退出；
          预扫描锁定文件夹总数，进度条分母固定不跳，收尾强制对齐
	v2.5  优化进度条显示，彻底解决长目录名折行刷屏
	v2.6.2：放弃动态宽度计算，进度条目录名固定显示前10个汉字（超长加"..."）。彻底解决长目录名临界折行/刷屏，保留前-5安全边距。
	v2.7：扫描完成后新增"未找到同名视频"NFO处理功能。仅开启同名视频匹配时触发，统计结果中视频路径为"(未找到同名视频)"的条目，显示预览列表（最多10行），提供三选一操作：[Y]清理删除 [S]仅导出路径列表为txt [N]跳过（默认）。txt文件名为"未找到同名视频文件的nfo列表.txt"，UTF-8编码，保存至扫描根目录。延续v2.6.2进度条防折行方案。
	v2.8：根据同名视频匹配开关决定输出CSV文件名前缀（对齐MAXM最新读取本插件生成的CSV功能）。
	选N（不匹配）时生成 nfo_export_onlynfo_*.csv，选Y（匹配）时生成默认 nfo_export_*.csv
#>

param(
    [string]$NfoRoot = $PWD.ProviderPath,
    [string]$CsvName = ""   # 留空，由下方根据匹配开关动态生成
)

# ── 0. 扫描范围 + 同名视频匹配开关（一键响应，无需回车） ──
Write-Host "================" -ForegroundColor Cyan
Write-Host "扫描范围设置"
Write-Host "================" -ForegroundColor Cyan

Write-Host "是否递归扫描子文件夹？[Y/N，默认 Y（直接按键=Y）]: " -NoNewline
$keyRecurse = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
$RecurseInput = $keyRecurse.Character
Write-Host $RecurseInput
$DoRecurse = ($RecurseInput -ne 'n' -and $RecurseInput -ne 'N')
if ($DoRecurse) { Write-Host "✅ 将递归扫描所有子文件夹" -ForegroundColor Green }
else { Write-Host "⚠️ 仅扫描当前文件夹（不含子目录）" -ForegroundColor Yellow }

Write-Host ""
Write-Host "是否启用【同名视频匹配】？（耗时较长，仅用于比对视频和NFO）" -ForegroundColor Cyan
Write-Host "输入Y启用，直接按键或输入N跳过 [默认：N]: " -NoNewline
$keyMatch = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
$MatchInput = $keyMatch.Character
Write-Host $MatchInput
$DoMatchVideo = ($MatchInput -eq 'y' -or $MatchInput -eq 'Y')
# >>> v2.8 根据同名视频匹配开关动态决定CSV文件名前缀
if ([string]::IsNullOrWhiteSpace($CsvName)) {
    if ($DoMatchVideo) {
        $CsvName = "nfo_export_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    } else {
        $CsvName = "nfo_export_onlynfo_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    }
}
Write-Host "→ 同名视频匹配: $(if($DoMatchVideo){'开启'}else{'关闭（跳过，速度最快）'})`n" -ForegroundColor Green

# ── 1. 路径严格预处理 ── 下方部分内容已被V2.8动态名称实质废弃，暂不改，不影响运行
try {
    $rootInfo = New-Object System.IO.DirectoryInfo($NfoRoot)
    if (-not $rootInfo.Exists) { throw "目录不存在: $NfoRoot" }
    $ValidRoot = $rootInfo.FullName

    if ([string]::IsNullOrWhiteSpace($CsvName)) { $CsvName = "nfo_export.csv" }
    $CsvPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($ValidRoot, $CsvName))
} catch {
    Write-Host "[错误] 路径处理失败: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "按回车退出"; exit 1
}

Write-Host "================" -ForegroundColor Cyan
Write-Host "Emby NFO 扫描 → CSV 导出"
Write-Host "扫描根目录: $ValidRoot"
Write-Host "输出文件:   $CsvPath"
Write-Host "================" -ForegroundColor Cyan

# ── 2. 枚举 NFO（受递归开关控制），按目录分组预统计 ──
Write-Host "正在索引文件，请稍候..." -ForegroundColor Cyan

$sw = [System.Diagnostics.Stopwatch]::StartNew()

$searchOpt = if ($DoRecurse) { [System.IO.SearchOption]::AllDirectories } else { [System.IO.SearchOption]::TopDirectoryOnly }
$nfoFilesAll = [System.IO.Directory]::GetFiles($ValidRoot, "*.nfo", $searchOpt)

$grouped  = $nfoFilesAll | Group-Object { Split-Path $_ -Parent }
$dirOrder = @($grouped | ForEach-Object { $_.Name })
$dirCounts = @{}; foreach ($g in $grouped) { $dirCounts[$g.Name] = $g.Count }
$dirFiles  = @{}; foreach ($g in $grouped) { $dirFiles[$g.Name]  = @($g.Group) }

$totalNfo   = $nfoFilesAll.Count
$totalDirs  = $dirOrder.Count   # ✅ 锁定总文件夹数，后续不跳动
$processed  = 0

$scopeText = if ($DoRecurse) { "（含子文件夹）" } else { "（仅当前文件夹）" }
Write-Host "发现 NFO 文件数: $totalNfo（共 $totalDirs 个文件夹）$scopeText" -ForegroundColor Cyan
Write-Host "运行中按 [P] 可暂停并按需保存半成品`n" -ForegroundColor Cyan

# ── 3. 解析 NFO（分组遍历 + 实时进度） ──
$rows = New-Object System.Collections.Generic.List[PSCustomObject]
$noFileinfoCount = 0; $parseErrorCount = 0

foreach ($dir in $dirOrder) {
    $completedDirs = ($dirOrder.IndexOf($dir) + 1)   # ✅ 当前已遍历到第几个文件夹（1~totalDirs）
    $dirNfos      = $dirFiles[$dir]
    $dirTotal     = $dirCounts[$dir]
    $dirDone      = 0

    $dirName = Split-Path $dir -Leaf
    if ([string]::IsNullOrEmpty($dirName)) { $dirName = $dir }

    foreach ($nfoPath in $dirNfos) {
        $dirDone++
        $processed++

        # ✅ v2.6.2 进度条：固定显示前10字，超长加…，前-5安全边距
        $prefix = ("{0}/{1}（文件夹）  {2}/{3}（NFO）  [{4}/{5}] " -f `
            $completedDirs, $totalDirs, $processed, $totalNfo, $dirDone, $dirTotal)
        $winWidth = $Host.UI.RawUI.WindowSize.Width
        if ($winWidth -le 0) { $winWidth = 120 }
        $maxLine = $winWidth - 5  # 前-5防折行

        # 固定10字限制
        $fixedLimit = 10
        if ($dirName.Length -gt $fixedLimit) {
            $showName = $dirName.Substring(0, $fixedLimit) + "…"
        } else {
            $showName = $dirName
        }

        $rawText = $prefix + $showName
        # 铺空格擦除旧行（用maxLine确保覆盖）
        Write-Host ("`r" + (" " * $maxLine)) -NoNewline
        Write-Host ("`r" + $rawText) -NoNewline -ForegroundColor DarkGray

        # ── v2.4 新增：非阻塞按键监听（按 P 暂停） ──
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            if ($key.KeyChar -eq 'p' -or $key.KeyChar -eq 'P') {
                Write-Host "`n[暂停] 已暂停。按 S=保存半成品 | C=继续 | Q=保存并退出 | CTRL+C直接中断脚本" -ForegroundColor Yellow
                $paused = $true
                while ($paused) {
                    Start-Sleep -Milliseconds 100
                    if ([Console]::KeyAvailable) {
                        $subKey = [Console]::ReadKey($true)
                        switch ($subKey.KeyChar) {
                            's' {
                                # 保存半成品 CSV（覆盖写入当前路径）
                                try {
                                    $partialContent = ($rows | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
                                    [System.IO.File]::WriteAllText($CsvPath, $partialContent, [System.Text.Encoding]::UTF8)
                                    Write-Host "  ✅ 半成品已保存（$((($rows).Count)) 条）: $CsvPath" -ForegroundColor Green
                                } catch {
                                    Write-Host "  ❌ 保存失败: $($_.Exception.Message)" -ForegroundColor Red
                                }
                            }
                            'c' {
                                $paused = $false
                                Write-Host "  [继续] 恢复扫描...`n" -ForegroundColor Cyan
                            }
                            'q' {
                                # 保存并退出
                                try {
                                    $partialContent = ($rows | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
                                    [System.IO.File]::WriteAllText($CsvPath, $partialContent, [System.Text.Encoding]::UTF8)
                                    Write-Host "  ✅ 已保存（$((($rows).Count)) 条），正在退出..." -ForegroundColor Green
                                } catch {}
                                Write-Host "`n按任意键退出..."
                                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                                exit 0
                            }
                        }
                    }
                }
            }
        }
        # ── v2.4 按键监听结束 ──

        try {
            $xml = New-Object System.Xml.XmlDocument
            $xml.LoadXml([System.IO.File]::ReadAllText($nfoPath))
            $fi = $xml.SelectSingleNode("//fileinfo/streamdetails")
            if (-not $fi) { $noFileinfoCount++; continue }

            $v = $fi.SelectSingleNode("video"); $a = $fi.SelectSingleNode("audio")

            # ✅ 时长：安全取值 + 强制转整数
            $durSec = 0
            $secNode = $v.SelectSingleNode("durationinseconds")
            if ($secNode -and [double]::TryParse($secNode.InnerText, [ref]$durSec)) {
            } elseif ($v.duration -and [double]::TryParse($v.duration, [ref]$durSec)) {
            }
            $totalSec = [int][Math]::Floor($durSec)
            $h  = [int]($totalSec / 3600)
            $rem = $totalSec % 3600
            $m  = [int]($rem / 60)
            $s  = [int]($rem % 60)
            $durationStr = "{0:D2}h{1:D2}m{2:D2}s" -f $h, $m, $s
            $durationSec = if ($totalSec -gt 0) { $totalSec } else { "-" }   # 纯秒数（筛选用）

            $width=0; $height=0
            if ($v.width)  { [int]::TryParse($v.width,  [ref]$width)  | Out-Null }
            if ($v.height) { [int]::TryParse($v.height, [ref]$height) | Out-Null }
            $vBit=0; $aBit=0
            if ($v.bitrate) { [long]::TryParse($v.bitrate, [ref]$vBit) | Out-Null }
            if ($a.bitrate) { [long]::TryParse($a.bitrate, [ref]$aBit) | Out-Null }
            $fpsVal = 0.0

            $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($nfoPath)
            $parentDir = [System.IO.Path]::GetDirectoryName($nfoPath)

            # ── 视频匹配（受开关控制，默认跳过） ──
            $videoPath = "未检测"
            $fileSizeMB = "-"
            if ($DoMatchVideo) {
                $videoPath = "(未找到同名视频)"
                foreach ($ext in @("*.mp4","*.mov","*.mkv","*.avi","*.flv","*.wmv","*.m4v","*.ts","*.mpg","*.mpeg","*.f4v","*.m2ts","*.mts","*.webm","*.rmvb")) {
                    foreach ($c in [System.IO.Directory]::GetFiles($parentDir, $ext)) {
                        if ([System.IO.Path]::GetFileNameWithoutExtension($c) -eq $baseName) {
                            $videoPath = $c
                            try {
                                $realFile = [System.IO.FileInfo]::new($videoPath)
                                if ($realFile.Exists) {
                                    $b = $realFile.Length
                                    if ($b -ge 1MB) { $fileSizeMB = [Math]::Round($b/1MB, 2) }
                                    elseif ($b -ge 1KB) { $fileSizeMB = [Math]::Round($b/1KB, 2) }
                                    else { $fileSizeMB = $b }
                                }
                            } catch {}
                            break
                        }
                    }
                    if ($videoPath -ne "(未找到同名视频)") { break }
                }
            }

            # 码率统一 kbps，只取整数部分
            $vBitrateKbps  = if ($vBit -gt 0) { [int][Math]::Round($vBit / 1024) } else { "-" }
            $aBitrateKbps  = if ($aBit -gt 0) { [int][Math]::Round($aBit / 1024) } else { "-" }
            $totalBitrateKbps = if (($vBit + $aBit) -gt 0) { [int][Math]::Round(($vBit + $aBit) / 1024) } else { "-" }

            # 帧率保留 1 位小数
            $fpsOut = if ($v.framerate -and [double]::TryParse($v.framerate, [ref]$fpsVal)) { [Math]::Round($fpsVal, 1) } else { "-" }

            # 名称校验：NFO 文件名（去扩展名）vs NFO 内 <title>，原文严格比对
            $nfoTitle = if ($xml.movie.title) { $xml.movie.title.ToString() } else { "" }
            if ($baseName -eq $nfoTitle) { $nameCheck = "一致" } else { $nameCheck = "（不一致）" }

            $rows.Add([PSCustomObject]@{
                NFO内文件名校验 = $nameCheck
                NFO文件名        = $baseName
                NFO内标题名      = if($xml.movie.title) { $xml.movie.title } else { "-" }
                文件大小_MB      = $fileSizeMB
                时长             = $durationStr
                时长_秒          = $durationSec
                视频编码         = if($v.codec)    { $v.codec }    else { "-" }
                分辨率           = if ($width -gt 0 -and $height -gt 0) {
                    if ($width -lt $height) { "$height`x$width（竖屏）" } else { "$width`x$height" }
                } else { "-" }
                视频码率_kbps    = $vBitrateKbps
                音频码率_kbps    = $aBitrateKbps
                总码率_kbps      = $totalBitrateKbps
                帧率             = $fpsOut
                音频编码         = if($a.codec)    { $a.codec }    else { "-" }
                声道             = if($a.channels) { $a.channels } else { "-" }
                视频文件路径     = $videoPath
                NFO路径          = $nfoPath
            }) | Out-Null
        } catch { $parseErrorCount++ }
    }
}

# ✅ 收尾：防折行 + 对齐定格
$winWidth = $Host.UI.RawUI.WindowSize.Width
if ($winWidth -le 0) { $winWidth = 120 }
$maxLine = $winWidth - 10
$finishText = ("{0}/{1}（文件夹）  {2}/{3}（NFO）  完成！" -f $totalDirs, $totalDirs, $totalNfo, $totalNfo)
if ($finishText.Length -gt $maxLine) {
    $finishText = $finishText.Substring(0, $maxLine - 3) + "…"
}
Write-Host ("`r" + (" " * $maxLine)) -NoNewline
Write-Host ("`r" + $finishText) -ForegroundColor Green
Write-Host ""

$sw.Stop()
$elapsed = $sw.Elapsed

# ── 4. 统计与导出 ──
Write-Host "====================" -ForegroundColor Cyan
Write-Host "扫描完成" -ForegroundColor Green
Write-Host "  总 NFO 数:            $totalNfo"
Write-Host "  涉及文件夹数:         $totalDirs（已遍历 $($dirOrder.Count)，对齐至 $totalDirs）"
Write-Host "  解析成功:             $($rows.Count)"
Write-Host "  无 fileinfo 段:       $noFileinfoCount"
Write-Host "  XML 解析失败/读取失败: $parseErrorCount"
Write-Host "====================" -ForegroundColor Cyan

if ($rows.Count -eq 0) {
    Write-Host "`n没有有效数据可导出，退出。" -ForegroundColor Red
    Read-Host "按回车退出"; exit 0
}

try {
    $csvContent = ($rows | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
    [System.IO.File]::WriteAllText($CsvPath, $csvContent, [System.Text.Encoding]::UTF8)
    Write-Host "`n✅ CSV 已导出:" -ForegroundColor Green
    Write-Host "   $CsvPath" -ForegroundColor Cyan
} catch {
    Write-Host "`n[错误] CSV 导出失败: $($_.Exception.Message)" -ForegroundColor Red
}

# ── 5. 未找到同名视频的 NFO 清理（仅开启同名视频匹配时触发） ──
if ($DoMatchVideo) {
    $orphanNfos = $rows | Where-Object { $_."视频文件路径" -eq "(未找到同名视频)" }
    $orphanCount = @($orphanNfos).Count

    if ($orphanCount -gt 0) {
        Write-Host "`n====================" -ForegroundColor Yellow
        Write-Host "发现 $orphanCount 个 NFO 文件未找到同名视频文件" -ForegroundColor Yellow

        # 预览：最多显示10行完整路径+文件名
        $previewList = @($orphanNfos | Select-Object -First 10)
        $previewIndex = 0
        foreach ($item in $previewList) {
            $previewIndex++
            Write-Host ("  {0}. {1}" -f $previewIndex, $item."NFO路径") -ForegroundColor DarkYellow
        }
        if ($orphanCount -gt 10) {
            $remainCount = $orphanCount - 10
            Write-Host ("  … 还有 $remainCount 个未显示") -ForegroundColor DarkGray
        }

        Write-Host ""
        Write-Host "请选择操作：[Y]清理删除  [S]仅导出列表  [N]跳过（默认 N）: " -NoNewline -ForegroundColor Cyan
        $keyClean = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $cleanInput = $keyClean.Character
        Write-Host $cleanInput

        if ($cleanInput -eq 'y' -or $cleanInput -eq 'Y') {
            # ── Y：清理删除 ──
            $deletedCount = 0
            $failCount = 0
            Write-Host "`n开始清理..." -ForegroundColor Cyan
            foreach ($orphan in $orphanNfos) {
                $nfoToDelete = $orphan."NFO路径"
                try {
                    if ([System.IO.File]::Exists($nfoToDelete)) {
                        [System.IO.File]::Delete($nfoToDelete)
                        Write-Host "  ✅ 已删除: $nfoToDelete" -ForegroundColor Green
                        $deletedCount++
                    } else {
                        Write-Host "  ⚠️ 文件不存在，跳过: $nfoToDelete" -ForegroundColor Yellow
                    }
                } catch {
                    Write-Host "  ❌ 删除失败: $nfoToDelete ($($_.Exception.Message))" -ForegroundColor Red
                    $failCount++
                }
            }
            Write-Host "`n清理完成：成功删除 $deletedCount 个，失败 $failCount 个`n" -ForegroundColor Green

        } elseif ($cleanInput -eq 's' -or $cleanInput -eq 'S') {
            # ── S：仅导出列表为 txt ──
            $txtFileName = "未找到同名视频文件的nfo列表.txt"
            $txtPath = [System.IO.Path]::Combine($ValidRoot, $txtFileName)
            try {
                $txtLines = @($orphanNfos | ForEach-Object { $_."NFO路径" })
                [System.IO.File]::WriteAllLines($txtPath, $txtLines, [System.Text.Encoding]::UTF8)
                Write-Host "  ✅ 列表已导出（$orphanCount 条）: $txtPath" -ForegroundColor Green
            } catch {
                Write-Host "  ❌ 导出失败: $($_.Exception.Message)" -ForegroundColor Red
            }

        } else {
            # ── N 或回车：跳过 ──
            Write-Host "⏭️ 跳过清理，保留所有 NFO 文件" -ForegroundColor Gray
        }
        Write-Host "====================" -ForegroundColor Yellow
    }
}

Write-Host "`n====================" -ForegroundColor Cyan
Write-Host ("  本次执行耗时: {0}小时{1}分钟{2}秒" -f $elapsed.Hours, $elapsed.Minutes, $elapsed.Seconds) -ForegroundColor Green
Write-Host "====================" -ForegroundColor Cyan

Write-Host "`n按任意键退出..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")