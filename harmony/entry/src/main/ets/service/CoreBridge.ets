/**
 * 代理内核桥接层
 *
 * Android 通过 libbox.aar（sing-box）提供转发能力；鸿蒙版通过 NAPI 模块
 * libfirefly.so 加载 libfireflycore.so（Go + sing-box）。
 *
 * 重要：Go 运行时只能在 **VPN 扩展进程** 中加载。主界面进程如果 dlopen
 * 该库，Go 的后台线程会与 ArkTS 运行时冲突并崩溃（已在模拟器复现）。
 * 因此 UI 只根据构建期常量展示状态，真正的加载发生在
 * FireflyVpnExtension 的 onCreate 中。
 */
import { start as nativeStart, stop as nativeStop, version as nativeVersion } from 'libfirefly.so';
import http from '@ohos.net.http';
import { AppConfig } from '../common/AppConfig';
import { RuntimeLog } from '../util/Utils';

const TAG: string = 'CoreBridge';

/** 构建期常量：当前 HAP 是否打包了 sing-box 原生内核 */
export const CORE_BUNDLED: boolean = true;
const CORE_VERSION_LABEL: string = 'fireflycore/0.1.0 (sing-box 1.13.9)';

export class TrafficStats {
  downloadBytesPerSecond: number = 0;
  uploadBytesPerSecond: number = 0;
  downloadTotalBytes: number = 0;
  uploadTotalBytes: number = 0;
}

interface ClashConnections {
  downloadTotal?: number;
  uploadTotal?: number;
}

export class CoreBridge {
  /** 仅用于 UI 展示，不加载原生库 */
  static isAvailable(): boolean {
    return CORE_BUNDLED;
  }

  static version(): string {
    return CORE_BUNDLED ? CORE_VERSION_LABEL : 'not-bundled';
  }

  /**
   * 启动内核（只能在 VPN 扩展进程中调用）。
   * @param configJson sing-box 配置
   * @param tunFd 系统分配的 TUN fd；自检时传 -1
   */
  static async start(configJson: string, tunFd: number): Promise<void> {
    RuntimeLog.info(TAG, `启动内核，配置 ${configJson.length} 字节，fd=${tunFd}`);
    let error: string = '';
    try {
      error = nativeStart(configJson, tunFd);
    } catch (e) {
      error = JSON.stringify(e);
    }
    if (error.length > 0) {
      RuntimeLog.error(TAG, `内核启动失败: ${error}`);
      throw new Error(`内核启动失败: ${error}`);
    }
    RuntimeLog.info(TAG, '内核已启动');
  }

  static async stop(): Promise<void> {
    try {
      const error: string = nativeStop();
      if (error.length > 0) {
        RuntimeLog.warn(TAG, `停止内核返回: ${error}`);
      }
    } catch (e) {
      RuntimeLog.warn(TAG, `停止内核异常: ${JSON.stringify(e)}`);
    }
  }

  /** 原生库自检：返回版本或加载错误（仅限 VPN 扩展/独立进程调用） */
  static nativeVersionProbe(): string {
    try {
      return nativeVersion();
    } catch (e) {
      return `unavailable (${JSON.stringify(e)})`;
    }
  }

  private static lastDownloadTotal: number = 0;
  private static lastUploadTotal: number = 0;
  private static lastSampleTime: number = 0;

  /**
   * 流量统计：读取 sing-box clash_api 的累计字节并换算速率。
   * 这是纯 HTTP 查询，不会在 UI 进程加载 Go 运行时。
   */
  static async queryTraffic(): Promise<TrafficStats | null> {
    const request: http.HttpRequest = http.createHttp();
    try {
      const response: http.HttpResponse = await request.request(
        `http://127.0.0.1:${AppConfig.CLASH_API_PORT}/connections`,
        {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.STRING,
          connectTimeout: 1500,
          readTimeout: 1500,
          usingCache: false
        });
      if (response.responseCode !== 200 || typeof response.result !== 'string') {
        return null;
      }
      const payload: ClashConnections = JSON.parse(response.result) as ClashConnections;
      const downloadTotal: number = payload.downloadTotal !== undefined ? payload.downloadTotal : 0;
      const uploadTotal: number = payload.uploadTotal !== undefined ? payload.uploadTotal : 0;
      const now: number = new Date().getTime();
      const stats: TrafficStats = new TrafficStats();
      stats.downloadTotalBytes = downloadTotal;
      stats.uploadTotalBytes = uploadTotal;
      if (CoreBridge.lastSampleTime > 0 && now > CoreBridge.lastSampleTime) {
        const seconds: number = (now - CoreBridge.lastSampleTime) / 1000;
        stats.downloadBytesPerSecond = Math.max(0, downloadTotal - CoreBridge.lastDownloadTotal) / seconds;
        stats.uploadBytesPerSecond = Math.max(0, uploadTotal - CoreBridge.lastUploadTotal) / seconds;
      }
      CoreBridge.lastDownloadTotal = downloadTotal;
      CoreBridge.lastUploadTotal = uploadTotal;
      CoreBridge.lastSampleTime = now;
      return stats;
    } catch (e) {
      return null;
    } finally {
      request.destroy();
    }
  }
}
