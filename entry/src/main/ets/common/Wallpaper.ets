/**
 * 壁纸工具：壁纸源解析（内置预置壁纸已移除，仅支持用户自定义壁纸）
 * - 'none' / 空串 = 未启用壁纸，src() 返回空串，由调用方据此隐藏 Image
 * - 'c:<path>'    = 用户导入 / 每日下载的自定义壁纸（file:// 读取）
 * - 其它（如历史遗留的 b1..b6）= 已废弃的内置壁纸 id，按未启用处理（返回空串）
 */
export class Wallpaper {
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
}
