/**
 * 主界面：连接控制、当前节点、流量与快捷入口
 * 对应 Android: ui/screens/MainScreen.kt
 */
import { router } from '@kit.ArkUI';
import commonEventManager from '@ohos.commonEventManager';
import { BusinessError } from '@kit.BasicServicesKit';
import { emitter } from '@kit.BasicServicesKit';
import { AppConfig } from '../common/AppConfig';
import { AppSettings, FireflyColors, Node, NodeType, SubscriptionGroupSummary } from '../model/Models';
import { Database } from '../data/Database';
import { SettingsStore } from '../data/SettingsStore';
import { VpnManager, VpnState } from '../service/VpnManager';
import { CoreBridge, TrafficStats } from '../service/CoreBridge';
import { VpnEvents } from '../common/AppContext';
import { VpnStatusReporter, VPN_STATE_EVENT } from '../service/VpnStatusReporter';
import { formatSpeed, RuntimeLog } from '../util/Utils';

const TAG: string = 'IndexPage';

@Entry
@Component
struct Index {
  @State vpnState: number = VpnState.DISCONNECTED as number;
  @State statusText: string = '未连接';
  @State detailText: string = '';
  @State nodes: Node[] = [];
  @State currentNode: Node | null = null;
  @State groupCount: number = 0;
  @State nodeCount: number = 0;
  @State downloadSpeed: number = 0;
  @State uploadSpeed: number = 0;
  @State coreAvailable: boolean = false;
  @State errorDialogVisible: boolean = false;
  private stateSubscriber: commonEventManager.CommonEventSubscriber | null = null;
  private timerId: number = -1;

  aboutToAppear(): void {
    this.coreAvailable = CoreBridge.isAvailable();
    this.refreshData();
    this.subscribeState();
    this.timerId = setInterval(() => {
      this.pollTraffic();
      this.refreshData();
    }, 3000);
  }

  aboutToDisappear(): void {
    if (this.timerId >= 0) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
    this.unsubscribeState();
  }

  onPageShow(): void {
    this.refreshData();
  }

  private async refreshData(): Promise<void> {
    try {
      const settings: AppSettings = SettingsStore.load();
      const groups: SubscriptionGroupSummary[] = await Database.loadGroups();
      this.groupCount = groups.length;
      const allNodes: Node[] = await Database.loadNodes();
      this.nodes = allNodes;
      this.nodeCount = allNodes.length;
      let selected: Node | null = null;
      if (settings.currentNodeId.length > 0) {
        for (const node of allNodes) {
          if (node.id === settings.currentNodeId) {
            selected = node;
            break;
          }
        }
      }
      if (selected === null && allNodes.length > 0) {
        selected = allNodes[0];
        settings.currentNodeId = selected.id;
        SettingsStore.save(settings);
      }
      this.currentNode = selected;
    } catch (e) {
      RuntimeLog.error(TAG, `刷新数据失败: ${JSON.stringify(e)}`);
    }
  }

  private subscribeState(): void {
    try {
      const info: commonEventManager.CommonEventSubscribeInfo = { events: [VPN_STATE_EVENT] };
      commonEventManager.createSubscriber(info).then((subscriber: commonEventManager.CommonEventSubscriber) => {
        this.stateSubscriber = subscriber;
        commonEventManager.subscribe(subscriber, (err: BusinessError, data: commonEventManager.CommonEventData) => {
          if (err) {
            return;
          }
          const params = data.parameters;
          if (params === undefined) {
            return;
          }
          const state: string = params['state'] as string;
          const message: string = params['message'] as string;
          this.applyState(state, message);
        });
      });
      emitter.on(VpnEvents.STATE_CHANGED, (event: emitter.EventData) => {
        const payload = event.data;
        if (payload === undefined) {
          return;
        }
        const state: number = payload['state'] as number;
        const message: string = payload['message'] as string;
        this.applyVpnState(state, message);
      });
    } catch (e) {
      RuntimeLog.warn(TAG, '状态订阅失败');
    }
  }

  private unsubscribeState(): void {
    if (this.stateSubscriber !== null) {
      commonEventManager.unsubscribe(this.stateSubscriber);
      this.stateSubscriber = null;
    }
    emitter.off(VpnEvents.STATE_CHANGED);
  }

  private applyState(state: string, message: string): void {
    if (state === 'CONNECTED') {
      this.applyVpnState(VpnState.CONNECTED as number, message);
    } else if (state === 'DISCONNECTED') {
      this.applyVpnState(VpnState.DISCONNECTED as number, '未连接');
    } else if (state === 'ERROR') {
      this.applyVpnState(VpnState.ERROR as number, message);
    }
  }

  private applyVpnState(state: number, message: string): void {
    this.vpnState = state;
    if (state === VpnState.CONNECTED as number) {
      this.statusText = '已连接';
      this.detailText = message;
    } else if (state === VpnState.CONNECTING as number) {
      this.statusText = '连接中…';
      this.detailText = message;
    } else if (state === VpnState.DISCONNECTING as number) {
      this.statusText = '断开中…';
      this.detailText = message;
    } else if (state === VpnState.ERROR as number) {
      this.statusText = '连接失败';
      this.detailText = message;
      this.errorDialogVisible = true;
    } else {
      this.statusText = '未连接';
      this.detailText = '';
    }
  }

  private async pollTraffic(): Promise<void> {
    const stats: TrafficStats | null = await CoreBridge.queryTraffic();
    if (stats !== null) {
      this.downloadSpeed = stats.downloadBytesPerSecond;
      this.uploadSpeed = stats.uploadBytesPerSecond;
    }
  }

  private async toggleConnection(): Promise<void> {
    if (this.nodes.length === 0) {
      this.statusText = '请先添加订阅';
      router.pushUrl({ url: 'pages/Subscriptions' });
      return;
    }
    if (this.vpnState === VpnState.CONNECTED as number ||
      this.vpnState === VpnState.CONNECTING as number) {
      await VpnManager.disconnect();
      this.applyVpnState(VpnState.DISCONNECTED as number, '');
      return;
    }
    if (!CoreBridge.isAvailable()) {
      this.statusText = '代理内核未集成';
      this.detailText = '当前构建不包含 sing-box 原生库，无法建立转发隧道';
      this.errorDialogVisible = true;
      return;
    }
    try {
      await VpnManager.connect();
      this.applyVpnState(VpnState.CONNECTING as number, '等待系统授权…');
    } catch (e) {
      this.applyVpnState(VpnState.ERROR as number, JSON.stringify(e));
    }
  }

  private nodeTitle(): string {
    if (this.currentNode === null) {
      return '未选择节点';
    }
    const display: string = SettingsStore.load().currentNodeId.length > 0
      ? this.currentNode.getDisplayName() : this.currentNode.getDisplayName();
    return display.length > 0 ? display : '未命名节点';
  }

  private protocolLabel(): string {
    if (this.currentNode === null) {
      return '';
    }
    const type: NodeType = this.currentNode.type;
    return `${type as string}`.toUpperCase();
  }

  @Builder
  quickAction(title: string, subtitle: string, page: string, accent: string) {
    Column({ space: 4 }) {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(FireflyColors.TEXT_PRIMARY)
      Text(subtitle)
        .fontSize(11)
        .fontColor(FireflyColors.TEXT_SECONDARY)
    }
    .layoutWeight(1)
    .height(72)
    .justifyContent(FlexAlign.Center)
    .backgroundColor(FireflyColors.SURFACE)
    .borderRadius(14)
    .onClick(() => {
      router.pushUrl({ url: page });
    })
    .border({ width: 1, color: accent })
  }

  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 160,
          colors: [[FireflyColors.BACKGROUND, 0.0], ['#0E2620', 0.55], [FireflyColors.BACKGROUND, 1.0]]
        })

      Column({ space: 0 }) {
        // 顶部栏
        Row() {
          Column({ space: 2 }) {
            Text('FireflyVPN')
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(FireflyColors.TEXT_PRIMARY)
            Text(this.coreAvailable ? 'sing-box 内核已集成' : '预览版 · 未集成代理内核')
              .fontSize(11)
              .fontColor(this.coreAvailable ? FireflyColors.PRIMARY : FireflyColors.WARNING)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text('日志')
            .fontSize(13)
            .fontColor(FireflyColors.TEXT_SECONDARY)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(() => {
              router.pushUrl({ url: 'pages/Logs' });
            })
          Text('设置')
            .fontSize(13)
            .fontColor(FireflyColors.TEXT_SECONDARY)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .onClick(() => {
              router.pushUrl({ url: 'pages/Settings' });
            })
        }
        .width('100%')
        .padding({ left: 20, right: 12, top: 12 })

        // 连接区
        Column({ space: 10 }) {
          Stack() {
            Circle()
              .width(230)
              .height(230)
              .fillOpacity(0.06)
              .fill(FireflyColors.PRIMARY)
            Circle()
              .width(196)
              .height(196)
              .fillOpacity(0.12)
              .fill(FireflyColors.PRIMARY)
            Column({ space: 6 }) {
              Text(this.statusText)
                .fontSize(26)
                .fontWeight(FontWeight.Bold)
                .fontColor(FireflyColors.TEXT_PRIMARY)
              if (this.detailText.length > 0) {
                Text(this.detailText)
                  .fontSize(11)
                  .fontColor(FireflyColors.TEXT_SECONDARY)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .padding({ left: 24, right: 24 })
              }
              Text('点击连接 / 断开')
                .fontSize(10)
                .fontColor(FireflyColors.TEXT_SECONDARY)
            }
          }
          .width(240)
          .height(240)
          .onClick(() => {
            this.toggleConnection();
          })
        }
        .margin({ top: 18 })

        // 当前节点
        Row({ space: 12 }) {
          Column({ space: 4 }) {
            Text('当前节点')
              .fontSize(11)
              .fontColor(FireflyColors.TEXT_SECONDARY)
            Text(this.nodeTitle())
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(FireflyColors.TEXT_PRIMARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Column({ space: 4 }) {
            Text(this.protocolLabel())
              .fontSize(11)
              .fontColor(FireflyColors.PRIMARY)
            Text(this.currentNode !== null ? `${this.currentNode.server}:${this.currentNode.port}` : '—')
              .fontSize(10)
              .fontColor(FireflyColors.TEXT_SECONDARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.End)
        }
        .width('92%')
        .padding(16)
        .backgroundColor(FireflyColors.SURFACE)
        .borderRadius(16)
        .margin({ top: 8 })
        .onClick(() => {
          router.pushUrl({ url: 'pages/Nodes' });
        })

        // 流量
        Row() {
          Column({ space: 3 }) {
            Text('↓ ' + formatSpeed(this.downloadSpeed))
              .fontSize(13)
              .fontColor(FireflyColors.PRIMARY)
            Text('下载')
              .fontSize(10)
              .fontColor(FireflyColors.TEXT_SECONDARY)
          }
          .layoutWeight(1)
          Column({ space: 3 }) {
            Text('↑ ' + formatSpeed(this.uploadSpeed))
              .fontSize(13)
              .fontColor('#4FC3F7')
            Text('上传')
              .fontSize(10)
              .fontColor(FireflyColors.TEXT_SECONDARY)
          }
          .layoutWeight(1)
          Column({ space: 3 }) {
            Text(`${this.nodeCount}`)
              .fontSize(13)
              .fontColor(FireflyColors.TEXT_PRIMARY)
            Text('节点')
              .fontSize(10)
              .fontColor(FireflyColors.TEXT_SECONDARY)
          }
          .layoutWeight(1)
        }
        .width('92%')
        .padding({ top: 5, bottom: 5 })

        // 快捷入口
        Row({ space: 10 }) {
          this.quickAction('节点', `${this.nodeCount} 个可用`, 'pages/Nodes', FireflyColors.SURFACE_LIGHT)
          this.quickAction('订阅', `${this.groupCount} 个分组`, 'pages/Subscriptions', FireflyColors.SURFACE_LIGHT)
          this.quickAction('工具箱', '测速 / 延迟', 'pages/Tools', FireflyColors.SURFACE_LIGHT)
        }
        .width('92%')
        .margin({ top: 4 })

        Blank()

        Text('FireflyVPN for HarmonyOS · GPLv3')
          .fontSize(10)
          .fontColor('#4A5563')
          .margin({ bottom: 14 })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(FireflyColors.BACKGROUND)
  }
}
