/**
 * 应用入口：未登录 -> 登录页，已登录 -> 主框架
 */
import { JwApi } from '../api/JwApi';
import { HttpClient } from '../api/HttpClient';
import { DataStore } from '../common/DataStore';
import { AppState } from '../common/AppState';
import { LoginView } from '../view/LoginView';
import { MainView } from '../view/MainView';
import { TermInfo, UserProfile } from '../model/Models';
import { promptAction } from '@kit.ArkUI';

@Entry
@Component
struct Index {
  @State logged: boolean = false;
  @State autoRelogin: boolean = false;
  /** 前往登录页模式（不退出登录，仅跳转登录界面，可从登录页返回首页） */
  @State showLoginOnly: boolean = false;

  /** 页面出现：初始化 AppStorage 兜底值并加载主界面 */
  aboutToAppear(): void {
    // 功能浏览模式（USE_MOCK=true）：学期默认即最新学年第一学期（AppState.term），
    // 这里仅固定展示周次为第二周，确保所有功能都有数据。同时启用 HttpClient 离线模式，
    // 禁止所有真实网络请求，避免意外访问教务系统泄露数据。
    if (JwApi.USE_MOCK) {
      AppState.mockCurrentWeek = 2;
      HttpClient.setOfflineMode(true);
    } else {
      HttpClient.setOfflineMode(false);
    }
    // 启动时优先恢复用户上次选择的学期（全局设置）
    const termId: string = DataStore.get(DataStore.KEY_DS_TERM);
    if (termId.length > 0) {
      const terms: TermInfo[] = JwApi.buildLocalTerms();
      for (const t of terms) {
        if (t.id === termId) {
          JwApi.setTerm(t);
          break;
        }
      }
    }
    // 自动重登凭据存在：进入 LoginView 自动重登模式（遮罩+加载符号+静默登录）。
    // 10 秒超时兜底：自动登录失败/无网时仍进入主页（用缓存数据），避免用户卡在登录页。
    const autoAcct: string = DataStore.get(DataStore.KEY_AUTO_ACCOUNT);
    const autoPwd: string = DataStore.get(DataStore.KEY_AUTO_PWD);
    if (autoAcct.length > 0 && autoPwd.length > 0) {
      this.autoRelogin = true;
      setTimeout(() => {
        if (!this.logged) {
          promptAction.showToast({ message: '登录失败，请稍后再试', duration: 2000 });
          this.logged = true; // 进入主页，使用本地缓存数据
        }
      }, 10000);
      return;
    }
    // 恢复网页登录的会话 Cookie（如果有缓存资料但没有 HttpClient cookie，从 DataStore 加载）
    const sessionCookie: string = DataStore.get(DataStore.KEY_SESSION_COOKIE);
    if (sessionCookie.length > 0 && HttpClient.getCookie().length === 0) {
      HttpClient.setCookie(sessionCookie);
    }
    // 启动时如果有缓存资料，先验证会话有效性再恢复登录态。
    // 会话 cookie 可能已过期（服务端动态刷新），失效时清除并回登录页让用户重新登录。
    const cachedProfile: UserProfile | null = JwApi.USE_MOCK ? null : DataStore.loadCachedProfile();
    if (cachedProfile !== null && cachedProfile.name.length > 0 && cachedProfile.studentId !== 'demo') {
      // 异步验证会话（aboutToAppear 不能直接 await，用 then 链）
      const doLogin: () => void = () => {
        AppState.profile = cachedProfile;
        AppState.account = cachedProfile.studentId;
        this.logged = true;
        JwApi.USE_MOCK = false;
        HttpClient.setOfflineMode(false);
        JwApi.refreshAll().catch(() => {});
      };
      if (sessionCookie.length > 0) {
        JwApi.verifySession().then((valid: boolean) => {
          if (valid) {
            doLogin();
          } else {
            // 会话失效：清除过期数据，回到登录页
            DataStore.put(DataStore.KEY_SESSION_COOKIE, '');
            HttpClient.clearCookie();
            DataStore.cacheProfile(null);
          }
        }).catch(() => {
          // 网络不通也直接进主页（用缓存数据）
          doLogin();
        });
      } else {
        doLogin();
      }
    }
  }

  build() {
    Stack() {
      if (this.logged) {
        if (this.showLoginOnly) {
          // 前往登录页（不退出）：登录页左上角显示返回按钮，可返回首页
          LoginView({
            showBack: true,
            autoRelogin: false,
            onBack: () => {
              this.showLoginOnly = false;
            },
            onSuccess: () => {
              // 在登录页完成登录后返回主页
              this.showLoginOnly = false;
              if (!JwApi.USE_MOCK) {
                HttpClient.setOfflineMode(false);
                JwApi.refreshAll().catch(() => {});
              } else {
                HttpClient.setOfflineMode(true);
              }
            }
          })
        } else {
          MainView({
            onLogout: () => {
              this.logged = false;
            },
            onGotoLogin: () => {
              this.showLoginOnly = true;
            }
          })
        }
      } else {
        LoginView({
          autoRelogin: this.autoRelogin,
          onSuccess: () => {
            this.logged = true;
            this.autoRelogin = false;
            // 登录成功后：如果是真实登录（USE_MOCK=false）才开启网络、刷新数据
            if (!JwApi.USE_MOCK) {
              HttpClient.setOfflineMode(false);
              JwApi.refreshAll().then(() => {
                // 数据已刷新
              }).catch(() => {
                // 忽略
              });
            } else {
              // 功能浏览模式：确保离线模式开启
              HttpClient.setOfflineMode(true);
            }
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
