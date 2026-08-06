/**
 * 教学周历（校历）数据模型与 HTML 解析
 *
 * 正方教务系统的"教学周历"页面以一张
 *   <table class="... tab-bor-col-1 ...">
 * 呈现：
 *   - 表头三行：① 学期标题（跨 25 列）② 月份分组（colspan）③ 教学周次（0..N）
 *   - 表体七行：周一~周日，每行 25 个单元格，单元格 id 为 yyyy-MM-dd（空白格 id=""）
 * 解析完全基于 HTML 结构，不写死任何具体日期/周次；开学后页面刷新即自动更新。
 */

export interface MonthGroup {
  label: string; // 8月 / 9月 ...
  span: number;  // 占几列
}

export interface TeachingWeekRow {
  weekday: string;  // 一 / 二 / ... / 日
  dates: string[];  // 25 项，'yyyy-MM-dd' 或 ''（空白格）
}

export interface TeachingCalendar {
  semesterLabel: string; // 2026-2027学年1学期(2026-08-24至2027-01-10)
  startDate: string;     // 2026-08-24
  endDate: string;       // 2027-01-10
  monthGroups: MonthGroup[];
  weekNumbers: number[]; // 25 项：0,1,1,2,...
  rows: TeachingWeekRow[]; // 7 行
  todayDate: string;      // 隐藏域 dqrq 的当前日期
}

/**
 * 从教学周历页面 HTML 中解析出结构化数据。
 * 解析失败（无目标表格 / 无表体）返回 null，调用方据此降级处理。
 */
export function parseTeachingCalendar(html: string): TeachingCalendar | null {
  if (!html || html.length === 0) {
    return null;
  }
  const tableMatch: RegExpMatchArray | null =
    html.match(/<table\b[^>]*tab-bor-col-1[^>]*>([\s\S]*?)<\/table>/);
  if (!tableMatch) {
    return null;
  }
  const table: string = tableMatch[1];

  // 学期标题（跨 25 列的表头）
  let semesterLabel: string = '';
  let startDate: string = '';
  let endDate: string = '';
  const semM: RegExpMatchArray | null = table.match(/colspan="25"[^>]*>([^<]*)</);
  if (semM) {
    semesterLabel = (semM[1] ?? '').replace(/\s+/g, ' ').trim();
    const dr: RegExpMatchArray | null =
      semesterLabel.match(/(\d{4}-\d{2}-\d{2})至(\d{4}-\d{2}-\d{2})/);
    if (dr) {
      startDate = dr[1];
      endDate = dr[2];
    }
  }

  // 表头三行
  const monthGroups: MonthGroup[] = [];
  const weekNumbers: number[] = [];
  const theadM: RegExpMatchArray | null = table.match(/<thead>([\s\S]*?)<\/thead>/);
  if (theadM) {
    const trs: RegExpMatchArray | null = theadM[1].match(/<tr[^>]*>([\s\S]*?)<\/tr>/g);
    if (trs && trs.length >= 3) {
      // 月份分组（第 2 行）
      const mgRe: RegExp = /<th[^>]*colspan="(\d+)"[^>]*>([^<]*)</g;
      let mm: RegExpExecArray | null;
      while ((mm = mgRe.exec(trs[1])) !== null) {
        monthGroups.push({ label: (mm[2] ?? '').trim(), span: parseInt(mm[1] ?? '0', 10) });
      }
      // 周次（第 3 行）
      const wRe: RegExp = /<th[^>]*>([^<]*)<\/th>/g;
      let wm: RegExpExecArray | null;
      while ((wm = wRe.exec(trs[2])) !== null) {
        const t: string = (wm[1] ?? '').replace(/&nbsp;/g, '').trim();
        const n: number = parseInt(t, 10);
        weekNumbers.push(isNaN(n) ? 0 : n);
      }
    }
  }

  // 表体七行
  const rows: TeachingWeekRow[] = [];
  const tbodyM: RegExpMatchArray | null = table.match(/<tbody>([\s\S]*?)<\/tbody>/);
  if (tbodyM) {
    const bodyTrs: RegExpMatchArray | null = tbodyM[1].match(/<tr[^>]*>([\s\S]*?)<\/tr>/g);
    if (bodyTrs) {
      for (let i: number = 0; i < bodyTrs.length; i++) {
        const tr: string = bodyTrs[i];
        const wdM: RegExpMatchArray | null = tr.match(/<th[^>]*>([^<]*)<\/th>/);
        const weekday: string = (wdM ? wdM[1] : '').replace(/&nbsp;/g, '').trim();
        const dates: string[] = [];
        const tdRe: RegExp = /<td\b[^>]*?id="([^"]*)"[^>]*>([\s\S]*?)<\/td>/g;
        let tm: RegExpExecArray | null;
        while ((tm = tdRe.exec(tr)) !== null) {
          dates.push(tm[1].trim());
        }
        rows.push({ weekday, dates });
      }
    }
  }

  // 当前日期（隐藏域 dqrq）
  let todayDate: string = '';
  const dqM: RegExpMatchArray | null = html.match(/name="dqrq"[^>]*value="([^"]*)"/);
  if (dqM) {
    todayDate = dqM[1];
  }

  if (rows.length === 0) {
    return null;
  }
  return { semesterLabel, startDate, endDate, monthGroups, weekNumbers, rows, todayDate };
}
