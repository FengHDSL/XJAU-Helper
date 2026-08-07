/**
 * 新闻详情页（Navigation 二级页）——左上角"新闻详情"，右上角分享
 */
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { NewsApi, ContentBlock, NewsDetail } from '../api/NewsApi';
import { AppState } from '../common/AppState';
import { Theme } from '../common/ThemeUtil';

@Component
export struct NewsDetailPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @State detail: NewsDetail | null = null;
  @State loading: boolean = true;
  /** 图片 PixelMap，按下标对应 blocks 中 image 块顺序 */
  @State imgPms: (image.PixelMap | null)[] = [];

  aboutToAppear(): void {
    this.loading = true;
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

  /** 分享新闻（标题 + 链接） */
  private async shareNews(): Promise<void> {
    if (this.detail === null) { return; }
    try {
      const shareData = new systemShare.SharedData({
        utd: utd.UniformDataType.PLAIN_TEXT,
        content: `${this.detail.title}\n${AppState.currentNewsUrl}`
      });
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      await controller.show(context, {
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        selectionMode: systemShare.SelectionMode.SINGLE
      });
    } catch (e) {
      promptAction.showToast({ message: '分享失败' });
    }
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('‹')
            .fontSize(26)
            .fontColor(this.isDarkMode ? $r('app.color.text_primary') : Color.White)
            .width(34).height(34).textAlign(TextAlign.Center)
            .onClick(() => { AppState.stack.pop(); })
          Text('新闻详情')
            .fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(this.isDarkMode ? $r('app.color.text_primary') : Color.White)
            .margin({ left: 6 })
            .layoutWeight(1)
          Text('分享')
            .fontSize(13)
            .fontColor(this.isDarkMode ? $r('app.color.text_primary') : Color.White)
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(this.isDarkMode ? $r('app.color.bg_chip') : '#33FFFFFF')
            .borderRadius(14)
            .onClick(() => { this.shareNews(); })
        }
        .width('100%').alignItems(VerticalAlign.Center)
        .padding({ left: 10, right: 16, bottom: 14, top: px2vp(this.topInsetPx) + 10 })
        .backgroundColor(this.isDarkMode ? '#1A1D1C' : Theme.colorOf(this.themeColor))

        if (this.loading) {
          Column() {
            LoadingProgress().width(32).height(32).color($r('app.color.brand'))
            Text('加载中').fontSize(12).fontColor($r('app.color.text_tertiary')).margin({ top: 10 })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.detail === null) {
          Column() {
            Text('加载失败').fontSize(14).fontColor($r('app.color.text_tertiary'))
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          Scroll() {
            Column() {
              Text(this.detail.title)
                .fontSize(20).fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary')).width('100%')
                .margin({ bottom: 12 })

              // 元信息：日期 / 来源 / 浏览量（来源过长自动换行）
              Column() {
                Row() {
                  Text(this.detail.date).fontSize(12).fontColor($r('app.color.text_tertiary'))
                  if (this.detail.views.length > 0) {
                    Text(`  浏览 ${this.detail.views}`).fontSize(12).fontColor($r('app.color.text_tertiary'))
                  }
                }.width('100%')
                if (this.detail.source.length > 0) {
                  Text(`来源：${this.detail.source}`)
                    .fontSize(12).fontColor($r('app.color.text_tertiary'))
                    .width('100%').margin({ top: 4 })
                }
              }
              .width('100%').margin({ bottom: 10 })

              if (this.detail.author.length > 0) {
                Text(`作者：${this.detail.author}`).fontSize(12)
                  .fontColor($r('app.color.text_tertiary')).width('100%').margin({ bottom: 16 })
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
                  .fontSize(12).fontColor($r('app.color.text_tertiary')).width('100%')
              }

              Column().height(40)
            }
            .width('100%').padding({ left: 20, right: 20, top: 12, bottom: 100 })
          }
          .width('100%').layoutWeight(1).scrollBar(BarState.Off)
        }
      }
      .width('100%').height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .hideTitleBar(true)
    .width('100%').height('100%')
  }
}
