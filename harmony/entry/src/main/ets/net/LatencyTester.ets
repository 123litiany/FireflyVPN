/**
 * 延迟测试（TCPing）
 *
 * Android 版通过 libbox 的 URL Test / TCPing 完成；鸿蒙版在未接入内核时
 * 使用系统 TCP 连接测得的握手时延，语义与 TCPing 一致。
 */
import { socket } from '@kit.NetworkKit';
import { Node } from '../model/Models';
import { AppConfig } from '../common/AppConfig';
import { nowMs, RuntimeLog } from '../util/Utils';

const TAG: string = 'LatencyTester';

export class LatencyTester {
  static async tcpPing(host: string, port: number, timeoutMs: number): Promise<number> {
    const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
    const started: number = nowMs();
    try {
      const address: socket.NetAddress = { address: host, port: port };
      const options: socket.TCPConnectOptions = { address: address, timeout: timeoutMs };
      await tcp.connect(options);
      return Math.max(1, nowMs() - started);
    } finally {
      try {
        await tcp.close();
      } catch (e) {
        // 已关闭或连接失败时无需再次报错
      }
    }
  }

  /** 并发测试节点延迟，原地更新 latency/isAvailable，并回调进度 */
  static async testNodes(nodes: Node[], onProgress?: (done: number, total: number) => void): Promise<void> {
    const total: number = nodes.length;
    let done: number = 0;
    const concurrency: number = Math.max(1, AppConfig.TCPING_CONCURRENCY);
    for (let start = 0; start < total; start += concurrency) {
      const batch: Node[] = nodes.slice(start, start + concurrency);
      await Promise.all(batch.map(async (node: Node) => {
        try {
          const latency: number = await LatencyTester.tcpPing(node.server, node.port, AppConfig.TCPING_TEST_TIMEOUT_MS);
          node.latency = latency;
          node.isAvailable = true;
          node.autoTestStatus = 'TCPING_OK';
        } catch (e) {
          node.latency = -2;
          node.isAvailable = false;
          node.autoTestStatus = 'TIMEOUT';
        }
        node.lastTestedAt = nowMs();
        node.autoTestedAt = node.lastTestedAt;
        done++;
        if (onProgress !== undefined) {
          onProgress(done, total);
        }
      }));
    }
    RuntimeLog.info(TAG, `延迟测试完成，共 ${total} 个节点`);
  }
}
