/**
 * 节次工具：按课程表配置（节数 + 每节课时间）解析实际作息时间表。
 * - 未自定义（配置为空）时使用内置默认作息（Const.SECTIONS）；
 * - 自定义时按 "HH:MM-HH:MM" 逗号分隔解析；节数以 sectionCount 为准。
 * 供课程表时间轴、格子时间文本与设置面板共用。
 */
import { SectionTime, Const } from './Constants';
import { ScheduleConfig } from './ScheduleConfig';

export class SectionUtil {
  /** 解析单节时间 "HH:MM-HH:MM" → [start, end]；非法返回 null */
  private static parseOne(text: string): string[] | null {
    const t: string = text.trim();
    const i: number = t.indexOf('-');
    if (i <= 0) {
      return null;
    }
    const start: string = t.substring(0, i).trim();
    const end: string = t.substring(i + 1).trim();
    if (!SectionUtil.isTime(start) || !SectionUtil.isTime(end)) {
      return null;
    }
    return [start, end];
  }

  /** 是否为合法的 HH:MM 时间 */
  static isTime(t: string): boolean {
    const m: RegExpMatchArray | null = t.match(new RegExp('^([0-1][0-9]|2[0-3]):([0-5][0-9])$'));
    return m !== null;
  }

  /** 当前配置下的节次总数（1~15） */
  static count(cfg: ScheduleConfig): number {
    let n: number = cfg.sectionCount;
    if (!(n >= 1)) {
      n = Const.SECTION_COUNT;
    }
    if (n > 15) {
      n = 15;
    }
    return n;
  }

  /**
   * 当前配置下的节次时间表（长度 = count）
   * 自定义项缺失时，对应节次回落到内置默认值（不足部分按 45 分钟顺延推算）
   */
  static list(cfg: ScheduleConfig): SectionTime[] {
    const n: number = SectionUtil.count(cfg);
    const custom: string[] = cfg.sectionTimeText.length > 0 ? cfg.sectionTimeText.split(',') : [];
    const out: SectionTime[] = [];
    for (let i = 0; i < n; i++) {
      let start: string = '';
      let end: string = '';
      if (i < custom.length) {
        const p: string[] | null = SectionUtil.parseOne(custom[i]);
        if (p !== null) {
          start = p[0];
          end = p[1];
        }
      }
      if (start.length === 0) {
        if (i < Const.SECTIONS.length) {
          start = Const.SECTIONS[i].start;
          end = Const.SECTIONS[i].end;
        } else {
          const last: SectionTime = out[out.length - 1];
          start = SectionUtil.addMinutes(last.end, 10);
          end = SectionUtil.addMinutes(start, 45);
        }
      }
      out.push({ index: i + 1, start: start, end: end } as SectionTime);
    }
    return out;
  }

  /** 取某一节的时间文本（用于详情/格子） */
  static rangeText(cfg: ScheduleConfig, startSection: number, endSection: number): string {
    const list: SectionTime[] = SectionUtil.list(cfg);
    const a: number = Math.max(1, Math.min(startSection, list.length));
    const b: number = Math.max(a, Math.min(endSection, list.length));
    if (list.length === 0) {
      return '';
    }
    return `${list[a - 1].start}-${list[b - 1].end}`;
  }

  /** 节次所属时段（上午/下午/晚上）：上午 1-4、下午 5-8、晚上 其余 */
  static period(index: number): string {
    if (index <= 4) {
      return '上午';
    }
    if (index <= 8) {
      return '下午';
    }
    return '晚上';
  }

  /** 把 "HH:MM" 加上分钟数（跨日则回到 00:00 起算） */
  private static addMinutes(time: string, minutes: number): string {
    const p: string[] = time.split(':');
    let h: number = Number.parseInt(p[0]);
    let m: number = Number.parseInt(p[1]);
    m += minutes;
    h += Math.floor(m / 60);
    m = m % 60;
    h = h % 24;
    const hh: string = h < 10 ? `0${h}` : `${h}`;
    const mm: string = m < 10 ? `0${m}` : `${m}`;
    return `${hh}:${mm}`;
  }

  /** 时间加减分钟（对外暴露，供设置面板顺延推算用） */
  static addMinutesText(time: string, minutes: number): string {
    return SectionUtil.addMinutes(time, minutes);
  }

  /** 生成用于持久化的时间文本（逗号分隔） */
  static toText(list: SectionTime[]): string {
    return list.map((s: SectionTime) => `${s.start}-${s.end}`).join(',');
  }
}
