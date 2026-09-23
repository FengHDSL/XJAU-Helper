/**
 * 消息：原"课程通知"，汇总显示教务通知（不做分类）
 *
 * 卡片外观接入（沉浸光感）：
 * - 本页唯一的一张卡片（noticeCard，消息列表项）改由 MaterialCard 承载材质层：
 *   材质层是卡片内部底层、与卡片同尺寸同圆角，材质生效时卡片的底色/磨砂/亮边/阴影自动让出，
 *   关闭光感时回落到原先的纯色/毛玻璃卡片外观。
 * - 原写法为「Column + backgroundColor/backgroundBlurStyle/border/shadow/systemMaterial/borderRadius/padding/margin/onClick」
 *   的整块卡片，现改为 MaterialCard 外壳，内边距走 cardPadding、圆角走 cardRadius、下间距走 cardMargin、整卡点击走 cardOnClick。
 * - NoticeDetailPage（消息详情）只有文字与 Divider，无卡片/按钮/弹窗，本次不涉及。
 */
import { JwApi } from '../api/JwApi';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { Theme } from '../common/ThemeUtil';
import { GlassMaterial } from '../common/GlassMaterial';
import { WallpaperTone } from '../common/WallpaperTone';
import { Immersive } from './common/Immersive';
import { NoticeItem } from '../model/Models';
import { EMPTY_NOTICE } from '../model/Empty';
import { BarTitle, EmptyTip, LoadingTip, TagChip } from './common/UiKit';
import { BackButton } from './common/BackButton';
import { WallpaperFill } from './common/WallpaperFill';
import { MaterialCard } from './common/MaterialCard';

@Component
export struct NoticePage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('barStyle') barStyle: string = 'new';
  @StorageProp('immersiveEffect') immersiveEffect: boolean = true;
  @StorageProp('subtitleColor') subtitleColor: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 响应式依赖：玻璃/灰字设置变化时触发本页重渲染（取值经 GlassMaterial 静态方法读取） */
  @StorageProp('glassStrength') glassStrength: number = 70;
  @StorageProp('cardMaterial') cardMaterial: boolean = false;
  @StorageProp('grayTextMode') grayTextMode: string = 'default';
  @StorageProp('grayTextColor') grayTextColor: string = '';
  @State notices: NoticeItem[] = [];
  @State loading: boolean = true;

  /** 页面出现：加载通知公告 */
  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    // 先用缓存秒开
    const cached: NoticeItem[] = JwApi.loadCachedNotices();
    if (cached.length > 0) {
      this.notices = cached;
      this.loading = false;
    }
    try {
      this.notices = await JwApi.getNotices();
    } catch (e) {
      // 网络异常时保持缓存
    }
    this.loading = false;
  }

  /** 未读通知数量 */
  private unreadCount(): number {
    let n: number = 0;
    for (const item of this.notices) {
      if (!item.read) {
        n++;
      }
    }
    return n;
  }

  /** 打开通知详情弹层 */
  private openDetail(item: NoticeItem): void {
    item.read = true;
    this.notices = this.notices.slice(0);
    AppState.currentNotice = item;
    AppState.stack.pushPath({ name: Const.ROUTE_NOTICE_DETAIL });
  }

  @Builder
  noticeCard(item: NoticeItem) {
    // 材质层位于卡片内部底层、与卡片同尺寸同圆角；原 16vp 内边距→cardPadding、16vp 圆角→cardRadius、
    // 12vp 下间距→cardMargin、整卡点击→cardOnClick（尾随闭包初始化的自定义组件之后不能再链式加属性）。
    MaterialCard({
      cardRadius: 16,
      cardPadding: 16,
      cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
      cardBlur: GlassMaterial.cardBlur(),
      cardBorderW: GlassMaterial.cardBorderWidth(),
      cardBorderC: GlassMaterial.borderColor(),
      cardShadow: GlassMaterial.cardShadowStyle(),
      cardMargin: { bottom: 12 },
      cardOnClick: () => {
        this.openDetail(item);
      }
    }) {
    Column() {
      Row() {
        if (item.isTop) {
          TagChip({ text: '置顶', color: $r('app.color.state_danger'), bg: $r('app.color.bg_chip') })
            .margin({ right: 6 })
        }
        Text(item.source)
          .fontSize(11)
          .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
          .layoutWeight(1)
        if (!item.read) {
          Circle()
            .width(7)
            .height(7)
            .fill($r('app.color.state_danger'))
        }
      }
      .width('100%')

      Text(item.title)
        .fontSize(15)
        .fontWeight(item.read ? FontWeight.Normal : FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 10 })

      Row() {
        Blank()
        Text(item.date)
          .fontSize(11)
          .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    }
  }

  build() {
    NavDestination() {
      // 二级页壁纸底层（无壁纸回 bg_page，不透下层）
      Stack({ alignContent: Alignment.TopStart }) {
        WallpaperFill()
      Column() {
        // 顶栏（两层）：内容(底)/主题渐变(顶)；模糊层已取消
        Stack({ alignContent: Alignment.TopStart }) {
          Column()
            .width('100%')
            .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
            .linearGradient({
              angle: 180,
              colors: Theme.barGradient(this.themeColor, this.barStyle)
            })
            .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, this.immersiveEffect && this.barStyle === 'legacy'))
        Row() {
          BackButton({ onBack: () => { AppState.stack.pop(); } })

          Column() {
            // 统一标题组件
            BarTitle({ title: '消息', subtitle: `教务通知汇总 · 共 ${this.notices.length} 条 · ${this.unreadCount()} 条未读` })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 6 })
          .layoutWeight(1)

          Blank()
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
        .padding({ left: 16, right: 16, bottom: 12, top: this.getUIContext().px2vp(this.topInsetPx) + 12 })
        }
        .width('100%')
        // 顶栏悬浮：正文可滚入其渐变下层透出
        .position({ x: 0, y: 0 })
        .zIndex(2)

        if (this.loading) {
          LoadingTip()
        } else if (this.notices.length === 0) {
          Scroll() {
            Column() {
              EmptyTip({ text: '暂无消息' })
              Text('消息来源: 教务系统 /jwglxt/xtgl/index_cxDbsy.html?flag=1')
                .fontSize(11)
                .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
                .margin({ top: 16, bottom: 24 })
            }
            .width('100%')
            .padding({ top: this.getUIContext().px2vp(this.topInsetPx) + 68, left: 16, right: 16 })
          }
        } else {
          Scroll() {
            Column() {
              ForEach(this.notices, (item: NoticeItem) => {
                this.noticeCard(item)
              }, (item: NoticeItem) => `${item.id}-${item.read}`)
              Column()
                .height(this.getUIContext().px2vp(this.bottomInsetPx) + 16)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: this.getUIContext().px2vp(this.topInsetPx) + 68 })
          }
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .layoutWeight(1)
          .align(Alignment.Top)
        }
      }
      .width('100%')
      .height('100%')
      // 全局壁纸：二级页根背景透明，透出主框架底层壁纸（无壁纸时由 MainView 底层纯色兜底）
      .backgroundColor(Color.Transparent)
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.bg_page'))
    .hideTitleBar(true)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
  }
}

/** 消息详情 */
@Component
export struct NoticeDetailPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('barStyle') barStyle: string = 'new';
  @StorageProp('immersiveEffect') immersiveEffect: boolean = true;
  @StorageProp('subtitleColor') subtitleColor: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @State notice: NoticeItem = AppState.currentNotice !== null ? AppState.currentNotice : EMPTY_NOTICE;

  build() {
    NavDestination() {
      // 二级页壁纸底层（无壁纸回 bg_page，不透下层）
      Stack({ alignContent: Alignment.TopStart }) {
        WallpaperFill()
      Column() {
        // 顶栏（两层）：内容(底)/主题渐变(顶)；模糊层已取消
        Stack({ alignContent: Alignment.TopStart }) {
          Column()
            .width('100%')
            .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
            .linearGradient({
              angle: 180,
              colors: Theme.barGradient(this.themeColor, this.barStyle)
            })
            .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, this.immersiveEffect && this.barStyle === 'legacy'))
        Row() {
          BackButton({ onBack: () => { AppState.stack.pop(); } })

          Column() {
            BarTitle({ title: '消息详情' })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 6 })
          .layoutWeight(1)

          Blank()
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
        .padding({ left: 16, right: 16, bottom: 12, top: this.getUIContext().px2vp(this.topInsetPx) + 12 })
        }
        .width('100%')
        // 顶栏悬浮：正文可滚入其渐变下层透出
        .position({ x: 0, y: 0 })
        .zIndex(2)

        Scroll() {
          Column() {
            if (this.notice.id.length > 0) {
              Text(this.notice.title)
                .fontSize(19)
                .fontWeight(FontWeight.Bold)
                .lineHeight(28)
                .fontColor($r('app.color.text_primary'))
                .width('100%')

              Row() {
                Text(this.notice.source)
                  .fontSize(12)
                  .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
                Text('·')
                  .fontSize(12)
                  .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
                  .margin({ left: 6, right: 6 })
                Text(this.notice.date)
                  .fontSize(12)
                  .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
              }
              .width('100%')
              .margin({ top: 12, bottom: 14 })

              Divider()
                .color($r('app.color.divider'))

              // 标题与正文内容完全相同时只显示标题，避免重复
              if (this.notice.content.length > 0 && this.notice.content !== this.notice.title) {
                Text(this.notice.content)
                  .fontSize(14)
                  .lineHeight(26)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')
                  .margin({ top: 16 })
              } else if (this.notice.content.length === 0) {
                Text('暂无详细内容，点击消息查看完整公告。')
                  .fontSize(14)
                  .lineHeight(26)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')
                  .margin({ top: 16 })
              }
            } else {
              EmptyTip({ text: '消息内容不存在' })
            }

            Column()
              .height(this.getUIContext().px2vp(this.bottomInsetPx) + 24)
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: this.getUIContext().px2vp(this.topInsetPx) + 68 })
        }
        .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
        .layoutWeight(1)
        .align(Alignment.Top)
        // 全局壁纸：正文滚动层透明，透出主框架底层壁纸
        .backgroundColor(Color.Transparent)
      }
      .width('100%')
      .height('100%')
      // 全局壁纸：详情页根背景透明，透出主框架底层壁纸
      .backgroundColor(Color.Transparent)
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.bg_page'))
    .hideTitleBar(true)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
  }
}