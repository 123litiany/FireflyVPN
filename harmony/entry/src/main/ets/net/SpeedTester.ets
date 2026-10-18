/**
 * 测速（对应 Android 的 SpeedTestService，Cloudflare __down/__up）
 */
import { AppConfig } from '../common/AppConfig';
import { HttpClient } from './HttpClient';
import { nowMs, RuntimeLog } from '../util/Utils';
import { BandwidthTestStatus, Node } from '../model/Models';

const TAG: string = 'SpeedTester';

export class SpeedResult {
  mbps: number = 0;
  bytes: number = 0;
  seconds: number = 0;
  status: BandwidthTestStatus = BandwidthTestStatus.NOT_TESTED;
  message: string = '';
}

export class SpeedTester {
  /** 下载测速：请求指定字节数，按实际耗时换算 Mbps */
  static async download(sizeBytes: number): Promise<SpeedResult> {
    const result: SpeedResult = new SpeedResult();
    const url: string = `${AppConfig.SPEED_TEST_DOWNLOAD_URL}?bytes=${sizeBytes}`;
    const started: number = nowMs();
    try {
      const data: Uint8Array = await HttpClient.downloadBytes(url, AppConfig.SPEED_TEST_TIMEOUT_MS);
      const seconds: number = Math.max(0.001, (nowMs() - started) / 1000);
      result.bytes = data.byteLength;
      result.seconds = seconds;
      result.mbps = (data.byteLength * 8) / seconds / 1000000;
      result.status = BandwidthTestStatus.SUCCESS;
      RuntimeLog.info(TAG, `下载测速完成: ${result.mbps.toFixed(2)} Mbps (${data.byteLength} bytes / ${seconds.toFixed(2)}s)`);
    } catch (e) {
      result.status = BandwidthTestStatus.REQUEST_FAILED;
      result.message = JSON.stringify(e);
      RuntimeLog.error(TAG, `下载测速失败: ${result.message}`);
    }
    return result;
  }

  /** 对单个节点写入测速结果（用于列表展示） */
  static applyDownloadResult(node: Node, result: SpeedResult): void {
    node.downloadTestStatus = result.status;
    node.downloadMbps = result.mbps;
    node.downloadTestMessage = result.message;
  }
}
