/**
 * 主框架：Navigation（承载二级页面）+ HdsTabs 底栏（首页 / 课程表 / 成绩 / 农大新闻 / 我的）
 * 悬浮底栏移植自 HarmonyOS Spatialization 示例
 * （https://gitcode.com/HarmonyOS_Samples/Spatialization）：
 *   - HdsTabs.barFloatingStyle：胶囊悬浮栏（两侧留白 + 底部留白 + 左右手自适应）
 *   - barWidth 与内容卡片宽度对齐（340/420/500），5 个选项间距适中
 *   - systemMaterialEffect: IMMERSIVE/ADAPTIVE 沉浸毛玻璃光感，自动按深浅色反色
 *   - 内容区底部已加 padding，避免悬浮栏遮挡最后一项内容
 */
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { Theme } from '../common/ThemeUtil';
import { Wallpaper } from '../common/Wallpaper';
import { WallpaperTone } from '../common/WallpaperTone';
import { AboutPage } from './AboutPage';
import { AcademicPage } from './AcademicPage';
import { ExamPage } from './ExamPage';
import { HomeView } from './HomeView';
import { KxjsPage } from './KxjsPage';
import { MineView } from './MineView';
import { NewsDetailPage } from './NewsDetailPage';
import { NewsFavPage } from './NewsFavPage';
import { NewsPage } from './NewsPage';
import { LogPage } from './LogPage';
import { SearchResultPage } from './SearchResultPage';
import { WebViewPage } from './WebViewPage';
import { WallpaperPage } from './WallpaperPage';
import { NoticeDetailPage, NoticePage } from './NoticePage';
import { PrivacyPage } from './PrivacyPage';
import { ScheduleView } from './ScheduleView';
import { ScoreView } from './ScoreView';

@Component
export struct MainView {
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 壁纸蒙版开关（关闭时不叠加可读性遮罩） */
  @StorageProp('wallpaperMask') wallpaperMask: boolean = true;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('immersiveEffect') immersiveEffect: boolean = true;
  /** 全局壁纸 id（'b1'..'b6' 预置 / 'c:<path>' 自定义 / 'none'=未启用） */
  @StorageProp('wallpaperId') wallpaperId: string = 'none';
  /** 壁纸亮度（自动对比度适配用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  @State currentIndex: number = 0;
  private tabsController: HdsTabsController = new HdsTabsController();
  onLogout: () => void = () => {
  };
  /** 前往登录页（不退出登录）：由 MineView 退出弹窗触发，向上传给 Index */
  onGotoLogin: () => void = () => {
  };

  /** 页面出现：处理桌面卡片点击跳转（AppState.openPageRequest） */
  aboutToAppear(): void {
    const req: string = AppState.openPageRequest;
    if (req.length === 0) {
      return;
    }
    // 先切到首页 Tab（无论哪种 open，都以此为入口）
    if (this.currentIndex !== 0) {
      this.currentIndex = 0;
      this.tabsController.changeIndex(0);
    }
    if (req === 'exam-pick') {
      // 跳转到「考试安排」页，ExamPage 内部通过 AppState.pickExam 触发选择弹窗
      AppState.openPageRequest = '';
      AppState.stack.pushPath({ name: Const.ROUTE_EXAM });
    } else {
      // 'home' 或其它：仅回到首页
      AppState.openPageRequest = '';
    }
  }

  /** Tab 按钮：图标 + 文字，选中品牌色、未选中灰 */
  @Builder
  tabItem(title: string, icon: Resource, index: number) {
    Column() {
      Image(icon)
        .width(20)
        .height(20)
        .fillColor(this.currentIndex === index ? Theme.colorOf(this.themeColor) : WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
      Text(title)
        .fontSize(10)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentIndex === index ? Theme.colorOf(this.themeColor) : (this.isDarkMode ? '#FFFFFF' : '#000000'))
        .margin({ top: 3 })
    }
    .width('100%')
    .height('46vp')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      // 点击立即更新选中态（图标/文字颜色即时变化），再切页（滑动动画照常）
      if (this.currentIndex !== index) {
        this.currentIndex = index;
        this.tabsController.changeIndex(index);
      }
    })
  }

  @Builder
  pageMap(name: string) {
    if (name === Const.ROUTE_EXAM) {
      ExamPage()
    } else if (name === Const.ROUTE_NOTICE) {
      NoticePage()
    } else if (name === Const.ROUTE_NOTICE_DETAIL) {
      NoticeDetailPage()
    } else if (name === Const.ROUTE_ACADEMIC) {
      AcademicPage()
    } else if (name === Const.ROUTE_PRIVACY) {
      PrivacyPage()
    } else if (name === Const.ROUTE_ABOUT) {
      AboutPage()
    } else if (name === Const.ROUTE_EMPTY_ROOM) {
      KxjsPage()
    } else if (name === Const.ROUTE_NEWS_DETAIL) {
      NewsDetailPage()
    } else if (name === Const.ROUTE_NEWS_FAV) {
      NewsFavPage()
    } else if (name === Const.ROUTE_LOG) {
      LogPage()
    } else if (name === Const.ROUTE_SEARCH) {
      SearchResultPage()
    } else if (name === Const.ROUTE_WEB_PAGE) {
      WebViewPage()
    } else if (name === Const.ROUTE_WALLPAPER) {
      WallpaperPage()
    }
  }

  /** HDS 材质类型（容错：部分 ROM/HDS 版本可能不提供该枚举） */
  private safeMaterialType(): hdsMaterial.MaterialType {
    try {
      return hdsMaterial.MaterialType.IMMERSIVE;
    } catch (e) {
      return 0 as hdsMaterial.MaterialType;
    }
  }

  /** HDS 材质档位（容错） */
  private safeMaterialLevel(): hdsMaterial.MaterialLevel {
    try {
      return hdsMaterial.MaterialLevel.ADAPTIVE;
    } catch (e) {
      return 0 as hdsMaterial.MaterialLevel;
    }
  }

  build() {
    Stack() {
      // 页面底色：无壁纸时的默认纯色底（五个 Tab 页根背景已透明，由本层兜底）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.bg_page'))
        .hitTestBehavior(HitTestMode.None)
      // 全局壁纸（'none'=未启用不渲染）。壁纸始终清晰显示；
      // 可读性遮罩仅壁纸启用时叠加，避免默认观感变化。
      if (this.wallpaperId.startsWith('c:')) {
        Image(Wallpaper.src(this.wallpaperId))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .hitTestBehavior(HitTestMode.None)
        if (this.wallpaperMask) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.wallpaperTone >= 0
              ? WallpaperTone.overlay(this.wallpaperTone, this.isDarkMode)
              : (this.isDarkMode ? 'rgba(8,10,10,0.38)' : 'rgba(255,255,255,0.18)'))
            .hitTestBehavior(HitTestMode.None)
        }
      }
      Navigation(AppState.stack) {
        HdsTabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.tabsController }) {
          TabContent() {
            HomeView({
              onSwitchTab: (index: number) => {
                this.currentIndex = index;
                this.tabsController.changeIndex(index);
              }
            })
          }
          .tabBar(this.tabItem('首页', $r('app.media.house'), 0))

          TabContent() {
            ScheduleView()
          }
          .tabBar(this.tabItem('课程表', $r('app.media.calendar'), 1))

          TabContent() {
            ScoreView()
          }
          .tabBar(this.tabItem('成绩', $r('app.media.doc_text_badge_magnifyingglass'), 2))

          // 农大新闻（占位页）：位于"成绩"和"我的"之间
          TabContent() {
            NewsPage()
          }
          .tabBar(this.tabItem('农大新闻', $r('app.media.list_square_bill'), 3))

          TabContent() {
            MineView({
              onLogout: () => {
                this.onLogout();
              },
              onGotoLogin: () => {
                this.onGotoLogin();
              }
            })
          }
          .tabBar(this.tabItem('我的', $r('app.media.person'), 4))
        }
        .scrollable(false)
        .animationDuration(220) // 页面切换动画
        .barMode(BarMode.Fixed)
        // 悬浮底栏（自适应长度 + 紧凑高度 + 沉浸光感）
        //  - barWidth 与上方内容卡片宽度对齐（手机约 300vp），5 个选项间距适中
        //  - systemMaterialEffect: IMMERSIVE + ADAPTIVE 沉浸毛玻璃，按系统算力/光感强弱分档适配
        //  - lightColor 为材质光效着色（深色下用浅色高光，浅色下用品牌色低饱和光效），增强光感层次
        //  - barBottomMargin 贴近底部，内容区底部已加 padding 防止遮挡
        .barOverlap(true) // 内容与底栏重叠，由 barFloatingStyle 控制悬浮外观
        .barFloatingStyle({
          barWidth: { smallWidth: 340, mediumWidth: 420, largeWidth: 500 },
          barSideMargin: 12, // 悬浮栏距屏幕左右边缘
          barBottomMargin: 4 + this.getUIContext().px2vp(this.bottomInsetPx), // 距屏幕底部尽量小（贴近底部，含小白条安全区）
          adaptToHandedness: true, // 左右手自适应
          // 光效颜色跟随主题色（点光源与主题色一致）
          lightColor: Theme.rgba(Theme.colorOf(this.themeColor), this.isDarkMode ? 0.40 : 0.28),
          systemMaterialEffect: {
            // 底栏沉浸光感固定开启（不受个性主题开关影响）
            materialType: this.safeMaterialType(),
            materialLevel: this.safeMaterialLevel() // 随系统沉浸光感强弱自适应
          }
        })
        .width('100%')
        .height('100%')
        .onChange((index: number) => {
          if (index === this.currentIndex) {
            return;
          }
          // 瞬时切换（无淡入淡出）：避免整页透明度 0→1 造成切换闪烁
          this.currentIndex = index;
        })
      }
      .hideTitleBar(true)
      .backgroundColor(Color.Transparent)
      .mode(NavigationMode.Stack)
      .navDestination(this.pageMap)
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
