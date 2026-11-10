<#
ext_lower.ps1
v2.0：扩展名大写转小写，对齐整套工具的 UI 规范，并加入递归开关。

【相对 v1.0 的改动】
    1、新增扫描范围选择：[y]递归子文件夹 / [n]仅当前文件夹（默认）
       递归用 [System.IO.Directory]::GetFiles 枚举，UNC 与超长路径更稳
    2、修正冲突检测：Windows 文件系统不区分大小写，
       旧逻辑下 Test-Path('a.mp4') 在仅有 A.MP4 时也返回 True，
       会把每个文件都误判为冲突。现先判断"是否纯大小写改名"，是则跳过占用检查。
    3、接入 modules\ui\ui.ps1：Clear-Screen + 统一标题块 + col_a_* 配色
    4、预览表从 Format-Table 改为视觉宽度对齐；递归时显示相对路径
    5、确认方式：裸 ReadKey → Select-Horizontal 横向菜单（默认 [n] 取消）
    6、新增撤销：扩展名从大写变小写后，原始大小写信息即丢失，
       撤销是唯一能精确还原的手段（不是防损坏，本操作不改文件内容）
    7、预览超过 30 行时只显示前 30 行，避免长列表刷屏

【保留的原有行为】
    - 仅当扩展名含大写字母才处理（-cmatch '[A-Z]'）
    - 只改扩展名，不碰文件名主体，不处理文件夹
    - 不做 .bak 备份（改名不涉及内容，无需备份）

【兼容性】PowerShell 5.1 / 7.x
#>

# ========== 加载公共 UI 框架 ==========
. (Join-Path $PSScriptRoot "ui\ui.ps1")

# ========== 表格工具 ==========
$script:W1 = 46   # 原文件名（递归时含相对路径）
$script:W2 = 46   # 新文件名

# Get-DisplayWidth 已移至 ui.ps1

# PadTo 已移至 ui.ps1

function Format-TruncatedName {
    param([string]$name, [int]$maxWidth = 44)
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

    $root = $PWD.ProviderPath
    $cwdDisplay = $root
    if ($cwdDisplay.Length -gt 78) {
        $cwdDisplay = $cwdDisplay.Substring(0, 38) + '…' + $cwdDisplay.Substring($cwdDisplay.Length - 38)
    }

    Write-Host "  $(col_a_title ('ext_lower.ps1 — 扩展名大写转小写'))"
    Write-Host "  $(col_a_line (sep))"
    Write-Host ""
    Write-Host "  $(col_a_text_muted '处理目录：')$(col_a_text $cwdDisplay)"
    Write-Host ""
    Write-Host "  $(col_a_text_muted '把文件扩展名统一转为小写（如 .MP4 → .mp4），只改扩展名，不动文件名主体')"
    Write-Host "  $(col_a_text_muted '不修改文件内容，无需备份；执行后可撤销以恢复原始大小写')"
    Write-Host ""

    # ---- 扫描范围 ----
    Write-Host "  $(col_a_text ('扫描范围：'))"
    Write-Host "  $(col_a_line (sep_weak))"

    $scopeOpts = @(
        @{ Label = "[n]仅当前文件夹（推荐）"; Value = "flat" }
        @{ Label = "[y]递归所有子文件夹"; Value = "recurse" }
        @{ Label = "[q/Esc]退出"; Value = "exit" }
    )
    $scopeResult = Select-Horizontal -Options $scopeOpts -Prompt "" -InitialIndex 0
    if ($null -eq $scopeResult -or $scopeResult -eq 'exit') { exit 0 }
    $DoRecurse = ($scopeResult -eq 'recurse')

    Write-Host ""
    if ($DoRecurse) { Write-Host "  $(col_a_warning '⚠  将递归扫描所有子文件夹')" }
    else            { Write-Host "  $(col_a_success '✅  仅扫描当前文件夹')" }

    # ---- 扫描 ----
    Write-Host ""
    Write-Host "  $(col_a_text_muted '正在索引文件，请稍候...')"

    $searchOpt = if ($DoRecurse) { [System.IO.SearchOption]::AllDirectories } else { [System.IO.SearchOption]::TopDirectoryOnly }
    $allPaths = @()
    try {
        $allPaths = [System.IO.Directory]::GetFiles($root, "*", $searchOpt)
    } catch {
        Write-Host "  $(col_a_error ('[错误] 枚举文件失败：' + $_.Exception.Message))"
        Wait-AnyKey "  按任意键退出..."
        exit 1
    }

    $todoList = @()
    foreach ($path in $allPaths) {
        $ext = [System.IO.Path]::GetExtension($path)
        if ([string]::IsNullOrEmpty($ext)) { continue }
        if ($ext -cnotmatch '[A-Z]') { continue }

        $dir     = [System.IO.Path]::GetDirectoryName($path)
        $name    = [System.IO.Path]::GetFileName($path)
        $base    = [System.IO.Path]::GetFileNameWithoutExtension($path)
        $newExt  = $ext.ToLower()
        $newName = $base + $newExt

        # 纯大小写改名（A.MP4 → a.mp4）时，目标"路径已存在"其实指向自己，不算冲突；
        # 只有新名字与原名并非仅差大小写时，才检查目标是否已被占用
        $isConflict = $false
        if ($newName -ine $name) {
            if (Test-Path -LiteralPath (Join-Path $dir $newName)) { $isConflict = $true }
        }
        if ($todoList | Where-Object { $_.Target -eq $newName -and $_.Dir -eq $dir }) { $isConflict = $true }

        # 递归时显示相对路径，便于定位
        if ($DoRecurse) {
            $relDir = $dir
            if ($relDir.StartsWith($root)) {
                $relDir = $relDir.Substring($root.Length).TrimStart('\')
            }
            $display = if ([string]::IsNullOrEmpty($relDir)) { $name } else { "$relDir\$name" }
            $displayTarget = if ([string]::IsNullOrEmpty($relDir)) { $newName } else { "$relDir\$newName" }
        } else {
            $display = $name
            $displayTarget = $newName
        }

        $todoList += [PSCustomObject]@{
            Dir         = $dir
            FullSource  = $path
            Source      = $name
            Target      = $newName
            Display     = $display
            DisplayNew  = $displayTarget
            Conflict    = $isConflict
        }
    }

    if ($todoList.Count -eq 0) {
        Write-Host "  $(col_a_success '✅  没有需要转换大写扩展名的文件。')"
        Wait-AnyKey
        exit 0
    }

    # ---- 预览 ----
    Write-Host ""
    Write-Host "  $(col_a_title ('重命名预览'))"
    Write-Host "  $(col_a_line (sep_weak))"
    $hdr = (PadTo "序号" 5) + (PadTo "原文件名" $script:W1) + (PadTo "新文件名" $script:W2) + "状态"
    Write-Host ("  " + $hdr)
    $sepLine = sep_weak -Len ($script:W1 + $script:W2 + 20)
    Write-Host ("  " + $sepLine)

    $maxShow = 30
    $showCount = [Math]::Min($maxShow, $todoList.Count)
    for ($i = 0; $i -lt $showCount; $i++) {
        $item = $todoList[$i]
        $op = if ($item.Conflict) { "$(col_a_error '[冲突 跳过]')" } else { "$(col_a_success '[RENAME]')" }
        $row = (PadTo ("{0,-3}" -f ($i + 1)) 5) + (Format-Cell $item.Display $script:W1) + (Format-Cell $item.DisplayNew $script:W2) + $op
        Write-Host ("  " + $row)
    }
    if ($todoList.Count -gt $maxShow) {
        Write-Host "  $(col_a_text_muted ("  … 还有 " + ($todoList.Count - $maxShow) + " 个未显示"))"
    }
    Write-Host ("  " + $sepLine)

    $validCount    = @($todoList | Where-Object { -not $_.Conflict }).Count
    $conflictCount = $todoList.Count - $validCount
    Write-Host "  $(col_a_text_muted ('共 ' + $todoList.Count + ' 个文件，可执行 ' + $validCount + ' 个'))"
    if ($conflictCount -gt 0) {
        Write-Host "  $(col_a_warning ('其中 ' + $conflictCount + ' 个因目标名已存在被跳过'))"
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

    # ---- 执行 ----
    Write-Host ""
    Write-Host "  $(col_a_title '开始重命名')"
    Write-Host ""
    $undoList = @()
    $failCount = 0

    foreach ($item in $todoList) {
        if ($item.Conflict) { continue }
        try {
            Rename-Item -LiteralPath $item.FullSource -NewName $item.Target -ErrorAction Stop
            Write-Host "  $(col_a_text_muted '原名：')" -NoNewline
            Write-Host "  $($item.Source)" -NoNewline
            Write-Host " → " -NoNewline
            Write-Host "  $($item.Target) " -NoNewline
            Write-Host "  $(col_a_success '[OK]')"
            $undoList += [PSCustomObject]@{
                AfterPath = Join-Path $item.Dir $item.Target
                OldName   = $item.Source
                NewName   = $item.Target
            }
        } catch {
            Write-Host "  $(col_a_error "❌ $($item.Source) 失败：$($_.Exception.Message)")"
            $failCount++
        }
    }

    Write-Host ""
    Write-Host "  $(col_a_success ('[√] 完成：成功 ' + $undoList.Count + ' 个' + $(if ($failCount -gt 0) { '，失败 ' + $failCount + ' 个' } else { '' })))"

    # ---- 事后菜单 ----
    Write-Host ""
    Write-Host ""
    Write-Host "  $(col_a_title ('后续操作选项'))"
    Write-Host "  $(col_a_text_muted '撤销会把扩展名恢复为原来的大小写（改名后原始大小写信息即丢失）')"
    Write-Host ""
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
            if (Test-Path -LiteralPath $u.AfterPath) {
                try {
                    Rename-Item -LiteralPath $u.AfterPath -NewName $u.OldName -ErrorAction Stop
                    Write-Host "  $(col_a_success "[撤销OK] $($u.NewName) → $($u.OldName)")"
                    $undoOk++
                } catch { Write-Host "  $(col_a_error "[撤销失败] $($u.AfterPath) : $_")"; $undoFail++ }
            } else { Write-Host "  $(col_a_error "[撤销跳过] 文件不存在：$($u.AfterPath)")"; $undoFail++ }
        }
        Write-Host ""
        Write-Host "  $(col_a_text ('撤销完成，成功：'))$(col_a_success $undoOk)$(col_a_text ' ｜失败：')$(col_a_error $undoFail)"
        Write-Host ""
        Wait-AnyKey "  $(col_a_text_muted '按任意键返回菜单...')"
    }

    return
}
