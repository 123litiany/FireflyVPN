/**
 * 订阅管理：分组、链接、更新与错误展示
 * 对应 Android: ui/screens/SubscriptionManagementScreen.kt
 */
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { FireflyColors, SubscriptionGroupSummary, SubscriptionLink } from '../model/Models';
import { SubscriptionRepository } from '../service/SubscriptionRepository';
import { Database } from '../data/Database';
import { RuntimeLog } from '../util/Utils';

const TAG: string = 'SubscriptionsPage';

@Entry
@Component
struct Subscriptions {
  @State groups: SubscriptionGroupSummary[] = [];
  @State showAdd: boolean = false;
  @State newName: string = '';
  @State newUrls: string = '';
  @State busy: boolean = false;
  @State busyText: string = '';
  @State expandedGroupId: string = '';

  aboutToAppear(): void {
    this.load();
  }

  onPageShow(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      this.groups = await Database.loadGroups();
    } catch (e) {
      RuntimeLog.error(TAG, `加载订阅失败: ${JSON.stringify(e)}`);
    }
  }

  private async addSubscription(): Promise<void> {
    if (this.busy) {
      return;
    }
    const urls: string[] = this.newUrls.split(/\r?\n/)
      .map((line: string) => line.trim())
      .filter((line: string) => line.length > 0);
    if (urls.length === 0) {
      promptAction.showToast({ message: '请填写订阅链接' });
      return;
    }
    this.busy = true;
    this.busyText = '正在拉取订阅…';
    try {
      await SubscriptionRepository.addGroup(this.newName, urls);
      this.showAdd = false;
      this.newName = '';
      this.newUrls = '';
      await this.load();
      promptAction.showToast({ message: '订阅已添加' });
    } catch (e) {
      RuntimeLog.error(TAG, `添加订阅失败: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: '添加失败，请检查链接与网络' });
    } finally {
      this.busy = false;
      this.busyText = '';
    }
  }

  private async refresh(groupId: string): Promise<void> {
    if (this.busy) {
      return;
    }
    this.busy = true;
    this.busyText = '正在更新订阅…';
    try {
      await SubscriptionRepository.refreshGroup(groupId);
      await this.load();
      promptAction.showToast({ message: '订阅已更新' });
    } catch (e) {
      RuntimeLog.error(TAG, `更新订阅失败: ${JSON.stringify(e)}`);
      promptAction.showToast({ message: '更新失败' });
    } finally {
      this.busy = false;
      this.busyText = '';
    }
  }

  private async remove(groupId: string): Promise<void> {
    try {
      await SubscriptionRepository.deleteGroup(groupId);
      await this.load();
      promptAction.showToast({ message: '已删除订阅分组' });
    } catch (e) {
      RuntimeLog.error(TAG, `删除订阅失败: ${JSON.stringify(e)}`);
    }
  }

  private formatTime(timestamp: number): string {
    if (timestamp === 0) {
      return '从未更新';
    }
    const date: Date = new Date(timestamp);
    const pad = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ` +
      `${pad(date.getHours())}:${pad(date.getMinutes())}`;
  }

  @Builder
  groupCard(summary: SubscriptionGroupSummary) {
    Column({ space: 8 }) {
      Row() {
        Column({ space: 3 }) {
          Text(summary.group.name)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(FireflyColors.TEXT_PRIMARY)
          Text(`更新于 ${this.formatTime(summary.group.lastUpdatedAt)} · ${summary.group.lastNodeCount} 个节点`)
            .fontSize(10)
            .fontColor(FireflyColors.TEXT_SECONDARY)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('刷新')
          .fontSize(12)
          .fontColor(FireflyColors.PRIMARY)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .onClick(() => {
            this.refresh(summary.group.id);
          })
        Text('删除')
          .fontSize(12)
          .fontColor(FireflyColors.DANGER)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .onClick(() => {
            this.remove(summary.group.id);
          })
      }
      .width('100%')

      ForEach(summary.links, (link: SubscriptionLink) => {
        Text(link.url)
          .fontSize(11)
          .fontColor(FireflyColors.TEXT_SECONDARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }, (link: SubscriptionLink) => link.id)

      if (summary.group.lastError.length > 0) {
        Text(summary.group.lastError)
          .fontSize(10)
          .fontColor(FireflyColors.WARNING)
          .maxLines(3)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(FireflyColors.SURFACE)
    .borderRadius(14)
  }

  build() {
    Stack() {
      Column() {
        Row() {
          Text('‹')
            .fontSize(28)
            .fontColor(FireflyColors.TEXT_PRIMARY)
            .width(36)
            .onClick(() => {
              router.back();
            })
          Text('订阅')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(FireflyColors.TEXT_PRIMARY)
            .layoutWeight(1)
          Text('+ 添加')
            .fontSize(13)
            .fontColor(FireflyColors.PRIMARY)
            .onClick(() => {
              this.showAdd = true;
            })
        }
        .width('100%')
        .padding({ left: 12, right: 16, top: 12, bottom: 8 })

        List({ space: 10 }) {
          ForEach(this.groups, (summary: SubscriptionGroupSummary) => {
            ListItem() {
              this.groupCard(summary)
            }
          }, (summary: SubscriptionGroupSummary) => summary.group.id)
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 16 })

        if (this.groups.length === 0) {
          Text('暂无订阅，点击右上角添加')
            .fontSize(13)
            .fontColor(FireflyColors.TEXT_SECONDARY)
            .margin({ bottom: 20 })
        }
      }
      .width('100%')
      .height('100%')

      if (this.busy) {
        Column({ space: 10 }) {
          LoadingProgress()
            .width(36)
            .height(36)
            .color(FireflyColors.PRIMARY)
          Text(this.busyText)
            .fontSize(12)
            .fontColor(FireflyColors.TEXT_PRIMARY)
        }
        .padding(20)
        .backgroundColor('#CC101820')
        .borderRadius(16)
      }

      if (this.showAdd) {
        Column() {
          Column({ space: 12 }) {
            Text('添加订阅')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(FireflyColors.TEXT_PRIMARY)
            TextInput({ placeholder: '分组名称（可选）', text: this.newName })
              .height(42)
              .backgroundColor(FireflyColors.SURFACE_LIGHT)
              .fontColor(FireflyColors.TEXT_PRIMARY)
              .onChange((value: string) => {
                this.newName = value;
              })
            TextArea({ placeholder: '订阅链接，每行一条（支持 Base64 订阅）', text: this.newUrls })
              .height(120)
              .backgroundColor(FireflyColors.SURFACE_LIGHT)
              .fontColor(FireflyColors.TEXT_PRIMARY)
              .onChange((value: string) => {
                this.newUrls = value;
              })
            Row({ space: 12 }) {
              Button('取消')
                .layoutWeight(1)
                .backgroundColor(FireflyColors.SURFACE_LIGHT)
                .fontColor(FireflyColors.TEXT_PRIMARY)
                .onClick(() => {
                  this.showAdd = false;
                })
              Button('拉取')
                .layoutWeight(1)
                .backgroundColor(FireflyColors.PRIMARY)
                .fontColor(FireflyColors.BACKGROUND)
                .onClick(() => {
                  this.addSubscription();
                })
            }
            .width('100%')
          }
          .width('88%')
          .padding(20)
          .backgroundColor('#1A2029')
          .borderRadius(18)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#99000000')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(FireflyColors.BACKGROUND)
  }
}
