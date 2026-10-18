/**
 * FireflyVPN 的 VpnExtensionAbility
 *
 * 与 Android VpnService 的对应关系：
 *   VpnService.Builder#addAddress/addRoute/setMtu/setSession  ->  vpnExtension.VpnConfig
 *   establish() 返回的 tun fd                                  ->  VpnConnection.create() 返回的 fd
 *   libbox.aar 启动的内核                                       ->  CoreBridge（NAPI 原生库）
 *
 * 注意：只有内核可用时才创建 TUN，避免出现“已连接但全部流量黑洞”的假成功。
 */
import VpnExtensionAbility from '@ohos.app.ability.VpnExtensionAbility';
import vpnExtension from '@ohos.net.vpnExtension';
import { Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import { AppConfig } from '../common/AppConfig';
import { Database } from '../data/Database';
import { SettingsStore } from '../data/SettingsStore';
import { ConfigGenerator } from '../util/ConfigGenerator';
import { CoreBridge } from '../service/CoreBridge';
import { VpnStatusReporter } from '../service/VpnStatusReporter';
import { Node, AppSettings, IPv6RoutingMode } from '../model/Models';
import { RuntimeLog } from '../util/Utils';

const TAG: string = 'VpnExtension';

export default class FireflyVpnExtension extends VpnExtensionAbility {
  private connection: vpnExtension.VpnConnection | null = null;
  private tunFd: number = -1;
  private started: boolean = false;

  onCreate(want: Want): void {
    RuntimeLog.info(TAG, 'VPN 扩展 onCreate');
    const params = want.parameters;
    let selfTest: string = '';
    if (params !== undefined) {
      const flag = params['selfTest'];
      if (typeof flag === 'string') {
        selfTest = flag as string;
      }
    }
    if (selfTest === 'true') {
      this.runSelfTest();
      return;
    }
    this.bootstrap();
  }

  /**
   * 独立进程内核自检：不创建 TUN，用本地 mixed 入站验证 Go 运行时、
   * sing-box 配置解析与 clash_api。结果写入偏好并发布事件。
   */
  private async runSelfTest(): Promise<void> {
    SettingsStore.init(this.context);
    const config: string = '{"log":{"level":"warn","timestamp":true},' +
      '"inbounds":[{"type":"mixed","tag":"self-test-in","listen":"127.0.0.1","listen_port":18080}],' +
      '"outbounds":[{"type":"direct","tag":"direct"}],' +
      '"experimental":{"clash_api":{"external_controller":"127.0.0.1:19091"}}}';
    let result: string = '';
    try {
      const probe: string = CoreBridge.nativeVersionProbe();
      RuntimeLog.info(TAG, `原生库版本: ${probe}`);
      if (probe.startsWith('unavailable')) {
        result = `内核不可用: ${probe}`;
      } else {
        await CoreBridge.start(config, -1);
        await new Promise<void>((resolve: () => void) => {
          setTimeout(() => resolve(), 800);
        });
        const request: http.HttpRequest = http.createHttp();
        try {
          const response: http.HttpResponse = await request.request(
            'http://127.0.0.1:19091/version',
            {
              method: http.RequestMethod.GET,
              expectDataType: http.HttpDataType.STRING,
              connectTimeout: 2000,
              readTimeout: 2000,
              usingCache: false
            });
          result = `自检通过: ${probe}; clash_api HTTP ${response.responseCode}: ${response.result}`;
        } finally {
          request.destroy();
        }
        await CoreBridge.stop();
      }
    } catch (e) {
      result = `自检失败: ${JSON.stringify(e)}`;
    }
    RuntimeLog.info(TAG, result);
    SettingsStore.writeString('core_self_test_result', result);
    VpnStatusReporter.report('SELFTEST', result);
    await this.stopSelf();
  }

  private async bootstrap(): Promise<void> {
    SettingsStore.init(this.context);
    try {
      await Database.init(this.context);
    } catch (e) {
      RuntimeLog.error(TAG, `数据库打开失败: ${JSON.stringify(e)}`);
      VpnStatusReporter.report('ERROR', '数据库打开失败');
      await this.stopSelf();
      return;
    }

    if (!CoreBridge.isAvailable()) {
      RuntimeLog.error(TAG, '原生代理内核未集成，拒绝建立 TUN');
      VpnStatusReporter.report('ERROR', '代理内核未集成：当前构建不包含 sing-box 原生库');
      await this.stopSelf();
      return;
    }

    const settings: AppSettings = SettingsStore.load();
    const node: Node | null = await this.loadCurrentNode(settings.currentNodeId);
    if (node === null) {
      VpnStatusReporter.report('ERROR', '未选择节点');
      await this.stopSelf();
      return;
    }

    let configJson: string = '';
    try {
      configJson = ConfigGenerator.generate(node, settings);
    } catch (e) {
      RuntimeLog.error(TAG, `配置生成失败: ${JSON.stringify(e)}`);
      VpnStatusReporter.report('ERROR', '配置生成失败');
      await this.stopSelf();
      return;
    }

    try {
      this.connection = vpnExtension.createVpnConnection(this.context);
      const config: vpnExtension.VpnConfig = this.buildVpnConfig(settings);
      const fd: number = await this.connection.create(config);
      this.tunFd = fd;
      RuntimeLog.info(TAG, `TUN 已建立，fd=${fd}`);
      // 让扩展进程的 socket 走物理网络，避免 sing-box 出站流量再次进入 TUN 形成回环
      try {
        await this.connection.protectProcessNet();
        RuntimeLog.info(TAG, '扩展进程已加入 VPN 保护');
      } catch (e) {
        RuntimeLog.warn(TAG, `protectProcessNet 失败: ${JSON.stringify(e)}`);
      }
      await CoreBridge.start(configJson, fd);
      this.started = true;
      VpnStatusReporter.report('CONNECTED', node.name);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      RuntimeLog.error(TAG, `启动失败: ${error.code} ${error.message}`);
      VpnStatusReporter.report('ERROR', `启动失败: ${error.code} ${error.message}`);
      await this.teardown();
    }
  }

  private buildVpnConfig(settings: AppSettings): vpnExtension.VpnConfig {
    const addresses: vpnExtension.LinkAddress[] = [];
    const ipv4: vpnExtension.LinkAddress = {
      address: { address: AppConfig.VPN_IPV4_ADDRESS, family: 1 },
      prefixLength: 30
    };
    addresses.push(ipv4);
    const ipv6Enabled: boolean = settings.ipv6Mode === IPv6RoutingMode.ENABLED ||
      settings.ipv6Mode === IPv6RoutingMode.PREFER ||
      settings.ipv6Mode === IPv6RoutingMode.ONLY;
    if (ipv6Enabled) {
      const ipv6: vpnExtension.LinkAddress = {
        address: { address: AppConfig.VPN_IPV6_ADDRESS, family: 2 },
        prefixLength: 126
      };
      addresses.push(ipv6);
    }
    const routes: vpnExtension.RouteInfo[] = [];
    const route4: vpnExtension.RouteInfo = {
      interface: 'tun0',
      destination: { address: { address: '0.0.0.0', family: 1 }, prefixLength: 0 },
      gateway: { address: AppConfig.VPN_IPV4_ADDRESS, family: 1 },
      hasGateway: false,
      isDefaultRoute: true
    };
    routes.push(route4);
    if (ipv6Enabled) {
      const route6: vpnExtension.RouteInfo = {
        interface: 'tun0',
        destination: { address: { address: '::', family: 2 }, prefixLength: 0 },
        gateway: { address: AppConfig.VPN_IPV6_ADDRESS, family: 2 },
        hasGateway: false,
        isDefaultRoute: true
      };
      routes.push(route6);
    }

    const config: vpnExtension.VpnConfig = {
      addresses: addresses,
      routes: routes,
      dnsAddresses: [AppConfig.VPN_DNS_PRIMARY, AppConfig.VPN_DNS_SECONDARY],
      mtu: AppConfig.VPN_MTU,
      isIPv4Accepted: true,
      isIPv6Accepted: ipv6Enabled
    };
    if (settings.perAppProxyEnabled && settings.perAppProxyPackages.length > 0) {
      config.trustedApplications = settings.perAppProxyPackages;
    }
    return config;
  }

  private async loadCurrentNode(nodeId: string): Promise<Node | null> {
    const nodes: Node[] = await Database.loadNodes();
    if (nodes.length === 0) {
      return null;
    }
    if (nodeId.length === 0) {
      return nodes[0];
    }
    for (const node of nodes) {
      if (node.id === nodeId) {
        return node;
      }
    }
    return nodes[0];
  }

  private async teardown(): Promise<void> {
    try {
      await CoreBridge.stop();
    } catch (e) {
      RuntimeLog.warn(TAG, '停止内核失败');
    }
    if (this.connection !== null) {
      try {
        await this.connection.destroy();
      } catch (e) {
        RuntimeLog.warn(TAG, '销毁 VPN 失败');
      }
      this.connection = null;
    }
    this.tunFd = -1;
    this.started = false;
  }

  private async stopSelf(): Promise<void> {
    await this.teardown();
    try {
      await vpnExtension.stopVpnExtensionAbility({
        bundleName: this.context.extensionAbilityInfo.bundleName,
        abilityName: 'FireflyVpnExtension'
      } as Want);
    } catch (e) {
      RuntimeLog.warn(TAG, '停止 VPN 扩展失败');
    }
  }

  onDestroy(): void {
    RuntimeLog.info(TAG, 'VPN 扩展 onDestroy');
    this.teardown();
    VpnStatusReporter.report('DISCONNECTED', '已断开');
  }
}
