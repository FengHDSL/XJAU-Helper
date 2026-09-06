/**
 * 壁纸工具：预置壁纸资源映射 + 自定义壁纸源（供主界面背景与选择页共用）
 * 预置 id：'b1'..'b6'（app.media.wallpaper_1..6）；自定义：'c:<path>'（file:// 读取）
 * 'none'（或空串）= 未启用壁纸，src() 返回空串由调用方据此隐藏 Image
 */
export class Wallpaper {
  /** 预置壁纸资源（ArkTS $r 需字面量，按 id 选） */
  static res(id: string): Resource {
    if (id === 'b2') {
      return $r('app.media.wallpaper_2');
    }
    if (id === 'b3') {
      return $r('app.media.wallpaper_3');
    }
    if (id === 'b4') {
      return $r('app.media.wallpaper_4');
    }
    if (id === 'b5') {
      return $r('app.media.wallpaper_5');
    }
    if (id === 'b6') {
      return $r('app.media.wallpaper_6');
    }
    return $r('app.media.wallpaper_1');
  }

  /** 壁纸源（自定义走 file://，预置走 app.media；'none'/空=无壁纸返回空串，调用方据此隐藏 Image） */
  static src(id: string): Resource | string {
    if (id === 'none' || id.length === 0) {
      return '';
    }
    if (id.startsWith('c:')) {
      return `file://${id.substring(2)}`;
    }
    return Wallpaper.res(id);
  }
}
