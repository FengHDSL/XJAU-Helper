/**
 * 隐私协议页：Web 组件加载本地 rawfile HTML（参考本地项目 xndcourse 的 privacy.html 写法）
 * 入口：关于页（MineView/AboutPage）底部「隐私协议」入口
 */
import { webview } from '@kit.ArkWeb';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { PageHeader } from './common/UiKit';

@Component
export struct PrivacyPage {
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();

  build() {
    NavDestination() {
      Column() {
        // 统一头部
        PageHeader({
          title: '隐私协议',
          onBack: () => {
            AppState.stack.pop();
          }
        })

        // 协议正文（本地 rawfile HTML，跟随系统深色）；拦截外链点击：在应用内「外部链接」页（WebViewPage）打开，不跳转系统浏览器
        Web({ src: $rawfile('privacy.html'), controller: this.controller })
          .width('100%')
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .darkMode(WebDarkMode.Auto)
          .onLoadIntercept((event) => {
            if (event && event.data) {
              const url: string = event.data.getRequestUrl();
              if (url.startsWith('http://') || url.startsWith('https://')) {
                AppState.webUrl = url;
                AppState.webTitle = 'GitHub 开源仓库';
                AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
                return true;
              }
            }
            return false;
          })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
  }
}
