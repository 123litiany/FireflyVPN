# 构建与验证记录

日期：2026-10-18
主机构建环境：Windows / DevEco Studio 26.0.0.851 / HarmonyOS SDK 26.0.0.105（API 26）
模拟器：HarmonyOS 7.0.0.107（SP8DEVC00E999R4P11），API 26，x86_64
Go：OpenHarmony 工具链 `go1.24.5 windows/amd64`（`openharmony-amd64-tlsdesc` 分支）
sing-box：v1.13.9；sing-tun：v0.8.9

## 一、构建结果

| 产物 | 大小 | 说明 |
| --- | --- | --- |
| `libfireflycore.so`（x86_64） | 47,792,464 B | `FireflyStart/Stop/Version/Free` |
| `libfireflycore.so`（arm64-v8a） | 45,629,872 B | 同上 |
| `entry-default-unsigned.hap` | 97,259,951 B | 双 ABI，含 NAPI 桥接 |
| HAP SHA256 | `2219fef206dd4dc28b8a1915c5d44864e16e6634edc380813694211e05da8af5` | 本次验证版本 |

内核 ELF 断言（x86_64）：

```
Class: ELF64   Machine: Advanced Micro Devices X86-64
R_X86_64_GOTTPOFF = 0
R_X86_64_TPOFF64  = 0
R_X86_64_TLSDESC  = 1
FLAGS: SYMBOLIC BIND_NOW        # 无 DF_STATIC_TLS
NEEDED: libc.so
```

arm64 内核同样无 initial-exec TLS 重定位。

## 二、模拟器验证（已通过）

模拟器接受**未签名 HAP**，可直接 `hdc install -r` 安装。

| 项目 | 证据 |
| --- | --- |
| 安装 | `App install path:... msg:install bundle successfully.` |
| 启动 | 主界面显示「sing-box 内核已集成」、节点 `Test-VLESS` |
| 加密数据库 | `Database 数据库已打开（加密存储）` |
| 订阅管理 | 添加 `http://10.0.2.2:8000/sub.txt` → `订阅解析完成，共 3 个节点` → `写入 3 个节点` → 列表显示 2 个分组 |
| 节点 | 主界面与节点页显示 3 个节点、当前节点、协议与地址 |
| 内核加载 | `VpnExtension 原生库版本: fireflycore/0.1.0 (sing-box 1.13.9)` |
| 内核启动 | `CoreBridge 内核已启动` |
| clash_api | `自检通过: ... clash_api HTTP 200: {"meta":true,"premium":true,"version":"sing-box unknown"}` |

自检命令：

```powershell
hdc shell "aa start -b io.github.iskongkongyo.fireflyvpn -a FireflyVpnExtension --ps selfTest true"
```

自检使用本地 `mixed` 入站 + `direct` 出站，不创建 TUN，不影响系统网络。

## 三、VPN 隧道：模拟器上无法验证

现象：点击连接后停在「连接中…」，系统尝试启动
`com.huawei.hmos.vpndialog/VpnServiceExtAbility`，但该 bundle 在模拟器镜像中不存在：

```
BMSCommon: bundle not exist -n com.huawei.hmos.vpndialog
AMS: failed: com.huawei.hmos.vpndialog
```

绕过授权直接 `aa start` 扩展时，扩展能运行，但：

```
NETMANAGER_EXT: enter VpnConnectionExt SetUp ... mtu: 9000 ... isDefaultRoute: 1
VpnExtension 启动失败: 202 Non-system applications use system APIs
```

说明 VPN 配置本身被系统网络服务接受，失败点是**未获得系统授权**，
而模拟器没有授权弹窗组件。该问题属于镜像能力缺失，不是应用代码缺陷；
需要在真实 HarmonyOS 设备上完成授权后验证 TUN 与转发。

## 四、调试过程中修复的问题

1. **Go c-shared 无法 dlopen**
   `Error relocating libfireflycore.so: initial-exec TLS resolves to dynamic definition`。
   官方 Go 在 musl 上使用 initial-exec TLS；改用 OpenHarmony Go 工具链
   （`openharmony-amd64-tlsdesc`，TLSDESC 重定位）后加载成功。

2. **Cronet/PartitionAlloc 符号污染**
   `with_naive_outbound` 会静态链接 Cronet，导出 `malloc/free` 并劫持进程分配器，
   导致 ArkTS 进程 SIGSEGV。移除该 tag，并用 version script 只导出 `Firefly*`。

3. **空指针崩溃（route.NewNetworkManager）**
   sing-box 在存在 PlatformInterface 时必调用
   `CreateDefaultInterfaceMonitor()` 并注册回调；返回 nil 导致 `0x40` 空指针。
   已实现基于 `net.Interfaces()` 的接口监控。

4. **缺少注册表**
   `box.New` 报 `missing endpoint registry in context`；改为先调用
   `include.Context(ctx)` 注册全部协议实现。

5. **UI 进程加载 Go 崩溃**
   Go 运行时只在 VPN 扩展进程加载；UI 进程只用构建期常量展示内核状态。

6. **订阅分组始终为 0**
   `loadGroups()` 在打开的结果集内嵌套查询 links，导致分组读取失败；
   改为先关闭结果集再查询，并实测可读取 2 个分组。

7. **「+ 添加」按钮被状态栏遮挡**
   `setWindowLayoutFullScreen(true)` 未配合安全区，标题栏与按钮被状态栏覆盖；
   关闭全屏布局后按钮可点击。

8. **首页数量不刷新**
   `@Builder` 值参数不随 @State 更新；改为内联组件直接读取状态。

## 五、未验证项

| 项目 | 原因 |
| --- | --- |
| 系统 VPN 授权对话框 | 模拟器缺少 `com.huawei.hmos.vpndialog` |
| TUN fd 创建与接管 | 同上（未授权时 `create()` 返回 202） |
| 真实代理转发 / DNS / TLS | 需要授权后的真实链路 |
| arm64 真机运行 | 仅有 x86_64 模拟器；arm64 内核只完成编译 |
| 签名安装 | 真机需要 DevEco 自动签名或自有证书 |

因此当前交付为「客户端与内核已在模拟器验证、VPN 隧道待真机验证」的预览版。
