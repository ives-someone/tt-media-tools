<#
video_tool.ps1
v1.1（2026-11-05）：视频合并 / 转码工具，主菜单第 9 项。
v1.2（2026-11-08）：新增 p 暂停 / 继续（挂起 ffmpeg 进程），
       恢复后从冻结处继续写，输出文件不会损坏。
v1.3（2026-11-09）：小文件并发转码——短边 ≤1080 的文件两两并行，
       2K/4K 逐个串行；并发时按 p 同时暂停 / 恢复全部任务。
v1.4（2026-11-09）：转码编码菜单增加「一键按上次」，默认选中，
       沿用上次参数与输出位置并跳过确认直接开始；
       QSV 检测结果缓存进 config.env，打开工具不再重复试编码。
v1.5（2026-11-09）：并发转码恢复进度显示——用 -progress 文件解析
       各任务的百分比与倍速，单行汇总刷新，两个任务都能看到进度。
v1.6（2026-11-10）：转码新增帧率选项（保持原帧率 / 自定义 1~120 fps）；
       合并帧率不兼容提示改为明确说明“无损拼接可能音画不同步”。
v1.7（2026-11-10）：转码改为任务池调度——小文件双槽滚动补位，
       2K/4K 独占；输出清单按原输入序号排序。
    合并：多段首尾拼接，无损 copy 优先，参数不一致时改有损重编码。
    转码：逐个文件按预设重编码，与合并共用 QSV / CRF 参数体系。

【为什么是这个脚本名】
    菜单 9 的定位是「视频转码 / 合并工具」，后续会补转码预设，
    故不叫 video_merge.ps1，避免加功能时再改一次名。

【技术路线：只用 ffmpeg，不引入第三方 QuickSync 工具】
    QuickSync 是 Intel 核显的硬件编解码能力，ffmpeg 自带 *_qsv 编码器
    （hevc_qsv / h264_qsv），已经能直接驱动它，无需再装「QuickSync 编码器」
    这类独立程序；多一层外部工具只会多一份依赖和一套参数。
    本脚本启动时对 QSV 做一次真实试编码，确认硬件真的可用：
        ffmpeg -f lavfi -i color=... -c:v hevc_qsv -global_quality 21 -f null -
    退出码为 0 才算可用。只查「编码器列表里有没有」是不够的——
    编码器存在但机器没有核显 / 驱动不对时，真正转码才会失败。

【无损合并】
    concat demuxer + -c copy，不重新编码，画质零损失、速度只受磁盘限制。
    但 -c copy 对参数不一致是「静默出错」：实测把 720p 和 1080p 拼在一起，
    ffmpeg 退出码仍是 0，输出却只有 4.85 秒（应为 6 秒）且画面花掉。
    因此本脚本不信任退出码，改为：
        1) 合并前逐项比对 编码/分辨率/像素格式/Profile/帧率/音轨参数；
        2) 任一项不一致就判定「不能无损」，把默认项切到有损；
        3) 合并后再用 ffprobe 复核输出时长，偏差过大即判定失败。

【有损合并】
    concat 滤镜 + 统一规格：每段先 fps 归一、等比缩放后补黑边到目标分辨率，
    再拼接，避免直接 concat 不同分辨率的裸流。
    目标分辨率取「出现次数最多的那个」，并列时取面积大的；
    目标帧率同理。这样多段同源、个别片段不同时，不会被少数片段带偏。

【转码】
    逐个文件重新编码，不改变分辨率与帧率（保持原规格，只换编码与质量）。
    音频为 AAC 时直接 copy，其余转 AAC；统一 8-bit yuv420p、mp4 容器。
    编码格式 / 编码方式 / 数值与合并共用同一套菜单，默认值分别记在 JSON 的
    merge 与 transcode 两段（老配置缺 transcode 时自动继承 merge）。
    输出位置二选一：
      a) 转码成果\ 子文件夹（默认）——保留原文件名
      b) 源文件夹——文件名加 转码_ 前缀
    选择记在 JSON 的 transcode.outputMode。

【处理范围】
    扫描后先选「全部」或「指定序号」（1-3,5，逗号 / 顿号 / 空格分隔）。
    合并严格按所选顺序拼接；选完会再列一遍并确认，避免拼错顺序。
    转码共用同一选择，顺序不影响结果。

【输出命名】
    合并：合并_<各段原名，去掉时间标记，用 + 连接><合并时长>.mp4
          例：合并_第一段+第二段07m21s.mp4；时长 >=1 小时写 01h02m03s。
          名称超长时截断末尾，但优先保住时长标签与扩展名。
    转码：<原文件名>_转码.mp4（源文件夹）或 <原文件名>.mp4（转码成果子文件夹）
    不再带时间戳；目标已存在时自动加 _2、_3，绝不覆盖。
    源文件夹用后缀而非前缀，是为了按文件名排序时原片与转码片相邻，
    方便直接对比两版的参数。
    扫描时会跳过 合并_ 开头、_转码 结尾的文件（视为历史产物）；
    用户素材若命中这两个规则，需要先改名。

【配置文件】
    与脚本同目录：video_tool.config.json
    首次运行自动生成，记录上次选择的编码格式 / 编码方式 / 数值，
    下次进入即作为默认值。数值越界或字段非法时回退内置默认，并给出提示，
    不会因为手改坏一个字段就整份失效。

【依赖】
    ffmpeg.exe + ffprobe.exe（缺一不可）。
    查找顺序：PATH → tools\ → 工具根目录；ffprobe 优先取 ffmpeg 同目录的副本。

【SMB / UNC】
    UNC 路径若 ffprobe 打不开，自动依次尝试 原样 → \\?\UNC\ → 映射盘，
    全部失败再等 250ms 重试一次；仍失败时把 ffprobe 的 stderr 摘要显示在
    「读取失败」清单里，便于判断是占用、权限还是文件还没拷完。
    探测成功的那一种路径形式会记进 FullPath，后续合并沿用同一形式。

    另外，探测一律走 ProcessStartInfo 显式重定向，不用 `& ffprobe 2>$null`。
    实测在 UNC 工作目录下，PowerShell 的原生输出捕获会丢数据：ffprobe 退出码是 0、
    stderr 为空，但拿到的 stdout 是空的，于是一整批文件被误判成「无法解析」。
    子进程的工作目录也固定到 ffprobe 所在目录，避开 UNC CWD。

【兼容性】PowerShell 5.1 / 7.x
#>

# ========== 加载公共 UI 框架 ==========
. (Join-Path $PSScriptRoot "ui\ui.ps1")

# ========== 常量与路径 ==========
$script:VideoExts = @('mp4','mov','mkv','avi','flv','wmv','m4v','ts','mpg','mpeg','f4v','m2ts','mts','webm','rmvb')
$script:ToolRoot  = Split-Path -Parent $PSScriptRoot
$script:ToolsDir  = Join-Path $script:ToolRoot 'tools'
$script:ConfigPath = Join-Path $PSScriptRoot 'video_tool.config.json'
$script:OutputPattern = '^(合并_|转码_)|_转码(_\d+)?\.[^.]+$'
$script:MaxMergedNameLength = 120   # 合并文件名（含时长与扩展名）的字符数上限
$script:MaxMergedPathLength = 240   # 文件名 + 目录的软上限，避免撞 MAX_PATH

# 运行时环境状态（只探测一次，后续复用）
$script:Env = @{
    Ready    = $false
    Ffmpeg   = $null
    Ffprobe  = $null
    Version  = ''
    Source   = ''
    QsvHevc  = $false
    QsvH264  = $false
}

$script:EncoderList = $null
$script:Config = $null
$script:ConfigCreated = $false
$script:ConfigWarnings = New-Object System.Collections.Generic.List[string]

# ============================================================
# 区块一：配置文件
# JSON 里只用 ASCII 键名与英文提示，避免 PS 5.1 的 ConvertTo-Json
# 把中文转成 \uXXXX，用户打开文件看不懂。
# ============================================================
# 返回一份全新的编码默认值（OrderedDictionary 没有 Clone，必须每次新建）
function New-EncodingDefaults {
    return [ordered]@{
        codec            = 'hevc'
        rateMode         = 'icq'
        icq              = 21
        cbrMbps          = 5
        crf              = 22
        qsvPreset        = 'medium'
        cpuPreset        = 'medium'
        audioBitrateKbps = 192
    }
}

function Get-DefaultConfig {
    # merge 与 transcode 各自保存一套编码偏好，互不影响；
    # 老配置文件只有 merge 段时，Import-ToolConfig 会让 transcode 继承 merge。
    $transcode = New-EncodingDefaults
    $transcode['outputMode'] = 'subfolder'
    $transcode['frameRate'] = 0
    return [ordered]@{
        merge     = New-EncodingDefaults
        transcode = $transcode
        env       = [ordered]@{
            ffmpegPath    = ''
            ffmpegVersion = ''
            qsvHevc       = $false
            qsvH264       = $false
            checkedAt     = ''
        }
        _help     = 'icq 18-28 | cbrMbps 1-50 | crf 0-51 (lower = better) | preset veryfast..veryslow | outputMode subfolder|source'
    }
}

# 把 JSON 里的一段编码配置校验后合并进目标段；非法字段回退默认并记录提示
function Merge-EncodingSection {
    param($Target, $Source, [string]$Label = '')

    $prefix = if ([string]::IsNullOrEmpty($Label)) { '' } else { "$Label." }
    $checkInt = {
        param($rawValue, [int]$min, [int]$max)
        if ($null -eq $rawValue) { return $null }
        $text = [string]$rawValue
        if ($text -notmatch '^\d+$') { return $null }
        $n = [int]$text
        if ($n -lt $min -or $n -gt $max) { return $null }
        return $n
    }

    if ($Source.codec -in @('hevc','h264')) { $Target['codec'] = [string]$Source.codec }
    elseif ($null -ne $Source.codec) { $script:ConfigWarnings.Add("${prefix}codec 只能是 hevc / h264，已忽略：$($Source.codec)") }

    if ($Source.rateMode -in @('icq','cbr','crf')) { $Target['rateMode'] = [string]$Source.rateMode }
    elseif ($null -ne $Source.rateMode) { $script:ConfigWarnings.Add("${prefix}rateMode 只能是 icq / cbr / crf，已忽略：$($Source.rateMode)") }

    $v = & $checkInt $Source.icq 18 28
    if ($null -ne $v) { $Target['icq'] = $v }
    elseif ($null -ne $Source.icq) { $script:ConfigWarnings.Add("${prefix}icq 超出 18~28，已忽略：$($Source.icq)") }

    if ($null -ne $Source.cbrMbps) {
        $cbrRaw = 0.0
        $cbrOk = [double]::TryParse([string]$Source.cbrMbps, [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$cbrRaw)
        if ($cbrOk -and $cbrRaw -ge 1 -and $cbrRaw -le 50) { $Target['cbrMbps'] = $cbrRaw }
        else { $script:ConfigWarnings.Add("${prefix}cbrMbps 超出 1~50，已忽略：$($Source.cbrMbps)") }
    }

    $v = & $checkInt $Source.crf 0 51
    if ($null -ne $v) { $Target['crf'] = $v }
    elseif ($null -ne $Source.crf) { $script:ConfigWarnings.Add("${prefix}crf 超出 0~51，已忽略：$($Source.crf)") }

    $presets = @('veryfast','faster','fast','medium','slow','slower','veryslow')
    if ($Source.qsvPreset -in $presets) { $Target['qsvPreset'] = [string]$Source.qsvPreset }
    if ($Source.cpuPreset -in $presets) { $Target['cpuPreset'] = [string]$Source.cpuPreset }

    $v = & $checkInt $Source.audioBitrateKbps 64 512
    if ($null -ne $v) { $Target['audioBitrateKbps'] = $v }

    if ($Target.Contains('frameRate') -and $null -ne $Source.frameRate) {
        $fr = 0.0
        $frOk = [double]::TryParse([string]$Source.frameRate, [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture, [ref]$fr)
        if ($frOk -and $fr -ge 0 -and $fr -le 120) { $Target['frameRate'] = $fr }
        else { $script:ConfigWarnings.Add("${prefix}frameRate 超出 0~120，已忽略：$($Source.frameRate)") }
    }
}

function Save-ToolConfig {
    param($Config)
    try {
        $json = $Config | ConvertTo-Json -Depth 6
        $utf8 = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($script:ConfigPath, $json, $utf8)
        return $true
    } catch {
        return $false
    }
}

function Import-ToolConfig {
    $cfg = Get-DefaultConfig

    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        if (Save-ToolConfig -Config $cfg) { $script:ConfigCreated = $true }
        return $cfg
    }

    try {
        $raw = Get-Content -LiteralPath $script:ConfigPath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) { throw 'empty file' }
        $obj = $raw | ConvertFrom-Json
    } catch {
        $script:ConfigWarnings.Add('配置文件无法解析，本次全部使用内置默认值')
        return $cfg
    }

    if ($null -ne $obj.merge) {
        Merge-EncodingSection -Target $cfg['merge'] -Source $obj.merge -Label 'merge'
    }
    if ($null -ne $obj.transcode) {
        Merge-EncodingSection -Target $cfg['transcode'] -Source $obj.transcode -Label 'transcode'
        if ($obj.transcode.outputMode -in @('subfolder','source')) {
            $cfg['transcode']['outputMode'] = [string]$obj.transcode.outputMode
        } elseif ($null -ne $obj.transcode.outputMode) {
            $script:ConfigWarnings.Add("transcode.outputMode 只能是 subfolder / source，已忽略：$($obj.transcode.outputMode)")
        }
    } else {
        # 老配置文件没有 transcode 段：直接继承 merge 的编码设置
        foreach ($key in @($cfg['transcode'].Keys)) {
            if ($cfg['merge'].Contains($key)) { $cfg['transcode'][$key] = $cfg['merge'][$key] }
        }
    }

    if ($null -ne $obj.env) {
        if ($obj.env.ffmpegPath) { $cfg['env']['ffmpegPath'] = [string]$obj.env.ffmpegPath }
        if ($obj.env.ffmpegVersion) { $cfg['env']['ffmpegVersion'] = [string]$obj.env.ffmpegVersion }
        if ($obj.env.checkedAt) { $cfg['env']['checkedAt'] = [string]$obj.env.checkedAt }
        if ($obj.env.qsvHevc -is [bool]) { $cfg['env']['qsvHevc'] = [bool]$obj.env.qsvHevc }
        if ($obj.env.qsvH264 -is [bool]) { $cfg['env']['qsvH264'] = [bool]$obj.env.qsvH264 }
    }

    return $cfg
}

# ============================================================
# 区块二：环境探测（ffmpeg / ffprobe / QSV）
# ============================================================

# 先查 PATH，再查 tools\，最后查工具根目录（与 install.ps1 的判定口径一致）
function Resolve-Exe {
    param([string]$Name)
    $cmd = Get-Command "$Name.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($dir in @($script:ToolsDir, $script:ToolRoot)) {
        $p = Join-Path $dir "$Name.exe"
        if (Test-Path -LiteralPath $p) { return $p }
    }
    return $null
}

# ffmpeg 的 -encoders 列表，用于确认 CPU 编码器是否存在（如 libx265）
function Test-EncoderAvailable {
    param([string]$Name)
    if ($null -eq $script:EncoderList) {
        $script:EncoderList = @()
        try {
            $lines = & $script:Env.Ffmpeg -hide_banner -encoders 2>$null
            foreach ($line in $lines) {
                if ($line -match '^\s*[VAS][.A-Z]{5}\s+(\S+)') {
                    $script:EncoderList += $Matches[1]
                }
            }
        } catch { }
    }
    return ($script:EncoderList -contains $Name)
}

# QSV 真实可用性：列表里有编码器 ≠ 硬件能用，必须跑一次空转试编码
function Test-QsvEncoder {
    param([string]$Codec)
    $enc = if ($Codec -eq 'hevc') { 'hevc_qsv' } else { 'h264_qsv' }
    $argv = @(
        '-hide_banner','-loglevel','error','-nostdin',
        '-f','lavfi','-i','color=c=black:s=320x240:d=0.2',
        '-c:v',$enc,'-global_quality','21','-f','null','-'
    )
    $null = & $script:Env.Ffmpeg @argv 2>&1
    return ($LASTEXITCODE -eq 0)
}

function Initialize-Environment {
    if ($script:Env.Ready) {
        return ($null -ne $script:Env.Ffmpeg -and $null -ne $script:Env.Ffprobe)
    }
    $script:Env.Ready = $true

    $script:Env.Ffmpeg = Resolve-Exe 'ffmpeg'
    if (-not $script:Env.Ffmpeg) { return $false }

    # ffprobe 优先取 ffmpeg 同目录的副本：Gyan / BtbN 等构建都是成对发布的
    $sibling = Join-Path (Split-Path -Parent $script:Env.Ffmpeg) 'ffprobe.exe'
    if (Test-Path -LiteralPath $sibling) { $script:Env.Ffprobe = $sibling }
    else { $script:Env.Ffprobe = Resolve-Exe 'ffprobe' }
    if (-not $script:Env.Ffprobe) { return $false }

    try {
        $line = (& $script:Env.Ffmpeg -hide_banner -version 2>$null | Select-Object -First 1)
        if ($line -match 'version\s+(\S+)') { $script:Env.Version = $Matches[1] }
    } catch { $script:Env.Version = '' }

    # QSV 真实试编码每次要启动 ffmpeg 1~3 秒；把结果缓存进 config，
    # 只有 ffmpeg 路径/版本变化、缓存超过 7 天或缓存无效时才重新检测。
    $cache = $null
    if ($null -ne $script:Config -and $script:Config.Contains('env')) { $cache = $script:Config['env'] }

    $cacheFresh = $false
    if ($null -ne $cache) {
        $checked = [datetime]::MinValue
        $checkedOk = $false
        if (-not [string]::IsNullOrWhiteSpace([string]$cache['checkedAt'])) {
            $checkedOk = [datetime]::TryParse([string]$cache['checkedAt'], [ref]$checked)
        }
        if ($checkedOk -and
            [string]$cache['ffmpegPath'] -eq [string]$script:Env.Ffmpeg -and
            [string]$cache['ffmpegVersion'] -eq [string]$script:Env.Version -and
            ((Get-Date) - $checked).TotalDays -lt 7) {
            $cacheFresh = $true
        }
    }

    if ($cacheFresh) {
        $script:Env.QsvHevc = [bool]$cache['qsvHevc']
        $script:Env.QsvH264 = [bool]$cache['qsvH264']
    } else {
        $script:Env.QsvHevc = Test-QsvEncoder -Codec 'hevc'
        $script:Env.QsvH264 = Test-QsvEncoder -Codec 'h264'
        if ($null -ne $cache) {
            $cache['ffmpegPath'] = [string]$script:Env.Ffmpeg
            $cache['ffmpegVersion'] = [string]$script:Env.Version
            $cache['qsvHevc'] = [bool]$script:Env.QsvHevc
            $cache['qsvH264'] = [bool]$script:Env.QsvH264
            $cache['checkedAt'] = (Get-Date).ToString('o')
            [void](Save-ToolConfig -Config $script:Config)
        }
    }

    return $true
}

# ============================================================
# 区块三：文本与表格工具
# 视觉宽度：沿用其余模块的口径（中文/全角按 2 列）
# ============================================================
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

function Format-Truncated {
    param([string]$Text, [int]$MaxWidth)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    if ((Get-DisplayWidth $Text) -le $MaxWidth) { return $Text }
    $budget = $MaxWidth - 2
    $res = ''
    $curW = 0
    foreach ($c in $Text.ToCharArray()) {
        $cw = if ($c -gt 0x2E7F -or ($c -ge 0xFF00 -and $c -le 0xFFEF)) { 2 } else { 1 }
        if ($curW + $cw -gt $budget) { break }
        $res += $c
        $curW += $cw
    }
    return $res + '…'
}

function Format-Cell {
    param([string]$Text, [int]$Width)
    return (PadTo (Format-Truncated -Text $Text -MaxWidth ($Width - 2)) $Width)
}

function Format-DurationText {
    param([double]$Seconds)
    if ($Seconds -le 0) { return '--:--:--' }
    $ts = [TimeSpan]::FromSeconds($Seconds)
    $hours = [int][math]::Floor($ts.TotalHours)
    return ('{0:00}:{1:00}:{2:00}' -f $hours, $ts.Minutes, $ts.Seconds)
}

# 文件名用的时长标签：>=1 小时写 HHhMMmSSs，否则 MMmSSs
function Format-DurationTag {
    param([double]$Seconds)
    if ($Seconds -lt 1) { $Seconds = 1 }
    $ts = [TimeSpan]::FromSeconds([math]::Round($Seconds))
    if ($ts.TotalHours -ge 1) {
        return ('{0:00}h{1:00}m{2:00}s' -f [int][math]::Floor($ts.TotalHours), $ts.Minutes, $ts.Seconds)
    }
    return ('{0:00}m{1:00}s' -f $ts.Minutes, $ts.Seconds)
}

function Format-FileSize {
    param([double]$Bytes)
    if ($Bytes -ge 1073741824) { return ('{0:0.00} GB' -f ($Bytes / 1073741824)) }
    if ($Bytes -ge 1048576)    { return ('{0:0.0} MB' -f ($Bytes / 1048576)) }
    if ($Bytes -ge 1024)       { return ('{0:0} KB' -f ($Bytes / 1024)) }
    return ('{0} B' -f [int]$Bytes)
}

# 自然排序：01 → 02 → 10，而不是 01 → 02 → 10 的字典序
function Get-SortKey {
    param([string]$Name)
    $sb = New-Object System.Text.StringBuilder
    $last = 0
    foreach ($m in [regex]::Matches($Name, '\d+')) {
        [void]$sb.Append($Name.Substring($last, $m.Index - $last))
        [void]$sb.Append($m.Value.PadLeft(10, '0'))
        $last = $m.Index + $m.Length
    }
    [void]$sb.Append($Name.Substring($last))
    return $sb.ToString()
}

# 命令行回显：含空格/引号的参数补引号，方便用户直接复制复现
function Format-CommandLine {
    param([string]$Exe, [string[]]$Arguments)
    $parts = foreach ($a in $Arguments) {
        $s = [string]$a
        if ($s -match '[\s"]') { '"' + ($s -replace '"', '\"') + '"' } else { $s }
    }
    return ('"' + $Exe + '" ' + ($parts -join ' '))
}

# 把参数数组拼成 CreateProcess 能解析的命令行（与 Format-CommandLine 同一套引号规则）
function ConvertTo-ProcessArgumentString {
    param([string[]]$Arguments)
    $parts = foreach ($a in $Arguments) {
        $s = [string]$a
        if ($s -match '[\s"]') { '"' + ($s -replace '"', '\"') + '"' } else { $s }
    }
    return ($parts -join ' ')
}

# ============================================================
# 区块三·B：ffmpeg 进程（支持 p 暂停 / 继续）
# ------------------------------------------------------------
# 为什么不用 `& ffmpeg @argv`：那条路会一直阻塞到 ffmpeg 退出，
# 脚本没有机会读键盘，也就无法暂停。这里改成 Process + 轮询：
#   - 输出不重定向，ffmpeg 的 -stats 进度条仍直接写控制台
#   - 每 200ms 检查一次键盘，按 p 调用 NtSuspendProcess / NtResumeProcess
#   - 挂起只是冻结进程，文件句柄与写入位置都保留，恢复后继续写，
#     输出文件不会损坏；只有强杀才会留下半成品
# ============================================================
function Invoke-FfmpegProcess {
    param(
        [string]$Exe,
        [string[]]$Arguments,
        [switch]$AllowPause
    )

    # 懒加载：PowerShell 5.1 没有内置的进程挂起 API，用 ntdll 的未文档化函数
    if (-not ('DshVideoTool.Native' -as [type])) {
        $nativeCode = '[DllImport("ntdll.dll")] public static extern int NtSuspendProcess(System.IntPtr processHandle); [DllImport("ntdll.dll")] public static extern int NtResumeProcess(System.IntPtr processHandle);'
        try { Add-Type -Namespace DshVideoTool -Name Native -MemberDefinition $nativeCode -ErrorAction Stop } catch { }
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = (ConvertTo-ProcessArgumentString -Arguments $Arguments)
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $false
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    [void]$proc.Start()

    $canPause = $false
    if ($AllowPause -and ('DshVideoTool.Native' -as [type])) {
        try {
            if (-not [Console]::IsInputRedirected) { $canPause = $true }
        } catch { $canPause = $false }
    }
    if ($canPause) {
        Write-Host "  $(col_a_text_muted '[p] 暂停 / 继续')"
    }

    $suspended = $false
    try {
        if ($canPause) {
            while (-not $proc.WaitForExit(200)) {
                try {
                    if ([Console]::KeyAvailable) {
                        $key = [Console]::ReadKey($true)
                        if ($key.Key -eq [ConsoleKey]::P) {
                            if (-not $suspended) {
                                [void][DshVideoTool.Native]::NtSuspendProcess($proc.Handle)
                                $suspended = $true
                                Write-Host "  $(col_a_warning '⏸ 已暂停，按 p 继续')"
                            } else {
                                [void][DshVideoTool.Native]::NtResumeProcess($proc.Handle)
                                $suspended = $false
                                Write-Host "  $(col_a_success '▶ 继续')"
                            }
                        }
                    }
                } catch {
                    # 终端不支持 KeyAvailable（重定向、部分宿主）时不再尝试暂停
                    $canPause = $false
                }
            }
        } else {
            $proc.WaitForExit()
        }
        if (-not $proc.HasExited) { $proc.WaitForExit() }
        return $proc.ExitCode
    } finally {
        # Ctrl+C / 异常退出时：先恢复挂起的进程，再确保它被终止，避免残留
        if ($suspended) {
            try { [void][DshVideoTool.Native]::NtResumeProcess($proc.Handle) } catch { }
        }
        if (-not $proc.HasExited) {
            try { $proc.Kill() } catch { }
            try { [void]$proc.WaitForExit(3000) } catch { }
        }
        $proc.Dispose()
    }
}

# ============================================================
# 区块四：ffprobe 元数据
# 只取合并需要的字段；ffprobe 报错（损坏文件）返回 $null 由调用方跳过
# ============================================================
function ConvertTo-FpsValue {
    param([string]$Rate)
    if ([string]::IsNullOrWhiteSpace($Rate)) { return 0.0 }
    $parts = $Rate -split '/'
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    if ($parts.Count -eq 2) {
        $num = 0.0; $den = 0.0
        [void][double]::TryParse($parts[0], [System.Globalization.NumberStyles]::Float, $inv, [ref]$num)
        [void][double]::TryParse($parts[1], [System.Globalization.NumberStyles]::Float, $inv, [ref]$den)
        if ($den -gt 0) { return ($num / $den) }
        return 0.0
    }
    $v = 0.0
    [void][double]::TryParse($Rate, [System.Globalization.NumberStyles]::Float, $inv, [ref]$v)
    return $v
}

# ---------- SMB / UNC 兼容 ----------
# 同一条 UNC 路径，个别环境里 ffprobe 打不开，但换成映射盘或 \\?\UNC\ 形式就正常。
# 下面按「原样 → 扩展长度 → 映射盘」逐个试；探测成功的那一种会被记进 FullPath，
# 后续合并也用同一种形式，避免探测能读、真合并却打不开。
$script:LastProbeError = ''
$script:DriveMap = $null

function Get-MappedPath {
    param([string]$Path)
    if ($null -eq $script:DriveMap) {
        $script:DriveMap = @()
        foreach ($d in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
            if ([string]::IsNullOrEmpty($d.DisplayRoot)) { continue }
            $script:DriveMap += [PSCustomObject]@{
                Unc  = $d.DisplayRoot.TrimEnd('\')
                Root = $d.Root.TrimEnd('\')
            }
        }
    }
    foreach ($m in $script:DriveMap) {
        if ($Path.StartsWith($m.Unc + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            return ($m.Root + $Path.Substring($m.Unc.Length))
        }
    }
    return $null
}

function Get-ProbePathCandidates {
    param([string]$Path)
    $list = New-Object System.Collections.Generic.List[string]
    $list.Add($Path)
    if ($Path.StartsWith('\\') -and -not $Path.StartsWith('\\?\')) {
        $list.Add('\\?\UNC\' + $Path.Substring(2))
        $mapped = Get-MappedPath -Path $Path
        if (-not [string]::IsNullOrEmpty($mapped)) { $list.Add($mapped) }
    }
    return $list
}

# 用 ProcessStartInfo 显式重定向来取 ffprobe 输出。
# 不能再用 `& ffprobe ... 2>$null`：实测在 UNC 工作目录下，
# PowerShell 的原生输出捕获会拿到空值，而 ffprobe 实际退出码是 0
# （界面上表现为「ffprobe 退出码 0（无错误输出）」却全部判失败）。
# 这里同时把子进程工作目录固定到 ffprobe 所在目录，彻底避开 UNC CWD。
function Invoke-FfprobeRaw {
    param([string]$Path)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = $script:Env.Ffprobe
    $psi.Arguments = '-v error -print_format json -show_format -show_streams -i "' + $Path + '"'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $psi.WorkingDirectory = Split-Path -Parent $script:Env.Ffprobe

    try {
        $proc = [System.Diagnostics.Process]::Start($psi)
        # 两路都异步读，避免 stderr 塞满缓冲区造成死锁
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        $proc.WaitForExit()
        return [PSCustomObject]@{
            ExitCode = $proc.ExitCode
            StdOut   = $outTask.Result
            StdErr   = $errTask.Result
        }
    } catch {
        return [PSCustomObject]@{
            ExitCode = -1
            StdOut   = ''
            StdErr   = $_.Exception.Message
        }
    }
}

function Format-ProbeError {
    param([int]$Code, [string]$StdErr)
    if ([string]::IsNullOrWhiteSpace($StdErr)) { return "ffprobe 退出码 $Code（无错误输出）" }
    $line = @($StdErr -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[0].Trim()
    if ($line.Length -gt 160) { $line = $line.Substring(0, 160) + '…' }
    return "ffprobe 退出码 $Code：$line"
}

function ConvertFrom-ProbeJson {
    param([string]$Text, [string]$Path)
    try {
        $j = ($Text | ConvertFrom-Json)
    } catch {
        return $null
    }
    if ($null -eq $j.streams) { return $null }

    $vStreams = @($j.streams | Where-Object { $_.codec_type -eq 'video' })
    if ($vStreams.Count -eq 0) { return $null }
    $v = $vStreams[0]
    $aStreams = @($j.streams | Where-Object { $_.codec_type -eq 'audio' })
    $a = if ($aStreams.Count -gt 0) { $aStreams[0] } else { $null }

    $duration = 0.0
    if ($null -ne $j.format -and $null -ne $j.format.duration) { $duration = [double]$j.format.duration }
    elseif ($null -ne $v.duration) { $duration = [double]$v.duration }

    $fps = ConvertTo-FpsValue -Rate ([string]$v.r_frame_rate)

    return [PSCustomObject]@{
        FullPath   = $Path
        Name       = [System.IO.Path]::GetFileName($Path)
        Duration   = $duration
        Width      = [int]$v.width
        Height     = [int]$v.height
        VCodec     = [string]$v.codec_name
        PixFmt     = [string]$v.pix_fmt
        Profile    = [string]$v.profile
        Fps        = $fps
        HasAudio   = ($null -ne $a)
        ACodec     = if ($null -ne $a) { [string]$a.codec_name } else { '' }
        AChannels  = if ($null -ne $a) { [int]$a.channels } else { 0 }
        ASampleRate = if ($null -ne $a) { [int]$a.sample_rate } else { 0 }
    }
}

function Get-VideoInfo {
    param([string]$Path)
    $script:LastProbeError = ''
    $lastCode = -1
    $lastErr = ''
    $emptyOutput = $false
    $parseFailed = $false

    foreach ($candidate in (Get-ProbePathCandidates -Path $Path)) {
        $result = Invoke-FfprobeRaw -Path $candidate
        if ($result.ExitCode -eq 0) {
            if ([string]::IsNullOrWhiteSpace($result.StdOut)) {
                $emptyOutput = $true
                continue
            }
            $info = ConvertFrom-ProbeJson -Text $result.StdOut -Path $candidate
            if ($null -ne $info) { return $info }
            $parseFailed = $true
            continue
        }
        $lastCode = $result.ExitCode
        if (-not [string]::IsNullOrWhiteSpace($result.StdErr)) { $lastErr = $result.StdErr }
    }

    # SMB 偶发占用 / 瞬时错误：稍等再试一次原路径
    Start-Sleep -Milliseconds 250
    $retry = Invoke-FfprobeRaw -Path $Path
    if ($retry.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($retry.StdOut)) {
        $info = ConvertFrom-ProbeJson -Text $retry.StdOut -Path $Path
        if ($null -ne $info) { return $info }
    }

    if ($parseFailed) {
        $script:LastProbeError = 'ffprobe 已返回数据但解析失败（可能读到不完整内容）'
    } elseif ($emptyOutput) {
        $script:LastProbeError = 'ffprobe 退出码 0 但没有返回数据（输出捕获异常）'
    } else {
        $script:LastProbeError = Format-ProbeError -Code $lastCode -StdErr $lastErr
    }
    return $null
}

# ============================================================
# 区块五：无损可行性判断
# 逐项比对，每类差异只记一条（避免 20 个文件刷 20 条同样的原因）
# ============================================================
function Get-Compatibility {
    param([object[]]$Infos)

    $reasons = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $first = $Infos[0]

    for ($i = 1; $i -lt $Infos.Count; $i++) {
        $cur = $Infos[$i]
        $name = $cur.Name

        if ($cur.VCodec -ne $first.VCodec -and -not $seen['codec']) {
            $reasons.Add("编码格式不同：$($first.VCodec) / $($cur.VCodec)（$name）"); $seen['codec'] = $true
        }
        if (($cur.Width -ne $first.Width -or $cur.Height -ne $first.Height) -and -not $seen['res']) {
            $reasons.Add("分辨率不同：$($first.Width)x$($first.Height) / $($cur.Width)x$($cur.Height)（$name）"); $seen['res'] = $true
        }
        if ($cur.PixFmt -ne $first.PixFmt -and -not $seen['pix']) {
            $reasons.Add("像素格式不同：$($first.PixFmt) / $($cur.PixFmt)（$name）"); $seen['pix'] = $true
        }
        if ($cur.Profile -ne $first.Profile -and -not $seen['profile']) {
            $reasons.Add("编码 Profile 不同：$($first.Profile) / $($cur.Profile)（$name）"); $seen['profile'] = $true
        }
        if ($first.Fps -gt 0 -and $cur.Fps -gt 0 -and
            [math]::Abs($cur.Fps - $first.Fps) -gt 0.01 -and -not $seen['fps']) {
            $reasons.Add("帧率不同：$([math]::Round($first.Fps,3)) / $([math]::Round($cur.Fps,3)) fps（$name；无损拼接可能音画不同步，已改用有损统一帧率）"); $seen['fps'] = $true
        }
        if ($cur.HasAudio -ne $first.HasAudio -and -not $seen['audioPresence']) {
            $reasons.Add('音轨有无不一致：部分视频没有音频轨'); $seen['audioPresence'] = $true
        }
        elseif ($cur.HasAudio -and $first.HasAudio) {
            if ($cur.ACodec -ne $first.ACodec -and -not $seen['acodec']) {
                $reasons.Add("音频编码不同：$($first.ACodec) / $($cur.ACodec)（$name）"); $seen['acodec'] = $true
            }
            if ($cur.AChannels -ne $first.AChannels -and -not $seen['ach']) {
                $reasons.Add("音频声道数不同：$($first.AChannels) / $($cur.AChannels)（$name）"); $seen['ach'] = $true
            }
            if ($cur.ASampleRate -ne $first.ASampleRate -and -not $seen['asr']) {
                $reasons.Add("音频采样率不同：$($first.ASampleRate) / $($cur.ASampleRate)（$name）"); $seen['asr'] = $true
            }
        }
    }

    return [PSCustomObject]@{
        Compatible = ($reasons.Count -eq 0)
        Reasons    = $reasons
    }
}

# ============================================================
# 区块六：有损转码的统一规格
# 分辨率 / 帧率都取众数，避免被个别片段带偏
# ============================================================
function Get-TargetSpec {
    param([object[]]$Infos)

    $resCount = @{}
    foreach ($i in $Infos) {
        $k = "$($i.Width)x$($i.Height)"
        $resCount[$k] = [int]$resCount[$k] + 1
    }
    $maxCount = ($resCount.Values | Measure-Object -Maximum).Maximum
    $tied = @($resCount.Keys | Where-Object { $resCount[$_] -eq $maxCount })
    $best = $tied | Sort-Object -Property @{
        Expression = { $p = $_.Split('x'); [int]$p[0] * [int]$p[1] }
    } -Descending | Select-Object -First 1
    $w = [int]$best.Split('x')[0]
    $h = [int]$best.Split('x')[1]
    # yuv420p 要求宽高为偶数，奇数时向下取偶
    if ($w % 2 -ne 0) { $w-- }
    if ($h % 2 -ne 0) { $h-- }

    $fpsCount = @{}
    foreach ($i in $Infos) {
        if ($i.Fps -le 0) { continue }
        $k = $i.Fps.ToString('0.###', [System.Globalization.CultureInfo]::InvariantCulture)
        $fpsCount[$k] = [int]$fpsCount[$k] + 1
    }
    $fpsText = '25'
    if ($fpsCount.Count -gt 0) {
        $fpsMax = ($fpsCount.Values | Measure-Object -Maximum).Maximum
        $fpsText = @($fpsCount.Keys | Where-Object { $fpsCount[$_] -eq $fpsMax })[0]
    }

    return [PSCustomObject]@{
        Width  = $w
        Height = $h
        Fps    = $fpsText
    }
}

# ============================================================
# 区块七：输出文件与临时文件
# ============================================================
function Get-OutputExtension {
    param([object[]]$Infos, [bool]$Lossless)

    if (-not $Lossless) { return 'mp4' }

    $mp4Video = @('h264','hevc','av1','vp9','mpeg4','mpeg2video')
    $mp4Audio = @('aac','mp3','ac3','eac3','alac')

    $vOk = $true
    foreach ($codec in @($Infos | ForEach-Object { $_.VCodec } | Select-Object -Unique)) {
        if ($mp4Video -notcontains $codec) { $vOk = $false }
    }
    $aOk = $true
    foreach ($codec in @($Infos | Where-Object { $_.HasAudio } | ForEach-Object { $_.ACodec } | Select-Object -Unique)) {
        if ($mp4Audio -notcontains $codec) { $aOk = $false }
    }

    $exts = @($Infos | ForEach-Object {
        [System.IO.Path]::GetExtension($_.Name).TrimStart('.').ToLower()
    } | Select-Object -Unique)

    # 全部同一种容器时尽量沿用原容器；ts/mov 这类改 mp4 更通用
    if ($exts.Count -eq 1) {
        $only = $exts[0]
        if ($only -eq 'webm' -and $vOk) { return 'webm' }
        if ($only -eq 'mkv') { return 'mkv' }
    }
    if ($vOk -and $aOk) { return 'mp4' }
    return 'mkv'
}

# 合并输出名：合并_A+B+C<合并时长>.mp4
#   - 各段原名去掉 XXhXXmXXs / XXmXXs 时间标记后再拼接
#   - 超长时截断末尾，但保留时长标签与扩展名的空间
function New-MergeOutputName {
    param(
        [object[]]$Infos,
        [double]$TotalSeconds,
        [string]$Root,
        [string]$Ext
    )

    $total = $Infos.Count
    $prefix = "合并_${total}段合并"

    # 逐段清理原名：去掉 XXhXXmXXs / XXmXXs，空白收紧，去掉首尾多余分隔符。
    # 清理后为空的段（纯时长名）用「第N段」占位；若所有段都是纯时长名，
    # 则不再逐段罗列，直接写成「合并_3段合并 07m21s」。
    $components = @()
    $emptyCount = 0
    for ($i = 0; $i -lt $Infos.Count; $i++) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($Infos[$i].Name)
        $clean = [regex]::Replace($base, '\d{2}h\d{2}m\d{2}s|\d{2}m\d{2}s', '')
        $clean = [regex]::Replace($clean, '\s{2,}', ' ')
        $clean = $clean.Trim(' ', '-', '_', '.', '·')
        if ([string]::IsNullOrEmpty($clean)) {
            $emptyCount++
            $components += "第$($i + 1)段"
        } else {
            $components += $clean
        }
    }
    if ($emptyCount -eq $total) { $components = @() }

    $joined = ($components -join '+')
    $durationTag = Format-DurationTag -Seconds $TotalSeconds
    $extPart = ".$Ext"

    # 预算 = 上限 - 前缀 - 两个空格 - 时长 - 扩展名；再按目录长度收紧，并预留 _99 冲突后缀
    $budget = [math]::Min($script:MaxMergedNameLength, $script:MaxMergedPathLength - $Root.Length) -
              $prefix.Length - 2 - $durationTag.Length - $extPart.Length - 4
    if ($budget -lt 8) { $budget = 8 }

    if ($joined.Length -gt $budget) {
        $cut = $budget
        # 不要把代理对（emoji）劈成半个字符
        if ($cut -gt 0 -and [char]::IsHighSurrogate($joined[$cut - 1])) { $cut-- }
        $joined = $joined.Substring(0, $cut).TrimEnd(' ', '-', '_', '.', '+')
    }

    # 前缀与拼接名之间、拼接名与时长之间各留一个空格
    if ([string]::IsNullOrEmpty($joined)) {
        $stem = $prefix + ' ' + $durationTag
    } else {
        $stem = $prefix + ' ' + $joined + ' ' + $durationTag
    }
    $name = "$stem.$Ext"
    $path = Join-Path $Root $name
    $n = 2
    while (Test-Path -LiteralPath $path) {
        $name = "${stem}_$n.$Ext"
        $path = Join-Path $Root $name
        $n++
    }
    return $path
}

function New-OutputPath {
    param(
        [string]$Root,
        [string]$FirstName,
        [string]$Ext,
        [string]$Prefix = '',
        [string]$Suffix = ''
    )
    # 转码保留完整原名，不做按长度截断：原名本身是合法文件名，
    # 截断会丢掉末尾的时长标记（如 "00m20s" 变成 "00m2"）。
    # 合并名的长度预算在 New-MergeOutputName 里单独处理。
    $base = [System.IO.Path]::GetFileNameWithoutExtension($FirstName)
    # 转码放源文件夹用后缀（原名_转码），
    # 这样按文件名排序时原片与转码片相邻，方便对比参数。
    $stem = "${Prefix}${base}${Suffix}"
    $name = "${stem}.$Ext"
    $path = Join-Path $Root $name
    $n = 2
    while (Test-Path -LiteralPath $path) {
        $name = "${stem}_$n.$Ext"
        $path = Join-Path $Root $name
        $n++
    }
    return $path
}

# concat demuxer 的列表文件：
#   - 路径统一换成正斜杠，避免 ffmpeg 把反斜杠当转义符
#   - 单引号按 ffmpeg 约定转成 '\''
#   - UTF-8 无 BOM，中文路径才不会读成乱码
function Write-ConcatList {
    param([string[]]$Paths, [string]$ListPath)
    $sb = New-Object System.Text.StringBuilder
    foreach ($p in $Paths) {
        $f = $p -replace '\\', '/'
        $f = $f -replace "'", "'\''"
        [void]$sb.AppendLine("file '$f'")
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($ListPath, $sb.ToString(), $utf8)
}

# 有损合并的滤镜脚本：
#   每段 [i:v] fps 归一 → 等比缩放 → 补黑边到目标尺寸 → 统一像素格式
#   无音轨的片段补 anullsrc，保证 concat 时每段都有 [i:a]
function New-FilterGraph {
    param([object[]]$Infos, $Spec)

    $parts = New-Object System.Collections.Generic.List[string]
    $silentDurations = New-Object System.Collections.Generic.List[string]
    $inv = [System.Globalization.CultureInfo]::InvariantCulture

    for ($i = 0; $i -lt $Infos.Count; $i++) {
        # 注意：-f 直接写在 $parts.Add(...) 里时，逗号会被当成方法参数分隔符，
        #       导致 -f 只拿到第一个实参而报「索引越界」，必须先算成变量。
        $videoLine = ("[{0}:v:0]fps={1},scale=w={2}:h={3}:force_original_aspect_ratio=decrease," +
                      "pad={2}:{3}:-1:-1,setsar=1,format=yuv420p[v{0}]") -f $i, $Spec.Fps, $Spec.Width, $Spec.Height
        $parts.Add($videoLine)
    }

    $anyAudio = @($Infos | Where-Object { $_.HasAudio }).Count -gt 0
    $silentIndex = $Infos.Count

    for ($i = 0; $i -lt $Infos.Count; $i++) {
        if ($Infos[$i].HasAudio) {
            $parts.Add(("[{0}:a:0]aformat=sample_fmts=fltp:channel_layouts=stereo:sample_rates=48000[a{0}]" -f $i))
        } elseif ($anyAudio) {
            # 该段没有音轨：用 lavfi 生成的静音补位，索引接在常规输入之后
            $dur = [math]::Max(0.1, [math]::Round($Infos[$i].Duration, 3))
            $silentDurations.Add($dur.ToString('0.###', $inv))
            $parts.Add(("[{0}:a:0]aformat=sample_fmts=fltp:channel_layouts=stereo:sample_rates=48000[a{1}]" -f $silentIndex, $i))
            $silentIndex++
        }
    }

    $concatInputs = ''
    for ($i = 0; $i -lt $Infos.Count; $i++) {
        $concatInputs += "[v$i]"
        if ($anyAudio) { $concatInputs += "[a$i]" }
    }
    $concatOut = if ($anyAudio) { '[outv][outa]' } else { '[outv]' }
    $parts.Add(($concatInputs + "concat=n=$($Infos.Count):v=1:a=$([int]$anyAudio)$concatOut"))

    return [PSCustomObject]@{
        Text             = ($parts -join ';')
        HasAudio         = $anyAudio
        SilentDurations  = @($silentDurations)
    }
}

# ============================================================
# 区块八：编码器与参数
# ============================================================
function Resolve-VideoEncoder {
    param([string]$Codec, [string]$RateMode)

    if ($RateMode -eq 'icq' -or $RateMode -eq 'cbr') {
        if ($Codec -eq 'hevc' -and $script:Env.QsvHevc) { return 'hevc_qsv' }
        if ($Codec -eq 'h264' -and $script:Env.QsvH264) { return 'h264_qsv' }
    }
    $cpuEnc = if ($Codec -eq 'hevc') { 'libx265' } else { 'libx264' }
    if (Test-EncoderAvailable $cpuEnc) { return $cpuEnc }
    return $null
}

function Format-Mbps {
    param([double]$Value)
    $text = $Value.ToString('0.##', [System.Globalization.CultureInfo]::InvariantCulture)
    return "${text}M"
}

function Get-EncoderArgs {
    param($Settings)

    $enc = Resolve-VideoEncoder -Codec $Settings.Codec -RateMode $Settings.RateMode
    if (-not $enc) { return $null }

    $args = @('-c:v', $enc)

    switch ($Settings.RateMode) {
        'icq' {
            # QSV 的质量模式：-global_quality 越低越清晰
            $args += @('-global_quality', [string]$Settings.Icq, '-preset', $Settings.QsvPreset)
        }
        'cbr' {
            # GPU 固定码率：maxrate 与 b:v 相同，bufsize 取 2 倍码率
            $bitrate = Format-Mbps $Settings.CbrMbps
            $buffer = Format-Mbps ($Settings.CbrMbps * 2)
            $args += @('-b:v', $bitrate, '-maxrate', $bitrate, '-bufsize', $buffer, '-preset', $Settings.QsvPreset)
        }
        'crf' {
            $args += @('-crf', [string]$Settings.Crf, '-preset', $Settings.CpuPreset)
            if ($enc -eq 'libx265') {
                # 屏蔽 x265 的逐帧日志，否则控制台会被刷屏
                $args += @('-x265-params', 'log-level=error')
            }
        }
    }

    return $args
}

# ============================================================
# 区块九：执行与校验
# ============================================================
function Test-MergeOutput {
    param(
        [string]$Path,
        [double]$ExpectedDuration,
        [int]$ExpectedWidth,
        [int]$ExpectedHeight
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [PSCustomObject]@{ Ok = $false; Message = '没有生成输出文件' }
    }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -le 0) {
        return [PSCustomObject]@{ Ok = $false; Message = '输出文件大小为 0' }
    }

    $info = Get-VideoInfo -Path $Path
    if ($null -eq $info) {
        return [PSCustomObject]@{ Ok = $false; Message = '输出文件无法解析（可能已损坏）' }
    }

    if ($ExpectedDuration -gt 0) {
        $diff = [math]::Abs($info.Duration - $ExpectedDuration)
        # 阈值取 max(1 秒, 0.2%)：
        #   实测混分辨率做 -c copy 时，输出可能只短 1~2 秒却已花屏，
        #   容差放太宽会把它当成成功。正常同源合并的偏差远小于 1 秒。
        $tolerance = [math]::Max(1.0, $ExpectedDuration * 0.002)
        if ($diff -gt $tolerance) {
            return [PSCustomObject]@{
                Ok      = $false
                Message = "时长不符：输出 $([math]::Round($info.Duration,2))s，预期 $([math]::Round($ExpectedDuration,2))s"
            }
        }
    }

    if ($ExpectedWidth -gt 0 -and ($info.Width -ne $ExpectedWidth -or $info.Height -ne $ExpectedHeight)) {
        return [PSCustomObject]@{
            Ok      = $false
            Message = "分辨率不符：输出 $($info.Width)x$($info.Height)，预期 ${ExpectedWidth}x${ExpectedHeight}"
        }
    }

    return [PSCustomObject]@{ Ok = $true; Message = ''; Info = $info }
}

function Invoke-LosslessMerge {
    param(
        [object[]]$Infos,
        [string]$OutPath,
        [string]$TempDir,
        [string]$OutExt
    )

    $listPath = Join-Path $TempDir 'concat.txt'
    Write-ConcatList -Paths @($Infos | ForEach-Object { $_.FullPath }) -ListPath $listPath

    $argv = @(
        # 拷流时 AAC 常有一串无害的 Non-monotonic DTS 警告，降成 error 只留真正的失败信息
        '-hide_banner','-loglevel','error','-stats','-nostdin','-y',
        '-f','concat','-safe','0','-i',$listPath,
        '-map','0:v:0','-map','0:a?','-c','copy'
    )
    if ($OutExt -eq 'mp4') { $argv += @('-movflags', '+faststart') }
    $argv += $OutPath

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $code = 0
    try {
        $code = Invoke-FfmpegProcess -Exe $script:Env.Ffmpeg -Arguments $argv -AllowPause
    } catch {
        $code = -1
    }
    $sw.Stop()

    return [PSCustomObject]@{
        ExitCode  = $code
        Elapsed   = $sw.Elapsed
        Command   = (Format-CommandLine -Exe $script:Env.Ffmpeg -Arguments $argv)
    }
}

function Invoke-ReencodeMerge {
    param(
        [object[]]$Infos,
        [string]$OutPath,
        [string]$TempDir,
        [string]$OutExt,
        $Settings,
        $Spec
    )

    $graph = New-FilterGraph -Infos $Infos -Spec $Spec

    # ffmpeg 9 已移除 -filter_complex_script，只能把滤镜串作为参数传；
    # Windows 命令行约 32767 字符，片段过多时提前给出可读的提示。
    if ($graph.Text.Length -gt 24000) {
        return [PSCustomObject]@{
            ExitCode = -3
            Elapsed  = [TimeSpan]::Zero
            Command  = ''
            Message  = '片段数量过多，滤镜串超出命令行长度限制，请分批合并'
        }
    }

    $argv = @('-hide_banner','-loglevel','error','-stats','-nostdin','-y')
    foreach ($info in $Infos) { $argv += @('-i', $info.FullPath) }

    # 缺音轨的片段用 lavfi 静音输入补齐，索引天然接在所有 -i 之后
    foreach ($dur in $graph.SilentDurations) {
        $argv += @('-f','lavfi','-t',$dur,'-i','anullsrc=channel_layout=stereo:sample_rate=48000')
    }

    $argv += @('-filter_complex', $graph.Text, '-map', '[outv]')
    if ($graph.HasAudio) { $argv += @('-map', '[outa]') }

    $encoderArgs = Get-EncoderArgs -Settings $Settings
    if (-not $encoderArgs) {
        return [PSCustomObject]@{ ExitCode = -2; Elapsed = [TimeSpan]::Zero; Command = ''; Message = '找不到可用的编码器' }
    }
    $argv += $encoderArgs

    if ($graph.HasAudio) {
        $argv += @('-c:a', 'aac', '-b:a', "$($Settings.AudioKbps)k")
    }
    if ($OutExt -eq 'mp4') { $argv += @('-movflags', '+faststart') }
    $argv += $OutPath

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $code = 0
    try {
        $code = Invoke-FfmpegProcess -Exe $script:Env.Ffmpeg -Arguments $argv -AllowPause
    } catch {
        $code = -1
    }
    $sw.Stop()

    return [PSCustomObject]@{
        ExitCode = $code
        Elapsed  = $sw.Elapsed
        Command  = (Format-CommandLine -Exe $script:Env.Ffmpeg -Arguments $argv)
        Message  = ''
    }
}

# ============================================================
# 区块十：交互小工具
# ============================================================

# 两格缩进的菜单标题（横向选单没有 -Title 参数，由调用方打印）
function Show-MenuTitle {
    param([string]$Title)
    Write-Host
    Write-Host "  $(col_a_title $Title)"
    Write-Host "  $(col_a_line (sep))"
    Write-Host
}

function Read-NumberInput {
    param(
        [string]$Prompt,
        [int]$Min,
        [int]$Max,
        [double]$Default,
        [switch]$AllowDecimal
    )

    while ($true) {
        $raw = Read-Host "  $Prompt"
        if ([string]::IsNullOrWhiteSpace($raw)) {
            if ($AllowDecimal) { return [double]$Default }
            return [int]$Default
        }

        $text = $raw.Trim()
        $inv = [System.Globalization.CultureInfo]::InvariantCulture
        $value = 0.0
        $ok = $false
        if ($AllowDecimal) {
            $ok = [double]::TryParse($text, [System.Globalization.NumberStyles]::Float, $inv, [ref]$value)
        } else {
            $n = 0
            $ok = [int]::TryParse($text, [ref]$n)
            if ($ok) { $value = $n }
        }
        if (-not $ok) {
            Write-Host "  $(col_a_error "❌ 请输入数字，范围 $Min ~ $Max")"
            continue
        }
        if ($value -lt $Min -or $value -gt $Max) {
            Write-Host "  $(col_a_error "❌ 超出范围，请输入 $Min ~ $Max")"
            continue
        }
        if ($AllowDecimal) { return [double]$value }
        return [int]$value
    }
}

# 有损模式的三个设置菜单。q/Esc 时返回 $null（由调用方回模块开头）
# 从配置段直接生成一套设置对象（“一键按上次”和手动设置的最终结果共用）
function New-SettingsFromConfig {
    param($Config, [string]$Section)
    $cfg = $Config[$Section]
    return [PSCustomObject]@{
        Codec     = $cfg['codec']
        RateMode  = $cfg['rateMode']
        Icq       = [int]$cfg['icq']
        CbrMbps   = [double]$cfg['cbrMbps']
        Crf       = [int]$cfg['crf']
        QsvPreset = $cfg['qsvPreset']
        CpuPreset = $cfg['cpuPreset']
        AudioKbps = [int]$cfg['audioBitrateKbps']
        FrameRate = [double]$cfg['frameRate']
    }
}

function Read-ReencodeSettings {
    param(
        $Config,
        [string]$Section = 'merge',
        [switch]$AllowQuickLast,
        [string]$OutputLabel = ''
    )

    $cfg = $Config[$Section]

    # ---- 选单2：编码格式 ----
    Show-MenuTitle '编码格式'
    if ($AllowQuickLast) {
        $lastSettings = New-SettingsFromConfig -Config $Config -Section $Section
        $lastText = Get-RateModeText -Settings $lastSettings
        $lastFrameText = if ([double]$lastSettings.FrameRate -gt 0) { "$($lastSettings.FrameRate) fps" } else { '原帧率' }
        # 摘要单独一行放标题下方，避免选项行过长折行
        Write-Host "  $(col_a_text_muted '上次编码选项：')$(col_a_text "$lastText · $lastFrameText · $OutputLabel")"
        Write-Host ""
        $codecOpts = @(
            @{ Label = '[1]一键按上次'; Value = 'last' }
            @{ Label = '[2]H.265（画质优先）'; Value = 'hevc' }
            @{ Label = '[3]H.264（兼容优先）'; Value = 'h264' }
            @{ Label = '[q/Esc]取消'; Value = 'cancel' }
        )
        $codecDefault = 0
    } else {
        $codecDefault = if ($cfg['codec'] -eq 'h264') { 1 } else { 0 }
        $codecOpts = @(
            @{ Label = '[5]H.265（画质优先）'; Value = 'hevc' }
            @{ Label = '[4]H.264（兼容优先）'; Value = 'h264' }
            @{ Label = '[q/Esc]取消'; Value = 'cancel' }
        )
    }
    $codecPick = Select-Horizontal -Options $codecOpts -Prompt '' -InitialIndex $codecDefault
    if ($null -eq $codecPick -or $codecPick -eq 'cancel') { return $null }

    if ($codecPick -eq 'last') {
        return [PSCustomObject]@{ QuickLast = $true; Settings = $lastSettings }
    }

    # ---- 选单3：编码方式 ----
    $rateMode = $null
    $qsvForCodec = if ($codecPick -eq 'hevc') { $script:Env.QsvHevc } else { $script:Env.QsvH264 }

    if (-not $qsvForCodec) {
        # 硬件不可用时 ICQ / CBR 无意义，直接落到 CPU CRF，省一步选择
        Write-Host "  $(col_a_warning '⚠  未检测到可用的 QSV 硬件编码，已自动使用 CPU CRF 模式')"
        Write-Host
        $rateMode = 'crf'
    } else {
        Show-MenuTitle '编码方式'
        Write-Host "  $(col_a_text_muted 'ICQ / CBR 走 GPU，CRF 走 CPU')"
        Write-Host
        $rateDefault = switch ($cfg['rateMode']) {
            'cbr' { 1 }
            'crf' { 2 }
            default { 0 }
        }
        $rateOpts = @(
            @{ Label = '[i]ICQ 质量'; Value = 'icq' }
            @{ Label = '[b]CBR 码率'; Value = 'cbr' }
            @{ Label = '[c]CRF 质量'; Value = 'crf' }
            @{ Label = '[q/Esc]取消'; Value = 'cancel' }
        )
        $ratePick = Select-Horizontal -Options $rateOpts -Prompt '' -InitialIndex $rateDefault
        if ($null -eq $ratePick -or $ratePick -eq 'cancel') { return $null }
        $rateMode = $ratePick
    }

    # ---- 选单4：数值 ----
    Show-MenuTitle '质量参数'
    $icq = [int]$cfg['icq']
    $cbr = [double]$cfg['cbrMbps']
    $crf = [int]$cfg['crf']

    switch ($rateMode) {
        'icq' {
            $icq = Read-NumberInput -Prompt "请输入 ICQ 质量 18~28（越小越清晰，回车默认 $icq）" -Min 18 -Max 28 -Default $icq
        }
        'cbr' {
            $cbr = Read-NumberInput -Prompt "请输入目标码率 Mbps（仅数字，回车默认 $cbr）" -Min 1 -Max 50 -Default $cbr -AllowDecimal
        }
        'crf' {
            $crf = Read-NumberInput -Prompt "请输入 CRF 质量 0~51（越小越清晰，回车默认 $crf）" -Min 0 -Max 51 -Default $crf
        }
    }

    # ---- 选单5：帧率（仅转码） ----
    $frameRate = 0
    if ($Section -eq 'transcode') {
        Show-MenuTitle '帧率'
        $curFrame = [double]$cfg['frameRate']
        $frameDefault = if ($curFrame -gt 0) { 1 } else { 0 }
        $frameOpts = @(
            @{ Label = '[0]保持原帧率（默认）'; Value = 0 }
            @{ Label = '[1]自定义帧率'; Value = 1 }
            @{ Label = '[q/Esc]取消'; Value = 'cancel' }
        )
        $framePick = Select-Horizontal -Options $frameOpts -Prompt '' -InitialIndex $frameDefault
        if ($null -eq $framePick -or $framePick -eq 'cancel') { return $null }

        if ($framePick -eq 1) {
            $frameDefaultValue = if ($curFrame -gt 0) { $curFrame } else { 30 }
            $frameRate = Read-NumberInput -Prompt "请输入目标帧率（建议 30，1~120，回车默认 $frameDefaultValue）" -Min 1 -Max 120 -Default $frameDefaultValue -AllowDecimal
        }
    }

    # 记住本次选择，下次作为默认值
    $cfg['codec'] = $codecPick
    $cfg['rateMode'] = $rateMode
    $cfg['icq'] = $icq
    $cfg['cbrMbps'] = $cbr
    $cfg['crf'] = $crf
    if ($Section -eq 'transcode') { $cfg['frameRate'] = $frameRate }
    [void](Save-ToolConfig -Config $Config)

    return [PSCustomObject]@{
        Codec      = $codecPick
        RateMode   = $rateMode
        Icq        = $icq
        CbrMbps    = $cbr
        Crf        = $crf
        QsvPreset  = $cfg['qsvPreset']
        CpuPreset  = $cfg['cpuPreset']
        AudioKbps  = $cfg['audioBitrateKbps']
        FrameRate  = [double]$frameRate
    }
}

function Get-RateModeText {
    param($Settings)
    $target = if ($Settings.Codec -eq 'hevc') { 'H.265 / HEVC' } else { 'H.264 / AVC' }
    switch ($Settings.RateMode) {
        'icq' { return "$target · ICQ $($Settings.Icq) · QSV 硬件编码" }
        'cbr' { return "$target · CBR $($Settings.CbrMbps) Mbps · QSV 硬件编码" }
        default { return "$target · CRF $($Settings.Crf) · CPU 软件编码" }
    }
}

# ============================================================
# 区块十一：合并流程
# ============================================================
function Show-ProbeFailures {
    param([object[]]$Items, [int]$Max = 6)
    $shown = [math]::Min($Max, $Items.Count)
    for ($i = 0; $i -lt $shown; $i++) {
        Write-Host "  $(col_a_text_muted ('   · ' + $Items[$i].Name))"
        if (-not [string]::IsNullOrEmpty($Items[$i].Reason)) {
            Write-Host "  $(col_a_error ('     ' + $Items[$i].Reason))"
        }
    }
    if ($Items.Count -gt $shown) {
        Write-Host "  $(col_a_text_muted ('   · … 另有 ' + ($Items.Count - $shown) + ' 个'))"
    }
}

function Show-UncHint {
    param([string]$Root)
    if ($Root.StartsWith('\\')) {
        Write-Host "  $(col_a_text_muted '   共享读取失败：确认文件未被占用；也可映射盘符后重试')"
    }
}

# ============================================================
# 区块十一：扫描与预览（合并 / 转码共用）
# ============================================================
function Get-FolderVideos {
    param([string]$Root)

    $files = @()
    try {
        $files = @(Get-ChildItem -LiteralPath $Root -File -ErrorAction Stop |
            Where-Object {
                $ext = $_.Extension.TrimStart('.').ToLower()
                ($script:VideoExts -contains $ext) -and ($_.Name -notmatch $script:OutputPattern)
            })
    } catch {
        Write-Host "  $(col_a_error "❌ 扫描目录失败：$($_.Exception.Message)")"
        return $null
    }

    if ($files.Count -eq 0) {
        return [PSCustomObject]@{ Count = 0; Infos = @(); Failed = @() }
    }

    # 自然排序：01 → 02 → 10
    $sorted = @($files | Sort-Object -Property @{ Expression = { Get-SortKey $_.Name } })

    Write-Host
    Write-Host "  $(col_a_text_muted "正在读取视频信息（共 $($sorted.Count) 个）...")"
    $infos = @()
    $failed = @()
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        Write-Host -NoNewline "`r  $(col_a_text_muted ("  进度 " + ($i + 1) + " / " + $sorted.Count))$([char]27)[K"
        $info = Get-VideoInfo -Path $sorted[$i].FullName
        if ($null -eq $info -or $info.Duration -le 0) {
            $failed += [PSCustomObject]@{ Name = $sorted[$i].Name; Reason = $script:LastProbeError }
        } else {
            $info | Add-Member -NotePropertyName SizeBytes -NotePropertyValue $sorted[$i].Length
            $infos += $info
        }
    }
    Write-Host

    return [PSCustomObject]@{ Count = $sorted.Count; Infos = $infos; Failed = $failed }
}

function Show-VideoTable {
    param([object[]]$Infos, [object[]]$Failed, [string]$Root, [string]$Title)

    $colName = 42
    $colDur = 10
    $colRes = 12
    $colFps = 8
    $colCodec = 7
    $colSize = 10

    Write-Host
    Write-Host "  $(col_a_title $Title)"
    Write-Host "  $(col_a_line (sep))"
    $hdr = (PadTo '序号' 5) + (PadTo '文件名' $colName) + (PadTo '时长' $colDur) +
           (PadTo '分辨率' $colRes) + (PadTo '帧率' $colFps) + (PadTo '编码' $colCodec) + '大小'
    Write-Host ('  ' + $hdr)
    $sepLine = sep_weak -Len (5 + $colName + $colDur + $colRes + $colFps + $colCodec + $colSize)
    Write-Host ('  ' + $sepLine)

    $maxShow = 25
    $showCount = [math]::Min($maxShow, $Infos.Count)
    for ($i = 0; $i -lt $showCount; $i++) {
        $info = $Infos[$i]
        $fpsText = if ($info.Fps -gt 0) { [math]::Round($info.Fps, 3) } else { '-' }
        $row = (PadTo ("{0,-3}" -f ($i + 1)) 5) +
               (Format-Cell $info.Name $colName) +
               (PadTo (Format-DurationText $info.Duration) $colDur) +
               (PadTo "$($info.Width)x$($info.Height)" $colRes) +
               (PadTo $fpsText $colFps) +
               (PadTo $info.VCodec $colCodec) +
               (Format-FileSize $info.SizeBytes)
        Write-Host ('  ' + $row)
    }
    if ($Infos.Count -gt $maxShow) {
        Write-Host "  $(col_a_text_muted ("  … 还有 " + ($Infos.Count - $maxShow) + " 个未显示"))"
    }
    Write-Host ('  ' + $sepLine)

    $totalDuration = ($Infos | Measure-Object -Property Duration -Sum).Sum
    $totalSize = ($Infos | Measure-Object -Property SizeBytes -Sum).Sum
    $totalLine = "  $(col_a_text_muted '合计：')$(col_a_text $Infos.Count)$(col_a_text_muted ' 个文件 ｜ ')" +
                 "$(col_a_text (Format-DurationText $totalDuration))$(col_a_text_muted ' ｜ ')" +
                 "$(col_a_text (Format-FileSize $totalSize))"
    Write-Host $totalLine

    if ($null -ne $Failed -and $Failed.Count -gt 0) {
        Write-Host "  $(col_a_warning ('⚠ ' + $Failed.Count + ' 个文件读取失败已跳过'))"
        Show-ProbeFailures -Items $Failed -Max 3
        Show-UncHint -Root $Root
    }
    Write-Host
}
# 解析序号输入：支持 1、1-3、1-3,5，也接受中文逗号 / 顿号 / 空格分隔。
# 返回 Indexes（1 基、按输入顺序、已去重），调用方据此挑文件。
function ConvertFrom-SelectionInput {
    param([string]$Text, [int]$Count)

    $indexes = New-Object System.Collections.Generic.List[int]
    $seen = @{}
    # 先把 "1 - 2" 这种带空格的区间收紧，再按逗号 / 空白切分，
    # 否则空格会把区间拆成 1、-、2 三个 token。
    $normalized = $Text -replace '\s*([-~至])\s*', '$1'
    $tokens = @($normalized -split '[,，、\s]+' | Where-Object { $_ -ne '' })
    if ($tokens.Count -eq 0) {
        return [PSCustomObject]@{ Ok = $false; Error = '没有识别到序号'; Indexes = @() }
    }

    foreach ($token in $tokens) {
        $start = 0
        $end = 0
        if ($token -match '^(\d+)$') {
            $start = [int]$Matches[1]
            $end = $start
        } elseif ($token -match '^(\d+)\s*[-~至]\s*(\d+)$') {
            $start = [int]$Matches[1]
            $end = [int]$Matches[2]
        } else {
            return [PSCustomObject]@{ Ok = $false; Error = "无法识别：$token（支持 1、1-3、1-3,5）"; Indexes = @() }
        }

        if ($start -lt 1 -or $end -gt $Count -or $start -gt $end) {
            return [PSCustomObject]@{ Ok = $false; Error = "序号超出范围：$token（有效范围 1~$Count）"; Indexes = @() }
        }
        for ($n = $start; $n -le $end; $n++) {
            if (-not $seen.ContainsKey($n)) {
                $seen[$n] = $true
                $indexes.Add($n)
            }
        }
    }

    if ($indexes.Count -eq 0) {
        return [PSCustomObject]@{ Ok = $false; Error = '没有识别到序号'; Indexes = @() }
    }
    return [PSCustomObject]@{ Ok = $true; Error = ''; Indexes = @($indexes) }
}

# 处理范围：全部 / 指定序号。返回按执行顺序排好的对象数组；取消返回 $null。
# 合并靠这个顺序决定拼接次序，因此选完会再列一遍并确认。
function Select-ProcessingScope {
    param(
        [object[]]$Infos,
        [string]$SelectedTitle = '已选文件（按执行顺序）',
        [string]$OrderHint = ''
    )

    $count = $Infos.Count
    Show-MenuTitle '处理范围'
    $scopeOpts = @(
        @{ Label = '[a]全部视频（回车）'; Value = 'all' }
        @{ Label = '[s]指定序号'; Value = 'select' }
        @{ Label = '[q/Esc]取消'; Value = 'cancel' }
    )
    $scopePick = Select-Horizontal -Options $scopeOpts -Prompt '' -InitialIndex 0
    if ($null -eq $scopePick -or $scopePick -eq 'cancel') { return $null }
    if ($scopePick -eq 'all') { return $Infos }

    while ($true) {
        $raw = Read-Host "  请输入序号（如 1-3,5；共 $count 个，回车取消）"
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }

        $parsed = ConvertFrom-SelectionInput -Text $raw -Count $count
        if (-not $parsed.Ok) {
            Write-Host "  $(col_a_error ('❌ ' + $parsed.Error))"
            continue
        }

        $selected = @($parsed.Indexes | ForEach-Object { $Infos[$_ - 1] })
        Write-Host
        Write-Host "  $(col_a_title $SelectedTitle)"
        Write-Host "  $(col_a_line (sep_weak))"
        for ($i = 0; $i -lt $selected.Count; $i++) {
            Write-Host "  $(col_a_text_muted ('  ' + ($i + 1) + '. '))$(col_a_text (Format-Truncated -Text $selected[$i].Name -MaxWidth 56))"
        }
        Write-Host
        if (-not [string]::IsNullOrEmpty($OrderHint)) {
            Write-Host "  $(col_a_warning $OrderHint)"
            Write-Host
        }

        $okOpts = @(
            @{ Label = '[y]确认这个范围'; Value = 'yes' }
            @{ Label = '[r]重新输入'; Value = 'retry' }
            @{ Label = '[q/Esc]取消'; Value = 'cancel' }
        )
        $ok = Select-Horizontal -Options $okOpts -Prompt '' -InitialIndex 0
        if ($null -eq $ok -or $ok -eq 'cancel') { return $null }
        if ($ok -eq 'retry') { continue }
        return $selected
    }
}
function Invoke-MergeWorkflow {
    param([string]$Root, $Config)

    $scan = Get-FolderVideos -Root $Root
    if ($null -eq $scan) {
        Write-Host
        Wait-AnyKey "  按任意键返回..."
        return
    }

    $infos = $scan.Infos
    $failed = $scan.Failed

    if ($infos.Count -eq 0) {
        if ($failed.Count -gt 0) {
            Write-Host "  $(col_a_error '❌ 没有可合并的视频（全部读取失败）。')"
            Show-ProbeFailures -Items $failed
            Show-UncHint -Root $Root
        } else {
            Write-Host "  $(col_a_warning '⚠  当前文件夹没有找到视频文件。')"
            Write-Host "  $(col_a_text_muted '   支持的扩展名：mp4 / mkv / mov / ts / avi 等常见视频格式')"
        }
        Write-Host
        Wait-AnyKey "  按任意键返回..."
        return
    }
    if ($infos.Count -lt 2) {
        Write-Host "  $(col_a_warning '⚠  只有 1 个可解析的视频，无法合并（至少需要 2 个）。')"
        if ($failed.Count -gt 0) {
            Show-ProbeFailures -Items $failed -Max 3
            Show-UncHint -Root $Root
        }
        Write-Host
        Wait-AnyKey "  按任意键返回..."
        return
    }

    Show-VideoTable -Infos $infos -Failed $failed -Root $Root -Title '视频清单（序号用于选择范围）'

    $selected = Select-ProcessingScope -Infos $infos -SelectedTitle '待合并视频（按此顺序拼接）' -OrderHint '合并将按以上顺序拼接；顺序不对请重新输入序号'
    if ($null -eq $selected) { return }
    $infos = @($selected)
    if ($infos.Count -lt 2) {
        Write-Host "  $(col_a_warning '⚠  至少需要选择 2 个视频才能合并。')"
        Write-Host
        Wait-AnyKey "  按任意键返回..."
        return
    }
    $totalDuration = ($infos | Measure-Object -Property Duration -Sum).Sum

    # ---- 无损可行性 ----
    $compat = Get-Compatibility -Infos $infos
    if ($compat.Compatible) {
        Write-Host "  $(col_a_success '✅ 所有视频参数一致，可以直接无损合并（不重新编码）')"
    } else {
        Write-Host "  $(col_a_warning '⚠  检测到参数不一致，无损合并预计会花屏或时长异常；建议改用有损重新编码')"
        $showReasons = [math]::Min(4, $compat.Reasons.Count)
        for ($r = 0; $r -lt $showReasons; $r++) {
            Write-Host "  $(col_a_text_muted ('   · ' + $compat.Reasons[$r]))"
        }
        if ($compat.Reasons.Count -gt $showReasons) {
            Write-Host "  $(col_a_text_muted ('   · … 另有 ' + ($compat.Reasons.Count - $showReasons) + ' 项差异'))"
        }
    }

    # ---- 选单1：合并方式 ----
    $defaultMode = if ($compat.Compatible) { 0 } else { 1 }
    $copyLabel = if ($compat.Compatible) { '[y]无损合并（推荐）' } else { '[y]仍要尝试无损合并' }
    Show-MenuTitle '合并方式'
    $modeOpts = @(
        @{ Label = $copyLabel; Value = 'copy' }
        @{ Label = '[n]有损重新编码合并'; Value = 'reencode' }
        @{ Label = '[q/Esc]取消'; Value = 'cancel' }
    )
    $modePick = Select-Horizontal -Options $modeOpts -Prompt '' -InitialIndex $defaultMode
    if ($null -eq $modePick -or $modePick -eq 'cancel') { return }

    # ---- 临时目录 ----
    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("TT_Media_Tools\merge_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    try {
        [void](New-Item -ItemType Directory -Path $tempDir -Force)

        $mode = $modePick
        $settings = $null
        $success = $false
        $outPath = $null

        while (-not $success) {

            if ($mode -eq 'copy') {

                $outExt = Get-OutputExtension -Infos $infos -Lossless $true
                $outPath = New-MergeOutputName -Infos $infos -TotalSeconds $totalDuration -Root $Root -Ext $outExt

                Write-Host
                Write-Host "  $(col_a_title '合并摘要')"
                Write-Host "  $(col_a_line (sep))"
                Write-Host "  $(col_a_text_muted '方式：')$(col_a_text '无损合并（-c copy，不重新编码）')"
                Write-Host "  $(col_a_text_muted '输出：')$(col_a_text ([System.IO.Path]::GetFileName($outPath)))"
                Write-Host "  $(col_a_text_muted '路径：')$(col_a_text $outPath)"
                Write-Host

                if (-not $compat.Compatible) {
                    Write-Host "  $(col_a_warning '⚠  参数不一致时 -c copy 可能静默产出坏文件，脚本会在合并后校验并提示回退')"
                    Write-Host
                }

                Show-MenuTitle '确认执行'
                $confirmOpts = @(
                    @{ Label = '[y]开始合并'; Value = 'yes' }
                    @{ Label = '[n]取消'; Value = 'no' }
                )
                $confirm = Select-Horizontal -Options $confirmOpts -Prompt '' -InitialIndex 0
                if ($null -eq $confirm -or $confirm -eq 'no') { return }

                Write-Host
                Write-Host "  $(col_a_title '开始合并')"
                Write-Host

                $result = Invoke-LosslessMerge -Infos $infos -OutPath $outPath -TempDir $tempDir -OutExt $outExt
                Write-Host
                # 列表文件在临时目录且执行后即清理，这里用占位符展示真实命令形状，
                # 避免用户误以为可以原样复制重跑。
                $displayCmd = 'ffmpeg -f concat -safe 0 -i <临时列表> -map 0:v:0 -map 0:a? -c copy "' + $outPath + '"'
                Write-Host "  $(col_a_text_muted '命令：')$(col_a_text_gray $displayCmd)"
                Write-Host

                $check = Test-MergeOutput -Path $outPath -ExpectedDuration $totalDuration
                if ($result.ExitCode -eq 0 -and $check.Ok) {
                    Write-Host "  $(col_a_success '✅ 无损合并完成')"
                    Write-Host "  $(col_a_text_muted '输出：')$(col_a_text ([System.IO.Path]::GetFileName($outPath)))"
                Write-Host "  $(col_a_text_muted '路径：')$(col_a_text $outPath)"
                    Write-Host "  $(col_a_text_muted '路径：')$(col_a_text $outPath)"
                    Write-Host "  $(col_a_text_muted '大小：')$(col_a_text (Format-FileSize (Get-Item -LiteralPath $outPath).Length))$(col_a_text_muted '  ｜ 时长：')$(col_a_text (Format-DurationText $check.Info.Duration))$(col_a_text_muted '  ｜ 用时：')$(col_a_text ([string][math]::Round($result.Elapsed.TotalSeconds, 1) + ' 秒'))"
                    $success = $true
                    break
                }

                # 无损失败：清理残缺输出，询问是否改走有损
                $reason = if ($result.Message) { $result.Message } elseif ($result.ExitCode -ne 0) { "ffmpeg 退出码 $($result.ExitCode)" } else { $check.Message }
                Write-Host "  $(col_a_error "❌ 无损合并失败：$reason")"
                if (Test-Path -LiteralPath $outPath) {
                    Remove-Item -LiteralPath $outPath -Force -ErrorAction SilentlyContinue
                    Write-Host "  $(col_a_text_muted '已删除本次生成的不完整文件，原视频未做任何改动。')"
                }
                Write-Host

                Show-MenuTitle '改用有损重新编码？'
                $retryOpts = @(
                    @{ Label = '[y]改用有损重新编码合并'; Value = 'yes' }
                    @{ Label = '[n]放弃'; Value = 'no' }
                )
                $retry = Select-Horizontal -Options $retryOpts -Prompt '' -InitialIndex 0
                if ($null -eq $retry -or $retry -eq 'no') { return }
                $mode = 'reencode'
                continue
            }

            # ---- 有损重新编码 ----
            $settings = Read-ReencodeSettings -Config $Config
            if ($null -eq $settings) { return }

            $outExt = Get-OutputExtension -Infos $infos -Lossless $false
            $outPath = New-MergeOutputName -Infos $infos -TotalSeconds $totalDuration -Root $Root -Ext $outExt
            $spec = Get-TargetSpec -Infos $infos
            $encoder = Resolve-VideoEncoder -Codec $settings.Codec -RateMode $settings.RateMode
            if (-not $encoder) {
                Write-Host "  $(col_a_error '❌ 没有找到可用的视频编码器（libx264 / libx265 都不可用）')"
                Write-Host
                Wait-AnyKey "  按任意键返回..."
                return
            }

            Write-Host
            Write-Host "  $(col_a_title '合并摘要')"
            Write-Host "  $(col_a_line (sep))"
            Write-Host "  $(col_a_text_muted '方式：')$(col_a_text '有损重新编码合并')"
            Write-Host "  $(col_a_text_muted '编码：')$(col_a_text (Get-RateModeText -Settings $settings))"
            Write-Host "  $(col_a_text_muted '规格：')$(col_a_text "$($spec.Width)x$($spec.Height) @ $($spec.Fps) fps")$(col_a_text_muted '（各段等比缩放后补黑边，统一到该规格）')"
            Write-Host "  $(col_a_text_muted '输出：')$(col_a_text ([System.IO.Path]::GetFileName($outPath)))"
            Write-Host "  $(col_a_text_muted '音频：')$(col_a_text "AAC $($settings.AudioKbps) kbps")$(col_a_text_muted '（无音轨片段自动补静音）')"
            Write-Host

            Show-MenuTitle '确认执行'
            $confirmOpts = @(
                @{ Label = '[y]开始合并'; Value = 'yes' }
                @{ Label = '[n]取消'; Value = 'no' }
            )
            $confirm = Select-Horizontal -Options $confirmOpts -Prompt '' -InitialIndex 0
            if ($null -eq $confirm -or $confirm -eq 'no') { return }

            Write-Host
            Write-Host "  $(col_a_title '开始合并（有损重新编码，耗时较长）')"
            Write-Host

            $result = Invoke-ReencodeMerge -Infos $infos -OutPath $outPath -TempDir $tempDir -OutExt $outExt -Settings $settings -Spec $spec
            Write-Host
            Write-Host "  $(col_a_text_muted '命令：')$(col_a_text_gray $result.Command)"
            Write-Host

            $check = Test-MergeOutput -Path $outPath -ExpectedDuration $totalDuration -ExpectedWidth $spec.Width -ExpectedHeight $spec.Height
            if ($result.ExitCode -eq 0 -and $check.Ok) {
                Write-Host "  $(col_a_success '✅ 有损合并完成')"
                Write-Host "  $(col_a_text_muted '输出：')$(col_a_text ([System.IO.Path]::GetFileName($outPath)))"
                Write-Host "  $(col_a_text_muted '路径：')$(col_a_text $outPath)"
                Write-Host "  $(col_a_text_muted '大小：')$(col_a_text (Format-FileSize (Get-Item -LiteralPath $outPath).Length))$(col_a_text_muted '  ｜ 时长：')$(col_a_text (Format-DurationText $check.Info.Duration))$(col_a_text_muted '  ｜ 用时：')$(col_a_text ([string][math]::Round($result.Elapsed.TotalSeconds, 1) + ' 秒'))"
                $success = $true
                break
            }

            $reason = if ($result.ExitCode -ne 0) { "ffmpeg 退出码 $($result.ExitCode)" } else { $check.Message }
            Write-Host "  $(col_a_error "❌ 有损合并失败：$reason")"
            if (Test-Path -LiteralPath $outPath) {
                Remove-Item -LiteralPath $outPath -Force -ErrorAction SilentlyContinue
                Write-Host "  $(col_a_text_muted '已删除本次生成的不完整文件，原视频未做任何改动。')"
            }
            Write-Host
            Wait-AnyKey "  按任意键返回..."
            return
        }

        Write-Host
        Wait-AnyKey "  按任意键返回..."

    } finally {
        if (Test-Path -LiteralPath $tempDir) {
            Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================
# 区块十一·B：转码流程
# 与合并共用编码器解析 / 质量参数 / 配置段，只是不做拼接与缩放
# ============================================================
# 单文件转码：只换编码/质量，不动分辨率与帧率
# 构建单个文件的转码参数；串行与并发两条路径共用，避免参数逻辑分叉
function Get-TranscodeArguments {
    param($Info, [string]$OutPath, $Settings)

    $encArgs = Get-EncoderArgs -Settings $Settings
    if (-not $encArgs) { return $null }

    $argv = @('-hide_banner','-loglevel','error','-stats','-nostdin','-y','-i',$Info.FullPath,
              '-map','0:v:0','-map','0:a?')
    $argv += $encArgs
    # QSV 原生只吃 nv12，传 yuv420p 会触发「auto-selecting format」告警
    $pixFmt = if (($encArgs -join ' ') -match '_qsv') { 'nv12' } else { 'yuv420p' }
    $argv += @('-pix_fmt', $pixFmt)
    if ($null -ne $Settings.FrameRate -and [double]$Settings.FrameRate -gt 0) {
        $argv += @('-r', [string]$Settings.FrameRate)
    }
    if ($Info.HasAudio) {
        if ($Info.ACodec -eq 'aac') { $argv += @('-c:a','copy') }
        else { $argv += @('-c:a','aac','-b:a',"$($Settings.AudioKbps)k") }
    }
    $argv += @('-movflags','+faststart')
    $argv += $OutPath
    return $argv
}

function Invoke-FileTranscode {
    param($Info, [string]$OutPath, $Settings)

    $argv = Get-TranscodeArguments -Info $Info -OutPath $OutPath -Settings $Settings
    if (-not $argv) {
        return [PSCustomObject]@{ ExitCode = -2; Elapsed = [TimeSpan]::Zero; Message = '没有可用的编码器' }
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $code = 0
    try {
        $code = Invoke-FfmpegProcess -Exe $script:Env.Ffmpeg -Arguments $argv -AllowPause
    } catch {
        $code = -1
    }
    $sw.Stop()

    return [PSCustomObject]@{ ExitCode = $code; Elapsed = $sw.Elapsed; Message = '' }
}

# 读取 ffmpeg -progress 文件，返回百分比与倍速（文件还没写入时返回 $null）
function Get-FfmpegProgressPercent {
    param([string]$Path, [double]$Duration)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        $lines = Get-Content -LiteralPath $Path -Tail 24 -ErrorAction Stop
    } catch {
        return $null
    }
    $us = $null
    $speed = ''
    foreach ($line in $lines) {
        if ($line -match '^out_time_us=(\d+)') { $us = [double]$Matches[1] }
        elseif ($line -match '^speed=(\S+)') { $speed = $Matches[1] }
    }
    if ($null -eq $us -or $Duration -le 0) { return $null }
    $pct = [math]::Min(100, [math]::Max(0, [math]::Round($us / 1000000 / $Duration * 100)))
    return [PSCustomObject]@{ Percent = [int]$pct; Speed = $speed }
}

# ============================================================
# 并发转码组：≤1080p 的文件两两并行，2K/4K 单文件串行
# ------------------------------------------------------------
# 并发时两个 ffmpeg 的 -stats 会互相刷屏，因此这里把 stderr 重定向到
# 临时日志，界面只显示「转码中 / 完成 / 失败」状态行。
# 按 p 会同时挂起 / 恢复本组内所有进程。
# ============================================================
# 启动单个转码任务（不等待），供任务池调度使用
function New-TranscodeJob {
    param(
        $Info,
        [int]$Index,
        [bool]$Big,
        [string]$OutDir,
        [string]$OutSuffix,
        $Settings
    )

    $outPath = New-OutputPath -Root $OutDir -FirstName $Info.Name -Ext 'mp4' -Suffix $OutSuffix
    $argv = Get-TranscodeArguments -Info $Info -OutPath $outPath -Settings $Settings
    if (-not $argv) {
        return [PSCustomObject]@{ Ok = $false; Reason = '没有可用的编码器' }
    }

    # 不开 -stats（多任务会互相刷屏），改用 -progress 写独立文件
    $progress = Join-Path ([System.IO.Path]::GetTempPath()) ("tt_progress_" + [guid]::NewGuid().ToString('N') + ".txt")
    $argv = @($argv | Where-Object { $_ -ne '-stats' })
    $argv = @('-nostats', '-progress', $progress) + $argv

    $argString = ConvertTo-ProcessArgumentString -Arguments $argv
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:Env.Ffmpeg
    $psi.Arguments = $argString
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $false
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    try {
        [void]$proc.Start()
    } catch {
        return [PSCustomObject]@{ Ok = $false; Reason = "无法启动 ffmpeg：$($_.Exception.Message)" }
    }

    return [PSCustomObject]@{
        Ok       = $true
        Process  = $proc
        Info     = $Info
        OutPath  = $outPath
        Progress = $progress
        Index    = $Index
        Big      = $Big
    }
}

# ============================================================
# 转码任务池：小文件滚动补位，大文件独占（有限插队）
# ------------------------------------------------------------
# - 短边 ≤1080：最多 2 个并行，完成一个立即补位
# - 短边 >1080：必须两个槽都空才启动，独占
# - 队首是大文件时，允许当前两个小任务跑完，但不再补位新小文件，
#   直接让大文件独占；完成后恢复小文件双槽
# - 结果按原输入序号排序返回
# ============================================================
function Invoke-TranscodePool {
    param(
        [object[]]$Infos,
        [string]$OutDir,
        [string]$OutSuffix,
        $Settings,
        [int]$TotalCount
    )

    $pending = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $Infos.Count; $i++) {
        $info = $Infos[$i]
        $shortSide = [math]::Min($info.Width, $info.Height)
        $pending.Add([PSCustomObject]@{
            Info  = $info
            Index = $i + 1
            Big   = ($shortSide -gt 1080)
        })
    }

    $outputs = @()
    $failures = @()
    $running = New-Object System.Collections.Generic.List[object]

    # 懒加载挂起 API
    if (-not ('DshVideoTool.Native' -as [type])) {
        $nativeCode = '[DllImport("ntdll.dll")] public static extern int NtSuspendProcess(System.IntPtr processHandle); [DllImport("ntdll.dll")] public static extern int NtResumeProcess(System.IntPtr processHandle);'
        try { Add-Type -Namespace DshVideoTool -Name Native -MemberDefinition $nativeCode -ErrorAction Stop } catch { }
    }

    $canPause = $false
    if ('DshVideoTool.Native' -as [type]) {
        try { if (-not [Console]::IsInputRedirected) { $canPause = $true } } catch { }
    }
    if ($canPause) {
        Write-Host "  $(col_a_text_muted '[p] 暂停 / 继续（作用于当前所有任务）')"
    }

    $suspended = $false
    $lastRefresh = [datetime]::MinValue
    $progressShown = $false

    while ($pending.Count -gt 0 -or $running.Count -gt 0) {

        # ---- 1. 处理已完成任务 ----
        $finished = @($running | Where-Object { $_.Process.HasExited })
        foreach ($job in $finished) {
            $running.Remove($job) | Out-Null
            if ($progressShown) { Write-Host ''; $progressShown = $false }

            $code = $job.Process.ExitCode
            $ok = $false
            $reason = ''
            if ($code -eq 0) {
                $check = Test-MergeOutput -Path $job.OutPath -ExpectedDuration $job.Info.Duration
                $ok = $check.Ok
                $reason = $check.Message
            } else {
                $reason = "ffmpeg 退出码 $code（错误信息见上方控制台输出）"
            }

            if ($ok) {
                $size = (Get-Item -LiteralPath $job.OutPath).Length
                $outName = [System.IO.Path]::GetFileName($job.OutPath)
                Write-Host "     $(col_a_success '✅ 完成')$(col_a_text_muted ' → ')$(col_a_text $outName)$(col_a_text_muted ' ｜ ')$(col_a_text (Format-FileSize $size))"
                $outputs += [PSCustomObject]@{
                    Index = $job.Index
                    Path  = $job.OutPath
                    Name  = $outName
                    Size  = $size
                }
            } else {
                Write-Host "     $(col_a_error "❌ 失败：$reason")"
                if (Test-Path -LiteralPath $job.OutPath) {
                    Remove-Item -LiteralPath $job.OutPath -Force -ErrorAction SilentlyContinue
                }
                $failures += [PSCustomObject]@{ Index = $job.Index; Name = $job.Info.Name; Reason = $reason }
            }

            Remove-Item -LiteralPath $job.Progress -Force -ErrorAction SilentlyContinue
            $job.Process.Dispose()
        }

        # ---- 2. 启动新任务（小文件滚动补位，大文件独占） ----
        while ($running.Count -lt 2) {
            if ($pending.Count -eq 0) { break }

            # 大文件独占：只要还有大文件在跑，就不再启动任何新任务
            if (@($running | Where-Object { $_.Big }).Count -gt 0) { break }

            $head = $pending[0]
            if ($head.Big -and $running.Count -gt 0) { break }   # 大文件必须等槽空

            $pending.RemoveAt(0)
            $job = New-TranscodeJob -Info $head.Info -Index $head.Index -Big $head.Big -OutDir $OutDir -OutSuffix $OutSuffix -Settings $Settings
            if (-not $job.Ok) {
                $failures += [PSCustomObject]@{ Index = $head.Index; Name = $head.Info.Name; Reason = $job.Reason }
                Write-Host "     $(col_a_error "❌ 失败：$($job.Reason)")"
                continue
            }

            $running.Add($job) | Out-Null
            if ($progressShown) { Write-Host ''; $progressShown = $false }
            $hint = if ($head.Big) { '（独占）' } else { '（并行）' }
            Write-Host "  $(col_a_text_muted ("  [$($head.Index)/$TotalCount] " + (Format-Truncated -Text $head.Info.Name -MaxWidth 40) + $hint))"

            if ($head.Big) { break }   # 大文件独占，不再填第二个槽
        }

        if ($running.Count -eq 0) {
            if ($pending.Count -eq 0) { break }
            continue
        }

        # ---- 3. 进度刷新 ----
        if (-not $suspended -and ((Get-Date) - $lastRefresh).TotalMilliseconds -ge 500) {
            $parts = foreach ($j in $running) {
                $name = Format-Truncated -Text $j.Info.Name -MaxWidth 18
                $pr = Get-FfmpegProgressPercent -Path $j.Progress -Duration $j.Info.Duration
                if ($null -eq $pr) { "$name …" }
                else { "$name $($pr.Percent)% $($pr.Speed)" }
            }
            Write-Host ("`r  " + ($parts -join '  ｜  ')) -NoNewline
            $progressShown = $true
            $lastRefresh = Get-Date
        }

        # ---- 4. 暂停 / 继续 ----
        if ($canPause) {
            try {
                if ([Console]::KeyAvailable) {
                    $key = [Console]::ReadKey($true)
                    if ($key.Key -eq [ConsoleKey]::P) {
                        foreach ($j in $running) {
                            try {
                                if ($suspended) { [void][DshVideoTool.Native]::NtResumeProcess($j.Process.Handle) }
                                else { [void][DshVideoTool.Native]::NtSuspendProcess($j.Process.Handle) }
                            } catch { }
                        }
                        $suspended = -not $suspended
                        if ($suspended) {
                            Write-Host ''
                            Write-Host "  $(col_a_warning '⏸ 已暂停当前任务，按 p 继续')"
                        } else {
                            Write-Host ''
                            Write-Host "  $(col_a_success '▶ 继续')"
                            $lastRefresh = [datetime]::MinValue
                        }
                    }
                }
            } catch {
                $canPause = $false
            }
        }

        Start-Sleep -Milliseconds 200
    }

    if ($progressShown) { Write-Host '' }

    return [PSCustomObject]@{
        Outputs  = @($outputs | Sort-Object Index)
        Failures = @($failures | Sort-Object Index)
    }
}
function Invoke-TranscodeWorkflow {
    param([string]$Root, $Config)

    $scan = Get-FolderVideos -Root $Root
    if ($null -eq $scan) {
        Write-Host
        Wait-AnyKey "  按任意键返回..."
        return
    }

    $infos = $scan.Infos
    if ($infos.Count -eq 0) {
        if ($scan.Failed.Count -gt 0) {
            Write-Host "  $(col_a_error '❌ 没有可转码的视频（全部读取失败）。')"
            Show-ProbeFailures -Items $scan.Failed
            Show-UncHint -Root $Root
        } else {
            Write-Host "  $(col_a_warning '⚠  当前文件夹没有找到视频文件。')"
            Write-Host "  $(col_a_text_muted '   支持的扩展名：mp4 / mkv / mov / ts / avi 等常见视频格式')"
        }
        Write-Host
        Wait-AnyKey "  按任意键返回..."
        return
    }

    Show-VideoTable -Infos $infos -Failed $scan.Failed -Root $Root -Title '视频清单（序号用于选择范围）'

    $selected = Select-ProcessingScope -Infos $infos -SelectedTitle '待转码视频（按执行顺序）'
    if ($null -eq $selected) { return }
    $infos = @($selected)

    # “一键按上次”需要把上次的输出位置一起显示出来
    $lastOutMode = $Config['transcode']['outputMode']
    $lastOutShort = if ($lastOutMode -eq 'source') { '源文件夹' } else { '转码成果子文件夹' }

    $settings = Read-ReencodeSettings -Config $Config -Section 'transcode' -AllowQuickLast -OutputLabel $lastOutShort
    if ($null -eq $settings) { return }

    $quickLast = $false
    if ($settings.PSObject.Properties.Name -contains 'QuickLast' -and $settings.QuickLast) {
        $quickLast = $true
        $settings = $settings.Settings
    }

    $encoder = Resolve-VideoEncoder -Codec $settings.Codec -RateMode $settings.RateMode
    if (-not $encoder) {
        Write-Host "  $(col_a_error '❌ 没有找到可用的视频编码器（libx264 / libx265 都不可用）')"
        Write-Host
        Wait-AnyKey "  按任意键返回..."
        return
    }

    # ---- 输出位置 ----
    if ($quickLast) {
        $outMode = $Config['transcode']['outputMode']
        if ($outMode -notin @('subfolder', 'source')) { $outMode = 'subfolder' }
        Write-Host "  $(col_a_text_muted '输出位置：')$(col_a_text $lastOutShort)$(col_a_text_muted '（按上次，开始后不再确认）')"
        Write-Host
    } else {
        Show-MenuTitle '输出位置'
        Write-Host "  $(col_a_text_muted '子文件夹保留原名；源文件夹用 _转码 后缀')"
        Write-Host
        $modeDefault = if ($Config['transcode']['outputMode'] -eq 'source') { 1 } else { 0 }
        $outModeOpts = @(
            @{ Label = '[1]转码成果子文件夹'; Value = 'subfolder' }
            @{ Label = '[2]源文件夹'; Value = 'source' }
            @{ Label = '[q/Esc]取消'; Value = 'cancel' }
        )
        $outMode = Select-Horizontal -Options $outModeOpts -Prompt '' -InitialIndex $modeDefault
        if ($null -eq $outMode -or $outMode -eq 'cancel') { return }

        $Config['transcode']['outputMode'] = $outMode
        [void](Save-ToolConfig -Config $Config)
    }

    $outDir = if ($outMode -eq 'subfolder') { Join-Path $Root '转码成果' } else { $Root }
    $outSuffix = if ($outMode -eq 'subfolder') { '' } else { '_转码' }
    $outLabel = if ($outMode -eq 'subfolder') { '转码成果 子文件夹（保留原名）' } else { '源文件夹（原名_转码）' }
    if ($outMode -eq 'subfolder' -and -not (Test-Path -LiteralPath $outDir)) {
        try {
            [void](New-Item -ItemType Directory -Path $outDir -Force -ErrorAction Stop)
        } catch {
            Write-Host "  $(col_a_error "❌ 无法创建输出文件夹：$($_.Exception.Message)")"
            Write-Host
            Wait-AnyKey "  按任意键返回..."
            return
        }
    }

    Write-Host
    Write-Host "  $(col_a_title '转码摘要')"
    Write-Host "  $(col_a_line (sep))"
    Write-Host "  $(col_a_text_muted '编码：')$(col_a_text (Get-RateModeText -Settings $settings))"
        $frameLabel = if ($null -ne $settings.FrameRate -and [double]$settings.FrameRate -gt 0) { "$($settings.FrameRate) fps" } else { '保持原帧率' }
    Write-Host "  $(col_a_text_muted '规格：')$(col_a_text "保持原分辨率 · 帧率 $frameLabel")$(col_a_text_muted '（统一 8-bit yuv420p）')"
    Write-Host "  $(col_a_text_muted '音频：')$(col_a_text "AAC $($settings.AudioKbps) kbps")$(col_a_text_muted '（AAC 源直接复制，其余转 AAC）')"
    Write-Host "  $(col_a_text_muted '输出：')$(col_a_text $outLabel)"
    Write-Host

    if (-not $quickLast) {
        Show-MenuTitle '确认执行'
        $confirmOpts = @(
            @{ Label = '[y]开始转码'; Value = 'yes' }
            @{ Label = '[n]取消'; Value = 'no' }
        )
        $confirm = Select-Horizontal -Options $confirmOpts -Prompt '' -InitialIndex 0
        if ($null -eq $confirm -or $confirm -eq 'no') { return }
    }

    Write-Host
    Write-Host "  $(col_a_title '开始转码（≤1080p 双任务滚动补位，2K/4K 独占）')"
    Write-Host

    $outputs = @()
    $failures = @()
    $totalSw = [System.Diagnostics.Stopwatch]::StartNew()

    $poolResult = Invoke-TranscodePool -Infos $infos -OutDir $outDir -OutSuffix $outSuffix -Settings $settings -TotalCount $infos.Count
    $outputs = @($poolResult.Outputs)
    $failures = @($poolResult.Failures)

    $totalSw.Stop()

    Write-Host
    Write-Host "  $(col_a_line (sep))"
    $summary = "  $(col_a_success ('[√] 完成：成功 ' + $outputs.Count + ' 个'))"
    if ($failures.Count -gt 0) {
        $summary += "，$(col_a_error ('失败 ' + $failures.Count + ' 个'))"
    }
    $summary += "$(col_a_text_muted ' ｜ 总用时 ')$(col_a_text ([string][math]::Round($totalSw.Elapsed.TotalSeconds, 1) + ' 秒'))"
    Write-Host $summary

    if ($failures.Count -gt 0) {
        Write-Host "  $(col_a_text_muted '失败列表：')"
        foreach ($f in ($failures | Select-Object -First 5)) {
            Write-Host "  $(col_a_text_muted ('   · ' + $f.Name))"
            Write-Host "  $(col_a_error ('     ' + $f.Reason))"
        }
    }

    if ($outputs.Count -gt 0) {
        Write-Host
        Write-Host "  $(col_a_text_muted '输出目录：')$(col_a_text $outDir)"
        Write-Host "  $(col_a_text_muted '输出清单：')"
        $shown = [math]::Min(20, $outputs.Count)
        for ($k = 0; $k -lt $shown; $k++) {
            Write-Host "  $(col_a_text_muted ('   · ' + $outputs[$k].Name))"
        }
        if ($outputs.Count -gt $shown) {
            Write-Host "  $(col_a_text_muted ('   · … 另有 ' + ($outputs.Count - $shown) + ' 个'))"
        }
    }

    Write-Host
    Wait-AnyKey "  按任意键返回..."
}
# ============================================================
# 区块十二：主循环
# ============================================================

# 被 dot-source 时只加载函数，不进入交互（便于调试与复用）
if ($MyInvocation.InvocationName -eq '.') { return }

$script:Config = Import-ToolConfig

while ($true) {

    Clear-Screen
    Write-Host

    $cwdDisplay = $PWD.ProviderPath
    if ($cwdDisplay.Length -gt 78) {
        $cwdDisplay = $cwdDisplay.Substring(0, 38) + '…' + $cwdDisplay.Substring($cwdDisplay.Length - 38)
    }

    Write-Host "  $(col_a_title ('video_tool.ps1 — 视频合并 / 转码工具'))"
    Write-Host "  $(col_a_line (sep))"
    Write-Host
    Write-Host "  $(col_a_text_muted '处理目录：')$(col_a_text $cwdDisplay)"
    Write-Host
    Write-Host "  $(col_a_text_muted '合并：当前文件夹内的视频首尾拼接，默认无损')"
    Write-Host "  $(col_a_text_muted '转码：逐个文件重新编码，QSV 硬件优先')"
    Write-Host "  $(col_a_text_muted '顺序按文件名自然排序：01 → 02 → 10')"
    Write-Host

    $envOk = Initialize-Environment
    if (-not $envOk) {
        $missing = @()
        if (-not $script:Env.Ffmpeg) { $missing += 'ffmpeg.exe' }
        if (-not $script:Env.Ffprobe) { $missing += 'ffprobe.exe' }
        Write-Host "  $(col_a_error ('❌ 未找到：' + ($missing -join '、')))"
        Write-Host "  $(col_a_text_muted '   视频合并需要 ffmpeg 与 ffprobe 同时可用。')"
        Write-Host
        Write-Host "  $(col_a_text '获取方式（任选其一）：')"
        Write-Host "  $(col_a_text_muted '   a）GitHub 构建（国内相对快）：')"
        Write-Host "  $(col_a_text_muted '      https://github.com/BtbN/FFmpeg-Builds/releases/latest')"
        Write-Host "  $(col_a_text_muted '      选 Windows x64 的 GPL static 包')"
        Write-Host "  $(col_a_text_muted '      解压后取 bin 下的 ffmpeg.exe / ffprobe.exe')"
        Write-Host "  $(col_a_text_muted '   b）winget install Gyan.FFmpeg')"
        Write-Host
        Write-Host "  $(col_a_text '放置位置（推荐）：')"
        Write-Host "  $(col_a_text_muted "   把 ffmpeg.exe / ffprobe.exe 放进  $($script:ToolsDir)")"
        Write-Host "  $(col_a_text_muted '   或放入系统 PATH，脚本会自动识别')"
        Write-Host
        Wait-AnyKey "  按任意键返回..."
        exit 1
    }

    $ffVer = if ($script:Env.Version) { "v$($script:Env.Version)" } else { '已找到' }
    $qsvText = if ($script:Env.QsvHevc -and $script:Env.QsvH264) { "$(col_a_success '可用') （hevc_qsv / h264_qsv）" }
               elseif ($script:Env.QsvHevc) { "$(col_a_success '仅 HEVC 可用')" }
               elseif ($script:Env.QsvH264) { "$(col_a_success '仅 H.264 可用')" }
               else { "$(col_a_text_muted '不可用（只提供 CPU CRF 模式）')" }

    Write-Host "  $(col_a_text_muted 'ffmpeg   ：')$(col_a_success $ffVer)"
    Write-Host "  $(col_a_text_muted 'ffprobe  ：')$(col_a_success '已找到')"
    Write-Host "  $(col_a_text_muted 'QSV 硬件 ：')$qsvText"
    Write-Host

    if ($script:ConfigCreated) {
        Write-Host "  $(col_a_text_muted '已生成配置文件：')$(col_a_text 'modules\video_tool.config.json')"
    }
    if ($script:ConfigWarnings.Count -gt 0) {
        Write-Host "  $(col_a_warning ('⚠ 配置文件有 ' + $script:ConfigWarnings.Count + ' 处问题，已回退内置默认值'))"
        for ($w = 0; $w -lt [math]::Min(3, $script:ConfigWarnings.Count); $w++) {
            Write-Host "  $(col_a_text_muted ('   · ' + $script:ConfigWarnings[$w]))"
        }
    }

    # ---- 选单0：功能模式 ----
    Show-MenuTitle '功能模式'
    $modeOpts = @(
        @{ Label = '[1]视频合并工具'; Value = 'merge' }
        @{ Label = '[2]视频转码工具'; Value = 'transcode' }
        @{ Label = '[q/Esc]退出'; Value = 'exit' }
    )
    $modePick = Select-Horizontal -Options $modeOpts -Prompt '' -InitialIndex 0
    if ($null -eq $modePick -or $modePick -eq 'exit') { exit 0 }

    if ($modePick -eq 'transcode') {
        Invoke-TranscodeWorkflow -Root $PWD.ProviderPath -Config $script:Config
        continue
    }

    Invoke-MergeWorkflow -Root $PWD.ProviderPath -Config $script:Config
}
