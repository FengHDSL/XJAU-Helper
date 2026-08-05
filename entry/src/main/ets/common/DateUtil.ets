/**
 * 日期 / 周次工具
 * 教务类应用的核心是"学期第几周 + 星期几 + 第几节"，这里统一处理。
 */
import { Const } from './Constants';
import { TermInfo } from '../model/Models';

const DAY_MS: number = 24 * 60 * 60 * 1000;

export class DateUtil {
  /** 数字补零（1 -> 01） */
  static pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  /** Date -> yyyy-MM-dd */
  static format(date: Date): string {
    return `${date.getFullYear()}-${DateUtil.pad(date.getMonth() + 1)}-${DateUtil.pad(date.getDate())}`;
  }

  /** Date -> MM月dd日 */
  static formatCn(date: Date): string {
    return `${date.getMonth() + 1}月${date.getDate()}日`;
  }

  /** yyyy-MM-dd -> Date（按本地 0 点） */
  static parse(text: string): Date {
    const parts: string[] = text.split('-');
    const y: number = Number.parseInt(parts[0], 10);
    const m: number = Number.parseInt(parts[1], 10);
    const d: number = Number.parseInt(parts[2], 10);
    return new Date(y, m - 1, d);
  }

  /** 取当天 0 点 */
  static startOfDay(date: Date): Date {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
  }

  /** 相差天数（b - a） */
  static diffDays(a: Date, b: Date): number {
    const ms: number = DateUtil.startOfDay(b).getTime() - DateUtil.startOfDay(a).getTime();
    return Math.round(ms / DAY_MS);
  }

  /** 日期加 N 天（负数即往前推） */
  static addDays(date: Date, days: number): Date {
    return new Date(date.getTime() + days * DAY_MS);
  }

  /** 星期几：1=周一 ... 7=周日 */
  static weekdayOf(date: Date): number {
    const w: number = date.getDay();
    return w === 0 ? 7 : w;
  }

  /** 本周周一 */
  static mondayOf(date: Date): Date {
    return DateUtil.addDays(DateUtil.startOfDay(date), 1 - DateUtil.weekdayOf(date));
  }

  /**
   * 构造"当前学期"。
   * 按真实开学日计算：第一学期 9-01、第二学期次年 3-01，
   * 与教务系统学期（正方 xnm/xqm）一致，保证课表周次正确。
   */
  /** 按当前系统日期构造学期（9月后为第一学期） */
  static buildCurrentTerm(): TermInfo {
    const now: Date = new Date();
    const year: number = now.getFullYear();
    const month: number = now.getMonth() + 1;
    let firstTerm: boolean = month >= 9;
    let beginYear: number = firstTerm ? year : year - 1;
    const startDate: string = firstTerm ? `${year}-09-01` : `${year}-03-01`;
    const label: string = `${beginYear}-${beginYear + 1}学年 ${firstTerm ? '第一学期' : '第二学期'}`;
    return {
      id: `${beginYear}-${beginYear + 1}-${firstTerm ? 1 : 2}`,
      label: label,
      startDate: startDate,
      totalWeeks: 20
    };
  }

  /** 根据学期算出某天是第几周（1 起，未开学返回 0）
   * 以"含 startDate 的那个自然周（Mon-Sun）为第 1 周"为基准，
   * 即使 startDate 不是周一也能正确对应。
   */
  /** 计算某天在学期中的第几周（1 起，未开学返回 0） */
  static weekOfTerm(term: TermInfo, date: Date): number {
    const start: Date = DateUtil.parse(term.startDate);
    const startWeekday: number = DateUtil.weekdayOf(start); // 1=周一 ... 7=周日
    const monday: Date = DateUtil.addDays(start, 1 - startWeekday);
    const days: number = DateUtil.diffDays(monday, date);
    if (days < 0) {
      return 0;
    }
    return Math.floor(days / 7) + 1;
  }

  /** 第 n 周周几的日期（按周一为一周首日的自然周计算，
   * 即使学期 startDate 不是周一也能正确对应）。
   */
  /** 计算第 N 周星期几对应的日期（周一为一周首日） */
  static dateOfWeekDay(term: TermInfo, week: number, weekday: number): Date {
    const start: Date = DateUtil.parse(term.startDate);
    const w0: number = DateUtil.weekdayOf(start); // 1=周一 ... 7=周日
    // 把 startDate 拉回到它所在周的周一，再按周次/星期推算
    const monday: Date = DateUtil.addDays(start, 1 - w0);
    return DateUtil.addDays(monday, (week - 1) * 7 + (weekday - 1));
  }

  /** 拼接节次时间：1-2 节 -> 10:00-11:40 */
  static sectionRange(startSection: number, endSection: number): string {
    const s: number = Math.max(1, Math.min(Const.SECTION_COUNT, startSection));
    const e: number = Math.max(1, Math.min(Const.SECTION_COUNT, endSection));
    return `${Const.SECTIONS[s - 1].start}-${Const.SECTIONS[e - 1].end}`;
  }

  /** 当前时间的分钟数 */
  static minutesOfNow(): number {
    const now: Date = new Date();
    return now.getHours() * 60 + now.getMinutes();
  }

  /** HH:mm -> 分钟数 */
  static minutesOf(hhmm: string): number {
    const parts: string[] = hhmm.split(':');
    return Number.parseInt(parts[0], 10) * 60 + Number.parseInt(parts[1], 10);
  }

  /** 友好的相对天数描述 */
  static relativeDay(target: Date): string {
    const d: number = DateUtil.diffDays(new Date(), target);
    if (d === 0) {
      return '今天';
    }
    if (d === 1) {
      return '明天';
    }
    if (d === 2) {
      return '后天';
    }
    if (d < 0) {
      return `${-d}天前`;
    }
    return `${d}天后`;
  }
}
