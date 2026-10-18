# FireflyVPN for HarmonyOS

FireflyVPN 的鸿蒙原生移植（ArkTS / ArkUI，Stage 模型）。
上游：https://github.com/Iskongkongyo/FireflyVPN

- 目标系统：HarmonyOS 26.0.0（API 26，兼容 HarmonyOS 7.0）
- 构建工具：DevEco Studio 26.0.0.851 / hvigor 6.26.8
- 包名：`io.github.iskongkongyo.fireflyvpn`
- 许可证：GPL-3.0
- 当前版本：0.1.0（**模拟器已验证客户端与内核，VPN 授权受模拟器镜像限制**）

## 已验证（HarmonyOS 7.0.0 模拟器，API 26，x86_64）

| 项目 | 结果 |
| --- | --- |
| 未签名 HAP 安装 | 通过（`hdc install -r`） |
| 应用启动 / 主界面 | 通过 |
| 加密 RDB（relationalStore） | 通过，读写订阅与节点 |
| 订阅添加 / 拉取 / 解析 / 去重 | 通过（HTTP + Base64，解析 3 个测试节点） |
| 节点列表 / 当前节点 | 通过 |
| sing-box 原生库加载 | 通过（`fireflycore/0.1.0 (sing-box 1.13.9)`） |
| sing-box 启动 + clash_api | 通过（自检：`HTTP 200 {"meta":true,...}`） |
| VPN 隧道 | **未能验证**：模拟器镜像缺少系统 VPN 授权组件 `com.huawei.hmos.vpndialog`，无法完成授权与 TUN 创建 |

VPN 部分需要真机验证：授权弹窗、TUN fd、真实代理转发、DNS/TLS 行为。

## 功能

| 模块 | 实现 | 状态 |
| --- | --- | --- |
| 主界面 / 连接控制 | ArkUI `pages/Index` | 已实现 |
| 节点列表 / 搜索 / 排序 / 选择 | `pages/Nodes` | 已实现 |
| 订阅管理（分组、多链接、去重、自动更新） | relationalStore + `pages/Subscriptions` | 已实现 |
| 链接解析（VLESS/VMess/Trojan/Hysteria2/AnyTLS/TUIC/SS/SOCKS/HTTP 等） | `util/LinkParser.ets` | 已实现 |
| sing-box 配置生成 | `util/ConfigGenerator.ets` | 主要协议与传输 |
| 延迟测试 | 系统 TCP（TCPing 语义） | 已实现 |
| 下载测速 / 出口 IP | `@ohos.net.http` | 已实现 |
| 运行时日志 | 环形缓冲 + hilog + `pages/Logs` | 已实现 |
| 设置（IPv6 / TUN 栈 / 自动更新 / 分应用开关） | preferences + `pages/Settings` | 已实现 |
| VPN 隧道 | `VpnExtensionAbility` + `@ohos.net.vpnExtension` + Go/sing-box | 代码完成，待真机 |
| 内核自检 | 扩展进程 mixed 入站 + clash_api | 已实现并通过 |
| 二维码导入 / 分应用选择器 / 浅色主题 | — | 未实现 |

## 目录

```
harmony/
├─ AppScope/                     # 应用级配置
├─ entry/
│  ├─ libs/<abi>/libfireflycore.so   # Go + sing-box 内核（构建产物，不入库）
│  ├─ src/main/cpp/                  # NAPI 桥接（dlopen 加载内核）
│  ├─ src/main/ets/
│  │  ├─ common/  data/  model/  net/  service/  util/  vpn/  pages/
│  │  └─ ...
│  └─ src/main/module.json5
├─ core/fireflycore/             # Go 包装层（sing-box + PlatformInterface）
├─ core/exports.map              # 只导出 Firefly* 符号，避免 malloc 等符号污染进程
├─ scripts/build-core.ps1        # 交叉编译内核
└─ scripts/build-hap.ps1         # 构建 HAP
```

## 构建

### 1. OpenHarmony Go 工具链（内核必需）

官方 Go 的 c-shared 在 musl 上使用 initial-exec TLS，`dlopen` 会报
`initial-exec TLS resolves to dynamic definition`。必须用 OpenHarmony 工具链：

```powershell
git clone -b openharmony-amd64-tlsdesc https://gitcode.com/ohstar/ohos_golang_go.git
cd ohos_golang_go\src
$env:GOROOT_BOOTSTRAP='<官方 Go 安装目录>'
.\make.bat
```

该分支为 `openharmony/amd64` 输出 TLSDESC 重定位（产物中
`R_X86_64_GOTTPOFF = 0`、`TLSDESC > 0`、无 `DF_STATIC_TLS`）。

### 2. 内核

```powershell
.\scripts\build-core.ps1 -GoRoot D:\HarmonyDev\go-ohos
```

脚本会检出 sing-box v1.13.9 与 sing-tun v0.8.9、调整其 go 指令、用 OHOS NDK
交叉编译 arm64-v8a 与 x86_64，并放入 `entry/libs/<abi>/`。

注意：构建内核时**不要**启用 `with_naive_outbound`。Naive 会静态链接
Cronet（Chromium），其 allocator shim 会与系统 libc 冲突并导致崩溃；
因此当前版本不支持 Naive 节点。

### 3. HAP

```powershell
.\scripts\build-hap.ps1
# 产物：entry\build\default\outputs\default\entry-default-unsigned.hap
```

模拟器可直接安装未签名 HAP；真机需要 DevEco 自动签名或自有证书：

```powershell
hdc install -r entry-default-unsigned.hap
hdc shell aa start -a EntryAbility -b io.github.iskongkongyo.fireflyvpn
```

### 4. 内核自检（不创建 TUN）

```powershell
hdc shell "aa start -b io.github.iskongkongyo.fireflyvpn -a FireflyVpnExtension --ps selfTest true"
hdc shell "hilog -x | grep FireflyVPN | tail"
```

预期日志：

```
VpnExtension 原生库版本: fireflycore/0.1.0 (sing-box 1.13.9)
CoreBridge 内核已启动
VpnExtension 自检通过: ... clash_api HTTP 200: {"meta":true,"premium":true,...}
```

## 架构要点

- **TUN**：`@ohos.net.vpnExtension` 的 `VpnConnection.create()` 返回 fd；
  Go 侧在 `adapter.PlatformInterface.OpenInterface` 中把 fd 写入
  `sing-tun` 的 `Options.FileDescriptor`，路由由系统 VPN 服务配置。
- **进程隔离**：Go 运行时只在 `FireflyVpnExtension` 进程加载；UI 进程
  不 `dlopen` 内核（否则 Go 后台线程与 ArkTS 运行时冲突）。
- **回环防护**：扩展创建 TUN 后调用 `protectProcessNet()`，让内核出站
  socket 走物理网络。
- **符号隔离**：链接时使用 `core/exports.map` 只导出 `Firefly*`，避免
  Cronet/musl 的 `malloc` 等符号污染 ArkTS 进程。

## 已知限制

1. 模拟器缺少 VPN 授权组件，无法验证隧道；需要真机。
2. 未签名 HAP 仅便于开发；真机安装必须签名。
3. 分应用选择器、二维码、浅色主题、周期自动更新未实现。
4. 配置生成覆盖主要协议，Naive 不支持；WireGuard/TUIC 等细节未逐一验证。
5. 延迟测试为 TCPing，非代理链路 URL Test。

## 许可证

GPL-3.0。sing-box 为 GPL-3.0-or-later，源码与构建脚本随仓库提供；
详见仓库根目录 `LICENSE` 与 `harmony/NOTICE`。
