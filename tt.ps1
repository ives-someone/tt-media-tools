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
    Write-Host "【1】 扫描提取视频时长并按多种需求添加到视频文件名里"        # 跳转到二级菜单1
    Write-Host "【2】 识别文件名内视频时长文字并按多种需求清理"          # 跳转到二级菜单2
    Write-Host "【3】 NFO同步：刷新同步与视频同名的NFO文件内部名称"  # nfo同步模块 nfo.ps1
	Write-Host "【4】 递归扫描NFO，提取信息导出CSV，便于筛查排序" 		   # 遍历nfo生成csv模块 nfo_output.ps1
    Write-Host "【5】 TOP XX 的视频/文件查找和输出_新版双模式"  # maxm查找模块 maxm.ps1
    Write-Host "【6】 快捷方式lnk目标路径批量替换，不完善，不认乱码"          # 快捷方式路径批量替换，暂不支持带emoji目标路径 rl.ps1
    Write-Host "【7】 小工具：文件扩展名规整，将大写扩展名批量转换为小写"        # ext_lower.ps1
    Write-Host "【8】 小工具：文件名、文件夹内汉字数字批量替换为阿拉伯数字"         # cn_num2seq.ps1
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
                Write-Host "【1】 提取视频时长添加到文件名末尾"   # time_add_end.ps1
                Write-Host "【2】 提取视频时长添加到文件名开头"       # time_add_begin.ps1
                Write-Host "【3】 不保留原名，提取视频时长作为新文件名" # time_add_only.ps1
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
                Write-Host "【1】 自动识别文件名内任意位置时间标记并保留，删除其他文件名内容"            # time_clr_auto.ps1
                Write-Host "【2】 识别文件名末尾时间标记，删除其他文件名内容"   # time_clr_end.ps1
                Write-Host "【3】 识别文件名开头时间标记，删除其他文件名内容"   # time_clr_begin.ps1
                Write-Host "【4】 识别并去除文件名中的时间部分"   # time_clr_remove.ps1
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
                    "4" {
                        Write-Host "`n`n"
                        & (Join-Path $ScriptDir "time_clr_remove.ps1")
                    }
                    default { break menu2 }
                }
            }
        }
        "3" {
            Write-Host "`n`n"
            & (Join-Path $ScriptDir "nfo.ps1")
        }
        "4" {
            Write-Host "`n`n"
            & (Join-Path $ScriptDir "nfo_output.ps1")
        }
        "5" {
            Write-Host "`n`n"
            & (Join-Path $ScriptDir "maxm.ps1")
        }
        "6" {
            Write-Host "`n`n"
            & (Join-Path $ScriptDir "rl.ps1")
        }
        "7" {
            Write-Host "`n`n"
            & (Join-Path $ScriptDir "ext_lower.ps1")
        }
        "8" {
            Write-Host "`n`n"
            & (Join-Path $ScriptDir "cn_num2seq.ps1")
		}
        "q" { return }
        default {
            Write-Host "`n无效选项！" -ForegroundColor Yellow
            Wait-AnyKey
        }
    }
}


