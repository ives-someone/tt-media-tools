<#
time_clear.ps1
v1.0：合并 time_clr_begin / time_clr_end / time_clr_auto / time_clr_remove 四个脚本为统一入口。
    【合并背景】
    原四个脚本各自独立实现，约 400~470 行/个，其中：
      - time_clr_begin  匹配文件名开头的时间串，仅保留时间作为新名
      - time_clr_end    与 begin 除注释外完全相同（历史复制事故，"结尾"从未实现）
      - time_clr_auto   匹配任意位置的时间串，仅保留时间作为新名（功能覆盖 begin）
      - time_clr_remove 删除时间片断，保留其余文本（反向操作）
    实际只有两种行为，四个脚本共 1800 行、Emby 交互段整段复制 4 份、
    各自重复定义 Get-SingleKey / Wait-AnyKey、纯 Write-Host -ForegroundColor 无配色体系。

    【本版结构】
    1、单一入口，两种模式：1=只保留时间（清除其余文本） 2=删除时间片断（保留其余文本）
    2、模式1 增加"位置"子选项：开头 / 结尾 / 任意
       —— "结尾"为本次新实现（原 time_clr_end 从未生效过，提交说明里只有意图）
    3、全面接入 modules\ui\ui.ps1：col_a_* 配色、sep/sep_weak、Select-Horizontal、Clear-Screen
    4、预览表对齐 time_add.ps1 的列宽与中文视觉宽度算法（Get-DisplayWidth）
    5、Emby 配图 / nfo 跟随改名，附属文件判定复用 time_add.ps1 v5.34 的词干白名单
    6、nfo 写入沿用 time_add.ps1 v5.34 的全部安全锁：
       字节级 .bak、编码探测（BOM→严格UTF-8→GB18030）、$safeTitle XML 转义、
       $rootTag 根节点判断、OldPath 撤销还原、写后自检失败自动回滚
    7、撤销：先逆序还原文件名（栈语义），再从 .bak 字节级还原 nfo 内容
    8、PS 5.1 / PS 7 双版本兼容：不使用 PS7 专属语法，不依赖 Get-WmiObject
#>

# ========== 加载公共 UI 框架 ==========
. (Join-Path $PSScriptRoot "ui\ui.ps1")
. (Join-Path $PSScriptRoot "common.ps1")

# ========== 配置 ==========
# 视频/附属文件扩展名已移至 common.ps1

# 时间标记：XXhXXmXXs 或 XXmXXs（两位数字，与旧脚本保持一致）
$timeUnit = '(\d{2}h\d{2}m\d{2}s|\d{2}m\d{2}s)'
$rePureTimeName   = '^' + $timeUnit + '$'          # 纯时间名
$reTimeWithNum    = '^' + $timeUnit + '\d+$'       # 脚本产物：时间+序号
$reAnyTime        = [regex]$timeUnit

# 附属文件白名单与 Test-ArtBaseName 已移至 common.ps1

# ========== 预览表格式化 ==========
$script:ColWidth = 46
$script:MaxWidth = 44
$diffSep = sep_weak -Len ($script:ColWidth * 2 + 18)

function Get-DisplayWidth {
    param([string]$s)
    $w = 0
    foreach ($c in $s.ToCharArray()) {
        $w += if ($c -gt 0x2E7F -or ($c -ge 0xFF00 -and $c -le 0xFFEF)) { 2 } else { 1 }
    }
    return $w
}

function Format-TruncatedName {
    param([string]$name, [int]$maxWidth = $script:MaxWidth)
    if (-not $name) { return "" }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
    $ext  = [System.IO.Path]::GetExtension($name)
    if ((Get-DisplayWidth $name) -le $maxWidth) { return $name }
    $budget = $maxWidth - (Get-DisplayWidth $ext) - (Get-DisplayWidth "…")
    if ($budget -lt 4) { $budget = 4 }
    $res = ""; $curW = 0
    foreach ($c in $base.ToCharArray()) {
        $cw = if ($c -gt 0x2E7F -or ($c -ge 0xFF00 -and $c -le 0xFFEF)) { 2 } else { 1 }
        if ($curW + $cw -gt $budget) { break }
        $res += $c; $curW += $cw
    }
    return $res + "…" + $ext
}

function Format-TableRow {
    param(
        [int]$Index,
        [string]$OrigName,
        [string]$NewName,
        [string]$Op = ""
    )
    $idxStr = "{0,-3}" -f $Index
    $oName = Format-TruncatedName -name $OrigName
    $nName = Format-TruncatedName -name $NewName
    $oPad  = $script:ColWidth - (Get-DisplayWidth $oName); if ($oPad -lt 0) { $oPad = 0 }
    $nPad  = $script:ColWidth - (Get-DisplayWidth $nName); if ($nPad -lt 0) { $nPad = 0 }
    return "$idxStr" + $oName + (" " * $oPad) + $nName + (" " * $nPad) + $Op
}

function Show-PreviewHeader {
    $hdr = "  " + ("{0,-3}" -f "序号")
    $oldHdr = "原文件名"
    $oldPad = ($script:ColWidth - 6) - (Get-DisplayWidth $oldHdr); if ($oldPad -lt 0) { $oldPad = 0 }
    $hdr += $oldHdr + (" " * $oldPad)
    $newHdr = "新文件名"
    $padNew = ($script:ColWidth - 1) - $hdr.Length; if ($padNew -lt 0) { $padNew = 0 }
    $hdr += (" " * $padNew) + $newHdr
    $opHdr = "操作"
    $padOp = ($script:ColWidth * 2 - 5) - $hdr.Length; if ($padOp -lt 0) { $padOp = 0 }
    $hdr += (" " * $padOp) + $opHdr
    Write-Host $hdr
    Write-Host "  $(col_a_line $diffSep)"
}

# ========== 时间标记匹配与改名计算 ==========

# 按"位置"构造匹配正则：head=开头 tail=结尾 any=任意
function Get-TimePattern {
    param([string]$Position)
    switch ($Position) {
        'head' { return '^(?<bt>' + $timeUnit + ')(?<num>\d*)' }
        'tail' { return '(?<bt>' + $timeUnit + ')(?<num>\d*)$' }
        default { return '(?<bt>' + $timeUnit + ')(?<num>\d*)' }
    }
}

# 删除时间片断：连同其前面的空白一起删除，再清理多余空格
function Get-NameWithoutTime {
    param([string]$BaseName)
    $clean = [regex]::Replace($BaseName, '\s*' + $timeUnit + '\s*', ' ')
    $clean = $clean.Trim()
    $clean = [regex]::Replace($clean, '\s{2,}', ' ')
    return $clean
}

# ========== nfo 编码探测 ==========
# 返回 Encoding；无 BOM 且非合法 UTF-8 时尝试 GB18030；
# 系统缺少 GB18030 代码页时返回 $null，调用方据此跳过该文件，绝不用错误编码写盘。
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

# ========== 主循环 ==========
while ($true) {

    Clear-Screen
    Write-Host ""

    # ---- 处理目录 ----
    $cwdDisplay = $PWD.ProviderPath
    if ($cwdDisplay.Length -gt 78) {
        $cwdDisplay = $cwdDisplay.Substring(0, 38) + '…' + $cwdDisplay.Substring($cwdDisplay.Length - 38)
    }

    Write-Host "  $(col_a_title ('time_clear.ps1 — 文件名时长标记清理工具'))"
    Write-Host "  $(col_a_line (sep))"
    Write-Host ""
    Write-Host "  $(col_a_text_muted '处理目录：')$(col_a_text $cwdDisplay)"
    Write-Host ""
    Write-Host "  $(col_a_text_muted ('从文件名中识别时长标记（如 01h30m45s / 02m15s），按所选模式改名'))"
    Write-Host "  $(col_a_text_muted ('可选 Emby 配图与 nfo 跟随改名，nfo 内部标题同步改写，全程可撤销'))"
    Write-Host ""

    # ---- 主菜单：模式选择 ----
    Write-Host "  $(col_a_text ('清理模式：'))"
    Write-Host "  $(col_a_line (sep_weak))"

    $modeOpts = @(
        @{ Label = "[1]只保留时间（清除其余文本）"; Value = "keep" }
        @{ Label = "[2]删除时间片断（保留其余文本）"; Value = "remove" }
        @{ Label = "[q/Esc]退出"; Value = "exit" }
    )
    $modeResult = Select-Horizontal -Options $modeOpts -Prompt "" -InitialIndex 0
    if ($null -eq $modeResult) { exit 0 }

    switch ($modeResult) {
        'keep'   { $mode = 'keep';   $modeName = '只保留时间' }
        'remove' { $mode = 'remove'; $modeName = '删除时间片断' }
        'exit'   { exit 0 }
    }

    # ---- 位置子选项（仅"只保留时间"需要）----
    $position = 'any'
    $positionName = '任意位置'
    if ($mode -eq 'keep') {
        Write-Host ""
        Write-Host "  $(col_a_text ('时间标记出现的位置：'))"
        Write-Host "  $(col_a_text_muted ('（文件名里有多个时间串时才需要指定；一般选任意位置即可）'))"
        Write-Host "  $(col_a_line (sep_weak))"

        $posOpts = @(
            @{ Label = "[1]开头"; Value = "head" }
            @{ Label = "[2]结尾"; Value = "tail" }
            @{ Label = "[3]任意位置（推荐）"; Value = "any" }
            @{ Label = "[q/Esc]重新开始"; Value = "restart" }
        )
        $posResult = Select-Horizontal -Options $posOpts -Prompt "" -InitialIndex 2
        if ($null -eq $posResult -or $posResult -eq 'restart') { continue }
        $position = $posResult
        $positionName = switch ($position) {
            'head' { '开头' } 'tail' { '结尾' } default { '任意位置' }
        }
    }

    # ---- Emby 跟随开关 ----
    $embyFollow = $false
    $orphannfoList   = @()   # 孤立 nfo 还原列表
    $orphanImageList = @()   # 孤立图片还原列表
    Write-Host ""
    Write-Host "  $(col_a_text ('Emby / Jellyfin 配图与 nfo 跟随：'))"
    Write-Host "  $(col_a_line (sep_weak))"

    $embyOpts = @(
        @{ Label = "[y]开启跟随改名（推荐）"; Value = "on" }
        @{ Label = "[n]关闭跟随改名（仅处理视频）"; Value = "off" }
        @{ Label = "[q/Esc]重新开始"; Value = "restart" }
    )
    $embyResult = Select-Horizontal -Options $embyOpts -Prompt "" -InitialIndex 0
    if ($null -eq $embyResult -or $embyResult -eq 'restart') { continue }
    if ($embyResult -eq 'on') { $embyFollow = $true }

    # ---- 扫描视频 ----
    $files = Get-ChildItem -File |
        Where-Object { $videoExts -contains $_.Extension.TrimStart('.').ToLower() } |
        Sort-Object Name

    if (-not $files) {
        Write-Host ""
        Write-Host "  $(col_a_warning ('⚠  当前目录没有找到支持的视频文件。'))"
        Wait-AnyKey
        exit 0
    }

    # ========== 孤立文件检测（对齐 time_add.ps1 v5.34）==========
    if ($embyFollow) {
        Write-Host
        Write-Host

        $allVideoBases = $files | ForEach-Object { $_.BaseName }

        # --- 孤立 nfo 检测 ---
        $allNfoFiles = Get-ChildItem -File -Filter "*.nfo"
        $orphanNfos = @()
        foreach ($nfo in $allNfoFiles) {
            $nfoBase = $nfo.BaseName
            if (Test-ArtBaseName -BaseName $nfoBase) { continue }
            if ($allVideoBases -contains $nfoBase) { continue }
            $orphanNfos += $nfo
        }

        # --- 孤立图片检测 ---
        $imageExts = @('.jpg','.jpeg','.png','.webp')
        $allImages = Get-ChildItem -File | Where-Object { $imageExts -contains $_.Extension.ToLower() }
        $orphanImgs = @()
        foreach ($img in $allImages) {
            $imgBase = $img.BaseName
            if (Test-ArtBaseName -BaseName $imgBase) { continue }
            if ($allVideoBases -contains $imgBase) { continue }
            $orphanImgs += $img
        }

        # 只有存在孤立文件时才显示红框提示
        $totalOrphan = $orphanNfos.Count + $orphanImgs.Count
        if ($totalOrphan -gt 0) {
            $bw = 36
            $hLine = "─" * ($bw - 2)
            Write-Host "  $(col_a_error ('┌' + $hLine + '┐'))"
            Write-Host "  $(col_a_error ('│   发现孤立文件，是否清理删除？   │'))"
            Write-Host "  $(col_a_error ('└' + $hLine + '┘'))"
        }

        if ($orphanNfos.Count -eq 0) {
            Write-Host "  $(col_a_success '✅  未发现孤立nfo文件。')"
        }
        else {
            Write-Host ""
            Write-Host "  $(col_a_warning "⚠  发现 $($orphanNfos.Count) 个孤立nfo（无同名视频）：")"
            Write-Host ""
            foreach ($o in $orphanNfos) { Write-Host "  📄 $($o.FullName)" }
            Write-Host ""
            Write-Host "  $(col_a_text ('孤立nfo清理：'))"
            Write-Host "  $(col_a_line (sep_weak))"

            $orphanCleanOpts = @(
                @{ Label = "[d]删除并备份"; Value = "clean" }
                @{ Label = "[s]跳过"; Value = "skip" }
                @{ Label = "[q/Esc]重新开始"; Value = "restart" }
            )
            $orphanCleanResult = Select-Horizontal -Options $orphanCleanOpts -Prompt "" -InitialIndex 1
            if ($null -eq $orphanCleanResult -or $orphanCleanResult -eq 'restart') { continue }

            if ($orphanCleanResult -eq 'clean') {
                Write-Host ""
                foreach ($o in $orphanNfos) {
                    try {
                        $bakPath = $o.FullName + ".bak"
                        [System.IO.File]::Copy($o.FullName, $bakPath, $true)
                        [System.IO.File]::Delete($o.FullName)
                        $orphannfoList += [PSCustomObject]@{ FilePath = $o.FullName; BakPath = $bakPath }
                        Write-Host "  $(col_a_success "🗑 $($o.Name) | 已删除（备份：$bakPath）")"
                    } catch {
                        Write-Host "  $(col_a_error "❌ $($o.Name) | 清理失败：$_")"
                    }
                }
                Write-Host ""
                Write-Host "  $(col_a_success "✅  已清理 $($orphannfoList.Count) 个孤立nfo（均生成.bak备份）")"
            }
        }

        if ($orphanImgs.Count -eq 0) {
            Write-Host "  $(col_a_success '✅  未发现孤立图片文件。')"
        }
        else {
            Write-Host ""
            Write-Host "  $(col_a_warning "⚠  发现 $($orphanImgs.Count) 个孤立图片（无同名视频）：")"
            Write-Host ""
            foreach ($o in $orphanImgs) { Write-Host "  🖼  $($o.FullName)" }
            Write-Host ""
            Write-Host "  $(col_a_text ('孤立图片清理：'))"
            Write-Host "  $(col_a_line (sep_weak))"

            $imgCleanOpts = @(
                @{ Label = "[d]删除并备份"; Value = "clean" }
                @{ Label = "[s]跳过"; Value = "skip" }
                @{ Label = "[q/Esc]重新开始"; Value = "restart" }
            )
            $imgCleanResult = Select-Horizontal -Options $imgCleanOpts -Prompt "" -InitialIndex 1
            if ($null -eq $imgCleanResult -or $imgCleanResult -eq 'restart') { continue }

            if ($imgCleanResult -eq 'clean') {
                Write-Host ""
                foreach ($o in $orphanImgs) {
                    try {
                        $bakPath = $o.FullName + ".bak"
                        [System.IO.File]::Copy($o.FullName, $bakPath, $true)
                        [System.IO.File]::Delete($o.FullName)
                        $orphanImageList += [PSCustomObject]@{ FilePath = $o.FullName; BakPath = $bakPath }
                        Write-Host "  $(col_a_success "🗑 $($o.Name) | 已删除（备份：$bakPath）")"
                    } catch {
                        Write-Host "  $(col_a_error "❌ $($o.Name) | 清理失败：$_")"
                    }
                }
                Write-Host ""
                Write-Host "  $(col_a_success "✅  已清理 $($orphanImageList.Count) 个孤立图片（均生成.bak备份）")"
            }
        }
    }

    # ========== 生成预览 ==========
    $previewList = @()
    $videoBaseMap = @{}
    $idx = 1
    $reTime = Get-TimePattern -Position $position

    foreach ($f in $files) {
        $baseName = $f.BaseName
        $ext      = $f.Extension

        # 保护1：本身就是纯时间名
        if ($baseName -match $rePureTimeName) {
            $previewList += [PSCustomObject]@{
                序号 = $idx; 原文件名 = $f.Name; 新文件名 = $f.Name; 操作 = '[EXIST]'
                FullName = $f.FullName; DoRename = $false; Status = 'SKIP'; NewBase = $baseName; NfoNewTitle = $null
            }
            $idx++; continue
        }

        # 保护2：脚本产物（时间+序号）
        if ($baseName -match $reTimeWithNum) {
            $previewList += [PSCustomObject]@{
                序号 = $idx; 原文件名 = $f.Name; 新文件名 = $f.Name; 操作 = '[EXIST]'
                FullName = $f.FullName; DoRename = $false; Status = 'SKIP'; NewBase = $baseName; NfoNewTitle = $null
            }
            $idx++; continue
        }

        $newBase = $null

        if ($mode -eq 'keep') {
            $m = [regex]::Match($baseName, $reTime)
            if (-not $m.Success) {
                $previewList += [PSCustomObject]@{
                    序号 = $idx; 原文件名 = $f.Name; 新文件名 = $f.Name; 操作 = '[SKIP 无时间]'
                    FullName = $f.FullName; DoRename = $false; Status = 'SKIP'; NewBase = $baseName; NfoNewTitle = $null
                }
                $idx++; continue
            }
            $newBase = $m.Groups['bt'].Value
        }
        else {
            if (-not $reAnyTime.IsMatch($baseName)) {
                $previewList += [PSCustomObject]@{
                    序号 = $idx; 原文件名 = $f.Name; 新文件名 = $f.Name; 操作 = '[SKIP 无时间]'
                    FullName = $f.FullName; DoRename = $false; Status = 'SKIP'; NewBase = $baseName; NfoNewTitle = $null
                }
                $idx++; continue
            }
            $cleanBase = Get-NameWithoutTime -BaseName $baseName
            if ([string]::IsNullOrWhiteSpace($cleanBase)) {
                $previewList += [PSCustomObject]@{
                    序号 = $idx; 原文件名 = $f.Name; 新文件名 = $f.Name; 操作 = '[SKIP 删空]'
                    FullName = $f.FullName; DoRename = $false; Status = 'SKIP'; NewBase = $baseName; NfoNewTitle = $null
                }
                $idx++; continue
            }
            $newBase = $cleanBase
        }

        # 计算最终名（同基名分组计数）
        $candidate = "$newBase$ext"
        $isSelf = ($candidate -eq $f.Name)
        $occupied = $false
        if (-not $isSelf) { $occupied = Test-Path -LiteralPath (Join-Path $f.Directory.FullName $candidate) }

        if (-not $occupied -and -not ($previewList | Where-Object { $_.新文件名 -eq $candidate })) {
            $finalBase = $newBase
        }
        else {
            $n = 2
            do {
                $finalBase = "$newBase$n"
                $candidate = "$finalBase$ext"
                $isSelf = ($candidate -eq $f.Name)
                $occupied = $false
                if (-not $isSelf) { $occupied = Test-Path -LiteralPath (Join-Path $f.Directory.FullName $candidate) }
                $exists = [bool]($previewList | Where-Object { $_.新文件名 -eq $candidate })
                $n++
            } while ($occupied -or $exists)
        }

        $finalName = "$finalBase$ext"
        $videoBaseMap[$baseName] = $finalBase

        if ($finalName -eq $f.Name) {
            $previewList += [PSCustomObject]@{
                序号 = $idx; 原文件名 = $f.Name; 新文件名 = $f.Name; 操作 = '[SKIP 同名]'
                FullName = $f.FullName; DoRename = $false; Status = 'SKIP'; NewBase = $baseName; NfoNewTitle = $null
            }
        }
        else {
            $previewList += [PSCustomObject]@{
                序号 = $idx; 原文件名 = $f.Name; 新文件名 = $finalName; 操作 = '[RENAME]'
                FullName = $f.FullName; DoRename = $true; Status = 'RENAME'; NewBase = $finalBase; NfoNewTitle = $null
            }
        }
        $idx++
    }

    # ========== 附属配图 / nfo 跟随 ==========
    if ($embyFollow) {
        $allFiles = Get-ChildItem -File
        foreach ($origBase in $videoBaseMap.Keys) {
            $targetBase = $videoBaseMap[$origBase]
            foreach ($f in $allFiles) {
                $bn = $f.BaseName
                $extLower = $f.Extension.TrimStart('.').ToLower()
                if ($artExts -notcontains $extLower) { continue }

                # 同基名 / 同基名-后缀（后缀须为白名单词干）
                $affix = $null
                if ($bn -eq $origBase) { $affix = '' }
                elseif ($bn.StartsWith("$origBase-")) {
                    $sub = $bn.Substring($origBase.Length)
                    if ($sub -match ('^-(' + ($artStemList -join '|') + ')\d*$')) { $affix = $sub }
                }
                if ($null -eq $affix) { continue }

                $newArtName = "$targetBase$affix$($f.Extension)"
                if ($newArtName -eq $f.Name) { continue }

                $previewList += [PSCustomObject]@{
                    序号 = $idx; 原文件名 = $f.Name; 新文件名 = $newArtName; 操作 = '[RENAME-EXT]'
                    FullName = $f.FullName; DoRename = $true; Status = 'RENAME-EXT'
                    NewBase = "$targetBase$affix"; NfoNewTitle = $null
                }
                $idx++
            }
        }
    }

    # ========== 预览表 ==========
    Write-Host ""
    Write-Host ""
    Write-Host "  $(col_a_title ('重命名预览（' + $modeName + ' / ' + $positionName + '）'))"
    Write-Host "  $(col_a_line (sep_weak))"
    if ($embyFollow) { $tip = "Emby配图跟随：✅  开启" } else { $tip = "Emby配图跟随：❌  关闭" }
    Write-Host "  $(col_a_text ('[' + $tip + ']'))"
    Write-Host ""
    Show-PreviewHeader

    foreach ($item in $previewList) {
        $opText = switch ($item.Status) {
            'RENAME'     { "$(col_a_success '[RENAME]')" }
            'RENAME-EXT' { "$(col_a_success '[RENAME-EXT]')" }
            default      { "$(col_a_text_muted $item.操作)" }
        }
        Write-Host ("  " + (Format-TableRow -Index $item.序号 -OrigName $item.原文件名 -NewName $item.新文件名 -Op $opText))
    }

    Write-Host "  $(col_a_line $diffSep)"
    $renameCount = ($previewList | Where-Object { $_.DoRename -eq $true }).Count

    if ($renameCount -eq 0) {
        Write-Host "  $(col_a_warning ('⚠  没有需要执行改名的文件。'))"
        Wait-AnyKey
        continue
    }

    # ========== nfo 内部标题差异扫描 ==========
    $nfoDiffList = @()
    $nfoActualRewriteCount = 0

    if ($embyFollow) {
        Write-Host ""
        Write-Host ""
        Write-Host "  $(col_a_title ('nfo 内部标题差异检测'))"
        Write-Host "  $(col_a_line (sep))"

        $allNfo = Get-ChildItem -File -Filter "*.nfo"
        $diffCount = 0; $sameCount = 0

        foreach ($nfo in $allNfo) {
            $nfoBase = $nfo.BaseName
            if (Test-ArtBaseName -BaseName $nfoBase) { continue }

            $innerTitle = $null
            try {
                $raw = [System.IO.File]::ReadAllBytes($nfo.FullName)
                $enc = Get-NfoEncoding -Bytes $raw
                $txt = $enc.GetString($raw)
                if ($txt -match '<title\b[^>]*>(.*?)</title>') { $innerTitle = $matches[1].Trim() }
            } catch { }

            # 目标名：优先取预览表中该 nfo 的目标基名
            $targetBase = $nfoBase
            $hit = $previewList | Where-Object { $_.原文件名 -eq $nfo.Name } | Select-Object -First 1
            if ($hit -and -not [string]::IsNullOrEmpty($hit.NewBase)) { $targetBase = $hit.NewBase }

            if ($null -ne $innerTitle -and $innerTitle -eq $targetBase) {
                $sameCount++
                continue
            }

            $diffCount++
            $nfoDiffList += [PSCustomObject]@{
                NfoName    = $nfo.Name
                NfoPath    = $nfo.FullName
                InnerTitle = $innerTitle
                Target     = $targetBase
            }
        }

        if ($diffCount -eq 0) {
            Write-Host "  $(col_a_success ('✅  所有 nfo 内部 <title> 均与目标文件名一致，无需改写。'))"
            Write-Host "  $(col_a_text_muted ("（共检查 $sameCount 个 nfo）"))"
        }
        else {
            Write-Host ""
            Write-Host "  $(col_a_warning ("⚠  发现 $diffCount 个 nfo 内部 <title> 与目标文件名不一致："))"
            Write-Host "  $(col_a_text_muted ("（一致的 $sameCount 个已跳过）"))"
            Write-Host ""
            Write-Host "  $(col_a_text ('  序号  nfo 文件 / 内部标题 → 目标名'))"
            Write-Host "  $(col_a_line (sep_weak))"
            $di = 1
            foreach ($d in $nfoDiffList) {
                $cur = if ($null -eq $d.InnerTitle) { '[无标签]' } else { $d.InnerTitle }
                Write-Host ("  {0,-4} {1}" -f $di, (Format-TruncatedName -name $d.NfoName -maxWidth 40))
                Write-Host ("       $(col_a_text_muted ('当前：'))$(col_a_warning $cur)")
                Write-Host ("       $(col_a_text_muted ('目标：'))$(col_a_success $d.Target)")
                $di++
            }
            Write-Host "  $(col_a_line (sep_weak))"
            Write-Host ""
            Write-Host "  $(col_a_text ('nfo 内部标题处理：'))"
            Write-Host "  $(col_a_line (sep_weak))"

            $nfoOpts = @(
                @{ Label = "[a]全部改写"; Value = "all" }
                @{ Label = "[p]逐个确认"; Value = "perfile" }
                @{ Label = "[s]全部跳过"; Value = "skip" }
                @{ Label = "[q/Esc]重新开始"; Value = "restart" }
            )
            $nfoResult = Select-Horizontal -Options $nfoOpts -Prompt "" -InitialIndex 0
            if ($null -eq $nfoResult -or $nfoResult -eq 'restart') { continue }

            switch ($nfoResult) {
                'all' {
                    foreach ($d in $nfoDiffList) {
                        $previewList += [PSCustomObject]@{
                            序号 = $idx; 原文件名 = $d.NfoName; 新文件名 = $d.NfoName; 操作 = '[TAB-SYNC]'
                            FullName = $d.NfoPath; DoRename = $false; Status = 'TAB-SYNC'
                            NewBase = $d.Target; NfoNewTitle = $d.Target
                        }
                        $idx++
                    }
                    $nfoActualRewriteCount = $nfoDiffList.Count
                }
                'perfile' {
                    foreach ($d in $nfoDiffList) {
                        Write-Host ""
                        Write-Host "  $(col_a_warning ("nfo：$($d.NfoName)"))"
                        Write-Host "  $(col_a_text_muted ("当前 <title>：'$($d.InnerTitle)'" ))"
                        Write-Host "  $(col_a_text_muted ("目标改为：'$($d.Target)'"))"
                        Write-Host ""
                        $perOpts = @(
                            @{ Label = "[y]改写"; Value = "yes" }
                            @{ Label = "[n]跳过"; Value = "no" }
                            @{ Label = "[q/Esc]重新开始"; Value = "restart" }
                        )
                        $perResult = Select-Horizontal -Options $perOpts -Prompt "" -InitialIndex 1
                        if ($null -eq $perResult -or $perResult -eq 'restart') { continue }
                        if ($perResult -eq 'yes') {
                            $previewList += [PSCustomObject]@{
                                序号 = $idx; 原文件名 = $d.NfoName; 新文件名 = $d.NfoName; 操作 = '[TAB-SYNC]'
                                FullName = $d.NfoPath; DoRename = $false; Status = 'TAB-SYNC'
                                NewBase = $d.Target; NfoNewTitle = $d.Target
                            }
                            $idx++
                            $nfoActualRewriteCount++
                        }
                    }
                }
                'skip' {
                    $nfoActualRewriteCount = 0
                    Write-Host "  $(col_a_text_muted ('⚪  已跳过 nfo 内部标题改写。'))"
                }
            }
        }
    }

    # ========== 最终确认 ==========
    Write-Host ""
    Write-Host ""
    Write-Host "  $(col_a_title ('开始按上述选择和预览执行重命名'))"
    Write-Host "  $(col_a_warning ('⚠️ 即将真实写入！随后仍可撤销还原文件名与 nfo 内容'))"
    Write-Host "  $(col_a_line (sep_weak))"

    $execOpts = @(
        @{ Label = "[y]执行重命名"; Value = "exec" }
        @{ Label = "[n]仅导出映射 txt（不改名）"; Value = "export" }
        @{ Label = "[q/Esc]重新开始"; Value = "restart" }
    )
    $execResult = Select-Horizontal -Options $execOpts -Prompt "" -InitialIndex 0
    if ($null -eq $execResult -or $execResult -eq 'restart') { continue }

    $timeStamp = Get-Date -Format "yyyyMMdd_HHmmss"

    if ($execResult -eq 'export') {
        $mapFile = Join-Path $PWD.Path "time_clear_map_$timeStamp.txt"
        $lines = @("# 仅映射（未执行改名）", "# 模式：$modeName / $positionName", "# 原名`t新名")
        foreach ($item in $previewList | Where-Object { $_.DoRename }) {
            $lines += "$($item.原文件名)`t$($item.新文件名)"
        }
        $lines | Out-File -FilePath $mapFile -Encoding utf8
        Write-Host "  $(col_a_success ('✅  已保存映射文件（未改名）：' + $mapFile))"
        Wait-AnyKey
        continue
    }

    # ========== 执行 ==========
    Write-Host ""
    Write-Host "  $(col_a_title ('开始执行改名'))"
    Write-Host ""

    $undoList      = @()
    $nfoBackupList = @()
    $nfoModifyLog  = @()

    foreach ($item in $previewList) {
        $src = $item.FullName

        # 改名
        if ($item.DoRename -eq $true) {
            $targetName = $item.新文件名
            $targetPath = Join-Path (Split-Path $src) $targetName
            try {
                Rename-Item -LiteralPath $src -NewName $targetName -ErrorAction Stop
                Write-Host "  $(col_a_text_muted '原名：')" -NoNewline
                Write-Host "  $($item.原文件名)" -NoNewline
                Write-Host " → " -NoNewline
                Write-Host "  $targetName " -NoNewline
                Write-Host "  $(col_a_success '[OK]')"
                $undoList += [PSCustomObject]@{
                    AfterPath  = $targetPath
                    BeforePath = $src
                    OldName    = $item.原文件名
                    NewName    = $targetName
                }
            } catch {
                Write-Host "  $(col_a_text_muted '原名：')" -NoNewline
                Write-Host "  $($item.原文件名)" -NoNewline
                Write-Host " → " -NoNewline
                Write-Host "  $targetName " -NoNewline
                Write-Host "  $(col_a_error "[ERROR] $_")"
            }
        }

        # nfo 内部标题改写（仅 TAB-SYNC 行）
        if ($item.Status -eq 'TAB-SYNC' -and -not [string]::IsNullOrEmpty($item.NfoNewTitle)) {
            $nfoOldPath = $src
            $nfoPath = if ([string]::IsNullOrEmpty($item.NewBase)) { $nfoOldPath }
                       else { Join-Path (Split-Path $nfoOldPath) "$($item.NewBase).nfo" }

            if ([System.IO.Path]::GetExtension($nfoPath).ToLower() -ne '.nfo') { continue }
            if (-not (Test-Path -LiteralPath $nfoPath)) {
                Write-Host "  $(col_a_text_muted "[nfo跳过] 目标不存在：$nfoPath")"
                continue
            }

            try {
                $nfoBytes = [System.IO.File]::ReadAllBytes($nfoPath)
                $nfoEnc = Get-NfoEncoding -Bytes $nfoBytes
                $nfoSkip = $false
                if ($null -eq $nfoEnc) { $nfoSkip = $true }
                if ($nfoSkip) {
                    Write-Host "  $(col_a_warning "[nfo跳过] 系统缺少 GB18030 代码页，无法安全处理：$nfoPath")"
                    continue
                }
                $nfoText = $nfoEnc.GetString($nfoBytes)

                $origTitleVal = $null; $origSortVal = $null
                if ($nfoText -match '<title\b[^>]*>(.*?)</title>') { $origTitleVal = $matches[1] }
                if ($nfoText -match '<sorttitle\b[^>]*>(.*?)</sorttitle>') { $origSortVal = $matches[1] }

                $bakPath = "$nfoPath.bak"
                if (-not (Test-Path -LiteralPath $bakPath)) {
                    Copy-Item -LiteralPath $nfoPath -Destination $bakPath -Force
                    $nfoBackupList += [PSCustomObject]@{
                        NfoFile = [System.IO.Path]::GetFileName($nfoPath)
                        OldPath = $nfoOldPath
                        BakPath = $bakPath
                    }
                }

                $safeTitle = [System.Security.SecurityElement]::Escape($item.NfoNewTitle).Replace('$', '$$')

                $rootTag = $null
                foreach ($rt in @('movie', 'episodedetails', 'tvshow')) {
                    if ($nfoText -match ('</' + $rt + '>')) { $rootTag = $rt; break }
                }

                if ($nfoText -match '<title\b[^>]*>.*?</title>') {
                    $nfoText = $nfoText -replace '<title\b[^>]*>.*?</title>', "<title>$safeTitle</title>"
                } elseif ($rootTag) {
                    $nfoText = $nfoText -replace ('</' + $rootTag + '>'), "<title>$safeTitle</title>`n</$rootTag>"
                } else {
                    $nfoText += "`n<title>$safeTitle</title>"
                }

                if ($nfoText -match '<sorttitle\b[^>]*>.*?</sorttitle>') {
                    $nfoText = $nfoText -replace '<sorttitle\b[^>]*>.*?</sorttitle>', "<sorttitle>$safeTitle</sorttitle>"
                } elseif ($rootTag) {
                    $nfoText = $nfoText -replace ('</' + $rootTag + '>'), "<sorttitle>$safeTitle</sorttitle>`n</$rootTag>"
                } else {
                    $nfoText += "`n<sorttitle>$safeTitle</sorttitle>"
                }

                [System.IO.File]::WriteAllBytes($nfoPath, $nfoEnc.GetBytes($nfoText))

                $nfoModifyLog += [PSCustomObject]@{
                    NfoFile  = $item.原文件名
                    OldTitle = $origTitleVal
                    NewTitle = $item.NfoNewTitle
                }
                Write-Host "  $(col_a_success '[nfo标题覆盖 OK]') → $($item.NfoNewTitle)"
            } catch {
                Write-Host "  $(col_a_error "[nfo标题更新失败] $_")"
            }
        }
    }

    Write-Host ""
    Write-Host "  $(col_a_success ('[√] 全部操作完成。'))"

    # ========== 事后菜单 ==========
    if ($undoList.Count -gt 0 -or $nfoBackupList.Count -gt 0 -or
        $orphannfoList.Count -gt 0 -or $orphanImageList.Count -gt 0) {
        Write-Host ""
        Write-Host ""
        Write-Host "  $(col_a_title ('后续操作选项'))"
        Write-Host "  $(col_a_warning ('⚠️ 后悔药只有一次，此处撤销可还原文件名/回滚nfo，恢复初始状态'))"
        Write-Host "  此处若不选择撤销，被删除的孤立文件和改内容的nfo可以通过前面生成的bak自行还原，但被修改过的文件名你只能自己还原了"
        Write-Host "  若有需要，可按s保存映射txt（供对比）后再退出"
        Write-Host "  $(col_a_line (sep_weak))"

        $postOpts = @(
            @{ Label = "[u]撤销改名"; Value = "undo" }
            @{ Label = "[s]保存映射txt"; Value = "save" }
            @{ Label = "[q/ESC]退出，不撤销也不保存txt，就这么定了~ "; Value = "exit" }
        )
        $postResult = Select-Horizontal -Options $postOpts -Prompt "" -InitialIndex 0
        if ($null -eq $postResult) { exit 0 }

        if ($postResult -eq 'undo') {
            $failFile = 0
            $failNfo  = 0

            Write-Host ""
            Write-Host "  $(col_a_warning ('⚠️  开始撤销，还原文件名...'))"
            [array]::Reverse($undoList)
            foreach ($u in $undoList) {
                if (Test-Path -LiteralPath $u.AfterPath) {
                    try {
                        Rename-Item -LiteralPath $u.AfterPath -NewName $u.OldName -ErrorAction Stop
                        Write-Host "  $(col_a_success "[撤销OK] $($u.NewName) → $($u.OldName)")"
                    } catch { Write-Host "  $(col_a_error "[撤销失败] $($u.AfterPath) : $_")"; $failFile++ }
                } else { Write-Host "  $(col_a_error "[撤销跳过] 文件不存在：$($u.AfterPath)")"; $failFile++ }
            }

            if ($nfoBackupList.Count -gt 0) {
                Write-Host ""
                Write-Host "  $(col_a_text ('还原 nfo 内容...'))"
                foreach ($b in $nfoBackupList) {
                    if (-not (Test-Path -LiteralPath $b.BakPath)) {
                        Write-Host "  $(col_a_error "[nfo还原跳过] 备份不存在：$($b.BakPath)")"; $failNfo++
                        continue
                    }
                    if ([System.IO.Path]::GetExtension($b.OldPath).ToLower() -ne '.nfo') {
                        Write-Host "  $(col_a_error "[nfo还原拒绝] 目标不是 .nfo：$($b.OldPath)")"; $failNfo++
                        continue
                    }
                    try {
                        Copy-Item -LiteralPath $b.BakPath -Destination $b.OldPath -Force
                        Remove-Item -LiteralPath $b.BakPath -Force -ErrorAction SilentlyContinue
                        Write-Host "  $(col_a_success "[nfo还原OK] $($b.NfoFile)")"
                    } catch { Write-Host "  $(col_a_error "[nfo还原失败] $($b.NfoFile) : $_")"; $failNfo++ }
                }
            }

            if ($orphannfoList.Count -gt 0) {
                Write-Host ""
                Write-Host "  $(col_a_text ('还原孤立nfo...'))"
                foreach ($o in $orphannfoList) {
                    if (-not (Test-Path -LiteralPath $o.BakPath)) { continue }
                    try {
                        [System.IO.File]::Copy($o.BakPath, $o.FilePath, $true)
                        Remove-Item -LiteralPath $o.BakPath -Force -ErrorAction SilentlyContinue
                        Write-Host "  $(col_a_success "[孤立nfo还原OK] $($o.FilePath)")"
                    } catch { Write-Host "  $(col_a_error "[孤立nfo还原失败] $($o.FilePath) : $_")"; $failNfo++ }
                }
            }
            if ($orphanImageList.Count -gt 0) {
                Write-Host ""
                Write-Host "  $(col_a_text ('还原孤立图片...'))"
                foreach ($o in $orphanImageList) {
                    if (-not (Test-Path -LiteralPath $o.BakPath)) { continue }
                    try {
                        [System.IO.File]::Copy($o.BakPath, $o.FilePath, $true)
                        Remove-Item -LiteralPath $o.BakPath -Force -ErrorAction SilentlyContinue
                        Write-Host "  $(col_a_success "[孤立图片还原OK] $($o.FilePath)")"
                    } catch { Write-Host "  $(col_a_error "[孤立图片还原失败] $($o.FilePath) : $_")"; $failNfo++ }
                }
            }

            Write-Host ""
            Write-Host "  $(col_a_text ('撤销完成，文件名还原成功：'))$(col_a_success "$($undoList.Count - $failFile)")$(col_a_text ' ｜失败：')$(col_a_error "$failFile")"
            if ($nfoBackupList.Count -gt 0) {
                Write-Host "  $(col_a_text ('nfo 还原失败：'))$(col_a_error "$failNfo")"
            }
            if ($orphannfoList.Count -gt 0 -or $orphanImageList.Count -gt 0) {
                Write-Host "  $(col_a_text ('孤立文件还原：'))$(col_a_success "$($orphannfoList.Count + $orphanImageList.Count)")$(col_a_text ' 个')"
            }
            Write-Host ""
            Wait-AnyKey "  $(col_a_text_muted '按任意键返回菜单...')"
        }
        elseif ($postResult -eq 'save') {
            $mapFile = Join-Path $PWD.Path "time_clear_map_$timeStamp.txt"
            $lines = @("# 备份时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", "# 模式：$modeName / $positionName", "# 原名`t新名")
            foreach ($u in $undoList) { $lines += "$($u.OldName)`t$($u.NewName)" }
            if ($nfoModifyLog.Count -gt 0) {
                $lines += "# nfo 内部标题覆盖记录"
                foreach ($l in $nfoModifyLog) { $lines += "# $($l.NfoFile) : '$($l.OldTitle)' → '$($l.NewTitle)'" }
            }
            $lines | Out-File -FilePath $mapFile -Encoding utf8
            Write-Host "  $(col_a_success ('✅  已保存映射文件：' + $mapFile))"
            Write-Host ""
            Wait-AnyKey "  $(col_a_text_muted '按任意键返回菜单...')"
        }
        return
    }

    # 没有可撤销内容时直接结束
    Wait-AnyKey "  $(col_a_text_muted '按任意键返回菜单...')"
    return
}
