/**
 * 主框架：Navigation（承载二级页面）+ HdsTabs 底栏（首页 / 课程表 / 成绩 / 农大新闻 / 我的）
 * 悬浮底栏移植自 HarmonyOS Spatialization 示例
 * （https://gitcode.com/HarmonyOS_Samples/Spatialization）：
 *   - HdsTabs.barFloatingStyle：胶囊悬浮栏（两侧留白 + 底部留白 + 左右手自适应）
 *   - barWidth 与内容卡片宽度对齐（340/420/500），5 个选项间距适中
 *   - systemMaterialEffect: IMMERSIVE/ADAPTIVE 沉浸毛玻璃光感，自动按深浅色反色
 *   - 内容区底部已加 padding，避免悬浮栏遮挡最后一项内容
 *
 * 页面底色：由 `AppearanceStore.pageBackground()` 派生（内置主题色染色；
 * 自定义 hex 需开启「高权限自定义主题色」）——移植自参考项目 miha_hm 的页面底色染色。
 * 新增页面路由：BackgroundCropPage（背景裁剪）/ FontManagePage（字体管理）。
 */
import { HdsTabs, HdsTabsController, hdsMaterial } from '@kit.UIDesignKit';
import { AppState } from '../common/AppState';
import { AppearanceStore } from '../common/AppearanceStore';
import { Const } from '../common/Constants';
import { GlassMaterial } from '../common/GlassMaterial';
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
import { BackgroundCropPage } from './BackgroundCropPage';
import { FontManagePage } from './FontManagePage';
import { GrayAdvancedPage } from './GrayAdvancedPage';
import { NoticeDetailPage, NoticePage } from './NoticePage';
import { PrivacyPage } from './PrivacyPage';
import { TermsPage } from './TermsPage';
import { ScheduleView } from './ScheduleView';
import { ScoreView } from './ScoreView';
import { ChangelogPage } from './ChangelogPage';
import { CourseRawPage } from './CourseRawPage';
import { QuickSelectPage } from './QuickSelectPage';
import { ResponsiveUtil } from '../common/ResponsiveUtil';

@Component
export struct MainView {
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 壁纸蒙版开关（关闭时不叠加可读性遮罩） */
  @StorageProp('wallpaperMask') wallpaperMask: boolean = true;
  @StorageProp('themeColor') themeColor: string = 'green';
  /** 高权限自定义主题色开关（登记依赖：切换后页面底色即时刷新） */
  @StorageProp('customAccentFull') customAccentFull: boolean = false;
  /** 页面背景色（广播键）：沾色/主题/深色/高权限开关变化时由 AppearanceStore.broadcastDerived() 重写 */
  @StorageProp('pageBackground') pageBgBc: string = '';
  @StorageProp('immersiveEffect') immersiveEffect: boolean = false;
  /** 全局壁纸 id（'b1'..'b6' 预置 / 'c:<path>' 自定义 / 'none'=未启用） */
  @StorageProp('wallpaperId') wallpaperId: string = 'none';
  /** 壁纸亮度（自动对比度适配用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  /** 是否 PC 窗口化（非全屏/最大化）：窗口底部无系统安全区，底栏需额外留白 */
  @StorageProp('winFloating') winFloating: boolean = false;
  @State currentIndex: number = 0;
  /** 全局字重响应式订阅：表达式读 this.fwMode 才登记依赖，fwValue 声明即订阅 */
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  /**
   * 底栏高亮专用状态（与页面解耦）：点击 tab 时立即更新（图标/文字即时变色），
   * 页面切换只交给 changeIndex(index) 带动画执行；currentIndex 在 onChange
   * （动画完成）才同步。此前点击直接赋值 currentIndex → HdsTabs 的 index 参数瞬跳，
   * 外观设置的「页面平滑切换」动画被完全绕过（开关无效的根因）。
   */
  @State activeIndex: number = 0;
  /** 主页页面平滑切换（外观设置）：开启后页签切换带页面滑动过渡 */
  @StorageProp('smoothPageSwitch') smoothPageSwitch: boolean = true;
  private tabsController: HdsTabsController = new HdsTabsController();
  onLogout: () => void = () => {
  };
  /** 前往登录页（不退出登录）：由 MineView 退出弹窗触发，向上传给 Index */
  onGotoLogin: () => void = () => {
  };

  /**
   * 悬浮底栏距窗口底部的距离（vp）。
   * - 常规（手机 / 平板 / PC 全屏、最大化）：仅让出系统导航条安全区，尽量贴底；
   * - PC 窗口化（浮动窗口）：窗口底部没有系统安全区，沿用"贴底"会显得过低，
   *   故保底留出 16vp，与全屏观感一致。
   */
  private barBottomMargin(): number {
    const inset: number = this.getUIContext().px2vp(this.bottomInsetPx);
    const base: number = 4 + inset;
    if (ResponsiveUtil.isDesktop() && this.winFloating) {
      return Math.max(base, 16);
    }
    return base;
  }

  /** Tab 序号 → 灰字高级调整页面 key（与 WallpaperPage GRAY_ADV_PAGES 一致） */
  static tabPageKey(index: number): string {
    if (index === 1) {
      return 'schedule';
    }
    if (index === 2) {
      return 'score';
    }
    if (index === 3) {
      return 'news';
    }
    if (index === 4) {
      return 'mine';
    }
    return 'home';
  }

  /** 页面出现：处理桌面卡片点击跳转（AppState.openPageRequest） */
  aboutToAppear(): void {
    // 灰字高级调整：初始活动页 = 当前 Tab（默认首页）
    GlassMaterial.setPageActive(MainView.tabPageKey(this.currentIndex));
    const req: string = AppState.openPageRequest;
    if (req.length === 0) {
      return;
    }
    // 先切到首页 Tab（无论哪种 open，都以此为入口）
    if (this.currentIndex !== 0) {
      this.currentIndex = 0;
      this.activeIndex = 0;
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

  /** Tab 按钮：图标 + 文字，选中品牌色、未选中灰（高亮读 activeIndex：点击即时变色，与页面动画解耦） */
  @Builder
  tabItem(title: string, icon: Resource, index: number) {
    Column() {
      Image(icon)
        .width(20)
        .height(20)
        .fillColor(this.activeIndex === index ? Theme.colorOf(this.themeColor) : WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
      Text(title)
        .fontSize(10)
        .fontWeight(this.fwMode === 'follow' ? (this.activeIndex === index ? FontWeight.Medium : FontWeight.Normal) : AppearanceStore.fontWeight(this.activeIndex === index ? FontWeight.Medium : FontWeight.Normal))
        .fontColor(this.activeIndex === index ? Theme.colorOf(this.themeColor) : (this.isDarkMode ? '#FFFFFF' : '#000000'))
        .margin({ top: 3 })
    }
    .width('100%')
    .height('46vp')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      // 高亮即时更新（activeIndex），页面切换只走 changeIndex(index) 带动画：
      // 直接赋值 currentIndex 会让 HdsTabs 的 index 参数瞬跳、绕过平滑切换动画（勿回退）。
      // 关闭平滑开关时 animationDuration(0)，changeIndex 瞬跳、行为不变。
      if (this.activeIndex !== index) {
        this.activeIndex = index;
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
    } else if (name === Const.ROUTE_TERMS) {
      TermsPage()
    } else if (name === Const.ROUTE_ABOUT) {
      AboutPage()
    } else if (name === Const.ROUTE_CHANGELOG) {
      ChangelogPage()
    } else if (name === Const.ROUTE_COURSE_RAW) {
      CourseRawPage()
    } else if (name === Const.ROUTE_QUICK_SELECT) {
      QuickSelectPage()
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
    } else if (name === Const.ROUTE_BG_CROP) {
      BackgroundCropPage()
    } else if (name === Const.ROUTE_FONT_MANAGE) {
      FontManagePage()
    } else if (name === Const.ROUTE_GRAY_ADV) {
      GrayAdvancedPage()
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
      // 页面底色：无壁纸时的默认底色（五个 Tab 页根背景已透明，由本层兜底）。
      // 底色经 AppearanceStore 派生：内置主题色始终染色；自定义 hex 需开启「高权限自定义主题色」。
      // 走广播键订阅：开关/主题/深色变化时即时刷新（广播未写入前回落静态派生兜底）。
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.pageBgBc.length > 0
          ? this.pageBgBc
          : AppearanceStore.pageBackground(this.isDarkMode, this.themeColor))
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
                // 同 tabItem 点击：高亮即时更新，切换走 changeIndex(index) 带动画
                // （直接赋值 currentIndex 会瞬跳、绕过平滑切换动画）
                if (this.activeIndex !== index) {
                  this.activeIndex = index;
                  this.tabsController.changeIndex(index);
                }
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
        .scrollable(this.smoothPageSwitch)
        .animationDuration(this.smoothPageSwitch ? 240 : 0) // 平滑切换：开启时页面滑动过渡（移植自参考项目）
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
          barBottomMargin: this.barBottomMargin(), // 距屏幕底部（PC 窗口化时自动多留白，见方法注释）
          adaptToHandedness: true, // 左右手自适应
          // 光效颜色跟随主题色（点光源与主题色一致）
          lightColor: Theme.rgba(Theme.colorOf(this.themeColor), this.isDarkMode ? 0.40 : 0.28),
          systemMaterialEffect: {
            // 底栏沉浸光感固定开启（不受外观设置开关影响）
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
          // 瞬时切换（无淡入淡出）：避免整页透明度 0→1 造成切换闪烁。
          // onChange 在切换（含滑动）完成后触发：currentIndex 同步给 HdsTabs 的 index 参数，
          // activeIndex 同步让底栏高亮跟上手势滑动（点击路径已在 onClick 里先行更新）。
          this.currentIndex = index;
          this.activeIndex = index;
          // 灰字高级调整：同步活动页面 key（常驻 Tab 页的每页单独灰字色随切换生效）
          GlassMaterial.setPageActive(MainView.tabPageKey(index));
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
