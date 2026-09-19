/**
 * 课表 HTML 生成：把当前课表渲染成一张 A4 横向的网页，供「课表原文件」页内预览使用。
 */
import { CourseItem, TermInfo } from '../model/Models';
import { ScheduleConfig } from './ScheduleConfig';
import { SectionUtil } from './SectionUtil';
import { SectionTime, Const } from './Constants';
import { DateUtil } from './DateUtil';

export class CourseHtml {
  /** HTML 转义（避免课程名/地点中的特殊字符破坏页面） */
  private static esc(t: string): string {
    let out: string = '';
    for (let i: number = 0; i < t.length; i++) {
      const ch: string = t.charAt(i);
      if (ch === '&') {
        out += '&amp;';
      } else if (ch === '<') {
        out += '&lt;';
      } else if (ch === '>') {
        out += '&gt;';
      } else {
        out += ch;
      }
    }
    return out;
  }

  /** 生成时间文本 yyyy-MM-dd HH:mm */
  private static nowText(): string {
    const d: Date = new Date();
    const p = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  /**
   * 生成课表 HTML（A4 横向，週一到周日，含节次时间与课程名/地点/教师）。
   * @param term 学期（用于周次对应日期）
   * @param week 周次
   * @param courses 课程列表（通常为当前学期全部课程）
   * @param cfg 课表配置（决定节数与每节时间）
   */
  static build(term: TermInfo, week: number, courses: CourseItem[], cfg: ScheduleConfig): string {
    // 表头：周一~周日 + 该周对应日期
    const dayHeads: string[] = [];
    for (let d: number = 1; d <= 7; d++) {
      let dateText: string = '';
      try {
        const dt: Date = DateUtil.dateOfWeekDay(term, week, d);
        dateText = `${dt.getMonth() + 1}/${dt.getDate()}`;
      } catch (e) {
        dateText = '';
      }
      dayHeads.push(`${Const.WEEK_LABELS[d - 1]}<br><span class="m">${dateText}</span>`);
    }

    // 节次行 × 7 天
    const secs: SectionTime[] = SectionUtil.list(cfg);
    let rows: string = '';
    for (const s of secs) {
      let cells: string = '';
      for (let d: number = 1; d <= 7; d++) {
        let inner: string = '';
        for (const c of courses) {
          if (c.weekday === d && c.weeks.includes(week) && c.startSection <= s.index && c.endSection >= s.index) {
            inner += `<div class="c"><span class="n">${CourseHtml.esc(c.name)}</span>`;
            if (c.weeksText.length > 0) {
              inner += `<div class="m">${CourseHtml.esc(c.weeksText)}</div>`;
            }
            if (c.location.length > 0) {
              inner += `<div class="m">@${CourseHtml.esc(c.location)}</div>`;
            }
            if (c.teacher.length > 0) {
              inner += `<div class="m">${CourseHtml.esc(c.teacher)}</div>`;
            }
            inner += `</div>`;
          }
        }
        cells += `<td>${inner}</td>`;
      }
      rows += `<tr><th class="sec">${s.index}<div class="m">${s.start}<br>${s.end}</div></th>${cells}</tr>`;
    }

    let weekCourses: number = 0;
    for (const c of courses) {
      if (c.weeks.includes(week)) {
        weekCourses += c.endSection - c.startSection + 1;
      }
    }

    let head: string = '';
    for (const h of dayHeads) {
      head += `<th>${h}</th>`;
    }

    return `<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<meta name="viewport" content="width=1122, initial-scale=1">
<title>${CourseHtml.esc(term.label)} 第 ${week} 周 课表</title>
<style>
  /* 固定按 A4 横向 1122px（96dpi）排版，与 PDF 页面 1:1，避免导出后文字过小 */
  @page { size: A4 landscape; margin: 0; }
  html, body { margin: 0; padding: 0; background: #FFFFFF; color: #1A1D1C; }
  body {
    width: 1122px;
    padding: 26px 30px 18px 30px;
    box-sizing: border-box;
    font-family: "HarmonyOS Sans", "Microsoft YaHei", "PingFang SC", sans-serif;
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }
  h1 { font-size: 32px; margin: 0 0 4px 0; }
  .sub { font-size: 17px; color: #4A5451; margin-bottom: 16px; }
  table { border-collapse: collapse; width: 100%; table-layout: fixed; }
  th, td { border: 1px solid #9AA4A1; vertical-align: top; padding: 7px 8px; }
  thead th { background: #E4F2EC; font-size: 19px; text-align: center; line-height: 1.35; }
  th.sec { width: 92px; background: #F0F4F2; font-size: 17px; text-align: center; }
  td { font-size: 16px; height: 92px; }
  .n { font-weight: 700; font-size: 17px; }
  .m { color: #4A5451; font-size: 14px; line-height: 1.35; }
  .c + .c { margin-top: 6px; padding-top: 6px; border-top: 1px dashed #B9C2BF; }
  .foot { margin-top: 10px; font-size: 13px; color: #6B7573; }
</style></head>
<body>
  <h1>${CourseHtml.esc(term.label)} · 第 ${week} 周课表</h1>
  <div class="sub">本周共 ${weekCourses} 节课 · 导出时间 ${CourseHtml.nowText()} · 新农助手</div>
  <table>
    <thead><tr><th class="sec">节次</th>${head}</tr></thead>
    <tbody>${rows}</tbody>
  </table>
  <div class="foot">说明：周六 / 周日的课程会一并显示；本文件由「新农助手」依据教务系统课表数据生成，仅供个人查看。</div>
</body></html>`;
  }
}
