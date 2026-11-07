<#
============================================================
tt.ps1 — TT_Media_Tools 视频重命名工具集 主菜单
============================================================
v2.0：主菜单选项1移除二级子菜单，改为直接调用合并版 time_add.ps1
v3.0：全面升级交互体验。
    dot-source modules/ui.ps1 引入公共 UI 框架（配色 + arrow_select）
    主菜单/二级菜单从 Get-SingleKey 升级为 arrow_select 箭头导航
    启动阶段 ffprobe 残留检测接入配色高亮
    ANSI 清屏替代 cls，兼容 UNC 路径
    PS7 可用，不刻意兼容 PS5.1
v3.1：全文梳理 UI 依赖点，在调用 ui.ps1 函数的位置补充注释说明
    功能由 ui.ps1 统一实现（配色/菜单/清屏/分割线），
    明确 tt.ps1 与 ui.ps1 的职责边界，提升可读性。
v3.2：配色调用点全面迁移至 col_a_ 语义别名体系，与 ui.ps1 v4.0 对齐。
    旧 col_gray_dark/col_cyan/col_yellow 等全部弃用，
    退出提示→col_a_text_muted，标题分隔线→col_a_title，
    无效选项警告→col_a_warning。sep_weak 补充 col_a_line 包裹。
v3.3：适配 modules 目录子文件夹重构。
    UI 模块迁移至 modules\ui\`，主文件tt.ps1加载路径同步更新，
    引入统一入口ui.ps1`，为后续子模块平铺做铺垫。
v3.4：适配 ui.ps1 v4.1，arrow_select 移除 -ShowSep / -ShowWeakSep 参数。
    主分割线 sep 和弱分割线 sep_weak 改由 tt.ps1 在调用 arrow_select 前后自行绘制，
    彻底解决弱线被终端显影重复问题。选项1~8 报错/输出逻辑不变。
v3.5：适配 ui.ps1 v4.2（PS7+WT 光标定位重绘）。
    arrow_select 内部不再清屏，调用方负责 Clear-Screen + 标题 + sep 的绘制顺序。
    调整主菜单绘制结构：先清屏 → 标题 → 主分割线 → arrow_select（内部只画选项区）→ 弱分割线在 arrow_select 返回后绘制（取消时弱线不画）。
    子菜单（submenu_time_clean）同步调整。
v3.6：适配 ui.ps1 v4.6 arrow_select 曾新增 -Footer 参数（历史记录）。
    当时设计意图：提示行由 ui 内部绘制，调用方只管标题+主分割线+菜单调用。
    注：v4.7 精简 Arrow-Menu 时 -Footer 被移除，v3.7 起改用新增的 -Footer1/-Footer2 参数恢复该职责边界。
v3.7：适配 ui.ps1 v4.9 Arrow-Menu 恢复并升级为 -Footer1/-Footer2 双行参数。
    主菜单提示行改用 -Footer1 传入，由 _Arrow-Menu_Draw 内部绘制（纳入 [2K] 覆盖刷新）。
    移除外部手动 Write-Host 提示行，彻底解决被覆盖/不显示问题。
    调用方定义提示内容、ui 控制绘制时机，职责边界与 v3.6 设计意图一致。
v3.8：主菜单恢复处理目录回显（子模块全部按 $PWD 处理文件，显式显示避免扫错盘）。
    取 $PWD.ProviderPath 而非 $PWD.Path，去掉 FileSystem provider 前缀，
    UNC 路径不再显示 Microsoft.PowerShell.Core\FileSystem:: 。
    超长路径按字符数保头保尾截断（38 + … + 38），避免折行挤爆 Arrow-Menu 选项区。
v3.9：抽出 Invoke-Module 统一封装子模块调用。
    原 8 个菜单分支各写一段「Test-Path + & $target」样板，差异只有文件名（8 段共约 72 行），
    现合并为 1 个函数 + 8 行调用，本次文件从 195 行降至 160 行。
    同时补上异常兜底：子脚本抛未捕获异常时提示后回主菜单，不再导致整个 tt 崩溃；
    子脚本内的 OperationCanceledException（q/Esc 取消）静默处理，不打印错误。
    注释区块编号调整为：区块零 初始化 / 区块一·B 子模块调用封装 / 区块二 主菜单循环。
v4.0：菜单新增第 9 项「视频合并 / 转码工具」（modules\video_tool.ps1）。
    底部直达提示同步改为 [1-9] 直达；其余结构不变。
v4.1：主菜单重排为 1~5 + 视频工具(6) + [0] 其他小工具集合。
    原 6/7/8 三项收进二级菜单；子菜单跑完一个工具即回主菜单。
    依赖 ui.ps1 v7.0 的数字标签（支持 [0] 直达）。
============================================================
#>

# ============================================================
# 区块零：初始化
# 加载公共 UI 框架、获取脚本目录、定义子模块调用路径
# ============================================================

# dot-source 公共 UI 框架（配色/菜单/预览格式化/清屏/分割线，全部由 ui.ps1 统一实现）
# v3.3：UI 模块实际文件已迁移至 modules\ui\ui.ps1，此处同步修正加载路径
. (Join-Path $PSScriptRoot "modules\ui\ui.ps1")

# 最低版本检查：低于 5.1 直接说明原因，避免报一堆语法错误
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Host ""
    Write-Host "  需要 PowerShell 5.1 或更高版本，当前版本：$($PSVersionTable.PSVersion)" -ForegroundColor Red
    Write-Host "  请使用 Windows 10/11 自带的 PowerShell，或安装 PowerShell 7+" -ForegroundColor Yellow
    Write-Host ""
    return
}

# 子模块目录（后续子模块迁入 modules/ 后统一从此加载）
$ModulesDir = Join-Path $PSScriptRoot "modules"

# ============================================================
# 区块一·B：子模块调用封装（v3.9）
# 8 个菜单项原本各写一段「Test-Path + & 调用」样板，差异只有文件名，
# 抽成统一函数：改一处八处生效，且顺带补上异常兜底。
# ============================================================
function Invoke-Module {
    <#
    .SYNOPSIS
        调用 modules 目录下的子脚本，带存在性检查与异常兜底
    .PARAMETER Name
        子脚本文件名，如 "time_add.ps1"
    #>
    param([string]$Name)

    Write-Host ""
    $target = Join-Path $ModulesDir $Name

    if (-not (Test-Path -LiteralPath $target)) {
        Write-Host (col_a_error "  错误：$Name 文件不存在！当前 ModulesDir=$ModulesDir")
        Wait-AnyKey "  按任意键返回主菜单..."
        return
    }

    try {
        & $target
    }
    catch [System.OperationCanceledException] {
        # 子模块内 q/Esc 取消：静默返回主菜单，不打印错误
    }
    catch {
        # 其它未捕获异常：提示后回主菜单，避免整个程序崩溃
        Write-Host ""
        Write-Host (col_a_error "  运行出错：$($_.Exception.Message)")
        Write-Host (col_a_text_muted "  位置：$Name")
        Wait-AnyKey "  按任意键返回主菜单..."
    }
}

# ============================================================
# 区块一·C：其他小工具集合（v4.1）
# 原菜单 6/7/8 三项收进二级菜单，跑完一个工具即回主菜单
# ============================================================
function Invoke-ToolSubmenu {
    Clear-Screen
    Write-Host ""
    $cwdDisplay = $PWD.ProviderPath
    if ($cwdDisplay.Length -gt 78) {
        $cwdDisplay = $cwdDisplay.Substring(0, 38) + '…' + $cwdDisplay.Substring($cwdDisplay.Length - 38)
    }
    $subTitle = 'TT_Media_Tools — 其他小工具集合'
    Write-Host "  $(col_a_title $subTitle)"
    Write-Host "  $(col_a_line (sep))"
    Write-Host ""
    Write-Host "  $(col_a_text_muted '处理目录：')$(col_a_text $cwdDisplay)"
    Write-Host ""

    $subOptions = @(
        "[1]文件扩展名规整，将大写扩展名批量转换为小写",
        "[2]文件名、文件夹内汉字数字批量替换为阿拉伯数字",
        "[3]快捷方式lnk目标路径批量替换（不完善，不认乱码）"
    )
    # 缩放重绘时要原样恢复标题区，行序必须与上面绘制的一致
    $subHeader = @(
        ""
        "  $(col_a_title $subTitle)"
        "  $(col_a_line (sep))"
        ""
        "  $(col_a_text_muted '处理目录：')$(col_a_text $cwdDisplay)"
        ""
    )
    try {
        $pick = Arrow-Menu -Options $subOptions -DefaultIndex 0 -Footer1 "  $(col_a_line (sep_weak))" -Footer2 "  $(col_a_text '[↑↓]移动  [1-3]直达  [Enter]确认  [q/Esc]返回主菜单')" -Header $subHeader
    } catch [System.OperationCanceledException] {
        # q / Esc → 回主菜单
        return
    }

    switch ($pick) {
        0 { Invoke-Module "ext_lower.ps1" }
        1 { Invoke-Module "cn_to_arabic.ps1" }
        2 { Invoke-Module "lnk_replace.ps1" }
    }
    # 子模块结束后函数返回，主循环重新绘制主菜单
}
# ============================================================
# 区块二：主菜单循环（v3.8 适配 Arrow-Menu -Footer1 参数）
# Arrow-Menu 箭头导航，↑↓移动 / 数字直达 / 回车确认 / q·Esc 退出
# 纯字符串数组传入，返回索引 0~6 直接 switch，无需 +1 映射
# 提示行通过 -Footer1 传入，由 ui 内部绘制（纳入 [2K] 覆盖刷新）
# 选项 1~6 与 [0] 统一经 Invoke-Module / Invoke-ToolSubmenu 调用
# ============================================================
while ($true) {
    # ANSI 清屏（由 ui.ps1 Clear-Screen 实现，不调 cls，兼容 UNC 路径）

    Clear-Screen
    # ---- 标题 + 主分割线（在 Arrow-Menu 之前画，函数内部不清屏不会覆盖） ----
    # 顶端空一行，更优雅
    Write-Host ""
    # ---- 标题，调用方自己写，自定义程度高，放弃之前全由UI定义格式的做法
    Write-Host "  $(col_a_title 'TT_Media_Tools 视频重命名工具集')"
    # ---- 主分割线，长度可以在ui.ps1里统一改
    Write-Host "  $(col_a_line (sep))"
    Write-Host ""
    # ---- 当前工作目录（v3.8）：子模块全部按 $PWD 处理文件，显式回显避免扫错盘
    #      UNC 安全：只用 [System.IO.Path] 纯字符串拼接，不调用 Resolve-Path / Get-Item，
    #      避免 SMB 断连或凭据失败时抛异常打断菜单
    $cwdDisplay = $PWD.ProviderPath
    if ($cwdDisplay.Length -gt 78) {
        $cwdDisplay = $cwdDisplay.Substring(0, 38) + '…' + $cwdDisplay.Substring($cwdDisplay.Length - 38)
    }
    Write-Host "  $(col_a_text_muted '处理目录：')$(col_a_text $cwdDisplay)"
    Write-Host ""

    # ---- 构建主菜单选项（纯字符串数组，v3.7 弃用 tuple） ----
    $mainOptions = @(
        "[1]视频提取时长并重命名添加",
        "[2]识别文件名内视频时长文字并按多种需求清理",
        "[3]NFO同步：刷新同步与视频同名的NFO文件内部名称",
        "[4]递归扫描NFO，提取信息导出CSV，便于筛查排序",
        "[5]TOP XX 的视频/文件查找和输出_新版双模式",
        "[6]视频合并 / 转码工具（支持无损快速合并）",
        "[0]其他小工具集合"
    )
    # ---- 显示菜单并等待选择 ----
    # Arrow-Menu（ui.ps1 v7.0：纯字符串数组，返回索引 0~6，ANSI 原地覆盖）
    # 标题+sep 已在上方绘制，Arrow-Menu 从 sep 后空一行开始画选项
    # 提示行由调用方通过 -Footer1 传入字符串（支持按需多一行-Footer2或全留空），_Arrow-Menu_Draw 内部绘制（[2K]覆盖刷新）
    try {
        # v7.1：把标题区交给 Arrow-Menu，窗口缩放清屏后可原样恢复
        $mainHeader = @(
            ""
            "  $(col_a_title 'TT_Media_Tools 视频重命名工具集')"
            "  $(col_a_line (sep))"
            ""
            "  $(col_a_text_muted '处理目录：')$(col_a_text $cwdDisplay)"
            ""
        )
        $sel = Arrow-Menu -Options $mainOptions -DefaultIndex 0 -Footer1 "  $(col_a_line (sep_weak))" -Footer2 "  $(col_a_text '[↑↓]移动  [0-6]直达  [Enter]确认  [q/Esc]退出')" -Header $mainHeader
    }
    catch [System.OperationCanceledException] {
        # q / Esc → 退出
        Write-Host ""
        Write-Host "  $(col_a_text_muted ('已退出。'))"
        return
    }
    # ---- 路由分发（v3.9）----
    # Arrow-Menu 直接返回索引 0~6，与 switch case 一一对应
    # 每项统一走 Invoke-Module：存在性检查 + 异常兜底集中在一处
    switch ($sel) {
        0 { Invoke-Module "time_add.ps1" }      # 选项1：视频时长提取 + 重命名
        1 { Invoke-Module "time_clear.ps1" }    # 选项2：清理时长文件名
        2 { Invoke-Module "nfo_title.ps1" }     # 选项3：NFO 同步
        3 { Invoke-Module "nfo_export.ps1" }    # 选项4：NFO 导出 CSV
        4 { Invoke-Module "top_finder.ps1" }    # 选项5：TOP XX 查找
        5 { Invoke-Module "video_tool.ps1" }    # 选项6：视频合并 / 转码
        6 { Invoke-ToolSubmenu }                # 选项0：其他小工具集合
        default {  # 兜底（理论上 Arrow-Menu 不会返回越界值）
            Write-Host ""
            Write-Host "$(col_a_warning ('无效选项！')) 收到索引: [$sel]"
            Start-Sleep -Milliseconds 500
        }
    }
}