/**
 * 自定义 Splash 启动页：
 * 全屏壁纸背景 + 应用图标/名称靠上居中 + 底部备用 logo，2 秒后进入主框架。
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

      // 应用图标 + 名称：靠上居中；底部 logo：推到最下方
      Column() {
        Column() {
          Image($r('app.media.startIcon'))
            .width(96)
            .height(96)
            .borderRadius(22)
            .objectFit(ImageFit.Contain)
            .backgroundColor('#FFFFFF')
            .margin({ bottom: 16 })

          Text('新农助手')
            .fontSize(26)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Bold)
            .textShadow({
              radius: 8,
              color: 'rgba(0,0,0,0.45)',
              offsetX: 0,
              offsetY: 2
            })
        }
        .width('100%')
        .padding({ top: 160 })
        .alignItems(HorizontalAlign.Center)

        Blank()
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
