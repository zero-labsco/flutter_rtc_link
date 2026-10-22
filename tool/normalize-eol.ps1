# normalize-eol.ps1 — force LF line endings (no BOM) across the repository.
# 强制全仓库 LF 换行（无 BOM）。
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$extensions = @('*.dart', '*.yaml', '*.yml', '*.md', '*.kt', '*.swift', '*.gradle', '*.json', '*.podspec', '*.mjs', '*.tsx', '*.js', '*.plist', '*.xml', '*.properties', '*.txt', '*.gitignore', '*.gitattributes', '*.pubignore')
$files = Get-ChildItem -Path $root -Recurse -File -Include $extensions |
  Where-Object { $_.FullName -notlike '*\build\*' -and $_.FullName -notlike '*\.dart_tool\*' -and $_.FullName -notlike '*\node_modules\*' -and $_.FullName -notlike '*\.next\*' }
$fixed = 0
foreach ($file in $files) {
  $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
  $text = [System.Text.Encoding]::UTF8.GetString($bytes)
  $normalized = ($text -replace "`r`n", "`n") -replace "`r", "`n"
  $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
  if ($normalized -ne $text -or $hasBom) {
    [System.IO.File]::WriteAllText($file.FullName, $normalized, (New-Object System.Text.UTF8Encoding($false)))
    $fixed++
    Write-Output "normalized: $($file.FullName)"
  }
}
Write-Output "done, $fixed file(s) normalized to LF"
