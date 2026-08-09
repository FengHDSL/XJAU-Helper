/**
 * 轻量 HTTP 封装（为后续抓取教务系统网页做准备）
 *
 * 参考 HiXD (github.com/PollenWang6/HiXD) 的 HttpUtil 思路：
 *  - HarmonyOS NETSTACK 自动跟随 302 时，中间每个重定向响应的 Set-Cookie
 *    都通过 on('headersReceive') 事件先回调。这里逐个收集并保存，
 *    避免"只在最终响应读一次 header"导致登录成功后（302 链中下发的
 *    JSESSIONID）丢失会话 Cookie —— 这是登录后查询失败的最大根因。
 *  - 手动维护会话 Cookie，登录后带上，保证课表/成绩/考试等接口可用。
 */
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { JwApi } from './JwApi';
import { AppState } from '../common/AppState';
import { LogStore } from '../common/LogStore';

export interface HttpResult {
  code: number;
  body: string;
  cookie: string;
}

/** 二进制响应结果（导出 Excel 等）：data 为空表示失败，code/body 用于诊断 */
export interface BinaryResult {
  data: ArrayBuffer | null;
  code: number;
  body: string;
}

export class HttpClient {
  /** 教务系统根地址（不含 /jwglxt，各接口路径已自带）。接入学校真实教务系统时改这里。 */
  static baseUrl: string = 'https://jwxt.xjau.edu.cn';
  /** 会话 Cookie */
  private static cookie: string = '';
  /** 功能浏览模式（USE_MOCK）下短路所有网络请求，避免意外访问真实接口 */
  private static offlineMode: boolean = false;
  /** 设置离线模式（功能浏览模式启用，HttpClient 所有请求直接返回空结果） */
  static setOfflineMode(value: boolean): void {
    HttpClient.offlineMode = value;
  }

  /** 设置请求会话 Cookie（登录成功后保存，供后续接口携带） */
  static setCookie(value: string): void {
    HttpClient.cookie = value;
  }

  /** 读取当前会话 Cookie */
  static getCookie(): string {
    return HttpClient.cookie;
  }

  /** 清空会话 Cookie（退出登录时调用） */
  static clearCookie(): void {
    HttpClient.cookie = '';
  }

  private static buildHeader(extra: Record<string, string>): Record<string, string> {
    const header: Record<string, string> = {};
    header['User-Agent'] = 'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';
    header['Accept'] = 'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8';
    if (HttpClient.cookie.length > 0) {
      header['Cookie'] = HttpClient.cookie;
    }
    const keys: string[] = Object.keys(extra);
    for (let i = 0; i < keys.length; i++) {
      header[keys[i]] = extra[keys[i]];
    }
    return header;
  }

  /**
   * 从 Set-Cookie 响应头解析出 key=value 片段。
   * 多条 cookie 以逗号分隔，但 cookie 值里也可能含逗号，
   * 用"逗号后紧跟非空 key=value"的正则边界分割（参考 HiXD saveResponseCookies）。
   */
  private static parseSetCookies(raw: string): string {
    if (raw.length === 0) {
      return '';
    }
    const pairs: string[] = [];
    // 按 ", key=" 边界分割多条 Set-Cookie
    const parts: string[] = raw.split(/,(?=\s*[^,;=]+=)/);
    for (let i = 0; i < parts.length; i++) {
      const seg: string = parts[i].split(';')[0].trim();
      if (seg.indexOf('=') > 0) {
        pairs.push(seg);
      }
    }
    return pairs.join('; ');
  }

  /** 把新收到的 cookie 合并进会话（同名覆盖），返回合并后的完整 cookie */
  private static mergeCookies(setCookieHeader: string): string {
    if (setCookieHeader.length === 0) {
      return HttpClient.cookie;
    }
    const fresh: string = HttpClient.parseSetCookies(setCookieHeader);
    if (fresh.length === 0) {
      return HttpClient.cookie;
    }
    // 合并：已有 cookie 保留，新 cookie 同名覆盖
    const map: Record<string, string> = {};
    const existing: string[] = HttpClient.cookie.split(';');
    for (let i = 0; i < existing.length; i++) {
      const kv: string = existing[i].trim();
      const eq: number = kv.indexOf('=');
      if (eq > 0) {
        map[kv.substring(0, eq)] = kv.substring(eq + 1);
      }
    }
    const freshPairs: string[] = fresh.split(';');
    for (let i = 0; i < freshPairs.length; i++) {
      const kv: string = freshPairs[i].trim();
      const eq: number = kv.indexOf('=');
      if (eq > 0) {
        map[kv.substring(0, eq)] = kv.substring(eq + 1);
      }
    }
    const keys: string[] = Object.keys(map);
    const out: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      out.push(`${keys[i]}=${map[keys[i]]}`);
    }
    HttpClient.cookie = out.join('; ');
    return HttpClient.cookie;
  }

  private static async request(url: string, method: http.RequestMethod, body: string,
    extraHeader: Record<string, string>): Promise<HttpResult> {
    // 功能浏览模式默认断网；隐藏调试模式（AppState.debugNetwork）开启后允许联网
    if (HttpClient.offlineMode && !AppState.debugNetwork) {
      return { code: 0, body: '', cookie: HttpClient.cookie };
    }
    const t0: number = Date.now();
    const client: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: method,
        header: HttpClient.buildHeader(extraHeader),
        extraData: body,
        connectTimeout: 15000,
        readTimeout: 20000,
        expectDataType: http.HttpDataType.STRING
      };
      // 关键：拦截重定向链上每个响应的 Set-Cookie，立即合并进会话。
      // HarmonyOS 自动跟随 302 时，登录成功的 JSESSIONID 正是在重定向
      // 响应头里下发，若不在此收集，最终 response.header 里会丢失。
      client.on('headersReceive', (header: Object) => {
        try {
          const hdr: Record<string, Object> = header as Record<string, Object>;
          const sc: Object | undefined = hdr['set-cookie'] ?? hdr['Set-Cookie'];
          if (sc !== undefined) {
            HttpClient.mergeCookies(String(sc));
          }
        } catch (e) {
          // 单次拦截失败不影响请求
        }
      });
      const response: http.HttpResponse = await client.request(url, options);
      let text: string = '';
      if (typeof response.result === 'string') {
        text = response.result as string;
      } else {
        text = JSON.stringify(response.result);
      }
      const cost: number = Date.now() - t0;
      // 日志调试：对齐开发者工具网络面板——URL / Method / 状态 / 请求头 / 响应头 / 耗时 / 响应片段
      const reqHeaders: Record<string, string> = HttpClient.buildHeader(extraHeader);
      LogStore.logNet('网络', '请求', '成功',
        {
          method: HttpClient.methodName(method),
          url: url,
          status: `${response.responseCode}`,
          cost: `${cost}ms`,
          reqHeaders: LogStore.reqHeaderSummary(reqHeaders),
          respHeaders: LogStore.respHeaderSummary(response.header as Object),
          body: text
        });
      return { code: response.responseCode as number, body: text, cookie: HttpClient.cookie };
    } catch (e) {
      const cost: number = Date.now() - t0;
      LogStore.logNet('网络', '请求', '异常',
        {
          method: HttpClient.methodName(method),
          url: url,
          status: '',
          cost: `${cost}ms`,
          error: LogStore.errorOf(e as Object)
        });
      throw e as Error;
    } finally {
      client.destroy();
    }
  }

  /** RequestMethod → 名称（日志用） */
  static methodName(m: http.RequestMethod): string {
    if (m === http.RequestMethod.GET) {
      return 'GET';
    }
    if (m === http.RequestMethod.POST) {
      return 'POST';
    }
    if (m === http.RequestMethod.PUT) {
      return 'PUT';
    }
    if (m === http.RequestMethod.DELETE) {
      return 'DELETE';
    }
    return 'OTHER';
  }

  /** 发送 GET 请求，返回响应 JSON 与状态码 */
  static get(path: string): Promise<HttpResult> {
    const url: string = path.startsWith('http') ? path : `${HttpClient.baseUrl}${path}`;
    return HttpClient.request(url, http.RequestMethod.GET, '', {});
  }

  /**
   * 拉取图片（验证码）并返回 base64（不含 data: 前缀）。
   * 验证码图片与会话 Cookie 绑定，这里复用同一会话，确保用户输入的验证码与服务端一致。
   * 失败时返回空字符串。
   */
  static async getImageBase64(path: string): Promise<string> {
    if (HttpClient.offlineMode && !AppState.debugNetwork) {
      return '';
    }
    const url: string = path.startsWith('http') ? path : `${HttpClient.baseUrl}${path}`;
    const client: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: HttpClient.buildHeader({ 'Accept': 'image/png,image/jpeg,image/*' }),
        connectTimeout: 15000,
        readTimeout: 20000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      };
      client.on('headersReceive', (header: Object) => {
        try {
          const hdr: Record<string, Object> = header as Record<string, Object>;
          const sc: Object | undefined = hdr['set-cookie'] ?? hdr['Set-Cookie'];
          if (sc !== undefined) {
            HttpClient.mergeCookies(String(sc));
          }
        } catch (e) {
          // ignore
        }
      });
      const response: http.HttpResponse = await client.request(url, options);
      if (response.responseCode === 200 && response.result instanceof ArrayBuffer) {
        const buf: ArrayBuffer = response.result as ArrayBuffer;
        const bytes: Uint8Array = new Uint8Array(buf);
        return new util.Base64Helper().encodeToString(bytes);
      }
    } catch (e) {
      // 验证码获取失败时返回空串，由上层决定是否提示
    } finally {
      client.destroy();
    }
    return '';
  }

  /** 表单提交，教务系统登录基本都用这个 */
  static postForm(path: string, form: Record<string, string>): Promise<HttpResult> {
    return HttpClient.postFormExtra(path, form, {});
  }

  /** 表单提交（可附加自定义请求头，如 X-Requested-With 等） */
  static postFormExtra(path: string, form: Record<string, string>,
    extraHeader: Record<string, string>): Promise<HttpResult> {
    const url: string = path.startsWith('http') ? path : `${HttpClient.baseUrl}${path}`;
    // 日志调试：记录脱敏表单参数（密码/账号打码），便于复现请求
    LogStore.logNet('网络', '表单', '提交',
      {
        method: 'POST',
        url: url,
        params: LogStore.paramsSummary(form, ['mm', 'yhm', 'password'])
      });
    const keys: string[] = Object.keys(form);
    const parts: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      parts.push(`${encodeURIComponent(keys[i])}=${encodeURIComponent(form[keys[i]])}`);
    }
    const header: Record<string, string> = {};
    header['Content-Type'] = 'application/x-www-form-urlencoded';
    const extraKeys: string[] = Object.keys(extraHeader);
    for (let i = 0; i < extraKeys.length; i++) {
      header[extraKeys[i]] = extraHeader[extraKeys[i]];
    }
    return HttpClient.request(url, http.RequestMethod.POST, parts.join('&'), header);
  }

  /**
   * 表单提交，返回二进制（ArrayBuffer）响应（导出 Excel 等）。
   * 失败时 data 为 null，code/body 提供诊断（body 截断前 600 字符）。
   */
  static async postFormBinary(path: string, form: Record<string, string>,
    extraHeader: Record<string, string>): Promise<BinaryResult> {
    const fail: BinaryResult = { data: null, code: 0, body: '' };
    if (HttpClient.offlineMode && !AppState.debugNetwork) {
      return fail;
    }
    const url: string = path.startsWith('http') ? path : `${HttpClient.baseUrl}${path}`;
    const keys: string[] = Object.keys(form);
    const parts: string[] = [];
    for (let i = 0; i < keys.length; i++) {
      parts.push(`${encodeURIComponent(keys[i])}=${encodeURIComponent(form[keys[i]])}`);
    }
    const header: Record<string, string> = {};
    header['Content-Type'] = 'application/x-www-form-urlencoded';
    const extraKeys: string[] = Object.keys(extraHeader);
    for (let i = 0; i < extraKeys.length; i++) {
      header[extraKeys[i]] = extraHeader[extraKeys[i]];
    }
    const client: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: HttpClient.buildHeader(header),
        extraData: parts.join('&'),
        connectTimeout: 15000,
        readTimeout: 30000,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      };
      client.on('headersReceive', (h: Object) => {
        try {
          const hdr: Record<string, Object> = h as Record<string, Object>;
          const sc: Object | undefined = hdr['set-cookie'] ?? hdr['Set-Cookie'];
          if (sc !== undefined) {
            HttpClient.mergeCookies(String(sc));
          }
        } catch (e) {
          // ignore
        }
      });
      const response: http.HttpResponse = await client.request(url, options);
      const code: number = response.responseCode as number;
      if (code === 200 && response.result instanceof ArrayBuffer) {
        return { data: response.result as ArrayBuffer, code: code, body: '' };
      }
      // 失败：非 200 或 result 不是二进制（如被重定向到登录页返回 HTML）
      let diag: string = '';
      if (typeof response.result === 'string') {
        diag = (response.result as string).substring(0, 600);
      }
      return { data: null, code: code, body: diag };
    } catch (e) {
      return fail;
    } finally {
      client.destroy();
    }
  }
}
