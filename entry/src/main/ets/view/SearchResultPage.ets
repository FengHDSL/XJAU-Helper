/**
 * 搜索结果页（Navigation 二级页）——左上角"搜索结果"，支持翻页
 * 点击结果 → 跳转 NewsDetailPage 阅读
 */
import { image } from '@kit.ImageKit';
import { NewsApi, SearchItem } from '../api/NewsApi';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { Theme } from '../common/ThemeUtil';

@Component
struct SearchRow {
  @Prop item: SearchItem | null = null;
  @Prop showThumb: boolean = true;
  @State thumb: image.PixelMap | null = null;
  onTap: () => void = () => {};

  aboutToAppear(): void {
    if (this.item !== null && this.item.thumb.length > 0) {
      NewsApi.fetchImage(this.item.thumb).then((pm: image.PixelMap) => {
        this.thumb = pm;
      }).catch(() => {
        this.thumb = null;
      });
    }
  }

  build() {
    Row() {
      if (this.item !== null) {
        if (this.showThumb) {
          if (this.thumb !== null) {
            Image(this.thumb).width(72).height(54).borderRadius(6)
              .objectFit(ImageFit.Cover).margin({ right: 12 })
          } else {
            Column().width(72).height(54).borderRadius(6)
              .backgroundColor($r('app.color.bg_chip')).justifyContent(FlexAlign.Center)
              .margin({ right: 12 })
          }
        }
        Column() {
          Text(this.item.title).fontSize(15).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          // 分类（过长截断，占剩余空间）+ 日期（完整显示，不超出屏幕）
          Row() {
            Text(this.item.category)
              .fontSize(11).fontColor($r('app.color.brand'))
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(this.item.date)
              .fontSize(11).fontColor($r('app.color.text_tertiary'))
              .margin({ left: 8 })
          }
          .width('100%').margin({ top: 6 })
          .alignItems(VerticalAlign.Center)
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => { this.onTap(); })
  }
}

@Component
export struct SearchResultPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @State results: SearchItem[] = [];
  @State loading: boolean = true;
  @State loadingMore: boolean = false;
  @State hasMore: boolean = true;
  private page: number = 1;
  private keyword: string = '';

  aboutToAppear(): void {
    this.keyword = AppState.currentSearchKeyword;
    if (this.keyword.length === 0) {
      this.loading = false;
      return;
    }
    this.loadPage(1, true);
  }

  /** 加载第 page 页；isFirst=true 时替换列表，否则追加 */
  private async loadPage(page: number, isFirst: boolean): Promise<void> {
    if (isFirst) {
      this.loading = true;
    } else {
      this.loadingMore = true;
    }
    try {
      const list: SearchItem[] = await NewsApi.search(this.keyword, page);
      if (isFirst) {
        this.results = list;
      } else {
        const merged: SearchItem[] = this.results.concat(list);
        this.results = merged;
      }
      this.hasMore = list.length > 0;
      this.page = page;
    } catch (e) {
      this.hasMore = false;
    } finally {
      this.loading = false;
      this.loadingMore = false;
    }
  }

  private loadMore(): void {
    if (this.loadingMore || !this.hasMore) { return; }
    this.loadPage(this.page + 1, false);
  }

  /** 打开结果：本站跳详情页，外链用 WebView 打开 */
  private openDetail(item: SearchItem): void {
    if (NewsApi.isLocalUrl(item.url)) {
      AppState.currentNewsUrl = item.url;
      AppState.stack.pushPath({ name: Const.ROUTE_NEWS_DETAIL });
    } else {
      AppState.webUrl = item.url;
      AppState.webTitle = '外部链接';
      AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
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
          Text('搜索结果')
            .fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(this.isDarkMode ? $r('app.color.text_primary') : Color.White)
            .margin({ left: 6 })
          if (this.keyword.length > 0) {
            Text(`"${this.keyword}"`)
              .fontSize(12)
              .fontColor(this.isDarkMode ? $r('app.color.text_tertiary') : '#CCFFFFFF')
              .margin({ left: 8 })
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
        }
        .width('100%').alignItems(VerticalAlign.Center)
        .height(px2vp(this.topInsetPx) + 60)
        .padding({ left: 16, right: 16, bottom: 12, top: px2vp(this.topInsetPx) + 12 })
        .backgroundColor(this.isDarkMode ? '#1A1D1C' : Theme.colorOf(this.themeColor))

        if (this.loading) {
          Column() {
            LoadingProgress().width(32).height(32).color($r('app.color.brand'))
            Text('搜索中').fontSize(12).fontColor($r('app.color.text_tertiary')).margin({ top: 10 })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.results.length === 0) {
          Column() {
            Text('未找到相关新闻').fontSize(14).fontColor($r('app.color.text_tertiary'))
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List() {
            ForEach(this.results, (item: SearchItem, i: number) => {
              ListItem() {
                Column() {
                  // 外链不显示缩略图（本站图才可抓取）
                  SearchRow({
                    item: item,
                    showThumb: NewsApi.isLocalUrl(item.url),
                    onTap: () => { this.openDetail(item); }
                  })
                  if (i < this.results.length - 1) {
                    Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
                  }
                }
              }
            }, (item: SearchItem, i: number) => `${i}`)
            // 底部：加载更多 / 没有更多
            ListItem() {
              Column() {
                if (this.loadingMore) {
                  LoadingProgress().width(24).height(24).color($r('app.color.brand'))
                  Text('加载中').fontSize(11).fontColor($r('app.color.text_tertiary')).margin({ top: 6 })
                } else if (this.hasMore) {
                  Text('上拉加载更多')
                    .fontSize(12).fontColor($r('app.color.text_tertiary'))
                    .padding({ top: 12, bottom: 12 })
                    .onClick(() => { this.loadMore(); })
                } else {
                  Text('— 已加载全部结果 —')
                    .fontSize(11).fontColor($r('app.color.text_tertiary'))
                    .padding({ top: 12, bottom: 12 })
                }
                Column().height(20)
              }
              .width('100%').justifyContent(FlexAlign.Center)
            }
          }
          .width('100%').layoutWeight(1)
          .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
          .onReachEnd(() => { this.loadMore(); })
        }
      }
      .width('100%').height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .hideTitleBar(true)
    .width('100%').height('100%')
  }
}
