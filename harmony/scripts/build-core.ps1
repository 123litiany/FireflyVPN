#requires -Version 5.1
<#
    构建 sing-box 鸿蒙原生内核（libfireflycore.so）

    关键点：官方 Go 的 c-shared 在 musl/OHOS 上使用 initial-exec TLS，
    dlopen 会失败（initial-exec TLS resolves to dynamic definition）。
    必须使用 OpenHarmony Go 工具链（openharmony/amd64 分支带 TLSDESC 修复）。

    前置：
      1. 官方 Go（用于 bootstrap）
      2. 构建好的 OpenHarmony Go 工具链：
         git clone -b openharmony-amd64-tlsdesc https://gitcode.com/ohstar/ohos_golang_go.git
         cd ohos_golang_go\src
         $env:GOROOT_BOOTSTRAP='<官方 Go 目录>'
         .\make.bat
      3. DevEco Studio 26（OHOS NDK）

    用法：
        .\scripts\build-core.ps1                       # 双 ABI
        .\scripts\build-core.ps1 -Abi arm64-v8a        # 只构建 arm64
#>
param(
    [string[]]$Abi = @('arm64-v8a', 'x86_64'),
    [string]$GoRoot = 'D:\HarmonyDev\go-ohos',
    [string]$SingBoxVersion = 'v1.13.9',
    [string]$SingTunVersion = 'v0.8.9'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$coreSource = Join-Path $projectRoot 'core\fireflycore'
$singBoxSource = Join-Path $projectRoot 'core\sing-box'
$singTunSource = Join-Path $projectRoot 'core\sing-tun'
$exportMap = Join-Path $projectRoot 'core\exports.map'

# 定位 OpenHarmony Go 工具链
$go = Join-Path $GoRoot 'bin\go.exe'
if (-not (Test-Path $go)) { throw "未找到 OpenHarmony Go 工具链：$go（可用 -GoRoot 指定）" }
$distList = & $go tool dist list 2>&1
if (($distList | Select-String -Quiet 'openharmony/amd64')) {
    Write-Host '[build-core] OpenHarmony Go 工具链检查通过' -ForegroundColor Cyan
} else {
    throw "该 Go 工具链不支持 openharmony/amd64，请使用 ohos_golang_go 的 openharmony-amd64-tlsdesc 分支"
}

# 定位 OHOS NDK
$sdkRoot = if ($env:DEVECO_SDK_HOME) { $env:DEVECO_SDK_HOME } else { 'D:\DEV\DevEco Studio\sdk' }
$native = Join-Path $sdkRoot 'default\openharmony\native'
if (-not (Test-Path (Join-Path $native 'llvm\bin\clang.exe'))) {
    throw "未找到 OHOS NDK：$native（请设置 DEVECO_SDK_HOME）"
}

# Go 的 CC 不接受含空格路径，用 junction 规避
$link = Join-Path $env:LOCALAPPDATA 'firefly-ohos-native'
if (-not (Test-Path $link)) {
    New-Item -ItemType Junction -Path $link -Target $native | Out-Null
}
$clang = Join-Path $link 'llvm\bin\clang.exe'
$sysroot = Join-Path $link 'sysroot'

function Ensure-GoDirective([string]$path, [string]$goVersion) {
    $content = Get-Content $path -Raw
    $updated = $content -replace '(?m)^go 1\.\d+(\.\d+)?\r?$', "go $goVersion"
    if ($updated -ne $content) {
        [IO.File]::WriteAllText($path, $updated, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "[build-core] 已调整 $path 的 go 指令为 $goVersion" -ForegroundColor Yellow
    }
}

# sing-box 源码（go.mod 中 replace 指向 ../sing-box）
if (-not (Test-Path (Join-Path $singBoxSource 'go.mod'))) {
    Write-Host "[build-core] 检出 sing-box $SingBoxVersion" -ForegroundColor Cyan
    git clone --depth 1 --branch $SingBoxVersion https://github.com/SagerNet/sing-box $singBoxSource
    if ($LASTEXITCODE -ne 0) { throw 'sing-box 检出失败' }
}
Ensure-GoDirective (Join-Path $singBoxSource 'go.mod') '1.24.5'

# sing-tun 源码（其 go.mod 要求 1.24.7，工具链为 1.24.5，需下调）
if (-not (Test-Path (Join-Path $singTunSource 'go.mod'))) {
    Write-Host "[build-core] 检出 sing-tun $SingTunVersion" -ForegroundColor Cyan
    git clone --depth 1 --branch $SingTunVersion https://github.com/SagerNet/sing-tun $singTunSource
    if ($LASTEXITCODE -ne 0) {
        throw 'sing-tun 检出失败（可改用 Go 模块缓存中的 sing-tun@v0.8.9 复制到 core/sing-tun）'
    }
}
Ensure-GoDirective (Join-Path $singTunSource 'go.mod') '1.24.5'

$tags = 'with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_ccm,with_ocm,badlinkname'
$ldflags = "-s -w -checklinkname=0 -extldflags=-Wl,--version-script=$exportMap"
$outDir = Join-Path $projectRoot 'entry\libs'

Push-Location $coreSource
try {
    foreach ($item in $Abi) {
        switch ($item) {
            'arm64-v8a' { $goarch = 'arm64'; $target = 'aarch64-linux-ohos' }
            'x86_64'    { $goarch = 'amd64'; $target = 'x86_64-linux-ohos' }
            default     { throw "不支持的 ABI：$item" }
        }
        $env:GOOS = 'openharmony'
        $env:GOARCH = $goarch
        $env:CGO_ENABLED = '1'
        $env:CGO_LDFLAGS_ALLOW = '.*'
        $env:CC = $clang
        $env:CGO_CFLAGS = "--target=$target --sysroot=$sysroot"
        $env:CGO_LDFLAGS = "--target=$target --sysroot=$sysroot -fuse-ld=lld"

        Write-Host "[build-core] $item ($target)" -ForegroundColor Cyan
        & $go build -tags $tags -ldflags $ldflags -buildmode=c-shared -o libfireflycore.so .
        if ($LASTEXITCODE -ne 0) { throw "Go 构建失败：$item" }

        $dest = Join-Path $outDir $item
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        Copy-Item libfireflycore.so (Join-Path $dest 'libfireflycore.so') -Force
        $hash = (Get-FileHash (Join-Path $dest 'libfireflycore.so') -Algorithm SHA256).Hash
        Write-Host "[build-core] $item -> $dest\libfireflycore.so  SHA256=$hash" -ForegroundColor Green
    }
} finally {
    Pop-Location
}
