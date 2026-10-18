/**
 * FireflyVPN HarmonyOS - 全局配置常量
 *
 * 移植自 Android: xyz.a202132.app.AppConfig
 * 说明：上游公开仓库中的 Firefly 后端域名为占位符，未配置后端时本应用作为
 * 通用 sing-box 订阅客户端工作，仅依赖用户自填订阅地址。
 */
export class AppConfig {
  static readonly APP_VERSION: string = '0.1.0';
  static readonly USER_AGENT: string = 'FireflyVPN/0.1.0 (HarmonyOS)';

  // 订阅与节点请求
  static readonly NODE_REQUEST_TIMEOUT_MS: number = 25000;
  static readonly MAX_SUBSCRIPTION_BYTES: number = 8 * 1024 * 1024;

  // 延迟测试
  static readonly TCPING_TEST_TIMEOUT_MS: number = 3000;
  static readonly TCPING_CONCURRENCY: number = 12;
  static readonly URL_TEST_URL: string = 'https://www.google.com/generate_204';
  static readonly URL_TEST_TIMEOUT_MS: number = 3000;

  // VPN
  static readonly VPN_MTU: number = 9000;
  static readonly VPN_DNS_PRIMARY: string = '8.8.8.8';
  static readonly VPN_DNS_SECONDARY: string = '8.8.4.4';
  static readonly VPN_DNS_CHINA: string = '223.5.5.5';
  static readonly VPN_IPV4_ADDRESS: string = '172.19.0.1';
  static readonly VPN_IPV6_ADDRESS: string = 'fdfe:dcba:9876::1';
  static readonly CLASH_API_PORT: number = 19090;

  // 测速
  static readonly SPEED_TEST_DOWNLOAD_URL: string = 'https://speed.cloudflare.com/__down';
  static readonly SPEED_TEST_UPLOAD_URL: string = 'https://speed.cloudflare.com/__up';
  static readonly SPEED_TEST_TIMEOUT_MS: number = 25000;

  // 节点 IP 信息
  static readonly NODE_IP_INFO_URL: string = 'https://my.ippure.com/v1/info';
  static readonly NODE_IP_INFO_TIMEOUT_MS: number = 12000;

  // 订阅自动更新
  static readonly STARTUP_STABILITY_DELAY_MS: number = 10000;
  static readonly PERIODIC_CHECK_INTERVAL_MS: number = 60000;

  // 存储
  static readonly DB_NAME: string = 'firefly.db';
  static readonly PREF_STORE: string = 'firefly_settings';

  // 运行时日志上限
  static readonly LOG_BUFFER_SIZE: number = 2000;
}
