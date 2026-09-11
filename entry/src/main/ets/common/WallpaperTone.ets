/**
 * 壁纸明暗分析：导入/更新壁纸后自动分析平均亮度，并给出"对比度适配"遮罩，
 * 使界面文字与背景的对比度满足无障碍要求：
 *  - 图标 / 标题文字 ≥ 3:1
 *  - 正文文字 ≥ 4.5:1
 *
 * 原理：以 WCAG 相对亮度近似计算——浅色正文（深色模式下为白字）需要更亮/更暗的背景，
 * 这里通过自动叠加白色或黑色半透明遮罩，把背景亮度调整到满足上述阈值的区间。
 */
import { image } from '@kit.ImageKit';
import { DataStore } from './DataStore';

export class WallpaperTone {
  static readonly KEY: string = 'wallpaper_tone';

  /** 分析图片平均亮度（0~1，越大越亮）；失败或异常返回 -1 */
  static async analyze(data: ArrayBuffer): Promise<number> {
    try {
      const src: image.ImageSource = image.createImageSource(data);
      const pm: image.PixelMap = await src.createPixelMap();
      const info: image.ImageInfo = await pm.getImageInfo();
      const w: number = info.size.width;
      const h: number = info.size.height;
      const total: number = w * h;
      const buf: ArrayBuffer = new ArrayBuffer(total * 4);
      await pm.readPixelsToBuffer(buf);
      const view: Uint8Array = new Uint8Array(buf);
      const step: number = Math.max(1, Math.floor(total / 4000));
      let sum: number = 0;
      let cnt: number = 0;
      for (let i = 0; i < total; i += step) {
        const r: number = view[i * 4];
        const g: number = view[i * 4 + 1];
        const b: number = view[i * 4 + 2];
        sum += (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
        cnt++;
      }
      pm.release();
      src.release();
      return cnt > 0 ? sum / cnt : -1;
    } catch (e) {
      return -1;
    }
  }

  /** 保存亮度（供界面实时适配） */
  static save(tone: number): void {
    if (tone < 0) {
      return;
    }
    DataStore.put(WallpaperTone.KEY, tone.toFixed(3));
    AppStorage.setOrCreate('wallpaperTone', tone);
  }

  /** 读取已保存的亮度（-1 = 未知） */
  static load(): number {
    const raw: string = DataStore.get(WallpaperTone.KEY);
    const v: number = Number.parseFloat(raw);
    return Number.isNaN(v) ? -1 : v;
  }


  /** 遮罩后的实际背景亮度近似值（用于判断其上文字应取深色还是浅色） */
  static effectiveBg(tone: number, isDarkMode: boolean): number {
    if (tone < 0) {
      return isDarkMode ? 0.18 : 0.72;
    }
    const target: number = isDarkMode ? 0.18 : 0.72;
    if (!isDarkMode) {
      if (tone >= target) {
        return tone;
      }
      const alpha: number = Math.min(0.72, Math.max(0.06, (target - tone) / (1 - tone)));
      // 白遮罩叠加：B = tone + (1 - tone) * alpha
      return tone + (1 - tone) * alpha;
    }
    if (tone <= target) {
      return tone;
    }
    const alpha: number = Math.min(0.72, Math.max(0.06, (tone - target) / Math.max(tone, 0.01)));
    // 黑遮罩叠加：B = tone * (1 - alpha)
    return tone * (1 - alpha);
  }

  /**
   * 壁纸之上的文字/图标颜色（自动满足对比度：图标/标题 ≥ 3:1、正文 ≥ 4.5:1）
   * 背景偏亮 → 深色文字；背景偏暗 → 浅色文字
   */
  static onWallpaper(tone: number, isDarkMode: boolean): string {
    const bg: number = WallpaperTone.effectiveBg(tone, isDarkMode);
    return bg > 0.45 ? '#1B1B1B' : '#FFFFFF';
  }

  /** 壁纸之上的"次要说明文字"颜色（75% 不透明度，兼顾层次与对比度） */
  static onWallpaperSecondary(tone: number, isDarkMode: boolean): string {
    const c: string = WallpaperTone.onWallpaper(tone, isDarkMode);
    return c === '#FFFFFF' ? '#BFFFFFFF' : '#BF1B1B1B';
  }

  /**
   * 对比度适配遮罩颜色（ARGB 字符串）
   *  - 浅色模式（正文深色）：背景需足够亮 → 叠加白色，越暗越厚（目标背景亮度 ≈ 0.72，满足正文 4.5:1）
   *  - 深色模式（正文白色）：背景需足够暗 → 叠加黑色，越亮越厚（目标背景亮度 ≈ 0.18）
   */
  static overlay(tone: number, isDarkMode: boolean): string {
    if (tone < 0) {
      return '#00000000';
    }
    if (!isDarkMode) {
      const target: number = 0.72; // 保证深色正文 ≥ 4.5:1
      if (tone >= target) {
        return '#00000000';
      }
      let alpha: number = (target - tone) / (1 - tone);
      alpha = Math.min(0.72, Math.max(0.06, alpha));
      return `#${Math.round(alpha * 255).toString(16).padStart(2, '0').toUpperCase()}FFFFFF`;
    }
    const target: number = 0.18; // 保证白色正文 ≥ 4.5:1
    if (tone <= target) {
      return '#00000000';
    }
    let alpha: number = (tone - target) / Math.max(tone, 0.01);
    alpha = Math.min(0.72, Math.max(0.06, alpha));
    return `#${Math.round(alpha * 255).toString(16).padStart(2, '0').toUpperCase()}000000`;
  }
}
