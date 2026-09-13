<#
功能：
1. 当前目录【文件+一级子文件夹】，不递归更深子目录
2. 文件名/文件夹名汉字：一→01，二→02，三→03，四→04，五→05，六→06，七→07，八→08，九→09，十→10
3. -LiteralPath 兼容NAS带[]的网络共享路径，PS5.1原生支持
4. 一键按键：y/u无需回车，修复op_Addition数组报错
#>
$charMap = @{
    "一" = "01"
    "二" = "02"
    "三" = "03"
    "四" = "04"
    "五" = "05"
    "六" = "06"
    "七" = "07"
    "八" = "08"
    "九" = "09"
    "十" = "10"
}
$renameLog = @()

Write-Host "`n===== 扫描当前目录【文件+一级子文件夹】：$PWD =====" -ForegroundColor Cyan
$items = Get-ChildItem -LiteralPath $PWD -Force
$changeList = @()

foreach ($item in $items) {
    $oldName = $item.Name
    $newName = $oldName
    foreach ($k in $charMap.Keys) {
        $newName = $newName -replace $k, $charMap[$k]
    }
    if ($newName -ne $oldName) {
        $changeList += [PSCustomObject]@{
            ParentDir = $item.DirectoryName
            OldName   = $oldName
            NewName   = $newName
            Type      = if ($item.PSIsContainer) { "文件夹" } else { "文件" }
        }
    }
}

if ($changeList.Count -eq 0) {
    Write-Host "`n没有匹配到需要修改的文件/文件夹！" -ForegroundColor Yellow
    Write-Host "`n按任意键退出..."
    $null = [Console]::ReadKey($true)
    exit
}

Write-Host "`n===== 预览待修改列表 =====" -ForegroundColor Green
$changeList | Format-Table Type, OldName, NewName -AutoSize

Write-Host "`n确认执行重命名？【按 Y 执行，其他键退出】"
$key = [Console]::ReadKey($true)
if ($key.Key.ToString() -ne "Y") {
    Write-Host "已取消操作"
    Write-Host "`n按任意键退出..."
    $null = [Console]::ReadKey($true)
    exit
}

# ==========修复这里：@()强制转为数组，避免空变量相加报错==========
$foldersList = @($changeList | Where-Object { $_.Type -eq "文件夹" })
$filesList   = @($changeList | Where-Object { $_.Type -eq "文件" })
$changeList  = $filesList + $foldersList
[Array]::Reverse($changeList)

Write-Host "`n===== 开始重命名（倒序执行） =====" -ForegroundColor Cyan
foreach ($item in $changeList) {
    $oldFull = Join-Path $item.ParentDir $item.OldName
    if (Test-Path -LiteralPath $oldFull) {
        Rename-Item -LiteralPath $oldFull -NewName $item.NewName -Force
        $renameLog += [PSCustomObject]@{
            ParentDir = $item.ParentDir
            OldName   = $item.OldName
            NewName   = $item.NewName
            Type      = $item.Type
        }
        Write-Host "[$($item.Type)] $($item.OldName) → $($item.NewName)"
    }
    else {
        Write-Host "⚠️ 跳过，找不到：$oldFull" -ForegroundColor Red
    }
}

Write-Host "`n✅ 重命名完成！" -ForegroundColor Green
Write-Host "输入 U 撤销本次全部改名，其他任意键直接退出："
$keyUndo = [Console]::ReadKey($true)
if ($keyUndo.Key.ToString() -eq "U") {
    Write-Host "`n===== 正在撤销 =====" -ForegroundColor Cyan
    [Array]::Reverse($renameLog)
    foreach ($rec in $renameLog) {
        $currentPath = Join-Path $rec.ParentDir $rec.NewName
        if (Test-Path -LiteralPath $currentPath) {
            Rename-Item -LiteralPath $currentPath -NewName $rec.OldName -Force
            Write-Host "[$($rec.Type)] $($rec.NewName) → $($rec.OldName)"
        }
        else {
            Write-Host "⚠️ 撤销时找不到：$currentPath" -ForegroundColor Red
        }
    }
    Write-Host "`n✅ 撤销成功！" -ForegroundColor Green
}

