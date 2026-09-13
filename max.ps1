<#
FindTopLargeFiles.ps1
修复：utf8BOM兼容PowerShell5.1，原业务逻辑不变
更新：
1. 元数据菜单提示默认项前置
2. B码率模式新增两种模式：【条目数量】/【码率阈值筛选】
   - S/R模式：仅输入最大输出条目数，默认100
   - B码率模式：可选两种逻辑
     ① 按条目数量：取前N条，默认100
     ② 按码率阈值：筛选 ≥ 指定kbps，默认阈值10000 kbps，再排序输出
3. 新增 blacklist.txt 目录黑名单；片段包含匹配；仅递归模式生效
未来可扩展功能备忘（暂未实现）
1. 文件修改时间筛选：只扫描指定时间范围内新增文件
2. CSV导出选项
#>
function Wait-KeyPress {
    param(
        [string]$Prompt
    )
    Write-Host "$Prompt " -NoNewline
    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    $char = $key.Character.ToString().ToUpper()
    #清空键盘缓冲区
    while ($Host.UI.RawUI.KeyAvailable) {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    Write-Host $char
    return $char
}
function Get-FriendlySize {
    param([long]$Bytes)
    $mb = $Bytes / 1MB
    $gb = $Bytes / 1GB
    if ($gb -ge 1) {
        return "{0:N2} GB" -f $gb
    } else {
        return "{0:N2} MB" -f $mb
    }
}
function Test-FfprobeAvailable {
    $null = Get-Command "ffprobe.exe" -ErrorAction SilentlyContinue
    return $?
}
function Get-VideoInfo {
    param([string]$FilePath)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "ffprobe.exe"
    # 同时取出 bit_rate 和 avg_bit_rate
    $psi.Arguments = "-v error -select_streams v:0 -show_entries stream=bit_rate,avg_bit_rate,width,height -of json `"$FilePath`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $rawJson = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    $bitrateBps = $null
    $bitrateSource = "bitrate" # bitrate / avgbitrate
    $w = $null
    $h = $null
    try {
        $jsonObj = $rawJson | ConvertFrom-Json
        $vStream = $jsonObj.streams[0]
        $w = [int]$vStream.width
        $h = [int]$vStream.height
        #优先bit_rate，不存在则用avg_bit_rate
        if (-not [string]::IsNullOrWhiteSpace($vStream.bit_rate)) {
            $bitrateBps = [long]$vStream.bit_rate
            $bitrateSource = "bitrate"
        }
        elseif (-not [string]::IsNullOrWhiteSpace($vStream.avg_bit_rate)) {
            $bitrateBps = [long]$vStream.avg_bit_rate
            $bitrateSource = "avgbitrate"
        }
    }
    catch {
    }
    $bitrateKbps = if ($bitrateBps -ne $null) { [Math]::Round($bitrateBps / 1000) } else { $null }
    $longEdge = if ($w -and $h) { [Math]::Max($w,$h) } else { $null }
    return [PSCustomObject]@{
        BitrateKbps   = $bitrateKbps
        BitrateSource = $bitrateSource
        Width         = $w
        Height        = $h
        LongEdge      = $longEdge
        ExitCode      = $proc.ExitCode
    }
}
function Cleanup-TaskProcesses {
    param()
    if (-not $taskList -or $taskList.Count -eq 0) { return }
    foreach($task in $taskList) {
        $proc = $task.Proc
        if($proc -ne $null -and -not $proc.HasExited) {
            try {
                $proc.Kill()
                $proc.WaitForExit(2000)
            }
            catch {
                #静默忽略进程已退出等异常
            }
        }
    }
}

# 手动递归扫描函数，支持黑名单过滤
function Get-AllFilteredFiles {
    param(
        [string]$Path,
        [bool]$DoRecurse,
        [string[]]$BlackList,
        [ref]$OutAccessDeniedDirs,
        [ref]$OutScanErrors
    )
    $fileList = @()
    $subDirs = @()
    try {
        $files = Get-ChildItem -LiteralPath $Path -File -ErrorAction Stop
        $fileList += $files
    }
    catch {
        if ($_.Exception.HResult -eq -2147024891) {
            if ($Path -and $Path -notin $OutAccessDeniedDirs.Value) {
                $OutAccessDeniedDirs.Value += $Path
            }
        }
        $OutScanErrors.Value += $_
    }

    if ($DoRecurse) {
        try {
            $subDirs = Get-ChildItem -LiteralPath $Path -Directory -ErrorAction Stop
        }
        catch {
            if ($_.Exception.HResult -eq -2147024891) {
                if ($Path -and $Path -notin $OutAccessDeniedDirs.Value) {
                    $OutAccessDeniedDirs.Value += $Path
                }
            }
            $OutScanErrors.Value += $_
        }

        foreach ($d in $subDirs) {
            $dirName = $d.Name
            $hitBlack = $false
            foreach($bItem in $BlackList){
                if($dirName.IndexOf($bItem, [System.StringComparison]::OrdinalIgnoreCase) -ge 0){
                    $hitBlack = $true
                    break
                }
            }
            if($hitBlack){
                Write-Host ">> 跳过黑名单文件夹：$($d.FullName)" -ForegroundColor DarkGray
                continue
            }
            $childResult = Get-AllFilteredFiles -Path $d.FullName -DoRecurse $true -BlackList $BlackList -OutAccessDeniedDirs $OutAccessDeniedDirs -OutScanErrors $OutScanErrors
            $fileList += $childResult
        }
    }
    return $fileList
}


# ====================== 主程序 ======================
# 启动阶段：检测系统全局残留 ffprobe.exe
$runningFfprobe = Get-Process -Name "ffprobe" -ErrorAction SilentlyContinue
if ($runningFfprobe -and $runningFfprobe.Count -gt 0) {
    Write-Host "`n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Yellow
    Write-Host "⚠️ 检测到本机存在 $($runningFfprobe.Count) 个正在运行 ffprobe.exe 进程" -ForegroundColor Yellow
    Write-Host "⚠️ 警告：无法区分是上一次脚本遗留僵尸进程，" -ForegroundColor Yellow
    Write-Host "⚠️ 还是格式工厂 / QuickFFSync / 用户手动启动的转码任务！" -ForegroundColor Yellow
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!`n" -ForegroundColor Yellow
    # 清空键盘脏缓冲区
    while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
    $cleanOpt = Wait-KeyPress -Prompt "【Y】全部终止本机所有ffprobe(高风险)；【N】保留进程继续运行(默认)"
    if ($cleanOpt -ieq "Y") {
        Write-Host ">>> 正在终止全部 ffprobe.exe ..."
        $runningFfprobe | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Host ">>> 已执行终止操作`n"
    }
    else {
        Write-Host ">>> 保留现有ffprobe进程，继续脚本`n"
    }
}
# 捕获Ctrl+C中断，触发资源清理
trap {
    # 判断是否为Ctrl+C中断
    if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) {
        Write-Host "`n`n⚠️ 捕获到Ctrl+C中断，正在清理本次脚本拉起的子进程..." -ForegroundColor Yellow
        Cleanup-TaskProcesses
    }
    break
}
$maxConcurrent = 8
$progressStep = 20
$maxNullBitrateItem = 200
$bitrateFilterMaxOutput = 500

Write-Host "=============================================="
Write-Host "查找视频/文件列表（按视频码率/分辨率/大小排序）"
Write-Host "=============================================="
#1 是否递归子文件夹
# 清空键盘残留脏字符
while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
$recurseOpt = Wait-KeyPress -Prompt "`n是否扫描子文件夹？【Y】递归(默认) 【N】仅当前目录"
$recurseParam = ($recurseOpt -ne "N")
#2 是否仅视频
while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
$videoModeOpt = Wait-KeyPress -Prompt "`n是否仅扫描视频文件？【Y】仅视频(默认) 【N】全部文件"
$videoMode = ($videoModeOpt -ne "N")
$videoExts = @('.mp4','.mov','.mkv','.avi','.flv','.wmv','.m4v','.ts','.mpg','.mpeg','.f4v','.m2ts','.mts')
$sortMode = "S"
$exportMeta = $false
$isDowngrade = $false
if ($videoMode) {
    while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
    $sortOpt = Wait-KeyPress -Prompt "`n排序维度选择：【S】文件大小(默认) 【B】视频流码率 【R】视频长边分辨率"
    if ($sortOpt -in "S","B","R") {
        $sortMode = $sortOpt
    }
    if ($sortMode -eq "S") {
        while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
        # 已调换顺序：默认N放前面
        $metaOpt = Wait-KeyPress -Prompt "`n是否读取视频元数据(码率及分辨率) ，读取的话耗时较久？【N】不读取(默认) 【Y】读取"
        if ($metaOpt -eq "Y") { $exportMeta = $true }
    }
    elseif ($sortMode -in "B","R") {
        $exportMeta = $true
        Write-Host "`n【提示】B/R排序必须读取视频流元数据，耗时较长，请等待。"
        # 清缓冲区
        while ($Host.UI.RawUI.KeyAvailable) {
            $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        }
        $ffprobeOk = Test-FfprobeAvailable
        if (-not $ffprobeOk) {
            Write-Host "`n【错误】未找到ffprobe.exe" -ForegroundColor Red
            Write-Host "【Y】降级按文件大小排序，其他键退出"
            $dgKey = Wait-KeyPress -Prompt "请按键："
            if ($dgKey -eq "Y") {
                $sortMode = "S"
                $exportMeta = $false
                $isDowngrade = $true
                Write-Host "✅降级成功，使用文件大小排序"
            } else { exit }
        }
    }
    if ($exportMeta -and (-not (Test-FfprobeAvailable))) {
        Write-Host "`n【错误】需要ffprobe读取视频元数据，未找到程序" -ForegroundColor Red
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        exit
    }
}
# ====================== 新增：区分B码率模式 / S、R模式的输入逻辑 ======================
$useBitrateFilter = $false
$bitrateThresholdKbps = 10000
$topCount = 100
Write-Host "`n"
if ($videoMode -and $sortMode -eq "B") {
    while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
    #码率模式：二选一
    $brModeOpt = Wait-KeyPress -Prompt "码率筛选模式选择：【N】指定条目数量(默认) 【T】按码率阈值筛选"
    if ($brModeOpt -eq "T") {
        $useBitrateFilter = $true
        while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
        $inputThr = Read-Host "输入最低码率阈值(kbps)，直接回车默认10000"
        if ([string]::IsNullOrWhiteSpace($inputThr) -or (-not [int]::TryParse($inputThr, [ref]$null))) {
            $bitrateThresholdKbps = 10000
        } else {
            $bitrateThresholdKbps = [int]$inputThr
        }
        Write-Host "✅筛选条件：仅保留码率 ≥ $bitrateThresholdKbps kbps 的视频"
    } else {
        while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
        $inputCount = Read-Host "指定最大的输出统计条目数，直接回车默认100"
        if ([string]::IsNullOrWhiteSpace($inputCount) -or (-not [int]::TryParse($inputCount, [ref]$null))) {
            $topCount = 100
        } else {
            $topCount = [Math]::Max(1, [int]$inputCount)
        }
    }
} else {
    #S / R / 全部文件模式：统一输入条目数量
    while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
    $inputCount = Read-Host "指定最大的输出统计条目数，直接回车默认100"
    if ([string]::IsNullOrWhiteSpace($inputCount) -or (-not [int]::TryParse($inputCount, [ref]$null))) {
        $topCount = 100
    } else {
        $topCount = [Math]::Max(1, [int]$inputCount)
    }
}
# 扫描描述文本
if ($videoMode) {
    $filterDesc = "仅视频文件"
    if($sortMode -eq "B"){
        if($useBitrateFilter){
            $sortText = "视频流码率降序，筛选≥$bitrateThresholdKbps kbps，同码率按文件大小降序"
        }else{
            $sortText = "视频流码率降序，同码率按文件大小降序"
        }
    }else{
        $sortText = @{
            "S" = if($exportMeta){"文件大小降序，附带视频元数据"}else{"文件大小降序，不读取元数据"}
            "R" = "视频长边分辨率降序，同分辨率按文件大小降序"
        }[$sortMode]
    }
    if ($isDowngrade) { $sortText = "【降级】$sortText" }
} else {
    $filterDesc = "全部文件"
    $sortText = "文件大小降序"
}
if($useBitrateFilter){
    $fullDesc = "过滤：$filterDesc | 排序：$sortText | 筛选码率≥$bitrateThresholdKbps kbps"
}else{
    $fullDesc = "过滤：$filterDesc | 排序：$sortText | 取前$topCount"
}
Write-Host "`n========================================"
Write-Host "开始扫描"
Write-Host $fullDesc
Write-Host "=======================================`n"

# 文件扫描（手动递归，支持黑名单过滤）
$scanRoot = $PWD.Path.Trim()
# ========== 读取【扫描根目录】下 blacklist.txt（片段包含匹配） ==========
$blacklistFile = Join-Path $scanRoot "blacklist.txt"
if (Test-Path -LiteralPath $blacklistFile) {
    $scanBlackList = Get-Content -LiteralPath $blacklistFile -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object {
        $_ -ne "" -and $_ -notmatch '^#'
    }
    Write-Host ">> 已加载扫描根目录下黑名单配置：$($scanBlackList -join ' | ')"
} else {
    $scanBlackList = @()
    Write-Host ">> 未找到blacklist.txt，不启用目录黑名单过滤"
}

$accessDeniedDirs = @()
$scanErrors = @()

$rawAll = Get-AllFilteredFiles -Path $scanRoot `
    -DoRecurse $recurseParam `
    -BlackList $scanBlackList `
    -OutAccessDeniedDirs ([ref]$accessDeniedDirs) `
    -OutScanErrors ([ref]$scanErrors)

if ($videoMode) {
    $rawFiles = $rawAll | Where-Object { $_.Extension -in $videoExts }
} else {
    $rawFiles = $rawAll
}
if ($rawFiles.Count -eq 0) {
    Write-Host "无匹配文件，按任意键退出"
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}
$workList = @()
$metaFail = 0
$totalVideoCount = $rawFiles.Count
if ($videoMode -and $exportMeta) {
    Write-Host "【批量读取视频流元数据】`n"
    $tempDir = Join-Path $env:TEMP "video_meta_$(Get-Random)"
    try {
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        $taskList = @()
        foreach ($f in $rawFiles) {
            while ((Get-Process ffprobe -ErrorAction SilentlyContinue | Measure-Object).Count -ge $maxConcurrent) {
                Start-Sleep -Milliseconds 80
            }
            $outPath = Join-Path $tempDir "$($f.BaseName)_$($f.LastWriteTime.Ticks).txt"
            $arg = '/c ffprobe.exe -v error -select_streams v:0 -show_entries stream=bit_rate,avg_bit_rate,width,height -of json "' + $f.FullName + '" > "' + $outPath + '"'
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "cmd.exe"
            $psi.Arguments = $arg
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            $taskList += [PSCustomObject]@{
                File    = $f
                Proc    = $proc
                OutFile = $outPath
            }
        }
        $processedCount = 0
        while ($taskList.Count -gt 0) {
            $running = @()
            foreach ($t in $taskList) {
                if (-not $t.Proc.HasExited) {
                    $running += $t
                    continue
                }
                $processedCount++
                #进度输出
                if($processedCount % $progressStep -eq 0){
                    Write-Host "已处理：$processedCount / $totalVideoCount"
                }
                $vi = [PSCustomObject]@{BitrateKbps=$null;BitrateSource=$null;Width=$null;Height=$null;LongEdge=$null;ExitCode=$t.Proc.ExitCode}
                if (Test-Path $t.OutFile) {
                    $rawTxt = Get-Content $t.OutFile -Raw
                    try {
                        $jsonObj = $rawTxt | ConvertFrom-Json
                        $vStream = $jsonObj.streams[0]
                        $w=[int]$vStream.width
                        $h=[int]$vStream.height
                        $bitrateBps = $null
                        $bitrateSource = "bitrate"
                        #优先bit_rate，没有则取avg_bit_rate
                        if (-not [string]::IsNullOrWhiteSpace($vStream.bit_rate)) {
                            $bitrateBps = [long]$vStream.bit_rate
                            $bitrateSource = "bitrate"
                        }
                        elseif (-not [string]::IsNullOrWhiteSpace($vStream.avg_bit_rate)) {
                            $bitrateBps = [long]$vStream.avg_bit_rate
                            $bitrateSource = "avgbitrate"
                        }
                        $brKbps = if($bitrateBps -ne $null) {[Math]::Round($bitrateBps /1000)} else {$null}
                        $le = [Math]::Max($w,$h)
                        $vi = [PSCustomObject]@{
                            BitrateKbps   = $brKbps
                            BitrateSource = $bitrateSource
                            Width         = $w
                            Height        = $h
                            LongEdge      = $le
                            ExitCode      = $t.Proc.ExitCode
                        }
                    }
                    catch {
                        $metaFail +=1
                    }
                } else {
                    $metaFail +=1
                }
                $szDisp = Get-FriendlySize -Bytes $t.File.Length
                # 拼接显示文本，区分错误标记
                if ($vi.ExitCode -ne 0 -or $vi.BitrateKbps -eq $null) {
                    $brDisp = "[元数据读取失败]"
                } else {
                    if ($vi.BitrateSource -eq "avgbitrate") {
                        $brDisp = "$($vi.BitrateKbps) kbps (avg)"
                    } else {
                        $brDisp = "$($vi.BitrateKbps) kbps"
                    }
                }
                $resDisp = if($vi.Width -and $vi.Height){"$($vi.Width)x$($vi.Height)"}else{"-"}
                $workList += [PSCustomObject]@{
                    FullPath       = $t.File.FullName.Trim()
                    FileSizeBytes  = $t.File.Length
                    FileSizeFriendly = $szDisp
                    BitrateKbps    = $vi.BitrateKbps
                    BitrateDisp    = $brDisp
                    BitrateSource  = $vi.BitrateSource
                    Width          = $vi.Width
                    Height         = $vi.Height
                    ResDisp        = $resDisp
                    LongEdge       = $vi.LongEdge
                    ProcExitCode   = $vi.ExitCode
                }
            }
            $taskList = $running
            Start-Sleep -Milliseconds 60
        }
    }
    finally {
        Cleanup-TaskProcesses
        Start-Sleep -Milliseconds 300
        if(Test-Path $tempDir){ Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
} else {
    foreach ($f in $rawFiles) {
        $szDisp = Get-FriendlySize -Bytes $f.Length
        $workList += [PSCustomObject]@{
            FullPath       = $f.FullName.Trim()
            FileSizeBytes  = $f.Length
            FileSizeFriendly = $szDisp
            BitrateKbps    = $null
            BitrateDisp    = "-"
            BitrateSource  = $null
            Width          = $null
            Height         = $null
            ResDisp        = "-"
            LongEdge       = $null
            ProcExitCode   = $null
        }
    }
}
# 排序 + 筛选逻辑
$validBitrateCount = 0
if ($videoMode -and $sortMode -eq "B") {
    #有效码率在前，空/失败放末尾
    $sortedAll = $workList | Sort-Object -Property @(
        @{Expression={if($_.BitrateKbps -eq $null){-1}else{$_.BitrateKbps}};Descending=$true},
        @{Expression={$_.FileSizeBytes};Descending=$true}
    )
    $validBitrateItems  = $sortedAll | Where-Object { $_.BitrateKbps -ne $null }
    $nullBitrateItems   = $sortedAll | Where-Object { $_.BitrateKbps -eq $null }
    $nullTotalCount = $nullBitrateItems.Count
    #截断无码率条目
    if($nullTotalCount -gt $maxNullBitrateItem){
        $nullBitrateItemsTruncated = $nullBitrateItems | Select-Object -First $maxNullBitrateItem
        $truncateWarnMsg = "⚠️ 无码率/元数据读取失败视频共$nullTotalCount条，超出上限$maxNullBitrateItem条，仅列出前$maxNullBitrateItem条，其余未写入报告"
    }else{
        $nullBitrateItemsTruncated = $nullBitrateItems
        $truncateWarnMsg = $null
    }
    $sortedAll = $validBitrateItems + $nullBitrateItemsTruncated
    if($useBitrateFilter){
        #阈值筛选：保留码率非空并且大于等于阈值
        $sorted = $sortedAll | Where-Object { $_.BitrateKbps -ne $null -and $_.BitrateKbps -ge $bitrateThresholdKbps }
        $validBitrateCount = $sorted.Count
        # 码率阈值筛选模式：条目上限截断 + 修改最大输出上限交互
        if ($sorted.Count -gt $bitrateFilterMaxOutput) {
            do {
                $truncateWarnMsg = "⚠️码率阈值筛选共命中{0}条记录，超出当前最大输出上限{1}，将仅列出前{1}条" -f $sorted.Count, $bitrateFilterMaxOutput
                Write-Host "`n$truncateWarnMsg" -ForegroundColor Yellow
                $reOpt = Wait-KeyPress -Prompt "是否调整【最大输出上限】？【Y】修改上限数值 【N】直接继续`n提示：调高上限可以输出更多已命中结果，但会增加预览与导出耗时"
                if ($reOpt -ieq "Y") {
                    while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
                    $inputMax = Read-Host "请输入新的最大输出上限（正整数，示例：1000）"
                    $tempNum = 0
                    if ([string]::IsNullOrWhiteSpace($inputMax) -or (-not [int]::TryParse($inputMax, [ref]$tempNum)) -or $tempNum -lt 1) {
                        Write-Host "输入无效，保持原上限 $bitrateFilterMaxOutput" -ForegroundColor Red
                    } else {
                        $bitrateFilterMaxOutput = $tempNum
                        Write-Host "已更新最大输出上限为 $bitrateFilterMaxOutput，重新判断..." -ForegroundColor Green
                    }
                }
            } while ($reOpt -ieq "Y" -and $sorted.Count -gt $bitrateFilterMaxOutput)
            # 最终截断
            if ($sorted.Count -gt $bitrateFilterMaxOutput) {
                $sorted = $sorted | Select-Object -First $bitrateFilterMaxOutput
            }
        }
    }else{
        $sorted = $sortedAll | Select-Object -First $topCount
    }
} elseif ($videoMode -and $sortMode -eq "R") {
    $sorted = $workList | Sort-Object -Property @(
        @{Expression={if($_.LongEdge -eq $null){-1}else{$_.LongEdge}};Descending=$true},
        @{Expression={$_.FileSizeBytes};Descending=$true}
    ) | Select-Object -First $topCount
} else {
    $sorted = $workList | Sort-Object FileSizeBytes -Descending | Select-Object -First $topCount
}
#控制台预览
Write-Host "`n==================== 预览 ===================="
$outputRows = @()
for($i=0;$i -lt $sorted.Count;$i++){
    $item = $sorted[$i]
    $rank = $i+1
    $outputRows += [PSCustomObject]@{
        Rank             = $rank
        FileSizeFriendly = $item.FileSizeFriendly
        BitrateDisp      = $item.BitrateDisp
        ResDisp          = $item.ResDisp
        FullPath         = $item.FullPath
    }
    if ($videoMode -and $exportMeta) {
        Write-Host ("[{0,3}] {1,-10} | {2,-16} | {3,-12} | {4}" -f $rank,$item.FileSizeFriendly,$item.BitrateDisp,$item.ResDisp,$item.FullPath)
    } else {
        Write-Host ("[{0,3}] {1,-10} {2}" -f $rank,$item.FileSizeFriendly,$item.FullPath)
    }
}
Write-Host "======================================================"
Write-Host $fullDesc
Write-Host "总扫描视频数量：$totalVideoCount"
if($useBitrateFilter){
    Write-Host "满足码率阈值条目数：$validBitrateCount"
}
if ($videoMode -and $exportMeta) { Write-Host "元数据读取失败数量：$metaFail" }
if($truncateWarnMsg){ Write-Host $truncateWarnMsg }
if($accessDeniedDirs.Count -gt 0){
    Write-Host "无法访问目录共 $($accessDeniedDirs.Count) 个"
}
# 强制刷新控制台输出流，等待所有打印内容渲染完成
[Console]::Out.Flush()
Start-Sleep -Milliseconds 100
[Console]::Out.Flush()
#输出txt【修复：兼容UNC网络路径 + PS5.1 UTF8-BOM；文件名自动根据筛选条件生成中文名称】
$saveKey = Wait-KeyPress -Prompt "`n保存列表（txt格式）到当前文件夹？【Y=保存（默认），N=跳过】"
# 逻辑：不是N就保存（回车/其他按键都走保存，仅N跳过）
if ($saveKey -ne "N") {
    Write-Host "开始导出文件清单..."
    # 生成安全中文文件名，剔除Windows非法文件名字符
    $fnRaw = $fullDesc `
        -replace '[<>:"/\|?*]','_' `
        -replace ' +',' '
    $outRaw = "本文件夹内文件排序统计 _ " + $fnRaw
    $outName = "$outRaw.txt"
    # 文件名超长截断，防止超过255字符
    if($outName.Length -gt 240){
        $outName = $outRaw.Substring(0,235) + ".txt"
    }
    $lines = @()
    $lines += $fullDesc
    $lines += "#扫描根目录: $scanRoot"
    $lines += "#扫描时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += "#总扫描视频数量:$totalVideoCount"
    if($useBitrateFilter){
        $lines += "#满足码率阈值条目数:$validBitrateCount"
    }
    $lines += "#元数据失败:$metaFail"
    if($truncateWarnMsg){
        $lines += "#$truncateWarnMsg"
    }
    if($accessDeniedDirs.Count -gt 0){
        $lines += "#无法访问目录($($accessDeniedDirs.Count)):"
        foreach($d in $accessDeniedDirs){
            $lines += "#  - $d"
        }
    }
    $lines += "-------------------------------------------------------------------------"
    foreach($r in $outputRows) {
        if ($videoMode -and $exportMeta) {
            $lines += ("[{0,3}] {1,-10} | {2,-16} | {3,-12} | {4}" -f $r.Rank,$r.FileSizeFriendly,$r.BitrateDisp,$r.ResDisp,$r.FullPath)
        } else {
            $lines += ("[{0,3}] {1,-10} {2}" -f $r.Rank,$r.FileSizeFriendly,$r.FullPath)
        }
    }
    $txtContent = $lines -join "`r`n"
    try{
        $txtContent | Out-File -LiteralPath $outName -Encoding UTF8
        Write-Host "✅已保存 $PWD\$outName"
    }
    catch{
        Write-Host "`n【错误】写入txt文件失败：$($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "❌跳过保存"
}
Write-Host "`n任务完成，按任意键关闭窗口"
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
