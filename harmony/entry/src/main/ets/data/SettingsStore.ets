/**
 * 设置存储（DataStore → preferences）
 */
import preferences from '@ohos.data.preferences';
import { common } from '@kit.AbilityKit';
import { AppConfig } from '../common/AppConfig';
import {
  AppSettings,
  AppThemeMode,
  DEFAULT_SUBSCRIPTION_GROUP_ID,
  IPv6RoutingMode,
  PerAppProxyMode,
  TunStackMode
} from '../model/Models';
import { RuntimeLog } from '../util/Utils';

const TAG: string = 'SettingsStore';

const KEY_THEME: string = 'themeMode';
const KEY_IPV6: string = 'ipv6Mode';
const KEY_TUN_STACK: string = 'tunStackModeName';
const KEY_PER_APP_ENABLED: string = 'perAppProxyEnabled';
const KEY_PER_APP_MODE: string = 'perAppProxyMode';
const KEY_PER_APP_PACKAGES: string = 'perAppProxyPackages';
const KEY_AUTO_UPDATE: string = 'subscriptionAutoUpdateEnabled';
const KEY_UPDATE_INTERVAL: string = 'subscriptionUpdateIntervalMinutes';
const KEY_CURRENT_GROUP: string = 'currentGroupId';
const KEY_CURRENT_NODE: string = 'currentNodeId';
const KEY_ALLOW_LAN: string = 'allowLan';
const KEY_TRAFFIC_NOTIFICATION: string = 'showTrafficNotification';
const KEY_AUTO_RECONNECT: string = 'autoReconnect';
const KEY_SPEED_SIZE: string = 'speedTestSizeBytes';

export class SettingsStore {
  private static prefs: preferences.Preferences | null = null;

  static init(context: common.Context): void {
    if (SettingsStore.prefs !== null) {
      return;
    }
    const options: preferences.Options = { name: AppConfig.PREF_STORE };
    SettingsStore.prefs = preferences.getPreferencesSync(context, options);
  }

  private static readNumber(key: string, defaultValue: number): number {
    if (SettingsStore.prefs === null) {
      return defaultValue;
    }
    const value: preferences.ValueType = SettingsStore.prefs.getSync(key, defaultValue);
    return typeof value === 'number' ? value : defaultValue;
  }

  private static readBoolean(key: string, defaultValue: boolean): boolean {
    if (SettingsStore.prefs === null) {
      return defaultValue;
    }
    const value: preferences.ValueType = SettingsStore.prefs.getSync(key, defaultValue);
    return typeof value === 'boolean' ? value : defaultValue;
  }

  private static readString(key: string, defaultValue: string): string {
    if (SettingsStore.prefs === null) {
      return defaultValue;
    }
    const value: preferences.ValueType = SettingsStore.prefs.getSync(key, defaultValue);
    return typeof value === 'string' ? value : defaultValue;
  }

  private static parseTunStack(value: string): TunStackMode {
    if (value === TunStackMode.GVISOR as string) {
      return TunStackMode.GVISOR;
    }
    if (value === TunStackMode.SYSTEM as string) {
      return TunStackMode.SYSTEM;
    }
    return TunStackMode.MIXED;
  }

  static load(): AppSettings {    const settings: AppSettings = new AppSettings();
    settings.themeMode = SettingsStore.readNumber(KEY_THEME, AppThemeMode.SYSTEM as number) as AppThemeMode;
    settings.ipv6Mode = SettingsStore.readNumber(KEY_IPV6, IPv6RoutingMode.DISABLED as number) as IPv6RoutingMode;
    settings.tunStackMode = SettingsStore.parseTunStack(SettingsStore.readString(KEY_TUN_STACK, 'mixed'));
    settings.perAppProxyEnabled = SettingsStore.readBoolean(KEY_PER_APP_ENABLED, false);
    settings.perAppProxyMode = SettingsStore.readNumber(KEY_PER_APP_MODE,
      PerAppProxyMode.BLACKLIST as number) as PerAppProxyMode;
    const packagesJson: string = SettingsStore.readString(KEY_PER_APP_PACKAGES, '[]');
    try {
      settings.perAppProxyPackages = JSON.parse(packagesJson) as string[];
    } catch (e) {
      settings.perAppProxyPackages = [];
    }
    settings.subscriptionAutoUpdateEnabled = SettingsStore.readBoolean(KEY_AUTO_UPDATE, true);
    settings.subscriptionUpdateIntervalMinutes = SettingsStore.readNumber(KEY_UPDATE_INTERVAL, 0);
    settings.currentGroupId = SettingsStore.readString(KEY_CURRENT_GROUP, DEFAULT_SUBSCRIPTION_GROUP_ID);
    settings.currentNodeId = SettingsStore.readString(KEY_CURRENT_NODE, '');
    settings.allowLan = SettingsStore.readBoolean(KEY_ALLOW_LAN, false);
    settings.showTrafficNotification = SettingsStore.readBoolean(KEY_TRAFFIC_NOTIFICATION, true);
    settings.autoReconnect = SettingsStore.readBoolean(KEY_AUTO_RECONNECT, true);
    settings.speedTestSizeBytes = SettingsStore.readNumber(KEY_SPEED_SIZE, 10000000);
    return settings;
  }

  static save(settings: AppSettings): void {
    const prefs: preferences.Preferences | null = SettingsStore.prefs;
    if (prefs === null) {
      RuntimeLog.warn(TAG, '偏好存储未初始化，设置未保存');
      return;
    }
    prefs.putSync(KEY_THEME, settings.themeMode as number);
    prefs.putSync(KEY_IPV6, settings.ipv6Mode as number);
    prefs.putSync(KEY_TUN_STACK, settings.tunStackMode as string);
    prefs.putSync(KEY_PER_APP_ENABLED, settings.perAppProxyEnabled);
    prefs.putSync(KEY_PER_APP_MODE, settings.perAppProxyMode as number);
    prefs.putSync(KEY_PER_APP_PACKAGES, JSON.stringify(settings.perAppProxyPackages));
    prefs.putSync(KEY_AUTO_UPDATE, settings.subscriptionAutoUpdateEnabled);
    prefs.putSync(KEY_UPDATE_INTERVAL, settings.subscriptionUpdateIntervalMinutes);
    prefs.putSync(KEY_CURRENT_GROUP, settings.currentGroupId);
    prefs.putSync(KEY_CURRENT_NODE, settings.currentNodeId);
    prefs.putSync(KEY_ALLOW_LAN, settings.allowLan);
    prefs.putSync(KEY_TRAFFIC_NOTIFICATION, settings.showTrafficNotification);
    prefs.putSync(KEY_AUTO_RECONNECT, settings.autoReconnect);
    prefs.putSync(KEY_SPEED_SIZE, settings.speedTestSizeBytes);
    prefs.flush();
  }

  /** 读取当前选中的节点 ID（供 VPN 扩展进程读取） */
  static readCurrentNodeId(): string {
    return SettingsStore.readString(KEY_CURRENT_NODE, '');
  }

  static writeCurrentNodeId(nodeId: string): void {
    const prefs: preferences.Preferences | null = SettingsStore.prefs;
    if (prefs === null) {
      return;
    }
    prefs.putSync(KEY_CURRENT_NODE, nodeId);
    prefs.flush();
  }

  static writeString(key: string, value: string): void {
    const prefs: preferences.Preferences | null = SettingsStore.prefs;
    if (prefs === null) {
      return;
    }
    prefs.putSync(key, value);
    prefs.flush();
  }

  static readStringKey(key: string, defaultValue: string): string {
    return SettingsStore.readString(key, defaultValue);
  }
}
