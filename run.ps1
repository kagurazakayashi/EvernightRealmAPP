<#
.SYNOPSIS
    執行 EvernightRealmAPP（Flutter 開發模式）。
.DESCRIPTION
    預設裝置為 Windows 桌面；可用 -Device 指定其他裝置
    （chrome、edge、android、macos、linux 等；列出可用裝置可先跑 flutter devices）。
    根倉庫的 dev-run.bat 是前後端一起跑，本腳本只跑前端。
.EXAMPLE
    .\run.ps1
    .\run.ps1 -Device chrome
    .\run.ps1 -Device android
#>
[CmdletBinding()]
param(
    [string]$Device = 'windows'
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw '找不到 flutter 命令：請安裝 Flutter SDK 並加入 PATH。'
}

Push-Location $root
try {
    Write-Host "flutter run -d $Device（Ctrl+C 結束）" -ForegroundColor Cyan
    & flutter run -d $Device
    exit $LASTEXITCODE
}
finally {
    Pop-Location
}
