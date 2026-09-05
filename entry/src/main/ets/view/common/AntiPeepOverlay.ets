/**
 * 防窥蒙层组件
 *
 * 当检测到窥屏时，在页面内容上方覆盖一层半透明蒙层，
 * 遮挡敏感信息（成绩、GPA等），并提示用户当前处于防窥保护状态。
 *
 * 用法：在页面 build() 中用 Stack 包裹页面内容，将本组件放在内容之后层叠覆盖。
 */
@Component
export struct AntiPeepOverlay {
  /** 是否检测到窥屏 */
  @Prop isPeeped: boolean = false;

  build() {
    if (this.isPeeped) {
      // 全屏蒙层：模糊背景 + 居中提示
      Column() {
        // 防窥图标
        Image($r('app.media.eye_off'))
          .width(56)
          .height(56)
          .fillColor($r('app.color.brand'))
          .margin({ bottom: 16 })

        Text('防窥保护已启动')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 8 })

        Text('检测到非机主观看，敏感信息已隐藏')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 4 })

        Text('请面向手机解锁后查看')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor($r('app.color.bg_page'))
      .backdropBlur(20)
      .opacity(0.96)
    }
  }
}
