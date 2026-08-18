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
import { promptAction, display, mediaquery } from '@kit.ArkUI';
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
  @State sheetWidth: Dimension = '100%'; // 平板加宽半模态面板（≥600vp 视为平板）
  @State selected: CourseItem = EMPTY_COURSE;
  // 课程表设置
  @State scheduleBg: string = ''; // base64 图片数据，空=无背景
  @State cfg: ScheduleConfig = new ScheduleConfig(); // 完整自定义配置
  @State customTermStart: string = ''; // 当前学期开学日（含自定义覆盖），用于设置面板回显
  /** 课程独立颜色（课程名 → 自定义 hex），空=按课程名 hash 默认 */
  @State customColors: Record<string, string> = {};
  private currentWeek: number = 1;
  /** 全局学期广播（首页顶栏切换学期时同步本页） */
  @StorageProp('currentTermId') @Watch('onGlobalTermChanged') currentTermId: string = '';
  /** 横屏标记（平板横屏下左列周数选择 + 右列课程表） */
  @State isLandscape: boolean = false;
  /** 平板（大屏）标记：屏幕宽度 ≥600vp；竖屏时课程表底部显示点阵周次（手机不显示） */
  @State isTablet: boolean = false;
  private landscapeListener: mediaquery.MediaQueryListener | null = null;

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
    this.customTermStart = AppState.term.startDate;
    // 注册全局学期切换监听（首页顶栏切换后立即同步本页）
    AppState.registerTermListener('schedule', () => {
      this.onGlobalTermChanged();
    });
    this.load();
    // 平板适配：半模态面板宽度（≥600vp 视为平板，加宽并水平居中；手机保持全宽）
    try {
      const d = display.getDefaultDisplaySync();
      const screenVp: number = px2vp(d.width);
      this.isTablet = screenVp >= 600;
      this.sheetWidth = screenVp >= 600 ? `${Math.min(Math.round(screenVp * 0.7), 840)}vp` : '100%';
    } catch (e) {
      this.isTablet = false;
      this.sheetWidth = '100%';
    }
    // 首页"下次课"点击跳转：自动打开对应课程详情
    const pc: CourseItem | null = AppState.pendingCourse;
    if (pc !== null && pc.id.length > 0) {
      AppState.pendingCourse = null;
      this.selected = pc;
      this.showSheet = true;
    }
    this.listenLandscape();
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
    // 应用「自定义开学时间」覆盖到当前选中项（影响日期标签/周次映射）
    if (this.terms[this.selectedTermIndex]) {
      this.terms[this.selectedTermIndex] = JwApi.applyCustomStart(this.terms[this.selectedTermIndex]);
    }
    this.customTermStart = this.terms[this.selectedTermIndex]?.startDate ?? AppState.term.startDate;
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

  /** 设置面板修改/清除自定义开学时间：持久化 + 实时刷新周次映射 */
  private onTermStartChanged(date: string): void {
    const id: string = AppState.term.id;
    DataStore.setCustomTermStart(id, date);
    const start: string = date.length > 0 ? date : DateUtil.defaultTermStart(id);
    const cur: TermInfo = AppState.term;
    const term: TermInfo = { id: cur.id, label: cur.label, startDate: start, totalWeeks: cur.totalWeeks };
    if (this.terms[this.selectedTermIndex]) {
      const t: TermInfo = this.terms[this.selectedTermIndex];
      this.terms[this.selectedTermIndex] = { id: t.id, label: t.label, startDate: start, totalWeeks: t.totalWeeks };
    }
    AppState.term = term;
    this.customTermStart = start;
    // 开学日变化影响周次映射，重新计算当前周
    const week: number = DateUtil.weekOfTerm(term, new Date());
    this.currentWeek = week < 1 ? 1 : week;
    this.viewWeek = this.currentWeek;
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
        // 应用「自定义开学时间」覆盖到当前选中项（影响日期标签/周次映射）
        if (this.terms[this.selectedTermIndex]) {
          this.terms[this.selectedTermIndex] = JwApi.applyCustomStart(this.terms[this.selectedTermIndex]);
        }
        this.customTermStart = this.terms[this.selectedTermIndex]?.startDate ?? AppState.term.startDate;
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

  /** 点阵周次：行对应节段（0→1-2节，1→3-4节，依此类推） */
  private dotRows(): number[] { return [0, 1, 2, 3, 4]; }
  private dotDays(): number[] { return [1, 2, 3, 4, 5, 6, 7]; }

  /** 某周某天某节段是否有课 */
  private isDotFilled(week: number, day: number, row: number): boolean {
    const startSec: number = row * 2 + 1;
    const endSec: number = row * 2 + 2;
    for (const c of this.courses) {
      if (c.weekday === day && c.weeks.includes(week) && c.startSection <= endSec && c.endSection >= startSec) {
        return true;
      }
    }
    return false;
  }

  private async selectTerm(index: number): Promise<void> {
    this.selectedTermIndex = index;
    this.showTermSheet = false;
    this.loading = true;
    try {
      const term: TermInfo = JwApi.applyCustomStart(this.currentTerm());
      // 切换学期时同步更新当前学期（应用自定义开学时间覆盖，影响 AppState 内的学期）
      this.terms[this.selectedTermIndex] = term;
      AppState.term = term;
      this.customTermStart = term.startDate;
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

  /** 点阵周次缩略图：7 列（天）× 5 行（节段） */
  @Builder
  weekDotMatrix(week: number) {
    Column() {
      ForEach(this.dotRows(), (row: number) => {
        Row() {
          ForEach(this.dotDays(), (day: number) => {
            Circle()
              .width(4)
              .height(4)
              .fill(this.isDotFilled(week, day, row) ?
                (week === this.viewWeek ? $r('app.color.brand_on') :
                  (week === this.currentWeek ? $r('app.color.brand') : $r('app.color.text_secondary'))) :
                (week === this.viewWeek ? 'rgba(255,255,255,0.3)' : $r('app.color.divider')))
              .margin(2)
          }, (day: number) => `d${day}`)
        }
      }, (row: number) => `r${row}`)
    }
  }

  /** 周次卡片：标题/当前标签 + 点阵（左右排列，与参考图一致） */
  @Builder
  weekItemCard(week: number, onClick: () => void) {
    Row() {
      Column() {
        Text(`第${week}周`)
          .fontSize(13)
          .fontWeight(week === this.viewWeek ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(week === this.viewWeek ? $r('app.color.brand_on') :
            (week === this.currentWeek ? $r('app.color.brand') : $r('app.color.text_primary')))
        if (week === this.currentWeek) {
          Text('当前')
            .fontSize(9)
            .fontColor($r('app.color.brand'))
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .backgroundColor($r('app.color.brand_light'))
            .borderRadius(4)
            .margin({ top: 6 })
        }
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      this.weekDotMatrix(week)
    }
    .width('100%')
    .padding(12)
    .backgroundColor(week === this.viewWeek ? $r('app.color.brand') :
      (week === this.currentWeek ? $r('app.color.brand_light') : $r('app.color.bg_chip')))
    .borderRadius(10)
    .onClick(onClick)
  }

  /** 周次卡片（4 列网格版）：标题在上、点阵在下并居中，避免窄格横向溢出 */
  @Builder
  weekItemCardGrid(week: number, onClick: () => void) {
    Column() {
      Row() {
        Text(`第${week}周`)
          .fontSize(13)
          .fontWeight(week === this.viewWeek ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(week === this.viewWeek ? $r('app.color.brand_on') :
            (week === this.currentWeek ? $r('app.color.brand') : $r('app.color.text_primary')))
        if (week === this.currentWeek) {
          Text('当前')
            .fontSize(9)
            .fontColor($r('app.color.brand'))
            .padding({ left: 4, right: 4, top: 1, bottom: 1 })
            .backgroundColor($r('app.color.brand_light'))
            .borderRadius(4)
            .margin({ left: 4 })
        }
      }
      .margin({ bottom: 8 })

      this.weekDotMatrix(week)
    }
    .width('100%')
    .padding(10)
    .backgroundColor(week === this.viewWeek ? $r('app.color.brand') :
      (week === this.currentWeek ? $r('app.color.brand_light') : $r('app.color.bg_chip')))
    .borderRadius(10)
    .onClick(onClick)
  }

  /** 日期栏容器：居中 720 宽、与课程表主体同宽，并挂载周次选择弹层 */
  @Builder
  weekHeaderBar() {
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
      height: SheetSize.MEDIUM,
      preferType: SheetType.BOTTOM,
      width: this.sheetWidth,
      dragBar: true,
      backgroundColor: $r('app.color.bg_card'),
      title: { title: '点阵周次' }
    })
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
      List({ space: 10 }) {
        ForEach(this.weekList(), (w: number) => {
          ListItem() {
            this.weekItemCard(w, () => {
              this.viewWeek = w;
              this.showWeekSheet = false;
            })
          }
        }, (w: number) => `pick${w}`)
      }
      .width('100%')
      .padding({ left: 16, right: 16 })
      .scrollBar(BarState.Off)
    }
    .width('100%')
    .height('100%')
    .padding({ top: 8, bottom: 24 })
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
      onCfgChange: (c: ScheduleConfig) => { this.cfg = c; },
      currentTermId: AppState.term.id,
      currentTermStart: this.customTermStart,
      onTermStartChange: (d: string) => { this.onTermStartChanged(d); }
    })
  }

  /** 课程表主体布局 */
  build() {
    Column() {
      Column() {
        this.topBar()

        // 横屏：左列点阵周次 + 右列（日期栏+课程表）；竖屏：日期栏 + 原 Stack 课程表
        if (this.isLandscape) {
          this.scheduleLandscape()
        } else {
          this.weekHeaderBar()

          Stack() {
            Column() {
              // 有缓存课表时直接显示（断网/登录失败也能秒开缓存），仅无数据时显示加载中
              if (this.loading && this.courses.length === 0) {
                LoadingTip()
              } else if (this.courses.length === 0) {
                LoadingTip({ text: '本学期暂无课程，可点击顶部"切换学期"查看其它学期' })
              } else {
                if (this.scheduleBg.length > 0) {
                  Image(`data:image/jpeg;base64,${this.scheduleBg}`)
                    .width('100%')
                    .height('100%')
                    .objectFit(ImageFit.Cover)
                    .position({ x: 0, y: 0 })
                    .opacity(0.85)
                    .zIndex(0)
                }
                this.scheduleTable()
              }
            }
            .width('100%')
            .height('100%')
          }
          .width('100%')
          .layoutWeight(1)
          // 左右滑动切换上一周/下一周（水平滑动手势，不干扰表格内部垂直滚动）
          .gesture(
            SwipeGesture({ direction: SwipeDirection.Horizontal })
              .onAction((event: SwipeGestureEvent) => {
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
            preferType: SheetType.BOTTOM,
            width: this.sheetWidth,
            dragBar: true,
            backgroundColor: $r('app.color.bg_card'),
            title: { title: '课程详情' }
          })
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
      .bindSheet($$this.showTermSheet, this.termPickerSheet(), {
        height: SheetSize.FIT_CONTENT,
        preferType: SheetType.BOTTOM,
        width: this.sheetWidth,
        dragBar: false,
        backgroundColor: $r('app.color.bg_card'),
        title: { title: '选择学年-学期' }
      })
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showSettingsSheet, this.settingsSheet(), {
      height: SheetSize.MEDIUM,
      preferType: SheetType.BOTTOM,
      width: this.sheetWidth,
      dragBar: true,
      backgroundColor: $r('app.color.bg_card'),
      title: { title: '课程表设置' }
    })
  }

  /** 页面消失：注销横竖屏监听 */
  aboutToDisappear(): void {
    this.landscapeListener = null;
  }

  /** 监听屏幕方向变化（横屏时左列周数选择 + 右列课程表） */
  private listenLandscape(): void {
    this.isLandscape = mediaquery.matchMediaSync('(orientation: landscape)').matches;
    this.landscapeListener = mediaquery.matchMediaSync('(orientation: landscape)');
    this.landscapeListener.on('change', (res: mediaquery.MediaQueryResult) => {
      this.isLandscape = res.matches;
    });
  }

  /** 课程表主体（竖屏/横屏右列共用，保证渲染完全一致、区域大小不变） */
  @Builder
  scheduleTable() {
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
          // bottom 100 是"悬浮底栏"预留（课程表页无悬浮底栏），正是课程表与点阵之间大间隙的来源；
          // 改小后（8vp）课程表与点阵间隙 = 8 + 点阵 margin 8 ≈ 16vp
          .padding({ left: 16, right: 16, top: 14, bottom: 8 })
          // 平板（大屏）竖屏：点阵周次与课程表在同一滚动区域内一体滑动（手机竖屏不显示；横屏走左列）
          if (this.isTablet && !this.isLandscape) {
            Column() {
              this.weekDotsPanel()
            }
            .width('100%')
            // 底部预留 = 安全区 + 180：提高滚动到底部的余量，点阵最后一行不被导航栏/手势条遮挡
            .padding({ left: 16, right: 16, bottom: px2vp(this.bottomInsetPx) + 0 })
            .margin({ top: 8 })
          }
        }
        .width('100%')
        // 滚动内容底部预留：横屏 200vp（用户设定）/ 竖屏 48vp，让课程表（第九节等）能滚动更多、底部不被遮挡
        .padding({ bottom: this.isLandscape ? 200 : 85 })
      }
      .width(720)
      .constraintSize({ maxWidth: '100%' })
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .backgroundColor(this.scheduleBg.length > 0 ? Color.Transparent :
        (this.cfg.bgColor.length > 0 ? this.cfg.bgColor : $r('app.color.bg_page')))
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  /** 点阵周次选择面板（标题 + 4 列周数网格）：横屏左列与平板竖屏底部共用 */
  @Builder
  weekDotsPanel() {
    Column() {
      Row() {
        Text('点阵周次')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
      }
      .width('100%')
      .padding({ left: 4, right: 4, bottom: 12 })

      Grid() {
        ForEach(this.weekList(), (w: number) => {
          GridItem() {
            this.weekItemCardGrid(w, () => {
              this.viewWeek = w;
            })
          }
        }, (w: number) => `wk${w}`)
      }
      .columnsTemplate('1fr 1fr 1fr 1fr')
      .columnsGap(10)
      .rowsGap(12)
      .width('100%')
    }
    .width('100%')
  }

  /** 平板横屏布局：左列点阵周次 + 右列（日期栏+课程表，大小不变） */
  @Builder
  scheduleLandscape() {
    Row() {
      // 左列：点阵周次选择
      Scroll() {
        Column() {
          Row() {
            Text('点阵周次')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Blank()
          }
          .width('100%')
          .padding({ left: 4, right: 4, bottom: 12 })

          Grid() {
            ForEach(this.weekList(), (w: number) => {
              GridItem() {
                this.weekItemCardGrid(w, () => {
                  this.viewWeek = w;
                })
              }
            }, (w: number) => `landwk${w}`)
          }
          .columnsTemplate('1fr 1fr 1fr 1fr')
          .columnsGap(10)
          .rowsGap(12)
          .width('100%')
        }
        .width('100%')
        .padding({ left: 16, right: 8, top: 12, bottom: 100 })
      }
      .layoutWeight(1)
      .height('100%')
      // 显式交叉轴拉伸：横屏 Row 里 height('100%') 可能不生效，导致该列高度塌缩、滚动受限
      .alignSelf(ItemAlign.Stretch)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)

      // 右列：日期栏 + 课程表（与竖屏同一渲染，大小不变）
      Column() {
        this.weekHeaderBar()

        Stack() {
        if (this.scheduleBg.length > 0) {
          Image(`data:image/jpeg;base64,${this.scheduleBg}`)
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .position({ x: 0, y: 0 })
            .opacity(0.85)
            .zIndex(0)
        }
        this.scheduleTable()
      }
      .layoutWeight(1)
      .height('100%')
      // 左右滑动切换上一周/下一周（与竖屏一致）
      .gesture(
        SwipeGesture({ direction: SwipeDirection.Horizontal })
          .onAction((event: SwipeGestureEvent) => {
            if (event.angle > 90 || event.angle < -90) {
              this.changeWeek(1); // 向左滑，下一周
            } else {
              this.changeWeek(-1); // 向右滑，上一周
            }
          })
      )
      .bindSheet($$this.showSheet, this.courseSheet(), {
        height: SheetSize.MEDIUM,
        preferType: SheetType.BOTTOM,
        width: this.sheetWidth,
        dragBar: true,
        backgroundColor: $r('app.color.bg_card'),
        title: { title: '课程详情' }
      })
    }
    .layoutWeight(1)
    .height('100%')
    // 显式交叉轴拉伸：修复横屏右列高度塌缩（课程表 Scroll 视口过矮，节数多时底部"第九节"滚不上来）
    .alignSelf(ItemAlign.Stretch)

    .width('100%')
    .layoutWeight(1)
    .align(Alignment.Top)
  }
}
}
