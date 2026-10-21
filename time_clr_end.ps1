<#
time_clr_end.ps1 (原r2n.ps1变体)
提取【文件名开头】的时间串(XXhXXmXXs / XXmXXs)，仅保留时间作为文件名
更新：
1. 文件名开头时间后允许紧贴数字，剥离原始附带数字，以基础时间作为分组key统一分配序号
2. 不会产生 00m09s22 这类嵌套编号；脚本输出产物标记[EXIST]跳过；找不到头部时间标记标记[SKIP]
3. 支持识别emby/jellyfin配套图片+nfo；-poster、-fanart、-cover、-thumb、-banner、-clearart、-clearlogo、-logo、-landscape、-backdrop、-disc、-cdart、-movie、-default，后缀可带数字；只有视频待改名附属才参与
4. 交互菜单：1开启Emby附属，2关闭；开启后子选项控制是否改写nfo <title>/<sorttitle>；⚠nfo文本修改u仅还原文件名
5. 对齐整套工具标准：单键交互、撤销u、保存映射s、预演s导出txt；移除Read-Host/pause
6. 导出txt文件名带日期时间，内容【原名、新名、文件大小(KB)】保留2位小数
7. 原有弹窗：检测到配图后按y才处理配图，其他按键跳过配图逻辑
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
# ==========【新增】Emby附属模式交互 ==========
$enableEmbyArtRename = $null
$enableNfoTagEdit = $false
while($null -eq $enableEmbyArtRename){
    Write-Host "`n===== Emby附属文件模式选择 =====" -ForegroundColor Cyan
    Write-Host "【1】开启Emby配图&nfo跟随（附属跟随视频改名）"
    Write-Host "【2】关闭Emby配图&nfo跟随（仅处理视频本体）"
    $sel = Get-SingleKey "请按数字键 1 或 2 选择模式："
    Write-Host ""
    if($sel -eq '1'){
        $enableEmbyArtRename = $true
        while($true){
            Write-Host "`n----- NFO处理子选项 -----" -ForegroundColor Cyan
            Write-Host "【1】配图跟随 + 强制改写NFO <title>/<sorttitle>为视频新基名 ⚠文本修改无法撤销"
            Write-Host "【2】配图跟随 + 仅重命名NFO文件，不修改NFO内部内容"
            $nfoSel = Get-SingleKey "请按数字键 1 或 2 选择NFO策略："
            Write-Host ""
            if($nfoSel -eq '1'){
                $enableNfoTagEdit = $true
                Write-Host "✅已选择：开启配图跟随 + 强制改写NFO标签（⚠nfo文本修改无法u撤销，仅文件名可撤销）" -ForegroundColor Green
                break
            }elseif($nfoSel -eq '2'){
                $enableNfoTagEdit = $false
                Write-Host "✅已选择：开启配图跟随 + 仅NFO改名，不改动NFO内部XML" -ForegroundColor Green
                break
            }else{
                Write-Host "[!]无效按键，请重新按1或2" -ForegroundColor Red
            }
        }
    }elseif($sel -eq '2'){
        $enableEmbyArtRename = $false
        Write-Host "❌已选择：关闭Emby配图跟随模式（仅处理视频）" -ForegroundColor Yellow
    }else{
        Write-Host "[!] 无效按键，请重新按1或2" -ForegroundColor Red
    }
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
# 加入nfo
$imgExts = @(
    'jpg','JPG','Jpg',
    'jpeg','JPEG','Jpeg',
    'png','PNG','Png',
    'nfo','NFO'
)
# 匹配emby附属后缀：-关键词后面允许带数字，匹配到字符串末尾
$reImgAffix = [regex]'-(poster|cover|thumb|fanart|banner|clearart|clearlogo|logo|landscape|backdrop|disc|cdart|movie|default)\d*$'
$extPattern = $videoExts -join '|'
# 匹配basename开头：基础时间 + 紧贴后面0~N位数字
$reHeadFullToken = [regex]'^(?<fulltoken>(?<basetime>\d{2}h\d{2}m\d{2}s|\d{2}m\d{2}s)(?<num>\d*))'
# basename完全等于纯时间
$rePureTimeName = [regex]'^(\d{2}h\d{2}m\d{2}s|\d{2}m\d{2}s)$'
# basename是脚本输出产物：时间后面紧跟数字
$reTimeWithSuffixNum = [regex]'^(\d{2}h\d{2}m\d{2}s|\d{2}m\d{2}s)\d+$'
# 获取全部文件，不提前过滤扩展名
$files = Get-ChildItem -File .
$rawList = @()
$nfoModifyLog = @()
# --------------------------第一步：先处理所有视频文件--------------------------
foreach($f in $files){
    $baseName = $f.BaseName
    $ext = $f.Extension.TrimStart('.')
    $fileSizeKB = [math]::Round($f.Length / 1KB,2)
    if ($ext -notin $videoExts) {
        # 图片、nfo、其它格式先占位，后续二次填充
        $rawList += [PSCustomObject]@{
            FileObj   = $f
            BaseTime  = $null
            Status    = $null
            OrigDisp  = $f.Name
            FinalName = $null
            FileSizeKB = $fileSizeKB
            NfoNewTitle = $null
        }
        continue
    }
    # ---- 仅视频执行原有逻辑 ----
    # 情况1：本身是纯时间名
    if ($rePureTimeName.IsMatch($baseName)) {
        $rawList += [PSCustomObject]@{
            FileObj   = $f
            BaseTime  = $baseName
            Status    = '[EXIST]'
            OrigDisp  = $f.Name
            FinalName = $f.Name
            FileSizeKB = $fileSizeKB
            NfoNewTitle = $null
        }
        continue
    }
    # 情况2：basename是脚本生成产物【时间+数字】，保护跳过
    if ($reTimeWithSuffixNum.IsMatch($baseName)) {
        $rawList += [PSCustomObject]@{
            FileObj   = $f
            BaseTime  = $null
            Status    = '[EXIST]'
            OrigDisp  = $f.Name
            FinalName = $f.Name
            FileSizeKB = $fileSizeKB
            NfoNewTitle = $null
        }
        continue
    }
    # 捕获basename开头完整token，提取基础时间（剥离后面数字）
    $matchAll = $reHeadFullToken.Match($baseName)
    if(-not $matchAll.Success){
        # 头部没有匹配到时间片段，SKIP
        $rawList += [PSCustomObject]@{
            FileObj   = $f
            BaseTime  = $null
            Status    = '[SKIP]'
            OrigDisp  = $f.Name
            FinalName = $f.Name
            FileSizeKB = $fileSizeKB
            NfoNewTitle = $null
        }
        continue
    }
    $baseTimeStr = $matchAll.Groups['basetime'].Value
    $status = '[RENAME]'
    $rawList += [PSCustomObject]@{
        FileObj   = $f
        BaseTime  = $baseTimeStr
        Status    = $status
        OrigDisp  = $f.Name
        FinalName = $null
        FileSizeKB = $fileSizeKB
        NfoNewTitle = $null
    }
}
# 视频：排序 + 做冲突计数，算出视频FinalName
$videoItems = $rawList | Where-Object {$_.FileObj.Extension.TrimStart('.') -in $videoExts}
$videoItems = $videoItems | Sort-Object {
    if($null -eq $_.BaseTime){
        [string]'zzzzzzzz'
    }else{
        $_.BaseTime
    }
}
$baseTimeCounter = @{}
foreach($item in $videoItems){
    if ($item.Status -in '[EXIST]','[SKIP]'){
        $item.FinalName = $item.FileObj.Name
        continue
    }
    $bt = $item.BaseTime
    $ext = $item.FileObj.Extension
    if(-not $baseTimeCounter.ContainsKey($bt)){
        $baseTimeCounter[$bt] = 1
    }else{
        $baseTimeCounter[$bt] += 1
    }
    $cnt = $baseTimeCounter[$bt]
    if($cnt -eq 1){
        $final = "$bt$ext"
    }else{
        $final = "$bt$cnt$ext"
    }
    $item.FinalName = $final
}
# 构建映射：key=视频原始basename，value=视频完整对象，只存[RENAME]视频
$videoEntryMap = @{}
foreach($vid in $videoItems){
    if ($vid.Status -eq '[RENAME]'){
        $origBN = $vid.FileObj.BaseName
        # 提取视频新basename（去掉扩展名）
        $vidNewBase = $vid.FinalName -replace '\.[^.]+$',''
        $videoEntryMap[$origBN] = [PSCustomObject]@{
            FinalName = $vid.FinalName
            NewBase   = $vidNewBase
        }
    }
}
# --------------------------第二步：处理图片&nfo与其它非视频--------------------------
foreach($item in $rawList){
    $f = $item.FileObj
    $baseName = $f.BaseName
    $ext = $f.Extension.TrimStart('.')
    if ($ext -in $videoExts) { continue } #视频已经处理完毕
    if ($enableEmbyArtRename -and $ext -in $imgExts) {
        #===== 图片 / NFO 处理 =====
        $matchedVid = $null
        $affixPart = $null
        # 模式1：附属basename完全等于视频原始basename
        if ($videoEntryMap.ContainsKey($baseName)) {
            $matchedVid = $videoEntryMap[$baseName]
        }
        else {
            #模式2：匹配 视频basename +-附属标记(带数字)
            foreach($keyBN in $videoEntryMap.Keys){
                if ($baseName.StartsWith("$keyBN-")) {
                    $remainSub = $baseName.Substring($keyBN.Length)
                    $mAff = $reImgAffix.Match($remainSub)
                    if ($mAff.Success) {
                        $matchedVid = $videoEntryMap[$keyBN]
                        $affixPart = $mAff.Value
                        break
                    }
                }
            }
        }
        if ($null -eq $matchedVid) {
            $item.Status = '[SKIP-NO-MATCH-VIDEO]'
            $item.FinalName = $f.Name
        }
        else {
            $vidFinalBase = $matchedVid.NewBase
            if ($null -ne $affixPart) {
                $artNewBN = "$vidFinalBase$affixPart"
            }
            else {
                $artNewBN = $vidFinalBase
            }
            $item.FinalName = "$artNewBN$($f.Extension)"
            $item.Status = '[RENAME-ART]'
            #仅主名nfo，不带-poster/fanart这类后缀，标记待改写title
            if($enableNfoTagEdit -and $ext -eq 'nfo' -and $null -eq $affixPart){
                $item.NfoNewTitle = $vidFinalBase
            }
        }
    }
    else {
        # 开关关闭 / 不属于图片nfo，全部跳过
        $item.Status = '[SKIP非视频]'
        $item.FinalName = $f.Name
    }
}
# --------------------------询问是否处理配图/nfo（原版保留弹窗）--------------------------
$artNeedProcess = $rawList | Where-Object {$_.Status -eq '[RENAME-ART]'}
if ($artNeedProcess.Count -gt 0) {
    $ans = Get-SingleKey ("`n[!] 检测到 $($artNeedProcess.Count) 个配套配图/NFO文件。`n按【y】同步一并处理附属；其他按键：仅处理视频，附属全部跳过")
    if ($ans -ne 'y') {
        foreach($it in $rawList.Where({$_.Status -eq '[RENAME-ART]'})){
            $it.Status = '[SKIP-USER-SKIP]'
        }
    }
}
$previewList = $rawList
# ========== 美化预览表格 ==========
Write-Host "`n==================== 重命名预览(time_clr_end) ====================" -ForegroundColor Cyan
if($enableEmbyArtRename){
    if($enableNfoTagEdit){
        $tip = "Emby配图跟随：✅开启 | NFO策略：强制改写<title>/<sorttitle> ⚠文本不可撤销"
    }else{
        $tip = "Emby配图跟随：✅开启 | NFO策略：仅改名，不修改内部XML"
    }
}else{
    $tip = "Emby配图跟随：❌关闭"
}
Write-Host "[$tip]" -ForegroundColor Cyan
Write-Host ("{0,-4} {1,-30} {2,-30} {3}" -f "序号","原文件名","新文件名","操作")
Write-Host "-------------------------------------------------------------------------"
$renameVideoTotal = ($previewList | Where-Object {$_.Status -eq '[RENAME]'}).Count
$renameArtTotal   = ($previewList | Where-Object {$_.Status -eq '[RENAME-ART]'}).Count
$skipTotal = ($previewList | Where-Object {$_.Status -notin '[RENAME]','[RENAME-ART]'}).Count
$idx = 1
foreach($item in $previewList){
    Write-Host ("{0,-4}" -f $idx) -NoNewline
    Write-Host ("{0,-30}" -f $item.OrigDisp) -NoNewline
    if($item.Status -eq '[RENAME]'){
        Write-Host ("{0,-30}" -f $item.FinalName) -ForegroundColor Yellow -NoNewline
        Write-Host "[RENAME]" -ForegroundColor Green
    }elseif($item.Status -eq '[RENAME-ART]'){
        Write-Host ("{0,-30}" -f $item.FinalName) -ForegroundColor Yellow -NoNewline
        $hint = if($null -ne $item.NfoNewTitle){" | NFO-TAGS(OVERWRITE)"}else{""}
        Write-Host "[RENAME-ART]$hint" -ForegroundColor DarkGreen
    }else{
        Write-Host ("{0,-30}" -f $item.FinalName) -ForegroundColor Gray -NoNewline
        Write-Host "$($item.Status)" -ForegroundColor Gray
    }
    $idx++
}
Write-Host "-------------------------------------------------------------------------"
if($enableEmbyArtRename){
    Write-Host ("视频改名：{0}｜配图/nfo改名：{1}｜跳过/已存在：{2}" -f $renameVideoTotal,$renameArtTotal,$skipTotal) -ForegroundColor Cyan
}else{
    Write-Host ("视频改名：{0}｜跳过/已存在：{1}" -f $renameVideoTotal,$skipTotal) -ForegroundColor Cyan
}
Write-Host "=========================================================================`n" -ForegroundColor Cyan
$totalNeedRename = $renameVideoTotal + $renameArtTotal
if($totalNeedRename -eq 0){
    Write-Host "`n[!] 没有需要执行改名的文件。" -ForegroundColor Yellow
    Wait-AnyKey
    exit 0
}
$undoList = @()
$timeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
# 操作选择：y执行改名 / s仅预演导出txt；其他按键退出（单键无回车）
$confirm = Get-SingleKey "操作选择：【y】执行改名；【s】仅生成新旧映射txt（不改名）；其他按键退出"
if ($confirm -eq 's') {
    $backupFile = Join-Path $PWD.Path "rename_backup_$timeStamp.txt"
    $lines = @()
    $lines += "# 备份时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $lines += "# Emby配图跟随开关：$enableEmbyArtRename"
    $lines += "# NFO标签改写开关：$enableNfoTagEdit"
    if($enableNfoTagEdit){
        $lines += "# ⚠️NFO内部文本会被强制覆盖；文本修改无法撤销，仅文件名支持u撤销"
    }
    $lines += "# 原名`t新名`t文件大小(KB)"
    foreach ($item in $previewList) {
        if ($item.Status -in '[RENAME]','[RENAME-ART]') {
            $lines += "$($item.OrigDisp)`t$($item.FinalName)`t$($item.FileSizeKB)"
            if($enableNfoTagEdit -and $null -ne $item.NfoNewTitle){
                $lines += "# NFO-TAG-OVERWRITE：<title>/<sorttitle> → $($item.NfoNewTitle)"
            }
        }
    }
    $lines | Out-File -FilePath $backupFile -Encoding utf8
    Write-Host "`n✅ 已生成映射文件：$backupFile，本次不执行改名。" -ForegroundColor Green
    Wait-AnyKey
    exit 0
}
elseif ($confirm -ne 'y') {
    Write-Host "[!] 已取消操作。" -ForegroundColor Yellow
    Wait-AnyKey
    exit 0
}
Write-Host "`n===== 开始执行改名 =====" -ForegroundColor Cyan
$toRename = $previewList | Where-Object {$_.Status -in '[RENAME]','[RENAME-ART]'}
foreach($item in $toRename){
    $srcFile = $item.FileObj
    $destPath = Join-Path $srcFile.Directory.FullName $item.FinalName
    # NFO内部标签改写（对标sed，-replace原生运算符）
    if($enableNfoTagEdit -and $null -ne $item.NfoNewTitle){
        try{
            $nfoText = [System.IO.File]::ReadAllText($srcFile.FullName, [System.Text.Encoding]::UTF8)
            $origTitleVal=$null;$origSortVal=$null
            if($nfoText -match '<title\b[^>]*>(.*?)</title>'){$origTitleVal=$matches[1]}
            if($nfoText -match '<sorttitle\b[^>]*>(.*?)</sorttitle>'){$origSortVal=$matches[1]}
            if($nfoText -match '<title>.*</title>'){
                $nfoText = $nfoText -replace '<title>.*</title>',"<title>$($item.NfoNewTitle)</title>"
            }
            if($nfoText -match '<sorttitle>.*</sorttitle>'){
                $nfoText = $nfoText -replace '<sorttitle>.*</sorttitle>',"<sorttitle>$($item.NfoNewTitle)</sorttitle>"
            }
            [System.IO.File]::WriteAllText($srcFile.FullName, $nfoText, [System.Text.Encoding]::UTF8)
            $nfoModifyLog += [PSCustomObject]@{
                NfoFile=$item.OrigDisp;OldTitle=$origTitleVal;NewTitle=$item.NfoNewTitle
                OldSortTitle=$origSortVal;NewSortTitle=$item.NfoNewTitle
            }
            Write-Host "`t[NFO标签覆盖 OK] title/sorttitle → $($item.NfoNewTitle)" -ForegroundColor DarkGreen
        }catch{
            Write-Host "`t[NFO标签更新失败] $_" -ForegroundColor Red
        }
    }
    try {
        Rename-Item -LiteralPath $srcFile.FullName -NewName $item.FinalName -Force -ErrorAction Stop
        Write-Host "原名：" -ForegroundColor Gray -NoNewline
        Write-Host "$($item.OrigDisp)" -NoNewline
        Write-Host " → " -ForegroundColor Gray -NoNewline
        Write-Host "$($item.FinalName) " -ForegroundColor Yellow -NoNewline
        Write-Host "[OK]" -ForegroundColor Green
        $undoList += [PSCustomObject]@{
            AfterPath  = $destPath
            BeforePath = $srcFile.FullName
            OldName    = $item.OrigDisp
            NewName    = $item.FinalName
            FileSizeKB = $item.FileSizeKB
        }
    }
    catch {
        Write-Host "原名：" -ForegroundColor Gray -NoNewline
        Write-Host "$($item.OrigDisp)" -NoNewline
        Write-Host " → " -ForegroundColor Gray -NoNewline
        Write-Host "$($item.FinalName) " -ForegroundColor Yellow -NoNewline
        Write-Host "[ERROR] $_" -ForegroundColor Red
    }
}
Write-Host "`n[✓] 全部操作完成。" -ForegroundColor Cyan
# ========== 改名完成后菜单 u撤销 / s保存映射txt ==========
if($undoList.Count -gt 0){
    $tipUndo = if($enableEmbyArtRename -and $enableNfoTagEdit){"（⚠️注意：nfo内部文本被覆盖无法撤销，仅文件名可u还原）"}else{""}
    Write-Host "`n===== 后续操作选项 =====" -ForegroundColor Cyan
    $optInput = Get-SingleKey "按【u】撤销本次改名$tipUndo；按【s】保存映射txt；其他按键直接退出"
    $optInput = $optInput.ToLower()
    $timeStamp2 = Get-Date -Format "yyyyMMdd_HHmmss"
    if($optInput -eq "u"){
        if($enableEmbyArtRename -and $enableNfoTagEdit){
            Write-Host "`n⚠️ 开始撤销，仅还原文件名！nfo内部title/sorttitle文本不会复原！" -ForegroundColor Yellow
        }else{
            Write-Host "`n⚠️ 开始撤销，还原文件名..." -ForegroundColor Yellow
        }
        $failUndo = 0
        foreach($uItem in $undoList){
            if(Test-Path -LiteralPath $uItem.AfterPath){
                try{
                    Rename-Item -LiteralPath $uItem.AfterPath -NewName $uItem.OldName -ErrorAction Stop
                    Write-Host "[撤销OK] $($uItem.AfterPath) → $($uItem.BeforePath)" -ForegroundColor Green
                }catch{
                    Write-Host "[撤销失败] $($uItem.AfterPath) : $_" -ForegroundColor Red
                    $failUndo++
                }
            }else{
                Write-Host "[撤销跳过] 文件不存在：$($uItem.AfterPath)" -ForegroundColor Red
                $failUndo++
            }
        }
        Write-Host "`n撤销完成，成功：$($undoList.Count - $failUndo) ｜失败：$failUndo" -ForegroundColor Cyan
    }
    elseif($optInput -eq "s"){
        $backupFile = Join-Path $PWD.Path "rename_backup_$timeStamp2.txt"
        $lines = @()
        $lines += "# 备份时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $lines += "# Emby配图跟随开关：$enableEmbyArtRename"
        $lines += "# NFO标签改写开关：$enableNfoTagEdit"
        if($enableNfoTagEdit){
            $lines += "# ⚠️NFO内部文本会被强制覆盖；文本修改无法撤销，仅文件名支持u撤销"
        }
        $lines += "# 原名`t新名`t文件大小(KB)"
        foreach($uItem in $undoList){
            $lines += "$($uItem.OldName)`t$($uItem.NewName)`t$($uItem.FileSizeKB)"
        }
        if($enableNfoTagEdit -and $nfoModifyLog.Count -gt 0){
            $lines += "`n# NFO内部标签覆盖记录（仅文本，无法撤销恢复内容）"
            foreach($log in $nfoModifyLog){
                $lines += "# File:$($log.NfoFile) | oldTitle:$($log.OldTitle) | newTitle:$($log.NewTitle)"
                $lines += "#        | oldSortTitle:$($log.OldSortTitle) | newSortTitle:$($log.NewSortTitle)"
            }
        }
        $lines | Out-File -FilePath $backupFile -Encoding utf8
        Write-Host "`n✅ 已保存映射文件：$backupFile" -ForegroundColor Green
    }
    else{
        Write-Host "`n退出脚本。" -ForegroundColor Gray
    }
}
Wait-AnyKey "`n按任意键返回菜单..."

