/**
 * 新闻详情页（Navigation 二级页）——左上角"新闻详情"，右上角收藏 + 分享，支持下拉刷新
 */
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { NewsApi, ContentBlock, NewsDetail, NewsItem } from '../api/NewsApi';
import { AppState } from '../common/AppState';
import { DataStore } from '../common/DataStore';
import { Theme } from '../common/ThemeUtil';
import { WallpaperTone } from '../common/WallpaperTone';
import { Immersive } from './common/Immersive';
import { GlassMaterial } from '../common/GlassMaterial';
import { MaterialCard } from './common/MaterialCard';
import { BackButton } from './common/BackButton';
import { WallpaperFill } from './common/WallpaperFill';
import { AppearanceStore } from '../common/AppearanceStore';

@Component
export struct NewsDetailPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  /** 灰字广播订阅：颜色表达式需传 this.grayTick 才登记响应式依赖（否则改色不实时刷新） */
  @StorageProp('grayTick') grayTick: number = 0;
  /** 全局字重响应式订阅：表达式读 this.fwMode 才登记依赖，fwValue 声明即订阅 */
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  /** 响应式依赖：玻璃/灰字设置变化时触发本页重渲染（取值经 GlassMaterial 静态方法读取） */
  @StorageProp('glassStrength') glassStrength: number = 70;
  @StorageProp('cardMaterial') cardMaterial: boolean = false;
  @StorageProp('grayTextMode') grayTextMode: string = 'default';
  @StorageProp('grayTextColor') grayTextColor: string = '';
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('barStyle') barStyle: string = 'new';
  @StorageProp('immersiveEffect') immersiveEffect: boolean = false;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 壁纸亮度（顶栏文字自适应用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  @State detail: NewsDetail | null = null;
  @State loading: boolean = true;
  /** 下拉刷新中 */
  @State refreshing: boolean = false;
  /** 是否已收藏（按当前 url 判断） */
  @State faved: boolean = false;
  /** 图片 PixelMap，按下标对应 blocks 中 image 块顺序 */
  @State imgPms: (image.PixelMap | null)[] = [];

  aboutToAppear(): void {
    this.faved = DataStore.isNewsFav(AppState.currentNewsUrl);
    this.loadData();
  }

  /** 加载/刷新详情（重设 loading，重新抓取 + 重新加载图片） */
  private loadData(): void {
    this.loading = true;
    this.imgPms = [];
    const url: string = AppState.currentNewsUrl;
    if (url.length > 0) {
      NewsApi.fetchDetailByUrl(url).then((d: NewsDetail) => {
        this.detail = d;
        this.loading = false;
        this.loadImages(d);
      }).catch(() => {
        this.loading = false;
      });
    } else {
      this.loading = false;
    }
  }

  /** 下拉刷新：仅刷新详情正文（图片保留，不重设全屏 loading） */
  private refreshData(): void {
    const url: string = AppState.currentNewsUrl;
    if (url.length === 0) {
      this.refreshing = false;
      return;
    }
    NewsApi.fetchDetailByUrl(url).then((d: NewsDetail) => {
      this.detail = d;
      this.refreshing = false;
      this.loadImages(d);
    }).catch(() => {
      this.refreshing = false;
      this.getUIContext().getPromptAction().showToast({ message: '刷新失败，请检查网络' });
    });
  }

  private async loadImages(d: NewsDetail): Promise<void> {
    let idx: number = 0;
    for (let i = 0; i < d.blocks.length; i++) {
      if (d.blocks[i].type === 'image') {
        const url: string = d.blocks[i].value;
        try {
          const pm: image.PixelMap = await NewsApi.fetchImage(url);
          this.imgPms[idx] = pm;
        } catch (e) {
          this.imgPms[idx] = null;
        }
        idx++;
        this.imgPms = this.imgPms.slice();
      }
    }
  }

  private imgIndexOf(i: number): number {
    let c: number = 0;
    for (let j = 0; j < i; j++) {
      if (this.detail !== null && this.detail.blocks[j].type === 'image') {
        c++;
      }
    }
    return c;
  }

  /** 加入收藏 / 取消收藏（写入 DataStore，按钮文案与颜色联动） */
  private toggleFav(): void {
    const url: string = AppState.currentNewsUrl;
    if (url.length === 0) {
      return;
    }
    if (this.faved) {
      DataStore.removeNewsFav(url);
      this.faved = false;
      this.getUIContext().getPromptAction().showToast({ message: '已取消收藏' });
    } else {
      const item: NewsItem = new NewsItem();
      if (this.detail !== null) {
        item.title = this.detail.title;
        item.date = this.detail.date;
      } else {
        item.title = '新闻';
      }
      item.url = url;
      item.thumb = '';
      DataStore.addNewsFav(JSON.stringify(item));
      this.faved = true;
      this.getUIContext().getPromptAction().showToast({ message: '已加入收藏' });
    }
  }

  /** 分享新闻（标题 + 链接） */
  private async shareNews(): Promise<void> {
    if (this.detail === null) { return; }
    try {
      const shareData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: `${this.detail.title}\n${AppState.currentNewsUrl}`
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      const context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await controller.show(context, {
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '分享失败' });
    }
  }

  build() {
    NavDestination() {
  /** 顶部装饰层（背景为整页纯色底，见根 Stack） */
  Stack({ alignContent: Alignment.TopStart }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.bg_page'))
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
          Text('新闻详情')
            .fontSize(18).fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
            .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
            .margin({ left: 6 })
            .layoutWeight(1)
          // 右上角：加入收藏 / 取消收藏（分享按钮左边）
          // 统一按钮质感（同返回按钮：白玻璃底 + 细亮边 + 微阴影 + 磨砂）；收藏态保留主题色实底以示激活
          Text(this.faved ? '取消收藏' : '收藏')
            .fontSize(13)
            .fontColor(this.faved ? Color.White : WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
            .height(34)
            .padding({ left: 14, right: 14 })
            .backgroundColor(this.faved ? Theme.colorOf(this.themeColor) :
              (this.isDarkMode ? 'rgba(255,255,255,0.16)' : 'rgba(255,255,255,0.24)'))
            .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, this.immersiveEffect))
            .border({ width: 1, color: 'rgba(255,255,255,0.28)' })
            .shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
            .borderRadius(17)
            .textAlign(TextAlign.Center)
            .onClick(() => { this.toggleFav(); })
          Text('分享')
            .fontSize(13)
            .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
            .height(34)
            .padding({ left: 14, right: 14 })
            .backgroundColor(this.isDarkMode ? 'rgba(255,255,255,0.16)' : 'rgba(255,255,255,0.24)')
            .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, this.immersiveEffect))
            .border({ width: 1, color: 'rgba(255,255,255,0.28)' })
            .shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
            .borderRadius(17)
            .textAlign(TextAlign.Center)
            .margin({ left: 8 })
            .onClick(() => { this.shareNews(); })
        }
        .width('100%').alignItems(VerticalAlign.Center)
        .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
        .padding({ left: 16, right: 16, bottom: 12, top: this.getUIContext().px2vp(this.topInsetPx) + 12 })
        }
        .width('100%')
        // 顶栏悬浮：正文上滑可滚入其渐变下层透出
        .position({ x: 0, y: 0 })
        .zIndex(2)

        if (this.loading) {
          Column() {
            LoadingProgress().width(32).height(32).color(Theme.colorOf(this.themeColor))
            Text('加载中').fontSize(12).fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick)).margin({ top: 10 })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.detail === null) {
          Column() {
            Text('加载失败').fontSize(14).fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          // 下拉刷新：Refresh 包 Scroll
          Refresh({ refreshing: $$this.refreshing }) {
            Scroll() {
              Column() {
                // 顶栏让位（悬浮顶栏之下才开始正文卡片）
                Column()
                  .width('100%')
                  .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
                // 标题 + 正文卡片背景（便于预读；沉浸光感开启时为玻璃卡）
                MaterialCard({
                  cardRadius: 16,
                  cardPadding: 16,
                  cardMargin: { left: 14, right: 14, bottom: 40 },
                  cardAlignItems: ItemAlign.Start,
                  cardBg: $r('app.color.bg_card'),
                  cardBlur: GlassMaterial.bgBlur(this.immersiveEffect),
                  cardBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
                  cardBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent
                }) {
                  Column() {
                    Text(this.detail.title)
                  .fontSize(20).fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
                  .fontColor($r('app.color.text_primary')).width('100%')
                  .margin({ bottom: 12 })

                // 元信息：日期 / 来源 / 浏览量（来源过长自动换行）
                Column() {
                  Row() {
                    Text(this.detail.date).fontSize(12).fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                    if (this.detail.views.length > 0) {
                      Text(`  浏览 ${this.detail.views}`).fontSize(12).fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                    }
                  }.width('100%')
                  if (this.detail.source.length > 0) {
                    Text(`来源: ${this.detail.source}`)
                      .fontSize(12).fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                      .width('100%').margin({ top: 4 })
                  }
                }
                .width('100%').margin({ bottom: 10 })

                if (this.detail.author.length > 0) {
                  Text(`作者: ${this.detail.author}`).fontSize(12)
                    .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick)).width('100%').margin({ bottom: 16 })
                }

                ForEach(this.detail.blocks, (b: ContentBlock, i: number) => {
                  if (b.type === 'image') {
                    if (this.imgPms[this.imgIndexOf(i)] !== null) {
                      Image(this.imgPms[this.imgIndexOf(i)] as image.PixelMap)
                        .width('100%').objectFit(ImageFit.Contain)
                        .borderRadius(8).margin({ top: 8, bottom: 8 })
                    }
                  } else {
                    Text(b.value).fontSize(16).lineHeight(28)
                      .fontColor($r('app.color.text_primary')).width('100%')
                      .margin({ bottom: 10 })
                  }
                }, (b: ContentBlock, i: number) => `${i}`)

                // 编辑 / 审核人
                if (this.detail.editor.length > 0) {
                  Divider().color($r('app.color.divider')).margin({ top: 16, bottom: 12 })
                  Text(this.detail.editor)
                    .fontSize(12).fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick)).width('100%')
                }

                Column().height(20)
                  }
                }
              }
              .width('100%')
            }
            .width('100%').layoutWeight(1).scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
          }
          .width('100%').height('100%')
          .onRefreshing(() => { this.refreshData(); })
        }
      }
      .width('100%').height('100%')
      // 全局壁纸：二级页根背景透明，透出主框架底层壁纸（无壁纸时由 MainView 底层纯色兜底）
      .backgroundColor(Color.Transparent)
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.bg_page'))
    .hideTitleBar(true)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    .width('100%').height('100%')
  }
}
