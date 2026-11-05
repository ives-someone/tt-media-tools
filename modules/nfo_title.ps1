<#
nfo_title.ps1
v4.0：全面重写，对齐整套工具的 UI 规范与 nfo 写入安全规范。

【本版保留的原有行为】
    1. 只处理「视频文件 + 同名 .nfo」配对，不处理 -poster/-fanart 等附属 nfo
    2. 只改写已存在的 <title> / <sorttitle>，不新增标签（与旧版一致）
    3. 三种模式：y 仅改内外不一致 / a 全覆盖重写 / s 仅导出日志
    4. 改写前生成 .bak，完成后可 u 撤销

【本版修正的问题】
    1. 编码：旧版无条件 ReadAllText/WriteAllText(UTF8)，GBK / UTF-16 的 nfo 会被整份写坏。
       改为字节读取 + BOM/严格UTF-8/GB18030 探测，并按原编码回写。
    2. XML 转义：旧版直接拼接标题，文件名含 & < > 时写出非法 XML；
       含 $ 时会被 -replace 当成分组引用吞掉。改为 SecurityElement::Escape + $ 转义。
    3. 标签正则：旧版 <title>.*</title> 为贪婪匹配，同一行有多个标签时会跨标签吞内容；
       改为 <title\b[^>]*>.*?</title> 惰性 + 允许标签带属性。
    4. 孤立 nfo 判定：旧版仅排除带连字符的 -poster 等，
       movie.nfo / tvshow.nfo / poster.nfo 会被误判为孤立文件并删除。
       改为复用 time_add/time_clear 的词干白名单 Test-ArtBaseName。
    5. 孤立清理默认值：旧版「回车/Y = 删除」，误触即删；改为默认 [s]跳过。
    6. 交互：Get-SingleKey 逐键 → Select-Horizontal 横向菜单；cls → Clear-Screen；
       裸 -ForegroundColor → col_a_* 配色体系。
    7. 撤销：旧版用 ReadAllText/WriteAllText 还原，GBK 备份会被转码；
       改为字节级 Copy-Item。

【兼容性】PowerShell 5.1 / 7.x 均可运行，未使用 PS7 专属语法。
#>

# ========== 加载公共 UI 框架 ==========
. (Join-Path $PSScriptRoot "ui\ui.ps1")

# ========== 配置 ==========
$videoExts = @('mp4','mov','mkv','avi','flv','wmv','m4v','ts','mpg','mpeg','f4v','m2ts','mts','webm','rmvb')

# 附属文件词干白名单（与 time_add.ps1 / time_clear.ps1 口径一致）
$artStemList  = @('poster','fanart','cover','folder','thumb','banner','clearart','clearlogo',
                  'logo','landscape','backdrop','background','disc','discart','cdart','default')
$metaStemList = @('movie','tvshow','season')
$stemTail     = '([ _-]?\(?\d+\)?)?$'

$artBareRegex     = '^(' + ($artStemList  -join '|') + ')' + $stemTail
$metaBareRegex    = '^(' + ($metaStemList -join '|') + ')' + $stemTail
$artPrefixedRegex = '.+-(' + (($artStemList + $metaStemList) -join '|') + ')' + $stemTail

function Test-ArtBaseName {
    param([string]$BaseName)
    if ([string]::IsNullOrEmpty($BaseName)) { return $false }
    if ($BaseName -match $artBareRegex)     { return $true }
    if ($BaseName -match $metaBareRegex)    { return $true }
    if ($BaseName -match $artPrefixedRegex) { return $true }
    return $false
}

# ========== 表格格式化 ==========
$script:W1 = 4    # 序号
$script:W2 = 34   # 视频文件 / nfo 文件
$script:W3 = 26   # 当前 title
$script:W4 = 26   # 目标值
$tableSep = sep_weak -Len ($script:W1 + $script:W2 + $script:W3 + $script:W4 + 16)

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
    param([string]$name, [int]$maxWidth = 30)
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

# 单元格：截断 + 按视觉宽度补齐
function Format-Cell {
    param([string]$Text, [int]$Width, [int]$TruncTo = 0)
    if ($TruncTo -le 0) { $TruncTo = $Width - 2 }
    if ($TruncTo -lt 4) { $TruncTo = 4 }
    return (PadTo (Format-TruncatedName -name $Text -maxWidth $TruncTo) $Width)
}

function Show-TableHeader {
    param([string]$H2, [string]$H3, [string]$H4)
    $hdr = (PadTo "序号" $script:W1) + (PadTo $H2 $script:W2) + (PadTo $H3 $script:W3) + (PadTo $H4 $script:W4) + "状态"
    Write-Host ("  " + $hdr)
    Write-Host "  $(col_a_line $tableSep)"
}

# ========== nfo 编码探测 ==========
# 返回 Encoding；无 BOM 且非合法 UTF-8 时尝试 GB18030；
# 系统缺少 GB18030 代码页时返回 $null（调用方跳过该文件，绝不用错误编码写盘）
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

    $cwdDisplay = $PWD.ProviderPath
    if ($cwdDisplay.Length -gt 78) {
        $cwdDisplay = $cwdDisplay.Substring(0, 38) + '…' + $cwdDisplay.Substring($cwdDisplay.Length - 38)
    }

    Write-Host "  $(col_a_title ('nfo_title.ps1 — NFO 内部名称同步与清理'))"
    Write-Host "  $(col_a_line (sep))"
    Write-Host ""
    Write-Host "  $(col_a_text_muted '处理目录：')$(col_a_text $cwdDisplay)"
    Write-Host ""
    Write-Host "  $(col_a_text_muted '把与视频同名的 nfo 内部 <title>/<sorttitle> 刷新为视频文件名（不含扩展名）')"
    Write-Host "  $(col_a_text_muted '仅处理已存在的标签，不新增；只在标签存在时改写，避免破坏原有 nfo 结构')"
    Write-Host ""

    # ---- 扫描配对 ----
    $allFiles  = Get-ChildItem -File
    $videoList = $allFiles | Where-Object { $videoExts -contains $_.Extension.TrimStart('.').ToLower() }

    $workItems = @()
    foreach ($vid in $videoList) {
        $vidBase = $vid.BaseName
        if (Test-ArtBaseName -BaseName $vidBase) { continue }

        $nfoPath = Join-Path $vid.Directory.FullName "$vidBase.nfo"
        if (-not (Test-Path -LiteralPath $nfoPath)) { continue }

        $nfoObj = Get-Item -LiteralPath $nfoPath
        $oldTitle = $null; $oldSort = $null; $readOk = $true
        try {
            $bytes = [System.IO.File]::ReadAllBytes($nfoObj.FullName)
            $enc = Get-NfoEncoding -Bytes $bytes
            if ($null -eq $enc) {
                $readOk = $false
            } else {
                $rawText = $enc.GetString($bytes)
                if ($rawText -match '<title\b[^>]*>(.*?)</title>') { $oldTitle = $matches[1] }
                if ($rawText -match '<sorttitle\b[^>]*>(.*?)</sorttitle>') { $oldSort = $matches[1] }
            }
        } catch { $readOk = $false }

        $workItems += [PSCustomObject]@{
            VideoName    = $vid.Name
            NfoFile      = $nfoObj.Name
            NfoFullPath  = $nfoObj.FullName
            NewBaseName  = $vidBase
            OldTitle     = $oldTitle
            OldSortTitle = $oldSort
            Readable     = $readOk
        }
    }

    if ($workItems.Count -eq 0) {
        Write-Host "  $(col_a_warning ('⚠  当前目录没有找到【视频 + 同名 nfo】配对。'))"
        Wait-AnyKey
        exit 0
    }

    # ---- 孤立 nfo 检测（对齐 time_add/time_clear 的白名单口径）----
    $allNfoFiles = $allFiles | Where-Object { $_.Extension.ToLower() -eq '.nfo' }
    $pairedNames = $workItems | ForEach-Object { $_.NfoFile }
    $orphanNfos  = @()

    foreach ($nfo in $allNfoFiles) {
        if ($pairedNames -contains $nfo.Name) { continue }
        if (Test-ArtBaseName -BaseName $nfo.BaseName) { continue }
        $orphanNfos += $nfo
    }

    if ($orphanNfos.Count -eq 0) {
        Write-Host "  $(col_a_success '✅  未发现孤立 nfo 文件。')"
    }
    else {
        Write-Host ""
        Write-Host "  $(col_a_warning "⚠  发现 $($orphanNfos.Count) 个孤立 nfo（无同名视频）：")"
        Write-Host ""
        foreach ($o in $orphanNfos) { Write-Host "  📄 $($o.FullName)" }
        Write-Host ""
        Write-Host "  $(col_a_text ('孤立 nfo 清理：'))"
        Write-Host "  $(col_a_line (sep_weak))"

        $orphanOpts = @(
            @{ Label = "[d]删除并备份"; Value = "clean" }
            @{ Label = "[s]跳过"; Value = "skip" }
            @{ Label = "[q/Esc]重新开始"; Value = "restart" }
        )
        $orphanResult = Select-Horizontal -Options $orphanOpts -Prompt "" -InitialIndex 1
        if ($null -eq $orphanResult -or $orphanResult -eq 'restart') { exit 0 }

        if ($orphanResult -eq 'clean') {
            Write-Host ""
            $okCount = 0
            foreach ($o in $orphanNfos) {
                try {
                    $bakPath = $o.FullName + ".bak"
                    [System.IO.File]::Copy($o.FullName, $bakPath, $true)
                    [System.IO.File]::Delete($o.FullName)
                    Write-Host "  $(col_a_success "🗑 $($o.Name) | 已删除（备份：$bakPath）")"
                    $okCount++
                } catch {
                    Write-Host "  $(col_a_error "❌ $($o.Name) | 清理失败：$_")"
                }
            }
            Write-Host ""
            Write-Host "  $(col_a_success "✅  已清理 $okCount 个孤立 nfo（均生成 .bak 备份）")"
        }
        else {
            Write-Host "  $(col_a_text_muted ('⚪  已跳过孤立 nfo 清理。'))"
        }
    }

    # ---- 预览表 ----
    Write-Host ""
    Write-Host ""
    Write-Host "  $(col_a_title ('NFO 内部名称同步预览'))"
    Write-Host "  $(col_a_line (sep_weak))"
    Write-Host ""
    Show-TableHeader -H2 "视频文件" -H3 "当前 <title>" -H4 "目标值"

    $idx = 1
    foreach ($wi in $workItems) {
        $cur = if ($null -eq $wi.OldTitle) { "[无标签]" } else { $wi.OldTitle }
        $diff = ($null -ne $wi.OldTitle) -and ($wi.OldTitle.Trim() -ne $wi.NewBaseName.Trim())

        $opText = if (-not $wi.Readable) { "$(col_a_error '[编码无法识别]')" }
                  elseif ($diff)          { "$(col_a_warning '[需修改]')" }
                  elseif ($null -eq $wi.OldTitle) { "$(col_a_text_muted '[无标签]')" }
                  else                    { "$(col_a_success '[一致]')" }

        $row = (PadTo ("{0,-3}" -f $idx) $script:W1) +
               (Format-Cell $wi.VideoName $script:W2) +
               (Format-Cell $cur $script:W3) +
               (Format-Cell $wi.NewBaseName $script:W4) +
               $opText
        Write-Host ("  " + $row)
        $idx++
    }

    Write-Host "  $(col_a_line $tableSep)"
    Write-Host "  $(col_a_text_muted "共 $($workItems.Count) 组配对")"
    Write-Host ""

    # ---- 模式选择 ----
    Write-Host "  $(col_a_text ('处理方式：'))"
    Write-Host "  $(col_a_line (sep_weak))"

    $modeOpts = @(
        @{ Label = "[y]仅改不一致的（推荐）"; Value = "smart" }
        @{ Label = "[a]全覆盖重写所有 nfo"; Value = "all" }
        @{ Label = "[s]仅导出日志（不改动）"; Value = "log" }
        @{ Label = "[q/Esc]退出"; Value = "exit" }
    )
    $modeResult = Select-Horizontal -Options $modeOpts -Prompt "" -InitialIndex 0
    if ($null -eq $modeResult -or $modeResult -eq 'exit') { exit 0 }

    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    # 两种日志分开命名：预览日志（未修改文件） / 执行结果日志
    # 必须用 ${ts}："_" 属于变量名字符，写成 $ts_preview 会被解析成另一个变量
    $previewLog = Join-Path $PWD.Path "nfo_map_${ts}_preview.txt"
    $resultLog  = Join-Path $PWD.Path "nfo_map_${ts}_result.txt"

    if ($modeResult -eq 'log') {
        $lines = @("# nfo 同步预览日志（未修改任何文件）", "# 视频`tNfo文件`t旧title`t旧sorttitle`t目标值")
        foreach ($wi in $workItems) {
            $ot  = if ($null -ne $wi.OldTitle) { $wi.OldTitle } else { "" }
            $ost = if ($null -ne $wi.OldSortTitle) { $wi.OldSortTitle } else { "" }
            $lines += "$($wi.VideoName)`t$($wi.NfoFile)`t$ot`t$ost`t$($wi.NewBaseName)"
        }
        $lines | Out-File -FilePath $previewLog -Encoding utf8
        Write-Host "  $(col_a_success ('✅  已输出预览日志（未改动）：' + $previewLog))"
        Wait-AnyKey
        continue
    }

    $forceAll = ($modeResult -eq 'all')

    # ---- 执行 ----
    Write-Host ""
    Write-Host "  $(col_a_title ('开始刷新 nfo 内部标签'))"
    Write-Host ""
    if ($forceAll) {
        Write-Host "  $(col_a_warning '⚠ 全覆盖模式：所有 nfo 都会重写（即使内外已一致）')"
    } else {
        Write-Host "  $(col_a_success '✓ 智能模式：仅修改内外不一致的 nfo')"
    }
    Write-Host ""

    $resultItems = @()
    $logLines = @("# nfo 同步执行日志", "# 视频`tNfo文件`t旧title`t旧sorttitle`t目标值`t状态")

    foreach ($wi in $workItems) {

        if (-not $wi.Readable) {
            Write-Host "  $(col_a_error "❌ $($wi.NfoFile) | 编码无法识别或系统缺少 GB18030，跳过")"
            $resultItems += [PSCustomObject]@{ NfoFile = $wi.NfoFile; NfoFullPath = $wi.NfoFullPath
                                               NewValue = $wi.NewBaseName; OldTitle = $wi.OldTitle; Status = 'Error' }
            $logLines += "$($wi.VideoName)`t$($wi.NfoFile)`t`t`t$($wi.NewBaseName)`tError-Encoding"
            continue
        }

        $isDifferent = ($null -ne $wi.OldTitle) -and ($wi.OldTitle.Trim() -ne $wi.NewBaseName.Trim())

        if (-not $forceAll -and -not $isDifferent) {
            Write-Host "  $(col_a_text_muted "⚪ $($wi.NfoFile) | 内外已一致，跳过")"
            $resultItems += [PSCustomObject]@{ NfoFile = $wi.NfoFile; NfoFullPath = $wi.NfoFullPath
                                               NewValue = $wi.NewBaseName; OldTitle = $wi.OldTitle; Status = 'Skipped-Same' }
            $logLines += "$($wi.VideoName)`t$($wi.NfoFile)`t$($wi.OldTitle)`t$($wi.OldSortTitle)`t$($wi.NewBaseName)`tSkipped-Same"
            continue
        }

        try {
            $bytes = [System.IO.File]::ReadAllBytes($wi.NfoFullPath)
            $enc = Get-NfoEncoding -Bytes $bytes
            if ($null -eq $enc) {
                Write-Host "  $(col_a_error "❌ $($wi.NfoFile) | 编码无法识别，跳过")"
                $resultItems += [PSCustomObject]@{ NfoFile = $wi.NfoFile; NfoFullPath = $wi.NfoFullPath
                                                   NewValue = $wi.NewBaseName; OldTitle = $wi.OldTitle; Status = 'Error' }
                continue
            }
            $text = $enc.GetString($bytes)

            $safeTitle = [System.Security.SecurityElement]::Escape($wi.NewBaseName).Replace('$', '$$')

            $modified = $false
            if ($text -match '<title\b[^>]*>.*?</title>') {
                $text = $text -replace '<title\b[^>]*>.*?</title>', "<title>$safeTitle</title>"
                $modified = $true
            }
            if ($text -match '<sorttitle\b[^>]*>.*?</sorttitle>') {
                $text = $text -replace '<sorttitle\b[^>]*>.*?</sorttitle>', "<sorttitle>$safeTitle</sorttitle>"
                $modified = $true
            }

            if (-not $modified) {
                Write-Host "  $(col_a_text_muted "⚪ $($wi.NfoFile) | 未找到标签，跳过")"
                $resultItems += [PSCustomObject]@{ NfoFile = $wi.NfoFile; NfoFullPath = $wi.NfoFullPath
                                                   NewValue = $wi.NewBaseName; OldTitle = $wi.OldTitle; Status = 'Skipped' }
                $logLines += "$($wi.VideoName)`t$($wi.NfoFile)`t$($wi.OldTitle)`t$($wi.OldSortTitle)`t$($wi.NewBaseName)`tSkipped-NoTag"
                continue
            }

            # 备份：已存在则不覆盖，保留最早的原始版本
            $bakPath = $wi.NfoFullPath + ".bak"
            if (-not (Test-Path -LiteralPath $bakPath)) {
                Copy-Item -LiteralPath $wi.NfoFullPath -Destination $bakPath -Force
                Write-Host "  $(col_a_text_muted "📋 已备份：$bakPath")"
            }

            [System.IO.File]::WriteAllBytes($wi.NfoFullPath, $enc.GetBytes($text))

            $oldTrim = if ($null -ne $wi.OldTitle) { $wi.OldTitle.Trim() } else { "" }
            if ($oldTrim -eq $wi.NewBaseName.Trim()) {
                Write-Host "  $(col_a_success "✅ $($wi.NfoFile) | 已一致（已重写）")"
            } else {
                Write-Host "  $(col_a_success "✅ $($wi.NfoFile) | title/sorttitle → $($wi.NewBaseName)")"
            }

            $resultItems += [PSCustomObject]@{ NfoFile = $wi.NfoFile; NfoFullPath = $wi.NfoFullPath
                                               NewValue = $wi.NewBaseName; OldTitle = $wi.OldTitle; Status = 'Modified' }
            $logLines += "$($wi.VideoName)`t$($wi.NfoFile)`t$($wi.OldTitle)`t$($wi.OldSortTitle)`t$($wi.NewBaseName)`tModified"
        }
        catch {
            Write-Host "  $(col_a_error "❌ $($wi.NfoFile) | 失败：$_")"
            $resultItems += [PSCustomObject]@{ NfoFile = $wi.NfoFile; NfoFullPath = $wi.NfoFullPath
                                               NewValue = $wi.NewBaseName; OldTitle = $wi.OldTitle; Status = 'Error' }
            $logLines += "$($wi.VideoName)`t$($wi.NfoFile)`t`t`t$($wi.NewBaseName)`tError"
        }
    }

    # ---- 结果表 ----
    Write-Host ""
    Write-Host "  $(col_a_title ('处理结果'))"
    Write-Host "  $(col_a_line (sep_weak))"
    Write-Host ""
    Show-TableHeader -H2 "NFO 文件" -H3 "旧 <title>" -H4 "写入值"

    $ridx = 1
    foreach ($ri in $resultItems) {
        $old = if ($null -eq $ri.OldTitle) { "[无标签]" } else { $ri.OldTitle }
        $opText = switch ($ri.Status) {
            'Modified'       { "$(col_a_success '[已修改]')" }
            'Skipped-Same'   { "$(col_a_text_muted '[一致跳过]')" }
            'Skipped'        { "$(col_a_text_muted '[无标签]')" }
            default          { "$(col_a_error '[失败]')" }
        }
        $row = (PadTo ("{0,-3}" -f $ridx) $script:W1) +
               (Format-Cell $ri.NfoFile $script:W2) +
               (Format-Cell $old $script:W3) +
               (Format-Cell $ri.NewValue $script:W4) +
               $opText
        Write-Host ("  " + $row)
        $ridx++
    }
    Write-Host "  $(col_a_line $tableSep)"

    # ---- 事后菜单 ----
    $modifiedCount = ($resultItems | Where-Object { $_.Status -eq 'Modified' }).Count

    Write-Host ""
    Write-Host ""
    Write-Host "  $(col_a_title ('后续操作选项'))"
    Write-Host "  此处若不选择撤销，修改内容的nfo可以通过前面生成的bak自行还原"
    Write-Host "  若有需要，可按s保存处理日志后再退出"
    Write-Host "  $(col_a_line (sep_weak))"

    $postOpts = @(
        @{ Label = "[u]撤销本次修改"; Value = "undo" }
        @{ Label = "[s]保存处理日志txt"; Value = "save" }
        @{ Label = "[q/Esc]退出，不撤销也不保存txt，就这么定了~ "; Value = "exit" }
    )
    $postResult = Select-Horizontal -Options $postOpts -Prompt "" -InitialIndex 0
    if ($null -eq $postResult) { exit 0 }

    if ($postResult -eq 'undo') {
        Write-Host ""
        Write-Host "  $(col_a_warning ('⚠️  开始撤销，从 .bak 还原 nfo 内容...'))"
        $undoOk = 0; $undoFail = 0

        foreach ($ri in $resultItems) {
            if ($ri.Status -ne 'Modified') { continue }
            $bakPath = $ri.NfoFullPath + ".bak"
            if (-not (Test-Path -LiteralPath $bakPath)) {
                Write-Host "  $(col_a_error "❌ $($ri.NfoFile) | 备份不存在")"
                $undoFail++
                continue
            }
            try {
                Copy-Item -LiteralPath $bakPath -Destination $ri.NfoFullPath -Force
                Remove-Item -LiteralPath $bakPath -Force -ErrorAction SilentlyContinue
                Write-Host "  $(col_a_success "↩ $($ri.NfoFile) | 已还原")"
                $undoOk++
            } catch {
                Write-Host "  $(col_a_error "❌ $($ri.NfoFile) | 还原失败：$_")"
                $undoFail++
            }
        }

        Write-Host ""
        if ($undoOk -eq 0 -and $undoFail -eq 0) {
            Write-Host "  $(col_a_text_muted '⚪ 本次没有修改过文件，无需撤销')"
        } else {
            Write-Host "  $(col_a_text ('撤销完成，成功：'))$(col_a_success "$undoOk")$(col_a_text ' ｜失败：')$(col_a_error "$undoFail")"
        }
        Write-Host ""
        Wait-AnyKey "  $(col_a_text_muted '按任意键返回菜单...')"
    }
    elseif ($postResult -eq 'save') {
        $logLines | Out-File -FilePath $resultLog -Encoding utf8
        Write-Host "  $(col_a_success ('✅  已保存执行结果日志：' + $resultLog))"
        Write-Host ""
        Wait-AnyKey "  $(col_a_text_muted '按任意键返回菜单...')"
    }

    return
}