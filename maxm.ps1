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

保留原脚本交互式使用的同时，支持AI自然语言驱动，可非交互式使用

将以下“自然语言 → maxm.ps1 参数映射 Prompt 模板”存成TXT喂给AI后，给出自己的需求，AI反馈相应筛查命令行，powershell复制执行即可

你是一个命令行参数翻译器。
请读取并锁定以下规则，等待用户后续输入具体需求（严禁主动翻译示例，当前处于【等待状态】，未收到需求前只回"已就绪，请提需求"）。
用户的脚本 maxm.ps1 已加入 PATH，支持以下参数：
## 参数说明
- -Mode <char>            : 排序维度。S=文件大小降序, B=码率降序, R=分辨率(长边)降序, D=视频时长降序
- -Path <string>          : 目标路径，不传则自动用当前目录（$PWD）
- -Recurse                : 递归子目录
- -Meta                   : 读取视频元数据（分辨率、码率等，耗时）
- -Top <int>              : 最终输出前N个
- -MinHeight <int>        : 最低高度筛选（默认0=不筛选）
- -MaxHeight <int>        : 最高高度筛选（默认0=不筛选）
- -MinBitrate <int>       : 最低码率阈值 kbps（默认0）。B模式主排序用；S模式下作为后置筛选条件（需配合-Meta读取码率）
- -SizeTop                : 启用"先按体积初筛"模式
- -SizeTopCount <int>     : 体积初筛取前N个（默认100）
- -UserQuery <string>     : 用户原始自然语言需求（用于txt文件命名和记录）
- -ScanDuration           : 后置扫描结果集的视频时长
## 规则
1. 用户不传 -Path 时，命令中不写 -Path（脚本自动用 $PWD）
2. 文件名固定为 maxm.ps1，不加 .\
3. 非交互模式：不询问用户，直接输出完整命令
4. 参数顺序：先排序/筛选参数，后数量参数
5. 如果用户说"码率最高/按码率排序"，对应 -Mode B
6. 如果用户说"体积最大/文件最大/按大小排序/从大到小"，对应 -Mode S
7. 如果用户说"分辨率最高/4K/1080p/720p"，对应 -Mode R 或配合 -MinHeight/-MaxHeight。"4K以下/低于4K" → -MaxHeight 2160（长边≤2160px 即包含1440p/1080p/720p等）
8. 如果用户说"时长最长/按时长排序"，对应 -Mode D
9. 如果用户说"先按体积取前N个再按XX排序"，对应 -SizeTop -SizeTopCount N（注意：这不是最终排序，只是初筛）
10. 如果用户说"扫描时长/读取时长"，加上 -ScanDuration
11. 【强制】每一次翻译输出【必须】附带 -UserQuery "用户原始需求原文"。无论需求多简单、多短，都不得省略。此参数用于txt文件命名和首行记录，省略将导致文件无法溯源。原文中的引号用单引号或转义。
12. 除非用户明确说"不递归"/"仅当前目录"/"不扫描子目录"，否则命令中始终包含 -Recurse
13. 如果用户描述中有矛盾（如说200个又说100个），以最后出现的数字为准，或询问用户
14. S模式 + -MinBitrate 组合说明：当用户要求"按大小排序"且附带码率条件时，使用 -Mode S -Meta -MinBitrate <值>。脚本执行逻辑为：先按文件大小降序排列，再筛选码率≥阈值的条目，最后取 -Top N。此组合要求必须带 -Meta（否则无码率数据可筛）。
## 输出格式
只输出一行完整命令，不要解释。如果用户需求不明确，先输出命令再追加一行问句确认。
## 示例
用户：帮我找本文件夹里码率最高的20个视频
输出：maxm.ps1 -Mode B -Meta -Top 20 -UserQuery "帮我找本文件夹里码率最高的20个视频"
用户：递归找体积前100里分辨率最高的30个
输出：maxm.ps1 -Mode R -Recurse -Meta -SizeTop -SizeTopCount 100 -Top 30 -UserQuery "递归找体积前100里分辨率最高的30个"
用户：查找文件夹里720P码率大于5000K的视频，按文件从大到小排序
输出：maxm.ps1 -Recurse -Mode S -Meta -MinHeight 720 -MaxHeight 720 -MinBitrate 5000 -UserQuery "查找文件夹里720P码率大于5000K的视频，按文件从大到小排序"
用户：帮我找文件夹内720P分辨率视频码率大于8000k的，按文件大小降序排列
输出：maxm.ps1 -Recurse -Mode S -Meta -MinHeight 720 -MaxHeight 720 -MinBitrate 8000 -UserQuery "帮我找文件夹内720P分辨率视频码率大于8000k的，按文件大小降序排列"
用户：文件夹里4k以下分辨率里，码率最大的文件，按从大到小排列
输出：maxm.ps1 -Recurse -Mode B -Meta -MaxHeight 2160 -UserQuery "文件夹里4k以下分辨率里，码率最大的文件，按从大到小排列"
---
当前处于【等待需求】状态，未收到用户真实需求前，只回复"已就绪，请提需求"并输出此状态。

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
    param([string]$Path,[bool]$DoRecurse,[string[]]$BlackList,[ref]$OutAccessDeniedDirs,[ref]$OutScanErrors)
    $fileList = @(); $subDirs = @()
    try { $files = Get-ChildItem -LiteralPath $Path -File -ErrorAction Stop; $fileList += $files }
    catch {
        if ($_.Exception.HResult -eq -2147024891) { if ($Path -and $Path -notin $OutAccessDeniedDirs.Value) { $OutAccessDeniedDirs.Value += $Path } }
        $OutScanErrors.Value += $_
    }
    if ($DoRecurse) {
        try { $subDirs = Get-ChildItem -LiteralPath $Path -Directory -ErrorAction Stop }
        catch { if ($_.Exception.HResult -eq -2147024891) { if ($Path -and $Path -notin $OutAccessDeniedDirs.Value) { $OutAccessDeniedDirs.Value += $Path } }; $OutScanErrors.Value += $_ }
        foreach ($d in $subDirs) {
            $dirName = $d.Name; $hitBlack = $false
            foreach($bItem in $BlackList){ if($dirName.IndexOf($bItem, [System.StringComparison]::OrdinalIgnoreCase) -ge 0){ $hitBlack = $true; break } }
            if($hitBlack){ Write-Host ">> 跳过黑名单文件夹：$($d.FullName)" -ForegroundColor DarkGray; continue }
            $childResult = Get-AllFilteredFiles -Path $d.FullName -DoRecurse $true -BlackList $BlackList -OutAccessDeniedDirs $OutAccessDeniedDirs -OutScanErrors $OutScanErrors
            $fileList += $childResult
        }
    }
    return $fileList
}

# ====================== 非交互模式入口 ======================
if ($Mode -ne "") {
    Write-Host ">>> 非交互模式：参数驱动" -ForegroundColor Cyan
    Write-Host ">>> Mode=$Mode Recurse=$($Recurse.IsPresent) Meta=$($Meta.IsPresent) BitrateThreshold=$BitrateThreshold MinBitrate=$MinBitrate MinHeight=$MinHeight MaxHeight=$MaxHeight" -ForegroundColor Gray

    # ---- 参数校验 ----
    $scanRoot = if ($Path) { $Path } else { $PWD.Path.Trim() }
    $recurseParam = $Recurse.IsPresent
    $videoMode = -not $AllFiles.IsPresent
    $sortMode = $Mode.ToUpper()
    if ($sortMode -notin "S","B","R","D") { Write-Host "错误：Mode 必须是 S/B/R/D 之一" -ForegroundColor Red; exit 1 }
    $exportMeta = $Meta.IsPresent -or ($sortMode -in "B","R","D")
    $topCount = [Math]::Max(1, $Top)
    # 兼容 -BitrateThreshold 和 -MinBitrate 两种写法
    $bitrateThresholdKbps = if ($MinBitrate -gt 0) { $MinBitrate } elseif ($BitrateThreshold -gt 0) { $BitrateThreshold } else { 0 }
    $useBitrateFilter = ($bitrateThresholdKbps -gt 0)
    $maxConcurrent = 4; $progressStep = 20; $maxNullBitrateItem = 200; $bitrateFilterMaxOutput = 500

    if ($exportMeta -and -not (Test-FfprobeAvailable)) {
        Write-Host "错误：需要 ffprobe 但未找到，请安装后重试" -ForegroundColor Red; exit 1
    }

    Write-Host "扫描路径：$scanRoot"
    Write-Host "递归：$recurseParam | 仅视频：$videoMode | 排序：$sortMode | 元数据：$exportMeta"
    if ($useBitrateFilter) { Write-Host "码率阈值：>= $bitrateThresholdKbps kbps" }
    Write-Host "输出条数：$topCount"
    Write-Host ""

    # ---- 黑名单 ----
    $scanBlackList = @()
    $blacklistFile = Join-Path $scanRoot "blacklist.txt"
    if (Test-Path -LiteralPath $blacklistFile) {
        $scanBlackList = Get-Content -LiteralPath $blacklistFile -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" -and $_ -notmatch '^#' }
        Write-Host ">> 已加载黑名单：$($scanBlackList -join ' | ')"
    }

    # ---- 扫描文件 ----
    $accessDeniedDirs = @(); $scanErrors = @()
    $rawAll = Get-AllFilteredFiles -Path $scanRoot -DoRecurse $recurseParam -BlackList $scanBlackList -OutAccessDeniedDirs ([ref]$accessDeniedDirs) -OutScanErrors ([ref]$scanErrors)
    $videoExts = @('.mp4','.mov','.mkv','.avi','.flv','.wmv','.m4v','.ts','.mpg','.mpeg','.f4v','.m2ts','.mts','.webm','.rmvb')
    if ($videoMode) { $rawFiles = $rawAll | Where-Object { $_.Extension -in $videoExts } } else { $rawFiles = $rawAll }
    if ($rawFiles.Count -eq 0) { Write-Host "无匹配文件"; exit 0 }

    $totalVideoCount = $rawFiles.Count
    Write-Host "扫描到 $totalVideoCount 个文件，开始处理..."

    # ---- 元数据读取 ----
    $workList = @(); $metaFail = 0; $durMap = @{}
    if ($videoMode -and $exportMeta) {
        Write-Host "【读取视频元数据】"
        $tempDir = Join-Path $env:TEMP "video_meta_$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        $taskList = @()
        foreach ($f in $rawFiles) {
            while ((Get-Process ffprobe -ErrorAction SilentlyContinue | Measure-Object).Count -ge $maxConcurrent) { Start-Sleep -Milliseconds 40 }
            $outPath = Join-Path $tempDir "$($f.BaseName)_$($f.LastWriteTime.Ticks).txt"
            $arg = '/c ffprobe.exe -v error -select_streams v:0 -show_entries stream=bit_rate,avg_bit_rate,width,height -of json "' + $f.FullName + '" > "' + $outPath + '"'
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "cmd.exe"; $psi.Arguments = $arg; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            $taskList += [PSCustomObject]@{ File=$f; Proc=$proc; OutFile=$outPath }
        }
        $processedCount = 0
        while ($taskList.Count -gt 0) {
            $running = @()
            foreach ($t in $taskList) {
                if (-not $t.Proc.HasExited) { $running += $t; continue }
                $processedCount++
                if($processedCount % $progressStep -eq 0){ Write-Host "已处理：$processedCount / $totalVideoCount" }
                $vi = [PSCustomObject]@{BitrateKbps=$null;BitrateSource=$null;Width=$null;Height=$null;LongEdge=$null}
                # >>> FIX: -LiteralPath 防特殊字符
                if (Test-Path -LiteralPath $t.OutFile -PathType Leaf) {
                    try {
                        $rawTxt = [System.IO.File]::ReadAllText($t.OutFile)
                        $jsonObj = $rawTxt | ConvertFrom-Json
                        $vStream = $jsonObj.streams[0]
                        $w=[int]$vStream.width; $h=[int]$vStream.height
                        $bitrateBps = $null; $bitrateSource = "bitrate"
                        if (-not [string]::IsNullOrWhiteSpace($vStream.bit_rate)) { $bitrateBps = [long]$vStream.bit_rate }
                        elseif (-not [string]::IsNullOrWhiteSpace($vStream.avg_bit_rate)) { $bitrateBps = [long]$vStream.avg_bit_rate; $bitrateSource = "avgbitrate" }
                        $vi = [PSCustomObject]@{
                            BitrateKbps=if($bitrateBps){[Math]::Round($bitrateBps/1000)}else{$null}
                            BitrateSource=$bitrateSource; Width=$w; Height=$h; LongEdge=[Math]::Max($w,$h)
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
                    DurationSec=$null; DurationDisp="-"
                }
            }
            $taskList = $running; Start-Sleep -Milliseconds 20
        }
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        foreach ($f in $rawFiles) {
            $workList += [PSCustomObject]@{
                FullPath=$f.FullName.Trim(); FileSizeBytes=$f.Length; FileSizeFriendly=(Get-FriendlySize -Bytes $f.Length)
                BitrateKbps=$null; BitrateDisp="-"; Width=$null; Height=$null; ResDisp="-"; LongEdge=$null; DurationSec=$null; DurationDisp="-"
            }
        }
    }

    # ---- 体积前N筛选 ----
    if ($SizeTop) {
        $sizeTopCount = [Math]::Max(1, $SizeTopCount)
        $workList = @($workList | Sort-Object FileSizeBytes -Descending | Select-Object -First $sizeTopCount)
        Write-Host "体积筛选：取体积最大前 $sizeTopCount 个，剩余 $($workList.Count) 个进入后续排序" -ForegroundColor Cyan
    }

    # ---- 分辨率筛选 ----
    if ($MinHeight -gt 0 -or $MaxHeight -gt 0) {
        $beforeCount = $workList.Count
        if ($MinHeight -gt 0) { $workList = @($workList | Where-Object { $_.Height -ge $MinHeight }) }
        if ($MaxHeight -gt 0) { $workList = @($workList | Where-Object { $_.Height -le $MaxHeight }) }
        Write-Host "分辨率筛选：从 $beforeCount 条过滤到 $($workList.Count) 条（高度 $MinHeight ~ $MaxHeight）"
    }

    # ---- 排序 + 筛选 ----
    if ($sortMode -eq "B") {
        $sortedAll = @($workList | Sort-Object @{E={if($_.BitrateKbps -eq $null){-1}else{$_.BitrateKbps}};D=$true}, @{E={$_.FileSizeBytes};D=$true})
        if ($useBitrateFilter) { $sorted = @($sortedAll | Where-Object { $_.BitrateKbps -ge $bitrateThresholdKbps }) }
        else { $sorted = @($sortedAll | Select-Object -First $topCount) }
    } elseif ($sortMode -eq "R") {
        $sorted = @($workList | Sort-Object @{E={if($_.LongEdge -eq $null){-1}else{$_.LongEdge}};D=$true}, @{E={$_.FileSizeBytes};D=$true} | Select-Object -First $topCount)
    } elseif ($sortMode -eq "D") {
        Write-Host "【D模式：扫描时长】"
        $durTempDir = Join-Path $env:TEMP "dur_$(Get-Random)"; New-Item -ItemType Directory -Path $durTempDir | Out-Null
        $durTaskList = @()
        foreach ($f in $rawFiles) {
            while ((Get-Process ffprobe -ErrorAction SilentlyContinue | Measure-Object).Count -ge $maxConcurrent) { Start-Sleep -Milliseconds 40 }
            $outFile = Join-Path $durTempDir "$($f.BaseName)_$($f.LastWriteTime.Ticks).txt"
            $arg = '/c ffprobe.exe -v error -show_entries format=duration -of default:noprint_wrappers=1:nokey=1 "' + $f.FullName + '" > "' + $outFile + '"'
            $psi = New-Object System.Diagnostics.ProcessStartInfo; $psi.FileName="cmd.exe"; $psi.Arguments=$arg; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
            $proc = [System.Diagnostics.Process]::Start($psi)
            $durTaskList += [PSCustomObject]@{ File=$f; Proc=$proc; OutFile=$outFile }
        }
        while($durTaskList.Count -gt 0){ $run=@(); foreach($t in $durTaskList){ if(-not $t.Proc.HasExited){$run+=$t;continue}; $txt=[System.IO.File]::ReadAllText($t.OutFile); $sec=$null; if($txt -match '^\s*[\d\.]+'){[double]::TryParse($txt,[ref]$sec)|Out-Null}; $durMap[$t.File.FullName]=$sec }; $durTaskList=$run; Start-Sleep -Milliseconds 40 }
        Remove-Item $durTempDir -Recurse -Force -ErrorAction SilentlyContinue
        for($wi=0;$wi -lt $workList.Count;$wi++){ $item=$workList[$wi]; $s=$durMap[$item.FullPath]; $item.DurationSec=$s; $item.DurationDisp=(Get-FriendlyDuration $s) }
        $sorted = @($workList | Sort-Object @{E={if($_.DurationSec -ne $null){$_.DurationSec}else{-1}};D=$true}, @{E={$_.FileSizeBytes};D=$true} | Select-Object -First $topCount)
    } else {
        # >>> FIX: S模式强制物化 + 码率筛选
        $sortedAll = @($workList | Sort-Object FileSizeBytes -Descending)
        if ($useBitrateFilter) {
            $sortedAll = @($sortedAll | Where-Object { $_.BitrateKbps -ne $null -and $_.BitrateKbps -ge $bitrateThresholdKbps })
            Write-Host "码率筛选：从 $($workList.Count) 条中筛选 >= $bitrateThresholdKbps kbps，剩余 $($sortedAll.Count) 条" -ForegroundColor Cyan
        }
        $sorted = @($sortedAll | Select-Object -First $topCount)
    }

    # >>> FIX: 最终保险，强制数组
    $sorted = @($sorted)

    # ---- 后置时长扫描 ----
    if ($ScanDuration -and $sortMode -ne "D") {
        Write-Host "【后置时长扫描】"
        $durTempDir = Join-Path $env:TEMP "dur_post_$(Get-Random)"; New-Item -ItemType Directory -Path $durTempDir | Out-Null
        $durTaskList = @()
        foreach ($item in $sorted) {
            $outFile = Join-Path $durTempDir "$(Get-Random).txt"
            $arg = '/c ffprobe.exe -v error -show_entries format=duration -of default:noprint_wrappers=1:nokey=1 "' + $item.FullPath + '" > "' + $outFile + '"'
            $psi = New-Object System.Diagnostics.ProcessStartInfo; $psi.FileName="cmd.exe"; $psi.Arguments=$arg; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
            $proc = [System.Diagnostics.Process]::Start($psi)
            $durTaskList += [PSCustomObject]@{ Item=$item; Proc=$proc; OutFile=$outFile }
        }
        while($durTaskList.Count -gt 0){ $run=@(); foreach($t in $durTaskList){ if(-not $t.Proc.HasExited){$run+=$t;continue}; $txt=[System.IO.File]::ReadAllText($t.OutFile); $sec=$null; if($txt -match '^\s*[\d\.]+'){[double]::TryParse($txt,[ref]$sec)|Out-Null}; $t.Item.DurationSec=$sec; $t.Item.DurationDisp=(Get-FriendlyDuration $sec) }; $durTaskList=$run; Start-Sleep -Milliseconds 20 }
        Remove-Item $durTempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ---- 输出到控制台 ----
    $outputRows = @()
    foreach($item in $sorted){
        $outputRows += [PSCustomObject]@{
            Rank = ($outputRows.Count + 1)
            Duration = $item.DurationDisp
            Size = $item.FileSizeFriendly
            Bitrate = $item.BitrateDisp
            Resolution = $item.ResDisp
            Path = $item.FullPath
        }
    }
    $outputRows = @($outputRows)  # >>> FIX: 强制物化

    if ($JsonOutput -or $Output -ne "") {
        $jsonText = $outputRows | ConvertTo-Json -Depth 3
        if ($Output -ne "") { $jsonText | Out-File -LiteralPath $Output -Encoding UTF8; Write-Host "已保存：$Output" }
        else { Write-Host $jsonText }
    } else {
        Write-Host "`n==================== 结果 ===================="
        foreach($r in $outputRows) {
            Write-Host ("[{0,3}] {1,-12} | {2,-10} | {3,-16} | {4,-12} | {5}" -f $r.Rank,$r.Duration,$r.Size,$r.Bitrate,$r.Resolution,$r.Path)
        }
        Write-Host "==============================================="
        Write-Host "共 $($outputRows.Count) 条结果"
    }

    # ========= 非交互模式：自动保存 txt =========
    if ($UserQuery -and $UserQuery.Trim() -ne "") {
        $fnRaw = $UserQuery.Trim() `
            -replace '[<>:"/\\|?*]','_' `
            -replace '_+','_' `
            -replace '^\s+|\s+$',''
    } else {
        $fnRaw = "视频筛选结果"
    }
    
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $outName = "${fnRaw}_${ts}.txt"

    $lines = @()
    $lines += "非交互模式筛选结果"
    $lines += "查询：$($UserQuery.Trim())"
    $lines += "参数：Mode=$sortMode Recurse=$recurseParam Meta=$exportMeta BitrateThreshold=$bitrateThresholdKbps MinHeight=$MinHeight MaxHeight=$MaxHeight"
    $lines += "扫描根目录: $scanRoot"
    $lines += "时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += "总视频: $totalVideoCount | 筛选后: $($sorted.Length)"
    $lines += "--------------------------------------------------"
    
    if ($videoMode -and $exportMeta) {
        $lines += ("{0,-4}|{1,-12}|{2,-10}|{3,-16}|{4,-12}|{5}" -f "序号","时长","大小","码率","分辨率","完整路径")
        $lines += "--------------------------------------------------"
        $dataCount = 0
        for($i=0; $i -lt $sorted.Length; $i++){
            $item = $sorted[$i]
            $lines += ("[{0,-3}]|{1,-12}|{2,-10}|{3,-16}|{4,-12}|{5}" -f ($i+1),$item.DurationDisp,$item.FileSizeFriendly,$item.BitrateDisp,$item.ResDisp,$item.FullPath)
            $dataCount++
        }
        if ($dataCount -eq 0) { $lines += "[无符合条件的数据]" }
    } else {
        $lines += ("{0,-4}|{1,-10}|{2}" -f "序号","大小","完整路径")
        $lines += "--------------------------------------------------"
        $dataCount = 0
        for($i=0; $i -lt $sorted.Length; $i++){
            $item = $sorted[$i]
            $lines += ("[{0,-3}]|{1,-10}|{2}" -f ($i+1),$item.FileSizeFriendly,$item.FullPath)
            $dataCount++
        }
        if ($dataCount -eq 0) { $lines += "[无符合条件的数据]" }
    }
    
    $txtContent = $lines -join "`r`n"
    try {
        $txtContent | Out-File -LiteralPath $outName -Encoding UTF8
        Write-Host "`n✅ 已自动保存：$PWD\$outName" -ForegroundColor Green
    } catch {
        Write-Host "`n❌ 保存失败：$($_.Exception.Message)" -ForegroundColor Red
    }

    if ($JsonOutput) {
        $jsonName = "${fnRaw}_${ts}.json"
        $jsonData = @()
        foreach($item in $sorted){
            $jsonData += [PSCustomObject]@{
                序号 = ($jsonData.Count + 1)
                时长 = $item.DurationDisp
                大小 = $item.FileSizeFriendly
                码率 = $item.BitrateDisp
                分辨率 = $item.ResDisp
                路径 = $item.FullPath
            }
        }
        $jsonData | ConvertTo-Json -Depth 3 | Out-File -LiteralPath $jsonName -Encoding UTF8
        Write-Host "✅ JSON 已保存：$PWD\$jsonName" -ForegroundColor Green
    }

    Write-Host "`n非交互模式执行完毕。"
    exit 0
}

# ====================== 交互模式（完整嵌入） ======================

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
        Write-Host "`n⚠️ 捕获到Ctrl+C中断，正在清理本次脚本拉起的子进程..." -ForegroundColor Yellow
        Cleanup-TaskProcesses -TaskList $taskList
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
    if ($sortOpt -in "S","B","R","D") { $sortMode = $sortOpt }
    if ($sortMode -eq "S") {
        while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
        $metaOpt = Wait-KeyPress -Prompt "`n是否读取视频元数据(码率及分辨率) ，读取的话耗时较久？【N】不读取(默认) 【Y】读取"
        if ($metaOpt -eq "Y") { $exportMeta = $true }
    }
    elseif ($sortMode -in "B","R","D") {
        $exportMeta = $true
        Write-Host "`n【提示】B/R/D排序必须读取视频流元数据，耗时较长，请等待。"
        if (-not (Test-FfprobeAvailable)) {
            Write-Host "`n【错误】未找到ffprobe.exe" -ForegroundColor Red
            Write-Host "【Y】降级按文件大小排序，其他键退出"
            $dgKey = Wait-KeyPress -Prompt "请按键："
            if ($dgKey -eq "Y") { $sortMode = "S"; $exportMeta = $false; $isDowngrade = $true; Write-Host "✅降级成功，使用文件大小排序" }
            else { exit }
        }
    }
    if ($exportMeta -and (-not (Test-FfprobeAvailable))) {
        Write-Host "`n【错误】需要ffprobe读取视频元数据，未找到程序" -ForegroundColor Red
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown"); exit
    }
}

# >>> FIX: 交互模式 S 分支也支持码率阈值筛选
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
        if ([string]::IsNullOrWhiteSpace($inputThr) -or (-not [int]::TryParse($inputThr, [ref]$null))) { $bitrateThresholdKbps = 10000 }
        else { $bitrateThresholdKbps = [int]$inputThr }
        Write-Host "✅筛选条件：仅保留码率 >= $bitrateThresholdKbps kbps 的视频"
    } else {
        while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
        $inputCount = Read-Host "指定最大的输出统计条目数，直接回车默认100"
        if ([string]::IsNullOrWhiteSpace($inputCount) -or (-not [int]::TryParse($inputCount, [ref]$null))) { $topCount = 100 }
        else { $topCount = [Math]::Max(1, [int]$inputCount) }
    }
} elseif ($videoMode -and $sortMode -eq "S" -and $exportMeta) {
    while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
    $brModeOpt = Wait-KeyPress -Prompt "是否按码率阈值筛选？【N】不过滤(默认) 【T】按码率阈值筛选"
    if ($brModeOpt -eq "T") {
        $useBitrateFilter = $true
        while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
        $inputThr = Read-Host "输入最低码率阈值(kbps)，直接回车默认10000"
        if ([string]::IsNullOrWhiteSpace($inputThr) -or (-not [int]::TryParse($inputThr, [ref]$null))) { $bitrateThresholdKbps = 10000 }
        else { $bitrateThresholdKbps = [int]$inputThr }
        Write-Host "✅筛选条件：仅保留码率 >= $bitrateThresholdKbps kbps 的视频"
    }
    while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
    $inputCount = Read-Host "指定最大的输出统计条目数，直接回车默认100"
    if ([string]::IsNullOrWhiteSpace($inputCount) -or (-not [int]::TryParse($inputCount, [ref]$null))) { $topCount = 100 }
    else { $topCount = [Math]::Max(1, [int]$inputCount) }
} else {
    while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
    $inputCount = Read-Host "指定最大的输出统计条目数，直接回车默认100"
    if ([string]::IsNullOrWhiteSpace($inputCount) -or (-not [int]::TryParse($inputCount, [ref]$null))) { $topCount = 100 }
    else { $topCount = [Math]::Max(1, [int]$inputCount) }
}

if ($videoMode) {
    $filterDesc = "仅视频文件"
    if($sortMode -eq "B"){
        if($useBitrateFilter){ $sortText = "视频流码率降序，筛选>=$bitrateThresholdKbps kbps，同码率按文件大小降序" }
        else { $sortText = "视频流码率降序，同码率按文件大小降序" }
    }elseif($sortMode -eq "R"){ $sortText = "视频长边分辨率降序，同分辨率按文件大小降序" }
    elseif($sortMode -eq "D"){ $sortText = "视频时长降序，相同时长按文件大小降序" }
    else{
        if($useBitrateFilter){ $sortText = "文件大小降序，筛选码率>=$bitrateThresholdKbps kbps" }
        else{ $sortText = if($exportMeta){"文件大小降序，附带视频元数据"}else{"文件大小降序，不读取元数据"} }
    }
    if ($isDowngrade) { $sortText = "【降级】$sortText" }
} else {
    $filterDesc = "全部文件"; $sortText = "文件大小降序"
}
if($useBitrateFilter){ $fullDesc = "过滤：$filterDesc | 排序：$sortText | 筛选码率>=$bitrateThresholdKbps kbps" }
else { $fullDesc = "过滤：$filterDesc | 排序：$sortText | 取前$topCount" }

Write-Host "`n========================================"
Write-Host "开始扫描"
Write-Host $fullDesc
Write-Host "=======================================`n"

$scanRoot = $PWD.Path.Trim()
$blacklistFile = Join-Path $scanRoot "blacklist.txt"
if (Test-Path -LiteralPath $blacklistFile) {
    $scanBlackList = Get-Content -LiteralPath $blacklistFile -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" -and $_ -notmatch '^#' }
    Write-Host ">> 已加载扫描根目录下黑名单配置：$($scanBlackList -join ' | ')"
} else { $scanBlackList = @(); Write-Host ">> 未找到blacklist.txt，不启用目录黑名单过滤" }

$accessDeniedDirs = @(); $scanErrors = @()
$rawAll = Get-AllFilteredFiles -Path $scanRoot -DoRecurse $recurseParam -BlackList $scanBlackList -OutAccessDeniedDirs ([ref]$accessDeniedDirs) -OutScanErrors ([ref]$scanErrors)
if ($videoMode) { $rawFiles = $rawAll | Where-Object { $_.Extension -in $videoExts } } else { $rawFiles = $rawAll }
if ($rawFiles.Count -eq 0) { Write-Host "无匹配文件，按任意键退出"; $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown"); exit 0 }

$workList = @(); $metaFail = 0; $totalVideoCount = $rawFiles.Count; $durMap = @{}; $taskList = @()

if ($videoMode -and $exportMeta) {
    Write-Host "【批量读取视频流元数据（码率、分辨率）】`n"
    $tempDir = Join-Path $env:TEMP "video_meta_$(Get-Random)"
    try {
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        foreach ($f in $rawFiles) {
            while ((Get-Process ffprobe -ErrorAction SilentlyContinue | Measure-Object).Count -ge $maxConcurrent) { Start-Sleep -Milliseconds 40 }
            $outPath = Join-Path $tempDir "$($f.BaseName)_$($f.LastWriteTime.Ticks).txt"
            $arg = '/c ffprobe.exe -v error -select_streams v:0 -show_entries stream=bit_rate,avg_bit_rate,width,height -of json "' + $f.FullName + '" > "' + $outPath + '"'
            $psi = New-Object System.Diagnostics.ProcessStartInfo; $psi.FileName="cmd.exe"; $psi.Arguments=$arg; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
            $proc = [System.Diagnostics.Process]::Start($psi)
            $taskList += [PSCustomObject]@{ File=$f; Proc=$proc; OutFile=$outPath }
        }
        $processedCount = 0
        while ($taskList.Count -gt 0) {
            $running = @()
            foreach ($t in $taskList) {
                if (-not $t.Proc.HasExited) { $running += $t; continue }
                $processedCount++
                if($processedCount % $progressStep -eq 0){ Write-Host "已处理：$processedCount / $totalVideoCount" }
                $vi = [PSCustomObject]@{BitrateKbps=$null;BitrateSource=$null;Width=$null;Height=$null;LongEdge=$null;ExitCode=$t.Proc.ExitCode}
                if (Test-Path -LiteralPath $t.OutFile -PathType Leaf) {
                    try {
                        $rawTxt = [System.IO.File]::ReadAllText($t.OutFile)
                        $jsonObj = $rawTxt | ConvertFrom-Json
                        $vStream = $jsonObj.streams[0]
                        $w=[int]$vStream.width; $h=[int]$vStream.height
                        $bitrateBps = $null; $bitrateSource = "bitrate"
                        if (-not [string]::IsNullOrWhiteSpace($vStream.bit_rate)) { $bitrateBps = [long]$vStream.bit_rate; $bitrateSource = "bitrate" }
                        elseif (-not [string]::IsNullOrWhiteSpace($vStream.avg_bit_rate)) { $bitrateBps = [long]$vStream.avg_bit_rate; $bitrateSource = "avgbitrate" }
                        $vi = [PSCustomObject]@{
                            BitrateKbps=if($bitrateBps){[Math]::Round($bitrateBps/1000)}else{$null}
                            BitrateSource=$bitrateSource; Width=$w; Height=$h; LongEdge=[Math]::Max($w,$h); ExitCode=$t.Proc.ExitCode
                        }
                    } catch { $metaFail++ }
                } else { $metaFail++ }
                $brDisp = if($vi.BitrateKbps){"$($vi.BitrateKbps) kbps"}else{"[码率缺失]"}
                $resDisp = if($vi.Width){"$($vi.Width)x$($vi.Height)"}else{"-"}
                $workList += [PSCustomObject]@{
                    FullPath=$t.File.FullName.Trim(); FileSizeBytes=$t.File.Length; FileSizeFriendly=(Get-FriendlySize -Bytes $t.File.Length)
                    BitrateKbps=$vi.BitrateKbps; BitrateDisp=$brDisp; BitrateSource=$vi.BitrateSource
                    Width=$vi.Width; Height=$vi.Height; ResDisp=$resDisp; LongEdge=$vi.LongEdge; DurationSec=$null; DurationDisp="-"
                }
            }
            $taskList = $running; Start-Sleep -Milliseconds 20
        }
    }
    finally { Cleanup-TaskProcesses -TaskList $taskList; [GC]::Collect(); [GC]::WaitForPendingFinalizers(); if(Test-Path $tempDir){Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue} }

    # D模式全局预读时长
    if($sortMode -eq "D"){
        Write-Host "`n【D模式：全局预读取全部视频时长】`n"
        $durTempDir = Join-Path $env:TEMP "dur_batch_$(Get-Random)"; New-Item -ItemType Directory -Path $durTempDir | Out-Null
        $durTaskList=@()
        foreach ($f in $rawFiles) {
            while ((Get-Process ffprobe -ErrorAction SilentlyContinue | Measure-Object).Count -ge $maxConcurrent) { Start-Sleep -Milliseconds 80 }
            $outFile = Join-Path $durTempDir "$($f.BaseName)_$($f.LastWriteTime.Ticks).txt"
            $arg = '/c ffprobe.exe -v error -show_entries format=duration -of default:noprint_wrappers=1:nokey=1 "' + $f.FullName + '" > "' + $outFile + '"'
            $psi = New-Object System.Diagnostics.ProcessStartInfo; $psi.FileName="cmd.exe"; $psi.Arguments=$arg; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
            $proc = [System.Diagnostics.Process]::Start($psi)
            $durTaskList += [PSCustomObject]@{ File=$f; Proc=$proc; OutFile=$outFile }
        }
        while($durTaskList.Count -gt 0){ $run=@(); foreach($t in $durTaskList){ if(-not $t.Proc.HasExited){$run+=$t;continue}; $txt=[System.IO.File]::ReadAllText($t.OutFile); $sec=$null; if($txt -match '^\s*[\d\.]+'){[double]::TryParse($txt,[ref]$sec)|Out-Null}; $durMap[$t.File.FullName]=$sec }; $durTaskList=$run; Start-Sleep -Milliseconds 40 }
        Remove-Item $durTempDir -Recurse -Force -ErrorAction SilentlyContinue
        for($wi=0;$wi -lt $workList.Count;$wi++){ $item=$workList[$wi]; $s=$durMap[$item.FullPath]; $item.DurationSec=$s; $item.DurationDisp=(Get-FriendlyDuration $s) }
    }
} else {
    foreach ($f in $rawFiles) {
        $workList += [PSCustomObject]@{
            FullPath=$f.FullName.Trim(); FileSizeBytes=$f.Length; FileSizeFriendly=(Get-FriendlySize -Bytes $f.Length)
            BitrateKbps=$null; BitrateDisp="-"; Width=$null; Height=$null; ResDisp="-"; LongEdge=$null; DurationSec=$null; DurationDisp="-"
        }
    }
}

# ---- 排序（交互模式） ----
$validBitrateCount = 0
$truncateWarnMsg = $null

if ($videoMode -and $sortMode -eq "B") {
    $sortedAll = @($workList | Sort-Object @{E={if($_.BitrateKbps -eq $null){-1}else{$_.BitrateKbps}};D=$true}, @{E={$_.FileSizeBytes};D=$true})
    if($useBitrateFilter){
        $sorted = @($sortedAll | Where-Object { $_.BitrateKbps -ne $null -and $_.BitrateKbps -ge $bitrateThresholdKbps })
        $validBitrateCount = $sorted.Count
    }else{
        $sorted = @($sortedAll | Select-Object -First $topCount)
    }
}
elseif ($videoMode -and $sortMode -eq "R") {
    $sorted = @($workList | Sort-Object @{E={if($_.LongEdge -eq $null){-1}else{$_.LongEdge}};D=$true}, @{E={$_.FileSizeBytes};D=$true} | Select-Object -First $topCount)
}
elseif ($videoMode -and $sortMode -eq "D") {
    $sorted = @($workList | Sort-Object @{E={if($_.DurationSec -ne $null){$_.DurationSec}else{-1}};D=$true}, @{E={$_.FileSizeBytes};D=$true} | Select-Object -First $topCount)
}
else {
    # >>> FIX: S模式强制物化 + 码率筛选
    $sortedAll = @($workList | Sort-Object FileSizeBytes -Descending)
    if ($useBitrateFilter) {
        $sortedAll = @($sortedAll | Where-Object { $_.BitrateKbps -ne $null -and $_.BitrateKbps -ge $bitrateThresholdKbps })
        $validBitrateCount = $sortedAll.Count
        Write-Host "码率筛选：从 $($workList.Count) 条中筛选 >= $bitrateThresholdKbps kbps，剩余 $validBitrateCount 条" -ForegroundColor Cyan
    }
    $sorted = @($sortedAll | Select-Object -First $topCount)
}

$sorted = @($sorted)  # >>> FIX: 最终保险

# ---- 预览 ----
Write-Host "`n==================== 预览 ===================="
$outputRows = @()
for($i=0; $i -lt $sorted.Length; $i++){
    $item = $sorted[$i]
    $rank = $i+1
    $outputRows += [PSCustomObject]@{
        RankOrig=$rank; FileSizeFriendly=$item.FileSizeFriendly; BitrateDisp=$item.BitrateDisp
        ResDisp=$item.ResDisp; FullPath=$item.FullPath; DurationSec=$item.DurationSec; DurationDisp=$item.DurationDisp
    }
    if ($videoMode -and $exportMeta) {
        Write-Host ("[{0,3}] {1,-12} | {2,-10} | {3,-16} | {4,-12} | {5}" -f $rank,$item.DurationDisp,$item.FileSizeFriendly,$item.BitrateDisp,$item.ResDisp,$item.FullPath)
    } else {
        Write-Host ("[{0,3}] {1,-10} {2}" -f $rank,$item.FileSizeFriendly,$item.FullPath)
    }
}
$outputRows = @($outputRows)  # >>> FIX: 强制物化

Write-Host "======================================================"
Write-Host $fullDesc
Write-Host "总扫描视频数量：$totalVideoCount"
if($useBitrateFilter){ Write-Host "满足码率阈值条目数：$validBitrateCount" }
if ($videoMode -and $exportMeta) { Write-Host "元数据读取失败数量：$metaFail" }
if($truncateWarnMsg){ Write-Host $truncateWarnMsg }
if($accessDeniedDirs.Count -gt 0){ Write-Host "无法访问目录共 $($accessDeniedDirs.Count) 个" }

# ---- 后置时长扫描 ----
$doScanDuration = $false; $reSortKey = $null; $mergedList = $null
if($sortMode -ne "D"){
    $durScanKey = Wait-KeyPress -Prompt "`n是否对本次结果集扫描视频时长？【Y=扫描；N=跳过(默认)】"
    if ($durScanKey -eq "Y" -and (Test-FfprobeAvailable)) {
        $doScanDuration = $true
        Write-Host "`n===== 开始扫描本次结果集的视频时长 =====" -ForegroundColor Cyan
        $durTempDir = Join-Path $env:TEMP "dur_postscan_$(Get-Random)"; New-Item -ItemType Directory -Path $durTempDir | Out-Null
        $durTaskList = @()
        foreach ($rowItem in $sorted) {
            $outFile = Join-Path $durTempDir "$(Get-Random).txt"
            $arg = '/c ffprobe.exe -v error -show_entries format=duration -of default:noprint_wrappers=1:nokey=1 "' + $rowItem.FullPath + '" > "' + $outFile + '"'
            $psi = New-Object System.Diagnostics.ProcessStartInfo; $psi.FileName="cmd.exe"; $psi.Arguments=$arg; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
            $proc = [System.Diagnostics.Process]::Start($psi)
            $durTaskList += [PSCustomObject]@{ FullPath=$rowItem.FullPath; Proc=$proc; OutFile=$outFile; OrigItem=$rowItem }
        }
        $durResultList = @()
        while ($durTaskList.Count -gt 0) {
            $runDur = @()
            foreach($dt in $durTaskList){ if(-not $dt.Proc.HasExited){$runDur+=$dt;continue}; $durSec=$null
                if(Test-Path -LiteralPath $dt.OutFile -PathType Leaf){ $c=[System.IO.File]::ReadAllText($dt.OutFile); if($c -match '^\s*[\d\.]+'){[double]::TryParse($c,[ref]$durSec)|Out-Null} }
                $dispTime = Get-FriendlyDuration $durSec
                $durResultList += [PSCustomObject]@{ OrigItem=$dt.OrigItem; DurationSec=$durSec; DurationDisp=$dispTime }
            }
            $durTaskList = $runDur; Start-Sleep -Milliseconds 20
        }
        Remove-Item $durTempDir -Recurse -Force -ErrorAction SilentlyContinue
        $mergedList = @()
        foreach($dr in $durResultList){ $src=$dr.OrigItem; $mergedList += [PSCustomObject]@{ RankOrig=0; DurationSec=$dr.DurationSec; DurationDisp=$dr.DurationDisp; FileSizeFriendly=$src.FileSizeFriendly; BitrateDisp=$src.BitrateDisp; ResDisp=$src.ResDisp; FullPath=$src.FullPath } }
        $outputRows = @($mergedList)
        $reSortKey = Wait-KeyPress -Prompt "`n保存选择：【N】沿用原有排序(默认)；【Y】按时长降序重新排序"
        if($reSortKey -eq "Y"){ $outputRows = @($outputRows | Sort-Object @{E={if($_.DurationSec){$_.DurationSec}else{-1}};D=$true}) }
    }
}

# ---- 保存 txt ----
$saveKey = Wait-KeyPress -Prompt "`n保存列表（txt格式）到当前文件夹？【Y=保存（默认），N=跳过】"
if ($saveKey -ne "N") {
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $fnRaw = $fullDesc -replace '[<>:"/\|?*]','_' -replace ' +',' '
    $outName = "本文件夹内文件排序统计_${fnRaw}_${ts}.txt"
    $lines = @()
    $lines += "全能文件排序统计结果"; $lines += $fullDesc
    if($doScanDuration){ $lines += "# 后置扫描：已附加视频时长列" }
    $lines += "#扫描根目录: $scanRoot"
    $lines += "#扫描时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += "#总扫描视频数量:$totalVideoCount"
    if($useBitrateFilter){ $lines += "#满足码率阈值条目数:$validBitrateCount" }
    $lines += "#--------------------------------------------------"
    if($videoMode -and $exportMeta){
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
} else { Write-Host "`n❌跳过保存" -ForegroundColor Yellow }

Write-Host "`n任务完成，按任意键关闭窗口"
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
