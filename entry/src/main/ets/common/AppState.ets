/**
 * 全局运行时状态（登录态、当前学期、路由栈、页面间传值）
 */
import { common } from '@kit.AbilityKit';
import { CourseItem, NoticeItem, TermInfo, UserProfile } from '../model/Models';
import { DateUtil } from './DateUtil';

export class AppState {
  /** 全局 Ability Context（EntryAbility 注入，供文件缓存等使用） */
  static context: common.Context | null = null;
  /** 全局路由栈，二级页面统一从这里 push/pop */
  static stack: NavPathStack = new NavPathStack();
  /** 当前学期（默认最新学年第一学期，首页/课程表/考试/成绩一致） */
  static term: TermInfo = DateUtil.buildLatestTerm();
  /** 功能浏览模式（USE_MOCK）下当前周次：>0 时首页/课程表用此值替代 DateUtil.weekOfTerm（让 mock 始终有数据） */
  static mockCurrentWeek: number = 0;
  /** 学期切换监听器（首页顶栏切换后广播，课程表/成绩页注册后自动同步，避免依赖 @Watch 触发） */
  private static termListenerKeys: string[] = [];
  private static termListeners: Array<() => void> = [];
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
  /** 应用内 WebView 要打开的网址与标题（网页版教务系统 / 找回密码 共用） */
  static webUrl: string = '';
  static webTitle: string = '';
  /** 是否以"网页版登录"方式打开 WebView（登录成功需自动进入主页） */
  static webLoginMode: boolean = false;
  /** 网页版登录成功后的回调（由 LoginView 注入） */
  static onWebLogin: (() => void) | null = null;
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
