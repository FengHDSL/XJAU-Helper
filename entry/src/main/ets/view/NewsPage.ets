/**
 * 农大新闻 — 四大板块新闻列表（各自独立懒加载）
 * 点击 → NavPathStack 跳转 NewsDetailPage
 */
import { SheetUtil } from '../common/SheetUtil';
import { image } from '@kit.ImageKit';
import { webview } from '@kit.ArkWeb';
import { promptAction, mediaquery } from '@kit.ArkUI';
import { ResponsiveUtil } from '../common/ResponsiveUtil';
import { Theme } from '../common/ThemeUtil';
import { WallpaperTone } from '../common/WallpaperTone';
import { Immersive } from './common/Immersive';
import { GlassMaterial } from '../common/GlassMaterial';
import { BarTitle } from './common/UiKit';
import { AppState } from '../common/AppState';
import { DataStore } from '../common/DataStore';
import { Const } from '../common/Constants';
import { NewsApi, NewsItem } from '../api/NewsApi';
import { JwApi } from '../api/JwApi';
// 沉浸光感：顶栏自绘按钮走 MaterialButton（常驻材质），分类标签用 btnTint 保留选中态，
// 半模态弹窗内容走 MaterialSheetPanel（WebSurface/Web 内容弹窗例外，保持 bg_page 不透底）
import { MaterialButton } from './common/MaterialButton';
import { MaterialSheetPanel } from './common/MaterialCard';
import { MaterialCardLayer } from './common/MaterialCarrier';
import { materialAvailable, sheetBlurStyle } from '../common/SystemMaterial';
import { AppearanceStore } from '../common/AppearanceStore';

/** 功能浏览模式虚拟新闻条目（中性示例数据，不联网） */
function mockNews(prefix: string, idx: number, title: string): NewsItem {
  const it: NewsItem = new NewsItem();
  it.title = title;
  it.date = idx <= 2 ? '2026-09-25' : (idx <= 5 ? '2026-09-24' : '2026-09-23');
  // 唯一假 URL 仅作 ForEach key 使用，详情入口已拦截不会真实打开
  it.url = `mock://xjau-news/${prefix}/${idx}`;
  return it;
}

/** 功能浏览模式虚拟新闻数据：4 板块各 8 条（要闻/综合/科研/媒体） */
const MOCK_NEWS: NewsItem[][] = [
  [
    mockNews('yw', 1, '示例新闻：学校召开新学期工作部署会议'),
    mockNews('yw', 2, '示例新闻：学校举行秋季学期开学典礼'),
    mockNews('yw', 3, '示例新闻：校领导带队开展校园安全检查'),
    mockNews('yw', 4, '示例新闻：学校召开人才工作会议'),
    mockNews('yw', 5, '示例新闻：我校与多家单位签署合作协议'),
    mockNews('yw', 6, '示例新闻：学校举办教师节表彰大会'),
    mockNews('yw', 7, '示例新闻：本科教育教学审核评估动员会召开'),
    mockNews('yw', 8, '示例新闻：校领导走访慰问一线教职工'),
  ],
  [
    mockNews('zh', 1, '示例新闻：校园文化艺术节拉开帷幕'),
    mockNews('zh', 2, '示例新闻：学生社团招新活动顺利举行'),
    mockNews('zh', 3, '示例新闻：志愿服务队开展社区服务活动'),
    mockNews('zh', 4, '示例新闻：校园歌手大赛圆满落幕'),
    mockNews('zh', 5, '示例新闻：运动会各项赛事有序进行'),
    mockNews('zh', 6, '示例新闻：图书馆举办读书分享会'),
    mockNews('zh', 7, '示例新闻：创新创业大赛校内选拔结束'),
    mockNews('zh', 8, '示例新闻：食堂满意度调查活动开展'),
  ],
  [
    mockNews('ky', 1, '示例新闻：科研团队在核心期刊发表研究成果'),
    mockNews('ky', 2, '示例新闻：重点实验室顺利通过年度评估'),
    mockNews('ky', 3, '示例新闻：我校获多项自然科学基金立项'),
    mockNews('ky', 4, '示例新闻：研究生学术论坛成功举行'),
    mockNews('ky', 5, '示例新闻：科研平台开放共享仪式举行'),
    mockNews('ky', 6, '示例新闻：校企联合实验室揭牌成立'),
    mockNews('ky', 7, '示例新闻：学术报告周活动安排发布'),
    mockNews('ky', 8, '示例新闻：科研成果转化项目集中签约'),
  ],
  [
    mockNews('mt', 1, '示例新闻：媒体报道我校教育教学改革'),
    mockNews('mt', 2, '示例新闻：媒体聚焦校园文化建设'),
    mockNews('mt', 3, '示例新闻：多家媒体探访实验实训基地'),
    mockNews('mt', 4, '示例新闻：我校师生事迹获媒体关注'),
    mockNews('mt', 5, '示例新闻：媒体报道毕业生就业工作'),
    mockNews('mt', 6, '示例新闻：社会实践团队事迹获报道'),
    mockNews('mt', 7, '示例新闻：媒体关注智慧校园建设'),
    mockNews('mt', 8, '示例新闻：媒体专访优秀校友代表'),
  ],
];

@Component
struct NewsRow {
  @Prop item: NewsItem | null = null;
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 主题色订阅：缩略图占位图标（picture_damage / livephoto_slash）跟随主题色 */
  @StorageProp('themeColor') themeColor: string = 'green';
  /** 全局字重响应式订阅：表达式读 this.fwMode 才登记依赖，fwValue 声明即订阅 */
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  @Prop showThumb: boolean = true;
  /** 缩略图加载失败标记（区分「失败」与「本来就没有图」两种占位） */
  @State thumbFailed: boolean = false;
  @State thumb: image.PixelMap | null = null;
  onTap: () => void = () => {};

  aboutToAppear(): void {
    if (this.showThumb && this.item !== null && this.item.thumb.length > 0) {
      NewsApi.fetchImage(this.item.thumb).then((pm: image.PixelMap) => {
        this.thumb = pm;
      }).catch(() => {
        this.thumb = null;
        this.thumbFailed = true;
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
          } else if (this.thumbFailed) {
            // 加载失败：picture_damage 占位（图标居中、跟随主题色）
            Column() {
              Image($r('app.media.picture_damage'))
                .width(26)
                .height(26)
                .fillColor(Theme.colorOf(this.themeColor))
            }
            .width(72).height(54).borderRadius(6)
            .backgroundColor($r('app.color.bg_chip'))
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .margin({ right: 12 })
          } else {
            // 本来就没有图片：livephoto_slash 占位（图标居中、跟随主题色）
            Column() {
              Image($r('app.media.livephoto_slash'))
                .width(26)
                .height(26)
                .fillColor(Theme.colorOf(this.themeColor))
            }
            .width(72).height(54).borderRadius(6)
            .backgroundColor($r('app.color.bg_chip'))
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .margin({ right: 12 })
          }
        }
        Column() {
          // 标题随深浅主题（text_primary）
          Text(this.item.title).fontSize(15).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor($r('app.color.text_primary')).maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(this.item.date).fontSize(11).fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
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
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('barStyle') barStyle: string = 'new';
  /** 壁纸亮度（顶栏文字自适应用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  /** 沉浸光感：标签胶囊磨砂背景随该开关（与其它按钮质感统一） */
  @StorageProp('immersiveEffect') immersiveEffect: boolean = false;
  /** 灰字覆盖响应（grayTextMode 变化时触发本页重渲染，取值经 GlassMaterial 读取） */
  @StorageProp('grayTextMode') grayTextMode: string = 'default';
  @StorageProp('grayTextColor') grayTextColor: string = '';
  /** 灰字广播依赖登记：根容器 opacity 恒真表达式登记依赖，广播时本页重算灰字色 */
  @StorageProp('grayTick') grayTick: number = 0;
  /** 卡片材质响应（开关变化时触发本页重渲染） */
  @StorageProp('cardMaterial') cardMaterial: boolean = false;
  /** 全局字重响应式订阅：表达式读 this.fwMode 才登记依赖，fwValue 声明即订阅 */
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  /** 调试模式（AppStorage 响应式）：开启后功能浏览模式允许加载新闻 */
  @StorageProp('debugNetwork') @Watch('onDebugNetworkChanged') debugNetwork: boolean = false;
  /** 新闻设置面板显隐 */
  @State showNewsSetting: boolean = false;
  /** 是否获取封面缩略图（设置项，默认开） */
  @StorageProp('newsThumb') newsThumb: boolean = true;
  /** 内容背景大卡片（设置项，默认开）：顶栏下方延伸到屏幕底的材质大卡 */
  @StorageProp('newsBgCard') newsBgCard: boolean = true;
  /** 大卡片存活开关：false 时卸载大卡片分支，80ms 后重新挂载——强制重建组件树，材质随新节点重新下发（偶发不显示的恢复手段，用户要求） */
  @State bgCardAlive: boolean = true;
  @State currentTab: number = 0;
  @State showWeb: boolean = false;
  @State keyword: string = '';
  @State refreshing: boolean = false;
  /** 顶栏板块（农大要闻等）是否收起：上滑浏览时隐藏、下滑回顶时展示 */
  @State tabsBarHidden: boolean = false;
  /** 板块栏视口宽 / 胶囊内容总宽（onAreaChange 实测 vp 值）：内容窄于视口时居中、超宽时左对齐可滚。
   *  不用 minWidth '100%'——横向 Scroll 滚动方向无确定约束，百分比 minWidth 解析不可靠 */
  @State tabViewportW: number = 0;
  @State tabContentW: number = 0;
  /** 背景大卡片基准：根 Stack 实测宽/高（vp）——超屏宽 = 实测宽+32；高 = 卡片恒定高度基准（跟随全程尺寸不变，防每帧重排卡顿） */
  @State bgCardW: number = 0;
  @State bgCardH: number = 0;
  /** 各板块大卡片跟随滚动偏移（vp，0=贴顶）：只驱动 translate.y 平移（渲染级变换，不触发布局），上限=顶栏让位高度 */
  @State bgCardOffsets: number[] = [0, 0, 0, 0, 0];
  /** 各板块 List 滚动控制器：onDidScroll 每帧读绝对偏移用（每板块独立实例，防绑定互相覆盖） */
  private listScrollers: Scroller[] = [
    new Scroller(), new Scroller(), new Scroller(), new Scroller(), new Scroller()
  ];
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
  /** 真实新闻板块（用于 Tabs 内容，避免为"收藏"创建空 TabContent） */
  private newsTabs: string[] = ['要闻', '综合', '科研', '媒体'];
  /** 板块栏标签（最后一项为"收藏"，与其它板块一致：点击或左右滑动均可进入） */
  private tabs: string[] = ['要闻', '综合', '科研', '媒体', '收藏'];
  /** 收藏板块列表（本地读取，滑入该板块时刷新） */
  @State favs: NewsItem[] = [];
  /** 收藏变化信号（AppStorage）：详情页收藏/取消后即时刷新收藏板块 */
  @StorageProp('newsFavVersion') @Watch('onFavVersionChanged') newsFavVersion: number = 0;
  /** 板块切换控制器：自绘板块栏点击 / 列表滑动联动 Tabs 切页 */
  private tabsController: TabsController = new TabsController();
  controller: webview.WebviewController = new webview.WebviewController();
  /** 横屏标记（平板横屏下每个板块新闻分两列显示） */
  @State isLandscape: boolean = false;
  private landscapeListener: mediaquery.MediaQueryListener | null = null;
  /** 窗口宽度断点监听（PC 窗口缩放时切换布局） */
  private wideListener: mediaquery.MediaQueryListener | null = null;
  /** 当前窗口是否横向 / 是否宽 ≥ 600vp（两者组合出布局判定） */
  private landscapeMq: boolean = false;
  private wideMq: boolean = false;

  aboutToAppear(): void {
    this.listenLandscape();
    this.ensureLoaded(0);
  }

  /** 页面消失：注销横竖屏监听 */
  aboutToDisappear(): void {
    this.landscapeListener = null;
    this.wideListener = null;
  }

  /** 监听窗口尺寸/方向变化：窗口缩放或旋转时实时切换布局（判定规则见 ResponsiveUtil） */
  private listenLandscape(): void {
    const mq = this.getUIContext().getMediaQuery();
    this.landscapeMq = mq.matchMediaSync(ResponsiveUtil.QUERY_LANDSCAPE).matches;
    this.wideMq = mq.matchMediaSync(ResponsiveUtil.QUERY_WIDE).matches;
    this.applyLayout();
    this.landscapeListener = mq.matchMediaSync(ResponsiveUtil.QUERY_LANDSCAPE);
    this.landscapeListener.on('change', (res: mediaquery.MediaQueryResult) => {
      this.landscapeMq = res.matches;
      this.applyLayout();
    });
    this.wideListener = mq.matchMediaSync(ResponsiveUtil.QUERY_WIDE);
    this.wideListener.on('change', (res: mediaquery.MediaQueryResult) => {
      this.wideMq = res.matches;
      this.applyLayout();
    });
  }

  /** 组合出布局判定：宽 ≥ 600vp 且横向 → 大屏布局，否则手机端布局（见 ResponsiveUtil.isWideLayout） */
  private applyLayout(): void {
    this.isLandscape = ResponsiveUtil.isWideLayout(this.wideMq, this.landscapeMq);
  }

  /** 调试模式状态变化：功能浏览 ↔ 调试联网切换 → 清空当前板块并按新模式重新加载（虚拟数据 / 真实新闻） */
  private onDebugNetworkChanged(): void {
    if (JwApi.USE_MOCK) {
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
    // 功能浏览模式（不联网）：填充虚拟新闻数据，页面保持完整可浏览的演示态
    if (JwApi.USE_MOCK && !this.debugNetwork) {
      this.lists[index] = MOCK_NEWS[index].slice(0, 10);
      this.pendingMore[index] = [];
      this.hasMore[index] = false;
      this.listLoading[index] = false;
      return;
    }
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

  /** 强制重建大卡片组件树：先卸载再挂载，材质层随新节点重新下发（下拉刷新/新闻设置开关时调用） */
  private rebuildBgCard(): void {
    this.bgCardAlive = false;
    setTimeout(() => {
      this.bgCardAlive = true;
    }, 80);
  }

  /** 下拉刷新当前板块（重置分页从第 1 页重新加载） */
  private async refreshCurrent(): Promise<void> {
    const index: number = this.currentTab;
    // 大卡片刷新重建（用户要求：偶发不显示时下拉刷新即可恢复；mock 短路之前也要执行）
    this.rebuildBgCard();
    // 功能浏览模式：不联网，直接用虚拟数据重灌当前板块（否则 fetchPage 返回 [] 会把列表清空）
    if (JwApi.USE_MOCK && !this.debugNetwork) {
      // 收藏板块（index=4）无虚拟数据：来自本地，无需刷新，直接收尾
      if (index >= 0 && index < MOCK_NEWS.length) {
        this.lists[index] = MOCK_NEWS[index].slice(0, 10);
        this.pendingMore[index] = [];
        this.pageIdx[index] = 1;
        this.hasMore[index] = false;
      }
      this.refreshing = false;
      return;
    }
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
    // 功能浏览模式：虚拟新闻不进入详情（不联网）
    if (JwApi.USE_MOCK && !this.debugNetwork) {
      this.getUIContext().getPromptAction().showToast({ message: '示例数据，暂不支持查看详情' });
      return;
    }
    if (NewsApi.isLocalUrl(item.url)) {
      AppState.currentNewsUrl = item.url;
      AppState.stack.pushPath({ name: Const.ROUTE_NEWS_DETAIL });
    } else {
      AppState.webUrl = item.url;
      AppState.webTitle = '外部链接';
      AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
    }
  }

  /** 收藏变化（详情页收藏/取消）→ 即时刷新收藏板块 */
  private onFavVersionChanged(): void {
    this.reloadFavs();
  }

  /** 收藏板块：从本地读取收藏并解析为 NewsItem（每次滑入该板块刷新） */
  private reloadFavs(): void {
    const raws: string[] = DataStore.loadNewsFavs();
    const list: NewsItem[] = [];
    for (let i = 0; i < raws.length; i++) {
      try {
        const o: Record<string, string> = JSON.parse(raws[i]) as Record<string, string>;
        const it: NewsItem = new NewsItem();
        it.title = o['title'] ?? '';
        it.url = o['url'] ?? '';
        it.date = o['date'] ?? '';
        it.thumb = o['thumb'] ?? '';
        if (it.url.length > 0) {
          list.push(it);
        }
      } catch (e) {
        // ignore：单条解析失败不影响其它
      }
    }
    this.favs = list;
  }

  /** 取消收藏（带确认），成功后刷新收藏板块 */
  private removeFav(item: NewsItem): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '取消收藏',
      message: '确定将该新闻从收藏中移除吗？',
      buttons: [
        { text: '取消', color: '#888888' },
        { text: '取消收藏', color: '#DB5252', primary: true }
      ]
    }).then((res: promptAction.ShowDialogSuccessResponse) => {
      if (res.index === 1) {
        DataStore.removeNewsFav(item.url);
        this.getUIContext().getPromptAction().showToast({ message: '已取消收藏' });
        this.reloadFavs();
      }
    });
  }

  /** 收藏板块列表：可左右滑动进入（无需点击跳转）；左滑可取消收藏，点击进详情 */
  @Builder
  favList() {
    if (this.favs.length === 0) {
      Column() {
        // 悬浮顶栏让位（与其它板块一致，避免内容被渐变顶栏遮挡）
        Column().width('100%').height(this.getUIContext().px2vp(this.topInsetPx) + 60 + 44)
        Text('暂无收藏')
          .fontSize(14)
          .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
        Text('在新闻详情页点击「收藏」即可加入')
          .fontSize(11)
          .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
          .margin({ top: 8 })
        Column().height(this.getUIContext().px2vp(this.bottomInsetPx) + 16)
      }
      .width('100%').height('100%')
      .alignItems(HorizontalAlign.Center)
    } else {
      List({ scroller: this.listScrollers[4] }) {
        ListItem() {
          Column().width('100%').height(this.getUIContext().px2vp(this.topInsetPx) + 60 + 44)
        }
        ForEach(this.favs, (item: NewsItem) => {
          ListItem() {
            Column() {
              NewsRow({
                item: item,
                showThumb: true,
                onTap: () => { this.openDetail(item); }
              })
              Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
            }
          }
          .swipeAction({ end: this.favDeleteBtn(item) })
        }, (item: NewsItem) => item.url)
        ListItem() {
          Column().height(this.getUIContext().px2vp(this.bottomInsetPx) + 120)
        }
      }
      .width('100%').height('100%')
      // 收藏板块大卡片同样跟随滚动（板块序号固定 4，与 listScrollers/bgCardOffsets 分桶对齐）
      .onDidScroll((_offset: number, _state: ScrollState) => { this.syncBgCardOffset(4); })
    }
  }

  /** 收藏项左滑「取消收藏」按钮 */
  @Builder
  favDeleteBtn(item: NewsItem) {
    Text('取消收藏')
      .fontSize(13)
      .fontColor(Color.White)
      .backgroundColor('#DB5252')
      .height('100%')
      .padding({ left: 18, right: 18 })
      .textAlign(TextAlign.Center)
      .onClick(() => {
        this.removeFav(item);
      })
  }

  /**
   * 沉浸光感生效判定（与 WallpaperPage 同款）：全局开关 + 材质可用性。
   * 搜索框承载层是否画材质、外壳是否降级玻璃，都以此为准。
   */
  private matOn(): boolean {
    return this.immersiveEffect && materialAvailable();
  }

  /** 背景大卡片材质判定：固定开启沉浸光感（用户要求，不受全局沉浸开关控制，仅看设备材质能力） */
  private bgMatOn(): boolean {
    return materialAvailable();
  }

  /**
   * 大卡片滚动跟随（用户要求：跟随列表上下滑动、上滑覆盖完屏幕就停止跟随；防卡顿）：
   * onDidScroll 每帧读所在板块 List 的绝对偏移（不用增量累计——回弹/丢帧会漂移），
   * 偏移只驱动 translate.y 平移（渲染级变换，卡片布局尺寸全程恒定→材质层零重排）。
   * 上限=顶栏让位高度：覆盖完屏幕后钳住（列表可无限滑，卡片保持全屏覆盖不再动）。
   */
  private syncBgCardOffset(index: number): void {
    const raw: number = this.listScrollers[index].currentOffset().yOffset;
    const max: number = this.getUIContext().px2vp(this.topInsetPx) + 56;
    const v: number = Math.min(Math.max(raw, 0), max);
    if (this.bgCardOffsets[index] !== v) {
      this.bgCardOffsets[index] = v;
    }
  }

  /** 站内搜索：跳转搜索结果页（原生页面，点击结果进详情） */
  private doSearch(): void {
    const kw: string = this.keyword.trim();
    if (kw.length === 0) { return; }
    AppState.currentSearchKeyword = kw;
    AppState.stack.pushPath({ name: Const.ROUTE_SEARCH });
  }

  /** 自绘板块按钮（视觉同原 Tabs bar：选中主题色/白字；点击/滑动共用 TabsController 切换）。
   *  颜色固定浅色观感，不受深色模式影响（新闻页自身为白字/主题渐变风格）。
   *  → MaterialButton（Toggle 承载层）：选中态改走 btnTint 叠主题色（比例 0.85，承载白字对比度），
   *    未选中比例 0（材质+玻璃胶囊，无色叠层）。不能用实色底——材质生效时底色让出会把选中态吃掉。
   *  原胶囊微阴影随材质统一让出（材质生效即无自绘投影）。 */
  @Builder tabPill(index: number, name: string) {
    MaterialButton({
      btnRadius: 16,
      btnMargin: { right: 8 },
      // 未选中：原玻璃胶囊底（光感关闭回落）；选中：材质生效时 btnTint 叠主题色 0.85；
      // 光感关闭/材质不可用时选中恢复**实色主题底**（用户反馈：关闭光感后选中标签要回到之前的绿底）
      btnBg: (materialAvailable() && this.immersiveEffect) ? GlassMaterial.surface(this.isDarkMode)
        : (this.currentTab === index ? Theme.colorOf(this.themeColor) : GlassMaterial.surface(this.isDarkMode)),
      btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
      btnBorderW: GlassMaterial.borderWidth(),
      btnBorderC: GlassMaterial.borderColor(),
      btnTint: Theme.colorOf(this.themeColor),
      btnTintRatio: this.currentTab === index ? 0.85 : 0,
      btnOnClick: () => {
        // 「收藏」为最后一个板块：与其它板块一致，点击或左右滑动均可进入（不再跳转独立页）
        if (this.currentTab !== index) {
          this.getUIContext().animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
            this.currentTab = index;
          });
          this.tabsController.changeIndex(index);
        }
        this.setTabsHidden(false); // 点击板块：展开板块栏
      }
    }) {
      Text(name)
        .fontSize(14)
        .fontWeight(this.fwMode === 'follow' ? (this.currentTab === index ? FontWeight.Bold : FontWeight.Normal) : AppearanceStore.fontWeight(this.currentTab === index ? FontWeight.Bold : FontWeight.Normal))
        .fontColor(this.currentTab === index ? Color.White
          : WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
        .padding({ left: 16, right: 16, top: 6, bottom: 6 })
    }
  }

  @Builder webSheet() {
    // ⚠ bindSheet 例外（保持 $r('app.color.bg_page') 不透底）：本弹窗内容为 Web 组件（网页端浏览），
    // Web 需要不透明底色渲染，沉浸材质面板对网页无意义且透底会出现白屏闪烁，故不套 MaterialSheetPanel。
    Web({ src: AppState.webUrl, controller: this.controller })
      .width('100%').height('100%').javaScriptAccess(true).domStorageAccess(true)
  }

  /** 新闻设置面板：封面缩略图开关 */
  @Builder newsSettingSheet() {
    // 弹窗内容套 MaterialSheetPanel：材质由 Toggle 承载层渲染；配套硬要求（见 build 的 bindSheet 选项）
    // 是显式 backgroundColor: Color.Transparent（默认白底会把材质整块盖住）。
    // SheetSize.FIT_CONTENT（高度随内容）→ panelFillHeight: false；内边距原样保留。
    MaterialSheetPanel({ panelRadius: 20, panelPadding: 0, panelFillHeight: false, panelTitle: '新闻设置', panelShowClose: true, panelOnClose: (): void => { this.showNewsSetting = false; } }) {
      Column() {
        Row() {
          Column() {
            Text('获取新闻封面缩略图')
              .fontSize(14)
              .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
              .fontColor($r('app.color.text_primary'))
            Text('关闭后列表不再加载封面图片，可节省流量、加快加载')
              .fontSize(11)
              .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.newsThumb })
            .selectedColor(Theme.colorOf(this.themeColor))
            .onChange((on: boolean) => {
              AppStorage.setOrCreate('newsThumb', on);
              DataStore.setNewsThumb(on);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ top: 14 })

        // 内容背景大卡片开关
        Row() {
          Column() {
            Text('内容背景大卡片')
              .fontSize(14)
              .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
              .fontColor($r('app.color.text_primary'))
            Text('新闻列表底部显示一张延伸到屏幕底的大卡片（沉浸光感材质）')
              .fontSize(11)
              .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.newsBgCard })
            .selectedColor(Theme.colorOf(this.themeColor))
            .onChange((on: boolean) => {
              AppStorage.setOrCreate('newsBgCard', on);
              DataStore.setNewsBgCard(on);
              // 开关切换即强制重建大卡片（用户要求：偶发不显示时开关一次即可恢复显示）
              this.rebuildBgCard();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ top: 14 })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 26 })
    }
  }

  /** 通用新闻列表（index = 板块下标），支持下拉刷新；
   *  功能浏览模式展示虚拟示例数据（loadPage 短路填充），调试模式开启后加载真实新闻 */
  @Builder tabNewsList(index: number) {
    if (this.listLoading[index]) {
      Column() {
        LoadingProgress().width(32).height(32).color(Theme.colorOf(this.themeColor))
        Text('加载中').fontSize(12).fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) }).margin({ top: 10 })
      }
      .width('100%').height('100%').justifyContent(FlexAlign.Center)
    } else if (this.lists[index].length === 0) {
      Column() {
        Text(this.listLoading[index] ? '加载中' : '暂无新闻')
          .fontSize(14)
          .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
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
        List({ scroller: this.listScrollers[index] }) {
          // 顶栏占位（随内容滚走）：列表初始从悬浮头（渐变顶栏+透明板块栏）下方开始，上滑后内容进入其下层
          ListItem() {
            Column().width('100%').height(this.getUIContext().px2vp(this.topInsetPx) + 60 + 44)
          }
          // 功能浏览模式：虚拟数据标识
          if (JwApi.USE_MOCK && !this.debugNetwork) {
            ListItem() {
              Text('示例数据 · 功能浏览模式')
                .fontSize(11)
                .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ bottom: 4 })
            }
          }
          // 横屏：每 ListItem 一行两列新闻；竖屏：单列
          if (this.isLandscape) {
            ForEach(this.newsRowStarts(index), (start: number) => {
              ListItem() {
                Row() {
                  Column() {
                    NewsRow({
                      item: this.lists[index][start],
                      showThumb: index !== 3 && this.newsThumb,
                      onTap: () => { this.openDetail(this.lists[index][start]); }
                    })
                  }
                  .layoutWeight(1)
                  if (start + 1 < this.lists[index].length) {
                    Column() {
                      NewsRow({
                        item: this.lists[index][start + 1],
                        showThumb: index !== 3 && this.newsThumb,
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
                    showThumb: index !== 3 && this.newsThumb,
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
                Text('加载中…').fontSize(12).fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) }).margin({ top: 6 })
              } else if (!this.hasMore[index]) {
                Text('已加载全部新闻').fontSize(12).fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) }).margin({ top: 14 })
              } else {
                Text('上拉加载更多').fontSize(12).fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) }).margin({ top: 14 })
              }
              Text('数据来源: 新疆农业大学新闻网')
                .fontSize(11).fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
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
        // 大卡片滚动跟随：每帧同步绝对偏移到 bgCardOffsets[index]（钳制与停驻逻辑见 syncBgCardOffset）
        .onDidScroll((_offset: number, _state: ScrollState) => { this.syncBgCardOffset(index); })
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
    // 根容器改 Stack：内容背景大卡片挂在「根 Stack 首子节点」才是真底层——
    // 此前误放进下方 zIndex(2) 的顶栏悬浮 Stack，跟着顶栏一起盖在了新闻列表上（2026-09-25 修复）
    Stack({ alignContent: Alignment.TopStart }) {
      // 内容背景大卡片（新闻设置可关）：从顶栏下方延伸到屏幕底部；
      // 最小光感卡结构（材质承载层 + 底色层），hitTestBehavior(None) 纯背景不拦截列表滚动/点击。
      if (this.newsBgCard && this.bgCardAlive) {
        // 宽度加大直接超出屏幕（用户要求）：卡片宽 = 屏宽实测+32，translate x=-16 纯绘制左移
        // → 视觉左右各出屏 16，边缘与圆角完全在屏外，形成全宽延伸底板。宽度用根 Stack
        // onAreaChange 实测（百分比无法表达 100%+32）；translate 是渲染级偏移（负值零兼容风险，
        // 不像 position 改布局定位有兼容疑点），不影响布局流，背景卡本就是独立叠层。
        // 材质固定开启（bgMatOn 不看全局沉浸开关）。
        Column() {
          // 顶部占位恒定：初始把材质区顶边让到顶栏下方（占位不随滚动变化——跟随靠整卡平移）
          Row()
            .width('100%')
            .height(this.getUIContext().px2vp(this.topInsetPx) + 56)
          Stack({ alignContent: Alignment.TopStart }) {
            if (this.bgMatOn()) {
              MaterialCardLayer({ layerRadius: 18, layerShadow: false })
            }
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor(this.bgMatOn() ? Color.Transparent
                : GlassMaterial.cardBg($r('app.color.bg_card'), this.isDarkMode))
              .backgroundBlurStyle(this.bgMatOn() ? BlurStyle.NONE : GlassMaterial.cardBlur())
              .border({ width: this.bgMatOn() ? 0 : GlassMaterial.cardBorderWidth(), color: GlassMaterial.borderColor() })
              .clip(true)
          }
          .width('100%')
          .layoutWeight(1)
        }
        .width(this.bgCardW > 0 ? this.bgCardW + 32 : '100%')
        // 恒定高度 = 屏幕高+顶栏让位：跟随全程布局尺寸不变（材质层不重排不重采样，滚动零重排开销），
        // 视觉「实时拉长覆盖屏幕」由 translate.y 平移呈现：offset=0 材质从顶栏下方开始（底边超出屏幕底），
        // offset=顶栏让位 材质恰好全屏覆盖，之后钳住停跟随（syncBgCardOffset）。
        .height(this.bgCardH > 0 ? this.bgCardH + this.getUIContext().px2vp(this.topInsetPx) + 56 : '100%')
        // x 出血保持；y=-偏移为渲染级平移（GPU 合成，不触发布局/材质重算）；
        // 切板块时 currentTab 在 Tabs.onChange 的 animateTo 闭包内赋值，平移跳变自动平滑过渡
        .translate({ x: -16, y: -this.bgCardOffsets[this.currentTab] })
        .hitTestBehavior(HitTestMode.None)
      }
      // 底层大卡片之上的原内容包裹层（原根 Column，内部结构不变）
      Column() {
      // 三层悬浮顶栏：内容(底) / 全透明模糊(中) / 主题渐变(顶)
      Stack({ alignContent: Alignment.TopStart }) {
      // 模糊层已取消（用户要求：内容直接透渐变）
        Column()
          .width('100%')
          .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
          .linearGradient({
            angle: 180,
            colors: Theme.barGradient(this.themeColor, this.barStyle)
          })
          .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, this.immersiveEffect && this.barStyle === 'legacy'))
      Row() {
        BarTitle({ title: '农大新闻' })
        // 搜索框：输入框，回车跳转搜索结果页。
        // 含 TextInput 不能套 MaterialCard（onTouch 写组件态会打断输入焦点）→ Stack 兄弟结构：
        // MaterialCardLayer 纯视觉承载层画沉浸光感（受全局开关控制、layerShadow:false 防成排投影叠暗带），
        // 内容层独立叠上。材质关闭时外壳回落玻璃胶囊（同右侧按钮配色）。
        // 尺寸恢复 32 高/16 圆角胶囊：与设置/网页端按钮同款对齐（9a02ba9 统一输入框时误拉成 48，顶栏里显笨重）。
        Stack() {
          if (this.matOn()) {
            MaterialCardLayer({ layerRadius: 16, layerShadow: false })
          }
          Row() {
            TextInput({ text: this.keyword, placeholder: '搜索新闻' })
              .height(32)
              .enterKeyType(EnterKeyType.Done)
              .fontSize(13)
              .fontWeight(this.fwMode === 'follow' ? FontWeight.Regular : AppearanceStore.fontWeight(FontWeight.Regular))
              .caretStyle({ color: $r('sys.color.font_emphasize') })
              .type(InputType.Normal)
              .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
              .placeholderColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
              .backgroundColor(Color.Transparent)
              .layoutWeight(1)
              .onChange((v: string) => { this.keyword = v; })
              .onSubmit(() => { this.doSearch(); })
          }
          .width('100%')
          .padding({ left: 4, right: 4 })
          .backgroundColor(this.matOn() ? Color.Transparent
            : (this.isDarkMode ? 'rgba(255,255,255,0.16)' : 'rgba(255,255,255,0.24)'))
          .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, !this.matOn() && this.immersiveEffect))
          .borderRadius(16)
          .height(32)
        }
        .height(32)
        .layoutWeight(1)
        .margin({ left: 10, right: 10 })
        .bindSheet($$this.showNewsSetting, this.newsSettingSheet(), {
          height: SheetSize.FIT_CONTENT,
          // 关闭按钮由 MaterialSheetPanel 自绘（沉浸光感），系统 showClose 必须关掉避免双按钮
          showClose: false,
          preferType: SheetType.BOTTOM,
          // 必须显式透明：BindOptions.backgroundColor 默认 Color.White，白底会把 MaterialSheetPanel 的材质整块盖住
          backgroundColor: Color.Transparent,
          blurStyle: sheetBlurStyle()
        })
        // 设置按钮 → MaterialButton（Toggle 承载层，btnPersistent 常驻：不随全局沉浸光感开关关闭而消失；
        // 光感关闭回落原白玻璃胶囊）。原 32 高胶囊由内容 Text height(32) 撑出；微阴影随材质统一让出。
        MaterialButton({
          btnRadius: 16,
          btnPersistent: true,
          btnBg: this.isDarkMode ? 'rgba(255,255,255,0.16)' : 'rgba(255,255,255,0.24)',
          btnBlur: Immersive.blur(BlurStyle.Thin, this.immersiveEffect),
          btnBorderW: 1,
          btnBorderC: 'rgba(255,255,255,0.28)',
          btnOnClick: () => {
            this.showNewsSetting = true;
          }
        }) {
          Text('设置').fontSize(12).fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
            .height(32)
            .textAlign(TextAlign.Center)
            .padding({ left: 14, right: 14 })
        }
        // 网页端按钮 → MaterialButton（同上，btnMargin left 8 保持原间距）
        MaterialButton({
          btnRadius: 16,
          btnPersistent: true,
          btnBg: this.isDarkMode ? 'rgba(255,255,255,0.16)' : 'rgba(255,255,255,0.24)',
          btnBlur: Immersive.blur(BlurStyle.Thin, this.immersiveEffect),
          btnBorderW: 1,
          btnBorderC: 'rgba(255,255,255,0.28)',
          btnMargin: { left: 8 },
          btnOnClick: () => {
            // 功能浏览模式默认禁止；调试模式开启后允许
            if (JwApi.USE_MOCK && !this.debugNetwork) {
              this.getUIContext().getPromptAction().showToast({ message: '当前模式禁止使用' });
              return;
            }
            AppState.webUrl = 'https://news.xjau.edu.cn/main.htm';
            AppState.webTitle = '农大新闻 · 网页端';
            AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
          }
        }) {
          Text('网页端').fontSize(12).fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
            .height(32)
            .textAlign(TextAlign.Center)
            .padding({ left: 14, right: 14 })
        }
      }
      .width('100%').height(this.getUIContext().px2vp(this.topInsetPx) + 60)
      .padding({ left: 16, right: 16, bottom: 12, top: this.getUIContext().px2vp(this.topInsetPx) + 12 })
      .alignItems(VerticalAlign.Top)
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
            // 内层：胶囊内容容器（自适应内容宽），onAreaChange 实测真实内容宽（不受外层 minWidth 影响）
            Row() {
              ForEach(this.tabs, (name: string, index: number) => {
                this.tabPill(index, name)
              }, (name: string) => name)
            }
            .alignItems(VerticalAlign.Top)
            .onAreaChange((_o: Area, n: Area) => {
              // Area.width 类型是 Length（运行时为 vp 数值），需断言成 number
              this.tabContentW = n.width as number;
            })
          }
          .height(44)
          .alignItems(VerticalAlign.Top)
          .padding({ left: 8, right: 8, top: 6 })
          // 内容窄于视口：minWidth 用实测视口宽（数值，无百分比解析歧义）撑满后 Center 居中；
          // 内容超宽：minWidth 不起作用、无富余空间 Center 自动失效，Start 左对齐可正常左滚
          .constraintSize({ minWidth: this.tabViewportW > 0 ? this.tabViewportW : 0 })
          .justifyContent(this.tabContentW < this.tabViewportW ? FlexAlign.Center : FlexAlign.Start)
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .width('100%')
        .height(44)
        .onAreaChange((_o: Area, n: Area) => {
          // Area.width 类型是 Length（运行时为 vp 数值），需断言成 number
          this.tabViewportW = n.width as number;
        })
      }
      .width('100%')
      .height(this.tabsBarHidden ? 0 : 44)
      .opacity(this.tabsBarHidden ? 0 : 1)
      // 板块栏全透明：直接透过显示底层（壁纸/滚动上来的内容），不加主题渐变
      .backgroundColor(Color.Transparent)
      .clip(true)
      // 内容穿透：悬浮于渐变顶栏正下方（y=顶栏高），不占布局空间
      .position({ x: 0, y: this.getUIContext().px2vp(this.topInsetPx) + 60 })
      .zIndex(1)

      Tabs({ barPosition: BarPosition.Start, index: this.currentTab, controller: this.tabsController }) {
        ForEach(this.newsTabs, (name: string, index: number) => {
          TabContent() { this.tabNewsList(index) }
            .onAppear(() => { this.ensureLoaded(index); })
        }, (name: string) => name)
        // 第 5 个板块「收藏」：与其它板块并列，左右滑动即可进入（无需点击跳转）
        TabContent() { this.favList() }
          .onAppear(() => { this.reloadFavs(); })
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
        // 收藏板块（第 5 个）：每次滑入/切页刷新一次（TabContent.onAppear 仅首次触发）
        if (index === 4) {
          this.reloadFavs();
        }
      })
      .layoutWeight(1).width('100%')
    }
    .width('100%').height('100%')
    // 跟随全局主题（透明：透出主框架壁纸/底色；深色时随 bg_page 兜底）
    // ⚠ 此 sheet 例外保持 bg_page 不透底：内容为 Web 组件（网页端），需不透明底渲染（见 webSheet 注释）
    .bindSheet($$this.showWeb, this.webSheet(), {
      width: SheetUtil.sheetWidth(),
      preferType: SheetType.BOTTOM,
      height: SheetSize.LARGE, dragBar: true,
      backgroundColor: $r('app.color.bg_page'), title: { title: '农大新闻 · 网页端' }
    })
    // 灰字广播依赖登记：grayTick 变化触发整页重算 grayTertiary 文本色（恒真不改变视觉）
    .opacity(this.grayTick >= 0 ? 1 : 1)
    }
    // 根 Stack 铺满：底层大卡片 height('100%') 以此为基准解析（直达屏幕底）
    .width('100%')
    .height('100%')
    .onAreaChange((_o: Area, n: Area) => {
      // 实测根 Stack 宽/高：背景大卡片超屏宽 = 宽+32；高 = 卡片恒定高度基准（屏幕高+顶栏让位）
      this.bgCardW = n.width as number;
      this.bgCardH = n.height as number;
    })
  }
}
