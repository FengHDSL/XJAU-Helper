/**
 * 通用网页页（Navigation 二级页）——外部链接用 WebView 打开
 *
 * 标题栏右上角提供"更多"功能菜单（复刻 DailyNic_HMOS）：
 *  复制链接 / 后退 / 前进 / 刷新 / 更改浏览器标识（桌面·手机·平板）/ 历史记录 / 释放内存
 */
import { SheetUtil } from '../common/SheetUtil';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { common, Want } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { WebSurface } from './WebSurface';
import { AppState, SharedHistoryItem } from '../common/AppState';
import { Theme } from '../common/ThemeUtil';
import { WallpaperTone } from '../common/WallpaperTone';
import { Immersive } from './common/Immersive';
import { BarTitle } from './common/UiKit';
import { BackButton } from './common/BackButton';
import { JwApi } from '../api/JwApi';

/** 浏览器标识（UA）常量：桌面 / 手机 / 平板 */
const DESKTOP_UA: string =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36';
const MOBILE_UA: string =
  'Mozilla/5.0 (Phone; OpenHarmony 5.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 ArkWeb/4.1.6.1 Mobile HuaweiBrowser/5.0.3.351';
const TABLET_UA: string =
  'Mozilla/5.0 (Tablet; OpenHarmony 5.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 ArkWeb/4.1.6.1';

/** UA 模式：0=手机 1=桌面 2=平板 */
const UA_MOBILE: number = 0;
const UA_DESKTOP: number = 1;
const UA_TABLET: number = 2;

@Component
export struct WebViewPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('barStyle') barStyle: string = 'new';
  @StorageProp('immersiveEffect') immersiveEffect: boolean = true;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 壁纸亮度（顶栏文字自适应用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  /** 标题栏文字：初始为调用方设置的 webTitle，网页加载完成后自动替换为网页自身标题 */
  @State pageTitle: string = '网页';
  /** 当前 UA 模式（0 手机 / 1 桌面 / 2 平板） */
  @State uaMode: number = UA_MOBILE;
  /** 历史记录弹层开关 */
  @State showHistory: boolean = false;
  /** 历史记录列表（应用级共享历史快照） */
  @State historyItems: SharedHistoryItem[] = [];
  /** WebSurface 回传的 controller（菜单操作前进后退/刷新/UA/历史用） */
  private ctrl: webview.WebviewController | null = null;

  aboutToAppear(): void {
    this.pageTitle = AppState.webTitle.length > 0 ? AppState.webTitle : '网页';
    // 功能浏览模式默认禁止使用外部链接页（所有入口统一拦截）；调试模式开启后放行
    if (JwApi.USE_MOCK && !AppState.debugNetwork) {
      this.getUIContext().getPromptAction().showToast({ message: '当前模式禁止使用' });
      setTimeout(() => {
        AppState.stack.pop();
      }, 400);
    }
  }

  // ── 标题栏菜单动作 ──

  /** 复制当前链接到剪贴板 */
  private copyLink(): void {
    const url: string = AppState.webUrl;
    if (url.length === 0) {
      return;
    }
    pasteboard.getSystemPasteboard().setDataSync(pasteboard.createPlainTextData(url));
    this.getUIContext().getPromptAction().showToast({ message: '链接已复制' });
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
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      controller.show(ctx, {});
    } catch (e) {
      // 设备不支持分享面板时退回复制
      this.copyLink();
    }
  }

  /** 用系统浏览器打开当前链接（外部浏览器） */
  private openInBrowser(): void {
    const url: string = AppState.webUrl;
    if (url.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '链接为空' });
      return;
    }
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: url
      };
      ctx.startAbility(want);
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '打开浏览器失败' });
    }
  }

  /** 后退一页（无历史时提示） */
  private goBack(): void {
    if (this.ctrl !== null && this.ctrl.accessBackward()) {
      this.ctrl.backward();
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '已是第一页' });
    }
  }

  /** 前进一页（无历史时提示） */
  private goForward(): void {
    if (this.ctrl !== null && this.ctrl.accessForward()) {
      this.ctrl.forward();
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '已是最后一页' });
    }
  }

  /** 刷新当前页 */
  private refreshPage(): void {
    try {
      this.ctrl?.refresh();
    } catch (e) {
      // ignore
    }
  }

  /** 切换浏览器标识（UA）并刷新 */
  private switchUA(mode: number): void {
    let ua: string = MOBILE_UA;
    if (mode === UA_DESKTOP) {
      ua = DESKTOP_UA;
    } else if (mode === UA_TABLET) {
      ua = TABLET_UA;
    }
    try {
      this.ctrl?.setCustomUserAgent(ua);
      this.uaMode = mode;
      this.ctrl?.refresh();
    } catch (e) {
      // ignore
    }
  }

  /** 释放 WebView 内存（参考 DailyNic_HMOS：trimMemoryByPressureLevel） */
  private trimMemory(): void {
    try {
      webview.WebviewController.trimMemoryByPressureLevel(webview.PressureLevel.MEMORY_PRESSURE_LEVEL_MODERATE);
      this.getUIContext().getPromptAction().showToast({ message: '内存已释放' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '释放失败' });
    }
  }

  // ── 历史记录 ──

  /** 打开历史记录弹层（应用级共享历史：所有网页场景互通，重启后保留） */
  private openHistory(): void {
    // 深拷贝快照，避免弹层内修改影响 AppState.webHistory 引用
    this.historyItems = AppState.getWebHistory().slice();
    this.showHistory = true;
  }

  /** 点击历史条目：在当前 WebView 中打开对应链接 */
  private jumpHistory(item: SharedHistoryItem): void {
    this.showHistory = false;
    if (this.ctrl === null) {
      return;
    }
    try {
      this.ctrl.loadUrl(item.url);
    } catch (e) {
      // ignore
    }
  }

  /** 清空全部历史记录（共享历史 + 当前 WebView 历史） */
  private clearHistoryAll(): void {
    AppState.clearWebHistory();
    this.historyItems = [];
    if (this.ctrl !== null) {
      try {
        this.ctrl.clearHistory();
      } catch (e) {
        // ignore
      }
    }
    this.getUIContext().getPromptAction().showToast({ message: '历史记录已清空' });
  }

  // ── 标题栏"更多"菜单（复刻 DailyNic_HMOS，不带图标）──

  @Builder
  moreMenu() {
    Menu() {
      MenuItem({ content: '复制链接' })
        .onClick(() => {
          this.copyLink();
        })
      MenuItem({ content: '跳转浏览器' })
        .onClick(() => {
          this.openInBrowser();
        })
      MenuItem({ content: '后退' })
        .onClick(() => {
          this.goBack();
        })
      MenuItem({ content: '前进' })
        .onClick(() => {
          this.goForward();
        })
      MenuItem({ content: '刷新' })
        .onClick(() => {
          this.refreshPage();
        })
      MenuItem({ content: '更改浏览器标识', builder: this.uaMenu() })
      MenuItem({ content: '历史记录' })
        .onClick(() => {
          this.openHistory();
        })
      MenuItem({ content: '释放内存' })
        .onClick(() => {
          this.trimMemory();
        })
    }
  }

  /** 浏览器标识子菜单（桌面 / 手机 / 平板） */
  @Builder
  uaMenu() {
    Menu() {
      MenuItem({
        content: this.uaMode === UA_DESKTOP ? '桌面版（当前）' : '桌面版'
      })
        .onClick(() => {
          this.switchUA(UA_DESKTOP);
        })
      MenuItem({
        content: this.uaMode === UA_MOBILE ? '手机版（当前）' : '手机版'
      })
        .onClick(() => {
          this.switchUA(UA_MOBILE);
        })
      MenuItem({
        content: this.uaMode === UA_TABLET ? '平板版（当前）' : '平板版'
      })
        .onClick(() => {
          this.switchUA(UA_TABLET);
        })
    }
  }

  /** 历史记录弹层（标题栏由系统 bindSheet 提供：左上角"历史记录"，右上角关闭按钮） */
  @Builder
  historySheet() {
    Column() {
      // 清空按钮：放在左上角标题下方（与系统关闭按钮分离）
      Row() {
        if (this.historyItems.length > 0) {
          Text('清空')
            .fontSize(13)
            .fontColor('#DB5252')
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .borderRadius(12)
            .backgroundColor('#14DB5252')
            .onClick(() => {
              this.clearHistoryAll();
            })
        } else {
          Text('清空')
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .borderRadius(12)
            .backgroundColor('#14FFFFFF')
            .enabled(false)
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .alignItems(VerticalAlign.Top)

      if (this.historyItems.length === 0) {
        Text('暂无历史记录')
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 40 })
      } else {
        List({ space: 6 }) {
          ForEach(this.historyItems, (item: SharedHistoryItem) => {
            ListItem() {
              Column() {
                Text(item.title)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')

                Text(item.url)
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .margin({ top: 3 })
              }
              .width('100%')
              .padding(12)
              .backgroundColor($r('app.color.bg_card'))
              .borderRadius(12)
            }
            .onClick(() => {
              this.jumpHistory(item);
            })
          }, (item: SharedHistoryItem) => item.url)
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 16 })
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  /** 是否服务大厅主页（仅此页面内部自带滚动容器，需页面级留白；其它外部链接保持穿透效果） */
  static isSpaPortal(url: string): boolean {
    // 服务大厅相关地址（rhmh 域名，含智慧学工等应用）→ 固定顶栏（页面级留白）
    return url.indexOf('rhmh.xjau.edu.cn') >= 0 || url.indexOf('/default/index.html') >= 0;
  }

  /** 是否智慧学工页面（默认使用电脑端 UA） */
  static isZhihuiXuegong(url: string): boolean {
    return url.indexOf('wid=1238430490178043904') >= 0 || url.indexOf('xgxt') >= 0 ||
      url.indexOf('zhihui') >= 0 || url.indexOf('ServiceShow') >= 0;
  }

  build() {
    NavDestination() {
      Column() {
        // 顶栏（两层）：内容(底)/主题渐变(顶)；模糊层已取消
        Stack({ alignContent: Alignment.TopStart }) {
          Column()
            .width('100%')
            .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
            .linearGradient({
              angle: 180,
              colors: Theme.barGradient(this.themeColor, this.barStyle)
            })
            .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, this.immersiveEffect && this.barStyle === 'legacy'))
        Row() {
          // 返回
          BackButton({ onBack: () => { AppState.stack.pop(); } })
          BarTitle({ title: this.pageTitle, marquee: true })
            .margin({ left: 6 })
            .layoutWeight(1)
          // 右上角胶囊按钮：分享
          Text('分享')
            .fontSize(12)
            .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .backgroundColor('#33FFFFFF')
            .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, this.immersiveEffect))
            .borderRadius(14)
            .onClick(() => { this.shareLink(); })
          // 右上角胶囊按钮：更多（功能菜单，复刻 DailyNic_HMOS）
          Text('更多')
            .fontSize(12)
            .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .backgroundColor('#33FFFFFF')
            .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, this.immersiveEffect))
            .borderRadius(14)
            .margin({ left: 8 })
            .bindMenu(this.moreMenu())
        }
        .width('100%').alignItems(VerticalAlign.Top)
        .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
        .padding({ left: 16, right: 16, bottom: 12, top: this.getUIContext().px2vp(this.topInsetPx) + 12 })
        }
        .width('100%')
        // 顶栏悬浮；网页文档头部注入一段可随滚动移动的留白（网页初始内容位于顶栏下方，上滚时可穿过渐变下层）
        .position({ x: 0, y: 0 })
        .zIndex(2)

        // 网页全屏：顶部让位顶栏、底部让位悬浮底栏；留白随网页滚动，上滑内容可穿入渐变底层
        WebSurface({
          onTitleChange: (t: string) => { this.pageTitle = t; },
          onControllerReady: (ctrl: webview.WebviewController) => { this.ctrl = ctrl; },
          desktopUa: WebViewPage.isZhihuiXuegong(AppState.webUrl),
          onLoadEnd: () => {
            const topVp: number = this.getUIContext().px2vp(this.topInsetPx) + 60;
            const bottomVp: number = this.getUIContext().px2vp(this.bottomInsetPx) + 64;
            if (this.ctrl === null) {
              return;
            }
            // 统一方案：给页面真正的滚动容器加内边距（body 滚动/内部容器滚动/平板横屏均适用），不插入 DOM 节点
            this.ctrl.runJavaScript(
              `(function(){` +
              `function pick(){` +
              `var best=null,area=0;` +
              `var all=document.querySelectorAll('div,main,section,article');` +
              `for(var i=0;i<all.length;i++){var e=all[i];var st=getComputedStyle(e);var oy=st.overflowY;` +
              `if((oy==='auto'||oy==='scroll')&&e.clientHeight>200&&e.scrollHeight>e.clientHeight+10){` +
              `var a=e.clientHeight*e.clientWidth;if(a>area){area=a;best=e;}}}` +
              `return best||document.scrollingElement||document.documentElement;}` +
              `function apply(){var s=pick();s.style.paddingTop='${topVp}px';s.style.paddingBottom='${bottomVp}px';}` +
              `apply();setTimeout(apply,600);setTimeout(apply,1600);` +
              `})()`, () => {
              });
          }
        })
          .width('100%')
          .layoutWeight(1)

      }
      .width('100%').height('100%')
      .backgroundColor($r('app.color.bg_page'))
      .bindSheet($$this.showHistory, this.historySheet(), {
        width: SheetUtil.sheetWidth(),
        preferType: SheetType.BOTTOM,
        height: SheetSize.MEDIUM,
        dragBar: false,
        showClose: true,
        title: { title: '历史记录' },
        backgroundColor: $r('app.color.bg_page')
      })
    }
    .hideTitleBar(true)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    .width('100%').height('100%')
  }
}
