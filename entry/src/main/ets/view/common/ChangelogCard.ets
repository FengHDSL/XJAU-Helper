/**
 * 单条更新日志卡片（关于应用页「最近 5 条」与更新日志页「全部历史」共用，保证样式一致）
 *
 * 卡片统一走 `MaterialCard` 承载：材质层是卡片内部底层、与卡片同尺寸同圆角，材质生效时
 * 卡片自身的底色/磨砂/亮边/阴影一并让出，所以整张卡只剩一层视觉（就是沉浸光感材质本身），
 * 不会出现「材质盖住卡片」或两层卡片。光感关闭时按构造参数回落为原来的纯色/毛玻璃卡片。
 *
 * 本卡是**成排**的更新日志卡（相邻卡片只隔 14vp），故传 `cardMaterialShadow: false`：
 * 材质仍照常渲染，只是不带 applyShadow 那层投影——投影会在卡间缝隙里叠成一条暗带。
 */
import { GlassMaterial } from '../../common/GlassMaterial';
import { MaterialCard } from './MaterialCard';
import { AppearanceStore } from '../../common/AppearanceStore';

@Component
export struct ChangelogCard {
  @Prop version: string = '';
  @Prop date: string = '';
  /** 灰字广播订阅：颜色表达式需传 this.grayTick 才登记响应式依赖（否则改色不实时刷新） */
  @StorageProp('grayTick') grayTick: number = 0;
  /** 全局字重响应式订阅：表达式读 this.fwMode 才登记依赖，fwValue 声明即订阅 */
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  /** 该版本的条目文本（静态数据，无需响应式） */
  items: string[] = [];

  build() {
    // 原 Stack 上的 backgroundColor / systemMaterial / 磨砂 / 边框 / 阴影 / 圆角 / 外边距
    // 全部改走 card* 参数（尾随闭包初始化的自定义组件之后不能再链式加属性）；
    // 原来的 16vp 内边距挂内部内容容器（这里是 MaterialCard 的 cardPadding，落在内容容器上）。
    MaterialCard({
      cardRadius: 16,
      cardPadding: 16,
      cardAlignItems: ItemAlign.Start,
      cardMaterialShadow: false,
      cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
      cardBlur: GlassMaterial.cardBlur(),
      cardBorderW: GlassMaterial.cardBorderWidth(),
      cardBorderC: GlassMaterial.borderColor(),
      cardShadow: GlassMaterial.cardShadowStyle(),
      cardMargin: { bottom: 14 }
    }) {
      Column() {
        Row() {
          Text(`v${this.version}`)
            .fontSize(15)
            .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
            .fontColor($r('app.color.text_primary'))
          Text(`  ${this.date}`)
            .fontSize(12)
            .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
        }
        .width('100%')
        .margin({ bottom: 8 })

        ForEach(this.items, (item: string) => {
          // 分组标题（@新增@ / @修复@ 开头 → 渲染为品牌色加粗小标题）
          if (item.startsWith('@新增@') || item.startsWith('@修复@')) {
            Text(item.substring(3))
              .fontSize(13)
              .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
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
                .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
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
    }
  }
}
