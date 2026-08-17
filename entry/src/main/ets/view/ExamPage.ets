/**
 * 考试安排（二级页）：学年/学期选择 + 考试列表 + 点开查看详情 + 导入日历
 */
import { SheetUtil } from '../common/SheetUtil';
import { common } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { JwApi } from '../api/JwApi';
import { AppState } from '../common/AppState';
import { CalendarUtil } from '../common/CalendarUtil';
import { Const } from '../common/Constants';
import { DataStore } from '../common/DataStore';
import { DateUtil } from '../common/DateUtil';
import { Theme } from '../common/ThemeUtil';
import { ExamItem, TermInfo } from '../model/Models';
import { EmptyTip, LoadingTip, TagChip } from './common/UiKit';

@Component
export struct ExamPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('themeColor') themeColor: string = 'green';
  @State terms: TermInfo[] = [];
  @State selectedTermIndex: number = 0;
  @State exams: ExamItem[] = [];
  @State loading: boolean = true;
  @State showTermSheet: boolean = false;
  @State showDetail: boolean = false;
  @State selectedExam: ExamItem | null = null;
  /** 桌面卡片挑考试弹窗 */
  @State showPickExam: boolean = false;
  /** 当前用作桌面卡片倒计时的考试 id（空=用最近一场） */
  @State pickedExamId: string = '';
  @State refreshing: boolean = false;
  /** 进入方式：是否由桌面卡片点过来 */
  private enterFromCard: boolean = false;

  /** 页面出现：加载考试数据 */
  aboutToAppear(): void {
    this.pickedExamId = DataStore.getPickedExamId();
    // 桌面卡片跳转 → 进入 picker 模式，加载完后自动弹
    this.enterFromCard = AppState.openPageRequest === 'exam-pick';
    if (this.enterFromCard) {
      // 清空意图避免下次进入时反复触发
      AppState.openPageRequest = '';
    }
    this.load();
  }

  /** 加载完成回调（用于桌面卡片模式自动弹 picker） */
  private afterLoaded(): void {
    this.loading = false;
    if (this.enterFromCard) {
      this.enterFromCard = false;
      // 始终弹出选考试弹窗，让用户主动确认
      this.showPickExam = true;
    }
  }

  /** 选中要倒计时的考试 */
  private pickExamForCard(item: ExamItem | null): void {
    const id: string = item === null ? '' : item.id;
    DataStore.setPickedExamId(id);
    this.pickedExamId = id;
    if (item !== null) {
      promptAction.showToast({ message: `已设置《${item.courseName}》为桌面卡片倒计时` });
    } else {
      promptAction.showToast({ message: '已恢复为最近一场考试自动倒计时' });
    }
  }

  /** 根据 pickedExamId 查找课程名称（展示用） */
  private pickedExamName(): string {
    for (const ex of this.exams) {
      if (ex.id === this.pickedExamId) {
        return ex.courseName;
      }
    }
    return this.pickedExamId;
  }

  private async load(): Promise<void> {
    this.loading = true;
    // 本地生成年学期列表（保证选择可用）
    this.terms = await JwApi.getTerms();
    for (let i = 0; i < this.terms.length; i++) {
      if (this.terms[i].id === AppState.term.id) {
        this.selectedTermIndex = i;
        break;
      }
    }
    // 先用缓存秒开（仅当前学期）
    const cached: ExamItem[] = JwApi.loadCachedExams();
    if (cached.length > 0) {
      this.exams = cached.slice(0);
      this.loading = false;
    }
    try {
      await this.fetchSelectedTerm();
    } catch (e) {
      // 网络异常保持缓存
    }
    this.afterLoaded();
  }

  /** 下拉刷新：重新加载考试安排 */
  private async onRefresh(): Promise<void> {
    await this.load();
    this.refreshing = false;
  }

  private async fetchSelectedTerm(): Promise<void> {
    if (this.selectedTermIndex < 0 || this.selectedTermIndex >= this.terms.length) {
      return;
    }
    const term: TermInfo = this.terms[this.selectedTermIndex];
    const list: ExamItem[] = await JwApi.getExams(term.id);
    list.sort((a: ExamItem, b: ExamItem) => DateUtil.parse(a.date).getTime() - DateUtil.parse(b.date).getTime());
    this.exams = list;
  }

  private async selectTerm(index: number): Promise<void> {
    this.selectedTermIndex = index;
    this.showTermSheet = false;
    this.loading = true;
    try {
      await this.fetchSelectedTerm();
    } catch (e) {
      // ignore
    } finally {
      this.loading = false;
    }
  }

  /** 当前学期展示文案 */
  private currentTermLabel(): string {
    if (this.terms.length === 0 || this.selectedTermIndex >= this.terms.length) {
      return AppState.term.label;
    }
    return this.terms[this.selectedTermIndex].label;
  }

  /** 考试距今天数（正数=还有几天，0=今天，负数=已过去） */
  private daysLeft(item: ExamItem): number {
    return DateUtil.diffDays(new Date(), DateUtil.parse(item.date));
  }

  /** 倒计时 TagChip 文字颜色（按剩余天数分级：≤3天红紧急、≤7天黄中等、>7天绿充足；已结束灰） */
  private daysTagColor(d: number): Resource {
    if (d < 0) {
      return $r('app.color.text_tertiary');
    }
    if (d <= 3) {
      return $r('app.color.state_danger');
    }
    if (d <= 7) {
      return $r('app.color.state_warn');
    }
    return $r('app.color.state_success');
  }

  /** 待考场次数（未开始的考试数量） */
  private comingCount(): number {
    let n: number = 0;
    for (const e of this.exams) {
      if (this.daysLeft(e) >= 0) {
        n++;
      }
    }
    return n;
  }

  /** 最近一场考试的倒计时/时间文案 */
  private nextExamText(): string {
    for (const e of this.exams) {
      const d: number = this.daysLeft(e);
      if (d >= 0) {
        return d === 0 ? `今天有《${e.courseName}》考试，加油！` : `距离《${e.courseName}》还有 ${d} 天`;
      }
    }
    return '本学期考试已全部结束';
  }

  @Builder
  examCard(item: ExamItem) {
    Row() {
      Column() {
        Text(`${DateUtil.parse(item.date).getMonth() + 1}`)
          .fontSize(11)
          .fontColor(this.daysLeft(item) < 0 ? $r('app.color.text_tertiary') : $r('app.color.accent_orange'))
        Text(`${DateUtil.parse(item.date).getDate()}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.daysLeft(item) < 0 ? $r('app.color.text_tertiary') : $r('app.color.accent_orange'))
        Text(Const.WEEK_LABELS[DateUtil.weekdayOf(DateUtil.parse(item.date)) - 1])
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 2 })
      }
      .width(60)
      .padding({ top: 10, bottom: 10 })
      .backgroundColor($r('app.color.bg_chip'))
      .borderRadius(12)

      Column() {
        Row() {
          Text(item.courseName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.daysLeft(item) < 0 ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.daysLeft(item) < 0) {
            TagChip({ text: '已结束', color: $r('app.color.text_tertiary'), bg: $r('app.color.bg_chip') })
          } else if (this.daysLeft(item) === 0) {
            TagChip({ text: '今天', color: $r('app.color.brand_on'), bg: $r('app.color.state_danger') })
          } else {
            // 倒计时按远近分级配色：≤3天红(紧急)、≤7天黄(中等)、>7天绿(充足)
            TagChip({
              text: `${this.daysLeft(item)} 天后`,
              color: this.daysTagColor(this.daysLeft(item)),
              bg: $r('app.color.bg_chip')
            })
          }
        }
        .width('100%')

        Row() {
          Column()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(this.examTypeColor(item.examType))
            .margin({ right: 5 })
          Text(item.timeRange)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 4 })
          Column()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(this.examTypeColor(item.examType))
            .margin({ left: 12, right: 5 })
          Text(item.location)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 4 })
        }
        .width('100%')
        .margin({ top: 8 })

        Row() {
          TagChip({ text: item.examType, color: $r('app.color.brand'), bg: $r('app.color.brand_light') })
          Text(`座位号 ${item.seat}`)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ left: 8 })
          Blank()
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .layoutWeight(1)
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(16)
    .margin({ bottom: 12 })
    .opacity(this.daysLeft(item) < 0 ? 0.6 : 1)
    .onClick(() => {
      this.selectedExam = item;
      this.showDetail = true;
    })
  }

  @Builder
  detailSheet() {
    Column() {
      if (this.selectedExam !== null) {
        Row() {
          Column()
            .width(4)
            .height(20)
            .borderRadius(2)
            .backgroundColor($r('app.color.accent_orange'))
          Text(this.selectedExam.courseName)
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .layoutWeight(1)
        }
        .width('100%')
        .margin({ bottom: 16 })

        this.sheetRow('考试日期', `${this.selectedExam.date}（${Const.WEEK_LABELS[DateUtil.weekdayOf(DateUtil.parse(this.selectedExam.date)) - 1]}）`, this.examTypeColor(this.selectedExam.examType))
        this.sheetRow('考试时间', this.selectedExam.timeRange, this.examTypeColor(this.selectedExam.examType))
        this.sheetRow('考试地点', this.selectedExam.location, this.examTypeColor(this.selectedExam.examType))
        this.sheetRow('座位号', this.selectedExam.seat, this.examTypeColor(this.selectedExam.examType))
        this.sheetRow('考试性质', this.selectedExam.examType, this.examTypeColor(this.selectedExam.examType))

        Row() {
          Button('导入日历')
            .fontSize(15)
            .fontColor($r('app.color.brand'))
            .backgroundColor($r('app.color.brand_light'))
            .height(44)
            .borderRadius(12)
            .layoutWeight(1)
            .onClick(() => {
              if (this.selectedExam !== null) {
                const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
                CalendarUtil.addExamToCalendar(this.selectedExam, ctx);
              }
            })
          Button('关闭')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.bg_chip'))
            .height(44)
            .borderRadius(12)
            .layoutWeight(1)
            .margin({ left: 12 })
            .onClick(() => {
              this.showDetail = false;
            })
        }
        .width('100%')
        .margin({ top: 18 })
      }
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
                  Image($r('app.media.checkmark_circle'))
                    .width(16)
                    .height(16)
                    .fillColor($r('app.color.brand_on'))
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
  sheetRow(label: string, value: string, dotColor: string) {
    Row() {
      Column()
        .width(6)
        .height(6)
        .borderRadius(3)
        .backgroundColor(dotColor)
        .margin({ right: 10 })
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .width(72)
      Text(value)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 7, bottom: 7 })
  }

  /** 考试性质配色（互不冲突）：正考=农大绿 / 补考重修=橙 / 缓考=蓝 / 其他=灰 */
  private examTypeColor(examType: string): string {
    if (examType === '正考' || examType === '正常考试') {
      return '#079841';
    }
    if (examType === '补考' || examType === '重修') {
      return '#FF9800';
    }
    if (examType === '缓考') {
      return '#3B82F6';
    }
    return '#9E9E9E';
  }

  /**
   * 桌面卡片"选择倒计时考试"弹窗：列出未来未开始的考试，让用户主动选一场
   * 作为桌面卡片显示；点击即生效。
   */
  @Builder
  pickExamSheet() {
    Column() {
      // 顶部说明（去掉重复标题"桌面卡片倒计时"，sheet 自身 title 已显示）
      Text('选一场考试作为桌面卡片的倒计时对象')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ bottom: 4 })
      Text('不选则自动显示最近一场未开始的考试')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .margin({ bottom: 14 })

      // 当前选择状态
      Row() {
        Text(this.pickedExamId.length === 0 ? '当前: 最近一场考试自动倒计时' : `当前: ${this.pickedExamName()}`)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.pickedExamId.length > 0) {
          Text('清除选择')
            .fontSize(11)
            .fontColor('#2C5FA8')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
            .backgroundColor('rgba(44,95,168,0.10)')
            .onClick(() => {
              this.pickExamForCard(null);
              this.showPickExam = false;
            })
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor($r('app.color.bg_chip'))
      .borderRadius(10)
      .margin({ bottom: 12 })

      // 未来未开始的考试列表
      Scroll() {
        Column() {
          if (this.exams.length === 0) {
            Text('本学期暂无考试安排，刷新后重试')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .padding(20)
          } else {
            ForEach(this.exams, (item: ExamItem) => {
              if (this.daysLeft(item) >= 0) {
                Row() {
                  Column() {
                    Text(item.courseName)
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(`${item.date} ${item.timeRange} · ${item.location}`)
                      .fontSize(11)
                      .fontColor($r('app.color.text_secondary'))
                      .margin({ top: 4 })
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  .margin({ right: 8 })

                  if (this.pickedExamId === item.id) {
                    Text('当前使用')
                      .fontSize(11)
                      .fontColor($r('app.color.brand_on'))
                      .backgroundColor($r('app.color.brand'))
                      .height(24)
                      .padding({ left: 8, right: 8 })
                      .borderRadius(12)
                      .textAlign(TextAlign.Center)
                  } else {
                    Text('用作倒计时')
                      .fontSize(11)
                      .fontColor($r('app.color.brand'))
                      .backgroundColor($r('app.color.brand_light'))
                      .height(24)
                      .padding({ left: 8, right: 8 })
                      .borderRadius(12)
                      .textAlign(TextAlign.Center)
                      .onClick(() => {
                        this.pickExamForCard(item);
                        this.showPickExam = false;
                      })
                  }
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .backgroundColor(this.pickedExamId === item.id ? $r('app.color.brand_light') : $r('app.color.bg_card'))
                .borderRadius(10)
                .margin({ bottom: 6 })
              }
            }, (item: ExamItem) => item.id)
          }
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: 380 })

      // 底部关闭按钮
      Row() {
        Button('关闭')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.bg_chip'))
          .height(40)
          .layoutWeight(1)
          .borderRadius(10)
          .onClick(() => {
            this.showPickExam = false;
          })
      }
      .width('100%')
      .margin({ top: 14 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
  }

  build() {
    NavDestination() {
      // Stack 包裹：让"桌面卡片选考试"弹窗单独挂载在独立组件上，
      // 与外层 showTermSheet / 内层 showDetail 三种弹窗互不冲突
      Stack() {
      Column() {
        Row() {
          Text('‹')
            .fontSize(26)
            .fontColor(Color.White)
            .width(34)
            .height(34)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              AppState.stack.pop();
            })

          Column() {
            Text('考试查询')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(Color.White)
Row() {
              Text(`${this.currentTermLabel()} · 待考 ${this.comingCount()} 场`)
                .fontSize(11)
                .fontColor(this.isDarkMode ? $r('app.color.text_tertiary') : '#CCFFFFFF')
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
          .margin({ left: 6 })
          .layoutWeight(1)

          // 右上："桌面卡片"快捷按钮（纯文字，触发选考试弹窗）
          Text('桌面卡片')
            .fontSize(13)
            .fontColor('#CCFFFFFF')
            .height(28)
            .padding({ left: 12, right: 12 })
            .backgroundColor('#1AFFFFFF')
            .borderRadius(14)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              this.showPickExam = true;
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 10, right: 16, bottom: 12, top: px2vp(this.topInsetPx) + 12 })
        .height(px2vp(this.topInsetPx) + 60)
        .backgroundColor(this.isDarkMode ? '#1A1D1C' : Theme.colorOf(this.themeColor))

        // 考试详情弹层挂在内层容器，与外层"选择学期"弹层分离
        Column() {
          if (this.loading) {
            LoadingTip()
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
            Scroll() {
              Column() {
                Row() {
                  Column() {
                    Text(this.nextExamText())
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    Text('考试须携带学生证与身份证，提前 15 分钟入场')
                      .fontSize(11)
                      .fontColor($r('app.color.text_tertiary'))
                      .margin({ top: 4 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                .padding(14)
                .backgroundColor($r('app.color.brand_light'))
                .borderRadius(16)
                .margin({ bottom: 14 })

                if (this.exams.length === 0) {
                  EmptyTip({ text: '本学期暂无考试安排' })
                } else {
                  ForEach(this.exams, (item: ExamItem) => {
                    this.examCard(item)
                  }, (item: ExamItem) => item.id)
                }

                Column()
                  .height(px2vp(this.bottomInsetPx) + 16)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 14 })
            }
            .scrollBar(BarState.Off)
            .layoutWeight(1)
            .align(Alignment.Top)
            }
            .layoutWeight(1)
            .height('100%')
            .onRefreshing(() => { this.onRefresh(); })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .bindSheet($$this.showDetail, this.detailSheet(), {
          width: SheetUtil.sheetWidth(),
          preferType: SheetType.BOTTOM,
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          backgroundColor: $r('app.color.bg_card'),
          title: { title: '考试详情' }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
      .bindSheet($$this.showTermSheet, this.termPickerSheet(), {
        width: SheetUtil.sheetWidth(),
        preferType: SheetType.BOTTOM,
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        backgroundColor: $r('app.color.bg_card'),
        title: { title: '选择学年-学期' }
      })
      }
      // pickSheet 挂在最外 Stack 上，独立组件避免与 showTermSheet/showDetail 互相覆盖
      .width('100%')
      .height('100%')
      .bindSheet($$this.showPickExam, this.pickExamSheet(), {
        width: SheetUtil.sheetWidth(),
        preferType: SheetType.BOTTOM,
        height: SheetSize.LARGE,
        dragBar: true,
        backgroundColor: $r('app.color.bg_card'),
        title: { title: '选择桌面卡片倒计时' }
      })
    }
    .hideTitleBar(true)
  }
}