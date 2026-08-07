/**
 * 通用网页页（Navigation 二级页）——外部链接用 WebView 打开
 */
import { WebSurface } from './WebSurface';
import { AppState } from '../common/AppState';
import { Theme } from '../common/ThemeUtil';

@Component
export struct WebViewPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('‹')
            .fontSize(26)
            .fontColor(this.isDarkMode ? $r('app.color.text_primary') : Color.White)
            .width(34).height(34).textAlign(TextAlign.Center)
            .onClick(() => { AppState.stack.pop(); })
          Text(AppState.webTitle.length > 0 ? AppState.webTitle : '网页')
            .fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(this.isDarkMode ? $r('app.color.text_primary') : Color.White)
            .margin({ left: 6 })
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%').alignItems(VerticalAlign.Center)
        .padding({ left: 10, right: 16, bottom: 14, top: px2vp(this.topInsetPx) + 10 })
        .backgroundColor(this.isDarkMode ? '#1A1D1C' : Theme.colorOf(this.themeColor))

        WebSurface()
          .width('100%').layoutWeight(1)
      }
      .width('100%').height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .hideTitleBar(true)
    .width('100%').height('100%')
  }
}
