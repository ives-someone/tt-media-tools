从 maxm_v2 到 maxm_v3：交互式脚本升级为「双模式」架构的总结

本文以 maxm 为主线，但第三章的多数条目是 PowerShell 通用陷阱，可直接套用到其他脚本。

一、升级背景与目标

旧版（v2）：纯交互式 PowerShell 脚本，用户通过键盘选择扫描参数，适合手动操作但无法被 AI/自动化调用。

新版（v3）核心目标：

保留原有交互体验：不破坏手动使用习惯
新增非交互模式：通过 param() 命令行参数驱动，配合 AI prompt 模板直接生成启动命令
统一输出规范：两种模式生成的 TXT 文件名前缀一致、结构清晰
修复已知 Bug：时长读取失败、数组物化、路径前缀等问题
二、核心架构变更
2.1 双模式入口设计
纯文本
脚本启动
  ├─ $Mode 参数非空 → 非交互模式（param() 驱动，直接执行）
  └─ $Mode 为空     → 交互模式（原有键盘选择逻辑）

实现方式：在 param() 块之后，用 if ($Mode -ne "") { ...; exit 0 } 作为非交互入口，其余代码为交互模式。

关键设计原则：

非交互模式不调用​ Wait-KeyPress（该函数检测到 $Mode -ne "" 时直接返回空字符串）
两种模式共享所有公共函数（Get-AllFilteredFiles、Invoke-FfprobeDuration 等）
非交互模式执行完毕后 exit 0，不进入交互逻辑
2.2 参数体系设计
powershell
param(
    [string]$Mode = "",        # S/B/R/D 排序模式
    [string]$Path = "",        # 扫描根目录（默认当前目录）
    [switch]$Recurse,         # 递归子目录
    [switch]$AllFiles,        # 扫描全部文件（默认仅视频）
    [switch]$Meta,            # 强制读取元数据
    [switch]$ScanDuration,    # 后置扫描时长
    [int]$Top = 100,          # 最大输出条数
    [int]$MinBitrate = 0,     # 最低码率阈值(kbps)
    [int]$MinHeight = 0,      # 最低分辨率
    [int]$MaxHeight = 0,      # 最高分辨率
    [string]$UserQuery = "",  # AI 自然语言需求原文
    # ... 其他参数
)

设计要点：

所有参数都有合理默认值，非交互模式只需传关键参数
-UserQuery 用于记录 AI 原始指令，同时作为 TXT 文件名来源
-Meta 在非 B/R/D 模式下可选，B/R/D 模式强制开启
三、关键 Bug 修复与优化（可复用于其他脚本）
3.1 数组物化（防止单结果 Count=$null）

问题：Sort-Object | Select-Object -First N 在只返回 1 条结果时，返回的是单个对象而非数组，导致 .Count 为 $null。

修复：所有结果赋值强制用 @() 包裹：

powershell
$sorted = @($workList | Sort-Object ... | Select-Object -First $topCount)

复用价值：★★★★★ — 任何 PowerShell 脚本中处理管道输出都应养成此习惯。

3.2 时长读取稳定性（FIX v5）

问题：RedirectStandardOutput + JSON 解析在某些 ffprobe 版本下静默失败。

修复：退回 cmd /c ffprobe ... > outFile + [System.IO.File]::ReadAllText() 方案，新增统一函数：

powershell
function Invoke-FfprobeDuration {
    param([string]$FilePath, [string]$OutFile)
    $arg = '/c ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "' + $FilePath + '" > "' + $OutFile + '"'
    # ... 启动 cmd.exe 执行
}

复用价值：★★★★★ — 外部进程调用时，文件重定向比管道捕获更稳定。

3.3 元数据顺带提取时长（FIX v10）

问题：S 模式选读取元数据时，ffprobe JSON 已包含 format.duration，但脚本未提取，导致后续仍弹窗问时长。

修复：在元数据解析处顺带提取时长字段：

powershell
if ($jsonObj.format -and $jsonObj.format.duration) {
    $durSec = [double]$jsonObj.format.duration
    $durDisp = (Get-FriendlyDuration $durSec)
}

复用价值：★★★★ — 一次外部调用尽量多取数据，减少重复 IO。

3.4 路径前缀清理

问题：$PWD.Path 在 UNC/PowerShell 特殊路径下会带 Microsoft.PowerShell.Core\FileSystem:: 前缀。

修复：

powershell
$displayRoot = $scanRoot -replace '^Microsoft\.PowerShell\.Core\\FileSystem::',''

复用价值：★★★ — 任何需要向用户展示路径的脚本都应注意。

3.5 TXT 文件名非法字符处理

问题：用户查询或参数描述含 < > : " / \ | ? * 会导致保存失败。

最终方案（经过正则报错→字面量替换迭代）：

powershell
$cleanDesc = $fullDesc.Replace("交互模式", "").Replace(" ", "_").Replace("__", "_")
$cleanDesc = $cleanDesc.Replace("<", "").Replace(">", "").Replace(":", "").Replace('"', "").Replace("/", "_").Replace("\", "_").Replace("|", "").Replace("?", "").Replace("*", "")
$cleanDesc = $cleanDesc.Trim("_ ").Trim()

复用价值：★★★★★ — 文件名生成时永远不要用正则处理非法字符，用 .Replace() 字面量逐个处理最安全。

3.6 param() 必须是脚本的第一条语句

问题：param() 写在函数定义之后，PowerShell 会把它当成名为 param 的命令执行
      —— 启动时报两条红字，且参数绑定完全失效（命令行传参进不来，只能靠默认值"碰巧"可用）。

根因：param 只能作为脚本/函数体的第一条语句；位置错了不报语法错，而是当普通命令跑。

正确做法：param() 紧跟头部注释块之后、所有函数定义之前。

自检：运行 .\x.ps1 -SomeParam "值"，确认值真的传进去了。

复用价值：★★★★★ — 这类错误"看起来能跑"，只在传参时才暴露。

3.7 CSV 列名是跨脚本契约

问题：A 脚本导出的 CSV 被 B 脚本读取，A 改了列名后，B 仍按旧列名取值 → 取到 $null
      → 判断恒为假，功能静默失效（不报错、不提示，只是"永远 0 条"）。

实例：nfo_export 把 HasVideo / Consistent 改成「NFO内文件名校验」，
      maxm 的"不一致检查"菜单从此恒为 0 条。

正确做法：
  - 导出方与读取方在注释里互相声明依赖的列名；
  - 读取方对取不到的列做兜底（$null 时给提示，而不是静默当成 False）；
  - 改列名时同步搜索整个工具集里的读取方。

复用价值：★★★★★ — 跨脚本数据交换最隐蔽的破坏方式。

3.8 路径含 [ ] 时 -Path 会静默失效

问题：Get-ChildItem -Path "D:\某[字幕组]目录" -Filter *.csv 返回 0 条，不报错。

根因：-Path 支持通配符，[ ] 被当成字符集处理。

正确做法：所有文件操作一律 -LiteralPath
          （Get-ChildItem / Import-Csv / Get-Item / Test-Path / Out-File / Export-Csv）。

验证：造一个含 [ ] 的目录放个文件，两种写法对比即可。

复用价值：★★★★★ — 媒体库目录名带方括号极其常见。

3.9 BOM 会让 XmlDocument.LoadXml 直接崩

问题：字节读取后用 Encoding.GetString 解码，带 BOM 的文件首字符是 U+FEFF，
      LoadXml 抛 "Data at the root level is invalid. Line 1, position 1."，全部 nfo 解析失败。

对比：ReadAllText 会自动跳过 BOM，换成字节读取后这个"免费福利"就没了。

修复：解码后 $text = $text.TrimStart([char]0xFEFF)。

复用价值：★★★★ — 任何"自己解码再解析 XML"的场合。

3.10 读 nfo 不能假定 UTF-8

问题：Emby 生成的 nfo 可能是 UTF-8（带/不带 BOM）、GBK、UTF-16。
      硬按 UTF-8 读会把中文读成乱码，再写回时整份文件就毁了。

修复：先看 BOM（FF FE / FE FF / EF BB BF）；无 BOM 时用严格的
      UTF8Encoding($false, $true) 试解（非法字节会抛异常），失败再退回 GB18030（GetEncoding(936)）。

注意：GetEncoding(936) 在系统缺少该代码页时会抛异常，必须 catch 并跳过该文件，
      绝不能用错误编码写盘——宁可不动，也不能写坏。

复用价值：★★★★★ — 处理"别人生成的文件"时必须先探测编码。

3.11 ffprobe 并发不要数全机器进程

问题：while ((Get-Process ffprobe).Count -ge 4) { Start-Sleep }
      —— 数的是机器上所有 ffprobe。用户同时开着格式工厂/QuickSync 转码时，
      配额被外部占满，本脚本永远等不到空位，表现为"半天不动"。

修复：只统计自己拉起的、且尚未退出的进程：

powershell
while (@($taskList | Where-Object { -not $_.Proc.HasExited }).Count -ge $maxConcurrent) { Start-Sleep -Milliseconds 40 }

另注：同步调用（cmd /c 一次跑一个）本来就受控，不需要额外限流；
      给它加限流只会被外部进程卡死。

复用价值：★★★★ — 任何"我自己批量拉起外部进程"的场景。

3.12 trap 的四个坑

位置：trap 只有被"执行到"才生效。写在交互段里，非交互模式早就 exit 了，等于没装
      → 放在 param 之后、所有逻辑之前。

颜色：trap 可能在任何时候触发，包括 ui.ps1 还没加载的时候 → 不能用 col_a_*，
      必须用裸 -ForegroundColor，否则触发时再抛"找不到函数"，把真实错误盖掉。

中断范围：trap { ...; break } 会吞掉所有异常。只对 [PipelineStoppedException]（Ctrl+C）break，
          其余必须 throw，否则"路径不存在"这类正常报错会变成静默退出。

变量：trap 里引用 $taskList 前要判空——异常可能发生在变量初始化之前。

复用价值：★★★★★ — 全局异常处理最容易帮倒忙。

3.13 $Matches 会被同一条件里的后续 -match 覆盖

问题：
powershell
if ($line -match 'patternA' -and $L[$i+1] -match 'patternB') { $x = $Matches[1] }

第二个 -match 已把 $Matches 改写，$x 取到的是 patternB 的分组（通常为空）。

正确做法：先把 $Matches[1] 存进变量，再做后续判断。

复用价值：★★★★ — 写"多条件正则判断"时的经典陷阱，且不会报错，只会悄悄取错值。

3.14 .Replace() 是全串替换，不是"当前位置替换"

问题：逐个匹配替换时用 $name.Replace($han, $arabic)，先匹配到"一"就会把全串所有"一"换掉，
      把后面的"十一"拆成"十01"，把"一百"拆成"01百"。

正确做法：按匹配位置重建字符串（记录 lastPos，逐段 Append），
          或改用 [regex]::Replace + MatchEvaluator。

复用价值：★★★★ — 任何"按正则匹配逐个替换"的需求。

四、输出文件名统一规范
设计思路

模式

	

前缀

	

后缀

	

示例




交互

	

本文件夹内文件筛选&排序统计_交互模式_

	

参数摘要_时间戳

	

..._递归子目录_仅视频_排序_文件大小_..._20261018_235912.txt




非交互

	

本文件夹内文件筛选&排序统计_非交互模式_

	

用户需求原文_时间戳

	

..._查找文件内码率大于5000k的视频按时长排序_20261018_235845.txt

实现要点：

交互模式：$fullDesc 变量生成参数摘要 → 清理前缀和空格 → 拼接
非交互模式：$UserQuery 原文 → 长度限制 80 字符 → 拼接
时间戳统一用 yyyyMMdd_HHmmss
五、升级过程中的迭代教训（避坑指南）

轮次

	

问题

	

根因

	

正确做法




早期

	

正则 `-replace '[<>:"/\

	

?*]'` 报错

	

方括号在正则中是特殊字符




中期

	

文件名重复"交互模式交互模式"

	

$fullDesc 自带前缀 + 代码又加前缀

	

清理逻辑中先 .Replace("交互模式","")




中期

	

文件名多余空格

	

参数间用 _ 分隔

	

.Replace(" ", "_").Replace("__", "_") 压缩




早期

	

复制脚本不完整导致大括号缺失

	

对话中代码输出被截断

	

分段复制或要求完整输出后验证行号

六、可复用到其他脚本的通用方法论
6.1 交互脚本 → 双模式脚本的改造步骤
提取公共函数：将文件扫描、格式转换、外部调用等逻辑封装为函数
添加 param() 块：设计合理的参数集，带默认值
入口分流：if ($args_mode) { 非交互逻辑; exit } 在前，交互逻辑在后
统一输出：两种模式共用输出格式化代码，仅数据源不同
文件名规范：提前设计命名规则，用安全替换处理用户自定义内容
6.2 PowerShell 脚本健壮性 checklist
[ ] 所有管道结果用 @() 物化
[ ] 外部进程调用优先用文件重定向，避免 stdout/stderr 管道捕获
[ ] 文件名生成用 .Replace() 而非正则处理非法字符
[ ] 路径展示前清理 PowerShell 底层前缀
[ ] Test-Path 全部用 -LiteralPath 防特殊字符
[ ] 并发进程数限制 + Ctrl+C 清理子进程
[ ] 文件长度限制（避免路径超 260 字符）
[ ] param() 必须是脚本/函数体的第一条语句（跟在头部注释之后）
[ ] 路径可能含 [ ] 时，所有文件操作使用 -LiteralPath
[ ] 横向菜单选项总宽超过屏幕时，改用竖向菜单（横向折行后 \r 重绘会残留重复行）
[ ] 自己拉起的外部进程，并发统计只数自己的，不要数全机器
[ ] trap 只对 Ctrl+C 中断，其余异常必须 throw；trap 内不使用 ui.ps1 的函数
七、总结

从 v2 到 v3 的升级，本质上是将"人操作"的脚本进化为"人+AI 都能操作"的脚本。核心改动量不大（约 200 行新增），但架构上实现了：

零侵入：原有交互体验完全保留
高兼容：PowerShell 5.0+ 全兼容，无第三方依赖
可扩展：新参数只需在 param() 中添加，AI prompt 模板同步更新即可

这套方法论可直接复用于其他需要"手动+自动化"双模式的 PowerShell 工具脚本。

## PowerShell 双模式升级通用规范（AI 必读）

### 1. 核心目标
将单脚本升级为「原交互模式（默认） + 非交互 AI 驱动模式（参数映射）」，零侵入原功能，兼容 PowerShell 5.0。

### 2. 架构与入口
- 保留原交互逻辑，新增 `param()` 块（带默认值）。
- 入口分流：非交互参数命中时走自动化逻辑并 `exit`，否则进入原交互流程。
- 公共函数（如按键等待、外部程序检测）需封装，避免重复。

### 3. 绝对避坑（PowerShell 特性）
- ❌ 禁用正则处理文件名：`[<>:"/\|?*]` 等易报 `InvalidRegularExpression`。
- ✅ 强制使用 `.Replace()` 字面量逐个清理非法字符，空格压缩用 `.Replace(" ", "_").Replace("__", "_")`。
- 路径展示需清理 `Microsoft.PowerShell.Core\FileSystem::` 前缀。
- 外部进程（如 ffprobe）优先用 `cmd /c ... > 文件` 重定向，避免管道阻塞。
- 管道结果用 `@()` 物化，文件测试用 `-LiteralPath`。

### 4. 输出文件名规范
- 交互模式：`本文件夹内XXX_交互模式_参数摘要_时间戳.txt`（时间戳 `yyyyMMdd_HHmmss`）。
- 非交互模式：`本文件夹内XXX_非交互模式_需求原文(截80字)_时间戳.txt`。
- 前缀固定，摘要需 `Trim("_ ")`，长度限制防超 260 路径。

### 5. 投喂指令模板（下次直接复制）
> “参考本文档规范，将以下 `.ps1` 升级为双模式（保留交互，新增非交互参数）。
> 要求：PowerShell 5 兼容，字面量替换文件名，统一命名规则，输出完整可运行代码。
> 【目标脚本代码】：[粘贴代码]
> 【可选：参数映射模板】：[粘贴自然语言转参数模板]”
