/**
 * 农大新闻 — 四大板块新闻列表（各自独立懒加载）
 * 点击 → NavPathStack 跳转 NewsDetailPage
 */
import { SheetUtil } from '../common/SheetUtil';
import { image } from '@kit.ImageKit';
import { webview } from '@kit.ArkWeb';
import { promptAction, mediaquery } from '@kit.ArkUI';
import { Theme } from '../common/ThemeUtil';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { NewsApi, NewsItem } from '../api/NewsApi';
import { JwApi } from '../api/JwApi';

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
          // 标题随深浅主题（text_primary）
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
  @StorageProp('barStyle') barStyle: string = 'new';
  /** 调试模式（AppStorage 响应式）：开启后功能浏览模式允许加载新闻 */
  @StorageProp('debugNetwork') @Watch('onDebugNetworkChanged') debugNetwork: boolean = false;
  @State currentTab: number = 0;
  @State showWeb: boolean = false;
  @State keyword: string = '';
  @State refreshing: boolean = false;
  /** 顶栏板块（农大要闻等）是否收起：上滑浏览时隐藏、下滑回顶时展示 */
  @State tabsBarHidden: boolean = false;
  /** 各板块列表上次滚动起始下标（用于判断滚动方向） */
  private lastTabStart: number[] = [0, 0, 0, 0];
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
  private tabs: string[] = ['要闻', '综合', '科研', '媒体'];
  /** 板块切换控制器：自绘板块栏点击 / 列表滑动联动 Tabs 切页 */
  private tabsController: TabsController = new TabsController();
  controller: webview.WebviewController = new webview.WebviewController();
  /** 横屏标记（平板横屏下每个板块新闻分两列显示） */
  @State isLandscape: boolean = false;
  private landscapeListener: mediaquery.MediaQueryListener | null = null;

  aboutToAppear(): void {
    this.listenLandscape();
    this.ensureLoaded(0);
  }

  /** 页面消失：注销横竖屏监听 */
  aboutToDisappear(): void {
    this.landscapeListener = null;
  }

  /** 监听屏幕方向变化（横屏时新闻分两列） */
  private listenLandscape(): void {
    this.isLandscape = mediaquery.matchMediaSync('(orientation: landscape)').matches;
    this.landscapeListener = mediaquery.matchMediaSync('(orientation: landscape)');
    this.landscapeListener.on('change', (res: mediaquery.MediaQueryResult) => {
      this.isLandscape = res.matches;
    });
  }

  /** 调试模式状态变化：功能浏览模式下开启调试 → 强制重新加载当前板块（清列表 + 加载态） */
  private onDebugNetworkChanged(): void {
    if (JwApi.USE_MOCK && this.debugNetwork) {
      for (let i = 0; i < this.loadedTabs.length; i++) {
        this.loadedTabs[i] = false;
      }
      // 清空当前板块列表并直接重新加载（不依赖 ensureLoaded 去重，保证 UI 进入加载态）
      this.lists[this.currentTab] = [];
      this.pendingMore[this.currentTab] = [];
      this.pageIdx[this.currentTab] = 1;
      this.hasMore[this.currentTab] = true;
      this.loadPage(this.currentTab, 1, false);
    }
  }

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

  /** 自绘板块按钮（视觉同原 Tabs bar：选中白胶囊/主题色字；点击/滑动共用 TabsController 切换）。
   *  颜色固定浅色观感，不受深色模式影响（新闻页自身为白字/主题渐变风格） */
  @Builder tabPill(index: number, name: string) {
    Text(name)
      .fontSize(14)
      .fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal)
      // 胶囊板块：未选=黑/白（随深浅）+chip 底；选中=主题色底 + 白字
      .fontColor(this.currentTab === index ? Color.White : $r('app.color.text_primary'))
      .padding({ left: 16, right: 16, top: 6, bottom: 6 })
      .borderRadius(16)
      .backgroundColor(this.currentTab === index ? Theme.colorOf(this.themeColor) : $r('app.color.bg_chip'))
      .margin({ right: 8 })
      .onClick(() => {
        if (this.currentTab !== index) {
          this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
            this.currentTab = index;
          });
          this.tabsController.changeIndex(index);
        }
        this.setTabsHidden(false); // 点击板块：展开板块栏
      })
  }

  @Builder webSheet() {
    Web({ src: AppState.webUrl, controller: this.controller })
      .width('100%').height('100%').javaScriptAccess(true).domStorageAccess(true)
  }

  /** 通用新闻列表（index = 板块下标），支持下拉刷新；
   *  功能浏览模式默认禁用（不加载新闻），调试模式开启后自动加载 */
  @Builder tabNewsList(index: number) {
    if (JwApi.USE_MOCK && !this.debugNetwork) {
      Column() {
        Text('当前模式禁止使用')
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center)
    } else if (this.listLoading[index]) {
      Column() {
        LoadingProgress().width(32).height(32).color(Theme.colorOf(this.themeColor))
        Text('加载中').fontSize(12).fontColor($r('app.color.text_tertiary')).margin({ top: 10 })
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center)
    } else if (this.lists[index].length === 0) {
      Column() {
        Text(this.listLoading[index] ? '加载中' : '暂无新闻')
          .fontSize(14)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center)
      .onAppear(() => {
        // 列表为空：功能浏览+调试模式下强制触发加载（兜底 @Watch/懒加载标记时序问题）
        if (JwApi.USE_MOCK && this.debugNetwork && !this.listLoading[index]) {
          this.pageIdx[index] = 1;
          this.pendingMore[index] = [];
          this.hasMore[index] = true;
          this.loadPage(index, 1, false);
        }
      })
    } else {
      Refresh({ refreshing: $$this.refreshing }) {
        List() {
          // 顶栏占位（随内容滚走）：列表初始从悬浮头（渐变顶栏+透明板块栏）下方开始，上滑后内容进入其下层
          ListItem() {
            Column().width('100%').height(px2vp(this.topInsetPx) + 60 + 44)
          }
          // 横屏：每 ListItem 一行两列新闻；竖屏：单列
          if (this.isLandscape) {
            ForEach(this.newsRowStarts(index), (start: number) => {
              ListItem() {
                Row() {
                  Column() {
                    NewsRow({
                      item: this.lists[index][start],
                      showThumb: index !== 3,
                      onTap: () => { this.openDetail(this.lists[index][start]); }
                    })
                  }
                  .layoutWeight(1)
                  if (start + 1 < this.lists[index].length) {
                    Column() {
                      NewsRow({
                        item: this.lists[index][start + 1],
                        showThumb: index !== 3,
                        onTap: () => { this.openDetail(this.lists[index][start + 1]); }
                      })
                    }
                    .layoutWeight(1)
                  } else {
                    Blank().layoutWeight(1)
                  }
                }
                .width('100%')
              }
            }, (start: number) => `row-${start}`)
          } else {
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
                    Divider().color('#E9EDEB').margin({ left: 16, right: 16 })
                  }
                }
              }
            }, (item: NewsItem) => item.url)
          }
          // 尾部：加载状态 + 数据来源标注 + 空隙（保证最后一条能滚到悬浮底栏上方）
          ListItem() {
            Column() {
              if (this.loadingMore[index]) {
                LoadingProgress().width(22).height(22).color(Theme.colorOf(this.themeColor)).margin({ top: 14 })
                Text('加载中…').fontSize(12).fontColor($r('app.color.text_tertiary')).margin({ top: 6 })
              } else if (!this.hasMore[index]) {
                Text('已加载全部新闻').fontSize(12).fontColor($r('app.color.text_tertiary')).margin({ top: 14 })
              } else {
                Text('上拉加载更多').fontSize(12).fontColor($r('app.color.text_tertiary')).margin({ top: 14 })
              }
              Text('数据来源: 新疆农业大学新闻网')
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
        .onScrollIndex((start: number) => {
          // 方向判定：start 增大 = 上滑浏览（收起板块栏）；start 减小 = 下滑（立即展示）
          const prev: number = this.lastTabStart[index];
          this.lastTabStart[index] = start;
          if (!this.tabsBarHidden && start > prev && start >= 2) {
            this.setTabsHidden(true); // 上滑浏览超过阈值：收起板块栏
          } else if (this.tabsBarHidden && start < prev) {
            this.setTabsHidden(false); // 下滑即展示板块栏（不必滑回顶部）
          }
        })
      }
      .width('100%').height('100%')
      .onRefreshing(() => { this.refreshCurrent(); })
    }
  }

  /** 收起/展开板块栏（带平滑动画） */
  private setTabsHidden(hidden: boolean): void {
    if (this.tabsBarHidden === hidden) {
      return;
    }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
      this.tabsBarHidden = hidden;
    });
  }

  /** 横屏两列：返回每行的起始下标（0,2,4,...） */
  private newsRowStarts(index: number): number[] {
    const arr: NewsItem[] = this.lists[index];
    const res: number[] = [];
    for (let i = 0; i < arr.length; i += 2) {
      res.push(i);
    }
    return res;
  }

  build() {
    Column() {
      // 三层悬浮顶栏：内容(底) / 全透明模糊(中) / 主题渐变(顶)
      Stack({ alignContent: Alignment.TopStart }) {
      // 模糊层已取消（用户要求：内容直接透渐变）
        Column()
          .width('100%')
          .height(px2vp(this.topInsetPx) + 60)
          .linearGradient({
            angle: 180,
            colors: Theme.barGradient(this.themeColor, this.barStyle)
          })
      Row() {
        Text('农大新闻').fontSize(20).fontWeight(FontWeight.Bold).fontColor(Color.White)
        // 搜索框：输入框，回车跳转搜索结果页
        Row() {
          TextInput({ text: this.keyword, placeholder: '搜索新闻' })
            .fontSize(13)
            .fontColor(Color.White)
            .placeholderColor('#CCFFFFFF')
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .height(32)
            .onChange((v: string) => { this.keyword = v; })
            .onSubmit(() => { this.doSearch(); })
        }
        .backgroundColor('#26FFFFFF')
        .borderRadius(16)
        .height(32)
        .layoutWeight(1)
        .margin({ left: 10, right: 10 })
        Text('收藏').fontSize(12).fontColor(Color.White)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor('#33FFFFFF').borderRadius(14)
          .onClick(() => {
            AppState.stack.pushPath({ name: Const.ROUTE_NEWS_FAV });
          })
        Text('网页端').fontSize(12).fontColor(Color.White)
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor('#33FFFFFF').borderRadius(14)
          .margin({ left: 8 })
          .onClick(() => {
            // 功能浏览模式默认禁止；调试模式开启后允许
            if (JwApi.USE_MOCK && !this.debugNetwork) {
              promptAction.showToast({ message: '当前模式禁止使用' });
              return;
            }
            AppState.webUrl = 'https://news.xjau.edu.cn/main.htm';
            AppState.webTitle = '农大新闻 · 网页端';
            AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
          })
      }
      .width('100%').height(px2vp(this.topInsetPx) + 60)
      .padding({ left: 16, right: 16, bottom: 12, top: px2vp(this.topInsetPx) + 12 })
      .alignItems(VerticalAlign.Center)
      }
      // 内容穿透：三层悬浮顶栏（底层内容→中层全透明模糊→顶层主题渐变），不占布局空间
      .width('100%')
      .position({ x: 0, y: 0 })
      .zIndex(2)

      // 板块栏（自绘于 Tabs 外）：收起/展开做「高度折叠 + 淡出」平滑动画；
      // 系统 Tabs bar 固定隐藏，切页由 TabsController 联动（点板块 / 左右滑动均可）。
      Column() {
        // 板块较多时横向滑动（右侧自动裁剪无遮拦），点击/滑动仍联动 TabsController
        Scroll() {
          Row() {
            ForEach(this.tabs, (name: string, index: number) => {
              this.tabPill(index, name)
            }, (name: string) => name)
          }
          .height(44)
          .alignItems(VerticalAlign.Top)
          .padding({ left: 8, right: 8, top: 6 })
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .width('100%')
        .height(44)
      }
      .width('100%')
      .height(this.tabsBarHidden ? 0 : 44)
      .opacity(this.tabsBarHidden ? 0 : 1)
      // 板块栏全透明：直接透过显示底层（壁纸/滚动上来的内容），不加主题渐变
      .backgroundColor(Color.Transparent)
      .clip(true)
      // 内容穿透：悬浮于渐变顶栏正下方（y=顶栏高），不占布局空间
      .position({ x: 0, y: px2vp(this.topInsetPx) + 60 })
      .zIndex(1)

      Tabs({ barPosition: BarPosition.Start, index: this.currentTab, controller: this.tabsController }) {
        ForEach(this.tabs, (name: string, index: number) => {
          TabContent() { this.tabNewsList(index) }
            .onAppear(() => { this.ensureLoaded(index); })
        }, (name: string) => name)
      }
      .vertical(false).barMode(BarMode.Fixed).barWidth('100%')
      .barHeight(0) // 系统 tabBar 已隐藏：板块栏由上方自绘栏承担
      .animationDuration(200)
      .onChange((index: number) => {
        // 左右滑动/点击切页：胶囊选中态随动画淡出淡入（颜色过渡，无跳变）
        this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
          this.currentTab = index;
        });
        this.setTabsHidden(false); // 切换板块：展开板块栏
      })
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%')
    // 跟随全局主题（透明：透出主框架壁纸/底色；深色时随 bg_page 兜底）
    .bindSheet($$this.showWeb, this.webSheet(), {
      width: SheetUtil.sheetWidth(),
      preferType: SheetType.BOTTOM,
      height: SheetSize.LARGE, dragBar: true,
      backgroundColor: $r('app.color.bg_page'), title: { title: '农大新闻 · 网页端' }
    })
  }
}
