<#
time_clr_remove.ps1
功能：与 time_clr_auto.ps1 反向，清除文件名中的时间串片段
清除规则：
1. 匹配时间格式：XXhXXmXXs / XXmXXs，时间前面允许带空格
2. 将匹配到的【(空格)+时间串】整体从 BaseName 删除，保留其余文本
3. 交互对齐整套工具：y执行改名 / s预演导出txt；改名后u撤销 / s保存映射；单键无回车
4. Emby配图/nfo跟随改名：*.{jpg,png,webp} *‑poster.* *‑fanart.* *‑thumb.* *.nfo
5. NFO策略：开启改写则强制改写<title>/<sorttitle>为视频新基名；⚠nfo文本修改无法u撤销，仅文件名可撤销
6. 保护逻辑：删除时间后如果basename为空，则标记[SKIP]不处理；非视频附属配图跟随视频重命名
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

# ========== 【第一步：交互拿到开关】 ==========
$enableEmbyArtRename = $null
$enableNfoTagEdit = $false
while($null -eq $enableEmbyArtRename){
    Write-Host "`n===== 运行模式选择 =====" -ForegroundColor Cyan
    Write-Host "【1】开启Emby配图跟随"
    Write-Host "【2】关闭Emby配图跟随  - 仅处理视频本体，图片/nfo全部跳过"
    $sel = Get-SingleKey "请按数字键 1 或 2 选择模式："
    Write-Host ""
    if($sel -eq '1'){
        $enableEmbyArtRename = $true
        while($true){
            Write-Host "`n----- NFO处理子选项 -----" -ForegroundColor Cyan
            Write-Host "【1】配图跟随 + 强制改写NFO <title>/<sorttitle>为视频新基名 ⚠文本修改无法撤销，原有标题会被覆盖"
            Write-Host "【2】配图跟随 + 仅重命名NFO文件，不修改NFO内部内容"
            $nfoSel = Get-SingleKey "请按数字键 1 或 2 选择NFO策略："
            Write-Host ""
            if($nfoSel -eq '1'){
                $enableNfoTagEdit = $true
                Write-Host "✅已选择：开启配图跟随 + 强制改写NFO标签（⚠原有title/sorttitle内容会被覆盖；nfo文本修改无法u撤销，仅文件名可撤销）" -ForegroundColor Green
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
$artExts = @('jpg','jpeg','png','webp','nfo','JPG','JPEG','PNG','WEBP','NFO')

# 正则：匹配【可选空格 + XXhXXmXXs / XXmXXs】，清除该片段
$reRemoveTimeToken = [regex]'\s*(\d{2}h\d{2}m\d{2}s|\d{2}m\d{2}s)'
$reImgAffix = [regex]'-(poster|cover|thumb|fanart|banner|clearart|clearlogo|logo|landscape|backdrop|disc|cdart|movie|default)\d*$'

# ==========【第二步：扫描视频，生成映射字典 videoBaseMap】 ==========
$allFiles = Get-ChildItem -File .
$videoBaseMap = @{}
$videoRawList = @()

foreach ($f in $allFiles) {
    $ext = $f.Extension.TrimStart('.')
    if ($ext -notin $videoExts) { continue }
    $bn = $f.BaseName
    $item = [PSCustomObject]@{
        FileObj    = $f
        BaseName   = $bn
        NewBase    = $null
        Status     = $null
        FinalName  = $null
        FileSizeKB = [math]::Round($f.Length /1KB,2)
    }

    # 删除时间片段
    $cleanBase = $reRemoveTimeToken.Replace($bn, "").Trim()
    if ($cleanBase -eq $bn) {
        # 没有找到时间片段
        $item.Status = '[SKIP]'
        $item.FinalName = $f.Name
    }
    elseif ([string]::IsNullOrWhiteSpace($cleanBase)) {
        # 删除时间后basename变空，禁止重命名
        $item.Status = '[SKIP-EMPTY]'
        $item.FinalName = $f.Name
    }
    else {
        $item.Status = '[RENAME]'
        $item.NewBase = $cleanBase
        $item.FinalName = $cleanBase + $f.Extension
    }
    $videoRawList += $item
}

# 处理视频重名冲突：同新basename追加数字1,2,3
$videoRawList = $videoRawList | Sort-Object BaseName
$counter = @{}
foreach($v in $videoRawList){
    if ($v.Status -ne '[RENAME]') { continue }
    $nb = $v.NewBase
    $ext = $v.FileObj.Extension
    if(-not $counter.ContainsKey($nb)){
        $counter[$nb] = 1
        $finalBn = $nb
    }else{
        $counter[$nb]++
        $finalBn = "$nb$($counter[$nb])"
    }
    $v.NewBase = $finalBn
    $v.FinalName = $finalBn + $ext
    $videoBaseMap[$v.FileObj.BaseName] = $v.NewBase
}

# ==========【第三步：全盘遍历所有文件，生成完整previewList】 ==========
$previewList = @()
foreach ($f in $allFiles) {
    $bn = $f.BaseName
    $ext = $f.Extension.TrimStart('.')
    $fsKB = [math]::Round($f.Length /1KB,2)
    $isVid = $ext -in $videoExts

    if($isVid){
        $vItem = $videoRawList | Where-Object { $_.FileObj.FullName -eq $f.FullName }
        $previewList += [PSCustomObject]@{
            FileObj     = $f
            OrigDisp    = $f.Name
            FinalName   = $vItem.FinalName
            Status      = $vItem.Status
            FileSizeKB  = $fsKB
            NfoNewTitle = $null
            IsVideo     = $true
        }
        continue
    }

    # ---- 非视频，匹配Emby附属配图/nfo ----
    $artMatchedVidKey = $null
    $artAffix = $null
    if($enableEmbyArtRename -and $ext -in $artExts){
        foreach($vk in $videoBaseMap.Keys){
            if($bn -eq $vk){
                $artMatchedVidKey = $vk
                $artAffix = ""
                break
            }
            if($bn.StartsWith("$vk-")){
                $sub = $bn.Substring($vk.Length)
                if($reImgAffix.IsMatch($sub)){
                    $artMatchedVidKey = $vk
                    $artAffix = $sub
                    break
                }
            }
        }
    }

    if($null -ne $artMatchedVidKey){
        $newBase = $videoBaseMap[$artMatchedVidKey]
        $newBn = "$newBase$artAffix"
        $newFn = $newBn + $f.Extension
        $nfoNewTitle = $null
        if($enableNfoTagEdit -and $ext -eq 'nfo' -and [string]::IsNullOrEmpty($artAffix)){
            $nfoNewTitle = $newBase
        }
        $previewList += [PSCustomObject]@{
            FileObj     = $f
            OrigDisp    = $f.Name
            FinalName   = $newFn
            Status      = '[RENAME-ART]'
            FileSizeKB  = $fsKB
            NfoNewTitle = $nfoNewTitle
            IsVideo     = $false
        }
    }else{
        $previewList += [PSCustomObject]@{
            FileObj     = $f
            OrigDisp    = $f.Name
            FinalName   = $f.Name
            Status      = '[SKIP非视频]'
            FileSizeKB  = $fsKB
            NfoNewTitle = $null
            IsVideo     = $false
        }
    }
}

# ========== 预览表格输出 ==========
Write-Host "`n==================== 清除文件名时间片段预览(time_clr_remove) ====================" -ForegroundColor Cyan
if($enableEmbyArtRename){
    if($enableNfoTagEdit){
        $artSwitchTip = "Emby配图跟随：✅开启 | NFO策略：强制改写<title>/<sorttitle>为视频新基名 ⚠原有标题会被覆盖"
    }else{
        $artSwitchTip = "Emby配图跟随：✅开启 | NFO策略：仅改名，不修改内部XML"
    }
}else{
    $artSwitchTip = "Emby配图跟随：❌关闭"
}
Write-Host "[$artSwitchTip]" -ForegroundColor Cyan
Write-Host ("{0,-4} {1,-34} {2,-34} {3}" -f "序号", "原文件名", "新文件名", "操作")
Write-Host "-----------------------------------------------------------------------------"
$renameVideoTotal  = ($previewList | Where-Object {$_.Status -eq '[RENAME]'}).Count
$renameArtTotal    = ($previewList | Where-Object {$_.Status -eq '[RENAME-ART]'}).Count
$skipTotal         = ($previewList | Where-Object {$_.Status -in '[SKIP]','[SKIP-EMPTY]','[SKIP非视频]'}).Count
$idx=1
foreach($item in $previewList){
    Write-Host ("{0,-4}" -f $idx) -NoNewline
    Write-Host ("{0,-34}" -f $item.OrigDisp) -NoNewline
    if($item.Status -in '[RENAME]','[RENAME-ART]'){
        Write-Host ("{0,-34}" -f $item.FinalName) -ForegroundColor Yellow -NoNewline
        if($item.Status -eq '[RENAME]'){
            Write-Host "[RENAME]" -ForegroundColor Green
        }else{
            $tagHint = if($null-ne $item.NfoNewTitle){" | NFO-TAGS(OVERWRITE)"}else{""}
            Write-Host "[RENAME-ART]$tagHint" -ForegroundColor DarkGreen
        }
    }else{
        Write-Host ("{0,-34}" -f $item.FinalName) -ForegroundColor Gray -NoNewline
        Write-Host "$($item.Status)" -ForegroundColor Gray
    }
    $idx++
}
Write-Host "-----------------------------------------------------------------------------"
if($enableEmbyArtRename){
    Write-Host ("视频改名：{0}｜配图/nfo改名：{1}｜跳过：{2}" -f $renameVideoTotal,$renameArtTotal,$skipTotal) -ForegroundColor Cyan
}else{
    Write-Host ("视频改名：{0}｜跳过：{1}" -f $renameVideoTotal,$skipTotal)
}
Write-Host "=============================================================================`n" -ForegroundColor Cyan

$totalNeedRename = if($enableEmbyArtRename){$renameVideoTotal + $renameArtTotal}else{$renameVideoTotal}
if($totalNeedRename -eq 0){
    Write-Host "`n[!] 没有需要执行改名的文件。" -ForegroundColor Yellow
    Wait-AnyKey
    exit 0
}

$undoList = @()
$nfoModifyLog = @()
$timeStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$confirm = Get-SingleKey "操作选择：【y】执行改名；【s】仅生成新旧映射txt（不改名）；其他按键退出"

if ($confirm -eq 's') {
    $backupFile = Join-Path $PWD.Path "remove_time_backup_$timeStamp.txt"
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
            if($enableNfoTagEdit -and $null-ne $item.NfoNewTitle){
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
$toRenameAll = $previewList | Where-Object {$_.Status -in '[RENAME]','[RENAME-ART]'}
foreach ($item in $toRenameAll) {
    $srcFile = $item.FileObj
    $destPath = Join-Path $srcFile.Directory.FullName $item.FinalName
    if($enableNfoTagEdit -and $null-ne $item.NfoNewTitle){
        try{
            $nfoText = [System.IO.File]::ReadAllText($srcFile.FullName, [System.Text.Encoding]::UTF8)
            $origTitleVal = $null;$origSortVal=$null
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
if ($undoList.Count -gt 0) {
    $tipUndo = if($enableEmbyArtRename-and $enableNfoTagEdit){"（⚠️注意：nfo内部文本被覆盖无法撤销，仅文件名可u还原）"}else{""}
    Write-Host "`n===== 后续操作选项 =====" -ForegroundColor Cyan
    $optInput = Get-SingleKey "按【u】撤销本次改名$tipUndo；按【s】保存映射txt；其他按键直接退出"
    $optInput = $optInput.ToLower()
    $timeStamp2 = Get-Date -Format "yyyyMMdd_HHmmss"
    if($optInput -eq "u"){
        if($enableEmbyArtRename-and $enableNfoTagEdit){
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
        Write-Host "`n撤销完成，成功：$($undoList.Count- $failUndo) ｜失败：$failUndo" -ForegroundColor Cyan
    }
    elseif($optInput -eq "s"){
        $backupFile = Join-Path $PWD.Path "remove_time_backup_$timeStamp2.txt"
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
        if($enableNfoTagEdit-and $nfoModifyLog.Count-gt 0){
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


