<#
nfo.ps1
功能：刷新与视频同名的nfo内部 <title> <sorttitle> = 视频basename(不带后缀)
适配PowerShell 5.1
【修改版】预览表格颜色区分是否需要修改 + 执行后列表颜色突出修改结果
注意：
1. 仅配对：视频.mp4 ↔ 同名视频.nfo；poster/fanart/thumb类(含-poster1带数字)附属nfo直接跳过
2. s=预览模式，只输出日志不修改文件；y=实际写入nfo（仅改不一致的）；a=全覆盖（全部重写）；其它按键退出
3. ⚠本脚本只改nfo文本，**不修改任何文件名，没有撤销功能！**
4. 找不到<title>/<sorttitle>标签则不会新增标签，保持原文件不变
【修复说明】预览及执行结果列表颜色判断加 .Trim() 防空格干扰；
            Modified状态下二次比对实际值，一致则全绿显示，仅真有差异才红/黄。
            y模式仅修改内外不一致的文件，一致的直接跳过不覆盖；a模式全覆盖重写。
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
if ($vidBase -match '-(poster|cover|thumb|fanart|banner|clearart|clearlogo|logo|landscape|backdrop|disc|cdart|movie|default)\d*$') {
continue
}
# 读取nfo原有title/sorttitle用于预览日志
$rawText = [System.IO.File]::ReadAllText($nfoObj.FullName, [System.Text.Encoding]::UTF8)
$oldTitle = $null
$oldSortTitle = $null
if ($rawText -match '<title\b[^>]*>(.*?)</title>') { $oldTitle = $matches[1] }
if ($rawText -match '<sorttitle\b[^>]*>(.*?)</sorttitle>') { $oldSortTitle = $matches[1] }
$workItems += [PSCustomObject]@{
VideoName   = $vid.Name
NfoFile     = $nfoObj.Name
NfoFullPath = $nfoObj.FullName
NewBaseName = $vidBase
OldTitle    = $oldTitle
OldSortTitle= $oldSortTitle
}
}
}
if ($workItems.Count -eq 0) {
Write-Host "`n[!]没有找到【视频+同名nfo】配对文件，退出。" -ForegroundColor Yellow
Wait-AnyKey
exit 0
}
# ========== 打印预览表格（颜色区分是否需要修改）==========
Write-Host "`n==================== NFO内部名称同步预览 ====================" -ForegroundColor Cyan
Write-Host ("{0,-30} {1,-22} {2,-22}" -f "视频文件", "原<title>", "→目标值")
Write-Host "-------------------------------------------------------------------------"
foreach ($wi in $workItems) {
$dispOldTitle = if ($wi.OldTitle -ne $null) { $wi.OldTitle } else { "[无标签]" }
# 判断原title和目标值是否不一致
$isDifferent = ($wi.OldTitle -ne $null) -and ($wi.OldTitle.Trim() -ne $wi.NewBaseName.Trim())
Write-Host ("{0,-30}" -f $wi.VideoName) -NoNewline
if ($isDifferent) {
# 红色 = 需要修改
Write-Host ("{0,-22}" -f $dispOldTitle) -ForegroundColor Red -NoNewline
} else {
# 绿色=已一致，灰色=无标签
$color = if ($wi.OldTitle -eq $null) { "Gray" } else { "Green" }
Write-Host ("{0,-22}" -f $dispOldTitle) -ForegroundColor $color -NoNewline
}
if ($isDifferent) {
Write-Host ("→ {0}" -f $wi.NewBaseName) -ForegroundColor Yellow
} else {
Write-Host ("→ {0}" -f $wi.NewBaseName) -ForegroundColor Gray
}
}
Write-Host "-------------------------------------------------------------------------"
Write-Host "一共 $($workItems.Count) 组视频-nfo配对待处理" -ForegroundColor Cyan
Write-Host "  🔴红色=需要修改  🟢绿色=已一致  ⚪灰色=无标签/无需改" -ForegroundColor White
Write-Host "=========================================================================`n" -ForegroundColor Cyan
$confirm = Get-SingleKey "操作选择：【y】仅改不一致的nfo；【a】全覆盖重写所有nfo；【s】输出日志log（不改动nfo）；其他按键直接退出"

$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$logFile = Join-Path $PWD.Path "nfo_sync_log_$ts.log"

if ($confirm -eq 's') {
# 仅导出日志，不修改
$lines = @()
$lines += "# nfo同步预览日志；s模式，未修改任何nfo"
$lines += "# 视频`tNfo文件`t旧title`t旧sorttitle`t目标新值"
foreach ($wi in $workItems) {
$ot  = if ($wi.OldTitle -ne $null) { $wi.OldTitle } else { "" }
$ost = if ($wi.OldSortTitle -ne $null) { $wi.OldSortTitle } else { "" }
$lines += "$($wi.VideoName)`t$($wi.NfoFile)`t$ot`t$ost`t$($wi.NewBaseName)"
}
$lines | Out-File $logFile -Encoding utf8
Write-Host "`n✅预览日志已输出：$logFile，本次不会修改nfo。" -ForegroundColor Green
Wait-AnyKey
exit 0
}
elseif ($confirm -ne 'y' -and $confirm -ne 'a') {
Write-Host "[!]已取消操作。" -ForegroundColor Yellow
Wait-AnyKey
exit 0
}

# 判断模式
$forceAll = ($confirm -eq 'a')
if ($forceAll) {
Write-Host "`n⚠ 全覆盖模式：所有nfo将被重写（即使内外已一致）" -ForegroundColor Yellow
} else {
Write-Host "`n✓ 智能模式：仅修改内外不一致的nfo，已一致的跳过" -ForegroundColor Green
}

# ========== 真正执行修改 ==========
$logLines = @()
$logLines += "# nfo同步执行日志；已修改nfo <title> <sorttitle> 为视频basename"
$logLines += "# 视频`tNfo文件`t旧title`t旧sorttitle`t目标新值`t状态"

# 记录修改结果用于最后展示
$resultItems = @()

Write-Host "`n=====开始刷新nfo内部标签 =====" -ForegroundColor Cyan

foreach ($wi in $workItems) {
try {
$text = [System.IO.File]::ReadAllText($wi.NfoFullPath, [System.Text.Encoding]::UTF8)
$ot = $wi.OldTitle
$ost = $wi.OldSortTitle

# 判断是否需要修改
$isDifferent = ($ot -ne $null) -and ($ot.Trim() -ne $wi.NewBaseName.Trim())

if (-not $forceAll -and -not $isDifferent) {
# y模式 + 内外一致 → 跳过，不碰文件
Write-Host "⚪ $($wi.NfoFile) | 内外已一致，跳过" -ForegroundColor Gray
$status = "Skipped-Same"

$resultItems += [PSCustomObject]@{
NfoFile  = $wi.NfoFile
OldTitle = $ot
NewValue = $wi.NewBaseName
Status   = $status
}
$logLines += "$($wi.VideoName)`t$($wi.NfoFile)`t$ot`t$ost`t$($wi.NewBaseName)`t$status"
continue
}

# 需要修改（y模式下不一致，或a模式全覆盖）
$modified = $false
if ($text -match '<title>.*</title>') {
$text = $text -replace '<title>.*</title>', "<title>$($wi.NewBaseName)</title>"
$modified = $true
}
if ($text -match '<sorttitle>.*</sorttitle>') {
$text = $text -replace '<sorttitle>.*</sorttitle>', "<sorttitle>$($wi.NewBaseName)</sorttitle>"
$modified = $true
}

if (-not $modified) {
Write-Host "⚪ $($wi.NfoFile) | 未找到标签，跳过" -ForegroundColor Gray
$status = "Skipped"

$resultItems += [PSCustomObject]@{
NfoFile  = $wi.NfoFile
OldTitle = $ot
NewValue = $wi.NewBaseName
Status   = $status
}
$logLines += "$($wi.VideoName)`t$($wi.NfoFile)`t$ot`t$ost`t$($wi.NewBaseName)`t$status"
continue
}

# 写入文件
[System.IO.File]::WriteAllText($wi.NfoFullPath, $text, [System.Text.Encoding]::UTF8)

# 回显颜色：一致=绿，真改=绿+黄
$oldTrim = if ($ot -ne $null) { $ot.Trim() } else { "" }
$newTrim = $wi.NewBaseName.Trim()
if ($oldTrim -eq $newTrim) {
Write-Host "✅ $($wi.NfoFile) | 已一致(已重写)" -ForegroundColor Green
} else {
Write-Host "✅ $($wi.NfoFile) | title/sorttitle → $($wi.NewBaseName)" -ForegroundColor Green
}
$status = "Modified"

$resultItems += [PSCustomObject]@{
NfoFile  = $wi.NfoFile
OldTitle = $ot
NewValue = $wi.NewBaseName
Status   = $status
}
$logLines += "$($wi.VideoName)`t$($wi.NfoFile)`t$ot`t$ost`t$($wi.NewBaseName)`t$status"
}
catch {
Write-Host "❌失败 $($wi.NfoFile) : $_" -ForegroundColor Red
$resultItems += [PSCustomObject]@{
NfoFile  = $wi.NfoFile
OldTitle = $wi.OldTitle
NewValue = $wi.NewBaseName
Status   = "Error"
}
$logLines += "$($wi.VideoName)`t$($wi.NfoFile)`tERROR`t$_`t$($wi.NewBaseName)`tError"
}
}

# ========== 最终修改结果列表（颜色突出）==========
Write-Host "`n==================== 修改结果列表 ====================" -ForegroundColor Cyan
Write-Host ("{0,-25} {1,-20} {2,-20} {3}" -f "NFO文件", "原title", "→新值", "状态")
Write-Host "-----------------------------------------------------------"
foreach ($ri in $resultItems) {
$dispOld = if ($ri.OldTitle -ne $null) { $ri.OldTitle } else { "[无]" }
Write-Host ("{0,-25}" -f $ri.NfoFile) -NoNewline

if ($ri.Status -eq "Modified") {
# Modified状态下再次比对实际值，一致则全绿，真改了才红+黄
$oldTrim = if ($ri.OldTitle -ne $null) { $ri.OldTitle.Trim() } else { "" }
$newTrim = $ri.NewValue.Trim()
if ($oldTrim -eq $newTrim) {
Write-Host ("{0,-20}" -f $dispOld) -ForegroundColor Green -NoNewline
Write-Host ("→ {0}" -f $ri.NewValue) -ForegroundColor Green -NoNewline
Write-Host "  ✅ 已一致" -ForegroundColor Green
} else {
Write-Host ("{0,-20}" -f $dispOld) -ForegroundColor Red -NoNewline
Write-Host ("→ {0}" -f $ri.NewValue) -ForegroundColor Yellow -NoNewline
Write-Host "  ✅ 已修改" -ForegroundColor Green
}
}
elseif ($ri.Status -eq "Skipped-Same") {
# 内外已一致，跳过不覆盖
Write-Host ("{0,-20}" -f $dispOld) -ForegroundColor Green -NoNewline
Write-Host ("→ {0}" -f $ri.NewValue) -ForegroundColor Green -NoNewline
Write-Host "  ⚪ 已一致(跳过)" -ForegroundColor Gray
}
elseif ($ri.Status -eq "Skipped") {
Write-Host ("{0,-20}" -f $dispOld) -ForegroundColor Gray -NoNewline
Write-Host ("→ {0}" -f $ri.NewValue) -ForegroundColor Gray -NoNewline
Write-Host "  ⚪ 跳过(无标签)" -ForegroundColor Gray
}
else {
Write-Host ("{0,-20}" -f $dispOld) -ForegroundColor Red -NoNewline
Write-Host ("→ {0}" -f $ri.NewValue) -ForegroundColor Red -NoNewline
Write-Host "  ❌ 失败" -ForegroundColor Red
}
}
Write-Host "-----------------------------------------------------------" -ForegroundColor Cyan

# ========== 是否保存日志 ==========
$saveLog = Get-SingleKey "`n是否保存本次处理日志？【s=保存，其他按键不保存日志】"
if ($saveLog -eq 's') {
$logLines | Out-File $logFile -Encoding utf8
Write-Host "`n✅日志已保存：$logFile" -ForegroundColor Green
} else {
Write-Host "`n日志已放弃，没有生成日志文件。" -ForegroundColor Yellow
}
Wait-AnyKey

