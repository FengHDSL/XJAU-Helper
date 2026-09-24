import { DataStore } from './DataStore';
import { AppearanceStore } from './AppearanceStore';

/**
 * 主题工具：顶栏主题色（中国红 / 天空蓝 / 农大绿 / 自定义 #RRGGBB）
 * AppStorage key: themeColor（'green' | 'red' | 'blue' | 'orange' | 'purple' | '#RRGGBB'，默认 'green'）
 * 顶栏样式 barStyle：'new'=主题色透明渐变 / 'legacy'=1.3.1 旧版实色
 */
export class Theme {
  static readonly KEY_DS: string = 'theme_color';

  /** 是否合法 hex 主题（#RRGGBB） */
  static isHex(t: string): boolean {
    return /^#[0-9a-fA-F]{6}$/.test(t);
  }

  /** 当前主题标识 */
  static current(): string {
    const t: string = AppStorage.get<string>('themeColor') ?? 'green';
    return t;
  }

  /** 当前主题的顶栏背景色 */
  static color(): string {
    return Theme.colorOf(Theme.current());
  }

  /** 指定主题的顶栏背景色（内置五色 + 自定义 hex） */
  static colorOf(theme: string): string {
    if (Theme.isHex(theme)) {
      return theme;
    }
    if (theme === 'red') {
      return '#C3272B'; // 中国红
    }
    if (theme === 'blue') {
      return '#3B82F6'; // 天空蓝
    }
    if (theme === 'orange') {
      return '#E0603A'; // 落日橙（暖色，2026-09-19 新增）
    }
    if (theme === 'purple') {
      return '#7C5CE0'; // 紫罗兰（冷紫，2026-09-19 新增）
    }
    return '#079841'; // 农大绿 RGB(7,152,65)
  }

  /** 内置主题键列表（用于校验/遍历） */
  static builtinKeys(): string[] {
    return ['green', 'red', 'blue', 'orange', 'purple'];
  }

  /** 是否为内置主题键 */
  static isBuiltin(t: string): boolean {
    return Theme.builtinKeys().indexOf(t) >= 0;
  }

  /** #RRGGBB → rgba(r,g,b,a)，供主题色渐隐渐变用（非法值回落农大绿） */
  static rgba(color: string, alpha: number): string {
    let hex = color;
    if (!/^#([0-9a-fA-F]{6})$/.test(hex)) {
      hex = '#079841';
    }
    const r = parseInt(hex.substring(1, 3), 16);
    const g = parseInt(hex.substring(3, 5), 16);
    const b = parseInt(hex.substring(5, 7), 16);
    return `rgba(${r},${g},${b},${alpha})`;
  }

  /** 顶栏渐变颜色段：两档均为"顶部实色 → 底部渐隐透明"（旧版实色仅为命名，实际同为渐变+毛玻璃） */
  static barGradient(key: string, style: string): [ResourceColor, number][] {
    return [[Theme.colorOf(key), 0], [Theme.rgba(Theme.colorOf(key), 0), 1]];
  }

  /**
   * 指定背景色上「可读性最优」的文字色（深 / 浅二选一）。
   * 依据 WCAG 相对亮度计算：亮度 > 0.179 时用深色文字，否则用浅色文字，
   * 保证主题色（含用户自定义 hex）改变时按钮文字始终清晰可读。
   */
  static onColor(bg: string): string {
    let hex: string = bg;
    if (!/^#([0-9a-fA-F]{6})$/.test(hex)) {
      hex = '#079841';
    }
    const r: number = parseInt(hex.substring(1, 3), 16);
    const g: number = parseInt(hex.substring(3, 5), 16);
    const b: number = parseInt(hex.substring(5, 7), 16);
    const toLin = (c: number): number => {
      const s: number = c / 255;
      return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
    };
    const lum: number = 0.2126 * toLin(r) + 0.7152 * toLin(g) + 0.0722 * toLin(b);
    // 0.179 为"白字/黑字"对比度相等点，超过该亮度用深色文字更清晰
    return lum > 0.179 ? '#101413' : '#FFFFFF';
  }

  /** 品牌色按钮上的文字色（浅色 #079841 / 深色 #3FBF92 两档品牌色均适用 → 深色文字） */
  static onBrand(): string {
    return Theme.onColor('#079841');
  }

  /** 主题显示名（自定义 hex 原样大写返回） */
  static label(): string {
    const t: string = Theme.current();
    if (Theme.isHex(t)) {
      return t.toUpperCase();
    }
    if (t === 'red') {
      return '中国红';
    }
    if (t === 'blue') {
      return '天空蓝';
    }
    if (t === 'orange') {
      return '落日橙';
    }
    if (t === 'purple') {
      return '紫罗兰';
    }
    return '农大绿';
  }

  /** 切换主题并写入 AppStorage + 持久化 */
  static apply(theme: string): void {
    AppStorage.setOrCreate('themeColor', theme);
    DataStore.put(Theme.KEY_DS, theme);
    // 主题色变化 → 卡片沾色/页面背景派生色重算并广播（订阅端即时刷新）
    AppearanceStore.broadcastDerived();
  }

  /** 启动时从持久化恢复主题（内置枚举或合法 hex，否则回退绿） */
  static restore(): void {
    const t: string = DataStore.get(Theme.KEY_DS);
    if (Theme.isBuiltin(t) || Theme.isHex(t)) {
      AppStorage.setOrCreate('themeColor', t);
    } else {
      AppStorage.setOrCreate('themeColor', 'green');
    }
    AppearanceStore.broadcastDerived();
  }
}
