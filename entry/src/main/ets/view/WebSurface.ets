/**
 * 应用内网页视图：用于"网页版教务系统"、"找回密码"和外部链接。
 *
 * 关键点：
 * 1) 登录本 App 后，HttpClient 已保存教务系统会话 Cookie。这里在网页加载前
 *    把同一份 Cookie 注入到 WebView 的 Cookie 存储（按域名），从而使网页版也保持登录状态。
 * 2) "网页版登录"模式（AppState.webLoginMode=true）：用户在 WebView 内完成真实登录后，
 *    页面会离开 login_slogin 跳转到主页。此时把 WebView 的会话 Cookie 读回 HttpClient，
 *    拉取学生资料，并自动调用 onWebLogin 回调进入主页，无需手动回退。
 * 若尚未登录（游客模式 / 未登录态），Cookie 为空，网页会显示教务系统登录页，属正常行为。
 * 3) controller 附着后通过 onControllerReady 回调把 WebviewController 交给外层，
 *    供"外部链接"页（WebViewPage）的左上角"更多"菜单操作：前进后退/刷新/UA/历史记录/释放内存等。
 */
import { webview } from '@kit.ArkWeb';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { DataStore } from '../common/DataStore';
import { HttpClient } from '../api/HttpClient';
import { JwApi } from '../api/JwApi';
import { UserProfile } from '../model/Models';

@Component
export struct WebSurface {
  /** 页面加载完成后回传网页标题（供外部链接页更新标题栏；默认空回调） */
  onTitleChange: (title: string) => void = () => {
  };
  /** WebviewController 附着后回调（供外层菜单操作前进后退/刷新/UA/历史等） */
  onControllerReady: (ctrl: webview.WebviewController) => void = () => {
  };
  private controller: webview.WebviewController = new webview.WebviewController();
  /** 防止网页版登录成功回调被重复触发 */
  private loggedIn: boolean = false;
  /** 服务大厅模式：是否已触发 /sso/jziotlogin 桥接（避免重复跳转死循环） */
  private bridging: boolean = false;
  /** 上次网页版登录目标（切换目标时重置 bridging） */
  private lastTarget: string = AppState.webLoginTarget;

  /** WebView 组件出现：加载目标网页 */
  aboutToAppear(): void {
    this.loggedIn = false;
    this.bridging = false;
    this.lastTarget = AppState.webLoginTarget;
    // 校园 SSO 域名注入会话 Cookie（教务系统 + 统一认证/服务大厅；外部链接如 GitHub 不注入，避免隐私泄漏）
    if (AppState.webUrl.indexOf('xjau.edu.cn') >= 0) {
      WebSurface.injectCookies(AppState.webUrl);
    }
  }

  /** 把 HttpClient 的教务系统会话 Cookie 写入 WebView 的域名 Cookie 存储，保持登录态；
   *  校园 SSO 域名（authserver/rhmh/xgxt 等）同时注入统一认证/服务大厅会话，使各 SSO 页面保持登录态 */
  private static injectCookies(url: string): void {
    // 教务系统会话（仅教务系统域名注入）
    if (url.indexOf('jwxt.xjau.edu.cn') >= 0) {
      const cookie: string = HttpClient.getCookie();
      if (cookie.length > 0) {
        const pairs: string[] = cookie.split(';');
        for (let i = 0; i < pairs.length; i++) {
          const kv: string = pairs[i].trim();
          if (kv.length === 0) {
            continue;
          }
          try {
            webview.WebCookieManager.setCookie(url, `${kv}; Domain=jwxt.xjau.edu.cn; Path=/`);
          } catch (e) {
            // 单条失败不影响其它
          }
        }
      }
    }
    // 校园 SSO 会话（统一认证 CASTGC + 服务大厅等），各 SSO 页面保持登录态
    if (url.indexOf('xjau.edu.cn') >= 0) {
      WebSurface.injectSsoCookies();
    }
  }

  /** 注入统一认证/服务大厅等 SSO 会话 Cookie（按域名写入 WebView Cookie 存储）：
   *  CASTGC（authserver）→ 服务大厅/第二课堂等页面自动走 CAS 单点登录；
   *  KEY_SSO_COOKIES（网页版服务大厅登录捕获的 host\ncookie 对）→ 直接恢复服务大厅登录态。 */
  private static injectSsoCookies(): void {
    // 统一认证 TGT（原生 CAS / 网页版服务大厅登录均可能持久化）
    const tgc: string = DataStore.get(DataStore.KEY_CAS_TGC);
    if (tgc.length > 0) {
      try {
        webview.WebCookieManager.setCookie('https://authserver.xjau.edu.cn/',
          `CASTGC=${tgc}; Domain=authserver.xjau.edu.cn; Path=/`);
      } catch (e) {
        // ignore
      }
    }
    // 网页版服务大厅登录捕获的会话 Cookie（host\ncookie 成对）
    const raw: string = DataStore.get(DataStore.KEY_SSO_COOKIES);
    if (raw.length === 0) {
      return;
    }
    const pairs: string[] = raw.split('\n');
    for (let i = 0; i + 1 < pairs.length; i += 2) {
      const host: string = pairs[i].trim();
      const cookieStr: string = pairs[i + 1];
      if (host.length === 0 || cookieStr.length === 0) {
        continue;
      }
      const kvs: string[] = cookieStr.split(';');
      for (let j = 0; j < kvs.length; j++) {
        const kv: string = kvs[j].trim();
        if (kv.length === 0) {
          continue;
        }
        try {
          webview.WebCookieManager.setCookie('https://' + host + '/',
            `${kv}; Domain=${host}; Path=/`);
        } catch (e) {
          // 单条失败不影响其它
        }
      }
    }
  }

  /** 捕获统一认证/服务大厅/智慧学工等 SSO 会话 Cookie（网页版登录成功后 + 浏览校园 SSO 页面时调用），
   *  供我的页「服务大厅/第二课堂」等 SSO 页面保持登录态。 */
  private static captureSsoCookies(): void {
    const auth: string = webview.WebCookieManager.getCookie('https://authserver.xjau.edu.cn/');
    const hall: string = webview.WebCookieManager.getCookie(Const.SERVICE_HALL_URL);
    // 智慧学工系统（第二课堂 AnalogLogin 需要其会话）
    const xgxt: string = webview.WebCookieManager.getCookie('https://xgxt.xjau.edu.cn/');
    if (auth.length === 0 && hall.length === 0 && xgxt.length === 0) {
      return;
    }
    const parts: string[] = [];
    if (auth.length > 0) {
      parts.push('authserver.xjau.edu.cn');
      parts.push(auth);
      // CASTGC 同步到 KEY_CAS_TGC（服务大厅登录：冷启动重新从服务大厅打开"新教务系统"刷新用；
      // rememberMe/7天免登录只影响服务端 TGT 有效期，本地持久化不依赖勾选）
      const castgc: string = WebSurface.cookieValueOf(auth, 'CASTGC');
      if (castgc.length > 0) {
        DataStore.put(DataStore.KEY_CAS_TGC, castgc);
      }
    }
    if (hall.length > 0) {
      parts.push('rhmh.xjau.edu.cn');
      parts.push(hall);
    }
    if (xgxt.length > 0) {
      parts.push('xgxt.xjau.edu.cn');
      parts.push(xgxt);
    }
    DataStore.put(DataStore.KEY_SSO_COOKIES, parts.join('\n'));
  }

  /** 从 cookie 串中取指定名称的值（如 CASTGC=xxx; Path=/ → CASTGC 的值） */
  private static cookieValueOf(cookieStr: string, name: string): string {
    const prefix: string = name + '=';
    const pairs: string[] = cookieStr.split(';');
    for (let i = 0; i < pairs.length; i++) {
      const kv: string = pairs[i].trim();
      if (kv.indexOf(prefix) === 0) {
        return kv.substring(prefix.length);
      }
    }
    return '';
  }

  /** 网页版登录成功后：Cookie 回 HttpClient、缓存资料到本地持久化、自动进入主页 */
  private async handleWebLoginSuccess(): Promise<void> {
    this.loggedIn = true;
    // 两种模式最终都落到 jwglxt 页面：
    //  教务系统模式：直接登录 jwxt.xjau.edu.cn/jwglxt/xtgl/login_slogin.html，成功即跳主页；
    //  服务大厅模式：登录 rhmh 服务大厅后由 /sso/jziotlogin 桥接出 jwglxt 会话。
    // 必须读取"教务系统域名"的会话 Cookie：用当前页面 URL（若为 jwxt）兜底到教务系统门户地址，
    // 不能用起始的 AppState.webUrl（可能是 rhmh/jwxt 登录页），否则取不到 jwxt 会话。
    const curUrl: string = this.controller.getUrl();
    const cookieUrl: string = curUrl.indexOf('jwxt.xjau.edu.cn') >= 0 ? curUrl : Const.WEB_PORTAL_URL;
    const cookie: string = webview.WebCookieManager.getCookie(cookieUrl);
    if (cookie.length > 0) {
      HttpClient.setCookie(cookie);
      // 持久化会话 Cookie 以便冷启动自动重登
      DataStore.put(DataStore.KEY_SESSION_COOKIE, cookie);
    }
    // 捕获统一认证/服务大厅会话 Cookie（网页版"服务大厅"登录后，我的页服务大厅/第二课堂保持登录态）
    WebSurface.captureSsoCookies();
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
        // 登录系统：服务大厅模式（网页版登录走 authserver CAS）= 服务大厅登录；教务系统直登 = 教务登录
        DataStore.put(DataStore.KEY_LOGIN_SYSTEM, AppState.webLoginTarget === 'hall' ? 'service' : 'original');
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
          // 功能浏览模式（USE_MOCK）默认断网：不加载真实网页，避免意外联网；
          // 隐藏调试模式（AppState.debugNetwork）开启后允许联网
          if (JwApi.USE_MOCK && !AppState.debugNetwork) {
            this.controller.loadUrl('about:blank');
            return;
          }
          // 校园 SSO 域名注入会话 Cookie（教务系统 + 统一认证/服务大厅；外部链接不注入，避免隐私泄漏）
          if (AppState.webUrl.indexOf('xjau.edu.cn') >= 0) {
            WebSurface.injectCookies(AppState.webUrl);
          }
          this.controller.loadUrl(AppState.webUrl);
          // 把 controller 交给外层（"更多"菜单操作前进后退/刷新/UA/历史等）
          this.onControllerReady(this.controller);
        })
        .onPageEnd(() => {
          const url: string = this.controller.getUrl();
          if (AppState.webLoginMode && !this.loggedIn) {
            // 切换了登录目标：重置桥接标记，按新目标继续
            if (this.lastTarget !== AppState.webLoginTarget) {
              this.bridging = false;
              this.lastTarget = AppState.webLoginTarget;
            }
            // 已到达教务系统主页（脱离登录页）→ 登录成功，读取 jwglxt 会话 Cookie
            const reachedJw: boolean = url.indexOf('login_slogin') < 0 && url.indexOf('jwglxt') >= 0;
            // 服务大厅模式：到达服务大厅内容页（非 CAS 登录页）→ 跳转 /sso/jziotlogin 桥接教务系统
            if (!reachedJw && AppState.webLoginTarget === 'hall' && !this.bridging &&
                url.indexOf('rhmh.xjau.edu.cn') >= 0 && url.indexOf('authserver') < 0) {
              this.bridging = true;
              this.controller.loadUrl(Const.JW_SSO_BRIDGE_URL);
            } else if (reachedJw) {
              this.handleWebLoginSuccess();
            }
          }
          // 页面加载完成：读取网页标题回传（让"外部链接"页标题栏自动变成网页标题）
          const pageTitle: string = this.controller.getTitle();
          if (pageTitle.length > 0) {
            this.onTitleChange(pageTitle);
          }
          // 浏览校园 SSO 页面（服务大厅/智慧学工/第二课堂等）时刷新捕获的会话 Cookie，
          // 保证下次「服务大厅/第二课堂」入口打开即是登录态
          if (url.indexOf('xjau.edu.cn') >= 0) {
            WebSurface.captureSsoCookies();
          }
          // 记录到应用级共享历史（所有网页场景互通：教务系统/新闻网页/外部链接）
          if (url.length > 0 && url.indexOf('about:blank') < 0 && url.indexOf('resource://') < 0) {
            AppState.recordWebHistory(pageTitle, url);
          }
        })
    }
    .width('100%')
    .height('100%')
  }
}
