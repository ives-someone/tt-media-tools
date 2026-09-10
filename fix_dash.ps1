<#
一键修复ps1脚本内U+2011(-) → 标准U+002D(-)
仅替换代码语法部分，输出显示字符串内容不会改动
#>
$ps1Files = Get-ChildItem -File -Filter *.ps1
foreach ($f in $ps1Files) {
    $raw = Get-Content -LiteralPath $f.FullName -Raw
    # 把U+2011全部替换为标准减号U+002D
    $fixed = $raw.Replace([char]0x2011, '-')
    if ($raw -ne $fixed) {
        Write-Host "修复文件：$($f.Name)"
        $fixed | Set-Content -LiteralPath $f.FullName -Encoding utf8
    }
}
Write-Host "`n全部ps1脚本U+2011非标准连字符替换完成！"

