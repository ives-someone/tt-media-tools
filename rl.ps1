<#
快捷方式路径批量替换【问号乱码跳过版 PS5.1兼容】
PS5.1兼容，推荐前缀自动复制剪贴板；确认环节一键按键A/Y，无需回车
规则：读取Target路径只要包含 ? 就直接跳过；无?则正常参与替换
新增：扫描阶段统计 总lnk数量 / 乱码跳过数量
新增开关：选择是否递归扫描子文件夹(Y递归/N仅当前目录)
#>
function Get-LnkWScript {
    param([Parameter(Mandatory)][string]$Path)
    $sl = New-Object -ComObject WScript.Shell
    $sc = $sl.CreateShortcut($Path)
    return [PSCustomObject]@{
        Target  = $sc.TargetPath
        WorkDir = $sc.WorkingDirectory
        Args    = $sc.Arguments
    }
}
# 等待单个按键，无需回车
function Wait-KeyPress {
    param(
        [string]$Prompt
    )
    Write-Host "$Prompt " -NoNewline
    $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    Write-Host $key.Character
    return $key.Character.ToString().ToUpper()
}
# ====================== 主程序 ======================
$scanRoot = $PWD.Path
Write-Host "========================================"
Write-Host "快捷方式路径批量替换"
Write-Host "Emoji路径显示为问号乱码，会跳过"
Write-Host "扫描目录：$scanRoot"
Write-Host "========================================"

# 新增：递归选择开关，默认Y
$recurseOpt = Wait-KeyPress -Prompt "`n是否扫描子文件夹内快捷方式？【Y】包含子文件夹(默认) 【N】仅当前文件夹"
$recurseParam = ($recurseOpt -ne "N") # 只要不是N，一律启用递归，Y/其他按键都走递归

Write-Host "`n正在扫描 *.lnk ..."
$lnkList = Get-ChildItem -Path $scanRoot -Filter *.lnk -Recurse:$recurseParam -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -notmatch '_backup\.lnk$'
}
$totalLnkCount = $lnkList.Count
$skipByGarbleCount = 0 # 乱码跳过计数器
Write-Host "共找到 $totalLnkCount 个待处理快捷方式（排除*_backup.lnk）`n"
Write-Host "==== 当前快捷方式目标清单 ===="
$candidates = @()
foreach($f in $lnkList){
    try{
        $info = Get-LnkWScript -Path $f.FullName
        # 核心判断：目标路径含有 ? 号 → 跳过
        if($info.Target -match '\?'){
            $skipByGarbleCount +=1
            Write-Host "$($f.Name) -> $($info.Target) 【检测到乱码，可能是PS无法识别的emoji，跳过】" -ForegroundColor Red
            continue
        }
        Write-Host "$($f.Name) -> $($info.Target)"
        $candidates += [PSCustomObject]@{
            FileFullName = $f.FullName
            OrigTarget   = $info.Target
            OrigWorkDir  = $info.WorkDir
            OrigArgs     = $info.Args
        }
    }
    catch{
        Write-Host "$($f.Name) 读取失败：$_" -ForegroundColor Red
    }
}
# 输出扫描统计汇总
Write-Host "`n----------扫描统计汇总----------"
Write-Host "扫描到快捷方式总数：$totalLnkCount"
Write-Host "检测到乱码跳过数量：$skipByGarbleCount"
Write-Host "可参与替换有效快捷方式：$($candidates.Count)"
Write-Host "--------------------------------`n"
if($candidates.Count -eq 0){
    Write-Host "`n没有可读取的有效快捷方式，按任意键退出"
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}
# 取第一条有效路径，截断至最后一个反斜杠
$firstTarget = $candidates[0].OrigTarget
$lastSlashIdx = $firstTarget.LastIndexOf('\')
if ($lastSlashIdx -gt 0) {
    $suggestPrefix = $firstTarget.Substring(0, $lastSlashIdx + 1)
} else {
    $suggestPrefix = $firstTarget
}
# PS5.1：复制推荐前缀到剪贴板
Set-Clipboard $suggestPrefix
Write-Host "`n========================================"
Write-Host "💡推荐原始前缀已自动复制到剪贴板：$suggestPrefix"
Write-Host "💡输入框处 Ctrl+V 粘贴，按需删减"
$oldPrefix = Read-Host "输入【原始路径前缀】"
$newPrefix = Read-Host "输入【替换后的新前缀】"
$changeList = @()
foreach($item in $candidates){
    if($item.OrigTarget -and $item.OrigTarget.StartsWith($oldPrefix, [System.StringComparison]::OrdinalIgnoreCase)){
        $newTarget  = $item.OrigTarget.Replace($oldPrefix,$newPrefix)
        $newWorkDir = $item.OrigWorkDir.Replace($oldPrefix,$newPrefix)
        $newArgs    = $item.OrigArgs.Replace($oldPrefix,$newPrefix)
        $changeList += [PSCustomObject]@{
            File    = $item.FileFullName
            OldTgt  = $item.OrigTarget
            NewTgt  = $newTarget
            NewWD   = $newWorkDir
            NewArg  = $newArgs
        }
    }
}
Write-Host "`n===== 预览将要修改的项目 ====="
if($changeList.Count -eq 0){
    Write-Host "✅无匹配前缀的快捷方式，按任意键退出"
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}
$changeList | Format-Table File,OldTgt,NewTgt -AutoSize
# 一键按键，无需回车
$ans = Wait-KeyPress -Prompt "确认执行替换？【A】替换并备份原文件，【Y】直接替换不备份，其他按键放弃"
if($ans -notin 'A','Y'){
    Write-Host "已放弃，无修改，按任意键关闭"
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit
}
Write-Host "`n开始处理..."
foreach($row in $changeList){
    try{
        if($ans -eq 'A'){
            $bak = $row.File -replace '\.lnk$','_backup.lnk'
            Copy-Item -Path $row.File -Destination $bak -Force
            Write-Host "已备份: $bak"
        }
        $sl = New-Object -ComObject WScript.Shell
        $sc = $sl.CreateShortcut($row.File)
        $sc.TargetPath      = $row.NewTgt
        $sc.WorkingDirectory = $row.NewWD
        $sc.Arguments       = $row.NewArg
        $sc.Save()
        Write-Host "✅修改成功: $($row.File)"
    }
    catch{
        Write-Host "❌修改失败 $($row.File) : $_" -ForegroundColor Red
    }
}
Write-Host "`n===== 全部任务完成，按任意键关闭 ====="
Write-Host "`n===== 快捷方式路径中如果有乱码/emoji内容，可用独立软件LiNK Fixer操作替换 ====="
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
