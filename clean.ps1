<#
.SYNOPSIS
    清理 EvernightRealmAPP 的建置產物。
.DESCRIPTION
    執行 flutter clean（刪除 build/、.dart_tool/ 等產物與快取），
    再補刪可能殘留的 build 目錄。不會觸碰 lib/、assets/、pubspec.yaml。
.EXAMPLE
    .\clean.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw '找不到 flutter 命令：請安裝 Flutter SDK 並加入 PATH。'
}

Push-Location $root
try {
    Write-Host 'flutter clean ...' -ForegroundColor Cyan
    & flutter clean
    if ($LASTEXITCODE -ne 0) { throw "flutter clean 失敗（退出碼 $LASTEXITCODE）。" }

    $build = Join-Path $root 'build'
    if (Test-Path -LiteralPath $build) {
        Remove-Item -LiteralPath $build -Recurse -Force
        Write-Host "已補刪 $build" -ForegroundColor Green
    }
    Write-Host '清理完成。' -ForegroundColor Green
}
finally {
    Pop-Location
}
