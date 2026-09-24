/**
 * 右箭头图标（chevron_right.svg，用户提供资源）。
 *
 * 黑白自适应：**不跟随主题色/灰字体系**——深色模式白色、浅色模式黑色。
 * SVG 原始画布 24×48、箭头垂直居中 → 用 ImageFit.Cover 裁掉上下透明区，
 * 得到正方形视觉（iconSize × iconSize）。
 */
@Component
export struct ChevronRight {
  /** 视觉边长（正方形） */
  @Prop iconSize: number = 16;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;

  build() {
    Image($r('app.media.chevron_right'))
      .width(this.iconSize)
      .height(this.iconSize)
      .objectFit(ImageFit.Cover)
      .fillColor(this.isDarkMode ? Color.White : Color.Black)
      .draggable(false)
  }
}
