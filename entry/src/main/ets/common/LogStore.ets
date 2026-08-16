/**
 * 日志调试模块（LogStore）：真实登录下开启 logEnabled 后，收集各功能模块的使用日志与联网反馈，
 * 供「我的 → 日志详情」页查看 / 导出，方便排查 bug。
 *
 * 设计：
 *  - 内存环形日志（上限 LOG_LIMIT 条），开启 logEnabled 时才记录
 *  - 字段覆盖（对齐浏览器开发者工具网络面板能看到的程度）：
 *      请求 URL / Method / HTTP 状态 / 请求头摘要 / 响应头摘要 / 脱敏表单参数 /
 *      耗时 / 异常信息 / 响应体片段
 *  - 隐私保护：密码、Cookie 一律打码；请求参数脱敏（登录表单 mm/yhm 打码）
 */
import { AppState } from './AppState';

export class LogEntry {
  time: string = '';
  module: string = '';
  action: string = '';
  result: string = '';
  /** 请求方法（GET/POST） */
  method: string = '';
  /** 请求地址 */
  url: string = '';
  /** HTTP 状态码 / 错误码（如 200 / 502 / 17100001） */
  status: string = '';
  /** 耗时（ms） */
  cost: string = '';
  /** 异常信息（name + code + message） */
  error: string = '';
  /** 请求头摘要（User-Agent / Accept / Content-Type / Referer，Cookie 打码） */
  reqHeaders: string = '';
  /** 响应头摘要（Content-Type / Content-Length / Server / Date） */
  respHeaders: string = '';
  /** 脱敏表单参数（如 xnm/xqm，密码/账号打码） */
  params: string = '';
  /** 响应体片段（前 BODY_PREVIEW_LEN 字符，压平，页面展示用） */
  bodyPreview: string = '';
  /** 完整响应体（上限 FULL_BODY_LEN 字符，详情展开/导出用，不省略） */
  fullBody: string = '';
  /** 附加说明（数据条数、业务判定等） */
  detail: string = '';
}

export class LogStore {
  /** 环形日志上限 */
  static readonly LOG_LIMIT: number = 300;
  /** 响应体片段最大长度（页面展示预览用） */
  static readonly BODY_PREVIEW_LEN: number = 400;
  /** 完整响应体最大长度（详情展开/导出用；超长才截断，避免内存失控） */
  static readonly FULL_BODY_LEN: number = 20000;
  /** 日志列表（最新的在末尾） */
  private static logs: LogEntry[] = [];
  /** 是否继续收集（日志页右上角开关控制：关 = 暂停收集但保留已有日志）
   *  响应式（AppStorage 'logCollecting'）：我的页"日志详情"入口状态灯跟随 */
  static get collecting(): boolean {
    return AppStorage.get<boolean>('logCollecting') ?? true;
  }
  static set collecting(value: boolean) {
    AppStorage.setOrCreate('logCollecting', value);
  }

  /** 是否开启日志调试 */
  static enabled(): boolean {
    return AppState.logEnabled;
  }

  /** 是否处于可收集状态（开启调试 && 未暂停） */
  static active(): boolean {
    return AppState.logEnabled && LogStore.collecting;
  }

  /**
   * 记录一条网络请求日志（联网反馈核心，对齐开发者工具网络面板信息量）。
   * @param module 功能模块（如 登录/课表/成绩/新闻/外部链接/网络）
   * @param action 动作（如 请求/解析/打开/刷新）
   * @param result 结果（成功/失败/异常 等）
   * @param opts   结构化信息
   */
  static logNet(module: string, action: string, result: string,
    opts: LogOptions): void {
    if (!LogStore.active()) {
      return;
    }
    const e: LogEntry = new LogEntry();
    e.time = LogStore.now();
    e.module = module;
    e.action = action;
    e.result = result;
    e.method = opts.method ?? '';
    e.url = opts.url ?? '';
    e.status = opts.status ?? '';
    e.cost = opts.cost ?? '';
    e.error = opts.error ?? '';
    e.reqHeaders = opts.reqHeaders ?? '';
    e.respHeaders = opts.respHeaders ?? '';
    e.params = opts.params ?? '';
    e.bodyPreview = LogStore.bodyPreview(opts.body ?? '');
    e.fullBody = LogStore.limitFull(opts.body ?? '');
    e.detail = opts.detail ?? '';
    LogStore.push(e);
  }

  /** 记录一条业务日志（无网络上下文时用） */
  static log(module: string, action: string, result: string, detail: string = ''): void {
    if (!LogStore.active()) {
      return;
    }
    const e: LogEntry = new LogEntry();
    e.time = LogStore.now();
    e.module = module;
    e.action = action;
    e.result = result;
    e.detail = detail;
    LogStore.push(e);
  }

  /** 统一压入并裁剪环形上限 */
  private static push(e: LogEntry): void {
    LogStore.logs.push(e);
    if (LogStore.logs.length > LogStore.LOG_LIMIT) {
      LogStore.logs.splice(0, LogStore.logs.length - LogStore.LOG_LIMIT);
    }
  }

  private static now(): string {
    const d: Date = new Date();
    return `${d.getHours().toString().padStart(2, '0')}:${d.getMinutes().toString().padStart(2, '0')}:${d.getSeconds().toString().padStart(2, '0')}`;
  }

  /** 截取响应体片段（去空白压平，避免日志过长；页面预览用） */
  static bodyPreview(body: string): string {
    if (body.length === 0) {
      return '';
    }
    const flat: string = body.replace(/\s+/g, ' ').trim();
    if (flat.length <= LogStore.BODY_PREVIEW_LEN) {
      return flat;
    }
    return flat.substring(0, LogStore.BODY_PREVIEW_LEN) + '…';
  }

  /** 完整响应体（保留原始格式，仅超长截断；详情展开/导出用，不省略） */
  static limitFull(body: string): string {
    if (body.length <= LogStore.FULL_BODY_LEN) {
      return body;
    }
    return body.substring(0, LogStore.FULL_BODY_LEN) + '\n…[响应体过长，已截断至 20000 字符]';
  }

  /** 提取异常信息（name + code + message） */
  static errorOf(err: Object | undefined): string {
    if (err === undefined) {
      return '';
    }
    const e: Record<string, Object> = err as Record<string, Object>;
    const name: string = String(e['name'] ?? '');
    const code: string = String(e['code'] ?? '');
    const msg: string = String(e['message'] ?? '');
    const parts: string[] = [];
    if (name.length > 0 && name !== 'Error') {
      parts.push(name);
    }
    if (code.length > 0) {
      parts.push(`code=${code}`);
    }
    if (msg.length > 0) {
      parts.push(msg);
    }
    return parts.join(' ');
  }

  /**
   * 请求头摘要：只保留关键头，Cookie 打码。
   * @param header 完整请求头
   * @returns "User-Agent=xxx; Accept=xxx; ..."
   */
  static reqHeaderSummary(header: Record<string, string>): string {
    const keys: string[] = ['User-Agent', 'Accept', 'Content-Type', 'Referer', 'X-Requested-With'];
    const out: string[] = [];
    for (const k of keys) {
      const v: string = header[k] ?? '';
      if (v.length === 0) {
        continue;
      }
      if (k === 'User-Agent') {
        out.push(`UA=${LogStore.shorten(v, 60)}`);
      } else if (k === 'Cookie') {
        out.push('Cookie=***');
      } else {
        out.push(`${k}=${LogStore.shorten(v, 40)}`);
      }
    }
    return out.join('; ');
  }

  /**
   * 响应头摘要：Content-Type / Content-Length / Server / Date。
   * @param headers 响应头对象（key 可能大小写混用）
   */
  static respHeaderSummary(headers: Object | undefined): string {
    if (headers === undefined) {
      return '';
    }
    const h: Record<string, Object> = headers as Record<string, Object>;
    const keys: string[] = ['content-type', 'Content-Type', 'content-length', 'Content-Length',
      'server', 'Server', 'date', 'Date'];
    const out: string[] = [];
    for (const k of keys) {
      const v: Object | undefined = h[k];
      if (v !== undefined && String(v).length > 0) {
        out.push(`${k}=${LogStore.shorten(String(v), 40)}`);
      }
    }
    return out.join('; ');
  }

  /** 表单参数脱敏摘要：密码/账号打码，其余保留 key=value */
  static paramsSummary(form: Record<string, string>, sensitive: string[] = []): string {
    const keys: string[] = Object.keys(form);
    const out: string[] = [];
    for (const k of keys) {
      const v: string = form[k];
      if (k === 'mm' || k === 'yhm' || k === 'password' || sensitive.indexOf(k) >= 0) {
        out.push(`${k}=***`);
      } else if (v.length > 0) {
        out.push(`${k}=${LogStore.shorten(v, 20)}`);
      }
    }
    return out.join(', ');
  }

  /** 截断字符串 */
  private static shorten(s: string, max: number): string {
    if (s.length <= max) {
      return s;
    }
    return s.substring(0, max) + '…';
  }

  /** 读取全部日志（快照） */
  static all(): LogEntry[] {
    return LogStore.logs.slice();
  }

  /** 清空日志 */
  static clear(): void {
    LogStore.logs = [];
  }
}

/** 网络日志结构化选项 */
export interface LogOptions {
  method?: string;
  url?: string;
  status?: string;
  cost?: string;
  error?: string;
  reqHeaders?: string;
  respHeaders?: string;
  params?: string;
  body?: string;
  detail?: string;
}
