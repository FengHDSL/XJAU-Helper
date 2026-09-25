/**
 * 每日壁纸：用户保存了「图像地址」后，每天首次启动自动从该地址下载新壁纸并应用。
 * 特性：静默执行（失败不影响启动与使用）、同日只更新一次（以 YYYY-MM-DD 记录）。
 */
import { http } from '@kit.NetworkKit';
import { fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { DataStore } from './DataStore';
import { DateUtil } from './DateUtil';
import { WallpaperTone } from './WallpaperTone';
import { Wallpaper } from './Wallpaper';
import { GlassMaterial } from './GlassMaterial';

export class DailyWallpaper {
  /** 防止同一时刻重复下载 */
  private static running: boolean = false;

  /**
   * 启动时调用：若已保存图像地址、且今天尚未更新，则自动下载并应用（静默）
   * @param context UIAbility 上下文（用于 filesDir）
   */
  static ensureToday(context: common.UIAbilityContext): void {
    if (DailyWallpaper.running) {
      return;
    }
    const url: string = DataStore.loadWallpaperUrl();
    if (url.length === 0 || (!url.startsWith('http://') && !url.startsWith('https://'))) {
      return;
    }
    const today: string = DateUtil.format(new Date());
    if (DataStore.loadWallpaperUrlDate() === today) {
      return;
    }
    DailyWallpaper.running = true;
    const req: http.HttpRequest = http.createHttp();
    req.request(url, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      readTimeout: 30000
    }).then((resp: http.HttpResponse) => {
      if (resp.responseCode !== 200) {
        DailyWallpaper.running = false;
        req.destroy();
        return;
      }
      try {
        const arr: ArrayBuffer = resp.result as ArrayBuffer;
        // 唯一命名：避免覆盖同一路径导致 Image 命中缓存而不刷新
        const dstPath: string = Wallpaper.newUserWallpaperPath(context.filesDir);
        const file: fileIo.File = fileIo.openSync(dstPath,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.READ_WRITE);
        fileIo.writeSync(file.fd, arr);
        fileIo.closeSync(file);
        DataStore.saveWallpaper(`c:${dstPath}`);
        DataStore.setWallpaperUrlDate(today);
        AppStorage.setOrCreate('wallpaperId', `c:${dstPath}`);
        // 清理历史自定义壁纸文件（保留当前使用的）
        Wallpaper.cleanupUserWallpapers(context.filesDir, dstPath);
        // 自动分析明暗并适配文字对比度
        WallpaperTone.analyze(arr).then((tone: number) => {
          WallpaperTone.save(tone);
          // 明暗分析完成后重算「自动」灰字色并广播（静默换壁纸也要刷新灰字自动色）
          GlassMaterial.scheduleAutoGray();
        });
      } catch (e) {
        // 静默：写入失败不影响启动
      }
      DailyWallpaper.running = false;
      req.destroy();
    }).catch(() => {
      // 静默：网络失败不影响启动
      DailyWallpaper.running = false;
      req.destroy();
    });
  }
}
