# 构建与验证记录

日期：2026-10-18
环境：Windows / DevEco Studio 26.0.0.851 / HarmonyOS SDK 26.0.0.105（API 26）
Go：1.27.2 windows/amd64
sing-box：v1.13.9（上游 tag）

## 已执行的命令与结果

### 1. ArkTS 应用构建

```powershell
$env:DEVECO_SDK_HOME='D:\DEV\DevEco Studio\sdk'
node "D:\DEV\DevEco Studio\tools\hvigor\bin\hvigorw.js" `
  --mode module -p module=entry@default -p product=default assembleHap --no-daemon
```

结果：`BUILD SUCCESSFUL`，0 error。
产物：`entry/build/default/outputs/default/entry-default-unsigned.hap`

### 2. NAPI 原生桥接

`entry/src/main/cpp/CMakeLists.txt` 由 hvigor 调用 OHOS CMake/Ninja 构建，
arm64-v8a 与 x86_64 均通过：

```
Finished :entry:default@BuildNativeWithCmake
Finished :entry:default@BuildNativeWithNinja
```

生成的 `libfirefly.so` 通过 `dlopen("libfireflycore.so")` 延迟加载内核，
因此内核缺失不会导致构建失败或启动崩溃。

### 3. sing-box 内核交叉编译

```powershell
$env:GOOS='linux'; $env:GOARCH='arm64'   # 或 amd64
$env:CGO_ENABLED='1'
$env:CC='<NDK>/llvm/bin/clang.exe'
$env:CGO_CFLAGS='--target=aarch64-linux-ohos --sysroot=<NDK>/sysroot'
$env:CGO_LDFLAGS='--target=aarch64-linux-ohos --sysroot=<NDK>/sysroot -fuse-ld=lld'
go build -tags with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,with_clash_api,with_ccm,with_ocm,with_naive_outbound,badlinkname `
  -ldflags '-checklinkname=0' -buildmode=c-shared -o libfireflycore.so .
```

结果：成功。

| ABI | 大小 | ELF Machine |
| --- | --- | --- |
| arm64-v8a | 30,890,720 B | AArch64 (183) |
| x86_64 | 32,134,168 B | x86-64 (62) |

`llvm-readelf` 结果：

```
Class: ELF64   Type: DYN (Shared object file)
NEEDED: libc.so
导出符号：FireflyStart / FireflyStop / FireflyVersion / FireflyFree
```

### 4. HAP 打包与内容检查

`entry-default-unsigned.hap`：37,271,872 B
SHA256：`e7341bc3ef2b7768537e92dee92e44fb18744479f859c4636995997c130bf329`

包内关键条目：

```
libs/arm64-v8a/libfireflycore.so   16,112,664 B
libs/x86_64/libfireflycore.so     17,335,224 B
libs/arm64-v8a/libfirefly.so           64,504 B
libs/x86_64/libfirefly.so              64,960 B
ets/modules.abc                       328,988 B
module.json                             1,715 B
```

`inspect_hap.py` 确认两个 ABI 的 ELF machine 与路径匹配。

## 未验证项（重要）

| 项目 | 原因 |
| --- | --- |
| 签名 | 开发机 `.ohos` 为空，无华为调试证书，无法生成可安装包 |
| 安装 / 启动 | 未签名 HAP 无法安装；模拟器启动要求接受 HarmonyOS 许可协议，未自动接受 |
| 系统 VPN 授权对话框 | 需要设备运行 |
| TUN fd 交接 | 需要设备运行 |
| Go runtime 在 OHOS musl 沙箱中的初始化 | 需要设备运行 |
| 实际代理转发、DNS、TLS 根证书 | 需要设备运行 |
| 二维码、分应用选择器、浅色主题 | 未实现 |

因此本版本只能交付为「构建级预览」，不能描述为功能已验证完成。
