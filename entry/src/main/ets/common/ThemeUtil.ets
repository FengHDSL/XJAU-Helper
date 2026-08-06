import { DataStore } from './DataStore';

/**
 * 主题工具：顶栏主题色（中国红 / 天空蓝 / 农大绿）
 * 只影响顶栏背景色（浅色模式），深色模式顶栏保持黑色
 * AppStorage key: themeColor（'red' | 'blue' | 'green'，默认 'green'）
 * 持久化 key: theme_color（DataStore）
 */
export class Theme {
  static readonly KEY_DS: string = 'theme_color';

  /** 当前主题标识 */
  static current(): string {
    const t: string = AppStorage.get<string>('themeColor') ?? 'green';
    return t;
  }

  /** 当前主题的顶栏背景色 */
  static color(): string {
    return Theme.colorOf(Theme.current());
  }

  /** 指定主题的顶栏背景色（供组件内 @StorageProp 绑定实时刷新） */
  static colorOf(theme: string): string {
    if (theme === 'red') {
      return '#C3272B'; // 中国红
    }
    if (theme === 'blue') {
      return '#3B82F6'; // 天空蓝
    }
    return '#079841'; // 农大绿 RGB(7,152,65)
  }

  /** 主题中文名（设置页展示） */
  static label(): string {
    const t: string = Theme.current();
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

  /** 启动时从持久化恢复主题 */
  static restore(): void {
    const t: string = DataStore.get(Theme.KEY_DS);
    if (t === 'red' || t === 'blue' || t === 'green') {
      AppStorage.setOrCreate('themeColor', t);
    } else {
      AppStorage.setOrCreate('themeColor', 'green');
    }
  }
}
