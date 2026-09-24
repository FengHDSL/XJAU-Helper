import { uiMaterial } from '@kit.ArkUI';
import { AppearanceStore } from './AppearanceStore';
import { DataStore } from './DataStore';
import { Theme } from './ThemeUtil';
import { WallpaperTone } from './WallpaperTone';

/**
 * 玻璃质感（GlassMaterial）—— 全应用统一的按钮与卡片材质
 *
 * 通透程度（外观设置页滑条 0~100，越高越通透）：
 *   - 高：底色更透明、磨砂更轻（透出壁纸，观感清透）
 *   - 低：底色更白、磨砂更强（偏白偏模糊，文字可读性优先）
 *   - 亮边（1vp）与微阴影恒定，不随滑条变化
 *
 * 次要文字颜色覆盖（灰/白/黑/自定义）：
 *   graySecondary(默认色) / grayTertiary(默认色) —— 未覆盖时返回传入的默认色。
 *
 * 卡片沾色（移植自参考项目 miha_hm「卡片沾色」）：
 *   cardBg / homeCardBg 在开关开启时把卡片底色替换为
 *   `AppearanceStore.cardBackground()` = 基准卡片色混入 10% 主题色；
 *   开关默认关闭 → 与原行为完全一致。
 *   对应参考文件：miha_hm `utils/DesignTokens.ets`（卡片底/沾色派生）
 */
export class GlassMaterial {
  /** 细亮边颜色（1vp） */
  static readonly BORDER: string = 'rgba(255,255,255,0.28)';
  /** 微阴影颜色（radius 6 / offsetY 1） */
  static readonly SHADOW: string = 'rgba(0,0,0,0.10)';
  /** 玻璃卡片圆角 */
  static readonly CARD_RADIUS: number = 16;

  // ── 通透程度滑条 ──
  /** AppStorage 键：通透程度（0~100，默认 70；越高越通透，越低越白越模糊） */
  static readonly KEY_STRENGTH: string = 'glassStrength';
  /** AppStorage 键：玻璃档位（兼容保留，由通透程度推导） */
  static readonly KEY_LEVEL: string = 'glassLevel';
  static readonly LEVEL_WEAK: string = 'weak';
  static readonly LEVEL_MID: string = 'mid';
  static readonly LEVEL_STRONG: string = 'strong';

  /** 当前通透程度（0~100，异常兜底 70） */
  static strength(): number {
    const v: number | undefined = AppStorage.get<number>(GlassMaterial.KEY_STRENGTH);
    if (v === undefined || isNaN(v)) {
      return 70;
    }
    return Math.max(0, Math.min(100, v));
  }

  /** 通透程度 → 0~1 系数 */
  private static k(): number {
    return GlassMaterial.strength() / 100;
  }

  /** 兼容保留：档位由通透程度推导（<33 弱=最白最糊 / <66 中 / 其余强=最通透） */
  static level(): string {
    const s: number = GlassMaterial.strength();
    if (s < 33) {
      return GlassMaterial.LEVEL_WEAK;
    }
    if (s < 66) {
      return GlassMaterial.LEVEL_MID;
    }
    return GlassMaterial.LEVEL_STRONG;
  }

  /** 兼容保留：档位文案 */
  static levelText(lv: string): string {
    if (lv === GlassMaterial.LEVEL_WEAK) {
      return '弱';
    }
    if (lv === GlassMaterial.LEVEL_MID) {
      return '中';
    }
    return '强';
  }

  /** 玻璃底透明色（按钮/胶囊；越高越通透） */
  static surface(isDark: boolean): string {
    const k: number = GlassMaterial.k();
    const light: number = 0.24 - 0.14 * k;
    const dark: number = 0.16 - 0.11 * k;
    return isDark ? `rgba(255,255,255,${dark.toFixed(3)})` : `rgba(255,255,255,${light.toFixed(3)})`;
  }

  /** 卡片底透明色（越高越通透：浅色 0.80→0.45 / 深色 0.14→0.04） */
  static cardSurface(isDark: boolean): string {
    const k: number = GlassMaterial.k();
    const light: number = 0.80 - 0.35 * k;
    const dark: number = 0.14 - 0.10 * k;
    return isDark ? `rgba(255,255,255,${dark.toFixed(3)})` : `rgba(255,255,255,${light.toFixed(3)})`;
  }

  /** 细亮边宽度（恒定 1vp，不随通透程度变化） */
  static borderWidth(): number {
    return 1;
  }

  /** 细亮边颜色 */
  static borderColor(): string {
    return GlassMaterial.BORDER;
  }

  /** 胶囊阴影（恒定微阴影） */
  static capsuleShadow(): ShadowOptions {
    return { radius: 6, color: GlassMaterial.SHADOW, offsetX: 0, offsetY: 1 };
  }

  /** 卡片是否启用磨砂（沉浸光感开启即启用） */
  static blurOn(immersive: boolean): boolean {
    return immersive;
  }

  /**
   * 背景模糊样式：**越通透磨砂越轻，越低磨砂越强**（与"通透程度"语义一致）
   * （本 SDK UI BlurStyle 无 ULTRA 系列，最低为 Thin；immersive=false 时 NONE）
   */
  static bgBlur(immersive: boolean): BlurStyle {
    if (!immersive) {
      return BlurStyle.NONE;
    }
    const k: number = GlassMaterial.k();
    if (k < 0.25) {
      return BlurStyle.Thick;
    }
    if (k < 0.5) {
      return BlurStyle.Regular;
    }
    return BlurStyle.Thin;
  }

  /** 背景模糊缩放：与顶栏按钮一致，不做缩放（1.0） */
  static blurScale(): number {
    return 1.0;
  }

  /** 背景模糊选项（折射缩放） */
  static blurOptions(): BackgroundBlurStyleOptions {
    return { scale: GlassMaterial.blurScale() };
  }

  /**
   * 卡片磨砂：**仅由「卡片材质」开关控制**（不再受「沉浸光感」开关影响，避免只开卡片材质时看不到玻璃）。
   * 通透程度只影响底色透明度与亮边/阴影，磨砂保持一致以保证开关联动明显。
   */
  static cardBlur(): BlurStyle {
    if (AppStorage.get<boolean>('cardMaterial') !== true || GlassMaterial.lightOn()) {
      return BlurStyle.NONE;
    }
    return BlurStyle.Thin;
  }

  /**
   * 卡片磨砂（不依赖「沉浸光感」开关）：卡片材质开启即磨砂，关闭即无。
   * 用于含自定义组件（无法挂系统材质）的页面卡片，保证开关联动明显。
   * 光感生效时同样让出（NONE）——磨砂叠在沉浸材质上会发灰。
   */
  static cardBlurSolid(): BlurStyle {
    if (AppStorage.get<boolean>('cardMaterial') !== true || GlassMaterial.lightOn()) {
      return BlurStyle.NONE;
    }
    return BlurStyle.Thin;
  }

  /** 卡片亮边宽度：卡片材质开启时恒 1vp，否则无边框 */
  static cardBorderWidth(): number {
    if (AppStorage.get<boolean>('cardMaterial') !== true || GlassMaterial.lightOn()) {
      return 0;
    }
    return GlassMaterial.borderWidth();
  }

  /** 卡片阴影：卡片材质开启时恒微阴影，否则无；光感时让出（材质自带视觉，叠加会发灰） */
  static cardShadowStyle(): ShadowOptions {
    if (AppStorage.get<boolean>('cardMaterial') !== true || GlassMaterial.lightOn()) {
      return { radius: 0, color: 'rgba(0,0,0,0)', offsetX: 0, offsetY: 0 };
    }
    return GlassMaterial.capsuleShadow();
  }

  // ── 系统沉浸材质（ImmersiveMaterial）：卡片/子块/按钮统一由系统渲染玻璃 ──
  /** 支持检测缓存：-1 未检测 / 0 不支持 / 1 支持（API<26 设备调用可能抛错，必须保护） */
  private static matState: number = -1;

  /** 是否启用系统材质（「卡片材质」开关开启 且 设备支持） */
  static sysMaterialOn(): boolean {
    if (AppStorage.get<boolean>('cardMaterial') !== true) {
      return false;
    }
    return GlassMaterial.immSupported();
  }

  /**
   * 兼容保留：恒返回 undefined（历史调用残留约 38 处，不产生任何效果）。
   * 实测结论：系统材质渲染时会优先并忽略 backgroundColor/blur/shadow/border，导致自绘玻璃失效——
   * 因此全应用玻璃观感统一由自绘组合实现，本方法仅为编译兼容保留，勿在新代码中调用。
   */
  static sysMaterial(): uiMaterial.Material | undefined {
    return undefined;
  }

  /** 设备是否支持系统沉浸材质（惰性检测，matState：-1 未检测 / 0 否 / 1 是） */
  static immSupported(): boolean {
    if (GlassMaterial.matState < 0) {
      let ok: boolean = false;
      try {
        ok = uiMaterial.isImmersiveMaterialSupported();
      } catch (e) {
        ok = false;
      }
      GlassMaterial.matState = ok ? 1 : 0;
    }
    return GlassMaterial.matState === 1;
  }

  /**
   * 首页同款卡片底色：系统材质启用时**透明**（真让材质渲染，观感与首页一致）；
   * 未开启开关或设备不支持时返回原卡片色兜底（避免卡片消失）。
   * **卡片沾色**：开启后返回「基准卡片色混入 10% 主题色」（默认关闭 → 与原行为一致）。
   */
  static homeCardBg(orig: ResourceColor): ResourceColor {
    const tintOn: boolean = AppearanceStore.cardTintOn();
    const dark: boolean = AppStorage.get<boolean>('isDarkMode') === true;
    if (GlassMaterial.lightOn() || (AppStorage.get<boolean>('cardMaterial') === true && GlassMaterial.immSupported())) {
      // 材质生效：通常让出底色；但开启沾色时保留沾色底——材质为半透明，
      // 会透出其下方（同一节点 backgroundColor）的主题色，从而呈现"沾色"观感。
      return tintOn ? AppearanceStore.cardBackground(dark, Theme.current()) : Color.Transparent;
    }
    return tintOn ? AppearanceStore.cardBackground(dark, Theme.current()) : orig;
  }

  /**
   * **强制版**卡片底色：恒透明（不受「卡片材质」开关影响，设备不支持时兜底原色）。
   * 用于必须恒定显示玻璃的元素（课程表时间条/日期条）。
   */
  static homeCardBgForce(orig: ResourceColor): ResourceColor {
    if (GlassMaterial.immSupported()) {
      return Color.Transparent;
    }
    return orig;
  }

  /**
   * **强制版**系统沉浸材质：不检查「卡片材质」开关（设备支持即启用），供恒定玻璃元素使用。
   */
  static immersiveForce(): uiMaterial.Material | undefined {
    if (!GlassMaterial.immSupported()) {
      return undefined;
    }
    try {
      const k: number = GlassMaterial.k();
      let style: uiMaterial.ImmersiveStyle = uiMaterial.ImmersiveStyle.REGULAR;
      if (k >= 0.75) {
        style = uiMaterial.ImmersiveStyle.ULTRA_THIN;
      } else if (k >= 0.5) {
        style = uiMaterial.ImmersiveStyle.THIN;
      } else if (k < 0.25) {
        style = uiMaterial.ImmersiveStyle.THICK;
      }
      const opts: uiMaterial.ImmersiveOptions = {
        style: style,
        applyShadow: true
      };
      return new uiMaterial.ImmersiveMaterial(opts);
    } catch (e) {
      return undefined;
    }
  }

  /** 兼容保留：恒返回传入色（历史调用） */
  static withMaterial(orig: ResourceColor): ResourceColor {
    return orig;
  }

  /**
   * 卡片底色：开关关闭=原卡片色；开启=玻璃底（透明度随通透程度）；光感=透明让出。
   * **卡片沾色**（移植自参考项目）：开启后卡片底色替换为「基准卡片色混入 10% 主题色」，
   * 对全应用所有走本方法的卡片生效（默认关闭 → 与原行为完全一致）。
   */
  static cardBg(orig: ResourceColor, isDark: boolean): ResourceColor {
    if (AppearanceStore.cardTintOn()) {
      return AppearanceStore.cardBackground(isDark, Theme.current());
    }
    if (AppStorage.get<boolean>('cardMaterial') !== true || GlassMaterial.lightOn()) {
      return orig;
    }
    return GlassMaterial.cardSurface(isDark);
  }

  /**
   * 系统沉浸材质（模糊程度随通透程度反转：通透=轻材质 ULTRA_THIN/THIN，低通透=厚材质 REGULAR/THICK）。
   * 启用条件：卡片材质开关开启 且 设备支持；否则 undefined（不设置该属性，回落自绘玻璃）。
   */
  static immersive(): uiMaterial.Material | undefined {
    if (AppStorage.get<boolean>('cardMaterial') !== true) {
      return undefined;
    }
    if (!GlassMaterial.immSupported()) {
      return undefined;
    }
    try {
      const k: number = GlassMaterial.k();
      let style: uiMaterial.ImmersiveStyle = uiMaterial.ImmersiveStyle.REGULAR;
      if (k >= 0.75) {
        style = uiMaterial.ImmersiveStyle.ULTRA_THIN;
      } else if (k >= 0.5) {
        style = uiMaterial.ImmersiveStyle.THIN;
      } else if (k < 0.25) {
        style = uiMaterial.ImmersiveStyle.THICK;
      }
      const opts: uiMaterial.ImmersiveOptions = {
        style: style,
        applyShadow: true
      };
      return new uiMaterial.ImmersiveMaterial(opts);
    } catch (e) {
      return undefined;
    }
  }

  // ── 材质风格：'mica'（云母，旧版自绘玻璃） / 'light'（光感，Toggle 承载系统沉浸材质）──
  static readonly KEY_MATERIAL_STYLE: string = 'materialStyle';
  static readonly STYLE_MICA: string = 'mica';
  static readonly STYLE_LIGHT: string = 'light';

  /** 当前材质风格（默认 mica） */
  static materialStyle(): string {
    const v: string | undefined = AppStorage.get<string>(GlassMaterial.KEY_MATERIAL_STYLE);
    return v === GlassMaterial.STYLE_LIGHT ? GlassMaterial.STYLE_LIGHT : GlassMaterial.STYLE_MICA;
  }

  /** 光感模式是否启用（材质风格=光感 且 卡片材质开 且 设备支持系统材质） */
  static lightOn(): boolean {
    return GlassMaterial.materialStyle() === GlassMaterial.STYLE_LIGHT
      && AppStorage.get<boolean>('cardMaterial') === true
      && GlassMaterial.immSupported();
  }

  /**
   * 静态沉浸材质（光感用，配 Toggle 承载层）。
   * README 实测：材质必须静态（只传 style）——ImmersiveMaterial({interactive:true, lightEffect:{}}) 组合完全不渲染。
   */
  static lightMaterial(): uiMaterial.Material | undefined {
    if (!GlassMaterial.lightOn()) {
      return undefined;
    }
    try {
      const k: number = GlassMaterial.k();
      let style: uiMaterial.ImmersiveStyle = uiMaterial.ImmersiveStyle.REGULAR;
      if (k >= 0.75) {
        style = uiMaterial.ImmersiveStyle.ULTRA_THIN;
      } else if (k >= 0.5) {
        style = uiMaterial.ImmersiveStyle.THIN;
      } else if (k < 0.25) {
        style = uiMaterial.ImmersiveStyle.THICK;
      }
      const opts: uiMaterial.ImmersiveOptions = {
        style: style,
        applyShadow: false
      };
      return new uiMaterial.ImmersiveMaterial(opts);
    } catch (e) {
      return undefined;
    }
  }

  /** 底色（光感时组件让出底色——材质样式优先级高于背景色，实底会盖住光感） */
  static cardBgEx(orig: ResourceColor, isDark: boolean): ResourceColor {
    if (GlassMaterial.lightOn()) {
      return Color.Transparent;
    }
    return GlassMaterial.cardBg(orig, isDark);
  }

  /** 磨砂（光感时关闭——BlurStyle 层级同样在材质之上，会让光感发灰） */
  static blurEx(orig: BlurStyle): BlurStyle {
    if (GlassMaterial.lightOn()) {
      return BlurStyle.NONE;
    }
    return orig;
  }

  /** 亮边宽度（光感时去掉，材质自带视觉） */
  static borderEx(orig: number): number {
    if (GlassMaterial.lightOn()) {
      return 0;
    }
    return orig;
  }

  /** 阴影（光感时去掉） */
  static shadowEx(orig: ShadowOptions): ShadowOptions {
    if (GlassMaterial.lightOn()) {
      return { radius: 0, color: 'rgba(0,0,0,0)', offsetX: 0, offsetY: 0 };
    }
    return orig;
  }

  // ── 次要文字颜色覆盖（灰/白/黑/自定义/每页单独）：外观设置页可调，提升壁纸上的可读性 ──
  /** AppStorage 键：灰字模式（default=默认灰 / white=白 / black=黑 / custom=自定义） */
  static readonly KEY_GRAY_MODE: string = 'grayTextMode';
  /** AppStorage 键：自定义灰字颜色（rrggbb 或 #rrggbb） */
  static readonly KEY_GRAY_CUSTOM: string = 'grayTextColor';
  /**
   * 广播键：灰字刷新计数器。含灰字调用的页面必须 @StorageProp 订阅此键并在根容器
   * 属性表达式里引用（登记依赖）——静态函数 graySecondary/grayTertiary 内部读
   * AppStorage 不登记依赖（实证），不订阅则拨开关后已画出的文本不会重算。
   *
   * ⚠️ **订阅侧必须写字面量 `@StorageProp('grayTick')`，不能写 `@StorageProp(GlassMaterial.KEY_GRAY_TICK)`**：
   * ArkUI 状态管理在编译期解析装饰器参数，传类静态字段无法登记订阅（2026-09-24 实测：
   * 13 处如此写 → 灰字颜色不实时刷新，而用字面量键的主题色/副标题一直正常）。本常量仅供运行期读写使用。
   */
  static readonly KEY_GRAY_TICK: string = 'grayTick';
  /** 广播键：当前生效的全局覆盖色（''＝不覆盖；grayOverride 缓存读取，由 broadcastGray 维护） */
  static readonly KEY_GRAY_EFFECTIVE: string = 'grayEffectiveColor';
  /** AppStorage 键：当前活动页面 key（每页单独灰字色的生效上下文；''＝无页面上下文） */
  static readonly KEY_GRAY_PAGE_ACTIVE: string = 'grayActivePage';
  /** AppStorage 键：当前 Tabs 页 key（MainView 切换 Tab 时写入；路由页退出时据此恢复活动页上下文，
   *  否则路由页把上下文清空后，回到 Tab 页会回落全局灰字色、该 Tab 的单独色"像没生效"） */
  static readonly KEY_GRAY_TAB_PAGE: string = 'grayTabPageKey';
  /** 每页单独灰字色（pageKey -> rrggbb），启动时从 DataStore 恢复 */
  private static grayPageMap: Map<string, string> = new Map();

  /** 全局覆盖色（mode/custom 现算；不读每页 map） */
  private static globalGrayOverride(): string | undefined {
    const mode: string | undefined = AppStorage.get<string>(GlassMaterial.KEY_GRAY_MODE);
    if (mode === 'gray') {
      return '#9AA0A6';
    }
    if (mode === 'white') {
      return '#FFFFFF';
    }
    if (mode === 'black') {
      return '#000000';
    }
    if (mode === 'custom') {
      const c: string | undefined = AppStorage.get<string>(GlassMaterial.KEY_GRAY_CUSTOM);
      if (c !== undefined && c.length >= 6) {
        return c.startsWith('#') ? c : `#${c}`;
      }
    }
    // 「自动」：按壁纸对比度算出的灰字色（1.5s 防抖后写入；未算出/无壁纸时返回 undefined → 用站点默认灰）
    const auto: string = GlassMaterial.autoGrayColor();
    if (auto.length >= 6) {
      return auto;
    }
    return undefined;
  }

  /**
   * 文本角色码：与 graySecondary / grayTertiary 一一对应。
   * 高级调整支持「每页 × 角色」粒度：map 键为 `页面key|角色`（角色粒度）或 `页面key`（整页）。
   * 解析优先级：角色 → 整页 → 全局灰字模式。
   */
  static readonly GRAY_ROLE_SECONDARY: string = 'secondary';
  static readonly GRAY_ROLE_TERTIARY: string = 'tertiary';

  /** 归一化 rrggbb → #rrggbb（非法返回 undefined） */
  private static normColor(c: string): string | undefined {
    if (c === undefined || c.length < 6) {
      return undefined;
    }
    return c.startsWith('#') ? c : `#${c}`;
  }

  /** 组合键：页面 key + 角色（高级调整的细粒度覆盖键） */
  static grayKeyOf(pageKey: string, role: string): string {
    return `${pageKey}|${role}`;
  }

  /** 读取「页面 × 角色」覆盖色（rrggbb 原文；未设置为空串）——高级调整面板显示用 */
  static grayRoleColor(pageKey: string, role: string): string {
    return GlassMaterial.grayPageMap.get(GlassMaterial.grayKeyOf(pageKey, role)) ?? '';
  }

  /**
   * 解析指定页面 + 角色的覆盖色：角色 → 整页 → 全局；
   * 返回 undefined 表示完全不覆盖（用默认灰色）。
   */
  private static resolveFor(pageKey: string, role: string): string | undefined {
    if (pageKey !== '') {
      const rc: string | undefined = GlassMaterial.grayPageMap.get(GlassMaterial.grayKeyOf(pageKey, role));
      const rn: string | undefined = rc === undefined ? undefined : GlassMaterial.normColor(rc);
      if (rn !== undefined) {
        return rn;
      }
      const pc: string | undefined = GlassMaterial.grayPageMap.get(pageKey);
      const pn: string | undefined = pc === undefined ? undefined : GlassMaterial.normColor(pc);
      if (pn !== undefined) {
        return pn;
      }
    }
    // 全局：广播缓存（broadcastGray 维护）；缓存未初始化时现算兜底
    const eff: string = AppStorage.get<string>(GlassMaterial.KEY_GRAY_EFFECTIVE) ?? '';
    if (eff !== '') {
      return eff;
    }
    return GlassMaterial.globalGrayOverride();
  }

  /** 按角色解析覆盖色（app 内实际渲染路径：活动页上下文 + 角色） */
  private static grayOverride(role: string): string | undefined {
    const pk: string = AppStorage.get<string>(GlassMaterial.KEY_GRAY_PAGE_ACTIVE) ?? '';
    return GlassMaterial.resolveFor(pk, role);
  }

  /**
   * 预览指定页面（可能是非活动页）某角色的灰字色——供「灰字高级调整」页的完整界面预览使用。
   * 与 app 内渲染同一套解析逻辑，保证「预览所见 = 实际所得」。
   */
  static grayTextFor(pageKey: string, role: string, defaultColor: ResourceColor): ResourceColor {
    return GlassMaterial.resolveFor(pageKey, role) ?? defaultColor;
  }

  /** 重算全局覆盖色并广播（灰字设置变化时调用；订阅 grayTick 的页面即时刷新） */
  static broadcastGray(): void {
    const g: string | undefined = GlassMaterial.globalGrayOverride();
    AppStorage.setOrCreate(GlassMaterial.KEY_GRAY_EFFECTIVE, g ?? '');
    const tick: number = (AppStorage.get<number>(GlassMaterial.KEY_GRAY_TICK) ?? 0) + 1;
    AppStorage.setOrCreate(GlassMaterial.KEY_GRAY_TICK, tick);
  }

  /** 页面激活时调用：设置每页单独灰字色的生效上下文并广播（活动页文本即时按本页色重算） */
  static setPageActive(pageKey: string): void {
    AppStorage.setOrCreate(GlassMaterial.KEY_GRAY_PAGE_ACTIVE, pageKey);
    GlassMaterial.broadcastGray();
  }

  /** Tabs 页激活（MainView 调用）：记录当前 Tab key 并设为活动页上下文 */
  static setTabPage(pageKey: string): void {
    AppStorage.setOrCreate(GlassMaterial.KEY_GRAY_TAB_PAGE, pageKey);
    GlassMaterial.setPageActive(pageKey);
  }

  /** 路由页（二级页）退出时调用：把活动页上下文恢复为「当前 Tab 页」。
   *  此前直接 setPageActive('') 会把上下文清空 → 回到 Tab 页后该页的单独灰字色不生效（回落全局）。 */
  static restoreTabPage(): void {
    const k: string = AppStorage.get<string>(GlassMaterial.KEY_GRAY_TAB_PAGE) ?? '';
    GlassMaterial.setPageActive(k);
  }

  /** 启动恢复：从 DataStore 读每页单独灰字色 map（EntryAbility 调用一次） */
  static loadGrayPageMap(): void {
    GlassMaterial.grayPageMap = DataStore.loadGrayPageMap();
  }

  /** 读取某页单独灰字色（rrggbb；未设置返回空串）——高级调整面板显示用 */
  static grayPageColor(pageKey: string): string {
    return GlassMaterial.grayPageMap.get(pageKey) ?? '';
  }

  /** 设置某页单独灰字色（rrggbb；空串=清除该页覆盖）并持久化 + 广播 */
  static setGrayPageColor(pageKey: string, color: string): void {
    if (color.length < 6) {
      GlassMaterial.grayPageMap.delete(pageKey);
    } else {
      GlassMaterial.grayPageMap.set(pageKey, color.startsWith('#') ? color.substring(1) : color);
    }
    DataStore.saveGrayPageMap(GlassMaterial.grayPageMap);
    GlassMaterial.broadcastGray();
  }

  /**
   * 角色解析（tick 仅作「响应式依赖载体」，不参与取值）。
   *
   * ⚠️ tick 必须来自调用组件自己的 `@StorageProp('grayTick')`：ArkUI 在**属性表达式**里
   * 读到响应式属性才登记依赖，广播时才会重算该属性；静态函数内部读 AppStorage 不登记依赖。
   * 参考项目内已验证可实时的主题副标题色写法：`this.subtitleColor.length > 0 ? this.subtitleColor : 默认`。
   */
  private static resolveRole(tick: number, role: string): string | undefined {
    if (tick < 0) {
      return undefined; // 异常输入（tick 由 0 起递增，不会为负）：不覆盖
    }
    return GlassMaterial.grayOverride(role);
  }

  /**
   * 次要文字色（原默认：text_secondary）。
   * @param tick **传入调用组件的 `this.grayTick`**（响应式依赖载体，见 resolveRole 说明）
   * @param defaultColor 传入 $r('app.color.text_secondary') 作为未覆盖时的默认值
   */
  static graySecondary(tick: number, defaultColor: ResourceColor): ResourceColor {
    return GlassMaterial.resolveRole(tick, GlassMaterial.GRAY_ROLE_SECONDARY) ?? defaultColor;
  }

  /**
   * 辅助文字色（原默认：text_tertiary）。
   * @param tick **传入调用组件的 `this.grayTick`**（响应式依赖载体，见 resolveRole 说明）
   * @param defaultColor 传入 $r('app.color.text_tertiary') 作为未覆盖时的默认值
   */
  static grayTertiary(tick: number, defaultColor: ResourceColor): ResourceColor {
    return GlassMaterial.resolveRole(tick, GlassMaterial.GRAY_ROLE_TERTIARY) ?? defaultColor;
  }

  // ── 文字样式增强（斜体 / 加粗 / 减细 / 荧光底）：外观设置可调，作用于全站灰字，便于区分与阅读 ──
  /** AppStorage 键：文字样式（''=默认 | 'italic' | 'bold' | 'thin' | 'glow'） */
  static readonly KEY_TEXT_STYLE: string = 'textStyleMode';
  /** AppStorage 键：自动灰字色（按壁纸对比度算出；''＝未算出，用各站点默认灰） */
  static readonly KEY_GRAY_AUTO: string = 'grayAutoColor';
  /** 荧光底色：荧光笔黄、半透明（醒目又不遮挡壁纸纹理） */
  private static readonly TEXT_GLOW_BG: string = 'rgba(255, 233, 92, 0.38)';
  /** 「自动」配色的防抖定时器句柄 */
  private static autoGrayTimer: number = -1;

  /** 当前文字样式（'' | 'italic' | 'bold' | 'thin' | 'glow'） */
  private static styleMode(): string {
    return AppStorage.get<string>(GlassMaterial.KEY_TEXT_STYLE) ?? '';
  }

  /**
   * 斜体：样式='italic' 时斜体，否则常规。
   * tick 仅作响应式依赖载体（调用处须传自己的订阅值，见 resolveRole 说明）。
   */
  static styleItalic(tick: number): FontStyle {
    if (tick < 0) {
      return FontStyle.Normal;
    }
    return GlassMaterial.styleMode() === 'italic' ? FontStyle.Italic : FontStyle.Normal;
  }

  /** 字重：'bold'=粗体 / 'thin'=更细 / 其余=常规（只作用于灰字，不影响主文字） */
  static styleWeight(tick: number): FontWeight {
    if (tick < 0) {
      return FontWeight.Normal;
    }
    const m: string = GlassMaterial.styleMode();
    if (m === 'bold') {
      return FontWeight.Bold;
    }
    if (m === 'thin') {
      return FontWeight.Lighter;
    }
    return FontWeight.Normal;
  }

  /** 荧光底：样式='glow' 时给灰字铺一层荧光高亮底，其余样式透明（不影响默认观感） */
  static styleGlowBg(tick: number): ResourceColor {
    if (tick < 0) {
      return Color.Transparent;
    }
    return GlassMaterial.styleMode() === 'glow' ? GlassMaterial.TEXT_GLOW_BG : Color.Transparent;
  }

  /** 已算出的自动灰字色（''＝未算出/无壁纸） */
  static autoGrayColor(): string {
    return AppStorage.get<string>(GlassMaterial.KEY_GRAY_AUTO) ?? '';
  }

  /**
   * 重新计算「自动」灰字色：按当前壁纸亮度选对比度更高的颜色（复用 WallpaperTone 的对比度算法）。
   * **1.5s 防抖**——壁纸刚变化时先不动，静止 1.5 秒后再切换，避免连续跳动。
   * 应在进入外观设置 / 冷启动 / 切换壁纸后调用。
   */
  static scheduleAutoGray(): void {
    if (GlassMaterial.autoGrayTimer >= 0) {
      clearTimeout(GlassMaterial.autoGrayTimer);
    }
    GlassMaterial.autoGrayTimer = setTimeout(() => {
      GlassMaterial.autoGrayTimer = -1;
      GlassMaterial.applyAutoGray();
    }, 1500);
  }

  /** 立即计算并写入自动灰字色并广播（无壁纸时不覆盖，沿用各站点默认灰） */
  private static applyAutoGray(): void {
    const tone: number = AppStorage.get<number>('wallpaperTone') ?? -1;
    const dark: boolean = AppStorage.get<boolean>('isDarkMode') ?? false;
    const color: string = tone < 0 ? '' : WallpaperTone.onWallpaperSecondary(tone, dark);
    AppStorage.setOrCreate(GlassMaterial.KEY_GRAY_AUTO, color);
    GlassMaterial.broadcastGray();
  }

  /** 切换文字样式（写 AppStorage + 持久化 + 广播灰字刷新） */
  static setTextStyle(mode: string): void {
    AppStorage.setOrCreate(GlassMaterial.KEY_TEXT_STYLE, mode);
    DataStore.saveTextStyle(mode);
    GlassMaterial.broadcastGray();
  }

  /** 启动恢复文字样式（EntryAbility 调用） */
  static loadTextStyle(): void {
    AppStorage.setOrCreate(GlassMaterial.KEY_TEXT_STYLE, DataStore.loadTextStyle());
  }
}
