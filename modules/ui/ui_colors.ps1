<#
============================================================
modules/ui_colors.ps1
TT_Media_Tools UI 配色预览工具（调试界面用）
v2.0：适配 col_c_ 基础色板 + col_a_ 语义别名架构
v3.0：同步 UI 模块迁移至 modules\ui\ui.ps1，修正加载路径，
    对齐最新ui函数
============================================================
dot-source 加载 ui.ps1，逐一输出所有配色函数实际渲染效果
============================================================
#>

# 加载 ui.ps1（v3.0：已迁移至 modules\ui\ui.ps1，兼容从 tt.ps1 同级或 modules\ui 直接调用）
if ($PSScriptRoot -match '\\modules\\ui$') {
    $uiPath = Join-Path $PSScriptRoot "ui.ps1"
} else {
    $uiPath = Join-Path (Split-Path $PSScriptRoot) "ui\ui.ps1"
}
if (-not (Test-Path $uiPath)) {
    Write-Host "ERROR: 找不到 ui.ps1，已尝试路径：$uiPath" -ForegroundColor Red
    exit 1
}
. $uiPath

# ANSI 清屏
Clear-Screen

Write-Host ""
Write-Host "  $(col_a_title '══════════════════════════════════════════════════')"
Write-Host "  $(col_a_title '  TT_Media_Tools UI 配色预览')"
Write-Host "  $(col_a_title '══════════════════════════════════════════════════')"
Write-Host ""

# ==================== 基础色板 col_c_ ====================
Write-Host "  $(col_a_subtitle '── 基础色板 col_c_（物理颜色，按彩虹色谱排列）──')"
Write-Host ""

# 红
Write-Host "  $(col_c_light_red      'col_c_light_red      ：浅红/亮红  →  91m')"
Write-Host "  $(col_c_dark_red       'col_c_dark_red       ：深红/暗红  →  31m')"

# 橙
Write-Host "  $(col_c_bright_orange  'col_c_bright_orange  ：亮橙       →  38;5;214m')"
Write-Host "  $(col_c_warm_orange    'col_c_warm_orange    ：暖橙棕     →  38;5;172m')"

# 黄
Write-Host "  $(col_c_light_yellow   'col_c_light_yellow   ：浅黄/亮黄  →  93m')"
Write-Host "  $(col_c_dark_yellow    'col_c_dark_yellow    ：暗黄/土黄  →  38;5;130m')"

# 绿
Write-Host "  $(col_c_grass_green    'col_c_grass_green    ：草绿/亮绿  →  92m')"
Write-Host "  $(col_c_dark_green     'col_c_dark_green     ：深绿/暗绿  →  32m')"

# 青
Write-Host "  $(col_c_cyan           'col_c_cyan           ：亮青       →  96m')"
Write-Host "  $(col_c_dark_cyan      'col_c_dark_cyan      ：深青       →  36m')"

# 蓝
Write-Host "  $(col_c_light_blue     'col_c_light_blue     ：浅蓝/亮蓝  →  94m')"
Write-Host "  $(col_c_dark_blue      'col_c_dark_blue      ：深蓝/暗蓝  →  34m')"

# 紫
Write-Host "  $(col_c_light_purple   'col_c_light_purple   ：浅紫/洋红  →  95m')"
Write-Host "  $(col_c_dark_purple    'col_c_dark_purple    ：深紫/暗紫  →  38;5;129m')" #避坑35m（PS5会看不到）

# 灰/白/黑
Write-Host "  $(col_c_light_gray     'col_c_light_gray     ：浅灰       →  37m')"
Write-Host "  $(col_c_dark_gray      'col_c_dark_gray      ：深灰       →  90m')"
Write-Host "  $(col_c_white          'col_c_white          ：纯白       →  97m')"
Write-Host "  $(col_c_black          'col_c_black          ：纯黑       →  30m')"

Write-Host ""
Write-Host "  $(col_a_line (sep_weak))"
Write-Host ""

# ==================== 语义别名 col_a_ ====================
Write-Host "  $(col_a_subtitle '── 语义别名 col_a_（UI视觉层级，指向基础色）──')"
Write-Host ""

Write-Host "  $(col_a_title      'col_a_title        ：主标题      → col_c_cyan')"
Write-Host "  $(col_a_subtitle   'col_a_subtitle     ：副标题      → col_c_light_blue')"
Write-Host "  $(col_a_text       'col_a_text         ：正文        → col_c_light_gray')"
Write-Host "  $(col_a_text_muted 'col_a_text_muted   ：弱化正文    → col_c_dark_gray')"
Write-Host "  $(col_a_sel        'col_a_sel          ：选中项      → 93;100m 亮黄+深灰底')"
Write-Host "  $(col_a_hover      'col_a_hover        ：悬停提示    → col_c_light_blue')"
Write-Host "  $(col_a_success    'col_a_success      ：成功/确认   → col_c_grass_green')"
Write-Host "  $(col_a_warning    'col_a_warning      ：警告/注意   → col_c_light_yellow')"
Write-Host "  $(col_a_error      'col_a_error        ：错误/危险   → col_c_light_red')"
Write-Host "  $(col_a_line       'col_a_line         ：分割线/边框 → col_c_dark_gray')"
Write-Host "  $(col_a_bold       'col_a_bold         ：加粗强调    → 1m 纯加粗')"

Write-Host ""
Write-Host "  $(col_a_line (sep_weak))"
Write-Host ""

# ==================== 分隔线对照 ====================
Write-Host "  $(col_a_subtitle '── 分隔线对照 ──')"
Write-Host ""
Write-Host "  $(col_a_text 'sep        ：')$(col_a_line (sep))"
Write-Host "  $(col_a_text 'sep_weak   ：')$(col_a_line (sep_weak))"

Write-Host ""
Write-Host "  $(col_a_line (sep_weak))"
Write-Host ""

# ==================== 选中项对照 ====================
Write-Host "  $(col_a_subtitle '── 选中项对照 ──')"
Write-Host ""
Write-Host "  » [1] $(col_a_sel '这是选中项效果（亮黄字 + 深灰底）')"
Write-Host "    [2] $(col_a_text '这是未选中项效果（浅灰正文）')"

Write-Host ""
Write-Host "  $(col_a_line (sep_weak))"
Write-Host ""

# ==================== 状态行对照 ====================
Write-Host "  $(col_a_subtitle '── 状态行对照 ──')"
Write-Host ""
Write-Host "  $(col_a_success '  [OK] 重命名完成！')"
Write-Host "  $(col_a_warning '  [!] 已标记，将重处理')"
Write-Host "  $(col_a_error   '  [X] ffprobe 未找到！')"
Write-Host "  $(col_a_text_muted '  [i] 按任意键继续...')"

Write-Host ""
Write-Host "  $(col_a_line (sep_weak))"
Write-Host ""

# ==================== 加粗叠加演示（v2.1 对比版） ====================
Write-Host "  $(col_a_subtitle '── 加粗叠加演示 ──')"
Write-Host ""

# 正文对照：无加粗 vs 加粗（同一段内容，仅差加粗提亮）
Write-Host "  $(col_a_text '无加粗正文：这段是普通浅灰正文，用于对比')"
Write-Host "  $(col_a_bold ('有加粗正文：这段是加粗+提亮纯白，视觉差异明显'))"

Write-Host ""

# 标题色对照
Write-Host "  $(col_a_text '无加粗标题色：')$(col_a_title '普通标题色，无加粗')"
Write-Host "  $(col_a_bold ('加粗+标题色：' + (col_a_title '标题色叠加加粗提亮')))"

# ... 前面所有预览输出 ...

# ConsoleColor 对比表（放在 ReadKey 之前）
Write-Host ""
Write-Host "  对比，-ForegroundColor颜色表"
foreach ($color in [enum]::GetValues([System.ConsoleColor])) {
    Write-Host ("  " + $color.ToString().PadRight(12)) -ForegroundColor $color -BackgroundColor Black -NoNewline
    Write-Host ("=" * 20) -ForegroundColor $color
}

# 最后才等按键
Write-Host ""
Write-Host "  $(col_a_line (sep_weak))"
Write-Host ""
Write-Host "  $(col_a_text_muted '按任意键退出...')"
[Console]::ReadKey($true) | Out-Null

