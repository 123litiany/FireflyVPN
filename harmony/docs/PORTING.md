# Android → HarmonyOS 移植记录

上游：https://github.com/Iskongkongyo/FireflyVPN
检查提交：`c003f3d1f79fa77c91d4bafaf45a67c29934e8e1`（main）
移植目标：HarmonyOS 26.0.0（API 26，兼容 HarmonyOS 7.0），ArkTS/ArkUI Stage 模型

## 结论

FireflyVPN 是 Kotlin + Jetpack Compose 的 sing-box 客户端（约 27,400 行 Kotlin），
Android 平台依赖集中在：

- `VpnService` / `Service` 前台服务 → 鸿蒙 `VpnExtensionAbility`
- `libbox.aar`（sing-box）→ Go 交叉编译的 `libfireflycore.so` + NAPI 桥接
- Room + SQLCipher → `relationalStore`（开启 `encrypt`）
- DataStore → `preferences`
- OkHttp/Retrofit/Gson → `@ohos.net.http` + `JSON.parse`
- CameraX + ML Kit 扫码 → 待接 ScanKit
- Compose UI → ArkUI 声明式 UI

上游 `AppConfig.API_BASE_URL` 在公开仓库中是占位符（`https://填写域名`），
因此公开版本本身就是通用 sing-box 订阅客户端；后端 Crypto V2 相关逻辑
（FireflySubscriptionClient / SubscriptionCryptoV2）在未配置后端时不参与主流程，
本移植暂未引入，避免与真实服务端协议不一致时产生伪加密。

## 映射表

| Android | HarmonyOS | 文件 |
| --- | --- | --- |
| `Node.kt` / `NodeType.kt` | `Node` / `NodeType` | `model/Models.ets` |
| `SubscriptionGroup.kt` / `SubscriptionLink.kt` | 同名类 | `model/Models.ets` |
| `AppConfig.kt` | `AppConfig` | `common/AppConfig.ets` |
| `SubscriptionParser.kt` | `LinkParser` | `util/LinkParser.ets` |
| `SingBoxConfigGenerator.kt` | `ConfigGenerator` | `util/ConfigGenerator.ets` |
| `RuntimeLog.kt` | `RuntimeLog` + `LogEntry` | `util/Utils.ets` |
| `AppDatabase.kt`（Room） | `Database`（RDB） | `data/Database.ets` |
| `SettingsRepository.kt`（DataStore） | `SettingsStore` | `data/SettingsStore.ets` |
| `NetworkClient.kt` / `ApiService`（OkHttp） | `HttpClient` | `net/HttpClient.ets` |
| `LatencyTester`（libbox TCPing/URLTest） | `LatencyTester`（系统 TCP） | `net/LatencyTester.ets` |
| `SpeedTestService.kt` | `SpeedTester` | `net/SpeedTester.ets` |
| `BoxVpnService.kt`（VpnService） | `FireflyVpnExtension` | `vpn/FireflyVpnExtension.ets` |
| `BoxPlatformInterface.kt` | `fireflycore` Go 平台层 | `core/fireflycore/main.go` |
| `MainViewModel.kt` + `MainScreen.kt` | `pages/Index.ets` | |
| `NodeListDialog.kt` | `pages/Nodes.ets` | |
| `SubscriptionManagementScreen.kt` | `pages/Subscriptions.ets` | |
| `OtherConfigScreen.kt` / `Dialogs.kt` | `pages/Settings.ets` | |
| `RuntimeLogScreen.kt` | `pages/Logs.ets` | |
| `NetworkToolboxDialog.kt` / `SpeedTestDialog.kt` | `pages/Tools.ets` | |

## 关键实现差异

1. **TUN 获取顺序不同**
   Android：`VpnService.Builder.establish()` 返回 fd，随后 `libbox` 启动。
   鸿蒙：`vpnExtension.create(config)` 返回 fd，随后原生内核启动；地址与路由
   由系统 VPN 服务下发，内核 `OpenInterface` 只接管 fd（`auto_route=false`）。

2. **没有前台 Service 通知**
   鸿蒙 VPN 扩展由系统管理生命周期，不需要 `startForeground`；状态通过
   `CommonEvent` 与 `preferences` 回传 UI。流量通知未实现。

3. **延迟测试语义收窄**
   Android 的 URL Test 通过代理链路发起；鸿蒙 v0.1 只做 TCP 握手时延。
   后者仍可用于节点排序，但不代表代理后的可用性。

4. **配置生成未完全对齐**
   上游生成器 1260 行，覆盖 TUN 分流、GeoIP/GeoSite 规则集、QUIC 规则、
   分应用、Hysteria2 自适应带宽等。本移植实现了主要协议与传输，
   规则集（`adrules.srs` 等）尚未打包，路由目前为「私有地址直连 + 全局代理」。

5. **存储加密**
   Android 用 SQLCipher + 随机口令；鸿蒙 RDB 使用系统 `encrypt: true`，
   密钥由系统托管，不落盘到应用偏好。

## 未实现 / 待办

- 二维码导入（ScanKit）
- 分应用应用选择器（`GET_BUNDLE_INFO` + 列表 UI）
- 主题（浅色/跟随系统）
- 订阅周期自动更新调度（当前仅启动检查一次）
- 解锁测试 / 自动择优 / 出口 IP 归属地库
- 应用内更新（HAP 分发方式不同，应由应用市场或手动安装）
- 真机运行验证（签名、安装、VPN 授权、内核加载、真实代理）

## 风险

- Go c-shared 库在鸿蒙 musl 应用沙箱中的运行行为未实测，包括：
  Go runtime 线程/信号初始化、`dlopen` 依赖解析、TUN fd 读写、
  DNS 与 TLS 根证书。
- 若内核加载失败，应用会明确报错并拒绝创建 TUN，不会造成全局断网。
- 系统 VPN 授权对话框与 `startVpnExtensionAbility` 的实际行为需要真机确认。

## 2026-10-18 模拟器实测补充

- Go c-shared 的 initial-exec TLS 在 musl 上不能 `dlopen`，已改用
  OpenHarmony Go 工具链（TLSDESC），内核在扩展进程中加载、启动并通过
  clash_api 自检。详见 `docs/VERIFICATION.md`。
- sing-box 在存在 `PlatformInterface` 时必调用
  `CreateDefaultInterfaceMonitor()`，必须返回可用对象，否则空指针崩溃；
  包装层已实现基于 `net.Interfaces()` 的监控。
- 不能用 `with_naive_outbound`：它会静态链接 Cronet，导出 `malloc/free`
  并劫持进程分配器，造成 ArkTS 崩溃；当前不支持 Naive。
- Go 运行时只能在 VPN 扩展进程加载，UI 进程不得 `dlopen` 内核。
- 模拟器镜像缺少 `com.huawei.hmos.vpndialog`，无法完成 VPN 授权；
  TUN 创建与转发仍需真机验证。

