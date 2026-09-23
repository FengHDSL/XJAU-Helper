/**
 * 壁纸工具：壁纸源解析（内置预置壁纸已移除，仅支持用户自定义壁纸）
 * - 'none' / 空串 = 未启用壁纸，src() 返回空串，由调用方据此隐藏 Image
 * - 'c:<path>'    = 用户导入 / 每日下载的自定义壁纸（file:// 读取）
 * - 其它（如历史遗留的 b1..b6）= 已废弃的内置壁纸 id，按未启用处理（返回空串）
 *
 * 注意（踩坑）：自定义壁纸文件**必须唯一命名**（带时间戳）。
 * 早期实现固定写入 `${filesDir}/wallpaper_user.dat`，导致：
 *   1) 二次导入时文件被覆盖，而 wallpaperId 仍是同一路径 → applyWallpaper 判重直接返回；
 *   2) Image 对同一 file:// 路径命中缓存 → 界面不刷新（用户观感：已选壁纸再选一个"无法应用"）。
 * 因此统一使用 newUserWallpaperPath() 生成唯一路径，并在应用后用 cleanupUserWallpapers() 清理旧文件。
 */
import { fileIo } from '@kit.CoreFileKit';

export class Wallpaper {
  /** 自定义壁纸文件名前缀（清理旧文件时按此前缀匹配） */
  private static readonly USER_PREFIX: string = 'wallpaper_user';

  /** 壁纸源（自定义走 file://；无壁纸或旧内置 id 返回空串） */
  static src(id: string): Resource | string {
    if (id === 'none' || id.length === 0) {
      return '';
    }
    if (id.startsWith('c:')) {
      return `file://${id.substring(2)}`;
    }
    // 内置预置壁纸已移除（减小包体）：旧 id 一律按"未启用"处理
    return '';
  }

  /** 生成新的自定义壁纸文件路径（唯一命名，避免同路径覆盖导致界面不刷新） */
  static newUserWallpaperPath(filesDir: string): string {
    return `${filesDir}/${Wallpaper.USER_PREFIX}_${Date.now()}.dat`;
  }

  /** 清理历史自定义壁纸文件（保留 keepPath 指向的文件；含早期固定命名的 wallpaper_user.dat） */
  static cleanupUserWallpapers(filesDir: string, keepPath: string): void {
    try {
      const names: string[] = fileIo.listFileSync(filesDir);
      for (let i = 0; i < names.length; i++) {
        const n: string = names[i];
        if (n.indexOf(Wallpaper.USER_PREFIX) !== 0) {
          continue;
        }
        const p: string = `${filesDir}/${n}`;
        if (p === keepPath) {
          continue;
        }
        try {
          fileIo.unlinkSync(p);
        } catch (e) {
          // 单个文件删除失败忽略（如仍被占用）
        }
      }
    } catch (e) {
      // 目录读取失败忽略
    }
  }
}
