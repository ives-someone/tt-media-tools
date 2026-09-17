<#
maxm_v2.ps1
变更要点：
1.D模式：主排序按时长，保留全局预读全部时长，不弹出后置询问
2.B/R模式：不再全局批量读取时长，仅读取码率+分辨率；跑完排序后，才弹出【是否对本次结果集扫描视频时长】，只扫描筛选后的子集
3.S开启元数据：维持原有后置扫描交互
4.选N不扫描时长：预览、txt都不展示时长；选Y才执行ffprobe，填充时长列
5.全部PS2.0兼容，使用[System.IO.File]::ReadAllText，无Get‑Content -Raw
6.保留黑名单、ffprobe进程检测、UNC兼容、Ctrl+C清理子进程
#>
function Wait-KeyPress {
    param(
        [string]$Prompt
    )
    Write-Host "$Prompt " -NoNewline
    while ($Host.UI.RawUI.KeyAvailable) {
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    $char = $key.Character.ToString().ToUpper()
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

function Get-FriendlyDuration {
    param([double]$TotalSec)
    if($null -eq $TotalSec -or $TotalSec -le 0){ return "读取失败" }
    $s = [Math]::Floor($TotalSec)
    $h = [Math]::Floor($s / 3600)
    $m = [Math]::Floor(($s % 3600)/60)
    $sec = $s % 60
    $hh = if($h -lt10){"0$h"}else{"$h"}
    $mm = if($m -lt10){"0$m"}else{"$m"}
    $ss = if($sec -lt10){"0$sec"}else{"$sec"}
    if($h -gt0){ return "$hh`h${mm}m${ss}s" }
    return "${mm}m${ss}s"
}

function Test-FfprobeAvailable {
    $null = Get-Command "ffprobe.exe" -ErrorAction SilentlyContinue
    return $?
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
            catch {}
        }
    }
}

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
$runningFfprobe = Get-Process -Name "ffprobe" -ErrorAction SilentlyContinue
if ($runningFfprobe -and $runningFfprobe.Count -gt 0) {
    Write-Host "`n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Yellow
    Write-Host "⚠️ 检测到本机存在 $($runningFfprobe.Count) 个正在运行 ffprobe.exe 进程" -ForegroundColor Yellow
    Write-Host "⚠️ 警告：无法区分是上一次脚本遗留僵尸进程，" -ForegroundColor Yellow
    Write-Host "⚠️ 还是格式工厂 / QuickFFSync / 用户手动启动的转码任务！" -ForegroundColor Yellow
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!`n" -ForegroundColor Yellow
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

trap {
    if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) {
        Write-Host "`n`n⚠️ 捕获到Ctrl+C中断，正在清理本次脚本拉起的子进程..." -ForegroundColor Yellow
        Cleanup-TaskProcesses
    }
    break
}

$maxConcurrent = 4
$progressStep = 20
$maxNullBitrateItem = 200
$bitrateFilterMaxOutput = 500

Write-Host "=============================================="
Write-Host "查找视频/文件列表（S大小｜B码率｜R长边分辨率｜D视频时长）"
Write-Host "=============================================="
while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
$recurseOpt = Wait-KeyPress -Prompt "`n是否扫描子文件夹？【Y】递归(默认) 【N】仅当前目录"
$recurseParam = ($recurseOpt -ne "N")

while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
$videoModeOpt = Wait-KeyPress -Prompt "`n是否仅扫描视频文件？【Y】仅视频(默认) 【N】全部文件"
$videoMode = ($videoModeOpt -ne "N")

$videoExts = @('.mp4','.mov','.mkv','.avi','.flv','.wmv','.m4v','.ts','.mpg','.mpeg','.f4v','.m2ts','.mts','.webm','.rmvb')
$sortMode = "S"
$exportMeta = $false
$isDowngrade = $false

if ($videoMode) {
    while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
    $sortOpt = Wait-KeyPress -Prompt "`n排序维度选择：【S】文件大小(默认) 【B】视频流码率 【R】视频长边分辨率 【D】视频时长"
    if ($sortOpt -in "S","B","R","D") {
        $sortMode = $sortOpt
    }
    if ($sortMode -eq "S") {
        while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
        $metaOpt = Wait-KeyPress -Prompt "`n是否读取视频元数据(码率及分辨率) ，读取的话耗时较久？【N】不读取(默认) 【Y】读取"
        if ($metaOpt -eq "Y") { $exportMeta = $true }
    }
    elseif ($sortMode -in "B","R","D") {
        $exportMeta = $true
        Write-Host "`n【提示】B/R/D排序必须读取视频流元数据，耗时较长，请等待。"
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

$useBitrateFilter = $false
$bitrateThresholdKbps = 10000
$topCount = 100
Write-Host "`n"
if ($videoMode -and $sortMode -eq "B") {
    while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
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
    while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
    $inputCount = Read-Host "指定最大的输出统计条目数，直接回车默认100"
    if ([string]::IsNullOrWhiteSpace($inputCount) -or (-not [int]::TryParse($inputCount, [ref]$null))) {
        $topCount = 100
    } else {
        $topCount = [Math]::Max(1, [int]$inputCount)
    }
}

if ($videoMode) {
    $filterDesc = "仅视频文件"
    if($sortMode -eq "B"){
        if($useBitrateFilter){
            $sortText = "视频流码率降序，筛选≥$bitrateThresholdKbps kbps，同码率按文件大小降序"
        }else{
            $sortText = "视频流码率降序，同码率按文件大小降序"
        }
    }elseif($sortMode -eq "R"){
        $sortText = "视频长边分辨率降序，同分辨率按文件大小降序"
    }elseif($sortMode -eq "D"){
        $sortText = "视频时长降序，相同时长按文件大小降序"
    }else{
        $sortText = if($exportMeta){"文件大小降序，附带视频元数据"}else{"文件大小降序，不读取元数据"}
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

$scanRoot = $PWD.Path.Trim()
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
    exit 0
}

$workList = @()
$metaFail = 0
$totalVideoCount = $rawFiles.Count
$durMap = @{}

if ($videoMode -and $exportMeta) {
    Write-Host "【批量读取视频流元数据（码率、分辨率）】`n"
    $tempDir = Join-Path $env:TEMP "video_meta_$(Get-Random)"
    try {
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        $taskList = @()
        foreach ($f in $rawFiles) {
            while ((Get-Process ffprobe -ErrorAction SilentlyContinue | Measure-Object).Count -ge $maxConcurrent) {
                Start-Sleep -Milliseconds 40
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
                if($processedCount % $progressStep -eq 0){
                    Write-Host "已处理：$processedCount / $totalVideoCount"
                }
                $vi = [PSCustomObject]@{BitrateKbps=$null;BitrateSource=$null;Width=$null;Height=$null;LongEdge=$null;ExitCode=$t.Proc.ExitCode}
                if (Test-Path $t.OutFile) {
                    $rawTxt = [System.IO.File]::ReadAllText($t.OutFile)
                    try {
                        $jsonObj = $rawTxt | ConvertFrom-Json
                        $vStream = $jsonObj.streams[0]
                        $w=[int]$vStream.width
                        $h=[int]$vStream.height
                        $bitrateBps = $null
                        $bitrateSource = "bitrate"
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
                if ($vi.Width -and $vi.Height) {
                    if ($vi.BitrateKbps -ne $null) {
                        if ($vi.BitrateSource -eq "avgbitrate") {
                            $brDisp = "$($vi.BitrateKbps) kbps (avg)"
                        } else {
                            $brDisp = "$($vi.BitrateKbps) kbps"
                        }
                    } else {
                        $brDisp = "[码率缺失]"
                    }
                } else {
                    $brDisp = "[元数据读取失败]"
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
                    DurationSec    = $null
                    DurationDisp   = "-"
                }
            }
            $taskList = $running
            Start-Sleep -Milliseconds 20
        }
    }
    finally {
        Cleanup-TaskProcesses
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
        if(Test-Path $tempDir){ Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    }

    # ========= 只有D模式：主排序按时长，必须全局预读全部时长 =========
    if($sortMode -eq "D"){
        Write-Host "`n【D模式：全局预读取全部视频时长】`n"
        $durTempDir = Join-Path $env:TEMP "dur_batch_$(Get-Random)"
        New-Item -ItemType Directory -Path $durTempDir | Out-Null
        $durTaskList=@()
        foreach ($f in $rawFiles) {
            while ((Get-Process ffprobe -ErrorAction SilentlyContinue | Measure-Object).Count -ge $maxConcurrent) { Start-Sleep -Milliseconds 80 }
            $outFile = Join-Path $durTempDir "$($f.BaseName)_$($f.LastWriteTime.Ticks).txt"
            $arg = '/c ffprobe.exe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "' + $f.FullName + '" > "' + $outFile + '"'
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "cmd.exe"
            $psi.Arguments = $arg
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            $durTaskList += [PSCustomObject]@{ File=$f; Proc=$proc; OutFile=$outFile }
        }
        while($durTaskList.Count -gt 0){
            $run=@()
            foreach($t in $durTaskList){
                if(-not $t.Proc.HasExited){ $run+=$t;continue }
                $txt = [System.IO.File]::ReadAllText($t.OutFile)
                $sec=$null
                if($txt -match '^\s*[\d\.]+'){
                    $tmp=0.0
                    if([double]::TryParse($txt,[ref]$tmp)){ $sec=$tmp }
                }
                $durMap[$t.File.FullName] = $sec
            }
            $durTaskList = $run
            Start-Sleep -Milliseconds 40
        }
        Remove-Item $durTempDir -Recurse -Force -ErrorAction SilentlyContinue
        for($wi=0;$wi -lt $workList.Count;$wi++){
            $item = $workList[$wi]
            $s = $durMap[$item.FullPath]
            $item.DurationSec = $s
            $item.DurationDisp = Get-FriendlyDuration $s
        }
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
            DurationSec    = $null
            DurationDisp   = "-"
        }
    }
}

$validBitrateCount = 0
$truncateWarnMsg = $null

if ($videoMode -and $sortMode -eq "B") {
    $sortedAll = $workList | Sort-Object -Property @(
        @{Expression={if($_.BitrateKbps -eq $null){-1}else{$_.BitrateKbps}};Descending=$true},
        @{Expression={$_.FileSizeBytes};Descending=$true}
    )
    $validBitrateItems  = $sortedAll | Where-Object { $_.BitrateKbps -ne $null }
    $nullBitrateItems   = $sortedAll | Where-Object { $_.BitrateKbps -eq $null }
    $nullTotalCount = $nullBitrateItems.Count
    if($nullTotalCount -gt $maxNullBitrateItem){
        $nullBitrateItemsTruncated = $nullBitrateItems | Select-Object -First $maxNullBitrateItem
        $truncateWarnMsg = "⚠️ 无码率/元数据读取失败视频共$nullTotalCount条，超出上限$maxNullBitrateItem条，仅列出前$maxNullBitrateItem条，其余未写入报告"
    }else{
        $nullBitrateItemsTruncated = $nullBitrateItems
        $truncateWarnMsg = $null
    }
    $sortedAll = $validBitrateItems + $nullBitrateItemsTruncated
    if($useBitrateFilter){
        $sorted = $sortedAll | Where-Object { $_.BitrateKbps -ne $null -and $_.BitrateKbps -ge $bitrateThresholdKbps }
        $validBitrateCount = $sorted.Count
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
            if ($sorted.Count -gt $bitrateFilterMaxOutput) {
                $sorted = $sorted | Select-Object -First $bitrateFilterMaxOutput
            }
        }
    }else{
        $sorted = $sortedAll | Select-Object -First $topCount
    }
}
elseif ($videoMode -and $sortMode -eq "R") {
    $sorted = $workList | Sort-Object -Property @(
        @{Expression={if($_.LongEdge -eq $null){-1}else{$_.LongEdge}};Descending=$true},
        @{Expression={$_.FileSizeBytes};Descending=$true}
    ) | Select-Object -First $topCount
}
elseif ($videoMode -and $sortMode -eq "D") {
    $sorted = $workList | Sort-Object -Property @(
        @{Expression={if($_.DurationSec -ne $null){$_.DurationSec}else{-1}};Descending=$true},
        @{Expression={$_.FileSizeBytes};Descending=$true}
    ) | Select-Object -First $topCount
}
else {
    $sorted = $workList | Sort-Object FileSizeBytes -Descending | Select-Object -First $topCount
}

Write-Host "`n==================== 预览 ===================="
$outputRows = @()
for($i=0;$i -lt $sorted.Count;$i++){
    $item = $sorted[$i]
    $rank = $i+1
    $outputRows += [PSCustomObject]@{
        RankOrig       = $rank
        FileSizeFriendly = $item.FileSizeFriendly
        BitrateDisp      = $item.BitrateDisp
        ResDisp          = $item.ResDisp
        FullPath         = $item.FullPath
        DurationSec      = $item.DurationSec
        DurationDisp     = $item.DurationDisp
    }
    if ($videoMode -and $exportMeta) {
        # D模式才会显示真实时长；B/R/S未扫描则显示"-"
        Write-Host ("[{0,3}] {1,-12} | {2,-10} | {3,-16} | {4,-12} | {5}" -f $rank,$item.DurationDisp,$item.FileSizeFriendly,$item.BitrateDisp,$item.ResDisp,$item.FullPath)
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

[Console]::Out.Flush()
while ($Host.UI.RawUI.KeyAvailable) {
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

$doScanDuration = $false
$reSortKey = $null
$mergedList = $null

# ========= 关键：D模式跳过；B/R/S全部进入后置询问，仅扫描筛选后结果集 =========
if($sortMode -ne "D")
{
    $durScanKey = Wait-KeyPress -Prompt "`n是否对本次结果集扫描视频时长？【Y=扫描；N=跳过(默认)】"
    if ($durScanKey -eq "Y") {
        if (-not (Test-FfprobeAvailable)) {
            Write-Host "`n⚠️未找到ffprobe.exe，无法扫描时长，跳过该步骤" -ForegroundColor Yellow
        } else {
            $doScanDuration = $true
            Write-Host "`n===== 开始扫描本次结果集的视频时长（仅扫描上面筛选出来的$($sorted.Count)个文件） =====" -ForegroundColor Cyan
            $durTempDir = Join-Path $env:TEMP "dur_postscan_$(Get-Random)"
            New-Item -ItemType Directory -Path $durTempDir | Out-Null
            $durTaskList = @()
            foreach ($rowItem in $sorted) {
                $fp = $rowItem.FullPath
                $outFile = Join-Path $durTempDir "$(Get-Random).txt"
                $arg = '/c ffprobe.exe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "' + $fp + '" > "' + $outFile + '"'
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = "cmd.exe"
                $psi.Arguments = $arg
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                $proc = [System.Diagnostics.Process]::Start($psi)
                $durTaskList += [PSCustomObject]@{ FullPath=$fp; Proc=$proc; OutFile=$outFile; OrigItem=$rowItem }
            }
            $durResultList = @()
            while ($durTaskList.Count -gt 0) {
                $runDur = @()
                foreach($dt in $durTaskList){
                    if(-not $dt.Proc.HasExited){
                        $runDur += $dt
                        continue
                    }
                    $durSec = $null
                    if(Test-Path $dt.OutFile){
                        $c = [System.IO.File]::ReadAllText($dt.OutFile)
                        if($c -match '^\s*[\d\.]+'){
                            try { $durSec = [double]$c }catch{}
                        }
                    }
                    $dispTime = "-"
                    if($null -ne $durSec -and $durSec -gt 0){
                        $totalSeconds = [Math]::Floor($durSec)
                        $h = [Math]::Floor($totalSeconds / 3600)
                        $rem = $totalSeconds % 3600
                        $m = [Math]::Floor($rem / 60)
                        $s = $rem % 60
                        $hh = if ($h -lt 10) { "0$h" } else { "$h" }
                        $mm = if ($m -lt 10) { "0$m" } else { "$m" }
                        $ss = if ($s -lt 10) { "0$s" } else { "$s" }
                        if ($h -gt 0) { $dispTime = "$hh`h${mm}m${ss}s" } else { $dispTime = "${mm}m${ss}s" }
                    }
                    $durResultList += [PSCustomObject]@{
                        OrigItem     = $dt.OrigItem
                        DurationSec  = $durSec
                        DurationDisp = $dispTime
                    }
                }
                $durTaskList = $runDur
                Start-Sleep -Milliseconds 20
            }
            Remove-Item $durTempDir -Recurse -Force -ErrorAction SilentlyContinue
            [GC]::Collect()
            [GC]::WaitForPendingFinalizers()
            $mergedList = @()
            foreach($dr in $durResultList){
                $src = $dr.OrigItem
                $mergedList += [PSCustomObject]@{
                    RankOrig       = 0
                    DurationSec    = $dr.DurationSec
                    DurationDisp   = $dr.DurationDisp
                    FileSizeFriendly = $src.FileSizeFriendly
                    BitrateDisp    = $src.BitrateDisp
                    ResDisp        = $src.ResDisp
                    FullPath       = $src.FullPath
                }
            }
            Write-Host "`n=====【追加时长后预览】序号｜时长｜大小｜码率｜分辨率｜路径 =====" -ForegroundColor Cyan
            for($idx=0;$idx -lt $mergedList.Count;$idx++){
                $r = $mergedList[$idx]
                $r.RankOrig = $idx+1
                Write-Host ("[{0,3}] {1,-12} | {2,-10} | {3,-16} | {4,-12} | {5}" -f $r.RankOrig,$r.DurationDisp,$r.FileSizeFriendly,$r.BitrateDisp,$r.ResDisp,$r.FullPath)
            }
            [Console]::Out.Flush()
            while ($Host.UI.RawUI.KeyAvailable) {
                $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
            }
            $reSortKey = Wait-KeyPress -Prompt "`n保存选择：【N】沿用原有排序保存txt(默认)；【Y】按视频时长降序重新排序再保存"
            if($reSortKey -eq "Y"){
                Write-Host "`n>>> 将按视频时长降序重新排序，时长读取失败条目放末尾" -ForegroundColor Yellow
                $mergedList = $mergedList | Sort-Object -Property @(
                    @{Expression={if($_.DurationSec){$_.DurationSec}else{-1}};Descending=$true},
                    @{Expression={$_.FileSizeFriendly};Descending=$true}
                )
                Write-Host "`n=====【按时长重新排序完成预览】 =====" -ForegroundColor Cyan
                for($idx=0;$idx -lt $mergedList.Count;$idx++){
                    $r = $mergedList[$idx]
                    $r.RankOrig = $idx+1
                    Write-Host ("[{0,3}] {1,-12} | {2,-10} | {3,-16} | {4,-12} | {5}" -f $r.RankOrig,$r.DurationDisp,$r.FileSizeFriendly,$r.BitrateDisp,$r.ResDisp,$r.FullPath)
                }
                [Console]::Out.Flush()
                while ($Host.UI.RawUI.KeyAvailable) {
                    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
                }
            }
            $outputRows = $mergedList
        }
    }
}

#输出txt
$saveKey = Wait-KeyPress -Prompt "`n保存列表（txt格式）到当前文件夹？【Y=保存（默认），N=跳过】"
if ($saveKey -ne "N") {
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $fnRaw = $fullDesc `
        -replace '[<>:"/\|?*]','_' `
        -replace ' +',' '
    $outRaw = "本文件夹内文件排序统计 _ " + $fnRaw
    if($doScanDuration){
        $outRaw += " _已附加视频时长"
    }
    $outName = "$outRaw.txt"
    if($outName.Length -gt 240){
        $outName = $outRaw.Substring(0,235) + ".txt"
    }
    $lines = @()
    $lines += "全能文件排序统计结果"
    $lines += $fullDesc
    if($doScanDuration){
        $lines += "# 后置扫描：已附加视频时长列；选择：$(if($reSortKey){$reSortKey}else{'N'})"
    }
    $lines += "#扫描根目录: $scanRoot"
    $lines += "#扫描时间: $(Get-Date -Format 'yyyy‑MM‑dd HH:mm:ss')"
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
    $lines += "---------------------------------------------------------------------------------------------------------"
    if($videoMode -and $exportMeta){
        $lines += ("{0,-4}|{1,-12}|{2,-10}|{3,-16}|{4,-12}|{5}" -f "序号","时长","大小","码率","分辨率","完整路径")
        $lines += "---------------------------------------------------------------------------------------------------------"
        foreach($r in $outputRows) {
            $lines += ("[{0,-3}]|{1,-12}|{2,-10}|{3,-16}|{4,-12}|{5}" -f $r.RankOrig,$r.DurationDisp,$r.FileSizeFriendly,$r.BitrateDisp,$r.ResDisp,$r.FullPath)
        }
    }else{
        $lines += ("{0,-4}|{1,-10}|{2}" -f "序号","大小","完整路径")
        $lines += "-------------------------------------------------------------------------------------"
        foreach($r in $outputRows) {
            $lines += ("[{0,-3}]|{1,-10}|{2}" -f $r.RankOrig,$r.FileSizeFriendly,$r.FullPath)
        }
    }
    $txtContent = $lines -join "`r`n"
    try{
        $txtContent | Out-File -LiteralPath $outName -Encoding UTF8
        Write-Host "`n✅已保存：$PWD\$outName" -ForegroundColor Green
    }
    catch{
        Write-Host "`n【错误】写入txt文件失败：$($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "`n❌跳过保存" -ForegroundColor Yellow
}

Write-Host "`n任务完成，按任意键关闭窗口"
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
