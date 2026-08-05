/**
 * 应用入口：未登录 -> 登录页，已登录 -> 主框架
 */
import { JwApi } from '../api/JwApi';
import { DataStore } from '../common/DataStore';
import { AppState } from '../common/AppState';
import { LoginView } from '../view/LoginView';
import { MainView } from '../view/MainView';
import { UserProfile } from '../model/Models';

@Entry
@Component
struct Index {
  @State logged: boolean = false;

  /** 页面出现：初始化 AppStorage 兜底值并加载主界面 */
  aboutToAppear(): void {
    // 启动时如果有缓存资料，先恢复登录态（秒进主页，后台刷新数据）。
    // 注意：只有真实登录（非功能浏览）才后台刷新；功能浏览直接用本地 mock 数据。
    const cachedProfile: UserProfile | null = DataStore.loadCachedProfile();
    if (cachedProfile !== null && cachedProfile.name.length > 0 && cachedProfile.studentId !== 'demo') {
      AppState.profile = cachedProfile;
      AppState.account = cachedProfile.studentId;
      this.logged = true;
      // 后台静默刷新：重新获取一遍数据并存本地
      JwApi.USE_MOCK = false;
      JwApi.refreshAll().then(() => {
        // 刷新完成（数据已写入缓存）
      }).catch(() => {
        // 网络异常时继续用缓存
      });
    }
  }

  build() {
    Stack() {
      if (this.logged) {
        MainView({
          onLogout: () => {
            this.logged = false;
          }
        })
      } else {
        LoginView({
          onSuccess: () => {
            this.logged = true;
            // 登录成功后：后台静默刷新数据并存本地（不阻塞进入主页）。
            // 注意：功能浏览(mock)模式下 USE_MOCK=true，绝不能强制置 false，
            // 否则页面会走真实网络请求导致一直转圈。只有真实登录才刷新。
            if (!JwApi.USE_MOCK) {
              JwApi.refreshAll().then(() => {
                // 数据已刷新
              }).catch(() => {
                // 忽略
              });
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
