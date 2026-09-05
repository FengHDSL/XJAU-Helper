/**
 * 防窥保护管理器
 *
 * 基于 HarmonyOS DeviceSecurityKit 的 dlpAntiPeep 模块，
 * 监听系统防窥状态变化，在检测到非机主窥屏时回调通知页面隐藏敏感内容。
 *
 * 权限说明：
 *  ohos.permission.DLP_GET_HIDE_STATUS 为受限权限，需在签名 profile 的 ACL 中配置。
 *  当前未声明该权限，API 调用失败时静默降级（不启用防窥但不影响页面正常使用）。
 *  如需启用，请在 AppGallery Connect 控制台为应用申请该权限的 ACL 授权。
 *
 * 使用前提：
 *  1. 签名 profile 已配置 ohos.permission.DLP_GET_HIDE_STATUS 的 ACL 授权
 *  2. 用户在「设置 > 隐私与安全 > 防窥保护」中为本应用开启开关
 *  3. 设备已开启人脸识别
 *
 * 典型用法：
 *   private peepMgr: AntiPeepManager = new AntiPeepManager();
 *   aboutToAppear() { this.peepMgr.start((hidden) => { this.isPeeped = hidden; }); }
 *   aboutToDisappear() { this.peepMgr.stop(); }
 */
import { dlpAntiPeep } from '@kit.DeviceSecurityKit';
import { common } from '@kit.AbilityKit';
import { LogStore } from './LogStore';

/** 防窥状态回调：true=检测到窥屏需隐藏，false=安全可显示 */
type PeepCallback = (hidden: boolean) => void;

export class AntiPeepManager {
  /** 当前是否处于窥屏状态 */
  private isHidden: boolean = false;
  /** 防窥开关是否已开启 */
  private switchOn: boolean = false;
  /** 状态变化回调 */
  private callback: PeepCallback | null = null;
  /** 是否已启动监听 */
  private listening: boolean = false;

  /**
   * 启动防窥监听
   *
   * @param cb 状态变化回调（true=需隐藏敏感内容，false=可正常显示）
   */
  async start(cb: PeepCallback): Promise<void> {
    this.callback = cb;
    try {
      // 检查防窥开关是否已开启
      this.switchOn = await dlpAntiPeep.isDlpAntiPeepSwitchOn();
      LogStore.log('防窥', '开关状态', this.switchOn ? '已开启' : '未开启', '');

      if (!this.switchOn) {
        // 开关未开启，不监听，页面正常显示
        this.notify(false);
        return;
      }

      // 获取当前初始状态
      const status: dlpAntiPeep.DlpAntiPeepStatus = dlpAntiPeep.getDlpAntiPeepInfo();
      this.isHidden = status === dlpAntiPeep.DlpAntiPeepStatus.HIDE;
      this.notify(this.isHidden);

      // 注册状态变化监听
      this.listening = true;
      dlpAntiPeep.on('dlpAntiPeep', (info: dlpAntiPeep.DlpAntiPeepStatus) => {
        const newHidden: boolean = info === dlpAntiPeep.DlpAntiPeepStatus.HIDE;
        if (newHidden !== this.isHidden) {
          this.isHidden = newHidden;
          this.notify(this.isHidden);
        }
      });
    } catch (e) {
      LogStore.log('防窥', '启动异常', '失败', `${e}`);
      // 异常时不阻断页面正常使用
      this.notify(false);
    }
  }

  /** 停止监听，清理资源 */
  stop(): void {
    if (this.listening) {
      try {
        dlpAntiPeep.off('dlpAntiPeep');
      } catch (e) {
        // 忽略清理异常
      }
      this.listening = false;
    }
    this.callback = null;
    this.isHidden = false;
  }

  /** 获取当前窥屏状态 */
  get isPeeped(): boolean {
    return this.isHidden;
  }

  /** 获取防窥开关是否已开启 */
  get isEnabled(): boolean {
    return this.switchOn;
  }

  /**
   * 拉起系统防窥保护设置页，引导用户开启
   *
   * @param context UIAbilityContext
   */
  async requestEnable(context: common.UIAbilityContext): Promise<void> {
    try {
      await dlpAntiPeep.requestAntiPeepOptions(context);
    } catch (e) {
      LogStore.log('防窥', '拉起设置', '失败', `${e}`);
    }
  }

  /** 通知回调 */
  private notify(hidden: boolean): void {
    if (this.callback !== null) {
      this.callback(hidden);
    }
  }
}
