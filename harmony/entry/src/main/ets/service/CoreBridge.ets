/**
 * 代理内核桥接层
 *
 * Android 通过 libbox.aar（sing-box）提供转发能力；鸿蒙版通过 NAPI 模块
 * libfirefly.so 加载 libfireflycore.so（Go + sing-box）。
 * 内核缺失或 ABI 不匹配时 isAvailable() 返回 false，扩展不会建立 TUN。
 */
import { start as nativeStart, stop as nativeStop, version as nativeVersion } from 'libfirefly.so';
import http from '@ohos.net.http';
import { AppConfig } from '../common/AppConfig';
import { RuntimeLog } from '../util/Utils';

const TAG: string = 'CoreBridge';

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
  private static cachedVersion: string = '';

  /** 原生内核是否可用（dlopen 成功且符号齐全） */
  static isAvailable(): boolean {
    return !CoreBridge.version().startsWith('unavailable');
  }

  static version(): string {
    if (CoreBridge.cachedVersion.length > 0) {
      return CoreBridge.cachedVersion;
    }
    let value: string = 'unavailable';
    try {
      value = nativeVersion();
    } catch (e) {
      value = `unavailable (${JSON.stringify(e)})`;
    }
    CoreBridge.cachedVersion = value;
    return value;
  }

  /**
   * 启动内核。
   * @param configJson sing-box 配置（tun 入站的 fd 由原生层接管）
   * @param tunFd 系统分配的 TUN 文件描述符
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

  private static lastDownloadTotal: number = 0;
  private static lastUploadTotal: number = 0;
  private static lastSampleTime: number = 0;

  /**
   * 流量统计：读取 sing-box clash_api 的累计字节并换算速率。
   * 内核未运行时返回 null，UI 保持 0 而不是伪造数据。
   */
  static async queryTraffic(): Promise<TrafficStats | null> {
    if (!CoreBridge.isAvailable()) {
      return null;
    }
    const request: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 1500,
        readTimeout: 1500,
        usingCache: false
      };
      const response: http.HttpResponse = await request.request(
        `http://127.0.0.1:${AppConfig.CLASH_API_PORT}/connections`, options);
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
