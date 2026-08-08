/**
 * 隐私协议页：以独立页面展示协议全文（正文取自 PrivacyText 单一事实源）
 */
import { AppState } from '../common/AppState';
import { PRIVACY_SECTIONS, PrivacySection } from '../common/PrivacyText';
import { PageHeader } from './common/UiKit';

@Component
export struct PrivacyPage {
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;

  @Builder
  section(title: string, content: string) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 8 })
      Text(content)
        .fontSize(13)
        .lineHeight(22)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 18 })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: '隐私协议',
          onBack: () => {
            AppState.stack.pop();
          }
        })

        Scroll() {
          Column() {
            ForEach(PRIVACY_SECTIONS, (sec: PrivacySection) => {
              this.section(sec.title, sec.content)
            }, (sec: PrivacySection) => sec.title)

            Column()
              .height(px2vp(this.bottomInsetPx) + 24)
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 4 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
  }
}
