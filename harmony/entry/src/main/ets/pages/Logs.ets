/**
 * 运行时日志
 * 对应 Android: ui/screens/RuntimeLogScreen.kt + util/RuntimeLog.kt
 */
import { router } from '@kit.ArkUI';
import { FireflyColors } from '../model/Models';
import { LogEntry, LogLevel, RuntimeLog } from '../util/Utils';

@Entry
@Component
struct Logs {
  @State entries: LogEntry[] = [];
  @State autoScroll: boolean = true;
  private listener: () => void = (): void => {
    this.entries = RuntimeLog.getEntries().slice();
  };

  aboutToAppear(): void {
    this.entries = RuntimeLog.getEntries().slice();
    RuntimeLog.subscribe(this.listener);
  }

  aboutToDisappear(): void {
    RuntimeLog.unsubscribe(this.listener);
  }

  private levelColor(level: LogLevel): string {
    if (level === LogLevel.ERROR) {
      return FireflyColors.DANGER;
    }
    if (level === LogLevel.WARN) {
      return FireflyColors.WARNING;
    }
    if (level === LogLevel.DEBUG) {
      return '#6B7684';
    }
    return FireflyColors.PRIMARY;
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
        Text('运行日志')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(FireflyColors.TEXT_PRIMARY)
          .layoutWeight(1)
        Text('清空')
          .fontSize(13)
          .fontColor(FireflyColors.DANGER)
          .onClick(() => {
            RuntimeLog.clear();
            this.entries = [];
          })
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: 12, bottom: 8 })

      List({ space: 2 }) {
        ForEach(this.entries, (entry: LogEntry) => {
          ListItem() {
            Row({ space: 6 }) {
              Text(entry.time)
                .fontSize(9)
                .fontColor('#5A6572')
                .width(52)
              Text(entry.level as string)
                .fontSize(9)
                .fontColor(this.levelColor(entry.level))
                .width(10)
              Text(`[${entry.tag}]`)
                .fontSize(9)
                .fontColor('#7A8797')
              Text(entry.message)
                .fontSize(10)
                .fontColor(FireflyColors.TEXT_PRIMARY)
                .layoutWeight(1)
            }
            .width('100%')
            .padding({ left: 12, right: 12, top: 2, bottom: 2 })
          }
        }, (entry: LogEntry) => `${entry.time}_${entry.tag}_${entry.message}`)
      }
      .layoutWeight(1)
      .width('100%')

      if (this.entries.length === 0) {
        Text('暂无日志')
          .fontSize(12)
          .fontColor(FireflyColors.TEXT_SECONDARY)
          .margin({ bottom: 20 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(FireflyColors.BACKGROUND)
  }
}
