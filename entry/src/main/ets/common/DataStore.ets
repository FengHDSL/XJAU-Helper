/**
 * 本地持久化存储（@ohos.data.preferences）
 * 用途：
 *  1. 历史登录账号列表（登录页快速填充）
 *  2. 登录成功后的数据缓存（profile / 课表 / 成绩 / 考试 / 学业 / 消息），下次启动秒开
 */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { UserProfile } from '../model/Models';

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

  /** 读取历史账号（仅账号字符串数组，登录页 chips 用） */
  static getAccounts(): string[] {
    const list: Record<string, string>[] = DataStore.getAccountList();
    const out: string[] = [];
    for (const it of list) {
      out.push(it['account'] ?? '');
    }
    return out;
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

  /** 读取最近一次登录的账号 */
  static getLastAccount(): string {
    return DataStore.get(DataStore.KEY_LAST_ACCOUNT);
  }

  // ── 数据缓存（登录成功后 refreshAll 写入，各页启动读）──
  static readonly KEY_PROFILE: string = 'cache_profile';
  static readonly KEY_COURSES: string = 'cache_courses';
  static readonly KEY_TERM_SCORES: string = 'cache_term_scores';
  static readonly KEY_EXAMS: string = 'cache_exams';
  static readonly KEY_ACADEMIC: string = 'cache_academic';
  static readonly KEY_NOTICES: string = 'cache_notices';
  static readonly KEY_NOTICES_JWC: string = 'cache_notices_jwc'; // 教务处官网通知（最新两条）
  static readonly KEY_TEACHING_CAL: string = 'cache_teaching_cal';
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

  /** 以 JSON 字符串形式缓存数据 */
  static cacheJSON(key: string, value: string): void {
    DataStore.put(key, value);
    DataStore.put(DataStore.KEY_CACHE_TIME, `${Date.now()}`);
  }

  /** 读取 JSON 字符串缓存，无则返回空串 */
  static loadJSON(key: string): string {
    return DataStore.get(key);
  }
}
