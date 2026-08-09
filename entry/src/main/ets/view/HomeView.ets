/**
 * 首页：学期概览 + 今日课程 + 快捷入口 + 近期考试
 * 头部：简约白卡头像（真实证件照）+ 学号/学院/班级
 */
import { promptAction } from '@kit.ArkUI';
import { mediaquery } from '@kit.ArkUI';
import { JwApi } from '../api/JwApi';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { DataStore } from '../common/DataStore';
import { DateUtil } from '../common/DateUtil';
import { LogStore } from '../common/LogStore';
import { Theme } from '../common/ThemeUtil';
import { CourseItem, ExamItem, NoticeItem, QuickEntry, TermInfo, TodayCourse } from '../model/Models';
import { TeachingCalendar } from '../model/TeachingCalendar';
import { EmptyTip, LoadingTip, SectionHeader, TagChip } from './common/UiKit';
import { WebSurface } from './WebSurface';

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
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('showAvatar') showAvatar: boolean = false;
  @State todayCourses: TodayCourse[] = [];
  @State nextClass: TodayCourse | null = null;
  @State exams: ExamItem[] = [];
  @State notices: NoticeItem[] = [];
  @State currentWeek: number = 0;
  @State loading: boolean = true;
  @State photo: string = '';
  @State isLandscape: boolean = false;
  @State teachingCal: TeachingCalendar | null = null;
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
  // 课程无课时：随机鼓励文案 + 下次课预告
  @State randomRestText: string = '';
  @State nextFutureCourse: NextFutureCourse | null = null;
  onSwitchTab: (index: number) => void = () => {
  };
  private landscapeListener: mediaquery.MediaQueryListener | null = null;

  /** 页面出现：加载数据并监听横竖屏 */
  aboutToAppear(): void {
    // 功能浏览模式优先用 AppState.mockCurrentWeek > 0 指定的周次，确保所有功能有数据
    if (AppState.mockCurrentWeek > 0) {
      this.currentWeek = AppState.mockCurrentWeek;
    } else {
      this.currentWeek = DateUtil.weekOfTerm(AppState.term, new Date());
    }
    this.calDefaultMonth = this.computeCurrentMonth();
    this.randomRestText = this.pickRestText();
    this.listenLandscape();
    this.loadData();
  }

  /** 页面消失：注销监听 */
  aboutToDisappear(): void {
    this.landscapeListener = null;
  }

  /** 监听屏幕方向变化（横屏时压缩头部） */
  private listenLandscape(): void {
    const mq: mediaquery.MediaQueryResult = mediaquery.matchMediaSync('(orientation: landscape)');
    this.isLandscape = mq.matches;
    this.landscapeListener = mediaquery.matchMediaSync('(orientation: landscape)');
    this.landscapeListener.on('change', (res: mediaquery.MediaQueryResult) => {
      this.isLandscape = res.matches;
    });
  }

  private async loadData(): Promise<void> {
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
      const courses: CourseItem[] = await JwApi.getCourses(AppState.term.id);
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
   * 1) 当前周 weekday > 今天 weekday
   * 2) 否则后续周 weekday 升序
   */
  private findNextFutureCourse(courses: CourseItem[], term: TermInfo): NextFutureCourse | null {
    const todayW: number = DateUtil.weekdayOf(new Date());
    const cw: number = DateUtil.weekOfTerm(term, new Date());
    for (let w: number = todayW + 1; w <= 7; w++) {
      for (const c of courses) {
        if (c.weekday === w && c.weeks.includes(cw)) {
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
      promptAction.showToast({ message: '该功能将在接入教务接口后开放' });
    }
  }

  @Builder
  titleBar() {
    // 顶部固定标题栏：浅色=主题色（中国红/天空蓝/农大绿），深色=黑色
    // 高度与其他主题色顶栏统一（topInset + 72vp 外高，内容区 48vp）
    Row() {
      Text('首页')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
      // 手动重登模式 + 校历为空：标题右侧显示"重登"胶囊（点击执行自动重新登录）
      if (this.shouldShowRelogin()) {
        Text('重登')
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
          .backgroundColor('#FF9800')
          .height(22)
          .padding({ left: 8, right: 8 })
          .borderRadius(11)
          .margin({ left: 8 })
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.onReloginClick();
          })
      }
      Blank()
      // 右侧：当前教学周（未开学显示"未开学"），模仿课程表右上角样式（不可点、无左右箭头）
      Text(this.isTermStarted() ? `第 ${this.todayTeachingWeek()} 周` : '未开学')
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .padding({ left: 10, right: 10, top: 5, bottom: 5 })
        .backgroundColor('#33FFFFFF')
        .borderRadius(12)
        .margin({ right: 8 })
      // 右侧：当前学年学期（完整格式，点击展开学期选择，全局设置）
      Row() {
        Text(this.terms.length > 0 && this.selectedTermIndex < this.terms.length
          ? this.terms[this.selectedTermIndex].label
          : AppState.term.label)
          .fontSize(11)
          .fontColor(this.isDarkMode ? $r('app.color.text_tertiary') : '#CCFFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Image($r('app.media.list'))
          .width(14)
          .height(14)
          .fillColor(this.isDarkMode ? $r('app.color.text_tertiary') : '#CCFFFFFF')
          .margin({ left: 4 })
      }
      .padding({ left: 10, right: 6, top: 4, bottom: 4 })
      .borderRadius(14)
      .onClick(() => {
        this.showTermSheet = true;
      })
    }
    .width('100%')
    .height(px2vp(this.topInsetPx) + 60)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16, top: px2vp(this.topInsetPx) + 12, bottom: 12 })
    .backgroundColor(this.isDarkMode ? '#1A1D1C' : Theme.colorOf(this.themeColor))
  }

  /** 学期选择弹层（全局设置） */
  @Builder
  termPickerSheet() {
    Column() {
      if (this.terms.length === 0) {
        Text('暂无可选学期')
          .fontSize(13)
          .fontColor($r('app.color.text_tertiary'))
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        Scroll() {
          Column() {
            ForEach(this.terms, (term: TermInfo, index: number) => {
              Row() {
                Text(term.label)
                  .fontSize(14)
                  .fontColor(this.selectedTermIndex === index ? $r('app.color.brand_on') : $r('app.color.text_primary'))
                  .layoutWeight(1)
                if (this.selectedTermIndex === index) {
                  Text('✓')
                    .fontSize(16)
                    .fontColor($r('app.color.brand_on'))
                }
              }
              .width('100%')
              .height(46)
              .padding({ left: 16, right: 16 })
              .backgroundColor(this.selectedTermIndex === index ? $r('app.color.brand') : $r('app.color.bg_chip'))
              .borderRadius(10)
              .margin({ bottom: 8 })
              .onClick(() => {
                this.selectTerm(index);
              })
            }, (term: TermInfo) => term.id)
          }
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .constraintSize({ maxHeight: 360 })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
  }

  @Builder
  avatarCard() {
    // 头像卡片：showAvatar 仅控制圆形头像的显示/隐藏，姓名等其余信息始终显示
    Row() {
      if (this.showAvatar) {
        if (this.photo.length > 0) {
          Image('data:image/jpeg;base64,' + this.photo)
            .width(52)
            .height(52)
            .borderRadius(26)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.bg_chip'))
        } else if (JwApi.USE_MOCK) {
          // 功能浏览模式：默认头像使用内置资源
          Image($r('app.media.zhangsan_avatar'))
            .width(52)
            .height(52)
            .borderRadius(26)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.bg_chip'))
        } else {
          Text(AppState.avatarText())
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand'))
            .width(52)
            .height(52)
            .borderRadius(26)
            .backgroundColor($r('app.color.bg_chip'))
            .textAlign(TextAlign.Center)
        }
      }

      Column() {
        Text(`${AppState.displayName()}，${this.greeting()}`)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.subtitleText())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
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
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(16)
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
        Text('下一节课')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        if (this.todayCourses.length > 0) {
          Text(this.nextClass === null ? '今日已结束' : `今日 ${this.todayCourses.length} 节`)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
        }
      }
      .width('100%')
      .margin({ bottom: 12 })

      if (this.todayCourses.length === 0) {
        // 无今日课时：当前没课了哦！ + 随机鼓励文案 + 下次课预告（点击跳课程表打开详情）
        Column() {
          Text(`当前没课了哦！${this.randomRestText.length > 0 ? this.randomRestText : '好好休息吧~'}`)
            .fontSize(13)
            .fontColor($r('app.color.text_tertiary'))
            .textAlign(TextAlign.Center)
            .width('100%')
          if (this.nextFutureCourse !== null) {
            // 下次课卡片：左侧"下次课"竖排 + 右侧（课程名/地点 + 时间）
            Row() {
              // 左侧竖条：下次课 三个字竖排
              Column() {
                Text('下').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.brand'))
                Text('次').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.brand'))
                Text('课').fontSize(13).fontWeight(FontWeight.Medium).fontColor($r('app.color.brand'))
              }
              .padding(10)
              .backgroundColor($r('app.color.brand_light'))
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .borderRadius({ topLeft: 16, bottomLeft: 16 })

              // 右侧主体：课程名+地点 居中
              Column() {
                Text(this.nextFutureCourse.course.name)
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .textAlign(TextAlign.Center)
                  .width('100%')
                Text(this.nextFutureCourse.course.location)
                  .fontSize(11)
                  .fontColor($r('app.color.text_secondary'))
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
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.brand'))
                  .textAlign(TextAlign.Center)
                Text(this.nextFutureCourse.timeRange)
                  .fontSize(11)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.text_primary'))
                  .textAlign(TextAlign.Center)
                  .margin({ top: 3 })
              }
              .padding({ left: 10, right: 12 })
              .justifyContent(FlexAlign.Center)
            }
            .width('100%')
            .backgroundColor($r('app.color.bg_chip'))
            .borderRadius(16)
            .margin({ top: 12 })
          }
        }
        .width('100%')
      } else if (this.nextClass === null) {
        Row() {
          Text('🎉')
            .fontSize(26)
            .margin({ right: 12 })
          Column() {
            Text('今日课程已全部结束')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(`今天共 ${this.todayCourses.length} 节课，辛苦啦`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .margin({ top: 4 })
          }
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding({ top: 8, bottom: 8 })
      } else {
        Row() {
          Column() {
            Text(this.nextClass!.timeRange.split('-')[0])
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(this.nextClass!.timeRange.split('-')[1])
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 2 })
          }
          .width(48)
          .alignItems(HorizontalAlign.Start)

          Column() {
            Circle()
              .width(8)
              .height(8)
              .fill(this.nextClass!.ongoing ? $r('app.color.brand') : Const.COURSE_FG[this.nextClass!.course.colorIndex])
          }
          .width(20)
          .margin({ top: 6 })

          Column() {
            Row() {
              Text(this.nextClass!.course.name)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (this.nextClass!.ongoing) {
                TagChip({ text: '进行中', color: $r('app.color.brand_on'), bg: $r('app.color.brand') })
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
              Text(`📍 ${this.nextClass!.course.location}`)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
              Text(`👤 ${this.nextClass!.course.teacher}`)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .margin({ left: 10 })
              Blank()
              Text(`第 ${this.nextClass!.course.startSection}-${this.nextClass!.course.endSection} 节`)
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
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
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
    .shadow({ radius: 16, color: '#0F000000', offsetY: 4 })
  }

  @Builder
  quickEntries() {
    Grid() {
      ForEach(Const.QUICK_ENTRIES, (item: QuickEntry) => {
        GridItem() {
          Column() {
            Row() {
              Image(item.key === 'exam' ? $r('app.media.exam_entry') : $r('app.media.academic_entry'))
                .width(20)
                .height(20)
                .fillColor(item.color)
              Text(item.title)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .margin({ left: 8 })
            }
            .width('90%')
            .height(48)
            .justifyContent(FlexAlign.Center)
            .backgroundColor($r('app.color.bg_chip'))
            .borderRadius(14)
          }
          .onClick(() => {
            this.onEntryTap(item.key);
          })
        }
      }, (item: QuickEntry) => item.key)
    }
    .columnsTemplate('1fr 1fr')
    .rowsTemplate('1fr')
    .height(64)
    .width('100%')
    .padding({ top: 6, bottom: 6 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
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
        Column() {
          EmptyTip({ text: '近期没有考试安排' })
        }
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius(18)
      } else {
        ForEach(this.exams, (item: ExamItem) => {
          Row() {
            Column() {
              Text(`${DateUtil.parse(item.date).getMonth() + 1}/${DateUtil.parse(item.date).getDate()}`)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.accent_orange'))
              Text(DateUtil.relativeDay(DateUtil.parse(item.date)))
                .fontSize(10)
                .fontColor($r('app.color.text_tertiary'))
                .margin({ top: 2 })
            }
            .width(54)
            .padding({ top: 8, bottom: 8 })
            .backgroundColor($r('app.color.bg_chip'))
            .borderRadius(10)

            Column() {
              Text(item.courseName)
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(`${item.timeRange} · ${item.location} · ${item.seat} 号座`)
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
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
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(16)
          .margin({ bottom: 10 })
          .onClick(() => {
            AppState.stack.pushPath({ name: Const.ROUTE_EXAM });
          })
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
        Column() {
          EmptyTip({ text: '暂无消息' })
        }
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius(18)
      } else {
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
                  .fontColor($r('app.color.text_tertiary'))
                Text(' · ')
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
                Text(item.date)
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
                Blank()
                Text('详情 ›')
                  .fontSize(11)
                  .fontColor($r('app.color.brand'))
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
        .padding(16)
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius(18)
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
        Column() {
          EmptyTip({ text: '暂无通知' })
        }
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius(18)
      } else {
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
                  .fontColor($r('app.color.text_tertiary'))
                Text(' · ')
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
                Text(item.date)
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
                Blank()
                Text('阅读 ›')
                  .fontSize(11)
                  .fontColor($r('app.color.brand'))
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
                  promptAction.showToast({ message: '当前模式禁止使用' });
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
        .padding(16)
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius(18)
      }
    }
    .width('100%')
    .margin({ top: 18 })
  }

  /** 通知详情底部弹层（原地展开，不跳页） */
  @Builder
  noticeSheet() {
    Column() {
      if (this.sheetNotice !== null) {
        Text(this.sheetNotice.title)
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
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
            .fontColor($r('app.color.text_tertiary'))
          Text(' · ')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
          Text(this.sheetNotice.date)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
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
    .padding(16)
  }

  /** 今日所属教学周次（开学后返回对应周次；未开学返回 0） */
  private todayTeachingWeek(): number {
    const cal: TeachingCalendar | null = this.teachingCal;
    if (cal === null || cal.todayDate.length === 0) {
      return 0;
    }
    for (let r: number = 0; r < cal.rows.length; r++) {
      const dates: string[] = cal.rows[r].dates;
      for (let c: number = 0; c < dates.length; c++) {
        if (dates[c] === cal.todayDate) {
          return cal.weekNumbers[c] !== undefined ? cal.weekNumbers[c] : 0;
        }
      }
    }
    return 0;
  }

  /** 是否已开学（今日 >= 校历开学日） */
  private isTermStarted(): boolean {
    const cal: TeachingCalendar | null = this.teachingCal;
    if (cal === null || cal.startDate.length === 0) {
      return false;
    }
    return DateUtil.parse(cal.startDate).getTime() <= new Date().getTime();
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
      promptAction.showToast({ message: '重登功能暂不可用' });
    }
  }

  /** 校历覆盖的自然月列表：[年份*100+月份, ...]（如 202608 ~ 202702） */
  private calMonthList(): number[] {
    const cal: TeachingCalendar | null = this.teachingCal;
    if (cal === null || cal.startDate.length === 0 || cal.endDate.length === 0) {
      return [];
    }
    const sy: number = Number(cal.startDate.slice(0, 4));
    const sm: number = Number(cal.startDate.slice(5, 7));
    const ey: number = Number(cal.endDate.slice(0, 4));
    const em: number = Number(cal.endDate.slice(5, 7));
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

  /** 学期日历信息小标签 */
  @Builder
  infoChip(text: string, color: Resource) {
    Text(text)
      .fontSize(11)
      .fontColor(color)
      .fontWeight(FontWeight.Medium)
      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
      .backgroundColor($r('app.color.bg_chip'))
      .borderRadius(10)
      .margin({ right: 8 })
  }

  /** 日期是否在校历学期范围内（开学日 ~ 结束日），范围外灰色显示 */
  private isInTerm(day: string): boolean {
    const cal: TeachingCalendar | null = this.teachingCal;
    if (cal === null || cal.startDate.length === 0 || cal.endDate.length === 0) {
      return true;
    }
    return day >= cal.startDate && day <= cal.endDate;
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
      SectionHeader({ title: '日历', action: '', onAction: () => {} })

      if (this.teachingCal === null) {
        LoadingTip({ text: '加载日历…' })
          .width('100%')
          .height(140)
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(18)
      } else {
        Text(this.teachingCal!.semesterLabel)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .margin({ bottom: 8 })

        Row() {
          // 未开学不显示周次，显示"未开学"
          if (this.isTermStarted()) {
            this.infoChip(`第 ${this.todayTeachingWeek()} 周`, $r('app.color.brand'))
          } else {
            this.infoChip('未开学', $r('app.color.accent_orange'))
          }
          if (this.teachingCal!.startDate.length > 0) {
            this.infoChip(`开学 ${this.teachingCal!.startDate.slice(5)}`, $r('app.color.accent_blue'))
          }
          if (this.teachingCal!.endDate.length > 0) {
            this.infoChip(`结束 ${this.teachingCal!.endDate.slice(5)}`, $r('app.color.accent_orange'))
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
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .margin({ top: 6, bottom: 6 })

              Row() {
                ForEach(Const.WEEK_SHORT, (d: string) => {
                  Text(d)
                    .fontSize(10)
                    .fontColor($r('app.color.text_tertiary'))
                    .textAlign(TextAlign.Center)
                    .layoutWeight(1)
                }, (d: string) => d)
              }
              .width('100%')
              .padding({ bottom: 4 })

              ForEach(this.monthGrid(Math.floor(ym / 100), ym % 100), (row: string[]) => {
                Row() {
                  ForEach(row, (day: string) => {
                    Column() {
                      if (day.length > 0) {
                        Text(day.slice(-2))
                          .fontSize(11)
                          .textAlign(TextAlign.Center)
                          .fontColor(
                            day === this.teachingCal!.todayDate
                              ? Color.White
                              : (this.isCalHoliday(day)
                                ? $r('app.color.accent_orange')
                                : (this.isInTerm(day) ? $r('app.color.text_primary') : $r('app.color.text_tertiary')))
                          )
                          .fontWeight(day === this.teachingCal!.todayDate ? FontWeight.Bold : FontWeight.Normal)
                          .width(30)
                          .height(28)
                          .borderRadius(14)
                          .backgroundColor(
                            day === this.teachingCal!.todayDate
                              ? Theme.colorOf(this.themeColor)
                              : Color.Transparent
                          )
                      }
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Center)
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
        .indicator(true)
        .width('100%')

        // 校历说明（来自校历 PDF 说明区）
        Column() {
          Text('校历说明')
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
          Text('第 1~20 周为秋季学期教学活动，第 21 周起放寒假。中秋节(9月25日)、国庆节(10月1日)、元旦(1月1日)、春节(2月6日)等节假日放假安排按照国家及自治区规定执行，详见校办通知。')
            .fontSize(11)
            .lineHeight(18)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .margin({ top: 6 })
        }
        .width('100%')
        .padding(12)
        .backgroundColor($r('app.color.bg_chip'))
        .borderRadius(12)
        .margin({ top: 6 })
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
    .margin({ top: 18 })
  }

  build() {
    Column() {
      this.titleBar()
      // 中间内容：可滚动；横屏/平板下内容限宽 720vp 并居中（一多适配）
      Row() {
        Scroll() {
          Column() {
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
              Text('数据来源：新疆农业大学教务系统').fontSize(11)
                .fontColor($r('app.color.text_tertiary')).width('100%').textAlign(TextAlign.Center)
              Text('新疆农业大学教务处').fontSize(11)
                .fontColor($r('app.color.text_tertiary')).width('100%').textAlign(TextAlign.Center)
                .margin({ top: 3 })
              Text('"功能浏览"模式为本地模拟数据').fontSize(11)
                .fontColor($r('app.color.text_tertiary')).width('100%').textAlign(TextAlign.Center)
                .margin({ top: 3 })
            }
            .width('100%')
            .margin({ top: 20, bottom: 24 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 100 }) // 底部预留悬浮底栏高度，避免内容被遮挡
          // 学期选择弹层（与根 Column 的通知弹层/Scroll 的网页弹层分置不同组件，避免同组件多 bindSheet 冲突）
          .bindSheet($$this.showTermSheet, this.termPickerSheet(), {
            height: SheetSize.FIT_CONTENT,
            dragBar: true,
            backgroundColor: $r('app.color.bg_card'),
            title: { title: '选择学年-学期' }
          })
        }
        .width(720)
        .constraintSize({ maxWidth: '100%' })
        .height('100%')
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
        // 通知文章页（教务处官网）挂在内层 Scroll，与根组件的通知弹层分离（同组件多 bindSheet 仅最后一个生效）
        .bindSheet($$this.showWebSheet, this.webSheet(), {
          height: SheetSize.LARGE,
          dragBar: false,
          backgroundColor: $r('app.color.bg_page'),
          title: { title: AppState.webTitle }
        })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center) // 横屏/平板下 Scroll 水平居中
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    .bindSheet($$this.showNoticeSheet, this.noticeSheet(), {
      height: SheetSize.LARGE,
      dragBar: true,
      backgroundColor: $r('app.color.bg_card')
    })
  }

  @Builder
  webSheet() {
    WebSurface()
  }
}