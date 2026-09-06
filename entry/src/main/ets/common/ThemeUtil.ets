import { DataStore } from './DataStore';

/**
 * 主题工具：顶栏主题色（中国红 / 天空蓝 / 农大绿 / 自定义 #RRGGBB）
 * AppStorage key: themeColor（'red' | 'blue' | 'green' | '#RRGGBB'，默认 'green'）
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

  /** 指定主题的顶栏背景色（内置三色 + 自定义 hex） */
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
    return '#079841'; // 农大绿 RGB(7,152,65)
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

  /** 顶栏渐变颜色段：新版=顶部实色→底部渐隐透明；旧版(1.3.1)=整段实色不透明 */
  static barGradient(key: string, style: string): [ResourceColor, number][] {
    if (style === 'legacy') {
      return [[Theme.colorOf(key), 0], [Theme.colorOf(key), 1]];
    }
    return [[Theme.colorOf(key), 0], [Theme.rgba(Theme.colorOf(key), 0), 1]];
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
    return '农大绿';
  }

  /** 切换主题并写入 AppStorage + 持久化 */
  static apply(theme: string): void {
    AppStorage.setOrCreate('themeColor', theme);
    DataStore.put(Theme.KEY_DS, theme);
  }

  /** 启动时从持久化恢复主题（三色枚举或合法 hex，否则回退绿） */
  static restore(): void {
    const t: string = DataStore.get(Theme.KEY_DS);
    if (t === 'red' || t === 'blue' || t === 'green' || Theme.isHex(t)) {
      AppStorage.setOrCreate('themeColor', t);
    } else {
      AppStorage.setOrCreate('themeColor', 'green');
    }
  }
}
