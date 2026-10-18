/**
 * 节点列表：搜索、分组筛选、延迟测试与选择
 * 对应 Android: ui/components/NodeListDialog.kt + ui/screens/MainScreen 的节点选择
 */
import { router } from '@kit.ArkUI';
import {
  AppSettings,
  FireflyColors,
  LatencyLevel,
  Node,
  SubscriptionGroupSummary
} from '../model/Models';
import { Database } from '../data/Database';
import { SettingsStore } from '../data/SettingsStore';
import { LatencyTester } from '../net/LatencyTester';
import { nowMs, RuntimeLog } from '../util/Utils';
import { AppConfig } from '../common/AppConfig';

const TAG: string = 'NodesPage';

@Entry
@Component
struct Nodes {
  @State nodes: Node[] = [];
  @State groups: SubscriptionGroupSummary[] = [];
  @State groupId: string = '';
  @State keyword: string = '';
  @State testing: boolean = false;
  @State testProgress: string = '';
  @State currentNodeId: string = '';
  @State sortByLatency: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  onPageShow(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      this.groups = await Database.loadGroups();
      this.nodes = await Database.loadNodes();
      this.currentNodeId = SettingsStore.load().currentNodeId;
    } catch (e) {
      RuntimeLog.error(TAG, `加载节点失败: ${JSON.stringify(e)}`);
    }
  }

  private filteredNodes(): Node[] {
    let result: Node[] = this.nodes;
    if (this.groupId.length > 0) {
      result = result.filter((node: Node) => node.subscriptionGroupId === this.groupId);
    }
    const kw: string = this.keyword.trim().toLowerCase();
    if (kw.length > 0) {
      result = result.filter((node: Node) =>
        node.name.toLowerCase().indexOf(kw) >= 0 ||
        node.server.toLowerCase().indexOf(kw) >= 0 ||
        (node.type as string).indexOf(kw) >= 0);
    }
    if (this.sortByLatency) {
      result = result.slice();
      result.sort((a: Node, b: Node) => {
        const aScore: number = a.isAvailable && a.latency >= 0 ? a.latency : 999999;
        const bScore: number = b.isAvailable && b.latency >= 0 ? b.latency : 999999;
        return aScore - bScore;
      });
    }
    return result;
  }

  private latencyColor(node: Node): string {
    const level: LatencyLevel = node.getLatencyLevel();
    if (level === LatencyLevel.GOOD) {
      return FireflyColors.PRIMARY;
    }
    if (level === LatencyLevel.MEDIUM) {
      return FireflyColors.WARNING;
    }
    return FireflyColors.DANGER;
  }

  private selectNode(node: Node): void {
    const settings: AppSettings = SettingsStore.load();
    settings.currentNodeId = node.id;
    SettingsStore.save(settings);
    this.currentNodeId = node.id;
  }

  private async testAll(): Promise<void> {
    const list: Node[] = this.filteredNodes();
    if (list.length === 0 || this.testing) {
      return;
    }
    this.testing = true;
    this.testProgress = `0/${list.length}`;
    try {
      await LatencyTester.testNodes(list, (done: number, total: number) => {
        this.testProgress = `${done}/${total}`;
      });
      for (const node of list) {
        node.lastTestedAt = nowMs();
        await Database.updateNodeTestResult(node);
      }
      this.nodes = this.nodes.slice();
      RuntimeLog.info(TAG, `延迟测试完成: ${list.length} 个节点`);
    } catch (e) {
      RuntimeLog.error(TAG, `延迟测试失败: ${JSON.stringify(e)}`);
    } finally {
      this.testing = false;
      this.testProgress = '';
    }
  }

  @Builder
  groupChip(id: string, label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.groupId === id ? FireflyColors.BACKGROUND : FireflyColors.TEXT_SECONDARY)
      .backgroundColor(this.groupId === id ? FireflyColors.PRIMARY : FireflyColors.SURFACE)
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .borderRadius(14)
      .onClick(() => {
        this.groupId = id;
      })
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
        Text('节点')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(FireflyColors.TEXT_PRIMARY)
          .layoutWeight(1)
        Text(this.testing ? `测试中 ${this.testProgress}` : '测延迟')
          .fontSize(13)
          .fontColor(this.testing ? FireflyColors.TEXT_SECONDARY : FireflyColors.PRIMARY)
          .onClick(() => {
            this.testAll();
          })
        Text('排序')
          .fontSize(13)
          .fontColor(this.sortByLatency ? FireflyColors.PRIMARY : FireflyColors.TEXT_SECONDARY)
          .margin({ left: 14 })
          .onClick(() => {
            this.sortByLatency = !this.sortByLatency;
          })
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: 12, bottom: 8 })

      TextInput({ placeholder: '搜索节点名称 / 地址 / 协议', text: this.keyword })
        .height(40)
        .fontSize(14)
        .fontColor(FireflyColors.TEXT_PRIMARY)
        .backgroundColor(FireflyColors.SURFACE)
        .placeholderColor('#6B7684')
        .margin({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.keyword = value;
        })

      Scroll() {
        Row({ space: 8 }) {
          this.groupChip('', '全部')
          ForEach(this.groups, (summary: SubscriptionGroupSummary) => {
            this.groupChip(summary.group.id, summary.group.name)
          }, (summary: SubscriptionGroupSummary) => summary.group.id)
        }
        .padding({ left: 16, right: 16, top: 10, bottom: 6 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')

      List({ space: 8 }) {
        ForEach(this.filteredNodes(), (node: Node) => {
          ListItem() {
            Row({ space: 10 }) {
              Column({ space: 3 }) {
                Text(node.getDisplayName().length > 0 ? node.getDisplayName() : node.name)
                  .fontSize(15)
                  .fontColor(FireflyColors.TEXT_PRIMARY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${(node.type as string).toUpperCase()} · ${node.server}:${node.port}`)
                  .fontSize(10)
                  .fontColor(FireflyColors.TEXT_SECONDARY)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Column({ space: 2 }) {
                Text(node.getLatencyText())
                  .fontSize(12)
                  .fontColor(this.latencyColor(node))
                if (node.downloadMbps > 0) {
                  Text(`${node.downloadMbps.toFixed(1)} Mbps`)
                    .fontSize(9)
                    .fontColor(FireflyColors.TEXT_SECONDARY)
                }
              }
              .alignItems(HorizontalAlign.End)

              if (this.currentNodeId === node.id) {
                Text('✓')
                  .fontSize(16)
                  .fontColor(FireflyColors.PRIMARY)
              }
            }
            .width('100%')
            .padding(14)
            .backgroundColor(this.currentNodeId === node.id ? '#16302A' : FireflyColors.SURFACE)
            .borderRadius(14)
            .border({
              width: 1,
              color: this.currentNodeId === node.id ? FireflyColors.PRIMARY_DARK : '#00000000'
            })
            .onClick(() => {
              this.selectNode(node);
            })
          }
        }, (node: Node) => node.id)
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16, top: 6, bottom: 16 })
      .listDirection(Axis.Vertical)

      if (this.nodes.length === 0) {
        Text('暂无节点，请先添加订阅')
          .fontSize(13)
          .fontColor(FireflyColors.TEXT_SECONDARY)
          .margin({ bottom: 24 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(FireflyColors.BACKGROUND)
  }
}
