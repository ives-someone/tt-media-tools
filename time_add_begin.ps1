# 时间前置版 (time_add_begin.ps1)
# 功能：获取视频时长，将时间标记前置（如：01h30m45s 原文件名）
# 逻辑：与 end 版完全对齐，仅时间拼接位置不同

function Get-SingleKey {
    param([string]$Prompt)
    Write-Host $Prompt -NoNewline
    $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host ""
    return $key.Character
}

function Wait-AnyKey {
    param([string]$Prompt)
    Write-Host $Prompt -NoNewline
    $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
    Write-Host ""
}

# ========== 初始化 ==========
$timeRegex = '(?i)(?:^|\s)((?:[0-9]+h)?[0-9]+m[0-9]+s)(?:\s|$)'
$undoList = @()
$nfoModifyLog = @()
$videoBaseMap = @{}
$idx = 1
$previewTable = @()

# 临时目录（用于 ffprobe）
$tempDir = Join-Path $env:TEMP "time_add_temp_$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

try {
    # ========== 获取文件 ==========
    $files = Get-ChildItem -File . | Where-Object { $_.Extension -match '\.(mp4|mkv|avi|ts|m2ts|wmv|flv|mov)$' }
    if ($files.Count -eq 0) {
        Write-Host "[!] 当前目录无视频文件。" -ForegroundColor Yellow
        Wait-AnyKey "按任意键退出..."
        exit
    }

    # ========== Emby 跟随选项 ==========
    Write-Host "===== 时间标记脚本（前置版） =====" -ForegroundColor Cyan
    Write-Host "[1] 开启 Emby 配图/nfo 跟随（默认关）" -ForegroundColor Yellow
    Write-Host "[其他键] 仅处理视频文件名（推荐）" -ForegroundColor Green
    $embyInput = Get-SingleKey "请选择："
    $embyFollow = ($embyInput -eq '1')
    if ($embyFollow) {
        Write-Host "☑ Emby配图/nfo跟随已开启" -ForegroundColor Yellow
        $enableNfoTagEdit = $true
    } else {
        Write-Host "☑ 仅视频重命名（Emby配图不处理）" -ForegroundColor Green
        $enableNfoTagEdit = $false
    }
    Write-Host ""

    # ========== 已标记文件策略 ==========
    $forceRewriteAll = $false
    $perFileSelect = $false
    Write-Host "===== 已含时间标记的文件处理策略 =====" -ForegroundColor Cyan
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
    Write-Host ""

    # ========== 获取时长并生成预览表 ==========
    Write-Host "正在分析视频时长，请稍候..." -ForegroundColor Cyan
    $resultList = @()
    foreach ($f in $files) {
        $durSec = $null
        try {
            # 尝试用 ffprobe（若系统有）
            $ffprobe = "ffprobe.exe"
            if (Test-Path $ffprobe) {
                $info = & $ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $f.FullName 2>$null
                if ($info) { $durSec = [double]$info }
            }
            # 备用：Shell.Application（较慢但兼容）
            if ($null -eq $durSec) {
                $shell = New-Object -ComObject Shell.Application
                $folder = $shell.Namespace($f.DirectoryName)
                $item = $folder.ParseName($f.Name)
                # 时长属性索引通常为 27
                $durationStr = $folder.GetDetailsOf($item, 27)
                if ($durationStr) {
                    $ts = [TimeSpan]::Parse($durationStr)
                    $durSec = $ts.TotalSeconds
                }
            }
        } catch {}
        $resultList += [PSCustomObject]@{ FullName = $f.FullName; DurationSec = $durSec }
    }

    foreach ($f in $files) {
        $res = $resultList | Where-Object { $_.FullName -eq $f.FullName }
        $origBase = $f.BaseName
        $basename = $origBase
        $ext = $f.Extension
        $hasTimeMark = $basename -match $timeRegex

        # ===== 已标记文件分支 =====
        if ($hasTimeMark) {
            if ($forceRewriteAll) {
                $basename = $basename -replace $timeRegex, ''
                $basename = $basename.TrimEnd()
            }
            elseif ($perFileSelect) {
                Write-Host "`n检测到已标记文件：$($f.Name)" -ForegroundColor Yellow
                $sub = Get-SingleKey "【r】重处理（替换旧时间）【k】跳过此文件"
                if ($sub -eq 'r') {
                    $basename = $basename -replace $timeRegex, ''
                    $basename = $basename.TrimEnd()
                }
                else {
                    $previewTable += [PSCustomObject]@{
                        序号=$idx; 原文件名=$f.Name; 新文件名=$f.Name; 操作='[跳过]'
                        FullName=$f.FullName; DoRename=$false; Status='跳过'; NewBase=$origBase; NfoNewTitle=$null
                    }
                    $idx++; continue
                }
            }
            else {
                $previewTable += [PSCustomObject]@{
                    序号=$idx; 原文件名=$f.Name; 新文件名=$f.Name; 操作='[跳过]'
                    FullName=$f.FullName; DoRename=$false; Status='跳过'; NewBase=$origBase; NfoNewTitle=$null
                }
                $idx++; continue
            }
        }

        # ===== 计算时长 → 前置追加时间 =====
        $durSec = $res.DurationSec
        if ($null -eq $durSec -or $durSec -le 0) {
            $previewTable += [PSCustomObject]@{
                序号=$idx; 原文件名=$f.Name; 新文件名=$f.Name; 操作='[跳过(无时长)]'
                FullName=$f.FullName; DoRename=$false; Status='跳过'; NewBase=$origBase; NfoNewTitle=$null
            }
            $idx++; continue
        }

        $totalSec = [int]$durSec
        $h = [Math]::Floor($totalSec / 3600)
        $rem = $totalSec % 3600
        $m = [Math]::Floor($rem / 60)
        $s = $rem % 60
        $hh = if ($h -lt 10) { "0$h" } else { "$h" }
        $mm = if ($m -lt 10) { "0$m" } else { "$m" }
        $ss = if ($s -lt 10) { "0$s" } else { "$s" }
        if ($h -gt 0) { $timeStr = "$hh`h${mm}m${ss}s" } else { $timeStr = "${mm}m${ss}s" }

        # ★ 前置时长（与end版唯一区别：时间在前）
        $newBase = "$timeStr $basename"
        $newFullName = "$newBase$ext"

        # 仅此处写入映射表（修复拼接残留问题）
        $videoBaseMap[$origBase] = $newBase
        $previewTable += [PSCustomObject]@{
            序号=$idx; 原文件名=$f.Name; 新文件名=$newFullName; 操作='[RENAME]'
            FullName=$f.FullName; DoRename=$true; Status='RENAME'; NewBase=$newBase; NfoNewTitle=$null
        }
        $idx++
    }

    # ---- 附属配图/nfo生成RENAME-ART条目（emby开启时） ----
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
                if ($f.Extension.TrimStart('.') -notin @('jpg','png','webp','nfo')) { continue }
                $newArtBase = $f.BaseName.Replace($origVidBase, $targetNewBase)
                $newArtName = $newArtBase + $f.Extension
                $nfoNewTitle = $null
                if ($enableNfoTagEdit -and $f.Extension.ToLower() -eq ".nfo" -and $f.BaseName -eq $origVidBase) {
                    $nfoNewTitle = $targetNewBase
                }
                $previewTable += [PSCustomObject]@{
                    序号=$idx; 原文件名=$f.Name; 新文件名=$newArtName; 操作='[RENAME-ART]'
                    FullName=$f.FullName; DoRename=$true; Status='RENAME-ART'; NewBase=$newArtBase; NfoNewTitle=$nfoNewTitle
                }
                $idx++
            }
        }
    }

    # ========== 显示预览表 ==========
    Write-Host "`n===== 预览表 =====" -ForegroundColor Cyan
    $previewTable | Format-Table -AutoSize 序号, 原文件名, 新文件名, 操作
    Write-Host "总计：$($previewTable.Count) ｜ 将重命名：$($($previewTable | Where-Object {$_.DoRename -eq $true}).Count) ｜ 跳过：$($($previewTable | Where-Object {$_.DoRename -eq $false}).Count)" -ForegroundColor Cyan
    Write-Host ""

    # ========== 预览后确认（y执行 / s导出 / 其他退出） =====
    $confirm = Get-SingleKey "【y】执行重命名 【s】仅导出预览(不实写) 【其他键】退出"
    if ($confirm -eq 's') {
        $exportFile = Join-Path $PWD.Path "preview_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        $previewTable | Format-Table -AutoSize | Out-File $exportFile -Encoding utf8
        Write-Host "✅ 已导出预览表（未实写）：$exportFile" -ForegroundColor Green
        Wait-AnyKey "按任意键退出..."
        exit
    }
    if ($confirm -ne 'y') {
        Write-Host "已取消，未做任何修改。" -ForegroundColor Gray
        Wait-AnyKey "按任意键退出..."
        exit
    }

    # ========== 执行重命名 ==========
    Write-Host "`n开始执行重命名..." -ForegroundColor Cyan
    foreach ($item in $previewTable | Where-Object { $_.DoRename -eq $true }) {
        try {
            $oldFull = $item.FullName
            $newName = $item.新文件名
            $oldName = (Get-Item -LiteralPath $oldFull).Name
            Rename-Item -LiteralPath $oldFull -NewName $newName -ErrorAction Stop
            $undoList += [PSCustomObject]@{ OldName=$oldName; NewName=$newName; AfterPath=(Join-Path (Split-Path $oldFull) $newName) }
            
            # nfo 内部标题覆盖（emby开启时）
            if ($embyFollow -and $enableNfoTagEdit -and $item.NfoNewTitle) {
                $nfoPath = Join-Path (Split-Path $oldFull) ($item.NewBase + ".nfo")
                if (Test-Path $nfoPath) {
                    $xml = [xml](Get-Content $nfoPath -Encoding UTF8)
                    $oldTitle = $xml.SelectSingleNode("//title").InnerText
                    $xml.SelectSingleNode("//title").InnerText = $item.NfoNewTitle
                    $sortTitle = $xml.SelectSingleNode("//sorttitle")
                    if ($sortTitle) { $sortTitle.InnerText = $item.NfoNewTitle }
                    $xml.Save($nfoPath)
                    $nfoModifyLog += [PSCustomObject]@{ NfoFile=$nfoPath; OldTitle=$oldTitle; NewTitle=$item.NfoNewTitle }
                }
            }
            Write-Host "[OK] $oldName → $newName" -ForegroundColor Green
        }
        catch {
            Write-Host "原名：" -ForegroundColor Gray -NoNewline
            Write-Host "$($item.原文件名)" -NoNewline
            Write-Host " → " -ForegroundColor Gray -NoNewline
            Write-Host "$($item.新文件名) " -ForegroundColor Yellow -NoNewline
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
            $lines += "# 原名`t新名"
            foreach ($uItem in $undoList) { $lines += "$($uItem.OldName)`t$($uItem.NewName)" }
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
