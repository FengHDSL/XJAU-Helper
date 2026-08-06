/**
 * 应用入口：未登录 -> 登录页，已登录 -> 主框架
 */
import { JwApi } from '../api/JwApi';
import { DataStore } from '../common/DataStore';
import { AppState } from '../common/AppState';
import { LoginView } from '../view/LoginView';
import { MainView } from '../view/MainView';
import { TermInfo, UserProfile } from '../model/Models';

@Entry
@Component
struct Index {
  @State logged: boolean = false;

  /** 页面出现：初始化 AppStorage 兜底值并加载主界面 */
  aboutToAppear(): void {
    // 功能浏览模式（USE_MOCK=true）：学期默认即最新学年第一学期（AppState.term），
    // 这里仅固定展示周次为第二周，确保所有功能都有数据。
    if (JwApi.USE_MOCK) {
      AppState.mockCurrentWeek = 2;
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
    // 启动时如果有缓存资料，先恢复登录态（秒进主页，后台刷新数据）。
    // 注意：功能浏览模式（USE_MOCK=true）绝不恢复真实登录态，避免真实用户数据泄露到浏览模式。
    const cachedProfile: UserProfile | null = JwApi.USE_MOCK ? null : DataStore.loadCachedProfile();
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
