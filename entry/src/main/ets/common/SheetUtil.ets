import { display } from '@kit.ArkUI';

/**
 * 半模态面板宽度工具。
 * 与课程表页面 ScheduleView 的 sheetWidth 逻辑保持一致：
 *  - 平板（屏幕宽度 ≥ 600vp）：限制为屏幕宽度的 70%，且封顶 840vp；
 *  - 手机：保持 100% 全宽。
 * 全屏设备上的 bindSheet 配合 preferType: SheetType.BOTTOM 会从底部上浮并自动居中。
 */
export class SheetUtil {
  static sheetWidth(): Dimension {
    try {
      const d = display.getDefaultDisplaySync();
      const screenVp: number = px2vp(d.width);
      return screenVp >= 600 ? `${Math.min(Math.round(screenVp * 0.7), 840)}vp` : '100%';
    } catch (e) {
      return '100%';
    }
  }
}
