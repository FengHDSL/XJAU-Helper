/**
 * 空对象常量：避免在 UI 里做 null 判空导致的类型收窄问题
 */
import { AcademicReport, CourseItem, NoticeItem } from './Models';

export const EMPTY_REPORT: AcademicReport = {
  totalRequired: 0,
  totalEarned: 0,
  gpa: 0,
  rank: 0,
  classSize: 0,
  failedCount: 0,
  unearnedCount: 0,
  studyingCount: 0,
  outsideCount: 0,
  passRate: 0,
  categories: [],
  warnings: [],
  gpaTrend: []
};

export const EMPTY_COURSE: CourseItem = {
  id: '',
  name: '',
  teacher: '',
  location: '',
  weekday: 1,
  startSection: 1,
  endSection: 1,
  weeks: [],
  weeksText: '',
  courseType: '',
  credit: 0,
  colorIndex: 0
};

export const EMPTY_NOTICE: NoticeItem = {
  id: '',
  title: '',
  source: '',
  date: '',
  tag: '',
  isTop: false,
  read: true,
  summary: '',
  content: '',
  url: ''
};
