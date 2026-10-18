/**
 * 数据模型
 *
 * 移植自 Android:
 *   data/model/Node.kt、NodeType.kt、SubscriptionGroup.kt、SettingsRepository.kt
 */

/** 节点协议类型 */
export enum NodeType {
  VLESS = 'vless',
  VMESS = 'vmess',
  TROJAN = 'trojan',
  HYSTERIA2 = 'hysteria2',
  ANYTLS = 'anytls',
  TUIC = 'tuic',
  NAIVE = 'naive',
  WIREGUARD = 'wireguard',
  SHADOWSOCKS = 'ss',
  SOCKS = 'socks',
  HTTP = 'http',
  UNKNOWN = 'unknown'
}

export enum LatencyLevel {
  GOOD,
  MEDIUM,
  BAD
}

export enum NodeSource {
  SUBSCRIPTION,
  FAVORITE
}

export enum BandwidthTestStatus {
  NOT_TESTED,
  SUCCESS,
  SKIPPED,
  PROXY_START_FAILED,
  TIMEOUT,
  REQUEST_FAILED
}

/** sing-box TUN TCP/IP 栈 */
export enum TunStackMode {
  MIXED = 'mixed',
  GVISOR = 'gvisor',
  SYSTEM = 'system'
}

/** IPv6 路由模式 */
export enum IPv6RoutingMode {
  DISABLED,
  ENABLED,
  PREFER,
  ONLY
}

export enum AppThemeMode {
  SYSTEM,
  LIGHT,
  DARK
}

/** 分应用代理模式 */
export enum PerAppProxyMode {
  WHITELIST,
  BLACKLIST
}

/** 代理节点 */
export class Node {
  id: string = '';
  name: string = '';
  type: NodeType = NodeType.UNKNOWN;
  server: string = '';
  port: number = 443;
  rawLink: string = '';
  country: string = '';
  countryName: string = '';
  latency: number = -1;
  isAvailable: boolean = true;
  lastTestedAt: number = 0;
  sortOrder: number = 0;
  downloadMbps: number = 0;
  uploadMbps: number = 0;
  downloadTestStatus: BandwidthTestStatus = BandwidthTestStatus.NOT_TESTED;
  uploadTestStatus: BandwidthTestStatus = BandwidthTestStatus.NOT_TESTED;
  downloadTestMessage: string = '';
  uploadTestMessage: string = '';
  unlockSummary: string = '';
  unlockPassed: boolean = false;
  autoTestStatus: string = '';
  autoTestedAt: number = 0;
  source: NodeSource = NodeSource.SUBSCRIPTION;
  subscriptionGroupId: string = '';
  favoriteSourceNodeId: string = '';
  favoriteCreatedAt: number = 0;

  /** 获取国旗 emoji：优先从名称中的区域指示符提取，其次由国家码生成 */
  getFlagEmojiOrNull(): string | null {
    let i: number = 0;
    while (i < this.name.length) {
      const c: number = this.name.charCodeAt(i);
      if (c >= 0xD83C && c <= 0xD83C && i + 3 < this.name.length) {
        const low: number = this.name.charCodeAt(i + 1);
        if (low >= 0xDDE6 && low <= 0xDDFF) {
          return this.name.substring(i, i + 4);
        }
      }
      i++;
    }
    if (this.country.length !== 2) {
      return null;
    }
    const upper: string = this.country.toUpperCase();
    const first: number = 0x1F1E6 + (upper.charCodeAt(0) - 0x41);
    const second: number = 0x1F1E6 + (upper.charCodeAt(1) - 0x41);
    return String.fromCodePoint(first) + String.fromCodePoint(second);
  }

  /** 去掉国旗 emoji 后的显示名 */
  getDisplayName(): string {
    let result: string = '';
    let i: number = 0;
    while (i < this.name.length) {
      const c: number = this.name.charCodeAt(i);
      if (c >= 0xD83C && c <= 0xD83C && i + 3 < this.name.length) {
        const low: number = this.name.charCodeAt(i + 1);
        if (low >= 0xDDE6 && low <= 0xDDFF) {
          i += 4;
          continue;
        }
      }
      result += this.name.charAt(i);
      i++;
    }
    return result.trim();
  }

  getLatencyText(): string {
    if (this.latency === -1) {
      return '未测试';
    }
    if (this.latency === -2) {
      return '超时';
    }
    if (!this.isAvailable && this.autoTestStatus.toUpperCase().indexOf('FILTERED') >= 0) {
      return '不达标';
    }
    if (!this.isAvailable) {
      return '不可用';
    }
    return `${this.latency}ms`;
  }

  getLatencyLevel(): LatencyLevel {
    if (this.latency < 0 || !this.isAvailable) {
      return LatencyLevel.BAD;
    }
    if (this.latency < 100) {
      return LatencyLevel.GOOD;
    }
    if (this.latency < 300) {
      return LatencyLevel.MEDIUM;
    }
    return LatencyLevel.BAD;
  }

  copy(): Node {
    const n: Node = new Node();
    n.id = this.id;
    n.name = this.name;
    n.type = this.type;
    n.server = this.server;
    n.port = this.port;
    n.rawLink = this.rawLink;
    n.country = this.country;
    n.countryName = this.countryName;
    n.latency = this.latency;
    n.isAvailable = this.isAvailable;
    n.lastTestedAt = this.lastTestedAt;
    n.sortOrder = this.sortOrder;
    n.downloadMbps = this.downloadMbps;
    n.uploadMbps = this.uploadMbps;
    n.downloadTestStatus = this.downloadTestStatus;
    n.uploadTestStatus = this.uploadTestStatus;
    n.downloadTestMessage = this.downloadTestMessage;
    n.uploadTestMessage = this.uploadTestMessage;
    n.unlockSummary = this.unlockSummary;
    n.unlockPassed = this.unlockPassed;
    n.autoTestStatus = this.autoTestStatus;
    n.autoTestedAt = this.autoTestedAt;
    n.source = this.source;
    n.subscriptionGroupId = this.subscriptionGroupId;
    n.favoriteSourceNodeId = this.favoriteSourceNodeId;
    n.favoriteCreatedAt = this.favoriteCreatedAt;
    return n;
  }
}

export const DEFAULT_SUBSCRIPTION_GROUP_ID: string = 'subscription_default';
export const FAVORITES_NODE_GROUP_ID: string = 'favorites';

/** 订阅分组 */
export class SubscriptionGroup {
  id: string = '';
  name: string = '';
  autoUpdateEnabled: boolean = false;
  updateIntervalMinutes: number = 0;
  deduplicateEnabled: boolean = true;
  userAgent: string = '';
  lastUpdatedAt: number = 0;
  lastError: string = '';
  lastNodeCount: number = 0;
  sortOrder: number = 0;
  createdAt: number = 0;
}

/** 订阅链接（一个分组可含多条链接） */
export class SubscriptionLink {
  id: string = '';
  groupId: string = '';
  url: string = '';
  sortOrder: number = 0;
}

export class SubscriptionGroupSummary {
  group: SubscriptionGroup = new SubscriptionGroup();
  links: SubscriptionLink[] = [];
}

export class NodeGroup {
  id: string = '';
  name: string = '';
  sortOrder: number = 0;
  isFavorites: boolean = false;
  isBuiltIn: boolean = false;
  nodeCount: number = 0;
}

/** 订阅自动更新策略 */
export class SubscriptionAutoUpdatePolicy {
  static readonly STARTUP_ONCE_INTERVAL_MINUTES: number = 0;
  static readonly MIN_PERIODIC_INTERVAL_MINUTES: number = 1;
  static readonly MAX_PERIODIC_INTERVAL_MINUTES: number = 7 * 24 * 60;

  static normalizeInterval(minutes: number): number {
    if (minutes <= 0) {
      return 0;
    }
    if (minutes < 1) {
      return 1;
    }
    return Math.min(minutes, SubscriptionAutoUpdatePolicy.MAX_PERIODIC_INTERVAL_MINUTES);
  }

  static isStartupOnce(intervalMinutes: number): boolean {
    return SubscriptionAutoUpdatePolicy.normalizeInterval(intervalMinutes) === 0;
  }

  static isPeriodicDue(intervalMinutes: number, lastUpdatedAt: number, now: number): boolean {
    const normalized: number = SubscriptionAutoUpdatePolicy.normalizeInterval(intervalMinutes);
    if (normalized === 0) {
      return false;
    }
    return now - lastUpdatedAt >= normalized * 60000;
  }
}

/** 应用设置 */
export class AppSettings {
  themeMode: AppThemeMode = AppThemeMode.SYSTEM;
  ipv6Mode: IPv6RoutingMode = IPv6RoutingMode.DISABLED;
  tunStackMode: TunStackMode = TunStackMode.MIXED;
  perAppProxyEnabled: boolean = false;
  perAppProxyMode: PerAppProxyMode = PerAppProxyMode.BLACKLIST;
  perAppProxyPackages: string[] = [];
  subscriptionAutoUpdateEnabled: boolean = true;
  subscriptionUpdateIntervalMinutes: number = 0;
  currentGroupId: string = DEFAULT_SUBSCRIPTION_GROUP_ID;
  currentNodeId: string = '';
  allowLan: boolean = false;
  showTrafficNotification: boolean = true;
  autoReconnect: boolean = true;
  speedTestSizeBytes: number = 10000000;
}

/** 应用主题色（对齐 Android 的深色青绿主色） */
export class FireflyColors {
  static readonly PRIMARY: string = '#00E5A0';
  static readonly PRIMARY_DARK: string = '#00B37E';
  static readonly BACKGROUND: string = '#0B0F14';
  static readonly SURFACE: string = '#151B23';
  static readonly SURFACE_LIGHT: string = '#1E2733';
  static readonly TEXT_PRIMARY: string = '#F2F5F8';
  static readonly TEXT_SECONDARY: string = '#8B98A8';
  static readonly DANGER: string = '#FF5C5C';
  static readonly WARNING: string = '#FFB020';
}
