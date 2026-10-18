/**
 * VPN 控制层：启动/停止系统 VPN 扩展
 *
 * Android 使用 VpnService；鸿蒙使用 VpnExtensionAbility + @ohos.net.vpnExtension。
 * 启动前必须由系统弹出用户授权。
 */
import vpnExtension from '@ohos.net.vpnExtension';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppContext } from '../common/AppContext';
import { VpnEvents } from '../common/AppContext';
import { RuntimeLog } from '../util/Utils';

const TAG: string = 'VpnManager';

export enum VpnState {
  DISCONNECTED = 0,
  CONNECTING = 1,
  CONNECTED = 2,
  DISCONNECTING = 3,
  ERROR = 4
}

export class VpnManager {
  private static state: VpnState = VpnState.DISCONNECTED;
  private static message: string = '';
  private static observer: vpnExtension.VpnObserver | null = null;
  private static observerReady: boolean = false;
  private static connectTimer: number = -1;

  private static clearConnectTimer(): void {
    if (VpnManager.connectTimer >= 0) {
      clearTimeout(VpnManager.connectTimer);
      VpnManager.connectTimer = -1;
    }
  }

  /** 注册系统 VPN 授权结果回调（API 26+） */
  private static ensureObserver(): void {
    if (VpnManager.observerReady) {
      return;
    }
    VpnManager.observerReady = true;
    try {
      VpnManager.observer = vpnExtension.createVpnObserver();
      VpnManager.observer.onAuthorizationResult((granted: boolean) => {
        if (!granted) {
          VpnManager.setState(VpnState.ERROR, '用户拒绝了 VPN 授权');
          RuntimeLog.warn(TAG, '用户拒绝了 VPN 授权');
        } else {
          RuntimeLog.info(TAG, '用户已授权 VPN');
        }
      });
    } catch (e) {
      RuntimeLog.warn(TAG, `授权结果监听不可用: ${JSON.stringify(e)}`);
      VpnManager.observer = null;
    }
  }

  static getState(): VpnState {
    return VpnManager.state;
  }

  static getMessage(): string {
    return VpnManager.message;
  }

  static setState(state: VpnState, message: string): void {
    VpnManager.state = state;
    VpnManager.message = message;
    if (state !== VpnState.CONNECTING) {
      VpnManager.clearConnectTimer();
    }
    VpnEvents.emitState(state, message);
  }

  /** 请求系统启动 VPN 扩展（会弹出授权对话框） */
  static async connect(): Promise<void> {
    if (VpnManager.state === VpnState.CONNECTING || VpnManager.state === VpnState.CONNECTED) {
      return;
    }
    VpnManager.setState(VpnState.CONNECTING, '正在请求 VPN 授权…');
    VpnManager.ensureObserver();
    try {
      await vpnExtension.startVpnExtensionAbility(AppContext.vpnWant());
      RuntimeLog.info(TAG, 'VPN 扩展启动请求已提交');
      VpnManager.clearConnectTimer();
      VpnManager.connectTimer = setTimeout(() => {
        if (VpnManager.state === VpnState.CONNECTING) {
          VpnManager.setState(VpnState.ERROR,
            '未收到系统 VPN 授权。模拟器缺少 VPN 授权组件（com.huawei.hmos.vpndialog），请在真机确认授权弹窗');
          RuntimeLog.error(TAG, '等待 VPN 授权超时');
        }
      }, 15000);
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      VpnManager.setState(VpnState.ERROR, `启动 VPN 扩展失败: ${error.code} ${error.message}`);
      RuntimeLog.error(TAG, `启动 VPN 扩展失败: ${error.code} ${error.message}`);
      throw new Error(`启动 VPN 扩展失败: ${error.code} ${error.message}`);
    }
  }

  /** 断开：停止 VPN 扩展 */
  static async disconnect(): Promise<void> {
    VpnManager.setState(VpnState.DISCONNECTING, '正在断开…');
    try {
      await vpnExtension.stopVpnExtensionAbility(AppContext.vpnWant());
      VpnManager.setState(VpnState.DISCONNECTED, '已断开');
    } catch (err) {
      const error: BusinessError = err as BusinessError;
      RuntimeLog.error(TAG, `停止 VPN 扩展失败: ${error.code} ${error.message}`);
      // 扩展可能已被系统回收，此时仍视为断开，但保留错误提示
      VpnManager.setState(VpnState.DISCONNECTED, `已断开（${error.code}）`);
    }
  }
}
