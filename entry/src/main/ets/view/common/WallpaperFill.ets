/**
 * WallpaperFill：二级页壁纸底层（与主界面 MainView 壁纸渲染同参数）
 * 置为 NavDestination 页最底下一层；无壁纸('none')时回落页面底色——
 * 既让二级页显示全局壁纸，又保持不透明背景（避免下层残留）。
 *
 * 页面底色由 `AppearanceStore.pageBackground()` 提供：
 * 内置主题色始终染色；自定义主题色仅在「高权限自定义主题色」开启时染色（移植自参考项目）。
 */
import { AppearanceStore } from '../../common/AppearanceStore';
import { Wallpaper } from '../../common/Wallpaper';
import { WallpaperTone } from '../../common/WallpaperTone';

@Component
export struct WallpaperFill {
  @StorageProp('wallpaperId') wallpaperId: string = 'none';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('themeColor') themeColor: string = 'green';
  /** 高权限自定义主题色开关（用于登记依赖：开关变化时本底色即时刷新） */
  @StorageProp('customAccentFull') customAccentFull: boolean = false;
  /** 页面背景色（广播键）：开关/主题/深色变化时由 AppearanceStore.broadcastDerived() 重写 */
  @StorageProp('pageBackground') pageBgBc: string = '';
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
        // 未启用壁纸：页面底色（内置主题色染色；自定义 hex 需开启「高权限自定义主题色」）。
        // 走广播键订阅：开关/主题/深色变化时即时刷新（广播未写入前回落静态派生兜底）。
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.pageBgBc.length > 0
            ? this.pageBgBc
            : AppearanceStore.pageBackground(this.isDarkMode, this.themeColor))
      }
    }
    .width('100%')
    .height('100%')
  }
}
