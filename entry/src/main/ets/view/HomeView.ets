/**
 * 首页：学期概览 + 今日课程 + 快捷入口 + 近期考试
 * 头部：简约白卡头像（真实证件照）+ 学号/学院/班级
 */
import { promptAction } from '@kit.ArkUI';
import { mediaquery } from '@kit.ArkUI';
import { JwApi } from '../api/JwApi';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { DateUtil } from '../common/DateUtil';
import { Theme } from '../common/ThemeUtil';
import { CourseItem, ExamItem, NoticeItem, QuickEntry, TodayCourse } from '../model/Models';
import { EmptyTip, SectionHeader, TagChip } from './common/UiKit';

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
  onSwitchTab: (index: number) => void = () => {
  };
  private landscapeListener: mediaquery.MediaQueryListener | null = null;

  /** 页面出现：加载数据并监听横竖屏 */
  aboutToAppear(): void {
    this.currentWeek = DateUtil.weekOfTerm(AppState.term, new Date());
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
    // 先用本地缓存快速展示（秒开），再后台刷新覆盖
    const cachedCourses: CourseItem[] = JwApi.loadCachedCourses();
    if (cachedCourses.length > 0) {
      this.todayCourses = this.pickToday(cachedCourses);
      this.nextClass = this.firstUnfinished(this.todayCourses);
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
    try {
      const courses: CourseItem[] = await JwApi.getCourses(AppState.term.id);
      this.todayCourses = this.pickToday(courses);
      this.nextClass = this.firstUnfinished(this.todayCourses);
      const exams: ExamItem[] = await JwApi.getExams(AppState.term.id);
      this.exams = this.pickComingExams(exams);
      const notices: NoticeItem[] = await JwApi.getNotices();
      this.notices = notices.slice(0, 3);
    } catch (e) {
      // 网络异常时保持缓存数据
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
    Row() {
      Text('首页')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
      Blank()
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: px2vp(this.topInsetPx) + 12, bottom: 12 })
    .backgroundColor(this.isDarkMode ? '#1A1D1C' : Theme.colorOf(this.themeColor))
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
        EmptyTip({ text: this.loading ? '正在加载课表…' : '今天没有课程安排，好好休息' })
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

  @Builder
  noticeSection() {
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

  build() {
    Column() {
      // 顶部标题栏：固定不动 + 半透明白 + 毛玻璃
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

            this.examSection()
            this.noticeSection()
            Text('数据来源：学校教务系统（功能浏览模式为本地模拟数据）')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 20, bottom: 24 })
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 100 }) // 底部预留悬浮底栏高度，避免内容被遮挡
        }
        .width(720)
        .constraintSize({ maxWidth: '100%' })
        .height('100%')
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center) // 横屏/平板下 Scroll 水平居中
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }
}