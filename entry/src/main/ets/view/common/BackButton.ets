/**
 * 官方风格圆形返回按钮：半透明白玻璃圆底 + 白色左箭头
 * 用于各页顶栏返回（替代纯文本 '‹'），浅/深色主题渐变顶栏上均可见。
 */
@Component
export struct BackButton {
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 返回回调（默认 pop，由调用页决定） */
  onBack: () => void = () => {
  };

  build() {
    Stack({ alignContent: Alignment.Center }) {
      SymbolGlyph($r('sys.symbol.chevron_left'))
        .fontSize(17)
        .fontColor([Color.White])
    }
    .width(34)
    .height(34)
    .borderRadius(17)
    .backgroundColor(this.isDarkMode ? 'rgba(255,255,255,0.16)' : 'rgba(255,255,255,0.24)')
    .border({ width: 1, color: 'rgba(255,255,255,0.28)' })
    .shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 })
    .onClick(() => {
      this.onBack();
    })
  }
}
