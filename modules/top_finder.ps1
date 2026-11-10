<#
top_finder.ps1
变更要点：
1. D模式：主排序按时长，保留全局预读全部时长
2. B/R模式：不全局读时长，后置询问
3. S开启元数据：后置扫描交互
4. 非交互模式：param() 驱动，-UserQuery 强制，txt 文件名用原文
5. S/B 模式均支持 -MinBitrate 码率筛选
6. Test-Path 全部用 -LiteralPath 防特殊字符
7. >>> FIX: 所有 $sorted/$outputRows 强制 @() 物化，防止单条结果时 Count=$null 导致 txt 空行
8. >>> FIX v5: 时长读取退回 cmd /c + noprint_wrappers=1:nokey=1 + 重定向文件方案
    新增 Invoke-FfprobeDuration 函数，所有时长点（D模式预读/后置扫描/交互预读/交互后置）
    统一用旧代码稳定调用方式，解决 nw=1:nk=1 + -- 分隔符 + RedirectStandardOutput
    在部分 ffprobe 版本下静默失败导致时长全部读取失败的问题
9. >>> 交互模式 TXT 文件名和内部描述补全：基于用户交互选择生成 $fullDesc，
    区分交互/非交互命名规则，扫描路径去掉 PowerShell 底层前缀
10. >>> FIX v10: 交互模式时长逻辑修复：
    - S模式选读取元数据：ffprobe 已返回 duration，顺带提取，不再弹窗问时长
    - 不读元数据→后置扫时长：TXT 强制输出时长列（即使 $exportMeta=$false）
    - 后置扫完时长后刷新预览，让用户看到实际结果
11. >>> FIX v11: 双进度条（目录+文件），单行回车刷新
12. >>> FIX v12: B模式等非D模式时长显示修复：
    - 预览输出直接信任 $metaHasDuration 标记，不再依赖单条 $item.DurationDisp -ne "-"
    - TXT 保存同步修复 $hasDurationCol 判定
    - 确保 ffprobe json 中 format.duration 被正确解析并传递到最终输出
13. >>> FIX v13: 时长显示兜底 + 进度条单行刷新（2026-10-20）
    - 元数据解析前强制初始化 $durSec=0.0/$durDisp="-"，解析成功才覆盖，确保 $vi.DurationDisp 非空
    - 预览段：当 $metaHasDuration 为真时，若单条 DurationDisp 仍为 "-" 则用 Get-FriendlyDuration(0) 兜底显示 "00m00s"，避免全 "-"
    - 进度条：Show-DualProgressBar 已用 `r + Write-Host -NoNewline 单行覆盖，扫描结束 Write-Host "" 换行
    - TXT 保存维持 v12 的 $metaHasDuration 判定（不再改列逻辑）
14. >>> FIX v14: 准备阶段实时进度（2026-10-20）
    - 目录统计与文件收集合并为同一阶段，边遍历边显示单行进度，消除"假死感"
    - 非交互模式同步应用
15. >>> FIX v15: 三阶段线性融合进度条（2026-10-20）
    - 将整体进度分为：阶段1(目录遍历40%) + 阶段2(元数据读取60%)
    - 全程单行覆盖，从0%到100%连续推进，不再出现"进度条一闪而过"
    - Show-DualProgressBar 改为 Show-LinearProgressBar，显示总进度百分比
16. >>> FIX v16: 一次 ffprobe 全拿三件套 + 删后置扫描 + 进度条收尾（2026-10-20）
    - $extraArgs 统一追加 :format=duration，B/R/S(元数据) 模式一次调用拿全码率+分辨率+时长
    - 删除交互模式后置时长扫描弹窗及整个后置扫描逻辑（时长已在第一轮 ffprobe 中获取）
    - 删除非交互模式 $ScanDuration 后置扫描段
    - $metaHasDuration 简化为直接等于 $exportMeta（只要调 ffprobe 就有时长）
    - 预览段不再对0秒调用 Get-FriendlyDuration(0) 兜底
    - 交互模式阶段1进度条收尾从40%改为100%
    - TXT 输出列判定统一用 $exportMeta
17. >>> FIX v17: 百分比变化才刷新，防止爆发式刷屏（2026-10-20）
    - 阶段2主循环增加 $lastPct 变量，仅百分比变化或完成时调用 Show-LinearProgressBar
    - 配合 300ms 节流，解决并发 ffprobe 结果集中返回时进度条瞬间刷屏问题
18. >>> FIX v18: 阶段2进度条独立0-100%（2026-10-20）
    - 阶段2不再映射 40-100%，改为独立 0-100%（$processedCount/$totalVideoCount*100）
    - 修复原代码中 $pctVal=$phase2Current 引用不存在变量的 bug，改为 $pctVal=$phase2Pct
    - 阶段1(扫描)和阶段2(元数据)各自从0%走到100%，视觉边界清晰
19. >>> FIX v19: 最终大小过滤 + TXT 注明过滤统计（2026-10-20）
    - 新增 -MinSizeMB 参数，在排序完成后、预览输出前过滤掉小于指定大小的文件
    - 原排序逻辑（升降序）一字不动，过滤仅作为最终拦截环节
    - TXT 输出头部注明：按大小条件过滤掉多少个文件、过滤阈值是多少
20. >>> FIX v20: 二次排序（2026-10-20）
    - 新增 -ReSortBy 参数，支持对主排序结果集按另一维度重新排序
    - 支持维度：D(时长)、S(文件大小)、B(码率)、R(分辨率长边)
    - 默认降序排列，升序接口预留（-ReSortAsc 将来再加）
    - 执行位置：主排序完成后、大小过滤前，不改变原排序逻辑
    - 非交互/交互模式均支持
21. >>> FIX v21: 筛选漏斗统计，TXT头部按执行顺序输出各环节拦截数量（2026-10-20）
    - 新增漏斗计数变量：$heightFilteredCount, $sizeTopFilteredCount, $bitrateFilteredCount, $reSortCount, $sizeFilteredCount
    - 非交互/交互模式均在对应筛选环节插入计数
    - TXT 头部按实际执行顺序逐行输出：总扫描 → 高度过滤 → 体积初筛 → 码率过滤 → 二次排序 → 大小过滤 → 最终输出
    - 仅在该环节实际触发且拦截数>0时才输出对应行，保持简洁
v22.0：新增CSV分析子菜单，检测当前目录nfo_export_*.csv（排除nfo_export_onlynfo_*.csv）
	菜单1/2内联检查孤儿NFO/不一致，
	菜单3纯CSV映射注入$workList（字段：视频文件路径/文件大小MB/总码率kbps/宽/高/时长_秒）跳过递归与格式询问从排序维度继续，
	菜单4忽略CSV走完整扫描，Q返回主菜单 return。
	全程零磁盘IO零ffprobe，D模式预读加-not $useCsvAsSource跳过，元数据分支加前置保护。
	延续v21漏斗统计/预览/TXT保存不变。
v3.2（2026-11-05）：修复 CSV 数据源与 nfo_export 的列名不匹配
	- 菜单2 改读「NFO内文件名校验」（旧列 HasVideo / Consistent 已不存在，原逻辑恒为 0 条）
	- 菜单3 分辨率优先读「宽/高」列，缺失时从「分辨率」列解析（原 R 排序长边恒为 $null，等于失效）
	- CSV 检测与 Import-Csv 改用 -LiteralPath（路径含 [ ] 时 -Path 会当通配符，静默找不到文件）
v3.3（2026-11-05）：排序与输出修正
	- B 模式 + 码率阈值时 -Top 失效（过滤分支没有截断），改为先过滤再统一截断
	- S 模式漏斗统计把「Top 截断」误报成「码率过滤」，改为只统计过滤本身造成的损失
	- D 模式删除二次 ffprobe 扫描（v16 起时长已在元数据阶段获取，原逻辑使耗时为两倍）
	- -SizeTopCount 默认 100 → 500（该截断发生在 ffprobe 之后，加大不增加任何耗时）
	- 新增 -Top 0 = 不限制；发生截断时控制台与 TXT 均给出提示，不再静默丢弃
	- 结果为空时输出「漏斗诊断」：列出各环节排除数量与对应阈值，便于定位哪一刀砍狠了
	- 新增 -DumpAll：导出本次扫描到的全量视频数据集 CSV（列名与 nfo_export 对齐，可直接回灌分析）
	- 移除「终止本机所有 ffprobe」功能（会误杀用户正在运行的格式工厂 / QuickSync 转码）
v3.4~v3.9（2026-11-05）：界面与选单统一
	- 接入 modules\ui\ui.ps1：Clear-Screen、col_a_* 配色、处理目录回显
	- 全部 11 个选单由「横向 Select-Horizontal」改为「竖向 Arrow-Menu」
	  原因：横向在选项多 / 文件名长时必然折行，而 Select-Horizontal 用 \r 回行首重绘，
	        折行后会残留重复行（实测可刷出十几行），故凡是可能超宽的菜单都必须竖向
	- 选单标题与分隔线改由菜单自身打印（Select-Vertical 的 -Title / -Note），
	  并作为 Header 传给 Arrow-Menu，使窗口缩放触发的清屏重绘能恢复标题，
	  避免清屏后用户看不出这个菜单是干什么的
	- 标题块统一为「空行 + 标题 + 说明 + 60 个 = 分隔线」；
	  因此子菜单前调用方的空行由 2 行减为 1 行（菜单自己补 1 行，合计仍为 2 行）
	- 合并 CSV 菜单里重复的「按任意键」提示（原先自打一行 + Wait-AnyKey 默认再打一行）
v3.10（2026-11-05）：并发与中断清理
	- ffprobe 并发限流由「全机器 Get-Process ffprobe 计数」改为「只统计本脚本自己拉起且未退出的进程」，
	  避免用户同时转码时，外部 ffprobe 占满配额导致本脚本长时间空等
	- 删除交互 D 模式预读里的同步限流（cmd /c 一次只跑一个，本就不可能超过并发上限）
	- trap 从交互段提前到 param 之后，使「非交互模式」也能在 Ctrl+C 时清理子进程

【维护警告 1】trap 内的颜色必须用裸 -ForegroundColor，不得改成 col_a_*
	trap 位于 param 之后、ui.ps1 加载之前；非交互模式根本不会加载 ui.ps1。
	若在 trap 里调用 col_a_*，一旦触发异常会再抛「找不到 col_a_warning」，把真实错误盖掉。
	这不是「不符合 UI 颜色规范」，而是此处必须脱离 ui.ps1 的硬约束。
【维护警告 2】trap 内只对 PipelineStoppedException（Ctrl+C）中断，其余异常必须 throw
	原 trap 是无条件 break，位置靠后时影响面小；移到脚本顶部后若仍无条件 break，
	会把「路径不存在 / ffprobe 缺失」这类正常报错吞成静默退出，比不捕获更糟。
【维护警告 3】trap 内引用 $taskList 前必须判空
	异常可能发生在变量初始化之前，直接传 $null 会引发二次异常。
#>

param(
    [string]$Mode = "",
    [string]$Path = "",
    [switch]$Recurse,
    [switch]$AllFiles,
    [switch]$Meta,
    [switch]$DumpAll,           # >>> v3.3: 导出本次扫描到的全量视频数据集为 CSV（不做任何筛选截断）
	
    [int]$Top = 100,
    [int]$BitrateThreshold = 0,
    [int]$MinBitrate = 0,
    [int]$MinHeight = 0,
    [int]$MaxHeight = 0,
    [string]$Output = "",
    [switch]$JsonOutput,
    [switch]$SizeTop,
    [int]$SizeTopCount = 500,
    [long]$MinSizeMB = 0,
    [string]$ReSortBy = "",           # >>> FIX v20: 二次排序维度，D/S/B/R，默认空=不二次排序
    [string]$UserQuery = ""
)

# ============================================================
# v3.10：trap 提到脚本顶部，让"非交互模式"在 Ctrl+C 时也能清理子进程。
#   三点必须注意：
#   1) 此处不能使用 col_a_* —— ui.ps1 只在交互模式加载，非交互模式调用会报错；
#   2) $taskList 可能在异常发生时尚未定义，必须判空；
#   3) 只对 Ctrl+C（PipelineStoppedException）中断，其余异常继续向外抛，
#      否则任何错误都会被 trap 吞掉、脚本静默退出，比不捕获还糟。
# ============================================================
trap {
    if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) {
        Write-Host "`n  ⚠️ 捕获到 Ctrl+C 中断，正在清理本次脚本拉起的子进程..." -ForegroundColor Yellow
        if ($taskList) { Cleanup-TaskProcesses -TaskList $taskList }
        break
    }
    throw
}

function Wait-AnyKey {
    param([string]$Prompt="`n按任意键继续...")
    Write-Host $Prompt
    [Console]::ReadKey($true) | Out-Null
}

# ====================== 公共函数区 ======================

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
    param([string]$Path,[bool]$DoRecurse,[string[]]$BlackList,[ref]$OutAccessDeniedDirs,[ref]$OutScanErrors,[switch]$ShowProgress)
    $fileList = @(); $subDirs = @(); $dirCount = 0
    try { $files = Get-ChildItem -LiteralPath $Path -File -ErrorAction Stop; $fileList += $files }
    catch {
        if ($_.Exception.HResult -eq -2147024891) { if ($Path -and $Path -notin $OutAccessDeniedDirs.Value) { $OutAccessDeniedDirs.Value += $Path } }
        $OutScanErrors.Value += $_
    }
    if ($DoRecurse) {
        try { $subDirs = Get-ChildItem -LiteralPath $Path -Directory -ErrorAction Stop }
        catch { if ($_.Exception.HResult -eq -2147024891) { if ($Path -and $Path -notin $OutAccessDeniedDirs.Value) { $OutAccessDeniedDirs.Value += $Path } }; $OutScanErrors.Value += $_ }
        foreach ($d in $subDirs) {
            $dirCount++
            if ($ShowProgress -and $dirCount % 5 -eq 0) {
                Write-Host ("`r  ├─ 扫描目录中... {0} | 已收集文件: {1}" -f $dirCount, $fileList.Count) -NoNewline
            }
            $dirName = $d.Name; $hitBlack = $false
            foreach($bItem in $BlackList){ if($dirName.IndexOf($bItem, [System.StringComparison]::OrdinalIgnoreCase) -ge 0){ $hitBlack = $true; break } }
            if($hitBlack){ Write-Host "`n  >> 跳过黑名单文件夹：$($d.FullName)" -ForegroundColor DarkGray; continue }
            $childResult = Get-AllFilteredFiles -Path $d.FullName -DoRecurse $true -BlackList $BlackList -OutAccessDeniedDirs $OutAccessDeniedDirs -OutScanErrors $OutScanErrors -ShowProgress:$ShowProgress
            $fileList += $childResult
        }
    }
    return $fileList
}

function Invoke-FfprobeDuration {
    param([string]$FilePath,[string]$OutFile)
    $arg = '/c ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "' + $FilePath + '" > "' + $OutFile + '"'
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = $arg
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($psi)
    $proc.WaitForExit()
    $output = ""
    if (Test-Path -LiteralPath $OutFile) { $output = [System.IO.File]::ReadAllText($OutFile).Trim() }
    return @{ ExitCode = $proc.ExitCode; Output = $output }
}

function Invoke-Ffprobe {
    param([string]$Arguments,[string]$OutFile)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "ffprobe.exe"; $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [System.Text.Encoding]::UTF8
    $proc = [System.Diagnostics.Process]::Start($psi)
    $stdOut = $proc.StandardOutput.ReadToEnd(); $stdErr = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    $output = if ($stdOut -and $stdOut.Trim() -match '\d') { $stdOut.Trim() } else { $stdErr.Trim() }
    if ($OutFile -and $output) { [System.IO.File]::WriteAllText($OutFile, $output, [System.Text.Encoding]::UTF8) }
    return @{ ExitCode = $proc.ExitCode; Output = $output }
}

function Get-FfprobeArgs {
    param([string]$FilePath,[string]$ExtraArgs = "")
    $esc = $FilePath -replace '(\\*)"', '$1$1\"'
    $esc = $esc -replace '(\\+)$', '$1$1'
    $quotedPath = '"' + $esc + '"'
    if ($ExtraArgs) { return "$ExtraArgs -- $quotedPath" } else { return "-- $quotedPath" }
}

# >>> FIX v15: 线性总进度条 - 三阶段融合，单行回车刷新
function Show-LinearProgressBar {
    param([int]$Current, [int]$Total, [string]$Status="", [int]$ThrottleMs=300)
    $now = [Environment]::TickCount
    if ($null -eq $script:_lastProgTick) { $script:_lastProgTick = 0 }
    $pct = if($Total -gt 0){ [int]($Current / $Total * 100) }else{0}
    if (($now - $script:_lastProgTick) -lt $ThrottleMs -and $pct -eq $script:_lastPct -and $Current -lt $Total) { return }
    $script:_lastProgTick = $now; $script:_lastPct = $pct
    $barLen = 30; $filled = [int]($barLen * $pct / 100)
    $bar = ("█" * $filled).PadRight($barLen, "░")
    $line = "`r[$bar] $pct% ($Current/$Total) $Status"
    if ($Current -ge $Total) { Write-Host "  $line`n" -NoNewline }
    else { Write-Host $line -NoNewline }
}

# ====================== 非交互模式入口 ======================
if ($Mode -ne "") {
    Write-Host "  >>> 非交互模式：参数驱动" -ForegroundColor Cyan
    Write-Host "  >>> Mode=$Mode Recurse=$($Recurse.IsPresent) Meta=$($Meta.IsPresent) BitrateThreshold=$BitrateThreshold MinBitrate=$MinBitrate MinHeight=$MinHeight MaxHeight=$MaxHeight MinSizeMB=$MinSizeMB ReSortBy=$ReSortBy" -ForegroundColor Gray

    $scanRoot = if ($Path) { $Path } else { $PWD.Path.Trim() }
    $recurseParam = $Recurse.IsPresent
    $videoMode = -not $AllFiles.IsPresent
    $sortMode = $Mode.ToUpper()
    if ($sortMode -notin "S","B","R","D") { Write-Host "  错误：Mode 必须是 S/B/R/D 之一" -ForegroundColor Red; exit 1 }
$exportMeta = $Meta.IsPresent -or ($sortMode -in "B","R","D") -or $DumpAll
    # v3.11：参数回显显示的是「你传了什么」，摘要显示的是「实际会不会读」。
    #   当两者不一致时（B/R/D 排序隐含、-DumpAll 隐含），补一句说明，
    #   避免用户看到 Meta=False 却又有「元数据：True」而误解。
    if (-not $Meta.IsPresent -and $exportMeta) {
        $metaReason = if ($DumpAll) { '-DumpAll 需要完整数据集' } else { "按 $sortMode 排序需要元数据" }
        Write-Host "  >>> 注意：$metaReason，已自动开启元数据读取（等同 -Meta）" -ForegroundColor DarkGray
    }
# -Top 0 表示不限制（输出全部）
$topCount = if ($Top -le 0) { [int]::MaxValue } else { $Top }
    $bitrateThresholdKbps = if ($MinBitrate -gt 0) { $MinBitrate } elseif ($BitrateThreshold -gt 0) { $BitrateThreshold } else { 0 }
    $useBitrateFilter = ($bitrateThresholdKbps -gt 0)
    $maxConcurrent = 4; $progressStep = 20

    # >>> FIX v19: 计算最小文件大小过滤阈值
    $minSizeBytes = if ($MinSizeMB -gt 0) { $MinSizeMB * 1024 * 1024 } else { 0 }
    if ($minSizeBytes -gt 0) { Write-Host "  大小过滤：排除小于 $MinSizeMB MB 的文件" -ForegroundColor Yellow }

    if ($exportMeta -and -not (Test-FfprobeAvailable)) {
        Write-Host "  错误：需要 ffprobe 但未找到，请安装后重试" -ForegroundColor Red; exit 1
    }

    Write-Host "  扫描路径：$scanRoot"
    Write-Host "  递归：$recurseParam | 仅视频：$videoMode | 排序：$sortMode | 元数据：$exportMeta"
    if ($useBitrateFilter) { Write-Host "  码率阈值：>= $bitrateThresholdKbps kbps" }
    if ($minSizeBytes -gt 0) { Write-Host "  大小过滤：>= $MinSizeMB MB" }
    if ($ReSortBy) { Write-Host "  二次排序：按 $ReSortBy 降序（默认降序）" -ForegroundColor Cyan }
Write-Host ("  输出条数：" + $(if ($Top -le 0) { "全部" } else { $topCount }))
    Write-Host

    $scanBlackList = @()
    $blacklistFile = Join-Path $scanRoot "blacklist.txt"
    if (Test-Path -LiteralPath $blacklistFile) {
        $scanBlackList = Get-Content -LiteralPath $blacklistFile -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" -and $_ -notmatch '^#' }
        Write-Host "  >> 已加载黑名单：$($scanBlackList -join ' | ')"
    }

    $accessDeniedDirs = @(); $scanErrors = @()

    Write-Host "  正在扫描文件（阶段1/2）..." -ForegroundColor DarkCyan
    $totalPhase1 = 100; $totalPhase2 = 100
    Show-LinearProgressBar -Current 0 -Total $totalPhase1 -Status "初始化扫描..."
    Start-Sleep -Milliseconds 100

    $rawAll = Get-AllFilteredFiles -Path $scanRoot -DoRecurse $recurseParam -BlackList $scanBlackList -OutAccessDeniedDirs ([ref]$accessDeniedDirs) -OutScanErrors ([ref]$scanErrors) -ShowProgress
    Show-LinearProgressBar -Current $totalPhase1 -Total $totalPhase1 -Status "文件收集完成，共 $($rawAll.Count) 个文件"
    Write-Host

    $videoExts = @('.mp4','.mov','.mkv','.avi','.flv','.wmv','.m4v','.ts','.mpg','.mpeg','.f4v','.m2ts','.mts','.webm','.rmvb')
    if ($videoMode) { $rawFiles = $rawAll | Where-Object { $_.Extension -in $videoExts } } else { $rawFiles = $rawAll }
    if ($rawFiles.Count -eq 0) { Write-Host "  无匹配文件"; exit 0 }

    $totalVideoCount = $rawFiles.Count
    Write-Host "  扫描到 $totalVideoCount 个视频文件，开始处理..." -ForegroundColor Green

    # >>> FIX v21: 初始化漏斗计数变量
    $heightFilteredCount = 0
    $sizeTopFilteredCount = 0
    $bitrateFilteredCount = 0
    $sizeFilteredCount = 0
    $workListCountBeforeHeight = 0
    $workListCountBeforeSizeTop = 0
    $workListCountBeforeBitrate = 0
    $workListCountBeforeSizeFilter = 0

    $workList = @(); $metaFail = 0; $durMap = @{}
    $metaHasDuration = $exportMeta
    
    if ($videoMode -and $exportMeta) {
        Write-Host "  【读取视频元数据（阶段2/2）】" -ForegroundColor Cyan
        $tempDir = Join-Path $env:TEMP "video_meta_$(Get-Random)"
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        $taskList = @()
        foreach ($f in $rawFiles) {
            # v3.10：只统计本次脚本自己拉起、且尚未退出的 ffprobe，避免被外部转码进程拖住
            while (@($taskList | Where-Object { -not $_.Proc.HasExited }).Count -ge $maxConcurrent) { Start-Sleep -Milliseconds 40 }
            $outPath = Join-Path $tempDir "$($f.BaseName)_$($f.LastWriteTime.Ticks).txt"
            $extraArgs = '-v error -select_streams v:0 -show_entries stream=bit_rate,avg_bit_rate,width,height:format=duration -of json'
            $args2 = Get-FfprobeArgs -FilePath $f.FullName -ExtraArgs $extraArgs
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "ffprobe.exe"; $psi.Arguments = $args2
            $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
            $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $proc = [System.Diagnostics.Process]::Start($psi)
            $taskList += [PSCustomObject]@{ File=$f; Proc=$proc; OutFile=$outPath }
        }
        $processedCount = 0; $lastPct = -1
        while ($taskList.Count -gt 0) {
            $running = @()
            foreach ($t in $taskList) {
                if (-not $t.Proc.HasExited) { $running += $t; continue }
                $processedCount++
                $phase2Pct = [int]($processedCount / $totalVideoCount * 100)
                $pctVal = $phase2Pct
                if ($pctVal -ne $lastPct -or $processedCount -eq $totalVideoCount) {
                    Show-LinearProgressBar -Current $phase2Pct -Total 100 -Status "元数据读取: $processedCount/$totalVideoCount | $($t.File.Name)"
                    $lastPct = $pctVal
                }
                $vi = [PSCustomObject]@{BitrateKbps=$null;BitrateSource=$null;Width=$null;Height=$null;LongEdge=$null;DurationSec=$null;DurationDisp="-"}
                if ($t.Proc.ExitCode -eq 0) {
                    try {
                        $rawTxt = $t.Proc.StandardOutput.ReadToEnd()
                        if (-not $rawTxt) { $rawTxt = [System.IO.File]::ReadAllText($t.OutFile) }
                        $jsonObj = $rawTxt | ConvertFrom-Json
                        $vStream = $jsonObj.streams[0]
                        $w=[int]$vStream.width; $h=[int]$vStream.height
                        $bitrateBps = $null; $bitrateSource = "bitrate"
                        if (-not [string]::IsNullOrWhiteSpace($vStream.bit_rate)) { $bitrateBps = [long]$vStream.bit_rate }
                        elseif (-not [string]::IsNullOrWhiteSpace($vStream.avg_bit_rate)) { $bitrateBps = [long]$vStream.avg_bit_rate; $bitrateSource = "avgbitrate" }
                        $durSec = 0.0; $durDisp = "-"
                        if ($jsonObj.format -and $jsonObj.format.duration) {
                            $tmp = 0.0
                            if ([double]::TryParse($jsonObj.format.duration, [ref]$tmp)) {
                                $durSec = $tmp; $durDisp = (Get-FriendlyDuration $durSec)
                            }
                        }
                        $vi = [PSCustomObject]@{
                            BitrateKbps=if($bitrateBps){[Math]::Round($bitrateBps/1000)}else{$null}
                            BitrateSource=$bitrateSource; Width=$w; Height=$h; LongEdge=[Math]::Max($w,$h)
                            DurationSec=$durSec; DurationDisp=$durDisp
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
                    DurationSec=$vi.DurationSec; DurationDisp=$vi.DurationDisp
                }
            }
            $taskList = $running; Start-Sleep -Milliseconds 20
        }
        Show-LinearProgressBar -Current 100 -Total 100 -Status "元数据读取完成！"
        Write-Host
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        foreach ($f in $rawFiles) {
            $workList += [PSCustomObject]@{
                FullPath=$f.FullName.Trim(); FileSizeBytes=$f.Length; FileSizeFriendly=(Get-FriendlySize -Bytes $f.Length)
                BitrateKbps=$null; BitrateDisp="-"; Width=$null; Height=$null; ResDisp="-"; LongEdge=$null; DurationSec=$null; DurationDisp="-"
            }
        }
    }

    # ===== v3.3：导出全量数据集（-DumpAll）=====
    #   导出"本次扫描到的全部视频"，不做任何筛选与截断；
    #   列名与 nfo_export 的 CSV 对齐，可直接作为 -CsvSource 的数据源。
    if ($DumpAll -and $workList.Count -gt 0) {
        $dumpTs = Get-Date -Format "yyyyMMdd_HHmmss"
        $dumpName = "top_finder_全量数据集_$dumpTs.csv"
        $dumpRows = @()
        foreach ($wi in $workList) {
            $dumpRows += [PSCustomObject]@{
                '文件名'       = [System.IO.Path]::GetFileName($wi.FullPath)
                '文件大小_MB'  = [math]::Round($wi.FileSizeBytes / 1MB, 2)
                '时长'         = $wi.DurationDisp
                '时长_秒'      = $wi.DurationSec
                '总码率_kbps'  = $wi.BitrateKbps
                '宽'           = $wi.Width
                '高'           = $wi.Height
                '分辨率'       = $wi.ResDisp
                '视频文件路径' = $wi.FullPath
            }
        }
        $dumpPath = Join-Path $scanRoot $dumpName
        try {
            $dumpRows | Export-Csv -LiteralPath $dumpPath -NoTypeInformation -Encoding UTF8
            Write-Host "`n  ✅ 全量数据集已导出（$($dumpRows.Count) 条）：$dumpPath" -ForegroundColor Green
        } catch {
            Write-Host "`n  ❌ 全量数据集导出失败：$($_.Exception.Message)" -ForegroundColor Red
        }
    }

    # >>> FIX v21: 体积初筛计数
    $workListCountBeforeSizeTop = $workList.Count
    if ($SizeTop) {
        $sizeTopCount = [Math]::Max(1, $SizeTopCount)
        $workList = @($workList | Sort-Object FileSizeBytes -Descending | Select-Object -First $sizeTopCount)
        $sizeTopFilteredCount = $workListCountBeforeSizeTop - $workList.Count
    }

    # >>> FIX v21: 高度过滤计数
    $workListCountBeforeHeight = $workList.Count
    if ($MinHeight -gt 0 -or $MaxHeight -gt 0) {
        if ($MinHeight -gt 0) { $workList = @($workList | Where-Object { $_.Height -ge $MinHeight }) }
        if ($MaxHeight -gt 0) { $workList = @($workList | Where-Object { $_.Height -le $MaxHeight }) }
        $heightFilteredCount = $workListCountBeforeHeight - $workList.Count
    }

    # ---- 主排序 ----
    if ($sortMode -eq "B") {
        $sortedAll = @($workList | Sort-Object @{E={if($_.BitrateKbps -eq $null){-1}else{$_.BitrateKbps}};D=$true}, @{E={$_.FileSizeBytes};D=$true})
        # >>> FIX v21: 码率过滤计数
        $workListCountBeforeBitrate = $sortedAll.Count
        if ($useBitrateFilter) { $sorted = @($sortedAll | Where-Object { $_.BitrateKbps -ge $bitrateThresholdKbps }) }
        else { $sorted = @($sortedAll) }
        # v3.3：先算过滤损失，再统一截 Top（原逻辑过滤分支完全跳过 -Top）
        $bitrateFilteredCount = $workListCountBeforeBitrate - $sorted.Count
        $preTopCount = $sorted.Count
        $sorted = @($sorted | Select-Object -First $topCount)
    } elseif ($sortMode -eq "R") {
        $preTopCount = $workList.Count
        $sorted = @($workList | Sort-Object @{E={if($_.LongEdge -eq $null){-1}else{$_.LongEdge}};D=$true}, @{E={$_.FileSizeBytes};D=$true} | Select-Object -First $topCount)
    } elseif ($sortMode -eq "D") {
        # v3.3：v16 起时长已在元数据阶段统一获取，此处不再二次扫描
        #       （原逻辑会为每个文件多跑一次 ffprobe，等于双倍耗时）
        $preTopCount = $workList.Count
        $sorted = @($workList | Sort-Object @{E={if($_.DurationSec -ne $null){$_.DurationSec}else{-1}};D=$true}, @{E={$_.FileSizeBytes};D=$true} | Select-Object -First $topCount)
    } else {
        $sortedAll = @($workList | Sort-Object FileSizeBytes -Descending)
        # v3.3：码率过滤只在真正启用时计数，Top 截断不再冒充"码率过滤"
        $workListCountBeforeBitrate = $sortedAll.Count
        if ($useBitrateFilter) { $sortedAll = @($sortedAll | Where-Object { $_.BitrateKbps -ne $null -and $_.BitrateKbps -ge $bitrateThresholdKbps }) }
        $bitrateFilteredCount = $workListCountBeforeBitrate - $sortedAll.Count
        $preTopCount = $sortedAll.Count
        $sorted = @($sortedAll | Select-Object -First $topCount)
    }
    $sorted = @($sorted)

    # v3.3：截断提示（-Top 生效且确有截断时）
    if ($preTopCount -gt $sorted.Count) {
        Write-Host "  >> 提示：符合条件共 $preTopCount 条，已按 -Top $Top 截断输出前 $($sorted.Count) 条（-Top 0 = 全部）" -ForegroundColor Yellow
    }

    # v3.3：结果为空时输出漏斗诊断，定位是哪一层筛选把结果筛没了
    if ($sorted.Count -eq 0) {
        Write-Host
        Write-Host "  ==================== 空结果诊断 ====================" -ForegroundColor Red
        Write-Host ("  总扫描视频      : {0}" -f $totalVideoCount)
        if ($heightFilteredCount -gt 0)  { Write-Host ("  高度筛选排除    : {0}  （MinHeight={1} / MaxHeight={2}）" -f $heightFilteredCount, $MinHeight, $MaxHeight) }
        if ($sizeTopFilteredCount -gt 0) { Write-Host ("  体积初筛排除    : {0}  （SizeTopCount={1}）" -f $sizeTopFilteredCount, $SizeTopCount) }
        if ($bitrateFilteredCount -gt 0) { Write-Host ("  码率过滤排除    : {0}  （MinBitrate={1}）" -f $bitrateFilteredCount, $bitrateThresholdKbps) }
        if ($sizeFilteredCount -gt 0)    { Write-Host ("  大小过滤排除    : {0}  （MinSizeMB={1}）" -f $sizeFilteredCount, $MinSizeMB) }
        Write-Host "  建议：逐项放宽上面的阈值；-SizeTop 只取前几十个时，很容易把后续筛选饿死"
        Write-Host "  ====================================================" -ForegroundColor Red
    }

    # >>> FIX v20: 二次排序（主排序完成后、大小过滤前）
    if ($ReSortBy -and $ReSortBy.ToUpper() -in @("D","S","B","R")) {
        $rsMode = $ReSortBy.ToUpper()
        Write-Host "  >> 二次排序：按 $rsMode 降序重新排列结果集（共 $($sorted.Count) 条）" -ForegroundColor Cyan
        switch ($rsMode) {
            "D" { $sorted = @($sorted | Sort-Object @{E={if($_.DurationSec -ne $null){$_.DurationSec}else{[double]::MaxValue}};D=$true}) }
            "S" { $sorted = @($sorted | Sort-Object @{E={$_.FileSizeBytes};D=$true}) }
            "B" { $sorted = @($sorted | Sort-Object @{E={if($_.BitrateKbps -eq $null){-1}else{$_.BitrateKbps}};D=$true}) }
            "R" { $sorted = @($sorted | Sort-Object @{E={if($_.LongEdge -eq $null){-1}else{$_.LongEdge}};D=$true}) }
        }
    }

    # >>> FIX v19: 最终大小过滤（带计数）
    $workListCountBeforeSizeFilter = $sorted.Count
    if ($minSizeBytes -gt 0) {
        $beforeFilter = $sorted.Count
        $sorted = @($sorted | Where-Object { $_.FileSizeBytes -ge $minSizeBytes })
        $sizeFilteredCount = $beforeFilter - $sorted.Count
        if ($sizeFilteredCount -gt 0) {
            Write-Host "  >> 按大小过滤：排除 $sizeFilteredCount 个小于 $MinSizeMB MB 的文件，剩余 $($sorted.Count) 个" -ForegroundColor Yellow
        }
    }

    # ---- 输出到控制台 ----
    $outputRows = @()
    foreach($item in $sorted){
        $outputRows += [PSCustomObject]@{
            Rank = ($outputRows.Count + 1)
            Duration = $item.DurationDisp; Size = $item.FileSizeFriendly
            Bitrate = $item.BitrateDisp; Resolution = $item.ResDisp; Path = $item.FullPath
        }
    }
    $outputRows = @($outputRows)

    if ($JsonOutput -or $Output -ne "") {
        $jsonText = $outputRows | ConvertTo-Json -Depth 3
        if ($Output -ne "") { $jsonText | Out-File -LiteralPath $Output -Encoding UTF8; Write-Host "  已保存：$Output" }
        else { Write-Host $jsonText }
    } else {
        Write-Host "`n  ==================== 结果 ===================="
        $showDuration = $videoMode -and $exportMeta
        foreach($r in $outputRows) {
            if ($showDuration) {
                $dispDur = $r.Duration
                if ($dispDur -eq $null) { $dispDur = "-" }
                Write-Host ("  [{0,3}] {1,-12} | {2,-10} | {3,-16} | {4,-12} | {5}" -f $r.Rank,$dispDur,$r.Size,$r.Bitrate,$r.Resolution,$r.Path)
            } else {
                Write-Host ("  [{0,3}] {1,-10} {2}" -f $r.Rank,$r.Size,$r.Path)
            }
        }
        Write-Host "  ==============================================="
        Write-Host "  共 $($outputRows.Count) 条结果"
    }

    # ========= 非交互模式：自动保存 txt =========
    if ($UserQuery -and $UserQuery.Trim() -ne "") {
        $fnRaw = $UserQuery.Trim() -replace '[<>:"/\\|?*]','_' -replace '_+','_' -replace '^\s+|\s+$',''
    } else {
        $fnRaw = "视频筛选结果"
    }
    if ($fnRaw.Length -gt 80) { $fnRaw = $fnRaw.Substring(0, 80) }
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $outName = "本文件夹内文件筛选&排序统计_非交互模式_${fnRaw}_${ts}.txt"
    $lines = @()
    $lines += "非交互模式筛选结果"
    $lines += "查询：$($UserQuery.Trim())"
    $lines += "参数：Mode=$sortMode Recurse=$recurseParam Meta=$exportMeta BitrateThreshold=$bitrateThresholdKbps MinHeight=$MinHeight MaxHeight=$MaxHeight MinSizeMB=$MinSizeMB ReSortBy=$ReSortBy"
    $displayRoot = $scanRoot -replace '^Microsoft\.PowerShell\.Core\\FileSystem::',''
    $lines += "扫描根目录: $displayRoot"
    $lines += "时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += "# ===== 筛选漏斗统计（按执行顺序）====="
    $lines += "#总扫描视频数量: $totalVideoCount"
    if ($heightFilteredCount -gt 0) { $lines += "#高度过滤: 排除 $heightFilteredCount 个（范围 ${MinHeight}-${MaxHeight}P），剩余 $($totalVideoCount - $heightFilteredCount)" }
    if ($sizeTopFilteredCount -gt 0) { $lines += "#体积初筛: 排除 $sizeTopFilteredCount 个（取前 $SizeTopCount 按大小），剩余 $($workListCountBeforeHeight - $heightFilteredCount)" }
    if ($bitrateFilteredCount -gt 0) { $lines += "#码率过滤: 排除 $bitrateFilteredCount 个（>= ${bitrateThresholdKbps}kbps），剩余 $($workListCountBeforeHeight - $heightFilteredCount - $bitrateFilteredCount)" }
    if ($ReSortBy) { $lines += "#二次排序: 按 $ReSortBy 降序重排（不拦截）" }
    if ($sizeFilteredCount -gt 0) { $lines += "#大小过滤: 排除 $sizeFilteredCount 个（>= ${MinSizeMB}MB），剩余 $($sorted.Length)" }
    $lines += "#最终输出数量: $($sorted.Length)"
    $lines += "# ===== 筛选漏斗统计结束 ====="
    $hasDurationCol = ($videoMode -and $exportMeta)
    if ($hasDurationCol) {
        $lines += ("{0,-4}|{1,-12}|{2,-10}|{3,-16}|{4,-12}|{5}" -f "序号","时长","大小","码率","分辨率","完整路径")
        $lines += "--------------------------------------------------"
        for($i=0; $i -lt $sorted.Length; $i++){
            $item = $sorted[$i]
            $lines += ("[{0,-3}]|{1,-12}|{2,-10}|{3,-16}|{4,-12}|{5}" -f ($i+1),$item.DurationDisp,$item.FileSizeFriendly,$item.BitrateDisp,$item.ResDisp,$item.FullPath)
        }
    } else {
        $lines += ("{0,-4}|{1,-10}|{2}" -f "序号","大小","完整路径")
        $lines += "--------------------------------------------------"
        for($i=0; $i -lt $sorted.Length; $i++){
            $item = $sorted[$i]
            $lines += ("[{0,-3}]|{1,-10}|{2}" -f ($i+1),$item.FileSizeFriendly,$item.FullPath)
        }
    }
    $txtContent = $lines -join "`r`n"
    try {
        $txtContent | Out-File -LiteralPath $outName -Encoding UTF8
        Write-Host "`n  ✅ 已自动保存：$PWD\$outName" -ForegroundColor Green
    } catch {
        Write-Host "`n  ❌ 保存失败：$($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host "`n  非交互模式执行完毕。"
    exit 0
}

# ====================== 交互模式 ======================

# ---- UI 框架（v3.2）：只在交互模式加载，非交互模式保持原样不受影响 ----
. (Join-Path $PSScriptRoot "ui\ui.ps1")

# ---- v3.7：竖向菜单统一封装 ----
#   Arrow-Menu 返回索引，Esc/q 抛 OperationCanceledException；
#   此处统一转换为 -1，并自动生成底部提示行。
function Select-Vertical {
    param(
        [string[]]$Labels,
        [int]$Default = 0,
        [string]$Title = "",
        [string]$Note = ""
    )

    # v7.0：标题与分隔线由菜单自身打印，并作为 Header 传给 Arrow-Menu，
    #       这样窗口缩放触发的清屏重绘能把标题一并恢复。
    $header = @()
    if ($Title -ne "") {
        # v7.1：标题块自带一行空行（空行 + 标题 + 说明 + 分隔线），
        #       缩放重绘时一并恢复，保证初始与重绘的版式完全一致。
        Write-Host
        $header += ""
        Write-Host "  $(col_a_title $Title)"
        $header += "  $(col_a_title $Title)"
        if ($Note -ne "") {
            Write-Host "  $(col_a_text_muted $Note)"
            $header += "  $(col_a_text_muted $Note)"
        }
        Write-Host "  $(col_a_line (sep))"
        $header += "  $(col_a_line (sep))"
    }
    $allNum = $true; $allAlpha = $true
    foreach ($lbl in $Labels) {
        if ($lbl -notmatch '^\[\d+\]') { $allNum = $false }
        if ($lbl -notmatch '^\[[a-zA-Z]\]') { $allAlpha = $false }
    }
    $hint = if ($allNum) { "[1-$($Labels.Count)]直达" }
            elseif ($allAlpha) { "[字母]直达" }
            else { "[数字/字母]直达" }
    $footer = "  [↑↓]移动  $hint  [Enter]确认  [q/Esc]退出"
    try {
        return (Arrow-Menu -Options $Labels -DefaultIndex $Default -Footer1 $footer -Header $header)
    } catch [System.OperationCanceledException] {
        return -1
    }
}

# v3.12：q/Esc = 返回本脚本开头（本层循环）；唯有第一屏 CSV 检测菜单的 q 才真正退出
#   （从 tt 进入时即返回 tt 主菜单）。
#   每次回到开头都彻底清屏（Clear-Screen，含清滚动缓冲），不保留上一轮的任何屏显。
:RESTART while ($true) {
    # 每轮重置跨轮变量，避免「返回开头」后累积上一轮数据
    $taskList = @()
Clear-Screen
Write-Host
$cwdDisplay = $PWD.ProviderPath
if ($cwdDisplay.Length -gt 78) {
    $cwdDisplay = $cwdDisplay.Substring(0, 38) + '…' + $cwdDisplay.Substring($cwdDisplay.Length - 38)
}

Write-Host "  $(col_a_title ('top_finder.ps1 — TOP XX 文件筛选与统计'))"
Write-Host "  $(col_a_line (sep))"
Write-Host
Write-Host "  $(col_a_text_muted '处理目录：')$(col_a_text $cwdDisplay)"
Write-Host
Write-Host "  $(col_a_text_muted '按 大小 / 码率 / 分辨率 / 时长 四个维度排序')"
Write-Host "  $(col_a_text_muted '支持多层漏斗筛选：高度 / 体积 / 码率 / 大小')"
Write-Host "  $(col_a_text_muted '数据源可用 nfo_export CSV，或直接扫描真实文件')"

# >>> v22.0 CSV检测与子菜单
$csvInjectedWorkList = @()
$useCsvAsSource = $false
$skipRecurseAndFormat = $false
$global:backToMainMenu = $false
$global:csvRawData = $null
$selectedCsv = $null

$allCsvFiles = @(Get-ChildItem -LiteralPath ($PWD.Path) -Filter "nfo_export_*.csv" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike "nfo_export_onlynfo_*" } | Sort-Object LastWriteTime -Descending)
if ($allCsvFiles.Count -gt 0) {
    # v3.6：改为竖向 Arrow-Menu。
    #   文件名长度固定且较长，横向排布在备选多时必然折行；
    #   Select-Horizontal 用 \r 回行首重绘，折行后会残留重复行（实测会刷十几行）。
    Write-Host

    $csvLabels = @()
    for ($ci = 0; $ci -lt $allCsvFiles.Count; $ci++) {
        $tag = if ($ci -eq 0) { '  ← 最新' } else { '' }
        $csvLabels += ("[$($ci+1)] " + $allCsvFiles[$ci].Name + $tag)
    }
    $csvLabels += '[n] 跳过 CSV，直接扫描真实文件'

    $csvPick = Select-Vertical -Labels $csvLabels -Default 0 -Title '检测到文件夹内有以下 CSV 文件：'
    if ($csvPick -lt 0) { exit 0 }

    if ($csvPick -lt $allCsvFiles.Count) {
        $selectedCsv = $allCsvFiles[$csvPick]
        $useCsvAsSource = $true
        $skipCsvMenu = $false
        # Write-Host "  $(col_a_success ('已选择：' + $selectedCsv.Name))"
        $global:csvRawData = Import-Csv -LiteralPath $selectedCsv.FullName
    }
    elseif ($csvPick -eq $allCsvFiles.Count) {
        # Write-Host "  $(col_a_text '⏭️ 跳过 CSV，将直接扫描真实文件')"
        $useCsvAsSource = $false
        $skipCsvMenu = $true
    }
    else {
        exit 0
    }

    # v2.8.6：选N时跳过整个CSV分析菜单，直接走真实扫描
    if (-not $skipCsvMenu) {
        while ($true) {
            Write-Host
            $csvMenuLabels = @(
                '[1] 孤立 NFO 检查（无同名视频）'
                '[2] NFO 内部名称不一致检查'
                '[3] 按 CSV 筛选排序（注入列表，跳过扫描）'
                '[4] 忽略 CSV，真实扫描文件夹'
            )
            $csvMenuPick = Select-Vertical -Labels $csvMenuLabels -Default 0 -Title 'CSV 分析菜单'
            if ($csvMenuPick -lt 0) { continue RESTART }
            $csvMenuValues = @(
                '1'
                '2'
                '3'
                '4'
            )
            $csvMenuResult = $csvMenuValues[$csvMenuPick]
            if ($null -eq $csvMenuResult) { continue RESTART }
            $csvMenu = $csvMenuResult

            switch ($csvMenu) {
                "1" {
                    # 孤立NFO检查
                    $count = 0
                    $orphanNfoPaths = @()
                    foreach ($r in $global:csvRawData) {
                        $vp = $r."视频文件路径"
                        if ([string]::IsNullOrWhiteSpace($vp) -or $vp -eq "(未找到同名视频)") {
                            $count++
                            $orphanNfoPaths += $r.'NFO路径'
                            Write-Host (col_a_warning "  孤儿NFO: $($r.'NFO路径')")
                        }
                    }
                    Write-Host (col_a_text "  孤立NFO总数: $count")

                    # >>> v22.1 预览+自动输出TXT+清理交互
                    if ($count -gt 0) {
                        # 屏幕预览最多10行
                        Write-Host
                        $previewMax = [Math]::Min(10, $orphanNfoPaths.Count)
                        for ($pi = 0; $pi -lt $previewMax; $pi++) {
                            Write-Host (col_c_dark_yellow ("  {0}. {1}" -f ($pi + 1), $orphanNfoPaths[$pi]))
                        }
                        if ($orphanNfoPaths.Count -gt 10) {
                            Write-Host (col_a_text_gray ("  … 还有 $($orphanNfoPaths.Count - 10) 个未显示"))
                        }

                        # 强制输出TXT到CSV所在目录（即当前目录）
                        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
                        $orphanTxt = Join-Path ($PWD.Path) "孤立NFO列表_${ts}.txt"
                        $orphanNfoPaths | Out-File $orphanTxt -Encoding UTF8
                        Write-Host (col_a_text "`n  已输出孤立NFO路径列表至: $orphanTxt")

                        # 一键清理交互（v3.4：改横向菜单，默认不清理）
                        Write-Host
                        $cleanLabels = @(
                            '[n]不清理（推荐，按 TXT 自行复核）'
                            '[y]删除这些孤立 NFO（不可撤销）'
                        )
                        $cleanPick = Select-Vertical -Labels $cleanLabels -Default 0 -Title '孤立 NFO 清理' -Note '可能存在误报，建议先按 TXT 自行复核'
                        if ($cleanPick -lt 0) { continue RESTART }
                        $cleanValues = @(
                            'no'
                            'yes'
                        )
                        $cleanResult = $cleanValues[$cleanPick]
                        if ($null -eq $cleanResult -or $cleanResult -eq 'quit') { continue RESTART }
                        if ($cleanResult -eq 'yes') {
                            $deleted = 0
                            foreach ($p in $orphanNfoPaths) {
                                try { Remove-Item -LiteralPath $p -Force; $deleted++ }
                                catch { Write-Host (col_a_error "  ❌ 删除失败: $p") }
                            }
                            Write-Host (col_a_success "  已清理 $deleted 个孤立NFO。")

                            # >>> v22.6 同步从内存CSV数据中移除已删行
                            $remainingRows = @()
                            foreach ($row in $global:csvRawData) {
                                $nfoPath = $row.'NFO路径'
                                if ($nfoPath -and $orphanNfoPaths -contains $nfoPath) {
                                    continue
                                }
                                $remainingRows += $row
                            }
                            $global:csvRawData = $remainingRows
                            Write-Host (col_a_text_gray "  已同步清理内存CSV数据中的对应行。")

                            # >>> v22.6 回写新CSV（原CSV不动，改用Export-Csv避免路径/编码坑）
                            $newCsvName = "nfo_export_cleaned_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
                            # 强制解析为文件系统绝对路径，避免.NET路径格式异常
                            $absDir = (Get-Item -LiteralPath $PWD.Path).FullName
                            $newCsvPath = Join-Path $absDir $newCsvName
                            try {
                                $global:csvRawData | Export-Csv -LiteralPath $newCsvPath -NoTypeInformation -Encoding UTF8 -Force
                                Write-Host (col_a_success "  已生成清理后的CSV: $newCsvPath")
                            } catch {
                                Write-Host (col_a_error "  ❌ 新CSV生成失败: $($_.Exception.Message)")
                            }
                        } else {
                            Write-Host (col_a_text_muted "  未清理，请根据TXT自行复核删除（注意误报风险）。")
                        }
                    }

                    Wait-AnyKey "`n  $(col_a_text_muted '按任意键返回CSV分析菜单...')"
                    continue
                }
                "2" {
                    # NFO内部名称不一致检查
                    $count = 0
                    $inconsistentPaths = @()
                    foreach ($r in $global:csvRawData) {
                        # v3.1：当前 nfo_export 输出「NFO内文件名校验」（一致 / （不一致）），
                        # 旧列 HasVideo / Consistent 已不存在，原逻辑恒为 0 条。
                        $check = $r.'NFO内文件名校验'
                        $hasVid = $r.'HasVideo'
                        $consistentOld = $r.'Consistent'
                        $isBad = $false
                        if (-not [string]::IsNullOrWhiteSpace($check) -and $check -ne '一致') { $isBad = $true }
                        if ($hasVid -eq 'False' -or $consistentOld -eq 'False') { $isBad = $true }
                        if ($isBad) {
                            $count++
                            $inconsistentPaths += $r.'NFO路径'
                            Write-Host (col_a_warning "  NFO内部名称不一致: $($r.'NFO路径') (校验=$check)")
                        }
                    }
                    Write-Host (col_a_text "  NFO内部名称不一致总数: $count")

                    # >>> v22.2 不一致列表预览+自动输出TXT
                    if ($count -gt 0) {
                        Write-Host
                        $previewMax = [Math]::Min(10, $inconsistentPaths.Count)
                        for ($pi = 0; $pi -lt $previewMax; $pi++) {
                            Write-Host (col_c_dark_yellow ("  {0}. {1}" -f ($pi + 1), $inconsistentPaths[$pi]))
                        }
                        if ($inconsistentPaths.Count -gt 10) {
                            Write-Host (col_a_text_gray ("  … 还有 $($inconsistentPaths.Count - 10) 个未显示"))
                        }

                        $ts = Get-Date -Format "yyyyMMdd_HHmmss"
                        $incTxt = Join-Path ($PWD.Path) "不一致NFO列表_${ts}.txt"
                        $inconsistentPaths | Out-File $incTxt -Encoding UTF8
                        Write-Host (col_a_text "`n  已输出不一致NFO路径列表至: $incTxt")
                    }

                    Wait-AnyKey "`n  $(col_a_text_muted '按任意键返回CSV分析菜单...')"
                    continue
                }

                "3" {
                    # 按CSV筛选排序 - 构建workList
                    $csvInjectedWorkList = @()
                    $onlyNfoSkipped = 0
                    foreach ($r in $global:csvRawData) {
                        $vPath = $r."视频文件路径"
                        # onlynfo跳过：无真实视频路径
                        if ([string]::IsNullOrWhiteSpace($vPath) -or $vPath -eq "(未找到同名视频)") {
                            $onlyNfoSkipped++
                            continue
                        }
                        # 文件大小：从CSV字段映射（MB → bytes）
                        $sz = 0
                        $mb = 0.0
                        if ([double]::TryParse($r."文件大小_MB", [ref]$mb)) {
                            $sz = [int64]($mb * 1048576)
                        }
                        $szF = if ($sz -gt 0) { (Get-FriendlySize -Bytes $sz) } else { "-" }
                        # 码率
                        $b = 0; $bit = $null
                        if ([int]::TryParse($r."总码率_kbps", [ref]$b)) { $bit = $b }
                        # 分辨率：优先读独立的 宽/高 列（更早的 CSV），
                        # 否则从「分辨率」列解析，格式如 1920x1080 / 1080x1920（竖屏）
                        # v3.1：旧版只读 宽/高，而 nfo_export 只输出「分辨率」一列，
                        #       导致 LongEdge 恒为 $null，R 模式排序完全失效。
                        $wid = $null; $hei = $null
                        $tmpInt = 0
                        if ([int]::TryParse($r."宽", [ref]$tmpInt)) { $wid = $tmpInt }
                        if ([int]::TryParse($r."高", [ref]$tmpInt)) { $hei = $tmpInt }
                        if (-not $wid -or -not $hei) {
                            $resCol = $r.'分辨率'
                            if ($resCol -match '(\d+)\s*[xX×]\s*(\d+)') {
                                $wid = [int]$Matches[1]
                                $hei = [int]$Matches[2]
                            }
                        }
                        $res = "-"; $long = $null
                        if ($wid -and $hei) { $res = "${wid}x${hei}"; $long = [Math]::Max($wid, $hei) }
                        # 时长
                        $durSec = $null; $durTxt = "-"
                        $ds = 0.0
                        if ([double]::TryParse($r."时长_秒", [ref]$ds)) { $durSec = $ds; $durTxt = (Get-FriendlyDuration $ds) }
                        # 注入
                        $csvInjectedWorkList += [PSCustomObject]@{
                            FullPath        = $vPath.Trim()
                            FileSizeBytes   = $sz
                            FileSizeFriendly = $szF
                            BitrateKbps     = $bit
                            BitrateDisp     = if ($bit) { "${bit}kbps" } else { "-" }
                            Width           = $wid
                            Height          = $hei
                            ResDisp         = $res
                            LongEdge        = $long
                            DurationSec     = $durSec
                            DurationDisp    = $durTxt
                        }
                    }
                    $totalVideoCount = $csvInjectedWorkList.Count
                    Write-Host (col_a_text "  有效视频条目=$totalVideoCount，跳过onlynfo/无效行=$onlyNfoSkipped，将跳至排序维度...")
                    $useCsvAsSource = $true
                    $exportMeta = $true; $videoMode = $true; $metaHasDuration = $true
                    $scanRoot = $PWD.Path.Trim()
                    $skipRecurseAndFormat = $true
                    break
                }
                "4" {
                    # 忽略CSV，走完整扫描
                    Write-Host (col_a_text "  忽略CSV，执行完整文件夹扫描...")
                    break
                }
                "Q" {
                    # 返回主菜单
                    $global:backToMainMenu = $true
                    break
                }
                default {
                    Write-Host (col_a_error "  无效选项，请重新选择")
                    continue
                }
            }
            # Q选项触发exit
            if ($global:backToMainMenu) { continue RESTART }
            # 菜单3/4 break出来后继续主流程
            if ($csvMenu -eq "3" -or $csvMenu -eq "4") { break }
        }
    }
    # 选N跳过菜单后，确保走真实扫描
    if ($skipCsvMenu) {
        # Write-Host (col_a_text "  将执行完整文件夹扫描...")
    }
}

# v3.1：移除「终止本机所有 ffprobe」功能。
#   原逻辑会 Stop-Process 掉机器上所有 ffprobe，包括用户正在跑的
#   格式工厂 / QuickSync 转码任务，风险远大于收益。
#   本脚本自身的 ffprobe 由并发限流控制，不需要外部清理。
$runningFfprobe = Get-Process -Name "ffprobe" -ErrorAction SilentlyContinue
if ($runningFfprobe -and $runningFfprobe.Count -gt 0) {
    Write-Host (col_a_text_gray "`n  提示：本机有 $($runningFfprobe.Count) 个 ffprobe 进程（可能是转码任务），本脚本不会干预。")
}


$maxConcurrent = 4; $progressStep = 20
Write-Host
Write-Host
# Write-Host "  $(col_a_title '查找视频/文件列表（S大小｜B码率｜R分辨率｜D视频时长）')"
# Write-Host "  $(col_a_line (sep))"

if ($useCsvAsSource -and $selectedCsv) {
    Write-Host "  $(col_a_text_muted '数据来源：')$(col_a_text ('CSV 注入 — ' + $selectedCsv.Name))"
    Write-Host "  $(col_a_text_muted '（直接读取该 CSV，不扫描磁盘、不调用 ffprobe）')"
} else {
    Write-Host "  $(col_a_text_muted '数据来源：')$(col_a_text '本地真实扫描 — 逐个读取文件夹内文件')"
    Write-Host "  $(col_a_text_muted '（读取真实文件信息；选读取元数据时会调用 ffprobe）')"
}

if (-not $skipRecurseAndFormat) {
    Write-Host
    $recurseLabels = @(
        '[y]递归扫描子文件夹（推荐）'
        '[n]仅当前文件夹'
    )
    $recursePick = Select-Vertical -Labels $recurseLabels -Default 0 -Title '扫描范围'
    if ($recursePick -lt 0) { exit 0 }
    $recurseValues = @(
        'yes'
        'no'
    )
    $recurseResult = $recurseValues[$recursePick]
    if ($null -eq $recurseResult -or $recurseResult -eq 'quit') { continue RESTART }
    $recurseParam = ($recurseResult -eq 'yes')
} else {
    $recurseParam = $true
}

if (-not $skipRecurseAndFormat) {
    Write-Host
    $videoModeLabels = @(
        '[y]仅扫描视频文件（推荐）'
        '[n]扫描全部文件类型'
    )
    $videoModePick = Select-Vertical -Labels $videoModeLabels -Default 0 -Title '文件类型'
    if ($videoModePick -lt 0) { continue RESTART }
    $videoModeValues = @(
        'yes'
        'no'
    )
    $videoModeResult = $videoModeValues[$videoModePick]
    if ($null -eq $videoModeResult -or $videoModeResult -eq 'quit') { continue RESTART }
    $videoMode = ($videoModeResult -eq 'yes')
} else {
    $videoMode = $true
}

$videoExts = @('.mp4','.mov','.mkv','.avi','.flv','.wmv','.m4v','.ts','.mpg','.mpeg','.f4v','.m2ts','.mts','.webm','.rmvb')
$sortMode = "S"; $exportMeta = $false; $isDowngrade = $false

if ($videoMode) {
    Write-Host
    $sortLabels = @(
        '[S]文件大小（推荐）'
        '[B]视频流码率'
        '[R]视频长边分辨率'
        '[D]视频时长'
    )
    $sortPick = Select-Vertical -Labels $sortLabels -Default 0 -Title '排序维度'
    if ($sortPick -lt 0) { continue RESTART }
    $sortValues = @(
        'S'
        'B'
        'R'
        'D'
    )
    $sortResult = $sortValues[$sortPick]
    if ($null -eq $sortResult -or $sortResult -eq 'quit') { continue RESTART }
    $sortMode = $sortResult
    if ($sortMode -eq "S") {
        Write-Host
        $metaLabels = @(
            '[n]不读取元数据（推荐，最快）'
            '[y]读取元数据（含时长/码率/分辨率）'
        )
        $metaPick = Select-Vertical -Labels $metaLabels -Default 0 -Title '是否读取视频元数据' -Note '读取后可获得时长 / 码率 / 分辨率，但每集要多跑一次 ffprobe'
        if ($metaPick -lt 0) { continue RESTART }
        $metaValues = @(
            'no'
            'yes'
        )
        $metaResult = $metaValues[$metaPick]
        if ($null -eq $metaResult -or $metaResult -eq 'quit') { continue RESTART }
        if ($metaResult -eq 'yes') { $exportMeta = $true }
    }
    elseif ($sortMode -in "B","R","D") {
        $exportMeta = $true
        if (-not (Test-FfprobeAvailable)) {
            Write-Host
            $dgLabels = @(
                '[y]降级为按文件大小排序'
                '[n]退出'
            )
            $dgPick = Select-Vertical -Labels $dgLabels -Default 1 -Title '未找到 ffprobe.exe' -Note '可降级为按文件大小排序，或退出后先安装 ffprobe'
            if ($dgPick -lt 0) { continue RESTART }
            $dgValues = @(
                'yes'
                'no'
            )
            $dgResult = $dgValues[$dgPick]
            if ($null -eq $dgResult -or $dgResult -eq 'no') { continue RESTART }
            $sortMode = "S"; $exportMeta = $false; $isDowngrade = $true
        }
    }
}

$useBitrateFilter = $false; $bitrateThresholdKbps = 10000; $topCount = 100
if ($videoMode -and $sortMode -eq "B") {
    Write-Host
    $brLabels = @(
        '[n]指定输出条目数（推荐）'
        '[t]按码率阈值筛选'
    )
    $brPick = Select-Vertical -Labels $brLabels -Default 0 -Title '码率筛选方式'
    if ($brPick -lt 0) { continue RESTART }
    $brValues = @(
        'count'
        'threshold'
    )
    $brResult = $brValues[$brPick]
    if ($null -eq $brResult -or $brResult -eq 'quit') { continue RESTART }
    if ($brResult -eq "threshold") {
        $useBitrateFilter = $true
        $inputThr = Read-Host "  输入最低码率阈值(kbps)，直接回车默认10000"
        if ([string]::IsNullOrWhiteSpace($inputThr) -or (-not [int]::TryParse($inputThr, [ref]$null))) { $bitrateThresholdKbps = 10000 }
        else { $bitrateThresholdKbps = [int]$inputThr }
    } else {
        $inputCount = Read-Host "  指定最大的输出统计条目数，直接回车默认100"
        if ([string]::IsNullOrWhiteSpace($inputCount) -or (-not [int]::TryParse($inputCount, [ref]$null))) { $topCount = 100 }
        else { $topCount = [Math]::Max(1, [int]$inputCount) }
    }
} elseif ($videoMode -and $sortMode -eq "S" -and $exportMeta) {
    Write-Host
    $brLabels = @(
        '[n]不过滤码率（推荐）'
        '[t]按码率阈值筛选'
    )
    $brPick = Select-Vertical -Labels $brLabels -Default 0 -Title '是否按码率阈值筛选'
    if ($brPick -lt 0) { continue RESTART }
    $brValues = @(
        'none'
        'threshold'
    )
    $brResult = $brValues[$brPick]
    if ($null -eq $brResult -or $brResult -eq 'quit') { continue RESTART }
    if ($brResult -eq "threshold") {
        $useBitrateFilter = $true
        $inputThr = Read-Host "  输入最低码率阈值(kbps)，直接回车默认10000"
        if ([string]::IsNullOrWhiteSpace($inputThr) -or (-not [int]::TryParse($inputThr, [ref]$null))) { $bitrateThresholdKbps = 10000 }
        else { $bitrateThresholdKbps = [int]$inputThr }
    }
    $inputCount = Read-Host "  指定最大的输出统计条目数，直接回车默认100"
    if ([string]::IsNullOrWhiteSpace($inputCount) -or (-not [int]::TryParse($inputCount, [ref]$null))) { $topCount = 100 }
    else { $topCount = [Math]::Max(1, [int]$inputCount) }
} else {
    $inputCount = Read-Host "  指定最大的输出统计条目数，直接回车默认100"
    if ([string]::IsNullOrWhiteSpace($inputCount) -or (-not [int]::TryParse($inputCount, [ref]$null))) { $topCount = 100 }
    else { $topCount = [Math]::Max(1, [int]$inputCount) }
}

# >>> FIX v20: 交互模式 - 询问是否二次排序
$reSortBy = ""
if ($videoMode -and $exportMeta) {
    Write-Host
    $reSortLabels = @(
        '[n]不二次排序（推荐）'
        '[D]按时长'
        '[S]按文件大小'
        '[B]按码率'
        '[R]按分辨率'
    )
    $reSortPick = Select-Vertical -Labels $reSortLabels -Default 0 -Title '是否对结果集二次排序'
    if ($reSortPick -lt 0) { continue RESTART }
    $reSortValues = @(
        'none'
        'D'
        'S'
        'B'
        'R'
    )
    $reSortResult = $reSortValues[$reSortPick]
    if ($null -eq $reSortResult -or $reSortResult -eq 'quit') { continue RESTART }
    if ($reSortResult -in @("D","S","B","R")) { $reSortBy = $reSortResult }
}

if ($videoMode) {
    $filterDesc = "仅视频文件"
    if($sortMode -eq "D"){ $sortText = "视频时长降序，相同时长按文件大小降序" }
    elseif($sortMode -eq "B"){ $sortText = "视频流码率降序" }
    elseif($sortMode -eq "R"){ $sortText = "视频长边分辨率降序" }
    else{ $sortText = if($exportMeta){"文件大小降序，附带视频元数据"}else{"文件大小降序"} }
} else { $filterDesc = "全部文件"; $sortText = "文件大小降序" }

$recurDesc = if($recurseParam){"递归子目录"}else{"仅当前目录"}
$typeDesc = if($videoMode){"仅视频"}else{"全部文件"}
$sortDesc = switch($sortMode){"S"{"文件大小"}"B"{"视频流码率"}"R"{"视频长边分辨率"}"D"{"视频时长"}}
$filterDesc2 = if($useBitrateFilter){"按码率阈值($bitrateThresholdKbps kbps)筛选"}else{"不过滤码率"}
$metaDesc = if($exportMeta){"读取元数据(码率/分辨率/时长)"}else{"不读取元数据"}
$reSortDesc = if($reSortBy){"二次排序:按$reSortBy降序"}else{"不二次排序"}
# >>> v22.0 CSV模式区分描述
$modeLabel = if ($useCsvAsSource) { "根据CSV交互模式" } else { "交互模式" }
$fullDesc = "$modeLabel | $recurDesc | $typeDesc | 排序:$sortDesc | $filterDesc2 | $metaDesc | $reSortDesc | 最大条数:$topCount"
$interactiveDetail = "递归:$recurDesc | 类型:$typeDesc | 排序维度:$sortDesc | 码率筛选:$filterDesc2 | 元数据:$metaDesc | 二次排序:$reSortDesc | 最大输出:$topCount"

$metaHasDuration = $exportMeta
Write-Host
Write-Host
Write-Host "  $(col_a_text_muted ('过滤：' + $filterDesc + ' | 排序：' + $sortText))"
if ($reSortBy) { Write-Host "  $(col_a_text ('（结果集将按 ' + $reSortBy + ' 二次降序排列）'))" }
if ($metaHasDuration) { Write-Host "  $(col_a_text_gray '（已读取元数据，时长/码率/分辨率将自动附带）')" }

# >>> v22.0 CSV模式：跳过扫描，直接构建workList
if ($useCsvAsSource -and $csvInjectedWorkList -and $csvInjectedWorkList.Count -gt 0) {
    $workList = $csvInjectedWorkList
    $totalVideoCount = $workList.Count
    Write-Host (col_a_text "  CSV注入模式：已加载 $totalVideoCount 个视频条目，跳过文件扫描。")
    # 设置后续排序/漏斗所需变量
    $rawFiles = @()  # 空占位，防止下方引用报错
    $scanRoot = $PWD.Path.Trim()
} else {
    $scanRoot = $PWD.Path.Trim()
    $blacklistFile = Join-Path $scanRoot "blacklist.txt"
    if (Test-Path -LiteralPath $blacklistFile) {
        $scanBlackList = Get-Content -LiteralPath $blacklistFile -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" -and $_ -notmatch '^#' }
    }

    $accessDeniedDirs = @(); $scanErrors = @()

    Write-Host (col_a_subtitle "  正在扫描文件（阶段1/2）...")
    Show-LinearProgressBar -Current 0 -Total 100 -Status "初始化扫描..."

    $rawAll = Get-AllFilteredFiles -Path $scanRoot -DoRecurse $recurseParam -BlackList $scanBlackList -OutAccessDeniedDirs ([ref]$accessDeniedDirs) -OutScanErrors ([ref]$scanErrors) -ShowProgress
    Show-LinearProgressBar -Current 100 -Total 100 -Status "文件收集完成，共 $($rawAll.Count) 个文件"
    Write-Host

    if ($videoMode) { $rawFiles = $rawAll | Where-Object { $_.Extension -in $videoExts } } else { $rawFiles = $rawAll }
    if ($rawFiles.Count -eq 0) { Write-Host "  无匹配文件"; Wait-AnyKey "  按任意键退出..."; return }

    $totalVideoCount = $rawFiles.Count
    Write-Host (col_a_success "  扫描到 $totalVideoCount 个视频文件，开始处理...")
}  # >>> v22.0 闭合CSV else块

# >>> FIX v21: 初始化漏斗计数变量（交互模式）
$interactiveHeightFiltered = 0
$interactiveSizeTopFiltered = 0
$interactiveBitrateFiltered = 0
$interactiveSizeFiltered = 0
$interactiveWorkListCountBeforeHeight = 0
$interactiveWorkListCountBeforeSizeTop = 0
$interactiveWorkListCountBeforeBitrate = 0

# >>> v22.0 CSV模式已赋值则跳过初始化
if (-not $useCsvAsSource) {
    $workList = @()
}
$metaFail = 0; $durMap = @{}; $taskList = @()

# >>> v22.0 CSV模式跳过元数据读取（已有元数据）
if (-not $useCsvAsSource -and $videoMode -and $exportMeta) {
    Write-Host (col_a_text "  【批量读取视频流元数据（阶段2/2）】`n")
    $tempDir = Join-Path $env:TEMP "video_meta_$(Get-Random)"
    try {
        New-Item -ItemType Directory -Path $tempDir | Out-Null
        foreach ($f in $rawFiles) {
            # v3.10：只统计本次脚本自己拉起、且尚未退出的 ffprobe，避免被外部转码进程拖住
            while (@($taskList | Where-Object { -not $_.Proc.HasExited }).Count -ge $maxConcurrent) { Start-Sleep -Milliseconds 40 }
            $outPath = Join-Path $tempDir "$($f.BaseName)_$($f.LastWriteTime.Ticks).txt"
            $extraArgs = '-v error -select_streams v:0 -show_entries stream=bit_rate,avg_bit_rate,width,height:format=duration -of json'
            $args2 = Get-FfprobeArgs -FilePath $f.FullName -ExtraArgs $extraArgs
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "ffprobe.exe"; $psi.Arguments = $args2
            $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
            $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
            $proc = [System.Diagnostics.Process]::Start($psi)
            $taskList += [PSCustomObject]@{ File=$f; Proc=$proc; OutFile=$outPath }
        }
        $processedCount = 0; $lastPct = -1
        while ($taskList.Count -gt 0) {
            $running = @()
            foreach ($t in $taskList) {
                if (-not $t.Proc.HasExited) { $running += $t; continue }
                $processedCount++
                $phase2Pct = [int]($processedCount / $totalVideoCount * 100)
                $pctVal = $phase2Pct
                if ($pctVal -ne $lastPct -or $processedCount -eq $totalVideoCount) {
                    Show-LinearProgressBar -Current $phase2Pct -Total 100 -Status "元数据读取: $processedCount/$totalVideoCount | $($t.File.Name)"
                    $lastPct = $pctVal
                }
                $vi = [PSCustomObject]@{BitrateKbps=$null;BitrateSource=$null;Width=$null;Height=$null;LongEdge=$null;DurationSec=$null;DurationDisp="-"}
                if ($t.Proc.ExitCode -eq 0) {
                    try {
                        $rawTxt = $t.Proc.StandardOutput.ReadToEnd()
                        if (-not $rawTxt) { $rawTxt = [System.IO.File]::ReadAllText($t.OutFile) }
                        $jsonObj = $rawTxt | ConvertFrom-Json
                        $vStream = $jsonObj.streams[0]
                        $w=[int]$vStream.width; $h=[int]$vStream.height
                        $bitrateBps = $null
                        if (-not [string]::IsNullOrWhiteSpace($vStream.bit_rate)) { $bitrateBps = [long]$vStream.bit_rate }
                        elseif (-not [string]::IsNullOrWhiteSpace($vStream.avg_bit_rate)) { $bitrateBps = [long]$vStream.avg_bit_rate }
                        $durSec = 0.0; $durDisp = "-"
                        if ($jsonObj.format -and $jsonObj.format.duration) {
                            $tmp = 0.0
                            if ([double]::TryParse($jsonObj.format.duration, [ref]$tmp)) {
                                $durSec = $tmp; $durDisp = (Get-FriendlyDuration $durSec)
                            }
                        }
                        $vi = [PSCustomObject]@{
                            BitrateKbps=if($bitrateBps){[Math]::Round($bitrateBps/1000)}else{$null}
                            BitrateSource="bitrate"; Width=$w; Height=$h; LongEdge=[Math]::Max($w,$h)
                            DurationSec=$durSec; DurationDisp=$durDisp
                        }
                    } catch { $metaFail++ }
                } else { $metaFail++ }
                $brDisp = if($vi.BitrateKbps){"$($vi.BitrateKbps) kbps"}else{"[码率缺失]"}
                $resDisp = if($vi.Width){"$($vi.Width)x$($vi.Height)"}else{"-"}
                $workList += [PSCustomObject]@{
                    FullPath=$t.File.FullName.Trim(); FileSizeBytes=$t.File.Length; FileSizeFriendly=(Get-FriendlySize -Bytes $t.File.Length)
                    BitrateKbps=$vi.BitrateKbps; BitrateDisp=$brDisp; BitrateSource=$vi.BitrateSource
                    Width=$vi.Width; Height=$vi.Height; ResDisp=$resDisp; LongEdge=$vi.LongEdge
                    DurationSec=$vi.DurationSec; DurationDisp=$vi.DurationDisp
                }
            }
            $taskList = $running; Start-Sleep -Milliseconds 20
        }
        Show-LinearProgressBar -Current 100 -Total 100 -Status "元数据读取完成！"
        Write-Host
    }
    finally { Cleanup-TaskProcesses -TaskList $taskList; [GC]::Collect(); [GC]::WaitForPendingFinalizers(); if(Test-Path $tempDir){Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue} }

    if($sortMode -eq "D" -and -not $useCsvAsSource){
        Write-Host (col_a_text "`n  【D模式：全局预读取全部视频时长】`n")
        $durTempDir = Join-Path $env:TEMP "dur_batch_$(Get-Random)"; New-Item -ItemType Directory -Path $durTempDir | Out-Null
        $durProcessed = 0
        foreach ($f in $rawFiles) {
            # v3.10：此处为 cmd /c 同步调用（一次只跑一个 ffprobe），本就不需要限流；
            #        原 while 用全机器 ffprobe 计数，外部转码会把本脚本卡死，故移除。
            $outFile = Join-Path $durTempDir "$($f.BaseName)_$($f.LastWriteTime.Ticks).txt"
            $result = Invoke-FfprobeDuration -FilePath $f.FullName -OutFile $outFile
            $txt = $result.Output
            $sec = $null; $tmp = 0.0
            if ([double]::TryParse($txt, [ref]$tmp)) { $sec = $tmp }
            $durMap[$f.FullName] = $sec
            $durProcessed++
            if ($durProcessed % $progressStep -eq 0) { Write-Host "  时长预读：$durProcessed / $totalVideoCount" }
        }
        Remove-Item $durTempDir -Recurse -Force -ErrorAction SilentlyContinue
        for($wi=0;$wi -lt $workList.Count;$wi++){ $item=$workList[$wi]; $s=$durMap[$item.FullPath]; $item.DurationSec=$s; $item.DurationDisp=(Get-FriendlyDuration $s) }
    }
} else {
    foreach ($f in $rawFiles) {
        $workList += [PSCustomObject]@{ FullPath=$f.FullName.Trim(); FileSizeBytes=$f.Length; FileSizeFriendly=(Get-FriendlySize -Bytes $f.Length); BitrateKbps=$null; BitrateDisp="-"; Width=$null; Height=$null; ResDisp="-"; LongEdge=$null; DurationSec=$null; DurationDisp="-" }
    }
}

# >>> FIX v21: 体积初筛计数（交互模式）
$interactiveWorkListCountBeforeSizeTop = $workList.Count
if ($SizeTop) {
    $sizeTopCount = [Math]::Max(1, $SizeTopCount)
    $workList = @($workList | Sort-Object FileSizeBytes -Descending | Select-Object -First $sizeTopCount)
    $interactiveSizeTopFiltered = $interactiveWorkListCountBeforeSizeTop - $workList.Count
}

# >>> FIX v21: 高度过滤计数（交互模式）
$interactiveWorkListCountBeforeHeight = $workList.Count
if ($MinHeight -gt 0 -or $MaxHeight -gt 0) {
    if ($MinHeight -gt 0) { $workList = @($workList | Where-Object { $_.Height -ge $MinHeight }) }
    if ($MaxHeight -gt 0) { $workList = @($workList | Where-Object { $_.Height -le $MaxHeight }) }
    $interactiveHeightFiltered = $interactiveWorkListCountBeforeHeight - $workList.Count
}

# ---- 排序 ----
if ($videoMode -and $sortMode -eq "B") {
    $sortedAll = @($workList | Sort-Object @{E={if($_.BitrateKbps -eq $null){-1}else{$_.BitrateKbps}};D=$true}, @{E={$_.FileSizeBytes};D=$true})
    # >>> FIX v21: 码率过滤计数（交互模式）
    $interactiveWorkListCountBeforeBitrate = $sortedAll.Count
    if($useBitrateFilter){ $sorted = @($sortedAll | Where-Object { $_.BitrateKbps -ge $bitrateThresholdKbps }) }
    else { $sorted = @($sortedAll) }
    # v3.3：先算过滤损失，再统一截 Top（原逻辑过滤分支完全跳过 -Top）
    $interactiveBitrateFiltered = $interactiveWorkListCountBeforeBitrate - $sorted.Count
    $sorted = @($sorted | Select-Object -First $topCount)
}
elseif ($videoMode -and $sortMode -eq "R") {
    $sorted = @($workList | Sort-Object @{E={if($_.LongEdge -eq $null){-1}else{$_.LongEdge}};D=$true}, @{E={$_.FileSizeBytes};D=$true} | Select-Object -First $topCount)
}
elseif ($videoMode -and $sortMode -eq "D") {
    $sorted = @($workList | Sort-Object @{E={if($_.DurationSec -ne $null){$_.DurationSec}else{-1}};D=$true}, @{E={$_.FileSizeBytes};D=$true} | Select-Object -First $topCount)
}
else {
    $sortedAll = @($workList | Sort-Object FileSizeBytes -Descending)
    # >>> FIX v21: 码率过滤计数（交互模式 S模式）
    $interactiveWorkListCountBeforeBitrate = $sortedAll.Count
    if ($useBitrateFilter) { $sortedAll = @($sortedAll | Where-Object { $_.BitrateKbps -ge $bitrateThresholdKbps }) }
    # v3.3：码率过滤只统计过滤损失，Top 截断不再冒充"码率过滤"
    $interactiveBitrateFiltered = $interactiveWorkListCountBeforeBitrate - $sortedAll.Count
    $sorted = @($sortedAll | Select-Object -First $topCount)
}
$sorted = @($sorted)

# >>> FIX v20: 交互模式二次排序
if ($reSortBy -and $reSortBy.ToUpper() -in @("D","S","B","R")) {
    $rsMode = $reSortBy.ToUpper()
    Write-Host (col_a_text "`n  >> 二次排序：按 $rsMode 降序重新排列结果集（共 $($sorted.Count) 条）")
    switch ($rsMode) {
        "D" { $sorted = @($sorted | Sort-Object @{E={if($_.DurationSec -ne $null){$_.DurationSec}else{[double]::MaxValue}};D=$true}) }
        "S" { $sorted = @($sorted | Sort-Object @{E={$_.FileSizeBytes};D=$true}) }
        "B" { $sorted = @($sorted | Sort-Object @{E={if($_.BitrateKbps -eq $null){-1}else{$_.BitrateKbps}};D=$true}) }
        "R" { $sorted = @($sorted | Sort-Object @{E={if($_.LongEdge -eq $null){-1}else{$_.LongEdge}};D=$true}) }
    }
}

# >>> FIX v19: 最终大小过滤（交互模式，带计数）
$interactiveSizeFiltered = 0
if ($MinSizeMB -gt 0) {
    $minSizeBytesInteractive = $MinSizeMB * 1024 * 1024
    $beforeFilter = $sorted.Count
    $sorted = @($sorted | Where-Object { $_.FileSizeBytes -ge $minSizeBytesInteractive })
    $interactiveSizeFiltered = $beforeFilter - $sorted.Count
    if ($interactiveSizeFiltered -gt 0) {
        Write-Host (col_a_warning "`n  >> 按大小过滤：排除 $interactiveSizeFiltered 个小于 $MinSizeMB MB 的文件，剩余 $($sorted.Count) 个")
    }
}

# ---- 预览 ----
Write-Host
Write-Host
$outputRows = @()
$showDuration = $videoMode -and $exportMeta
for($i=0; $i -lt $sorted.Length; $i++){
    $item = $sorted[$i]; $rank = $i+1
    $outputRows += [PSCustomObject]@{ RankOrig=$rank; DurationDisp=$item.DurationDisp; FileSizeFriendly=$item.FileSizeFriendly; BitrateDisp=$item.BitrateDisp; ResDisp=$item.ResDisp; FullPath=$item.FullPath }
    if ($showDuration) {
        $dispDur = $item.DurationDisp
        if ($dispDur -eq $null) { $dispDur = "-" }
        Write-Host ("  [{0,3}] {1,-12} | {2,-10} | {3,-16} | {4,-12} | {5}" -f $rank,$dispDur,$item.FileSizeFriendly,$item.BitrateDisp,$item.ResDisp,$item.FullPath)
    } else {
        Write-Host ("  [{0,3}] {1,-10} {2}" -f $rank,$item.FileSizeFriendly,$item.FullPath)
    }
}
$outputRows = @($outputRows)

# ---- 保存 txt ----
Write-Host
$saveLabels = @(
    '[y]保存 TXT（推荐）'
    '[n]不保存'
)
$savePick = Select-Vertical -Labels $saveLabels -Default 0 -Title '是否保存结果到 TXT'
if ($savePick -lt 0) { continue RESTART }
$saveValues = @(
    'yes'
    'no'
)
$saveResult = $saveValues[$savePick]
if ($null -ne $saveResult -and $saveResult -eq 'yes') {
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $cleanDesc = $fullDesc.Replace("交互模式", "").Replace(" ", "_").Replace("__", "_")
    $cleanDesc = $cleanDesc.Replace("<", "").Replace(">", "").Replace(":", "").Replace('"', "").Replace("/", "_").Replace("\", "_").Replace("|", "").Replace("?", "").Replace("*", "")
    $cleanDesc = $cleanDesc.Trim("_ ").Trim()
    if ($cleanDesc.Length -gt 80) { $cleanDesc = $cleanDesc.Substring(0, 80) }
	
	# >>> v22.0 CSV模式区分文件名
    $modeTag = if ($useCsvAsSource) { "根据CSV交互模式" } else { "交互模式" }
    $outName = "本文件夹内文件筛选&排序统计_${modeTag}_${cleanDesc}_${ts}.txt"
	
    $lines = @()
    $lines += "全能文件排序统计结果"
    $lines += $fullDesc
    $lines += "# 交互详情: $interactiveDetail"
    $displayRoot = $scanRoot -replace '^Microsoft\.PowerShell\.Core\\FileSystem::',''
    $lines += "#扫描根目录: $displayRoot"
    $lines += "#扫描时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += "# ===== 筛选漏斗统计（按执行顺序）====="
    $lines += "#总扫描视频数量: $totalVideoCount"
    if ($interactiveHeightFiltered -gt 0) { $lines += "#高度过滤: 排除 $interactiveHeightFiltered 个（范围 ${MinHeight}-${MaxHeight}P），剩余 $($totalVideoCount - $interactiveHeightFiltered)" }
    if ($interactiveSizeTopFiltered -gt 0) { $lines += "#体积初筛: 排除 $interactiveSizeTopFiltered 个（取前 $SizeTopCount 按大小），剩余 $($totalVideoCount - $interactiveHeightFiltered - $interactiveSizeTopFiltered)" }
    if ($interactiveBitrateFiltered -gt 0) { $lines += "#码率过滤: 排除 $interactiveBitrateFiltered 个（>= ${bitrateThresholdKbps}kbps），剩余 $($totalVideoCount - $interactiveHeightFiltered - $interactiveSizeTopFiltered - $interactiveBitrateFiltered)" }
    if ($reSortBy) { $lines += "#二次排序: 按 $reSortBy 降序重排（不拦截）" }
    if ($interactiveSizeFiltered -gt 0) { $lines += "#大小过滤: 排除 $interactiveSizeFiltered 个（>= ${MinSizeMB}MB），剩余 $($sorted.Length)" }
    $lines += "#最终输出数量: $($sorted.Length)"
    $lines += "# ===== 筛选漏斗统计结束 ====="
    $hasDurationCol = ($videoMode -and $exportMeta)
    if($hasDurationCol){
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
    try{ $txtContent | Out-File -LiteralPath $outName -Encoding UTF8; Write-Host (col_a_success "`n  ✅已保存：$PWD\$outName") }
    catch{ Write-Host (col_a_error "`n  【错误】写入失败：$($_.Exception.Message)") }
}

Wait-AnyKey "`n  任务完成，按任意键关闭窗口"
break   # 正常走完流程 → 跳出 :RESTART 循环
}   # end :RESTART while ($true)
return