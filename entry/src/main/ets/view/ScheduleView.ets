/**
 * 课程表：周视图（左侧节次 + 7 天列，课程块按节次跨行）
 * 顶部支持学年/学期/周次选择，header 显示几月几日
 * 设置弹窗（bindSheet 半屏，内容为 ScheduleSettingsPanel 组件）
 * 课程详情（bindSheet 半屏，内容为 CourseDetailPanel 组件）
 * 课程颜色：按课程名 hash 取固定色板（一门课一色），可单独为每门课指定颜色
 */
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import { JwApi } from '../api/JwApi';
import { AppState } from '../common/AppState';
import { Const, SectionTime } from '../common/Constants';
import { DataStore } from '../common/DataStore';
import { DateUtil } from '../common/DateUtil';
import { ScheduleConfig, COURSE_BG_HEX, COURSE_FG_HEX } from '../common/ScheduleConfig';
import { Theme } from '../common/ThemeUtil';
import { CourseItem, TermInfo } from '../model/Models';
import { EMPTY_COURSE } from '../model/Empty';
import { LoadingTip } from './common/UiKit';
import { ScheduleSettingsPanel } from './ScheduleSettingsPanel';
import { CourseDetailPanel } from './CourseDetailPanel';

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
  @State showSettingsSheet: boolean = false;
  @State selected: CourseItem = EMPTY_COURSE;
  // 课程表设置
  @State scheduleBg: string = ''; // base64 图片数据，空=无背景
  @State cfg: ScheduleConfig = new ScheduleConfig(); // 完整自定义配置
  /** 课程独立颜色（课程名 → 自定义 hex），空=按课程名 hash 默认 */
  @State customColors: Record<string, string> = {};
  private currentWeek: number = 1;
  /** 全局学期广播（首页顶栏切换学期时同步本页） */
  @StorageProp('currentTermId') @Watch('onGlobalTermChanged') currentTermId: string = '';

  /** 页面出现：计算当前周次并加载课表 + 恢复设置 */
  aboutToAppear(): void {
    // 恢复设置
    this.scheduleBg = DataStore.getScheduleBg();
    this.cfg = ScheduleConfig.load();
    this.customColors = this.loadCustomColors();
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

  /** 取某星期几"下周"的课程（灰色半透明预览，只显示本周没有的位置避免重叠） */
  private coursesOfNextWeek(weekday: number): CourseItem[] {
    const list: CourseItem[] = [];
    const nextW: number = this.viewWeek + 1;
    if (nextW > this.currentTerm().totalWeeks) {
      return list;
    }
    for (const c of this.courses) {
      if (c.weekday === weekday && c.weeks.includes(nextW) && !c.weeks.includes(this.viewWeek)) {
        list.push(c);
      }
    }
    return list;
  }

  /** 格子高度（vp，可配置） */
  private cellH(): number {
    return this.cfg.cellHeight;
  }

  /** 显示的星期几列表（周六周日开关） */
  private weekdays(): number[] {
    if (this.cfg.showWeekend) {
      return [1, 2, 3, 4, 5, 6, 7];
    }
    return [1, 2, 3, 4, 5];
  }

  /** 课程名 hash 索引 */
  private colorIdx(name: string): number {
    return JwApi.ensureColorIndex(name);
  }

  /** 读取课程独立颜色 map（课程名 → hex） */
  private loadCustomColors(): Record<string, string> {
    const raw: string = DataStore.getCourseCustomColors();
    if (raw.length === 0) {
      return {};
    }
    try {
      return JSON.parse(raw) as Record<string, string>;
    } catch (e) {
      return {};
    }
  }

  /** 课程当前生效颜色：自定义 > hash 默认 */
  private colorOf(course: CourseItem): string {
    const custom: string = this.customColors[course.name] ?? '';
    if (custom.length > 0) {
      return custom;
    }
    return COURSE_BG_HEX[this.colorIdx(course.name)];
  }

  /** 格子背景色（非本周用灰） */
  private bgOf(course: CourseItem, isNext: boolean): string {
    if (isNext) {
      return '#9E9E9E';
    }
    return this.colorOf(course);
  }

  /** 解析 #RRGGBB → 亮度（0-1），用于文字叠加 */
  private hexLuma(hex: string): number {
    let r: number = 0;
    let g: number = 0;
    let b: number = 0;
    const h: string = hex.replace('#', '');
    if (h.length === 6) {
      r = Number.parseInt(h.substring(0, 2), 16);
      g = Number.parseInt(h.substring(2, 4), 16);
      b = Number.parseInt(h.substring(4, 6), 16);
    }
    return (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  }

  /** 根据背景亮度自动选黑/白文字（文字叠加格子颜色） */
  private contrastText(bgHex: string): string {
    return this.hexLuma(bgHex) > 0.6 ? '#212121' : '#FFFFFF';
  }

  /** 格子文字颜色：文字叠加 > 自定义文字色 > 课程主题文字色 */
  private fgOf(course: CourseItem, isNext: boolean): string {
    if (isNext) {
      return '#666666';
    }
    if (this.cfg.textMixWithBg) {
      return this.contrastText(this.bgOf(course, false));
    }
    if (this.cfg.textColor.length > 0) {
      return this.cfg.textColor;
    }
    return COURSE_FG_HEX[this.colorIdx(course.name)];
  }

  /** 格子边框样式 */
  private cellBorder(course: CourseItem, isNext: boolean): BorderOptions {
    if (this.cfg.borderWidth <= 0) {
      return { width: 0 } as BorderOptions;
    }
    let color: string = '';
    if (this.cfg.borderUseCourseColor) {
      color = this.bgOf(course, isNext);
    } else if (this.cfg.borderColor.length > 0) {
      color = this.cfg.borderColor;
    } else {
      // 未配置颜色默认浅灰描边
      color = '#CCCCCC';
    }
    const w: string = `${this.cfg.borderWidth}vp`;
    if (this.cfg.borderDashed) {
      return { width: w, style: BorderStyle.Dashed, dashGap: 3, color } as BorderOptions;
    }
    return { width: w, style: BorderStyle.Solid, color } as BorderOptions;
  }

  /** 格子内上课时间文本（只显示时刻，不显示第几节） */
  private cellTimeText(course: CourseItem): string {
    return DateUtil.sectionRange(course.startSection, course.endSection);
  }

  /** 格子内地点文本（@ 前缀开关） */
  private cellLocationText(course: CourseItem): string {
    if (course.location.length === 0) {
      return '';
    }
    return (this.cfg.showAtPrefix ? '@ ' : '') + course.location;
  }

  /** 格子文字水平对齐（右 > 中 > 左） */
  private cellTextAlign(): TextAlign {
    if (this.cfg.textRight) {
      return TextAlign.End;
    }
    if (this.cfg.textHCenter) {
      return TextAlign.Center;
    }
    return TextAlign.Start;
  }

  /** 格子内容水平对齐（右 > 中 > 左） */
  private cellHAlign(): HorizontalAlign {
    if (this.cfg.textRight) {
      return HorizontalAlign.End;
    }
    if (this.cfg.textHCenter) {
      return HorizontalAlign.Center;
    }
    return HorizontalAlign.Start;
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
          Row() {
            Text('课程表')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
            // 设置按钮：紧贴"课程表"标题右侧，圆形半透白底 + 齿轮图标
            Column() {
              Image($r('app.media.gearshape'))
                .width(20)
                .height(20)
                .fillColor(Color.White)
                .opacity(0.9)
            }
            .width(30)
            .height(30)
            .borderRadius(15)
            .backgroundColor('#26FFFFFF')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .margin({ left: 8 })
            .onClick(() => {
              this.showSettingsSheet = true;
            })
          }
          .alignItems(VerticalAlign.Center)

          // 学期选择器（点击弹层切换）
          Row() {
            Text(this.currentTerm().label)
              .fontSize(11)
              .fontColor(this.isDarkMode ? $r('app.color.text_tertiary') : '#CCFFFFFF')
            // 学期选择箭头：list.png 图标，深色模式用浅色 fillColor 适配
            Image($r('app.media.list_bullet'))
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

      ForEach(this.weekdays(), (wd: number) => {
        Column() {
          Text(Const.WEEK_SHORT[wd - 1])
            .fontSize(this.cfg.headerFontSize)
            .fontWeight(this.isToday(wd) ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(this.isToday(wd) ? $r('app.color.brand') : $r('app.color.text_secondary'))
          Text(`${this.dateOf(wd).getMonth() + 1}/${this.dateOf(wd).getDate()}`)
            .fontSize(11)
            .fontColor(this.isToday(wd) ? $r('app.color.brand') : $r('app.color.text_tertiary'))
            .margin({ top: 2 })
        }
        .layoutWeight(1)
        .margin({ left: 2, right: 2 })
        .padding({ top: 7, bottom: 7 })
        .backgroundColor(this.isToday(wd) ? $r('app.color.brand_light') : Color.Transparent)
        .borderRadius(8)
      }, (wd: number) => `w${wd}`)
    }
    .width('100%')
    .padding({ top: 4, bottom: 4 })
    .backgroundColor(this.cfg.headerColor.length > 0 ? this.cfg.headerColor : $r('app.color.bg_card'))
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
          if (this.cfg.showSectionTime) {
            Text(item.start)
              .fontSize(9)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 2 })
            Text(item.end)
              .fontSize(9)
              .fontColor($r('app.color.text_tertiary'))
          }
        }
        .width('100%')
        .height(this.cellH())
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
            .height(this.cellH())
            .border(this.gridBorderStyle())
        }, (item: SectionTime) => `g${weekday}-${item.index}`)
      }
      .width('100%')

      // 非本周课程（下周预览，灰色半透明，渲染在底层）
      if (this.cfg.showNextWeek) {
        ForEach(this.coursesOfNextWeek(weekday), (course: CourseItem) => {
          this.courseBlock(course, true)
        }, (course: CourseItem) => `nx${weekday}-${course.id}`)
      }

      // 本周课程（渲染在上层）
      ForEach(this.coursesOfDay(weekday), (course: CourseItem) => {
        this.courseBlock(course, false)
      }, (course: CourseItem) => `${weekday}-${course.id}`)
    }
    .layoutWeight(1)
    .margin({ left: 2, right: 2 })
    .height(this.cellH() * Const.SECTION_COUNT)
  }

  /** 课程格子：支持文字色/叠加/边框/圆角/透明度/大小/对齐/时间/地点/@/老师全套配置 */
  @Builder
  courseBlock(course: CourseItem, isNext: boolean) {
    Column() {
      if (this.cfg.showTimeInCell) {
        Text(this.cellTimeText(course))
          .fontSize(this.cfg.textSize - 2)
          .fontColor(this.fgOf(course, isNext))
          .width('100%')
          .textAlign(this.cellTextAlign())
          .margin({ bottom: 2 })
      }
      Text(course.name)
        .fontSize(this.cfg.textSize)
        .lineHeight(this.cfg.textSize + 3)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.fgOf(course, isNext))
        .width('100%')
        .textAlign(this.cellTextAlign())
      if (this.cfg.showLocation && course.location.length > 0) {
        Text(this.cellLocationText(course))
          .fontSize(this.cfg.textSize - 2)
          .fontColor(this.fgOf(course, isNext))
          .opacity(0.85)
          .width('100%')
          .textAlign(this.cellTextAlign())
          .margin({ top: 2 })
      }
      if (this.cfg.showTeacher && course.teacher.length > 0) {
        Text(course.teacher)
          .fontSize(this.cfg.textSize - 2)
          .fontColor(this.fgOf(course, isNext))
          .opacity(0.75)
          .width('100%')
          .textAlign(this.cellTextAlign())
          .margin({ top: 1 })
      }
    }
    .width('100%')
    .height((course.endSection - course.startSection + 1) * this.cellH() - 4)
    .padding(6)
    .justifyContent(this.cfg.textVCenter ? FlexAlign.Center : FlexAlign.Start)
    .alignItems(this.cellHAlign())
    .backgroundColor(this.bgOf(course, isNext))
    .opacity(isNext ? this.cfg.nextWeekOpacity / 100 : this.cfg.cellOpacity / 100)
    .border(this.cellBorder(course, isNext))
    .borderRadius(this.cfg.cellRadius)
    .position({ x: 0, y: (course.startSection - 1) * this.cellH() + 2 })
    .onClick(() => {
      this.selected = course;
      this.showSheet = true;
    })
  }

  /**
   * 网格辅助线样式：
   *  - gridEnabled=false → 无网格线
   *  - gridDashed=true → 虚线；false → 实线
   *  粗细可调（gridWidth vp）。
   */
  private gridBorderStyle(): BorderOptions {
    if (!this.cfg.gridEnabled) {
      return { width: 0 } as BorderOptions;
    }
    const w: string = `${this.cfg.gridWidth}vp`;
    if (this.cfg.gridDashed) {
      return { width: { bottom: w, right: w }, style: BorderStyle.Dashed, dashGap: 3, color: $r('app.color.divider') } as BorderOptions;
    }
    return { width: { bottom: w, right: w }, style: BorderStyle.Solid, color: $r('app.color.divider') } as BorderOptions;
  }

  /** 课程详情弹窗（bindSheet 半屏）：内容为独立组件 CourseDetailPanel，本地 @State 镜像+回调实时刷新 */
  @Builder
  courseSheet() {
    CourseDetailPanel({
      selected: this.selected,
      customColors: this.customColors,
      courseNames: this.courseNameList(),
      timeText: this.selectedTimeText(),
      onClose: () => {
        this.showSheet = false;
      },
      onColorsChange: (m: Record<string, string>) => {
        this.customColors = m;
      }
    })
  }

  /**
   * 选择并导入图片作为课程表背景：
   * 1) 调 photoAccessHelper 选图（图片选择器）
   * 2) 读取文件 → 编码为 base64 → 写入 DataStore
   * 大图自动缩放至 1280px 边长以控制存储占用。
   */
  private async pickBackgroundImage(): Promise<void> {
    try {
      const picker: photoAccessHelper.PhotoViewPicker = new photoAccessHelper.PhotoViewPicker();
      const result: ESObject = await picker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      const uris: string[] = (result as Record<string, ESObject>)['photoUris'] as string[] ?? [];
      if (uris.length === 0) {
        return;
      }
      const srcPath: string = uris[0];
      // 读取并缩放图片
      const file: fileIo.File = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY);
      const stat: fileIo.Stat = fileIo.statSync(srcPath);
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buffer);
      fileIo.closeSync(file);
      const imgSource: image.ImageSource = image.createImageSource(buffer);
      const info: image.ImageInfo = await imgSource.getImageInfo();
      const longSide: number = Math.max(info.size.width, info.size.height);
      const target: number = longSide > 1280 ? 1280 : longSide;
      const scaled: image.PixelMap = await imgSource.createPixelMap({
        editable: false,
        desiredSize: {
          width: info.size.width >= info.size.height ? target : Math.round(target * info.size.width / info.size.height),
          height: info.size.height > info.size.width ? target : Math.round(target * info.size.height / info.size.width)
        }
      });
      const packer: image.ImagePacker = image.createImagePacker();
      const out: ArrayBuffer = await packer.packing(scaled, { format: 'image/jpeg', quality: 75 });
      imgSource.release();
      scaled.release();
      packer.release();
      // 编码 base64
      const base64: string = JwApi.arrayBufferToBase64(out);
      DataStore.setScheduleBg(base64);
      this.scheduleBg = base64;
      promptAction.showToast({ message: '背景图已设置' });
    } catch (e) {
      promptAction.showToast({ message: '设置背景图失败' });
    }
  }

  /** 清除背景图（恢复默认透明） */
  private clearBackgroundImage(): void {
    DataStore.setScheduleBg('');
    this.scheduleBg = '';
    promptAction.showToast({ message: '背景图已清除' });
  }

  /** 所有课程名（去重），课程详情"一键分配"用 */
  private courseNameList(): string[] {
    const names: string[] = [];
    for (const c of this.courses) {
      if (!names.includes(c.name)) {
        names.push(c.name);
      }
    }
    return names;
  }

  @Builder
  weekPickerSheet() {
    Column() {
      // 标题由 bindSheet title 显示（左上角），此处不再重复
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
              Image($r('app.media.checkmark_circle'))
                .width(16)
                .height(16)
                .fillColor($r('app.color.brand_on'))
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

  /** 课程表设置弹窗（bindSheet 半屏）：内容为 ScheduleSettingsPanel 组件 */
  @Builder
  settingsSheet() {
    ScheduleSettingsPanel({
      cfg: this.cfg,
      scheduleBg: this.scheduleBg,
      onPickBg: () => { this.pickBackgroundImage(); },
      onClearBg: () => { this.clearBackgroundImage(); },
      onClose: () => { this.showSettingsSheet = false; },
      onCfgChange: (c: ScheduleConfig) => { this.cfg = c; }
    })
  }

  /** 分组标题 */
  build() {
    Column() {
      Column() {
        this.topBar()
      // 把"选择周次"弹层绑在 weekHeader 自己的容器上（与根 Column 的"选择学期"弹层分开锚点）
      Row() {
        Column() {
          this.weekHeader()
        }
        .width(720)
        .constraintSize({ maxWidth: '100%' })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .bindSheet($$this.showWeekSheet, this.weekPickerSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        backgroundColor: $r('app.color.bg_card'),
        title: { title: '选择周次' }
      })
      // 横屏/平板下内容限宽 720vp 并居中（一多适配），单一 Scroll 占满剩余空间
      Stack() {
        Column() {
          if (this.loading) {
            LoadingTip()
          } else if (this.courses.length === 0) {
            LoadingTip({ text: '本学期暂无课程，可点击顶部"切换学期"查看其它学期' })
          } else {
            // 背景：纯色优先（可配置），背景图叠加在上层（可配置）
            if (this.scheduleBg.length > 0) {
              Image(`data:image/jpeg;base64,${this.scheduleBg}`)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .position({ x: 0, y: 0 })
                .opacity(0.85)
                .zIndex(0)
            }
            Row() {
              Scroll() {
                Column() {
                  Row() {
                    this.sectionColumn()
                    ForEach(this.weekdays(), (wd: number) => {
                      this.dayColumn(wd)
                    }, (wd: number) => `day${wd}`)
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Top)

                  Row() {
                    Text(`本周共 ${this.weekCourseCount()} 节课`)
                      .fontSize(11)
                      .fontColor(this.scheduleBg.length > 0 ? '#FFFFFF' : $r('app.color.text_tertiary'))
                    Blank()
                    Text('点击课程查看详情')
                      .fontSize(11)
                      .fontColor(this.scheduleBg.length > 0 ? '#FFFFFF' : $r('app.color.text_tertiary'))
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 14, bottom: 100 })
                }
                .width('100%')
              }
              .width(720)
              .constraintSize({ maxWidth: '100%' })
              .height('100%')
              // 内容不足一屏时顶部对齐（align 默认 Center 会导致平板竖屏下格子区垂直居中、顶部留空）
              .align(Alignment.TopStart)
              .scrollBar(BarState.Off)
              .edgeEffect(EdgeEffect.Spring)
              .backgroundColor(this.scheduleBg.length > 0 ? Color.Transparent :
                (this.cfg.bgColor.length > 0 ? this.cfg.bgColor : $r('app.color.bg_page')))
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          }
        }
        .width('100%')
        .height('100%')
      }
      .width('100%')
      .alignContent(Alignment.TopStart)
      .layoutWeight(1)
      // 左右滑动切换上一周/下一周（水平滑动手势，不干扰表格内部垂直滚动）
      .gesture(
        SwipeGesture({ direction: SwipeDirection.Horizontal })
          .onAction((event: SwipeGestureEvent) => {
            // angle > 90 或 < -90 表示向左滑动，否则为向右滑动
            if (event.angle > 90 || event.angle < -90) {
              this.changeWeek(1); // 向左滑，下一周
            } else {
              this.changeWeek(-1); // 向右滑，上一周
            }
          })
      )
      // 课程详情弹层（bindSheet 半屏，内容组件本地镜像+回调实时刷新）
      .bindSheet($$this.showSheet, this.courseSheet(), {
        height: SheetSize.MEDIUM,
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
      dragBar: false,
      backgroundColor: $r('app.color.bg_card'),
      title: { title: '选择学年-学期' }
    })
    }
    .width('100%')
    .height('100%')
    // 设置弹层挂在独立外层容器上，与"选择学年-学期"弹层分开锚点（同一组件多个 bindSheet 仅最后一个生效）
    .bindSheet($$this.showSettingsSheet, this.settingsSheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      backgroundColor: $r('app.color.bg_card'),
      title: { title: '课程表设置' }
    })
  }
}
