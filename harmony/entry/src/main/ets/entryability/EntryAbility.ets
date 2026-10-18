import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppContext } from '../common/AppContext';
import { SettingsStore } from '../data/SettingsStore';
import { Database } from '../data/Database';
import { AppContextBundleNameHolder } from '../util/ConfigGenerator';
import { SubscriptionRepository } from '../service/SubscriptionRepository';
import { RuntimeLog } from '../util/Utils';

const TAG: string = 'EntryAbility';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    RuntimeLog.info(TAG, 'EntryAbility onCreate');
    AppContext.set(this.context);
    SettingsStore.init(this.context);
    AppContextBundleNameHolder.setBundleName(this.context.abilityInfo.bundleName);
    this.prepareStorage();
  }

  private async prepareStorage(): Promise<void> {
    try {
      await Database.init(this.context);
      await SubscriptionRepository.ensureDefaultGroup();
      RuntimeLog.info(TAG, '本地存储准备完成');
      setTimeout(() => {
        SubscriptionRepository.autoUpdateIfDue().then(() => {
          RuntimeLog.info(TAG, '启动自动更新检查完成');
        });
      }, 10000);
    } catch (e) {
      RuntimeLog.error(TAG, `本地存储初始化失败: ${JSON.stringify(e)}`);
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        RuntimeLog.error(TAG, `页面加载失败: ${err.code} ${err.message}`);
        return;
      }
      try {
        const mainWindow: window.Window = windowStage.getMainWindowSync();
        mainWindow.setWindowLayoutFullScreen(true);
      } catch (e) {
        RuntimeLog.warn(TAG, '系统栏配置失败');
      }
    });
  }

  onWindowStageDestroy(): void {
    RuntimeLog.info(TAG, 'onWindowStageDestroy');
  }

  onDestroy(): void {
    RuntimeLog.info(TAG, 'EntryAbility onDestroy');
  }
}
