/**
 * WallpaperFill：二级页壁纸底层（与主界面 MainView 壁纸渲染同参数）
 * 置为 NavDestination 页最底下一层；无壁纸('none')时回落 bg_page 纯色——
 * 既让二级页显示全局壁纸，又保持不透明背景（避免下层残留）。
 */
import { Wallpaper } from '../../common/Wallpaper';
import { WallpaperTone } from '../../common/WallpaperTone';

@Component
export struct WallpaperFill {
  @StorageProp('wallpaperId') wallpaperId: string = 'none';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 壁纸蒙版开关（关闭时不叠加可读性遮罩） */
  @StorageProp('wallpaperMask') wallpaperMask: boolean = true;
  /** 壁纸平均亮度（-1=未分析）；用于自动适配文字对比度 */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;

  build() {
    Stack() {
      if (this.wallpaperId.startsWith('c:')) {
        Image(Wallpaper.src(this.wallpaperId))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
        // 对比度适配遮罩：按壁纸明暗自动加厚/减薄，保证正文 ≥ 4.5:1、标题 ≥ 3:1
        // （未分析出亮度时回落固定遮罩）
        if (this.wallpaperMask) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.wallpaperTone >= 0
              ? WallpaperTone.overlay(this.wallpaperTone, this.isDarkMode)
              : (this.isDarkMode ? 'rgba(8,10,10,0.38)' : 'rgba(255,255,255,0.18)'))
        }
      } else {
        // 未启用壁纸：与原有页面底色一致（不透出下层）
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.bg_page'))
      }
    }
    .width('100%')
    .height('100%')
  }
}
