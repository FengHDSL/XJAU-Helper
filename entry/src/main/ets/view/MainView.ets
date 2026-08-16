/**
 * 主框架：Navigation（承载二级页面）+ 原生 Tabs 底栏（首页 / 课程表 / 成绩 / 农大新闻 / 我的）
 * HdsTabs（@kit.UIDesignKit Beta）已替换为原生 Tabs：
 *   - barPosition: End + barBackgroundBlurStyle(COMPONENT_THIN) 毛玻璃底栏
 *   - barHeight 含安全区高度，tabItem 内部 padding 避开小白条
 *   - 内容区底部已加 padding，避免底栏遮挡最后一项内容
 * TODO: 悬浮胶囊效果需用 Stack 叠加方案，但当前设备上 Stack+Tabs 渲染异常，暂用全宽底栏
 */
// HdsTabs（@kit.UIDesignKit，API26 Beta）已替换为原生 Tabs + backgroundBlurStyle 悬浮胶囊栏
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
import { NewsFavPage } from './NewsFavPage';
import { NewsPage } from './NewsPage';
import { LogPage } from './LogPage';
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
  private tabsController: TabsController = new TabsController();
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

  /** Tab 按钮：图标 + 文字，选中品牌色、未选中灰（浅色 #9AA0A6 / 深色 #5F6368，随系统深色模式切换） */
  @Builder
  tabItem(title: string, icon: Resource, index: number) {
    Column() {
      Image(icon)
        .width(20)
        .height(20)
        .fillColor(this.currentIndex === index ? Theme.colorOf(this.themeColor) : (this.isDarkMode ? '#5F6368' : '#9AA0A6'))
      Text(title)
        .fontSize(10)
        .fontWeight(this.currentIndex === index ? FontWeight.Medium : FontWeight.Normal)
        .fontColor(this.currentIndex === index ? Theme.colorOf(this.themeColor) : (this.isDarkMode ? '#5F6368' : '#9AA0A6'))
        .margin({ top: 3 })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ bottom: px2vp(this.bottomInsetPx) })
    .onClick(() => {
      if (this.currentIndex !== index) {
        this.currentIndex = index;
        this.tabsController.changeIndex(index);
      }
    })
  }

  /** 空占位 tabBar（Tabs 内置底栏已隐藏，tabBar 仅用于满足 Tabs 结构要求） */
  @Builder
  emptyTabBar() {
    Text('')
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
    }
  }

  build() {
    Navigation(AppState.stack) {
      Tabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.tabsController }) {
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
      .barHeight(50 + px2vp(this.bottomInsetPx))
      .barBackgroundBlurStyle(BlurStyle.COMPONENT_THIN)
      .barBackgroundColor(this.isDarkMode ? '#801F1F1F' : '#80FFFFFF')
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
