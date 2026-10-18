/**
 * 工具箱：延迟测试、下载测速、出口 IP 查询、配置导出
 * 对应 Android: ui/dialogs/NetworkToolboxDialog.kt、SpeedTestDialog.kt、NodeIpInfoDialog.kt
 */
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import pasteboard from '@ohos.pasteboard';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConfig } from '../common/AppConfig';
import { FireflyColors, Node, NodeType } from '../model/Models';
import { Database } from '../data/Database';
import { SettingsStore } from '../data/SettingsStore';
import { LatencyTester } from '../net/LatencyTester';
import { SpeedTester, SpeedResult } from '../net/SpeedTester';
import { ConfigGenerator } from '../util/ConfigGenerator';
import { HttpClient } from '../net/HttpClient';
import { RuntimeLog } from '../util/Utils';

const TAG: string = 'ToolsPage';

interface IpInfo {
  ip?: string;
  country?: string;
  country_name?: string;
  region?: string;
  city?: string;
  isp?: string;
}

@Entry
@Component
struct Tools {
  @State busy: boolean = false;
  @State busyText: string = '';
  @State latencyResult: string = '';
  @State speedResult: string = '';
  @State ipResult: string = '';
  @State exportResult: string = '';

  private async runLatencyTest(): Promise<void> {
    if (this.busy) {
      return;
    }
    const nodes: Node[] = await Database.loadNodes();
    if (nodes.length === 0) {
      promptAction.showToast({ message: '请先添加订阅' });
      return;
    }
    this.busy = true;
    this.busyText = '正在测试节点延迟…';
    try {
      await LatencyTester.testNodes(nodes, (done: number, total: number) => {
        this.busyText = `延迟测试 ${done}/${total}`;
      });
      for (const node of nodes) {
        await Database.updateNodeTestResult(node);
      }
      let available: number = 0;
      let sum: number = 0;
      for (const node of nodes) {
        if (node.isAvailable && node.latency > 0) {
          available++;
          sum += node.latency;
        }
      }
      const avg: number = available > 0 ? Math.round(sum / available) : 0;
      this.latencyResult = `共 ${nodes.length} 个节点，${available} 个可达，平均 ${avg} ms`;
    } catch (e) {
      this.latencyResult = `测试失败: ${JSON.stringify(e)}`;
    } finally {
      this.busy = false;
      this.busyText = '';
    }
  }

  private async runSpeedTest(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.busyText = '正在下载测速…';
    try {
      const settings = SettingsStore.load();
      const result: SpeedResult = await SpeedTester.download(settings.speedTestSizeBytes);
      if (result.status === 0) {
        this.speedResult = `${result.mbps.toFixed(2)} Mbps · ${(result.bytes / 1024 / 1024).toFixed(1)} MB / ` +
          `${result.seconds.toFixed(2)} s（当前网络，非代理链路）`;
      } else {
        this.speedResult = `测速失败: ${result.message}`;
      }
    } catch (e) {
      this.speedResult = `测速失败: ${JSON.stringify(e)}`;
    } finally {
      this.busy = false;
      this.busyText = '';
    }
  }

  private async queryIp(): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.busyText = '正在查询出口 IP…';
    try {
      const body: string = await HttpClient.fetchText(AppConfig.NODE_IP_INFO_URL,
        AppConfig.USER_AGENT, AppConfig.NODE_IP_INFO_TIMEOUT_MS);
      const info: IpInfo = JSON.parse(body) as IpInfo;
      this.ipResult = `${info.ip !== undefined ? info.ip : '未知 IP'}\n` +
        `${info.country_name !== undefined ? info.country_name : ''} ` +
        `${info.region !== undefined ? info.region : ''} ${info.city !== undefined ? info.city : ''}\n` +
        `${info.isp !== undefined ? info.isp : ''}`;
    } catch (e) {
      this.ipResult = `查询失败: ${JSON.stringify(e)}`;
      RuntimeLog.error(TAG, `IP 查询失败: ${JSON.stringify(e)}`);
    } finally {
      this.busy = false;
      this.busyText = '';
    }
  }

  private async exportConfig(): Promise<void> {
    try {
      const settings = SettingsStore.load();
      const nodes: Node[] = await Database.loadNodes();
      let target: Node | null = null;
      for (const node of nodes) {
        if (node.id === settings.currentNodeId) {
          target = node;
          break;
        }
      }
      if (target === null && nodes.length > 0) {
        target = nodes[0];
      }
      if (target === null) {
        promptAction.showToast({ message: '没有可用节点' });
        return;
      }
      const json: string = ConfigGenerator.generate(target, settings);
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, json);
      await pasteboard.getSystemPasteboard().setData(data);
      this.exportResult = `已复制 ${target.getDisplayName()} 的 sing-box 配置（${json.length} 字符）`;
      promptAction.showToast({ message: 'sing-box 配置已复制到剪贴板' });
    } catch (e) {
      const error: BusinessError = e as BusinessError;
      this.exportResult = `导出失败: ${error.message}`;
      RuntimeLog.error(TAG, `导出配置失败: ${JSON.stringify(e)}`);
    }
  }

  @Builder
  toolCard(title: string, desc: string, actionLabel: string, action: () => void) {
    Row({ space: 10 }) {
      Column({ space: 3 }) {
        Text(title)
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(FireflyColors.TEXT_PRIMARY)
        Text(desc)
          .fontSize(10)
          .fontColor(FireflyColors.TEXT_SECONDARY)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(actionLabel)
        .fontSize(12)
        .fontColor(FireflyColors.PRIMARY)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor('#16302A')
        .borderRadius(10)
        .onClick(action)
    }
    .width('100%')
    .padding(14)
    .backgroundColor(FireflyColors.SURFACE)
    .borderRadius(14)
  }

  build() {
    Column() {
      Row() {
        Text('‹')
          .fontSize(28)
          .fontColor(FireflyColors.TEXT_PRIMARY)
          .width(36)
          .onClick(() => {
            router.back();
          })
        Text('工具箱')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(FireflyColors.TEXT_PRIMARY)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: 12, bottom: 8 })

      Scroll() {
        Column({ space: 10 }) {
          this.toolCard('节点延迟测试', '对所有节点执行 TCP 握手测速', '开始', () => {
            this.runLatencyTest();
          })
          if (this.latencyResult.length > 0) {
            Text(this.latencyResult)
              .fontSize(11)
              .fontColor(FireflyColors.PRIMARY)
              .width('100%')
              .padding({ left: 6 })
          }

          this.toolCard('下载测速', 'Cloudflare 测速节点，10 MB', '开始', () => {
            this.runSpeedTest();
          })
          if (this.speedResult.length > 0) {
            Text(this.speedResult)
              .fontSize(11)
              .fontColor(FireflyColors.PRIMARY)
              .width('100%')
              .padding({ left: 6 })
          }

          this.toolCard('出口 IP 查询', '查询当前网络的公网 IP 与归属', '查询', () => {
            this.queryIp();
          })
          if (this.ipResult.length > 0) {
            Text(this.ipResult)
              .fontSize(11)
              .fontColor(FireflyColors.TEXT_PRIMARY)
              .width('100%')
              .padding({ left: 6 })
          }

          this.toolCard('导出 sing-box 配置', '复制当前节点配置，便于排障与外部使用', '复制', () => {
            this.exportConfig();
          })
          if (this.exportResult.length > 0) {
            Text(this.exportResult)
              .fontSize(11)
              .fontColor(FireflyColors.TEXT_SECONDARY)
              .width('100%')
              .padding({ left: 6 })
          }

          Text('说明：延迟与测速均从本机发起。未接入代理内核时，测速结果反映当前网络而非节点链路。')
            .fontSize(10)
            .fontColor('#5A6572')
            .margin({ top: 12, bottom: 24 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 6 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      if (this.busy) {
        Row({ space: 10 }) {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(FireflyColors.PRIMARY)
          Text(this.busyText)
            .fontSize(12)
            .fontColor(FireflyColors.TEXT_PRIMARY)
        }
        .padding(12)
        .margin({ bottom: 16 })
        .backgroundColor(FireflyColors.SURFACE)
        .borderRadius(12)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(FireflyColors.BACKGROUND)
  }
}
