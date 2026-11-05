<#
cn_to_arabic.ps1
v2.0：文件名/文件夹名汉字数字批量转阿拉伯数字，对齐整套工具的 UI 与撤销规范。

【相对 v1.0 的改动】
    1、接入 modules\ui\ui.ps1：Clear-Screen + 统一标题块 + col_a_* 配色
    2、预览表：弃用 Format-Table | Out-String 再按行染色的做法，
       改为视觉宽度对齐的自绘表格（中文不再错列，表头不再靠字符串前缀判断）
    3、确认方式：裸 ReadKey → Select-Horizontal 横向菜单
    4、新增冲突检测：目标名已存在时标 [冲突] 并跳过，
       旧版遇到重名会在 Rename-Item 中途抛错，且前面的改动已经落地、状态不一致
    5、撤销：保留原有 [u] 撤销，改为菜单选择，并接入统一的事后菜单样式
    6、扫描改用 Get-ChildItem -LiteralPath（与旧版一致，兼容 NAS 带 [] 的路径）

【保留的原有行为】
    - 仅处理当前目录的【文件 + 一级子文件夹】，不递归到子文件夹内部
    - 汉字数字映射：一~十，支持 十一 / 二十 / 二十三 等百位以内组合
    - 单字补零：一 → 01 … 九 → 09；十 → 10
    - 无法解析的组合跳过，不改名

【兼容性】PowerShell 5.1 / 7.x
#>

# ========== 加载公共 UI 框架 ==========
. (Join-Path $PSScriptRoot "ui\ui.ps1")

# ========== 汉字数字解析 ==========
$cnMap = @{ "一" = 1; "二" = 2; "三" = 3; "四" = 4; "五" = 5; "六" = 6; "七" = 7; "八" = 8; "九" = 9; "十" = 10 }

function Convert-HanNum {
    param([string]$han)
    if ([string]::IsNullOrEmpty($han)) { return $null }
    if ($han -eq "十") { return "10" }
    if ($han -match "^十([一二三四五六七八九])$") { return ("1" + $cnMap[$Matches[1]]) }
    if ($han -match "^([一二三四五六七八九])十$") { return (($cnMap[$Matches[1]] * 10).ToString()) }
    if ($han -match "^([一二三四五六七八九])十([一二三四五六七八九])$") {
        return (($cnMap[$Matches[1]] * 10 + $cnMap[$Matches[2]]).ToString())
    }
    if ($han.Length -eq 1 -and $cnMap.ContainsKey($han)) { return ("0" + $cnMap[$han]) }
    return $null
}

# ========== 表格工具 ==========
$script:W1 = 6    # 类型
$script:W2 = 40   # 旧名称
$script:W3 = 40   # 新名称

function Get-DisplayWidth {
    param([string]$s)
    $w = 0
    foreach ($c in $s.ToCharArray()) {
        $w += if ($c -gt 0x2E7F -or ($c -ge 0xFF00 -and $c -le 0xFFEF)) { 2 } else { 1 }
    }
    return $w
}

function PadTo {
    param([string]$Text, [int]$Width)
    $pad = $Width - (Get-DisplayWidth $Text)
    if ($pad -lt 0) { $pad = 0 }
    return $Text + (" " * $pad)
}

function Format-TruncatedName {
    param([string]$name, [int]$maxWidth = 38)
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

function Format-Cell {
    param([string]$Text, [int]$Width)
    return (PadTo (Format-TruncatedName -name $Text -maxWidth ($Width - 2)) $Width)
}

# ========== 主循环 ==========
while ($true) {

    Clear-Screen
    Write-Host ""

    $cwdDisplay = $PWD.ProviderPath
    if ($cwdDisplay.Length -gt 78) {
        $cwdDisplay = $cwdDisplay.Substring(0, 38) + '…' + $cwdDisplay.Substring($cwdDisplay.Length - 38)
    }

    Write-Host "  $(col_a_title ('cn_to_arabic.ps1 — 汉字数字转阿拉伯数字'))"
    Write-Host "  $(col_a_line (sep))"
    Write-Host ""
    Write-Host "  $(col_a_text_muted '处理目录：')$(col_a_text $cwdDisplay)"
    Write-Host ""
    Write-Host "  $(col_a_text_muted '把文件名/文件夹名里的汉字数字换成阿拉伯数字：一→01 … 九→09，十→10，二十三→23')"
    Write-Host "  $(col_a_text_muted '仅处理当前目录的文件与一级子文件夹，不递归；无法解析的组合自动跳过')"
    Write-Host "  $(col_a_text_muted '此工具不能识别中文语义，仅对常见汉字数字做转换，请自行根据预览判断修改')"
    Write-Host ""

    # ---- 扫描 ----
    $items = Get-ChildItem -LiteralPath $PWD -Force
    $changeList = @()

    foreach ($item in $items) {
        $oldName = $item.Name
        $newName = $oldName
        $changed = $false

        # v2.0：改为「按位置重建」，不再用 String.Replace 全串替换。
        #   旧写法的问题：先匹配到「一」时会 Replace 掉全串所有「一」，
        #   把后面的「十一」破坏成「十01」，导致混合编号的文件名被改花。
        #   字符类补入「百/千」：让「一百」作为一个整体被识别，
        #   Convert-HanNum 不支持时返回 $null → 整个 token 原样保留，
        #   避免出现「第一百集 → 第01百集」这种半截转换。
        $matchesAll = [regex]::Matches($oldName, "[一二三四五六七八九十百千]+")
        if ($matchesAll.Count -gt 0) {
            $sb = New-Object System.Text.StringBuilder
            $lastPos = 0
            foreach ($m in $matchesAll) {
                [void]$sb.Append($oldName.Substring($lastPos, $m.Index - $lastPos))
                $arabic = Convert-HanNum -han $m.Value
                if ($null -eq $arabic) {
                    [void]$sb.Append($m.Value)
                } else {
                    # 单字补零（十 除外）
                    if ($m.Value.Length -eq 1 -and $arabic -ne "10") {
                        $arabic = "0" + ($arabic -replace "^0", "")
                    }
                    [void]$sb.Append($arabic)
                }
                $lastPos = $m.Index + $m.Length
            }
            [void]$sb.Append($oldName.Substring($lastPos))
            $newName = $sb.ToString()
            $changed = ($newName -ne $oldName)
        }

        if ($changed -and $newName -ne $oldName) {
            # 兼容：DirectoryInfo 没有 DirectoryName 属性（只有 FileInfo 有），
            # 之前直接用 $item.DirectoryName，处理文件夹时得到 $null，
            # 导致后续 Join-Path 报「无法将自变量绑定到参数 Path」。
            # Split-Path -Parent 对文件和文件夹都有效。
            $parentDir = Split-Path -Parent $item.FullName
            $type = if ($item.PSIsContainer) { "文件夹" } else { "文件" }

            # 冲突检测：目标名已存在，或本批次内已有同名目标
            $isConflict = $false
            if (Test-Path -LiteralPath (Join-Path $parentDir $newName)) { $isConflict = $true }
            if ($changeList | Where-Object { $_.NewName -eq $newName -and $_.ParentDir -eq $parentDir }) {
                $isConflict = $true
            }

            $changeList += [PSCustomObject]@{
                ParentDir = $parentDir
                OldName   = $oldName
                NewName   = $newName
                Type      = $type
                Conflict  = $isConflict
            }
        }
    }

    if ($changeList.Count -eq 0) {
        Write-Host "  $(col_a_success '✅  没有匹配到需要修改的文件/文件夹。')"
        Wait-AnyKey
        exit 0
    }

    # ---- 预览 ----
    Write-Host "  $(col_a_title ('重命名预览'))"
    Write-Host "  $(col_a_line (sep_weak))"
    $hdr = (PadTo "序号" 5) + (PadTo "类型" $script:W1) + (PadTo "旧名称" $script:W2) + (PadTo "新名称" $script:W3) + "状态"
    Write-Host ("  " + $hdr)
    $sepLine = sep_weak -Len ($script:W1 + $script:W2 + $script:W3 + 20)
    Write-Host ("  " + $sepLine)

    $idx = 1
    foreach ($c in $changeList) {
        $op = if ($c.Conflict) { "$(col_a_error '[冲突 跳过]')" } else { "$(col_a_success '[RENAME]')" }
        $row = (PadTo ("{0,-3}" -f $idx) 5) + (PadTo $c.Type $script:W1) + (Format-Cell $c.OldName $script:W2) + (Format-Cell $c.NewName $script:W3) + $op
        Write-Host ("  " + $row)
        $idx++
    }
    Write-Host ("  " + $sepLine)

    $validCount    = @($changeList | Where-Object { -not $_.Conflict }).Count
    $conflictCount = $changeList.Count - $validCount
    Write-Host "  $(col_a_text_muted ('共 ' + $changeList.Count + ' 项，可执行 ' + $validCount + ' 项'))"
    if ($conflictCount -gt 0) {
        Write-Host "  $(col_a_warning ('其中 ' + $conflictCount + ' 项因目标名已存在被跳过'))"
    }
    Write-Host ""

    if ($validCount -eq 0) {
        Write-Host "  $(col_a_warning '⚠  没有可执行的改名（全部冲突）。')"
        Wait-AnyKey
        exit 0
    }

    # ---- 确认 ----
    $execOpts = @(
        @{ Label = "[y]执行重命名"; Value = "exec" }
        @{ Label = "[n]取消"; Value = "cancel" }
    )
    $execResult = Select-Horizontal -Options $execOpts -Prompt "" -InitialIndex 0
    if ($null -eq $execResult -or $execResult -eq 'cancel') {
        Write-Host "  $(col_a_text_muted '已取消，未做任何修改。')"
        Wait-AnyKey
        exit 0
    }

    # ---- 执行（文件夹先改，再改文件，避免父目录名变化影响子项路径）----
    Write-Host ""
    Write-Host "  $(col_a_title '开始重命名')"
    Write-Host ""

    $execList = @($changeList | Where-Object { -not $_.Conflict -and $_.Type -eq "文件夹" }) +
                @($changeList | Where-Object { -not $_.Conflict -and $_.Type -eq "文件" })

    $undoList = @()
    $failCount = 0

    foreach ($item in $execList) {
        $oldFull = Join-Path $item.ParentDir $item.OldName
        if (-not (Test-Path -LiteralPath $oldFull)) {
            Write-Host "  $(col_a_warning "⚠ 跳过，找不到：$oldFull")"
            $failCount++
            continue
        }
        try {
            Rename-Item -LiteralPath $oldFull -NewName $item.NewName -ErrorAction Stop
            Write-Host "  $(col_a_text_muted ("[" + $item.Type + "] "))" -NoNewline
            Write-Host "  $($item.OldName)" -NoNewline
            Write-Host " → " -NoNewline
            Write-Host "  $($item.NewName) " -NoNewline
            Write-Host "  $(col_a_success '[OK]')"
            $undoList += [PSCustomObject]@{
                ParentDir = $item.ParentDir
                OldName   = $item.OldName
                NewName   = $item.NewName
                Type      = $item.Type
            }
        } catch {
            Write-Host "  $(col_a_error "❌ $($item.OldName) 失败：$($_.Exception.Message)")"
            $failCount++
        }
    }

    Write-Host ""
    Write-Host "  $(col_a_success ('[√] 完成：成功 ' + $undoList.Count + ' 项' + $(if ($failCount -gt 0) { '，失败 ' + $failCount + ' 项' } else { '' })))"

    # ---- 事后菜单 ----
    Write-Host ""
    Write-Host ""
    Write-Host "  $(col_a_title ('后续操作选项'))"
    $postOpts = @(
        @{ Label = "[u]撤销本次改名"; Value = "undo" }
        @{ Label = "[q/Esc]退出"; Value = "exit" }
    )
    $postResult = Select-Horizontal -Options $postOpts -Prompt "" -InitialIndex 0
    if ($null -eq $postResult) { exit 0 }

    if ($postResult -eq 'undo') {
        Write-Host ""
        Write-Host "  $(col_a_warning ('⚠️  开始撤销...'))"
        [array]::Reverse($undoList)
        $undoOk = 0; $undoFail = 0
        foreach ($u in $undoList) {
            $curPath = Join-Path $u.ParentDir $u.NewName
            if (Test-Path -LiteralPath $curPath) {
                try {
                    Rename-Item -LiteralPath $curPath -NewName $u.OldName -ErrorAction Stop
                    Write-Host "  $(col_a_success "[撤销OK] [$($u.Type)] $($u.NewName) → $($u.OldName)")"
                    $undoOk++
                } catch { Write-Host "  $(col_a_error "[撤销失败] $curPath : $_")"; $undoFail++ }
            } else { Write-Host "  $(col_a_error "[撤销跳过] 找不到：$curPath")"; $undoFail++ }
        }
        Write-Host ""
        Write-Host "  $(col_a_text ('撤销完成，成功：'))$(col_a_success $undoOk)$(col_a_text ' ｜失败：')$(col_a_error $undoFail)"
        Write-Host ""
        Wait-AnyKey "  $(col_a_text_muted '按任意键返回菜单...')"
    }

    return
}