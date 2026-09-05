/**
 * 自定义 Splash 启动页：
 * 全屏壁纸背景 + 应用前景图标居中显示，2 秒后进入主框架。
 */
import { router } from '@kit.ArkUI';

@Entry
@Component
struct Splash {
  /** 跳转定时器 id */
  private timer: number = 0;

  aboutToAppear(): void {
    // 2 秒后进入主框架（replaceUrl 使 Splash 销毁，返回键不回启动页）
    this.timer = setTimeout(() => {
      router.replaceUrl({ url: 'pages/Index' });
    }, 2000);
  }

  aboutToDisappear(): void {
    clearTimeout(this.timer);
  }

  build() {
    Stack() {
      // 壁纸背景：全屏铺满，同步加载首帧即出图
      Image($r('app.media.splash_bg'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .syncLoad(true)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 应用前景图标：屏幕居中显示
      Image($r('app.media.foreground'))
        .width(180)
        .height(180)
        .objectFit(ImageFit.Contain)
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
