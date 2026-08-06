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
