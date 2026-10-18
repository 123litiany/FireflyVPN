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
    this.bootstrap();
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
