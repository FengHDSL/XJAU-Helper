/**
 * 单条更新日志卡片（关于应用页「最近 5 条」与更新日志页「全部历史」共用，保证样式一致）
 */
@Component
export struct ChangelogCard {
  @Prop version: string = '';
  @Prop date: string = '';
  /** 该版本的条目文本（静态数据，无需响应式） */
  items: string[] = [];

  build() {
    Column() {
      Row() {
        Text(`v${this.version}`)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(`  ${this.date}`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      ForEach(this.items, (item: string) => {
        // 分组标题（@新增@ / @修复@ 开头 → 渲染为品牌色加粗小标题）
        if (item.startsWith('@新增@') || item.startsWith('@修复@')) {
          Text(item.substring(3))
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.brand'))
            .width('100%')
            .margin({ top: 6, bottom: 2 })
        } else {
          Row() {
            Text('·')
              .fontSize(13)
              .fontColor($r('app.color.brand'))
              .margin({ right: 8 })
            Text(item)
              .fontSize(13)
              .lineHeight(20)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .margin({ bottom: 6 })
        }
      }, (item: string) => item)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(16)
    .margin({ bottom: 14 })
  }
}
