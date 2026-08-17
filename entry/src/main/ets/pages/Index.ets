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
  /** 主页"重登"按钮触发时的全局遮罩（与 LoginView 自动重登共用 loading 效果） */
  @State forceReloginLoading: boolean = false;
  /** 系统深色模式（功能浏览水印颜色适配） */
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 功能浏览水印（进入功能浏览模式 5 秒后强制显示） */
  @State mockWatermark: boolean = false;

  /** 进入功能浏览模式后：延迟 5 秒显示全屏水印 */
  private scheduleMockWatermark(): void {
    if (JwApi.USE_MOCK) {
      setTimeout(() => {
        this.mockWatermark = true;
      }, 5000);
    }
  }

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
    // 「手动重登模式」用户选择不自动重新登录：跳过自动重登，直接用缓存进主页。
    const autoAcct: string = DataStore.get(DataStore.KEY_AUTO_ACCOUNT);
    const autoPwd: string = DataStore.get(DataStore.KEY_AUTO_PWD);
    const loginMode: string = DataStore.getLoginMode();
    if (autoAcct.length > 0 && autoPwd.length > 0 && loginMode !== 'legacy') {
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
    // 启动时如果有缓存资料，先恢复登录态（手动重登模式 / 无自动凭据 / 凭据已用）：
    // 手动重登模式不刷新会话（用户可手动点"重登"），其他情况照常刷新。
    const cachedProfile: UserProfile | null = JwApi.USE_MOCK ? null : DataStore.loadCachedProfile();
    if (cachedProfile !== null && cachedProfile.name.length > 0 && cachedProfile.studentId !== 'demo') {
      AppState.profile = cachedProfile;
      AppState.account = cachedProfile.studentId;
      this.logged = true;
      JwApi.USE_MOCK = false;
      HttpClient.setOfflineMode(false);
      if (loginMode !== 'legacy') {
        JwApi.refreshAll().catch(() => {});
      }
    }
    // 注册主页"重登"按钮回调（HomeView 在 aboutToAppear 触发）
    AppState.onForceRelogin = () => {
      this.forceRelogin();
    };
  }

  /**
   * 主页"重登"按钮：弹"真正重新登录"确认对话框，
   * 用户确认后切换到 LoginView 自动重登模式（遮罩+静默登录），
   * 登录成功回到主页 + 刷新数据；登录失败/超时兜底回主页用缓存。
   */
  private forceRelogin(): void {
    promptAction.showDialog({
      title: '真正重新登录',
      message: '将使用保存的账号密码重新登录教务系统，登录期间不允许操作其他功能。',
      buttons: [
        { text: '取消', color: '#888888' },
        { text: '重新登录', color: '#FF9800' }
      ]
    }).then((r: promptAction.ShowDialogSuccessResponse) => {
      if (r.index !== 1) {
        return;
      }
      // 用户确认：切到登录页自动重登模式
      this.autoRelogin = true;
      this.showLoginOnly = true;
      this.forceReloginLoading = true;
      // 10 秒超时兜底
      setTimeout(() => {
        if (this.forceReloginLoading) {
          this.forceReloginLoading = false;
          promptAction.showToast({ message: '登录失败，请稍后再试', duration: 2000 });
          this.showLoginOnly = false;
        }
      }, 10000);
    }).catch(() => {
      // 弹窗失败时不做任何事
    });
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
              this.scheduleMockWatermark();
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
            this.forceReloginLoading = false;
            this.showLoginOnly = false;
            this.scheduleMockWatermark();
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
      // 功能浏览模式：全屏淡水印（进入功能浏览模式 5 秒后强制显示；每字单独旋转保证平铺铺满无死角；不拦截触摸）
      if (this.mockWatermark) {
        Stack() {
          // 平铺多行水印：Column/Row 不旋转（正常铺满全屏），每个 Text 自身旋转 -28°，避免整块旋转露白
          Column() {
            ForEach([0, 1, 2, 3, 4, 5, 6, 7, 8], (row: number) => {
              Row() {
                ForEach([0, 1, 2, 3, 4], (col: number) => {
                  Text('功能浏览模式，内容非真实信息')
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.isDarkMode ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.10)')
                    .rotate({ angle: -28 })
                    .margin({ left: 34, right: 34, top: 30, bottom: 30 })
                    .hitTestBehavior(HitTestMode.None)
                }, (col: number) => `${col}`)
              }
              .hitTestBehavior(HitTestMode.None)
            }, (row: number) => `${row}`)
          }
          .width('100%')
          .hitTestBehavior(HitTestMode.None)
        }
        .width('100%')
        .height('100%')
        .hitTestBehavior(HitTestMode.None)
      }
      // "重登" 全局遮罩：叠加在主页之上，居中提示正在重新登录
      if (this.forceReloginLoading) {
        Column() {
          LoadingProgress()
            .width(42)
            .height(42)
            .color($r('app.color.brand_on'))
          Text('正在重新登录…')
            .fontSize(14)
            .fontColor($r('app.color.brand_on'))
            .margin({ top: 14 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .backgroundColor('#CC079841')
        .onClick(() => {
          // 拦截点击
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}
