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
import { CourseItem, AcademicReport, CreditCategory, TermScore } from '../model/Models';
import { EMPTY_REPORT } from '../model/Empty';
import { LoadingTip, PageHeader, StatCell } from './common/UiKit';

@Component
export struct AcademicPage {
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @State report: AcademicReport = EMPTY_REPORT;
  @State courses: CourseItem[] = [];
  @State termScores: TermScore[] = [];
  @State loading: boolean = true;

  /** 页面出现：触发学业数据加载 */
  aboutToAppear(): void {
    this.load();
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
    try {
      const report: AcademicReport = await JwApi.getAcademic();
      this.report = report;
      const courses: CourseItem[] = await JwApi.getCourses(AppState.term.id);
      this.courses = courses;
      const scores: TermScore[] = await JwApi.getTermScores();
      this.termScores = scores;
    } catch (e) {
      // 网络异常时保持缓存
    }
    this.loading = false;
  }

  /** 当前学期 GPA（直接读教务页算好的，不重新计算） */
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

      Text(`数据来源：教务系统学业页（统计时间 ${new Date().toLocaleDateString('zh-CN')}）`)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
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
              .fontColor($r('app.color.brand'))
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
              .backgroundColor($r('app.color.brand'))
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
  private percent(earned: number, required: number): number {
    if (required <= 0) {
      return 0;
    }
    const p: number = Math.round(earned / required * 100);
    return p > 100 ? 100 : p;
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: '学业情况',
          subtitle: AppState.profile !== null ? `${AppState.profile.major} · ${AppState.profile.grade}` : '',
          onBack: () => {
            AppState.stack.pop();
          }
        })

        if (this.loading) {
          LoadingTip()
        } else {
          Scroll() {
            Column() {
              this.gpaCard()
              this.overviewRow()
              this.categorySection()
              this.warningSection()
              Column()
                .height(px2vp(this.bottomInsetPx) + 24)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14 })
          }
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .align(Alignment.Top)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .hideTitleBar(true)
  }
}