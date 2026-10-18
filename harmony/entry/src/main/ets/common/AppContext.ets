/**
 * 应用级上下文与事件总线
 */
import { common, Want } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';

export class AppContext {
  private static uiContext: common.UIAbilityContext | null = null;

  static set(context: common.UIAbilityContext): void {
    AppContext.uiContext = context;
  }

  static get(): common.UIAbilityContext {
    if (AppContext.uiContext === null) {
      throw new Error('AppContext 尚未初始化');
    }
    return AppContext.uiContext;
  }

  static bundleName(): string {
    if (AppContext.uiContext !== null) {
      return AppContext.uiContext.abilityInfo.bundleName;
    }
    return 'io.github.iskongkongyo.fireflyvpn';
  }

  static vpnWant(): Want {
    const want: Want = {
      bundleName: AppContext.bundleName(),
      abilityName: 'FireflyVpnExtension'
    };
    return want;
  }
}

/** VPN 状态事件（进程内） */
export class VpnEvents {
  static readonly STATE_CHANGED: string = 'firefly_vpn_state_changed';
  static readonly TRAFFIC_CHANGED: string = 'firefly_vpn_traffic_changed';

  static emitState(state: number, message: string): void {
    const options: emitter.EventData = { data: { 'state': state, 'message': message } };
    emitter.emit(VpnEvents.STATE_CHANGED, options);
  }

  static emitTraffic(rx: number, tx: number): void {
    const options: emitter.EventData = { data: { 'rx': rx, 'tx': tx } };
    emitter.emit(VpnEvents.TRAFFIC_CHANGED, options);
  }
}
