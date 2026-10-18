#requires -Version 5.1
<#
    构建 sing-box 鸿蒙原生内核（libfireflycore.so）

    目标：aarch64-linux-ohos / x86_64-linux-ohos
    依赖：Go 1.24+、DevEco Studio 26 自带 OHOS NDK

    脚本会：
      1. 在 core/sing-box 下检出 sing-box v1.13.9（go.mod 中 replace 的目标）
      2. 用 OHOS clang 交叉编译 core/fireflycore 为 c-shared 库
      3. 复制到 entry/libs/<abi>/libfireflycore.so

    用法：
        .\scripts\build-core.ps1                 # 构建 arm64-v8a + x86_64
        .\scripts\build-core.ps1 -Abi arm64-v8a  # 只构建指定 ABI
#>
param(
    [string[]]$Abi = @('arm64-v8a', 'x86_64'),
    [string]$GoRoot = '',
    [string]$SingBoxVersion = 'v1.13.9'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$coreSource = Join-Path $projectRoot 'core\fireflycore'
$singBoxSource = Join-Path $projectRoot 'core\sing-box'

# 定位 Go
if (-not $GoRoot) {
    $cmd = Get-Command go -ErrorAction SilentlyContinue
    if ($cmd) {
        $GoRoot = Split-Path -Parent (Split-Path -Parent $cmd.Source)
    } elseif (Test-Path 'D:\HarmonyDev\go\bin\go.exe') {
        $GoRoot = 'D:\HarmonyDev\go'
    }
}
$go = Join-Path $GoRoot 'bin\go.exe'
if (-not (Test-Path $go)) { throw "未找到 Go，请用 -GoRoot 指定 Go 安装目录" }

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

# 准备 sing-box 源码（go.mod 使用 replace ../sing-box）
if (-not (Test-Path (Join-Path $singBoxSource 'go.mod'))) {
    Write-Host "[build-core] 检出 sing-box $SingBoxVersion" -ForegroundColor Cyan
    git clone --depth 1 --branch $SingBoxVersion https://github.com/SagerNet/sing-box $singBoxSource
    if ($LASTEXITCODE -ne 0) { throw 'sing-box 检出失败' }
}

$tags = 'with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_ccm,with_ocm,with_naive_outbound,badlinkname'
$outDir = Join-Path $projectRoot 'entry\libs'

Push-Location $coreSource
try {
    & $go mod download
    foreach ($item in $Abi) {
        switch ($item) {
            'arm64-v8a' { $goarch = 'arm64'; $target = 'aarch64-linux-ohos' }
            'x86_64'    { $goarch = 'amd64'; $target = 'x86_64-linux-ohos' }
            default     { throw "不支持的 ABI：$item" }
        }
        $env:GOOS = 'linux'
        $env:GOARCH = $goarch
        $env:CGO_ENABLED = '1'
        $env:CGO_LDFLAGS_ALLOW = '.*'
        $env:CC = $clang
        $env:CGO_CFLAGS = "--target=$target --sysroot=$sysroot"
        $env:CGO_LDFLAGS = "--target=$target --sysroot=$sysroot -fuse-ld=lld"

        Write-Host "[build-core] $item ($target)" -ForegroundColor Cyan
        & $go build -tags $tags -ldflags '-checklinkname=0' -buildmode=c-shared -o libfireflycore.so .
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
