<#
视频重命名工具集 主菜单 tt.ps1
修复：使用$PSScriptRoot获取脚本目录，解决相对路径找不到子脚本的问题
#>
# 启动阶段：检测系统全局残留 ffprobe.exe
$runningFfprobe = @(Get-Process -Name "ffprobe" -ErrorAction SilentlyContinue)
if ($runningFfprobe.Count -gt 0) {
    Write-Host "`n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Yellow
    Write-Host "⚠️ 检测到本机存在 $($runningFfprobe.Count) 个正在运行 ffprobe.exe 进程" -ForegroundColor Yellow
    Write-Host "⚠️ 警告：无法区分是上一次脚本遗留僵尸进程，" -ForegroundColor Yellow
    Write-Host "⚠️ 还是格式工厂 / QuickFFSync / 用户手动启动的转码任务！" -ForegroundColor Yellow
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!`n" -ForegroundColor Yellow
    # 清空键盘脏缓冲区
    while ($Host.UI.RawUI.KeyAvailable) { $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") }
    $cleanOpt = Wait-KeyPress -Prompt "【Y】全部终止本机所有ffprobe(高风险)；【N】保留进程继续运行(默认)"
    if ($cleanOpt -ieq "Y") {
        Write-Host ">>> 正在终止全部 ffprobe.exe ..."
        $runningFfprobe | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Host ">>> 已执行终止操作`n"
    }
    else {
        Write-Host ">>> 保留现有ffprobe进程，继续脚本`n"
    }
}
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
    Write-Host "        TT_Media_Tools 视频重命名工具集       "
    Write-Host "=============================================="
    Write-Host "【1】 视频文件名扫描添加时间"        # 跳转到二级菜单1
    Write-Host "【2】 含时长视频文件名清理"          # 跳转到二级菜单2
    Write-Host "【3】 大写文件名扩展改成小写"        # ext_lower.ps1
    Write-Host "【4】 汉字数字重命名为01~10"         # cn_num2seq.ps1
    Write-Host "【5】 NFO同步：刷新同名nfo内部名称"  # nfo同步模块 nfo.ps1
    Write-Host "【6】 查找最大体积/码率/分辨率文件并排序"   # max查找模块 max.ps1
    Write-Host "【7】 快捷方式路径批量替换"          # 快捷方式路径批量替换，暂不支持带emoji目标路径 rl.ps1
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
                    "1" {
                        Write-Host "`n`n"
                        & (Join-Path $ScriptDir "time_add_end.ps1")
                    }
                    "2" {
                        Write-Host "`n`n"
                        & (Join-Path $ScriptDir "time_add_begin.ps1")
                    }
                    "3" {
                        Write-Host "`n`n"
                        & (Join-Path $ScriptDir "time_add_only.ps1")
                    }
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
                    "1" {
                        Write-Host "`n`n"
                        & (Join-Path $ScriptDir "time_clr_auto.ps1")
                    }
                    "2" {
                        Write-Host "`n`n"
                        & (Join-Path $ScriptDir "time_clr_end.ps1")
                    }
                    "3" {
                        Write-Host "`n`n"
                        & (Join-Path $ScriptDir "time_clr_begin.ps1")
                    }
                    default { break menu2 }
                }
            }
        }
        "3" {
            Write-Host "`n`n"
            & (Join-Path $ScriptDir "ext_lower.ps1")
        }
        "4" {
            Write-Host "`n`n"
            & (Join-Path $ScriptDir "cn_num2seq.ps1")
        }
        "5" {
            Write-Host "`n`n"
            & (Join-Path $ScriptDir "nfo.ps1")
        }
        "6" {
            Write-Host "`n`n"
            & (Join-Path $ScriptDir "max.ps1")
        }
        "7" {
            Write-Host "`n`n"
            & (Join-Path $ScriptDir "rl.ps1")
        }
        "q" { return }
        default {
            Write-Host "`n无效选项！" -ForegroundColor Yellow
            Wait-AnyKey
        }
    }
}
