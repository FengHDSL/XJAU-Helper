/**
 * 全局常量：作息时间、色板、快捷入口等
 */
import { QuickEntry } from '../model/Models';

/** 一节课的时间段 */
export interface SectionTime {
  index: number;
  start: string;
  end: string;
}

export class Const {
  /** 课表总节次（新疆高校常见的 10 节作息） */
  static readonly SECTION_COUNT: number = 10;

  /** 节次时间表（新疆农业大学官方作息，按老满城/亚心/塔城校区，10 节） */
  static readonly SECTIONS: SectionTime[] = [
    { index: 1, start: '10:00', end: '10:50' },
    { index: 2, start: '11:00', end: '11:50' },
    { index: 3, start: '12:10', end: '13:00' },
    { index: 4, start: '13:10', end: '14:00' },
    { index: 5, start: '15:30', end: '16:20' },
    { index: 6, start: '16:30', end: '17:20' },
    { index: 7, start: '17:40', end: '18:30' },
    { index: 8, start: '18:40', end: '19:30' },
    { index: 9, start: '20:30', end: '21:15' },
    { index: 10, start: '21:25', end: '22:10' }
  ];

  /** 节次所属的时段（上午 / 下午 / 晚上） */
  static readonly SECTION_PERIODS: string[] = [
    '上午', '上午', '上午', '上午',
    '下午', '下午', '下午', '下午',
    '晚上', '晚上'
  ];

  static readonly WEEK_LABELS: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  static readonly WEEK_SHORT: string[] = ['一', '二', '三', '四', '五', '六', '日'];

  /** 课程块背景色板 */
  static readonly COURSE_BG: Resource[] = [
    $r('app.color.course_bg_1'), $r('app.color.course_bg_2'), $r('app.color.course_bg_3'), $r('app.color.course_bg_4'),
    $r('app.color.course_bg_5'), $r('app.color.course_bg_6'), $r('app.color.course_bg_7'), $r('app.color.course_bg_8')
  ];

  /** 课程块文字色板 */
  static readonly COURSE_FG: Resource[] = [
    $r('app.color.course_fg_1'), $r('app.color.course_fg_2'), $r('app.color.course_fg_3'), $r('app.color.course_fg_4'),
    $r('app.color.course_fg_5'), $r('app.color.course_fg_6'), $r('app.color.course_fg_7'), $r('app.color.course_fg_8')
  ];

  /** 首页快捷入口（通知/校历已下放到右上角"消息"入口与日历组件） */
  static readonly QUICK_ENTRIES: QuickEntry[] = [
    { key: 'exam', title: '考试查询', icon: '考试查询', color: $r('app.color.accent_orange') },
    { key: 'academic', title: '学业情况', icon: '学业情况', color: $r('app.color.accent_purple') }
  ];

  /** 页面路由名 */
  static readonly ROUTE_EXAM: string = 'ExamPage';
  static readonly ROUTE_NOTICE: string = 'NoticePage';
  static readonly ROUTE_NOTICE_DETAIL: string = 'NoticeDetailPage';
  static readonly ROUTE_ACADEMIC: string = 'AcademicPage';
  static readonly ROUTE_PRIVACY: string = 'PrivacyPage';
  static readonly ROUTE_ABOUT: string = 'AboutPage';
  static readonly ROUTE_EMPTY_ROOM: string = 'KxjsPage';
  static readonly ROUTE_NEWS_DETAIL: string = 'NewsDetailPage';
  static readonly ROUTE_NEWS_FAV: string = 'NewsFavPage';
  static readonly ROUTE_LOG: string = 'LogPage';
  static readonly ROUTE_SEARCH: string = 'SearchResultPage';
  static readonly ROUTE_WEB_PAGE: string = 'WebViewPage';

  /** 教务系统网址（应用内 WebView 打开） */
  static readonly WEB_PORTAL_URL: string = 'https://jwxt.xjau.edu.cn/jwglxt/xtgl/index_initMenu.html';
  /** 教务系统登录页（应用内 WebView 打开，"网页版登录"切换到「教务系统」时使用） */
  static readonly WEB_LOGIN_URL: string = 'https://jwxt.xjau.edu.cn/jwglxt/xtgl/login_slogin.html';
  /** 服务大厅首页（rhmh）—— WebSurface 捕获 rhmh 会话 Cookie 时使用的查询地址 */
  static readonly SERVICE_HALL_URL: string = 'https://rhmh.xjau.edu.cn/default/index.html#/';
  /**
   * 智慧学工（我的页入口）：服务大厅「智慧学工系统」应用入口
   * （ServiceShow?wid=1238430490178043904，用户确认），登录后 SSO 到 xgxt 智慧学工系统。
   */
  static readonly ZHIHUI_XUEGONG_URL: string =
    'https://rhmh.xjau.edu.cn/index.html#/ServiceShow?isMobile=2&wid=1238430490178043904';
  /** 服务大厅→新教务系统 跳转地址（authserver CAS，service=jziotlogin?gid_=...；用户 2026-08-19 提供，服务大厅点开新教务系统的真实地址） */
  static readonly JW_BRIDGE_FROM_HALL_URL: string =
    'https://authserver.xjau.edu.cn/authserver/login?service=http%3A%2F%2Fjwxt.xjau.edu.cn%2Fsso%2Fjziotlogin%3Fgid_%3DTWdOQ25Nbm5POW9pQ0NQQzVUZ3kzc2hxRlNHSFhrY3dvRnZqQ3liMVc0eEJjRERUWk84Sy9wS0ZZYTRwVUZxVkxKSGZEVTlHZ2xOak9veERKQktmSUE9PQ%26amp_sec_version_%3D1%26EMAP_LANG%3Dzh%26THEME%3D';
  /** 服务大厅→教务系统桥接地址：网页版登录"服务大厅"模式登录成功后跳转，换取 jwglxt 会话 */
  static readonly JW_SSO_BRIDGE_URL: string = 'https://jwxt.xjau.edu.cn/sso/jziotlogin';
  /**
   * 服务大厅登录入口（authserver CAS 登录页，service 指向 rhmh）——
   *  "网页版登录"切换到「服务大厅」的目标 URL + 我的页"服务大厅"入口 URL。
   *  登录成功后由 authserver 302 跳到 rhmh.xjau.edu.cn 服务大厅，
   *  再由 WebSurface 自动跳 /sso/jziotlogin 桥接出 jwglxt 会话。
   */
  static readonly CAS_LOGIN_URL: string =
    'https://authserver.xjau.edu.cn/authserver/login?service=https%3A%2F%2Frhmh.xjau.edu.cn%2Flogin';
  /** 找回密码页（学校统一身份认证平台，应用内 WebView 打开） */
  static readonly FORGOT_PASSWORD_URL: string = 'https://authserver.xjau.edu.cn/retrieve-password/retrievePassword/index.html#/';
  /**
   * 教务处官网「学期校历」栏目列表（通知取最新两条；校历取最新一条校历文章的 PDF 转换）。
   * 无需登录，页面文章标题形如「2026年秋季学期校历」，链接 /yyyy/MMdd/c3318aXXXXX/page.htm。
   */
  static readonly JWC_LIST_URL: string = 'https://jwc.xjau.edu.cn/jxrl_3318/list.htm';
  /** 教务处官网「课程及学分」：绩点计算方法（成绩页入口 + GPA/平均分计算依据） */
  static readonly JWC_KJXF_URL: string = 'https://jwc.xjau.edu.cn/kcjxf/list.htm';
}
