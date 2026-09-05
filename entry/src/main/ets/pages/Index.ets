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

    // ── 冷启动会话恢复策略（核心：服务大厅登录态在 → 必须先"从服务大厅重新打开新教务系统"再取数据）──
    //  有 CASTGC（服务大厅登录成功且保持登录态）：教务系统会话不可持久化 →
    //    冷启动第一步总是用 CASTGC 桥接（GET /sso/jziotlogin）重新打开"新教务系统"换取全新 jwglxt 会话，
    //    第二步才取数据（refreshAll）。TGC 过期时仅自动重登模式用账号密码走服务大厅补登；手动重登则保留缓存等"重登"。
    //  无 CASTGC（教务登录 RSA）：按重登方式 → 自动重登用账号密码 RSA 直登刷新；手动重登不自动刷新。
    const autoAcct: string = DataStore.get(DataStore.KEY_AUTO_ACCOUNT);
    const autoPwd: string = DataStore.get(DataStore.KEY_AUTO_PWD);
    const loginMode: string = DataStore.getLoginMode();
    const casTgc: string = DataStore.get(DataStore.KEY_CAS_TGC);
    const sessionCookie: string = DataStore.get(DataStore.KEY_SESSION_COOKIE);
    const cachedProfile: UserProfile | null = JwApi.USE_MOCK ? null : DataStore.loadCachedProfile();
    const hasCache: boolean = cachedProfile !== null && cachedProfile.name.length > 0 && cachedProfile.studentId !== 'demo';

    // 已登录过（有缓存资料）：直接进主页（秒开，无闪登录页），后台静默恢复会话并刷新。
    if (hasCache && !JwApi.USE_MOCK) {
      AppState.profile = cachedProfile;
      AppState.account = cachedProfile!.studentId;
      this.logged = true;
      JwApi.USE_MOCK = false;
      HttpClient.setOfflineMode(false);
      // 注册主页"重登"按钮回调（HomeView 在 aboutToAppear 触发）
      AppState.onForceRelogin = () => {
        this.forceRelogin();
      };
      // 会话恢复中：首页数据加载须等待（防止用旧教务会话取数失败）
      AppState.sessionReady = false;
      if (casTgc.length > 0) {
        // 服务大厅登录态在 → 第一步：从服务大厅重新打开"新教务系统"（CASTGC 桥接），第二步：取数据
        JwApi.silentCasRelogin()
          .then((ok: boolean) => {
            if (ok) {
              JwApi.refreshAll().catch(() => {});
            } else if (loginMode !== 'legacy' && autoAcct.length > 0 && autoPwd.length > 0) {
              // 桥接失败（TGC 过期）：仅自动重登模式用账号密码走服务大厅登录补登
              JwApi.login(autoAcct, DataStore.decodePwd(autoPwd), '', 'service')
                .then(() => JwApi.refreshAll().catch(() => {}))
                .catch(() => {});
            }
            // 桥接失败 + 手动重登：保留缓存，等用户点"重登"
            AppState.sessionReady = true;
          })
          .catch(() => {
            JwApi.refreshAll().catch(() => {});
            AppState.sessionReady = true;
          });
      } else {
        // 教务登录（无 TGC）：按重登方式（自动=账号密码 RSA 直登刷新；手动=不自动刷新）
        if (loginMode !== 'legacy') {
          if (autoAcct.length > 0 && autoPwd.length > 0) {
            JwApi.login(autoAcct, DataStore.decodePwd(autoPwd), '', 'original')
              .then(() => {
                JwApi.refreshAll().catch(() => {});
                AppState.sessionReady = true;
              })
              .catch(() => {
                AppState.sessionReady = true;
              });
          } else if (sessionCookie.length > 0) {
            // 无自动凭据时用本地会话 Cookie 恢复
            HttpClient.setCookie(sessionCookie);
            JwApi.refreshAll().catch(() => {});
            AppState.sessionReady = true;
          } else {
            AppState.sessionReady = true;
          }
        } else {
          // 手动重登：不自动刷新，直接放行（首页用缓存展示）
          AppState.sessionReady = true;
        }
      }
      return;
    }

    // 无缓存资料：走账号+密码自动重登（弹登录页遮罩）或手动登录。
    if (autoAcct.length > 0 && autoPwd.length > 0 && loginMode !== 'legacy') {
      this.autoRelogin = true;
      setTimeout(() => {
        if (!this.logged) {
          promptAction.showToast({ message: '登录失败，请稍后再试', duration: 2000 });
          this.logged = true; // 进入主页，使用本地缓存数据
        }
      }, 10000);
      AppState.onForceRelogin = () => {
        this.forceRelogin();
      };
      return;
    }
    // 无任何凭据：手动登录页（注册重登回调即可）
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
    // 识别当前登录系统：服务大厅登录 → 重新从服务大厅登录并自动打开教务系统；教务登录 → 账号密码重登
    const sys: string = DataStore.get(DataStore.KEY_LOGIN_SYSTEM);
    const reloginMsg: string = sys === 'service'
      ? '当前为「服务大厅登录」。将重新从服务大厅登录，并自动打开教务系统刷新数据；登录期间不允许操作其他功能。'
      : '当前为「教务登录」。将使用保存的账号密码重新登录教务系统；登录期间不允许操作其他功能。';
    promptAction.showDialog({
      title: '真正重新登录',
      message: reloginMsg,
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
