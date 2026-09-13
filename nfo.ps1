<#
nfo.ps1
功能：刷新与视频同名的nfo内部 <title> <sorttitle> = 视频basename(不带后缀)
适配PowerShell 5.1
作用：视频改名后，nfo内部标题还是旧名字，内外不一致，一键强制同步
注意：
1. 仅配对：视频.mp4 ↔ 同名视频.nfo；poster/fanart/thumb类(含-poster1带数字)附属nfo直接跳过
2. s=预览模式，只输出日志不修改文件；y=实际写入nfo；其它按键退出
3. ⚠本脚本只改nfo文本，**不修改任何文件名，没有撤销功能！**
4. 找不到<title>/<sorttitle>标签则不会新增标签，保持原文件不变
#>
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

$videoExts = @(
    'mp4','MP4','Mp4',
    'mov','MOV','Mov',
    'mkv','MKV','Mkv',
    'avi','AVI','Avi',
    'flv','FLV','Flv',
    'wmv','WMV','Wmv',
    'm4v','M4V','M4v',
    'ts','TS','Ts',
    'mpg','MPG','Mpg',
    'mpeg','MPEG','Mpeg',
    'f4v','F4V','F4v',
    'm2ts','M2TS','M2ts',
    'mts','MTS','Mts'
)

# 1.扫描当前目录所有视频
$allFiles = Get-ChildItem -File .
$videoList = $allFiles | Where-Object { $_.Extension.TrimStart('.') -in $videoExts }

$workItems = @()
foreach ($vid in $videoList) {
    $vidBase = $vid.BaseName
    $nfoPath = Join-Path $vid.Directory.FullName "$vidBase.nfo"
    if (Test-Path -LiteralPath $nfoPath) {
        $nfoObj = Get-Item -LiteralPath $nfoPath
        # 过滤附属nfo，和整套脚本正则统一
        if($vidBase -match '-(poster|cover|thumb|fanart|banner|clearart|clearlogo|logo|landscape|backdrop|disc|cdart|movie|default)\d*$'){
            continue
        }
        # 读取nfo原有title/sorttitle用于预览日志
        $rawText = [System.IO.File]::ReadAllText($nfoObj.FullName, [System.Text.Encoding]::UTF8)
        $oldTitle = $null
        $oldSortTitle = $null
        if($rawText -match '<title\b[^>]*>(.*?)</title>'){ $oldTitle = $matches[1] }
        if($rawText -match '<sorttitle\b[^>]*>(.*?)</sorttitle>'){ $oldSortTitle = $matches[1] }

        $workItems += [PSCustomObject]@{
            VideoName  = $vid.Name
            NfoFile    = $nfoObj.Name
            NfoFullPath= $nfoObj.FullName
            NewBaseName= $vidBase
            OldTitle   = $oldTitle
            OldSortTitle=$oldSortTitle
        }
    }
}

if($workItems.Count -eq 0){
    Write-Host "`n[!]没有找到【视频+同名nfo】配对文件，退出。" -ForegroundColor Yellow
    Wait-AnyKey
    exit 0
}

# 打印预览表格
Write-Host "`n==================== NFO内部名称同步预览 ====================" -ForegroundColor Cyan
Write-Host ("{0,-30} {1,-22} {2,-22}" -f "视频文件","原<title>","→目标值")
Write-Host "-------------------------------------------------------------------------"
foreach($wi in $workItems){
    $dispOldTitle = if($wi.OldTitle -ne $null) {$wi.OldTitle} else {"[无标签]"}
    Write-Host ("{0,-30}" -f $wi.VideoName) -NoNewline
    Write-Host ("{0,-22}" -f $dispOldTitle) -ForegroundColor Gray -NoNewline
    Write-Host ("→ {0}" -f $wi.NewBaseName) -ForegroundColor Yellow
}
Write-Host "-------------------------------------------------------------------------"
Write-Host "一共 $($workItems.Count) 组视频-nfo配对待处理" -ForegroundColor Cyan
Write-Host "=========================================================================`n" -ForegroundColor Cyan

$confirm = Get-SingleKey "操作选择：【y】实际修改nfo文件；【s】输出日志log，自己手动改（不改动nfo）；其他按键直接退出"
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $PWD.Path "nfo_sync_log_$ts.log"

if($confirm -eq 's'){
    # 仅导出日志，不修改
    $lines=@()
    $lines += "# nfo同步预览日志；s模式，未修改任何nfo"
    $lines += "# 视频`tNfo文件`t旧title`t旧sorttitle`t目标新值"
    foreach($wi in $workItems){
        $ot = if($wi.OldTitle -ne $null) {$wi.OldTitle} else {""}
        $ost = if($wi.OldSortTitle -ne $null) {$wi.OldSortTitle} else {""}
        $lines += "$($wi.VideoName)`t$($wi.NfoFile)`t$ot`t$ost`t$($wi.NewBaseName)"
    }
    $lines | Out-File $logFile -Encoding utf8
    Write-Host "`n✅预览日志已输出：$logFile，本次不会修改nfo。" -ForegroundColor Green
    Wait-AnyKey
    exit 0
}
elseif ($confirm -ne 'y') {
    Write-Host "[!]已取消操作。" -ForegroundColor Yellow
    Wait-AnyKey
    exit 0
}

# 真正执行修改
$logLines = @()
$logLines += "# nfo同步执行日志；已修改nfo <title> <sorttitle> 为视频basename"
$logLines += "# 视频`tNfo文件`t旧title`t旧sorttitle`t目标新值"

Write-Host "`n=====开始刷新nfo内部标签 =====" -ForegroundColor Cyan
foreach($wi in $workItems){
    try{
        $text = [System.IO.File]::ReadAllText($wi.NfoFullPath, [System.Text.Encoding]::UTF8)
        $ot = $wi.OldTitle
        $ost = $wi.OldSortTitle
        # 只替换存在的同行标签；不存在标签则跳过，不会新增
        if($text -match '<title>.*</title>'){
            $text = $text -replace '<title>.*</title>',"<title>$($wi.NewBaseName)</title>"
        }
        if($text -match '<sorttitle>.*</sorttitle>'){
            $text = $text -replace '<sorttitle>.*</sorttitle>',"<sorttitle>$($wi.NewBaseName)</sorttitle>"
        }
        [System.IO.File]::WriteAllText($wi.NfoFullPath, $text, [System.Text.Encoding]::UTF8)
        Write-Host "✅ $($wi.NfoFile) | title/sorttitle → $($wi.NewBaseName)" -ForegroundColor Green
        $logLines += "$($wi.VideoName)`t$($wi.NfoFile)`t$ot`t$ost`t$($wi.NewBaseName)"
    }
    catch{
        Write-Host "❌失败 $($wi.NfoFile) : $_" -ForegroundColor Red
        $logLines += "$($wi.VideoName)`t$($wi.NfoFile)`tERROR`t$_`t$($wi.NewBaseName)"
    }
}

$saveLog = Get-SingleKey "`n是否保存本次处理日志？【s=保存，其他按键不保存日志】"
if($saveLog -eq 's'){
    $logLines | Out-File $logFile -Encoding utf8
    Write-Host "`n✅日志已保存：$logFile" -ForegroundColor Green
}else{
    Write-Host "`n日志已放弃，没有生成日志文件。" -ForegroundColor Yellow
}
Wait-AnyKey

