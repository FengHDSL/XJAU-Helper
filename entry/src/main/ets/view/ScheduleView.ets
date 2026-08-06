/**
 * 课程表：周视图（左侧节次 + 7 天列，课程块按节次跨行）
 * 顶部支持学年/学期/周次选择，header 显示几月几日
 */
import { JwApi } from '../api/JwApi';
import { AppState } from '../common/AppState';
import { Const, SectionTime } from '../common/Constants';
import { DateUtil } from '../common/DateUtil';
import { Theme } from '../common/ThemeUtil';
import { CourseItem, TermInfo } from '../model/Models';
import { EMPTY_COURSE } from '../model/Empty';
import { LoadingTip } from './common/UiKit';

const CELL_H: number = 58;

@Component
export struct ScheduleView {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @State courses: CourseItem[] = [];
  @State terms: TermInfo[] = [];
  @State selectedTermIndex: number = 0;
  @State viewWeek: number = 1;
  @State loading: boolean = true;
  @State showSheet: boolean = false;
  @State showWeekSheet: boolean = false;
  @State showTermSheet: boolean = false;
  @State selected: CourseItem = EMPTY_COURSE;
  private currentWeek: number = 1;
  /** 全局学期广播（首页顶栏切换学期时同步本页） */
  @StorageProp('currentTermId') @Watch('onGlobalTermChanged') currentTermId: string = '';

  /** 页面出现：计算当前周次并加载课表 */
  aboutToAppear(): void {
    if (AppState.mockCurrentWeek > 0) {
      this.currentWeek = AppState.mockCurrentWeek;
    } else {
      const week: number = DateUtil.weekOfTerm(AppState.term, new Date());
      this.currentWeek = week < 1 ? 1 : week;
    }
    this.viewWeek = this.currentWeek;
    // 注册全局学期切换监听（首页顶栏切换后立即同步本页）
    AppState.registerTermListener('schedule', () => {
      this.onGlobalTermChanged();
    });
    this.load();
    // 首页"下次课"点击跳转：自动打开对应课程详情
    const pc: CourseItem | null = AppState.pendingCourse;
    if (pc !== null && pc.id.length > 0) {
      AppState.pendingCourse = null;
      this.selected = pc;
      this.showSheet = true;
    }
  }

  /** 首页顶栏切换学期（JwApi.setTerm 广播 currentTermId）后同步本页课表：直接用新学期重载课表 */
  private async onGlobalTermChanged(): Promise<void> {
    // 同步 selectedTermIndex 到 AppState.term.id（纠正任何错位）
    const id: string = AppState.term.id;
    for (let i: number = 0; i < this.terms.length; i++) {
      if (this.terms[i].id === id) {
        this.selectedTermIndex = i;
        break;
      }
    }
    // 清空旧课表 + 强制按 AppState.term 重载（不依赖缓存，避免与新学期混淆）
    this.courses = [];
    this.loading = true;
    try {
      const list: CourseItem[] = await JwApi.getCourses(AppState.term.id);
      this.courses = list;
      const week: number = DateUtil.weekOfTerm(AppState.term, new Date());
      this.currentWeek = week < 1 ? 1 : week;
      this.viewWeek = this.currentWeek;
    } catch (e) {
      // ignore
    } finally {
      this.loading = false;
    }
  }

  private async load(): Promise<void> {
    this.loading = true;
    try {
      if (this.terms.length === 0) {
        this.terms = await JwApi.getTerms();
        // 默认选中当前学期（最新学年第一学期，terms[0]）
        this.selectedTermIndex = 0;
        for (let i = 0; i < this.terms.length; i++) {
          if (this.terms[i].id === AppState.term.id) {
            this.selectedTermIndex = i;
            break;
          }
        }
      }
      const term: TermInfo = this.terms[this.selectedTermIndex] ?? AppState.term;
      // 先用缓存（仅当前学期有缓存）
      if (term.id === AppState.term.id) {
        const cached: CourseItem[] = JwApi.loadCachedCourses();
        if (cached.length > 0) {
          this.courses = cached;
        }
      }
      // 强制刷新（无论缓存是否命中，非 mock 模式都去拉取真实数据）
      const fresh: CourseItem[] = await JwApi.getCourses(term.id);
      if (fresh.length > 0) {
        this.courses = fresh;
      } else if (term.id === AppState.term.id) {
        // 接口返回空才回落到缓存
        const cached: CourseItem[] = JwApi.loadCachedCourses();
        if (cached.length > 0) {
          this.courses = cached;
        }
      }
    } catch (e) {
      // 网络异常时保持缓存
      const cached: CourseItem[] = JwApi.loadCachedCourses();
      if (cached.length > 0) {
        this.courses = cached;
      }
    } finally {
      this.loading = false;
    }
  }

  /** 当前选中的学期对象 */
  private currentTerm(): TermInfo {
    return this.terms[this.selectedTermIndex] ?? AppState.term;
  }

  /** 课程详情 sheet 中的"上课时间"行内容 */
  private selectedTimeText(): string {
    const startSec: number = this.selected.startSection;
    const endSec: number = this.selected.endSection;
    const period: string = Const.SECTION_PERIODS[startSec - 1] ?? '';
    const dateLabel: string = `${Const.WEEK_LABELS[this.selected.weekday - 1]}（${DateUtil.formatCn(this.dateOf(this.selected.weekday))}）`;
    return `${dateLabel} ${period} 第 ${startSec}-${endSec} 节（${DateUtil.sectionRange(startSec, endSec)}）`;
  }

  /** 取某星期几当天（当前周）的课程列表 */
  private coursesOfDay(weekday: number): CourseItem[] {
    const list: CourseItem[] = [];
    for (const c of this.courses) {
      if (c.weekday === weekday && c.weeks.includes(this.viewWeek)) {
        list.push(c);
      }
    }
    return list;
  }

  /** 本周总课程节数 */
  private weekCourseCount(): number {
    let count: number = 0;
    for (const c of this.courses) {
      if (c.weeks.includes(this.viewWeek)) {
        count += c.endSection - c.startSection + 1;
      }
    }
    return count;
  }

  /** 周次前/后切换（delta=±1，越界钳制） */
  private changeWeek(delta: number): void {
    const next: number = this.viewWeek + delta;
    if (next < 1 || next > this.currentTerm().totalWeeks) {
      return;
    }
    this.viewWeek = next;
  }

  /** 全部周次列表（1..totalWeeks），用于快速选择 */
  private weekList(): number[] {
    const list: number[] = [];
    for (let i = 1; i <= this.currentTerm().totalWeeks; i++) {
      list.push(i);
    }
    return list;
  }

  private async selectTerm(index: number): Promise<void> {
    this.selectedTermIndex = index;
    this.showTermSheet = false;
    this.loading = true;
    try {
      const term: TermInfo = this.currentTerm();
      // 切换学期时同步更新当前学期（影响 AppState 内的学期）
      AppState.term = term;
      const list: CourseItem[] = await JwApi.getCourses(term.id);
      this.courses = list;
      const week: number = DateUtil.weekOfTerm(term, new Date());
      this.currentWeek = week < 1 ? 1 : week;
      this.viewWeek = this.currentWeek;
    } catch (e) {
      // ignore
    } finally {
      this.loading = false;
    }
  }

  /** 周次 header 单格的副文案：几月几日 */
  private dateOf(weekday: number): Date {
    return DateUtil.dateOfWeekDay(this.currentTerm(), this.viewWeek, weekday);
  }

  @Builder
  topBar() {
    // 顶部标题栏：浅色=主题色（中国红/天空蓝/农大绿），深色=黑色；文字白色
    Column() {
      Row() {
        Column() {
          Text('课程表')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
          // 学期选择器（点击弹层切换）
          Row() {
            Text(this.currentTerm().label)
              .fontSize(11)
              .fontColor(this.isDarkMode ? $r('app.color.text_tertiary') : '#CCFFFFFF')
            // 深色模式用白底图标（expand_dark.png 是白 chevron + 透明背景），浅色模式用原图
            Image($r('app.media.list'))
              .width(14)
              .height(14)
              .fillColor(this.isDarkMode ? $r('app.color.text_tertiary') : '#CCFFFFFF')
              .margin({ left: 3 })
          }
          .margin({ top: 3 })
          .onClick(() => {
            this.showTermSheet = true;
          })
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        // 右侧："回到本周" + 周次切换器，与"课程表"标题水平中线对齐
        if (this.viewWeek !== this.currentWeek) {
          Text('回到本周')
            .fontSize(11)
            .fontColor(Color.White)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor('#33FFFFFF')
            .borderRadius(12)
            .margin({ right: 8 })
            .onClick(() => {
              this.viewWeek = this.currentWeek;
            })
        }

        // 右侧：周次切换器。点击"第 N 周"弹出周次选择弹层（原 📅 按钮功能并入）
        Row() {
          Text('‹')
            .fontSize(16)
            .fontColor(Color.White)
            .width(22)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.changeWeek(-1);
            })
          Text(`第 ${this.viewWeek} 周`)
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .width(56)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.showWeekSheet = true;
            })
          Text('›')
            .fontSize(16)
            .fontColor(Color.White)
            .width(22)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.changeWeek(1);
            })
        }
        .backgroundColor('#33FFFFFF')
        .borderRadius(14)
        .padding({ top: 4, bottom: 4 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center) // 右侧"回到本周"/周次组件与"课程表"标题水平中线对齐
    }
    .width('100%')
    .height(px2vp(this.topInsetPx) + 60)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 16, right: 16, bottom: 12, top: px2vp(this.topInsetPx) + 12 })
    .backgroundColor(this.isDarkMode ? '#1A1D1C' : Theme.colorOf(this.themeColor))
  }

  @Builder
  weekHeader() {
    Row() {
      Column() {
        Text(`${this.dateOf(1).getMonth() + 1}月`)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width(40)
      .justifyContent(FlexAlign.Center)

      ForEach(Const.WEEK_SHORT, (label: string, index: number) => {
        Column() {
          Text(label)
            .fontSize(12)
            .fontWeight(this.isToday(index + 1) ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.isToday(index + 1) ? $r('app.color.brand') : $r('app.color.text_secondary'))
          Text(`${this.dateOf(index + 1).getMonth() + 1}/${this.dateOf(index + 1).getDate()}`)
            .fontSize(11)
            .fontColor(this.isToday(index + 1) ? $r('app.color.brand') : $r('app.color.text_tertiary'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .padding({ top: 7, bottom: 7 })
        .backgroundColor(this.isToday(index + 1) ? $r('app.color.brand_light') : Color.Transparent)
        .borderRadius(8)
      }, (label: string) => label)
    }
    .width('100%')
    .padding({ left: 6, right: 6, top: 4, bottom: 4 })
    .backgroundColor($r('app.color.bg_card'))
  }

  /** 判断某星期几是否今天（同周同星期才高亮） */
  private isToday(weekday: number): boolean {
    return this.viewWeek === this.currentWeek && DateUtil.weekdayOf(new Date()) === weekday;
  }

  @Builder
  sectionColumn() {
    Column() {
      ForEach(Const.SECTIONS, (item: SectionTime) => {
        Column() {
          Text(`${item.index}`)
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
          Text(item.start)
            .fontSize(9)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 2 })
          Text(item.end)
            .fontSize(9)
            .fontColor($r('app.color.text_tertiary'))
        }
        .width('100%')
        .height(CELL_H)
        .justifyContent(FlexAlign.Center)
      }, (item: SectionTime) => `s${item.index}`)
    }
    .width(40)
  }

  @Builder
  dayColumn(weekday: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        ForEach(Const.SECTIONS, (item: SectionTime) => {
          Column()
            .width('100%')
            .height(CELL_H)
            .border({
              width: { bottom: 0.5, right: 0.5 },
              color: $r('app.color.divider')
            })
        }, (item: SectionTime) => `g${weekday}-${item.index}`)
      }
      .width('100%')

      ForEach(this.coursesOfDay(weekday), (course: CourseItem) => {
        Column() {
          Text(course.name)
            .fontSize(11)
            .lineHeight(14)
            .fontColor(Const.COURSE_FG[course.colorIndex])
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(course.location)
            .fontSize(9)
            .lineHeight(12)
            .fontColor(Const.COURSE_FG[course.colorIndex])
            .opacity(0.85)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 2 })
        }
        .width('100%')
        .height((course.endSection - course.startSection + 1) * CELL_H - 4)
        .padding(4)
        .backgroundColor(Const.COURSE_BG[course.colorIndex])
        .borderRadius(8)
        .position({ x: 0, y: (course.startSection - 1) * CELL_H + 2 })
        .onClick(() => {
          this.selected = course;
          this.showSheet = true;
        })
      }, (course: CourseItem) => course.id)
    }
    .layoutWeight(1)
    .height(CELL_H * Const.SECTION_COUNT)
  }

  @Builder
  courseSheet() {
    Column() {
      if (this.selected.id.length > 0) {
        Row() {
          Column()
            .width(4)
            .height(20)
            .borderRadius(2)
            .backgroundColor(Const.COURSE_FG[this.selected.colorIndex])
          Text(this.selected.name)
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ bottom: 16 })

        this.sheetRow('任课教师', this.selected.teacher)
        this.sheetRow('上课地点', this.selected.location)
        this.sheetRow('上课时间', this.selectedTimeText())
        this.sheetRow('上课周次', this.selected.weeksText)
        this.sheetRow('课程属性', `${this.selected.courseType} · ${this.selected.credit} 学分`)

        Button('关闭')
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor($r('app.color.brand'))
          .backgroundColor($r('app.color.brand_light'))
          .borderRadius(12)
          .margin({ top: 18 })
          .onClick(() => {
            this.showSheet = false;
          })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
  }

  @Builder
  weekPickerSheet() {
    Column() {
      Text('选择周次')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 14 })
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
        ForEach(this.weekList(), (w: number) => {
          Column() {
            Text(`第${w}周`)
              .fontSize(13)
              .fontWeight(w === this.viewWeek ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(w === this.viewWeek ? $r('app.color.brand_on') :
                (w === this.currentWeek ? $r('app.color.brand') : $r('app.color.text_primary')))
          }
          .width('18%')
          .height(42)
          .justifyContent(FlexAlign.Center)
          .backgroundColor(w === this.viewWeek ? $r('app.color.brand') :
            (w === this.currentWeek ? $r('app.color.brand_light') : $r('app.color.bg_chip')))
          .borderRadius(10)
          .margin({ bottom: 10 })
          .onClick(() => {
            this.viewWeek = w;
            this.showWeekSheet = false;
          })
        }, (w: number) => `pick${w}`)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
  }

  @Builder
  termPickerSheet() {
    Column() {
      Text('选择学期')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 14 })
      if (this.terms.length === 0) {
        Text('暂无可查询的学期')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 12 })
      } else {
        ForEach(this.terms, (term: TermInfo, index: number) => {
          Row() {
            Text(term.label)
              .fontSize(14)
              .fontColor(index === this.selectedTermIndex ? $r('app.color.brand_on') : $r('app.color.text_primary'))
              .layoutWeight(1)
            if (index === this.selectedTermIndex) {
              Text('✓')
                .fontSize(16)
                .fontColor($r('app.color.brand_on'))
            }
          }
          .width('100%')
          .height(46)
          .padding({ left: 16, right: 16 })
          .backgroundColor(index === this.selectedTermIndex ? $r('app.color.brand') : $r('app.color.bg_chip'))
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

  @Builder
  sheetRow(label: string, value: string) {
    Row() {
      // 课程主题色小圆点，替代原 Emoji 图标
      Column()
        .width(6)
        .height(6)
        .borderRadius(3)
        .backgroundColor(Const.COURSE_FG[this.selected.colorIndex])
        .margin({ right: 10 })
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .width(62)
      Text(value)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 8, bottom: 8 })
  }

  build() {
    Column() {
      this.topBar()
      // 把"选择周次"弹层绑在 weekHeader 自己的容器上（与根 Column 的"选择学期"弹层分开锚点）
      Column() {
        this.weekHeader()
      }
      .width('100%')
      .bindSheet($$this.showWeekSheet, this.weekPickerSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        backgroundColor: $r('app.color.bg_card'),
        title: { title: '选择周次' }
      })
      // 课程详情弹层绑定在内层容器上，与"选择周次"+"选择学期"分三个独立锚点
      // 横屏/平板下内容限宽 720vp 并居中（一多适配），单一 Scroll 占满剩余空间
      Column() {
        if (this.loading) {
          LoadingTip()
        } else if (this.courses.length === 0) {
          LoadingTip({ text: '本学期暂无课程，可点击顶部"切换学期"查看其它学期' })
        } else {
          Row() {
            Scroll() {
              Column() {
                Row() {
                  this.sectionColumn()
                  this.dayColumn(1)
                  this.dayColumn(2)
                  this.dayColumn(3)
                  this.dayColumn(4)
                  this.dayColumn(5)
                  this.dayColumn(6)
                  this.dayColumn(7)
                }
                .width('100%')
                .alignItems(VerticalAlign.Top)

                Row() {
                  Text(`本周共 ${this.weekCourseCount()} 节课`)
                    .fontSize(11)
                    .fontColor($r('app.color.text_tertiary'))
                  Blank()
                  Text('点击课程查看详情')
                    .fontSize(11)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .width('100%')
                .padding({ left: 16, right: 16, top: 14, bottom: 100 }) // 底部预留悬浮底栏高度，避免内容被遮挡
              }
              .width('100%')
            }
            .width(720)
            .constraintSize({ maxWidth: '100%' })
            .height('100%')
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .backgroundColor($r('app.color.bg_page'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center) // 横屏/平板下课表居中
        }
      }
      .width('100%')
      .layoutWeight(1)
      // 悬浮底栏模式下 Scroll 内容区延伸到屏幕底部，靠内容自身 bottom padding 预留空间
      .bindSheet($$this.showSheet, this.courseSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        backgroundColor: $r('app.color.bg_card'),
        title: { title: '课程详情' }
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    .bindSheet($$this.showTermSheet, this.termPickerSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: $r('app.color.bg_card'),
      title: { title: '选择学期' }
    })
  }
}