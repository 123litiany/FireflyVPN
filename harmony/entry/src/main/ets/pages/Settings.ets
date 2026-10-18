/**
 * 设置页：IPv6、TUN 栈、自动更新、分应用代理与关于
 * 对应 Android: ui/screens/OtherConfigScreen.kt + Dialogs 中的设置项
 */
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import {
  AppSettings,
  AppThemeMode,
  FireflyColors,
  IPv6RoutingMode,
  TunStackMode
} from '../model/Models';
import { SettingsStore } from '../data/SettingsStore';
import { CoreBridge } from '../service/CoreBridge';
import { AppConfig } from '../common/AppConfig';

@Entry
@Component
struct Settings {
  @State settings: AppSettings = new AppSettings();
  @State coreAvailable: boolean = false;

  aboutToAppear(): void {
    this.settings = SettingsStore.load();
    this.coreAvailable = CoreBridge.isAvailable();
  }

  private persist(): void {
    SettingsStore.save(this.settings);
    this.settings = SettingsStore.load();
  }

  @Builder
  sectionTitle(title: string) {
    Text(title)
      .fontSize(12)
      .fontColor(FireflyColors.TEXT_SECONDARY)
      .width('100%')
      .padding({ left: 4, top: 14, bottom: 6 })
  }

  @Builder
  choiceRow(label: string, value: string, selected: boolean, onSelect: () => void) {
    Row() {
      Text(label)
        .fontSize(14)
        .fontColor(FireflyColors.TEXT_PRIMARY)
        .layoutWeight(1)
      if (selected) {
        Text('✓')
          .fontSize(15)
          .fontColor(FireflyColors.PRIMARY)
      }
    }
    .width('100%')
    .padding(14)
    .backgroundColor(selected ? '#16302A' : FireflyColors.SURFACE)
    .borderRadius(12)
    .onClick(() => {
      onSelect();
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
        Text('设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(FireflyColors.TEXT_PRIMARY)
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 12, right: 16, top: 12, bottom: 4 })

      Scroll() {
        Column({ space: 8 }) {
          this.sectionTitle('代理内核')
          Row({ space: 8 }) {
            Column({ space: 3 }) {
              Text(this.coreAvailable ? 'sing-box 内核已集成' : '未集成 sing-box 内核')
                .fontSize(14)
                .fontColor(this.coreAvailable ? FireflyColors.PRIMARY : FireflyColors.WARNING)
              Text(this.coreAvailable
                ? '连接时将创建 TUN 并启动转发'
                : '预览版仅包含订阅管理与节点管理；连接前会明确提示内核缺失')
                .fontSize(10)
                .fontColor(FireflyColors.TEXT_SECONDARY)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Text(CoreBridge.version())
              .fontSize(10)
              .fontColor(FireflyColors.TEXT_SECONDARY)
          }
          .width('100%')
          .padding(14)
          .backgroundColor(FireflyColors.SURFACE)
          .borderRadius(12)

          this.sectionTitle('IPv6 路由')
          this.choiceRow('禁用 IPv6（默认）', '', this.settings.ipv6Mode === IPv6RoutingMode.DISABLED, () => {
            this.settings.ipv6Mode = IPv6RoutingMode.DISABLED;
            this.persist();
          })
          this.choiceRow('启用双栈', '', this.settings.ipv6Mode === IPv6RoutingMode.ENABLED, () => {
            this.settings.ipv6Mode = IPv6RoutingMode.ENABLED;
            this.persist();
          })
          this.choiceRow('优先 IPv6', '', this.settings.ipv6Mode === IPv6RoutingMode.PREFER, () => {
            this.settings.ipv6Mode = IPv6RoutingMode.PREFER;
            this.persist();
          })

          this.sectionTitle('TUN 栈')
          this.choiceRow('mixed（gVisor UDP + 系统 TCP）', '', this.settings.tunStackMode === TunStackMode.MIXED, () => {
            this.settings.tunStackMode = TunStackMode.MIXED;
            this.persist();
          })
          this.choiceRow('gvisor（完整用户态栈）', '', this.settings.tunStackMode === TunStackMode.GVISOR, () => {
            this.settings.tunStackMode = TunStackMode.GVISOR;
            this.persist();
          })
          this.choiceRow('system（依赖系统实现）', '', this.settings.tunStackMode === TunStackMode.SYSTEM, () => {
            this.settings.tunStackMode = TunStackMode.SYSTEM;
            this.persist();
          })

          this.sectionTitle('订阅')
          Row() {
            Column({ space: 2 }) {
              Text('启动时自动更新订阅')
                .fontSize(14)
                .fontColor(FireflyColors.TEXT_PRIMARY)
              Text('周期可在订阅页手动刷新')
                .fontSize(10)
                .fontColor(FireflyColors.TEXT_SECONDARY)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.subscriptionAutoUpdateEnabled })
              .selectedColor(FireflyColors.PRIMARY)
              .onChange((isOn: boolean) => {
                this.settings.subscriptionAutoUpdateEnabled = isOn;
                this.persist();
              })
          }
          .width('100%')
          .padding(14)
          .backgroundColor(FireflyColors.SURFACE)
          .borderRadius(12)

          this.sectionTitle('分应用代理')
          Row() {
            Column({ space: 2 }) {
              Text('启用分应用代理')
                .fontSize(14)
                .fontColor(FireflyColors.TEXT_PRIMARY)
              Text('鸿蒙以 trustedApplications 白名单实现；当前版本尚未提供应用选择器')
                .fontSize(10)
                .fontColor(FireflyColors.TEXT_SECONDARY)
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
            Toggle({ type: ToggleType.Switch, isOn: this.settings.perAppProxyEnabled })
              .selectedColor(FireflyColors.PRIMARY)
              .onChange((isOn: boolean) => {
                this.settings.perAppProxyEnabled = isOn;
                this.persist();
                if (isOn && this.settings.perAppProxyPackages.length === 0) {
                  promptAction.showToast({ message: '尚未选择应用，暂按全局代理运行' });
                }
              })
          }
          .width('100%')
          .padding(14)
          .backgroundColor(FireflyColors.SURFACE)
          .borderRadius(12)

          this.sectionTitle('其他')
          Row() {
            Text('运行时日志')
              .fontSize(14)
              .fontColor(FireflyColors.TEXT_PRIMARY)
              .layoutWeight(1)
            Text('查看 ›')
              .fontSize(12)
              .fontColor(FireflyColors.TEXT_SECONDARY)
          }
          .width('100%')
          .padding(14)
          .backgroundColor(FireflyColors.SURFACE)
          .borderRadius(12)
          .onClick(() => {
            router.pushUrl({ url: 'pages/Logs' });
          })

          Row() {
            Text('主题')
              .fontSize(14)
              .fontColor(FireflyColors.TEXT_PRIMARY)
              .layoutWeight(1)
            Text(this.settings.themeMode === AppThemeMode.DARK ? '深色'
              : (this.settings.themeMode === AppThemeMode.LIGHT ? '浅色' : '跟随系统'))
              .fontSize(12)
              .fontColor(FireflyColors.TEXT_SECONDARY)
          }
          .width('100%')
          .padding(14)
          .backgroundColor(FireflyColors.SURFACE)
          .borderRadius(12)
          .onClick(() => {
            if (this.settings.themeMode === AppThemeMode.SYSTEM) {
              this.settings.themeMode = AppThemeMode.DARK;
            } else if (this.settings.themeMode === AppThemeMode.DARK) {
              this.settings.themeMode = AppThemeMode.LIGHT;
            } else {
              this.settings.themeMode = AppThemeMode.SYSTEM;
            }
            this.persist();
            promptAction.showToast({ message: '主题偏好已保存（当前界面固定深色配色）' });
          })

          Text(`FireflyVPN ${AppConfig.APP_VERSION} · HarmonyOS 26.0.0 (API 26) · GPLv3`)
            .fontSize(10)
            .fontColor('#4A5563')
            .margin({ top: 18, bottom: 24 })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(FireflyColors.BACKGROUND)
  }
}
