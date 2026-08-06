/**
 * EntryFormAbility — 桌面卡片数据提供者（移植自 HiXD 的 EntryFormAbility）
 * 读取本地 DataStore 缓存的课表/考试数据，组装成卡片可绑定的平面数据
 * （formBindingData 不支持对象数组，全部转成 string[]/number[] 传参）。
 * 数据源：DataStore.KEY_COURSES（CourseItem[] JSON）、DataStore.KEY_EXAMS（ExamItem[] JSON）
 */
import { Want } from '@kit.AbilityKit';
import { formBindingData, FormExtensionAbility, formInfo, formProvider } from '@kit.FormKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DataStore } from '../common/DataStore';
import { DateUtil } from '../common/DateUtil';
import { CourseItem, ExamItem } from '../model/Models';

const TAG: string = 'EntryFormAbility';
const DOMAIN: number = 0xFF00;
let showTomorrowFlag: boolean = false;

/** 节次时间表（索引 0 占位，与 Const.SECTIONS 一致） */
const SECTION_TIMES: string[] = [
  '', '10:00-10:50', '11:00-11:50', '12:10-13:00', '13:10-14:00',
  '15:30-16:20', '16:30-17:20', '17:40-18:30', '18:40-19:30', '20:30-21:15', '21:25-22:10'
];

/** 卡片绑定数据结构：全部用平面字段（string[]/number[]/number） */
class FormData {
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
  examName: string;
  examDays: string;
  examTime: string;
  examLocation: string;
  hasExam: boolean;
  weekLabel: string;
  dateLabel: string;
  lastRefresh: string;
  isEmpty: boolean;
  showTomorrow: boolean;

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
    this.examName = '';
    this.examDays = '';
    this.examTime = '';
    this.examLocation = '';
    this.hasExam = false;
    this.weekLabel = '';
    this.dateLabel = '';
    this.lastRefresh = '';
    this.isEmpty = true;
    this.showTomorrow = false;
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

/** 取某天的课程（过滤 星期 + 周次），返回按起始节次排序的并行数组 */
function coursesOfDay(list: CourseItem[], weekday: number, week: number): DayCourses {
  const out: DayCourses = new DayCourses();
  for (const c of list) {
    if (c.weekday !== weekday || !c.weeks.includes(week)) {
      continue;
    }
    out.names.push(c.name);
    out.starts.push(c.startSection);
    out.times.push(SECTION_TIMES[c.startSection] ?? `${c.startSection}-${c.endSection}节`);
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

/** 组装卡片数据：从 DataStore 读缓存 → 按 星期+周次 过滤 → 排序 */
function buildFormData(showTomorrow: boolean): FormData {
  const f: FormData = new FormData();
  f.showTomorrow = showTomorrow;
  const term = DateUtil.buildCurrentTerm();
  const week: number = DateUtil.weekOfTerm(term, new Date());
  f.weekLabel = `第${Math.max(1, week)}周`;
  f.dateLabel = showTomorrow
    ? `明日 ${DateUtil.formatCn(new Date(Date.now() + 86400000))}`
    : `今日 ${DateUtil.formatCn(new Date())}`;
  const now: Date = new Date();
  f.lastRefresh = `更新于 ${now.getHours()}:${now.getMinutes() < 10 ? '0' + now.getMinutes() : now.getMinutes()}`;

  // 1) 课程预告：今天 + 明天
  try {
    const raw: string = DataStore.get(DataStore.KEY_COURSES);
    if (raw.length > 0) {
      const list: CourseItem[] = JSON.parse(raw) as CourseItem[];
      const today = coursesOfDay(list, localWeekday(0), Math.max(1, week));
      const tomorrow = coursesOfDay(list, localWeekday(1), Math.max(1, week));
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
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'read courses failed: %{public}s', JSON.stringify(e));
  }

  // 2) 考试倒计时：最近一场未开始的考试
  try {
    const raw: string = DataStore.get(DataStore.KEY_EXAMS);
    if (raw.length > 0) {
      const list: ExamItem[] = JSON.parse(raw) as ExamItem[];
      const today: Date = DateUtil.startOfDay(new Date());
      let best: ExamItem | null = null;
      let bestDays: number = Number.MAX_SAFE_INTEGER;
      for (const ex of list) {
        const days: number = DateUtil.diffDays(today, DateUtil.parse(ex.date));
        if (days >= 0 && days < bestDays) {
          best = ex;
          bestDays = days;
        }
      }
      if (best !== null) {
        f.examName = best.courseName;
        f.examTime = `${best.date} ${best.timeRange}`;
        f.examLocation = best.location;
        f.examDays = bestDays === 0 ? '今天' : `${bestDays}天后`;
        f.hasExam = true;
      }
    }
  } catch (e) {
    hilog.warn(DOMAIN, TAG, 'read exams failed: %{public}s', JSON.stringify(e));
  }

  f.isEmpty = f.todayNames.length === 0 && !f.hasExam;
  return f;
}

export default class EntryFormAbility extends FormExtensionAbility {
  private initDone: boolean = false;

  /** Form 扩展进程内首次使用时初始化本地存储（与主 Ability 共用 xjau_helper 文件） */
  private ensureInit(): void {
    if (!this.initDone) {
      DataStore.init(this.context);
      this.initDone = true;
    }
  }

  /** 桌面添加卡片：组装数据并返回 */
  onAddForm(want: Want): formBindingData.FormBindingData {
    this.ensureInit();
    const formId: string = want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string ?? '';
    const data: FormData = buildFormData(false);
    if (formId.length > 0) {
      formProvider.setFormNextRefreshTime(formId, 30).catch((_: Error) => {
      });
    }
    return formBindingData.createFormBindingData(data);
  }

  /** 定时更新 / 主动刷新 */
  onUpdateForm(formId: string): void {
    this.ensureInit();
    const data: FormData = buildFormData(showTomorrowFlag);
    formProvider.updateForm(formId, formBindingData.createFormBindingData(data))
      .then(() => {
        formProvider.setFormNextRefreshTime(formId, 30).catch((_: Error) => {
        });
      })
      .catch((err: Error) => {
        hilog.error(DOMAIN, TAG, 'updateForm failed: %{public}s', JSON.stringify(err));
      });
  }

  /** 卡片交互：toggle = 今天/明天切换 */
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
        showTomorrowFlag = !showTomorrowFlag;
      }
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'onFormEvent parse failed');
    }
    const data: FormData = buildFormData(showTomorrowFlag);
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
