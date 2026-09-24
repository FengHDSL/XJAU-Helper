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

/** 外观设置组合：背景壁纸 + 顶栏主题色 + 副标题颜色 */
export interface ThemeCombo {
  name: string;
  wallpaper: string;
  theme: string;
  subtitle: string;
}

/** 自定义字体条目：alias = 注册到系统字体库的别名，fileName = 应用沙箱内的文件名 */
export interface CustomFontItem {
  alias: string;
  fileName: string;
}

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
  // ── 备份 / 恢复（全部应用信息，排除账号、密码与登录 Cookie）──
  /** 不参与备份的敏感键（账号、密码、会话凭据） */
  static readonly BACKUP_EXCLUDE: string[] = [
    'login_accounts', 'last_account', 'auto_relogin_account', 'auto_relogin_pwd',
    'session_cookie', 'cas_tgc', 'sso_cookies'
  ];

  /** 参与备份的键（设置项 + 数据缓存 + 个人化内容） */
  static readonly BACKUP_KEYS: string[] = [
    'show_avatar', 'current_term_id', 'custom_term_start', 'custom_term_end', 'semester_label',
    'privacy_agreed', 'privacy_agreed_at', 'risk_tip_shown', 'declaration_shown',
    'login_method', 'login_system', 'login_mode', 'picked_exam_id',
    'schedule_bg', 'schedule_dashed', 'schedule_cfg', 'course_color_map', 'course_custom_color',
    'wallpaper_id', 'wallpaper_mask', 'wallpaper_url', 'wallpaper_url_date',
    'dark_mode', 'bar_style', 'immersive_effect', 'subtitle_color', 'theme_combos',
    'card_tint', 'immersive_press_glow', 'card_glow_touch', 'custom_accent_full',
    'font_mode', 'font_family_zh', 'font_family_en', 'font_weight_mode', 'font_weight_value',
    'custom_fonts',
    'cache_profile', 'cache_courses', 'cache_term_scores', 'cache_exams', 'cache_academic',
    'cache_notices', 'cache_notices_jwc', 'cache_teaching_cal', 'cache_jwc_cal',
    'cache_photo', 'cache_time', 'news_favs', 'web_history'
  ];

  /** 导出全部可备份数据（不含账号、密码、Cookie） */
  static exportAll(): Record<string, string> {
    const out: Record<string, string> = {};
    for (let i = 0; i < DataStore.BACKUP_KEYS.length; i++) {
      const k: string = DataStore.BACKUP_KEYS[i];
      const v: string = DataStore.get(k);
      if (v.length > 0) {
        out[k] = v;
      }
    }
    return out;
  }

  /** 导入可备份数据（自动跳过敏感键），返回写入条数 */
  static importAll(data: Record<string, string>): number {
    let n: number = 0;
    const keys: string[] = Object.keys(data);
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      if (DataStore.BACKUP_EXCLUDE.indexOf(k) >= 0) {
        continue;
      }
      const v: string = data[k];
      if (typeof v === 'string') {
        DataStore.put(k, v);
        n++;
      }
    }
    return n;
  }

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
  /** 「记住密码」勾选状态（持久化：退出登录/重启后仍记住，自动填充已保存密码） */
  static readonly KEY_REMEMBER: string = 'remember_pwd';

  /** 保存「记住密码」勾选状态 */
  static saveRemember(on: boolean): void {
    DataStore.put(DataStore.KEY_REMEMBER, on ? '1' : '0');
  }

  /** 读取「记住密码」勾选状态（默认关闭，隐私优先） */
  static loadRemember(): boolean {
    return DataStore.get(DataStore.KEY_REMEMBER) === '1';
  }

  // ── 应用内字体大小（字体管理页调节，全局生效；启动时由 EntryAbility 恢复）──
  static readonly KEY_FONT_SCALE: string = 'font_scale';

  /** 保存字体缩放倍数（1.0 = 标准） */
  static saveFontScale(v: number): void {
    DataStore.put(DataStore.KEY_FONT_SCALE, `${v}`);
  }

  /** 读取字体缩放倍数（默认 1.0，范围 0.8~1.6 兜底） */
  static loadFontScale(): number {
    const raw: string = DataStore.get(DataStore.KEY_FONT_SCALE);
    if (raw.length === 0) {
      return 1.0;
    }
    const v: number = Number(raw);
    return isNaN(v) ? 1.0 : Math.max(0.8, Math.min(1.6, v));
  }

  // ── 通透程度滑条（外观设置页可调：0~100，控制毛玻璃模糊强度与透明度）──
  static readonly KEY_GLASS_STRENGTH: string = 'glass_strength';

  /** 保存玻璃强度 */
  static saveGlassStrength(v: number): void {
    DataStore.put(DataStore.KEY_GLASS_STRENGTH, `${Math.max(0, Math.min(100, Math.round(v)))}`);
  }

  /** 读取玻璃强度（默认 70） */
  static loadGlassStrength(): number {
    const v: number = Number(DataStore.get(DataStore.KEY_GLASS_STRENGTH));
    return isNaN(v) ? 70 : Math.max(0, Math.min(100, v));
  }

  // ── 灰色字体颜色覆盖（default=自动跟随深浅 / gray=固定灰 / white / black / custom）──
  static readonly KEY_GRAY_MODE: string = 'gray_text_mode';
  static readonly KEY_GRAY_CUSTOM: string = 'gray_text_custom';

  /** 保存灰字模式 */
  static saveGrayMode(mode: string): void {
    DataStore.put(DataStore.KEY_GRAY_MODE, mode);
  }

  /** 读取灰字模式（默认 default） */
  static loadGrayMode(): string {
    const v: string = DataStore.get(DataStore.KEY_GRAY_MODE);
    return (v === 'gray' || v === 'white' || v === 'black' || v === 'custom') ? v : 'default';
  }

  /** 保存自定义灰字颜色（rrggbb） */
  static saveGrayCustom(color: string): void {
    DataStore.put(DataStore.KEY_GRAY_CUSTOM, color);
  }

  /** 读取自定义灰字颜色（未设置返回空串） */
  static loadGrayCustom(): string {
    return DataStore.get(DataStore.KEY_GRAY_CUSTOM);
  }

  /** 每页单独灰字色 JSON（pageKey -> rrggbb） */
  static readonly KEY_GRAY_PAGE_MAP: string = 'gray_text_page_map';

  /** 读取每页单独灰字色 map（JSON 反序列化；为空/损坏返回空 Map） */
  static loadGrayPageMap(): Map<string, string> {
    const raw: string = DataStore.get(DataStore.KEY_GRAY_PAGE_MAP);
    const m: Map<string, string> = new Map();
    if (raw.length < 2 || !raw.startsWith('{')) {
      return m;
    }
    try {
      const obj: Record<string, string> = JSON.parse(raw) as Record<string, string>;
      const keys: string[] = Object.keys(obj);
      for (let i: number = 0; i < keys.length; i++) {
        const v: string = obj[keys[i]];
        if (typeof v === 'string' && v.length >= 6) {
          m.set(keys[i], v);
        }
      }
    } catch (e) {
      // JSON 损坏时返回空 map（覆盖失效但不崩溃）
    }
    return m;
  }

  /** 保存每页单独灰字色 map（JSON 序列化） */
  static saveGrayPageMap(m: Map<string, string>): void {
    const obj: Record<string, string> = {};
    m.forEach((v: string, k: string) => {
      obj[k] = v;
    });
    DataStore.put(DataStore.KEY_GRAY_PAGE_MAP, JSON.stringify(obj));
  }

  // 当前学期 ID（全局设置，启动时优先恢复）
  static readonly KEY_DS_TERM: string = 'current_term_id';
  // 自定义开学时间：各学期 termId -> 自定义开学日(yyyy-MM-dd)，覆盖默认 9-01/3-01 推算；空串=未自定义
  static readonly KEY_CUSTOM_TERM_START: string = 'custom_term_start';
  /** 自定义学期结束日（yyyy-MM-dd，空 = 使用校历解析值） */
  static readonly KEY_CUSTOM_TERM_END: string = 'custom_term_end';
  /** 自定义学年学期标题（空 = 使用校历解析值） */
  static readonly KEY_SEMESTER_LABEL: string = 'semester_label';

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
  // 开发者声明是否已展示（同意隐私后改为"用户首次任意点击"时弹出，仅一次）
  static readonly KEY_DECLARATION_SHOWN: string = 'declaration_shown';
  // 网页登录会话 Cookie（持久化，下次启动恢复）
  static readonly KEY_SESSION_COOKIE: string = 'session_cookie';
  // 自动重新登录凭据（账号+加密密码，冷启动时静默重登刷新会话）
  static readonly KEY_AUTO_ACCOUNT: string = 'auto_relogin_account';
  static readonly KEY_AUTO_PWD: string = 'auto_relogin_pwd';
  // 当前登录方式：'pwd'=账号密码登录，'web'=网页登录（我的页退出按钮长按提示用）
  static readonly KEY_LOGIN_METHOD: string = 'login_method';
  // 当前登录系统：'original'=教务登录（教务系统 RSA 直登）/ 'service'=服务大厅登录（统一身份认证 CAS）
  // 冷启动按此决定刷新方式（服务大厅登录：教务会话不可持久化，须用 CASTGC 重新桥接；教务登录：按重登方式）
  static readonly KEY_LOGIN_SYSTEM: string = 'login_system';
  // 统一身份认证 TGC（CASTGC）：开启"7天免登录"时持久化，冷启动静默重登教务系统会话用
  static readonly KEY_CAS_TGC: string = 'cas_tgc';
  // SSO 会话 Cookie（网页版"服务大厅"登录后捕获，host\ncookie 成对存储）：
  // 我的页「服务大厅/第二课堂」等 SSO 页面打开时按域名注入，保持登录态
  static readonly KEY_SSO_COOKIES: string = 'sso_cookies';

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

  /** 取消隐私同意（清空同意标记与时间；下次启动重新弹出引导） */
  static clearPrivacyAgreed(): void {
    DataStore.put(DataStore.KEY_PRIVACY_AGREED, '');
    DataStore.put(DataStore.KEY_PRIVACY_AGREED_AT, '');
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

  /** 开发者声明是否已展示过（同意隐私后首次点击弹出，仅一次） */
  static isDeclarationShown(): boolean {
    return DataStore.get(DataStore.KEY_DECLARATION_SHOWN) === '1';
  }

  /** 标记开发者声明已展示 */
  static setDeclarationShown(): void {
    DataStore.put(DataStore.KEY_DECLARATION_SHOWN, '1');
  }

  // ── 全局壁纸（我的页选择，主界面背景；b1~b6 预置，c:<path> 相册导入，'none'=未启用）──
  static readonly KEY_WALLPAPER: string = 'wallpaper_id';

  /** 保存当前壁纸 id（空串/'none'=未启用） */
  static saveWallpaper(id: string): void {
    DataStore.put(DataStore.KEY_WALLPAPER, id);
  }

  /** 读取当前壁纸 id（空串=未设置，默认 'none' 由调用方兜底） */
  static loadWallpaper(): string {
    return DataStore.get(DataStore.KEY_WALLPAPER);
  }

  // ── 壁纸蒙版（可读性遮罩）开关：'1'=开（默认） / '0'=关 ──
  static readonly KEY_WALLPAPER_MASK: string = 'wallpaper_mask';

  static wallpaperMaskOn(): boolean {
    return DataStore.get(DataStore.KEY_WALLPAPER_MASK) !== '0';
  }

  static setWallpaperMask(on: boolean): void {
    DataStore.put(DataStore.KEY_WALLPAPER_MASK, on ? '1' : '0');
  }

  // ── 壁纸图像地址（用户填写的 URL；保存后每天自动下载新壁纸）──
  static readonly KEY_WALLPAPER_URL: string = 'wallpaper_url';
  static readonly KEY_WALLPAPER_URL_DATE: string = 'wallpaper_url_date';

  static saveWallpaperUrl(url: string): void {
    DataStore.put(DataStore.KEY_WALLPAPER_URL, url);
  }

  static loadWallpaperUrl(): string {
    return DataStore.get(DataStore.KEY_WALLPAPER_URL);
  }

  /** 记录最近一次自动/手动按 URL 更新壁纸的日期（YYYY-MM-DD） */
  static setWallpaperUrlDate(date: string): void {
    DataStore.put(DataStore.KEY_WALLPAPER_URL_DATE, date);
  }

  static loadWallpaperUrlDate(): string {
    return DataStore.get(DataStore.KEY_WALLPAPER_URL_DATE);
  }

  // ── 深色模式（开关，默认浅色）──
  static readonly KEY_DARK: string = 'dark_mode';

  /** 是否深色模式（未设置时默认为浅色） */
  /** 是否已手动设置过深色模式（'1'/'0'；空 = 未设置，跟随系统） */
  static hasDarkSetting(): boolean {
    const v: string = DataStore.get(DataStore.KEY_DARK);
    return v === '1' || v === '0';
  }

  static isDarkOn(): boolean {
    return DataStore.get(DataStore.KEY_DARK) === '1';
  }

  /** 设置深色模式 */
  static setDark(on: boolean): void {
    DataStore.put(DataStore.KEY_DARK, on ? '1' : '0');
  }

  // ── 顶栏样式：新版(渐变, 默认) / 旧版 1.3.1 实色 ──
  static readonly KEY_BAR_STYLE: string = 'bar_style';

  static barStyle(): string {
    const raw: string = DataStore.get(DataStore.KEY_BAR_STYLE);
    return raw === 'legacy' ? 'legacy' : 'new';
  }

  static setBarStyle(style: string): void {
    DataStore.put(DataStore.KEY_BAR_STYLE, style === 'legacy' ? 'legacy' : 'new');
  }

  // ── 沉浸光感（系统材质）开关：'1'=开 / '0'=关（默认关：效果依赖 API26+，且可能发热/掉帧）──
  static readonly KEY_IMMERSIVE: string = 'immersive_effect';

  /** 沉浸光感开关（外观设置主开关，默认关闭；仅 '1' 时开启） */
  static immersiveOn(): boolean {
    return DataStore.get(DataStore.KEY_IMMERSIVE) === '1';
  }

  /** 沉浸光感风险提示已确认（首次开启弹窗确认过一次后不再提示） */
  static readonly KEY_IMMERSIVE_HINT: string = 'immersive_hint_shown';

  static immersiveHintShown(): boolean {
    return DataStore.get(DataStore.KEY_IMMERSIVE_HINT) === '1';
  }

  static markImmersiveHintShown(): void {
    DataStore.put(DataStore.KEY_IMMERSIVE_HINT, '1');
  }

  static setImmersive(on: boolean): void {
    DataStore.put(DataStore.KEY_IMMERSIVE, on ? '1' : '0');
  }

  // ── 顶栏副标题颜色（空 = 自动，按顶栏样式/深浅决定）──
  static readonly KEY_SUBTITLE_COLOR: string = 'subtitle_color';

  static subtitleColor(): string {
    return DataStore.get(DataStore.KEY_SUBTITLE_COLOR);
  }

  static setSubtitleColor(color: string): void {
    DataStore.put(DataStore.KEY_SUBTITLE_COLOR, color);
  }

  // ── 外观设置组合（背景 + 顶栏颜色 + 副标题颜色）──
  static readonly KEY_THEME_COMBOS: string = 'theme_combos';

  /** 已保存的组合列表 */
  static combos(): ThemeCombo[] {
    const raw: string = DataStore.get(DataStore.KEY_THEME_COMBOS);
    if (raw.length === 0) {
      return [];
    }
    try {
      return JSON.parse(raw) as ThemeCombo[];
    } catch (e) {
      return [];
    }
  }

  /** 保存组合（同名覆盖） */
  static saveCombo(c: ThemeCombo): void {
    const list: ThemeCombo[] = DataStore.combos();
    const out: ThemeCombo[] = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].name !== c.name) {
        out.push(list[i]);
      }
    }
    out.push(c);
    DataStore.put(DataStore.KEY_THEME_COMBOS, JSON.stringify(out));
  }

  /** 删除组合（按名称） */
  static removeCombo(name: string): void {
    const list: ThemeCombo[] = DataStore.combos();
    const out: ThemeCombo[] = [];
    for (let i = 0; i < list.length; i++) {
      if (list[i].name !== name) {
        out.push(list[i]);
      }
    }
    DataStore.put(DataStore.KEY_THEME_COMBOS, JSON.stringify(out));
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
  /** 总体成绩（累计统计 + 课程明细）缓存，移植自参考项目的成绩「总体」 */
  static readonly KEY_OVERALL_GRADES: string = 'cache_overall_grades';
  /** 抢课目标队列（GrabTarget[] JSON），对应参考项目 AcademicGrabQueueStore */
  static readonly KEY_GRAB_QUEUE: string = 'grab_queue';
  /** 抢课定时策略（GrabPolicy JSON）：间隔/最大轮次/成功后是否继续 */
  static readonly KEY_GRAB_POLICY: string = 'grab_policy';
  static readonly KEY_NOTICES: string = 'cache_notices';
  static readonly KEY_NOTICES_JWC: string = 'cache_notices_jwc'; // 教务处官网通知（最新两条）
  static readonly KEY_TEACHING_CAL: string = 'cache_teaching_cal'; // 校历缓存 key（清理缓存时一并清除）
  static readonly KEY_JWC_CAL: string = 'cache_jwc_cal'; // 校历转换结果（含来源标记，变化才更新）
  static readonly KEY_PHOTO: string = 'cache_photo';
  static readonly KEY_CACHE_TIME: string = 'cache_time';
  /**
   * 课表最近一次成功拉取的标记：'<termId>|<yyyy-MM-dd>'。
   * 用途：课表**每天只自动查询识别一次**（同一天内直接读缓存），
   * 需要立即更新时由课表的刷新按钮强制重取。
   */
  static readonly KEY_COURSES_FETCH: string = 'cache_courses_fetch';

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
  /** 收藏变化信号（AppStorage）：收藏/取消收藏后写入时间戳，新闻页「收藏」板块据此即时刷新 */
  static readonly KEY_NEWS_FAV_VERSION: string = 'newsFavVersion';

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
    // 收藏变化信号：通知新闻页「收藏」板块即时刷新（TabContent.onAppear 仅首次触发）
    AppStorage.setOrCreate(DataStore.KEY_NEWS_FAV_VERSION, Date.now());
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
    // 收藏变化信号（同上）
    AppStorage.setOrCreate(DataStore.KEY_NEWS_FAV_VERSION, Date.now());
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
  /** 新闻页：是否获取封面缩略图（'1'=开（默认） / '0'=关） */
  static readonly KEY_NEWS_THUMB: string = 'news_thumb';

  /** 是否获取新闻封面缩略图（默认开启；'0' 时关闭，节省流量） */
  static newsThumbOn(): boolean {
    return DataStore.get(DataStore.KEY_NEWS_THUMB) !== '0';
  }

  static setNewsThumb(on: boolean): void {
    DataStore.put(DataStore.KEY_NEWS_THUMB, on ? '1' : '0');
  }

  /** 读取共享网页历史 JSON 数组（未记录返回空串） */
  static loadWebHistoryJson(): string {
    return DataStore.get(DataStore.KEY_WEB_HISTORY);
  }

  /** 保存共享网页历史 JSON 数组（空串=清空） */
  static saveWebHistoryJson(json: string): void {
    DataStore.put(DataStore.KEY_WEB_HISTORY, json);
  }

  // ══════════════════════════════════════════════════════════════
  // 外观设置（移植自参考项目 miha_hm：卡片沾色 / 主题色流光 /
  // 卡片流光触感 / 高权限自定义主题色 / 字体管理）
  // 对应参考文件：miha_hm `utils/DesignTokens.ets`（键名与默认值）+ `pages/AppearanceSettingsPage.ets`
  // 全部为「开关型」或「字符串型」持久化，配合 AppStorage 实时联动。
  // ══════════════════════════════════════════════════════════════

  // ── 卡片沾色：开启后所有卡片底色混入 10% 主题色 ──
  static readonly KEY_CARD_TINT: string = 'card_tint';

  /** 卡片沾色是否开启（默认关闭） */
  static cardTintOn(): boolean {
    return DataStore.get(DataStore.KEY_CARD_TINT) === '1';
  }

  static setCardTint(on: boolean): void {
    DataStore.put(DataStore.KEY_CARD_TINT, on ? '1' : '0');
  }

  // ── 主题色流光：开启后按压沉浸光感卡片的流光/光晕改用主题色 ──
  static readonly KEY_PRESS_GLOW: string = 'immersive_press_glow';

  /** 主题色流光是否开启（默认开启，与参考项目一致） */
  static pressGlowOn(): boolean {
    return DataStore.get(DataStore.KEY_PRESS_GLOW) !== '0';
  }

  static setPressGlow(on: boolean): void {
    DataStore.put(DataStore.KEY_PRESS_GLOW, on ? '1' : '0');
  }

  // ── 卡片流光触感：关闭后按压卡片不再出现流光 ──
  static readonly KEY_CARD_GLOW_TOUCH: string = 'card_glow_touch';

  /** 卡片流光触感是否开启（默认开启） */
  static cardGlowTouchOn(): boolean {
    return DataStore.get(DataStore.KEY_CARD_GLOW_TOUCH) !== '0';
  }

  static setCardGlowTouch(on: boolean): void {
    DataStore.put(DataStore.KEY_CARD_GLOW_TOUCH, on ? '1' : '0');
  }

  // ── 高权限自定义主题色：开启后自定义 hex 也参与页面背景染色 ──
  static readonly KEY_CUSTOM_ACCENT_FULL: string = 'custom_accent_full';

  /** 高权限自定义主题色是否开启（默认关闭：仅内置主题色染背景） */
  static customAccentFullOn(): boolean {
    return DataStore.get(DataStore.KEY_CUSTOM_ACCENT_FULL) === '1';
  }

  static setCustomAccentFull(on: boolean): void {
    DataStore.put(DataStore.KEY_CUSTOM_ACCENT_FULL, on ? '1' : '0');
  }

  // ── 字体管理：字号 / 字重 / 中文族 / 英数族 / 已上传字体列表 ──
  static readonly KEY_FONT_MODE: string = 'font_mode';
  static readonly KEY_FONT_FAMILY_ZH: string = 'font_family_zh';
  static readonly KEY_FONT_FAMILY_EN: string = 'font_family_en';
  static readonly KEY_FONT_WEIGHT_MODE: string = 'font_weight_mode';
  static readonly KEY_FONT_WEIGHT_VALUE: string = 'font_weight_value';
  static readonly KEY_CUSTOM_FONTS: string = 'custom_fonts';
  /** 字号方案（follow=跟随系统 / custom=自定义）—— 移植自参考项目外观设置 */
  static readonly KEY_FONT_SIZE_MODE: string = 'font_size_mode';
  /** 自定义字号值（12~28，基准 16） */
  static readonly KEY_FONT_SIZE_VALUE: string = 'font_size_value';

  /** 保存字号方案（follow / custom） */
  static saveFontSizeMode(mode: string): void {
    DataStore.put(DataStore.KEY_FONT_SIZE_MODE, mode.length > 0 ? mode : 'follow');
  }

  /** 读取字号方案（默认 follow） */
  static fontSizeMode(): string {
    const v: string = DataStore.get(DataStore.KEY_FONT_SIZE_MODE);
    return v.length > 0 ? v : 'follow';
  }

  /** 保存自定义字号值（12~28 取整） */
  static saveFontSizeValue(v: number): void {
    DataStore.put(DataStore.KEY_FONT_SIZE_VALUE, `${Math.round(v)}`);
  }

  /** 读取自定义字号值（默认 16） */
  static fontSizeValue(): number {
    const v: number = Number.parseInt(DataStore.get(DataStore.KEY_FONT_SIZE_VALUE));
    if (isNaN(v) || v <= 0) {
      return 16;
    }
    return Math.max(12, Math.min(28, v));
  }

  /** 保存字体方案（preset=跟随系统 / zh-en=中英分设 / custom=自定义） */
  static saveFontMode(mode: string): void {
    DataStore.put(DataStore.KEY_FONT_MODE, mode.length > 0 ? mode : 'preset');
  }

  /** 读取字体方案（默认 preset） */
  static fontMode(): string {
    const v: string = DataStore.get(DataStore.KEY_FONT_MODE);
    return v.length > 0 ? v : 'preset';
  }

  /** 保存中文字体族（空串=跟随系统） */
  static saveFontFamilyZh(name: string): void {
    DataStore.put(DataStore.KEY_FONT_FAMILY_ZH, name);
  }

  /** 读取中文字体族（默认空串=跟随系统） */
  static fontFamilyZh(): string {
    return DataStore.get(DataStore.KEY_FONT_FAMILY_ZH);
  }

  /** 保存英数字体族（空串=跟随系统） */
  static saveFontFamilyEn(name: string): void {
    DataStore.put(DataStore.KEY_FONT_FAMILY_EN, name);
  }

  /** 读取英数字体族（默认空串=跟随系统） */
  static fontFamilyEn(): string {
    return DataStore.get(DataStore.KEY_FONT_FAMILY_EN);
  }

  /** 保存字重方案（follow/thin/light/regular/medium/bold） */
  static saveFontWeightMode(mode: string): void {
    DataStore.put(DataStore.KEY_FONT_WEIGHT_MODE, mode.length > 0 ? mode : 'follow');
  }

  /** 读取字重方案（默认 follow=跟随原本样式） */
  static fontWeightMode(): string {
    const v: string = DataStore.get(DataStore.KEY_FONT_WEIGHT_MODE);
    return v.length > 0 ? v : 'follow';
  }

  /** 保存自定义字重数值（100~900，非法值回落 400） */
  static saveFontWeightValue(v: number): void {
    const n: number = isNaN(v) ? 400 : Math.max(100, Math.min(900, Math.round(v)));
    DataStore.put(DataStore.KEY_FONT_WEIGHT_VALUE, `${n}`);
  }

  /** 读取自定义字重数值（默认 400） */
  static fontWeightValue(): number {
    const v: number = Number(DataStore.get(DataStore.KEY_FONT_WEIGHT_VALUE));
    return isNaN(v) || v <= 0 ? 400 : Math.max(100, Math.min(900, v));
  }

  /** 保存已上传字体列表（JSON 数组） */
  static saveCustomFonts(list: CustomFontItem[]): void {
    DataStore.put(DataStore.KEY_CUSTOM_FONTS, JSON.stringify(list));
  }

  /** 读取已上传字体列表（解析失败返回空数组） */
  static loadCustomFonts(): CustomFontItem[] {
    const out: CustomFontItem[] = [];
    const raw: string = DataStore.get(DataStore.KEY_CUSTOM_FONTS);
    if (raw.length === 0) {
      return out;
    }
    try {
      const arr: CustomFontItem[] = JSON.parse(raw) as CustomFontItem[];
      for (let i = 0; i < arr.length; i++) {
        const it: CustomFontItem = arr[i];
        if (it === null || it === undefined) {
          continue;
        }
        const fileName: string = it.fileName === undefined ? '' : it.fileName;
        if (fileName.length === 0) {
          continue;
        }
        const alias: string = it.alias === undefined ? '' : it.alias;
        const item: CustomFontItem = { alias: alias, fileName: fileName };
        out.push(item);
      }
    } catch (e) {
      return out;
    }
    return out;
  }
}
