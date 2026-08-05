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
import { AcademicReport, CourseItem, CreditCategory, ExamItem, LoginResult, NoticeItem, ScoreItem, SectionInfo, TermGpa, TermInfo, TermScore,
  UserProfile, WeekInfo } from '../model/Models';
import { MockData } from '../mock/MockData';
import { AppState } from '../common/AppState';
import { DataStore } from '../common/DataStore';
import { DateUtil } from '../common/DateUtil';
import { EMPTY_REPORT } from '../model/Empty';
import { HttpClient, HttpResult } from './HttpClient';
import { RsaUtil } from '../common/RsaUtil';

/** 正方下发的 RSA 公钥 */
interface RsaPublicKey {
  modulus: string;
  exponent: string;
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

  /** 正方学期码 -> 学期序号（1/2/3） */
  private static semIndexOf(xqm: string): number {
    if (xqm === '3') {
      return 1;
    }
    if (xqm === '12') {
      return 2;
    }
    return 3;
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
      const m: RegExpMatchArray | null = seg.match(reg);
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
    const m: RegExpMatchArray | null = (jcs ?? '').match(reg);
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
      return { success: false, message: '账号已被锁定/冻结，请稍后再试', profile: null, needCaptcha: false };
    }

    // 明确的密码错误且未要求验证码：直接返回失败，避免多余请求
    if (failByPwd && !needCaptcha) {
      return { success: false, message: '学号或密码错误', profile: null, needCaptcha: false };
    }

    // ── 成功判定：进入主页 或 携带 JSESSIONID 且资料可获取（双保险，模仿 HiXD）──
    if (enteredHome || hasJsession) {
      try {
        const profile: UserProfile = await JwApi.getProfile();
        if (profile.name.length > 0) {
          // 登录成功：记录账号 + 缓存资料
          DataStore.cacheProfile(profile);
          return { success: true, message: '登录成功', profile: profile, needCaptcha: false };
        }
      } catch (e) {
        // 忽略，走下面的失败分支
      }
    }
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
    const tags: RegExpMatchArray | null = html.match(tagRe);
    if (tags === null) {
      return map;
    }
    for (let i = 0; i < tags.length; i++) {
      const tag: string = tags[i];
      const nameM: RegExpMatchArray | null = tag.match(/name\s*=\s*["']?([^"'>\s]+)/i);
      const valM: RegExpMatchArray | null = tag.match(/value\s*=\s*["']?([^"'>\s]*)/i);
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

  /** 从 HTML 中提取指定 name 的隐藏域 value（如 csrftoken）。 */
  private static extractHidden(html: string, name: string): string {
    const tagRe: RegExp = new RegExp('<input[^>]*name=["\']?' + name + '["\']?[^>]*>', 'i');
    const m: RegExpMatchArray | null = html.match(tagRe);
    if (m !== null) {
      const vm: RegExpMatchArray | null = m[0].match(/value=["']?([^"'>\s]*)/i);
      if (vm !== null) {
        return vm[1] ?? '';
      }
    }
    return '';
  }

  /** 退出登录：清空会话与本地登录状态 */
  static logout(): void {
    HttpClient.clearCookie();
  }

  /** 当前学期 */
  static currentTerm(): TermInfo {
    return JwApi.term;
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
      return JwApi.delay(MockData.courses(), 500);
    }
    const parts: string[] = termId.split('-');
    const xnm: string = parts[0];
    const xqm: string = JwApi.xqmOf(termId);
    const res: HttpResult = await HttpClient.postForm('/jwglxt/kbcx/xskbcx_cxXsgrkb.html', { 'xnm': xnm, 'xqm': xqm });
    const root: ESObject = JSON.parse(res.body);
    const kbList: ESObject[] = (root['kbList'] as ESObject[]) ?? [];
    const list: CourseItem[] = [];
    for (let i = 0; i < kbList.length; i++) {
      list.push(JwApi.mapCourse(kbList[i]));
    }
    DataStore.cacheJSON(DataStore.KEY_COURSES, JSON.stringify(list));
    return list;
  }

  /** 考试安排 */
  static async getExams(termId: string): Promise<ExamItem[]> {
    if (JwApi.USE_MOCK) {
      return JwApi.delay(MockData.exams(), 500);
    }
    const parts: string[] = termId.split('-');
    const xnm: string = parts[0];
    const xqm: string = JwApi.xqmOf(termId);
    const res: HttpResult = await HttpClient.postForm('/jwglxt/kwgl/kscx_cxXsksxxIndex.html',
      { 'doType': 'query', 'xnm': xnm, 'xqm': xqm });
    const root: ESObject = JSON.parse(res.body);
    const items: ESObject[] = (root['items'] as ESObject[]) ?? [];
    const list: ExamItem[] = [];
    for (let i = 0; i < items.length; i++) {
      list.push(JwApi.mapExam(items[i]));
    }
    DataStore.cacheJSON(DataStore.KEY_EXAMS, JSON.stringify(list));
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
    return result;
  }

  /** 消息/通知（真实接口：GET /jwglxt/xtgl/index_cxDbsy.html?doType=query&flag=1&sfyy=1 -> JSON items[]） */
  static async getNotices(): Promise<NoticeItem[]> {
    if (JwApi.USE_MOCK) {
      return JwApi.delay(MockData.notices(), 400);
    }
    // 1) 优先读本地缓存（上次成功拉取）
    const cached: string = DataStore.loadJSON(DataStore.KEY_NOTICES);
    if (cached.length > 0) {
      try {
        return JSON.parse(cached) as NoticeItem[];
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
        const date: string = cjsj.length >= 10 ? cjsj.substring(0, 10) : cjsj;
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
          content: content.length > 0 ? content : title
        });
      }
      DataStore.cacheJSON(DataStore.KEY_NOTICES, JSON.stringify(list));
      return list;
    } catch (e) {
      return [];
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
    // 记录更新时间
    DataStore.put(DataStore.KEY_CACHE_TIME, `${Date.now()}`);
  }

  /** 读取缓存中的课程表（无缓存返回空数组） */
  static loadCachedCourses(): CourseItem[] {
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

  /** 读取缓存中的学期成绩 */
  static loadCachedTermScores(): TermScore[] {
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

  /** 读取缓存中的考试安排 */
  static loadCachedExams(): ExamItem[] {
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

  /** 读取缓存中的学业情况 */
  static loadCachedAcademic(): AcademicReport {
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

  /** 读取缓存中的消息列表 */
  static loadCachedNotices(): NoticeItem[] {
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

  /** 读取缓存中的学生照片（base64，无则空串） */
  static loadCachedPhoto(): string {
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
      return JwApi.delay(MockData.academic(), 550);
    }
    // 1) 优先读本地缓存
    const cached: string = DataStore.loadJSON(DataStore.KEY_ACADEMIC);
    if (cached.length > 0) {
      try {
        return JSON.parse(cached) as AcademicReport;
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
      return report;
    } catch (e) {
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
    const categories: CreditCategory[] = [];
    const catRe: RegExp = /yxxf='([\d.]+)'\s*yqzdxf='([\d.]+)'\s*sftg='(\d)'[^>]*>\s*"\s*\+\s*"([^"&]{2,30})&nbsp;/g;
    let cm: RegExpExecArray | null = catRe.exec(html);
    while (cm !== null) {
      const name: string = cm[4].trim();
      // 排除顶层汇总节点（如"2023应用化学"），只保留真实分类
      if (name.length > 0 && name.indexOf('应用化学') < 0 && name.indexOf('化学') < 0 || name.length > 0) {
        const earned: number = Number(cm[1]);
        const required: number = Number(cm[2]);
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
}
