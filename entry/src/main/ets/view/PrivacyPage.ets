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
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  private controller: webview.WebviewController = new webview.WebviewController();

  build() {
    NavDestination() {
      // 悬浮顶栏：正文(网页)占满全屏，上滑网页内容可从渐变下层透出
      Stack({ alignContent: Alignment.TopStart }) {
        // 协议正文（本地 rawfile HTML）：悬浮顶栏 + 网页全屏；加载完成后在文档头部注入可随滚动移动的留白段
        Web({ src: $rawfile('privacy.html'), controller: this.controller })
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
          .darkMode(WebDarkMode.Auto)
          .onPageEnd(() => {
            const barVp: number = this.getUIContext().px2vp(this.topInsetPx) + 60;
            this.controller.runJavaScript(
              `(function(){var s=document.getElementById('xju_top_spacer');` +
              `if(!s){s=document.createElement('div');s.id='xju_top_spacer';` +
              `s.style.width='100%';s.style.height='0px';s.style.flexShrink='0';` +
              `document.body.insertBefore(s,document.body.firstChild);}` +
              `s.style.height=${barVp}+'px';})()`, () => {
              });
          })
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

        // 统一头部（悬浮层）
        PageHeader({
          title: '隐私协议',
          onBack: () => {
            AppState.stack.pop();
          }
        })
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.bg_page'))
    .hideTitleBar(true)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    .width('100%')
    .height('100%')
  }
}
