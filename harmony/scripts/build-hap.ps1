#requires -Version 5.1
<#
    构建 FireflyVPN HarmonyOS HAP（未签名）

    依赖：DevEco Studio 26 / HarmonyOS SDK 26.0.0（API 26）
    用法：
        .\scripts\build-hap.ps1                # debug 未签名 HAP
        .\scripts\build-hap.ps1 -Mode release
#>
param(
    [ValidateSet('debug', 'release')]
    [string]$Mode = 'debug',
    [string]$DevEcoHome = 'D:\DEV\DevEco Studio'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$node = Join-Path $DevEcoHome 'tools\node\node.exe'
$hvigor = Join-Path $DevEcoHome 'tools\hvigor\bin\hvigorw.js'
$env:DEVECO_SDK_HOME = Join-Path $DevEcoHome 'sdk'

if (-not (Test-Path $node)) { throw "未找到 DevEco node：$node" }
if (-not (Test-Path $hvigor)) { throw "未找到 hvigor：$hvigor" }

Push-Location $projectRoot
try {
    & $node $hvigor --mode module -p module=entry@default -p product=default `
        -p buildMode=$Mode assembleHap --no-daemon
    if ($LASTEXITCODE -ne 0) { throw 'HAP 构建失败' }
} finally {
    Pop-Location
}

$outputs = Join-Path $projectRoot 'entry\build\default\outputs\default'
Get-ChildItem $outputs -Filter '*.hap' | ForEach-Object {
    Write-Host ("构建产物: {0}  ({1:N0} bytes)" -f $_.FullName, $_.Length) -ForegroundColor Green
    Write-Host ("SHA256: {0}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash)
}
