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
import { AboutPage } from './AboutPage';
import { AcademicPage } from './AcademicPage';
import { ExamPage } from './ExamPage';
import { HomeView } from './HomeView';
import { KxjsPage } from './KxjsPage';
import { MineView } from './MineView';
import { NewsDetailPage } from './NewsDetailPage';
import { NewsPage } from './NewsPage';
import { SearchResultPage } from './SearchResultPage';
import { WebViewPage } from './WebViewPage';
import { NoticeDetailPage, NoticePage } from './NoticePage';
import { PrivacyPage } from './PrivacyPage';
import { ScheduleView } from './ScheduleView';
import { ScoreView } from './ScoreView';

@Component
export struct MainView {
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('themeColor') themeColor: string = 'green';
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
        .fillColor(this.currentIndex === index ? Theme.colorOf(this.themeColor) : '#9AA0A6')
      Text(title)
        .fontSize(10)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentIndex === index ? Theme.colorOf(this.themeColor) : '#9AA0A6')
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
    } else if (name === Const.ROUTE_SEARCH) {
      SearchResultPage()
    } else if (name === Const.ROUTE_WEB_PAGE) {
      WebViewPage()
    }
  }

  build() {
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
        .tabBar(this.tabItem('首页', $r('app.media.home_tab'), 0))

        TabContent() {
          ScheduleView()
        }
        .tabBar(this.tabItem('课程表', $r('app.media.calendar_tab'), 1))

        TabContent() {
          ScoreView()
        }
        .tabBar(this.tabItem('成绩', $r('app.media.search_tab'), 2))

        // 农大新闻（占位页）：位于"成绩"和"我的"之间
        TabContent() {
          NewsPage()
        }
        .tabBar(this.tabItem('农大新闻', $r('app.media.newspaper'), 3))

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
        .tabBar(this.tabItem('我的', $r('app.media.user_tab'), 4))
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
        barBottomMargin: 4 + px2vp(this.bottomInsetPx), // 距屏幕底部尽量小（贴近底部，含小白条安全区）
        adaptToHandedness: true, // 左右手自适应
        lightColor: this.isDarkMode ? '#40FFFFFF' : '#20FFFFFF', // 光效颜色：深色半透白高光 / 浅色低饱和
        systemMaterialEffect: {
          materialType: hdsMaterial.MaterialType.IMMERSIVE, // 沉浸式系统材质（毛玻璃光感）
          materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE // 随系统沉浸光感强弱自适应
        }
      })
      .width('100%')
      .height('100%')
      .onChange((index: number) => {
        this.currentIndex = index;
      })
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.pageMap)
    .width('100%')
    .height('100%')
  }
}
