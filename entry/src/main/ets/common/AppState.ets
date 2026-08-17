/**
 * 全局运行时状态（登录态、当前学期、路由栈、页面间传值）
 */
import { common } from '@kit.AbilityKit';
import { CourseItem, NoticeItem, TermInfo, UserProfile } from '../model/Models';
import { DateUtil } from './DateUtil';
import { DataStore } from './DataStore';

/** 共享网页历史条目（title + url，应用级互通） */
export class SharedHistoryItem {
  title: string = '';
  url: string = '';
}

export class AppState {
  /** 全局 Ability Context（EntryAbility 注入，供文件缓存等使用） */
  static context: common.Context | null = null;
  /** 在系统浏览器中打开外部链接（隐私协议等 Web 内点击外链时使用） */
  static openExternalLink(url: string): void {
    if (AppState.context === null) {
      return;
    }
    try {
      (AppState.context as common.UIAbilityContext).openLink(url);
    } catch (e) {
      // 忽略：无可用浏览器时静默失败
    }
  }
  /** 全局路由栈，二级页面统一从这里 push/pop */
  static stack: NavPathStack = new NavPathStack();
  /** 当前学期（默认最新学年第一学期，首页/课程表/考试/成绩一致） */
  static term: TermInfo = DateUtil.buildLatestTerm();
  /** 功能浏览模式（USE_MOCK）下当前周次：>0 时首页/课程表用此值替代 DateUtil.weekOfTerm（让 mock 始终有数据） */
  static mockCurrentWeek: number = 0;
  /** 学期切换监听器（首页顶栏切换后广播，课程表/成绩页注册后自动同步，避免依赖 @Watch 触发） */
  private static termListenerKeys: string[] = [];
  private static termListeners: Array<() => void> = [];
  /**
   * 桌面卡片跳转意图（EntryAbility.onCreate/onNewWant 写入）。
   *  - 'home'      → 进入应用首页（不切换任何页面）
   *  - 'exam-pick' → 进入应用，自动切到"考试安排"页并弹出"选择要倒计时的考试"弹窗
   *  - 'schedule'  → 进入应用，自动切到"课程表"页（桌面课程预告卡片点击跳转）
   * 处理一次后清空，避免重复触发。
   */
  static openPageRequest: string = '';

  /**
   * 主页"重登"按钮触发回调（Index 注入）。
   * HomeView 检测到校历为空时显示重登按钮，点击后调用此回调。
   * 回调内部负责：弹"真正重新登录"提示 + 重新登录 + 跳回主页。
   */
  static onForceRelogin: (() => void) | null = null;
  /** 注册学期切换监听器（key 去重，组件 aboutToAppear 注册） */
  static registerTermListener(key: string, listener: () => void): void {
    const idx: number = AppState.termListenerKeys.indexOf(key);
    if (idx >= 0) {
      AppState.termListeners[idx] = listener;
    } else {
      AppState.termListenerKeys.push(key);
      AppState.termListeners.push(listener);
    }
  }
  /** 广播学期已切换（JwApi.setTerm 后由首页调用，同步课程表/成绩页） */
  static notifyTermSwitched(): void {
    for (const l of AppState.termListeners) {
      l();
    }
  }
  /** 登录后的学生信息 */
  static profile: UserProfile | null = null;
  /** 登录账号 */
  static account: string = '';
  /** 通知详情页要展示的数据 */
  static currentNotice: NoticeItem | null = null;
  /** 新闻详情页要加载的 URL */
  static currentNewsUrl: string = '';
  /** 搜索结果页要搜索的关键词 */
  static currentSearchKeyword: string = '';
  /** 应用内 WebView 要打开的网址与标题（网页版教务系统 / 找回密码 共用） */
  static webUrl: string = '';
  static webTitle: string = '';
  /** 应用级共享网页浏览历史（所有 WebSurface 场景互通：教务系统/新闻网页/外部链接） */
  static webHistory: SharedHistoryItem[] = [];
  /** 共享历史上限（超出移除最旧） */
  static readonly WEB_HISTORY_LIMIT: number = 100;
  /** 是否已从 DataStore 恢复历史（懒加载标记） */
  private static webHistoryLoaded: boolean = false;

  /** 确保历史已从本地恢复（首次访问时从 DataStore 加载，重启后保留） */
  private static ensureWebHistoryLoaded(): void {
    if (AppState.webHistoryLoaded) {
      return;
    }
    AppState.webHistoryLoaded = true;
    const raw: string = DataStore.loadWebHistoryJson();
    if (raw.length === 0) {
      return;
    }
    try {
      const parsed: SharedHistoryItem[] = JSON.parse(raw) as SharedHistoryItem[];
      if (Array.isArray(parsed)) {
        AppState.webHistory = parsed;
      }
    } catch (e) {
      // 解析失败保持空历史
    }
  }

  /** 获取共享网页历史（确保已从本地恢复） */
  static getWebHistory(): SharedHistoryItem[] {
    AppState.ensureWebHistoryLoaded();
    return AppState.webHistory;
  }

  /** 记录一条网页访问历史（同 url 去重置顶；title 为空时保留旧标题），变更后立即落盘 */
  static recordWebHistory(title: string, url: string): void {
    if (url.length === 0) {
      return;
    }
    AppState.ensureWebHistoryLoaded();
    const list: SharedHistoryItem[] = AppState.webHistory;
    const idx: number = list.findIndex((it: SharedHistoryItem) => it.url === url);
    if (idx >= 0) {
      const old: SharedHistoryItem = list[idx];
      old.title = title.length > 0 ? title : old.title;
      list.splice(idx, 1);
      list.unshift(old);
    } else {
      const item: SharedHistoryItem = new SharedHistoryItem();
      item.title = title.length > 0 ? title : '未命名页面';
      item.url = url;
      list.unshift(item);
    }
    if (list.length > AppState.WEB_HISTORY_LIMIT) {
      list.splice(AppState.WEB_HISTORY_LIMIT);
    }
    // 持久化：重启后历史保留
    DataStore.saveWebHistoryJson(JSON.stringify(list));
  }

  /** 清空共享网页历史（内存 + 本地） */
  static clearWebHistory(): void {
    AppState.ensureWebHistoryLoaded();
    AppState.webHistory = [];
    DataStore.saveWebHistoryJson('');
  }
  /** 是否以"网页版登录"方式打开 WebView（登录成功需自动进入主页） */
  static webLoginMode: boolean = false;
  /** 网页版登录成功后的回调（由 LoginView 注入） */
  static onWebLogin: (() => void) | null = null;
  /** 隐藏调试模式：功能浏览（USE_MOCK）下允许联网（关于页连点图标 5 次 + 密码 admin 开启）。
   *  用 AppStorage 存储，页面通过 @StorageProp('debugNetwork') 响应式监听（如 NewsPage 开调试后自动加载）。 */
  static get debugNetwork(): boolean {
    return AppStorage.get<boolean>('debugNetwork') ?? false;
  }
  static set debugNetwork(value: boolean) {
    AppStorage.setOrCreate('debugNetwork', value);
  }
  /** 日志调试模式（真实登录下开启）：开启后收集各功能模块使用日志，用于排查 bug。
   *  用 AppStorage 存储，页面可通过 @StorageProp('logEnabled') 响应式监听。 */
  static get logEnabled(): boolean {
    return AppStorage.get<boolean>('logEnabled') ?? false;
  }
  static set logEnabled(value: boolean) {
    AppStorage.setOrCreate('logEnabled', value);
  }
  /** 首页"下次课"点击后，切到课程表要自动打开的课程（ScheduleView 打开详情后清空） */
  static pendingCourse: CourseItem | null = null;

  /** 当前用户显示名（姓+名，缺省返回"同学"） */
  static displayName(): string {
    return AppState.profile !== null ? AppState.profile.name : '同学';
  }

  /** 头像占位字符（取姓名第一个字符） */
  static avatarText(): string {
    const name: string = AppState.displayName();
    return name.length > 0 ? name.substring(name.length - 2) : '同学';
  }

  /** 当前登录学号，未登录返回空串 */
  static studentId(): string {
    return AppState.profile !== null ? AppState.profile.studentId : AppState.account;
  }

  /** 清空全局状态（退出登录/清空数据时调用） */
  static clear(): void {
    AppState.profile = null;
    AppState.account = '';
    AppState.currentNotice = null;
  }
}
