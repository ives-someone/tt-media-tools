<#
视频重命名工具集 主菜单 tt.ps1
修复：使用$PSScriptRoot获取脚本目录，解决相对路径找不到子脚本的问题
#>
# 获取当前tt.ps1所在目录（核心修复）
$ScriptDir = $PSScriptRoot

function Get-SingleKey {
    param([string]$Prompt)
    Write-Host $Prompt
    $k = [Console]::ReadKey($true)
    return $k.KeyChar.ToString().ToLower()
}
function Wait-AnyKey {
    param([string]$Prompt="`n按任意键继续...")
    Write-Host $Prompt
    [Console]::ReadKey($true) | Out-Null
}
while ($true) {
    Write-Host "`n=============================================="
    Write-Host "          视频重命名工具集 TT 入口"
    Write-Host "=============================================="
    Write-Host "【1】 视频文件名扫描添加时间"        # 跳转到二级菜单1
    Write-Host "【2】 含时长视频文件名清理"          # 跳转到二级菜单2
    Write-Host "【3】 大写文件名扩展改成小写"        # ext_lower.ps1
    Write-Host "【4】 汉字数字重命名为01~10"         # cn_num2seq.ps1
    Write-Host "【5】 NFO同步：刷新同名nfo内部名称"  # nfo同步模块
    Write-Host ""
    Write-Host "【Q】退出程序"
    Write-Host "=============================================="
    $sel = Get-SingleKey "请按数字键选择："
    switch ($sel) {
        "1" {
            :menu1 while ($true) {
                Write-Host "`n=============================================="
                Write-Host "        扫描添加时间 - 二级菜单"
                Write-Host "=============================================="
                Write-Host "【1】 保留原名，时长追加到新文件名末尾"   # time_add_end.ps1
                Write-Host "【2】 保留原名，时长放新文件名开头"       # time_add_begin.ps1
                Write-Host "【3】 不保留原名，直接用时长作为新文件名" # time_add_only.ps1
                Write-Host ""
                Write-Host "【任意键返回上级菜单】"
                Write-Host "=============================================="
                $subSel = Get-SingleKey "请按数字键选择："
                switch ($subSel) {
                    "1" { & (Join-Path $ScriptDir "time_add_end.ps1") }
                    "2" { & (Join-Path $ScriptDir "time_add_begin.ps1") }
                    "3" { & (Join-Path $ScriptDir "time_add_only.ps1") }
                    default { break menu1 }
                }
            }
        }
        "2" {
            :menu2 while ($true) {
                Write-Host "`n=============================================="
                Write-Host "        清理时长文件名 - 二级菜单"
                Write-Host "=============================================="
                Write-Host "【1】 自动识别文件名中的时间"            # time_clr_auto.ps1
                Write-Host "【2】 视频文件名里的时长在文件名末尾"   # time_clr_end.ps1
                Write-Host "【3】 视频文件名里的时长在文件名开头"   # time_clr_begin.ps1
                Write-Host ""
                Write-Host "【任意键返回上级菜单】"
                Write-Host "=============================================="
                $subSel = Get-SingleKey "请按数字键选择："
                switch ($subSel) {
                    "1" { & (Join-Path $ScriptDir "time_clr_auto.ps1") }
                    "2" { & (Join-Path $ScriptDir "time_clr_end.ps1") }
                    "3" { & (Join-Path $ScriptDir "time_clr_begin.ps1") }
                    default { break menu2 }
                }
            }
        }
        "3" {
            & (Join-Path $ScriptDir "ext_lower.ps1")
        }
        "4" {
            & (Join-Path $ScriptDir "cn_num2seq.ps1")
        }
        "5" {
            & (Join-Path $ScriptDir "nfo.ps1")
        }
        "q" { return }
        default {
            Write-Host "`n无效选项！" -ForegroundColor Yellow
            Wait-AnyKey
        }
    }
}
