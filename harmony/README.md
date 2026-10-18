# FireflyVPN for HarmonyOS

FireflyVPN 的鸿蒙原生移植（ArkTS / ArkUI，Stage 模型）。

- 目标系统：HarmonyOS 26.0.0（API 26，兼容 HarmonyOS 7.0）
- 构建工具：DevEco Studio 26.0.0.851 / hvigor 6.26.8
- 包名：`io.github.iskongkongyo.fireflyvpn`
- 许可证：GPL-3.0（与上游 FireflyVPN、sing-box 一致）

> 当前版本是 **0.1.0 预览版**。应用外壳、订阅与节点管理、设置、日志、工具箱、
> VPN 扩展以及 sing-box 原生内核均已落地并通过构建；由于本机没有可用的
> HarmonyOS 调试签名证书，**尚未在真机或模拟器上完成运行验证**。
> 详见文末「验证状态」。

## 功能

| 模块 | Android 原实现 | 鸿蒙实现 | 状态 |
| --- | --- | --- | --- |
| 主界面 / 连接控制 | Compose + MainViewModel | ArkUI `pages/Index` | 已实现 |
| 节点列表 / 搜索 / 排序 / 选择 | NodeListDialog | ArkUI `pages/Nodes` | 已实现 |
| 订阅管理（分组、多链接、去重、自动更新） | Room + SubscriptionManagementScreen | relationalStore + `pages/Subscriptions` | 已实现 |
| 链接解析（VLESS/VMess/Trojan/Hysteria2/AnyTLS/TUIC/Naive/WireGuard/SS/SOCKS/HTTP） | SubscriptionParser | `util/LinkParser.ets` | 已实现 |
| sing-box 配置生成 | SingBoxConfigGenerator（1260 行） | `util/ConfigGenerator.ets` | 主要协议与传输已实现 |
| 延迟测试 | libbox TCPing / URLTest | 系统 TCP 连接（TCPing 语义） | 已实现 |
| 下载测速 | OkHttp + Cloudflare | `@ohos.net.http` | 已实现 |
| 出口 IP 查询 | OkHttp | `@ohos.net.http` | 已实现 |
| 运行时日志 | RuntimeLog | 内存环形缓冲 + `pages/Logs` | 已实现 |
| 设置（IPv6 / TUN 栈 / 自动更新 / 分应用开关） | DataStore | preferences + `pages/Settings` | 已实现 |
| VPN 隧道 | `VpnService` + libbox | `VpnExtensionAbility` + `@ohos.net.vpnExtension` + Go/sing-box 内核 | 代码完成，**未运行验证** |
| 二维码导入 | CameraX + ML Kit | 未实现 | 待办 |
| 分应用应用选择器 | PackageManager | 未实现（仅开关与已保存白名单） | 待办 |
| 主题切换 | Compose 深色主题 | 固定深色（设置项已持久化） | 待办 |
| 应用内更新 | OkHttp + APK 安装 | 未实现（HAP 更新机制不同） | 不适用 |

## 目录

```
harmony/
├─ AppScope/                     # 应用级配置（bundleName、图标）
├─ entry/
│  ├─ libs/<abi>/libfireflycore.so   # Go + sing-box 内核（由 scripts/build-core.ps1 生成）
│  ├─ src/main/cpp/                  # NAPI 桥接（dlopen 加载内核）
│  ├─ src/main/ets/
│  │  ├─ common/       AppConfig、AppContext
│  │  ├─ data/         Database（relationalStore）、SettingsStore（preferences）
│  │  ├─ model/        Node / Subscription / Settings 模型
│  │  ├─ net/          HttpClient、LatencyTester、SpeedTester
│  │  ├─ service/      SubscriptionRepository、VpnManager、CoreBridge
│  │  ├─ util/         LinkParser、ConfigGenerator、JsonWriter、RuntimeLog
│  │  ├─ vpn/          FireflyVpnExtension（VpnExtensionAbility）
│  │  └─ pages/        Index / Nodes / Subscriptions / Settings / Logs / Tools
│  └─ src/main/module.json5
├─ scripts/build-core.ps1        # 交叉编译 sing-box 内核
└─ scripts/build-hap.ps1         # 构建 HAP
```

## 构建

前置：DevEco Studio 26（含 HarmonyOS SDK 26.0.0）、Node（DevEco 自带）、
Go 1.24+（构建内核时需要）。

```powershell
# 1) 可选：构建并放入原生内核（需要 Go 与 OHOS NDK）
.\scripts\build-core.ps1

# 2) 构建 HAP（未签名）
.\scripts\build-hap.ps1
# 产物：entry\build\default\outputs\default\entry-default-unsigned.hap
```

签名与安装：在 DevEco Studio 打开 `harmony/`，登录华为开发者账号后
`Project Structure → Signing Configs` 勾选自动签名，或使用自有证书对
HAP 签名，然后 `hdc install` 安装。仓库中的 HAP 为**未签名**产物，
不能直接安装。

### 内核构建说明

`libfireflycore.so` 使用 sing-box v1.13.9 作为库，通过
`adapter.PlatformInterface` 接管由 ArkTS 创建的 TUN fd：

- `@ohos.net.vpnExtension` 的 `VpnConnection.create()` 返回 fd；
- 原生层在 `OpenInterface` 中把 fd 写入 `sing-tun` 的 `Options.FileDescriptor`；
- 路由与地址由系统 VPN 服务配置，内核只负责收发与代理。

构建参数（`scripts/build-core.ps1` 已封装）：

```
GOOS=linux GOARCH=arm64|x86_64 CGO_ENABLED=1
CC=<OHOS NDK>/llvm/bin/clang
CGO_CFLAGS=--target=aarch64-linux-ohos --sysroot=<NDK>/sysroot
tags: with_gvisor,with_quic,with_dhcp,with_wireguard,with_utls,with_acme,
      with_clash_api,with_ccm,with_ocm,with_naive_outbound,badlinkname
```

## 验证状态

| 项目 | 证据 |
| --- | --- |
| ArkTS 编译 | `hvigor assembleHap` 成功（0 error） |
| NAPI 原生模块 | CMake/Ninja 构建成功，arm64-v8a 与 x86_64 双 ABI |
| sing-box 内核 | Go 交叉编译成功；`llvm-readelf` 确认 ELF64、AArch64/x86-64、仅依赖 `libc.so`，导出 `FireflyStart/Stop/Version/Free` |
| HAP 包内容 | `libs/arm64-v8a/libfireflycore.so`（16.1 MB 压缩）、`libs/x86_64/...`、`libs/*/libfirefly.so`、`ets/modules.abc` |
| 签名 | **未签名**（本机无证书） |
| 安装 / 启动 / VPN 连接 | **未验证**（无签名，无法安装） |

因此本版本只能称为「构建级预览」。内核在 OHOS musl 环境下的运行行为
（Go runtime 初始化、TUN fd 接管、DNS/TLS 证书）尚未实测。

## 已知限制

1. 未签名 HAP 无法安装；需要开发者签名。
2. 二维码导入、分应用选择器、浅色主题尚未实现。
3. 配置生成覆盖主要协议，但未逐一与上游 1260 行生成器对齐（如 WireGuard/Naive 的细节）。
4. 流量统计依赖 sing-box `clash_api`，内核未运行时显示 0。
5. 自动更新目前为「启动后检查一次」，周期检查尚未调度。

## 许可证

本移植遵循上游 GPL-3.0。原生内核为 sing-box（GPL-3.0）的衍生构建，
其源码与构建脚本随仓库提供。详见仓库根目录 `LICENSE` 与
`harmony/NOTICE`。
