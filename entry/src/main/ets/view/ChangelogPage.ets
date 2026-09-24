/**
 * 更新日志页：展示**全部历史**版本日志（关于应用页固定只显示最新 5 条，此页查看完整历史）
 * 入口：关于应用页更新日志区底部的「查看全部更新日志」
 */
import { AppState } from '../common/AppState';
import { CHANGELOG_ALL, ChangelogItem } from '../common/Changelog';
import { PageHeader } from './common/UiKit';
import { WallpaperFill } from './common/WallpaperFill';
import { ChangelogCard } from './common/ChangelogCard';

@Component
export struct ChangelogPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  /** 灰字广播订阅：颜色表达式需传 this.grayTick 才登记响应式依赖（否则改色不实时刷新） */
  @StorageProp('grayTick') grayTick: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // 二级页壁纸底层（无壁纸回 bg_page，不透下层）
        WallpaperFill()

        // 内容全屏：顶部占位随内容滚走，让上滑的内容进入悬浮顶栏下层
        Scroll() {
          Column() {
            // 顶栏占位（滚动时随内容滚走）
            Column()
              .width('100%')
              .height(this.getUIContext().px2vp(this.topInsetPx) + 60)

            Text(`共 ${CHANGELOG_ALL.length} 个版本`)
              .fontSize(12)
              .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
              .width('100%')
              .margin({ bottom: 10 })

            ForEach(CHANGELOG_ALL, (e: ChangelogItem) => {
              ChangelogCard({ version: e.version, date: e.date, items: e.items })
            }, (e: ChangelogItem) => e.version)
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 40 + this.getUIContext().px2vp(this.bottomInsetPx) })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        // 统一头部（悬浮层）
        PageHeader({
          title: '更新日志',
          onBack: () => {
            AppState.stack.pop();
          }
        })
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.bg_page'))
    .hideTitleBar(true)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    .width('100%')
    .height('100%')
  }
}
