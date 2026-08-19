/**
 * 教务数据接口层（唯一的数据出口）
 *
 * ── 后续接入真实教务系统时，只需要改这个文件 ──
 * 1. 把 USE_MOCK 置为 false；
 * 2. 把 HttpClient.baseUrl 改成学校教务系统地址；
 * 3. 在每个方法的"真实分支"里已是"请求 + JSON 解析 -> 模型"逻辑（基于已探测的正方字段映射）。
 * UI 层完全不感知数据来自 mock 还是真实网络。
 *
 * 已验证的正方字段映射（zftal-ui v5 / 新农大 jwxt.xjau.edu.cn）：
 *  - 课表  POST /jwglxt/kbcx/xskbcx_cxXsgrkb.html {xnm,xqm} -> { xsxx, kbList[] }
 *           kbList: kcmc=课程, xm=教师, cdmc=教室, xqj=星期(1-7), jcs="1-2"节次, zcd="1-5周,8-14周"周次
 *  - 成绩  POST /jwglxt/cjcx/cjcx_cxDgXscj.html {doType:query,xnm,xqm,queryModel.showCount:100} -> { items[] }
 *           items: kcmc, cj=分数, jd=绩点, xf=学分, kcxzmc=属性, ksxz=考试性质(重修/正常)
 *  - 考试  POST /jwglxt/kwgl/kscx_cxXsksxxIndex.html {doType:query,xnm,xqm} -> { items[] }
 *           items: ksmc=考试名, kssj=时间, cdbh=考场, zwh=座位, ksfs=方式
 *  - 学生信息含在课表 xsxx 中（XM/BJMC/ZYMC/NJDM_ID...），正方不返回辅导员字段
 *
 * 待完成：学业情况(xsxyqk 返回 911)；通知公告(HTML 解析)。
 */
import { AcademicReport, CourseItem, CreditCategory, EmptyRoomCondition, EmptyRoomConditions, EmptyRoomItem, EmptyRoomQueryParams, EmptyRoomResult, ExamItem, LoginResult, NoticeItem, ScoreItem, SectionInfo, TermInfo, TermScore,
  UserProfile, WeekInfo } from '../model/Models';
import { TeachingCalendar } from '../model/TeachingCalendar';
import { MockData } from '../mock/MockData';
import { AppState } from '../common/AppState';
import { DataStore } from '../common/DataStore';
import { DateUtil } from '../common/DateUtil';
import { EMPTY_REPORT } from '../model/Empty';
import { Const } from '../common/Constants';
import { HttpClient, HttpResult, BinaryResult } from './HttpClient';
import { RsaUtil } from '../common/RsaUtil';
import { LogStore } from '../common/LogStore';
import zlib from '@ohos.zlib';
import { fileIo } from '@kit.CoreFileKit';

/** 正方下发的 RSA 公钥 */
interface RsaPublicKey {
  modulus: string;
  exponent: string;
}

/** 校历缓存结构：来源（最新校历文章/PDF URL）+ 转换结果数据 */
interface JwcCalCacheStore {
  sourceArticleUrl: string;
  sourcePdfUrl: string;
  data: string;
}

export class JwApi {
  /** demo 开关：true = 使用本地模拟数据。默认 false（直连真实教务系统）。
   *  登录页底部"Demo 体验"入口会临时置为 true；真实登录时会复位为 false。 */
  static USE_MOCK: boolean = false;

  private static term: TermInfo = DateUtil.buildCurrentTerm();

  private static delay<T>(data: T, ms: number): Promise<T> {
    return new Promise<T>((resolve: (value: T) => void) => {
      setTimeout(() => {
        resolve(data);
      }, ms);
    });
  }

  /** 学期 id（如 2025-2026-1）-> 正方 xqm：第一学期=3，第二学期=12，第三/短学期=16 */
  private static xqmOf(termId: string): string {
    const parts: string[] = termId.split('-');
    const idx: string = parts[parts.length - 1];
    if (idx === '1') {
      return '3';
    }
    if (idx === '2') {
      return '12';
    }
    return '16';
  }


  /**
   * 本地生成学年学期列表（不依赖网络，与正方 select 结构一致）。
   * 学年 xnm = 起始年（如 "2026" -> "2026-2027"），范围：入学年 .. 当前学年+1。
   * 每学期含第一/第二学期；当前学年额外含短学期。
   *
   * startDate 取合理开学日（第一学期 9-01、第二学期次年 3-01），
   * 保证 DateUtil.weekOfTerm 能正确算周次（否则空串解析为 NaN，课表空白）。
   */
  /** 生成本地学期列表（mock 模式使用） */
  static buildLocalTerms(): TermInfo[] {
    const now: Date = new Date();
    const curYear: number = now.getFullYear();
    const month: number = now.getMonth() + 1;
    // 当前学年起始年：9月及以后算当年，否则上一年
    const curStartYear: number = month >= 9 ? curYear : curYear - 1;
    // 入学年：从 AppState.profile.grade（"2023级"）解析，失败回退 curStartYear-3
    let startYear: number = curStartYear - 3;
    if (AppState.profile !== null && AppState.profile.grade.length > 0) {
      const m: RegExpExecArray | null = /(\d{4})/.exec(AppState.profile.grade);
      if (m !== null) {
        const y: number = Number(m[1]);
        if (!isNaN(y) && y >= 2000) {
          startYear = y;
        }
      }
    }
    const list: TermInfo[] = [];
    for (let y: number = curStartYear + 1; y >= startYear; y--) {
      for (let s: number = 1; s <= 2; s++) {
        const startDate: string = s === 1 ? `${y}-09-01` : `${y + 1}-03-01`;
        list.push({
          id: `${y}-${y + 1}-${s}`,
          label: `${y}-${y + 1}学年 ${s === 1 ? '第一' : '第二'}学期`,
          startDate: startDate,
          totalWeeks: 20
        });
      }
    }
    return list;
  }

  /** 把"1-5周,8-14周(双)"解析成周次数组与原文 */
  private static parseWeeks(zcd: string): WeekInfo {
    const text: string = zcd ?? '';
    const weeks: number[] = [];
    if (text.length === 0) {
      return { weeks: weeks, text: '' };
    }
    const segs: string[] = text.split(',');
    const reg: RegExp = /(\d+)\s*-\s*(\d+)/;
    for (const seg of segs) {
      const m: ESObject | null = seg.match(reg);
      if (m !== null) {
        const from: number = Number(m[1]);
        const to: number = Number(m[2]);
        const odd: boolean = seg.indexOf('单') >= 0;
        const even: boolean = seg.indexOf('双') >= 0;
        for (let w = from; w <= to; w++) {
          if (odd && w % 2 === 0) {
            continue;
          }
          if (even && w % 2 === 1) {
            continue;
          }
          weeks.push(w);
        }
      }
    }
    return { weeks: weeks, text: text };
  }

  /** 把"1-2"解析成起始/结束节次 */
  private static parseSections(jcs: string): SectionInfo {
    const reg: RegExp = /(\d+)\s*-\s*(\d+)/;
    const m: ESObject | null = (jcs ?? '').match(reg);
    if (m !== null) {
      return { start: Number(m[1]), end: Number(m[2]) };
    }
    const single: number = Number(jcs);
    if (!isNaN(single)) {
      return { start: single, end: single };
    }
    return { start: 1, end: 1 };
  }

  private static mapCourse(raw: ESObject): CourseItem {
    const zcd: string = (raw['zcd'] as string) ?? '';
    const jcs: string = (raw['jcs'] as string) ?? '1';
    const xqj: number = Number(raw['xqj'] ?? 1);
    const weeksInfo = JwApi.parseWeeks(zcd);
    const secInfo = JwApi.parseSections(jcs);
    const name: string = (raw['kcmc'] as string) ?? '未知课程';
    const teacher: string = (raw['xm'] as string) ?? '';
    const location: string = (raw['cdmc'] as string) ?? '';
    return {
      id: `${name}_${teacher}_${xqj}_${jcs}`,
      name: name,
      teacher: teacher,
      location: location,
      weekday: xqj,
      startSection: secInfo.start,
      endSection: secInfo.end,
      weeks: weeksInfo.weeks,
      weeksText: weeksInfo.text,
      courseType: (raw['kcxzmc'] as string) ?? (raw['kcxz'] as string) ?? '必修',
      credit: Number(raw['xf'] ?? 0),
      colorIndex: (xqj + name.length) % 8
    };
  }

  private static mapExam(raw: ESObject): ExamItem {
    const kssj: string = (raw['kssj'] as string) ?? '';
    let date: string = '';
    let timeRange: string = '';
    const sp: string[] = kssj.split(' ');
    if (sp.length >= 2) {
      date = sp[0];
      timeRange = sp[1];
    } else if (sp.length === 1) {
      date = sp[0];
    }
    return {
      id: `${raw['ksmc']}_${kssj}`,
      courseName: (raw['ksmc'] as string) ?? '未知考试',
      date: date,
      timeRange: timeRange,
      location: (raw['cdbh'] as string) ?? '待定',
      seat: (raw['zwh'] as string) ?? '待定',
      examType: (raw['ksfs'] as string) ?? '考试',
      teacher: (raw['jsxm'] as string) ?? ''
    };
  }

  private static mapScore(raw: ESObject, termId: string): ScoreItem {
    const cj: number = Number(raw['cj']);
    const valid: boolean = !isNaN(cj);
    return {
      id: `${raw['kcmc']}_${raw['xnmmc']}_${raw['xqmmc']}`,
      courseName: (raw['kcmc'] as string) ?? '未知课程',
      credit: Number(raw['xf'] ?? 0),
      score: valid ? cj : -1,
      scoreText: valid ? `${cj}` : (raw['cj'] as string),
      gradePoint: Number(raw['jd'] ?? 0),
      courseType: (raw['kcxzmc'] as string) ?? '必修',
      examType: (raw['ksxz'] as string) ?? '正常考试',
      // 任课教师名：教务返回的字段是 jsxm，xm 是学生本人名字（不能错位）
      teacher: (raw['jsxm'] as string) ?? '',
      termId: termId,
      kclbmc: (raw['kclbmc'] as string) ?? ''
    };
  }

  /**
   * 按课程名生成稳定的颜色索引（0-7），同名课程始终返回同一颜色。
   * 使用 djb2 hash 算法 → 模 8 取索引，颜色板与 Const.COURSE_BG / COURSE_FG 对齐。
   * 课程名做 trim 处理避免空格差异；空名回退到 0。
   */
  static colorIndexOf(name: string): number {
    const key: string = (name ?? '').trim();
    if (key.length === 0) {
      return 0;
    }
    let hash: number = 5381;
    for (let i = 0; i < key.length; i++) {
      hash = ((hash << 5) + hash + key.charCodeAt(i)) & 0x7FFFFFFF;
    }
    return hash % 8;
  }

  /**
   * 课程颜色索引缓存：保证用户首次打开应用时同名课程使用一致颜色，
   * 同时减少 hash 计算（虽然 djb2 极快，但缓存是 O(1) 直查）。
   * 格式：{ "课程名": "颜色索引(0-7)", ... }
   */
  static loadColorMap(): Record<string, number> {
    const raw: string = DataStore.loadJSON(DataStore.KEY_COURSE_COLOR_MAP);
    if (raw.length === 0) {
      return {};
    }
    try {
      const parsed: Record<string, number> = JSON.parse(raw) as Record<string, number>;
      return parsed;
    } catch (e) {
      return {};
    }
  }

  static saveColorMap(map: Record<string, number>): void {
    DataStore.cacheJSON(DataStore.KEY_COURSE_COLOR_MAP, JSON.stringify(map));
  }

  /**
   * ArrayBuffer → base64 字符串（用于图片转 DataStore 持久化）。
   * 逐字节读 Uint8Array，拼接标准 base64 字符表。
   */
  static arrayBufferToBase64(buf: ArrayBuffer): string {
    const u8: Uint8Array = new Uint8Array(buf);
    const chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let out: string = '';
    let i: number = 0;
    for (; i + 2 < u8.length; i += 3) {
      const b0: number = u8[i];
      const b1: number = u8[i + 1];
      const b2: number = u8[i + 2];
      out += chars.charAt(b0 >> 2);
      out += chars.charAt(((b0 & 0x03) << 4) | (b1 >> 4));
      out += chars.charAt(((b1 & 0x0F) << 2) | (b2 >> 6));
      out += chars.charAt(b2 & 0x3F);
    }
    if (i < u8.length) {
      const b0: number = u8[i];
      const b1: number = i + 1 < u8.length ? u8[i + 1] : 0;
      out += chars.charAt(b0 >> 2);
      out += chars.charAt(((b0 & 0x03) << 4) | (b1 >> 4));
      out += i + 1 < u8.length ? chars.charAt(((b1 & 0x0F) << 2)) : '=';
      out += '=';
    }
    return out;
  }

  /**
   * 确保课程名有颜色索引：先读缓存，命中直接返回；未命中按 name hash 计算并写入缓存。
   * 用于 ScheduleView 渲染时按 course.name 取颜色。
   */
  static ensureColorIndex(name: string): number {
    const trimmed: string = (name ?? '').trim();
    if (trimmed.length === 0) {
      return 0;
    }
    const map: Record<string, number> = JwApi.loadColorMap();
    const cached: number | undefined = map[trimmed];
    if (cached !== undefined) {
      return cached;
    }
    const idx: number = JwApi.colorIndexOf(trimmed);
    map[trimmed] = idx;
    JwApi.saveColorMap(map);
    return idx;
  }

  /** 登录教务系统 */
  static async login(account: string, password: string, captcha: string = ''): Promise<LoginResult> {
    if (JwApi.USE_MOCK) {
      const ok: boolean = account.length >= 6 && password.length >= 6;
      const result: LoginResult = {
        success: ok,
        message: ok ? '登录成功' : '学号或密码格式不正确（demo：学号 6 位以上、密码 6 位以上即可）',
        profile: ok ? MockData.PROFILE : null,
        needCaptcha: false
      };
      return JwApi.delay(result, 900);
    }
    // ── 真实教务登录链路 ──
    // 1) GET 登录页，提取隐藏域（csrftoken 等）；
    // 2) GET 公钥（/xtgl/login_getPublicKey.html 返回 {modulus, exponent} base64）；
    // 3) RSA(PKCS#1 v1.5) 加密密码；
    // 4) POST 登录表单（yhm / mm密文 / csrftoken / mmsfjm / yzm），HttpClient 自动保存会话 Cookie；
    // 5) 用 getProfile() 验证会话是否真正建立（避免被登录页 HTML 误导）。
    AppState.account = account;
    const pageRes: HttpResult = await HttpClient.get('/jwglxt/xtgl/login_slogin.html');
    // 提取登录页【全部】隐藏域（csrftoken、xxdm、yzcskz、mmsfjm 等约 18 个）。
    // 只提交部分字段会导致服务端退回登录页 / 误判"验证码错误"，必须整表单提交。
    const hidden: Record<string, string> = JwApi.extractAllHidden(pageRes.body);
    const csrf: string = hidden['csrftoken'] ?? '';
    const pub: RsaPublicKey = await JwApi.fetchPublicKey();
    const encPwd: string = await RsaUtil.encryptPassword(password, pub.modulus, pub.exponent);

    const form: Record<string, string> = hidden; // 已包含全部隐藏域
    form['csrftoken'] = csrf;
    form['yhm'] = account;
    form['mm'] = encPwd;   // 密码经 RSA 加密；mmsfjm=1 表示密码已加密
    form['mmsfjm'] = '1';
    if (captcha.length > 0) {
      form['yzm'] = captcha; // 服务端要求验证码时携带
    }

    const res: HttpResult = await HttpClient.postForm('/jwglxt/xtgl/login_slogin.html', form);
    const body: string = res.body;
    // ── 模仿 HiXD CasLoginService：先按 HTML 具体关键词提取错误 ──
    const hasJsession: boolean = res.cookie.indexOf('JSESSIONID') >= 0;
    const enteredHome: boolean = body.indexOf('index_initMenu') >= 0 || body.indexOf('教学管理信息服务平台') >= 0 ||
      body.indexOf('学生个人信息') >= 0 || body.indexOf('当前角色消息') >= 0;
    // 失败关键词（登录页会回显这些提示）
    const failByPwd: boolean = body.indexOf('用户名或密码') >= 0 || body.indexOf('密码错误') >= 0 ||
      body.indexOf('账号错误') >= 0 || body.indexOf('账号被锁定') >= 0 || body.indexOf('账号被冻结') >= 0;
    const needCaptcha: boolean = body.indexOf('验证码') >= 0 || body.indexOf('校验码') >= 0;

    if (body.indexOf('账号被锁定') >= 0 || body.indexOf('账号被冻结') >= 0) {
      LogStore.logNet('登录', '登录', '失败', { method: 'POST', url: '/jwglxt/xtgl/login_slogin.html', status: `${res.code}`, detail: '账号被锁定/冻结' });
      return { success: false, message: '账号已被锁定/冻结，请稍后再试', profile: null, needCaptcha: false };
    }

    // 明确的密码错误且未要求验证码：直接返回失败，避免多余请求
    if (failByPwd && !needCaptcha) {
      LogStore.logNet('登录', '登录', '失败', { method: 'POST', url: '/jwglxt/xtgl/login_slogin.html', status: `${res.code}`, detail: '服务端返回密码错误' });
      return { success: false, message: '学号或密码错误', profile: null, needCaptcha: false };
    }

    // ── 成功判定：进入主页 或 携带 JSESSIONID 且资料可获取（双保险，模仿 HiXD）──
    if (enteredHome || hasJsession) {
      try {
        const profile: UserProfile = await JwApi.getProfile();
        if (profile.name.length > 0) {
          // 登录成功：记录账号 + 缓存资料
          DataStore.cacheProfile(profile);
          LogStore.logNet('登录', '登录', '成功',
            { method: 'POST', url: '/jwglxt/xtgl/login_slogin.html', status: `${res.code}`, detail: `enteredHome=${enteredHome} hasJsession=${hasJsession}` });
          return { success: true, message: '登录成功', profile: profile, needCaptcha: false };
        }
      } catch (e) {
        LogStore.log('登录', '登录', '资料获取异常', LogStore.errorOf(e as Object));
        // 忽略，走下面的失败分支
      }
    }
    LogStore.logNet('登录', '登录', '失败',
      {
        method: 'POST',
        url: '/jwglxt/xtgl/login_slogin.html',
        status: `${res.code}`,
        body: body,
        detail: `needCaptcha=${needCaptcha} enteredHome=${enteredHome} hasJsession=${hasJsession} failByPwd=${failByPwd}`
      });
    return {
      success: false,
      message: needCaptcha ? '请输入验证码后重试' : '登录失败，请检查学号密码',
      profile: null,
      needCaptcha: needCaptcha
    };
  }

  /** 验证码图片地址（与服务端会话绑定）。正方 zftal-ui v5 实际端点为 /kaptcha（带 time 防缓存）。 */
  static CAPTCHA_URL: string = '/jwglxt/kaptcha';

  /** 拉取验证码图片，返回 base64（无 data: 前缀）；mock 模式或无图时返回空串。 */
  static async getCaptcha(): Promise<string> {
    if (JwApi.USE_MOCK) {
      return '';
    }
    const ts: number = new Date().getTime();
    return HttpClient.getImageBase64(`${JwApi.CAPTCHA_URL}?time=${ts}`);
  }

  /** 提取登录页【全部】隐藏域（name -> value），覆盖 csrftoken、xxdm、yzcskz、mmsfjm 等约 18 个字段。
   *  该站点 input 写法不统一（value= 1 或 value="..."），这里做容错解析，确保整表单提交。 */
  private static extractAllHidden(html: string): Record<string, string> {
    const map: Record<string, string> = {};
    const tagRe: RegExp = /<input[^>]*type\s*=\s*["']?hidden["']?[^>]*>/gi;
    const tags: ESObject | null = html.match(tagRe);
    if (tags === null) {
      return map;
    }
    for (let i = 0; i < tags.length; i++) {
      const tag: string = tags[i];
      const nameM: ESObject | null = tag.match(/name\s*=\s*["']?([^"'>\s]+)/i);
      const valM: ESObject | null = tag.match(/value\s*=\s*["']?([^"'>\s]*)/i);
      if (nameM !== null) {
        map[nameM[1]] = valM !== null ? valM[1] : '';
      }
    }
    return map;
  }

  /** 从登录页 HTML 取 RSA 公钥 {modulus, exponent}，均为 base64。 */
  private static async fetchPublicKey(): Promise<RsaPublicKey> {
    const res: HttpResult = await HttpClient.get('/jwglxt/xtgl/login_getPublicKey.html');
    try {
      const obj: ESObject = JSON.parse(res.body);
      return {
        modulus: (obj['modulus'] as string) ?? '',
        exponent: (obj['exponent'] as string) ?? ''
      };
    } catch (e) {
      return { modulus: '', exponent: '' };
    }
  }


  /** 退出登录：清空会话、本地 Cookie 持久化、自动重登凭据、缓存资料、离线模式 */
  static logout(): void {
    HttpClient.clearCookie();
    DataStore.put(DataStore.KEY_SESSION_COOKIE, '');
    DataStore.put(DataStore.KEY_AUTO_ACCOUNT, '');
    DataStore.put(DataStore.KEY_AUTO_PWD, '');
    // 清除缓存的登录资料，确保下次打开回到登录页而不是直接进主页
    DataStore.cacheProfile(null);
    AppState.clear();
    HttpClient.setOfflineMode(true);
  }



  /**
   * 切换学期（全局设置）。同步更新 JwApi.term 与 AppState.term，
   * 持久化到 DataStore.KEY_DS_TERM 供启动恢复。各页（首页/课表/成绩/考试）依赖 term 重新计算周次/拉数据。
   */
  /**
   * 应用「自定义开学时间」覆盖：若该学期存在用户自定义的开学日，则返回覆盖后的副本，
   * 否则原样返回。集中在此处理，保证首页/课程表/桌面卡片等所有周次推算一致。
   */
  static applyCustomStart(term: TermInfo): TermInfo {
    const custom: string = DataStore.getCustomTermStart(term.id);
    return custom.length > 0
      ? { id: term.id, label: term.label, startDate: custom, totalWeeks: term.totalWeeks }
      : term;
  }

  static setTerm(term: TermInfo): void {
    const t: TermInfo = JwApi.applyCustomStart(term);
    JwApi.term = t;
    AppState.term = t;
    DataStore.put(DataStore.KEY_DS_TERM, term.id);
    // 广播学期变化，供各页（课程表等）@StorageProp @Watch 监听同步切换
    AppStorage.setOrCreate('currentTermId', term.id);
  }

  /** 学生基本信息（真实数据取自课表接口返回的 xsxx） */
  static async getProfile(): Promise<UserProfile> {
    if (JwApi.USE_MOCK) {
      return JwApi.delay(MockData.PROFILE, 200);
    }
    // 优先读缓存
    const cached: UserProfile | null = DataStore.loadCachedProfile();
    if (cached !== null && cached.name.length > 0) {
      return cached;
    }
    const parts: string[] = JwApi.term.id.split('-');
    const xnm: string = parts[0];
    const xqm: string = JwApi.xqmOf(JwApi.term.id);
    const res: HttpResult = await HttpClient.postForm('/jwglxt/kbcx/xskbcx_cxXsgrkb.html', { 'xnm': xnm, 'xqm': xqm });
    try {
      const root: ESObject = JSON.parse(res.body);
      const xs: ESObject = (root['xsxx'] as ESObject) ?? {};
      if (xs === null || xs === undefined) {
        throw new Error('no xsxx');
      }
      const nj: string = (xs['NJDM_ID'] as string) ?? '';
      const profile: UserProfile = {
        studentId: (xs['XH'] as string) ?? AppState.account,
        name: (xs['XM'] as string) ?? '',
        college: (xs['JGMC'] as string) ?? '',
        major: (xs['ZYMC'] as string) ?? '',
        className: (xs['BJMC'] as string) ?? '',
        grade: nj.length > 0 ? `${nj}级` : '',
        counselor: '', // 教务系统不提供辅导员字段
        eduSystem: (xs['XZ'] as string) ?? '',
        status: (xs['XJZT'] as string) ?? '在读'
      };
      // 学院字段：课表 xsxx 无 JGMC，尝试从"查询个人信息"页面补全
      if (profile.name.length > 0 && profile.college.length === 0) {
        const enriched: UserProfile | null = await JwApi.fetchFullProfile();
        if (enriched !== null) {
          if (enriched.college.length > 0) {
            profile.college = enriched.college;
          }
          if (enriched.major.length > 0) {
            profile.major = enriched.major;
          }
          if (enriched.className.length > 0) {
            profile.className = enriched.className;
          }
          if (enriched.grade.length > 0) {
            profile.grade = enriched.grade;
          }
          if (enriched.eduSystem.length > 0) {
            profile.eduSystem = enriched.eduSystem;
          }
        }
      }
      if (profile.name.length > 0) {
        DataStore.cacheProfile(profile);
      }
      return profile;
    } catch (e) {
      // 未登录或返回非 JSON（如登录页 HTML）时，返回空资料，交由上层判断登录态
      return {
        studentId: AppState.account,
        name: '',
        college: '',
        major: '',
        className: '',
        grade: '',
        counselor: '',
        eduSystem: '',
        status: '未登录'
      };
    }
  }

  /**
   * 拉取"查询个人信息"页面，补充学生资料的学院、年级等字段（课表 xsxx 不含 JGMC）。
   * 从 /jwglxt/xsxxxggl/xsgrxxwh_cxXsgrxx.html?gnmkdm=N100801 解析纯文本。
   */
  static async fetchFullProfile(): Promise<UserProfile | null> {
    if (JwApi.USE_MOCK) {
      return null;
    }
    try {
      const res: HttpResult = await HttpClient.get(
        '/jwglxt/xsxxxggl/xsgrxxwh_cxXsgrxx.html?gnmkdm=N100801&layout=default');
      const html: string = res.body;
      // 提取字段：学号/姓名/性别/出生/民族/政治面貌/年级/学院/专业/班级/学制/学籍状态
      const grab: (re: RegExp) => string = (re: RegExp): string => {
        const m: RegExpExecArray | null = re.exec(html);
        return m !== null ? m[1].trim() : '';
      };
      const name: string = grab(/姓名[：:]\s*<[^>]*>([^<]+)/);
      const xh: string = grab(/学号[：:]\s*<[^>]*>([^<]+)/);
      const xb: string = grab(/性别[：:]\s*<[^>]*>([^<]+)/);
      const mz: string = grab(/民族[：:]\s*<[^>]*>([^<]+)/);
      const zzmm: string = grab(/政治面貌[：:]\s*<[^>]*>([^<]+)/);
      const nj: string = grab(/年级[：:]\s*<[^>]*>([^<]+)/);
      const xy: string = grab(/学院[：:]\s*<[^>]*>([^<]+)/) || grab(/学院名称[：:]\s*<[^>]*>([^<]+)/);
      const zy: string = grab(/专业[：:]\s*<[^>]*>([^<]+)/) || grab(/专业名称[：:]\s*<[^>]*>([^<]+)/);
      const bj: string = grab(/班级[：:]\s*<[^>]*>([^<]+)/) || grab(/班级名称[：:]\s*<[^>]*>([^<]+)/);
      const xz: string = grab(/学制[：:]\s*<[^>]*>([^<]+)/);
      const xjzt: string = grab(/学籍状态[：:]\s*<[^>]*>([^<]+)/);
      if (name.length === 0 && xh.length === 0) {
        return null;
      }
      // 合并到现有 profile（保留课表已有字段，未取到的置空）
      const merged: UserProfile = {
        studentId: xh.length > 0 ? xh : AppState.account,
        name: name,
        college: xy,
        major: zy,
        className: bj,
        grade: nj,
        counselor: '',
        eduSystem: xz,
        status: xjzt.length > 0 ? xjzt : (AppState.profile !== null ? AppState.profile.status : '在读')
      };
      DataStore.cacheProfile(merged);
      return merged;
    } catch (e) {
      return null;
    }
  }

  /** 课程表 */
  static async getCourses(termId: string): Promise<CourseItem[]> {
    if (JwApi.USE_MOCK) {
      const list: CourseItem[] = MockData.courses();
      DataStore.cacheJSON(DataStore.KEY_COURSES, JSON.stringify(list));
      return JwApi.delay(list, 500);
    }
    const parts: string[] = termId.split('-');
    const xnm: string = parts[0];
    const xqm: string = JwApi.xqmOf(termId);
    const res: HttpResult = await HttpClient.postForm('/jwglxt/kbcx/xskbcx_cxXsgrkb.html', { 'xnm': xnm, 'xqm': xqm });
    let root: ESObject;
    try {
      root = JSON.parse(res.body);
    } catch (e) {
      LogStore.logNet('课表', '解析', '异常',
        { url: '/jwglxt/kbcx/xskbcx_cxXsgrkb.html', status: `${res.code}`, error: LogStore.errorOf(e as Object), body: res.body, detail: `xnm=${xnm} xqm=${xqm}` });
      throw e as Error;
    }
    const kbList: ESObject[] = (root['kbList'] as ESObject[]) ?? [];
    const list: CourseItem[] = [];
    for (let i = 0; i < kbList.length; i++) {
      list.push(JwApi.mapCourse(kbList[i]));
    }
    DataStore.cacheJSON(DataStore.KEY_COURSES, JSON.stringify(list));
    LogStore.logNet('课表', '获取', '成功',
      { url: '/jwglxt/kbcx/xskbcx_cxXsgrkb.html', status: `${res.code}`, detail: `${list.length}节 xnm=${xnm} xqm=${xqm}` });
    return list;
  }

  /** 考试安排 */
  static async getExams(termId: string): Promise<ExamItem[]> {
    if (JwApi.USE_MOCK) {
      const list: ExamItem[] = MockData.exams();
      DataStore.cacheJSON(DataStore.KEY_EXAMS, JSON.stringify(list));
      return JwApi.delay(list, 500);
    }
    const parts: string[] = termId.split('-');
    const xnm: string = parts[0];
    const xqm: string = JwApi.xqmOf(termId);
    const res: HttpResult = await HttpClient.postForm('/jwglxt/kwgl/kscx_cxXsksxxIndex.html',
      { 'doType': 'query', 'xnm': xnm, 'xqm': xqm });
    let root: ESObject;
    try {
      root = JSON.parse(res.body);
    } catch (e) {
      LogStore.logNet('考试', '解析', '异常',
        { url: '/jwglxt/kwgl/kscx_cxXsksxxIndex.html', status: `${res.code}`, error: LogStore.errorOf(e as Object), body: res.body, detail: `xnm=${xnm} xqm=${xqm}` });
      throw e as Error;
    }
    const items: ESObject[] = (root['items'] as ESObject[]) ?? [];
    const list: ExamItem[] = [];
    for (let i = 0; i < items.length; i++) {
      list.push(JwApi.mapExam(items[i]));
    }
    DataStore.cacheJSON(DataStore.KEY_EXAMS, JSON.stringify(list));
    LogStore.logNet('考试', '获取', '成功',
      { url: '/jwglxt/kwgl/kscx_cxXsksxxIndex.html', status: `${res.code}`, detail: `${list.length}条 xnm=${xnm} xqm=${xqm}` });
    return list;
  }

  /** 学期列表：本地生成（与正方学年/学期 select 一致，不依赖网络），保证学年学期选择可用 */
  static async getTerms(): Promise<TermInfo[]> {
    if (JwApi.USE_MOCK) {
      return JwApi.delay(MockData.terms(JwApi.term), 150);
    }
    return JwApi.buildLocalTerms();
  }

  /** 各学期成绩（默认当前学期，可传入指定学期 id 如 2024-2025-2） */
  static async getTermScores(termId?: string): Promise<TermScore[]> {
    if (JwApi.USE_MOCK) {
      return JwApi.delay(MockData.termScores(MockData.terms(JwApi.term)), 600);
    }
    const realTermId: string = termId ?? JwApi.term.id;
    const parts: string[] = realTermId.split('-');
    const xnm: string = parts[0];
    const xqm: string = JwApi.xqmOf(realTermId);
    const res: HttpResult = await HttpClient.postForm('/jwglxt/cjcx/cjcx_cxDgXscj.html',
      { 'doType': 'query', 'xnm': xnm, 'xqm': xqm, 'queryModel.showCount': '100' });
    const root: ESObject = JSON.parse(res.body);
    const items: ESObject[] = (root['items'] as ESObject[]) ?? [];
    const scores: ScoreItem[] = [];
    for (let i = 0; i < items.length; i++) {
      scores.push(JwApi.mapScore(items[i], realTermId));
    }
    let gpaW: number = 0;
    let creditSum: number = 0;
    let scoreSum: number = 0;
    let scoreCount: number = 0;
    for (const s of scores) {
      gpaW += s.gradePoint * s.credit;
      creditSum += s.credit;
      if (s.score > 0) {
        scoreSum += s.score;
        scoreCount++;
      }
    }
    // 查询学期 label（用 JwApi.terms 映射，未找到时回退为 id）
    const termLabel: string = JwApi.term.id === realTermId ? JwApi.term.label : realTermId;
    const ts: TermScore = {
      termId: realTermId,
      termLabel: termLabel,
      gpa: creditSum > 0 ? gpaW / creditSum : 0,
      avgScore: scoreCount > 0 ? scoreSum / scoreCount : 0,
      totalCredit: creditSum,
      earnedCredit: creditSum,
      rank: 0, // 学校不允许查看排名
      classSize: 0,
      items: scores
    };
    const result: TermScore[] = [ts];
    // 仅缓存当前学期成绩，避免把其他学期的成绩覆盖掉
    if (realTermId === JwApi.term.id) {
      DataStore.cacheJSON(DataStore.KEY_TERM_SCORES, JSON.stringify(result));
    }
    LogStore.logNet('成绩', '获取', '成功',
      { method: 'POST', url: '/jwglxt/cjcx/cjcx_cxDgXscj.html', status: `${res.code}`,
        detail: `${scores.length}条 GPA=${ts.gpa.toFixed(2)} ${termLabel}` });
    return result;
  }

  /** 消息/通知（真实接口：GET /jwglxt/xtgl/index_cxDbsy.html?doType=query&flag=1&sfyy=1 -> JSON items[]） */
  static async getNotices(): Promise<NoticeItem[]> {
    if (JwApi.USE_MOCK) {
      const list: NoticeItem[] = MockData.notices();
      DataStore.cacheJSON(DataStore.KEY_NOTICES, JSON.stringify(list));
      return JwApi.delay(list, 400);
    }
    // 1) 优先读本地缓存（上次成功拉取）
    const cached: string = DataStore.loadJSON(DataStore.KEY_NOTICES);
    if (cached.length > 0) {
      try {
        const cl: NoticeItem[] = JSON.parse(cached) as NoticeItem[];
        LogStore.log('通知', '读取', '缓存命中', `${cl.length}条`);
        return cl;
      } catch (e) {
        // ignore
      }
    }
    // 2) 真实拉取
    try {
      const res: HttpResult = await HttpClient.get(
        '/jwglxt/xtgl/index_cxDbsy.html?doType=query&flag=1&sfyy=1');
      const root: ESObject = JSON.parse(res.body);
      const items: ESObject[] = (root['items'] as ESObject[]) ?? [];
      const list: NoticeItem[] = [];
      let index: number = 0;
      for (let i = 0; i < items.length; i++) {
        const it: ESObject = items[i];
        const title: string = (it['xxbt'] as string) ?? '';
        const content: string = (it['xxnr'] as string) ?? '';
        if (title.length < 2 && content.length < 2) {
          continue;
        }
        const cjsj: string = (it['cjsj'] as string) ?? '';
        const date: string = cjsj.length >= 19 ? cjsj.substring(0, 19) : cjsj;
        const read: boolean = (it['sfyd'] as string) !== '0';
        index += 1;
        list.push({
          id: `n${index}-${date}`,
          title: title.length > 0 ? title : content,
          source: (it['jsmc'] as string) ?? '教务处',
          date: date,
          tag: '通知',
          isTop: false,
          read: read,
          summary: content,
          content: content.length > 0 ? content : title,
          url: ''
        });
      }
      DataStore.cacheJSON(DataStore.KEY_NOTICES, JSON.stringify(list));
      LogStore.logNet('通知', '加载', '成功',
        { method: 'GET', url: '/jwglxt/xtgl/index_cxDbsy.html', status: `${res.code}`, detail: `${list.length}条` });
      return list;
    } catch (e) {
      LogStore.log('通知', '加载', '失败', LogStore.errorOf(e as Object));
      return [];
    }
  }

  /**
   * 教务处官网「学期校历」通知：GET Const.JWC_LIST_URL（/jxrl_3318/list.htm）取最新两条文章。
   * mock：MockData.jwcNotices()；真实：解析列表页 li.news 取前两条并缓存（KEY_NOTICES_JWC）。
   */
  static async getJwcNotices(): Promise<NoticeItem[]> {
    if (JwApi.USE_MOCK) {
      return JwApi.delay(MockData.jwcNotices(), 300);
    }
    const cached: string = DataStore.loadJSON(DataStore.KEY_NOTICES_JWC);
    if (cached.length > 0) {
      try {
        const cl: NoticeItem[] = JSON.parse(cached) as NoticeItem[];
        LogStore.log('通知', '官网读取', '缓存命中', `${cl.length}条`);
        return cl;
      } catch (e) {
        // ignore
      }
    }
    try {
      const res: HttpResult = await HttpClient.get(Const.JWC_LIST_URL);
      const list: NoticeItem[] = JwApi.parseJwcListNotices(res.body);
      if (list.length > 0) {
        DataStore.cacheJSON(DataStore.KEY_NOTICES_JWC, JSON.stringify(list));
      }
      LogStore.logNet('通知', '官网列表', '成功',
        { method: 'GET', url: Const.JWC_LIST_URL, status: `${res.code}`, detail: `${list.length}条` });
      return list;
    } catch (e) {
      LogStore.log('通知', '官网列表', '失败', LogStore.errorOf(e as Object));
      return [];
    }
  }

  /** 解析 jxrl_3318/list.htm 的 news 列表，取最新两条文章 */
  private static parseJwcListNotices(html: string): NoticeItem[] {
    const out: NoticeItem[] = [];
    const re: RegExp = /<li[^>]*class="news[^"]*"[^>]*>([\s\S]{0,600}?)<\/li>/gi;
    let m: ESObject | null = re.exec(html);
    while (m !== null && out.length < 2) {
      const li: string = m[1];
      const am: ESObject | null = /<a[^>]+href="([^"]+)"[^>]*>([\s\S]{2,150}?)<\/a>/i.exec(li);
      if (am !== null) {
        const title: string = am[2].replace(/<[^>]+>/g, '').trim();
        if (title.length > 2) {
          const dm: ESObject | null = /<span class="news_meta">([^<]*)<\/span>/i.exec(li);
          const date: string = dm !== null ? dm[1].trim() : '';
          out.push({
            id: `jwc-${out.length + 1}`,
            title: title,
            source: '教务处官网',
            date: date,
            tag: '通知',
            isTop: out.length === 0,
            read: false,
            summary: title,
            content: title,
            url: JwApi.absJwcUrl(am[1])
          });
        }
      }
      m = re.exec(html);
    }
    return out;
  }

  /** 相对链接转绝对（jwc.xjau.edu.cn 教务处官网） */
  private static absJwcUrl(href: string): string {
    if (href.startsWith('http')) {
      return href;
    }
    return `https://jwc.xjau.edu.cn${href}`;
  }

  /** 从 jxrl_3318 列表页取最新一条校历文章 URL（返回绝对地址，无则空串） */
  private static firstCalendarArticle(html: string): string {
    const re: RegExp = /<li[^>]*class="news[^"]*"[^>]*>([\s\S]{0,600}?)<\/li>/gi;
    let m: ESObject | null = re.exec(html);
    while (m !== null) {
      const li: string = m[1];
      const am: ESObject | null = /<a[^>]+href="([^"]+page\.htm)"[^>]*>([\s\S]{2,150}?)<\/a>/i.exec(li);
      if (am !== null) {
        return JwApi.absJwcUrl(am[1]);
      }
      m = re.exec(html);
    }
    return '';
  }

  /** 从校历文章页提取 PDF 附件 URL（返回绝对地址，无则空串） */
  private static async findCalendarPdfUrl(articleUrl: string): Promise<string> {
    try {
      const res: HttpResult = await HttpClient.get(articleUrl);
      const pm: ESObject | null = /href="([^"]+\.pdf[^"]*)"/i.exec(res.body);
      if (pm !== null) {
        return JwApi.absJwcUrl(pm[1]);
      }
    } catch (e) {
      // ignore
    }
    return '';
  }

  /** 内置校历转换结果（预置的"最新校历 PDF 转换数据"，真实模式兜底） */
  private static builtinCal(): TeachingCalendar | null {
    try {
      return JSON.parse(MockData.jwcCalendarJson()) as TeachingCalendar;
    } catch (e) {
      return null;
    }
  }

  /** 从缓存原始串中解出 TeachingCalendar（无则 null） */
  private static cachedCal(raw: string): TeachingCalendar | null {
    if (raw.length === 0) {
      return null;
    }
    try {
      const obj: ESObject = JSON.parse(raw);
      const data: string = (obj['data'] as string) ?? '';
      if (data.length > 0) {
        return JSON.parse(data) as TeachingCalendar;
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  /**
   * 校历（日历）：数据源为教务处官网「学期校历」（Const.JWC_LIST_URL / jxrl_3318/list.htm）。
   * 流程：列表 → 最新校历文章 → 文章页 PDF 附件 URL → 转换结果缓存（KEY_JWC_CAL）。
   * 转换完成后的数据直接缓存；重新获取时对比最新文章 URL（来源），无变化直接用缓存，有变化才更新。
   * 说明：客户端受限于 PDF 表头为矢量图无法可靠自动转换，转换结果由预置数据（MockData.jwcCalendarJson，
   * 即沙箱内由最新校历 PDF 转换生成）提供；真实模式负责抓取来源与变化检测，PDF 解析待后续版本。
   */
  static async getTeachingCalendar(): Promise<TeachingCalendar | null> {
    if (JwApi.USE_MOCK) {
      return JwApi.builtinCal();
    }
    // 1) 缓存秒开
    const cachedRaw: string = DataStore.loadJSON(DataStore.KEY_JWC_CAL);
    const cached: TeachingCalendar | null = JwApi.cachedCal(cachedRaw);
    let cachedSrc: string = '';
    if (cachedRaw.length > 0) {
      try {
        const obj: ESObject = JSON.parse(cachedRaw);
        cachedSrc = (obj['sourceArticleUrl'] as string) ?? '';
      } catch (e) {
        // ignore
      }
    }
    try {
      // 2) 拉列表，取最新校历文章 URL
      const res: HttpResult = await HttpClient.get(Const.JWC_LIST_URL);
      LogStore.logNet('校历', '拉取', '成功',
        { method: 'GET', url: Const.JWC_LIST_URL, status: `${res.code}`, detail: `本地缓存=${cached !== null ? '有' : '无'}` });
      const article: string = JwApi.firstCalendarArticle(res.body);
      if (article.length === 0) {
        LogStore.log('校历', '解析', '无文章', '列表页未匹配到校历文章');
        return cached;
      }
      // 3) 来源无变化 → 直接返回缓存（不更新）
      if (cached !== null && article === cachedSrc) {
        LogStore.log('校历', '更新', '来源未变', article);
        return cached;
      }
      // 4) 来源有变化 → 找 PDF、更新来源标记；转换结果以缓存/预置兜底
      const pdfUrl: string = await JwApi.findCalendarPdfUrl(article);
      const cal: TeachingCalendar | null = cached !== null ? cached : JwApi.builtinCal();
      if (cal !== null) {
        const store: JwcCalCacheStore = {
          'sourceArticleUrl': article,
          'sourcePdfUrl': pdfUrl,
          'data': JSON.stringify(cal)
        };
        DataStore.cacheJSON(DataStore.KEY_JWC_CAL, JSON.stringify(store));
      }
      LogStore.log('校历', '更新', '成功', `新来源 ${article}`);
      return cal;
    } catch (e) {
      LogStore.log('校历', '拉取', '失败', LogStore.errorOf(e as Object));
      return cached;
    }
  }

  /**
   * 拉取学生证件照（/jwglxt/xtgl/photo_cxXszp4.html?xh_id=&zplx=rxhzp）。
   * 返回 base64（不含 data: 前缀）；失败/未登录返回空串。
   */
  static async getPhoto(): Promise<string> {
    if (JwApi.USE_MOCK) {
      return '';
    }
    // 优先读缓存
    const cached: string = DataStore.loadJSON(DataStore.KEY_PHOTO);
    if (cached.length > 0) {
      return cached;
    }
    const sid: string = AppState.account.length > 0 ? AppState.account : (AppState.profile?.studentId ?? '');
    if (sid.length === 0) {
      return '';
    }
    try {
      const b64: string = await HttpClient.getImageBase64(`/jwglxt/xtgl/photo_cxXszp4.html?xh_id=${sid}&zplx=rxhzp&_t=${Date.now()}`);
      if (b64.length > 0) {
        DataStore.cacheJSON(DataStore.KEY_PHOTO, b64);
      }
      return b64;
    } catch (e) {
      return '';
    }
  }

  /**
   * 登录成功 / 手动刷新时：把课表、成绩、考试、学业、消息、头像全部重新拉取并写入本地缓存。
   * 界面可先用旧缓存秒开，后台静默刷新覆盖。
   */
  static async refreshAll(): Promise<void> {
    if (JwApi.USE_MOCK) {
      return;
    }
    LogStore.log('首页', '刷新', '开始', '并行拉取课表/成绩/考试/学业/通知');
    const term: TermInfo = JwApi.term;
    const parts: string[] = term.id.split('-');
    const xnm: string = parts[0];
    const xqm: string = JwApi.xqmOf(term.id);
    const h: Record<string, string> = { 'xnm': xnm, 'xqm': xqm };

    // 并行拉取
    const taskCourses: Promise<CourseItem[]> = JwApi.getCourses(term.id);
    const taskScores: Promise<TermScore[]> = JwApi.getTermScores();
    const taskExams: Promise<ExamItem[]> = JwApi.getExams(term.id);
    const taskAcademic: Promise<AcademicReport> = JwApi.getAcademic();
    const taskNotices: Promise<NoticeItem[]> = JwApi.getNotices();

    const courses: CourseItem[] = await taskCourses;
    const scores: TermScore[] = await taskScores;
    const exams: ExamItem[] = await taskExams;
    const academic: AcademicReport = await taskAcademic;
    const notices: NoticeItem[] = await taskNotices;

    DataStore.cacheJSON(DataStore.KEY_COURSES, JSON.stringify(courses));
    DataStore.cacheJSON(DataStore.KEY_TERM_SCORES, JSON.stringify(scores));
    DataStore.cacheJSON(DataStore.KEY_EXAMS, JSON.stringify(exams));
    DataStore.cacheJSON(DataStore.KEY_ACADEMIC, JSON.stringify(academic));
    DataStore.cacheJSON(DataStore.KEY_NOTICES, JSON.stringify(notices));

    // 个人资料与头像
    try {
      const profile: UserProfile = await JwApi.getProfile();
      if (profile.name.length > 0) {
        AppState.profile = profile;
        DataStore.cacheProfile(profile);
      }
    } catch (e) {
      // ignore
    }
    try {
      const p: string = await JwApi.getPhoto();
      if (p.length > 0) {
        DataStore.cacheJSON(DataStore.KEY_PHOTO, p);
      }
    } catch (e) {
      // ignore
    }
    LogStore.log('首页', '刷新', '成功',
      `课表${courses.length}节 成绩${scores.length}学期 考试${exams.length}门 学业GPA=${academic.gpa} 通知${notices.length}条`);
    // 记录更新时间
    DataStore.put(DataStore.KEY_CACHE_TIME, `${Date.now()}`);
  }

  /** 读取缓存中的课程表（功能浏览模式不读真实缓存，避免泄露真实用户数据；无缓存返回空数组） */
  static loadCachedCourses(): CourseItem[] {
    if (JwApi.USE_MOCK) {
      return [];
    }
    const raw: string = DataStore.loadJSON(DataStore.KEY_COURSES);
    if (raw.length === 0) {
      return [];
    }
    try {
      return JSON.parse(raw) as CourseItem[];
    } catch (e) {
      return [];
    }
  }

  /** 读取缓存中的学期成绩（功能浏览模式不读真实缓存） */
  static loadCachedTermScores(): TermScore[] {
    if (JwApi.USE_MOCK) {
      return [];
    }
    const raw: string = DataStore.loadJSON(DataStore.KEY_TERM_SCORES);
    if (raw.length === 0) {
      return [];
    }
    try {
      return JSON.parse(raw) as TermScore[];
    } catch (e) {
      return [];
    }
  }

  /** 读取缓存中的考试安排（功能浏览模式不读真实缓存） */
  static loadCachedExams(): ExamItem[] {
    if (JwApi.USE_MOCK) {
      return [];
    }
    const raw: string = DataStore.loadJSON(DataStore.KEY_EXAMS);
    if (raw.length === 0) {
      return [];
    }
    try {
      return JSON.parse(raw) as ExamItem[];
    } catch (e) {
      return [];
    }
  }

  /** 读取缓存中的学业情况（功能浏览模式不读真实缓存） */
  static loadCachedAcademic(): AcademicReport {
    if (JwApi.USE_MOCK) {
      return EMPTY_REPORT;
    }
    const raw: string = DataStore.loadJSON(DataStore.KEY_ACADEMIC);
    if (raw.length === 0) {
      return EMPTY_REPORT;
    }
    try {
      return JSON.parse(raw) as AcademicReport;
    } catch (e) {
      return EMPTY_REPORT;
    }
  }

  /** 读取缓存中的消息列表（功能浏览模式不读真实缓存） */
  static loadCachedNotices(): NoticeItem[] {
    if (JwApi.USE_MOCK) {
      return [];
    }
    const raw: string = DataStore.loadJSON(DataStore.KEY_NOTICES);
    if (raw.length === 0) {
      return [];
    }
    try {
      return JSON.parse(raw) as NoticeItem[];
    } catch (e) {
      return [];
    }
  }

  /** 读取缓存中的学生照片 base64（功能浏览模式不读真实缓存，无则空串） */
  static loadCachedPhoto(): string {
    if (JwApi.USE_MOCK) {
      return '';
    }
    return DataStore.loadJSON(DataStore.KEY_PHOTO);
  }

  /** 上次刷新时间（时间戳），0 表示从未刷新 */
  static lastRefreshTime(): number {
    const raw: string = DataStore.get(DataStore.KEY_CACHE_TIME);
    const n: number = Number(raw);
    return isNaN(n) ? 0 : n;
  }

  /**
   * 学业情况（真实接口：GET /jwglxt/xsxy/xsxyqk_cxXsxyqkIndex.html?gnmkdm=N105515
   *  -> HTML 内嵌纯文本，去 script/标签后正则解析）。不要 POST（POST 会 500/911）。
   */
  static async getAcademic(): Promise<AcademicReport> {
    if (JwApi.USE_MOCK) {
      const report: AcademicReport = MockData.academic();
      DataStore.cacheJSON(DataStore.KEY_ACADEMIC, JSON.stringify(report));
      return JwApi.delay(report, 550);
    }
    // 1) 优先读本地缓存
    const cached: string = DataStore.loadJSON(DataStore.KEY_ACADEMIC);
    if (cached.length > 0) {
      try {
        const r: AcademicReport = JSON.parse(cached) as AcademicReport;
        LogStore.log('学业', '读取', '缓存命中', `GPA=${r.gpa} 分类${r.categories.length}门`);
        return r;
      } catch (e) {
        // ignore
      }
    }
    // 2) 真实拉取 + 解析
    try {
      const res: HttpResult = await HttpClient.get(
        '/jwglxt/xsxy/xsxyqk_cxXsxyqkIndex.html?gnmkdm=N105515&layout=default');
      const report: AcademicReport = JwApi.parseAcademicText(res.body);
      DataStore.cacheJSON(DataStore.KEY_ACADEMIC, JSON.stringify(report));
      LogStore.logNet('学业', '加载', '成功',
        { method: 'GET', url: '/jwglxt/xsxy/xsxyqk_cxXsxyqkIndex.html', status: `${res.code}`,
          detail: `GPA=${report.gpa} 分类${report.categories.length}门 警告${report.warnings.length}条` });
      return report;
    } catch (e) {
      LogStore.log('学业', '加载', '失败', LogStore.errorOf(e as Object));
      return EMPTY_REPORT;
    }
  }

  /**
   * 从学业页 HTML 提取关键数据：
   *  - GPA / 计划总课程 / 通过 / 未通过 / 未修 / 在读 / 计划外（去 script/标签后正则）
   *  - 课程分类学分（yxxf=已获得 yqzdxf=要求 + 类别名，直接从原始 HTML 正则，不去标签）
   */
  private static parseAcademicText(html: string): AcademicReport {
    // ── 纯文本部分（GPA、门数统计）──
    let text: string = html.replace(/<script[\s\S]*?<\/script>/gi, ' ');
    text = text.replace(/<style[\s\S]*?<\/style>/gi, ' ');
    text = text.replace(/<[^>]+>/g, ' ');
    text = text.replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ');

    const gpa: number = JwApi.matchFirstNumber(text, /平均学分绩点\s*（GPA）[：:]\s*([\d.]+)/);
    const total: number = JwApi.matchFirstNumber(text, /计划总课程\s*(\d+)\s*门/);
    const passed: number = JwApi.matchFirstNumber(text, /通过\s*(\d+)\s*门/);
    const failed: number = JwApi.matchFirstNumber(text, /未通过\s*(\d+)\s*门/);
    const unearned: number = JwApi.matchFirstNumber(text, /未修\s*(\d+)\s*门/);
    const studying: number = JwApi.matchFirstNumber(text, /在读\s*(\d+)\s*门/);
    const outside: number = JwApi.matchFirstNumber(text, /计划外\s*[：:]\s*通过\s*(\d+)\s*门/);

    // ── 课程分类学分（从原始 HTML 直接正则，类别名在属性后）──
    // 结构：yxxf='已获得' yqzdxf='要求' sftg='..'>" + "类别名&nbsp;"
    // 注意：ArkTS 正则字面量不支持裸双引号，用 new RegExp 字符串构造
    const categories: CreditCategory[] = [];
    const catRe: RegExp = /yxxf='([\d.]+)'\s*yqzdxf='([\d.]+)'\s*sftg='(\d)'[^>]*>\s*"\s*\+\s*"([^"&]{2,30})&nbsp;/g;
    let cm: RegExpExecArray | null = catRe.exec(html);
    while (cm !== null) {
      const name: string = cm[4].trim();
      const earned: number = Number(cm[1]);
      const required: number = Number(cm[2]);
      // 排除顶层汇总节点（节点名 = 入学年份 + 专业名），只保留真实分类。
      // 用通用特征替代专业名硬编码（保证不同专业学生使用都正常）：
      // 汇总节点名称以 4 位年份开头且要求学分=0；真实分类（通识教育/专业基础课等）不以年份开头。
      const isSummaryNode: boolean = name.length >= 4 && (name.match(/^\d{4}/) !== null);
      if (name.length > 0 && !isSummaryNode) {
        // 只加入有"要求学分"的真实分类（要求>0），且去重
        if (!isNaN(required) && required > 0 && !JwApi.hasCategory(categories, name)) {
          categories.push({ name: name, required: required, earned: isNaN(earned) ? 0 : earned });
        }
      }
      cm = catRe.exec(html);
    }

    const warnings: string[] = [];
    if (failed > 0) {
      warnings.push(`计划内未通过课程 ${failed} 门，建议尽快补考/重修。`);
    } else {
      warnings.push('计划内课程全部通过，保持节奏即可。');
    }
    if (unearned > 0) {
      warnings.push(`还有 ${unearned} 门课程未修、${studying} 门在读。`);
    }
    if (outside > 0) {
      warnings.push(`另有计划外课程通过 ${outside} 门（跨专业/辅修等）。`);
    }

    return {
      // 计划总课程门数 / 已通过门数（含计划外），用于概览统计
      totalRequired: total > 0 ? total : 60,
      totalEarned: passed + outside,
      gpa: gpa,
      rank: 0,
      classSize: 0,
      failedCount: failed,
      unearnedCount: unearned,
      studyingCount: studying,
      outsideCount: outside,
      passRate: (total > 0 && passed > 0) ? Math.round(passed / total * 100) : 0,
      categories: categories,
      warnings: warnings,
      gpaTrend: []
    };
  }

  /** 检查分类数组里是否已有同名分类（去重） */
  private static hasCategory(list: CreditCategory[], name: string): boolean {
    for (const c of list) {
      if (c.name === name) {
        return true;
      }
    }
    return false;
  }

  /** 正则取第一个数字（规避 RegExpMatchArray 结构类型：用 RegExpExecArray） */
  private static matchFirstNumber(text: string, re: RegExp): number {
    const m: RegExpExecArray | null = re.exec(text);
    if (m !== null && m[1] !== undefined) {
      const n: number = Number(m[1]);
      return isNaN(n) ? 0 : n;
    }
    return 0;
  }

  /**
   * 空闲教室查询条件（校区/楼号/场地类别）。
   * 真实入口：信息查询-查询空闲教室（cdjy），条件数据来自 cdjy_cxKxcdlb.html 页面 <select> 选项
   * （xqh_id 校区 / lh 楼号 / cdlb_id 场地类别一级）。解析失败返回空数组，页面降级为"全部"。
   */
  static async getEmptyRoomConditions(): Promise<EmptyRoomConditions> {
    const empty: EmptyRoomConditions = { campus: [], building: [], roomType: [] };
    if (JwApi.USE_MOCK) {
      // 功能浏览模式：返回固定校区/楼号/场地类别，便于演示
      return {
        campus: [
          { code: '1', name: '老满城校区' },
          { code: '2', name: '亚心校区' },
          { code: '3', name: '塔城校区' }
        ],
        building: [
          { code: '01', name: '主教学楼' },
          { code: '02', name: '综合实验楼' },
          { code: '03', name: '博学楼' },
          { code: '04', name: '图书馆' }
        ],
        roomType: [
          { code: '1', name: '普通教室' },
          { code: '2', name: '多媒体教室' },
          { code: '3', name: '实验室' },
          { code: '4', name: '机房' },
          { code: '5', name: '报告厅' }
        ]
      };
    }
    try {
      const res: HttpResult = await HttpClient.get(
        `/jwglxt/cdjy/cdjy_cxKxcdlb.html?gnmkdm=N2155&layout=default&su=${AppState.account}`);
      const body: string = res.body;
      const parseSelect = (name: string): EmptyRoomCondition[] => {
        const out: EmptyRoomCondition[] = [];
        const m: RegExpExecArray | null = new RegExp(
          `<select[^>]*name="${name}"[^>]*>([\\s\\S]*?)</select>`).exec(body);
        if (m === null) {
          return out;
        }
        const optRe: RegExp = /<option[^>]*value="([^"]*)"[^>]*>([^<]*)<\/option>/g;
        let om: RegExpExecArray | null = null;
        while ((om = optRe.exec(m[1])) !== null) {
          const code: string = om[1];
          const text: string = om[2].trim();
          if (text.length > 0 && (code.length > 0 || text === '全部')) {
            out.push({ code: code, name: text });
          }
        }
        return out;
      };
      const campus: EmptyRoomCondition[] = parseSelect('xqh_id');
      const building: EmptyRoomCondition[] = parseSelect('lh');
      const roomType: EmptyRoomCondition[] = parseSelect('cdlb_id');
      return { campus: campus, building: building, roomType: roomType };
    } catch (e) {
      return empty;
    }
  }

  /**
   * 场地二级类别（选完一级类别 cdlb_id 后联动加载）。
   * 真实接口：/jwglxt/query/query_cxEjjxcdlbList.html?sscdlb_id=xxx&cdyysfkj=1
   * 返回数组项 { CDLB_ID, CDLBMC }（大写字段）。
   */
  static async getSubRoomTypes(parentId: string): Promise<EmptyRoomCondition[]> {
    if (parentId.length === 0) {
      return [];
    }
    if (JwApi.USE_MOCK) {
      const mocks: Record<string, EmptyRoomCondition[]> = {
        '1': [{ code: '11', name: '普通小教室' }, { code: '12', name: '普通大教室' }],
        '2': [{ code: '21', name: '多媒体小教室' }, { code: '22', name: '多媒体大教室' }, { code: '23', name: '智慧教室' }],
        '3': [{ code: '31', name: '化学实验室' }, { code: '32', name: '物理实验室' }, { code: '33', name: '计算机实验室' }],
        '4': [{ code: '41', name: '公共机房' }, { code: '42', name: '专业机房' }],
        '5': [{ code: '51', name: '大型报告厅' }, { code: '52', name: '中型报告厅' }]
      };
      const list: EmptyRoomCondition[] = mocks[parentId];
      return list !== undefined ? list : [];
    }
    try {
      const res: HttpResult = await HttpClient.postForm('/jwglxt/query/query_cxEjjxcdlbList.html', {
        'sscdlb_id': parentId,
        'cdyysfkj': '1'
      });
      const out: EmptyRoomCondition[] = [];
      const root: ESObject = JSON.parse(res.body);
      if (Array.isArray(root)) {
        for (let i: number = 0; i < root.length; i++) {
          const row: ESObject = root[i] as ESObject;
          const code: string = String(row['CDLB_ID'] ?? row['cdlb_id'] ?? '');
          const name: string = String(row['CDLBMC'] ?? row['cdlbmc'] ?? '');
          if (code.length > 0 && name.length > 0) {
            out.push({ code: code, name: name });
          }
        }
      }
      return out;
    } catch (e) {
      return [];
    }
  }

  /** 功能浏览模式用的模拟空闲教室 */
  private static buildMockEmptyRooms(p: EmptyRoomQueryParams): EmptyRoomItem[] {
    const name: string = p.roomName.length > 0 ? p.roomName : '';
    const out: EmptyRoomItem[] = [];
    const buildings: string[] = ['主教学楼', '综合实验楼', '博学楼', '图书馆'];
    const roomNames: string[] = ['101', '102', '201', '202', '301', '305', '401', '408', '502', '506'];
    for (let i: number = 0; i < roomNames.length; i++) {
      const b: string = buildings[i % buildings.length];
      const r: string = roomNames[i];
      out.push({
        cdbh: `${b.charAt(0)}${r}`,
        cdmc: `${b} ${r}室`,
        xqmc: '老满城校区',
        jxlmc: b,
        lch: `${1 + Math.floor(i / 3)}`,
        cdlbmc: i % 3 === 0 ? '多媒体教室' : (i % 3 === 1 ? '普通教室' : '实验室'),
        cdejlbmc: i % 3 === 0 ? '多媒体小教室' : (i % 3 === 1 ? '普通小教室' : '物理实验室'),
        sjzws: `${40 + (i % 5) * 20}`,
        sybmmc: i % 2 === 0 ? '教务处' : '学院',
        sybj: '',
        bz: '',
        sfkfy: '1',
        time: JwApi.buildEmptyRoomTimeText(p)
      });
    }
    if (name.length > 0) {
      return out.filter((item) => item.cdmc.indexOf(name) >= 0 || item.cdbh.indexOf(name) >= 0);
    }
    return out;
  }


  /**
   * 空闲教室导出（网页版"导出Excel"）：一次拉取全量数据（不受每页条数限制）。
   * 流程与 kxcdlb.js 对齐：先初始化导出配置（dcclbh=JW_N2155_CXKXJS），
   * 再 POST cdjy_cxDcKxcdlb.html 拿标准 xlsx（zip），解压解析后按用户选择的条件展示全部结果。
   * 导出失败返回空 rooms + message 诊断。
   */
  static async exportEmptyRooms(p: EmptyRoomQueryParams): Promise<EmptyRoomResult> {
    const emptyResult: EmptyRoomResult = { rooms: [], message: '' };
    if (JwApi.USE_MOCK) {
      const mockResult: EmptyRoomResult = { rooms: JwApi.buildMockEmptyRooms(p), message: '' };
      return JwApi.delay(mockResult, 300);
    }
    // 导出接口走正方反代网关，用桌面浏览器请求头避免被网关拒绝（移动端 UA 曾触发 502）。
    // Referer 必须指向导出来源页（kxcdlb 查询页），X-Requested-With 标识 ajax 调用，
    // 否则反代可能判为异常请求或网关层 502。
    const browserHeader: Record<string, string> = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': '*/*',
      'Accept-Language': 'zh-CN,zh;q=0.9',
      'Referer': `https://jwxt.xjau.edu.cn/jwglxt/cdjy/cdjy_cxKxcdlb.html?gnmkdm=N2155&layout=default&su=${AppState.account}`,
      'X-Requested-With': 'XMLHttpRequest'
    };
    const tparts: string[] = p.termId.split('-');
    const xnm: string = tparts.length >= 3 ? tparts[0] : '';
    const xqm: string = JwApi.xqmOf(p.termId);
    const zcd: number = p.weeks.reduce((s: number, w: number) => s + Math.pow(2, Math.max(0, w - 1)), 0);
    const jcd: number = p.sections.reduce((s: number, n: number) => s + Math.pow(2, Math.max(0, n - 1)), 0);
    const form: Record<string, string> = {
      'xnm': xnm, 'xqm': xqm, 'xqh_id': p.campus, 'lh': p.building,
      'cdlb_id': p.roomType, 'cdejlb_id': p.roomSubType,
      'qszws': p.seatMin, 'jszws': p.seatMax, 'cdmc': p.roomName,
      'cd_id': '', 'cdjylx': '', 'zysx': '', 'sflb': '', 'hbsl': '', 'bbsl': '',
      'sfyzz': '', 'sfjtjs': '', 'tjsl': '', 'tymbsl': '', 'yczb': '', 'zws': '',
      'sfbhkc': '', 'kszws1': '', 'jyfs': '0',
      'zcd': `${zcd}`, 'xqj': p.weekdays.join(','), 'jcd': `${jcd}`
    };
    try {
      // Step1 初始化导出配置（与 kxcdlb.js exportDialog 一致，dcclbh 是导出处类别编码）。
      // 关键：路径必须带 /jwglxt 前缀，与其它接口一致；少了前缀会被反向代理判为不存在路径并返回 502。
      const initForm: Record<string, string> = { 'dcclbh': 'JW_N2155_CXKXJS' };
      await HttpClient.postFormExtra('/jwglxt/zftal/drdc/export_exportInitDcpz.html', initForm, browserHeader);
      // Step2 导出（带查询条件 + 排序，返回标准 xlsx）
      const expForm: Record<string, string> = {};
      const formKeys: string[] = Object.keys(form);
      for (let i = 0; i < formKeys.length; i++) {
        expForm[formKeys[i]] = form[formKeys[i]];
      }
      expForm['dcclbh'] = 'JW_N2155_CXKXJS';
      expForm['xsnrbt'] = '0';
      expForm['queryModel.sortName'] = 'cdbh';
      expForm['queryModel.sortOrder'] = 'asc';
      const bin: BinaryResult =
        await HttpClient.postFormBinary('/jwglxt/cdjy/cdjy_cxDcKxcdlb.html', expForm, browserHeader);
      if (bin.data === null) {
        // 请求失败：按诊断信息区分原因
        let reason: string = '';
        if (bin.body.indexOf('login_slogin') >= 0 || bin.body.indexOf('登录') >= 0) {
          reason = '登录会话已失效，请到"我的-网页版教务系统"重新登录后再试';
        } else if (bin.body.indexOf('尚未开放') >= 0 || bin.body.indexOf('cdwkfsq') >= 0) {
          reason = '该学年学期场地预约尚未开放申请';
        } else if (bin.code === 200) {
          reason = '导出数据格式异常，请稍后重试';
        } else {
          reason = `导出请求失败(code=${bin.code})，请检查网络后重试`;
        }
        return { rooms: [], message: reason };
      }
      const rooms: EmptyRoomItem[] = await JwApi.parseXlsxRooms(bin.data, p);
      // 解析失败时把具体诊断透传给用户（解压失败/文件为空等），避免误报"该条件下暂无教室"
      if (rooms.length === 0 && JwApi.lastXlsxError.length > 0) {
        return { rooms: [], message: JwApi.lastXlsxError };
      }
      return {
        rooms: rooms,
        message: rooms.length === 0 ? '该条件下暂无可用的空闲教室，可尝试调整条件' : ''
      };
    } catch (e) {
      return { rooms: [], message: '导出异常，请检查网络后重试' };
    }
  }

  /** 最近一次导出 xlsx 解析失败的诊断（供 exportEmptyRooms 提示用户，避免误报"无数据"） */
  private static lastXlsxError: string = '';
  /** 解析导出 xlsx（zip）：写临时文件 → unzipFile 解压 → 读 sheet1.xml + sharedStrings.xml → 按表头名映射字段 */
  private static async parseXlsxRooms(bin: ArrayBuffer, p: EmptyRoomQueryParams): Promise<EmptyRoomItem[]> {
    const out: EmptyRoomItem[] = [];
    JwApi.lastXlsxError = '';
    const ctx = AppState.context;
    if (ctx === null) {
      return out;
    }
    const cacheDir: string = ctx.cacheDir;
    try {
      // 1. 把 xlsx 二进制写入应用缓存目录
      const xlsxPath: string = `${cacheDir}/kxcdlb_export.xlsx`;
      const file = fileIo.openSync(xlsxPath,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      // writeSync 的 buffer 参数要求 ArrayBuffer | string（不能传 Uint8Array）
      fileIo.writeSync(file.fd, bin);
      fileIo.closeSync(file);
      // 2. 解压：unzipFile 要求 outFile 目录【已存在】，否则解压直接失败（SDK 文档明确）；
      //    且 rmdirSync 只能删空目录（非空抛异常）。因此每次用时间戳唯一目录并提前 mkdir，
      //    规避"目录不存在解压失败"与"旧文件残留删除失败"两个坑。
      const outDir: string = `${cacheDir}/kxcdlb_xlsx_${new Date().getTime()}`;
      fileIo.mkdirSync(outDir);
      await zlib.unzipFile(xlsxPath, outDir, {});
      // 3. 读 XML（标准 OOXML 路径；unzipFile 未按标准结构解压时递归查找兜底）
      let sheetXml: string = '';
      let sharedXml: string = '';
      try {
        sheetXml = fileIo.readTextSync(`${outDir}/xl/worksheets/sheet1.xml`);
      } catch (e) {
        sheetXml = JwApi.findXmlText(outDir, 'sheet1.xml');
      }
      try {
        sharedXml = fileIo.readTextSync(`${outDir}/xl/sharedStrings.xml`);
      } catch (e) {
        sharedXml = JwApi.findXmlText(outDir, 'sharedStrings.xml');
      }
      if (sheetXml.length === 0 || sharedXml.length === 0) {
        JwApi.lastXlsxError = '导出文件解压失败（未找到工作表数据），请稍后重试';
        LogStore.logNet('空教室', '解析', '失败',
          { method: 'POST', url: '/jwglxt/cdjy/cdjy_cxDcKxcdlb.html', status: '200', detail: `解压失败 sheet=${sheetXml.length} shared=${sharedXml.length}` });
        return out;
      }
      const shared: string[] = JwApi.parseSharedStrings(sharedXml);
      const rows: string[][] = JwApi.parseSheetRows(sheetXml, shared);
      if (rows.length < 2) {
        JwApi.lastXlsxError = '导出文件内容为空，该条件下暂无教室数据';
        LogStore.logNet('空教室', '解析', '失败',
          { method: 'POST', url: '/jwglxt/cdjy/cdjy_cxDcKxcdlb.html', status: '200', detail: `行数=${rows.length}（仅表头或无数据）` });
        return out;
      }
      // 4. 表头 → 列索引，按表头名映射字段（鲁棒，列序变化不影响）
      const header: string[] = rows[0];
      const colIdx: Record<string, number> = {};
      for (let i = 0; i < header.length; i++) {
        colIdx[header[i]] = i;
      }
      const pick = (name: string): number => {
        const idx: number = colIdx[name];
        return idx !== undefined && idx >= 0 && idx < header.length ? idx : -1;
      };
      const iCdbh: number = pick('场地编号');
      const iCdmc: number = pick('场地名称');
      const iXqmc: number = pick('校区');
      const iCdlbmc: number = pick('场地类别');
      const iZws: number = pick('座位数');
      const iJxlmc: number = pick('楼号');
      const iLch: number = pick('楼层号');
      const iBz: number = pick('场地备注信息');
      const iSybm: number = pick('使用部门');
      const iSybj: number = pick('使用班级');
      const iCdejlb: number = pick('场地二级类别');
      const iSfkjy: number = pick('是否可借用');
      const timeText: string = JwApi.buildEmptyRoomTimeText(p);
      // 日志调试：记录实际表头与关键列映射结果，用于排查"导出成功但解析无数据"（表头名不匹配时所有索引为 -1）
      LogStore.logNet('空教室', '解析', '诊断',
        { method: 'POST', url: '/jwglxt/cdjy/cdjy_cxDcKxcdlb.html', status: '200',
          detail: `行数=${rows.length} 表头=${header.join('|')} 首行=${rows.length > 1 ? rows[1].join('|') : ''} shared=${shared.length} 场地编号=${iCdbh} 场地名称=${iCdmc} 校区=${iXqmc} 类别=${iCdlbmc} 座位数=${iZws} 楼号=${iJxlmc}` });
      // 日志调试：输出 sheet1.xml 与 sharedStrings.xml 片段（确诊 V9.0 单元格格式：<v> 共享字符串 还是 <is><t> 内联字符串）
      LogStore.logNet('空教室', '解析', 'XML',
        { method: 'POST', url: '/jwglxt/cdjy/cdjy_cxDcKxcdlb.html', status: '200',
          detail: `sheet前400=${sheetXml.substring(0, 400)} shared前200=${sharedXml.substring(0, 200)}` });
      for (let r = 1; r < rows.length; r++) {
        const row: string[] = rows[r];
        const cell = (idx: number): string => (idx >= 0 && idx < row.length ? row[idx] : '');
        const item: EmptyRoomItem = {
          cdbh: cell(iCdbh),
          cdmc: cell(iCdmc),
          xqmc: cell(iXqmc),
          jxlmc: cell(iJxlmc),
          lch: cell(iLch),
          cdlbmc: cell(iCdlbmc),
          cdejlbmc: cell(iCdejlb),
          sjzws: cell(iZws),
          sybmmc: cell(iSybm),
          sybj: cell(iSybj),
          bz: cell(iBz),
          sfkfy: cell(iSfkjy),
          time: timeText
        };
        out.push(item);
      }
    } catch (e) {
      JwApi.lastXlsxError = '导出文件解析异常，请稍后重试';
      return out;
    }
    return out;
  }

  /** 在目录（含子目录）递归查找指定 xml 文件并返回其文本内容（unzipFile 解压结构兜底） */
  private static findXmlText(dir: string, fileName: string): string {
    try {
      const names: string[] = fileIo.listFileSync(dir);
      for (let i = 0; i < names.length; i++) {
        const child: string = `${dir}/${names[i]}`;
        try {
          const st = fileIo.statSync(child);
          if (st.isDirectory()) {
            const sub: string = JwApi.findXmlText(child, fileName);
            if (sub.length > 0) {
              return sub;
            }
          } else if (names[i] === fileName) {
            return fileIo.readTextSync(child);
          }
        } catch (e) {
          // 单个条目 stat/read 失败跳过，继续找下一个
        }
      }
    } catch (e) {
      // 目录不存在/不可读，返回空
    }
    return '';
  }

  /** 解析 sharedStrings.xml → 字符串数组 */
  private static parseSharedStrings(xml: string): string[] {
    const out: string[] = [];
    if (xml.length === 0) {
      return out;
    }
    const siRegex = /<si>([\s\S]*?)<\/si>/gi;
    let sm: RegExpExecArray | null;
    while ((sm = siRegex.exec(xml)) !== null) {
      const tRegex = /<t[^>]*>([\s\S]*?)<\/t>/gi;
      let tm: RegExpExecArray | null;
      let txt: string = '';
      while ((tm = tRegex.exec(sm[1])) !== null) {
        txt += tm[1];
      }
      out.push(JwApi.xmlUnescape(txt));
    }
    return out;
  }

  /** 解析 sheet1.xml → 行二维数组（含表头行），兼容 <v> 共享字符串/数值 与 <is><t> 内联字符串（V9.0 两种格式都存在） */
  private static parseSheetRows(xml: string, shared: string[]): string[][] {
    const rows: string[][] = [];
    const rowRegex = /<row[^>]*>([\s\S]*?)<\/row>/gi;
    // 先按 <c ...>...</c> 块整体匹配，再在块内分别提取 <v> 或 <t>：
    //   <c r="A1" t="s"><v>0</v></c>             → 共享字符串（查 shared 表）
    //   <c r="B2" t="inlineStr"><is><t>文本</t></is></c>  → 内联字符串
    //   <c r="C3"><v>42</v></c>                  → 数字/日期
    //   <c r="D4"/>                              → 空单元格
    const cellRegex = /<c([^>]*)>([\s\S]*?)<\/c>|<c([^>]*)\/>/gi;
    // t 属性正则含双引号，用字符串构造规避 ArkTS 正则字面量坑（00305015）
    const tAttrRe = new RegExp('t="([^"]*)"', 'i');
    const vRe = /<v>([\s\S]*?)<\/v>/i;
    const tRe = /<t[^>]*>([\s\S]*?)<\/t>/i;
    let rm: RegExpExecArray | null;
    while ((rm = rowRegex.exec(xml)) !== null) {
      const cells: string[] = [];
      let cm: RegExpExecArray | null;
      while ((cm = cellRegex.exec(rm[1])) !== null) {
        const attrs: string = cm[1] !== undefined ? cm[1] : (cm[3] !== undefined ? cm[3] : '');
        const inner: string = cm[2] !== undefined ? cm[2] : '';
        const tAttrM: RegExpExecArray | null = tAttrRe.exec(attrs);
        const t: string = tAttrM !== null ? tAttrM[1] : '';
        const vM: RegExpExecArray | null = vRe.exec(inner);
        const tM: RegExpExecArray | null = tRe.exec(inner);
        let val: string = '';
        if (t === 's') {
          // 共享字符串：<v> 是 shared 表索引
          const idx: number = parseInt(vM !== null ? vM[1] : '', 10);
          val = !isNaN(idx) && idx >= 0 && idx < shared.length ? shared[idx] : '';
        } else if (t === 'inlineStr' || t.length === 0) {
          // 内联字符串 <is><t>…</t></is>（优先），无则回退 <v>
          val = tM !== null ? tM[1] : (vM !== null ? vM[1] : '');
        } else {
          // 数字/日期/布尔等：直接取 <v>
          val = vM !== null ? vM[1] : '';
        }
        cells.push(JwApi.xmlUnescape(val));
      }
      rows.push(cells);
    }
    return rows;
  }

  /** XML 实体反转义：命名实体（&amp; 等）+ 数字实体（&#NNN; 十进制 / &#xHH; 十六进制，V9.0 内联字符串中文均用数字实体） */
  private static xmlUnescape(s: string): string {
    let r: string = s.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"').replace(/&apos;/g, "'").replace(/&#10;/g, ' ');
    // XML 数字实体（先十进制后十六进制；&#10; 已在上面转为空格，避免再被转回换行符）
    r = r.replace(/&#(\d+);/g, (m: string, d: string) => {
      const n: number = parseInt(d, 10);
      return !isNaN(n) && n > 0 ? String.fromCharCode(n) : m;
    });
    r = r.replace(/&#x([0-9a-fA-F]+);/g, (m: string, h: string) => {
      const n: number = parseInt(h, 16);
      return !isNaN(n) && n > 0 ? String.fromCharCode(n) : m;
    });
    return r;
  }


  /** 构造空闲教室时间描述（多选周次/星期/节次） */
  private static buildEmptyRoomTimeText(p: EmptyRoomQueryParams): string {
    const weeksStr: string = p.weeks.length > 0 ? p.weeks.map((w: number) => `${w}`).join('、') : '-';
    const weekDaysStr: string = p.weekdays.length > 0
      ? p.weekdays.map((w: number) => Const.WEEK_LABELS[w - 1]).join('、')
      : '-';
    const sectionsStr: string = p.sections.length > 0
      ? (p.sections.length === 1
          ? `${p.sections[0]}`
          : `${Math.min(...p.sections)}-${Math.max(...p.sections)}`)
      : '-';
    return `第 ${weeksStr} 周 ${weekDaysStr} 第 ${sectionsStr} 节`;
  }
}
