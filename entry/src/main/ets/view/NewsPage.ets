/**
 * 农大新闻 — 四大板块新闻列表（各自独立懒加载）
 * 点击 → NavPathStack 跳转 NewsDetailPage
 */
import { image } from '@kit.ImageKit';
import { webview } from '@kit.ArkWeb';
import { Theme } from '../common/ThemeUtil';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { NewsApi, NewsItem } from '../api/NewsApi';

@Component
struct NewsRow {
  @Prop item: NewsItem | null = null;
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
          Text(this.item.date).fontSize(11).fontColor($r('app.color.text_tertiary'))
            .margin({ top: 6 }).width('100%')
        }
        .layoutWeight(1).alignItems(HorizontalAlign.Start)
      }
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .onClick(() => { this.onTap(); })
  }
}

@Component
export struct NewsPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @State currentTab: number = 0;
  @State showWeb: boolean = false;
  @State keyword: string = '';
  @State refreshing: boolean = false;
  /** 每个板块的新闻列表 */
  @State lists: NewsItem[][] = [[], [], [], []];
  /** 每个板块的加载状态 */
  @State listLoading: boolean[] = [false, false, false, false];
  /** 每个板块当前已加载到的官方页页码（1 起） */
  @State pageIdx: number[] = [1, 1, 1, 1];
  /** 每个板块是否还有下一页 */
  @State hasMore: boolean[] = [true, true, true, true];
  /** 每个板块"加载更多"进行中 */
  @State loadingMore: boolean[] = [false, false, false, false];
  /** 官方页每页 14 条，展示每批 10 条后溢出的剩余（跨页补足，不漏新闻） */
  @State pendingMore: NewsItem[][] = [[], [], [], []];
  /** 每个板块是否已加载过（懒加载去重） */
  private loadedTabs: boolean[] = [false, false, false, false];
  private tabs: string[] = ['农大要闻', '综合新闻', '教学科研', '媒体农大'];
  controller: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void { this.ensureLoaded(0); }

  /** 懒加载指定板块（每个板块只加载一次） */
  private ensureLoaded(index: number): void {
    if (this.loadedTabs[index] || this.listLoading[index]) { return; }
    this.loadedTabs[index] = true;
    this.loadPage(index, 1, false);
  }

  /**
   * 加载指定官方页并补足 10 条展示（跨页补足：官方页 14 条，多出的暂存 pendingMore）
   * @param officialPage 官方列表页页码（1 起）
   * @param append 是否追加到现有列表（false = 首次/刷新重置）
   */
  private async loadPage(index: number, officialPage: number, append: boolean): Promise<void> {
    this.listLoading[index] = true;
    try {
      const raw: NewsItem[] = await NewsApi.fetchPage(this.tabs[index], officialPage);
      if (raw.length === 0) {
        this.hasMore[index] = false; // 官方页空 → 到底
        this.listLoading[index] = false;
        return;
      }
      this.pageIdx[index] = officialPage;
      const merged: NewsItem[] = this.pendingMore[index].concat(raw);
      const take: NewsItem[] = merged.slice(0, 10);
      const rest: NewsItem[] = merged.slice(10);
      if (append) {
        this.lists[index] = this.lists[index].concat(take);
      } else {
        this.lists[index] = take;
      }
      this.pendingMore[index] = rest;
    } catch (e) { /* ignore */ }
    this.listLoading[index] = false;
  }

  /** 滚动到底加载下一页 */
  private loadMore(index: number): void {
    if (this.loadingMore[index] || this.listLoading[index] || !this.hasMore[index]) { return; }
    this.loadingMore[index] = true;
    const next: number = this.pageIdx[index] + 1;
    NewsApi.fetchPage(this.tabs[index], next).then((raw: NewsItem[]) => {
      if (raw.length === 0) {
        this.hasMore[index] = false;
      } else {
        this.pageIdx[index] = next;
        const merged: NewsItem[] = this.pendingMore[index].concat(raw);
        const take: NewsItem[] = merged.slice(0, 10);
        const rest: NewsItem[] = merged.slice(10);
        this.lists[index] = this.lists[index].concat(take);
        this.pendingMore[index] = rest;
      }
      this.loadingMore[index] = false;
    }).catch(() => {
      this.loadingMore[index] = false;
    });
  }

  /** 下拉刷新当前板块（重置分页从第 1 页重新加载） */
  private async refreshCurrent(): Promise<void> {
    const index: number = this.currentTab;
    try {
      this.pageIdx[index] = 1;
      this.pendingMore[index] = [];
      this.hasMore[index] = true;
      const raw: NewsItem[] = await NewsApi.fetchPage(this.tabs[index], 1);
      const take: NewsItem[] = raw.slice(0, 10);
      const rest: NewsItem[] = raw.slice(10);
      this.lists[index] = take;
      this.pendingMore[index] = rest;
      this.hasMore[index] = raw.length > 0;
    } catch (e) { /* ignore */ }
    this.refreshing = false;
  }

  /** 打开新闻：本站走详情页，外链用 WebView 打开 */
  private openDetail(item: NewsItem): void {
    if (NewsApi.isLocalUrl(item.url)) {
      AppState.currentNewsUrl = item.url;
      AppState.stack.pushPath({ name: Const.ROUTE_NEWS_DETAIL });
    } else {
      AppState.webUrl = item.url;
      AppState.webTitle = '外部链接';
      AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
    }
  }

  /** 站内搜索：跳转搜索结果页（原生页面，点击结果进详情） */
  private doSearch(): void {
    const kw: string = this.keyword.trim();
    if (kw.length === 0) { return; }
    AppState.currentSearchKeyword = kw;
    AppState.stack.pushPath({ name: Const.ROUTE_SEARCH });
  }

  @Builder tabBar(index: number, name: string) {
    Text(name).fontSize(14)
      .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
      .fontColor(this.currentTab === index ? $r('app.color.brand_on') : $r('app.color.text_primary'))
      .padding({ left: 16, right: 16, top: 7, bottom: 7 }).borderRadius(16)
      .backgroundColor(this.currentTab === index ? $r('app.color.brand') : Color.Transparent)
  }

  @Builder webSheet() {
    Web({ src: AppState.webUrl, controller: this.controller })
      .width('100%').height('100%').javaScriptAccess(true).domStorageAccess(true)
  }

  /** 通用新闻列表（index = 板块下标），支持下拉刷新 */
  @Builder tabNewsList(index: number) {
    if (this.listLoading[index]) {
      Column() {
        LoadingProgress().width(32).height(32).color($r('app.color.brand'))
        Text('加载中').fontSize(12).fontColor($r('app.color.text_tertiary')).margin({ top: 10 })
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center)
    } else if (this.lists[index].length === 0) {
      Column() {
        Text('暂无新闻').fontSize(14).fontColor($r('app.color.text_tertiary'))
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center)
    } else {
      Refresh({ refreshing: $$this.refreshing }) {
        List() {
          ForEach(this.lists[index], (item: NewsItem, i: number) => {
            ListItem() {
              Column() {
                // 媒体农大（index=3）不显示缩略图
                NewsRow({
                  item: item,
                  showThumb: index !== 3,
                  onTap: () => { this.openDetail(item); }
                })
                if (i < this.lists[index].length - 1) {
                  Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
                }
              }
            }
          }, (item: NewsItem) => item.url)
          // 尾部：加载状态 + 数据来源标注 + 空隙（保证最后一条能滚到悬浮底栏上方）
          ListItem() {
            Column() {
              if (this.loadingMore[index]) {
                LoadingProgress().width(22).height(22).color($r('app.color.brand')).margin({ top: 14 })
                Text('加载中…').fontSize(12).fontColor($r('app.color.text_tertiary')).margin({ top: 6 })
              } else if (!this.hasMore[index]) {
                Text('已加载全部新闻').fontSize(12).fontColor($r('app.color.text_tertiary')).margin({ top: 14 })
              } else {
                Text('上拉加载更多').fontSize(12).fontColor($r('app.color.text_tertiary')).margin({ top: 14 })
              }
              Text('数据来源：新疆农业大学新闻网')
                .fontSize(11).fontColor($r('app.color.text_tertiary'))
                .margin({ top: 16 })
              Column().height(120)
            }
            .width('100%').alignItems(HorizontalAlign.Center)
          }
        }
        .width('100%').layoutWeight(1)
        .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
        .onReachEnd(() => { this.loadMore(index); })
      }
      .width('100%').height('100%')
      .onRefreshing(() => { this.refreshCurrent(); })
    }
  }

  build() {
    Column() {
      Row() {
        Text('农大新闻').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White)
        // 搜索框：输入关键词回车，在 WebView 中打开官网搜索结果
        TextInput({ text: this.keyword, placeholder: '搜索新闻' })
          .fontSize(13)
          .fontColor(Color.White)
          .placeholderColor('#CCFFFFFF')
          .backgroundColor('#26FFFFFF')
          .borderRadius(16)
          .height(32)
          .layoutWeight(1)
          .margin({ left: 10, right: 10 })
          .onChange((v: string) => { this.keyword = v; })
          .onSubmit(() => { this.doSearch(); })
        Text('网页端').fontSize(12).fontColor(Color.White)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor('#33FFFFFF').borderRadius(14)
          .onClick(() => {
            AppState.webUrl = 'https://news.xjau.edu.cn/main.htm';
            AppState.webTitle = '农大新闻 · 网页端';
            this.showWeb = true;
          })
      }
      .width('100%').height(px2vp(this.topInsetPx) + 60)
      .padding({ left: 16, right: 16, bottom: 12, top: px2vp(this.topInsetPx) + 12 })
      .backgroundColor(this.isDarkMode ? '#1A1D1C' : Theme.colorOf(this.themeColor))
      .alignItems(VerticalAlign.Center)

      Tabs({ barPosition: BarPosition.Start, index: this.currentTab }) {
        ForEach(this.tabs, (name: string, index: number) => {
          TabContent() { this.tabNewsList(index) }
          .tabBar(this.tabBar(index, name))
          .onAppear(() => { this.ensureLoaded(index); })
        }, (name: string) => name)
      }
      .vertical(false).barMode(BarMode.Fixed).barWidth('100%').barHeight(52)
      .barBackgroundColor($r('app.color.bg_card')).animationDuration(200)
      .onChange((index: number) => { this.currentTab = index; })
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%').backgroundColor($r('app.color.bg_page'))
    .bindSheet($$this.showWeb, this.webSheet(), {
      height: SheetSize.LARGE, dragBar: true,
      backgroundColor: $r('app.color.bg_page'), title: { title: '农大新闻 · 网页端' }
    })
  }
}
