<#
time_add_only.ps1
规则：
1. 仅使用视频时长作为新文件名，丢弃原文件名
2. 预览阶段预计算重名冲突，冲突追加紧贴序号不加空格：00m09s2.mp4
3. 原有规则：如果文件主体完全等于时间格式(XXhXXmXXs/XXmXXs)直接SKIP
4. 文件名任意位置存在时间标记，三选一策略：n全重处理 / s逐文件选 / 其他跳过
5. 简易并发ffprobe、美化预览表格、y/s操作、u撤销、导出KB映射txt
6. Emby配图/nfo跟随：默认关闭，按1开启；子选项控制nfo<title>/<sorttitle>改写
7. 严谨正则，不误伤纯数字文件名
8. 单键无回车交互，与begin/end版完全对齐
#>

function Get-SingleKey {
    param([string]$Prompt)
    Write-Host $Prompt
    $k = [Console]::ReadKey($true)
    return $k.KeyChar.ToString().ToLower()
}

function Wait-AnyKey {
    param([string]$Prompt="`n按任意键继续...")
    Write-Host $Prompt
    [Console]::ReadKey($true) | Out-Null
}

# ========== Emby配图跟随选择（默认关闭） ==========
$embyFollow = $false
$enableNfoTagEdit = $false

Write-Host "`n===== Emby附属文件模式（可选） =====" -ForegroundColor Cyan
Write-Host "【1】开启 Emby 配图跟随（图片/nfo 跟随视频改名）"
Write-Host "【按其他任意键】关闭配图跟随（仅处理视频本体）— 推荐" -ForegroundColor Green
$sel = Get-SingleKey "请选择（按 1 开启，其他键跳过）："
Write-Host ""

if ($sel -eq '1') {
    $embyFollow = $true
    while ($true) {
        Write-Host "`n----- NFO处理子选项 -----" -ForegroundColor Cyan
        Write-Host "【1】配图跟随 + 强制改写NFO <title>/<sorttitle>为视频新基名 ⚠文本修改无法撤销"
        Write-Host "【2】配图跟随 + 仅重命名NFO文件，不修改NFO内部内容"
        Write-Host "【按其他任意键】返回上级（取消配图跟随）" -ForegroundColor Gray
        $nfoSel = Get-SingleKey "请按数字键 1 或 2 选择NFO策略："
        Write-Host ""
        if ($nfoSel -eq '1') {
            $enableNfoTagEdit = $true
            Write-Host "✅ 已选择：开启配图跟随 + 强制改写NFO标签（⚠nfo文本修改无法u撤销，仅文件名可撤销）" -ForegroundColor Green
            break
        }
        elseif ($nfoSel -eq '2') {
            $enableNfoTagEdit = $false
            Write-Host "✅ 已选择：开启配图跟随 + 仅NFO改名，不改动NFO内部XML" -ForegroundColor Green
            break
        }
        else {
            $embyFollow = $false
            Write-Host "❌ 已取消配图跟随，仅处理视频本体" -ForegroundColor Yellow
            break
        }
    }
}
else {
    Write-Host "✅ 已选择：关闭Emby配图跟随模式（仅处理视频）" -ForegroundColor Yellow
}

# ========== 配置 ==========
$maxConcurrent = 8
$videoExts = @(
    'mp4','MP4','Mp4','mov','MOV','Mov','mkv','MKV','Mkv',
    'avi','AVI','Avi','flv','FLV','Flv','wmv','WMV','Wmv',
    'm4v','M4V','M4v','ts','TS','Ts','mpg','MPG','Mpg',
    'mpeg','MPEG','Mpeg','f4v','F4V','F4v','m2ts','M2TS','M2ts',
    'mts','MTS','Mts'
)
$artExts = @('jpg','jpeg','png','webp','nfo','JPG','JPEG','PNG','WEBP','NFO')
# 严谨正则：不误伤纯数字文件名
$timeRegex = '(?<!\d)((\d{1,2}h)?\d{1,2}m\d{1,2}s)(?!\d)'
$pureTimeNameRegex = '^(?<!\d)((\d{1,2}h)?\d{1,2}m\d{1,2}s)(?!\d)$'

$files = Get-ChildItem -File . | Where-Object { $_.Extension.TrimStart('.') -in $videoExts }
if (-not $files) {
    Write-Host "`n[!] 当前目录没有找到支持的视频文件。" -ForegroundColor Yellow
    Wait-AnyKey
    exit 0
}

$totalCount = $files.Count
$tempDir = Join-Path $env:TEMP "tao_tmp_$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir | Out-Null
$taskList   = @()
$resultList = @()
$undoList   = @()
$nfoModifyLog = @()
$videoBaseMap = @{}

try {
    # ========== 并发 ffprobe ==========
    foreach ($f in $files) {
        while ((Get-Process ffprobe -ErrorAction SilentlyContinue | Measure-Object).Count -ge $maxConcurrent) {
            Start-Sleep -Milliseconds 80
        }
        $outFile = Join-Path $tempDir "$($f.BaseName)_$($f.LastWriteTime.Ticks).txt"
        $arg = '/c ffprobe.exe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "' + $f.FullName + '" > "' + $outFile + '"'
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "cmd.exe"
        $psi.Arguments = $arg
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $taskList += [PSCustomObject]@{ File = $f; Process = $proc; OutputPath = $outFile }
    }

    Write-Host "`n===== 正在并发读取视频元信息 =====" -ForegroundColor Cyan
    $doneCount = 0
    while ($taskList.Count -gt 0) {
        $running = @()
        foreach ($t in $taskList) {
            if (-not $t.Process.HasExited) { $running += $t; continue }
            $durSec = $null
            if (Test-Path $t.OutputPath) {
                $content = Get-Content $t.OutputPath -Raw
                if ($content -match '^\s*[\d\.]+') {
                    try { $durSec = [double]$content } catch {}
                }
            }
            $resultList += [PSCustomObject]@{ FullName = $t.File.FullName; DurationSec = $durSec }
            $doneCount++
            $pct = [math]::Round(($doneCount / $totalCount) * 100, 0)
            $shortName = $t.File.Name
            if ($null -ne $durSec -and $durSec -gt 0) {
                $totalSec = [int]$durSec
                $h = [Math]::Floor($totalSec / 3600)
                $rem = $totalSec % 3600
                $m = [Math]::Floor($rem / 60)
                $s = $rem % 60
                $hh = if ($h -lt 10) { "0$h" } else { "$h" }
                $mm = if ($m -lt 10) { "0$m" } else { "$m" }
                $ss = if ($s -lt 10) { "0$s" } else { "$s" }
                if ($h -gt 0) { $dispTime = "$hh`h${mm}m${ss}s" } else { $dispTime = "${mm}m${ss}s" }
                $color = "Green"
            }
            else { $dispTime = "ERROR"; $color = "Red" }
            Write-Host ("[{0,3}/{1}] {2,3}% | " -f $doneCount, $totalCount, $pct) -NoNewline
            Write-Host ("{0,-8}" -f $dispTime) -ForegroundColor $color -NoNewline
            Write-Host " | $shortName"
        }
        $taskList = $running
        Start-Sleep -Milliseconds 60
    }
    Write-Host "`n[✓] 元信息读取全部完成。`n" -ForegroundColor Cyan

    # ========== 已标记文件策略（三选一，与begin/end对齐） ==========
    $hasMarkFiles = $files | Where-Object { $_.BaseName -match $timeRegex }
    $forceRewriteAll = $false
    $perFileSelect = $false

    if ($hasMarkFiles.Count -gt 0) {
        Write-Host "[!] 检测到 $($hasMarkFiles.Count) 个文件文件名已包含时间标记。" -ForegroundColor Yellow
        Write-Host "[n] 全部重处理：移除旧时间标记，重新追加新时间" -ForegroundColor Yellow
        Write-Host "[s] 逐个确认：对每个已标记文件询问是否重处理，不含时间标记文件直接加标记" -ForegroundColor Yellow
        Write-Host "[其他键] 推荐：全部跳过（仅处理未含时间标记的文件）" -ForegroundColor Green
        $inp = Get-SingleKey "请选择："
        Write-Host ""
        if ($inp -eq 'n') {
            $forceRewriteAll = $true
            Write-Host "☑ 策略：全部强制重处理（全刷新时间标记）" -ForegroundColor Yellow
        }
        elseif ($inp -eq 's') {
            $perFileSelect = $true
            Write-Host "☑ 策略：逐文件询问重处理" -ForegroundColor Yellow
        }
        else {
            Write-Host "☑ 策略：有时间标记的全部跳过，仅处理未含时间标记的文件" -ForegroundColor Green
        }
    }

    # ========== 生成预览表 ==========
    $rawList = @()
    foreach ($f in $files) {
        $res = $resultList | Where-Object { $_.FullName -eq $f.FullName }
        $baseName = $f.BaseName
        $ext = $f.Extension
        $origDisp = $f.Name
        $origBase = $f.BaseName
        $fileSizeKB = [math]::Round($f.Length / 1KB, 2)

        # 规则1：basename本身就是纯时间格式，直接SKIP
        if ($baseName -match $pureTimeNameRegex) {
            $rawList += [PSCustomObject]@{
                FileObj=$f; TimeToken=$null; Status='[SKIP]'; OrigDisp=$origDisp
                BaseTarget=$null; Ext=$ext; FinalName=$origDisp; FileSizeKB=$fileSizeKB
                OrigBase=$origBase; NewBase=$null; NfoNewTitle=$null
            }
            continue
        }

        # 规则2：文件名任意位置有时间标记 → 三选一分支
        $hasTimeMark = $baseName -match $timeRegex
        if ($hasTimeMark) {
            if ($forceRewriteAll) {
                # 移除旧时间标记，继续往下走重新生成
                $baseName = $baseName -replace $timeRegex, ''
                $baseName = $baseName.TrimEnd()
                # 不continue，继续计算时长
            }
            elseif ($perFileSelect) {
                Write-Host "`n检测到已标记文件：$($f.Name)" -ForegroundColor Yellow
                $sub = Get-SingleKey "【r】重处理（替换旧时间）【k】跳过此文件"
                if ($sub -eq 'r') {
                    $baseName = $baseName -replace $timeRegex, ''
                    $baseName = $baseName.TrimEnd()
                    # 不continue，继续计算时长
                }
                else {
                    $rawList += [PSCustomObject]@{
                        FileObj=$f; TimeToken=$null; Status='[SKIP]'; OrigDisp=$origDisp
                        BaseTarget=$null; Ext=$ext; FinalName=$origDisp; FileSizeKB=$fileSizeKB
                        OrigBase=$origBase; NewBase=$null; NfoNewTitle=$null
                    }
                    continue
                }
            }
            else {
                # 默认跳过
                $rawList += [PSCustomObject]@{
                    FileObj=$f; TimeToken=$null; Status='[SKIP]'; OrigDisp=$origDisp
                    BaseTarget=$null; Ext=$ext; FinalName=$origDisp; FileSizeKB=$fileSizeKB
                    OrigBase=$origBase; NewBase=$null; NfoNewTitle=$null
                }
                continue
            }
        }

        # 时长读取失败 → SKIP
        $durSec = $res.DurationSec
        if ($null -eq $durSec -or $durSec -le 0) {
            $rawList += [PSCustomObject]@{
                FileObj=$f; TimeToken=$null; Status='[SKIP]'; OrigDisp=$origDisp
                BaseTarget=$null; Ext=$ext; FinalName=$origDisp; FileSizeKB=$fileSizeKB
                OrigBase=$origBase; NewBase=$null; NfoNewTitle=$null
            }
            continue
        }

        # 计算时长字符串
        $totalSec = [int]$durSec
        $h = [Math]::Floor($totalSec / 3600)
        $rem = $totalSec % 3600
        $m = [Math]::Floor($rem / 60)
        $s = $rem % 60
        $hh = if ($h -lt 10) { "0$h" } else { "$h" }
        $mm = if ($m -lt 10) { "0$m" } else { "$m" }
        $ss = if ($s -lt 10) { "0$s" } else { "$s" }
        if ($h -gt 0) { $timeStr = "$hh`h${mm}m${ss}s" } else { $timeStr = "${mm}m${ss}s" }

        $rawList += [PSCustomObject]@{
            FileObj=$f; TimeToken=$timeStr; Status='[RENAME]'; OrigDisp=$origDisp
            BaseTarget=$timeStr; Ext=$ext; FinalName=$null; FileSizeKB=$fileSizeKB
            OrigBase=$origBase; NewBase=$timeStr; NfoNewTitle=$null
        }
    }

    # 按原始文件名升序，预计算冲突文件名
    $previewList = $rawList | Sort-Object OrigDisp
    $usedNames = New-Object System.Collections.Generic.HashSet[string]
    foreach ($item in $previewList) {
        if ($item.Status -ne '[RENAME]') { continue }
        $base = $item.BaseTarget
        $ext = $item.Ext
        $candidate = "$base$ext"
        $counter = 2
        while ($true) {
            $existsDisk = Test-Path -LiteralPath (Join-Path $item.FileObj.Directory.FullName $candidate)
            $existsBatch = $usedNames.Contains($candidate)
            if ((-not $existsDisk) -and (-not $existsBatch)) { break }
            $candidate = "$base$counter$ext"
            $counter++
        }
        $null = $usedNames.Add($candidate)
        $item.FinalName = $candidate
        $item.NewBase = $candidate.Substring(0, $candidate.Length - $ext.Length)
        $videoBaseMap[$item.OrigBase] = $item.NewBase
    }

    # ========== 生成Emby配图/nfo RENAME-ART预览条目 ==========
    if ($embyFollow) {
        $allFileObjs = Get-ChildItem -File .
        foreach ($origVidBase in $videoBaseMap.Keys) {
            $targetNewBase = $videoBaseMap[$origVidBase]
            $artPatterns = @(
                "^$([regex]::Escape($origVidBase))$",
                "^$([regex]::Escape($origVidBase))\-poster$",
                "^$([regex]::Escape($origVidBase))\-fanart$",
                "^$([regex]::Escape($origVidBase))\-thumb$"
            )
            foreach ($f in $allFileObjs) {
                $isMatchPattern = $false
                foreach ($p in $artPatterns) { if ($f.BaseName -match $p) { $isMatchPattern = $true; break } }
                if (-not $isMatchPattern) { continue }
                if ($f.Extension.TrimStart('.') -notin $artExts) { continue }
                $fsKB = [math]::Round($f.Length / 1KB, 2)
                $newArtBase = $f.BaseName.Replace($origVidBase, $targetNewBase)
                $newArtName = $newArtBase + $f.Extension
                $nfoNewTitle = $null
                if ($enableNfoTagEdit -and $f.Extension.ToLower() -eq ".nfo" -and $f.BaseName -eq $origVidBase) {
                    $nfoNewTitle = $targetNewBase
                }
                $previewList += [PSCustomObject]@{
                    FileObj=$f; TimeToken=$null; Status='[RENAME-ART]'; OrigDisp=$f.Name
                    BaseTarget=$null; Ext=$f.Extension; FinalName=$newArtName; FileSizeKB=$fsKB
                    OrigBase=$f.BaseName; NewBase=$newArtBase; NfoNewTitle=$nfoNewTitle
                }
            }
        }
    }

    # ========== 预览表格 ==========
    Write-Host "`n==================== 重命名预览(time_add_only) ====================" -ForegroundColor Cyan
    if ($embyFollow) {
        if ($enableNfoTagEdit) { $tip = "Emby配图跟随：✅开启 | NFO策略：强制改写<title>/<sorttitle> ⚠文本不可撤销" }
        else { $tip = "Emby配图跟随：✅开启 | NFO策略：仅改名，不修改内部XML" }
    }
    else { $tip = "Emby配图跟随：❌关闭（默认）" }
    Write-Host "[$tip]" -ForegroundColor Cyan
    Write-Host ("{0,-4} {1,-30} {2,-30} {3}" -f "序号","原文件名","新文件名","操作")
    Write-Host "-------------------------------------------------------------------------"
    $renameVideoTotal = ($previewList | Where-Object { $_.Status -eq '[RENAME]' }).Count
    $renameArtTotal   = ($previewList | Where-Object { $_.Status -eq '[RENAME-ART]' }).Count
    $skipTotal = ($previewList | Where-Object { $_.Status -eq '[SKIP]' }).Count
    $idx = 1
    foreach ($item in $previewList) {
        Write-Host ("{0,-4}" -f $idx) -NoNewline
        Write-Host ("{0,-30}" -f $item.OrigDisp) -NoNewline
        if ($item.Status -eq '[RENAME]') {
            Write-Host ("{0,-30}" -f $item.FinalName) -ForegroundColor Yellow -NoNewline
            Write-Host "[RENAME]" -ForegroundColor Green
        }
        elseif ($item.Status -eq '[RENAME-ART]') {
            Write-Host ("{0,-30}" -f $item.FinalName) -ForegroundColor Yellow -NoNewline
            $hint = if ($null -ne $item.NfoNewTitle) { " | NFO-TAGS(OVERWRITE)" } else { "" }
            Write-Host "[RENAME-ART]$hint" -ForegroundColor DarkGreen
        }
        else {
            Write-Host ("{0,-30}" -f $item.FinalName) -ForegroundColor Gray -NoNewline
            Write-Host "[SKIP]" -ForegroundColor Gray
        }
        $idx++
    }
    Write-Host "-------------------------------------------------------------------------"
    if ($embyFollow) {
        Write-Host ("视频改名：{0}｜配图/nfo改名：{1}｜跳过：{2}" -f $renameVideoTotal, $renameArtTotal, $skipTotal) -ForegroundColor Cyan
    }
    else {
        Write-Host ("视频改名：{0}｜跳过：{1}" -f $renameVideoTotal, $skipTotal) -ForegroundColor Cyan
    }
    Write-Host "=========================================================================`n" -ForegroundColor Cyan

    $totalNeedRename = $renameVideoTotal + $renameArtTotal
    if ($totalNeedRename -eq 0) {
        Write-Host "`n[!] 没有需要执行改名的文件。" -ForegroundColor Yellow
        Wait-AnyKey
        exit 0
    }

    # ========== ★ 最后一次确认（y执行 / s导出 / 其他退出） ==========
    $timeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $opt = Get-SingleKey "操作选择：【y】执行改名；【s】仅生成新旧映射txt（不改名）；其他按键退出"
    Write-Host ""

    if ($opt -eq 's') {
        $backupFile = Join-Path $PWD.Path "rename_backup_$timeStamp.txt"
        $lines = @()
        $lines += "# 备份时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $lines += "# 模式：time_add_only（仅时长命名）"
        $lines += "# Emby配图跟随：$embyFollow | NFO改写：$enableNfoTagEdit"
        $lines += "# 原名`t新名`t文件大小(KB)"
        foreach ($item in $previewList) {
            if ($item.Status -in '[RENAME]','[RENAME-ART]') {
                $lines += "$($item.OrigDisp)`t$($item.FinalName)`t$($item.FileSizeKB)"
                if ($enableNfoTagEdit -and $null -ne $item.NfoNewTitle) {
                    $lines += "# NFO-TAG-OVERWRITE：<title>/<sorttitle> → $($item.NfoNewTitle)"
                }
            }
        }
        $lines | Out-File -FilePath $backupFile -Encoding utf8
        Write-Host "`n✅ 已生成映射文件（未执行改名）：$backupFile" -ForegroundColor Green
        Wait-AnyKey
        exit 0
    }
    elseif ($opt -ne 'y') {
        Write-Host "[!] 已取消操作，退出。" -ForegroundColor Yellow
        Wait-AnyKey
        exit 0
    }

    # ========== 执行改名 ==========
    Write-Host "`n===== 开始执行改名 =====" -ForegroundColor Cyan
    foreach ($item in $previewList | Where-Object { $_.Status -in '[RENAME]','[RENAME-ART]' }) {
        $srcFile = $item.FileObj
        $destPath = Join-Path $srcFile.Directory.FullName $item.FinalName

        # NFO内部标签改写
        if ($enableNfoTagEdit -and $null -ne $item.NfoNewTitle) {
            try {
                $nfoText = [System.IO.File]::ReadAllText($srcFile.FullName, [System.Text.Encoding]::UTF8)
                $origTitleVal = $null; $origSortVal = $null
                if ($nfoText -match '<title\b[^>]*>(.*?)</title>') { $origTitleVal = $matches[1] }
                if ($nfoText -match '<sorttitle\b[^>]*>(.*?)</sorttitle>') { $origSortVal = $matches[1] }
                if ($nfoText -match '<title>.*</title>') {
                    $nfoText = $nfoText -replace '<title>.*</title>', "<title>$($item.NfoNewTitle)</title>"
                }
                if ($nfoText -match '<sorttitle>.*</sorttitle>') {
                    $nfoText = $nfoText -replace '<sorttitle>.*</sorttitle>', "<sorttitle>$($item.NfoNewTitle)</sorttitle>"
                }
                [System.IO.File]::WriteAllText($srcFile.FullName, $nfoText, [System.Text.Encoding]::UTF8)
                $nfoModifyLog += [PSCustomObject]@{
                    NfoFile=$item.OrigDisp; OldTitle=$origTitleVal; NewTitle=$item.NfoNewTitle
                    OldSortTitle=$origSortVal; NewSortTitle=$item.NfoNewTitle
                }
                Write-Host "`t[NFO标签覆盖 OK] title/sorttitle → $($item.NfoNewTitle)" -ForegroundColor DarkGreen
            }
            catch { Write-Host "`t[NFO标签更新失败] $_" -ForegroundColor Red }
        }

        try {
            Rename-Item -LiteralPath $srcFile.FullName -NewName $item.FinalName -Force -ErrorAction Stop
            Write-Host "原名：" -ForegroundColor Gray -NoNewline
            Write-Host "$($item.OrigDisp)" -NoNewline
            Write-Host " → " -ForegroundColor Gray -NoNewline
            Write-Host "$($item.FinalName) " -ForegroundColor Yellow -NoNewline
            Write-Host "[OK]" -ForegroundColor Green
            $undoList += [PSCustomObject]@{
                AfterPath=$destPath; BeforePath=$srcFile.FullName
                OldName=$item.OrigDisp; NewName=$item.FinalName; FileSizeKB=$item.FileSizeKB
            }
        }
        catch {
            Write-Host "原名：" -ForegroundColor Gray -NoNewline
            Write-Host "$($item.OrigDisp)" -NoNewline
            Write-Host " → " -ForegroundColor Gray -NoNewline
            Write-Host "$($item.FinalName) " -ForegroundColor Yellow -NoNewline
            Write-Host "[ERROR] $_" -ForegroundColor Red
        }
    }
    Write-Host "`n[✓] 全部操作完成。" -ForegroundColor Cyan

    # ========== 完成后菜单（u撤销 / s保存映射） ==========
    if ($undoList.Count -gt 0) {
        $tipUndo = if ($embyFollow -and $enableNfoTagEdit) { "（⚠️nfo内部文本被覆盖无法撤销，仅文件名可u还原）" } else { "" }
        Write-Host "`n===== 后续操作选项 =====" -ForegroundColor Cyan
        $optInput = Get-SingleKey "按【u】撤销本次改名$tipUndo；按【s】保存映射txt；其他按键直接退出"
        $timeStamp2 = Get-Date -Format "yyyyMMdd_HHmmss"

        if ($optInput -eq "u") {
            if ($embyFollow -and $enableNfoTagEdit) {
                Write-Host "`n⚠️ 开始撤销，仅还原文件名！nfo内部title/sorttitle文本不会复原！" -ForegroundColor Yellow
            }
            else { Write-Host "`n⚠️ 开始撤销，还原文件名..." -ForegroundColor Yellow }
            $failUndo = 0
            foreach ($uItem in $undoList) {
                if (Test-Path -LiteralPath $uItem.AfterPath) {
                    try {
                        Rename-Item -LiteralPath $uItem.AfterPath -NewName $uItem.OldName -ErrorAction Stop
                        Write-Host "[撤销OK] $($uItem.NewName) → $($uItem.OldName)" -ForegroundColor Green
                    }
                    catch { Write-Host "[撤销失败] $($uItem.AfterPath) : $_" -ForegroundColor Red; $failUndo++ }
                }
                else { Write-Host "[撤销跳过] 文件不存在：$($uItem.AfterPath)" -ForegroundColor Red; $failUndo++ }
            }
            Write-Host "`n撤销完成，成功：$($undoList.Count - $failUndo) ｜失败：$failUndo" -ForegroundColor Cyan
        }
        elseif ($optInput -eq "s") {
            $backupFile = Join-Path $PWD.Path "rename_backup_$timeStamp2.txt"
            $lines = @()
            $lines += "# 备份时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $lines += "# Emby配图跟随：$embyFollow | NFO改写：$enableNfoTagEdit"
            $lines += "# 原名`t新名`t文件大小(KB)"
            foreach ($uItem in $undoList) { $lines += "$($uItem.OldName)`t$($uItem.NewName)`t$($uItem.FileSizeKB)" }
            if ($enableNfoTagEdit -and $nfoModifyLog.Count -gt 0) {
                $lines += "`n# NFO内部标签覆盖记录（文本无法撤销恢复）"
                foreach ($log in $nfoModifyLog) { $lines += "# File:$($log.NfoFile) | oldTitle:$($log.OldTitle) | newTitle:$($log.NewTitle)" }
            }
            $lines | Out-File -FilePath $backupFile -Encoding utf8
            Write-Host "`n✅ 已保存映射文件：$backupFile" -ForegroundColor Green
        }
        else { Write-Host "`n退出脚本。" -ForegroundColor Gray }
    }
}
finally {
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
}

Wait-AnyKey "`n按任意键返回菜单..."
