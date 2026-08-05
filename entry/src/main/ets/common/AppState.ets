/**
 * 全局运行时状态（登录态、当前学期、路由栈、页面间传值）
 */
import { NoticeItem, TermInfo, UserProfile } from '../model/Models';
import { DateUtil } from './DateUtil';

export class AppState {
  /** 全局路由栈，二级页面统一从这里 push/pop */
  static stack: NavPathStack = new NavPathStack();
  /** 当前学期 */
  static term: TermInfo = DateUtil.buildCurrentTerm();
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
