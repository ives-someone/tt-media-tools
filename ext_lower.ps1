<#
le.ps1
扩展名大写转小写，直接读取shell当前位置，不做路径对象转字符串
修改：确认改为单键ReadKey，按y确认无需回车；其他按键取消
#>
Write-Host "`n【处理目录】$(Get-Location)`n" -ForegroundColor Cyan
# 无参数Get-ChildItem：直接读取powershell内部当前位置，避开LiteralPath解析bug
$files = Get-ChildItem -File
$todoList = @()
foreach ($f in $files) {
    if ($f.Extension -cmatch '[A-Z]') {
        $newExt = $f.Extension.ToLower()
        $newName = $f.BaseName + $newExt
        $todoList += [PSCustomObject]@{
            Source     = $f.Name
            Target     = $newName
            FullSource = $f.FullName
        }
    }
}
if ($todoList.Count -eq 0) {
    Write-Host "没有需要转换大写扩展名的文件，退出。`n" -ForegroundColor Gray
    pause
    exit
}
Write-Host "=====预览：将要执行的重命名=====`n"
$todoList | Format-Table Source,Target -AutoSize
Write-Host "`n共 $($todoList.Count) 个文件待处理"

# 单键确认，无需回车
Write-Host "确认执行重命名？按 y 确认，其他按键取消" -NoNewline
$kIn = [Console]::ReadKey($true)
$opt = $kIn.KeyChar.ToString().ToLower()
Write-Host "`n"

if ($opt -ne "y") {
    Write-Host "已取消操作" -ForegroundColor Yellow
    pause
    exit
}

Write-Host "`n开始重命名...`n" -ForegroundColor Green
foreach ($item in $todoList) {
    try {
        Rename-Item -LiteralPath $item.FullSource -NewName $item.Target -ErrorAction Stop
        Write-Host "$($item.Source) --> $($item.Target)"
    }
    catch {
        Write-Host "[ERROR] $($item.Source) 失败：$($_.Exception.Message)" -ForegroundColor Red
    }
}
Write-Host "`n全部完成`n" -ForegroundColor Cyan
pause

