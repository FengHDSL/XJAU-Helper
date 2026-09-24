/**
 * 考试安排（二级页）：学年/学期选择 + 考试列表 + 点开查看详情 + 导入日历
 *
 * 卡片外观接入（照首页 HomeView / 关于页 AboutPage 的写法推广）：
 *  - 页面级卡片（顶部提示卡 / 考试卡）统一用 `MaterialCard` 承载（材质层在卡片内部、位于内容之下），
 *    材质生效时卡片自身的底色/磨砂/亮边/阴影一并让出，每张卡只有一层视觉；
 *    关闭光感回落为原来的纯色/毛玻璃卡片；
 *  - 原卡片上的 `.padding(...)` / `.borderRadius(...)` / `.margin(...)` / `.opacity(...)` / `.onClick(...)`
 *    一律改走 `cardPadding` / `cardRadius` / `cardMargin` / `cardOpacity` / `cardOnClick`
 *    （尾随闭包初始化的自定义组件之后不能再链式加属性）；
 *  - 弹窗内容套 `MaterialSheetPanel`，`bindSheet` 显式 `backgroundColor: Color.Transparent` +
 *    `blurStyle: sheetBlurStyle()`；弹窗**内部**的列表行保持原 Row 写法（面板本身已是材质，
 *    再包 MaterialCard 会在同一区域叠第二层材质）。
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
import { GlassMaterial } from '../common/GlassMaterial';
import { WallpaperTone } from '../common/WallpaperTone';
import { Immersive } from './common/Immersive';
import { ExamItem, TermInfo } from '../model/Models';
import { EmptyTip, LoadingTip, TagChip } from './common/UiKit';
import { BackButton } from './common/BackButton';
import { WallpaperFill } from './common/WallpaperFill';
// 沉浸光感：页面级卡片统一走 MaterialCard（材质承载层在卡片内容之下，材质生效时卡片底色/磨砂/亮边/阴影
// 一并让出，每张卡只剩一层视觉），胶囊小按钮走 MaterialButton，半模态弹窗内容走 MaterialSheetPanel
import { MaterialCard, MaterialSheetPanel } from './common/MaterialCard';
import { MaterialButton } from './common/MaterialButton';
import { sheetBlurStyle } from '../common/SystemMaterial';

@Component
export struct ExamPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 壁纸亮度（顶栏文字自适应用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('barStyle') barStyle: string = 'new';
  @StorageProp('immersiveEffect') immersiveEffect: boolean = true;
  /** 响应式依赖：玻璃/灰字设置变化时即时刷新本页（取值经 GlassMaterial 静态方法读取） */
  @StorageProp('glassStrength') glassStrength: number = 70;
  @StorageProp('cardMaterial') cardMaterial: boolean = false;
  /** 卡片沾色底色（广播键）：沾色开关变化时由 AppearanceStore.broadcastDerived() 重写 */
  @StorageProp('cardTintBg') tintBg: string = '';
  @StorageProp('grayTextMode') grayTextMode: string = 'default';
  @StorageProp('grayTextColor') grayTextColor: string = '';
  @StorageProp('subtitleColor') subtitleColor: string = '';
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
      this.getUIContext().getPromptAction().showToast({ message: `已设置《${item.courseName}》为桌面卡片倒计时` });
    } else {
      this.getUIContext().getPromptAction().showToast({ message: '已恢复为最近一场考试自动倒计时' });
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
  private daysTagColor(d: number): ResourceColor {
    if (d < 0) {
      return GlassMaterial.grayTertiary($r('app.color.text_tertiary'));
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
    // MaterialCard 承载：材质层是卡片内部底层、与卡片同尺寸同圆角，材质生效时卡片底色/磨砂/亮边/阴影让出；
    // 原 14vp 内边距走 cardPadding、16vp 圆角走 cardRadius、12vp 下间距走 cardMargin、
    // 已结束考试的 0.6 透明度走 cardOpacity、整卡点击走 cardOnClick
    // （尾随闭包初始化的自定义组件之后不能再链式加属性）。
    MaterialCard({
      cardRadius: 16,
      cardPadding: 14,
      cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
      cardBlur: GlassMaterial.cardBlur(),
      cardBorderW: GlassMaterial.cardBorderWidth(),
      cardBorderC: GlassMaterial.borderColor(),
      cardShadow: GlassMaterial.cardShadowStyle(),
      cardMargin: { bottom: 12 },
      cardOpacity: this.daysLeft(item) < 0 ? 0.6 : 1,
      cardOnClick: () => {
        this.selectedExam = item;
        this.showDetail = true;
      }
    }) {
    Row() {
      Column() {
        Text(`${DateUtil.parse(item.date).getMonth() + 1}`)
          .fontSize(11)
          .fontColor(this.daysLeft(item) < 0 ? GlassMaterial.grayTertiary($r('app.color.text_tertiary')) : $r('app.color.accent_orange'))
        Text(`${DateUtil.parse(item.date).getDate()}`)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.daysLeft(item) < 0 ? GlassMaterial.grayTertiary($r('app.color.text_tertiary')) : $r('app.color.accent_orange'))
        Text(Const.WEEK_LABELS[DateUtil.weekdayOf(DateUtil.parse(item.date)) - 1])
          .fontSize(10)
          .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
          .margin({ top: 2 })
      }
      .width(60)
      .padding({ top: 10, bottom: 10 })
      .backgroundColor($r('app.color.bg_chip')).backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? true) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
      .borderRadius(12)

      Column() {
        Row() {
          Text(item.courseName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.daysLeft(item) < 0 ? GlassMaterial.graySecondary($r('app.color.text_secondary')) : $r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          if (this.daysLeft(item) < 0) {
            TagChip({ text: '已结束', color: GlassMaterial.grayTertiary($r('app.color.text_tertiary')), bg: $r('app.color.bg_chip') })
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
            .fontColor(GlassMaterial.graySecondary($r('app.color.text_secondary')))
            .margin({ left: 4 })
          Column()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(this.examTypeColor(item.examType))
            .margin({ left: 12, right: 5 })
          Text(item.location)
            .fontSize(12)
            .fontColor(GlassMaterial.graySecondary($r('app.color.text_secondary')))
            .margin({ left: 4 })
        }
        .width('100%')
        .margin({ top: 8 })

        Row() {
          TagChip({ text: item.examType, color: Theme.colorOf(this.themeColor), bg: Theme.rgba(Theme.colorOf(this.themeColor), 0.12) })
          Text(`座位号 ${item.seat}`)
            .fontSize(11)
            .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
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
    }
  }

  @Builder
  detailSheet() {
    // 弹窗内容套 MaterialSheetPanel：bindSheet 自身的 systemMaterial 挂在面板上、内容区不生效，
    // 由 MaterialSheetPanel 的 Toggle 承载层渲染材质；配套硬要求（见 build 的 bindSheet 选项）
    // 是显式 backgroundColor: Color.Transparent（默认白底会把材质整块盖住）。
    // 高度随内容（SheetSize.FIT_CONTENT）→ panelFillHeight: false；内层 20/8/24vp 内边距原样保留。
    MaterialSheetPanel({ panelRadius: 20, panelPadding: 0, panelFillHeight: false, panelShowClose: true, panelOnClose: (): void => { this.showDetail = false; } }) {
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
          // 导入日历：材质走 MaterialButton 的 Toggle 承载层（普通 Button 直接挂材质真机不渲染）；
          // MaterialButton 的 Stack 内部 layoutWeight 不生效 → 把 layoutWeight 移到外层 Column，
          // 内容自己写 width('100%') / height(44) 把点击区撑满（与我的页备份弹窗同一写法）。
          Column() {
            MaterialButton({
              btnRadius: 12,
              btnBg: Theme.rgba(Theme.colorOf(this.themeColor), 0.12),
              btnBlur: BlurStyle.NONE,
              btnOnClick: () => {
                if (this.selectedExam !== null) {
                  const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
                  CalendarUtil.addExamToCalendar(this.selectedExam, ctx);
                }
              }
            }) {
              Text('导入日历')
                .fontSize(15)
                .fontColor(Theme.colorOf(this.themeColor))
                .width('100%')
                .height(44)
                .textAlign(TextAlign.Center)
            }
          }
          .layoutWeight(1)
          Column() {
            // 原按钮是「浅灰玻璃底 + 亮边 + 磨砂」，回落值按原值写（immersive 关时无磨砂、1vp 亮边）
            MaterialButton({
              btnRadius: 12,
              btnBg: $r('app.color.bg_chip'),
              btnBlur: (AppStorage.get<boolean>('immersiveEffect') ?? true) ? BlurStyle.Thin : BlurStyle.NONE,
              btnBorderW: 1,
              btnBorderC: 'rgba(255,255,255,0.28)',
              btnOnClick: () => {
                this.showDetail = false;
              }
            }) {
              Text('关闭')
                .fontSize(15)
                .fontColor(GlassMaterial.graySecondary($r('app.color.text_secondary')))
                .width('100%')
                .height(44)
                .textAlign(TextAlign.Center)
            }
          }
          .layoutWeight(1)
          .margin({ left: 12 })
        }
        .width('100%')
        .margin({ top: 18 })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
    }
  }

  @Builder
  termPickerSheet() {
    // 弹窗内容套 MaterialSheetPanel（同考试详情弹窗）：材质由 Toggle 承载层渲染，bindSheet 必须显式透明底；
    // 高度随内容（FIT_CONTENT）→ panelFillHeight: false；内层 20/8/24vp 内边距原样保留。
    MaterialSheetPanel({ panelRadius: 20, panelPadding: 0, panelFillHeight: false, panelShowClose: true, panelOnClose: (): void => { this.showTermSheet = false; } }) {
    Column() {
      if (this.terms.length === 0) {
        Text('暂无可查询的学期')
          .fontSize(13)
          .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        Scroll() {
          Column() {
            ForEach(this.terms, (term: TermInfo, index: number) => {
              // 学期行保留实色底：选中态靠实色背景（选中=主题色 / 未选中=浅灰）表达，
              // 沉浸光感材质会让出底色、把选中态吃掉，故不改为材质按钮。
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
          .width('100%')
        }
        .scrollBar(BarState.Off)
        .constraintSize({ maxHeight: 360 })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
    }
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
        .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
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
    // 弹窗内容套 MaterialSheetPanel（同详情/学期弹窗）：材质由 Toggle 承载层渲染，bindSheet 必须显式透明底；
    // 高度随内容（SheetSize.LARGE 固定高）→ 保持 panelFillHeight 默认 true，让材质裹住整块面板。
    MaterialSheetPanel({ panelRadius: 20, panelPadding: 0, panelShowClose: true, panelOnClose: (): void => { this.showPickExam = false; } }) {
    Column() {
      // 顶部说明（去掉重复标题"桌面卡片倒计时"，sheet 自身 title 已显示）
      Text('选一场考试作为桌面卡片的倒计时对象')
        .fontSize(12)
        .fontColor(GlassMaterial.graySecondary($r('app.color.text_secondary')))
        .width('100%')
        .margin({ bottom: 4 })
      Text('不选则自动显示最近一场未开始的考试')
        .fontSize(11)
        .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
        .width('100%')
        .margin({ bottom: 14 })

      // 当前选择状态
      Row() {
        Text(this.pickedExamId.length === 0 ? '当前: 最近一场考试自动倒计时' : `当前: ${this.pickedExamName()}`)
          .fontSize(12)
          .fontColor(GlassMaterial.graySecondary($r('app.color.text_secondary')))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (this.pickedExamId.length > 0) {
          // 清除选择：胶囊小按钮，材质走 MaterialButton 的 Toggle 承载层（btnBg 保留原蓝色浅底；
          // 原按钮无边框、无磨砂 → 光感关闭时按原样回落）
          MaterialButton({
            btnRadius: 4,
            btnBg: 'rgba(44,95,168,0.10)',
            btnBlur: BlurStyle.NONE,
            btnOnClick: () => {
              this.pickExamForCard(null);
              this.showPickExam = false;
            }
          }) {
            Text('清除选择')
              .fontSize(11)
              .fontColor('#2C5FA8')
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          }
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })
      .backgroundColor($r('app.color.bg_chip')).backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? true) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
      .borderRadius(10)
      .margin({ bottom: 12 })

      // 未来未开始的考试列表
      Scroll() {
        Column() {
          if (this.exams.length === 0) {
            Text('本学期暂无考试安排，刷新后重试')
              .fontSize(12)
              .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
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
                      .fontColor(GlassMaterial.graySecondary($r('app.color.text_secondary')))
                      .margin({ top: 4 })
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .layoutWeight(1)
                  .alignItems(HorizontalAlign.Start)
                  .margin({ right: 8 })

                  if (this.pickedExamId === item.id) {
                    // 「当前使用」是选中态标签（无点击）：保留实色底——选中态靠实色背景表达，
                    // 材质会让出底色、把选中态吃掉，故不改为材质按钮。
                    Text('当前使用')
                      .fontSize(11)
                      .fontColor($r('app.color.brand_on'))
                      .backgroundColor(Theme.colorOf(this.themeColor)).backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? true) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
                      .height(24)
                      .padding({ left: 8, right: 8 })
                      .borderRadius(12)
                      .textAlign(TextAlign.Center)
                  } else {
                    // 用作倒计时：胶囊小按钮，材质走 MaterialButton 的 Toggle 承载层
                    MaterialButton({
                      btnRadius: 12,
                      btnBg: Theme.rgba(Theme.colorOf(this.themeColor), 0.12),
                      btnBlur: GlassMaterial.cardBlur(),
                      btnBorderW: GlassMaterial.cardBorderWidth(),
                      btnBorderC: GlassMaterial.borderColor(),
                      btnOnClick: () => {
                        this.pickExamForCard(item);
                        this.showPickExam = false;
                      }
                    }) {
                      Text('用作倒计时')
                        .fontSize(11)
                        .fontColor(Theme.colorOf(this.themeColor))
                        .height(24)
                        .padding({ left: 8, right: 8 })
                        .textAlign(TextAlign.Center)
                    }
                  }
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .backgroundColor(this.pickedExamId === item.id ? Theme.rgba(Theme.colorOf(this.themeColor), 0.12) : (this.tintBg.length > 0 ? this.tintBg : GlassMaterial.homeCardBg($r('app.color.bg_card')))).backgroundBlurStyle(GlassMaterial.cardBlur()).border({ width: GlassMaterial.cardBorderWidth(), color: GlassMaterial.borderColor() }).shadow(GlassMaterial.cardShadowStyle()).clip(true)
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
        // 关闭：材质走 MaterialButton；原 Button 的 layoutWeight 移到外层 Column
        // （MaterialButton 的 Stack 内部 layoutWeight 不生效），内容自己撑满点击区。
        Column() {
          MaterialButton({
            btnRadius: 10,
            btnBg: $r('app.color.bg_chip'),
            btnBlur: (AppStorage.get<boolean>('immersiveEffect') ?? true) ? BlurStyle.Thin : BlurStyle.NONE,
            btnBorderW: 1,
            btnBorderC: 'rgba(255,255,255,0.28)',
            btnOnClick: () => {
              this.showPickExam = false;
            }
          }) {
            Text('关闭')
              .fontSize(14)
              .fontColor(GlassMaterial.graySecondary($r('app.color.text_secondary')))
              .width('100%')
              .height(40)
              .textAlign(TextAlign.Center)
          }
        }
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 14 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
    }
  }

  build() {
    NavDestination() {
      // Stack 包裹：让"桌面卡片选考试"弹窗单独挂载在独立组件上，
      // 与外层 showTermSheet / 内层 showDetail 三种弹窗互不冲突
      Stack() {
        // 二级页壁纸底层（无壁纸回 bg_page，不透下层）
        WallpaperFill()
      Column() {
        // 顶栏（两层）：内容(底)/主题渐变(顶)；模糊层已取消
        Stack({ alignContent: Alignment.TopStart }) {
          Column()
            .width('100%')
            .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
            .linearGradient({
              angle: 180,
              colors: Theme.barGradient(this.themeColor, this.barStyle)
            })
            .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, this.immersiveEffect && this.barStyle === 'legacy'))
        Row() {
          BackButton({ onBack: () => { AppState.stack.pop(); } })

          Column() {
            Text('考试查询')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
              .height(28)
              .lineHeight(28)
Row() {
              Text(`${this.currentTermLabel()} · 待考 ${this.comingCount()} 场`)
                .fontSize(11)
                .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
              Image($r('app.media.list_bullet'))
                .width(14)
                .height(14)
                .fillColor(this.subtitleColor.length > 0 ? this.subtitleColor : (this.barStyle === 'legacy' ? 'rgba(255,255,255,0.92)' : (this.isDarkMode ? GlassMaterial.grayTertiary($r('app.color.text_tertiary')) : '#CCFFFFFF')))
                .margin({ left: 3 })
            }
            .height(15)
            .margin({ top: 2 })
            .onClick(() => {
              this.showTermSheet = true;
            })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 6 })
          .layoutWeight(1)

          // 右上："桌面卡片"快捷按钮（触发选考试弹窗）→ MaterialButton（Toggle 承载层，btnPersistent 常驻：
          // 不随全局沉浸光感开关关闭而消失；光感关闭回落原白玻璃胶囊）。原 34 高胶囊由内容 Text height(34) 撑出，
          // 视觉与左侧返回按钮统一；微阴影随材质统一让出。
          MaterialButton({
            btnRadius: 17,
            btnPersistent: true,
            btnBg: this.isDarkMode ? 'rgba(255,255,255,0.16)' : 'rgba(255,255,255,0.24)',
            btnBlur: Immersive.blur(BlurStyle.Thin, this.immersiveEffect),
            btnBorderW: 1,
            btnBorderC: 'rgba(255,255,255,0.28)',
            btnOnClick: () => {
              this.showPickExam = true;
            }
          }) {
            Text('桌面卡片')
              .fontSize(13)
              .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
              .height(34)
              .padding({ left: 14, right: 14 })
              .textAlign(TextAlign.Center)
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Top)
        .padding({ left: 10, right: 16, bottom: 12, top: this.getUIContext().px2vp(this.topInsetPx) + 12 })
        .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
        }
        .width('100%')
        // 顶栏悬浮：正文可滚入其渐变下层透出
        .position({ x: 0, y: 0 })
        .zIndex(2)

        // 考试详情弹层挂在内层容器，与外层"选择学期"弹层分离
        Column() {
          if (this.loading) {
            LoadingTip()
          } else {
            Refresh({ refreshing: $$this.refreshing }) {
            Scroll() {
              Column() {
                // 顶栏悬浮让位（正文默认从顶栏下方开始，上滑才滚入渐变下层）
                Column().width('100%').height(this.getUIContext().px2vp(this.topInsetPx) + 60)
                // MaterialCard 承载：材质层是卡片内部底层，材质生效时卡片底色让出；
                // 原 14vp 内边距走 cardPadding、16vp 圆角走 cardRadius、14vp 下间距走 cardMargin；
                // 卡片底色是主题色淡底（材质不可用时回落它，观感与原卡片一致）
                MaterialCard({
                  cardRadius: 16,
                  cardPadding: 14,
                  cardBg: Theme.rgba(Theme.colorOf(this.themeColor), 0.12),
                  cardBlur: GlassMaterial.cardBlur(),
                  cardBorderW: GlassMaterial.cardBorderWidth(),
                  cardBorderC: GlassMaterial.borderColor(),
                  cardShadow: GlassMaterial.cardShadowStyle(),
                  cardMargin: { bottom: 14 }
                }) {
                Row() {
                  Column() {
                    Text(this.nextExamText())
                      .fontSize(14)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_primary'))
                    Text('考试须携带学生证与身份证，提前 15 分钟入场')
                      .fontSize(11)
                      .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
                      .margin({ top: 4 })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .layoutWeight(1)
                }
                .width('100%')
                }

                if (this.exams.length === 0) {
                  EmptyTip({ text: '本学期暂无考试安排' })
                } else {
                  ForEach(this.exams, (item: ExamItem) => {
                    this.examCard(item)
                  }, (item: ExamItem) => item.id)
                }

                Column()
                  .height(this.getUIContext().px2vp(this.bottomInsetPx) + 16)
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
            .pullToRefresh(false)
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
          // 关闭按钮由 MaterialSheetPanel 自绘（沉浸光感），系统 showClose 必须关掉避免双按钮
          showClose: false,
          // 必须显式透明：BindOptions.backgroundColor 默认是 Color.White，
          // 而沉浸光感的视觉层级位于 backgroundColor **之下**，白底会把 MaterialSheetPanel 的材质整块盖住。
          backgroundColor: Color.Transparent,
          blurStyle: sheetBlurStyle(),
          title: { title: '考试详情' }
        })
      }
      .width('100%')
      .height('100%')
      // 全局壁纸：二级页根背景透明，透出主框架底层壁纸（无壁纸时由 MainView 底层纯色兜底）
      .backgroundColor(Color.Transparent)
      .bindSheet($$this.showTermSheet, this.termPickerSheet(), {
        width: SheetUtil.sheetWidth(),
        preferType: SheetType.BOTTOM,
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        // 关闭按钮由 MaterialSheetPanel 自绘（沉浸光感），系统 showClose 必须关掉避免双按钮
        showClose: false,
        // 同考试详情弹窗：显式透明底 + 材质模糊（否则默认白底盖住 MaterialSheetPanel 的材质）
        backgroundColor: Color.Transparent,
        blurStyle: sheetBlurStyle(),
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
        // 关闭按钮由 MaterialSheetPanel 自绘（沉浸光感），系统 showClose 必须关掉避免双按钮
        showClose: false,
        // 同考试详情弹窗：显式透明底 + 材质模糊（否则默认白底盖住 MaterialSheetPanel 的材质）
        backgroundColor: Color.Transparent,
        blurStyle: sheetBlurStyle(),
        title: { title: '选择桌面卡片倒计时' }
      })
    }
    .backgroundColor($r('app.color.bg_page'))
    .hideTitleBar(true)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
  }
}