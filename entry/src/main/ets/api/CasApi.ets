/**
 * CasApi —— 原生 CAS 统一身份认证登录（不依赖 WebView）
 *
 * 流程：
 *  1) GET  CAS 登录页，提取 pwdEncryptSalt + execution 隐藏域；
 *  2) checkNeedCaptcha 判断是否需要验证码（需要则抛出 CasCaptchaRequiredError，UI 转网页版兜底）；
 *  3) AES 加密密码，POST 登录表单（rememberMe 对应"7天免登录"）；
 *  4) 手动跟随 302 链（autoRedirect=false），按 host+path 维护 Cookie 罐，最终在 authserver 拿到 CASTGC（TGT）；
 *  5) 携带 CASTGC GET jwxt.xjau.edu.cn/sso/jziotlogin，后台自动打开教务系统，
 *     按路径区分取出 jwglxt 的 JSESSIONID + route（关键：/sso 与 /jwglxt 的 JSESSIONID 路径不同，必须按路径隔离）。
 *
 * 使用 @kit.RemoteCommunicationKit(rcp)：autoRedirect 默认 true，这里显式关闭并手动跟随，
 * 以在每一步注入/收集"按路径匹配"的 Cookie，规避 HarmonyOS http 自动跟随 302 时
 * 同名 JSESSIONID 跨路径串味导致无限重定向/901 的问题。
 */
import rcp from '@hms.collaboration.rcp';
import { aesEncryptPassword } from '../common/AesUtil';
import { LogStore } from '../common/LogStore';
import { Const } from '../common/Constants';

/** CAS（统一身份认证）登录入口 */
const CAS_LOGIN_URL: string =
  'https://authserver.xjau.edu.cn/authserver/login?service=https%3A%2F%2Frhmh.xjau.edu.cn%2Flogin';
/** 浏览器 UA（与服务端交互需要，部分网关按 UA 放行） */
const CAS_UA: string =
  'Mozilla/5.0 (Linux; HarmonyOS) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

/** 需要验证码时抛出，调用方据此切换到网页版登录兜底 */
export class CasCaptchaRequiredError extends Error {
  constructor(msg: string) {
    super(msg);
    this.name = 'CasCaptchaRequiredError';
  }
}

/** 一跳响应 */
interface Hop {
  status: number;
  headers: rcp.ResponseHeaders;
  body: string;
  url: string;
}

/** Cookie 罐中的单条记录（按 host+path 隔离同名 Cookie） */
interface CookieEntry {
  name: string;
  value: string;
  path: string;
}

/** 解析后的 URL 组成部分 */
interface UrlParts {
  host: string;
  path: string;
}

/** 一次 CAS 登录的产出：教务系统会话 Cookie 串 + CASTGC（7天免登录用） */
export interface CasLoginResult {
  cookie: string;
  castgc: string;
}

/** 简易 Cookie 罐：host -> (name|path -> {name,value,path})，按路径隔离同名 Cookie */
class CookieJar {
  private jar: Map<string, Map<string, CookieEntry>> = new Map();

  private hostOf(url: string): string {
    const idx: number = url.indexOf('://');
    const rest: string = idx >= 0 ? url.substring(idx + 3) : url;
    const slash: number = rest.indexOf('/');
    return slash >= 0 ? rest.substring(0, slash) : rest;
  }

  private reqPathOf(url: string): string {
    const idx: number = url.indexOf('://');
    const rest: string = idx >= 0 ? url.substring(idx + 3) : url;
    const slash: number = rest.indexOf('/');
    if (slash < 0) {
      return '/';
    }
    const q: number = rest.indexOf('?', slash);
    return q >= 0 ? rest.substring(slash, q) : rest.substring(slash);
  }

  /** 从响应头解析并存入 Set-Cookie（支持多条、带 path 属性） */
  setCookies(url: string, header: rcp.ResponseHeaders): void {
    const sc: string | string[] | undefined = header['set-cookie'] as (string | string[] | undefined);
    if (sc === undefined) {
      return;
    }
    const list: string[] = Array.isArray(sc) ? sc : [String(sc)];
    const host: string = this.hostOf(url);
    if (!this.jar.has(host)) {
      this.jar.set(host, new Map());
    }
    const m: Map<string, CookieEntry> = this.jar.get(host)!;
    for (let i = 0; i < list.length; i++) {
      const seg: string[] = list[i].split(';');
      const eq: number = seg[0].indexOf('=');
      if (eq <= 0) {
        continue;
      }
      const name: string = seg[0].substring(0, eq).trim();
      const value: string = seg[0].substring(eq + 1).trim();
      let path: string = '/';
      for (let j = 1; j < seg.length; j++) {
        const t: string = seg[j].trim();
        if (t.toLowerCase().startsWith('path=')) {
          path = t.substring(5).trim();
          if (path.length === 0) {
            path = '/';
          }
        }
      }
      m.set(name + '|' + path, { name, value, path });
    }
  }

  /** 取某个请求 URL 应携带的 Cookie 头（按路径前缀匹配，path=/ 全匹配） */
  cookieHeader(url: string): string {
    const host: string = this.hostOf(url);
    const m: Map<string, CookieEntry> | undefined = this.jar.get(host);
    if (m === undefined) {
      return '';
    }
    const reqPath: string = this.reqPathOf(url);
    const out: string[] = [];
    m.forEach((c) => {
      if (reqPath.startsWith(c.path) || c.path === '/') {
        out.push(c.name + '=' + c.value);
      }
    });
    return out.join('; ');
  }

  /** 直接注入一条 cookie（冷启动自动重登时复用持久化 CASTGC） */
  putCookie(host: string, name: string, value: string, path: string = '/'): void {
    if (!this.jar.has(host)) {
      this.jar.set(host, new Map());
    }
    this.jar.get(host)!.set(name + '|' + path, { name, value, path });
  }

  /** 取某 host 下指定 path 的某 name Cookie 值 */
  cookieValue(host: string, path: string, name: string): string {
    const full: string = this.cookieHeader('https://' + host + path);
    const parts: string[] = full.split(';');
    for (let i = 0; i < parts.length; i++) {
      const seg: string = parts[i].trim();
      const eq: number = seg.indexOf('=');
      if (eq > 0 && seg.substring(0, eq).trim() === name) {
        return seg.substring(eq + 1).trim();
      }
    }
    return '';
  }
}

/** 解析绝对 URL 的 host 与 path（ArkTS 不依赖标准 URL） */
function parseUrl(url: string): UrlParts {
  const idx: number = url.indexOf('://');
  const rest: string = idx >= 0 ? url.substring(idx + 3) : url;
  const slash: number = rest.indexOf('/');
  const host: string = slash >= 0 ? rest.substring(0, slash) : rest;
  let path: string = slash >= 0 ? rest.substring(slash) : '/';
  const q: number = path.indexOf('?');
  if (q >= 0) {
    path = path.substring(0, q);
  }
  return { host, path };
}

export class CasApi {
  /** 执行原生 CAS 登录，返回教务系统会话 Cookie 串（含 jwglxt JSESSIONID 与 route）与 CASTGC（用于 7天免登录）。 */
  static async nativeCasLogin(account: string, password: string, remember7d: boolean): Promise<CasLoginResult> {
    const session: rcp.Session = rcp.createSession({
      requestConfiguration: {
        transfer: { autoRedirect: false } as rcp.TransferConfiguration
      }
    });
    const jar: CookieJar = new CookieJar();
    try {
      // ── STEP 1: 取登录页，拿 salt / execution ──
      const p1: Hop = await CasApi.fetch(session, jar, CAS_LOGIN_URL, 'GET');
      const salt: string = CasApi.pick(p1.body, /name="pwdEncryptSalt"\s+value="([^"]*)"/) ||
        CasApi.pick(p1.body, /id="pwdEncryptSalt"\s+value="([^"]*)"/);
      const execution: string = CasApi.pick(p1.body, /name="execution"\s+value="([^"]*)"/);
      const lt: string = CasApi.pick(p1.body, /name="lt"\s+value="([^"]*)"/);
      if (salt.length === 0 || execution.length === 0) {
        throw new Error('无法解析 CAS 登录页（salt/execution 缺失）');
      }

      // ── STEP 2: 是否需要验证码 ──
      const capUrl: string = `https://authserver.xjau.edu.cn/authserver/checkNeedCaptcha.htl?username=${encodeURIComponent(account)}&_=${new Date().getTime()}`;
      const cap: Hop = await CasApi.fetch(session, jar, capUrl, 'GET', {
        'Referer': CAS_LOGIN_URL,
        'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'application/json'
      });
      const needCap: boolean = /"isNeed"\s*:\s*true/.test(cap.body);
      if (needCap) {
        throw new CasCaptchaRequiredError('账号需要验证码，请改用网页版登录');
      }

      // ── STEP 3: 加密密码并 POST 登录 ──
      const enc: string = await aesEncryptPassword(password, salt);
      const form: string = 'username=' + encodeURIComponent(account) +
        '&password=' + encodeURIComponent(enc) +
        '&captcha=&rememberMe=' + (remember7d ? 'true' : 'false') +
        '&_eventId=submit&cllt=userNameLogin&dllt=generalLogin&lt=' + encodeURIComponent(lt) +
        '&execution=' + encodeURIComponent(execution);
      const p2: Hop = await CasApi.fetch(session, jar, CAS_LOGIN_URL, 'POST', {
        'Referer': CAS_LOGIN_URL,
        'Origin': 'https://authserver.xjau.edu.cn',
        'Content-Type': 'application/x-www-form-urlencoded'
      }, form);

      // 登录失败（密码错/账号锁）：CAS 通常返回 200 + 错误提示
      if (p2.status >= 200 && p2.status < 300) {
        const tip: string = CasApi.pick(p2.body, /id="showErrorTip"[^>]*>([^<]*)</);
        if (/用户名|密码|账号|错误|锁定|冻结/.test(p2.body) || tip.length > 0) {
          throw new Error(tip.length > 0 ? tip : '学号或密码错误');
        }
      }

      // 跟随 302 链，落到 rhmh 服务大厅，期间收集 CASTGC
      await CasApi.follow(session, jar, p2, 12);
      const castgc: string = jar.cookieValue('authserver.xjau.edu.cn', '/authserver', 'CASTGC');
      if (castgc.length === 0) {
        throw new Error('CAS 登录未返回 CASTGC（登录可能失败）');
      }

      LogStore.log('登录', 'CAS', '成功', '已获取 CASTGC，正在后台打开教务系统');

      // ── STEP 4: 后台自动打开教务系统（服务大厅→新教务系统 真实跳转地址，带 gid_）──
      const p3: Hop = await CasApi.fetch(session, jar, Const.JW_BRIDGE_FROM_HALL_URL, 'GET', {
        'Referer': 'https://rhmh.xjau.edu.cn/'
      });
      await CasApi.follow(session, jar, p3, 20);

      // 取 jwglxt 的 JSESSIONID + route（按 /jwglxt 路径匹配）
      const jwglxtSid: string = jar.cookieValue('jwxt.xjau.edu.cn', '/jwglxt', 'JSESSIONID');
      const route: string = jar.cookieValue('jwxt.xjau.edu.cn', '/', 'route');
      if (jwglxtSid.length === 0) {
        // 兜底：取 jwxt 域下任意 JSESSIONID
        const anySid: string = jar.cookieValue('jwxt.xjau.edu.cn', '/', 'JSESSIONID');
        if (anySid.length === 0) {
          throw new Error('教务系统会话建立失败（未拿到 jwxt JSESSIONID）');
        }
        return { cookie: 'JSESSIONID=' + anySid + (route.length > 0 ? '; route=' + route : ''), castgc };
      }
      return { cookie: 'JSESSIONID=' + jwglxtSid + (route.length > 0 ? '; route=' + route : ''), castgc };
    } finally {
      try {
        session.close();
      } catch (e) {
        // ignore
      }
    }
  }

  /** 冷启动自动重登：仅用持久化的 CASTGC 重新桥接 jwxt 会话（不重新输入密码）。
   *  走服务大厅→新教务系统真实跳转地址（带 gid_），用 CASTGC 自动 SSO 换全新 jwglxt 会话。 */
  static async silentRelogin(castgc: string): Promise<string> {
    const session: rcp.Session = rcp.createSession({
      requestConfiguration: {
        transfer: { autoRedirect: false } as rcp.TransferConfiguration
      }
    });
    const jar: CookieJar = new CookieJar();
    jar.putCookie('authserver.xjau.edu.cn', 'CASTGC', castgc, '/authserver');
    try {
      const p3: Hop = await CasApi.fetch(session, jar, Const.JW_BRIDGE_FROM_HALL_URL, 'GET', {
        'Referer': 'https://rhmh.xjau.edu.cn/'
      });
      await CasApi.follow(session, jar, p3, 20);
      // 关键：必须带上本次桥接产生的 route（负载均衡粘滞 cookie），
      // 与登录成功时 nativeCasLogin 返回的 cookie 格式保持一致；
      // 否则无 route 时请求被路由到其它后端节点，JSESSIONID 不被识别，取数全部失败。
      const route: string = jar.cookieValue('jwxt.xjau.edu.cn', '/', 'route');
      const routePart: string = route.length > 0 ? '; route=' + route : '';
      const jwglxtSid: string = jar.cookieValue('jwxt.xjau.edu.cn', '/jwglxt', 'JSESSIONID');
      if (jwglxtSid.length === 0) {
        const anySid: string = jar.cookieValue('jwxt.xjau.edu.cn', '/', 'JSESSIONID');
        if (anySid.length === 0) {
          throw new Error('CASTGC 自动重登失败');
        }
        return 'JSESSIONID=' + anySid + routePart;
      }
      return 'JSESSIONID=' + jwglxtSid + routePart;
    } finally {
      try {
        session.close();
      } catch (e) {
        // ignore
      }
    }
  }

  // ── 内部工具 ──

  private static async fetch(session: rcp.Session, jar: CookieJar, url: string, method: 'GET' | 'POST',
    extraHeaders: Record<string, string> = {}, body?: string): Promise<Hop> {
    const ck: string = jar.cookieHeader(url);
    const headers: rcp.RequestHeaders = {
      'User-Agent': CAS_UA,
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
      'Accept-Language': 'zh-CN,zh;q=0.9'
    };
    (Object.keys(extraHeaders) as string[]).forEach((k: string) => {
      headers[k] = extraHeaders[k];
    });
    if (ck.length > 0) {
      headers['Cookie'] = ck;
    }
    const request: rcp.Request = new rcp.Request(url, method, headers, (body as rcp.RequestContent) ?? '');
    const resp: rcp.Response = await session.fetch(request);
    jar.setCookies(url, resp.headers);
    const text: string = resp.toString() ?? '';
    return { status: resp.statusCode ?? 0, headers: resp.headers, body: text, url };
  }

  /** 手动跟随 302 链（redirect 变 GET，http 升 https）。封顶 max 跳。 */
  private static async follow(session: rcp.Session, jar: CookieJar, start: Hop, max: number): Promise<void> {
    let cur: Hop = start;
    for (let i = 0; i < max; i++) {
      if (cur.status >= 300 && cur.status < 400) {
        const loc: string | string[] | undefined = cur.headers['location'] as (string | string[] | undefined);
        if (loc === undefined) {
          return;
        }
        let next: string = Array.isArray(loc) ? loc[0] : String(loc);
        if (next.startsWith('/')) {
          const u: UrlParts = parseUrl(cur.url);
          next = `https://${u.host}${next}`;
        }
        // 明文 http 在 rcp 下被禁（1007900201），统一升 https
        if (next.startsWith('http://')) {
          next = 'https://' + next.substring('http://'.length);
        }
        cur = await CasApi.fetch(session, jar, next, 'GET');
        continue;
      }
      return;
    }
  }

  private static pick(html: string, re: RegExp): string {
    const m: RegExpMatchArray | null = html.match(re);
    return m ? m[1] : '';
  }
}
