import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * 窗口自适应工具：统一「手机端布局 / 大屏（平板 · PC）布局」的判定口径。
 *
 * 判定规则（所有设备一致）：**窗口宽 ≥ 600vp 且窗口横向 → 大屏布局**，否则手机端布局。
 * - PC / 2in1：窗口可自由缩放 → 拖动改变窗口宽高比/宽度时实时切换（窄窗 = 手机端样式，
 *   放大到 ≥ 600vp 宽且横向 = 大屏平板端样式）；
 * - 手机 / 平板：与改造前一致（竖屏 = 手机端样式，横屏 = 大屏样式）。
 *
 * 说明：ArkUI 的 mediaquery 以**窗口**为参照并随窗口尺寸变化回调，
 * 因此无需额外注册 windowSizeChange 即可感知 PC 窗口缩放。
 */
export class ResponsiveUtil {
  /** 大屏布局的窗口宽度阈值（vp）：窗口宽 ≥ 该值视为大屏 */
  static readonly WIDE_WIDTH_VP: number = 600;
  /** mediaquery 条件：窗口宽度达到大屏阈值 */
  static readonly QUERY_WIDE: string = '(width>=600vp)';
  /** mediaquery 条件：窗口处于横向 */
  static readonly QUERY_LANDSCAPE: string = '(orientation: landscape)';

  /** 是否 PC / 2in1 设备（窗口可自由缩放，底栏留白等需按窗口形态微调） */
  static isDesktop(): boolean {
    const t: string = deviceInfo.deviceType;
    return t === '2in1' || t === 'pc';
  }

  /**
   * 由「宽度是否达阈值」与「是否横向」组合出最终布局判定。
   * @param wide 窗口宽度 ≥ 600vp
   * @param landscape 窗口横向
   */
  static isWideLayout(wide: boolean, landscape: boolean): boolean {
    return wide && landscape;
  }
}
