/**
 * 学业情况：
 *  - 平均学分绩点 GPA（大字号）
 *  - 4 个统计卡：已修 / 在读 / 未修 / 未通过
 *  - 课程分类与修读情况（点击分类查看：已完成 / 在读 / 未修 / 未通过 课程）
 *  - 未通过课程列表
 *  - 学业提醒
 *
 * 数据来源：JwApi.getAcademic() 解析完正方学业页纯文本得到总体统计；
 * 课程分类与详情从成绩（ScoreItem.kclbmc）+ 课表数据组合产生。
 */
import { JwApi } from '../api/JwApi';
import { AppState } from '../common/AppState';
import { LogStore } from '../common/LogStore';
import { AntiPeepManager } from '../common/AntiPeepManager';
import { CourseItem, AcademicReport, CreditCategory, OverallGradeStats, OverallGrades, ScoreItem, TermInfo, TermScore } from '../model/Models';
import { EMPTY_REPORT } from '../model/Empty';
import { LoadingTip, PageHeader, StatCell } from './common/UiKit';
import { AntiPeepOverlay } from './common/AntiPeepOverlay';
import { WallpaperFill } from './common/WallpaperFill';
import { Theme } from '../common/ThemeUtil';
import { WallpaperTone } from '../common/WallpaperTone';

@Component
export struct AcademicPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 壁纸亮度（文字自适应用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('barStyle') barStyle: string = 'new';
  /** 沉浸光感：卡片玻璃化 */
  @StorageProp('glassEnabled') glassEnabled: boolean = false;
  @StorageProp('glassBlur') glassBlur: number = 16;
  @StorageProp('glassRefract') glassRefract: number = 40;
  @State report: AcademicReport = EMPTY_REPORT;
  @State courses: CourseItem[] = [];
  @State termScores: TermScore[] = [];
  /** 总体成绩统计（移植自参考项目「成绩-总体」：累计绩点/已修学分/总课程 + 成绩分布） */
  @State overallStats: OverallGradeStats | null = null;
  /** 总体成绩 - 课程明细（含成绩/学分/绩点） */
  @State overallCourses: ScoreItem[] = [];
  /** 课程明细是否展开（默认只显示前 8 条） */
  @State detailExpanded: boolean = false;
  /** 学期名称缓存（termId → label，避免重复构建） */
  private termLabels: TermInfo[] = [];
  @State loading: boolean = true;
  @State refreshing: boolean = false;
  @State isPeeped: boolean = false;
  private peepMgr: AntiPeepManager = new AntiPeepManager();

  /** 页面出现：触发学业数据加载 */
  aboutToAppear(): void {
    this.load();
    // 启动防窥保护监听
    this.peepMgr.start((hidden: boolean) => { this.isPeeped = hidden; });
  }

  aboutToDisappear(): void {
    this.peepMgr.stop();
  }

  private async load(): Promise<void> {
    this.loading = true;
    const cached: AcademicReport = JwApi.loadCachedAcademic();
    if (cached.gpa > 0 || cached.totalRequired > 0) {
      this.report = cached;
    }
    const cachedCourses: CourseItem[] = JwApi.loadCachedCourses();
    if (cachedCourses.length > 0) {
      this.courses = cachedCourses;
    }
    this.termScores = JwApi.loadCachedTermScores();
    // 总体成绩：先展示缓存
    const cachedOverall: OverallGrades | null = JwApi.loadCachedOverallGrades();
    if (cachedOverall !== null) {
      this.overallStats = cachedOverall.stats;
      this.overallCourses = cachedOverall.courses;
    }
    // 日志调试：记录本地操作（先展示缓存）+ 实际反馈
    LogStore.log('学业', '页面加载', '开始',
      `先展示缓存 GPA=${cached.gpa} 课程${cachedCourses.length}节 成绩${this.termScores.length}学期`);
    try {
      const report: AcademicReport = await JwApi.getAcademic();
      this.report = report;
      const courses: CourseItem[] = await JwApi.getCoursesSmart(AppState.term.id, false);
      this.courses = courses;
      const scores: TermScore[] = await JwApi.getTermScores();
      this.termScores = scores;
      LogStore.log('学业', '页面加载', '完成',
        `网络更新 GPA=${report.gpa} 课程${courses.length}节 成绩${scores.length}学期`);
      // 总体成绩（累计绩点/已修学分/成绩分布/课程明细）：独立拉取，失败不影响其它数据
      try {
        const overall: OverallGrades = await JwApi.getOverallGrades();
        this.overallStats = overall.stats;
        this.overallCourses = overall.courses;
      } catch (e2) {
        LogStore.log('学业', '总体成绩', '异常', LogStore.errorOf(e2 as Object));
      }
    } catch (e) {
      // 网络异常时保持缓存
      LogStore.log('学业', '页面加载', '网络异常', LogStore.errorOf(e as Object));
    }
    this.loading = false;
  }

  /** 下拉刷新：重新加载学业情况 */
  private async buttonRefresh(): Promise<void> {
    if (this.refreshing) {
      return;
    }
    this.refreshing = true;
    await this.load();
    this.refreshing = false;
  }

  private async onRefresh(): Promise<void> {
    await this.load();
    this.refreshing = false;
  }
  private currentGpa(): number {
    return this.report.gpa;
  }

  /** 各课程分类（从学业页提取） */
  private categories(): CreditCategory[] {
    return this.report.categories;
  }

  @Builder
  gpaCard() {
    Column() {
      Text('平均学分绩点（GPA）')
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Row() {
        Text(this.currentGpa().toFixed(2))
          .fontSize(48)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand'))
        Text('/ 5.0')
          .fontSize(16)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ left: 6, bottom: 8 })
      }
      .alignItems(VerticalAlign.Bottom)
      .margin({ top: 4 })

      Text(`数据来源: 教务系统学业页（统计时间 ${new Date().toLocaleDateString('zh-CN')}）`)
        .fontSize(11)
        .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
        .margin({ top: 4 })
    }
    .width('100%')
    .padding(20)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  overviewRow() {
    Row() {
      StatCell({
        value: `${this.report.totalEarned}`,
        label: '已修',
        color: $r('app.color.brand')
      })
      Divider()
        .vertical(true)
        .height(28)
        .color($r('app.color.divider'))
      StatCell({
        value: `${this.report.studyingCount}`,
        label: '在读',
        color: $r('app.color.accent_blue')
      })
      Divider()
        .vertical(true)
        .height(28)
        .color($r('app.color.divider'))
      StatCell({
        value: `${this.report.unearnedCount}`,
        label: '未修',
        color: $r('app.color.accent_orange')
      })
      Divider()
        .vertical(true)
        .height(28)
        .color($r('app.color.divider'))
      StatCell({
        value: `${this.report.failedCount}`,
        label: '未通过',
        color: this.report.failedCount > 0 ? $r('app.color.state_danger') : $r('app.color.text_primary')
      })
    }
    .width('100%')
    .padding({ top: 18, bottom: 18 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
    .margin({ top: 14 })
  }

  @Builder
  categorySection() {
    Column() {
      Row() {
        Text('课程分类与修读情况')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .margin({ bottom: 14 })

      ForEach(this.categories(), (item: CreditCategory, index: number) => {
        Column() {
          Row() {
            Text(item.name)
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${item.earned.toFixed(1)} / ${item.required.toFixed(1)}`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
            Text(`  ${this.percent(item.earned, item.required)}%`)
              .fontSize(12)
              .fontColor(this.pctColor(this.percent(item.earned, item.required)))
          }
          .width('100%')

          Stack({ alignContent: Alignment.Start }) {
            Row()
              .width('100%')
              .height(7)
              .backgroundColor($r('app.color.bg_chip'))
              .borderRadius(4)
            Row()
              .width(`${this.percent(item.earned, item.required)}%`)
              .height(7)
              .backgroundColor(this.pctColor(this.percent(item.earned, item.required)))
              .borderRadius(4)
          }
          .width('100%')
          .margin({ top: 6 })
        }
        .width('100%')
        .margin({ bottom: 14 })
      }, (item: CreditCategory) => item.name)
    }
    .width('100%')
    .padding(18)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
    .margin({ top: 14 })
  }

  @Builder
  warningSection() {
    Column() {
      Row() {
        Text('学业提醒')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .margin({ bottom: 10 })

      ForEach(this.report.warnings, (text: string, index: number) => {
        Stack({ alignContent: Alignment.Start }) {
          // 序号圆圈：固定在左上（Stack 定位，不受文本行数影响）
          Row() {
            Text(`${index + 1}`)
              .fontSize(11)
              .fontColor($r('app.color.state_warn'))
              .width(18)
              .height(18)
              .lineHeight(18)
              .textAlign(TextAlign.Center)
              .backgroundColor($r('app.color.bg_chip'))
              .borderRadius(9)
          }
          .width(18)
          .height(18)
          .position({ x: 0, y: 0 })

          // 文字：左侧预留 28vp 给序号圆圈，width 100% 自然换行
          Text(text)
            .fontSize(13)
            .lineHeight(21)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 28 })
            .width('100%')
        }
        .width('100%')
        .margin({ bottom: 10 })
      }, (text: string) => text)
    }
    .width('100%')
    .padding(18)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
    .margin({ top: 14 })
  }

  /** 计算学分完成百分比（0-100，超 100 截断） */
  /** 总体（累计）成绩卡片：累计绩点 / 已修学分 / 总课程 */
  @Builder
  overallCard() {
    Column() {
      Row() {
        Text('总体成绩')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.overallCourses.length > 0 ? `${this.overallCourses.length} 门` : '累计')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .margin({ bottom: 12 })

      Row() {
        StatCell({
          value: this.overallStats !== null ? this.overallStats.gpa : '--',
          label: '累计绩点'
        })
        StatCell({
          value: this.overallStats !== null ? this.overallStats.credits : '--',
          label: '已修学分'
        })
        StatCell({
          value: this.overallStats !== null ? `${this.overallStats.courseCount}` : '--',
          label: '总课程'
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .padding(18)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
    .margin({ top: 14 })
  }

  /** 成绩分布（优 ≥90 / 良 ≥80 / 中 ≥70 / 及 ≥60），移植自参考项目「成绩分布」 */
  @Builder
  distributionSection() {
    Column() {
      Row() {
        Text('成绩分布')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('按已统计课程划分')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .margin({ bottom: 12 })

      // 分段条：按门数占比
      Row() {
        if (this.distTotal() > 0) {
          Row()
            .layoutWeight(this.distCount(0) > 0 ? this.distCount(0) : 0.0001)
            .height(8)
            .backgroundColor($r('app.color.brand'))
          Row()
            .layoutWeight(this.distCount(1) > 0 ? this.distCount(1) : 0.0001)
            .height(8)
            .backgroundColor($r('app.color.accent_blue'))
          Row()
            .layoutWeight(this.distCount(2) > 0 ? this.distCount(2) : 0.0001)
            .height(8)
            .backgroundColor($r('app.color.accent_orange'))
          Row()
            .layoutWeight(this.distCount(3) > 0 ? this.distCount(3) : 0.0001)
            .height(8)
            .backgroundColor($r('app.color.accent_purple'))
        } else {
          Row()
            .layoutWeight(1)
            .height(8)
            .backgroundColor($r('app.color.bg_chip'))
        }
      }
      .width('100%')
      .borderRadius(4)
      .clip(true)
      .margin({ bottom: 12 })

      Row() {
        this.distItem('优', this.distCount(0), $r('app.color.brand'))
        this.distItem('良', this.distCount(1), $r('app.color.accent_blue'))
        this.distItem('中', this.distCount(2), $r('app.color.accent_orange'))
        this.distItem('及', this.distCount(3), $r('app.color.accent_purple'))
      }
      .width('100%')
    }
    .width('100%')
    .padding(18)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
    .margin({ top: 14 })
  }

  /** 分布图例单项 */
  @Builder
  distItem(label: string, count: number, color: ResourceColor) {
    Column() {
      Row() {
        Row()
          .width(8)
          .height(8)
          .backgroundColor(color)
          .borderRadius(4)
        Text(label)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ left: 5 })
      }
      .alignItems(VerticalAlign.Center)
      Text(`${count} 门`)
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
  }

  /** 课程明细（成绩/学分/绩点），默认显示前 8 条 */
  @Builder
  courseDetailSection() {
    Column() {
      Row() {
        Text('课程明细')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(this.overallCourses.length > 0
          ? `共 ${this.overallCourses.length} 门 · ${this.detailTermCount()} 个学期` : '暂无数据')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .margin({ bottom: 10 })

      if (this.overallCourses.length === 0) {
        Text('暂无课程明细：需教务系统开放学业情况-课程修读数据')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
      } else {
        ForEach(this.detailList(), (item: ScoreItem) => {
          Row() {
            Column() {
              Text(item.courseName)
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
              Text(`${this.termLabelOf(item.termId)}${item.kclbmc.length > 0 ? ` · ${item.kclbmc}` : (item.courseType.length > 0 ? ` · ${item.courseType}` : '')}`)
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .margin({ top: 2 })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)

            Text(item.credit > 0 ? `${item.credit} 学分` : '')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .margin({ right: 10 })
            Text(item.gradePoint > 0 ? `绩点 ${item.gradePoint}` : '')
              .fontSize(11)
              .fontColor($r('app.color.text_secondary'))
              .margin({ right: 10 })
            Text(item.scoreText)
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(this.scoreTone(item.scoreText))
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ top: 7, bottom: 7 })
        }, (item: ScoreItem) => `${item.courseName}-${item.termId}`)

        if (this.overallCourses.length > 8) {
          Text(this.detailExpanded ? '收起' : `展开全部 ${this.overallCourses.length} 门`)
            .fontSize(12)
            .fontColor(Theme.colorOf(this.themeColor))
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding({ top: 10 })
            .onClick(() => {
              this.detailExpanded = !this.detailExpanded;
            })
        }
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
    .margin({ top: 14 })
  }

  /** 明细展示列表（默认前 8 条） */
  private detailList(): ScoreItem[] {
    return this.detailExpanded ? this.overallCourses : this.overallCourses.slice(0, 8);
  }

  /** 明细覆盖的学期数（证明"全部学期"） */
  private detailTermCount(): number {
    const ids: string[] = [];
    for (const c of this.overallCourses) {
      if (c.termId.length > 0 && ids.indexOf(c.termId) < 0) {
        ids.push(c.termId);
      }
    }
    return ids.length;
  }

  /** 学期 id → 学期名称（如 2024-2025-1 → 2024-2025学年 第一学期） */
  private termLabelOf(termId: string): string {
    if (termId.length === 0) {
      return '学期未知';
    }
    if (this.termLabels.length === 0) {
      const terms: TermInfo[] = JwApi.buildLocalTerms();
      for (const t of terms) {
        this.termLabels.push(t);
      }
    }
    for (const t of this.termLabels) {
      if (t.id === termId) {
        return t.label;
      }
    }
    return termId;
  }

  /** 分布门数（0=优 1=良 2=中 3=及） */
  private distCount(index: number): number {
    const s: OverallGradeStats | null = this.overallStats;
    if (s === null) {
      return 0;
    }
    if (index === 0) {
      return s.excellent;
    }
    if (index === 1) {
      return s.good;
    }
    if (index === 2) {
      return s.medium;
    }
    return s.pass;
  }

  /** 分布总门数 */
  private distTotal(): number {
    return this.distCount(0) + this.distCount(1) + this.distCount(2) + this.distCount(3);
  }

  /** 成绩文本 → 颜色（≥90 品牌色 / ≥80 蓝 / ≥70 橙 / 其它 紫） */
  private scoreTone(text: string): ResourceColor {
    let digits: string = '';
    for (let i: number = 0; i < text.length; i++) {
      const ch: string = text.charAt(i);
      if (ch >= '0' && ch <= '9') {
        digits += ch;
      }
    }
    const n: number = digits.length > 0 ? Number(digits) : -1;
    if (n >= 90) {
      return $r('app.color.brand');
    }
    if (n >= 80) {
      return $r('app.color.accent_blue');
    }
    if (n >= 70) {
      return $r('app.color.accent_orange');
    }
    if (n >= 60) {
      return $r('app.color.accent_purple');
    }
    return $r('app.color.text_secondary');
  }

  private percent(earned: number, required: number): number {
    if (required <= 0) {
      return 0;
    }
    const p: number = Math.round(earned / required * 100);
    return p > 100 ? 100 : p;
  }

  /** 进度条颜色按完成度分档（静态语义，不随主题）：<40 橙 / 40-70 琥珀 / 70-95 农大绿 / ≥95 深绿 */
  private pctColor(p: number): ResourceColor {
    if (p < 40) {
      return $r('app.color.accent_orange');
    }
    if (p < 70) {
      return '#D98E04';
    }
    if (p < 95) {
      return '#079841';
    }
    return '#0B6E3B';
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // 二级页壁纸底层（无壁纸回 bg_page，不透下层）
        WallpaperFill()
        Column() {
        if (this.loading) {
          // 悬浮顶栏下垂直居中
          Column() {
            LoadingTip()
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else {
          Refresh({ refreshing: $$this.refreshing }) {
          Scroll() {
            Column() {
              // 顶栏让位 spacer（与成绩页同款：下拉刷新指示位置统一）
              Column()
                .width('100%')
                .height(this.getUIContext().px2vp(this.topInsetPx) + 60 + (this.barStyle === 'legacy' ? 14 : 0))
              this.gpaCard()
              this.overallCard()
              this.distributionSection()
              this.overviewRow()
              this.categorySection()
              this.courseDetailSection()
              this.warningSection()
              Column()
                .height(this.getUIContext().px2vp(this.bottomInsetPx) + 24)
            }
            .width('100%')
            .padding({ left: 16, right: 16 })
          }
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .align(Alignment.Top)
          .edgeEffect(EdgeEffect.Spring)
          }
          .layoutWeight(1)
          .height('100%')
          .pullToRefresh(false)
          .onRefreshing(() => { this.onRefresh(); })
        }
      }
      .width('100%')
      .height('100%')
      // 全局壁纸：二级页根背景透明，透出主框架底层壁纸（无壁纸时由 MainView 底层纯色兜底）
      .backgroundColor(Color.Transparent)

        // 顶栏悬浮（最上层）：正文 Scroll 顶部已让位，上滑可滚入其渐变下层透出
        PageHeader({
          title: '学业情况',
          subtitle: AppState.profile !== null ? `${AppState.profile.major} · ${AppState.profile.grade}` : '',
          actionText: '刷新',
          actionTone: 'glass',
          onAction: () => {
            this.buttonRefresh();
          },
          onBack: () => {
            AppState.stack.pop();
          }
        })

        AntiPeepOverlay({ isPeeped: this.isPeeped })
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.bg_page'))
    .hideTitleBar(true)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
  }
}