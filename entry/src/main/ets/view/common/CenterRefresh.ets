/**
 * CenterRefresh：下拉刷新动效——松手进入刷新时，顶部出现的刷新图标滑向屏幕中央继续播放。
 * 无圆形背景，仅单一图标；用法：页面把 refreshing @State 传入 show，结束自动隐藏。
 */
import { Theme } from '../../common/ThemeUtil';

@Component
export struct CenterRefresh {
  @Prop show: boolean = false;
  @StorageProp('themeColor') themeColor: string = 'green';
  /** 平移偏移：初始在屏幕上方（与下拉图标一致的位置），刷新开始时滑向中央 */
  @State offY: number = -900;
  @State scaleVal: number = 0.7;

  build() {
    if (this.show) {
      Stack() {
        // 单一刷新图标（无圆形背景）：从顶部滑入屏幕中心后持续转圈
        LoadingProgress()
          .width(46)
          .height(46)
          .color(Theme.colorOf(this.themeColor))
          .scale({ x: this.scaleVal, y: this.scaleVal })
      }
      .width('100%')
      .height('100%')
      .alignContent(Alignment.Center)
      .hitTestBehavior(HitTestMode.None)
      .translate({ y: this.offY })
      .opacity(this.offY === 0 ? 1 : 0.4)
      .onAppear(() => {
        // 从顶部（顶栏下方，与下拉出现的图标一致的位置）滑向屏幕中央
        this.offY = -900;
        this.scaleVal = 0.7;
        this.getUIContext().animateTo({ duration: 380, curve: Curve.EaseOut }, () => {
          this.offY = 0;
          this.scaleVal = 1;
        });
      })
    }
  }
}
