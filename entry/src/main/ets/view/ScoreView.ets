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
import { WebSurface } from './WebSurface';
import { promptAction, mediaquery } from '@kit.ArkUI';

@Component
export struct ScoreView {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
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
  private landscapeListener: mediaquery.MediaQueryListener | null = null;

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
        .fontColor($r('app.color.brand'))
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
  }

  aboutToDisappear(): void {
    this.landscapeListener = null;
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
    this.termScores = [];
    await this.load();
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
    // 顶部标题栏：浅色=主题色（中国红/天空蓝/农大绿），深色=黑色；文字白色
    // 高度与其他主题色顶栏统一（topInset + 72vp 外高，内容区 48vp）
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
              .fontColor(this.isDarkMode ? $r('app.color.text_tertiary') : '#CCFFFFFF')
            Image($r('app.media.list_bullet'))
              .width(14)
              .height(14)
              .fillColor(this.isDarkMode ? $r('app.color.text_tertiary') : '#CCFFFFFF')
              .margin({ left: 3 })
          }
          .margin({ top: 4 })
          .onClick(() => {
            this.showTermSheet = true;
          })
        }
        .alignItems(HorizontalAlign.Start)

        Blank()
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(px2vp(this.topInsetPx) + 60)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 16, right: 16, bottom: 12, top: px2vp(this.topInsetPx) + 12 })
    .backgroundColor(this.isDarkMode ? '#1A1D1C' : Theme.colorOf(this.themeColor))
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

  build() {
    Column() {
      this.topBar()
      if (this.isLandscape) {
        if (this.loading) {
          LoadingTip()
        } else if (this.currentTermScore() === null || this.currentTermScore()!.items.length === 0) {
          // 横屏直接打开且数据未就绪/为空时必须兜底，否则 scoreLandscape→statsCard 的
          // currentTermScore()! 非空断言会空指针闪退（竖屏转横屏时数据已加载所以正常）
          Column() {
            EmptyTip({ text: '本学期成绩尚未发布\n期末考试结束两周后可查询' })
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(18)
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
                    .fontColor($r('app.color.brand'))
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
            .align(Alignment.Top)
            .edgeEffect(EdgeEffect.Spring)
            .backgroundColor($r('app.color.bg_page'))
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

  @Builder
  scoreLandscape() {
    Column() {
      // 横屏：平均分栏宽度收窄 5%（Column 默认水平居中 → 左右各留 2.5%），并给顶栏留一点间距
      Column() {
        this.statsCard()
      }
      .width('97%')
      .margin({ top: 20 })
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
            .align(Alignment.Top)
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
