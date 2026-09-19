/**
 * 全局数据模型定义
 * 说明：ArkTS 要求所有对象字面量都必须有明确的 interface / class 类型，
 * 因此教务系统返回的每一类数据都在这里统一建模，接口层解析后直接产出这些结构。
 */

/** 学期信息 */
export interface TermInfo {
  id: string; // 2025-2026-1
  label: string; // 2025-2026学年 第一学期
  startDate: string; // 开学第一周周一，yyyy-MM-dd
  totalWeeks: number;
}

/** 学生基本信息 */
export interface UserProfile {
  studentId: string;
  name: string;
  college: string;
  major: string;
  className: string;
  grade: string;
  counselor: string;
  eduSystem: string; // 学制
  status: string; // 学籍状态
}

/** 单门课程（课表格子） */
export interface CourseItem {
  id: string;
  name: string;
  teacher: string;
  location: string;
  weekday: number; // 1=周一 ... 7=周日
  startSection: number; // 起始节次 1-10
  endSection: number; // 结束节次
  weeks: number[]; // 上课周次列表
  weeksText: string; // 1-16周 / 1-16周(单)
  courseType: string; // 必修 / 选修 / 实践
  credit: number;
  colorIndex: number; // 0-7，用于取色板
}

/** 考试安排 */
export interface ExamItem {
  id: string;
  courseName: string;
  date: string; // yyyy-MM-dd
  timeRange: string; // 10:00-12:00
  location: string;
  seat: string;
  examType: string; // 期末考试 / 期中考试 / 补考
  teacher: string;
}

/** 单条成绩 */
export interface ScoreItem {
  id: string;
  courseName: string;
  credit: number;
  score: number; // 百分制分数，-1 表示等级制
  scoreText: string; // 展示用：92 / 优秀
  gradePoint: number; // 绩点
  courseType: string; // 必修 / 选修
  examType: string; // 正常考试 / 补考 / 重修
  teacher: string; // 任课教师
  termId: string;
  kclbmc: string; // 课程类别名称（用于学业页分类映射）
}

/** 某学期成绩汇总 */
export interface TermScore {
  termId: string;
  termLabel: string;
  gpa: number;
  avgScore: number;
  totalCredit: number;
  earnedCredit: number;
  rank: number;
  classSize: number;
  items: ScoreItem[];
}

/** 通知公告 */
export interface NoticeItem {
  id: string;
  title: string;
  source: string; // 教务处 / 学院
  date: string;
  tag: string; // 选课 / 考试 / 教学 / 通知
  isTop: boolean;
  read: boolean;
  summary: string;
  content: string;
  url: string; // 文章链接（教务处官网 jwc.xjau.edu.cn），空表示无外部链接
}

/** 学分类别完成情况 */
export interface CreditCategory {
  name: string;
  required: number;
  earned: number;
}

/** 学业情况总览 */
export interface AcademicReport {
  totalRequired: number;   // 计划总课程门数
  totalEarned: number;     // 已通过门数（含计划外）
  gpa: number;             // 平均学分绩点（直接从教务页读取）
  rank: number;
  classSize: number;
  failedCount: number;     // 计划内未通过门数
  unearnedCount: number;   // 未修门数
  studyingCount: number;   // 在读门数
  outsideCount: number;    // 计划外通过门数
  passRate: number;
  categories: CreditCategory[];
  warnings: string[];
  gpaTrend: TermGpa[];
}

/** 学期 GPA 走势点 */
export interface TermGpa {
  termLabel: string;
  gpa: number;
}

/**
 * 总体成绩统计（移植自参考项目 zhengfang-apk 的「成绩-总体」）：
 * 累计绩点 / 已修学分 / 总课程数 + 成绩分布（优 ≥90、良 ≥80、中 ≥70、及 ≥60 门数）。
 */
export interface OverallGradeStats {
  /** 累计绩点（索引页提取值优先，缺失时按学分加权计算，保留 2 位） */
  gpa: string;
  /** 已修学分（索引页提取优先，缺失时按明细累加，保留 1 位） */
  credits: string;
  /** 总课程数 */
  courseCount: number;
  excellent: number;
  good: number;
  medium: number;
  pass: number;
}

/** 总体成绩结果：统计 + 课程明细 */
export interface OverallGrades {
  stats: OverallGradeStats;
  courses: ScoreItem[];
}

/** 可选教学班（快捷选课列表项） */
export interface SelectableClass {
  /** 课程代码 kch_id */
  kchId: string;
  /** 教学班号 jxb_id */
  jxbId: string;
  /** 加密教学班号 do_jxb_id（选课/退课优先使用） */
  doJxbId: string;
  courseName: string;
  className: string;
  teacher: string;
  time: string;
  location: string;
  credit: string;
  /** 容量上限 */
  capacity: number;
  /** 已选人数 */
  selected: number;
  /** 是否已选 */
  chosen: boolean;
  /**
   * 提交选课时需要合并的**原始参数**（新正方：课程行字段 + 轮次参数；
   * 教学班详情返回后追加教学班行字段）——对应参考项目 `course.raw + section.raw`。
   */
  raw: Record<string, string>;
}

/** 选课轮次（新正方：入口页每个 queryCourse 分类对应一个 scope，参数来自 Display 接口合并） */
export interface SelectScope {
  /** 内部 id（zf-<index>-<kklxdm>） */
  id: string;
  /** 显示名（kklxmc 或类别代码） */
  label: string;
  /** 学年学期（xkxnm-xkxqm，用于展示） */
  term: string;
  /** 该轮次的完整请求参数（隐藏域合并结果，提交列表/选课接口时按白名单取用） */
  params: Record<string, string>;
}


/** 已选课程（快捷选课 - 已选列表；xkxnm/xkxqm 供退选提交使用） */
export interface SelectedCourseItem {
  kchId: string;
  jxbId: string;
  doJxbId: string;
  courseName: string;
  className: string;
  teacher: string;
  time: string;
  location: string;
  credit: string;
  /** 选课学年（xkxnm） */
  xkxnm: string;
  /** 选课学期（xkxqm） */
  xkxqm: string;
}

/** 选课首页隐藏参数（xkkz 等），供课程查询/选课/退课复用 */
export interface SelectContext {
  /** 轮次控制 ID（正方 V9 字段名为 xkkz_xh，旧版为 xkkz_id） */
  xkkzId: string;
  /** 轮次控制字段名（'xkkz_id' 或 'xkkz_xh'） */
  xkkzKey: string;
  kklxdm: string;
  njdmId: string;
  zyhId: string;
  jgId: string;
  xqhId: string;
  xkxnm: string;
  xkxqm: string;
  xklc: string;
  rwlx: string;
}

/**
 * 抢课目标（队列项）—— 对应参考项目 AcademicGrabItem：
 * 记录目标课程/教学班 + 匹配模式 + 运行状态，支持多个目标排队依次/并行抢。
 */
export interface GrabTarget {
  /** 课程代码（唯一键之一） */
  kchId: string;
  courseName: string;
  teacher: string;
  time: string;
  /** 教学班号（精确模式命中该教学班） */
  jxbId: string;
  /** 加密教学班号（优先用于提交） */
  doJxbId: string;
  /** 是否参与抢课 */
  enabled: boolean;
  /** 状态：waiting=待抢 / success=成功 / failed=失败 */
  status: string;
  /** 已尝试轮次 */
  attempts: number;
  /**
   * 匹配模式：
   *  - 'exact' 精确模式（只抢指定教学班）
   *  - 'fuzzy' 模糊匹配（按课程名，任意教学班有空位就抢 —— 对应参考项目模糊匹配/捡漏）
   */
  matchMode: string;
}

/** 抢课运行策略（定时/并发/捡漏）—— 对应参考项目 GrabRunPolicy */
export interface GrabPolicy {
  /** 轮询间隔（秒，支持 0.5 起） */
  intervalSec: number;
  /** 最大轮次（0 = 不限） */
  maxRounds: number;
  /** 抢到一门后是否继续抢队列中的其它课程 */
  continueAfterSuccess: boolean;
  /** 并行处理的目标数（1=顺序模式；2/3=并行模式，对应参考项目 parallel mode） */
  parallelWorkers: number;
  /** 延时开始秒数（0=立即开始，对应参考项目"定时启动"） */
  delaySec: number;
  /**
   * 捡漏模式：轮询中若发现"已选人数比上一轮减少"（有人退课），立即尝试抢占，
   * 不再等下一个间隔。对应参考项目 fuzzy/捡漏的 selected < lastSelected 判定。
   */
  leakMode: boolean;
}

/** 教学班筛选条件（对应参考项目 AcademicCourseFilter） */
export interface ClassFilter {
  teacher: string;
  time: string;
  location: string;
  credit: string;
  onlyAvailable: boolean;
}




/** 登录结果 */
export interface LoginResult {
  success: boolean;
  message: string;
  profile: UserProfile | null;
  needCaptcha: boolean; // 服务端是否要求验证码（由登录失败响应判断）
}

/** 首页快捷入口 */
export interface QuickEntry {
  key: string;
  title: string;
  icon: string;
  color: Resource;
}

/** 今日课程（带节次时间） */
export interface TodayCourse {
  course: CourseItem;
  timeRange: string;
  finished: boolean;
  ongoing: boolean;
}

/** 周次解析结果（正方 zcd 字段 -> 周次数组 + 原文） */
export interface WeekInfo {
  weeks: number[];
  text: string;
}

/** 节次解析结果（正方 jcs 字段 -> 起始/结束节次） */
export interface SectionInfo {
  start: number;
  end: number;
}

/** 空闲教室查询条件项（正方 kxjs：校区/楼号/场地类型） */
export interface EmptyRoomCondition {
  code: string;
  name: string;
}

/** 空闲教室结果项（字段名与 web kxcdlb.js colModel 对齐） */
export interface EmptyRoomItem {
  cdbh: string;          // 场地编号
  cdmc: string;          // 场地名称
  xqmc: string;          // 校区
  jxlmc: string;         // 楼号
  lch: string;           // 楼层
  cdlbmc: string;        // 场地类别（一级）
  cdejlbmc: string;      // 场地二级类别
  sjzws: string;         // 座位数
  sybmmc: string;        // 使用部门
  sybj: string;          // 使用班级
  bz: string;            // 场地备注
  sfkfy: string;         // 是否可借用（"1"/"是"=可借用）
  time: string;          // 空闲时间（按周次/星期/节次计算）
}

/** 空闲教室查询条件集合（校区/楼号/场地类型） */
export interface EmptyRoomConditions {
  campus: EmptyRoomCondition[];
  building: EmptyRoomCondition[];
  roomType: EmptyRoomCondition[];
}

/** 空闲教室查询参数（周次/星期/节次支持多选） */
export interface EmptyRoomQueryParams {
  termId: string;
  campus: string;        // xqh_id
  building: string;      // lh
  roomType: string;      // cdlb_id 场地类别（一级）
  roomSubType: string;   // cdejlb_id 场地二级类别（选完一级才有）
  seatMin: string;       // qszws 座位数下限
  seatMax: string;       // jszws 座位数上限
  roomName: string;      // cdmc 场地名称
  weeks: number[];
  weekdays: number[];
  sections: number[];
}

/** 空闲教室查询结果（含服务端提示消息） */
export interface EmptyRoomResult {
  rooms: EmptyRoomItem[];
  message: string;
}
