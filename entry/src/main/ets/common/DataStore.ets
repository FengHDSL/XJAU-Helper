/**
 * 本地持久化存储（@ohos.data.preferences）
 * 用途：
 *  1. 历史登录账号列表（登录页快速填充）
 *  2. 登录成功后的数据缓存（profile / 课表 / 成绩 / 考试 / 学业 / 消息），下次启动秒开
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { UserProfile } from '../model/Models';
import { DateUtil } from './DateUtil';

export class DataStore {
  private static pref: preferences.Preferences | null = null;

  /** 需在 Ability onCreate 后调用一次，注入 context */
  static init(context: common.Context): void {
    try {
      const options: preferences.Options = { name: 'xjau_helper' };
      DataStore.pref = preferences.getPreferencesSync(context, options);
    } catch (e) {
      DataStore.pref = null;
    }
  }

  private static store(): preferences.Preferences {
    if (DataStore.pref === null) {
      throw new Error('DataStore not initialized');
    }
    return DataStore.pref;
  }

  /** 写入本地键值缓存（string） */
  static put(key: string, value: string): void {
    try {
      DataStore.store().putSync(key, value);
      DataStore.store().flush();
    } catch (e) {
      // 忽略持久化失败
    }
  }

  /** 读取本地键值缓存，不存在返回空串 */
  static get(key: string): string {
    try {
      return DataStore.store().getSync(key, '') as string;
    } catch (e) {
      return '';
    }
  }

  /** 删除单个缓存键并落盘 */
  static remove(key: string): void {
    try {
      DataStore.store().deleteSync(key);
      DataStore.store().flush();
    } catch (e) {
      // ignore
    }
  }

  /** 清空所有本地数据（含历史账号、缓存、个人信息等） */
  static clearAll(): void {
    try {
      DataStore.store().clearSync();
      DataStore.store().flush();
    } catch (e) {
      // ignore
    }
  }

  // ── 历史账号（密码加密后保存，本地基础防护，敏感数据仍请慎用）──
  static readonly KEY_ACCOUNTS: string = 'login_accounts';
  static readonly KEY_LAST_ACCOUNT: string = 'last_account';
  static readonly KEY_SHOW_AVATAR: string = 'show_avatar';
  // 当前学期 ID（全局设置，启动时优先恢复）
  static readonly KEY_DS_TERM: string = 'current_term_id';
  // 自定义开学时间：各学期 termId -> 自定义开学日(yyyy-MM-dd)，覆盖默认 9-01/3-01 推算；空串=未自定义
  static readonly KEY_CUSTOM_TERM_START: string = 'custom_term_start';

  /** 读取某学期的自定义开学日（空串=未自定义，用默认推算） */
  static getCustomTermStart(termId: string): string {
    const raw: string = DataStore.get(DataStore.KEY_CUSTOM_TERM_START);
    if (raw.length === 0) {
      return '';
    }
    try {
      const map: Record<string, string> = JSON.parse(raw) as Record<string, string>;
      return map[termId] ?? '';
    } catch (e) {
      return '';
    }
  }

  /** 设置某学期的自定义开学日（date 为空串则清除该学期的自定义） */
  static setCustomTermStart(termId: string, date: string): void {
    const raw: string = DataStore.get(DataStore.KEY_CUSTOM_TERM_START);
    let map: Record<string, string> = {};
    if (raw.length > 0) {
      try {
        map = JSON.parse(raw) as Record<string, string>;
      } catch (e) {
        map = {};
      }
    }
    if (date.length === 0) {
      const rebuilt: Record<string, string> = {};
      for (const k of Object.keys(map)) {
        if (k !== termId) {
          rebuilt[k] = map[k];
        }
      }
      map = rebuilt;
    } else {
      map[termId] = date;
    }
    DataStore.put(DataStore.KEY_CUSTOM_TERM_START, JSON.stringify(map));
  }
  // 隐私协议：是否已同意 + 同意时间
  static readonly KEY_PRIVACY_AGREED: string = 'privacy_agreed';
  static readonly KEY_PRIVACY_AGREED_AT: string = 'privacy_agreed_at';
  // 账号风控提醒是否已展示（首次启动，开发者声明之后）
  static readonly KEY_RISK_TIP_SHOWN: string = 'risk_tip_shown';
  // 网页登录会话 Cookie（持久化，下次启动恢复）
  static readonly KEY_SESSION_COOKIE: string = 'session_cookie';
  // 自动重新登录凭据（账号+加密密码，冷启动时静默重登刷新会话）
  static readonly KEY_AUTO_ACCOUNT: string = 'auto_relogin_account';
  static readonly KEY_AUTO_PWD: string = 'auto_relogin_pwd';
  // 当前登录方式：'pwd'=账号密码登录，'web'=网页登录（我的页退出按钮长按提示用）
  static readonly KEY_LOGIN_METHOD: string = 'login_method';

  // 用户在桌面卡片主动选择的"要倒计时的考试"id（持久化，供 EntryFormAbility 读取）
  static readonly KEY_PICKED_EXAM: string = 'picked_exam_id';

  /** 用户主动选定的考试 id（空串表示用最近一场未开始的考试） */
  static setPickedExamId(id: string): void {
    DataStore.put(DataStore.KEY_PICKED_EXAM, id);
  }

  /** 读取用户主动选定的考试 id */
  static getPickedExamId(): string {
    return DataStore.get(DataStore.KEY_PICKED_EXAM);
  }

  // 课程表设置（背景图、网格虚线、课程名→颜色索引）
  static readonly KEY_SCHEDULE_BG: string = 'schedule_bg';
  static readonly KEY_SCHEDULE_DASHED: string = 'schedule_dashed';
  static readonly KEY_SCHEDULE_CFG: string = 'schedule_cfg';
  static readonly KEY_COURSE_COLOR_MAP: string = 'course_color_map';
  /** 课程独立颜色：课程名 → 自定义 hex（3 套 × 20 色选择器，空=按课程名 hash 默认） */
  static readonly KEY_COURSE_CUSTOM_COLOR: string = 'course_custom_color';

  /** 设置课程表背景图（base64 编码的 JPEG/PNG），空串表示恢复默认 */
  static setScheduleBg(b64: string): void {
    DataStore.put(DataStore.KEY_SCHEDULE_BG, b64);
  }

  /** 读取课程表背景图（空串=无背景） */
  static getScheduleBg(): string {
    return DataStore.get(DataStore.KEY_SCHEDULE_BG);
  }



  /** 保存课程表完整自定义配置（JSON，见 ScheduleConfig） */
  static setScheduleCfg(json: string): void {
    DataStore.put(DataStore.KEY_SCHEDULE_CFG, json);
  }


  /** 读取课程独立颜色 JSON（课程名 → hex 的 Record 序列化，空串=无自定义） */
  static getCourseCustomColors(): string {
    return DataStore.get(DataStore.KEY_COURSE_CUSTOM_COLOR);
  }

  /** 保存课程独立颜色 JSON */
  static setCourseCustomColors(json: string): void {
    DataStore.put(DataStore.KEY_COURSE_CUSTOM_COLOR, json);
  }

  /**
   * 登录方式：
   *  - 'auto'   = 新版：冷启动自动用保存的账号密码重新登录（推荐，默认）
   *  - 'legacy' = 旧版：冷启动不重新登录（保留会话过期可能导致功能不可用）
   *  - ''       = 用户尚未选择（首次启用时由 LoginView 询问）
   */
  static readonly KEY_LOGIN_MODE: string = 'login_mode';

  /** 设置登录方式（auto/legacy） */
  static setLoginMode(mode: string): void {
    DataStore.put(DataStore.KEY_LOGIN_MODE, mode);
  }

  /** 读取登录方式，未选择时返回空串 */
  static getLoginMode(): string {
    return DataStore.get(DataStore.KEY_LOGIN_MODE);
  }

  /** 记录当前登录方式（pwd/web） */
  static setLoginMethod(method: string): void {
    DataStore.put(DataStore.KEY_LOGIN_METHOD, method);
  }

  /** 读取当前登录方式，未知返回空串 */
  static getLoginMethod(): string {
    return DataStore.get(DataStore.KEY_LOGIN_METHOD);
  }

  /** 是否已同意隐私协议 */
  static isPrivacyAgreed(): boolean {
    return DataStore.get(DataStore.KEY_PRIVACY_AGREED) === '1';
  }

  /** 设置隐私协议已同意（写入同意时间，供协议页右下角展示） */
  static setPrivacyAgreed(): void {
    const ts: string = DateUtil.formatCn(new Date());
    DataStore.put(DataStore.KEY_PRIVACY_AGREED, '1');
    DataStore.put(DataStore.KEY_PRIVACY_AGREED_AT, ts);
  }

  /** 读取同意时间（未同意返回空串） */
  static getPrivacyAgreedAt(): string {
    return DataStore.get(DataStore.KEY_PRIVACY_AGREED_AT);
  }

  /** 账号风控提醒是否已展示过（首次启动，开发者声明之后） */
  static isRiskTipShown(): boolean {
    return DataStore.get(DataStore.KEY_RISK_TIP_SHOWN) === '1';
  }

  /** 标记风控提醒已展示 */
  static setRiskTipShown(): void {
    DataStore.put(DataStore.KEY_RISK_TIP_SHOWN, '1');
  }

  /** 记录一次成功登录的账号（去重、置顶、最多保留 8 个，密码 base64+XOR 编码存储） */
  static addAccount(account: string, password: string): void {
    if (account.length === 0) {
      return;
    }
    const list: Record<string, string>[] = DataStore.getAccountList();
    const filtered: Record<string, string>[] = [];
    for (const a of list) {
      if (a['account'] !== account) {
        filtered.push(a);
      }
    }
    filtered.unshift({ 'account': account, 'password': DataStore.encodePwd(password) });
    while (filtered.length > 8) {
      filtered.pop();
    }
    DataStore.put(DataStore.KEY_ACCOUNTS, JSON.stringify(filtered));
    DataStore.put(DataStore.KEY_LAST_ACCOUNT, account);
  }

  /** 读取历史账号列表（每项包含 account + 加密后的 password） */
  static getAccountList(): Record<string, string>[] {
    const raw: string = DataStore.get(DataStore.KEY_ACCOUNTS);
    if (raw.length === 0) {
      return [];
    }
    interface AccountEntry {
      account: string;
      password: string;
    }
    try {
      const parsed: AccountEntry[] = JSON.parse(raw) as AccountEntry[];
      if (Array.isArray(parsed)) {
        const out: Record<string, string>[] = [];
        for (let i = 0; i < parsed.length; i++) {
          const e: AccountEntry = parsed[i];
          out.push({ 'account': e.account, 'password': e.password });
        }
        return out;
      }
      return [];
    } catch (e) {
      return [];
    }
  }


  /** 解密历史账号的密码 */
  static decodePwd(encoded: string): string {
    if (encoded.length === 0) {
      return '';
    }
    try {
      const buf: Uint8Array = DataStore.b64decode(encoded);
      let out: string = '';
      for (let i = 0; i < buf.length; i++) {
        out += String.fromCharCode(buf[i] ^ 0x5A);
      }
      return out;
    } catch (e) {
      return '';
    }
  }

  /** 加密密码（XOR 0x5A + base64，仅本地基础防护） */
  static encodePwd(pwd: string): string {
    if (pwd.length === 0) {
      return '';
    }
    const bytes: Uint8Array = new Uint8Array(pwd.length);
    for (let i = 0; i < pwd.length; i++) {
      bytes[i] = pwd.charCodeAt(i) ^ 0x5A;
    }
    return DataStore.b64encode(bytes);
  }

  private static b64encode(bytes: Uint8Array): string {
    const chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    let result: string = '';
    let i: number = 0;
    for (; i + 2 < bytes.length; i += 3) {
      const triplet: number = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
      result += chars.charAt((triplet >> 18) & 0x3F) + chars.charAt((triplet >> 12) & 0x3F) +
        chars.charAt((triplet >> 6) & 0x3F) + chars.charAt(triplet & 0x3F);
    }
    if (i < bytes.length) {
      const rem: number = bytes.length - i;
      if (rem === 1) {
        const b1: number = bytes[i];
        result += chars.charAt((b1 >> 2) & 0x3F) + chars.charAt((b1 << 4) & 0x3F) + '==';
      } else {
        const b1: number = bytes[i];
        const b2: number = bytes[i + 1];
        result += chars.charAt((b1 >> 2) & 0x3F) + chars.charAt(((b1 << 4) | (b2 >> 4)) & 0x3F) +
          chars.charAt((b2 << 2) & 0x3F) + '=';
      }
    }
    return result;
  }

  private static b64decode(text: string): Uint8Array {
    const chars: string = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    const lookup: Record<string, number> = {};
    for (let i = 0; i < chars.length; i++) {
      lookup[chars.charAt(i)] = i;
    }
    const cleaned: string = text.replace(/[^A-Za-z0-9+/=]/g, '');
    const len: number = cleaned.length;
    let outLen: number = Math.floor((len * 3) / 4);
    if (cleaned.charAt(len - 1) === '=') {
      outLen -= 1;
    }
    if (cleaned.charAt(len - 2) === '=') {
      outLen -= 1;
    }
    const out: Uint8Array = new Uint8Array(outLen);
    let p: number = 0;
    for (let i: number = 0; i < len; i += 4) {
      const c0: number = lookup[cleaned.charAt(i)] ?? 0;
      const c1: number = lookup[cleaned.charAt(i + 1)] ?? 0;
      const c2: number = lookup[cleaned.charAt(i + 2)] ?? 0;
      const c3: number = lookup[cleaned.charAt(i + 3)] ?? 0;
      const triple: number = (c0 << 18) | (c1 << 12) | ((c2 & 0x3F) << 6) | (c3 & 0x3F);
      if (p < outLen) {
        out[p++] = (triple >> 16) & 0xFF;
      }
      if (p < outLen) {
        out[p++] = (triple >> 8) & 0xFF;
      }
      if (p < outLen) {
        out[p++] = triple & 0xFF;
      }
    }
    return out;
  }


  // ── 数据缓存（登录成功后 refreshAll 写入，各页启动读）──
  static readonly KEY_PROFILE: string = 'cache_profile';
  static readonly KEY_COURSES: string = 'cache_courses';
  static readonly KEY_TERM_SCORES: string = 'cache_term_scores';
  static readonly KEY_EXAMS: string = 'cache_exams';
  static readonly KEY_ACADEMIC: string = 'cache_academic';
  static readonly KEY_NOTICES: string = 'cache_notices';
  static readonly KEY_NOTICES_JWC: string = 'cache_notices_jwc'; // 教务处官网通知（最新两条）
  static readonly KEY_TEACHING_CAL: string = 'cache_teaching_cal'; // 校历缓存 key（清理缓存时一并清除）
  static readonly KEY_JWC_CAL: string = 'cache_jwc_cal'; // 校历转换结果（含来源标记，变化才更新）
  static readonly KEY_PHOTO: string = 'cache_photo';
  static readonly KEY_CACHE_TIME: string = 'cache_time';

  /** 缓存学生信息到本地 */
  static cacheProfile(profile: UserProfile | null): void {
    if (profile === null) {
      DataStore.remove(DataStore.KEY_PROFILE);
      return;
    }
    DataStore.put(DataStore.KEY_PROFILE, JSON.stringify(profile));
  }

  /** 读取缓存的学生信息，无则返回 null */
  static loadCachedProfile(): UserProfile | null {
    const raw: string = DataStore.get(DataStore.KEY_PROFILE);
    if (raw.length === 0) {
      return null;
    }
    try {
      return JSON.parse(raw) as UserProfile;
    } catch (e) {
      return null;
    }
  }

  // 农大新闻收藏（title/url/date/thumb 的 JSON 数组，按收藏时间倒序）
  static readonly KEY_NEWS_FAVS: string = 'news_favs';

  /** 读取收藏的新闻列表（NewsItem 序列化数组，按收藏时间倒序） */
  static loadNewsFavs(): string[] {
    const raw: string = DataStore.get(DataStore.KEY_NEWS_FAVS);
    if (raw.length === 0) {
      return [];
    }
    try {
      const parsed: string[] = JSON.parse(raw) as string[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
      return [];
    }
  }

  /** 保存收藏列表（内部：整表覆盖） */
  private static saveNewsFavs(list: string[]): void {
    DataStore.put(DataStore.KEY_NEWS_FAVS, JSON.stringify(list));
  }

  /** 是否已收藏（按 url 判断） */
  static isNewsFav(url: string): boolean {
    if (url.length === 0) {
      return false;
    }
    const list: string[] = DataStore.loadNewsFavs();
    for (const raw of list) {
      try {
        const it: Record<string, string> = JSON.parse(raw) as Record<string, string>;
        if (it['url'] === url) {
          return true;
        }
      } catch (e) {
        // ignore
      }
    }
    return false;
  }

  /** 收藏一篇新闻（传 NewsItem 关键字段 JSON；已收藏则忽略，返回是否新增） */
  static addNewsFav(itemJson: string): boolean {
    if (itemJson.length === 0) {
      return false;
    }
    let url: string = '';
    try {
      const it: Record<string, string> = JSON.parse(itemJson) as Record<string, string>;
      url = it['url'] ?? '';
    } catch (e) {
      return false;
    }
    if (url.length === 0) {
      return false;
    }
    if (DataStore.isNewsFav(url)) {
      return false;
    }
    const list: string[] = DataStore.loadNewsFavs();
    list.unshift(itemJson); // 新收藏置顶
    DataStore.saveNewsFavs(list);
    return true;
  }

  /** 取消收藏（按 url 移除） */
  static removeNewsFav(url: string): void {
    if (url.length === 0) {
      return;
    }
    const list: string[] = DataStore.loadNewsFavs();
    const filtered: string[] = [];
    for (const raw of list) {
      try {
        const it: Record<string, string> = JSON.parse(raw) as Record<string, string>;
        if (it['url'] !== url) {
          filtered.push(raw);
        }
      } catch (e) {
        filtered.push(raw);
      }
    }
    DataStore.saveNewsFavs(filtered);
  }

  /** 以 JSON 字符串形式缓存数据 */
  static cacheJSON(key: string, value: string): void {
    DataStore.put(key, value);
    DataStore.put(DataStore.KEY_CACHE_TIME, `${Date.now()}`);
  }

  /** 读取 JSON 字符串缓存，无则返回空串 */
  static loadJSON(key: string): string {
    return DataStore.get(key);
  }

  // 应用级共享网页浏览历史（持久化：重启后保留）
  static readonly KEY_WEB_HISTORY: string = 'web_history';

  /** 读取共享网页历史 JSON 数组（未记录返回空串） */
  static loadWebHistoryJson(): string {
    return DataStore.get(DataStore.KEY_WEB_HISTORY);
  }

  /** 保存共享网页历史 JSON 数组（空串=清空） */
  static saveWebHistoryJson(json: string): void {
    DataStore.put(DataStore.KEY_WEB_HISTORY, json);
  }
}
