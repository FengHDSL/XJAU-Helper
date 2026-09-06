/**
 * TabSlideIn：Tab 切换时页面内容滑入/淡入（壁纸固定在底层不动）。
 * 包裹在 TabContent 子内容外，每次 appear 播放 translate+opacity。
 */
@Component
export struct TabSlideIn {
  @BuilderParam content: () => void = this.emptyBuilder;
  @State offX: number = 26;
  @State op: number = 0.35;

  @Builder
  emptyBuilder() {
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .height('100%')
    .translate({ x: this.offX })
    .opacity(this.op)
    .onAppear(() => {
      this.offX = 26;
      this.op = 0.35;
      this.getUIContext().animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
        this.offX = 0;
        this.op = 1;
      });
    })
  }
}
