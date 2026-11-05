<#
lnk_replace.ps1
快捷方式（.lnk）目标路径批量替换，适配 NAS 迁移、盘符变更场景。

v2.0（2026-11-05）：完整改造，对齐整套工具的 UI 与安全规范。

【相对 v1.0 的改动】
    1、修复前缀为空导致路径被毁的严重问题
       旧版直接把 Read-Host 的输入丢进 String.Replace：
         · 新前缀为空  → 路径前缀被删除，快捷方式全部失效
         · 旧前缀为空  → PS 5.1 下 .Replace("", x) 会在每个字符间插入 x，路径彻底报废
         · 旧前缀过短（如只输入 "\"）→ 所有含反斜杠的路径被错误替换
       本版强制校验：旧前缀非空且 ≥ 3 字符、新前缀非空、两者不能相同。

    2、新增「替换后目标是否存在」检查
       旧版不管目标是否可达，NAS 未挂载或盘符写错也照样写入，用户点开才发现失效。
       预览表新增状态列：目标不存在时标 [目标不存在]，执行前可见。

    3、新增撤销
       执行后可按 [u] 一次性还原全部快捷方式的目标 / 起始位置 / 参数。
       同时保留原有的 [a] 替换并备份模式（生成 *_backup.lnk）。

    4、COM 对象改为循环外创建一次复用
       旧版在 foreach 内反复 New-Object -ComObject，数量多时明显变慢。

    5、接入 modules\ui\ui.ps1：Clear-Screen + 统一标题块 + col_a_* 配色 +
       Select-Horizontal 横向菜单；预览表改视觉宽度对齐（中文不再错列）。

    6、扫描路径改用 $PWD.ProviderPath，避免 UNC 场景下的 FileSystem 前缀。

【保留的原有行为】
    - 目标路径含 ? 的视为乱码（emoji 无法识别）直接跳过，并统计数量
    - 排除 *_backup.lnk，避免把备份当成待处理项
    - 递归 / 仅当前目录 可选
    - 推荐前缀自动复制到剪贴板

【兼容性】PowerShell 5.1 / 7.x
#>

# ========== 加载公共 UI 框架 ==========
. (Join-Path $PSScriptRoot "ui\ui.ps1")

# ========== 表格工具 ==========
$script:W1 = 4    # 序号
$script:W2 = 28   # 快捷方式
$script:W3 = 52   # 新目标

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
    param([string]$name, [int]$maxWidth = 50)
    if (-not $name) { return "" }
    if ((Get-DisplayWidth $name) -le $maxWidth) { return $name }
    $res = ""; $curW = 0
    foreach ($c in $name.ToCharArray()) {
        $cw = if ($c -gt 0x2E7F -or ($c -ge 0xFF00 -and $c -le 0xFFEF)) { 2 } else { 1 }
        if ($curW + $cw -gt ($maxWidth - 2)) { break }
        $res += $c; $curW += $cw
    }
    return $res + "…"
}

function Format-Cell {
    param([string]$Text, [int]$Width)
    return (PadTo (Format-TruncatedName -name $Text -maxWidth ($Width - 2)) $Width)
}

# ========== 快捷方式读写 ==========
# COM 对象在循环外创建一次，全流程复用
$Script:Shell = $null

function Get-LnkShell {
    if ($null -eq $Script:Shell) {
        $Script:Shell = New-Object -ComObject WScript.Shell
    }
    return $Script:Shell
}

function Get-LnkInfo {
    param([string]$Path)
    try {
        $sc = (Get-LnkShell).CreateShortcut($Path)
        return [PSCustomObject]@{
            Target  = $sc.TargetPath
            WorkDir = $sc.WorkingDirectory
            Args    = $sc.Arguments
            Ok      = $true
        }
    } catch {
        return [PSCustomObject]@{ Target = ""; WorkDir = ""; Args = ""; Ok = $false; Error = $_.Exception.Message }
    }
}

function Set-LnkInfo {
    param([string]$Path, [string]$Target, [string]$WorkDir, [string]$Arguments)
    $sc = (Get-LnkShell).CreateShortcut($Path)
    $sc.TargetPath       = $Target
    $sc.WorkingDirectory = $WorkDir
    $sc.Arguments        = $Arguments
    $sc.Save()
}

# ========== 主循环 ==========
while ($true) {

    Clear-Screen
    Write-Host ''

    $scanRoot = $PWD.ProviderPath
    $cwdDisplay = $scanRoot
    if ($cwdDisplay.Length -gt 78) {
        $cwdDisplay = $cwdDisplay.Substring(0, 38) + '…' + $cwdDisplay.Substring($cwdDisplay.Length - 38)
    }

    Write-Host "  $(col_a_title ('lnk_replace.ps1 — 快捷方式目标路径批量替换'))"
    Write-Host "  $(col_a_line (sep))"
    Write-Host ''
    Write-Host "  $(col_a_text_muted '处理目录：')$(col_a_text $cwdDisplay)"
    Write-Host ''
    Write-Host "  $(col_a_text_muted '批量修改 .lnk 的目标路径 / 起始位置 / 参数，适用于 NAS 迁移、盘符变更')"
    Write-Host "  $(col_a_text_muted '目标路径含 ? 的视为 emoji 乱码，自动跳过')"
    Write-Host ''

    # ---- 扫描范围 ----
    Write-Host ''
    Write-Host "  $(col_a_title '扫描范围')"
    Write-Host "  $(col_a_line (sep))"
    $recurseOpts = @(
        @{ Label = "[y]递归扫描子文件夹（推荐）"; Value = "yes" }
        @{ Label = "[n]仅当前文件夹"; Value = "no" }
        @{ Label = "[q/Esc]退出"; Value = "quit" }
    )
    $recurseResult = Select-Horizontal -Options $recurseOpts -Prompt "" -InitialIndex 0
    if ($null -eq $recurseResult -or $recurseResult -eq 'quit') { exit 0 }
    $doRecurse = ($recurseResult -eq 'yes')

    Write-Host ''
    Write-Host "  $(col_a_text_muted '正在扫描 *.lnk ...')"

    $lnkList = @(Get-ChildItem -LiteralPath $scanRoot -Filter '*.lnk' -Recurse:$doRecurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '_backup\.lnk$' })

    if ($lnkList.Count -eq 0) {
        Write-Host "  $(col_a_warning '⚠  没有找到任何快捷方式。')"
        Wait-AnyKey
        exit 0
    }

    # ---- 读取目标 ----
    $candidates = @()
    $garbleCount = 0
    $readFailCount = 0

    foreach ($f in $lnkList) {
        $info = Get-LnkInfo -Path $f.FullName
        if (-not $info.Ok) {
            Write-Host "  $(col_a_error "❌ $($f.Name) 读取失败：$($info.Error)")"
            $readFailCount++
            continue
        }
        if ([string]::IsNullOrWhiteSpace($info.Target)) {
            Write-Host "  $(col_a_text_muted "· $($f.Name) 目标为空，跳过")"
            $readFailCount++
            continue
        }
        if ($info.Target -match '\?') {
            Write-Host "  $(col_a_warning "⚠ $($f.Name) → $($info.Target)（含乱码，跳过）")"
            $garbleCount++
            continue
        }
        $candidates += [PSCustomObject]@{
            FileName    = $f.Name
            FileFullName = $f.FullName
            OrigTarget  = $info.Target
            OrigWorkDir = $info.WorkDir
            OrigArgs    = $info.Args
        }
    }

    Write-Host ''
    Write-Host "  $(col_a_line (sep_weak))"
    Write-Host "  $(col_a_text_muted '扫描到的快捷方式：')$(col_a_text $lnkList.Count)$(col_a_text_muted '  ｜ 乱码跳过：')$(col_a_warning $garbleCount)$(col_a_text_muted '  ｜ 读取失败：')$(col_a_error $readFailCount)$(col_a_text_muted '  ｜ 可处理：')$(col_a_success $candidates.Count)"
    Write-Host "  $(col_a_line (sep_weak))"

    if ($candidates.Count -eq 0) {
        Write-Host ''
        Write-Host "  $(col_a_warning '⚠  没有可处理的有效快捷方式。')"
        Wait-AnyKey
        exit 0
    }

    # ---- 输入前缀（带校验循环）----
    $firstTarget = $candidates[0].OrigTarget
    $lastSlash = $firstTarget.LastIndexOf('\')
    $suggestPrefix = if ($lastSlash -gt 0) { $firstTarget.Substring(0, $lastSlash + 1) } else { $firstTarget }
    try { Set-Clipboard -Value $suggestPrefix } catch { }

    Write-Host ''
    Write-Host "  $(col_a_text_muted '推荐原始前缀（已复制到剪贴板）：')"
    Write-Host "  $(col_a_text $suggestPrefix)"
    Write-Host ''

    $oldPrefix = ''
    $newPrefix = ''
    $inputOk = $false

    while (-not $inputOk) {
        $oldPrefix = Read-Host '  输入【原始路径前缀】(Ctrl+V 粘贴，直接回车放弃)'
        if ([string]::IsNullOrWhiteSpace($oldPrefix)) {
            Write-Host "  $(col_a_text_muted '⚪  已放弃，未做任何修改。')"
            Wait-AnyKey
            exit 0
        }
        if ($oldPrefix.Length -lt 3) {
            Write-Host "  $(col_a_error '❌ 前缀太短（至少 3 个字符），否则会大面积误替换，请重新输入。')"
            continue
        }

        $newPrefix = Read-Host '  输入【替换后的新前缀】(直接回车放弃)'
        if ([string]::IsNullOrWhiteSpace($newPrefix)) {
            Write-Host "  $(col_a_text_muted '⚪  已放弃，未做任何修改。')"
            Wait-AnyKey
            exit 0
        }
        if ($newPrefix.TrimEnd('\') -ieq $oldPrefix.TrimEnd('\')) {
            Write-Host "  $(col_a_error '❌ 新旧前缀相同，无需替换，请重新输入。')"
            continue
        }

        $inputOk = $true
    }

    # ---- 生成变更列表 ----
    $changeList = @()
    foreach ($item in $candidates) {
        if ($item.OrigTarget.StartsWith($oldPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            $newTarget = $item.OrigTarget.Substring($oldPrefix.Length)
            $newTarget = $newPrefix.TrimEnd('\') + '\' + $newTarget.TrimStart('\')

            # 起始位置（WorkingDirectory）通常【不含】末尾反斜杠，
            # 直接和带反斜杠的前缀比 StartsWith 会匹配失败，故先规范化两边
            $newWorkDir = $item.OrigWorkDir
            if (-not [string]::IsNullOrWhiteSpace($item.OrigWorkDir)) {
                $oldNorm = $oldPrefix.TrimEnd('\')
                $wdNorm  = $item.OrigWorkDir.TrimEnd('\')
                if ($wdNorm -ieq $oldNorm) {
                    # 起始位置正好等于前缀本身
                    $newWorkDir = $newPrefix.TrimEnd('\')
                } elseif ($wdNorm.StartsWith($oldNorm + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                    $newWorkDir = $newPrefix.TrimEnd('\') + '\' + $wdNorm.Substring($oldNorm.Length).TrimStart('\')
                }
            }

            $newArgs = $item.OrigArgs
            if (-not [string]::IsNullOrWhiteSpace($newArgs)) {
                $newArgs = $newArgs.Replace($oldPrefix, $newPrefix)
            }

            $targetExists = Test-Path -LiteralPath $newTarget

            $changeList += [PSCustomObject]@{
                FileName     = $item.FileName
                FileFullName = $item.FileFullName
                OldTarget    = $item.OrigTarget
                OldWorkDir   = $item.OrigWorkDir
                OldArgs      = $item.OrigArgs
                NewTarget    = $newTarget
                NewWorkDir   = $newWorkDir
                NewArgs      = $newArgs
                TargetExists = $targetExists
            }
        }
    }

    if ($changeList.Count -eq 0) {
        Write-Host ''
        Write-Host "  $(col_a_warning '⚠  没有任何快捷方式的目标路径匹配该前缀。')"
        Write-Host "  $(col_a_text_muted '   请检查粘贴的前缀是否与原目标一致（注意末尾的反斜杠）。')"
        Wait-AnyKey
        continue
    }

    # ---- 预览表 ----
    Write-Host ''
    Write-Host ''
    Write-Host "  $(col_a_title '替换预览')"
    Write-Host "  $(col_a_line (sep))"
    $hdr = (PadTo '序号' $script:W1) + (PadTo '快捷方式' $script:W2) + (PadTo '新目标' $script:W3) + '状态'
    Write-Host ("  " + $hdr)
    $sepLine = sep_weak -Len ($script:W1 + $script:W2 + $script:W3 + 14)
    Write-Host ("  " + $sepLine)

    $maxShow = 30
    $showCount = [Math]::Min($maxShow, $changeList.Count)
    for ($i = 0; $i -lt $showCount; $i++) {
        $c = $changeList[$i]
        $status = if ($c.TargetExists) { "$(col_a_success '[存在]')" } else { "$(col_a_error '[目标不存在]')" }
        $row = (PadTo ("{0,-3}" -f ($i + 1)) $script:W1) + (Format-Cell $c.FileName $script:W2) + (Format-Cell $c.NewTarget $script:W3) + $status
        Write-Host ("  " + $row)
    }
    if ($changeList.Count -gt $maxShow) {
        Write-Host "  $(col_a_text_muted ("  … 还有 " + ($changeList.Count - $maxShow) + " 个未显示"))"
    }
    Write-Host ("  " + $sepLine)

    $missingCount = @($changeList | Where-Object { -not $_.TargetExists }).Count
    Write-Host "  $(col_a_text_muted ('共 ' + $changeList.Count + ' 个快捷方式将被修改'))"
    if ($missingCount -gt 0) {
        Write-Host "  $(col_a_warning ('其中 ' + $missingCount + ' 个的新目标当前不存在（NAS 未挂载？路径写错？）'))"
    }
    Write-Host ''

    # ---- 确认 ----
    $confirmOpts = @(
        @{ Label = "[a]替换并备份原 .lnk（推荐）"; Value = "backup" }
        @{ Label = "[y]直接替换（不备份）"; Value = "direct" }
        @{ Label = "[q/Esc]取消"; Value = "cancel" }
    )
    $confirmResult = Select-Horizontal -Options $confirmOpts -Prompt "" -InitialIndex 0
    if ($null -eq $confirmResult -or $confirmResult -eq 'cancel') {
        Write-Host "  $(col_a_text_muted '已取消，未做任何修改。')"
        Wait-AnyKey
        continue
    }

    # ---- 执行 ----
    Write-Host ''
    Write-Host "  $(col_a_title '开始替换')"
    Write-Host ''

    $undoList = @()
    $okCount = 0
    $failCount = 0

    foreach ($c in $changeList) {
        try {
            if ($confirmResult -eq 'backup') {
                $bakPath = $c.FileFullName -replace '\.lnk$', '_backup.lnk'
                Copy-Item -LiteralPath $c.FileFullName -Destination $bakPath -Force
            }
            Set-LnkInfo -Path $c.FileFullName -Target $c.NewTarget -WorkDir $c.NewWorkDir -Arguments $c.NewArgs

            $undoList += [PSCustomObject]@{
                FileFullName = $c.FileFullName
                OldTarget    = $c.OldTarget
                OldWorkDir   = $c.OldWorkDir
                OldArgs      = $c.OldArgs
            }

            Write-Host "  $(col_a_success "✅ $($c.FileName)")"
            Write-Host "     $(col_a_text_muted '→ ')$(col_a_text $c.NewTarget)"
            $okCount++
        } catch {
            Write-Host "  $(col_a_error "❌ $($c.FileName) 修改失败：$($_.Exception.Message)")"
            $failCount++
        }
    }

    Write-Host ''
    Write-Host "  $(col_a_line (sep))"
    Write-Host "  $(col_a_success ('[√] 完成：成功 ' + $okCount + ' 个' + $(if ($failCount -gt 0) { '，失败 ' + $failCount + ' 个' } else { '' })))"

    # ---- 事后菜单 ----
    Write-Host ''
    Write-Host ''
    Write-Host "  $(col_a_title '后续操作选项')"
    Write-Host "  $(col_a_text_muted '撤销会把这批快捷方式的目标路径恢复为修改前的值')"
    Write-Host ''

    $postOpts = @(
        @{ Label = "[u]撤销本次替换"; Value = "undo" }
        @{ Label = "[q/Esc]退出"; Value = "exit" }
    )
    $postResult = Select-Horizontal -Options $postOpts -Prompt "" -InitialIndex 0
    if ($null -eq $postResult) { exit 0 }

    if ($postResult -eq 'undo') {
        Write-Host ''
        Write-Host "  $(col_a_warning '⚠️  开始撤销...')"
        $undoOk = 0; $undoFail = 0
        [array]::Reverse($undoList)
        foreach ($u in $undoList) {
            try {
                Set-LnkInfo -Path $u.FileFullName -Target $u.OldTarget -WorkDir $u.OldWorkDir -Arguments $u.OldArgs
                Write-Host "  $(col_a_success "↩ $([System.IO.Path]::GetFileName($u.FileFullName)) → $($u.OldTarget)")"
                $undoOk++
            } catch {
                Write-Host "  $(col_a_error "❌ $($u.FileFullName) 撤销失败：$($_.Exception.Message)")"
                $undoFail++
            }
        }
        Write-Host ''
        Write-Host "  $(col_a_text ('撤销完成，成功：'))$(col_a_success $undoOk)$(col_a_text ' ｜失败：')$(col_a_error $undoFail)"
        Write-Host ''
        Wait-AnyKey "  $(col_a_text_muted '按任意键返回菜单...')"
    }

    exit 0
}