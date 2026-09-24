/**
 * 顶栏返回按钮（miha_hm 风格）：IconCircleButton 承载 + 用户提供的 chevron_left.svg 图标。
 *
 * - 图标黑白自适应（深色白/浅色黑，与其他箭头一致，不跟随主题色）；
 * - 材质走 applyMaterialCarrier：按压弹性形变（interactive）+ 跟手流光（拖拽光感）；
 * - buttonForce 常驻：不随应用内「全局沉浸光感」开关关闭而消失（顶栏按钮固定有光感）。
 */
import { IconCircleButton } from './IconCircleButton';

@Component
export struct BackButton {
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 返回回调（默认 pop，由调用页决定） */
  onBack: () => void = () => {
  };

  build() {
    IconCircleButton({
      // 图标用用户提供的 chevron_left.svg（黑白自适应，与其他箭头一致）
      hasImage: true,
      image: $r('app.media.chevron_left'),
      buttonSize: 34,
      iconSize: 16,
      tint: this.isDarkMode ? Color.White : Color.Black,
      buttonInteractive: true,
      buttonForce: true,
      onAction: (): void => {
        this.onBack();
      }
    })
  }
}
