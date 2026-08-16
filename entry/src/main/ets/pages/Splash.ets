/**
 * 自定义 Splash 启动页（参考本地项目 xndcourse 的实现方式）：
 * 全屏壁纸背景 + 应用图标/名称靠上居中 + 底部备用 logo，2 秒后进入主框架。
 * 与系统启动窗口（应用图标 + 壁纸主色调背景）无缝衔接，避免闪屏。
 */
import { router } from '@kit.ArkUI';
import { DataStore } from '../common/DataStore';

@Entry
@Component
struct Splash {
  /** 跳转定时器 id */
  private timer: number = 0;

  aboutToAppear(): void {
    // 2 秒后进入主框架（Index 内按登录态展示登录页或主页；replaceUrl 使 Splash 销毁，返回键不回启动页）
    this.timer = setTimeout(() => {
      router.replaceUrl({ url: 'pages/Index' });
    }, 2000);
  }

  aboutToDisappear(): void {
    clearTimeout(this.timer);
  }

  build() {
    Stack() {
      // 壁纸背景：全屏铺满（与系统启动窗口背景同色系，平滑过渡）
      Image($r('app.media.splash_bg'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .syncLoad(true) // 同步加载，首帧即出图，避免白屏闪烁
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 应用图标 + 名称：靠上居中
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
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 160 })
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
