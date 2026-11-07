<#
============================================================
modules/ui.ps1
TT_Media_Tools 公共 UI 框架
============================================================
v1.0：从 Python ui.py 移植，集中管理配色/菜单/预览格式化
    供 tt.ps1 及所有子模块 ps1 dot-source 引用

v1.1：模块化分段注释，便于理解和维护

v2.7：根治菜单显示括号与尾部数字问题。
    传入元组被扁平化为双字符串，内部强制两两合并还原选项，
    界面只显示纯净文本。显示序号固定 1~N（内部仍 0 基索引），数字键直达同步适配。

v3.0：交互体验升级。
    ↑↓ 光标移动支持循环（到顶跳底、到底跳顶）
    高亮渲染弃用 ANSI 反显，改用自定义 231/28 配色反显，
    彻底解决黑底/蓝底控制台文字消失问题

v4.0：配色架构重构为"基础色板(col_c_) + 语义别名(col_a_)"两层体系。
    旧单色函数全部弃用，调用点统一换为 col_a_ 语义别名。
    sep/sep_weak 改为返回裸线，由调用方自行包裹 col_a_line。
v4.1~v4.3：菜单渲染与分割线布局定型（历史）。
    当时方案：调用方负责标题+主分割线，_Draw-ArrowMenu 内部
    负责选项绘制+弱分割线+提示行，ANSI 光标归位+[2K]逐行覆盖。
    不再兼容 PS5/conhost，仅限 PS7+Windows Terminal。
    （v4.7 精简后弱分割线/提示行绘制被移除，职责归还调用方）
v4.4：全面补回各函数参数说明、示例、区块说明，恢复可读性。
v4.5：修复提示行硬编码 [1-9] 改为动态显示实际可用范围（历史）。
    （v4.7 精简时提示行整段移除，v4.9 通过 Footer1/Footer2 恢复）
    同步移除 arrow_select 数字键段中已无用的扁平化检测残留代码。
v4.7：arrow_select 精简为 Arrow-Menu，砍掉 tuple/hashtable/扁平化支持，
    仅接受纯字符串数组返回索引，ANSI 原地覆盖保留，接口极简。
    提示行/弱分割线绘制逻辑被移除，调用方需自行处理（v4.9 恢复为 Footer 参数）。
v4.9：Arrow-Menu 新增 -Footer1/-Footer2 双行独立参数。
    调用方定义提示内容传入，_Arrow-Menu_Draw 内部逐行绘制并纳入 [2K] 覆盖刷新。
    支持无提示/单行/双行三种模式，空字符串自动跳过不占行。
v5.1：修复移动光标后回车导致后续输出重叠。
    Enter 返回前强制完整重绘（画满 Footer1+Footer2），确保光标落在菜单底部；
    _Arrow-Menu_Draw 始终按最大行数（选项+Footer1+Footer2）覆盖，消除残留。
v5.2：纵向菜单大改动（独立成型）。
    正式确立纵向 Arrow-Menu 与横向 Select-Horizontal 双菜单体系；
    纵向菜单支持循环移动、数字直达、Q/Esc 取消，接口极简。
v5.3：修复纵向菜单上下移动时选项文字闪烁。
    _Arrow-Menu_Draw 新增 -PreviousSelected 参数，支持差异更新模式——
    仅覆写变更的两行（旧选中恢复普通色+新选中加高亮），
    首次绘制/Enter确认仍全量兜底，消除清屏-重画间隙。
v5.4：修复纵向/横向菜单光标闪烁。
    弃用 ANSI 光标序列，改用 [Console]::CursorVisible 原生 API
    （进入隐藏/所有退出路径恢复），横向菜单同步原生隐藏。
v5.5：纵向菜单差异更新彻底稳定。
    配合 v5.4 原生光标隐藏，上下移动仅覆写2行无黑帧，
    首次/确认全量兜底，Footer 提示行稳定底部，视觉完全无闪。
v5.6：横向菜单字母直达兼容 [x] + Q退出
v6.1：纵向 Arrow-Menu 字母/数字双模直达。优先匹配 Label 中 [x] 括号字母，
    无则回退 1~9 数字。绘制自适应前缀（有字母显原 Label，无则 [数字]），
    与横向 Select-Horizontal 字母直达逻辑对齐，调用方传带 [] 字母 Label 即可通用。
v6.2：横向 Select-Horizontal 补全字母+数字双模直达，与纵向 Arrow-Menu v6.1 对齐。
    通用直达分支扩展：优先匹配 Label [字母] → 回退 Label [数字] → 兜底 1~9 索引直达。
    支持混搭（[1]xxx [2]xxx [u]xxx），调用方传带 [] 的 Label 即可通用。
v6.3：修复横向菜单字母/数字直达时画面残留上一次高亮位置的问题。
    所有直达命中分支在 return 前先将 $idx 同步为命中索引并刷新选项行，确保视觉与返回值一致。
v6.4：修复 _Arrow-Menu_Draw 全量刷新时 $totalLines 行数计算笔误。
    原代码第二个条件误写 $hasF1 而非 $hasF2，导致 Footer2 有内容时
    少算一行，清屏覆盖不完整，菜单下方残留旧内容。
    修正为 $(if($hasF2){1}else{0})，行数计算与实际绘制对齐。
v6.5：修复 Select-Horizontal 中 U2（ANSI 光标混用→统一 [Console]::CursorVisible）。
v7.0：Arrow-Menu 保留调用方给的数字标签，不再按位置重排；
      数字键直达改为先匹配标签里的数字（支持 [0]），再回退 1~9 位置。
============================================================
#>

# ============================================================
# 区块一：ANSI 配色函数
# 架构：基础色板(col_c_) + 语义别名(col_a_) 两层解耦
# col_c_ = 物理颜色，不关心用途；col_a_ = UI视觉层级，指向基础色
# 改色只需改别名指向，调用方零改动
# ============================================================

# ==================== 基础色板 col_c_ ====================
# 🔴🟠🟡🟢🔵🟣🟤⚫⚪
# 命名规则：col_c_ + 颜色名，按彩虹色谱排列

# ---- 红 Red ----
function col_c_light_red    { param([string]$Text) return "$([char]27)[91m$Text$([char]27)[0m" } #浅红/亮红 91
function col_c_dark_red     { param([string]$Text) return "$([char]27)[31m$Text$([char]27)[0m" } #深红/暗红 31

# ---- 橙 Orange ----
function col_c_bright_orange { param([string]$Text) return "$([char]27)[38;5;214m$Text$([char]27)[0m" } # 亮橙 214
function col_c_warm_orange   { param([string]$Text) return "$([char]27)[38;5;172m$Text$([char]27)[0m" } # 暖橙棕 172

# ---- 黄 Yellow ----
function col_c_light_yellow { param([string]$Text) return "$([char]27)[93m$Text$([char]27)[0m" } #浅黄/亮黄 93
function col_c_dark_yellow  { param([string]$Text) return "$([char]27)[38;5;130m$Text$([char]27)[0m" } #暗黄/土黄 130

# ---- 绿 Green ----
function col_c_grass_green  { param([string]$Text) return "$([char]27)[92m$Text$([char]27)[0m" } #草绿/亮绿 92
function col_c_dark_green   { param([string]$Text) return "$([char]27)[32m$Text$([char]27)[0m" } #深绿/暗绿 32

# ---- 青 Cyan ----
function col_c_cyan         { param([string]$Text) return "$([char]27)[96m$Text$([char]27)[0m" } #亮青 96
function col_c_dark_cyan    { param([string]$Text) return "$([char]27)[36m$Text$([char]27)[0m" } #深青 36

# ---- 蓝 Blue ----
function col_c_light_blue   { param([string]$Text) return "$([char]27)[94m$Text$([char]27)[0m" } #浅蓝/亮蓝 94
function col_c_dark_blue    { param([string]$Text) return "$([char]27)[34m$Text$([char]27)[0m" } #深蓝/暗蓝 34

# ---- 紫 Purple ----
function col_c_light_purple { param([string]$Text) return "$([char]27)[95m$Text$([char]27)[0m" } #浅紫/洋红 95
function col_c_dark_purple  { param([string]$Text) return "$([char]27)[38;5;129m$Text$([char]27)[0m" } #深紫/暗紫，避坑35m（PS5会看不到） 129

# ---- 灰/白/黑 Gray / White / Black ----
function col_c_light_gray   { param([string]$Text) return "$([char]27)[37m$Text$([char]27)[0m" } #浅灰，PS5/7里看着都很像白，只略暗一点 37
function col_c_dark_gray    { param([string]$Text) return "$([char]27)[90m$Text$([char]27)[0m" } #深灰 90
function col_c_white        { param([string]$Text) return "$([char]27)[97m$Text$([char]27)[0m" } #纯白，不常用 97
function col_c_black        { param([string]$Text) return "$([char]27)[30m$Text$([char]27)[0m" } #纯黑，几乎不用，黑底ps7/终端看不到，蓝底ps5看不清 30

# 备忘 0-7（暗色）：0黑、1红、2绿、3黄、4蓝、5洋红、6青、7白（灰白）
# 8-15（亮色）：8灰、9亮红、10亮绿、11亮黄、12亮蓝、13亮洋红、14亮青、15亮白（纯白）
# 256颜色 38;5;X 前景色 48;5;X 背景色

# ==================== 语义别名 col_a_ ====================
# 命名规则：col_a_ + 视觉层级名，指向基础色板，改一处全生效
# 调用方只碰这些，不碰 col_c_

# ---- 标题层级 ----
function col_a_title        { param([string]$Text) return (col_c_grass_green $Text) } # 主标题：浅，菜单/区块大标题
function col_a_subtitle     { param([string]$Text) return (col_c_dark_green $Text) }   # 副标题：深，二级标题/分组名

# ---- 正文层级 ----
function col_a_text         { param([string]$Text) return (col_c_white $Text) }     # 正文：默认白，菜单选项/常规文本/提示行
function col_a_text_muted   { param([string]$Text) return (col_c_light_gray $Text) }     # 弱化正文：浅灰，辅助说明，未选中正文
function col_a_text_gray    { param([string]$Text) return (col_c_dark_gray $Text) }     # 极度弱化正文：深灰，忽略/跳过项

# ---- 交互层级 ----
function col_a_sel          { param([string]$Text) return "$([char]27)[38;5;231;48;5;28m$Text$([char]27)[0m" }  # 选中项：浅字+深灰底反显
function col_a_hover        { param([string]$Text) return (col_c_light_blue $Text) }    # 悬停提示：浅蓝，预留交互态

# ---- 状态层级 ----
function col_a_success      { param([string]$Text) return (col_c_grass_green $Text) }    # 成功/确认：草绿，完成/通过
function col_a_warning      { param([string]$Text) return (col_c_light_yellow $Text) }  # 警告/注意：亮黄，需关注/将重处理
function col_a_error        { param([string]$Text) return (col_c_light_red $Text) }      # 错误/危险：亮红，失败/异常

# ---- 结构层级 ----
function col_a_line         { param([string]$Text) return (col_c_dark_gray $Text) }      # 分割线/边框：深灰，弱边界
# Reset 用 22;39m 只清加粗+颜色，不清其他样式，嵌套时加粗不中断 在powershell里，怎么调整都不直观，只是亮一点，建议加粗慎用，改用颜色层级+符号区分
function col_a_bold         { param([string]$Text) return "$([char]27)[1;38;5;231m$Text$([char]27)[22;39m" }  # 加粗强调：提亮纯白，PS终端渲染不可靠，慎用

# ==================== 分隔线 ====================

# 主分隔线 ===============（裸线，不带颜色，默认60个=）
function sep {
    <#
    .SYNOPSIS
        生成指定字符和长度的主分隔线字符串（裸线，不带颜色）
    .PARAMETER Char
        分隔线使用的字符，默认 '='
    .PARAMETER Len
        分隔线长度，默认 60
    .EXAMPLE
        sep -Char '=' -Len 60   →   ==================================================
    #>
    param(
        [string]$Char = '=',
        [int]$Len = 60
    )
    return ($Char * $Len)
}

# 弱分隔线 ---------------（裸线，不带颜色，默认60个-）
function sep_weak {
    <#
    .SYNOPSIS
        生成弱分隔线字符串（裸线，不带颜色，默认 - 字符）
    .PARAMETER Char
        分隔线使用的字符，默认 '-'
    .PARAMETER Len
        分隔线长度，默认 60
    .EXAMPLE
        sep_weak -Len 60   →   ------------------------------------------------------------
    #>
    param(
        [string]$Char = "-",
        [int]$Len = 60
    )
    return ($Char * $Len)
}

# ============================================================
# 区块二：Arrow-Menu 精简箭头选择菜单（v4.9）
# 仅接受纯字符串数组，返回索引 0~N-1
# ANSI 光标定位原地覆盖，不清屏，循环移动，数字键直达
# 提示行通过 -Footer1/-Footer2 传入，内部绘制（[2K]覆盖刷新）
# 取消时抛 OperationCanceledException
# ============================================================

function Arrow-Menu {
    <#
    .SYNOPSIS
        精简箭头选择菜单，纯字符串数组传入，返回选中索引
    .PARAMETER Options
        字符串数组，如 @('选项1', '选项2', '选项3')
    .PARAMETER DefaultIndex
        默认高亮项索引，默认 0
    # .PARAMETER Title
        菜单标题（当前未使用，预留兼容，调用方自行绘制标题+sep）
    .PARAMETER Footer1
        底部提示行第一行，由调用方定义字符串，ui 内部绘制。
        不传或空字符串则不显示该行。例："  [↑↓]移动  [1-8]直达  [Enter]确认  [q/Esc]退出"
    .PARAMETER Footer2
        底部提示行第二行，可选。不传或空字符串则不显示。
        例："  $(col_a_text_muted '注意：修改不可逆，请确认后操作')"
    .OUTPUTS
        int 选中索引 0~N-1
    .EXAMPLE
        # 单行提示
        Arrow-Menu -Options $opts -Footer1 "  [↑↓]移动  [1-3]直达  [Enter]确认"
    .EXAMPLE
        # 双行提示
        Arrow-Menu -Options $opts -Footer1 "  [↑↓]移动  [1-3]直达  [Enter]确认" -Footer2 "  $(col_a_text_muted '注意：操作不可逆')"
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Options,
        [int]$DefaultIndex = 0,
        # [string]$Title = "",
        [string]$Footer1 = "",
        [string]$Footer2 = "",
        [string[]]$Header = @()   # v7.0：菜单上方固定行（标题/分隔线），窗口缩放重绘时一并恢复
    )

    $selected = $DefaultIndex
    $total = $Options.Count

    # v6.6：菜单实际占用的行数（选项 + Footer1 前的空行 + Footer1 + Footer2），
    #       与 _Arrow-Menu_Draw 里的 $totalLines 算法一致；
    #       取消时用它把光标移到菜单下方，避免调用方的提示覆盖菜单首行
    $menuHeight = $total
    if ($Footer1 -ne "") { $menuHeight += 2 }
    if ($Footer2 -ne "") { $menuHeight += 1 }

    # v6.8：先预留菜单所需行数再反推顶部。
    #   菜单贴近缓冲区底部时，绘制最后一行会触发控制台滚动，
    #   内容整体上移而 $menuTop 仍是旧值，导致后续 ↑↓ 差异更新错位、
    #   出现"同一行有两个高亮"的重影。先写足空行把滚动提前消化掉。
    Write-Host ("`n" * $menuHeight) -NoNewline
    $menuTop = [Console]::CursorTop - $menuHeight

    # 隐藏光标（原生 API，兼容 PS5/ConEmu，避免 ANSI 解析失败）
    $prevCursorVisible = [Console]::CursorVisible
    [Console]::CursorVisible = $false

    # v6.9：记录绘制时的窗口尺寸，用于检测中途缩放
    $lastW = [Console]::WindowWidth
    $lastH = [Console]::WindowHeight

    # 首次绘制
    _Arrow-Menu_Draw -Options $Options -Selected $selected -MenuTop $menuTop -Footer1 $Footer1 -Footer2 $Footer2

    while ($true) {
        # v6.9：窗口缩放后，保存的 $menuTop 失效（控制台重排），
        #       差异更新会写错行造成重影。检测到尺寸变化就清屏并从顶部整块重绘。
        $curW = [Console]::WindowWidth
        $curH = [Console]::WindowHeight
        if ($curW -ne $lastW -or $curH -ne $lastH) {
            $lastW = $curW
            $lastH = $curH
            Clear-Screen
            # v7.0：先恢复调用方的标题/分隔线，再按当前光标位置重绘菜单，
            #       避免清屏后用户看不出这个菜单是干什么的
            foreach ($hLine in $Header) { Write-Host $hLine }
            $menuTop = [Console]::CursorTop
            _Arrow-Menu_Draw -Options $Options -Selected $selected -MenuTop $menuTop -Footer1 $Footer1 -Footer2 $Footer2
            continue
        }

        $key = [Console]::ReadKey($true)

        switch ($key.Key) {

            # 上移（循环）
            ([ConsoleKey]::UpArrow) {
                $prev = $selected
                if ($selected -gt 0) { $selected-- } else { $selected = $total - 1 }
                _Arrow-Menu_Draw -Options $Options -Selected $selected -MenuTop $menuTop -PreviousSelected $prev
            }

            # 下移（循环）
            ([ConsoleKey]::DownArrow) {
                $prev = $selected
                if ($selected -lt ($total - 1)) { $selected++ } else { $selected = 0 }
                _Arrow-Menu_Draw -Options $Options -Selected $selected -MenuTop $menuTop -PreviousSelected $prev
            }

            # 确认
            ([ConsoleKey]::Enter) {
                _Arrow-Menu_Draw -Options $Options -Selected $selected -MenuTop $menuTop -Footer1 $Footer1 -Footer2 $Footer2
                [Console]::CursorVisible = $prevCursorVisible # 恢复光标
                return $selected
            }

            # 取消（v6.6：先把光标移到菜单下方，否则调用方的提示会覆盖菜单首行）
            ([ConsoleKey]::Q) {
                [Console]::CursorVisible = $prevCursorVisible
                _Arrow-Menu_MoveToBottom -MenuTop $menuTop -MenuHeight $menuHeight
                throw [System.OperationCanceledException]::new("Menu cancelled by user")
            }
            ([ConsoleKey]::Escape) {
                [Console]::CursorVisible = $prevCursorVisible
                _Arrow-Menu_MoveToBottom -MenuTop $menuTop -MenuHeight $menuHeight
                throw [System.OperationCanceledException]::new("Menu cancelled by user")
            }

            # 字母/数字直达：优先匹配 Label 中 [x] 括号字母，无则回退 1~9 数字
            default {
                # 尝试字母匹配（Label 含 [x] 格式）
                if ($key.KeyChar -ge 'a' -and $key.KeyChar -le 'z') {
                    $char = $key.KeyChar.ToString().ToUpper()
                    for ($j = 0; $j -lt $total; $j++) {
                        if ($Options[$j] -match '\[([a-zA-Z])\]') {
                            $mc = $Matches[1].ToUpper()
                            if ($mc -eq $char) {
                                # v6.7：直达时先把高亮移到选中项并整块重绘（含 Footer），
                                #       让光标落到菜单下方；否则调用方后续输出会覆盖菜单行，
                                #       表现为"光标停在旧位置 + 与选中项重叠"。
                                $selected = $j
                                _Arrow-Menu_Draw -Options $Options -Selected $selected -MenuTop $menuTop -Footer1 $Footer1 -Footer2 $Footer2
                                [Console]::CursorVisible = $prevCursorVisible
                                return $j
                            }
                        }
                    }
                }
                # v7.0：先按标签里的数字匹配（支持 [0] 这种非连续编号）
                if ($key.KeyChar -ge '0' -and $key.KeyChar -le '9') {
                    $digitKey = [string]$key.KeyChar
                    for ($j = 0; $j -lt $total; $j++) {
                        if ($Options[$j] -match '^\[(\d+)\]') {
                            if ($Matches[1] -eq $digitKey) {
                                $selected = $j
                                _Arrow-Menu_Draw -Options $Options -Selected $selected -MenuTop $menuTop -Footer1 $Footer1 -Footer2 $Footer2
                                [Console]::CursorVisible = $prevCursorVisible
                                return $j
                            }
                        }
                    }
                }
                # 回退数字键 1~9（按位置）
                if ($key.KeyChar -ge '1' -and $key.KeyChar -le '9') {
                    $idx = [int]$key.KeyChar.ToString() - 1
                    if ($idx -ge 0 -and $idx -lt $total) {
                        # v6.7：同字母直达，先移动高亮并重绘，再返回
                        $selected = $idx
                        _Arrow-Menu_Draw -Options $Options -Selected $selected -MenuTop $menuTop -Footer1 $Footer1 -Footer2 $Footer2
                        [Console]::CursorVisible = $prevCursorVisible
                        return $idx
                    }
                }
            }
        }
    }
}

# ============================================================
# v6.6：取消时把光标移到菜单下方
# 参数越界（菜单贴着缓冲区底部）时自动钳位，失败也不抛异常
# ============================================================
function _Arrow-Menu_MoveToBottom {
    param(
        [int]$MenuTop,
        [int]$MenuHeight
    )
    try {
        $row = $MenuTop + $MenuHeight
        $maxRow = [Console]::BufferHeight - 1
        if ($row -gt $maxRow) { $row = $maxRow }
        if ($row -lt 0) { $row = 0 }
        [Console]::SetCursorPosition(0, $row)
    } catch {
        # 极端情况下（缓冲区尺寸变化）不阻断退出流程
    }
}

function _Arrow-Menu_Draw {
    <#
    .SYNOPSIS
        （私有）绘制/刷新菜单，支持全量首次绘制与差异更新
    .DESCRIPTION
        v6.1：首次绘制全量输出；后续移动时仅覆写变更的两行（旧选中+新选中），
        消除逐行清屏重画导致的文字闪烁。
    #>
    param(
        [string[]]$Options,
        [int]$Selected,
        [int]$MenuTop,
        [string]$Footer1 = "",
        [string]$Footer2 = "",
        [int]$PreviousSelected = -1   # v6.1：新增，上一次选中索引，-1 表示首次全量绘制
    )

    $optCount = $Options.Count
    $hasF1 = ($Footer1 -ne "")
    $hasF2 = ($Footer2 -ne "")

    if ($PreviousSelected -eq -1 -or $PreviousSelected -eq $Selected) {
        # ===== 首次绘制 或 强制全量刷新（Enter前）=====
        $totalLines = $optCount + $(if($hasF1){2}else{0}) + $(if($hasF2){1}else{0})

        [Console]::SetCursorPosition(0, $MenuTop)

        # 逐行清屏
        for ($r = 0; $r -lt $totalLines; $r++) {
            Write-Host "$([char]27)[$($MenuTop + 1 + $r);1H$([char]27)[2K" -NoNewline
        }
        [Console]::SetCursorPosition(0, $MenuTop)

        # 绘制所有选项（有 [x] 字母则显示原 Label，无则回退 [数字] 前缀）
        for ($i = 0; $i -lt $optCount; $i++) {
            $displayIdx = $i + 1
            # 检测是否含 [x] 格式（调用方已传入带 [] 的 Label）
            $hasLetter = ($Options[$i] -match '\[([a-zA-Z])\]')
            $hasNumber = ($Options[$i] -match '^\[(\d+)\]')
            if ($hasLetter -or $hasNumber) {
                # v7.0：字母 / 数字标签都由调用方决定，原样显示，
                #       这样 [0] 这类非连续序号不会被按位置重排成 [8]。
                $displayText = $Options[$i]
            } else {
                $rawText = $Options[$i] -replace '^\[\d+\]\s*', ''
                $displayText = "[$displayIdx] $rawText"
            }
            if ($i -eq $Selected) {
                Write-Host "  » $(col_a_sel $displayText)"
            } else {
                Write-Host "    $(col_a_text_muted $displayText)"
            }
        }

        # 绘制底部区域
        if ($hasF1) {
            Write-Host ""
            Write-Host "$Footer1"
        }
        if ($hasF2) {
            Write-Host "$Footer2"
        }
    } else {
        # ===== 差异更新：只覆写旧选中行 + 新选中行 =====
        
        # 覆写旧选中行 → 恢复普通色（自适应字母/数字前缀）
        $oldRow = $MenuTop + 1 + $PreviousSelected
        $oldIdx = $PreviousSelected + 1
        $oldHasLetter = ($Options[$PreviousSelected] -match '\[([a-zA-Z])\]')
        $oldHasNumber = ($Options[$PreviousSelected] -match '^\[(\d+)\]')
        if ($oldHasLetter -or $oldHasNumber) {
            $oldDisplay = $Options[$PreviousSelected]
        } else {
            $oldRaw = $Options[$PreviousSelected] -replace '^\[\d+\]\s*', ''
            $oldDisplay = "[$oldIdx] $oldRaw"
        }
        Write-Host "$([char]27)[${oldRow};1H$([char]27)[2K" -NoNewline
        Write-Host "$([char]27)[${oldRow};1H" -NoNewline
        Write-Host "    $(col_a_text_muted $oldDisplay)" -NoNewline

        # 覆写新选中行 → 高亮（自适应字母/数字前缀）
        $newRow = $MenuTop + 1 + $Selected
        $newIdx = $Selected + 1
        $newHasLetter = ($Options[$Selected] -match '\[([a-zA-Z])\]')
        $newHasNumber = ($Options[$Selected] -match '^\[(\d+)\]')
        if ($newHasLetter -or $newHasNumber) {
            $newDisplay = $Options[$Selected]
        } else {
            $newRaw = $Options[$Selected] -replace '^\[\d+\]\s*', ''
            $newDisplay = "[$newIdx] $newRaw"
        }
        Write-Host "$([char]27)[${newRow};1H$([char]27)[2K" -NoNewline
        Write-Host "$([char]27)[${newRow};1H" -NoNewline
        Write-Host "  » $(col_a_sel $newDisplay)" -NoNewline

        # 光标归位到菜单顶部（保持隐藏光标状态下不干扰）
        [Console]::SetCursorPosition(0, $MenuTop)
    }
}

# ============================================================
# 区块三：预览表配色格式化（v6.6 已移除）
# 原 Format-PreviewLine 从 time_add.py v2.32 移植，
# time_add.ps1 现用自行实现的 Format-TableRow，本函数无任何调用方；
# 且其内部状态名（RENAME-ART / 跳过-已标记）已与现状不符，故整段移除。
# ============================================================

# ============================================================
# 区块四：旧版兼容函数
# 原 PS5 时代的单键输入/等待函数，子模块未升级时可继续调用
# 新代码建议使用 Arrow-Menu（ui.ps1 v4.7+）替代 Get-SingleKey
# ============================================================

function Get-SingleKey {
    <#
    .SYNOPSIS
        等待用户按任意单键并返回字符（小写）
    .DESCRIPTION
        旧版兼容函数，新版菜单请使用 arrow_select 替代。
        等待用户按任意键，返回小写字符。
    .PARAMETER Prompt
        提示文本，显示在等待前
    #>
    param([string]$Prompt)
    Write-Host $Prompt
    $k = [Console]::ReadKey($true)
    return $k.KeyChar.ToString().ToLower()
}

function Wait-AnyKey {
    <#
    .SYNOPSIS
        等待用户按任意键后继续（用于暂停画面）
    .DESCRIPTION
        在需要暂停等待用户确认时调用，按任意键后继续。
    .PARAMETER Prompt
        提示文本，默认 "按任意键继续..."
    #>
    param([string]$Prompt = "`n按任意键继续...")
    Write-Host $Prompt
    [Console]::ReadKey($true) | Out-Null
}


# ============================================================
# 区块五：清屏工具
# 用 ANSI 转义实现，不调 cls / cmd.exe，兼容 UNC 路径
# 供各模块在需要全屏重绘时调用
# ============================================================

function Clear-Screen {
    <#
    .SYNOPSIS
        ANSI 清屏（光标归位 + 清可见区域 + 清滚动缓冲）
    .DESCRIPTION
        使用 ANSI 转义序列实现清屏，不调用 cls/cmd.exe，
        避免 UNC 路径下触发 CMD UNC 检查报错。
        等效于 cls 但完全在 PowerShell 进程内完成。
    #>
    Write-Host "$([char]27)[H$([char]27)[2J$([char]27)[3J" -NoNewline
}

# ==============================================
# 区块六：横向选择器（v5.8）
# 单行水平选项选择器，左右键切换，Enter确认，Esc取消
# 支持四层结构（标题/分割线由外部输出，选项行+Footer提示行）
# 新增 -Footer 参数，由调用方自定义提示行（无多余空行）
# ==============================================
function Select-Horizontal {
    <#
    .SYNOPSIS
        单行水平选项选择器，左右键切换，Enter确认，Esc取消
    .PARAMETER Options
        选项数组，每个元素为 @{ Label="显示文本"; Value="返回值" }
    .PARAMETER InitialIndex
        初始选中索引（默认0）
    .PARAMETER Prompt
        左侧提示文字。传空字符串("")时走四层结构（仅选项行+Footer）
    .PARAMETER Footer
        自定义提示行内容（如操作指南），空则仅选项行
    .OUTPUTS
        选中项的 Value；Esc/取消返回 $null
    #>
    param(
        [Parameter(Mandatory=$true)]
        [array]$Options,
        [int]$InitialIndex = 0,
        [string]$Prompt = "选择",
        [string]$Footer = ""
    )

    $idx = $InitialIndex
    if ($idx -lt 0) { $idx = 0 }
    if ($idx -ge $Options.Count) { $idx = 0 }

    # 拼接选项行内容
    $optLine = ""
    for ($i = 0; $i -lt $Options.Count; $i++) {
        $lbl = $Options[$i].Label
        if ($i -eq $idx) {
            $optLine += (col_a_sel $lbl) + "  "
        } else {
            $optLine += (col_a_text_muted ($lbl + "  "))
        }
    }

    # 首次绘制
    if ($Footer -ne "") {
        Write-Host $Footer
    }
    Write-Host -NoNewline "  $optLine  $([char]27)[K"

    # v6.5-fix U2：统一原生光标隐藏（替代 ANSI ?25l）
    $prevCursorVisible = [Console]::CursorVisible
    [Console]::CursorVisible = $false

    while ($true) {
        $key = $host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        $vk = $key.VirtualKeyCode

        switch ($key.VirtualKeyCode) {
            37 { if ($idx -gt 0) { $idx-- } else { $idx = $Options.Count - 1 } }
            39 { if ($idx -lt $Options.Count - 1) { $idx++ } else { $idx = 0 } }
            13 {
                # v6.5-fix U2+U3：恢复光标，不输出空行
                [Console]::CursorVisible = $prevCursorVisible
                Write-Host ""
                return $Options[$idx].Value
            }
            27 {
                # v6.5-fix U2+U3：恢复光标，不输出空行
                [Console]::CursorVisible = $prevCursorVisible
                Write-Host ""
                return $null
            }
            81 {  # Q 键
                # v6.5-fix U2+U3：恢复光标，不输出空行
                [Console]::CursorVisible = $prevCursorVisible
                Write-Host ""
                return $null
            }
            # 通用直达：字母 + 数字双模
            default {
                $hitIndex = -1

                if ($vk -ge 65 -and $vk -le 90) {
                    $char = [char]$vk
                    for ($i = 0; $i -lt $Options.Count; $i++) {
                        $lbl = $Options[$i].Label
                        if ($lbl -match '\[([a-zA-Z])\]') {
                            $mc = $Matches[1].ToUpper()
                            if ($mc -eq $char) {
                                $hitIndex = $i
                                break
                            }
                        }
                    }
                }

                $numKeys = @(48,49,50,51,52,53,54,55,56,57,96,97,98,99,100,101,102,103,104,105)
                if ($hitIndex -eq -1 -and $vk -in $numKeys) {
                    $numChar = switch ($vk) {
                        48 { "0" } 49 { "1" } 50 { "2" } 51 { "3" } 52 { "4" }
                        53 { "5" } 54 { "6" } 55 { "7" } 56 { "8" } 57 { "9" }
                        96 { "0" } 97 { "1" } 98 { "2" } 99 { "3" } 100 { "4" }
                        101 { "5" } 102 { "6" } 103 { "7" } 104 { "8" } 105 { "9" }
                    }

                    for ($i = 0; $i -lt $Options.Count; $i++) {
                        $lbl = $Options[$i].Label
                        if ($lbl -match '\[(\d+)\]') {
                            if ($Matches[1] -eq $numChar) {
                                $hitIndex = $i
                                break
                            }
                        }
                    }

                    if ($hitIndex -eq -1 -and $numChar -ge "1" -and $numChar -le "9") {
                        $idxByNum = [int]$numChar - 1
                        if ($idxByNum -ge 0 -and $idxByNum -lt $Options.Count) {
                            $hitIndex = $idxByNum
                        }
                    }
                }

                if ($hitIndex -ne -1) {
                    $idx = $hitIndex
                    $optLine = ""
                    for ($i = 0; $i -lt $Options.Count; $i++) {
                        $lbl = $Options[$i].Label
                        if ($i -eq $idx) {
                            $optLine += (col_a_sel $lbl) + "  "
                        } else {
                            $optLine += (col_a_text_muted ($lbl + "  "))
                        }
                    }
                    Write-Host -NoNewline ("`r  " + $optLine + "  $([char]27)[K")
                    # v6.5-fix U2：恢复光标
                    [Console]::CursorVisible = $prevCursorVisible
                    Write-Host ""
                    return $Options[$hitIndex].Value
                }
            }
        }

        # 刷新选项行
        $optLine = ""
        for ($i = 0; $i -lt $Options.Count; $i++) {
            $lbl = $Options[$i].Label
            if ($i -eq $idx) {
                $optLine += (col_a_sel $lbl) + "  "
            } else {
                $optLine += (col_a_text_muted ($lbl + "  "))
            }
        }
        Write-Host -NoNewline ("`r  " + $optLine + "  $([char]27)[K")
    }
}