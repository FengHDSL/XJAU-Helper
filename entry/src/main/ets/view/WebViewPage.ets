/**
 * 通用网页页（Navigation 二级页）——外部链接用 WebView 打开
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { common } from '@kit.AbilityKit';
import { WebSurface } from './WebSurface';
import { AppState } from '../common/AppState';
import { Theme } from '../common/ThemeUtil';

@Component
export struct WebViewPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 标题栏文字：初始为调用方设置的 webTitle，网页加载完成后自动替换为网页自身标题 */
  @State pageTitle: string = '网页';

  aboutToAppear(): void {
    this.pageTitle = AppState.webTitle.length > 0 ? AppState.webTitle : '网页';
  }

  /** 复制当前链接到剪贴板 */
  private copyLink(): void {
    const url: string = AppState.webUrl;
    if (url.length === 0) {
      return;
    }
    pasteboard.getSystemPasteboard().setDataSync(pasteboard.createPlainTextData(url));
    promptAction.showToast({ message: '链接已复制' });
  }

  /** 拉起系统分享面板（链接），分享不可用时退回复制 */
  private shareLink(): void {
    const url: string = AppState.webUrl;
    if (url.length === 0) {
      return;
    }
    try {
      const record: systemShare.SharedRecord = {
        utd: 'general.hyperlink',
        title: AppState.webTitle.length > 0 ? AppState.webTitle : '外部链接',
        content: url
      };
      const data: systemShare.SharedData = new systemShare.SharedData(record);
      const controller: systemShare.ShareController = new systemShare.ShareController(data);
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      controller.show(ctx, {});
    } catch (e) {
      // 设备不支持分享面板时退回复制
      this.copyLink();
    }
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('‹')
            .fontSize(26)
            .fontColor(this.isDarkMode ? $r('app.color.text_primary') : Color.White)
            .width(34).height(34).textAlign(TextAlign.Center)
            .onClick(() => { AppState.stack.pop(); })
          Text(this.pageTitle)
            .fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(this.isDarkMode ? $r('app.color.text_primary') : Color.White)
            .margin({ left: 6 })
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          // 右上角胶囊按钮：复制链接
          Text('复制')
            .fontSize(12)
            .fontColor(this.isDarkMode ? $r('app.color.text_primary') : Color.White)
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .backgroundColor('#33FFFFFF')
            .borderRadius(14)
            .onClick(() => { this.copyLink(); })
          // 右上角胶囊按钮：分享
          Text('分享')
            .fontSize(12)
            .fontColor(this.isDarkMode ? $r('app.color.text_primary') : Color.White)
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .backgroundColor('#33FFFFFF')
            .borderRadius(14)
            .margin({ left: 8 })
            .onClick(() => { this.shareLink(); })
        }
        .width('100%').alignItems(VerticalAlign.Center)
        .padding({ left: 10, right: 16, bottom: 14, top: px2vp(this.topInsetPx) + 10 })
        .backgroundColor(this.isDarkMode ? '#1A1D1C' : Theme.colorOf(this.themeColor))

        WebSurface({ onTitleChange: (t: string) => { this.pageTitle = t; } })
          .width('100%').layoutWeight(1)
      }
      .width('100%').height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .hideTitleBar(true)
    .width('100%').height('100%')
  }
}
