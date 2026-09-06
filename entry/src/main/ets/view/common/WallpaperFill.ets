/**
 * WallpaperFill：二级页壁纸底层（与主界面 MainView 壁纸渲染同参数）
 * 置为 NavDestination 页最底下一层；无壁纸('none')时回落 bg_page 纯色——
 * 既让二级页显示全局壁纸，又保持不透明背景（避免下层残留）。
 */
import { Wallpaper } from '../../common/Wallpaper';

@Component
export struct WallpaperFill {
  @StorageProp('wallpaperId') wallpaperId: string = 'none';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;

  build() {
    Stack() {
      if (this.wallpaperId !== 'none') {
        Image(Wallpaper.src(this.wallpaperId))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
        // 可读性遮罩（深浅各半透明），同主界面观感
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(this.isDarkMode ? 'rgba(8,10,10,0.38)' : 'rgba(255,255,255,0.18)')
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
