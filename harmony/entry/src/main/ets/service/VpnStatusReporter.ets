/**
 * VPN 状态上报：写入偏好 + 发布公共事件（跨进程）
 */
import commonEventManager from '@ohos.commonEventManager';
import { BusinessError } from '@kit.BasicServicesKit';
import { SettingsStore } from '../data/SettingsStore';
import { RuntimeLog } from '../util/Utils';

const TAG: string = 'VpnStatus';
export const VPN_STATE_EVENT: string = 'io.github.iskongkongyo.fireflyvpn.VPN_STATE';
export const KEY_LAST_STATE: string = 'vpn_last_state';
export const KEY_LAST_MESSAGE: string = 'vpn_last_message';

export class VpnStatusReporter {
  static report(state: string, message: string): void {
    SettingsStore.writeString(KEY_LAST_STATE, state);
    SettingsStore.writeString(KEY_LAST_MESSAGE, message);
    RuntimeLog.info(TAG, `状态: ${state} ${message}`);
    const data: commonEventManager.CommonEventPublishData = {
      parameters: {
        'state': state,
        'message': message
      }
    };
    commonEventManager.publish(VPN_STATE_EVENT, data, (err: BusinessError) => {
      if (err && err.code !== 0) {
        RuntimeLog.warn(TAG, `公共事件发布失败: ${err.code} ${err.message}`);
      }
    });
  }

  static readLastState(): string {
    return SettingsStore.readStringKey(KEY_LAST_STATE, 'DISCONNECTED');
  }

  static readLastMessage(): string {
    return SettingsStore.readStringKey(KEY_LAST_MESSAGE, '');
  }
}
