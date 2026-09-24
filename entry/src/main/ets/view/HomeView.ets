/**
 * 首页：学期概览 + 今日课程 + 快捷入口 + 近期考试
 * 头部：简约白卡头像（真实证件照）+ 学号/学院/班级
 *
 * 卡片外观接入（移植自参考项目 miha_hm `components/MaterialCard.ets` + `pages/AppearanceSettingsPage.ets`）：
 *  - 卡片统一用 `MaterialCard` 承载，层级照抄参考：材质承载层在卡片内部、位于内容之下，
 *    材质生效时卡片自身的底色/磨砂/边框/阴影一并让出，因此每张卡片只有一层视觉
 *    （就是沉浸光感材质本身），不会出现「材质盖住卡片」或两层卡片；
 *  - 卡片间距：卡片与卡片之间的间距走 `MaterialCard` 的 `cardMargin`（迁移前挂在卡片自身的 margin），
 *    区块与区块之间的间距仍由外层 Column 的 margin 承载（原样保留）；
 *  - 卡片沾色：材质生效时由 `MaterialCard` 内部在材质**之上**铺一层沾色（材质不采样同 Stack 兄弟节点，
 *    所以沾色必须独立成层），非材质场景由 `cardSurface()` 直接返回沾色底；
 *  - 主题色流光 / 卡片流光触感：由 MaterialCard **内置流光**承担（跟手光斑 + 溢出光晕，
 *    与参考项目 miha_hm 完全同源）；首页曾用页面级流光层（128vp 光斑画在页面根 Stack，
 *    不受卡片圆角裁切导致「范围错误」），已删除统一走卡内流光；
 *  - 卡片内的小卡片 / 小胶囊按钮同样接入材质（对应参考 README「按钮的沉浸光感」）：
 *    成排的快捷入口小卡用 `MaterialCard` + `cardMaterialShadow: false`（挨得近，投影会在卡间叠成暗带）；
 *    胶囊小按钮用公共组件 `MaterialButton`（Toggle 承载层 + 内容，普通 Button 直接挂材质真机不渲染）；
 *    半模态弹窗内容用 `MaterialSheetPanel`，且 `bindSheet` 必须显式 `backgroundColor: Color.Transparent`。
 */
import { SheetUtil } from '../common/SheetUtil';
import { promptAction } from '@kit.ArkUI';
import { mediaquery } from '@kit.ArkUI';
import { JwApi } from '../api/JwApi';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { DataStore } from '../common/DataStore';
import { DateUtil } from '../common/DateUtil';
import { LogStore } from '../common/LogStore';
import { Theme } from '../common/ThemeUtil';
import { WallpaperTone } from '../common/WallpaperTone';
import { Immersive } from './common/Immersive';
// 玻璃质感（GlassMaterial）：按钮=玻璃胶囊 GlassCapsule / 卡片=玻璃卡片 GlassCard
// 卡片容器统一走 MaterialCard（材质承载层在卡片内容之下，见 view/common/MaterialCard.ets）
import { MaterialCard, MaterialSheetPanel } from './common/MaterialCard';
import { materialActive, sheetBlurStyle } from '../common/SystemMaterial';
import { MaterialCardLayer } from './common/MaterialCarrier';
import { MaterialButton } from './common/MaterialButton';
import { AppearanceStore } from '../common/AppearanceStore';
import { GlassMaterial } from '../common/GlassMaterial';
import { CourseItem, ExamItem, NoticeItem, QuickEntry, TermInfo, TodayCourse } from '../model/Models';
import { TeachingCalendar } from '../model/TeachingCalendar';
import { BarTitle, EmptyTip, LoadingTip, SectionHeader, TagChip } from './common/UiKit';
import { WebSurface } from './WebSurface';
import { ResponsiveUtil } from '../common/ResponsiveUtil';

/** 下一次非今日课的预告（首页课程无课时展示） */
interface NextFutureCourse {
  course: CourseItem;
  weekdayLabel: string;
  weekTag: string;
  timeRange: string;
  /** 月日（如 "8月12日"），用于卡片显示具体日期 */
  dateLabel: string;
}

@Component
export struct HomeView {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('barStyle') barStyle: string = 'new';
  @StorageProp('immersiveEffect') immersiveEffect: boolean = false;
  /** 灰字覆盖响应（grayTextMode/grayTextColor 变化时触发本页重渲染，取值经 GlassMaterial 读取） */
  @StorageProp('grayTextMode') grayTextMode: string = 'default';
  @StorageProp('grayTextColor') grayTextColor: string = '';
  /** 灰字广播依赖登记：声明不进表达式=假订阅（实证），根容器 opacity 恒真表达式才真正登记 */
  @StorageProp('grayTick') grayTick: number = 0;
  /** 玻璃档位（weak/mid/strong）：仅用于档位切换时触发本页重渲染（取值经 GlassMaterial 静态方法） */
  @StorageProp('glassLevel') glassLevel: string = 'strong';
  /** 通透程度（0~100 滑条）：材质风格/磨砂与底色透明度联动（实时切换） */
  @StorageProp('glassStrength') glassStrength: number = 70;
  @StorageProp('subtitleColor') subtitleColor: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 壁纸亮度（顶栏文字自适应用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  @StorageLink('showAvatar') showAvatar: boolean = false;
  // ── 移植自参考项目的卡片外观开关（@StorageProp：开关变化即时触发本页重渲染）──
  /** 卡片沾色：卡片底色混入 10% 主题色 */
  @StorageProp('cardTint') cardTint: boolean = false;
  /** 主题色流光 / 卡片流光触感：由 MaterialCard 内部订阅（cardGlowTouch / immersivePressGlow），本页不再跟踪 */
  @State todayCourses: TodayCourse[] = [];
  @State nextClass: TodayCourse | null = null;
  @State exams: ExamItem[] = [];
  @State notices: NoticeItem[] = [];
  @State currentWeek: number = 0;
  @State loading: boolean = true;
  @State photo: string = '';
  @State isLandscape: boolean = false;
  @State teachingCal: TeachingCalendar | null = null;
  /** 日历月份 Swiper 当前页（自绘页码指示器用） */
  @State calPageIndex: number = 0;
  @State jwcNotices: NoticeItem[] = [];
  @State showNoticeSheet: boolean = false;
  @State sheetNotice: NoticeItem | null = null;
  @State showWebSheet: boolean = false;
  // 学期选择（首页顶栏 + 全局设置）
  @State terms: TermInfo[] = [];
  @State selectedTermIndex: number = 0;
  @State showTermSheet: boolean = false;
  // 日历：Swiper 左右滑动查看月份
  @State calDefaultMonth: number = 0;
  // 日历自定义：开学日（按学期存，与课程表共用同一份数据）/ 结束日 / 学期标题（空 = 用校历解析值）
  @State customTermStart: string = '';
  @State customTermEnd: string = '';
  @State customSemesterLabel: string = '';
  @State labelInput: string = '';
  @State showCalEditor: boolean = false;
  /** 全局字重响应式订阅：表达式读 this.fwMode 才登记依赖（静态函数内读 AppStorage 不登记），
   *  fwValue 声明即订阅（custom 模式调数值时触发本页重渲染） */
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  // 课程无课时：随机鼓励文案 + 下次课预告
  @State randomRestText: string = '';
  @State nextFutureCourse: NextFutureCourse | null = null;
  @State refreshing: boolean = false;
  onSwitchTab: (index: number) => void = () => {
  };
  private landscapeListener: mediaquery.MediaQueryListener | null = null;
  /** 窗口宽度断点监听（PC 窗口缩放时切换布局） */
  private wideListener: mediaquery.MediaQueryListener | null = null;
  /** 当前窗口是否横向 / 是否宽 ≥ 600vp（两者组合出布局判定） */
  private landscapeMq: boolean = false;
  private wideMq: boolean = false;

  /**
   * 卡片底色（作为 MaterialCard 的 cardBg 传入）：
   * - 沉浸光感材质生效 → **透明**（让卡片内部承载层的材质来渲染，材质优先级高于原有底色/模糊/边框）；
   * - 卡片沾色开启 → 混入 10% 主题色的卡片底（移植自参考项目「卡片沾色」）；
   * - 光感开启但材质不可用 → 半透明玻璃底（配 cardBlur 出毛玻璃）；
   * - 光感关闭 → 原纯色卡片（可读性优先）。
   *
   * 注：材质生效时 MaterialCard 会把该底色与磨砂一并让出（行内再判一次），
   * 这里返回透明只是保证「非材质分支」与承载层的取值一致。
   */
  private cardSurface(): ResourceColor {
    if (materialActive()) {
      // 材质生效：底色让出；沾色由 MaterialCard 承载层内部的「沾色层」压在材质之上呈现
      return Color.Transparent;
    }
    if (this.cardTint) {
      return AppearanceStore.cardBackground(this.isDarkMode, this.themeColor);
    }
    if (!this.immersiveEffect) {
      return $r('app.color.bg_card');
    }
    return GlassMaterial.cardSurface(this.isDarkMode);
  }

  /** 页面级触摸跟踪已删除：流光统一由 MaterialCard 内置实现（对齐参考项目） */

  /**
   * 卡片底色（作为 MaterialCard 的 cardBg 传入）。
   * 卡片阴影不再单独下发：MaterialCard 的 cardShadow 默认即「无阴影」（与原 cardShadow() 一致）。
   */
  private cardBgColor(): ResourceColor {
    return this.cardSurface();
  }

  /** 卡片内子层（子卡片/子块）底色：光感开启时同步半透明，避免不透明子块挡住毛玻璃 */
  private subBg(orig: ResourceColor): ResourceColor {
    if (!this.immersiveEffect) {
      return orig;
    }
    return GlassMaterial.surface(this.isDarkMode);
  }

  /** 页面出现：加载数据并监听横竖屏 */
  aboutToAppear(): void {
    // 功能浏览模式优先用 AppState.mockCurrentWeek > 0 指定的周次，确保所有功能有数据
    if (AppState.mockCurrentWeek > 0) {
      this.currentWeek = AppState.mockCurrentWeek;
    } else {
      this.currentWeek = DateUtil.weekOfTerm(AppState.term, new Date());
    }
    this.calDefaultMonth = this.computeCurrentMonth();
    this.calPageIndex = this.calInitialIndex();
    this.loadTermCustom();
    this.randomRestText = this.pickRestText();
    this.listenLandscape();
    this.loadData();
  }

  /** 页面消失：注销监听 */
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

  /** 等待冷启动会话恢复完成（AppState.sessionReady；服务大厅登录时 Index 先桥接新教务系统再置 true） */
  private waitSessionReady(): Promise<void> {
    return new Promise<void>((resolve) => {
      if (AppState.sessionReady) {
        resolve();
        return;
      }
      let waited: number = 0;
      const check: () => void = () => {
        waited += 200;
        if (AppState.sessionReady || waited > 15000) {
          resolve();
          return;
        }
        setTimeout(() => {
          check();
        }, 200);
      };
      check();
    });
  }

  private async loadData(): Promise<void> {
    // 冷启动会话恢复中（服务大厅登录：Index 正在用 CASTGC 重新桥接"新教务系统"）：
    // 等待就绪后再取数，避免用旧教务会话导致数据拉取失败（最多等 15s 兜底）
    await this.waitSessionReady();
    // 学期列表（顶栏选择用）
    this.terms = await JwApi.getTerms();
    for (let i: number = 0; i < this.terms.length; i++) {
      if (this.terms[i].id === AppState.term.id) {
        this.selectedTermIndex = i;
        break;
      }
    }
    // 先用本地缓存快速展示（秒开），再后台刷新覆盖
    const cachedCourses: CourseItem[] = JwApi.loadCachedCourses();
    if (cachedCourses.length > 0) {
      this.todayCourses = this.pickToday(cachedCourses);
      this.nextClass = this.firstUnfinished(this.todayCourses);
      this.nextFutureCourse = this.findNextFutureCourse(cachedCourses, AppState.term);
      this.randomRestText = this.pickRestText();
      const cachedExams: ExamItem[] = JwApi.loadCachedExams();
      this.exams = this.pickComingExams(cachedExams);
      this.notices = JwApi.loadCachedNotices().slice(0, 3);
      this.loading = false;
    }
    // 头像：先读缓存，再独立拉取（不依赖课表/考试成功，避免被前面接口失败跳过）
    const cachedPhoto: string = JwApi.loadCachedPhoto();
    if (cachedPhoto.length > 0) {
      this.photo = cachedPhoto;
    }
    // 日志调试：记录本地操作（先用缓存秒开）与实际反馈（网络刷新结果）
    LogStore.log('首页', '消息加载', '开始',
      `缓存课表${cachedCourses.length}节 考试${this.exams.length}门 通知${this.notices.length}条`);
    try {
      const courses: CourseItem[] = await JwApi.getCoursesSmart(AppState.term.id, false);
      this.todayCourses = this.pickToday(courses);
      this.nextClass = this.firstUnfinished(this.todayCourses);
      this.nextFutureCourse = this.findNextFutureCourse(courses, AppState.term);
      this.randomRestText = this.pickRestText();
      const exams: ExamItem[] = await JwApi.getExams(AppState.term.id);
      this.exams = this.pickComingExams(exams);
      const notices: NoticeItem[] = await JwApi.getNotices();
      this.notices = notices.slice(0, 3);
      const cal: TeachingCalendar | null = await JwApi.getTeachingCalendar();
      this.teachingCal = cal;
      // 通知卡：教务处官网「学期校历」最新两条（独立于消息）
      const jn: NoticeItem[] = await JwApi.getJwcNotices();
      if (jn.length > 0) {
        this.jwcNotices = jn;
      }
      LogStore.log('首页', '消息加载', '完成',
        `网络课表${courses.length}节 考试${exams.length}门 通知${notices.length}条 校历${cal !== null ? '有' : '无'} 官网通知${jn.length}条`);
    } catch (e) {
      // 网络异常时保持缓存数据
      LogStore.log('首页', '消息加载', '网络异常', LogStore.errorOf(e as Object));
    }
    // 独立拉取头像（真实模式，不与上面共用一个 try）
    if (!JwApi.USE_MOCK) {
      try {
        const p: string = await JwApi.getPhoto();
        if (p.length > 0) {
          this.photo = p;
        }
      } catch (e) {
        // ignore
      }
    }
    this.loading = false;
  }

  /** 下拉刷新：重新加载首页全部数据 */
  private async onRefresh(): Promise<void> {
    await this.loadData();
    this.refreshing = false;
  }

  /** 今日所在自然月（yyyymm，用于日历默认展示） */
  private computeCurrentMonth(): number {
    const d: Date = new Date();
    return d.getFullYear() * 100 + (d.getMonth() + 1);
  }

  /** 课程无课时随机鼓励文案（三选一） */
  private pickRestText(): string {
    const opts: string[] = ['好好休息吧~', '放松一下吧~', '做自己想做的事吧！'];
    return opts[Math.floor(Math.random() * opts.length)];
  }

  /**
   * 寻找今天之后最近的一节课（用于"无课时下次课预告"）。
   * 1) 当前周 weekday > 今天 weekday（今天的课已全部结束，视为"今天没课了"，从明天起找）
   * 2) 否则后续周 weekday 升序
   */
  private findNextFutureCourse(courses: CourseItem[], term: TermInfo): NextFutureCourse | null {
    const todayW: number = DateUtil.weekdayOf(new Date());
    const cw: number = DateUtil.weekOfTerm(term, new Date());
    const nowMin: number = DateUtil.minutesOfNow();
    // 1) 当前周，今天及之后
    for (let w: number = todayW; w <= 7; w++) {
      for (const c of courses) {
        if (c.weekday === w && c.weeks.includes(cw)) {
          // 今天的课必须还没结束；明天及之后的课直接命中
          if (w === todayW) {
            const e: number = Math.max(1, Math.min(Const.SECTION_COUNT, c.endSection));
            const endMin: number = DateUtil.minutesOf(Const.SECTIONS[e - 1].end);
            if (nowMin > endMin) {
              continue;
            }
          }
          const dt: Date = DateUtil.dateOfWeekDay(term, cw, w);
          return {
            course: c,
            weekdayLabel: Const.WEEK_SHORT[w - 1],
            weekTag: '本周',
            timeRange: DateUtil.sectionRange(c.startSection, c.endSection),
            dateLabel: DateUtil.formatCn(dt)
          };
        }
      }
    }
    for (let wk: number = cw + 1; wk <= term.totalWeeks; wk++) {
      for (let w: number = 1; w <= 7; w++) {
        for (const c of courses) {
          if (c.weekday === w && c.weeks.includes(wk)) {
            const dt: Date = DateUtil.dateOfWeekDay(term, wk, w);
            return {
              course: c,
              weekdayLabel: Const.WEEK_SHORT[w - 1],
              weekTag: `第 ${wk} 周`,
              timeRange: DateUtil.sectionRange(c.startSection, c.endSection),
              dateLabel: DateUtil.formatCn(dt)
            };
          }
        }
      }
    }
    return null;
  }

  /**
   * 切换学期（全局设置）。调用 JwApi.setTerm 同步 JwApi.term + AppState.term + 持久化，
   * 重新拉首页数据（currentWeek/今日/下次课/通知/校历）。其他页（课表/成绩/考试）下次进页时自动按新 term 加载。
   */
  private async selectTerm(index: number): Promise<void> {
    if (index < 0 || index >= this.terms.length || index === this.selectedTermIndex) {
      this.showTermSheet = false;
      return;
    }
    const term: TermInfo = this.terms[index];
    this.selectedTermIndex = index;
    this.showTermSheet = false;
    JwApi.setTerm(term);
    // 全局广播：课程表/成绩页等立即同步切换学期（不依赖下次进页/组件 @Watch）
    AppState.notifyTermSwitched();
    // 刷新增强：完成选择后自动临时切到另一学期再切回（不显示给用户），
    // 强制所有依赖学期缓存的页面完成两轮刷新，确保全局切到与首页一致。
    const tmpIdx: number = index === 0 ? 1 : index - 1;
    if (tmpIdx >= 0 && tmpIdx < this.terms.length && tmpIdx !== index) {
      JwApi.setTerm(this.terms[tmpIdx]);
      AppState.notifyTermSwitched();
      JwApi.setTerm(term);
      AppState.notifyTermSwitched();
    }
    this.currentWeek = DateUtil.weekOfTerm(term, new Date());
    // 学期变更：重新读取该学期的自定义开学日等设置
    this.loadTermCustom();
    // 学期变更：清空旧数据并重新拉取
    this.todayCourses = [];
    this.nextClass = null;
    this.nextFutureCourse = null;
    this.exams = [];
    this.notices = [];
    this.jwcNotices = [];
    this.teachingCal = null;
    this.loading = true;
    await this.loadData();
  }

  /** 从课表中筛选今日课程并按节次排序 */
  private pickToday(courses: CourseItem[]): TodayCourse[] {
    const weekday: number = DateUtil.weekdayOf(new Date());
    const nowMin: number = DateUtil.minutesOfNow();
    const list: TodayCourse[] = [];
    for (const c of courses) {
      if (c.weekday === weekday && c.weeks.includes(this.currentWeek)) {
        const startMin: number = DateUtil.minutesOf(Const.SECTIONS[c.startSection - 1].start);
        const endMin: number = DateUtil.minutesOf(Const.SECTIONS[c.endSection - 1].end);
        list.push({
          course: c,
          timeRange: DateUtil.sectionRange(c.startSection, c.endSection),
          finished: nowMin > endMin,
          ongoing: nowMin >= startMin && nowMin <= endMin
        });
      }
    }
    list.sort((a: TodayCourse, b: TodayCourse) => a.course.startSection - b.course.startSection);
    return list;
  }

  /** 今日最早一节未结束的课程（进行中或尚未开始） */
  private firstUnfinished(list: TodayCourse[]): TodayCourse | null {
    for (const c of list) {
      if (!c.finished) {
        return c;
      }
    }
    return null;
  }

  /** 距离下一节课开始的倒计时文案 */
  private countdownText(item: TodayCourse): string {
    if (item.ongoing) {
      return '进行中';
    }
    const startMin: number = DateUtil.minutesOf(Const.SECTIONS[item.course.startSection - 1].start);
    const diff: number = startMin - DateUtil.minutesOfNow();
    if (diff <= 0) {
      return '即将开始';
    }
    const h: number = Math.floor(diff / 60);
    const m: number = diff % 60;
    if (h <= 0) {
      return `${m} 分钟后`;
    }
    return `${h} 小时${m > 0 ? ` ${m} 分` : ''}后`;
  }

  /** 从考试列表中筛选近期（未来）考试 */
  private pickComingExams(exams: ExamItem[]): ExamItem[] {
    const today: Date = new Date();
    const list: ExamItem[] = [];
    for (const e of exams) {
      if (DateUtil.diffDays(today, DateUtil.parse(e.date)) >= 0) {
        list.push(e);
      }
    }
    list.sort((a: ExamItem, b: ExamItem) => DateUtil.parse(a.date).getTime() - DateUtil.parse(b.date).getTime());
    return list.slice(0, 2);
  }

  /** 根据当前时段返回问候语（早上好/下午好等） */
  private greeting(): string {
    const h: number = new Date().getHours();
    if (h < 6) {
      return '夜深了';
    }
    if (h < 12) {
      return '早上好';
    }
    if (h < 14) {
      return '中午好';
    }
    if (h < 19) {
      return '下午好';
    }
    return '晚上好';
  }

  /** 首页功能入口点击分发（跳转对应页面） */
  private onEntryTap(key: string): void {
    if (key === 'schedule') {
      this.onSwitchTab(1);
    } else if (key === 'score') {
      this.onSwitchTab(2);
    } else if (key === 'exam') {
      AppState.stack.pushPath({ name: Const.ROUTE_EXAM });
    } else if (key === 'academic') {
      AppState.stack.pushPath({ name: Const.ROUTE_ACADEMIC });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '该功能将在接入教务接口后开放' });
    }
  }

  @Builder
  titleBar() {
    // 顶部固定标题栏（三层）：最下内容 → 中全透明模糊层 → 顶主题色渐变
    Stack({ alignContent: Alignment.TopStart }) {
      // 顶：主题色渐变
      Column()
        .width('100%')
        .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
        .linearGradient({
          angle: 180,
          colors: Theme.barGradient(this.themeColor, this.barStyle)
        })
        .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, this.immersiveEffect && this.barStyle === 'legacy'))
    Row() {
      BarTitle({ title: '首页' })
      // 手动重登模式 + 校历为空：标题右侧显示"重登"胶囊（点击执行自动重新登录）
      if (this.shouldShowRelogin()) {
        Text('重登')
          .fontSize(11)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
          .fontColor('#FFFFFF')
          .backgroundColor('#FF9800')
          .height(22)
          .padding({ left: 8, right: 8 })
          .borderRadius(11)
          // 形态与其它顶栏按钮统一（细亮边 + 微阴影），保留橙色警示语义
          .border({ width: 1, color: 'rgba(255,255,255,0.35)' })
          .shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 })
          .margin({ left: 8 })
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onReloginClick();
          })
      }
      Blank()
      // 右侧：当前教学周（未开学显示"未开学"）—— 沉浸光感常驻
      MaterialButton({
        btnRadius: 12,
        btnPersistent: true,
        btnBg: '#33FFFFFF',
        btnBlur: BlurStyle.Thin,
        btnMargin: { right: 8 }
      }) {
        Text(this.isTermStarted() ? `第 ${this.todayTeachingWeek()} 周` : '未开学')
          .fontSize(12)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
          .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      }
      // 右侧：当前学年学期（完整格式，点击展开学期选择，全局设置）—— 沉浸光感常驻
      MaterialButton({
        btnRadius: 14,
        btnPersistent: true,
        btnOnClick: (): void => {
          this.showTermSheet = true;
        }
      }) {
        Row() {
          Text(this.terms.length > 0 && this.selectedTermIndex < this.terms.length
            ? this.terms[this.selectedTermIndex].label
            : AppState.term.label)
            .fontSize(11)
            .fontColor(this.subtitleColor.length > 0 ? this.subtitleColor : WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Image($r('app.media.list_bullet'))
            .width(14)
            .height(14)
            .fillColor(this.subtitleColor.length > 0 ? this.subtitleColor : WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
            .margin({ left: 4 })
        }
        .padding({ left: 10, right: 6, top: 4, bottom: 4 })
      }
    }
    .width('100%')
    .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
    .alignItems(VerticalAlign.Top)
    .padding({ left: 16, right: 16, top: this.getUIContext().px2vp(this.topInsetPx) + 12, bottom: 12 })
    }
    .width('100%')
    // 内容穿透：整个三层标题栏悬浮最上层、不占布局空间，内容可滚入其下层
    .position({ x: 0, y: 0 })
    .zIndex(2)
  }

  /** 学期选择弹层（全局设置）—— 与课程表页 termPickerSheet 完全同构 */
  @Builder
  termPickerSheet() {
    // 弹窗内容套 MaterialSheetPanel：材质由 Toggle 承载层渲染，bindSheet 必须显式透明底（见外层选项）。
    // SheetSize.FIT_CONTENT（高度随内容）→ panelFillHeight: false；内层 20/8/24vp 内边距原样保留。
    MaterialSheetPanel({ panelRadius: 20, panelPadding: 0, panelFillHeight: false, panelShowClose: true, panelOnClose: (): void => { this.showTermSheet = false; } }) {
      Column() {
        if (this.terms.length === 0) {
          Text('暂无可选学期')
            .fontSize(13)
            .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 12 })
        } else {
          ForEach(this.terms, (term: TermInfo, index: number) => {
            Row() {
              Text(term.label)
                .fontSize(14)
                .fontColor(this.selectedTermIndex === index ? $r('app.color.brand_on') : $r('app.color.text_primary'))
                .layoutWeight(1)
              if (this.selectedTermIndex === index) {
                Image($r('app.media.checkmark_circle'))
                  .width(16)
                  .height(16)
                  .fillColor($r('app.color.brand_on'))
              }
            }
            .width('100%')
            .height(46)
            .padding({ left: 16, right: 16 })
            .backgroundColor(this.selectedTermIndex === index ? Theme.colorOf(this.themeColor) : $r('app.color.bg_chip'))
            .borderRadius(10)
            .margin({ bottom: 8 })
            .onClick(() => {
              this.selectTerm(index);
            })
          }, (term: TermInfo) => term.id)
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 24 })
    }
  }

  @Builder
  avatarCard() {
    // 头像卡片（MaterialCard 承载：材质层是卡片内部底层，材质生效时卡片底色让出）：
    // showAvatar 仅控制圆形头像的显示/隐藏，姓名等其余信息始终显示
    MaterialCard({
      cardRadius: 16,
      cardBg: this.cardBgColor(),
      cardBlur: GlassMaterial.bgBlur(this.immersiveEffect),
      cardBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
      cardBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent
    }) {
      Row() {
        if (this.showAvatar) {
        if (this.photo.length > 0) {
          Image('data:image/jpeg;base64,' + this.photo)
            .width(52)
            .height(52)
            .borderRadius(26)
            .objectFit(ImageFit.Cover)
            .backgroundColor(this.subBg($r('app.color.bg_chip'))).backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? false) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
        } else if (JwApi.USE_MOCK) {
          // 功能浏览模式：默认头像使用内置资源
          Image($r('app.media.default_avatar'))
            .width(52)
            .height(52)
            .borderRadius(26)
            .objectFit(ImageFit.Cover)
            .backgroundColor(this.subBg($r('app.color.bg_chip'))).backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? false) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
        } else {
          Text(AppState.avatarText())
            .fontSize(17)
            .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor(Theme.colorOf(this.themeColor))
            .width(52)
            .height(52)
            .borderRadius(26)
            .backgroundColor(this.subBg($r('app.color.bg_chip'))).backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? false) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
            .textAlign(TextAlign.Center)
        }
      }

      Column() {
        Text(`${AppState.displayName()}，${this.greeting()}`)
          .fontSize(17)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.subtitleText())
          .fontSize(12)
          .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
          .margin({ top: 4 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: this.showAvatar ? 12 : 0 })
      .layoutWeight(1)

      Blank()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(16)
    }
  }

  /** 学生名字下方的副标题：学号 · 学院 · 班级（仅展示存在的字段） */
  private subtitleText(): string {
    const sid: string = AppState.studentId();
    const college: string = AppState.profile !== null ? AppState.profile.college : '';
    const cls: string = AppState.profile !== null ? AppState.profile.className : '';
    const parts: string[] = [];
    if (sid.length > 0) {
      parts.push(sid);
    }
    if (college.length > 0) {
      parts.push(college);
    }
    if (cls.length > 0) {
      parts.push(cls);
    }
    return parts.join(' · ');
  }

  @Builder
  todayCard() {
    Column() {
      Row() {
        Divider()
          .vertical(true)
          .strokeWidth(3)
          .color(Theme.colorOf(this.themeColor))
          .height(14)
          .margin({ right: 8 })
        Text('下一节课')
          .fontSize(16)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (this.todayCourses.length > 0) {
          Text(this.nextClass === null ? '今日课程已结束' : `今日 ${this.todayCourses.length} 节`)
            .fontSize(12)
            .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
        }
      }
      .width('100%')

      // 卡片主体（"下一节课"标题单独在卡片外显示）
      // MaterialCard 承载：材质层是卡片内部底层、与卡片同尺寸同圆角，材质生效时卡片底色让出
      MaterialCard({
        cardRadius: 18,
        cardBg: this.cardBgColor(),
        cardBlur: GlassMaterial.bgBlur(this.immersiveEffect),
        cardBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
        cardBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent,
        // 标题行与卡片之间原有 12vp（迁移前挂在标题行上的 margin）→ 改由卡片的外边距承载
        cardMargin: { top: 12 }
      }) {
      Column() {
      if (this.todayCourses.length === 0) {
        // 无今日课时：当前没课了哦！ + 随机鼓励文案 + 下次课预告（点击跳课程表打开详情）
        Column() {
          Text(`当前没课了哦！${this.randomRestText.length > 0 ? this.randomRestText : '好好休息吧~'}`)
            .fontSize(13)
            .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
            .textAlign(TextAlign.Center)
            .width('100%')
          if (this.nextFutureCourse !== null) {
            // 下次课子卡（卡片内部的子卡）：同样接入材质承载（Toggle 承载层 + 内容）。
            // 关掉材质自带投影——小卡挨得近时投影会在卡间缝隙里叠成暗带（参考 README「卡片迁移约定」）
            MaterialCard({
              cardRadius: 16,
              cardDirection: FlexDirection.Row,
              cardMaterialShadow: false,
              cardBg: this.subBg($r('app.color.bg_chip')),
              cardBlur: GlassMaterial.bgBlur(this.immersiveEffect),
              cardBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
              cardBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent,
              cardShadow: GlassMaterial.capsuleShadow(),
              // 标题内容与子卡之间原有 12vp 上边距 → 改由卡片外边距承载
              cardMargin: { top: 12 }
            }) {
            Row() {
              // 左侧竖条：下次课 三个字竖排
              Column() {
                Text('下').fontSize(13).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium)).fontColor(Theme.colorOf(this.themeColor))
                Text('次').fontSize(13).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium)).fontColor(Theme.colorOf(this.themeColor))
                Text('课').fontSize(13).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium)).fontColor(Theme.colorOf(this.themeColor))
              }
              .padding(10)
              .backgroundColor(this.subBg(Theme.rgba(Theme.colorOf(this.themeColor), 0.12))).backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? false) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .borderRadius({ topLeft: 16, bottomLeft: 16 })

              // 右侧主体：课程名+地点 居中
              Column() {
                Text(this.nextFutureCourse.course.name)
                  .fontSize(18)
                  .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center)
                  .width('100%')
                Text(this.nextFutureCourse.course.location)
                  .fontSize(11)
                  .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
                  .textAlign(TextAlign.Center)
                  .width('100%')
                  .margin({ top: 6 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Center)
              .padding({ left: 8, right: 8, top: 12, bottom: 12 })
              .border({ width: { right: 1 }, color: $r('app.color.divider') })

              // 最右侧：日期 + 时间（与桌面卡片"X月X日"对齐）
              Column() {
                Text(this.nextFutureCourse.dateLabel)
                  .fontSize(11)
                  .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
                  .fontColor(Theme.colorOf(this.themeColor))
                  .textAlign(TextAlign.Center)
                Text(this.nextFutureCourse.timeRange)
                  .fontSize(11)
                  .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
                  .fontColor($r('app.color.text_primary'))
                  .textAlign(TextAlign.Center)
                  .margin({ top: 3 })
              }
              .padding({ left: 10, right: 12 })
              .justifyContent(FlexAlign.Center)
            }
            .width('100%')
            }
          }
        }
        .width('100%')
      } else if (this.nextClass === null) {
        Column() {
          Row() {
            Text('🎉')
              .fontSize(26)
              .margin({ right: 12 })
            Column() {
              Text('今日课程已全部结束')
                .fontSize(16)
                .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
                .fontColor($r('app.color.text_primary'))
              Text(`今天共 ${this.todayCourses.length} 节课，辛苦啦`)
                .fontSize(12)
                .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          if (this.nextFutureCourse !== null) {
            // 下次课子卡（与上一分支同款）：材质承载 + 关掉材质自带投影
            MaterialCard({
              cardRadius: 16,
              cardDirection: FlexDirection.Row,
              cardMaterialShadow: false,
              cardBg: this.subBg($r('app.color.bg_chip')),
              cardBlur: GlassMaterial.bgBlur(this.immersiveEffect),
              cardBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
              cardBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent,
              cardShadow: GlassMaterial.capsuleShadow(),
              cardMargin: { top: 12 }
            }) {
            Row() {
              Column() {
                Text('下').fontSize(13).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium)).fontColor(Theme.colorOf(this.themeColor))
                Text('次').fontSize(13).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium)).fontColor(Theme.colorOf(this.themeColor))
                Text('课').fontSize(13).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium)).fontColor(Theme.colorOf(this.themeColor))
              }
              .padding(10)
              .backgroundColor(this.subBg(Theme.rgba(Theme.colorOf(this.themeColor), 0.12))).backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? false) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .borderRadius({ topLeft: 16, bottomLeft: 16 })

              Column() {
                Text(this.nextFutureCourse.course.name)
                  .fontSize(18)
                  .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center)
                  .width('100%')
                Text(this.nextFutureCourse.course.location)
                  .fontSize(11)
                  .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
                  .textAlign(TextAlign.Center)
                  .width('100%')
                  .margin({ top: 6 })
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Center)
              .padding({ left: 8, right: 8, top: 12, bottom: 12 })
              .border({ width: { right: 1 }, color: $r('app.color.divider') })

              Column() {
                Text(this.nextFutureCourse.dateLabel)
                  .fontSize(11)
                  .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
                  .fontColor(Theme.colorOf(this.themeColor))
                  .textAlign(TextAlign.Center)
                Text(this.nextFutureCourse.timeRange)
                  .fontSize(11)
                  .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
                  .fontColor($r('app.color.text_primary'))
                  .textAlign(TextAlign.Center)
                  .margin({ top: 3 })
              }
              .padding({ left: 10, right: 12 })
              .justifyContent(FlexAlign.Center)
            }
            .width('100%')
            }
          }
        }
        .width('100%')
      } else {
        Row() {
          Column() {
            Text(this.nextClass!.timeRange.split('-')[0])
              .fontSize(14)
              .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
              .fontColor($r('app.color.text_primary'))
            Text(this.nextClass!.timeRange.split('-')[1])
              .fontSize(11)
              .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
              .margin({ top: 2 })
          }
          .width(48)
          .alignItems(HorizontalAlign.Start)

          Column() {
            Circle()
              .width(8)
              .height(8)
              .fill(this.nextClass!.ongoing ? Theme.colorOf(this.themeColor) : Const.COURSE_FG[this.nextClass!.course.colorIndex])
          }
          .width(20)
          .margin({ top: 6 })

          Column() {
            Row() {
              Text(this.nextClass!.course.name)
                .fontSize(18)
                .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (this.nextClass!.ongoing) {
                TagChip({ text: '进行中', color: $r('app.color.brand_on'), bg: Theme.colorOf(this.themeColor) })
              } else {
                TagChip({
                  text: this.countdownText(this.nextClass!),
                  color: $r('app.color.accent_orange'),
                  bg: $r('app.color.bg_chip')
                })
              }
            }
            .width('100%')

            Row() {
              // 上课地点：地图定位图标（农大绿）
              Image($r('app.media.map_badge_local'))
                .width(13)
                .height(13)
              Text(this.nextClass!.course.location)
                .fontSize(12)
                .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
                .margin({ left: 4 })
              // 授课教师：人像图标（农大绿）
              Image($r('app.media.portrait'))
                .width(13)
                .height(13)
                .margin({ left: 12 })
              Text(this.nextClass!.course.teacher)
                .fontSize(12)
                .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
                .margin({ left: 4 })
              Blank()
              Text(`第 ${this.nextClass!.course.startSection}-${this.nextClass!.course.endSection} 节`)
                .fontSize(11)
                .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
            }
            .width('100%')
            .margin({ top: 6 })
          }
          .layoutWeight(1)
          .padding({ left: 6 })
        }
          .width('100%')
          .alignItems(VerticalAlign.Top)
        }
      }
      .width('100%')
      .padding(16)
      }
    }
    .width('100%')
  }

  @Builder
  quickEntries() {
    Column() {
      SectionHeader({ title: '快捷入口', action: '', onAction: () => {} })
      // 快捷入口卡（实色底）
      // MaterialCard 承载：材质层是卡片内部底层、与卡片同尺寸同圆角，材质生效时卡片底色让出
      MaterialCard({
        cardRadius: 18,
        cardBg: this.cardBgColor(),
        cardBlur: GlassMaterial.bgBlur(this.immersiveEffect),
        cardBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
        cardBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent
      }) {
      Column() {
        Grid() {
        ForEach(Const.QUICK_ENTRIES, (item: QuickEntry) => {
          GridItem() {
            Column() {
              // 快捷入口小卡（成排）：材质承载 + 内容，与首页大卡同源。
              // 挨得近的小卡必须关掉材质自带投影（cardMaterialShadow: false），
              // 否则投影会在卡间缝隙里叠成一条暗带（参考 README「卡片迁移约定」）。
              MaterialCard({
                cardWidth: '94%',
                cardRadius: 14,
                cardDirection: FlexDirection.Row,
                cardMaterialShadow: false,
                cardBg: this.subBg($r('app.color.bg_chip')),
                cardBlur: GlassMaterial.bgBlur(this.immersiveEffect),
                cardBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
                cardBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent,
                cardOnClick: () => {
                  this.onEntryTap(item.key);
                }
              }) {
                Row() {
                  // 考试查询/学业情况图标（单色 SVG，随主题色渲染）
                  Image(item.key === 'exam' ? $r('app.media.exam_arrange') : $r('app.media.data_icon'))
                    .width(22)
                    .height(22)
                    .objectFit(ImageFit.Contain)
                    .fillColor(Theme.colorOf(this.themeColor))
                  Text(item.title)
                    .fontSize(14)
                    .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
                    .fontColor($r('app.color.text_primary'))
                    .margin({ left: 8 })
                }
                .width('100%')
                .height(48)
                .justifyContent(FlexAlign.Center)
              }
            }
          }
        }, (item: QuickEntry) => item.key)
      }
        .columnsTemplate('1fr 1fr')
        .rowsTemplate('1fr')
        .width('100%')
        .padding({ top: 6, bottom: 6 })
      }
      .width('100%')
      .height(64) // 固定卡高（原液态玻璃容器高度），避免 Grid 内容撑高导致卡片拉长
      .padding({ left: 16, right: 16 })
      }
    }
    .width('100%')
  }

  @Builder
  examSection() {
    Column() {
      SectionHeader({
        title: '近期考试', action: '全部', onAction: () => {
          AppState.stack.pushPath({ name: Const.ROUTE_EXAM });
        }
      })
      if (this.exams.length === 0) {
        // MaterialCard 承载：材质层是卡片内部底层，材质生效时卡片底色让出
        MaterialCard({
          cardRadius: 18,
          cardBg: this.cardBgColor(),
          cardBlur: GlassMaterial.bgBlur(this.immersiveEffect),
          cardBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
          cardBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent
        }) {
          EmptyTip({ text: '近期没有考试安排' })
        }
      } else {
        ForEach(this.exams, (item: ExamItem) => {
          // 成排卡片：卡片之间的 10vp 由 MaterialCard 的 cardMargin 承载
          // （迁移前是挂在卡片自身的 .margin({ bottom: 10 })；尾随闭包之后不能再链式加属性）
          MaterialCard({
            cardRadius: 16,
            cardBg: this.cardBgColor(),
            cardBlur: GlassMaterial.bgBlur(this.immersiveEffect),
            cardBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
            cardBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent,
            cardMargin: { bottom: 10 },
            cardOnClick: () => {
              AppState.stack.pushPath({ name: Const.ROUTE_EXAM });
            }
          }) {
            Row() {
              Column() {
                Text(`${DateUtil.parse(item.date).getMonth() + 1}/${DateUtil.parse(item.date).getDate()}`)
                  .fontSize(15)
                  .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
                  .fontColor($r('app.color.accent_orange'))
                Text(DateUtil.relativeDay(DateUtil.parse(item.date)))
                  .fontSize(10)
                  .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
                  .margin({ top: 2 })
              }
              .width(54)
              .padding({ top: 8, bottom: 8 })
              .backgroundColor(this.subBg($r('app.color.bg_chip'))).backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? false) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
              .borderRadius(10)

              Column() {
                Text(item.courseName)
                  .fontSize(15)
                  .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${item.timeRange} · ${item.location} · ${item.seat} 号座`)
                  .fontSize(12)
                  .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
                  .margin({ top: 5 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              .margin({ left: 12 })

              TagChip({
                text: item.examType,
                color: $r('app.color.accent_orange'),
                bg: $r('app.color.bg_chip')
              })
            }
            .width('100%')
            .padding(14)
          }
        }, (item: ExamItem) => item.id)
      }
    }
    .width('100%')
    .margin({ top: 18 })
  }

  /** 首页消息卡（v1.0.0 原样恢复）：教务消息汇总，查看更多进消息页，点击进消息详情页 */
  @Builder
  messageSection() {
    Column() {
      SectionHeader({
        title: '消息', action: '查看更多', onAction: () => {
          AppState.stack.pushPath({ name: Const.ROUTE_NOTICE });
        }
      })
      if (this.notices.length === 0) {
        // MaterialCard 承载：材质层是卡片内部底层，材质生效时卡片底色让出
        MaterialCard({
          cardRadius: 18,
          cardBg: this.cardBgColor(),
          cardBlur: GlassMaterial.bgBlur(this.immersiveEffect),
          cardBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
          cardBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent
        }) {
          EmptyTip({ text: '暂无消息' })
        }
      } else {
        MaterialCard({
          cardRadius: 18,
          cardBg: this.cardBgColor(),
          cardBlur: GlassMaterial.bgBlur(this.immersiveEffect),
          cardBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
          cardBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent
        }) {
        Column() {
          ForEach(this.notices.slice(0, 3), (item: NoticeItem, index: number) => {
            Column() {
              Row() {
                if (!item.read) {
                  Circle()
                    .width(7)
                    .height(7)
                    .fill($r('app.color.state_danger'))
                    .margin({ right: 8 })
                }
                Text(item.title)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')

              Row() {
                Text(item.source)
                  .fontSize(11)
                  .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
                Text(' · ')
                  .fontSize(11)
                  .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
                Text(item.date)
                  .fontSize(11)
                  .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
                Blank()
                Text('详情 ›')
                  .fontSize(11)
                  .fontColor(Theme.colorOf(this.themeColor))
              }
              .width('100%')
              .margin({ top: 6 })

              if (index < Math.min(this.notices.length, 3) - 1) {
                Divider()
                  .color($r('app.color.divider'))
                  .margin({ top: 12, bottom: 12 })
              }
            }
            .width('100%')
            .onClick(() => {
              AppState.currentNotice = item;
              AppState.stack.pushPath({ name: Const.ROUTE_NOTICE_DETAIL });
            })
          }, (item: NoticeItem) => item.id)
        }
        .width('100%')
        .padding(16)
        }
      }
    }
    .width('100%')
    .margin({ top: 18 })
  }

  /** 首页通知卡（独立功能卡片）：数据源为教务处官网「学期校历」最新两条，每条带【通知】标志 + 文章链接，点击打开文章页 */
  @Builder
  noticeSection() {
    Column() {
      SectionHeader({ title: '校历信息', action: '查看校历', onAction: () => {
        // 打开教务处官网学期校历列表（外部链接页）
        AppState.webUrl = Const.JWC_LIST_URL;
        AppState.webTitle = '学期校历';
        AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
      } })
      if (this.jwcNotices.length === 0) {
        // MaterialCard 承载：材质层是卡片内部底层，材质生效时卡片底色让出
        MaterialCard({
          cardRadius: 18,
          cardBg: this.cardBgColor(),
          cardBlur: GlassMaterial.bgBlur(this.immersiveEffect),
          cardBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
          cardBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent
        }) {
          EmptyTip({ text: '暂无通知' })
        }
      } else {
        MaterialCard({
          cardRadius: 18,
          cardBg: this.cardBgColor(),
          cardBlur: GlassMaterial.bgBlur(this.immersiveEffect),
          cardBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
          cardBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent
        }) {
        Column() {
          ForEach(this.jwcNotices, (item: NoticeItem, index: number) => {
            Column() {
              Row() {
                Text(item.title)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
              }
              .width('100%')

              Row() {
                Text(item.source)
                  .fontSize(11)
                  .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
                Text(' · ')
                  .fontSize(11)
                  .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
                Text(item.date)
                  .fontSize(11)
                  .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
                Blank()
                Text('阅读 ›')
                  .fontSize(11)
                  .fontColor(Theme.colorOf(this.themeColor))
              }
              .width('100%')
              .margin({ top: 6 })

              if (index < this.jwcNotices.length - 1) {
                Divider()
                  .color($r('app.color.divider'))
                  .margin({ top: 12, bottom: 12 })
              }
            }
            .width('100%')
            .onClick(() => {
              if (item.url.length > 0) {
                // 功能浏览模式默认禁止打开网页；调试模式开启后允许
                if (JwApi.USE_MOCK && !AppState.debugNetwork) {
                  this.getUIContext().getPromptAction().showToast({ message: '当前模式禁止使用' });
                  return;
                }
                // 有文章链接：在"外部链接"页面打开教务处官网文章页
                AppState.webUrl = item.url;
                AppState.webTitle = '教务处通知';
                AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
              } else {
                this.sheetNotice = item;
                this.showNoticeSheet = true;
              }
            })
          }, (item: NoticeItem) => item.id)
        }
        .width('100%')
        .padding(16)
        }
      }
    }
    .width('100%')
    .margin({ top: 18 })
  }

  /** 通知详情底部弹层（原地展开，不跳页） */
  @Builder
  noticeSheet() {
    // 面板材质与卡片同源：bindSheet 自身的 systemMaterial 挂在面板上、内容区不生效，
    // 所以由 MaterialSheetPanel 的 Toggle 承载层铺满整块面板来渲染材质。
    // 配套硬要求：bindSheet 必须显式 backgroundColor: Color.Transparent，
    // 否则默认白底会把材质整块盖住（表现为「弹窗一点光感都没有」）。
    MaterialSheetPanel({ panelRadius: 24, panelPadding: 16, panelShowClose: true, panelOnClose: (): void => { this.showNoticeSheet = false; } }) {
    Column() {
      if (this.sheetNotice !== null) {
        Text(this.sheetNotice.title)
          .fontSize(17)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Row() {
          TagChip({ text: '【通知】', color: $r('app.color.accent_purple'), bg: $r('app.color.bg_chip') })
            .margin({ right: 8 })
          if (this.sheetNotice.isTop) {
            TagChip({ text: '置顶', color: $r('app.color.state_danger'), bg: $r('app.color.bg_chip') })
              .margin({ right: 8 })
          }
          Text(this.sheetNotice.source)
            .fontSize(12)
            .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
          Text(' · ')
            .fontSize(12)
            .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
          Text(this.sheetNotice.date)
            .fontSize(12)
            .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
          Blank()
        }
        .width('100%')
        .margin({ top: 12, bottom: 14 })
        Divider()
          .color($r('app.color.divider'))
        Scroll() {
          Text(this.sheetNotice.content.length > 0 ? this.sheetNotice.content : '暂无详细内容，可在消息页查看完整公告。')
            .fontSize(14)
            .lineHeight(24)
            .fontColor($r('app.color.text_primary'))
            .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        .margin({ top: 14 })
      }
    }
    .width('100%')
    .height('100%')
    }
  }

  /** 设备当前日期（yyyy-MM-dd），优先于校历内置 todayDate，避免缓存/预置数据过期 */
  private effectiveToday(): string {
    return DateUtil.format(new Date());
  }

  /** 今日所属教学周次（开学后返回对应周次；未开学返回 0）。自定义开学日时按自定义日推算 */
  private todayTeachingWeek(): number {
    const cal: TeachingCalendar | null = this.teachingCal;
    if (cal === null) {
      return 0;
    }
    const today: string = this.effectiveToday();
    if (this.customTermStart.length > 0) {
      const d: number = DateUtil.diffDays(DateUtil.parse(this.customTermStart), DateUtil.parse(today));
      if (d < 0) {
        return 0;
      }
      return Math.floor(d / 7) + 1;
    }
    for (let r: number = 0; r < cal.rows.length; r++) {
      const dates: string[] = cal.rows[r].dates;
      for (let c: number = 0; c < dates.length; c++) {
        if (dates[c] === today) {
          return cal.weekNumbers[c] !== undefined ? cal.weekNumbers[c] : 0;
        }
      }
    }
    return 0;
  }

  /** 是否已开学（今日 >= 有效开学日，支持自定义） */
  private isTermStarted(): boolean {
    const start: string = this.effStart();
    if (start.length === 0) {
      return false;
    }
    return DateUtil.parse(start).getTime() <= new Date().getTime();
  }

  /**
   * 是否在顶栏显示"重登"胶囊。
   * 条件：手动重登模式 + 首页底部校历为空 + 数据已加载完 + 真实登录（非功能浏览）。
   */
  private shouldShowRelogin(): boolean {
    if (JwApi.USE_MOCK) {
      return false;
    }
    if (this.loading) {
      return false;
    }
    if (DataStore.getLoginMode() !== 'legacy') {
      return false;
    }
    return this.teachingCal === null;
  }

  /** 点击"重登"胶囊：调用 Index 注册的回调（弹"真正重新登录"确认 + 全局遮罩重登） */
  private onReloginClick(): void {
    if (AppState.onForceRelogin !== null) {
      AppState.onForceRelogin();
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '重登功能暂不可用' });
    }
  }

  /** 校历覆盖的自然月列表：[年份*100+月份, ...]（如 202608 ~ 202702），采用有效起止（自定义优先） */
  private calMonthList(): number[] {
    const s: string = this.effStart();
    const e: string = this.effEnd();
    if (s.length === 0 || e.length === 0) {
      return [];
    }
    const sy: number = Number(s.slice(0, 4));
    const sm: number = Number(s.slice(5, 7));
    const ey: number = Number(e.slice(0, 4));
    const em: number = Number(e.slice(5, 7));
    if (sy === 0 || sm === 0 || ey === 0 || em === 0) {
      return [];
    }
    if (sy > ey || (sy === ey && sm > em)) {
      return [];
    }
    const out: number[] = [];
    let y: number = sy;
    let m: number = sm;
    while (y < ey || (y === ey && m <= em)) {
      out.push(y * 100 + m);
      m++;
      if (m > 12) {
        m = 1;
        y++;
      }
    }
    return out;
  }

  /** 某自然月的月历格子：每行 7 格（周一~周日），值为 yyyy-MM-dd 或 ''（空位补齐） */
  private monthGrid(year: number, month: number): string[][] {
    const rows: string[][] = [];
    const first: Date = new Date(year, month - 1, 1);
    const daysInMonth: number = new Date(year, month, 0).getDate();
    const lead: number = (first.getDay() + 6) % 7; // 周一=0
    let cur: string[] = [];
    for (let i = 0; i < lead; i++) {
      cur.push('');
    }
    for (let d = 1; d <= daysInMonth; d++) {
      cur.push(DateUtil.format(new Date(year, month - 1, d)));
      if (cur.length === 7) {
        rows.push(cur);
        cur = [];
      }
    }
    if (cur.length > 0) {
      while (cur.length < 7) {
        cur.push('');
      }
      rows.push(cur);
    }
    // 固定补足到 6 行（31 天大小），保证各月份高度一致，滑动时不会上下抽动
    while (rows.length < 6) {
      rows.push(['', '', '', '', '', '', '']);
    }
    return rows;
  }

  /** 日期是否属于校历中的节假日（中秋节/国庆节/元旦/春节） */
  private isCalHoliday(date: string): boolean {
    if (date === '2026-09-25' || date === '2026-10-01' || date === '2027-01-01' || date === '2027-02-06') {
      return true;
    }
    return false;
  }

  /** 某日期所属教学周（1 起；不在学期内返回 0，按有效开学日推算） */
  private weekIndex(day: string): number {
    const start: string = this.effStart();
    if (start.length === 0 || day.length === 0) {
      return 0;
    }
    const d: number = DateUtil.diffDays(DateUtil.parse(start), DateUtil.parse(day));
    if (d < 0) {
      return 0;
    }
    return Math.floor(d / 7) + 1;
  }

  /** 周次配色（同周同色，8 色循环；低透明度以保持文字可读） */
  private weekColor(idx: number): string {
    if (idx <= 0) {
      return '#00000000';
    }
    const palette: string[] = [
      '#332E7AFF', '#3322A06B', '#33E8833A', '#339B59C9',
      '#33D94F70', '#3300A6B8', '#33C9A227', '#33546E7A'
    ];
    return palette[(idx - 1) % palette.length];
  }

  /** 载入日历自定义设置（开学日按学期存，结束日与标题为全局） */
  private loadTermCustom(): void {
    this.customTermStart = DataStore.getCustomTermStart(AppState.term.id);
    this.customTermEnd = DataStore.get(DataStore.KEY_CUSTOM_TERM_END);
    this.customSemesterLabel = DataStore.get(DataStore.KEY_SEMESTER_LABEL);
    this.labelInput = this.customSemesterLabel;
  }

  /** 有效开学日（自定义优先，回落校历解析值） */
  private effStart(): string {
    if (this.customTermStart.length > 0) {
      return this.customTermStart;
    }
    if (this.teachingCal === null) {
      return '';
    }
    return this.teachingCal!.startDate;
  }

  /** 有效结束日（自定义优先，回落校历解析值） */
  private effEnd(): string {
    if (this.customTermEnd.length > 0) {
      return this.customTermEnd;
    }
    if (this.teachingCal === null) {
      return '';
    }
    return this.teachingCal!.endDate;
  }

  /** 有效学期标题（自定义优先，回落校历解析值） */
  private effLabel(): string {
    if (this.customSemesterLabel.length > 0) {
      return this.customSemesterLabel;
    }
    if (this.teachingCal === null) {
      return '';
    }
    return this.teachingCal!.semesterLabel;
  }

  /** 自定义起止变化后重算当前月与页码（避免停留在已被排除的空白月份） */
  private refreshCalendarState(): void {
    this.calDefaultMonth = this.computeCurrentMonth();
    this.calPageIndex = this.calInitialIndex();
  }

  /** 打开「开学日」选择器（立即生效；与课程表共用同一份数据，周次同步变化） */
  private openStartPicker(): void {
    const base: string = this.effStart();
    const sel: Date = base.length > 0 ? DateUtil.parse(base) : new Date();
    DatePickerDialog.show({
      start: new Date(2000, 0, 1),
      end: new Date(2035, 11, 31),
      selected: sel,
      onAccept: (value: DatePickerResult) => {
        const y: number = value.year ?? 2000;
        const m: number = value.month ?? 0;
        const d: number = value.day ?? 1;
        const date: string = DateUtil.format(new Date(y, m, d));
        this.customTermStart = date;
        DataStore.setCustomTermStart(AppState.term.id, date);
        this.refreshCalendarState();
      }
    });
  }

  /** 打开「结束日」选择器 */
  private openEndPicker(): void {
    const base: string = this.effEnd();
    const sel: Date = base.length > 0 ? DateUtil.parse(base) : new Date();
    DatePickerDialog.show({
      start: new Date(2000, 0, 1),
      end: new Date(2035, 11, 31),
      selected: sel,
      onAccept: (value: DatePickerResult) => {
        const y: number = value.year ?? 2000;
        const m: number = value.month ?? 0;
        const d: number = value.day ?? 1;
        const date: string = DateUtil.format(new Date(y, m, d));
        this.customTermEnd = date;
        DataStore.put(DataStore.KEY_CUSTOM_TERM_END, date);
        this.refreshCalendarState();
      }
    });
  }

  /** 保存自定义学期标题（留空 = 恢复校历原标题） */
  private saveCalLabel(): void {
    this.customSemesterLabel = this.labelInput.trim();
    DataStore.put(DataStore.KEY_SEMESTER_LABEL, this.customSemesterLabel);
    this.getUIContext().getPromptAction().showToast({
      message: this.customSemesterLabel.length > 0 ? '已保存' : '已恢复默认标题'
    });
  }

  /** 恢复默认日期（清除自定义开学 / 结束日） */
  private restoreCalDates(): void {
    this.customTermStart = '';
    this.customTermEnd = '';
    DataStore.setCustomTermStart(AppState.term.id, '');
    DataStore.put(DataStore.KEY_CUSTOM_TERM_END, '');
    this.refreshCalendarState();
    this.getUIContext().getPromptAction().showToast({ message: '已恢复校历日期' });
  }

  /** 日历设置面板：学期标题 + 开学日 / 结束日自定义 */
  @Builder
  calEditorSheet() {
    Column() {
      Text('学期标题')
        .fontSize(13)
        .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
        .fontColor($r('app.color.text_primary'))
        .width('100%')
      // 学期标题输入框：TextInput 属表单控件，不能走 Toggle 承载层 → Stack 兄弟结构：
      // MaterialCardLayer 纯视觉承载层画沉浸光感（受全局开关控制），输入框自身透明底；
      // 材质关闭时回落原 comp_background_tertiary 实色底。原 top:6 间距由外壳 margin 承担。
      Stack() {
        if (materialActive()) {
          MaterialCardLayer({ layerRadius: $r('sys.float.corner_radius_level12'), layerShadow: false })
        }
        TextInput({ placeholder: '留空则显示校历原标题', text: this.labelInput })
          .height(48)
          .enterKeyType(EnterKeyType.Done)
          .borderRadius($r('sys.float.corner_radius_level12'))
          .fontSize($r('sys.float.Body_L'))
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Regular : AppearanceStore.fontWeight(FontWeight.Regular))
          .backgroundColor(materialActive() ? Color.Transparent : $r('sys.color.comp_background_tertiary'))
          .caretStyle({ color: $r('sys.color.font_emphasize') })
          .type(InputType.Normal)
          .fontColor('rgba(0, 85, 255, 1.0)')
          .placeholderFont({ size: $r('sys.float.Body_L'), weight: FontWeight.Regular })
          .onChange((v: string) => {
            this.labelInput = v;
          })
      }
      .width('100%')
      .margin({ top: 6 })
      .borderRadius($r('sys.float.corner_radius_level12'))
      Row() {
        Text('保存标题')
          .fontSize(13)
          .fontColor(Color.White)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor(Theme.colorOf(this.themeColor))
          .borderRadius(10)
          .onClick(() => {
            this.saveCalLabel();
          })
        Text('恢复默认标题')
          .fontSize(13)
          .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .backgroundColor(this.subBg($r('app.color.bg_chip'))).backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? false) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
          .borderRadius(10)
          .margin({ left: 10 })
          .onClick(() => {
            this.labelInput = '';
            this.saveCalLabel();
          })
      }
      .width('100%')
      .margin({ top: 10 })

      Row() {
        Text('开学日期')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(this.effStart().length > 0 ? this.effStart() : '未设置')
          .fontSize(13)
          .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
          .margin({ right: 10 })
        Text('修改')
          .fontSize(12)
          .fontColor(Theme.colorOf(this.themeColor))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(this.subBg($r('app.color.bg_chip'))).backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? false) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
          .borderRadius(10)
      }
      .width('100%')
      .height(46)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.openStartPicker();
      })

      Row() {
        Text('结束日期')
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(this.effEnd().length > 0 ? this.effEnd() : '未设置')
          .fontSize(13)
          .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
          .margin({ right: 10 })
        Text('修改')
          .fontSize(12)
          .fontColor(Theme.colorOf(this.themeColor))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor(this.subBg($r('app.color.bg_chip'))).backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? false) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
          .borderRadius(10)
      }
      .width('100%')
      .height(46)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.openEndPicker();
      })

      Text('恢复默认日期')
        .fontSize(13)
        .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor(this.subBg($r('app.color.bg_chip'))).backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? false) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
        .borderRadius(10)
        .margin({ top: 10 })
        .onClick(() => {
          this.restoreCalDates();
        })

      Text('提示：修改开学时间会同时影响课程表的周次推算；学期标题留空即恢复校历原标题。')
        .fontSize(11)
        .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
        .width('100%')
        .margin({ top: 12 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 14, bottom: 26 })
  }

  /** 学期日历信息小标签（胶囊小按钮：材质走 MaterialButton 的 Toggle 承载层） */
  @Builder
  infoChip(text: string, color: ResourceColor) {
    MaterialButton({
      btnRadius: 10,
      btnMargin: { right: 8 },
      btnBg: this.subBg($r('app.color.bg_chip')),
      btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
      btnBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
      btnBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent
    }) {
      Text(text)
        .fontSize(11)
        .fontColor(color)
        .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
    }
  }

  /** 日期是否在有效学期范围内（有效开学日 ~ 有效结束日），范围外灰色显示 */
  private isInTerm(day: string): boolean {
    const s: string = this.effStart();
    const e: string = this.effEnd();
    if (s.length === 0 || e.length === 0) {
      return true;
    }
    return day >= s && day <= e;
  }

  /** Swiper 初始页索引（默认当月，不在校历覆盖月份则第一月） */
  private calInitialIndex(): number {
    const all: number[] = this.calMonthList();
    const idx: number = all.indexOf(this.calDefaultMonth);
    return idx >= 0 ? idx : 0;
  }

  /** 日历（正常日历样式）：Swiper 左右滑动查看月份；按自然月分块的月历（周一~周日），今日/节假日高亮，学期范围外灰色；底部附校历说明。数据运行时解析，不写死 */
  @Builder
  calendar() {
    Column() {
      SectionHeader({ title: '日历', action: '设置', onAction: () => {
        this.labelInput = this.customSemesterLabel;
        this.showCalEditor = true;
      } })

      // 卡片主体（标题"日历"单独在卡片外，样式对齐"近期考试"）
      // MaterialCard 承载：材质层是卡片内部底层、与卡片同尺寸同圆角，材质生效时卡片底色让出
      MaterialCard({
        cardRadius: 18,
        cardBg: this.cardBgColor(),
        cardBlur: GlassMaterial.bgBlur(this.immersiveEffect),
        cardBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
        cardBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent
      }) {
      if (this.teachingCal === null) {
        // "加载日历"占位卡：固定高度（不再套 padding，避免卡片被撑高）
        Column() {
          LoadingTip({ text: '加载日历…' })
        }
          .width('100%')
          .height(140)
          .justifyContent(FlexAlign.Center)
      } else {
        // else 分支内容自带 padding（padding 必须挂在卡片内部的内容容器上，承载层才能铺满整张卡片）
        Column() {
        // 学期标题：点击可自定义（留空恢复校历原标题）
        Text(this.effLabel())
          .fontSize(13)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 8 })
          .onClick(() => {
            this.labelInput = this.customSemesterLabel;
            this.showCalEditor = true;
          })

        Row() {
          // 未开学不显示周次，显示"未开学"
          if (this.isTermStarted()) {
            this.infoChip(`第 ${this.todayTeachingWeek()} 周`, Theme.colorOf(this.themeColor))
          } else {
            this.infoChip('未开学', $r('app.color.accent_orange'))
          }
          if (this.effStart().length > 0) {
            // 开生日胶囊小按钮（点击改期）：材质走 MaterialButton 的 Toggle 承载层
            MaterialButton({
              btnRadius: 10,
              btnMargin: { right: 8 },
              btnBg: this.subBg($r('app.color.bg_chip')),
              btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
              btnBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
              btnBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent,
              btnOnClick: () => {
                this.openStartPicker();
              }
            }) {
              Text(`开学 ${this.effStart().slice(5)}`)
                .fontSize(11)
                .fontColor($r('app.color.accent_blue'))
                .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            }
          }
          if (this.effEnd().length > 0) {
            // 结束日胶囊小按钮（点击改期）：同上，材质走 MaterialButton 的 Toggle 承载层
            MaterialButton({
              btnRadius: 10,
              btnMargin: { right: 8 },
              btnBg: this.subBg($r('app.color.bg_chip')),
              btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
              btnBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
              btnBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent,
              btnOnClick: () => {
                this.openEndPicker();
              }
            }) {
              Text(`结束 ${this.effEnd().slice(5)}`)
                .fontSize(11)
                .fontColor($r('app.color.accent_orange'))
                .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
                .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            }
          }
        }
        .width('100%')
        .margin({ bottom: 10 })

        // 月份 Swiper：左右滑动查看其他月份
        Swiper() {
          ForEach(this.calMonthList(), (ym: number) => {
            Column() {
              Text(`${ym % 100}月 ${Math.floor(ym / 100)}`)
                .fontSize(13)
                .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .margin({ top: 6, bottom: 6 })

              Row() {
                ForEach(Const.WEEK_SHORT, (d: string) => {
                  Text(d)
                    .fontSize(10)
                    .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
                    .textAlign(TextAlign.Center)
                    .layoutWeight(1)
                }, (d: string) => d)
              }
              .width('100%')
              .padding({ bottom: 4 })

              ForEach(this.monthGrid(Math.floor(ym / 100), ym % 100), (row: string[]) => {
                Row() {
                  ForEach(row, (day: string, di: number) => {
                    Column() {
                      if (day.length > 0) {
                        Text(day.slice(-2))
                          .fontSize(11)
                          .fontColor(
                            day === this.effectiveToday()
                              ? Color.White
                              : (this.isCalHoliday(day)
                                ? $r('app.color.accent_orange')
                                : (this.isInTerm(day)
                                  ? (day < this.effectiveToday()
                                    ? GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))
                                    : $r('app.color.text_primary'))
                                  : GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))))
                          )
                          .fontWeight(this.fwMode === 'follow' ? (day === this.effectiveToday() ? FontWeight.Bold : FontWeight.Normal) : AppearanceStore.fontWeight(day === this.effectiveToday() ? FontWeight.Bold : FontWeight.Normal))
                          .width('100%')
                          .height(28)
                          .textAlign(TextAlign.Center)
                      }
                    }
                    .layoutWeight(1)
                    .height(28)
                    .justifyContent(FlexAlign.Center)
                    // 色带两端圆角（周一到周日为一条，两头收角）
                    .borderRadius({
                      topLeft: di === 0 ? 10 : 0,
                      bottomLeft: di === 0 ? 10 : 0,
                      topRight: di === row.length - 1 ? 10 : 0,
                      bottomRight: di === row.length - 1 ? 10 : 0
                    })
                    // 背景铺满整格 → 同一周（行内 7 天）连成一条色带；已过去的日期/周次显示为灰色
                    .backgroundColor(
                      day.length === 0
                        ? Color.Transparent
                        : (day === this.effectiveToday()
                          ? Theme.colorOf(this.themeColor)
                          : (day < this.effectiveToday()
                            ? 'rgba(128,138,136,0.22)'
                            : (this.isInTerm(day) ? this.weekColor(this.weekIndex(day)) : Color.Transparent)))
                    )
                  }, (day: string, di: number) => `${di}-${day}`)
                }
                .width('100%')
                .height(32)
                .margin({ bottom: 2 })
              }, (row: string[], ri: number) => `${ri}-${row.length}`)
            }
            .width('100%')
            .padding({ top: 6, bottom: 8 })
          }, (ym: number) => `${ym}`)
        }
        .index(this.calInitialIndex())
        .loop(false)
        .indicator(false)
        .onChange((index: number) => {
          this.calPageIndex = index;
        })
        .width('100%')

        // 页码指示器（自绘）：位于月份内容下方，位置可精确控制，不遮挡日期
        Row({ space: 6 }) {
          ForEach(this.calMonthList(), (ym: number, i: number) => {
            Column()
              .width(i === this.calPageIndex ? 14 : 6)
              .height(6)
              .borderRadius(3)
              .backgroundColor(i === this.calPageIndex ? Theme.colorOf(this.themeColor) : '#33000000')
          }, (ym: number, i: number) => `caldot${i}`)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 2, bottom: 2 })

        // 校历说明（来自校历 PDF 说明区）
        Column() {
          Text('校历说明')
            .fontSize(11)
            .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
            .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
            .width('100%')
          Text('第 1~20 周为秋季学期教学活动，第 21 周起放寒假。中秋节(9月25日)、国庆节(10月1日)、元旦(1月1日)、春节(2月6日)等节假日放假安排按照国家及自治区规定执行，详见校办通知。')
            .fontSize(11)
            .lineHeight(18)
            .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
            .width('100%')
            .margin({ top: 6 })
        }
        .width('100%')
        .padding(12)
          .backgroundColor(this.subBg($r('app.color.bg_chip'))).backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? false) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
          .borderRadius(12)
          .margin({ top: 6 })
        }
        .width('100%')
        .padding(16)
      }
      }
    }
    .width('100%')
    .margin({ top: 18 })
    // 日历设置面板（挂日历卡片外框；与根 Column / Scroll 上的其它弹层分属不同组件，避免冲突）
    .bindSheet($$this.showCalEditor, this.calEditorSheet(), {
      height: SheetSize.FIT_CONTENT,
      showClose: true,
      preferType: SheetType.BOTTOM,
      title: { title: '日历设置' }
    })
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
    Column() {
    this.titleBar()
    if (this.isLandscape) {
      this.homeLandscape()
    } else {
    // 中间内容：可滚动；横屏/平板下内容限宽 720vp 并居中（一多适配）
    Row() {
      Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
          Column() {
            // 顶栏占位（随内容滚走）：固定高度，位于悬浮渐变标题栏下方
            Column()
              .width('100%')
              .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
            // 头像卡片（始终显示；圆形头像由 showAvatar 开关控制）
            this.avatarCard()

            Column() {
              this.todayCard()
            }
            .margin({ top: 12 })

            Column() {
              this.quickEntries()
            }
            .margin({ top: 18 })

            this.calendar()
            this.examSection()
            this.messageSection()
            this.noticeSection()
            Column() {
              Text('数据来源: 新疆农业大学教务系统').fontSize(11)
                .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
              Text('新疆农业大学教务处').fontSize(11)
                .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
                .margin({ top: 3 })
              Text('"功能浏览"模式为本地模拟数据').fontSize(11)
                .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
                .margin({ top: 3 })
            }
            .width('100%')
            .margin({ top: 20, bottom: 24 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 100 }) // 底部预留悬浮底栏高度，避免内容被遮挡
          // 学期选择弹层（与根 Column 的通知弹层/Scroll 的网页弹层分置不同组件，避免同组件多 bindSheet 冲突）
          .bindSheet($$this.showTermSheet, this.termPickerSheet(), {
            width: SheetUtil.sheetWidth(),
            preferType: SheetType.BOTTOM,
            height: SheetSize.FIT_CONTENT,
            // 关闭按钮由 MaterialSheetPanel 自绘（沉浸光感），系统 showClose 必须关掉避免双按钮
            showClose: false,
            dragBar: true,
            // 必须显式透明：不透明底（默认白/bg_card）会把 MaterialSheetPanel 的材质整块盖住
            backgroundColor: Color.Transparent,
            blurStyle: sheetBlurStyle(),
            title: { title: '选择学年-学期' }
          })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
        // 通知文章页（教务处官网）挂在内层 Scroll，与根组件的通知弹层分离（同组件多 bindSheet 仅最后一个生效）
        .bindSheet($$this.showWebSheet, this.webSheet(), {
          width: SheetUtil.sheetWidth(),
          preferType: SheetType.BOTTOM,
          height: SheetSize.LARGE,
          dragBar: false,
          backgroundColor: $r('app.color.bg_page'),
          title: { title: AppState.webTitle }
        })
      }
      .onRefreshing(() => { this.onRefresh(); })
      }
      .width(720)
      .constraintSize({ maxWidth: '100%' })
      .height('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center) // 横屏/平板下 Scroll 水平居中
    }
    }
    .width('100%')
    .height('100%')
    // 壁纸功能：页面根背景透明，让主框架底层的全局壁纸透出（无壁纸时由 MainView 底层 bg_page 兜底）
    .backgroundColor(Color.Transparent)
    .bindSheet($$this.showNoticeSheet, this.noticeSheet(), {
      width: SheetUtil.sheetWidth(),
      preferType: SheetType.BOTTOM,
      height: SheetSize.LARGE,
      // 关闭按钮由 MaterialSheetPanel 自绘（沉浸光感），系统 showClose 必须关掉避免双按钮
      showClose: false,
      dragBar: true,
      // 必须显式透明：BindOptions.backgroundColor 默认是 Color.White，
      // 而沉浸光感的视觉层级位于 backgroundColor 之下，白底会把面板材质整块盖住
      backgroundColor: Color.Transparent,
      blurStyle: sheetBlurStyle()
    })
    }
    .width('100%')
    .height('100%')
    // 灰字广播依赖登记：grayTick 变化触发整页重算 graySecondary/grayTertiary 文本色（恒真不改变视觉）
    .opacity(this.grayTick >= 0 ? 1 : 1)
  }

  @Builder
  homeLandscape() {
    Row() {
      // 左列：头像 / 今日课程 / 校历 / 快捷入口
      Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
          Column() {
            // 顶栏占位（随内容滚走）：固定高度，与左/右列保持一致
            Column()
              .width('100%')
              .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
            this.avatarCard()
            Column() {
              this.todayCard()
            }
            .margin({ top: 12 })
            Column() {
              this.quickEntries()
            }
            .margin({ top: 12 })
            this.calendar()
          }
          .width('100%')
          .padding({ left: 16, right: 8, top: 12, bottom: 100 })
        }
        .layoutWeight(1)
        .height('100%')
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
        .bindSheet($$this.showTermSheet, this.termPickerSheet(), {
          width: SheetUtil.sheetWidth(),
          preferType: SheetType.BOTTOM,
          height: SheetSize.FIT_CONTENT,
          // 关闭按钮由 MaterialSheetPanel 自绘（沉浸光感），系统 showClose 必须关掉避免双按钮
          showClose: false,
          dragBar: true,
          backgroundColor: $r('app.color.bg_card'),
          title: { title: '选择学年-学期' }
        })
      }
      .layoutWeight(1)
      .height('100%')
      .onRefreshing(() => { this.onRefresh(); })

      // 右列：考试 / 消息 / 通知
      Refresh({ refreshing: $$this.refreshing }) {
        Scroll() {
          Column() {
            // 顶栏占位（随内容滚走）
            Column()
              .width('100%')
              .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
            this.examSection()
            this.messageSection()
            this.noticeSection()
            Column() {
              Text('数据来源: 新疆农业大学教务系统').fontSize(11)
                .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
              Text('新疆农业大学教务处').fontSize(11)
                .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
                .margin({ top: 3 })
              Text('"功能浏览"模式为本地模拟数据').fontSize(11)
                .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
                .margin({ top: 3 })
            }
            .width('100%')
            .margin({ top: 20, bottom: 24 })
          }
          .width('100%')
          .padding({ left: 8, right: 16, top: 12, bottom: 100 })
        }
        .layoutWeight(1)
        .height('100%')
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
        .bindSheet($$this.showWebSheet, this.webSheet(), {
          width: SheetUtil.sheetWidth(),
          preferType: SheetType.BOTTOM,
          height: SheetSize.LARGE,
          dragBar: false,
          backgroundColor: $r('app.color.bg_page'),
          title: { title: AppState.webTitle }
        })
      }
      .layoutWeight(1)
      .height('100%')
      .onRefreshing(() => { this.onRefresh(); })
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.Top)
  }

  @Builder
  webSheet() {
    WebSurface()
  }
}