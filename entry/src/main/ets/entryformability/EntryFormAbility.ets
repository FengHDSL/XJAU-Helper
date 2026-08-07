/**
 * EntryFormAbility — 桌面卡片数据提供者（移植自 HiXD 的 EntryFormAbility）
 *
 * 数据流：
 *  1) 从 DataStore 读课程/考试缓存
 *  2) 考试倒计时：优先显示用户主动选择的考试（KEY_PICKED_EXAM），
 *     没选就显示最近一场未开始的考试，没有任何考试时显示「示例」卡片
 *  3) 课程预告：解决学期外周次无课程的问题——
 *     - today/tomorrow：按当前周次精确过滤今天/明天的课
 *     - nextDay：学期内找到「今天/明天之外」最近一次有课的日期（避免 today/tomorrow 都没课时卡片空着）
 *     - 学期外（week<1 或 week>totalWeeks）时，nextDay 自动回退为学期第一周第一堂课
 *  4) 全部字段转成 formBindingData 支持的平面 string[]/number[]/number 字段
 */
import { Want } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DataStore } from '../common/DataStore';
import { Const } from '../common/Constants';
import { DateUtil } from '../common/DateUtil';
import { CourseItem, ExamItem } from '../model/Models';

const TAG: string = 'EntryFormAbility';
const DOMAIN: number = 0xFF00;
let viewIndex: number = 0; // 0=today, 1=tomorrow, 2=nextDay（持久化在 Form 进程内）

/** 节次时间表（索引 0 占位，与 Const.SECTIONS 一致） */
const SECTION_TIMES: string[] = [
  '', '10:00-10:50', '11:00-11:50', '12:10-13:00', '13:10-14:00',
  '15:30-16:20', '16:30-17:20', '17:40-18:30', '18:40-19:30', '20:30-21:15', '21:25-22:10'
];

/** 卡片绑定数据结构：全部用平面字段（string[]/number[]/number） */
class FormData {
  // 今天/明天
  todayNames: string[];
  todayTimes: string[];
  todayRooms: string[];
  todayStarts: number[];
  todayCount: number;
  tomorrowNames: string[];
  tomorrowTimes: string[];
  tomorrowRooms: string[];
  tomorrowStarts: number[];
  tomorrowCount: number;
  // 下次有课日（不含今天/明天）
  nextDayNames: string[];
  nextDayTimes: string[];
  nextDayRooms: string[];
  nextDayStarts: number[];
  nextDayCount: number;
  // 周课表（7 天，每天最多 3 门课）— 序列化为 JSON 字符串传卡片
  // 格式: [{n,t,c}, {n,t,c}, ...] （n=课程名, t=时间, c=颜色索引）
  weeklyJson: string;
  // 今日课表：每天 1 个 JSON 字符串，最多 10 门课（与节次数一致）
  // 格式: [{n,t,r,c}, ...] （n=课程名, t=时间, r=教室, c=颜色索引）
  todayJson: string;
  tomorrowJson: string;
  // 标签
  dayLabel: string;
  dayLabelTomorrow: string;
  dayLabelNextDay: string;
  /** 今日日期标签：M月D日 / 周X（今日卡片使用） */
  todayLabel: string;
  // 考试
  examName: string;
  examDays: string;
  examTime: string;
  examLocation: string;
  hasExam: boolean;
  isDemoExam: boolean;
  // 其他
  weekLabel: string;
  dateLabel: string;
  lastRefresh: string;
  isEmpty: boolean;
  currentView: number;

  constructor() {
    this.todayNames = [];
    this.todayTimes = [];
    this.todayRooms = [];
    this.todayStarts = [];
    this.todayCount = 0;
    this.tomorrowNames = [];
    this.tomorrowTimes = [];
    this.tomorrowRooms = [];
    this.tomorrowStarts = [];
    this.tomorrowCount = 0;
    this.nextDayNames = [];
    this.nextDayTimes = [];
    this.nextDayRooms = [];
    this.nextDayStarts = [];
    this.nextDayCount = 0;
    this.weeklyJson = '[]';
    this.todayJson = '[]';
    this.tomorrowJson = '[]';
    this.dayLabel = '今天';
    this.dayLabelTomorrow = '明天';
    this.dayLabelNextDay = '';
    this.todayLabel = '';
    this.examName = '';
    this.examDays = '';
    this.examTime = '';
    this.examLocation = '';
    this.hasExam = false;
    this.isDemoExam = false;
    this.weekLabel = '';
    this.dateLabel = '';
    this.lastRefresh = '';
    this.isEmpty = true;
    this.currentView = 0;
  }
}

/** 本地星期几（1=周一 ... 7=周日） */
function localWeekday(offset: number): number {
  const d: Date = new Date();
  d.setDate(d.getDate() + offset);
  const w: number = d.getDay();
  return w === 0 ? 7 : w;
}

/** 一天的课程并行数组（按起始节次排序） */
class DayCourses {
  names: string[];
  times: string[];
  rooms: string[];
  starts: number[];

  constructor() {
    this.names = [];
    this.times = [];
    this.rooms = [];
    this.starts = [];
  }
}

/**
 * 节次时间范围：与 DateUtil.sectionRange 一致（10:00-11:40 这样的字符串）。
 * 卡片不依赖 DateUtil 是因为 Form 进程无 UI Context 直接调用复杂。
 */
function sectionTime(startSection: number, endSection: number): string {
  const s: string = SECTION_TIMES[startSection] ?? '';
  const eEnd: string = (SECTION_TIMES[endSection] ?? '').split('-')[1] ?? '';
  return eEnd.length > 0 ? `${s.split('-')[0] ?? ''}-${eEnd}` : s;
}

/**
 * 取某天（指定 weekday+周次）的课程。
 * 兼容学期外：week 不在 [1,totalWeeks] 时，回退为周次窗口 [1..totalWeeks] 并集。
 */
function coursesOfDay(list: CourseItem[], weekday: number, cw: number, totalWeeks: number): DayCourses {
  const out: DayCourses = new DayCourses();
  let weeksToMatch: number[];
  if (cw >= 1 && cw <= totalWeeks) {
    weeksToMatch = [cw];
  } else {
    weeksToMatch = [];
    for (let i = 1; i <= totalWeeks; i++) {
      weeksToMatch.push(i);
    }
  }
  const weekSet: Set<number> = new Set(weeksToMatch);
  for (const c of list) {
    if (c.weekday !== weekday) {
      continue;
    }
    let hit: boolean = false;
    for (const w of c.weeks) {
      if (weekSet.has(w)) {
        hit = true;
        break;
      }
    }
    if (!hit) {
      continue;
    }
    out.names.push(c.name);
    out.starts.push(c.startSection);
    out.times.push(sectionTime(c.startSection, c.endSection));
    out.rooms.push(c.location);
  }
  const idx: number[] = out.names.map((_: string, i: number) => i).sort((a: number, b: number) => out.starts[a] - out.starts[b]);
  const res: DayCourses = new DayCourses();
  res.names = idx.map((i: number) => out.names[i]);
  res.starts = idx.map((i: number) => out.starts[i]);
  res.times = idx.map((i: number) => out.times[i]);
  res.rooms = idx.map((i: number) => out.rooms[i]);
  return res;
}

/**
 * 取"今天/明天之外的最近一次有课"的数据。
 * 在学期内沿 (weekday, week) 双层循环找到第一堂课，学期外回退为第一周第一节课。
 */
function coursesOfNextDay(list: CourseItem[], todayW: number, tomorrowW: number, cw: number, totalWeeks: number): DayCourses {
  if (list.length === 0) {
    return new DayCourses();
  }
  // 学期内：先在当前周找 weekday > tomorrow 的课
  if (cw >= 1 && cw <= totalWeeks) {
    for (let w: number = tomorrowW + 1; w <= 7; w++) {
      const out: DayCourses = coursesOfDay(list, w, cw, totalWeeks);
      if (out.names.length > 0) {
        return out;
      }
    }
    // 否则后续周
    for (let wk: number = cw + 1; wk <= totalWeeks; wk++) {
      for (let w: number = 1; w <= 7; w++) {
        const out: DayCourses = coursesOfDay(list, w, wk, totalWeeks);
        if (out.names.length > 0) {
          return out;
        }
      }
    }
  }
  // 学期外或学期内都没找到 → 直接取第一周第一节课（演示用）
  const out: DayCourses = coursesOfDay(list, 1, 1, totalWeeks);
  if (out.names.length > 0) {
    return out;
  }
  // 退而求其次：找所有周里第一个有课的 weekday
  for (let w: number = 1; w <= 7; w++) {
    for (let wk: number = 1; wk <= totalWeeks; wk++) {
      const t: DayCourses = coursesOfDay(list, w, wk, totalWeeks);
      if (t.names.length > 0) {
        return t;
      }
    }
  }
  return new DayCourses();
}

/** 计算 nextDay 对应的日期 */
function nextDayDate(today: Date, tomorrowW: number, list: CourseItem[], cw: number, totalWeeks: number): Date {
  // 学期内
  if (cw >= 1 && cw <= totalWeeks) {
    for (let w: number = tomorrowW + 1; w <= 7; w++) {
      const out: DayCourses = coursesOfDay(list, w, cw, totalWeeks);
      if (out.names.length > 0) {
        return new Date(today.getTime() + (w - tomorrowW + 7 - 7) * 86400000);
      }
    }
    for (let wk: number = cw + 1; wk <= totalWeeks; wk++) {
      for (let w: number = 1; w <= 7; w++) {
        const t: DayCourses = coursesOfDay(list, w, wk, totalWeeks);
        if (t.names.length > 0) {
          // 计算下一周 weekday=w 的日期
          const offset: number = (7 - tomorrowW) + 1 + w - 1 + (wk - cw - 1) * 7;
          return new Date(today.getTime() + offset * 86400000);
        }
      }
    }
  }
  // 学期外：默认 2 周后
  return new Date(today.getTime() + 14 * 86400000);
}

/**
 * 课程名 djb2 hash → 0-7 颜色索引（与 JwApi.colorIndexOf 算法一致，保证卡片与课程表配色统一）
 */
function formColorIndex(name: string): number {
  const key: string = (name ?? '').trim();
  if (key.length === 0) {
    return 0;
  }
  let hash: number = 5381;
  for (let i: number = 0; i < key.length; i++) {
    hash = ((hash << 5) + hash + key.charCodeAt(i)) & 0x7FFFFFFF;
  }
  return hash % 8;
}

/** 转义 JSON 字符串中的双引号与反斜杠 */
function jsonEscape(s: string): string {
  return s.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

/**
 * 一天课程数组 → JSON 字符串：[{n,t,r,c}, ...]（最多 maxItems 条）
 * 用字符串拼接避免 JSON.stringify 引入额外依赖。
 */
function buildDayJson(names: string[], times: string[], rooms: string[], maxItems: number): string {
  const parts: string[] = [];
  const n: number = Math.min(names.length, maxItems);
  for (let i: number = 0; i < n; i++) {
    parts.push(`{"n":"${jsonEscape(names[i] ?? '')}","t":"${jsonEscape(times[i] ?? '')}","r":"${jsonEscape(rooms[i] ?? '')}","c":${formColorIndex(names[i] ?? '')}}`);
  }
  return `[${parts.join(',')}]`;
}

/**
 * 7 天课程数组 → JSON 字符串：[[{n,t,c}*3]*7]
 * 每天最多 maxPerDay 节课，简化版（无教室字段，节省空间）。
 */
function buildWeekJson(days: DayCourses[], maxPerDay: number): string {
  const dayStrs: string[] = [];
  for (let d: number = 0; d < days.length; d++) {
    const day: DayCourses = days[d];
    const parts: string[] = [];
    const n: number = Math.min(day.names.length, maxPerDay);
    for (let i: number = 0; i < n; i++) {
      parts.push(`{"n":"${jsonEscape(day.names[i] ?? '')}","t":"${jsonEscape(day.times[i] ?? '')}","c":${formColorIndex(day.names[i] ?? '')}}`);
    }
    dayStrs.push(`[${parts.join(',')}]`);
  }
  return `[${dayStrs.join(',')}]`;
}

/** 装配卡片数据 */
function buildFormData(view: number): FormData {
  const f: FormData = new FormData();
  f.currentView = view;
  const term = DateUtil.buildCurrentTerm();
  const week: number = DateUtil.weekOfTerm(term, new Date());
  // 学期外：未开学（week<1）或已放假（week>totalWeeks）。桌面卡片一律不显示课程，避免"没开学却显示今天有课"。
  const isVacation: boolean = week < 1 || week > term.totalWeeks;
  if (week < 1) {
    const start: Date = DateUtil.parse(term.startDate);
    const daysToStart: number = DateUtil.diffDays(new Date(), start);
    f.weekLabel = daysToStart > 0 ? `距开学${daysToStart}天` : '即将开学';
  } else if (week > term.totalWeeks) {
    f.weekLabel = '已放假';
  } else {
    f.weekLabel = `第${week}周`;
  }
  f.dateLabel = `今日 ${DateUtil.formatCn(new Date())}`;
  // 今日标签：M月D日 · 周X（例：8月7日 · 周四）
  {
    const d: Date = new Date();
    const weekdayLabels: string[] = ['日', '一', '二', '三', '四', '五', '六'];
    const wd: number = d.getDay();
    f.todayLabel = `${DateUtil.formatCn(d)} · 周${weekdayLabels[wd]}`;
  }
  const now: Date = new Date();
  f.lastRefresh = `更新于 ${now.getHours()}:${now.getMinutes() < 10 ? '0' + now.getMinutes() : now.getMinutes()}`;

  // 1) 课程预告：今天 / 明天 / 下次有课日。学期外一律不填充课表数据（卡片显示空态）。
  try {
    const raw: string = DataStore.get(DataStore.KEY_COURSES);
    if (raw.length > 0 && !isVacation) {
      const list: CourseItem[] = JSON.parse(raw) as CourseItem[];
      const todayW: number = localWeekday(0);
      const tomorrowW: number = localWeekday(1);
      const today = coursesOfDay(list, todayW, week, term.totalWeeks);
      const tomorrow = coursesOfDay(list, tomorrowW, week, term.totalWeeks);
      const nextDay = coursesOfNextDay(list, todayW, tomorrowW, week, term.totalWeeks);

      f.todayNames = today.names;
      f.todayTimes = today.times;
      f.todayRooms = today.rooms;
      f.todayStarts = today.starts;
      f.todayCount = today.names.length;

      f.tomorrowNames = tomorrow.names;
      f.tomorrowTimes = tomorrow.times;
      f.tomorrowRooms = tomorrow.rooms;
      f.tomorrowStarts = tomorrow.starts;
      f.tomorrowCount = tomorrow.names.length;

      f.nextDayNames = nextDay.names;
      f.nextDayTimes = nextDay.times;
      f.nextDayRooms = nextDay.rooms;
      f.nextDayStarts = nextDay.starts;
      f.nextDayCount = nextDay.names.length;

      // nextDay 日期：学期内用精确日期，学期外用 14 天后
      const ndDate: Date = nextDayDate(new Date(), tomorrowW, list, week, term.totalWeeks);
      f.dayLabelNextDay = DateUtil.formatCn(ndDate);

      // 今日课表 + 明日课表：JSON 序列化 [{n,t,r,c}, ...]（最多 10 节课）
      f.todayJson = buildDayJson(today.names, today.times, today.rooms, 10);
      f.tomorrowJson = buildDayJson(tomorrow.names, tomorrow.times, tomorrow.rooms, 10);

      // 周课表：7 天，每天最多 3 节课 → JSON [[{n,t,c}*3]*7]
      const weekArr: DayCourses[] = [];
      for (let d: number = 1; d <= 7; d++) {
        weekArr.push(coursesOfDay(list, d, week, term.totalWeeks));
      }
      f.weeklyJson = buildWeekJson(weekArr, 3);
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'read courses failed: %{public}s', JSON.stringify(e));
  }

  // 2) 考试倒计时：用户选 > 最近未开始 > 示例
  try {
    const raw: string = DataStore.get(DataStore.KEY_EXAMS);
    if (raw.length > 0) {
      const list: ExamItem[] = JSON.parse(raw) as ExamItem[];
      const today: Date = DateUtil.startOfDay(new Date());
      const pickedId: string = DataStore.getPickedExamId();
      let chosen: ExamItem | null = null;

      if (pickedId.length > 0) {
        for (const ex of list) {
          if (ex.id === pickedId) {
            chosen = ex;
            break;
          }
        }
      }

      if (chosen === null) {
        let best: ExamItem | null = null;
        let bestDays: number = Number.MAX_SAFE_INTEGER;
        for (const ex of list) {
          const days: number = DateUtil.diffDays(today, DateUtil.parse(ex.date));
          if (days >= 0 && days < bestDays) {
            best = ex;
            bestDays = days;
          }
        }
        chosen = best;
      }

      if (chosen !== null) {
        const days: number = DateUtil.diffDays(today, DateUtil.parse(chosen.date));
        f.examName = chosen.courseName;
        f.examTime = `${chosen.date} ${chosen.timeRange}`;
        f.examLocation = chosen.location;
        f.examDays = days === 0 ? '今天' : (days > 0 ? `${days}天后` : `${-days}天前`);
        f.hasExam = true;
      }
    }

    if (!f.hasExam) {
      f.examName = '示例：高等数学';
      f.examTime = '请在应用内选择真实考试';
      f.examLocation = '点击卡片进入选择';
      f.examDays = '25天后';
      f.isDemoExam = true;
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'read exams failed: %{public}s', JSON.stringify(e));
    if (!f.hasExam) {
      f.examName = '示例：高等数学';
      f.examTime = '请在应用内选择真实考试';
      f.examLocation = '点击卡片进入选择';
      f.examDays = '25天后';
      f.isDemoExam = true;
    }
  }

  f.isEmpty = f.todayCount === 0 && f.tomorrowCount === 0 && f.nextDayCount === 0;
  return f;
}

export default class EntryFormAbility extends FormExtensionAbility {
  private initDone: boolean = false;

  private ensureInit(): void {
    if (!this.initDone) {
      DataStore.init(this.context);
      this.initDone = true;
    }
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    this.ensureInit();
    const formId: string = want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string ?? '';
    const data: FormData = buildFormData(0);
    if (formId.length > 0) {
      formProvider.setFormNextRefreshTime(formId, 30).catch((_: Error) => {
      });
    }
    return formBindingData.createFormBindingData(data);
  }

  onUpdateForm(formId: string): void {
    this.ensureInit();
    const data: FormData = buildFormData(viewIndex);
    formProvider.updateForm(formId, formBindingData.createFormBindingData(data))
      .then(() => {
        formProvider.setFormNextRefreshTime(formId, 30).catch((_: Error) => {
        });
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'updateForm failed: %{public}s', JSON.stringify(err));
      });
  }

  /** 卡片交互：toggle = 当前视图循环切换（0=今天, 1=明天, 2=下次有课日） */
  onFormEvent(formId: string, message: string): void {
    this.ensureInit();
    try {
      const parsed: Record<string, Object> = JSON.parse(message) as Record<string, Object>;
      let action: string = '';
      if (typeof parsed['msgTest'] === 'string') {
        action = parsed['msgTest'] as string;
      } else if (parsed['params'] !== undefined &&
        typeof (parsed['params'] as Record<string, Object>)['msgTest'] === 'string') {
        action = (parsed['params'] as Record<string, Object>)['msgTest'] as string;
      }
      if (action === 'toggle') {
        viewIndex = (viewIndex + 1) % 3;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'onFormEvent parse failed');
    }
    const data: FormData = buildFormData(viewIndex);
    formProvider.updateForm(formId, formBindingData.createFormBindingData(data))
      .then(() => {
        formProvider.setFormNextRefreshTime(formId, 30).catch((_: Error) => {
        });
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'formEvent update failed: %{public}s', JSON.stringify(err));
      });
  }

  onRemoveForm(formId: string): void {
    hilog.info(DOMAIN, TAG, 'onRemoveForm %{public}s', formId);
  }
}