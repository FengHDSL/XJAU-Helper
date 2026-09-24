/**
 * 顶栏返回按钮（移植 miha_hm 风格）：IconCircleButton 承载 + SymbolGlyph 左箭头。
 *
 * - 图标用系统符号 `sys.symbol.chevron_left`（不再是图片/文字箭头）；
 * - 材质走 applyMaterialCarrier：按压弹性形变（interactive）+ 跟手流光（拖拽光感）；
 * - buttonForce 常驻：不随应用内「全局沉浸光感」开关关闭而消失（顶栏按钮固定有光感）；
 * - 图标颜色沿用壁纸自适应（onWallpaper），浅/深色渐变顶栏上均可见。
 */
import { WallpaperTone } from '../../common/WallpaperTone';
import { IconCircleButton } from './IconCircleButton';

@Component
export struct BackButton {
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  /** 返回回调（默认 pop，由调用页决定） */
  onBack: () => void = () => {
  };

  build() {
    IconCircleButton({
      symbol: $r('sys.symbol.chevron_left'),
      buttonSize: 34,
      iconSize: 18,
      tint: WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode),
      buttonInteractive: true,
      buttonForce: true,
      onAction: (): void => {
        this.onBack();
      }
    })
  }
}
