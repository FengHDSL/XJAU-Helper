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

  /** 教务系统网址（应用内 WebView 打开） */
  static readonly WEB_PORTAL_URL: string = 'https://jwxt.xjau.edu.cn/jwglxt/xtgl/index_initMenu.html';
  /** 教务系统登录页（应用内 WebView 打开，用于"网页版直接登录"的兜底方案） */
  static readonly WEB_LOGIN_URL: string = 'https://jwxt.xjau.edu.cn/jwglxt/xtgl/login_slogin.html';
  /** 找回密码页（学校统一身份认证平台，应用内 WebView 打开） */
  static readonly FORGOT_PASSWORD_URL: string = 'https://authserver.xjau.edu.cn/retrieve-password/retrievePassword/index.html#/';
  /**
   * 教务处官网「学期校历」栏目列表（通知取最新两条；校历取最新一条校历文章的 PDF 转换）。
   * 无需登录，页面文章标题形如「2026年秋季学期校历」，链接 /yyyy/MMdd/c3318aXXXXX/page.htm。
   */
  static readonly JWC_LIST_URL: string = 'https://jwc.xjau.edu.cn/jxrl_3318/list.htm';
  /** 教务处官网「课程及学分」：绩点计算方法（成绩页入口 + GPA/平均分计算依据） */
  static readonly JWC_KJXF_URL: string = 'https://jwc.xjau.edu.cn/kcjxf/list.htm';
  /** 正方教学日历端点（实测学生端不可用：方法未定义）。已弃用，校历改用 JWC_LIST_URL。 */
  static readonly TEACHING_CALENDAR_URL: string = '/jwglxt/jxrl/jxrl_cxJxrl.html';
}
