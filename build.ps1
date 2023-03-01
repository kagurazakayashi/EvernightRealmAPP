<#
.SYNOPSIS
    建置 EvernightRealmAPP（Flutter 前端）。
.DESCRIPTION
    預設建置 Windows 桌面版（Release）；可用 -Platform 指定其他目標，
    加 -Debug 改為除錯建置（Android 除錯建置不需簽名）。
    注意：後端內嵌用的 Web 產物由根倉庫 .\build.ps1（tools/buildweb）建置，
    本腳本的 web 目標適合獨立驗證前端，不作為發布用內嵌產物的入口。
.EXAMPLE
    .\build.ps1                    # flutter build windows（Release）
    .\build.ps1 -Platform web
    .\build.ps1 -Platform android -Debug
#>
[CmdletBinding()]
param(
    [ValidateSet('windows', 'web', 'macos', 'linux', 'android', 'ios')]
    [string]$Platform = 'windows',
    [switch]$Debug
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw '找不到 flutter 命令：請安裝 Flutter SDK 並加入 PATH。'
}

Push-Location $root
try {
    $flutterArgs = @('build', $Platform)
    if ($Debug) { $flutterArgs += '--debug' }
    Write-Host ("flutter {0}" -f ($flutterArgs -join ' ')) -ForegroundColor Cyan
    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) { throw "flutter build 失敗（退出碼 $LASTEXITCODE）。" }

    Write-Host "`n建置完成：$Platform（$($(if ($Debug) { 'Debug' } else { 'Release' }))）" -ForegroundColor Green
}
finally {
    Pop-Location
}
