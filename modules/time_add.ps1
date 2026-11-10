<#
time_add.ps1
v1.0：合并 time_add_begin/end/only 三脚本为统一入口。
    主菜单 1/2/3 选择时间前置/后置/仅时长，q 退出。
    ffprobe 并发提取时长 + Shell.Application 兜底，自动检测 CPU 核心数×0.75 控制并发。
    已标记文件三选一（n全重/s逐文件/其他跳过），预览表分列原名|新名，
    y执行/s导出映射txt/其他退出，u撤销/s保存映射。
    Emby配图跟随+nfo标签改写子选项，正则处理nfo内部XML。
    PS 5.1 兼容，不引入PS 7语法。
v1.1：ffprobe 并发增加 5 秒超时 kill 兜底，
    超时后自动切入 Shell.Application 并屏幕输出黄色警告提示（含文件名+原因），方便排查损坏文件。其余逻辑不变。
v1.2：优化扩展名匹配为小写列表＋ToLower()对照（$videoExts含mp4/mov/mkv/avi/flv/wmv/m4v/ts/mpg/mpeg/f4v/m2ts/mts/webm/rmvb，$artExts含jpg/jpeg/png/webp/nfo）。
v1.3：修复$timeRegex/$pureTimeNameRegex正则中(?!\d)前后瞻导致纯数字开头时长(如00m10s)无法被识别为已标记文件的bug，
    改用\b单词边界替代，对齐sh版正则逻辑。修复后已含时间标记的文件能正确命中策略分支，不再重复追加。
v1.4：在元信息读取完成后，直观高亮显示已含时间标记的文件（黄色），
    并在预览表中延续黄色标识；正常文件默认色。解决底部仅文字提示不直观的问题，对齐 sh 版行为，为后续 n/s/跳过策略提供视觉依据。nfo子选项仍留待后续。
v1.5：反转 Emby 附属文件模式默认推荐方向——选项1改为"关闭配图跟随（仅处理视频）"，
    "按其他任意键开启"标注为推荐项并绿色高亮；
    已标记文件策略选单前三行（标题/n全重/s逐个）从 Yellow 改为白色（默认色），推荐跳过保留 Green。
    延续 v1.4 已标记文件黄色高亮列出逻辑。
v1.6：引入 modules\ui\ui.ps1 配色体系，替换全部裸 ForegroundColor 为 col_a_* 调用（事实并没有改全）。
    零逻辑改动，视觉行为与 v1.5 一致。配色风格与 tt.ps1 对齐。
v2.0~v3.X：尝试菜单使用 ui.ps1 arrow_select 光标移动，但存在预览后选单重叠问题，多次修改未能解决，暂时放弃。
    后续 v4.1~v4.2 重新通过 Get-SingleKey 逐键读取方案稳定替代，
    孤立检测/撤销还原等新增交互均基于该方案实现，未再出现重叠问题。
v4.0.7：修复全文大括号配对——补回外层 try 包裹业务逻辑，与末尾 finally 正确配对；
    清理 undoList 菜单多余闭合；所有 switch/if 缩进规范化。无业务逻辑改动。
v4.1：nfo改写前自动生成 .bak 备份文件（$nfoBackupList 记录），撤销时还原 .bak 内容并清理备份，
    保存映射 txt 时追加 bak 路径记录。
    修复 $nfoBackupList 未初始化为 @() 导致的 op_Addition 报错。
v4.2：对齐 nfo.ps1 v3.7。
    新增孤立 nfo/图片检测（排除已配对+排除附属，删前 .bak 备份，撤销可还原）；
    预览表新增 nfo 标签状态颜色区分（黄=需改/绿=一致/灰=无标签）；撤销分支补充孤立文件还原逻辑。
v4.3：清理孤立检测模块中 5 处裸 -ForegroundColor 硬编码，全部替换为 col_a_* 配色函数调用；
    预览表 nfo 标签状态颜色从 -ForegroundColor $nfoColor 变量写法固化为
    col_c_light_yellow / col_c_grass_green / col_c_dark_gray 纯色函数直接调用，
    与 ui.ps1 基础色板解耦，便于后续统一换色。零逻辑改动。
v4.4：主菜单简化写法，弃用 switch+[int]，改 if/elseif 直给映射，回车默认'1'，与 Emby 菜单风格统一；默认项高亮。
v5.0：交互方案重构。弃用 Get-SingleKey 逐键读取，全面替换为
    Select-Horizontal 横向菜单（左右键切换、Enter确认、Esc取消）。
    彻底解决 Arrow-Menu 多级嵌套导致的预览表重影/错行问题。
    线性流程不变，仅交互层替换，零逻辑改动。
v5.3：Select-Horizontal 函数迁移至 ui\ui.ps1 作为公共组件，
    time_add.ps1 不再内联定义，由 UI 框架统一加载。
    其他子脚本（nfo_title.ps1 等）可直接复用，零逻辑改动。
v5.4：新增外层 while($true) 循环实现"重新开始"逻辑。第一层 q/Esc 退出脚本（break），
    其他层 q/Esc 回脚本开头（continue）。保留原有注释与 #-Footer 行。
    延续 v5.3 Select-Horizontal 公共组件调用。
v5.7：修复第二层/第三层 q/Esc 误退出脚本的问题。
    根因为 $null 处理用了 break 跳出了外层 while($true) 循环导致脚本结束。
    改为 continue 跳回循环开头（Clear-Screen 重来），与"回第一级菜单"需求对齐。第一层 exit 保持 exit 0 不变。
v5.8：孤立nfo/图片清理提示、已标记文件逐文件确认均弃用Get-SingleKey，改为Select-Horizontal横向菜单。
    选项明确拆分（删除并备份/跳过、重处理/跳过），默认高亮安全项。全脚本交互统一为横向菜单，零逻辑改动。
v5.9：nfo内部标签改写逻辑重构。删除步骤②的提前开关菜单，改为视频改名预览后独立扫描所有.nfo文件，
    对比<title>与外部文件名，单独出差异表让用户看到差异后再决定（全改/逐条确认/跳过）。
    执行阶段nfo标签改写与视频改名统一执行、统一进undoList。
    附属配对阶段不再顺带赋值nfoNewTitle。延续v5.8交互规范。
v5.10：在 nfo 标签决策后、最终执行前，新增独立“最终执行预览”重绘模块。
    无条件输出完整表（RENAME/RENAME-EXT/TAB-SYNC），TAB-SYNC 特殊标记，表尾提示标签改写。
    采用独立渲染不复用前表，便于后续维护。
v5.11：修复一次预览表长文件名（如第7行）截断不足导致下方行错行/挤行问题。
    根因为 $truncName 截断阈值（16）远低于列宽（30），超长名未截断直接撑爆终端。
    加固截断逻辑（阈值提至28，含中英文宽度估算），绘制循环末尾强制换行清尾。执行段/二次表不动。
    已标记文件选“跳过”时操作列显 [SKIP]
v5.16：合并 v5.14/v5.15。统一预览表列宽（42）与表头绘制（Show-PreviewHeader），
    收归全局变量，调用处零硬编码，序号宽-3。
v5.18：新增 $nfoActualRewriteCount 计数器，在 nfo 差异选单各分支赋值；
    二次预览模块前加 if ($nfoActualRewriteCount -gt 0) 守卫，标题动态拼接
    "含 nfo 标签改写项"后缀。无实际改写时跳过二次预览直接进确认执行。
    原 v5.9 TAB-SYNC 内联改写注释废弃，改为 v5.18 统一块去重；
    原 v5.10/v5.16 二次预览硬编码标题调整为计数器守卫动态标题。
v5.19：执行阶段 nfo 输出对齐下午三点基线。
    改写成功时打一行 [nfo标签覆盖 OK] title→目标名；[nfo MISS] 和未开启改写时完全静默不输出。视频改名行格式不变。
v5.28：修复模式三（only）对已有序号文件二次重处理时执行段跳号（00m06s2→22/32/42）。
    根因为执行段"同名冲突自动追加序号"未排除自身，且 nfo 段存在重复改名死代码（引用未定义 $DoRename）。
    修复：执行段冲突检测增加 $isSelf 排除自身（与预览 v5.24-fix 对齐）；
    删除 nfo 段 1241~1296 行重复重命名块，主逻辑唯一且纯净。零其他逻辑改动。
v5.29：预览表新增名实一致判定。
    在 only 模式全部重处理场景下，若计算结果新文件名与原名相同，操作列标 [SKIP]（灰色）并标记 $skipRow = $true，渲染为空白占位行；
    执行段增加同名兜底跳过，避免无意义 Rename-Item 调用。延续 v5.28 逻辑，零其他改动。
v5.30-fix：严格还原原始基线执行顺序，仅新增 $diffIdx = 0 初始化防止 $null++ 报错。
    保留 $rowPrefix = $idxStr 确保序号拼入输出行。最小改动，其余原样。
    差异表序号计数器初始化，防止首次运行 $null++ 报错
    在 RENAME-EXT 附属文件（如 .nfo）原名=新名时，于循环首部直接拦截，跳过文件重命名与 nfo 标签改写（因预览已确认内外一致），
    彻底消灭 00m34s2.nfo → 00m34s2.nfo [OK] 的幽灵输出；
    文件层行为不变（无写入、无 .bak）。最小改动，保留原冲突处理与标签逻辑
v5.31-fix（nfo写入加锁）：针对 P0-1（误写视频文件）与 P0-2（编码破坏/备份损坏）加三道锁。
    1、else { $nfoPath = $src } 改为强制基名推导 .nfo，杜绝视频路径直传；
    2、写入前硬性校验 .nfo 扩展名 + 存在性，不合法直接 continue；
    3、.bak 备份改为 Copy-Item 字节级复制保编码，ReadAllText/WriteAllText 增加 BOM 探测（UTF8/UTF16/GBK）并按原编码回写。
    最小改动，其余原样保留。
v5.32（孤立文件白名单修正，实际修正于 v5.34）：原正则强制要求 -(poster|cover|...)\d*$ 连字符前缀，
    且以 BaseName（不含扩展名）去匹配要求 \.nfo$ / \.jpg$ 结尾的模式，导致 poster.jpg、movie.nfo 等
    Emby 标准无连字符命名被漏判为"孤立文件"进而被误删。此类文件同时会在 nfo 差异扫描中被当成
    "外部文件名不一致"，<title> 有被改写成 movie / poster 字面量的风险。
    本版未修成，问题在 v5.34 一并解决。
v5.34：nfo 写入安全加固 + 正则修复 + 交互完善 + 死代码清理。本次为本脚本的主线修复版本。
    一、孤立文件白名单（修复 v5.32 遗留）
        1、新增 Test-ArtBaseName 公共判定函数，判定对象统一为 BaseName（不含扩展名）：
           形态① 无连字符标准命名：poster / poster1 / poster (2)
           形态② 无连字符元数据：movie / tvshow / season01
           形态③ 带连字符的视频配图：AAA-poster / AAA-fanart1 / AAA (2020)-thumb
           词干扩展为 16 种（新增 folder/background/discart），尾号支持 2 / -2 / _2 / " (2)"。
        2、孤立 nfo 检测、孤立图片检测、nfo 内部标签差异扫描三处统一改调 Test-ArtBaseName，
           单一真相源，后续加词干只改 $artStemList / $metaStemList 一处。
        3、配图跟随改名改为从 $artStemList 动态生成后缀模式，与孤立检测口径一致，
           解决 -banner/-logo/-clearart 等配图不跟随视频改名后变成无主文件的静默失效。
    二、nfo 写入路径加锁
        1、nfo 改写段限定 Status -eq 'TAB-SYNC' 唯一入口，
           视频改名行、配图改名行不再进入 nfo 改写，杜绝旧基名回填 <title>。
        2、备份记录新增 OldPath（撤销回滚目标），撤销还原改为字节级 Copy-Item，
           并对还原目标强制 .nfo 扩展名校验，杜绝把 nfo 文本写进 .mp4。
        3、编码探测重写：BOM 优先（UTF8/UTF16LE/UTF16BE），无 BOM 先严格试 UTF-8，
           失败才回退 GB18030；回写沿用探测编码，不再无条件写 UTF-8 带 BOM，
           解决 GBK / UTF-16 nfo 被整份写坏且备份同样损坏的问题。
           系统缺失 GB18030 代码页（Windows N / Server Core / 纯英文系统）时，
           捕获后打印 [nfo跳过] 并 continue 跳过该文件，不做错误编码兜底（避免写坏）。
        4、备份改为字节级复制，编码与 BOM 状态原样保留。
        5、nfo 目标路径推导简化为单行（原三段 if/elseif/else 中两支不可达），
           目标不存在时打印 [nfo跳过] 提示，不再静默漏改。
    三、XML 内容安全
        1、$safeTitle 全链路转义：SecurityElement::Escape 后将 $ 替换为 $$（防 -replace 分组解析），
           覆盖 <title>/<sorttitle> 的替换分支与追加分支共 6 处，
           解决文件名含 & < > $ 时写出非法 XML 或吞字符的问题。
        2、新增 $rootTag 根节点探测（movie / episodedetails / tvshow），
           缺失标签统一插入根节点闭合标签之前，不再追加到文件末尾，
           解决剧集 nfo（<episodedetails>）缺 <title> 时生成非法 XML 的问题。
    四、文件名正则修复
        1、$timeRegex 去掉尾部 \b、左侧改 (?<!\d)，
           解决 00m06s2 / 00m06s-2 等"时间标记后紧跟数字"被误判为未标记、重复追加时长的问题。
        2、$pureTimeNameRegex 保持不变（^...$ 锚定，无边界问题）。
    五、交互与显示
        1、撤销结束后补 Wait-AnyKey 停留，解决撤销完成提示一闪而过直接返回的问题。
        2、主菜单头部显示处理目录，取 $PWD.ProviderPath 去掉 FileSystem provider 前缀，
           UNC 路径不再显示 Microsoft.PowerShell.Core\FileSystem:: ，超长路径保头保尾截断。
        3、撤销段采用 [array]::Reverse($undoList) 逆序还原（栈语义），
           链式/交叉改名链后改先撤，降低还原撞名概率。
        4、$nfoActualRewriteCount 在 while 顶部每轮重置，
           解决上一轮残留值导致无 nfo 差异时误显示"最终执行预览"二次表的问题。
        5、撤销统计拆分：$failUndo 仅统计文件名还原失败，新增 $failNfo 统计 nfo/孤立文件
           还原失败，解决原"文件名数 - 混合失败数"可能算出负数的问题。
        6、nfo 差异表表头改为全程按视觉宽度（Get-DisplayWidth）推进，
           列起点按正文实际布局推算（$col2Pos / $statusPos），
           解决原用 .Length 与视觉宽度混算导致的 3 列表头错位、状态列无间隔的问题。
        7、事后菜单改为先取值再判空：if ($null -eq $postResult) { exit 0 }，
           替换原来判数组 $postOpts 的恒假无效判断，Esc/q 可正确 exit 0 返回 tt 主菜单。
    六、死代码清理（零行为变更）
        1、删除本文件内的 Get-SingleKey 自定义函数（早期 Arrow-Menu 错行时的临时方案，
           改用 Select-Horizontal 后已零调用）；ui.ps1 中的同名函数作为公共备选保留不动。
        2、删除 $truncText 脚本块（已被 Format-TruncatedName 取代，零引用）。
        3、删除重复定义的 Get-DisplayWidth（第一处在 while 之前、从未被调用，
           保留 Format-TruncatedName 区内的第二处定义）。
        4、$isSkipMode 移除对 $global:MarkedStrategy 的引用（该变量从未赋值，条件恒为 $false），
           简化为等价表达式 (-not $forceRewriteAll -and -not $perFileSelect)。
    说明：本版所有改动均经真机端到端验证：
          双轮幂等回归（only 模式重复跑全 [SKIP]，00m34s2 不再跳号）；
          movie.nfo / poster.jpg 全程保留、未被误删也未被改 <title>；
          ssss 00m33s-poster.jpg 正常跟随视频改名；
          nfo 编码保真（GBK / UTF-8 / UTF-16 回写不变）；
          改名与撤销全链路往返：撤销后文件名、nfo 名、nfo 内 <title> 全部还原；
          撤销输出"文件名还原成功 32 ｜失败 0 ｜附属文件还原失败 0"。
v5.35：ffprobe 并发调度重构——与外部 ffprobe 进程解耦。
    1、删除 Get-AllDurations 中基于 Get-Process ffprobe 的全机器计数限流。
       旧实现在机器上同时有 QuickSync / 格式工厂 / Emby 转码时，外部 ffprobe 会被计入额度，
       导致本脚本长时间空等甚至看起来卡死。
    2、改为单循环「额度内启动 + 轮询收集」模型：限流额度只统计本函数自己启动、
       尚未退出的进程（$running.Count），与外部 ffprobe 完全无关。
       原实现是先全部启动、再统一收集的两段式，只能靠外部进程数实现限流，无法解耦。
    3、超时判断改用自记的 $t.StartAt，替代 $t.Process.StartTime。
       后者在进程已退出时会抛 InvalidOperationException，原代码未捕获。
    4、HasExited / Process::Start / Get-Content 全部加 try/catch 包裹：
       进程已退出、ffprobe 不在 PATH、输出文件被占用等场景不再抛未捕获异常。
    5、ffprobe 输出重定向追加 2>nul，屏蔽错误输出污染进度界面。
    6、启动失败（如 ffprobe 缺失）也计入进度并走 Shell.Application 兜底，
       避免原实现中"启动失败 → 进度永远到不了 100%"的问题。
    7、保留 5 秒超时 → Shell.Application 兜底 的原设计不变。
#>


# ========== 加载公共 UI 框架 ==========
. (Join-Path $PSScriptRoot "ui\ui.ps1")
. (Join-Path $PSScriptRoot "common.ps1")

# ========== 工具函数 ==========
function Wait-AnyKey {
    param([string]$Prompt = "`n  按任意键继续...")
    Write-Host $Prompt -NoNewline
    [Console]::ReadKey($true) | Out-Null
    Write-Host ""
}

# ========== 时长提取函数 ==========
function Get-VideoDuration {
    param([string]$FilePath)
    $durSec = $null
    try {
        $ffprobe = "ffprobe.exe"
        $info = & $ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$FilePath" 2>$null
        if ($info -and $info -match '^\s*[\d\.]+') {
            try { $durSec = [double]$info } catch {}
        }
    } catch {}
    if ($null -eq $durSec -or $durSec -le 0) {
        try {
            $shell = New-Object -ComObject Shell.Application
            $folder = $shell.Namespace((Split-Path $FilePath))
            $item = $folder.ParseName((Split-Path $FilePath -Leaf))
            $durationStr = $folder.GetDetailsOf($item, 27)
            if ($durationStr) {
                $parts = $durationStr -split ':'
                if ($parts.Count -eq 3) {
                    $durSec = [double](([int]$parts[0]*3600) + ([int]$parts[1]*60) + [int]$parts[2])
                } elseif ($parts.Count -eq 2) {
                    $durSec = [double](([int]$parts[0]*60) + [int]$parts[1])
                }
            }
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($item) | Out-Null
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($folder) | Out-Null
            [System.Runtime.Interopservices.Marshal]::ReleaseComObject($shell) | Out-Null
            [System.GC]::Collect()
            [System.GC]::WaitForPendingFinalizers()
        } catch {}
    }
    return $durSec
}

# ========== 格式化时长字符串 ==========
function Format-DurationString {
    param([double]$DurationSec)
    if ($null -eq $DurationSec -or $DurationSec -le 0) { return $null }
    $totalSec = [int]$DurationSec
    $h = [Math]::Floor($totalSec / 3600)
    $rem = $totalSec % 3600
    $m = [Math]::Floor($rem / 60)
    $s = $rem % 60
    $hh = if ($h -lt 10) { "0$h" } else { "$h" }
    $mm = if ($m -lt 10) { "0$m" } else { "$m" }
    $ss = if ($s -lt 10) { "0$s" } else { "$s" }
    if ($h -gt 0) { return "$hh`h${mm}m${ss}s" } else { return "${mm}m${ss}s" }
}

# ========== 并发 ffprobe ==========
function Get-AllDurations {
    param([array]$Files, [string]$TempDir, [int]$MaxConcurrent)

    $resultList = @()
    $totalCount = $Files.Count
    $doneCount  = 0
    $pending    = New-Object System.Collections.ArrayList
    foreach ($f in $Files) { [void]$pending.Add($f) }
    $running    = @()
    $timeoutSec = 5

    Write-Host; Write-Host
    Write-Host "  $(col_a_title ('正在并发读取视频元信息'))"
    Write-Host ""

    # v5.35：改为「额度内启动 + 轮询收集」的单循环模型
    #   旧实现用 Get-Process ffprobe 全机器计数当额度，
    #   同时有 QuickSync / 格式工厂 / Emby 转码时会被外部 ffprobe 占满配额而长时间空等；
    #   新实现只统计本函数自己启动、尚未退出的进程，彻底与外部进程解耦。
    while ($pending.Count -gt 0 -or $running.Count -gt 0) {

        # ---- ① 启动：在额度内尽量多启 ----
        while ($running.Count -lt $MaxConcurrent -and $pending.Count -gt 0) {
            $f = $pending[0]
            $pending.RemoveAt(0)
            $outFile = Join-Path $TempDir "$($f.BaseName)_$($f.LastWriteTime.Ticks).txt"
            $arg = '/c ffprobe.exe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "' + $f.FullName + '" > "' + $outFile + '" 2>nul'
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "cmd.exe"
            $psi.Arguments = $arg
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            try {
                $proc = [System.Diagnostics.Process]::Start($psi)
                $running += [PSCustomObject]@{ File = $f; Process = $proc; OutputPath = $outFile; StartAt = (Get-Date) }
            } catch {
                # 启动失败（例如 ffprobe 不在 PATH）直接走 Shell 兜底，不占额度
                $doneCount++
                $durSec = Get-VideoDuration -FilePath $f.FullName
                $resultList += [PSCustomObject]@{ FullName = $f.FullName; DurationSec = $durSec }
                Write-Host ("  [{0,2}/{1}] {2,3}% | " -f $doneCount, $totalCount, [math]::Round(($doneCount/$totalCount)*100,0)) -NoNewline
                if ($null -ne $durSec -and $durSec -gt 0) {
                    Write-Host "  $(col_a_success (("{0,-6}" -f (Format-DurationString -DurationSec $durSec))))" -NoNewline
                } else {
                    Write-Host "  $(col_a_error (("{0,-6}" -f 'ERROR')))" -NoNewline
                }
                Write-Host " | $($f.Name)"
            }
        }

        # ---- ② 收集：扫一遍已完成的 ----
        $still = @()
        foreach ($t in $running) {
            $exited = $false
            try { $exited = $t.Process.HasExited } catch { $exited = $true }

            if (-not $exited) {
                $elapsed = ((Get-Date) - $t.StartAt).TotalSeconds
                if ($elapsed -le $timeoutSec) {
                    $still += $t
                    continue
                }
                # 超时：杀掉并走 Shell 兜底
                try { $t.Process.Kill(); [void]$t.Process.WaitForExit(1000) } catch {}
                Write-Host ("`r" + (col_a_warning "[⚠  超时] ") + (col_a_text_muted $t.File.Name))
            }

            # 读 ffprobe 输出
            $durSec = $null
            if (Test-Path -LiteralPath $t.OutputPath) {
                try {
                    $content = Get-Content -LiteralPath $t.OutputPath -Raw -ErrorAction Stop
                    if ($content -match '^\s*[\d\.]+') { $durSec = [double]$content }
                } catch {}
            }
            if ($null -eq $durSec -or $durSec -le 0) {
                $durSec = Get-VideoDuration -FilePath $t.File.FullName
            }

            $resultList += [PSCustomObject]@{ FullName = $t.File.FullName; DurationSec = $durSec }
            $doneCount++
            $pct = [math]::Round(($doneCount / $totalCount) * 100, 0)
            Write-Host ("  [{0,2}/{1}] {2,3}% | " -f $doneCount, $totalCount, $pct) -NoNewline
            if ($null -ne $durSec -and $durSec -gt 0) {
                Write-Host "  $(col_a_success (("{0,-6}" -f (Format-DurationString -DurationSec $durSec))))" -NoNewline
            } else {
                Write-Host "  $(col_a_error (("{0,-6}" -f 'ERROR')))" -NoNewline
            }
            Write-Host " | $($t.File.Name)"
        }
        $running = $still

        if ($pending.Count -gt 0 -or $running.Count -gt 0) { Start-Sleep -Milliseconds 60 }
    }

    Write-Host ""
    Write-Host "  $(col_a_success ('[✓] 元信息读取全部完成。'))"
    Write-Host ""
    return $resultList
}

# v5.16：合并 v5.14/v5.15。最终两次预览表的列宽参数，列宽/截断变量化（原35/33->42/40），改这里一处全生效
$script:PreviewColWidth = 46
$script:PreviewMaxWidth = 44
$diffSep = sep_weak -Len ($script:PreviewColWidth * 2 + 18)

# ========== 主菜单（v5.1 四层结构：标题→分割线→选项行→操作指南）==========
while ($true) {
Clear-Screen
$script:baseCounters = @{}
$nfoActualRewriteCount = 0        # v5.34：每轮重置，防止无 nfo 差异时残留上一轮的值误触发二次预览
Write-Host ""

Write-Host "  $(col_a_title ('time_add.ps1 — 视频时长重命名工具'))"
Write-Host "  $(col_a_line (sep))"
Write-Host ""

# ---- 当前工作目录（与 tt.ps1 保持一致）：本模块所有 Get-ChildItem 均按 $PWD 处理
#      $PWD.ProviderPath 去掉 PowerShell provider 前缀（UNC 下不显示 ...FileSystem::）
#      超长路径按字符数保头保尾截断，避免折行挤爆菜单区
$cwdDisplay = $PWD.ProviderPath
if ($cwdDisplay.Length -gt 78) {
    $cwdDisplay = $cwdDisplay.Substring(0, 38) + '…' + $cwdDisplay.Substring($cwdDisplay.Length - 38)
}
Write-Host "  $(col_a_text_muted '处理目录：')$(col_a_text $cwdDisplay)"
Write-Host ""

Write-Host "  $(col_a_text_muted ('自动提取本文件夹下视频时长加入视频文件名内，支持加在不同位置'))"
Write-Host "  $(col_a_text_muted ('适配Emby生态，可选配图文件和nfo跟随改名、可选nfo内部改名替换'))"
Write-Host "  $(col_a_text_muted ('检测清理孤立nfo与图片，确保视频文件夹纯净，生成bak可自行删除'))"
Write-Host "  $(col_a_text_muted ('改名前提供完整预览，改名执行后提供一键撤销还原机会'))"

Write-Host ""
Write-Host "  $(col_a_text ('重命名模式：'))"
Write-Host "  $(col_a_line (sep_weak))"

$modeOpts = @(
    @{ Label = "[1]时间后置"; Value = "end" }
    @{ Label = "[2]时间前置"; Value = "begin" }
    @{ Label = "[3]仅时长命名"; Value = "only" }
    @{ Label = "[q/Esc]退出"; Value = "exit" }
)

# 仅调用一次：Prompt="" 走四层结构，Footer 自定义提示行（无多余空行）
$modeResult = Select-Horizontal -Options $modeOpts -Prompt "" -InitialIndex 0 `
    #-Footer "  [←/→]切换  [字母]直达  [Enter]确认  [q/Esc]退出"
if ($null -eq $modeResult) { exit 0 }

switch ($modeResult) {
    'end'   { $mode = 'end';   $modeName = '时长后置' }
    'begin'{ $mode = 'begin'; $modeName = '时长前置' }
    'only' { $mode = 'only';  $modeName = '仅时长命名' }
    'exit' { exit 0 }
}

# ======== Emby配图跟随选择（v5.0 横向菜单）========
$embyFollow = $false
$enablenfoTagEdit = $false

Write-Host; Write-Host


Write-Host "  $(col_a_title ('Emby/Jellyfin配图和nfo文件跟随处理开关'))"
Write-Host "  $(col_a_line (sep))"
Write-Host ""

Write-Host "  $(col_a_text_muted ('视频改名时可选配图与nfo同步重命名，确保Emby媒体库关联不丢失'))"
Write-Host "  $(col_a_text_muted ('配图包括且不限于poster/cover/thumb/fanart等常见Emby配图格式'))"
Write-Host "  $(col_a_text_muted ('打开开关后将进行孤立文件检测、同名附属文件同步修改、NFO内部改名'))"

Write-Host ""
Write-Host "  $(col_a_text ('是否跟随视频修改同步处理Emby/Jellyfin配图和nfo文件：'))"
Write-Host "  $(col_a_line (sep_weak))"

$embyOpts = @(
    @{ Label = "[y]开启跟随改名（推荐）"; Value = "on" }
    @{ Label = "[n]关闭跟随改名"; Value = "off" }
    @{ Label = "[q/Esc]重新开始"; Value = "restart" }
)

$embyResult = Select-Horizontal -Options $embyOpts -Prompt "" -InitialIndex 0 #-Footer "  [←/→]切换  [字母]直达  [Enter]确认  [q/Esc]退出"

# q/Esc 回本脚本第一级菜单（Clear-Screen 重来）；restart 同理
if ($null -eq $embyResult) { continue }
if ($embyResult -eq 'restart') { continue }

if ($embyResult -eq 'on') {
    $embyFollow = $true

    # v5.9：nfo内部改写开关已移除，改为视频改名预览后独立扫描差异再决定
    # $enablenfoTagEdit 保持 $false，后续由差异扫描结果动态赋值
} else {
    # Write-Host "  $(col_a_warning ('✅  已选择：关闭Emby配图跟随模式（仅处理视频）'))"
}

# ========== 配置 ==========
try {
    # v6.6：改用 [Environment]::ProcessorCount，PS5.1 / PS7 通用。
    #       原 Get-WmiObject 在 PS7 已移除（实测报"术语不会被识别"），
    #       会被 catch 吞掉并静默退化成 4 并发；Get-CimInstance 在部分环境需要更高权限，
    #       故直接取 .NET 原生属性，无权限要求、无 WMI 查询开销。
    $logicalCores = [Environment]::ProcessorCount
    $maxConcurrent = [Math]::Max(2, [Math]::Floor($logicalCores * 0.75))
} catch {
    $maxConcurrent = 4
}
# 视频/附属文件扩展名已移至 common.ps1
# v5.34：去掉尾部 \b，改用左侧 (?<!\d) —— 否则 "00m06s2" / "00m06s-2" 认不出已标记，会重复追加时长
$timeRegex = '(?<!\d)(\d{1,2}h)?\d{1,2}m\d{1,2}s'
$pureTimeNameRegex = '^(\d{1,2}h)?\d{1,2}m\d{1,2}s$'

# 附属文件白名单与 Test-ArtBaseName 已移至 common.ps1

# v5.14：统一长名截断函数（默认 maxWidth 33，适配统一列宽 35）
    # 参数：$name 文件名，$maxWidth 最大显示宽度（中文/全角算2，英文算1）
    # 返回：截断后文本，超宽时前12+…+后8+扩展名，未超宽原样返回
    function Format-TruncatedName {
        param([string]$name, [int]$maxWidth = $script:PreviewMaxWidth)
        if (-not $name) { return "" }
        $base = [System.IO.Path]::GetFileNameWithoutExtension($name)
        $ext  = [System.IO.Path]::GetExtension($name)
        # 完整名视觉宽
        $totalW = (Get-DisplayWidth $name)
        # 放得下：原样返回，不截断
        if ($totalW -le $maxWidth) { return $name }
        # 放不下：按视觉宽截断 base，预留 ext + "…"
        $extW = (Get-DisplayWidth $ext)
        $ellipW = (Get-DisplayWidth "…")
        $budget = $maxWidth - $extW - $ellipW
        if ($budget -lt 4) { $budget = 4 }
        $res = ""; $curW = 0
        foreach ($c in $base.ToCharArray()) {
            $cw = if ($c -gt 0x2E7F -or ($c -ge 0xFF00 -and $c -le 0xFFEF)) { 2 } else { 1 }
            if ($curW + $cw -gt $budget) { break }
            $res += $c; $curW += $cw
        }
        return $res + "…" + $ext
    }

    function Get-DisplayWidth {
        param([string]$txt)
        $w = 0
        foreach ($c in $txt.ToCharArray()) {
            $w += if ($c -gt 0x2E7F -or ($c -ge 0xFF00 -and $c -le 0xFFEF)) { 2 } else { 1 }
        }
        return $w
    }

    # v5.16：ColWidth/MaxWidth 默认走脚本级变量，调用处零硬编码
    function Format-TableRow {
        param(
            [int]$Index,
            [string]$OrigName,
            [string]$NewName,
            [string]$Op = "",
            [int]$ColWidth = $script:PreviewColWidth,
            [int]$MaxWidth = $script:PreviewMaxWidth
        )
        $idxStr = "{0,-3}" -f $Index
        $oName = Format-TruncatedName -name $OrigName -maxWidth $MaxWidth
        $nName = Format-TruncatedName -name $NewName -maxWidth $MaxWidth
        # 按视觉宽度精确补齐（中文算2列），解决PadRight字符数≠显示宽度导致顶列
        $oDisp = Get-DisplayWidth $oName
        $oPadCnt = $ColWidth - $oDisp
        if ($oPadCnt -lt 0) { $oPadCnt = 0 }
        $oPadded = $oName + (" " * $oPadCnt)
        $nDisp = Get-DisplayWidth $nName
        $nPadCnt = $ColWidth - $nDisp
        if ($nPadCnt -lt 0) { $nPadCnt = 0 }
        $nPadded = $nName + (" " * $nPadCnt)
        $row = "$idxStr$oPadded$nPadded$Op"
        return $row
    }

    function Show-PreviewHeader {
        param([int]$ColWidth = $script:PreviewColWidth)
        # ---- 基于列宽自动推算（差值来自实测校准） ----
        $oldVisualWidth = $ColWidth - 6   # 原文件名表头视觉宽（正文截断后比ColWidth少6）
        $newPos = $ColWidth - 1          # 新文件名表头起始位置
        $opPos  = $ColWidth * 2 - 5        # 操作表头起始位置
        # --------------------------------------------
        
        # 前缀："  " + 序号(3) — 与正文 Format-TableRow 一致
        $hdr = "  " + ("{0,-3}" -f "序号")
        
        # 原文件名表头：复用正文视觉宽填充逻辑（Get-DisplayWidth）
        $oldHdr = "原文件名"
        $oldDispW = Get-DisplayWidth $oldHdr
        $oldPad = $oldVisualWidth - $oldDispW
        if ($oldPad -lt 0) { $oldPad = 0 }
        $hdr += $oldHdr + (" " * $oldPad)
        
        # 新文件名表头：复用正文视觉宽填充逻辑
        $newHdr = "新文件名"
        $padNew = $newPos - $hdr.Length
        if ($padNew -lt 0) { $padNew = 0 }
        $hdr += (" " * $padNew) + $newHdr
        
        # 操作表头：绝对定位
        $opHdr = "操作"
        $padOp = $opPos - $hdr.Length
        if ($padOp -lt 0) { $padOp = 0 }
        $hdr += (" " * $padOp) + $opHdr
        
        Write-Host $hdr
        Write-Host "  $(col_a_line $diffSep)"
    }

# ========== 扫描视频 ==========
$files = Get-ChildItem -File |
    Where-Object { $videoExts -contains $_.Extension.TrimStart('.').ToLower() } |
    Sort-Object Name

if (-not $files) {
    Write-Host "  $(col_a_warning ('`n⚠  当前目录没有找到支持的视频文件。'))"
    Wait-AnyKey
    exit 0
}

$tempDir = Join-Path $env:TEMP "time_add_tmp_$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir | Out-Null
$undoList       = @()
$nfoModifyLog   = @()
$nfoBackupList  = @()   # v4.1：必须是 @() 空数组，不能是 $null 或 {}
$orphannfoList  = @()   # v5.9：孤立 nfo 还原列表，必须初始化
$orphanImageList = @()  # v5.9：孤立图片还原列表，必须初始化
$videoBaseMap   = @{}
$nfoDiffList    = @()   # v5.9：nfo 差异扫描结果

# ========== 外层 try 包裹全部业务逻辑 ==========
try {

    # ========== v4.2：孤立 nfo/图片检测（对齐 nfo.ps1 v3.7） ==========
    if ($embyFollow) {
        Write-Host; Write-Host

        # 收集所有视频文件名（不含后缀），用于配对判断
        $allVideoBases = $files | ForEach-Object { $_.BaseName }

        # --- 孤立 nfo 检测 ---
        $allnfoFiles = Get-ChildItem -File -Filter "*.nfo"
        $orphannfos = @()
        
        foreach ($nfo in $allnfoFiles) {
            $nfoBase = $nfo.BaseName
            # 排除附属/元数据 nfo（poster.nfo / movie.nfo / AAA-poster.nfo）
            if (Test-ArtBaseName -BaseName $nfoBase) { continue }
            # 排除已配对的（有同名视频）
            if ($allVideoBases -contains $nfoBase) { continue }
            $orphannfos += $nfo
        }        

        # --- 孤立图片检测（无对应视频的配图） ---
        $imageExts = @('.jpg','.jpeg','.png','.webp')
        $allImageFiles = Get-ChildItem -File | Where-Object { $imageExts -contains $_.Extension.ToLower() }
        $orphanImages = @()

        foreach ($img in $allImageFiles) {
            $imgBase = $img.BaseName
            # 排除附属图片（poster.jpg / cover.png / AAA-poster.jpg）
            if (Test-ArtBaseName -BaseName $imgBase) { continue }
            # 排除已配对的（BaseName 与某视频一致）
            if ($allVideoBases -contains $imgBase) { continue }
            $orphanImages += $img
        }        

        # 只有存在孤立文件时才显示红框提示，无则全跳过
        $totalOrphan = $orphannfos.Count + $orphanImages.Count
        if ($totalOrphan -gt 0) {
            $bw = 36 # 总内宽（含边框）
            $hLine = "─" * ($bw - 2)
            Write-Host "  $(col_a_error ('┌' + $hLine + '┐'))"
            Write-Host "  $(col_a_error ('│   发现孤立文件，是否清理删除？   │'))" # 手动空格最稳
            Write-Host "  $(col_a_error ('└' + $hLine + '┘'))"
        }

        if ($orphannfos.Count -eq 0) {
            Write-Host "  $(col_a_success '✅  未发现孤立nfo文件。')"
        }
        else {
            Write-Host ""
            Write-Host ("  " + (col_a_warning "⚠  发现 $($orphannfos.Count) 个孤立nfo（无同名视频）："))
            Write-Host ""
            foreach ($onfo in $orphannfos) {
                Write-Host "  📄 " -NoNewline
                Write-Host $onfo.FullName
            }
            Write-Host ""
            Write-Host "  $(col_a_text ('孤立nfo清理：'))"
            Write-Host "  $(col_a_line (sep_weak))"

            $orphanCleanOpts = @(
                @{ Label = "[d]删除并备份"; Value = "clean" }
                @{ Label = "[s]跳过"; Value = "skip" }
                @{ Label = "[q/Esc]重新开始"; Value = "restart" }
            )

            $orphanCleanResult = Select-Horizontal -Options $orphanCleanOpts -Prompt "" -InitialIndex 1
            # q/Esc 回本脚本第一级菜单（Clear-Screen 重来）；restart 同理
            if ($null -eq $orphanCleanResult) { continue }
            if ($orphanCleanResult -eq 'restart') { continue }

            if ($orphanCleanResult -eq 'clean') {
                Write-Host ""
                foreach ($onfo in $orphannfos) {
                    try {
                        $bakPath = $onfo.FullName + ".bak"
                        [System.IO.File]::Copy($onfo.FullName, $bakPath, $true)
                        [System.IO.File]::Delete($onfo.FullName)
                        $orphannfoList += [PSCustomObject]@{
                            FilePath = $onfo.FullName
                            BakPath  = $bakPath
                        }
                        Write-Host ("  " + (col_a_success "🗑 $($onfo.Name) | 已删除（备份：$bakPath）"))
                    }
                    catch {
                        Write-Host ("  " + (col_a_error "❌ $($onfo.Name) | 清理失败：$_"))
                    }
                }
                Write-Host ""
                Write-Host ("  " + (col_a_success "✅  已清理 $($orphannfoList.Count) 个孤立nfo（均生成.bak备份）"))
            }
            else {
                # Write-Host "  $(col_a_text_gray '⚪  已跳过孤立nfo清理。')"
            }
        }

        if ($orphanImages.Count -eq 0) {
            Write-Host "  $(col_a_success '✅  未发现孤立图片文件。')"
        }
        else {
            Write-Host ""
            Write-Host ("  " + (col_a_warning "⚠  发现 $($orphanImages.Count) 个孤立图片（无同名视频）："))
            Write-Host ""
            foreach ($oimg in $orphanImages) {
                Write-Host "  $(col_a_warning '🖼  ')" -NoNewline
                Write-Host "$(col_a_warning $oimg.FullName)"
            }
            Write-Host ""
            Write-Host "  $(col_a_text ('孤立图片清理：'))"
            Write-Host "  $(col_a_line (sep_weak))"

            $imgCleanOpts = @(
                @{ Label = "[d]删除并备份"; Value = "clean" }
                @{ Label = "[s]跳过"; Value = "skip" }
                @{ Label = "[q/Esc]重新开始"; Value = "restart" }
            )

            $imgCleanResult = Select-Horizontal -Options $imgCleanOpts -Prompt "" -InitialIndex 1

            # q/Esc 回本脚本第一级菜单（Clear-Screen 重来）；restart 同理
            if ($null -eq $imgCleanResult) { continue }
            if ($imgCleanResult -eq 'restart') { continue }

            if ($imgCleanResult -eq 'clean') {
                Write-Host ""
                foreach ($oimg in $orphanImages) {
                    try {
                        $bakPath = $oimg.FullName + ".bak"
                        [System.IO.File]::Copy($oimg.FullName, $bakPath, $true)
                        [System.IO.File]::Delete($oimg.FullName)
                        $orphanImageList += [PSCustomObject]@{
                            FilePath = $oimg.FullName
                            BakPath  = $bakPath
                        }
                        Write-Host ("  " + (col_a_success "🗑 $($oimg.Name) | 已删除（备份：$bakPath）"))
                    }
                    catch {
                        Write-Host ("  " + (col_a_error "❌ $($oimg.Name) | 清理失败：$_"))
                    }
                }
                Write-Host ""
                Write-Host ("  " + (col_a_success "✅  已清理 $($orphanImageList.Count) 个孤立图片（均生成.bak备份）"))
            }
            else {
                # Write-Host "  $(col_a_text_gray '⚪  已跳过孤立图片清理。')"
            }
        }
    }

    # ========== 并发读取时长 ==========
    $resultList = Get-AllDurations -Files $files -TempDir $tempDir -MaxConcurrent $maxConcurrent

    # ========== v1.4：高亮显示已标记文件 ==========
    $markedFileNames = @()
    foreach ($f in $files) {
        if ($f.BaseName -match $timeRegex) {
            $markedFileNames += $f.Name
        }
    }
    if ($markedFileNames.Count -gt 0) {
        Write-Host "  $(col_a_warning ("⚠  检测到 $($markedFileNames.Count) 个文件文件名已包含时间标记："))"
        foreach ($mn in $markedFileNames) {
            Write-Host "  $(col_a_warning $mn)"
        }
        # Write-Host "  $(col_a_text_muted ('（后续将进入 n重处理 / s逐个 / 其他键跳过 策略）'))"
    } else {
        Write-Host "  $(col_a_text_muted ('✅  未检测到已包含时间标记的文件。'))"
    }

    # ========== 已标记文件策略（v5.0 横向菜单）==========
    $hasMarkFiles = $files | Where-Object { $_.BaseName -match $timeRegex }
    $forceRewriteAll = $false
    $perFileSelect = $false
    if ($hasMarkFiles.Count -gt 0) {
        $markOpts = @(
            @{ Label = "[1]全部跳过（推荐）"; Value = "skip" }
            @{ Label = "[2]全部重处理"; Value = "rewrite" }
            @{ Label = "[3]逐个确认"; Value = "perfile" }
            @{ Label = "[q/Esc]重新开始"; Value = "restart" }
        )

        Write-Host ""
        Write-Host "  $(col_a_text ('已包含时间标记的文件怎么处理：'))"
        Write-Host "  $(col_a_text ('（推荐跳过，但如果原标记时间有误，此处可以重处理）'))"
        Write-Host "  $(col_a_line (sep_weak))"

        $markResult = Select-Horizontal -Options $markOpts -Prompt "" -InitialIndex 0

        # q/Esc 回本脚本第一级菜单（Clear-Screen 重来）；restart 同理
        if ($null -eq $markResult) { continue } 
        if ($markResult -eq 'restart') { continue } 

        switch ($markResult) {
            'rewrite' { 
                $forceRewriteAll = $true
                # Write-Host "  $(col_a_warning ('☑ 策略：全部强制重处理'))" 
            }
            'perfile'{ 
                $perFileSelect = $true
                # Write-Host "  $(col_a_warning ('☑ 策略：逐文件询问重处理'))" 
            }
            default   {
                # Write-Host "  $(col_a_success ('☑ 策略：有时间标记的全部跳过'))" 
            }
        }
    }

    # ========== 生成预览表 ==========
    $previewList = @()
    $usedNames = New-Object System.Collections.Generic.HashSet[string]
    $idx = 1

    foreach ($f in $files) {
        $res = $resultList | Where-Object { $_.FullName -eq $f.FullName }
        $origBase = $f.BaseName
        $basename = $origBase
        $ext = $f.Extension
        $hasTimeMark = $basename -match $timeRegex

        if ($mode -eq 'only' -and $origBase -match $pureTimeNameRegex -and
            -not $forceRewriteAll -and -not $perFileSelect) {
            $previewList += [PSCustomObject]@{
                序号=$idx; 原文件名=$f.Name; 新文件名=$f.Name; 操作='[跳过]'
                FullName=$f.FullName; DoRename=$false; Status='跳过'; NewBase=$origBase; nfoNewTitle=$null
            }
            $idx++; continue
        }

        if ($hasTimeMark) {
            if ($forceRewriteAll) {
                $basename = $basename -replace $timeRegex, ''
                $basename = $basename.TrimEnd()
            } elseif ($perFileSelect) {
                Write-Host ""
                Write-Host "  $(col_a_warning ("检测到已标记文件：$($f.Name)"))"
                Write-Host ""
                Write-Host "  $(col_a_text ('请选择操作：'))"
                Write-Host "  $(col_a_line (sep_weak))"

                $perFileOpts = @(
                    @{ Label = "[r]重处理，替换旧时间"; Value = "reprocess" }
                    @{ Label = "[s]跳过此文件"; Value = "skip" }
                    @{ Label = "[q/Esc]重新开始"; Value = "restart" }

                )

                $perFileResult = Select-Horizontal -Options $perFileOpts -Prompt "" -InitialIndex 1

                # q/Esc 回本脚本第一级菜单（Clear-Screen 重来）；restart 同理
                if ($null -eq $perFileResult) { continue } 
                if ($perFileResult -eq 'restart') { continue } 

                if ($perFileResult -eq 'reprocess') {
                    $basename = $basename -replace $timeRegex, ''
                    $basename = $basename.TrimEnd()
                } else {
                    $previewList += [PSCustomObject]@{
                        序号=$idx; 原文件名=$f.Name; 新文件名=$f.Name; 操作='[跳过]'
                        FullName=$f.FullName; DoRename=$false; Status='跳过'; NewBase=$origBase; nfoNewTitle=$null
                    }
                    $idx++; continue
                }
            } else {
                $previewList += [PSCustomObject]@{
                    序号=$idx; 原文件名=$f.Name; 新文件名=$f.Name; 操作='[跳过]'
                    FullName=$f.FullName; DoRename=$false; Status='跳过'; NewBase=$origBase; nfoNewTitle=$null
                }
                $idx++; continue
            }
        }

        $durSec = $res.DurationSec
        if ($null -eq $durSec -or $durSec -le 0) {
            $previewList += [PSCustomObject]@{
                序号=$idx; 原文件名=$f.Name; 新文件名=$f.Name; 操作='[跳过(无时长)]'
                FullName=$f.FullName; DoRename=$false; Status='跳过'; NewBase=$origBase; nfoNewTitle=$null
            }
            $idx++; continue
        }
        $timeStr = Format-DurationString -DurationSec $durSec

        if ($mode -eq 'end') {
            $newBase = "$basename $timeStr"
        } elseif ($mode -eq 'begin') {
            $newBase = "$timeStr $basename"
        } else {
            $newBase = $timeStr
        }
        $newFullName = "$newBase$ext"

        $finalNewFullName = $newFullName
        $finalNewBase = $newBase

        if ($mode -eq 'only') {
            if (-not $script:baseCounters) { $script:baseCounters = @{} }
            if (-not $script:baseCounters.ContainsKey($newBase)) {
                $script:baseCounters[$newBase] = 2
            }
            $candidate = "$newBase$ext"
            # v5.24-fix：Test-Path 排除自身（二次重命名时旧文件即将被替换，不算冲突）
            $isSelf = ($candidate -eq $f.Name)
            $candidatePath = Join-Path $f.Directory.FullName $candidate
            $pathOccupied = $false
            if (-not $isSelf) {
                $pathOccupied = Test-Path -LiteralPath $candidatePath
            }
            if ((-not $pathOccupied) -and (-not $usedNames.Contains($candidate))) {
                $null = $usedNames.Add($candidate)
                $finalNewFullName = $candidate
                $finalNewBase = $newBase
            } else {
                $counter = $script:baseCounters[$newBase]
                do {
                    $candidate = "$newBase$counter$ext"
                    $candidatePath = Join-Path $f.Directory.FullName $candidate
                    # v5.24-fix：do-while 中也排除自身
                    $isSelf = ($candidate -eq $f.Name)
                    $pathOccupied = $false
                    if (-not $isSelf) {
                        $pathOccupied = Test-Path -LiteralPath $candidatePath
                    }
                    $counter++
                } while ($pathOccupied -or ($usedNames.Contains($candidate)))
                $script:baseCounters[$newBase] = $counter
                $null = $usedNames.Add($candidate)
                $finalNewFullName = $candidate
                $finalNewBase = [System.IO.Path]::GetFileNameWithoutExtension($candidate)
            }
        } else {
            $finalNewFullName = "$newBase$ext"
            $finalNewBase = $newBase
        }
        # v5.29：新旧名一致时标记 SKIP，执行段直接跳过（避免无意义 Rename-Item）
        $isNameUnchanged = ($finalNewFullName -eq $f.Name)
        $videoBaseMap[$origBase] = $finalNewBase
        $null = $usedNames.Add($finalNewFullName)
        if ($isNameUnchanged) {
            $previewList += [PSCustomObject]@{
                序号=$idx; 原文件名=$f.Name; 新文件名=$f.Name; 操作='[SKIP]'
                FullName=$f.FullName; DoRename=$false; Status='跳过'; NewBase=$origBase; nfoNewTitle=$null
            }
        } else {
            $previewList += [PSCustomObject]@{
                序号=$idx; 原文件名=$f.Name; 新文件名=$finalNewFullName; 操作='[RENAME]'
                FullName=$f.FullName; DoRename=$true; Status='RENAME'; NewBase=$finalNewBase; nfoNewTitle=$null
            }
        }
        $idx++
    }

    # ========== 附属配图/nfo ==========
    if ($embyFollow) {
        $allFileObjs = Get-ChildItem -File .
        foreach ($origVidBase in $videoBaseMap.Keys) {
            $targetNewBase = $videoBaseMap[$origVidBase]
            $artPatterns = @("^$([regex]::Escape($origVidBase))$")
            foreach ($stem in $artStemList) {
                $artPatterns += "^$([regex]::Escape($origVidBase))\-$stem\d*$"
            }
            foreach ($f in $allFileObjs) {
                $isMatchPattern = $false
                foreach ($p in $artPatterns) { if ($f.BaseName -match $p) { $isMatchPattern = $true; break } }
                if (-not $isMatchPattern) { continue }
                if ($artExts -notcontains $f.Extension.TrimStart('.').ToLower()) { continue }
                $newArtBase = $f.BaseName.Replace($origVidBase, $targetNewBase)
                $newArtName = $newArtBase + $f.Extension
                $nfoNewTitle = $null  # v5.9：不再顺带赋值，nfo内部标签由后续差异扫描独立决策
                $previewList += [PSCustomObject]@{
                    序号=$idx; 原文件名=$f.Name; 新文件名=$newArtName; 操作='[RENAME-EXT]'
                    FullName=$f.FullName; DoRename=$true; Status='RENAME-EXT'; NewBase=$newArtBase; nfoNewTitle=$nfoNewTitle
                    IsConflict=$false
                }
                $idx++
            }
        }
    }

    # ========== 预览表格 ==========
    Write-Host; Write-Host


    Write-Host "  $(col_a_title ('重命名预览 (time_add - ' + $modeName + ')'))"
    Write-Host "  $(col_a_line (sep_weak))"
    if ($embyFollow) {
        $tip = "Emby配图跟随：✅  开启"
    } else { $tip = "Emby配图跟随：❌  关闭" }
    Write-Host "  $(col_a_text ('[' + $tip + ']'))"
    Write-Host ""
    # v5.16：表头无参，走全局变量
    Show-PreviewHeader
    foreach ($item in $previewList) {
        $isMarked = ($item.原文件名 -match $timeRegex)
        # 构建操作列文本
        $opText = ""
        $skipRow = $false
        if ($item.Status -eq "RENAME") {
            # v5.34：$global:MarkedStrategy 从未赋值，原条件恒为 $false，等价表达式直接写出
            $isSkipMode = (-not $forceRewriteAll -and -not $perFileSelect)
            if ($isMarked -and $isSkipMode) {
                $opText = "$(col_a_text_muted '[SKIP]')"
                $skipRow = $true
            }
            elseif ($isMarked) {
                $opText = "$(col_a_warning '[已标记-重处理]')"
            }
            # v5.29：名实一致时标 SKIP（仅标记，不强制 skipRow）
            elseif ($item.新文件名 -eq $item.原文件名) {
                $opText = "$(col_a_text_muted '[SKIP]')"
            }
            else {
                $opText = "$(col_a_success '[RENAME]')"
            }
            if (-not $skipRow -and $embyFollow -and $null -ne $item.nfoNewTitle) {
                if ($item.OldTitle -ne $null -and $item.OldTitle.Trim() -eq $item.nfoNewTitle.Trim()) {
                    $opText += "  $(col_c_grass_green '[nfo]')"
                }
                elseif ($item.OldTitle -eq $null) {
                    $opText += "  $(col_c_dark_gray '[nfo]')"
                }
                else {
                    $opText += "  $(col_c_light_yellow '[nfo]')"
                }
            }
        }
        elseif ($item.Status -eq 'RENAME-EXT') {
            $opText = "$(col_a_success '[RENAME-EXT]')"
        }
        else {
            if ($item.操作 -eq '[跳过]') {
                # v5.12：第二列空占位，第三列显 [SKIP]
                $opText = "$(col_a_text_muted '[SKIP]')"
            }
        }
        # 修复：仅兜底锁定 [SKIP] 文本防空白，不强制 $skipRow，保留原基线路由
        if ($item.新文件名 -eq $item.原文件名) {
            $opText = "$(col_a_text_muted '[SKIP]')"
        }
        if ($skipRow) {
            # 已标记跳过：仅输出序号+空原列+空新列+[SKIP]
            Write-Host ("{0,-3} {1,-35} {2,-35} {3}" -f $item.序号, "", "", $opText)
        }
        else {
            $row = Format-TableRow -Index $item.序号 -OrigName $item.原文件名 -NewName $item.新文件名 -Op $opText
            Write-Host "  $row"
        }
    }

    Write-Host "  $(col_a_line $diffSep)"
    $renameCount = ($previewList | Where-Object { $_.DoRename -eq $true }).Count

    if ($renameCount -eq 0) {
        Write-Host "  $(col_a_warning ('⚠  没有需要执行改名的文件。'))"
        Wait-AnyKey
        exit 0
    }
    # ========== v5.9：nfo 内部标签差异扫描 ==========
    $nfoDiffList = @()
    if ($embyFollow) {
        Write-Host; Write-Host

        Write-Host "  $(col_a_title ('nfo内部标签差异检测'))"
        Write-Host "  $(col_a_line (sep))"

        $allnfoFiles = Get-ChildItem -File -Filter "*.nfo"
        $nfoDiffCount = 0
        $nfoConsistentCount = 0

        foreach ($nfo in $allnfoFiles) {
            $nfoBase = $nfo.BaseName
            # 与孤立检测共用白名单：movie.nfo / poster.nfo 不得成为改写目标
            if (Test-ArtBaseName -BaseName $nfoBase) { continue }
            # 读取 <title>
            $innerTitle = $null

            try {
                $nfoText = [System.IO.File]::ReadAllText($nfo.FullName, [System.Text.Encoding]::UTF8)
                if ($nfoText -match '<title\b[^>]*>(.*?)</title>') {
                    $innerTitle = $matches[1].Trim()
                }
            } catch {}

            # v5.19-fix：对比基准改为预览目标名（NewBase），非原名 nfoBase
            $targetBase = $nfoBase
            $matchedPreviewItem = $previewList | Where-Object { $_.原文件名 -eq $nfo.Name } | Select-Object -First 1
            if ($matchedPreviewItem -and -not [string]::IsNullOrEmpty($matchedPreviewItem.NewBase)) {
                $targetBase = $matchedPreviewItem.NewBase
            }

            $isConsistent = ($null -ne $innerTitle -and $innerTitle -eq $targetBase)

            if (-not $isConsistent) {
                $nfoDiffCount++
                # 差异页左侧显示目标名（预览一已定），不再显示旧原名
                $displayName = if ($targetBase -ne $nfoBase) { "$($targetBase)$([System.IO.Path]::GetExtension($nfo.Name))" } else { $nfo.Name }
                $nfoDiffList += [PSCustomObject]@{
                    nfoFile     = $displayName      # 左侧展示用目标名
                    nfoPath     = $nfo.FullName
                    nfoBase     = $targetBase       # 基名存目标基名（供后续改写/预览）
                    innerTitle  = $innerTitle
                    newTitle    = $targetBase       # 改写目标：与目标文件名一致
                    Status      = 'DIFF'
                }
            } else {
                $nfoConsistentCount++
            }
        }

        if ($nfoDiffCount -eq 0) {
            Write-Host "  $(col_a_success ('✅  所有 nfo 内部 <title> 均与外部文件名一致，无需改写。'))"
            Write-Host "  $(col_a_text_muted ("（共检查 $($nfoConsistentCount) 个 nfo，全部一致）"))"
        } else {
            # --- 差异表（复用预览表列宽与对齐公式，修正正文宽度） ---
            Write-Host ""
            Write-Host "  $(col_a_warning ("⚠  发现 $nfoDiffCount 个 nfo 内部 <title> 与外部文件名不一致："))"
            Write-Host ""

            $ColWidth = $script:PreviewColWidth
            # v5.35：列起点按正文实际布局推算（视觉列，0 基）
            #   正文行 = "  " + 序号(3) + 列1($ColWidth) + 列2($ColWidth) + 2空格 + 状态
            #   旧值 $ColWidth*2-5 = 99 小于正文宽度 109，导致状态列被钳成 0 间隔、表头错 3 列
            $col2Pos   = 5 + $ColWidth                # 57：第二列起点
            $statusPos = $col2Pos + $ColWidth + 2     # 111：状态列起点（留 2 空格间隔）
            # 打印动态分隔线长度（对齐表头）
            Write-Host "  $(col_a_line $diffSep)"

            # 表头：全程按视觉宽度推进（Get-DisplayWidth），不再混用 .Length
            $diffHdr = "  " + "序号"                   # 视觉宽 6（"序号"占 4 列）
            $col1 = "nfo文件名"
            $pad1 = $col2Pos - (Get-DisplayWidth $diffHdr) - (Get-DisplayWidth $col1)
            if ($pad1 -lt 0) { $pad1 = 0 }
            $diffHdr += $col1 + (" " * $pad1)

            $col2 = "内部<title>"
            $pad2 = $statusPos - (Get-DisplayWidth $diffHdr) - (Get-DisplayWidth $col2)
            if ($pad2 -lt 0) { $pad2 = 0 }
            $diffHdr += $col2 + (" " * $pad2)

            $diffHdr += "状态"

            Write-Host "$diffHdr"
            # v5.30-fix：差异表序号计数器初始化，防止首次运行 $null++ 报错
            $diffIdx = 0
            foreach ($d in $nfoDiffList) {
                $dispName = Format-TruncatedName -name $d.nfoFile -maxWidth ($ColWidth - 6)
                $diffIdx++
                $idxStr ="  {0,-3}" -f $diffIdx
                $rowPrefix = $idxStr
                
                $oDisp = Get-DisplayWidth $dispName
                $oPadCnt = $ColWidth - $oDisp
                if ($oPadCnt -lt 0) { $oPadCnt = 0 }
                $col1Body = $dispName + (" " * $oPadCnt)
                
                $rawTitle = if ($null -eq $d.innerTitle) { "[无标签]" } else { $d.innerTitle }
                $dispTitle = Format-TruncatedName -name $rawTitle -maxWidth ($ColWidth - 5)
                $nPadCnt = $ColWidth - (Get-DisplayWidth $dispTitle)
                if ($nPadCnt -lt 0) { $nPadCnt = 0 }
                $col2Body = $dispTitle + (" " * $nPadCnt)
                
                $rowBody = $rowPrefix + $col1Body + $col2Body
                $padStatus2 = $statusPos - (Get-DisplayWidth $rowBody)
                if ($padStatus2 -lt 0) { $padStatus2 = 0 }
                
                $statusText = "$(col_a_warning '[不一致]')"
                $finalLine = $rowBody + (" " * $padStatus2) + $statusText
                Write-Host $finalLine
            }
            Write-Host "  $(col_a_line ($diffSep))"
            Write-Host ""
            Write-Host "  $(col_a_text_muted ("一致的 nfo：$nfoConsistentCount 个（跳过）"))"
            Write-Host ""

            # --- 用户选择 ---
            Write-Host "  $(col_a_text ('nfo内部标签改写选项：'))"
            Write-Host "  $(col_a_line (sep_weak))"

            $nfoDiffOpts = @(
                @{ Label = "[a]全部改写"; Value = "all" }
                @{ Label = "[p]逐个确认"; Value = "perfile" }
                @{ Label = "[s]全部跳过"; Value = "skip" }
                @{ Label = "[q/Esc]重新开始"; Value = "restart" }
            )

            # v5.18：实际改写计数器，用于二次预览守卫
            $nfoActualRewriteCount = 0

            $nfoDiffResult = Select-Horizontal -Options $nfoDiffOpts -Prompt "" -InitialIndex 0
            # q/Esc 回本脚本第一级菜单（Clear-Screen 重来）；restart 同理
            if ($null -eq $nfoDiffResult) { continue }
            if ($nfoDiffResult -eq 'restart') { continue }
            switch ($nfoDiffResult) {
                'all' {
                    $enablenfoTagEdit = $true
                    $nfoActualRewriteCount = 0
                    # v5.33：回归基线，nfo改写仅看内部title不一致，不误关联视频改名状态
                    foreach ($d in $nfoDiffList) {
                        $nfoActualRewriteCount++
                        $previewList += [PSCustomObject]@{
                            序号       = $idx
                            原文件名   = $d.nfoFile
                            新文件名   = $d.nfoFile
                            操作       = '[TAB-SYNC]'
                            FullName   = $d.nfoPath
                            DoRename   = $false
                            Status     = 'TAB-SYNC'
                            NewBase    = $d.nfoBase
                            nfoNewTitle = $d.newTitle
                        }
                        $idx++
                    }
                    Write-Host ""
                    Write-Host "  $(col_a_success ("✅  已标记 $nfoActualRewriteCount 个 nfo 待改写内部标签（全部改写）"))"
                }
                'perfile' {
                    $enablenfoTagEdit = $true
                    $confirmedCount = 0
                    foreach ($d in $nfoDiffList) {
                        Write-Host ""
                        Write-Host "  $(col_a_warning ("nfo：$($d.nfoFile)"))"
                        Write-Host "  $(col_a_text_muted ("内部 <title>：'$($d.innerTitle)'"))"
                        Write-Host "  $(col_a_text_muted ("目标改写为：'$($d.newTitle)'"))"
                        Write-Host ""
                        Write-Host "  $(col_a_text ('是否改写此 nfo 内部标签：'))"
                        Write-Host "  $(col_a_line (sep_weak))"

                        $perNfoOpts = @(
                            @{ Label = "[y]改写"; Value = "yes" }
                            @{ Label = "[n]跳过"; Value = "no" }
                            @{ Label = "[q/Esc]重新开始"; Value = "restart" }
                        )

                        $perNfoResult = Select-Horizontal -Options $perNfoOpts -Prompt "" -InitialIndex 1
                        # q/Esc 回本脚本第一级菜单（Clear-Screen 重来）；restart 同理
                        if ($null -eq $perNfoResult) { continue }
                        if ($perNfoResult -eq 'restart') { continue }

                        if ($perNfoResult -eq 'yes') {
                            $nfoActualRewriteCount++
                            $previewList += [PSCustomObject]@{
                                序号       = $idx
                                原文件名   = $d.nfoFile
                                新文件名   = $d.nfoFile
                                操作       = '[TAB-SYNC]'
                                FullName   = $d.nfoPath
                                DoRename   = $false
                                Status     = 'TAB-SYNC'
                                NewBase    = $d.nfoBase
                                nfoNewTitle = $d.newTitle
                            }
                            $idx++
                            $confirmedCount++
                        }
                    }
                    Write-Host ""
                    Write-Host "  $(col_a_success ("✅  已标记 $confirmedCount 个 nfo 待改写内部标签（逐个确认）"))"
                }
                'skip' {
                    $enablenfoTagEdit = $false
                    $nfoActualRewriteCount = 0
                    Write-Host ""
                    Write-Host "  $(col_a_text_muted ('⚪  已跳过 nfo 内部标签改写。'))"
                }
            }
        }
    }

    # ========== 最终执行预览重绘（v5.18 动态标题 + 计数器守卫）==========
    # 仅当存在实际 nfo 改写项时才展示二次预览，无不一致则跳过进最终提问
    if ($nfoActualRewriteCount -gt 0) {
        $titleSuffix = '（含 nfo 标签改写项）'
        Write-Host ""
        Write-Host "  $(col_a_title ('最终执行预览' + $titleSuffix))"
        Write-Host "  $(col_a_line $diffSep)"
        # v5.16：表头无参，走全局变量
        Show-PreviewHeader

        $finalIdx = 1
        foreach ($item in $previewList) {
            # v5.36：过滤 RENAME-EXT / SKIP 的空跑项（原名=新名），防止 00m34s2.nfo 幽灵显示
            if (($item.Status -eq 'RENAME-EXT' -or $item.Status -eq 'SKIP') -and $item.原文件名 -eq $item.新文件名) {
                continue
            }
            
            $opText = ""
            if ($item.Status -eq 'TAB-SYNC') {
                $opText = "$(col_a_warning '[TAB-SYNC]')"
            }
            elseif ($item.Status -eq 'RENAME-EXT') {
                $opText = "$(col_a_success '[RENAME-EXT]')"
            }
            else {
                $opText = if ($item.DoRename) { "$(col_a_success '[RENAME]')" } else { "$(col_a_text_muted '[SKIP]')" }
            }
            # v5.19-fix：TAB-SYNC 项显示目标名而非原名，与第一次预览对齐
            $displayNewName = $item.新文件名
            if ($item.Status -eq 'TAB-SYNC' -and -not [string]::IsNullOrEmpty($item.NewBase)) {
                $displayNewName = "$($item.NewBase)$([System.IO.Path]::GetExtension($item.原文件名))"
            }
            $row = Format-TableRow -Index $finalIdx -OrigName $item.原文件名 -NewName $displayNewName -Op $opText
            Write-Host "  $row"
            $finalIdx++
        }
        Write-Host "  $(col_a_line $diffSep)"
        # 表尾提示（已进入改写块，必然含改写项）
        Write-Host "  $(col_a_warning ('* 含 nfo 内部标签改写项，执行时将同步覆盖 <title>/<sorttitle>'))"
    }

    # ========== 最终确认执行（v5.0 横向菜单）==========
    $timeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
    Write-Host ""
    Write-Host ""
    Write-Host "  $(col_a_title('开始按上述选择和预览执行重命名'))"
    Write-Host "  $(col_a_warning('⚠️ 即将真实写入！随后仍可还原文件名/回滚nfo(.BAK)'))"
    Write-Host "  $(col_a_line (sep_weak))"

    $execOpts = @(
        @{ Label = "[y]执行重命名"; Value = "exec" }
        @{ Label = "[n]仅导出映射txt备用 (不改名)"; Value = "export" }
        @{ Label = "[q/Esc]重新开始"; Value = "restart" }
    )

    $execResult = Select-Horizontal -Options $execOpts -Prompt "" -InitialIndex 0

    # q/Esc 回本脚本第一级菜单（Clear-Screen 重来）；restart 同理
    if ($null -eq $execResult) { continue }
    if ($execResult -eq 'restart') { continue }
    # 此后仅剩 'export' 或 'exec'，不再重复判断 restart
    Write-Host ""

    if ($execResult -eq 'export') {
        $backupFile = Join-Path $PWD.Path "rename_map_$timeStamp.txt"
        $lines = @("# 仅映射（未执行改名）", "# 原名`t新名")
        foreach ($item in $previewList | Where-Object { $_.DoRename }) {
            $lines += "$($item.原文件名)`t$($item.新文件名)"
        }
        $lines | Out-File -FilePath $backupFile -Encoding utf8
        Write-Host "  $(col_a_success ('✅  已保存映射文件（未改名）：' + $backupFile))"
        Wait-AnyKey
        continue  # 统一回顶部（替代原 return，避免退出脚本）
    }
    # 删除了重复的 elseif ('restart')
    # 后续直接走 'exec' 执行改名，执行完自然落回 while 顶部

    # ========== 执行改名 ==========
    Write-Host ""
    Write-Host "  $(col_a_title ('开始执行改名'))"
    Write-Host ""
    foreach ($item in $previewList) {
        $src = $item.FullName
        # v5.36：空跑硬拦截（如 00m34s2.nfo → 00m34s2.nfo，RENAME-EXT 且名实一致，内外一致）
        # 非 TAB-SYNC 且原名=新名 -> 跳过（不输出[OK]，不写nfo，不生成.bak）
        if ($item.Status -ne 'TAB-SYNC' -and $item.原文件名 -eq $item.新文件名) {
            continue
        }
        # v5.19：仅跳过"既不改名也不改nfo"的条目（TAB-SYNC需放行）
        if ($item.DoRename -ne $true -and (-not $enablenfoTagEdit -or $null -eq $item.nfoNewTitle)) { continue }

        # ---- 文件改名（唯一一处 Rename-Item，防双跑） ----
        if ($item.DoRename -eq $true) {
            $targetName = $item.新文件名
            $targetPath = Join-Path (Split-Path $src) $targetName
            # v5.28-fix：同名冲突自动追加序号，排除自身（二次重命名时旧文件即将被替换，不算冲突）
            if (Test-Path -LiteralPath $targetPath) {
                $isSelf = ($targetName -eq $item.原文件名)
                if (-not $isSelf) {
                    $ext = [System.IO.Path]::GetExtension($targetName)
                    $base = [System.IO.Path]::GetFileNameWithoutExtension($targetName)
                    $retry = 2
                    while (Test-Path -LiteralPath $targetPath) {
                        $candidate = "$base$retry$ext"
                        $candPath = Join-Path (Split-Path $src) $candidate
                        $isSelfCand = ($candidate -eq $item.原文件名)
                        if (-not $isSelfCand) {
                            $targetName = $candidate
                            $targetPath = $candPath
                            $retry++
                        } else {
                            $retry++
                        }
                    }
                    Write-Host "  $(col_a_text_muted '原名：')" -NoNewline
                    Write-Host "  $($item.原文件名)" -NoNewline
                    Write-Host " → " -NoNewline
                    Write-Host "  $targetName " -NoNewline
                    Write-Host "  $(col_a_warning '[同名冲突自动追加序号]') " -NoNewline
                }
                # 目标=自身时，不进入追加逻辑，$targetName 保持原值（预览已正确）
            }
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
        } # end if DoRename

        # ---- nfo 改写：只认 TAB-SYNC 行（唯一真相源）----
        if ($enablenfoTagEdit -and $item.Status -eq 'TAB-SYNC') {

            # 兜底：nfoNewTitle
            if ([string]::IsNullOrEmpty($item.nfoNewTitle)) {
                $item.nfoNewTitle = [System.IO.Path]::GetFileNameWithoutExtension($src)
            }

            # 路径定位：$src 是扫描时的 nfo 原路径，NewBase 是改名后的基名
            # 改名行（RENAME-EXT）已在本行之前把 nfo 改到 NewBase.nfo，这里直接按 NewBase 定位
            $nfoDir  = Split-Path $src
            $nfoPath = if ([string]::IsNullOrEmpty($item.NewBase)) { $src } else { Join-Path $nfoDir "$($item.NewBase).nfo" }

            # v5.31-fix P0-1：硬性扩展名校验 + 存在性检查，不合法直接跳过
            if (([System.IO.Path]::GetExtension($nfoPath).ToLower() -ne '.nfo') -or (-not (Test-Path -LiteralPath $nfoPath))) {
                # 目标不存在（改名行跳过/失败，导致 nfo 仍停在原路径）时提示，避免静默漏改
                Write-Host "  $(col_a_text_muted "[nfo跳过] 目标不存在：$nfoPath")"
                continue
            }

            if (Test-Path -LiteralPath $nfoPath) {
                try {
                    # v5.31-fix P0-2：编码探测，避免硬写 UTF8 毁文件
                    $nfoBytes = [System.IO.File]::ReadAllBytes($nfoPath)
                    if ($nfoBytes.Length -ge 2 -and $nfoBytes[0] -eq 0xFF -and $nfoBytes[1] -eq 0xFE) {
                        $nfoEnc = [System.Text.Encoding]::Unicode
                    } elseif ($nfoBytes.Length -ge 2 -and $nfoBytes[0] -eq 0xFE -and $nfoBytes[1] -eq 0xFF) {
                        $nfoEnc = [System.Text.Encoding]::BigEndianUnicode
                    } elseif ($nfoBytes.Length -ge 3 -and $nfoBytes[0] -eq 0xEF -and $nfoBytes[1] -eq 0xBB -and $nfoBytes[2] -eq 0xBF) {
                        $nfoEnc = New-Object System.Text.UTF8Encoding($true)
                    } else {
                        # 无 BOM：先严格试 UTF-8，失败才按 GB18030，避免把 UTF-8 中文当 GBK 解码
                        try {
                            $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
                            $null = $strictUtf8.GetString($nfoBytes)
                            $nfoEnc = New-Object System.Text.UTF8Encoding($false)
                        } catch {
                            Write-Host "  $(col_a_warning "[nfo跳过] 系统缺少 GB18030 代码页，无法安全处理：$nfoPath")"
                            continue          # ← 直接跳，不用变量
                        }
                    }
                    $nfoText = $nfoEnc.GetString($nfoBytes)

                    $origTitleVal = $null; $origSortVal = $null
                    if ($nfoText -match '<title\b[^>]*>(.*?)</title>') { $origTitleVal = $matches[1] }
                    if ($nfoText -match '<sorttitle\b[^>]*>(.*?)</sorttitle>') { $origSortVal = $matches[1] }

                    $bakPath = "$nfoPath.bak"
                    if (-not (Test-Path -LiteralPath $bakPath)) {
                        # v5.31-fix P0-2：备份改为 Copy-Item 字节级复制，保留原编码
                        Copy-Item -LiteralPath $nfoPath -Destination $bakPath -Force
                        $nfoBackupList += [PSCustomObject]@{
                            nfoFile    = [System.IO.Path]::GetFileName($nfoPath)   # 仅用于显示
                            nfoPath    = $nfoPath                                  # 写入时的路径
                            OldPath    = $src                                      # 撤销后应回到的路径
                            BakPath    = $bakPath
                            OldTitle   = $origTitleVal
                            OldSortVal = $origSortVal
                        }
                    }

                    $modified = $false
                    # v5.23：兼容带属性，无则追加（确保真实覆盖）
                    $safeTitle = Format-SafeXmlTitle -Title $item.nfoNewTitle

                    # v5.33：根节点探测——movie / episodedetails / tvshow 三类，追加时插到根节点闭合标签之前
                    # 找不到已知根节点时 $rootTag = $null，退化为直接追加到文件末尾（保持旧行为）
                    $rootTag = $null
                    foreach ($rt in @('movie', 'episodedetails', 'tvshow')) {
                        if ($nfoText -match ('</' + $rt + '>')) { $rootTag = $rt; break }
                    }
                    if ($nfoText -match '<title\b[^>]*>.*?</title>') {
                        $nfoText = $nfoText -replace '<title\b[^>]*>.*?</title>', "<title>$safeTitle</title>"
                        $modified = $true
                    } else {
                        if ($rootTag) {
                            $nfoText = $nfoText -replace ('</' + $rootTag + '>'), "<title>$safeTitle</title>`n</$rootTag>"
                        } else {
                            $nfoText += "`n<title>$safeTitle</title>"
                        }
                        $modified = $true
                    }
                    if ($nfoText -match '<sorttitle\b[^>]*>.*?</sorttitle>') {
                        $nfoText = $nfoText -replace '<sorttitle\b[^>]*>.*?</sorttitle>', "<sorttitle>$safeTitle</sorttitle>"
                        $modified = $true
                    } else {
                        if ($rootTag) {
                            $nfoText = $nfoText -replace ('</' + $rootTag + '>'), "<sorttitle>$safeTitle</sorttitle>`n</$rootTag>"
                        } else {
                            $nfoText += "`n<sorttitle>$safeTitle</sorttitle>"
                        }
                        $modified = $true
                    }

                    # v5.31-fix P0-2：按探测到的原编码回写，不再硬写 UTF8
                    if ($modified) {
                        [System.IO.File]::WriteAllBytes($nfoPath, $nfoEnc.GetBytes($nfoText))
                    }
                    $nfoModifyLog += [PSCustomObject]@{
                        nfoFile      = $item.原文件名
                        OldTitle     = $origTitleVal
                        NewTitle     = $item.nfoNewTitle
                        OldSortTitle = $origSortVal
                        NewSortTitle = $item.nfoNewTitle
                    }
                    if ($modified) {
                        Write-Host "  $(col_a_success '[nfo标签覆盖 OK]') title→$($item.nfoNewTitle) (path=$nfoPath)"
                    }
                } catch {
                    Write-Host "  $(col_a_error "[nfo标签更新失败] $_")"
                }
            }
            # nfo 不存在（MISS）完全静默
        }
    } # end foreach
    Write-Host ""
    Write-Host "  $(col_a_success ('[√] 全部操作完成。'))"

    # ========== 完成后菜单（v5.0 横向菜单） ==========
    if ($undoList.Count -gt 0) {
        $tipUndo = if ($embyFollow -and $enablenfoTagEdit) { "（⚠️  nfo内部文本被覆盖无法撤销，仅文件名可还原）" } else { "" }
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
        # q/Esc 退出本程序（之前若是tt.ps1调用则返回tt.ps1主菜单）
        if ($null -eq $postResult) { exit 0 }
        $timeStamp2 = Get-Date -Format "yyyyMMdd_HHmmss"
        if ($postResult -eq "undo") {
            if ($embyFollow -and $enablenfoTagEdit) { Write-Host "  $(col_a_warning ('⚠️  开始撤销，还原文件名 + nfo文本...'))" } 
            else { Write-Host "  $(col_a_warning ('⚠️  开始撤销，还原文件名...'))" }
            $failUndo = 0        # 仅统计文件名撤销失败
            $failNfo  = 0        # 仅统计 nfo / 孤立文件还原失败
            # v5.34：撤销逆序——后改的先还原，避免 A→A2 后再撤 A 时撞上 A2 的旧名
            [array]::Reverse($undoList)
            foreach ($uItem in $undoList) {
                if (Test-Path -LiteralPath $uItem.AfterPath) {
                    try {
                        Rename-Item -LiteralPath $uItem.AfterPath -NewName $uItem.OldName -ErrorAction Stop
                        Write-Host "  $(col_a_success "[撤销OK] $($uItem.NewName) → $($uItem.OldName)")"
                    } catch { Write-Host "  $(col_a_error "[撤销失败] $($uItem.AfterPath) : $_")"; $failUndo++ }
                } else { Write-Host "  $(col_a_error "[撤销跳过] 文件不存在：$($uItem.AfterPath)")"; $failUndo++ }
            }
            if ($enablenfoTagEdit -and $nfoBackupList.Count -gt 0) {
                Write-Host ""; Write-Host "  $(col_a_text ('还原 nfo 备份...'))"
                foreach ($bakItem in $nfoBackupList) {
                    $bakPath = $bakItem.BakPath
                    $restorePath = if ($bakItem.OldPath) { $bakItem.OldPath }
                                   else { Join-Path (Split-Path $bakItem.nfoPath) $bakItem.nfoFile }
                    # 安全锁：还原目标必须是 .nfo，绝不能是视频/图片
                    if ([System.IO.Path]::GetExtension($restorePath).ToLower() -ne '.nfo') {
                        Write-Host "  $(col_a_error "[nfo还原拒绝] 目标不是 .nfo：$restorePath")"; $failNfo++; continue
                    }
                    if (Test-Path -LiteralPath $bakPath) {
                        try {
                            Copy-Item -LiteralPath $bakPath -Destination $restorePath -Force   # 字节级还原
                            Remove-Item -LiteralPath $bakPath -Force -ErrorAction SilentlyContinue
                            Write-Host "  $(col_a_success "[nfo还原OK] $($bakItem.nfoFile)")"
                        } catch { Write-Host "  $(col_a_error "[nfo还原失败] $($bakItem.nfoFile) : $_")"; $failNfo++ }
                    } else { Write-Host "  $(col_a_error "[nfo还原跳过] 备份不存在：$bakPath")"; $failNfo++ }
                }
            }
            if ($orphannfoList.Count -gt 0) {
                Write-Host ""; Write-Host "  $(col_a_text ('还原孤立nfo...'))"
                foreach ($orph in $orphannfoList) {
                    if (Test-Path -LiteralPath $orph.BakPath) {
                        try {
                            [System.IO.File]::Copy($orph.BakPath, $orph.FilePath, $true)
                            Remove-Item -LiteralPath $orph.BakPath -Force -ErrorAction SilentlyContinue
                            Write-Host "  $(col_a_success "[孤立nfo还原OK] $($orph.FilePath)")"
                        } catch { Write-Host "  $(col_a_error "[孤立nfo还原失败] $($orph.FilePath) : $_")"; $failNfo++ }
                    }
                }
            }
            if ($orphanImageList.Count -gt 0) {
                Write-Host ""; Write-Host "  $(col_a_text ('还原孤立图片...'))"
                foreach ($orph in $orphanImageList) {
                    if (Test-Path -LiteralPath $orph.BakPath) {
                        try {
                            [System.IO.File]::Copy($orph.BakPath, $orph.FilePath, $true)
                            Remove-Item -LiteralPath $orph.BakPath -Force -ErrorAction SilentlyContinue
                            Write-Host "  $(col_a_success "[孤立图片还原OK] $($orph.FilePath)")"
                        } catch { Write-Host "  $(col_a_error "[孤立图片还原失败] $($orph.FilePath) : $_")"; $failNfo++ }
                    }
                }
            }
            Write-Host ""; Write-Host "  $(col_a_text ('撤销完成，文件名还原成功：'))" 
            Write-Host "  $(col_a_success "$($undoList.Count - $failUndo)")" 
            Write-Host "  $(col_a_text (' ｜失败：'))" 
            Write-Host "  $(col_a_error "$failUndo")"
            if ($nfoBackupList.Count -gt 0 -or $orphannfoList.Count -gt 0 -or $orphanImageList.Count -gt 0) {
                Write-Host "  $(col_a_text ('附属文件还原失败：'))" 
                Write-Host "  $(col_a_error "$failNfo")"
            }
            Write-Host ""
            Wait-AnyKey "  $(col_a_text_muted ('按任意键返回菜单...'))"
        } elseif ($postResult -eq "save") {
            $backupFile = Join-Path $PWD.Path "rename_backup_$timeStamp2.txt"
            $lines = @()
            $lines += "# 备份时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            $lines += "# Emby配图跟随：$embyFollow | nfo改写：$enablenfoTagEdit"
            $lines += "# 原名`t新名"
            foreach ($uItem in $undoList) { $lines += "$($uItem.OldName)`t$($uItem.NewName)" }
            if ($enablenfoTagEdit -and $nfoModifyLog.Count -gt 0) {
                $lines += "# nfo内部标签覆盖记录"
                foreach ($log in $nfoModifyLog) { $lines += "# File:$($log.nfoFile) | oldTitle:$($log.OldTitle) | newTitle:$($log.NewTitle)" }
            }
            $lines | Out-File -FilePath $backupFile -Encoding utf8
            Write-Host "  $(col_a_success ('✅  已保存映射文件：' + $backupFile))"
            Write-Host ""
            Wait-AnyKey "  $(col_a_text_muted ('按任意键返回菜单...'))"
        } 
        # 退出分支：不打印“按任意键”，否则与紧随其后的 return 打架（用户来不及看）
        return
    }
} 
finally 
{
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
}
Wait-AnyKey "  $(col_a_text_muted ('按任意键返回菜单...'))"
return
} # end while($true)