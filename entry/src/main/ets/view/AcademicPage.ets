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
import { CourseItem, AcademicReport, CreditCategory, TermScore, ScoreItem } from '../model/Models';
import { EMPTY_REPORT } from '../model/Empty';
import { LoadingTip, PageHeader, StatCell } from './common/UiKit';

@Component
export struct AcademicPage {
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @State report: AcademicReport = EMPTY_REPORT;
  @State courses: CourseItem[] = [];
  @State termScores: TermScore[] = [];
  @State loading: boolean = true;
  @State selectedCategory: CreditCategory | null = null;
  @State showCategorySheet: boolean = false;

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

  /** 单条成绩的修读状态：
   *  - 已修：cj ≥ 60 且 ksxz 不是"补考/重修"
   *  - 未通过：cj < 60，或 cj ≥ 60 但 ksxz 含补考/重修（说明之前有未通过记录）
   *  - 在修：课程在当前学期课表中，但还未出成绩
   *  - 未修：不在成绩、不在课表中
   */
  /** 判断单条成绩修读状态：已修(一次通过) / 未通过(含补考重修) */
  private statusOf(s: ScoreItem): 'completed' | 'failed' {
    const isRemedial: boolean = s.examType.includes('补考') || s.examType.includes('重修');
    if (s.score >= 0 && s.score < 60) {
      return 'failed';
    }
    if (s.score >= 60 && isRemedial) {
      return 'failed';
    }
    if (s.score >= 60) {
      return 'completed';
    }
    return 'completed';
  }

  /** 所有成绩按 category.name 过滤（kclbmc 模糊匹配）。无匹配则不过滤。 */
  private matchesCategory(s: ScoreItem, categoryName: string): boolean {
    if (s.kclbmc === '') {
      return false;
    }
    if (s.kclbmc.includes(categoryName) || categoryName.includes(s.kclbmc)) {
      return true;
    }
    // 类别关键词匹配：通识/专业
    const keywords: string[] = ['通识', '专业'];
    for (const kw of keywords) {
      if (categoryName.includes(kw) && s.kclbmc.includes(kw)) {
        return true;
      }
    }
    return false;
  }

  /** 该分类下：已修（一次通过） */
  private completedInCategory(name: string): ScoreItem[] {
    const list: ScoreItem[] = [];
    for (const t of this.termScores) {
      for (const s of t.items) {
        if (this.statusOf(s) === 'completed' && this.matchesCategory(s, name)) {
          list.push(s);
        }
      }
    }
    return list;
  }

  /** 该分类下：未通过（含补考/重修） */
  private failedInCategory(name: string): ScoreItem[] {
    const list: ScoreItem[] = [];
    for (const t of this.termScores) {
      for (const s of t.items) {
        if (this.statusOf(s) === 'failed' && this.matchesCategory(s, name)) {
          list.push(s);
        }
      }
    }
    return list;
  }

  /** 该分类下：在读（课表中且无成绩） */
  private studyingInCategory(name: string): CourseItem[] {
    const doneNames: Set<string> = new Set();
    for (const t of this.termScores) {
      for (const s of t.items) {
        doneNames.add(s.courseName);
      }
    }
    const list: CourseItem[] = [];
    for (const c of this.courses) {
      if (doneNames.has(c.name)) {
        continue;
      }
      // 课表侧没有 kclbmc，按类别关键词粗分
      const keywords: string[] = ['通识', '专业'];
      let match: boolean = false;
      for (const kw of keywords) {
        if (name.includes(kw)) {
          match = true;
          break;
        }
      }
      if (match) {
        list.push(c);
      }
    }
    return list;
  }

  /** 所有未通过课程（不分类） */
  private failedCourses(): ScoreItem[] {
    const list: ScoreItem[] = [];
    for (const t of this.termScores) {
      for (const s of t.items) {
        if (this.statusOf(s) === 'failed') {
          list.push(s);
        }
      }
    }
    return list;
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

  /** 分类详情弹层（已完成 / 在读 / 未修 / 未通过） */
  @Builder
  categorySheet() {
    Column() {
      if (this.selectedCategory !== null) {
        Row() {
          Text(this.selectedCategory.name)
            .fontSize(17)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text(`${this.selectedCategory.earned.toFixed(1)} / ${this.selectedCategory.required.toFixed(1)} 学分`)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .margin({ bottom: 14 })

        // 已完成
        Column() {
          Row() {
            Text('✓ 已完成')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.state_success'))
            Blank()
            Text(`${this.completedInCategory(this.selectedCategory.name).length} 项`)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .margin({ top: 8, bottom: 4 })

          if (this.completedInCategory(this.selectedCategory.name).length > 0) {
            ForEach(this.completedInCategory(this.selectedCategory.name), (s: ScoreItem) => {
              Row() {
                Text(s.courseName)
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(s.scoreText)
                  .fontSize(12)
                  .fontColor($r('app.color.state_success'))
                  .margin({ left: 8 })
              }
              .width('100%')
              .padding({ top: 5, bottom: 5 })
            }, (s: ScoreItem) => s.id)
          } else {
            Text('暂无已完成课程')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
              .padding({ top: 6, bottom: 6 })
          }
        }
        .width('100%')

        // 在读
        Column() {
          Row() {
            Text('◷ 在读')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.accent_blue'))
            Blank()
            Text(`${this.studyingInCategory(this.selectedCategory.name).length} 项`)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .margin({ top: 8, bottom: 4 })

          if (this.studyingInCategory(this.selectedCategory.name).length > 0) {
            ForEach(this.studyingInCategory(this.selectedCategory.name), (c: CourseItem) => {
              Row() {
                Text(c.name)
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${c.credit} 学分`)
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ left: 8 })
              }
              .width('100%')
              .padding({ top: 5, bottom: 5 })
            }, (c: CourseItem) => c.id)
          } else {
            Text('暂无在读课程')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
              .padding({ top: 6, bottom: 6 })
          }
        }
        .width('100%')

        // 未修
        Column() {
          Row() {
            Text('− 未修')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_tertiary'))
            Blank()
            Text(`${this.report.unearnedCount} 项`)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .margin({ top: 8, bottom: 4 })
          Text('未修课程数据需培养方案权限，当前未提供')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .padding({ top: 6, bottom: 6 })
        }
        .width('100%')

        // 未通过
        Column() {
          Row() {
            Text('✗ 未通过')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.state_danger'))
            Blank()
            Text(`${this.failedInCategory(this.selectedCategory.name).length} 项`)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          .width('100%')
          .margin({ top: 8, bottom: 4 })

          if (this.failedInCategory(this.selectedCategory.name).length > 0) {
            ForEach(this.failedInCategory(this.selectedCategory.name), (s: ScoreItem) => {
              Row() {
                Text(s.courseName)
                  .fontSize(13)
                  .fontColor($r('app.color.state_danger'))
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(s.scoreText)
                  .fontSize(12)
                  .fontColor($r('app.color.state_danger'))
                  .margin({ left: 8 })
              }
              .width('100%')
              .padding({ top: 5, bottom: 5 })
            }, (s: ScoreItem) => s.id)
          } else {
            Text('暂无未通过课程')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
              .padding({ top: 6, bottom: 6 })
          }
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
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
        Row() {
          Text(`${index + 1}`)
            .fontSize(11)
            .fontColor($r('app.color.state_warn'))
            .width(18)
            .height(18)
            .textAlign(TextAlign.Center)
            .backgroundColor($r('app.color.bg_chip'))
            .borderRadius(9)
          Text(text)
            .fontSize(13)
            .lineHeight(21)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .margin({ left: 10 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
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