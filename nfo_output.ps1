<#
.SYNOPSIS
    Emby NFO 扫描与元数据 CSV 导出脚本
.DESCRIPTION
    递归扫描 Emby/Jellyfin 生成的 NFO 文件，提取视频/音频流信息（时长、编码、分辨率、码率等），
    导出为 UTF-8 CSV。支持竖屏分辨率自动对调标注、同名视频路径可选匹配、处理进度实时显示、
    递归/当前目录可选扫描。
.PARAMETER NfoRoot
    扫描根目录，默认当前目录
.PARAMETER CsvName
    CSV 文件名，默认带时间戳
.NOTES
    版本: v1.7
    兼容: PowerShell 2.0 / 5.1 / 7
    特性: UNC/超长路径支持、纯 XML 解析不依赖 ffprobe、字段缺失不中断、
          实时进度显示、递归开关（默认递归，可仅扫当前目录）

    ── 修改记录 ──
    v1.0  初版骨架，Get-ChildItem 递归，时长用 duration 显示"X分"
    v1.1  改用 .NET Directory::GetFiles + Queue 枚举，修复 UNC/超长路径
    v1.2  试验 durationinseconds 节点，因未判空+格式化崩溃导致全批失败
    v1.3  加诊断日志，定位真因：{0:D2} 格式符收到 double 类型抛异常
    v1.4  修复：totalSec/m/s 强制 [int] 转整数，时长正常显示 00h00m12s
    v1.5  加同名视频匹配开关（默认 N 跳过，提速）；占位符改"未检测"；
          分辨率加竖屏对调（width<height 时输出 高x宽（竖屏））；保留 NFO路径列
    v1.6  按文件夹分组枚举，单行覆盖刷新进度条，显示 X/XX（文件夹）X/XX（NFO）
    v1.7  加递归扫描开关（默认 Y 递归，输入 N 仅扫当前文件夹）
#>

param(
    [string]$NfoRoot = $PWD.ProviderPath,
    [string]$CsvName = "nfo_export_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
)

# ── 0. 扫描范围 + 同名视频匹配开关（一键响应，无需回车） ──
Write-Host "================" -ForegroundColor Cyan
Write-Host "扫描范围设置"
Write-Host "================" -ForegroundColor Cyan

Write-Host "是否递归扫描子文件夹？[Y/N，默认 Y（直接按键=Y）]: " -NoNewline
$keyRecurse = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
$RecurseInput = $keyRecurse.Character
Write-Host $RecurseInput
$DoRecurse = ($RecurseInput -ne 'n' -and $RecurseInput -ne 'N')
if ($DoRecurse) { Write-Host "✅ 将递归扫描所有子文件夹" -ForegroundColor Green }
else { Write-Host "⚠️ 仅扫描当前文件夹（不含子目录）" -ForegroundColor Yellow }

Write-Host ""
Write-Host "是否启用【同名视频匹配】？（耗时较长，仅用于比对视频和NFO）" -ForegroundColor Cyan
Write-Host "输入Y启用，直接按键或输入N跳过 [默认：N]: " -NoNewline
$keyMatch = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
$MatchInput = $keyMatch.Character
Write-Host $MatchInput
$DoMatchVideo = ($MatchInput -eq 'y' -or $MatchInput -eq 'Y')
Write-Host "→ 同名视频匹配: $(if($DoMatchVideo){'开启'}else{'关闭（跳过，速度最快）'})`n" -ForegroundColor Green

# ── 1. 路径严格预处理 ──
try {
    $rootInfo = New-Object System.IO.DirectoryInfo($NfoRoot)
    if (-not $rootInfo.Exists) { throw "目录不存在: $NfoRoot" }
    $ValidRoot = $rootInfo.FullName

    if ([string]::IsNullOrWhiteSpace($CsvName)) { $CsvName = "nfo_export.csv" }
    $CsvPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($ValidRoot, $CsvName))
} catch {
    Write-Host "[错误] 路径处理失败: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "按回车退出"; exit 1
}

Write-Host "================" -ForegroundColor Cyan
Write-Host "Emby NFO 扫描 → CSV 导出"
Write-Host "扫描根目录: $ValidRoot"
Write-Host "输出文件:   $CsvPath"
Write-Host "================" -ForegroundColor Cyan

# ── 2. 枚举 NFO（受递归开关控制），按目录分组预统计 ──
Write-Host "正在索引文件..." -ForegroundColor Cyan

$searchOpt = if ($DoRecurse) { [System.IO.SearchOption]::AllDirectories } else { [System.IO.SearchOption]::TopDirectoryOnly }
$nfoFilesAll = [System.IO.Directory]::GetFiles($ValidRoot, "*.nfo", $searchOpt)

# 按父目录分组，算出每个目录的文件数，保持枚举顺序
$grouped  = $nfoFilesAll | Group-Object { Split-Path $_ -Parent }
$dirOrder = @($grouped | ForEach-Object { $_.Name })
$dirCounts = @{}; foreach ($g in $grouped) { $dirCounts[$g.Name] = $g.Count }
$dirFiles  = @{}; foreach ($g in $grouped) { $dirFiles[$g.Name]  = @($g.Group) }

$totalNfo  = $nfoFilesAll.Count
$processed = 0

$scopeText = if ($DoRecurse) { "（含子文件夹）" } else { "（仅当前文件夹）" }
Write-Host "发现 NFO 文件数: $totalNfo $scopeText`n" -ForegroundColor Cyan

# ── 3. 解析 NFO（分组遍历 + 实时进度） ──
$rows = New-Object System.Collections.Generic.List[PSCustomObject]
$noFileinfoCount = 0; $parseErrorCount = 0

foreach ($dir in $dirOrder) {
    $dirNfos  = $dirFiles[$dir]
    $dirTotal = $dirCounts[$dir]
    $dirDone  = 0

    $dirName = Split-Path $dir -Leaf
    if ([string]::IsNullOrEmpty($dirName)) { $dirName = $dir }

    foreach ($nfoPath in $dirNfos) {
        $dirDone++
        $processed++

        # ── 单行覆盖刷新进度 ──
        Write-Host "`r$dirDone/$dirTotal（文件夹） $processed/$totalNfo（NFO）  $dirName  " -NoNewline -ForegroundColor DarkGray

        try {
            $xml = New-Object System.Xml.XmlDocument
            $xml.LoadXml([System.IO.File]::ReadAllText($nfoPath))
            $fi = $xml.SelectSingleNode("//fileinfo/streamdetails")
            if (-not $fi) { $noFileinfoCount++; continue }

            $v = $fi.SelectSingleNode("video"); $a = $fi.SelectSingleNode("audio")

            # ✅ 时长：安全取值 + 强制转整数（修复"格式说明符无效"）
            $durSec = 0
            $secNode = $v.SelectSingleNode("durationinseconds")
            if ($secNode -and [double]::TryParse($secNode.InnerText, [ref]$durSec)) {
            } elseif ($v.duration -and [double]::TryParse($v.duration, [ref]$durSec)) {
            }
            $totalSec = [int][Math]::Floor($durSec)
            $h  = [int]($totalSec / 3600)
            $rem = $totalSec % 3600
            $m  = [int]($rem / 60)
            $s  = [int]($rem % 60)
            $durationStr = "{0:D2}h{1:D2}m{2:D2}s" -f $h, $m, $s

            # ↓↓↓ 稳定版写法 ━━━━━━━━━━━━━━━━━━
            $width=0; $height=0
            if ($v.width)  { [int]::TryParse($v.width,  [ref]$width)  | Out-Null }
            if ($v.height) { [int]::TryParse($v.height, [ref]$height) | Out-Null }
            $vBit=0; $aBit=0
            if ($v.bitrate) { [long]::TryParse($v.bitrate, [ref]$vBit) | Out-Null }
            if ($a.bitrate) { [long]::TryParse($a.bitrate, [ref]$aBit) | Out-Null }

            $baseName  = [System.IO.Path]::GetFileNameWithoutExtension($nfoPath)
            $parentDir = [System.IO.Path]::GetDirectoryName($nfoPath)

            # ── 视频匹配（受开关控制，默认跳过） ──
            $videoPath = "未检测"
            if ($DoMatchVideo) {
                $videoPath = "(未找到同名视频)"
                foreach ($ext in @("*.mkv","*.mp4","*.m4v","*.ts","*.avi","*.mov","*.webm")) {
                    foreach ($c in [System.IO.Directory]::GetFiles($parentDir, $ext)) {
                        if ([System.IO.Path]::GetFileNameWithoutExtension($c) -eq $baseName) { $videoPath = $c; break }
                    }
                    if ($videoPath -ne "(未找到同名视频)") { break }
                }
            }

            $rows.Add([PSCustomObject]@{
                文件名         = $baseName
                标题           = if($xml.movie.title) { $xml.movie.title } else { "-" }
                时长           = $durationStr
                视频编码       = if($v.codec)    { $v.codec }    else { "-" }
                分辨率         = if ($width -gt 0 -and $height -gt 0) {
                    if ($width -lt $height) {
                        "$height`x$width（竖屏）"
                    } else {
                        "$width`x$height"
                    }
                } else {
                    "-"
                }
                视频码率_Mbps  = if($vBit -gt 0) { [Math]::Round($vBit/1MB, 2) } else { "-" }
                音频码率_kbps  = if($aBit -gt 0) { [Math]::Round($aBit/1KB, 2) } else { "-" }
                总码率_Mbps    = if(($vBit+$aBit) -gt 0) { [Math]::Round(($vBit+$aBit)/1MB, 2) } else { "-" }
                帧率           = if($v.framerate) { $v.framerate } else { "-" }
                音频编码       = if($a.codec)    { $a.codec }    else { "-" }
                声道           = if($a.channels) { $a.channels } else { "-" }
                视频文件路径   = $videoPath
                NFO路径        = $nfoPath
            }) | Out-Null
        } catch { $parseErrorCount++ }
    }
}

# 进度走完，换行
Write-Host ""

# ── 4. 统计与导出 ──
Write-Host "====================" -ForegroundColor Cyan
Write-Host "扫描完成" -ForegroundColor Green
Write-Host "  总 NFO 数:            $totalNfo"
Write-Host "  涉及文件夹数:         $($dirOrder.Count)"
Write-Host "  解析成功:             $($rows.Count)"
Write-Host "  无 fileinfo 段:       $noFileinfoCount"
Write-Host "  XML 解析失败/读取失败: $parseErrorCount"
Write-Host "====================" -ForegroundColor Cyan

if ($rows.Count -eq 0) {
    Write-Host "`n没有有效数据可导出，退出。" -ForegroundColor Red
    Read-Host "按回车退出"; exit 0
}

try {
    $csvContent = ($rows | ConvertTo-Csv -NoTypeInformation) -join "`r`n"
    [System.IO.File]::WriteAllText($CsvPath, $csvContent, [System.Text.Encoding]::UTF8)
    Write-Host "`n✅ CSV 已导出:" -ForegroundColor Green
    Write-Host "   $CsvPath" -ForegroundColor Cyan
} catch {
    Write-Host "`n[错误] CSV 导出失败: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n按任意键退出..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

