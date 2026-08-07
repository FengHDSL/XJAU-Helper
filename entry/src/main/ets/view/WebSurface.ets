/**
 * 应用内网页视图：用于"网页版教务系统"和"找回密码"。
 *
 * 关键点：
 * 1) 登录本 App 后，HttpClient 已保存教务系统会话 Cookie。这里在网页加载前
 *    把同一份 Cookie 注入到 WebView 的 Cookie 存储（按域名），从而使网页版也保持登录状态。
 * 2) "网页版登录"模式（AppState.webLoginMode=true）：用户在 WebView 内完成真实登录后，
 *    页面会离开 login_slogin 跳转到主页。此时把 WebView 的会话 Cookie 读回 HttpClient，
 *    拉取学生资料，并自动调用 onWebLogin 回调进入主页，无需手动回退。
 * 若尚未登录（游客模式 / 未登录态），Cookie 为空，网页会显示教务系统登录页，属正常行为。
 */
import { webview } from '@kit.ArkWeb';
import { AppState } from '../common/AppState';
import { DataStore } from '../common/DataStore';
import { HttpClient } from '../api/HttpClient';
import { JwApi } from '../api/JwApi';
import { UserProfile } from '../model/Models';

@Component
export struct WebSurface {
  private controller: webview.WebviewController = new webview.WebviewController();
  /** 防止网页版登录成功回调被重复触发 */
  private loggedIn: boolean = false;

  /** WebView 组件出现：加载目标网页 */
  aboutToAppear(): void {
    this.loggedIn = false;
    WebSurface.injectCookies(AppState.webUrl);
  }

  /** 把 HttpClient 的会话 Cookie 写入 WebView 的域名 Cookie 存储，保持登录态 */
  private static injectCookies(url: string): void {
    const cookie: string = HttpClient.getCookie();
    if (cookie.length === 0) {
      return;
    }
    const pairs: string[] = cookie.split(';');
    for (let i = 0; i < pairs.length; i++) {
      const kv: string = pairs[i].trim();
      if (kv.length === 0) {
        continue;
      }
      const withMeta: string = `${kv}; Domain=jwxt.xjau.edu.cn; Path=/`;
      try {
        webview.WebCookieManager.setCookie(url, withMeta);
      } catch (e) {
        // 单条失败不影响其它
      }
    }
  }

  /** 网页版登录成功后：Cookie 回 HttpClient、缓存资料到本地持久化、自动进入主页 */
  private async handleWebLoginSuccess(): Promise<void> {
    this.loggedIn = true;
    const cookie: string = webview.WebCookieManager.getCookie(AppState.webUrl);
    if (cookie.length > 0) {
      HttpClient.setCookie(cookie);
      DataStore.put(DataStore.KEY_SESSION_COOKIE, cookie);
    }
    HttpClient.setOfflineMode(false);
    JwApi.USE_MOCK = false;
    try {
      const profile: UserProfile = await JwApi.getProfile();
      if (profile.name.length > 0) {
        AppState.profile = profile;
        AppState.account = profile.studentId;
        DataStore.cacheProfile(profile);
        DataStore.put(DataStore.KEY_LAST_ACCOUNT, profile.studentId);
        DataStore.setLoginMethod('web');
      }
    } catch (e) {
      // ignore
    }
    if (AppState.onWebLogin !== null) {
      AppState.onWebLogin();
    }
    AppState.webLoginMode = false;
  }

  build() {
    Column() {
      Web({ src: AppState.webUrl, controller: this.controller })
        .layoutWeight(1)
        .width('100%')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .onControllerAttached(() => {
          WebSurface.injectCookies(AppState.webUrl);
          this.controller.loadUrl(AppState.webUrl);
        })
        .onPageEnd(() => {
          const url: string = this.controller.getUrl();
          if (AppState.webLoginMode && !this.loggedIn &&
              url.indexOf('login_slogin') < 0 && url.indexOf('jwglxt') >= 0) {
            this.handleWebLoginSuccess();
          }
        })
    }
    .width('100%')
    .height('100%')
  }
}
