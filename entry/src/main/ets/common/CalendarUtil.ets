/**
 * 日历工具：把考试安排写入系统日历（HarmonyOS Calendar Kit）
 *
 * 需要权限：ohos.permission.READ_CALENDAR / ohos.permission.WRITE_CALENDAR
 * 首次调用时会在界面上向用户申请授权；授权失败或设备不支持时给出 Toast 提示，不崩溃。
 */
import { abilityAccessCtrl, common, PermissionRequestResult, Permissions } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { calendarManager } from '@kit.CalendarKit';
import { promptAction } from '@kit.ArkUI';
import { DateUtil } from './DateUtil';
import { ExamItem, SectionInfo } from '../model/Models';

const CALENDAR_PERMISSIONS: Permissions[] = [
  'ohos.permission.READ_CALENDAR',
  'ohos.permission.WRITE_CALENDAR'
];

export class CalendarUtil {
  /**
   * 将单场考试写入系统日历。
   * @param exam 考试信息
   * @param context 当前 UIAbility 上下文（用于申请权限与获取日历管理器）
   * @returns 是否成功写入
   */
  static async addExamToCalendar(exam: ExamItem, context: common.UIAbilityContext): Promise<boolean> {
    // 1) 解析起止时间：exam.date(yyyy-MM-dd) + exam.timeRange(HH:mm-HH:mm)
    const range: SectionInfo = CalendarUtil.parseTimeRange(exam.date, exam.timeRange);
    if (range.start <= 0 || range.end <= range.start) {
      promptAction.showToast({ message: '考试时间信息不完整，无法导入' });
      return false;
    }

    // 2) 运行时申请日历读写权限
    const granted: boolean = await CalendarUtil.ensurePermission(context);
    if (!granted) {
      promptAction.showToast({ message: '未授予日历权限，无法导入' });
      return false;
    }

    // 3) 构造日程并写入系统日历
    try {
      const mgr: calendarManager.CalendarManager = calendarManager.getCalendarManager(context);
      const calendar: calendarManager.Calendar = await mgr.getCalendar();
      const event: calendarManager.Event = {
        title: `${exam.courseName}（考试）`,
        type: calendarManager.EventType.NORMAL,
        startTime: range.start,
        endTime: range.end,
        location: { location: exam.location },
        description: `座位号 ${exam.seat} · ${exam.examType} · 监考教师 ${exam.teacher}`,
        reminderTime: [60, 1440]
      };
      await calendar.addEvent(event);
      promptAction.showToast({ message: `已导入《${exam.courseName}》到系统日历` });
      return true;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      promptAction.showToast({ message: `导入失败：${e.message ?? '系统日历不可用'}` });
      return false;
    }
  }

  /** 申请日历权限，全部授权返回 true */
  private static async ensurePermission(context: common.UIAbilityContext): Promise<boolean> {
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result: PermissionRequestResult = await atManager.requestPermissionsFromUser(context, CALENDAR_PERMISSIONS);
      for (const code of result.authResults) {
        if (code !== 0) {
          return false;
        }
      }
      return true;
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      promptAction.showToast({ message: `权限申请失败：${e.message ?? ''}` });
      return false;
    }
  }

  /** 把 "yyyy-MM-dd" + "HH:mm-HH:mm" 解析为起止毫秒时间戳 */
  private static parseTimeRange(date: string, timeRange: string): SectionInfo {
    const parts: string[] = timeRange.split('-');
    if (parts.length < 2) {
      return { start: 0, end: 0 };
    }
    const base: Date = DateUtil.parse(date);
    const start: number = CalendarUtil.atTime(base, parts[0]);
    const end: number = CalendarUtil.atTime(base, parts[1]);
    return { start: start, end: end };
  }

  private static atTime(base: Date, hhmm: string): number {
    const seg: string[] = hhmm.split(':');
    if (seg.length < 2) {
      return 0;
    }
    const h: number = Number.parseInt(seg[0], 10);
    const m: number = Number.parseInt(seg[1], 10);
    return new Date(base.getFullYear(), base.getMonth(), base.getDate(), h, m, 0).getTime();
  }
}
