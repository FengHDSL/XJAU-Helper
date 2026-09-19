/**
 * 课表「原始导入识别文件」存取：
 * 每次成功拉取课表时，把教务系统返回的**原始响应体**（正方课表接口的 JSON 全文）
 * 原样落盘到应用 filesDir/course_raw/<termId>.json，并记录元信息（来源接口 / 抓取时间 / 条数 / 字节数）。
 * 课表页底部的「课表原文件」入口可快速查看该文件，便于核对识别结果与排查漏课。
 */
import { fileIo } from '@kit.CoreFileKit';
import { AppState } from './AppState';

/** 原始课表文件元信息 */
export interface CourseRawMeta {
  termId: string;
  /** 数据来源接口 */
  url: string;
  /** 抓取时间 yyyy-MM-dd HH:mm */
  time: string;
  /** 课程条数（解析后） */
  count: number;
  /** JSON 原文文件字节数 */
  bytes: number;
  /** 课表 HTML（用于输出 PDF / 预览）生成时间，''=未生成 */
  htmlTime?: string;
  /** PDF 生成时间，''=未生成 */
  pdfTime?: string;
  /** PDF 字节数 */
  pdfBytes?: number;
}

export class CourseRawStore {
  /** 存放目录名（filesDir 下，持久保存，不随系统缓存清理丢失） */
  private static readonly DIR: string = 'course_raw';

  /** 目录绝对路径（无 Context 时返回空串） */
  private static dir(): string {
    const ctx = AppState.context;
    if (ctx === null) {
      return '';
    }
    return `${ctx.filesDir}/${CourseRawStore.DIR}`;
  }

  /** 原文件路径 */
  static filePath(termId: string): string {
    const d: string = CourseRawStore.dir();
    return d.length > 0 ? `${d}/${termId}.json` : '';
  }

  /** 元信息文件路径 */
  private static metaPath(termId: string): string {
    const d: string = CourseRawStore.dir();
    return d.length > 0 ? `${d}/${termId}.meta.json` : '';
  }

  /** 课表 HTML 路径（预览用） */
  static htmlPath(termId: string): string {
    const d: string = CourseRawStore.dir();
    return d.length > 0 ? `${d}/${termId}.html` : '';
  }

  /** 当前时间文本（yyyy-MM-dd HH:mm） */
  private static nowText(): string {
    const d: Date = new Date();
    const p = (n: number): string => n < 10 ? `0${n}` : `${n}`;
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  /** 写入文本文件（自动建目录；失败静默） */
  private static writeText(path: string, text: string): boolean {
    if (path.length === 0) {
      return false;
    }
    try {
      const dirPath: string = CourseRawStore.dir();
      if (dirPath.length > 0 && !fileIo.accessSync(dirPath)) {
        fileIo.mkdirSync(dirPath);
      }
      const f: fileIo.File = fileIo.openSync(path,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.READ_WRITE);
      fileIo.writeSync(f.fd, text);
      fileIo.closeSync(f);
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 保存原始响应体 + 元信息（每次拉取课表后调用） */
  static save(termId: string, body: string, url: string, count: number): void {
    if (termId.length === 0 || body.length === 0) {
      return;
    }
    if (!CourseRawStore.writeText(CourseRawStore.filePath(termId), body)) {
      return;
    }
    let bytes: number = body.length;
    try {
      const st: fileIo.Stat = fileIo.statSync(CourseRawStore.filePath(termId));
      bytes = st.size;
    } catch (e) {
      // 取不到大小则退回字符数
    }
    const patch: CourseRawMeta = {
      termId: termId,
      url: url,
      time: CourseRawStore.nowText(),
      count: count,
      bytes: bytes,
      htmlTime: '',
      pdfTime: '',
      pdfBytes: 0
    };
    CourseRawStore.patchMeta(termId, patch);
  }

  /** 原文件是否存在 */
  static exists(termId: string): boolean {
    const p: string = CourseRawStore.filePath(termId);
    if (p.length === 0) {
      return false;
    }
    try {
      return fileIo.accessSync(p);
    } catch (e) {
      return false;
    }
  }

  /** 读取原文件全文（不存在返回空串） */
  static read(termId: string): string {
    const p: string = CourseRawStore.filePath(termId);
    if (p.length === 0) {
      return '';
    }
    try {
      if (!fileIo.accessSync(p)) {
        return '';
      }
      return fileIo.readTextSync(p);
    } catch (e) {
      return '';
    }
  }

  /** 读取元信息（不存在返回 null） */
  static meta(termId: string): CourseRawMeta | null {
    const p: string = CourseRawStore.metaPath(termId);
    if (p.length === 0) {
      return null;
    }
    try {
      if (!fileIo.accessSync(p)) {
        return null;
      }
      return JSON.parse(fileIo.readTextSync(p)) as CourseRawMeta;
    } catch (e) {
      return null;
    }
  }

  /** 覆盖写入元信息（保留已有字段，只更新传入项） */
  private static patchMeta(termId: string, patch: CourseRawMeta): void {
    const p: string = CourseRawStore.metaPath(termId);
    if (p.length === 0) {
      return;
    }
    const old: CourseRawMeta | null = CourseRawStore.meta(termId);
    const meta: CourseRawMeta = {
      termId: termId,
      url: patch.url.length > 0 ? patch.url : (old !== null ? old.url : ''),
      time: patch.time.length > 0 ? patch.time : (old !== null ? old.time : ''),
      count: patch.count > 0 ? patch.count : (old !== null ? old.count : 0),
      bytes: patch.bytes > 0 ? patch.bytes : (old !== null ? old.bytes : 0),
      htmlTime: patch.htmlTime !== undefined && patch.htmlTime.length > 0
        ? patch.htmlTime : (old !== null ? old.htmlTime : ''),
      pdfTime: patch.pdfTime !== undefined && patch.pdfTime.length > 0
        ? patch.pdfTime : (old !== null ? old.pdfTime : ''),
      pdfBytes: patch.pdfBytes !== undefined && patch.pdfBytes > 0
        ? patch.pdfBytes : (old !== null ? old.pdfBytes : 0)
    };
    CourseRawStore.writeText(p, JSON.stringify(meta));
  }

  // ── 课表 HTML（预览用）──

  /** 保存课表 HTML（课表原文件页预览用，每次预览前刷新） */
  static saveHtml(termId: string, html: string, url: string, count: number): void {
    if (!CourseRawStore.writeText(CourseRawStore.htmlPath(termId), html)) {
      return;
    }
    const patch: CourseRawMeta = {
      termId: termId, url: url, time: '', count: count, bytes: 0,
      htmlTime: CourseRawStore.nowText(), pdfTime: '', pdfBytes: 0
    };
    CourseRawStore.patchMeta(termId, patch);
  }

  /** 读取课表 HTML（不存在返回空串） */
  static readHtml(termId: string): string {
    const p: string = CourseRawStore.htmlPath(termId);
    if (p.length === 0) {
      return '';
    }
    try {
      return fileIo.accessSync(p) ? fileIo.readTextSync(p) : '';
    } catch (e) {
      return '';
    }
  }
}
