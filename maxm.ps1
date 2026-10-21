<#
maxm_v3.ps1
变更要点：
1. D模式：主排序按时长，保留全局预读全部时长
2. B/R模式：不全局读时长，后置询问
3. S开启元数据：后置扫描交互
4. 非交互模式：param() 驱动，-UserQuery 强制，txt 文件名用原文
5. S/B 模式均支持 -MinBitrate 码率筛选
6. Test-Path 全部用 -LiteralPath 防特殊字符
7. >>> FIX: 所有 $sorted/$outputRows 强制 @() 物化，防止单条结果时 Count=$null 导致 txt 空行
8. >>> FIX v5: 时长读取退回 cmd /c + noprint_wrappers=1:nokey=1 + 重定向文件方案
    新增 Invoke-FfprobeDuration 函数，所有时长点（D模式预读/后置扫描/交互预读/交互后置）
    统一用旧代码稳定调用方式，解决 nw=1:nk=1 + -- 分隔符 + RedirectStandardOutput
    在部分 ffprobe 版本下静默失败导致时长全部读取失败的问题
9. >>> 交互模式 TXT 文件名和内部描述补全：基于用户交互选择生成 $fullDesc，
    区分交互/非交互命名规则，扫描路径去掉 PowerShell 底层前缀
10. >>> FIX v10: 交互模式时长逻辑修复：
    - S模式选读取元数据：ffprobe 已返回 duration，顺带提取，不再弹窗问时长
    - 不读元数据→后置扫时长：TXT 强制输出时长列（即使 $exportMeta=$false）
    - 后置扫完时长后刷新预览，让用户看到实际结果
11. >>> FIX v11: 双进度条（目录+文件），单行回车刷新
12. >>> FIX v12: B模式等非D模式时长显示修复：
    - 预览输出直接信任 $metaHasDuration 标记，不再依赖单条 $item.DurationDisp -ne "-"
    - TXT 保存同步修复 $hasDurationCol 判定
    - 确保 ffprobe json 中 format.duration 被正确解析并传递到最终输出
13. >>> FIX v13: 时长显示兜底 + 进度条单行刷新（2026-10-20）
    - 元数据解析前强制初始化 $durSec=0.0/$durDisp="-"，解析成功才覆盖，确保 $vi.DurationDisp 非空
    - 预览段：当 $metaHasDuration 为真时，若单条 DurationDisp 仍为 "-" 则用 Get-FriendlyDuration(0) 兜底显示 "00m00s"，避免全 "-"
    - 进度条：Show-DualProgressBar 已用 `r + Write-Host -NoNewline 单行覆盖，扫描结束 Write-Host "" 换行
    - TXT 保存维持 v12 的 $metaHasDuration 判定（不再改列逻辑）
14. >>> FIX v14: 准备阶段实时进度（2026-10-20）
    - 目录统计与文件收集合并为同一阶段，边遍历边显示单行进度，消除"假死感"
    - 非交互模式同步应用
15. >>> FIX v15: 三阶段线性融合进度条（2026-10-20）
    - 将整体进度分为：阶段1(目录遍历40%) + 阶段2(元数据读取60%)
    - 全程单行覆盖，从0%到100%连续推进，不再出现"进度条一闪而过"
    - Show-DualProgressBar 改为 Show-LinearProgressBar，显示总进度百分比
16. >>> FIX v16: 一次 ffprobe 全拿三件套 + 删后置扫描 + 进度条收尾（2026-10-20）
    - $extraArgs 统一追加 :format=duration，B/R/S(元数据) 模式一次调用拿全码率+分辨率+时长
    - 删除交互模式后置时长扫描弹窗及整个后置扫描逻辑（时长已在第一轮 ffprobe 中获取）
    - 删除非交互模式 $ScanDuration 后置扫描段
    - $metaHasDuration 简化为直接等于 $exportMeta（只要调 ffprobe 就有时长）
    - 预览段不再对0秒调用 Get-FriendlyDuration(0) 兜底
    - 交互模式阶段1进度条收尾从40%改为100%
    - TXT 输出列判定统一用 $exportMeta
17. >>> FIX v17: 百分比变化才刷新，防止爆发式刷屏（2026-10-20）
    - 阶段2主循环增加 $lastPct 变量，仅百分比变化或完成时调用 Show-LinearProgressBar
    - 配合 300ms 节流，解决并发 ffprobe 结果集中返回时进度条瞬间刷屏问题
18. >>> FIX v18: 阶段2进度条独立0-100%（2026-10-20）
    - 阶段2不再映射 40-100%，改为独立 0-100%（$processedCount/$totalVideoCount*100）
    - 修复原代码中 $pctVal=$phase2Current 引用不存在变量的 bug，改为 $pctVal=$phase2Pct
    - 阶段1(扫描)和阶段2(元数据)各自从0%走到100%，视觉边界清晰
19. >>> FIX v19: 最终大小过滤 + TXT 注明过滤统计（2026-10-20）
    - 新增 -MinSizeMB 参数，在排序完成后、预览输出前过滤掉小于指定大小的文件
    - 原排序逻辑（升降序）一字不动，过滤仅作为最终拦截环节
    - TXT 输出头部注明：按大小条件过滤掉多少个文件、过滤阈值是多少
20. >>> FIX v20: 二次排序（2026-10-20）
    - 新增 -ReSortBy 参数，支持对主排序结果集按另一维度重新排序
    - 支持维度：D(时长)、S(文件大小)、B(码率)、R(分辨率长边)
    - 默认降序排列，升序接口预留（-ReSortAsc 将来再加）
    - 执行位置：主排序完成后、大小过滤前，不改变原排序逻辑
    - 非交互/交互模式均支持
21. >>> FIX v21: 筛选漏斗统计，TXT头部按执行顺序输出各环节拦截数量（2026-10-20）
    - 新增漏斗计数变量：$heightFilteredCount, $sizeTopFilteredCount, $bitrateFilteredCount, $reSortCount, $sizeFilteredCount
    - 非交互/交互模式均在对应筛选环节插入计数
    - TXT 头部按实际执行顺序逐行输出：总扫描 → 高度过滤 → 体积初筛 → 码率过滤 → 二次排序 → 大小过滤 → 最终输出
    - 仅在该环节实际触发且拦截数>0时才输出对应行，保持简洁
#>

param(
    [string]$Mode = "",
    [string]$Path = "",
    [switch]$Recurse,
    [switch]$AllFiles,
    [switch]$Meta,
    [switch]$ScanDuration,
	
    [int]$Top = 100,
    [int]$BitrateThreshold = 0,
    [int]$MinBitrate = 0,
    [int]$MinHeight = 0,
    [int]$MaxHeight = 0,
    [string]$Output = "",
    [switch]$JsonOutput,
    [switch]$SizeTop,
    [int]$SizeTopCount = 100,
    [long]$MinSizeMB = 0,
    [string]$ReSortBy = "",           # >>> FIX v20: 二次排序维度，D/S/B/R，默认空=不二次排序
    [string]$UserQuery = ""
)

# ====================== 公共函数区 ======================
function Wait-KeyPress {
    param([string]$Prompt)
    if ($Mode -ne "") { return "" }
    Write-Host "$Prompt " -NoNewline
    while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    $char = $key.Character.ToString().ToUpper()
    while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
    Write-Host $char
    return $char
}

function Get-FriendlySize {
    param([long]$Bytes)
    $mb = $Bytes / 1MB; $gb = $Bytes / 1GB
    if ($gb -ge 1) { return "{0:N2} GB" -f $gb } else { return "{0:N2} MB" -f $mb }
}

function Get-FriendlyDuration {
    param([double]$TotalSec)
    if($null -eq $TotalSec -or $TotalSec -le 0){ return "读取失败" }
    $s = [Math]::Floor($TotalSec)
    $h = [Math]::Floor($s / 3600); $m = [Math]::Floor(($s % 3600)/60); $sec = $s % 60
    $hh = if($h -lt10){"0$h"}else{"$h"}; $mm = if($m -lt10){"0$m"}else{"$m"}; $ss = if($sec -lt10){"0$sec"}else{"$sec"}
    if($h -gt0){ return "$hh`h${mm}m${ss}s" } return "${mm}m${ss}s"
}

function Test-FfprobeAvailable {
    $null = Get-Command "ffprobe.exe" -ErrorAction SilentlyContinue
    return $?
}

function Cleanup-TaskProcesses {
    param($TaskList)
    if (-not $TaskList -or $TaskList.Count -eq 0) { return }
    foreach($task in $TaskList) {
        $proc = $task.Proc
        if($proc -ne $null -and -not $proc.HasExited) {
            try { $proc.Kill(); $proc.WaitForExit(2000) } catch {}
        }
    }
}

function Get-AllFilteredFiles {
    param([string]$Path,[bool]$DoRecurse,[string[]]$BlackList,[ref]$OutAccessDeniedDirs,[ref]$OutScanErrors,[switch]$ShowProgress)
    $fileList = @(); $subDirs = @(); $dirCount = 0
    try { $files = Get-ChildItem -LiteralPath $Path -File -ErrorAction Stop; $fileList += $files }
    catch {
        if ($_.Exception.HResult -eq -2147024891) { if ($Path -and $Path -notin $OutAccessDeniedDirs.Value) { $OutAccessDeniedDirs.Value += $Path } }
        $OutScanErrors.Value += $_
    }
    if ($DoRecurse) {
        try { $subDirs = Get-ChildItem -LiteralPath $Path -Directory -ErrorAction Stop }
        catch { if ($_.Exception.HResult -eq -2147024891) { if ($Path -and $Path -notin $OutAccessDeniedDirs.Value) { $OutAccessDeniedDirs.Value += $Path } }; $OutScanErrors.Value += $_ }
        foreach ($d in $subDirs) {
            $dirCount++
            if ($ShowProgress -and $dirCount % 5 -eq 0) {
                Write-Host ("`r  ├─ 扫描目录中... {0} | 已收集文件: {1}" -f $dirCount, $fileList.Count) -NoNewline
            }
            $dirName = $d.Name; $hitBlack = $false
            foreach($bItem in $BlackList){ if($dirName.IndexOf($bItem, [System.StringComparison]::OrdinalIgnoreCase) -ge 0){ $hitBlack = $true; break } }
            if($hitBlack){ Write-Host "`n>> 跳过黑名单文件夹：$($d.FullName)" -ForegroundColor DarkGray; continue }
            $childResult = Get-AllFilteredFiles -Path $d.FullName -DoRecurse $true -BlackList $BlackList -OutAccessDeniedDirs $OutAccessDeniedDirs -OutScanErrors $OutScanErrors -ShowProgress:$ShowProgress
            $fileList += $childResult
        }
    }
    return $fileList
}

function Invoke-FfprobeDuration {
    param([string]$FilePath,[string]$OutFile)
    $arg = '/c ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "' + $FilePath + '" > "' + $OutFile + '"'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = $arg
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.WaitForExit()
    $output = ""
    if (Test-Path -LiteralPath $OutFile) { $output = [System.IO.File]::ReadAllText($OutFile).Trim() }
    return @{ ExitCode = $proc.ExitCode; Output = $output }
}

function Invoke-Ffprobe {
    param([string]$Arguments,[string]$OutFile)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "ffprobe.exe"; $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdOut = $proc.StandardOutput.ReadToEnd(); $stdErr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $output = if ($stdOut -and $stdOut.Trim() -match '\d') { $stdOut.Trim() } else { $stdErr.Trim() }
    if ($OutFile -and $output) { [System.IO.File]::WriteAllText($OutFile, $output, [System.Text.Encoding]::UTF8) }
    return @{ ExitCode = $proc.ExitCode; Output = $output }
}

function Get-FfprobeArgs {
    param([string]$FilePath,[string]$ExtraArgs = "")
    $esc = $FilePath -replace '(\\*)"', '$1$1\"'
    $esc = $esc -replace '(\\+)$', '$1$1'
    $quotedPath = '"' + $esc + '"'
    if ($ExtraArgs) { return "$ExtraArgs -- $quotedPath" } else { return "-- $quotedPath" }
}

# >>> FIX v15: 线性总进度条 - 三阶段融合，单行回车刷新
function Show-LinearProgressBar {
    param([int]$Current, [int]$Total, [string]$Status="", [int]$ThrottleMs=300)
    $now = [Environment]::TickCount
    if ($null -eq $script:_lastProgTick) { $script:_lastProgTick = 0 }
    $pct = if($Total -gt 0){ [int]($Current / $Total * 100) }else{0}
    if (($now - $script:_lastProgTick) -lt $ThrottleMs -and $pct -eq $script:_lastPct -and $Current -lt $Total) { return }
    $script:_lastProgTick = $now; $script:_lastPct = $pct
    $barLen = 30; $filled = [int]($barLen * $pct / 100)
    $bar = ("█" * $filled).PadRight($barLen, "░")
    $line = "`r[$bar] $pct% ($Current/$Total) $Status"
    if ($Current -ge $Total) { Write-Host "$line`n" -NoNewline }
    else { Write-Host $line -NoNewline }
}

# ====================== 非交互模式入口 ======================
if ($Mode -ne "") {
    Write-Host ">>> 非交互模式：参数驱动" -ForegroundColor Cyan
    Write-Host ">>> Mode=$Mode Recurse=$($Recurse.IsPresent) Meta=$($Meta.IsPresent) BitrateThreshold=$BitrateThreshold MinBitrate=$MinBitrate MinHeight=$MinHeight MaxHeight=$MaxHeight MinSizeMB=$MinSizeMB ReSortBy=$ReSortBy" -ForegroundColor Gray

    $scanRoot = if ($Path) { $Path } else { $PWD.Path.Trim() }
    $recurseParam = $Recurse.IsPresent
    $videoMode = -not $AllFiles.IsPresent
    $sortMode = $Mode.ToUpper()
    if ($sortMode -notin "S","B","R","D") { Write-Host "错误：Mode 必须是 S/B/R/D 之一" -ForegroundColor Red; exit 1 }
    $exportMeta = $Meta.IsPresent -or ($sortMode -in "B","R","D")
    $topCount = [Math]::Max(1, $Top)
    $bitrateThresholdKbps = if ($MinBitrate -gt 0) { $MinBitrate } elseif ($BitrateThreshold -gt 0) { $BitrateThreshold } else { 0 }
    $useBitrateFilter = ($bitrateThresholdKbps -gt 0)
    $maxConcurrent = 4; $progressStep = 20

    # >>> FIX v19: 计算最小文件大小过滤阈值
    $minSizeBytes = if ($MinSizeMB -gt 0) { $MinSizeMB * 1024 * 1024 } else { 0 }
    if ($minSizeBytes -gt 0) { Write-Host "大小过滤：排除小于 $MinSizeMB MB 的文件" -ForegroundColor Yellow }

    if ($exportMeta -and -not (Test-FfprobeAvailable)) {
        Write-Host "错误：需要 ffprobe 但未找到，请安装后重试" -ForegroundColor Red; exit 1
    }

    Write-Host "扫描路径：$scanRoot"
    Write-Host "递归：$recurseParam | 仅视频：$videoMode | 排序：$sortMode | 元数据：$exportMeta"
    if ($useBitrateFilter) { Write-Host "码率阈值：>= $bitrateThresholdKbps kbps" }
    if ($minSizeBytes -gt 0) { Write-Host "大小过滤：>= $MinSizeMB MB" }
    if ($ReSortBy) { Write-Host "二次排序：按 $ReSortBy 降序（默认降序）" -ForegroundColor Cyan }
    Write-Host "输出条数：$topCount"
    Write-Host ""

    $scanBlackList = @()
    $blacklistFile = Join-Path $scanRoot "blacklist.txt"
    if (Test-Path -LiteralPath $blacklistFile) {
        $scanBlackList = Get-Content -LiteralPath $blacklistFile -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" -and $_ -notmatch '^#' }
        Write-Host ">> 已加载黑名单：$($scanBlackList -join ' | ')"
    }

    $accessDeniedDirs = @(); $scanErrors = @()

    Write-Host "正在扫描文件（阶段1/2）..." -ForegroundColor DarkCyan
    $totalPhase1 = 100; $totalPhase2 = 100
    Show-LinearProgressBar -Current 0 -Total $totalPhase1 -Status "初始化扫描..."
    Start-Sleep -Milliseconds 100

    $rawAll = Get-AllFilteredFiles -Path $scanRoot -DoRecurse $recurseParam -BlackList $scanBlackList -OutAccessDeniedDirs ([ref]$accessDeniedDirs) -OutScanErrors ([ref]$scanErrors) -ShowProgress
    Show-LinearProgressBar -Current $totalPhase1 -Total $totalPhase1 -Status "文件收集完成，共 $($rawAll.Count) 个文件"
    Write-Host ""

    $videoExts = @('.mp4','.mov','.mkv','.avi','.flv','.wmv','.m4v','.ts','.mpg','.mpeg','.f4v','.m2ts','.mts','.webm','.rmvb')
    if ($videoMode) { $rawFiles = $rawAll | Where-Object { $_.Extension -in $videoExts } } else { $rawFiles = $rawAll }
    if ($rawFiles.Count -eq 0) { Write-Host "无匹配文件"; exit 0 }

    $totalVideoCount = $rawFiles.Count
    Write-Host "扫描到 $totalVideoCount 个视频文件，开始处理..." -ForegroundColor Green

    # >>> FIX v21: 初始化漏斗计数变量
    $heightFilteredCount = 0
    $sizeTopFilteredCount = 0
    $bitrateFilteredCount = 0
    $sizeFilteredCount = 0
    $workListCountBeforeHeight = 0
    $workListCountBeforeSizeTop = 0
    $workListCountBeforeBitrate = 0
    $workListCountBeforeSizeFilter = 0

    $workList = @(); $metaFail = 0; $durMap = @{}
    $metaHasDuration = $exportMeta
    
    if ($videoMode -and $exportMeta) {
        Write-Host "【读取视频元数据（阶段2/2）】" -ForegroundColor Cyan
        $tempDir = Join-Path $env:TEMP "video_meta_$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        $taskList = @()
        foreach ($f in $rawFiles) {
            while ((Get-Process ffprobe -ErrorAction SilentlyContinue | Measure-Object).Count -ge $maxConcurrent) { Start-Sleep -Milliseconds 40 }
            $outPath = Join-Path $tempDir "$($f.BaseName)_$($f.LastWriteTime.Ticks).txt"
            $extraArgs = '-v error -select_streams v:0 -show_entries stream=bit_rate,avg_bit_rate,width,height:format=duration -of json'
            $args2 = Get-FfprobeArgs -FilePath $f.FullName -ExtraArgs $extraArgs
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "ffprobe.exe"; $psi.Arguments = $args2
            $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
            $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $proc = [System.Diagnostics.Process]::Start($psi)
            $taskList += [PSCustomObject]@{ File=$f; Proc=$proc; OutFile=$outPath }
        }
        $processedCount = 0; $lastPct = -1
        while ($taskList.Count -gt 0) {
            $running = @()
            foreach ($t in $taskList) {
                if (-not $t.Proc.HasExited) { $running += $t; continue }
                $processedCount++
                $phase2Pct = [int]($processedCount / $totalVideoCount * 100)
                $pctVal = $phase2Pct
                if ($pctVal -ne $lastPct -or $processedCount -eq $totalVideoCount) {
                    Show-LinearProgressBar -Current $phase2Pct -Total 100 -Status "元数据读取: $processedCount/$totalVideoCount | $($t.File.Name)"
                    $lastPct = $pctVal
                }
                $vi = [PSCustomObject]@{BitrateKbps=$null;BitrateSource=$null;Width=$null;Height=$null;LongEdge=$null;DurationSec=$null;DurationDisp="-"}
                if ($t.Proc.ExitCode -eq 0) {
                    try {
                        $rawTxt = $t.Proc.StandardOutput.ReadToEnd()
                        if (-not $rawTxt) { $rawTxt = [System.IO.File]::ReadAllText($t.OutFile) }
                        $jsonObj = $rawTxt | ConvertFrom-Json
                        $vStream = $jsonObj.streams[0]
                        $w=[int]$vStream.width; $h=[int]$vStream.height
                        $bitrateBps = $null; $bitrateSource = "bitrate"
                        if (-not [string]::IsNullOrWhiteSpace($vStream.bit_rate)) { $bitrateBps = [long]$vStream.bit_rate }
                        elseif (-not [string]::IsNullOrWhiteSpace($vStream.avg_bit_rate)) { $bitrateBps = [long]$vStream.avg_bit_rate; $bitrateSource = "avgbitrate" }
                        $durSec = 0.0; $durDisp = "-"
                        if ($jsonObj.format -and $jsonObj.format.duration) {
                            $tmp = 0.0
                            if ([double]::TryParse($jsonObj.format.duration, [ref]$tmp)) {
                                $durSec = $tmp; $durDisp = (Get-FriendlyDuration $durSec)
                            }
                        }
                        $vi = [PSCustomObject]@{
                            BitrateKbps=if($bitrateBps){[Math]::Round($bitrateBps/1000)}else{$null}
                            BitrateSource=$bitrateSource; Width=$w; Height=$h; LongEdge=[Math]::Max($w,$h)
                            DurationSec=$durSec; DurationDisp=$durDisp
                        }
                    } catch { $metaFail++ }
                } else { $metaFail++ }
                $brDisp = if($vi.BitrateKbps){"$($vi.BitrateKbps) kbps"}else{"[码率缺失]"}
                $resDisp = if($vi.Width){"$($vi.Width)x$($vi.Height)"}else{"-"}
                $workList += [PSCustomObject]@{
                    FullPath=$t.File.FullName.Trim(); FileSizeBytes=$t.File.Length
                    FileSizeFriendly=(Get-FriendlySize -Bytes $t.File.Length)
                    BitrateKbps=$vi.BitrateKbps; BitrateDisp=$brDisp; BitrateSource=$vi.BitrateSource
                    Width=$vi.Width; Height=$vi.Height; ResDisp=$resDisp; LongEdge=$vi.LongEdge
                    DurationSec=$vi.DurationSec; DurationDisp=$vi.DurationDisp
                }
            }
            $taskList = $running; Start-Sleep -Milliseconds 20
        }
        Show-LinearProgressBar -Current 100 -Total 100 -Status "元数据读取完成！"
        Write-Host ""
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        foreach ($f in $rawFiles) {
            $workList += [PSCustomObject]@{
                FullPath=$f.FullName.Trim(); FileSizeBytes=$f.Length; FileSizeFriendly=(Get-FriendlySize -Bytes $f.Length)
                BitrateKbps=$null; BitrateDisp="-"; Width=$null; Height=$null; ResDisp="-"; LongEdge=$null; DurationSec=$null; DurationDisp="-"
            }
        }
    }

    # >>> FIX v21: 体积初筛计数
    $workListCountBeforeSizeTop = $workList.Count
    if ($SizeTop) {
        $sizeTopCount = [Math]::Max(1, $SizeTopCount)
        $workList = @($workList | Sort-Object FileSizeBytes -Descending | Select-Object -First $sizeTopCount)
        $sizeTopFilteredCount = $workListCountBeforeSizeTop - $workList.Count
    }

    # >>> FIX v21: 高度过滤计数
    $workListCountBeforeHeight = $workList.Count
    if ($MinHeight -gt 0 -or $MaxHeight -gt 0) {
        if ($MinHeight -gt 0) { $workList = @($workList | Where-Object { $_.Height -ge $MinHeight }) }
        if ($MaxHeight -gt 0) { $workList = @($workList | Where-Object { $_.Height -le $MaxHeight }) }
        $heightFilteredCount = $workListCountBeforeHeight - $workList.Count
    }

    # ---- 主排序 ----
    if ($sortMode -eq "B") {
        $sortedAll = @($workList | Sort-Object @{E={if($_.BitrateKbps -eq $null){-1}else{$_.BitrateKbps}};D=$true}, @{E={$_.FileSizeBytes};D=$true})
        # >>> FIX v21: 码率过滤计数
        $workListCountBeforeBitrate = $sortedAll.Count
        if ($useBitrateFilter) { $sorted = @($sortedAll | Where-Object { $_.BitrateKbps -ge $bitrateThresholdKbps }) }
        else { $sorted = @($sortedAll | Select-Object -First $topCount) }
        $bitrateFilteredCount = $workListCountBeforeBitrate - $sorted.Count
    } elseif ($sortMode -eq "R") {
        $sorted = @($workList | Sort-Object @{E={if($_.LongEdge -eq $null){-1}else{$_.LongEdge}};D=$true}, @{E={$_.FileSizeBytes};D=$true} | Select-Object -First $topCount)
    } elseif ($sortMode -eq "D") {
        Write-Host "【D模式：扫描时长】"
        $durTempDir = Join-Path $env:TEMP "dur_$(Get-Random)"; New-Item -ItemType Directory -Path $durTempDir | Out-Null
        $durProcessed = 0
        foreach ($f in $rawFiles) {
            while ((Get-Process ffprobe -ErrorAction SilentlyContinue | Measure-Object).Count -ge $maxConcurrent) { Start-Sleep -Milliseconds 40 }
            $outFile = Join-Path $durTempDir "$($f.BaseName)_$($f.LastWriteTime.Ticks).txt"
            $result = Invoke-FfprobeDuration -FilePath $f.FullName -OutFile $outFile
            $txt = $result.Output
            $sec = $null; $tmp = 0.0
            if ([double]::TryParse($txt, [ref]$tmp)) { $sec = $tmp }
            $durMap[$f.FullName] = $sec
            $durProcessed++
            if ($durProcessed % $progressStep -eq 0) { Write-Host "时长扫描：$durProcessed / $totalVideoCount" }
        }
        Remove-Item $durTempDir -Recurse -Force -ErrorAction SilentlyContinue
        for($wi=0;$wi -lt $workList.Count;$wi++){ $item=$workList[$wi]; $s=$durMap[$item.FullPath]; $item.DurationSec=$s; $item.DurationDisp=(Get-FriendlyDuration $s) }
        $sorted = @($workList | Sort-Object @{E={if($_.DurationSec -ne $null){$_.DurationSec}else{-1}};D=$true}, @{E={$_.FileSizeBytes};D=$true} | Select-Object -First $topCount)
    } else {
        $sortedAll = @($workList | Sort-Object FileSizeBytes -Descending)
        # >>> FIX v21: 码率过滤计数（S模式）
        $workListCountBeforeBitrate = $sortedAll.Count
        if ($useBitrateFilter) { $sortedAll = @($sortedAll | Where-Object { $_.BitrateKbps -ne $null -and $_.BitrateKbps -ge $bitrateThresholdKbps }) }
        $sorted = @($sortedAll | Select-Object -First $topCount)
        $bitrateFilteredCount = $workListCountBeforeBitrate - ($sortedAll.Count + ($sorted.Count))
        # 修正：S模式下精确计算
        if ($sortMode -eq "S") {
            $bitrateFilteredCount = $workListCountBeforeBitrate - $sorted.Count - ($workListCountBeforeBitrate - $sortedAll.Count)
        }
    }
    $sorted = @($sorted)

    # >>> FIX v20: 二次排序（主排序完成后、大小过滤前）
    if ($ReSortBy -and $ReSortBy.ToUpper() -in @("D","S","B","R")) {
        $rsMode = $ReSortBy.ToUpper()
        Write-Host ">> 二次排序：按 $rsMode 降序重新排列结果集（共 $($sorted.Count) 条）" -ForegroundColor Cyan
        switch ($rsMode) {
            "D" { $sorted = @($sorted | Sort-Object @{E={if($_.DurationSec -ne $null){$_.DurationSec}else{[double]::MaxValue}};D=$true}) }
            "S" { $sorted = @($sorted | Sort-Object @{E={$_.FileSizeBytes};D=$true}) }
            "B" { $sorted = @($sorted | Sort-Object @{E={if($_.BitrateKbps -eq $null){-1}else{$_.BitrateKbps}};D=$true}) }
            "R" { $sorted = @($sorted | Sort-Object @{E={if($_.LongEdge -eq $null){-1}else{$_.LongEdge}};D=$true}) }
        }
    }

    # >>> FIX v19: 最终大小过滤（带计数）
    $workListCountBeforeSizeFilter = $sorted.Count
    if ($minSizeBytes -gt 0) {
        $beforeFilter = $sorted.Count
        $sorted = @($sorted | Where-Object { $_.FileSizeBytes -ge $minSizeBytes })
        $sizeFilteredCount = $beforeFilter - $sorted.Count
        if ($sizeFilteredCount -gt 0) {
            Write-Host ">> 按大小过滤：排除 $sizeFilteredCount 个小于 $MinSizeMB MB 的文件，剩余 $($sorted.Count) 个" -ForegroundColor Yellow
        }
    }

    # ---- 输出到控制台 ----
    $outputRows = @()
    foreach($item in $sorted){
        $outputRows += [PSCustomObject]@{
            Rank = ($outputRows.Count + 1)
            Duration = $item.DurationDisp; Size = $item.FileSizeFriendly
            Bitrate = $item.BitrateDisp; Resolution = $item.ResDisp; Path = $item.FullPath
        }
    }
    $outputRows = @($outputRows)

    if ($JsonOutput -or $Output -ne "") {
        $jsonText = $outputRows | ConvertTo-Json -Depth 3
        if ($Output -ne "") { $jsonText | Out-File -LiteralPath $Output -Encoding UTF8; Write-Host "已保存：$Output" }
        else { Write-Host $jsonText }
    } else {
        Write-Host "`n==================== 结果 ===================="
        $showDuration = $videoMode -and $exportMeta
        foreach($r in $outputRows) {
            if ($showDuration) {
                $dispDur = $r.Duration
                if ($dispDur -eq $null) { $dispDur = "-" }
                Write-Host ("[{0,3}] {1,-12} | {2,-10} | {3,-16} | {4,-12} | {5}" -f $r.Rank,$dispDur,$r.Size,$r.Bitrate,$r.Resolution,$r.Path)
            } else {
                Write-Host ("[{0,3}] {1,-10} {2}" -f $r.Rank,$r.Size,$r.Path)
            }
        }
        Write-Host "==============================================="
        Write-Host "共 $($outputRows.Count) 条结果"
    }

    # ========= 非交互模式：自动保存 txt =========
    if ($UserQuery -and $UserQuery.Trim() -ne "") {
        $fnRaw = $UserQuery.Trim() -replace '[<>:"/\\|?*]','_' -replace '_+','_' -replace '^\s+|\s+$',''
    } else {
        $fnRaw = "视频筛选结果"
    }
    if ($fnRaw.Length -gt 80) { $fnRaw = $fnRaw.Substring(0, 80) }
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $outName = "本文件夹内文件筛选&排序统计_非交互模式_${fnRaw}_${ts}.txt"
    $lines = @()
    $lines += "非交互模式筛选结果"
    $lines += "查询：$($UserQuery.Trim())"
    $lines += "参数：Mode=$sortMode Recurse=$recurseParam Meta=$exportMeta BitrateThreshold=$bitrateThresholdKbps MinHeight=$MinHeight MaxHeight=$MaxHeight MinSizeMB=$MinSizeMB ReSortBy=$ReSortBy"
    $displayRoot = $scanRoot -replace '^Microsoft\.PowerShell\.Core\\FileSystem::',''
    $lines += "扫描根目录: $displayRoot"
    $lines += "时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += "# ===== 筛选漏斗统计（按执行顺序）====="
    $lines += "#总扫描视频数量: $totalVideoCount"
    if ($heightFilteredCount -gt 0) { $lines += "#高度过滤: 排除 $heightFilteredCount 个（范围 ${MinHeight}-${MaxHeight}P），剩余 $($totalVideoCount - $heightFilteredCount)" }
    if ($sizeTopFilteredCount -gt 0) { $lines += "#体积初筛: 排除 $sizeTopFilteredCount 个（取前 $SizeTopCount 按大小），剩余 $($workListCountBeforeHeight - $heightFilteredCount)" }
    if ($bitrateFilteredCount -gt 0) { $lines += "#码率过滤: 排除 $bitrateFilteredCount 个（>= ${bitrateThresholdKbps}kbps），剩余 $($workListCountBeforeHeight - $heightFilteredCount - $bitrateFilteredCount)" }
    if ($ReSortBy) { $lines += "#二次排序: 按 $ReSortBy 降序重排（不拦截）" }
    if ($sizeFilteredCount -gt 0) { $lines += "#大小过滤: 排除 $sizeFilteredCount 个（>= ${MinSizeMB}MB），剩余 $($sorted.Length)" }
    $lines += "#最终输出数量: $($sorted.Length)"
    $lines += "# ===== 筛选漏斗统计结束 ====="
    $hasDurationCol = ($videoMode -and $exportMeta)
    if ($hasDurationCol) {
        $lines += ("{0,-4}|{1,-12}|{2,-10}|{3,-16}|{4,-12}|{5}" -f "序号","时长","大小","码率","分辨率","完整路径")
        $lines += "--------------------------------------------------"
        for($i=0; $i -lt $sorted.Length; $i++){
            $item = $sorted[$i]
            $lines += ("[{0,-3}]|{1,-12}|{2,-10}|{3,-16}|{4,-12}|{5}" -f ($i+1),$item.DurationDisp,$item.FileSizeFriendly,$item.BitrateDisp,$item.ResDisp,$item.FullPath)
        }
    } else {
        $lines += ("{0,-4}|{1,-10}|{2}" -f "序号","大小","完整路径")
        $lines += "--------------------------------------------------"
        for($i=0; $i -lt $sorted.Length; $i++){
            $item = $sorted[$i]
            $lines += ("[{0,-3}]|{1,-10}|{2}" -f ($i+1),$item.FileSizeFriendly,$item.FullPath)
        }
    }
    $txtContent = $lines -join "`r`n"
    try {
        $txtContent | Out-File -LiteralPath $outName -Encoding UTF8
        Write-Host "`n✅ 已自动保存：$PWD\$outName" -ForegroundColor Green
    } catch {
        Write-Host "`n❌ 保存失败：$($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "`n非交互模式执行完毕。"
    exit 0
}

# ====================== 交互模式 ======================

$runningFfprobe = Get-Process -Name "ffprobe" -ErrorAction SilentlyContinue
if ($runningFfprobe -and $runningFfprobe.Count -gt 0) {
    Write-Host "`n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Yellow
    Write-Host "⚠️ 检测到本机存在 $($runningFfprobe.Count) 个正在运行 ffprobe.exe 进程" -ForegroundColor Yellow
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!`n" -ForegroundColor Yellow
    while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
    $cleanOpt = Wait-KeyPress -Prompt "【Y】全部终止本机所有ffprobe(高风险)；【N】保留进程继续运行(默认)"
    if ($cleanOpt -ieq "Y") {
        $runningFfprobe | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Host ">>> 已执行终止操作`n"
    }
}

trap {
    if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) {
        Write-Host "`n⚠️ 捕获到Ctrl+C中断，正在清理本次脚本拉起的子进程..." -ForegroundColor Yellow
        Cleanup-TaskProcesses -TaskList $taskList
    }
    break
}

$maxConcurrent = 4; $progressStep = 20

Write-Host "=============================================="
Write-Host "查找视频/文件列表（S大小｜B码率｜R分辨率｜D视频时长）"
Write-Host "=============================================="
$recurseOpt = Wait-KeyPress -Prompt "`n是否扫描子文件夹？【Y】递归(默认) 【N】仅当前目录"
$recurseParam = ($recurseOpt -ne "N")

$videoModeOpt = Wait-KeyPress -Prompt "`n是否仅扫描视频文件？【Y】仅视频(默认) 【N】全部文件"
$videoMode = ($videoModeOpt -ne "N")

$videoExts = @('.mp4','.mov','.mkv','.avi','.flv','.wmv','.m4v','.ts','.mpg','.mpeg','.f4v','.m2ts','.mts','.webm','.rmvb')
$sortMode = "S"; $exportMeta = $false; $isDowngrade = $false

if ($videoMode) {
    $sortOpt = Wait-KeyPress -Prompt "`n排序维度选择：【S】文件大小(默认) 【B】视频流码率 【R】视频长边分辨率 【D】视频时长"
    if ($sortOpt -in "S","B","R","D") { $sortMode = $sortOpt }
    if ($sortMode -eq "S") {
        $metaOpt = Wait-KeyPress -Prompt "`n是否读取视频元数据（含时长、码率、分辨率等信息，会多耗费一些时间）？【N】不读取(默认) 【Y】读取"
        if ($metaOpt -eq "Y") { $exportMeta = $true }
    }
    elseif ($sortMode -in "B","R","D") {
        $exportMeta = $true
        if (-not (Test-FfprobeAvailable)) {
            Write-Host "`n【错误】未找到ffprobe.exe" -ForegroundColor Red
            $dgKey = Wait-KeyPress -Prompt "【Y】降级按文件大小排序，其他键退出"
            if ($dgKey -eq "Y") { $sortMode = "S"; $exportMeta = $false; $isDowngrade = $true }
            else { exit }
        }
    }
}

$useBitrateFilter = $false; $bitrateThresholdKbps = 10000; $topCount = 100
if ($videoMode -and $sortMode -eq "B") {
    $brModeOpt = Wait-KeyPress -Prompt "码率筛选模式选择：【N】指定条目数量(默认) 【T】按码率阈值筛选"
    if ($brModeOpt -eq "T") {
        $useBitrateFilter = $true
        $inputThr = Read-Host "输入最低码率阈值(kbps)，直接回车默认10000"
        if ([string]::IsNullOrWhiteSpace($inputThr) -or (-not [int]::TryParse($inputThr, [ref]$null))) { $bitrateThresholdKbps = 10000 }
        else { $bitrateThresholdKbps = [int]$inputThr }
    } else {
        $inputCount = Read-Host "指定最大的输出统计条目数，直接回车默认100"
        if ([string]::IsNullOrWhiteSpace($inputCount) -or (-not [int]::TryParse($inputCount, [ref]$null))) { $topCount = 100 }
        else { $topCount = [Math]::Max(1, [int]$inputCount) }
    }
} elseif ($videoMode -and $sortMode -eq "S" -and $exportMeta) {
    $brModeOpt = Wait-KeyPress -Prompt "是否按码率阈值筛选？【N】不过滤(默认) 【T】按码率阈值筛选"
    if ($brModeOpt -eq "T") {
        $useBitrateFilter = $true
        $inputThr = Read-Host "输入最低码率阈值(kbps)，直接回车默认10000"
        if ([string]::IsNullOrWhiteSpace($inputThr) -or (-not [int]::TryParse($inputThr, [ref]$null))) { $bitrateThresholdKbps = 10000 }
        else { $bitrateThresholdKbps = [int]$inputThr }
    }
    $inputCount = Read-Host "指定最大的输出统计条目数，直接回车默认100"
    if ([string]::IsNullOrWhiteSpace($inputCount) -or (-not [int]::TryParse($inputCount, [ref]$null))) { $topCount = 100 }
    else { $topCount = [Math]::Max(1, [int]$inputCount) }
} else {
    $inputCount = Read-Host "指定最大的输出统计条目数，直接回车默认100"
    if ([string]::IsNullOrWhiteSpace($inputCount) -or (-not [int]::TryParse($inputCount, [ref]$null))) { $topCount = 100 }
    else { $topCount = [Math]::Max(1, [int]$inputCount) }
}

# >>> FIX v20: 交互模式 - 询问是否二次排序
$reSortBy = ""
if ($videoMode -and $exportMeta) {
    $reSortOpt = Wait-KeyPress -Prompt "`n是否对结果集进行二次排序？【N】不二次排序(默认) 【D】按时长 【S】按文件大小 【B】按码率 【R】按分辨率"
    if ($reSortOpt -in @("D","S","B","R")) { $reSortBy = $reSortOpt }
}

if ($videoMode) {
    $filterDesc = "仅视频文件"
    if($sortMode -eq "D"){ $sortText = "视频时长降序，相同时长按文件大小降序" }
    elseif($sortMode -eq "B"){ $sortText = "视频流码率降序" }
    elseif($sortMode -eq "R"){ $sortText = "视频长边分辨率降序" }
    else{ $sortText = if($exportMeta){"文件大小降序，附带视频元数据"}else{"文件大小降序"} }
} else { $filterDesc = "全部文件"; $sortText = "文件大小降序" }

$recurDesc = if($recurseParam){"递归子目录"}else{"仅当前目录"}
$typeDesc = if($videoMode){"仅视频"}else{"全部文件"}
$sortDesc = switch($sortMode){"S"{"文件大小"}"B"{"视频流码率"}"R"{"视频长边分辨率"}"D"{"视频时长"}}
$filterDesc2 = if($useBitrateFilter){"按码率阈值($bitrateThresholdKbps kbps)筛选"}else{"不过滤码率"}
$metaDesc = if($exportMeta){"读取元数据(码率/分辨率/时长)"}else{"不读取元数据"}
$reSortDesc = if($reSortBy){"二次排序:按$reSortBy降序"}else{"不二次排序"}
$fullDesc = "交互模式 | $recurDesc | $typeDesc | 排序:$sortDesc | $filterDesc2 | $metaDesc | $reSortDesc | 最大条数:$topCount"
$interactiveDetail = "递归:$recurDesc | 类型:$typeDesc | 排序维度:$sortDesc | 码率筛选:$filterDesc2 | 元数据:$metaDesc | 二次排序:$reSortDesc | 最大输出:$topCount"

$metaHasDuration = $exportMeta

Write-Host "`n========================================"
Write-Host "开始扫描"
Write-Host "过滤：$filterDesc | 排序：$sortText"
if ($reSortBy) { Write-Host "（结果集将按 $reSortBy 二次降序排列）" -ForegroundColor Cyan }
if ($metaHasDuration) { Write-Host "（已读取元数据，时长/码率/分辨率将自动附带）" -ForegroundColor DarkGray }
Write-Host "=======================================`n"

$scanRoot = $PWD.Path.Trim()
$blacklistFile = Join-Path $scanRoot "blacklist.txt"
if (Test-Path -LiteralPath $blacklistFile) {
    $scanBlackList = Get-Content -LiteralPath $blacklistFile -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" -and $_ -notmatch '^#' }
}

$accessDeniedDirs = @(); $scanErrors = @()

Write-Host "正在扫描文件（阶段1/2）..." -ForegroundColor DarkCyan
Show-LinearProgressBar -Current 0 -Total 100 -Status "初始化扫描..."

$rawAll = Get-AllFilteredFiles -Path $scanRoot -DoRecurse $recurseParam -BlackList $scanBlackList -OutAccessDeniedDirs ([ref]$accessDeniedDirs) -OutScanErrors ([ref]$scanErrors) -ShowProgress
Show-LinearProgressBar -Current 100 -Total 100 -Status "文件收集完成，共 $($rawAll.Count) 个文件"
Write-Host ""

if ($videoMode) { $rawFiles = $rawAll | Where-Object { $_.Extension -in $videoExts } } else { $rawFiles = $rawAll }
if ($rawFiles.Count -eq 0) { Write-Host "无匹配文件，按任意键退出"; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown"); exit 0 }

$totalVideoCount = $rawFiles.Count
Write-Host "扫描到 $totalVideoCount 个视频文件，开始处理..." -ForegroundColor Green

# >>> FIX v21: 初始化漏斗计数变量（交互模式）
$interactiveHeightFiltered = 0
$interactiveSizeTopFiltered = 0
$interactiveBitrateFiltered = 0
$interactiveSizeFiltered = 0
$interactiveWorkListCountBeforeHeight = 0
$interactiveWorkListCountBeforeSizeTop = 0
$interactiveWorkListCountBeforeBitrate = 0

$workList = @(); $metaFail = 0; $durMap = @{}; $taskList = @()

if ($videoMode -and $exportMeta) {
    Write-Host "【批量读取视频流元数据（阶段2/2）】`n" -ForegroundColor Cyan
    $tempDir = Join-Path $env:TEMP "video_meta_$(Get-Random)"
    try {
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        foreach ($f in $rawFiles) {
            while ((Get-Process ffprobe -ErrorAction SilentlyContinue | Measure-Object).Count -ge $maxConcurrent) { Start-Sleep -Milliseconds 40 }
            $outPath = Join-Path $tempDir "$($f.BaseName)_$($f.LastWriteTime.Ticks).txt"
            $extraArgs = '-v error -select_streams v:0 -show_entries stream=bit_rate,avg_bit_rate,width,height:format=duration -of json'
            $args2 = Get-FfprobeArgs -FilePath $f.FullName -ExtraArgs $extraArgs
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "ffprobe.exe"; $psi.Arguments = $args2
            $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
            $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $proc = [System.Diagnostics.Process]::Start($psi)
            $taskList += [PSCustomObject]@{ File=$f; Proc=$proc; OutFile=$outPath }
        }
        $processedCount = 0; $lastPct = -1
        while ($taskList.Count -gt 0) {
            $running = @()
            foreach ($t in $taskList) {
                if (-not $t.Proc.HasExited) { $running += $t; continue }
                $processedCount++
                $phase2Pct = [int]($processedCount / $totalVideoCount * 100)
                $pctVal = $phase2Pct
                if ($pctVal -ne $lastPct -or $processedCount -eq $totalVideoCount) {
                    Show-LinearProgressBar -Current $phase2Pct -Total 100 -Status "元数据读取: $processedCount/$totalVideoCount | $($t.File.Name)"
                    $lastPct = $pctVal
                }
                $vi = [PSCustomObject]@{BitrateKbps=$null;BitrateSource=$null;Width=$null;Height=$null;LongEdge=$null;DurationSec=$null;DurationDisp="-"}
                if ($t.Proc.ExitCode -eq 0) {
                    try {
                        $rawTxt = $t.Proc.StandardOutput.ReadToEnd()
                        if (-not $rawTxt) { $rawTxt = [System.IO.File]::ReadAllText($t.OutFile) }
                        $jsonObj = $rawTxt | ConvertFrom-Json
                        $vStream = $jsonObj.streams[0]
                        $w=[int]$vStream.width; $h=[int]$vStream.height
                        $bitrateBps = $null
                        if (-not [string]::IsNullOrWhiteSpace($vStream.bit_rate)) { $bitrateBps = [long]$vStream.bit_rate }
                        elseif (-not [string]::IsNullOrWhiteSpace($vStream.avg_bit_rate)) { $bitrateBps = [long]$vStream.avg_bit_rate }
                        $durSec = 0.0; $durDisp = "-"
                        if ($jsonObj.format -and $jsonObj.format.duration) {
                            $tmp = 0.0
                            if ([double]::TryParse($jsonObj.format.duration, [ref]$tmp)) {
                                $durSec = $tmp; $durDisp = (Get-FriendlyDuration $durSec)
                            }
                        }
                        $vi = [PSCustomObject]@{
                            BitrateKbps=if($bitrateBps){[Math]::Round($bitrateBps/1000)}else{$null}
                            BitrateSource="bitrate"; Width=$w; Height=$h; LongEdge=[Math]::Max($w,$h)
                            DurationSec=$durSec; DurationDisp=$durDisp
                        }
                    } catch { $metaFail++ }
                } else { $metaFail++ }
                $brDisp = if($vi.BitrateKbps){"$($vi.BitrateKbps) kbps"}else{"[码率缺失]"}
                $resDisp = if($vi.Width){"$($vi.Width)x$($vi.Height)"}else{"-"}
                $workList += [PSCustomObject]@{
                    FullPath=$t.File.FullName.Trim(); FileSizeBytes=$t.File.Length; FileSizeFriendly=(Get-FriendlySize -Bytes $t.File.Length)
                    BitrateKbps=$vi.BitrateKbps; BitrateDisp=$brDisp; BitrateSource=$vi.BitrateSource
                    Width=$vi.Width; Height=$vi.Height; ResDisp=$resDisp; LongEdge=$vi.LongEdge
                    DurationSec=$vi.DurationSec; DurationDisp=$vi.DurationDisp
                }
            }
            $taskList = $running; Start-Sleep -Milliseconds 20
        }
        Show-LinearProgressBar -Current 100 -Total 100 -Status "元数据读取完成！"
        Write-Host ""
    }
    finally { Cleanup-TaskProcesses -TaskList $taskList; [GC]::Collect(); [GC]::WaitForPendingFinalizers(); if(Test-Path $tempDir){Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue} }

    if($sortMode -eq "D"){
        Write-Host "`n【D模式：全局预读取全部视频时长】`n"
        $durTempDir = Join-Path $env:TEMP "dur_batch_$(Get-Random)"; New-Item -ItemType Directory -Path $durTempDir | Out-Null
        $durProcessed = 0
        foreach ($f in $rawFiles) {
            while ((Get-Process ffprobe -ErrorAction SilentlyContinue | Measure-Object).Count -ge $maxConcurrent) { Start-Sleep -Milliseconds 80 }
            $outFile = Join-Path $durTempDir "$($f.BaseName)_$($f.LastWriteTime.Ticks).txt"
            $result = Invoke-FfprobeDuration -FilePath $f.FullName -OutFile $outFile
            $txt = $result.Output
            $sec = $null; $tmp = 0.0
            if ([double]::TryParse($txt, [ref]$tmp)) { $sec = $tmp }
            $durMap[$f.FullName] = $sec
            $durProcessed++
            if ($durProcessed % $progressStep -eq 0) { Write-Host "时长预读：$durProcessed / $totalVideoCount" }
        }
        Remove-Item $durTempDir -Recurse -Force -ErrorAction SilentlyContinue
        for($wi=0;$wi -lt $workList.Count;$wi++){ $item=$workList[$wi]; $s=$durMap[$item.FullPath]; $item.DurationSec=$s; $item.DurationDisp=(Get-FriendlyDuration $s) }
    }
} else {
    foreach ($f in $rawFiles) {
        $workList += [PSCustomObject]@{ FullPath=$f.FullName.Trim(); FileSizeBytes=$f.Length; FileSizeFriendly=(Get-FriendlySize -Bytes $f.Length); BitrateKbps=$null; BitrateDisp="-"; Width=$null; Height=$null; ResDisp="-"; LongEdge=$null; DurationSec=$null; DurationDisp="-" }
    }
}

# >>> FIX v21: 体积初筛计数（交互模式）
$interactiveWorkListCountBeforeSizeTop = $workList.Count
if ($SizeTop) {
    $sizeTopCount = [Math]::Max(1, $SizeTopCount)
    $workList = @($workList | Sort-Object FileSizeBytes -Descending | Select-Object -First $sizeTopCount)
    $interactiveSizeTopFiltered = $interactiveWorkListCountBeforeSizeTop - $workList.Count
}

# >>> FIX v21: 高度过滤计数（交互模式）
$interactiveWorkListCountBeforeHeight = $workList.Count
if ($MinHeight -gt 0 -or $MaxHeight -gt 0) {
    if ($MinHeight -gt 0) { $workList = @($workList | Where-Object { $_.Height -ge $MinHeight }) }
    if ($MaxHeight -gt 0) { $workList = @($workList | Where-Object { $_.Height -le $MaxHeight }) }
    $interactiveHeightFiltered = $interactiveWorkListCountBeforeHeight - $workList.Count
}

# ---- 排序 ----
if ($videoMode -and $sortMode -eq "B") {
    $sortedAll = @($workList | Sort-Object @{E={if($_.BitrateKbps -eq $null){-1}else{$_.BitrateKbps}};D=$true}, @{E={$_.FileSizeBytes};D=$true})
    # >>> FIX v21: 码率过滤计数（交互模式）
    $interactiveWorkListCountBeforeBitrate = $sortedAll.Count
    if($useBitrateFilter){ $sorted = @($sortedAll | Where-Object { $_.BitrateKbps -ge $bitrateThresholdKbps }) }
    else { $sorted = @($sortedAll | Select-Object -First $topCount) }
    $interactiveBitrateFiltered = $interactiveWorkListCountBeforeBitrate - $sorted.Count
}
elseif ($videoMode -and $sortMode -eq "R") {
    $sorted = @($workList | Sort-Object @{E={if($_.LongEdge -eq $null){-1}else{$_.LongEdge}};D=$true}, @{E={$_.FileSizeBytes};D=$true} | Select-Object -First $topCount)
}
elseif ($videoMode -and $sortMode -eq "D") {
    $sorted = @($workList | Sort-Object @{E={if($_.DurationSec -ne $null){$_.DurationSec}else{-1}};D=$true}, @{E={$_.FileSizeBytes};D=$true} | Select-Object -First $topCount)
}
else {
    $sortedAll = @($workList | Sort-Object FileSizeBytes -Descending)
    # >>> FIX v21: 码率过滤计数（交互模式 S模式）
    $interactiveWorkListCountBeforeBitrate = $sortedAll.Count
    if ($useBitrateFilter) { $sortedAll = @($sortedAll | Where-Object { $_.BitrateKbps -ge $bitrateThresholdKbps }) }
    $sorted = @($sortedAll | Select-Object -First $topCount)
    $interactiveBitrateFiltered = $interactiveWorkListCountBeforeBitrate - $sorted.Count
}
$sorted = @($sorted)

# >>> FIX v20: 交互模式二次排序
if ($reSortBy -and $reSortBy.ToUpper() -in @("D","S","B","R")) {
    $rsMode = $reSortBy.ToUpper()
    Write-Host "`n>> 二次排序：按 $rsMode 降序重新排列结果集（共 $($sorted.Count) 条）" -ForegroundColor Cyan
    switch ($rsMode) {
        "D" { $sorted = @($sorted | Sort-Object @{E={if($_.DurationSec -ne $null){$_.DurationSec}else{[double]::MaxValue}};D=$true}) }
        "S" { $sorted = @($sorted | Sort-Object @{E={$_.FileSizeBytes};D=$true}) }
        "B" { $sorted = @($sorted | Sort-Object @{E={if($_.BitrateKbps -eq $null){-1}else{$_.BitrateKbps}};D=$true}) }
        "R" { $sorted = @($sorted | Sort-Object @{E={if($_.LongEdge -eq $null){-1}else{$_.LongEdge}};D=$true}) }
    }
}

# >>> FIX v19: 最终大小过滤（交互模式，带计数）
$interactiveSizeFiltered = 0
if ($MinSizeMB -gt 0) {
    $minSizeBytesInteractive = $MinSizeMB * 1024 * 1024
    $beforeFilter = $sorted.Count
    $sorted = @($sorted | Where-Object { $_.FileSizeBytes -ge $minSizeBytesInteractive })
    $interactiveSizeFiltered = $beforeFilter - $sorted.Count
    if ($interactiveSizeFiltered -gt 0) {
        Write-Host "`n>> 按大小过滤：排除 $interactiveSizeFiltered 个小于 $MinSizeMB MB 的文件，剩余 $($sorted.Count) 个" -ForegroundColor Yellow
    }
}

# ---- 预览 ----
Write-Host "`n==================== 预览 ===================="
$outputRows = @()
$showDuration = $videoMode -and $exportMeta
for($i=0; $i -lt $sorted.Length; $i++){
    $item = $sorted[$i]; $rank = $i+1
    $outputRows += [PSCustomObject]@{ RankOrig=$rank; DurationDisp=$item.DurationDisp; FileSizeFriendly=$item.FileSizeFriendly; BitrateDisp=$item.BitrateDisp; ResDisp=$item.ResDisp; FullPath=$item.FullPath }
    if ($showDuration) {
        $dispDur = $item.DurationDisp
        if ($dispDur -eq $null) { $dispDur = "-" }
        Write-Host ("[{0,3}] {1,-12} | {2,-10} | {3,-16} | {4,-12} | {5}" -f $rank,$dispDur,$item.FileSizeFriendly,$item.BitrateDisp,$item.ResDisp,$item.FullPath)
    } else {
        Write-Host ("[{0,3}] {1,-10} {2}" -f $rank,$item.FileSizeFriendly,$item.FullPath)
    }
}
$outputRows = @($outputRows)

# ---- 保存 txt ----
$saveKey = Wait-KeyPress -Prompt "`n保存列表（txt格式）到当前文件夹？【Y=保存（默认），N=跳过】"
if ($saveKey -ne "N") {
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $cleanDesc = $fullDesc.Replace("交互模式", "").Replace(" ", "_").Replace("__", "_")
    $cleanDesc = $cleanDesc.Replace("<", "").Replace(">", "").Replace(":", "").Replace('"', "").Replace("/", "_").Replace("\", "_").Replace("|", "").Replace("?", "").Replace("*", "")
    $cleanDesc = $cleanDesc.Trim("_ ").Trim()
    if ($cleanDesc.Length -gt 80) { $cleanDesc = $cleanDesc.Substring(0, 80) }
    $outName = "本文件夹内文件筛选&排序统计_交互模式_${cleanDesc}_${ts}.txt"
    $lines = @()
    $lines += "全能文件排序统计结果"
    $lines += $fullDesc
    $lines += "# 交互详情: $interactiveDetail"
    $displayRoot = $scanRoot -replace '^Microsoft\.PowerShell\.Core\\FileSystem::',''
    $lines += "#扫描根目录: $displayRoot"
    $lines += "#扫描时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += "# ===== 筛选漏斗统计（按执行顺序）====="
    $lines += "#总扫描视频数量: $totalVideoCount"
    if ($interactiveHeightFiltered -gt 0) { $lines += "#高度过滤: 排除 $interactiveHeightFiltered 个（范围 ${MinHeight}-${MaxHeight}P），剩余 $($totalVideoCount - $interactiveHeightFiltered)" }
    if ($interactiveSizeTopFiltered -gt 0) { $lines += "#体积初筛: 排除 $interactiveSizeTopFiltered 个（取前 $SizeTopCount 按大小），剩余 $($totalVideoCount - $interactiveHeightFiltered - $interactiveSizeTopFiltered)" }
    if ($interactiveBitrateFiltered -gt 0) { $lines += "#码率过滤: 排除 $interactiveBitrateFiltered 个（>= ${bitrateThresholdKbps}kbps），剩余 $($totalVideoCount - $interactiveHeightFiltered - $interactiveSizeTopFiltered - $interactiveBitrateFiltered)" }
    if ($reSortBy) { $lines += "#二次排序: 按 $reSortBy 降序重排（不拦截）" }
    if ($interactiveSizeFiltered -gt 0) { $lines += "#大小过滤: 排除 $interactiveSizeFiltered 个（>= ${MinSizeMB}MB），剩余 $($sorted.Length)" }
    $lines += "#最终输出数量: $($sorted.Length)"
    $lines += "# ===== 筛选漏斗统计结束 ====="
    $hasDurationCol = ($videoMode -and $exportMeta)
    if($hasDurationCol){
        $lines += ("{0,-4}|{1,-12}|{2,-10}|{3,-16}|{4,-12}|{5}" -f "序号","时长","大小","码率","分辨率","完整路径")
        $lines += "#--------------------------------------------------"
        for($i=0; $i -lt $outputRows.Length; $i++){
            $r = $outputRows[$i]
            $lines += ("[{0,-3}]|{1,-12}|{2,-10}|{3,-16}|{4,-12}|{5}" -f ($i+1),$r.DurationDisp,$r.FileSizeFriendly,$r.BitrateDisp,$r.ResDisp,$r.FullPath)
        }
    }else{
        $lines += ("{0,-4}|{1,-10}|{2}" -f "序号","大小","完整路径")
        $lines += "#--------------------------------------------------"
        for($i=0; $i -lt $outputRows.Length; $i++){
            $r = $outputRows[$i]
            $lines += ("[{0,-3}]|{1,-10}|{2}" -f ($i+1),$r.FileSizeFriendly,$r.FullPath)
        }
    }
    $txtContent = $lines -join "`r`n"
    try{ $txtContent | Out-File -LiteralPath $outName -Encoding UTF8; Write-Host "`n✅已保存：$PWD\$outName" -ForegroundColor Green }
    catch{ Write-Host "`n【错误】写入失败：$($_.Exception.Message)" -ForegroundColor Red }
}

Write-Host "`n任务完成，按回车键关闭窗口"
Read-Host | Out-Null