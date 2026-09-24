/**
 * 外观设置存储与派生 —— 移植自参考项目 miha_hm（鸿米家）
 * 对应参考文件：
 *   - `utils/DesignTokens.ets`（主题色 / 卡片沾色 / 页面底色 等外观派生函数）
 *   - `pages/AppearanceSettingsPage.ets`（各设置项的语义与默认值）
 *   - `utils/CustomFonts.ets`（自定义字体装载 / 卸载）
 *
 * 职责：
 * 1) 新增外观开关统一「持久化(DataStore) + AppStorage 实时联动」读写，开关即时生效；
 * 2) 派生卡片与页面底色（卡片沾色 10% 主题色；高权限自定义主题色染页面背景）；
 * 3) 字体族 / 字重 / 字号 的统一出口（含自定义字体注册，供字体管理页使用）。
 *
 * 用法约定（ArkUI 依赖登记）：
 *   AppStorage 的读取必须写在**组件的属性表达式**里（或 @StorageProp/@StorageLink）才能登记依赖，
 *   因此本类同时提供「读取函数」（供纯逻辑/Builder 内部按需取用）与「设置函数」（写持久化 + AppStorage）。
 */
import { common } from '@kit.AbilityKit';
import { text } from '@kit.ArkGraphics2D';
import { uiAppearance } from '@kit.ArkUI';
import { CustomFontItem, DataStore } from './DataStore';
import { Theme } from './ThemeUtil';
import { AppState } from './AppState';

export class AppearanceStore {
  // ── AppStorage 键（页面用 @StorageLink / @StorageProp 与之一一对应）──
  /** 卡片沾色：卡片底色混入 10% 主题色 */
  static readonly KEY_CARD_TINT: string = 'cardTint';
  /** 主题色流光：按压沉浸光感卡片的流光/光晕改用主题色 */
  static readonly KEY_PRESS_GLOW: string = 'immersivePressGlow';
  /** 卡片流光触感：开启后按压卡片才出现流光 */
  static readonly KEY_CARD_GLOW_TOUCH: string = 'cardGlowTouch';
  /** 高权限自定义主题色：自定义 hex 也染页面背景 */
  static readonly KEY_CUSTOM_ACCENT_FULL: string = 'customAccentFull';
  /** 字体方案：preset（跟随系统）/ zh-en（中英分设）/ custom（自定义） */
  static readonly KEY_FONT_MODE: string = 'fontMode';
  /** 中文字体族（空串=跟随系统） */
  static readonly KEY_FONT_FAMILY_ZH: string = 'fontFamilyZh';
  /** 英数字体族（空串=跟随系统） */
  static readonly KEY_FONT_FAMILY_EN: string = 'fontFamilyEn';
  /** 字重方案：follow / thin / light / regular / medium / bold / custom */
  static readonly KEY_FONT_WEIGHT_MODE: string = 'fontWeightMode';
  /** 自定义字重数值（100~900） */
  static readonly KEY_FONT_WEIGHT_VALUE: string = 'fontWeightValue';
  /** 已上传字体别名列表（string[]，供管理页列表渲染） */
  static readonly KEY_CUSTOM_FONTS: string = 'customFonts';
  /** 主页页面平滑切换（页签切换时页面平滑滑动过渡）—— 移植自参考项目外观设置 */
  static readonly KEY_SMOOTH_PAGE: string = 'smoothPageSwitch';
  /** 字号方案：follow（跟随系统）/ custom（自定义）—— 移植自参考项目外观设置 */
  static readonly KEY_FONT_SIZE_MODE: string = 'fontSizeMode';
  /** 自定义字号值（12~28，基准 16） */
  static readonly KEY_FONT_SIZE_VALUE: string = 'fontSizeValue';
  /**
   * 广播键：卡片沾色底色（不透明 #RRGGBB；空串＝沾色关闭）。
   * 卡片组件必须用 @StorageProp 订阅此键来取沾色底色——
   * 参考项目 DesignTokens 的 CARD_SURFACE_KEY 同款机制。
   */
  static readonly KEY_BROADCAST_CARD_BG: string = 'cardTintBg';
  /**
   * 广播键：页面背景色（#RRGGBB）。
   * 页面根背景订阅此键（参考项目 DesignTokens 的 PAGE_BACKGROUND_KEY 同款机制）。
   */
  static readonly KEY_BROADCAST_PAGE_BG: string = 'pageBackground';

  // ── 派生参数 ──
  /** 卡片沾色比例（参考项目取值：10% 主题色） */
  static readonly CARD_TINT_RATIO: number = 0.10;
  /** 页面底色主题染色比例（内置主题色默认染色；自定义 hex 需高权限开关） */
  static readonly PAGE_TINT_RATIO: number = 0.10;

  /** 基准色（与 resources base/dark 的 bg_card、bg_page 保持一致，用于沾色混合） */
  private static readonly CARD_LIGHT: string = '#FFFFFF';
  private static readonly CARD_DARK: string = '#191D1C';
  private static readonly PAGE_LIGHT: string = '#F2F5F4';
  private static readonly PAGE_DARK: string = '#0C0F0E';

  /** 自定义字体目录名（应用沙箱 filesDir 下） */
  private static readonly FONT_DIR: string = 'custom_fonts';

  // ══════════════════════════════════════════════════════════════
  // 启动恢复
  // ══════════════════════════════════════════════════════════════

  /** 启动时调用一次：持久化 → AppStorage，并注册已上传字体（EntryAbility.onCreate） */
  static init(): void {
    AppStorage.setOrCreate(AppearanceStore.KEY_CARD_TINT, DataStore.cardTintOn());
    AppStorage.setOrCreate(AppearanceStore.KEY_SMOOTH_PAGE, DataStore.get('smooth_page_switch') !== '0');
    AppStorage.setOrCreate(AppearanceStore.KEY_PRESS_GLOW, DataStore.pressGlowOn());
    AppStorage.setOrCreate(AppearanceStore.KEY_CARD_GLOW_TOUCH, DataStore.cardGlowTouchOn());
    AppStorage.setOrCreate(AppearanceStore.KEY_CUSTOM_ACCENT_FULL, DataStore.customAccentFullOn());
    AppStorage.setOrCreate(AppearanceStore.KEY_FONT_MODE, DataStore.fontMode());
    AppStorage.setOrCreate(AppearanceStore.KEY_FONT_FAMILY_ZH, DataStore.fontFamilyZh());
    AppStorage.setOrCreate(AppearanceStore.KEY_FONT_FAMILY_EN, DataStore.fontFamilyEn());
    AppStorage.setOrCreate(AppearanceStore.KEY_FONT_WEIGHT_MODE, DataStore.fontWeightMode());
    AppStorage.setOrCreate(AppearanceStore.KEY_FONT_WEIGHT_VALUE, DataStore.fontWeightValue());
    AppStorage.setOrCreate(AppearanceStore.KEY_FONT_SIZE_MODE, DataStore.fontSizeMode());
    AppStorage.setOrCreate(AppearanceStore.KEY_FONT_SIZE_VALUE, DataStore.fontSizeValue());
    AppStorage.setOrCreate(AppearanceStore.KEY_CUSTOM_FONTS, AppearanceStore.customFontAliases());
    // 广播派生色（卡片沾色底色 / 页面背景）——订阅端见 MaterialCard / MainView / WallpaperFill
    AppearanceStore.broadcastDerived();
    AppearanceStore.registerCustomFonts();
  }

  // ══════════════════════════════════════════════════════════════
  // 开关：读取（供逻辑判断；组件属性表达式请用 @StorageProp/@StorageLink）
  // ══════════════════════════════════════════════════════════════

  /** 卡片沾色是否开启（默认关） */
  static cardTintOn(): boolean {
    return AppStorage.get<boolean>(AppearanceStore.KEY_CARD_TINT) === true;
  }

  /** 主页页面平滑切换开关（默认开启；'0' 时关闭，页签切换不带滑动过渡） */
  static smoothPageSwitchOn(): boolean {
    const v: boolean | undefined = AppStorage.get<boolean>(AppearanceStore.KEY_SMOOTH_PAGE);
    return v === undefined ? true : v;
  }

  static setSmoothPageSwitch(on: boolean): void {
    AppStorage.setOrCreate(AppearanceStore.KEY_SMOOTH_PAGE, on);
    DataStore.put('smooth_page_switch', on ? '1' : '0');
  }

  /** 主题色流光是否开启（默认开） */
  static pressGlowOn(): boolean {
    const v: boolean | undefined = AppStorage.get<boolean>(AppearanceStore.KEY_PRESS_GLOW);
    return v === undefined ? true : v;
  }

  /** 卡片流光触感是否开启（默认开） */
  static cardGlowTouchOn(): boolean {
    const v: boolean | undefined = AppStorage.get<boolean>(AppearanceStore.KEY_CARD_GLOW_TOUCH);
    return v === undefined ? true : v;
  }

  /** 高权限自定义主题色是否开启（默认关） */
  static customAccentFullOn(): boolean {
    return AppStorage.get<boolean>(AppearanceStore.KEY_CUSTOM_ACCENT_FULL) === true;
  }

  // ══════════════════════════════════════════════════════════════
  // 开关：写入（持久化 + AppStorage 双写，保证即时生效）
  // ══════════════════════════════════════════════════════════════

  static setCardTint(on: boolean): void {
    DataStore.setCardTint(on);
    AppStorage.setOrCreate(AppearanceStore.KEY_CARD_TINT, on);
    // 沾色底色/材质沾色层随开关重算并广播（卡片订阅广播键即时刷新）
    AppearanceStore.broadcastDerived();
  }

  static setPressGlow(on: boolean): void {
    DataStore.setPressGlow(on);
    AppStorage.setOrCreate(AppearanceStore.KEY_PRESS_GLOW, on);
  }

  static setCardGlowTouch(on: boolean): void {
    DataStore.setCardGlowTouch(on);
    AppStorage.setOrCreate(AppearanceStore.KEY_CARD_GLOW_TOUCH, on);
  }

  static setCustomAccentFull(on: boolean): void {
    DataStore.setCustomAccentFull(on);
    AppStorage.setOrCreate(AppearanceStore.KEY_CUSTOM_ACCENT_FULL, on);
    // 高权限开关影响自定义 hex 是否染页面背景 → 页面背景广播键重算
    AppearanceStore.broadcastDerived();
  }

  // ══════════════════════════════════════════════════════════════
  // 主题色派生
  // ══════════════════════════════════════════════════════════════

  /**
   * 重算并广播派生色（卡片沾色底色 + 页面背景）—— 对齐参考项目
   * miha_hm `DesignTokens.applyAppTheme()` 的广播键机制。
   *
   * 为什么需要广播：ArkUI 按**属性表达式**登记依赖，组件里的静态函数
   * （如 `GlassMaterial.homeCardBg()`）内部读 AppStorage 不会登记依赖，
   * 拨开关后已画出的卡片不会重算。组件用 @StorageProp 订阅广播键、
   * 本方法在开关/主题/深色变化时重写广播键，才能实现全站即时刷新。
   *
   * 触发时机：启动恢复(init) / 卡片沾色开关 / 高权限自定义主题色开关 /
   * 主题色切换(Theme.apply/restore) / 深色模式切换。
   */
  static broadcastDerived(): void {
    const dark: boolean = AppStorage.get<boolean>('isDarkMode') === true;
    const card: string = AppearanceStore.cardTintOn()
      ? AppearanceStore.cardBackground(dark, Theme.current())
      : '';
    AppStorage.setOrCreate(AppearanceStore.KEY_BROADCAST_CARD_BG, card);
    AppStorage.setOrCreate(AppearanceStore.KEY_BROADCAST_PAGE_BG,
      AppearanceStore.pageBackground(dark, Theme.current()));
  }

  /** 当前主题色 hex（内置五色或自定义 #RRGGBB） */
  static accentHex(): string {
    return Theme.colorOf(Theme.current());
  }

  /**
   * 当前主题色是否允许染「页面背景」：
   * - 内置主题色：始终允许；
   * - 自定义 hex：仅当「高权限自定义主题色」开启时允许（参考项目默认行为）。
   */
  static pageTintAllowed(themeKey: string): boolean {
    if (Theme.isBuiltin(themeKey)) {
      return true;
    }
    if (!Theme.isHex(themeKey)) {
      return false;
    }
    return AppearanceStore.customAccentFullOn();
  }

  /** 页面底色（开启主题染色时混入 PAGE_TINT_RATIO 比例主题色，否则原色） */
  static pageBackground(isDark: boolean, themeKey: string): string {
    const base: string = isDark ? AppearanceStore.PAGE_DARK : AppearanceStore.PAGE_LIGHT;
    // 「背景跟随主题色」关闭：页面底色保持中性，不再混入主题色
    // （用户反馈：沉浸光感开启后绿底/红底不好看，需要可取消的取色）
    if (AppStorage.get<boolean>(AppearanceStore.KEY_PAGE_BG_TINT) === false) {
      return base;
    }
    if (!AppearanceStore.pageTintAllowed(themeKey)) {
      return base;
    }
    return AppearanceStore.mix(base, Theme.colorOf(themeKey), AppearanceStore.PAGE_TINT_RATIO);
  }

  /** AppStorage 键：页面背景是否混入主题色（true=默认取色；false=中性底色） */
  static readonly KEY_PAGE_BG_TINT: string = 'pageBgTint';
  /** AppStorage 键：卡片降级样式（mica=云母磨砂玻璃 / solid=实色纯底），默认 mica */
  static readonly KEY_CARD_FALLBACK: string = 'cardFallback';

  /** 当前是否「云母」降级（默认 true；'solid'=实色纯底）。
   *  tick 仅作响应式依赖载体：静态读值不触发重渲染，调用方必须传自己的订阅值，
   *  切换样式时 setCardFallback 自增 cardFallbackTick 广播，卡片才会重算底色。 */
  static cardFallbackMica(tick: number): boolean {
    return AppStorage.get<string>(AppearanceStore.KEY_CARD_FALLBACK) !== 'solid';
  }

  /** 切换卡片降级样式（写 AppStorage + 持久化 + 自增 tick 广播全站卡片重渲染） */
  static setCardFallback(mode: string): void {
    AppStorage.setOrCreate(AppearanceStore.KEY_CARD_FALLBACK, mode);
    DataStore.saveCardFallback(mode);
    const t: number = AppStorage.get<number>('cardFallbackTick') ?? 0;
    AppStorage.setOrCreate('cardFallbackTick', t + 1);
  }

  /** 启动恢复卡片降级样式（EntryAbility 调用；缺省 mica） */
  static loadCardFallback(): void {
    const v: string = DataStore.loadCardFallback();
    AppStorage.setOrCreate(AppearanceStore.KEY_CARD_FALLBACK, v.length > 0 ? v : 'mica');
  }

  /** 切换「背景跟随主题色」（写 AppStorage + 持久化 + 重新广播派生底色） */
  static setPageBgTint(on: boolean): void {
    AppStorage.setOrCreate(AppearanceStore.KEY_PAGE_BG_TINT, on);
    DataStore.savePageBgTint(on);
    AppearanceStore.broadcastDerived();
  }

  /** 启动恢复「背景跟随主题色」（EntryAbility 调用；缺省 true = 默认取色） */
  static loadPageBgTint(): void {
    AppStorage.setOrCreate(AppearanceStore.KEY_PAGE_BG_TINT, DataStore.loadPageBgTint());
  }

  /** 卡片底色（开启卡片沾色时混入 CARD_TINT_RATIO 比例主题色，否则原色） */
  static cardBackground(isDark: boolean, themeKey: string): string {
    const base: string = isDark ? AppearanceStore.CARD_DARK : AppearanceStore.CARD_LIGHT;
    if (!AppearanceStore.cardTintOn()) {
      return base;
    }
    return AppearanceStore.mix(base, Theme.colorOf(themeKey), AppearanceStore.CARD_TINT_RATIO);
  }

  /**
   * 卡片沾色「叠加层」颜色：材质渲染时卡片底色会让出（透明），
   * 此时沾色需作为独立一层压在材质之上才能看见（参考项目做法）。
   */
  static cardTintLayer(themeKey: string): string {
    return Theme.rgba(Theme.colorOf(themeKey), AppearanceStore.CARD_TINT_RATIO);
  }

  // ══════════════════════════════════════════════════════════════
  // 字重 / 字体族
  // ══════════════════════════════════════════════════════════════

  /** 字重方案（默认 follow=不改动原样式） */
  static fontWeightMode(): string {
    const v: string | undefined = AppStorage.get<string>(AppearanceStore.KEY_FONT_WEIGHT_MODE);
    return v === undefined || v.length === 0 ? 'follow' : v;
  }

  /** 自定义字重数值（100~900） */
  static fontWeightValue(): number {
    const v: number | undefined = AppStorage.get<number>(AppearanceStore.KEY_FONT_WEIGHT_VALUE);
    if (v === undefined || isNaN(v) || v <= 0) {
      return 400;
    }
    return Math.max(100, Math.min(900, v));
  }

  /** 字重是否被外观设置覆盖 */
  static fontWeightOverridden(): boolean {
    return AppearanceStore.fontWeightMode() !== 'follow';
  }

  /**
   * 全局字重取值（返回数值字重 100~900）：未被覆盖时返回调用方原本的默认字重（=不改变原样式）。
   * 用法：`.fontWeight(AppearanceStore.fontWeight(700))`（可传 `FontWeight.Bold` 等枚举，数值枚举可赋给 number）
   */
  static fontWeight(defaultWeight: number): number {
    const mode: string = AppearanceStore.fontWeightMode();
    if (mode === 'follow') {
      return defaultWeight;
    }
    if (mode === 'thin') {
      return 200;
    }
    if (mode === 'light') {
      return 300;
    }
    if (mode === 'regular') {
      return 400;
    }
    if (mode === 'medium') {
      return 500;
    }
    if (mode === 'bold') {
      return 700;
    }
    return AppearanceStore.fontWeightValue();
  }

  /** 中文字体族（空串=跟随系统） */
  static fontFamilyZh(): string {
    const v: string | undefined = AppStorage.get<string>(AppearanceStore.KEY_FONT_FAMILY_ZH);
    return v === undefined ? '' : v;
  }

  /** 英数字体族（空串=跟随系统） */
  static fontFamilyEn(): string {
    const v: string | undefined = AppStorage.get<string>(AppearanceStore.KEY_FONT_FAMILY_EN);
    return v === undefined ? '' : v;
  }

  /**
   * 按内容选择字体族：含中文（CJK）用中文字体族，否则用英数字体族；
   * 返回空串表示不设置 fontFamily（跟随系统默认）。
   */
  static fontFamilyFor(content: string): string {
    if (AppearanceStore.hasCjk(content)) {
      return AppearanceStore.fontFamilyZh();
    }
    return AppearanceStore.fontFamilyEn();
  }

  /** 文本是否含中文（CJK 统一汉字区 0x4E00~0x9FFF） */
  static hasCjk(content: string): boolean {
    for (let i = 0; i < content.length; i++) {
      const c: number = content.charCodeAt(i);
      if (c >= 0x4E00 && c <= 0x9FFF) {
        return true;
      }
    }
    return false;
  }

  // ══════════════════════════════════════════════════════════════
  // 字体设置写入
  // ══════════════════════════════════════════════════════════════

  static setFontMode(mode: string): void {
    DataStore.saveFontMode(mode);
    AppStorage.setOrCreate(AppearanceStore.KEY_FONT_MODE, DataStore.fontMode());
  }

  static setFontFamilyZh(name: string): void {
    DataStore.saveFontFamilyZh(name);
    AppStorage.setOrCreate(AppearanceStore.KEY_FONT_FAMILY_ZH, name);
  }

  static setFontFamilyEn(name: string): void {
    DataStore.saveFontFamilyEn(name);
    AppStorage.setOrCreate(AppearanceStore.KEY_FONT_FAMILY_EN, name);
  }

  static setFontWeightMode(mode: string): void {
    DataStore.saveFontWeightMode(mode);
    AppStorage.setOrCreate(AppearanceStore.KEY_FONT_WEIGHT_MODE, DataStore.fontWeightMode());
  }

  static setFontWeightValue(v: number): void {
    DataStore.saveFontWeightValue(v);
    AppStorage.setOrCreate(AppearanceStore.KEY_FONT_WEIGHT_VALUE, DataStore.fontWeightValue());
  }

  // ══════════════════════════════════════════════════════════════
  // 字号（跟随系统 / 自定义缩放）—— 移植自参考项目外观设置
  // ══════════════════════════════════════════════════════════════

  /** 字号方案（follow=跟随系统 / custom=自定义） */
  static fontSizeMode(): string {
    const v: string | undefined = AppStorage.get<string>(AppearanceStore.KEY_FONT_SIZE_MODE);
    return v === undefined || v.length === 0 ? 'follow' : v;
  }

  /** 自定义字号值（12~28，基准 16，默认 16） */
  static fontSizeValue(): number {
    const v: number | undefined = AppStorage.get<number>(AppearanceStore.KEY_FONT_SIZE_VALUE);
    if (v === undefined || isNaN(v) || v <= 0) {
      return 16;
    }
    return Math.max(12, Math.min(28, v));
  }

  static setFontSizeMode(mode: string): void {
    DataStore.saveFontSizeMode(mode);
    AppStorage.setOrCreate(AppearanceStore.KEY_FONT_SIZE_MODE, DataStore.fontSizeMode());
  }

  static setFontSizeValue(v: number): void {
    DataStore.saveFontSizeValue(v);
    AppStorage.setOrCreate(AppearanceStore.KEY_FONT_SIZE_VALUE, DataStore.fontSizeValue());
  }

  /**
   * 应用字号缩放到全局（自定义 = 字号值/16；跟随系统 = 还原系统缩放）。
   * 参考项目同款：appContext.setFontSizeScale(scale)，应用级即时生效。
   */
  static applyFontSizeScale(): void {
    try {
      const ctx: common.Context | null = AppState.context;
      if (ctx === null) {
        return;
      }
      let scale: number = 1;
      if (AppearanceStore.fontSizeMode() === 'custom') {
        scale = AppearanceStore.fontSizeValue() / 16;
      } else {
        scale = uiAppearance.getFontScale();
      }
      ctx.getApplicationContext().setFontSizeScale(scale);
    } catch (e) {
      // 系统不支持或上下文未就绪时静默
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 自定义字体（上传 / 注册 / 删除）
  // ══════════════════════════════════════════════════════════════

  /** 自定义字体目录绝对路径（context 未就绪时返回空串） */
  static fontDir(): string {
    const ctx: common.Context | null = AppState.context;
    if (ctx === null) {
      return '';
    }
    return `${ctx.filesDir}/${AppearanceStore.FONT_DIR}`;
  }

  /** 文件名 → 字体别名（去掉扩展名，作为注册到系统字体库的名称） */
  static aliasOf(fileName: string): string {
    const dot: number = fileName.lastIndexOf('.');
    return dot > 0 ? fileName.substring(0, dot) : fileName;
  }

  /** 已上传字体的别名列表（AppStorage 用） */
  static customFontAliases(): string[] {
    const list: CustomFontItem[] = DataStore.loadCustomFonts();
    const out: string[] = [];
    for (let i = 0; i < list.length; i++) {
      const it: CustomFontItem = list[i];
      if (it !== null && it !== undefined && it.alias.length > 0) {
        out.push(it.alias);
      }
    }
    return out;
  }

  /** 已上传字体条目列表（管理页用） */
  static customFontItems(): CustomFontItem[] {
    return DataStore.loadCustomFonts();
  }

  /** 把已上传字体全部注册到系统字体库；返回注册成功数量 */
  static registerCustomFonts(): number {
    const dir: string = AppearanceStore.fontDir();
    if (dir.length === 0) {
      return 0;
    }
    const list: CustomFontItem[] = DataStore.loadCustomFonts();
    let ok: number = 0;
    for (let i = 0; i < list.length; i++) {
      const it: CustomFontItem = list[i];
      if (it === null || it === undefined || it.alias.length === 0) {
        continue;
      }
      if (AppearanceStore.loadOneFont(it.alias, `${dir}/${it.fileName}`)) {
        ok++;
      }
    }
    return ok;
  }

  /**
   * 注册单个字体文件（不抛异常）。
   * 使用 loadFontSyncWithCheck：已注册同名别名时不会重复加载。
   */
  static loadOneFont(alias: string, absPath: string): boolean {
    try {
      text.FontCollection.getGlobalInstance().loadFontSyncWithCheck(alias, `file://${absPath}`);
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 注销字体别名（删除字体时调用；失败静默） */
  static unregisterFont(alias: string): void {
    try {
      text.FontCollection.getGlobalInstance().unloadFontSync(alias);
    } catch (e) {
      // 未注册或系统不支持时忽略
    }
  }

  /** 追加一条自定义字体记录并注册，返回是否成功 */
  static addCustomFont(fileName: string): boolean {
    const dir: string = AppearanceStore.fontDir();
    if (dir.length === 0 || fileName.length === 0) {
      return false;
    }
    const alias: string = AppearanceStore.aliasOf(fileName);
    if (alias.length === 0) {
      return false;
    }
    const list: CustomFontItem[] = DataStore.loadCustomFonts();
    // 同别名去重（重新上传视为替换，仍沿用同名注册）
    for (let i = 0; i < list.length; i++) {
      const it: CustomFontItem = list[i];
      if (it.alias === alias) {
        AppearanceStore.loadOneFont(alias, `${dir}/${fileName}`);
        AppearanceStore.syncFontAliases();
        return true;
      }
    }
    const item: CustomFontItem = { alias: alias, fileName: fileName };
    list.push(item);
    DataStore.saveCustomFonts(list);
    AppearanceStore.loadOneFont(alias, `${dir}/${fileName}`);
    AppearanceStore.syncFontAliases();
    return true;
  }

  /** 删除一条自定义字体记录并注销（文件由调用方删除） */
  static removeCustomFont(alias: string): void {
    const list: CustomFontItem[] = DataStore.loadCustomFonts();
    const keep: CustomFontItem[] = [];
    for (let i = 0; i < list.length; i++) {
      const it: CustomFontItem = list[i];
      if (it.alias !== alias) {
        keep.push(it);
      }
    }
    DataStore.saveCustomFonts(keep);
    AppearanceStore.unregisterFont(alias);
    // 被删字体若正在使用则回退到跟随系统，避免字体失效
    if (AppearanceStore.fontFamilyZh() === alias) {
      AppearanceStore.setFontFamilyZh('');
    }
    if (AppearanceStore.fontFamilyEn() === alias) {
      AppearanceStore.setFontFamilyEn('');
    }
    AppearanceStore.syncFontAliases();
  }

  /** 同步字体别名列表到 AppStorage（管理页列表实时刷新） */
  static syncFontAliases(): void {
    AppStorage.setOrCreate(AppearanceStore.KEY_CUSTOM_FONTS, AppearanceStore.customFontAliases());
  }

  /**
   * 系统可用字体全名列表（「选择系统字体族」落选用）。
   * 失败时返回空数组（调用方提示"系统未提供可枚举字体"）。
   */
  static async systemFontNames(): Promise<string[]> {
    try {
      const names: string[] = await text.getSystemFontFullNamesByType(text.SystemFontType.ALL);
      return names;
    } catch (e) {
      return [];
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 颜色工具
  // ══════════════════════════════════════════════════════════════

  /** #RRGGBB → 分量数组 [r,g,b]；非法值返回 [-1,-1,-1] */
  private static parseHex(hex: string): number[] {
    if (!/^#([0-9a-fA-F]{6})$/.test(hex)) {
      return [-1, -1, -1];
    }
    const r: number = parseInt(hex.substring(1, 3), 16);
    const g: number = parseInt(hex.substring(3, 5), 16);
    const b: number = parseInt(hex.substring(5, 7), 16);
    return [r, g, b];
  }

  /** 混合两色（base 占比 1-ratio，accent 占比 ratio），返回 #RRGGBB */
  private static mix(base: string, accent: string, ratio: number): string {
    const b: number[] = AppearanceStore.parseHex(base);
    const a: number[] = AppearanceStore.parseHex(accent);
    if (b[0] < 0) {
      return base;
    }
    if (a[0] < 0) {
      return base;
    }
    const k: number = Math.max(0, Math.min(1, ratio));
    const r: number = Math.round(b[0] * (1 - k) + a[0] * k);
    const g: number = Math.round(b[1] * (1 - k) + a[1] * k);
    const bl: number = Math.round(b[2] * (1 - k) + a[2] * k);
    return `#${AppearanceStore.hex2(r)}${AppearanceStore.hex2(g)}${AppearanceStore.hex2(bl)}`;
  }

  /** 0~255 → 两位十六进制 */
  private static hex2(v: number): string {
    const n: number = Math.max(0, Math.min(255, Math.round(v)));
    return n.toString(16).padStart(2, '0').toUpperCase();
  }
}
