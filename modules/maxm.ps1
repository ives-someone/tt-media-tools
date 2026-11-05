<#
maxm.ps1 — top_finder.ps1 的兼容入口

保留原短名的原因：
  1. 命令行直接调用方便（maxm 比 top_finder 短）
  2. 「自然语言 → maxm.ps1 参数映射 Prompt 模板.txt」里写的就是 maxm.ps1，
     AI 生成的命令形如：maxm.ps1 -Mode B -Meta -Top 20
  3. AI 驱动模式有独立调用需求，不一定要经过 tt 主菜单

实际逻辑全部在 top_finder.ps1，本文件只做参数转发。
#>
& (Join-Path $PSScriptRoot 'top_finder.ps1') @args