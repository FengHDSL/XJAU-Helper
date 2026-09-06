/**
 * 成绩查询：学年/学期选择 + 成绩明细（点击展开详情）
 * 不及格(<60) 红色，重修标蓝色，补考标橙色
 *
 * 说明：两个 bindSheet（成绩详情 / 选择学期）分别挂在不同的内层容器上，
 * 因为 ArkUI 同一组件上多次 .bindSheet 只有最后一个生效。
 */
import { SheetUtil } from '../common/SheetUtil';
import { JwApi } from '../api/JwApi';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { Theme } from '../common/ThemeUtil';
import { ScoreItem, TermInfo, TermScore } from '../model/Models';
import { EmptyTip, LoadingTip, TagChip } from './common/UiKit';
import { AntiPeepOverlay } from './common/AntiPeepOverlay';
import { AntiPeepManager } from '../common/AntiPeepManager';
import { WebSurface } from './WebSurface';
import { promptAction, mediaquery } from '@kit.ArkUI';

@Component
export struct ScoreView {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('barStyle') barStyle: string = 'new';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
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
      promptAction.showToast({ message: '当前模式禁止使用' });
      return;
    }
    AppState.webUrl = Const.JWC_KJXF_URL;
    AppState.webTitle = '课程及学分 · 绩点计算方法';
    AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
  }

  /** 顶部统计卡：按学校「课程及学分」方法自动计算的平均分与 GPA */
  @Builder
  statsCard() {
    Row() {
      Column() {
        Text(this.calcAvgScore(this.sortedItems()).toFixed(2))
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand'))
        Text('平均分')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
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
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand'))
        Text('平均学分绩点 GPA')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
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
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.accent_orange'))
        Text('已修课程')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
    .margin({ bottom: 12 })
  }

  /** 绩点计算方法说明入口（网页） */
  @Builder
  calcInfoEntry() {
    Row() {
      Text('GPA 按学校「课程及学分」办法计算，仅供参考')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
      Text('查看 ›')
        .fontSize(12)
        .fontColor(Theme.colorOf(this.themeColor))
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.bg_chip'))
    .borderRadius(14)
    .margin({ top: 12, bottom: 16 })
    .onClick(() => {
      this.openCalcWeb();
    })
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
    this.peepMgr.stop();
  }

  /** 监听屏幕方向变化（横屏时拆分为两列铺满屏幕） */
  private listenLandscape(): void {
    const mq: mediaquery.MediaQueryResult = mediaquery.matchMediaSync('(orientation: landscape)');
    this.isLandscape = mq.matches;
    this.landscapeListener = mediaquery.matchMediaSync('(orientation: landscape)');
    this.landscapeListener.on('change', (res: mediaquery.MediaQueryResult) => {
      this.isLandscape = res.matches;
    });
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

  private async load(): Promise<void> {
    this.loading = true;
    // 本地生成年学期列表（保证学年学期选择一定可用）
    this.terms = await JwApi.getTerms();
    // 默认选中当前学期
    for (let i = 0; i < this.terms.length; i++) {
      if (this.terms[i].id === AppState.term.id) {
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
    // 保留旧数据直到新数据就绪；try/finally 兜底复位，避免异常导致刷新态悬挂（黑/白屏）
    try {
      await this.load();
    } catch (e) {
    } finally {
      setTimeout(() => { this.refreshing = false; }, 120);
    }
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

  /** 成绩文本颜色（静态语义，不随主题）：<60 红 / 60-69 黄褐 / 70-79 蓝 / 80-89 农大绿 / 90+ 深绿 */
  private scoreColor(item: ScoreItem): ResourceColor {
    if (item.score < 0) {
      return '#9E9E9E';
    }
    if (item.score < 60) {
      return $r('app.color.state_danger');
    }
    if (item.score >= 90) {
      return $r('app.color.state_success');
    }
    if (item.score >= 80) {
      return '#079841';
    }
    if (item.score >= 70) {
      return $r('app.color.accent_blue');
    }
    return $r('app.color.state_warn');
  }

  /** 考试性质标签颜色 */
  private examTypeColor(item: ScoreItem): ResourceColor {
    if (item.examType.indexOf('重修') >= 0) {
      return $r('app.color.accent_blue');
    }
    if (item.examType.indexOf('补考') >= 0) {
      return $r('app.color.accent_orange');
    }
    return Theme.colorOf(this.themeColor);
  }

  @Builder
  topBar() {
    // 顶部标题栏（三层）：内容(底) / 全透明模糊(中) / 主题渐变(顶)
    Stack({ alignContent: Alignment.TopStart }) {
      // 顶：主题色渐变
      Column()
        .width('100%')
        .height(px2vp(this.topInsetPx) + 60)
        .linearGradient({
          angle: 180,
          colors: Theme.barGradient(this.themeColor, this.barStyle)
        })
    Column() {
      Row() {
        Column() {
          Text('成绩查询')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
          Row() {
            Text(this.currentTermLabel())
              .fontSize(11)
              .fontColor(this.barStyle === 'legacy' ? 'rgba(255,255,255,0.92)' : (this.isDarkMode ? $r('app.color.text_tertiary') : '#CCFFFFFF'))
            Image($r('app.media.list_bullet'))
              .width(14)
              .height(14)
              .fillColor(this.barStyle === 'legacy' ? 'rgba(255,255,255,0.92)' : (this.isDarkMode ? $r('app.color.text_tertiary') : '#CCFFFFFF'))
              .margin({ left: 3 })
          }
          .margin({ top: 6 })
          .onClick(() => {
            this.showTermSheet = true;
          })
        }
        .alignItems(HorizontalAlign.Start)
        // ★ 主标题整组微调：只改这个 offset 的 y（正=下移 / 负=上移）
        .offset({ y: -5 })

        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(px2vp(this.topInsetPx) + 60)
    .padding({ left: 16, right: 16, bottom: 12, top: px2vp(this.topInsetPx) + 23 })
    }
    .width('100%')
    // 内容穿透：三层顶栏悬浮最上层、不占布局空间，内容可滚入其下层（与首页/我的页一致）
    .position({ x: 0, y: 0 })
    .zIndex(2)
  }

  @Builder
  scoreRow(item: ScoreItem) {
    Row() {
      Column() {
        Text(item.courseName)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Row() {
          TagChip({
            text: item.courseType,
            color: item.courseType === '必修' ? '#079841' : $r('app.color.accent_blue'),
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
            .fontColor($r('app.color.text_tertiary'))
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
          .fontWeight(FontWeight.Bold)
          .fontColor(this.scoreColor(item))
        Text(`绩点 ${item.gradePoint.toFixed(1)}`)
          .fontSize(10)
          .fontColor($r('app.color.text_tertiary'))
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
    Column() {
      if (this.selectedItem !== null) {
        Row() {
          Text(this.selectedItem.courseName)
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
          Text(this.selectedItem.scoreText)
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
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
            .fontColor($r('app.color.text_tertiary'))
            .width(72)
          Row() {
            TagChip({
              text: this.selectedItem.courseType,
              color: this.selectedItem.courseType === '必修' ? '#079841' : $r('app.color.accent_blue'),
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

        Button('关闭')
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor(Theme.colorOf(this.themeColor))
          .backgroundColor(Theme.rgba(Theme.colorOf(this.themeColor), 0.12))
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

  build() {
    Stack() {
      Column() {
      this.topBar()
      if (this.isLandscape) {
        if (this.loading && !this.refreshing) {
          LoadingTip()
        } else if (this.currentTermScore() === null || this.currentTermScore()!.items.length === 0) {
        // 横屏空态：位于顶栏下方（与竖屏一致），可下拉刷新
        Column() {
          Refresh({ refreshing: $$this.refreshing }) {
            Scroll() {
              Column() {
                // 顶栏占位（卡片在顶栏下方；想下移卡片就增大此值）
                Column()
                  .width('100%')
                  .height(px2vp(this.topInsetPx) + 1)
                // 与"平均成绩"卡片同宽同风格：紧凑提示，不撑高
                Column() {
                  Text('本学期成绩尚未发布')
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                  Text('期末考试结束两周后可查询')
                    .fontSize(11)
                    .fontColor($r('app.color.text_tertiary'))
                    .margin({ top: 4 })
                }
                .width('97%')
                .backgroundColor($r('app.color.bg_card'))
                .borderRadius(18)
                .padding({ top: 22, bottom: 22 })
              }
              .width('100%')
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.Spring)
            .align(Alignment.Start)
          }
          .width('100%')
          .height('100%')
          .onRefreshing(() => { this.onRefresh(); })
        }
        } else {
          this.scoreLandscape()
        }
      } else {
      // 成绩详情弹层挂在内层容器，与外层"选择学期"弹层分离（ArkUI 同组件多 bindSheet 只有最后一个生效）
      // 横屏/平板下内容限宽 720vp 并居中（一多适配）
      Column() {
        if (this.loading && !this.refreshing) {
          LoadingTip()
        } else {
          Row() {
            Refresh({ refreshing: $$this.refreshing }) {
            Scroll() {
              Column() {
                // 顶栏占位（随内容滚走）：内容初始位于悬浮渐变标题栏下方，上滑后进入其下层
                Column()
                  .width('100%')
                  .height(px2vp(this.topInsetPx) + 84)
                if (this.currentTermScore() === null || this.currentTermScore()!.items.length === 0) {
                  Column() {
                    EmptyTip({ text: '本学期成绩尚未发布\n期末考试结束两周后可查询' })
                }
                .width('100%')
                .backgroundColor($r('app.color.bg_card'))
                .borderRadius(18)
              } else {
                this.statsCard()
                Row() {
                  Text(`共 ${this.currentTermScore()!.items.length} 门`)
                    .fontSize(16)
                    .fontWeight(FontWeight.Bold)
                    .fontColor($r('app.color.text_primary'))
                  Blank()
                  Text(this.sortByScore ? '按绩点排序 ⇅' : '默认排序 ⇅')
                    .fontSize(12)
                    .fontColor(Theme.colorOf(this.themeColor))
                    .onClick(() => {
                      this.sortByScore = !this.sortByScore;
                    })
                }
                .width('100%')
                .margin({ top: 4, bottom: 6 })

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
                .backgroundColor($r('app.color.bg_card'))
                .borderRadius(18)

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
            .align(Alignment.Start)
            .edgeEffect(EdgeEffect.Spring)
            // 壁纸功能：列表滚动层背景透明，透出主框架底层的全局壁纸
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
      .bindSheet($$this.showSheet, this.detailSheet(), {
        width: SheetUtil.sheetWidth(),
        preferType: SheetType.BOTTOM,
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        backgroundColor: $r('app.color.bg_card'),
        title: { title: '成绩详情' }
      })
    }
    }
    .width('100%')
    .height('100%')
    // 壁纸功能：页面根背景透明，让主框架底层的全局壁纸透出（无壁纸时由 MainView 底层 bg_page 兜底）
    .backgroundColor(Color.Transparent)
    .bindSheet($$this.showTermSheet, this.termPickerSheet(), {
      width: SheetUtil.sheetWidth(),
      preferType: SheetType.BOTTOM,
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      backgroundColor: $r('app.color.bg_card'),
      title: { title: '选择学年-学期' }
    })

      AntiPeepOverlay({ isPeeped: this.isPeeped })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  scoreLandscape() {
    Column() {
      // 横屏：平均分栏宽度收窄 5%（Column 默认水平居中 → 左右各留 2.5%），并给顶栏让位
      Column() {
        this.statsCard()
      }
      .width('97%')
      .margin({ top: px2vp(this.topInsetPx) + 84 })
      Row() {
          // 左列
          Refresh({ refreshing: $$this.refreshing }) {
            Scroll() {
              Column() {
                this.scoreListColumn(this.sortedItems().filter((_item: ScoreItem, i: number) => i % 2 === 0))
              }
              .width('100%')
              .padding({ left: 16, right: 8, top: 14, bottom: 100 })
            }
            .layoutWeight(1)
            .height('100%')
            .scrollBar(BarState.Off)
            .align(Alignment.Start)
            .edgeEffect(EdgeEffect.Spring)
            .bindSheet($$this.showSheet, this.detailSheet(), {
              width: SheetUtil.sheetWidth(),
              preferType: SheetType.BOTTOM,
              height: SheetSize.FIT_CONTENT,
              dragBar: true,
              backgroundColor: $r('app.color.bg_card'),
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
              .padding({ left: 8, right: 16, top: 14, bottom: 100 })
            }
            .layoutWeight(1)
            .height('100%')
            .scrollBar(BarState.Off)
            .align(Alignment.Start)
            .edgeEffect(EdgeEffect.Spring)
          }
          .layoutWeight(1)
          .height('100%')
          .onRefreshing(() => { this.onRefresh(); })
        }
        .layoutWeight(1)
        .align(Alignment.Start)
      }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Start)
  }

  @Builder
  scoreListColumn(items: ScoreItem[]) {
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
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius(18)
  }

  @Builder
  webSheet() {
    WebSurface()
  }
}
