import { uiMaterial } from '@kit.ArkUI';
import { AppearanceStore } from './AppearanceStore';
import { Theme } from './ThemeUtil';

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

  // ── 次要文字颜色覆盖（灰/白/黑/自定义）：外观设置页可调，提升壁纸上的可读性 ──
  /** AppStorage 键：灰字模式（default=默认灰 / white=白 / black=黑 / custom=自定义） */
  static readonly KEY_GRAY_MODE: string = 'grayTextMode';
  /** AppStorage 键：自定义灰字颜色（rrggbb 或 #rrggbb） */
  static readonly KEY_GRAY_CUSTOM: string = 'grayTextColor';

  /** 按模式解析覆盖色；返回 undefined 表示不覆盖（用默认灰色） */
  private static grayOverride(): string | undefined {
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
    return undefined;
  }

  /**
   * 次要文字色（原默认：text_secondary）。
   * @param defaultColor 传入 $r('app.color.text_secondary') 作为未覆盖时的默认值
   */
  static graySecondary(defaultColor: ResourceColor): ResourceColor {
    return GlassMaterial.grayOverride() ?? defaultColor;
  }

  /**
   * 辅助文字色（原默认：text_tertiary）。
   * @param defaultColor 传入 $r('app.color.text_tertiary') 作为未覆盖时的默认值
   */
  static grayTertiary(defaultColor: ResourceColor): ResourceColor {
    return GlassMaterial.grayOverride() ?? defaultColor;
  }
}
