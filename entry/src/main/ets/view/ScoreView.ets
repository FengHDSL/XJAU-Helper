/**
 * 成绩查询：学年/学期选择 + 成绩明细（点击展开详情）
 * 不及格(<60) 红色，重修标蓝色，补考标橙色
 *
 * 说明：两个 bindSheet（成绩详情 / 选择学期）分别挂在不同的内层容器上，
 * 因为 ArkUI 同一组件上多次 .bindSheet 只有最后一个生效。
 *
 * 卡片外观接入（照首页 HomeView / 关于页 AboutPage 的写法推广）：
 *  - 卡片统一用 `MaterialCard` 承载（材质层在卡片内部、位于内容之下），材质生效时卡片自身的
 *    底色/磨砂/亮边/阴影一并让出，每张卡只有一层视觉；关闭光感回落为原来的纯色/毛玻璃卡片；
 *  - 原卡片上的 `.padding(...)` / `.borderRadius(...)` / `.margin(...)` / `.onClick(...)` 一律改走
 *    `cardPadding` / `cardRadius` / `cardMargin` / `cardOnClick`（尾随闭包初始化的自定义组件之后
 *    不能再链式加属性）；不对称的 padding（如 `{ top: 16, bottom: 16 }` 无法用 Length 表达）
 *    挂到内部内容容器上，间距与原值逐张对齐；
 *  - 弹窗内容套 `MaterialSheetPanel`，`bindSheet` 显式 `backgroundColor: Color.Transparent` +
 *    `blurStyle: sheetBlurStyle()`；网页弹层（WebSurface）是网页内容本身、不是材质面板，保持原样。
 */
import { SheetUtil } from '../common/SheetUtil';
import { JwApi } from '../api/JwApi';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { Theme } from '../common/ThemeUtil';
import { AppearanceStore } from '../common/AppearanceStore';
import { GlassMaterial } from '../common/GlassMaterial';
import { WallpaperTone } from '../common/WallpaperTone';
import { Immersive } from './common/Immersive';
import { ScoreItem, TermInfo, TermScore } from '../model/Models';
import { BarTitle, EmptyTip, LoadingTip, TagChip } from './common/UiKit';
import { AntiPeepOverlay } from './common/AntiPeepOverlay';
import { AntiPeepManager } from '../common/AntiPeepManager';
import { WebSurface } from './WebSurface';
import { promptAction, mediaquery } from '@kit.ArkUI';
import { ResponsiveUtil } from '../common/ResponsiveUtil';
// 沉浸光感：卡片统一走 MaterialCard（材质承载层在卡片内容之下，材质生效时卡片底色/磨砂/亮边/阴影一并让出，
// 每张卡只剩一层视觉），胶囊小按钮走 MaterialButton，半模态弹窗内容走 MaterialSheetPanel
import { MaterialCard, MaterialSheetPanel } from './common/MaterialCard';
import { MaterialButton } from './common/MaterialButton';
import { sheetBlurStyle } from '../common/SystemMaterial';

@Component
export struct ScoreView {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('barStyle') barStyle: string = 'new';
  /** 响应式依赖：玻璃/灰字设置变化时触发本页重渲染（取值经 GlassMaterial 静态方法读取） */
  @StorageProp('glassStrength') glassStrength: number = 70;
  @StorageProp('cardMaterial') cardMaterial: boolean = false;
  @StorageProp('grayTextMode') grayTextMode: string = 'default';
  @StorageProp('grayTextColor') grayTextColor: string = '';
  /** 灰字广播依赖登记：根容器 opacity 恒真表达式登记依赖，广播时本页重算灰字色 */
  @StorageProp('grayTick') grayTick: number = 0;
  @StorageProp('immersiveEffect') immersiveEffect: boolean = false;
  @StorageProp('subtitleColor') subtitleColor: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 壁纸亮度（顶栏文字/图标自适应用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  /** 全局字重响应式订阅：表达式读 this.fwMode 才登记依赖，fwValue 声明即订阅（custom 调值触发重渲染） */
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  @State terms: TermInfo[] = [];
  @State selectedTermIndex: number = 0;
  @State termScores: TermScore[] = [];
  @State loading: boolean = true;
  @State sortByScore: boolean = false;
  @State showSheet: boolean = false;
  @State selectedItem: ScoreItem | null = null;
  @State showTermSheet: boolean = false;
  @State showWeb: boolean = false;
  @State isLandscape: boolean = false;
  @State refreshing: boolean = false;
  @State isPeeped: boolean = false;
  private landscapeListener: mediaquery.MediaQueryListener | null = null;
  /** 窗口宽度断点监听（PC 窗口缩放时切换布局） */
  private wideListener: mediaquery.MediaQueryListener | null = null;
  /** 当前窗口是否横向 / 是否宽 ≥ 600vp（两者组合出布局判定） */
  private landscapeMq: boolean = false;
  private wideMq: boolean = false;
  private peepMgr: AntiPeepManager = new AntiPeepManager();

  /**
   * 学分绩点换算（依据教务处官网「课程及学分」kcjxf/list.htm）：
   * 100-95→4.5 | 94-90→4 | 89-85→3.5 | 84-80→3 | 79-75→2.5 | 74-70→2 | 69-65→1.5 | 64-60→1 | <60→0
   */
  private gpaOfScore(score: number): number {
    if (score >= 95) {
      return 4.5;
    }
    if (score >= 90) {
      return 4;
    }
    if (score >= 85) {
      return 3.5;
    }
    if (score >= 80) {
      return 3;
    }
    if (score >= 75) {
      return 2.5;
    }
    if (score >= 70) {
      return 2;
    }
    if (score >= 65) {
      return 1.5;
    }
    if (score >= 60) {
      return 1;
    }
    return 0;
  }

  /** 加权平均分 = ∑(百分制成绩×学分) / ∑学分（仅计百分制课程） */
  private calcAvgScore(items: ScoreItem[]): number {
    let sum: number = 0;
    let credits: number = 0;
    for (const s of items) {
      if (s.score > 0) {
        sum += s.score * s.credit;
        credits += s.credit;
      }
    }
    return credits > 0 ? sum / credits : 0;
  }

  /** 平均学分绩点 GPA = ∑(换算绩点×学分) / ∑学分（依据 kcjxf 方法，百分制课程） */
  private calcGpa(items: ScoreItem[]): number {
    let sum: number = 0;
    let credits: number = 0;
    for (const s of items) {
      if (s.score > 0) {
        sum += this.gpaOfScore(s.score) * s.credit;
        credits += s.credit;
      }
    }
    return credits > 0 ? sum / credits : 0;
  }

  /** 打开绩点计算方法网页（教务处官网 kcjxf，在"外部链接"页面中访问） */
  private openCalcWeb(): void {
    if (JwApi.USE_MOCK && !AppState.debugNetwork) {
      this.getUIContext().getPromptAction().showToast({ message: '当前模式禁止使用' });
      return;
    }
    AppState.webUrl = Const.JWC_KJXF_URL;
    AppState.webTitle = '课程及学分 · 绩点计算方法';
    AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
  }

  /** 顶部统计卡：按学校「课程及学分」方法自动计算的平均分与 GPA */
  @Builder
  statsCard() {
    // MaterialCard 承载：材质层是卡片内部底层、与卡片同尺寸同圆角，材质生效时卡片底色/磨砂/亮边/阴影让出；
    // 原卡片上的 18vp 圆角走 cardRadius、12vp 下间距走 cardMargin；上下 16vp 内边距无法用 Length 表达，
    // 挂到内部内容容器上（承载层才能铺满含 padding 的整块卡片）。
    MaterialCard({
      cardRadius: 18,
      cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
      cardBlur: GlassMaterial.cardBlur(),
      cardBorderW: GlassMaterial.cardBorderWidth(),
      cardBorderC: GlassMaterial.borderColor(),
      cardShadow: GlassMaterial.cardShadowStyle(),
      cardMargin: { bottom: 12 }
    }) {
    Row() {
      Column() {
        Text(this.calcAvgScore(this.sortedItems()).toFixed(2))
          .fontSize(28)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontColor($r('app.color.brand'))
        Text('平均分')
          .fontSize(11)
          .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      Column()
        .width(1)
        .height(36)
        .backgroundColor($r('app.color.divider'))

      Column() {
        Text(this.calcGpa(this.sortedItems()).toFixed(2))
          .fontSize(28)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontColor($r('app.color.brand'))
        Text('平均学分绩点 GPA')
          .fontSize(11)
          .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      Column()
        .width(1)
        .height(36)
        .backgroundColor($r('app.color.divider'))

      Column() {
        Text(`${this.currentTermScore()?.items.length ?? 0}`)
          .fontSize(28)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontColor($r('app.color.accent_orange'))
        Text('已修课程')
          .fontSize(11)
          .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    }
  }

  /** 绩点计算方法说明入口（网页） */
  @Builder
  calcInfoEntry() {
    // MaterialCard 承载：原 14vp 内边距走 cardPadding、上下 12/16vp 间距走 cardMargin、
    // 整卡点击走 cardOnClick（尾随闭包之后不能再链式写 .onClick）。
    MaterialCard({
      cardRadius: 14,
      cardPadding: 14,
      cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
      cardBlur: GlassMaterial.cardBlur(),
      cardBorderW: GlassMaterial.cardBorderWidth(),
      cardBorderC: GlassMaterial.borderColor(),
      cardShadow: GlassMaterial.cardShadowStyle(),
      cardMargin: { top: 12, bottom: 16 },
      cardOnClick: () => {
        this.openCalcWeb();
      }
    }) {
    Row() {
      Text('GPA 按学校「课程及学分」办法计算，仅供参考')
        .fontSize(12)
        .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
        .layoutWeight(1)
      Text('查看 ›')
        .fontSize(12)
        .fontColor($r('app.color.brand'))
    }
    .width('100%')
    }
  }

  /** 页面出现：加载成绩数据 */
  aboutToAppear(): void {
    // 注册全局学期切换监听（首页顶栏切换后立即同步本页）
    AppState.registerTermListener('score', () => {
      this.onTermSwitched();
    });
    this.load();
    this.listenLandscape();
    // 启动防窥保护监听
    this.peepMgr.start((hidden: boolean) => { this.isPeeped = hidden; });
  }

  aboutToDisappear(): void {
    this.landscapeListener = null;
    this.wideListener = null;
    this.peepMgr.stop();
  }

  /** 监听窗口尺寸/方向变化：窗口缩放或旋转时实时切换布局（判定规则见 ResponsiveUtil） */
  private listenLandscape(): void {
    const mq = this.getUIContext().getMediaQuery();
    this.landscapeMq = mq.matchMediaSync(ResponsiveUtil.QUERY_LANDSCAPE).matches;
    this.wideMq = mq.matchMediaSync(ResponsiveUtil.QUERY_WIDE).matches;
    this.applyLayout();
    this.landscapeListener = mq.matchMediaSync(ResponsiveUtil.QUERY_LANDSCAPE);
    this.landscapeListener.on('change', (res: mediaquery.MediaQueryResult) => {
      this.landscapeMq = res.matches;
      this.applyLayout();
    });
    this.wideListener = mq.matchMediaSync(ResponsiveUtil.QUERY_WIDE);
    this.wideListener.on('change', (res: mediaquery.MediaQueryResult) => {
      this.wideMq = res.matches;
      this.applyLayout();
    });
  }

  /** 组合出布局判定：宽 ≥ 600vp 且横向 → 大屏布局，否则手机端布局（见 ResponsiveUtil.isWideLayout） */
  private applyLayout(): void {
    this.isLandscape = ResponsiveUtil.isWideLayout(this.wideMq, this.landscapeMq);
  }

  /** 首页顶栏切换学期后：同步选中学期并重新加载成绩 */
  private async onTermSwitched(): Promise<void> {
    // 同步 selectedTermIndex 到 AppState.term.id
    for (let i: number = 0; i < this.terms.length; i++) {
      if (this.terms[i].id === AppState.term.id) {
        this.selectedTermIndex = i;
        break;
      }
    }
    // 清空旧学期成绩（避免与新学期混在一起）
    this.termScores = [];
    this.loading = true;
    try {
      await this.load();
    } catch (e) {
      // 网络异常时保持缓存
    }
    this.loading = false;
  }

  private async load(keepTerm: boolean = false): Promise<void> {
    this.loading = true;
    // 刷新时记录当前选中的学期 id，重建学期列表后找回原选择（不重置到当前学期）
    let targetTermId: string = '';
    if (keepTerm && this.selectedTermIndex >= 0 && this.selectedTermIndex < this.terms.length) {
      targetTermId = this.terms[this.selectedTermIndex].id;
    }
    // 本地生成年学期列表（保证学年学期选择一定可用）
    this.terms = await JwApi.getTerms();
    // 优先找回刷新前选中的学期；首次加载默认选中当前学期
    if (targetTermId === '') {
      targetTermId = AppState.term.id;
    }
    for (let i = 0; i < this.terms.length; i++) {
      if (this.terms[i].id === targetTermId) {
        this.selectedTermIndex = i;
        break;
      }
    }
    // 先用缓存秒开
    const cached: TermScore[] = JwApi.loadCachedTermScores();
    if (cached.length > 0) {
      this.termScores = cached;
      this.loading = false;
    }
    try {
      await this.fetchSelectedTerm();
    } catch (e) {
      // 网络异常时保持缓存
    }
    this.loading = false;
  }

  /** 下拉刷新：重新加载成绩（保留学期选择，清空已加载成绩后重新拉取） */
  private async onRefresh(): Promise<void> {
    this.termScores = [];
    await this.load(true);
    this.refreshing = false;
  }
  private async fetchSelectedTerm(): Promise<void> {
    if (this.selectedTermIndex < 0 || this.selectedTermIndex >= this.terms.length) {
      return;
    }
    const term: TermInfo = this.terms[this.selectedTermIndex];
    // 已在列表里则不再拉
    for (const t of this.termScores) {
      if (t.termId === term.id) {
        return;
      }
    }
    const scores: TermScore[] = await JwApi.getTermScores(term.id);
    for (const s of scores) {
      this.termScores.push(s);
    }
    this.termScores = this.termScores.slice(0);
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

  /** 当前学期成绩（按 terms 索引从 termScores 查） */
  private currentTermScore(): TermScore | null {
    if (this.terms.length === 0 || this.selectedTermIndex >= this.terms.length) {
      return this.termScores[0] ?? null;
    }
    const targetId: string = this.terms[this.selectedTermIndex].id;
    for (let i = 0; i < this.termScores.length; i++) {
      if (this.termScores[i].termId === targetId) {
        return this.termScores[i];
      }
    }
    return null;
  }

  /** 当前学期展示文案 */
  private currentTermLabel(): string {
    if (this.terms.length === 0 || this.selectedTermIndex >= this.terms.length) {
      return '';
    }
    return this.terms[this.selectedTermIndex].label;
  }

  /** 按绩点排序（开启时降序）后的成绩列表 */
  private sortedItems(): ScoreItem[] {
    const term: TermScore | null = this.currentTermScore();
    if (term === null) {
      return [];
    }
    const list: ScoreItem[] = term.items.slice(0);
    if (this.sortByScore) {
      list.sort((a: ScoreItem, b: ScoreItem) => b.gradePoint - a.gradePoint);
    }
    return list;
  }

  /** 成绩文本颜色（及格绿/不及格红） */
  private scoreColor(item: ScoreItem): Resource {
    if (item.score < 0) {
      return $r('app.color.brand');
    }
    if (item.score < 60) {
      return $r('app.color.state_danger');
    }
    if (item.score >= 90) {
      return $r('app.color.state_success');
    }
    if (item.score >= 80) {
      return $r('app.color.brand');
    }
    if (item.score >= 70) {
      return $r('app.color.accent_blue');
    }
    return $r('app.color.state_warn');
  }

  /** 考试性质标签颜色 */
  private examTypeColor(item: ScoreItem): Resource {
    if (item.examType.indexOf('重修') >= 0) {
      return $r('app.color.accent_blue');
    }
    if (item.examType.indexOf('补考') >= 0) {
      return $r('app.color.accent_orange');
    }
    return $r('app.color.brand');
  }

  @Builder
  topBar() {
    // 顶栏（保留新版效果）：主题色渐变（新版）/实色（旧版 1.3.1），占位式不悬浮
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
        Column() {
          // 统一标题组件（大标题固定高 28，副标题独立行）
          BarTitle({
            title: '成绩查询',
            subtitle: this.currentTermLabel(),
            showChevron: true,
            onSubtitleTap: () => { this.showTermSheet = true; }
          })
        }
        .alignItems(HorizontalAlign.Start)
        .onClick(() => {
          this.showTermSheet = true;
        })

        Blank()
      }
      .width('100%')
      .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
      .padding({ left: 16, right: 16, bottom: 12, top: this.getUIContext().px2vp(this.topInsetPx) + 12 })
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    // 悬浮顶栏：内容上滑可穿入渐变下层透出
    .position({ x: 0, y: 0 })
    .zIndex(2)
  }

  @Builder
  scoreRow(item: ScoreItem) {
    Row() {
      Column() {
        Text(item.courseName)
          .fontSize(15)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row() {
          TagChip({
            text: item.courseType,
            color: item.courseType === '必修' ? $r('app.color.brand') : $r('app.color.accent_blue'),
            bg: $r('app.color.bg_chip')
          })
          if (item.examType !== '正常考试') {
            TagChip({
              text: item.examType,
              color: this.examTypeColor(item),
              bg: $r('app.color.bg_chip')
            })
              .margin({ left: 6 })
          }
          Text(`${item.credit} 学分`)
            .fontSize(11)
            .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
            .margin({ left: 8 })
        }
        .width('100%')
        .margin({ top: 7 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Column() {
        Text(item.scoreText)
          .fontSize(20)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontColor(this.scoreColor(item))
        Text(`绩点 ${item.gradePoint.toFixed(1)}`)
          .fontSize(10)
          .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.End)
      .margin({ left: 12 })
    }
    .width('100%')
    .padding({ top: 14, bottom: 14 })
    .onClick(() => {
      this.selectedItem = item;
      this.showSheet = true;
    })
  }

  @Builder
  detailSheet() {
    // 弹窗内容套 MaterialSheetPanel：bindSheet 自身的 systemMaterial 挂在面板上、内容区不生效，
    // 由 MaterialSheetPanel 的 Toggle 承载层渲染材质。配套硬要求（见 build 里的 bindSheet）：
    // 显式 backgroundColor: Color.Transparent，否则默认白底会把材质整块盖住。
    // 本弹窗高度随内容（SheetSize.FIT_CONTENT）→ panelFillHeight: false；
    // 原内容的 20/8/24vp 内边距原样留在内层 Column 上（panelPadding: 0，间距不变）。
    // 关闭按钮由面板自绘（沉浸光感），替代系统 showClose。
    MaterialSheetPanel({ panelRadius: 20, panelPadding: 0, panelFillHeight: false,
      panelShowClose: true, panelOnClose: (): void => { this.showSheet = false; } }) {
    Column() {
      if (this.selectedItem !== null) {
        Row() {
          Text(this.selectedItem.courseName)
            .fontSize(19)
            .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text(this.selectedItem.scoreText)
            .fontSize(28)
            .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
            .fontColor(this.scoreColor(this.selectedItem))
        }
        .width('100%')
        .margin({ bottom: 14 })

        this.detailRow('课程名称', this.selectedItem.courseName, this.courseAttrColor(this.selectedItem.courseType))
        // 课程属性：显示为符号标签（必修=绿色、选修=蓝色，与成绩卡片一致）+ 学分
        Row() {
          Column()
            .width(6)
            .height(6)
            .borderRadius(3)
            .backgroundColor(this.courseAttrColor(this.selectedItem.courseType))
            .margin({ right: 10 })
          Text('课程属性')
            .fontSize(13)
            .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
            .width(72)
          Row() {
            TagChip({
              text: this.selectedItem.courseType,
              color: this.selectedItem.courseType === '必修' ? $r('app.color.brand') : $r('app.color.accent_blue'),
              bg: $r('app.color.bg_chip')
            })
            Text(`${this.selectedItem.credit} 学分`)
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
              .margin({ left: 8 })
          }
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ top: 7, bottom: 7 })
        this.detailRow('任课教师', this.selectedItem.teacher.length > 0 ? this.selectedItem.teacher : '暂未公布',
          this.courseAttrColor(this.selectedItem.courseType))
        this.detailRow('成绩', `${this.selectedItem.scoreText}（绩点 ${this.selectedItem.gradePoint.toFixed(1)}）`,
          this.courseAttrColor(this.selectedItem.courseType))
        this.detailRow('考试性质', this.selectedItem.examType, this.courseAttrColor(this.selectedItem.courseType))
        this.detailRow('所属学期', this.currentTermLabel(), this.courseAttrColor(this.selectedItem.courseType))

        // 关闭按钮：材质走 MaterialButton 的 Toggle 承载层（普通 Button 直接挂材质真机不渲染）；
        // 原 .width('100%')/.height(44)/.margin({ top: 18 })/.onClick 改由内容与 btnMargin/btnOnClick 承担，
        // 点击行为与文案不变。原按钮是纯色底（无边框、无磨砂）→ 光感关闭时按原样回落（NONE / 无边）。
        MaterialButton({
          btnRadius: 12,
          btnBg: $r('app.color.brand_light'),
          btnBlur: BlurStyle.NONE,
          btnMargin: { top: 18 },
          btnOnClick: () => {
            this.showSheet = false;
          }
        }) {
          Text('关闭')
            .fontSize(15)
            .fontColor($r('app.color.brand'))
            .width('100%')
            .height(44)
            .textAlign(TextAlign.Center)
        }
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
    }
  }

  /** 课程属性配色（互不冲突）：必修=农大绿 / 选修=天空蓝 / 实践=橙 / 其他=灰 */
  private courseAttrColor(courseType: string): string {
    if (courseType === '必修') {
      return '#079841';
    }
    if (courseType === '选修') {
      return '#3B82F6';
    }
    if (courseType === '实践') {
      return '#FF9800';
    }
    return '#9E9E9E';
  }

  @Builder
  detailRow(label: string, value: string, dotColor: string) {
    Row() {
      // 课程属性色小圆点（与课程详情弹层风格一致）
      Column()
        .width(6)
        .height(6)
        .borderRadius(3)
        .backgroundColor(dotColor)
        .margin({ right: 10 })
      Text(label)
        .fontSize(13)
        .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
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

  @Builder
  termPickerSheet() {
    // 弹窗内容套 MaterialSheetPanel（同 detailSheet）：材质由 Toggle 承载层渲染，配套要求 bindSheet 显式透明底。
    // 高度随内容（FIT_CONTENT）→ panelFillHeight: false；内层 Column 的 20/8/24vp 内边距原样保留。
    // 关闭按钮由面板自绘（沉浸光感），替代系统 showClose。
    MaterialSheetPanel({ panelRadius: 20, panelPadding: 0, panelFillHeight: false,
      panelShowClose: true, panelOnClose: (): void => { this.showTermSheet = false; } }) {
    Column() {
      if (this.terms.length === 0) {
        Text('暂无可查询的学期')
          .fontSize(13)
          .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
          .width('100%')
          .textAlign(TextAlign.Center)
      } else {
        Scroll() {
          Column() {
            ForEach(this.terms, (term: TermInfo, index: number) => {
              // 学期行保留实色底：选中态完全靠实色背景（选中=品牌色 / 未选中=浅灰）表达，
              // 而沉浸光感材质会让出底色、把选中态吃掉，故此处不改为材质按钮。
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
  }

  build() {
    Stack() {
      Column() {
      this.topBar()
      if (this.isLandscape) {
        if (this.loading) {
          LoadingTip()
        } else if (this.currentTermScore() === null || this.currentTermScore()!.items.length === 0) {
          // 横屏空态：顶部让位顶栏 + 空态卡限宽 720vp 居中（平板/大屏横屏下不铺满整屏，与内容区一多适配一致）
          Column() {
            Column()
              .width('100%')
              .height(this.getUIContext().px2vp(this.topInsetPx) + 72)
            // MaterialCard 承载：宽度由外层限宽容器控制、18vp 圆角走 cardRadius；
            // 上下 40vp 内边距挂内部内容容器（承载层铺满整块卡片）。
            Column() {
              MaterialCard({
                cardWidth: '100%',
                cardRadius: 18,
                cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
                cardBlur: GlassMaterial.cardBlur(),
                cardBorderW: GlassMaterial.cardBorderWidth(),
                cardBorderC: GlassMaterial.borderColor(),
                cardShadow: GlassMaterial.cardShadowStyle()
              }) {
              Column() {
                EmptyTip({ text: '本学期成绩尚未发布\n期末考试结束两周后可查询' })
              }
              .width('100%')
              .padding({ top: 40, bottom: 40 })
              }
            }
            .width('100%')
            .constraintSize({ maxWidth: 720 })
            .padding({ left: 16, right: 16 })
          }
          .width('100%')
          .height('100%')
          .backgroundColor(Color.Transparent)
        } else {
          this.scoreLandscape()
        }
      } else {
      // 成绩详情弹层挂在内层容器，与外层"选择学期"弹层分离（ArkUI 同组件多 bindSheet 只有最后一个生效）
      // 横屏/平板下内容限宽 720vp 并居中（一多适配）
      Column() {
        if (this.loading) {
          LoadingTip()
        } else {
          Row() {
            Refresh({ refreshing: $$this.refreshing }) {
            Scroll() {
              Column() {
                // 顶栏让位（随内容滚走）：初始内容位于悬浮渐变顶栏下方
                Column()
                  .width('100%')
                  .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
                if (this.currentTermScore() === null || this.currentTermScore()!.items.length === 0) {
                  // MaterialCard 承载：材质层在卡片内部底层，材质生效时卡片底色/磨砂/亮边/阴影让出；
                  // 原卡片上的 18vp 圆角走 cardRadius（原卡片无内边距，EmptyTip 自带留白）。
                  MaterialCard({
                    cardRadius: 18,
                    cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
                    cardBlur: GlassMaterial.cardBlur(),
                    cardBorderW: GlassMaterial.cardBorderWidth(),
                    cardBorderC: GlassMaterial.borderColor(),
                    cardShadow: GlassMaterial.cardShadowStyle()
                  }) {
                    EmptyTip({ text: '本学期成绩尚未发布\n期末考试结束两周后可查询' })
                  }
              } else {
                this.statsCard()
                Row() {
                  Text(`共 ${this.currentTermScore()!.items.length} 门`)
                    .fontSize(16)
                    .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
                    .fontColor($r('app.color.text_primary'))
                  Blank()
                  Text(this.sortByScore ? '按绩点排序 ⇅' : '默认排序 ⇅')
                    .fontSize(12)
                    .fontColor($r('app.color.brand'))
                    .onClick(() => {
                      this.sortByScore = !this.sortByScore;
                    })
                }
                .width('100%')
                .margin({ top: 4, bottom: 6 })

                // MaterialCard 承载：材质层是卡片内部底层、与卡片同尺寸同圆角，材质生效时卡片底色让出；
                // 原卡片上的 18vp 圆角走 cardRadius；左右 16vp 内边距（不对称）挂内部内容容器，间距不变。
                MaterialCard({
                  cardRadius: 18,
                  cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
                  cardBlur: GlassMaterial.cardBlur(),
                  cardBorderW: GlassMaterial.cardBorderWidth(),
                  cardBorderC: GlassMaterial.borderColor(),
                  cardShadow: GlassMaterial.cardShadowStyle()
                }) {
                Column() {
                  ForEach(this.sortedItems(), (item: ScoreItem, index: number) => {
                    Column() {
                      this.scoreRow(item)
                      if (index < this.currentTermScore()!.items.length - 1) {
                        Divider()
                          .color($r('app.color.divider'))
                      }
                    }
                  }, (item: ScoreItem) => item.id)
                }
                .width('100%')
                .padding({ left: 16, right: 16 })
                }

                this.calcInfoEntry()
              }
              // 底部预留悬浮底栏高度，避免最后一项成绩被遮挡
              Column()
                .height(100)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14 })
            }
            .width(720)
            .constraintSize({ maxWidth: '100%' })
            .height('100%')
            .scrollBar(BarState.Off)
            .align(Alignment.Top)
            .edgeEffect(EdgeEffect.Spring)
            // 中间层透明：不遮挡底层壁纸（卡片与文字为最上层）
            .backgroundColor(Color.Transparent)
            // 绩点计算方法网页挂在内层 Scroll（同组件多 bindSheet 仅最后一个生效，故与其他弹层分离）
            .bindSheet($$this.showWeb, this.webSheet(), {
              width: SheetUtil.sheetWidth(),
              preferType: SheetType.BOTTOM,
              height: SheetSize.LARGE,
              dragBar: false,
              backgroundColor: $r('app.color.bg_page'),
              title: { title: AppState.webTitle }
            })
            }
            .width(720)
            .constraintSize({ maxWidth: '100%' })
            .height('100%')
            .onRefreshing(() => { this.onRefresh(); })
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center) // 横屏/平板下成绩列表居中
        }
      }
      .width('100%')
      .layoutWeight(1)
      // 悬浮底栏模式下 Scroll 内容区延伸到屏幕底部，靠内容自身 bottom 预留空间
      // （网页弹层仍用不透明 bg_page——它承载的是 WebSurface 网页内容，不是材质面板，故不套 MaterialSheetPanel）
      .bindSheet($$this.showSheet, this.detailSheet(), {
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
        title: { title: '成绩详情' }
      })
    }
    }
    .width('100%')
    .height('100%')
    // 背景透明：跟随全局壁纸/主题底色（与其它 Tab 一致）
    .backgroundColor(Color.Transparent)
    .bindSheet($$this.showTermSheet, this.termPickerSheet(), {
      width: SheetUtil.sheetWidth(),
      preferType: SheetType.BOTTOM,
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      // 关闭按钮由 MaterialSheetPanel 自绘（沉浸光感），系统 showClose 必须关掉避免双按钮
      showClose: false,
      // 同 detailSheet：显式透明底 + 材质模糊，否则默认白底会盖住 MaterialSheetPanel 的材质
      backgroundColor: Color.Transparent,
      blurStyle: sheetBlurStyle(),
      title: { title: '选择学年-学期' }
    })

      AntiPeepOverlay({ isPeeped: this.isPeeped })
    }
    .width('100%')
    .height('100%')
    // 灰字广播依赖登记：grayTick 变化触发整页重算 graySecondary/grayTertiary 文本色（恒真不改变视觉）
    .opacity(this.grayTick >= 0 ? 1 : 1)
  }

  @Builder
  scoreLandscape() {
    Column() {
      Row() {
        // 左列：统计卡随列一起滚动（修：统计卡固定占位过高时平板横屏下方列表区被挤没、整页无法滑动）
        Refresh({ refreshing: $$this.refreshing }) {
          Scroll() {
            Column() {
              this.statsCard()
              this.scoreListColumn(this.sortedItems().filter((_item: ScoreItem, i: number) => i % 2 === 0))
            }
            .width('100%')
            // 顶栏让位随内容滚走（与竖屏一致），底部预留悬浮底栏高度
            .padding({ left: 16, right: 8, top: this.getUIContext().px2vp(this.topInsetPx) + 86, bottom: 100 })
          }
          .layoutWeight(1)
          .height('100%')
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .edgeEffect(EdgeEffect.Spring)
          .bindSheet($$this.showSheet, this.detailSheet(), {
            width: SheetUtil.sheetWidth(),
            preferType: SheetType.BOTTOM,
            height: SheetSize.FIT_CONTENT,
            dragBar: true,
            // 关闭按钮由 MaterialSheetPanel 自绘（沉浸光感），系统 showClose 必须关掉避免双按钮
            showClose: false,
            // 同竖屏成绩详情弹层：显式透明底 + 材质模糊（MaterialSheetPanel 才能透出材质）
            backgroundColor: Color.Transparent,
            blurStyle: sheetBlurStyle(),
            title: { title: '成绩详情' }
          })
        }
        .layoutWeight(1)
        .height('100%')
        .onRefreshing(() => { this.onRefresh(); })

        // 右列
        Refresh({ refreshing: $$this.refreshing }) {
          Scroll() {
            Column() {
              this.scoreListColumn(this.sortedItems().filter((_item: ScoreItem, i: number) => i % 2 === 1))
              this.calcInfoEntry()
            }
            .width('100%')
            .padding({ left: 8, right: 16, top: this.getUIContext().px2vp(this.topInsetPx) + 86, bottom: 100 })
          }
          .layoutWeight(1)
          .height('100%')
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .edgeEffect(EdgeEffect.Spring)
        }
        .layoutWeight(1)
        .height('100%')
        .onRefreshing(() => { this.onRefresh(); })
      }
      .layoutWeight(1)
      .align(Alignment.Top)
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.Top)
  }

  @Builder
  scoreListColumn(items: ScoreItem[]) {
    // MaterialCard 承载（横屏左右列各一张）：原 18vp 圆角走 cardRadius，左右 16vp 内边距挂内部内容容器。
    MaterialCard({
      cardRadius: 18,
      cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
      cardBlur: GlassMaterial.cardBlur(),
      cardBorderW: GlassMaterial.cardBorderWidth(),
      cardBorderC: GlassMaterial.borderColor(),
      cardShadow: GlassMaterial.cardShadowStyle()
    }) {
    Column() {
      ForEach(items, (item: ScoreItem, idx: number) => {
        Column() {
          this.scoreRow(item)
          if (idx < items.length - 1) {
            Divider().color($r('app.color.divider'))
          }
        }
      }, (item: ScoreItem) => item.id)
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    }
  }

  @Builder
  webSheet() {
    WebSurface()
  }
}
