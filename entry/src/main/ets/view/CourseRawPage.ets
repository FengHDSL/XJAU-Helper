/**
 * 课表原文件页
 * - 课表预览：由当前课表数据渲染的网页（含周六/周日与自定义作息）
 * - 原始识别文件：教务系统课表接口的原始响应体（JSON）全文预览与复制
 * 入口：课程表页底部「课表原文件」
 * 注：曾提供「输出PDF」，经设备验证 ArkWeb 导出不可用，已移除该功能。
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { AppState } from '../common/AppState';
import { CourseRawStore, CourseRawMeta } from '../common/CourseRawStore';
import { CourseItem } from '../model/Models';
import { JwApi } from '../api/JwApi';
import { Theme } from '../common/ThemeUtil';
import { GlassMaterial } from '../common/GlassMaterial';
import { PageHeader } from './common/UiKit';
import { WallpaperFill } from './common/WallpaperFill';
// 沉浸光感：卡片统一走 MaterialCard，胶囊小按钮走 MaterialButton（含「材质 + 原色」共存的 btnTint）
import { MaterialCard } from './common/MaterialCard';
import { MaterialButton } from './common/MaterialButton';
import { AppearanceStore } from '../common/AppearanceStore';

/** JSON 原文预览最多显示的字符数（完整内容可复制） */
const PREVIEW_MAX: number = 20000;

@Component
export struct CourseRawPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  /** 全局字重响应式订阅：表达式读 this.fwMode 才登记依赖，fwValue 声明即订阅 */
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  /** 响应式依赖：玻璃/灰字设置变化时触发本页重渲染（取值经 GlassMaterial 静态方法读取） */
  @StorageProp('glassStrength') glassStrength: number = 70;
  @StorageProp('cardMaterial') cardMaterial: boolean = false;
  @StorageProp('grayTextMode') grayTextMode: string = 'default';
  @StorageProp('grayTextColor') grayTextColor: string = '';
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  /** 沉浸光感开关（登记依赖：拨动后小按钮的玻璃底/材质即时重渲染） */
  @StorageProp('immersiveEffect') immersiveEffect: boolean = false;
  /** JSON 原文件是否存在 */
  @State hasFile: boolean = false;
  /** JSON 原文（已按 PREVIEW_MAX 截断） */
  @State preview: string = '';
  @State truncated: boolean = false;
  @State metaTime: string = '';
  @State metaUrl: string = '';
  @State metaCount: number = 0;
  @State metaSize: string = '';
  /** 识别结果概览：按周一到周日统计条数（含周末） */
  @State weekdaySummary: string = '';
  @State fetching: boolean = false;

  aboutToAppear(): void {
    this.loadFile();
    this.loadSummary();
  }

  /** 读取 JSON 原文件与元信息 */
  private loadFile(): void {
    const termId: string = AppState.term.id;
    const full: string = CourseRawStore.read(termId);
    this.hasFile = full.length > 0;
    this.truncated = full.length > PREVIEW_MAX;
    this.preview = this.truncated ? full.substring(0, PREVIEW_MAX) : full;
    const m: CourseRawMeta | null = CourseRawStore.meta(termId);
    this.metaTime = m !== null ? m.time : '';
    this.metaUrl = m !== null ? m.url : '';
    this.metaCount = m !== null ? m.count : 0;
    this.metaSize = m !== null && m.bytes > 0 ? CourseRawPage.sizeText(m.bytes) : '';
  }

  /** 统计已识别课程的星期分布（1=周一 … 7=周日） */
  private loadSummary(): void {
    const list: CourseItem[] = JwApi.loadCachedCourses();
    const names: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    const parts: string[] = [];
    for (let d: number = 1; d <= 7; d++) {
      let n: number = 0;
      for (const c of list) {
        if (c.weekday === d) {
          n++;
        }
      }
      parts.push(`${names[d - 1]} ${n}`);
    }
    this.weekdaySummary = list.length > 0 ? parts.join(' · ') : '';
  }

  /** 字节数 → 可读大小 */
  private static sizeText(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes} B`;
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)} KB`;
    }
    return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
  }

  /** 重新获取：强制重新查询识别课表，并刷新 JSON 原文与预览 */
  private async refetch(): Promise<void> {
    if (this.fetching) {
      return;
    }
    this.fetching = true;
    try {
      await JwApi.getCoursesSmart(AppState.term.id, true);
      this.loadFile();
      this.loadSummary();
      this.getUIContext().getPromptAction().showToast({ message: '已重新获取课表数据' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '获取失败，请检查网络后重试' });
    } finally {
      this.fetching = false;
    }
  }

  /** 复制 JSON 原文到剪贴板 */
  private copyAll(): void {
    const full: string = CourseRawStore.read(AppState.term.id);
    if (full.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '暂无文件内容' });
      return;
    }
    pasteboard.getSystemPasteboard().setDataSync(pasteboard.createPlainTextData(full));
    this.getUIContext().getPromptAction().showToast({ message: '已复制原文件全部内容' });
  }

  /** 元信息行 */
  @Builder
  metaRow(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .width(66)
      Text(value.length > 0 ? value : '—')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: 4 })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        WallpaperFill()

        Scroll() {
          Column() {
            // 顶栏占位（随内容滚走；额外留 12vp 避免首卡贴住悬浮顶栏）
            Column()
              .width('100%')
              .height(this.getUIContext().px2vp(this.topInsetPx) + 72)

            // 元信息 + 操作（MaterialCard 承载：原 16vp 内边距挂内部内容容器，承载层才能铺满整块卡片；
            // 16vp 圆角走 cardRadius；12vp 下间距走 cardMargin；材质生效时卡片底色/磨砂/亮边/阴影一并让出）
            MaterialCard({
              cardRadius: 16,
              cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
              cardBlur: GlassMaterial.cardBlur(),
              cardBorderW: GlassMaterial.cardBorderWidth(),
              cardBorderC: GlassMaterial.borderColor(),
              cardShadow: GlassMaterial.cardShadowStyle(),
              cardMargin: { bottom: 12 }
            }) {
            Column() {
              this.metaRow('学期', AppState.term.label)
              this.metaRow('抓取时间', this.metaTime)
              this.metaRow('课程条数', this.metaCount > 0 ? `${this.metaCount} 条` : '')
              this.metaRow('识别结果', this.weekdaySummary)
              this.metaRow('文件大小', this.metaSize)
              this.metaRow('来源接口', this.metaUrl)

              Row() {
                // 「重新获取」原来是主题色实底 + 白字：材质生效时靠 btnTint 叠回主题色（比例 0.85，
                // 因白字需要足够对比度）——材质照常可见、按钮配色也保留；光感关闭时回落 btnBg 原实底。
                MaterialButton({
                  btnRadius: 12,
                  btnBg: Theme.colorOf(this.themeColor),
                  btnTint: Theme.colorOf(this.themeColor),
                  btnTintRatio: 0.85,
                  btnOnClick: () => {
                    this.refetch();
                  }
                }) {
                  Text(this.fetching ? '获取中…' : '重新获取')
                    .fontSize(12)
                    .fontColor(Color.White)
                    .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                }
                // 「复制原文」原有的淡灰玻璃底：材质走 MaterialButton 的 Toggle 承载层，
                // 光感关闭时回落 bg_chip + 亮边 + 微阴影（原自绘玻璃写法）。
                MaterialButton({
                  btnRadius: 12,
                  btnMargin: { left: 10 },
                  btnBg: $r('app.color.bg_chip'),
                  btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
                  btnBorderW: GlassMaterial.borderWidth(),
                  btnBorderC: GlassMaterial.borderColor(),
                  btnOnClick: () => {
                    this.copyAll();
                  }
                }) {
                  Text('复制原文')
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                }
              }
              .width('100%')
              .margin({ top: 10 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(16)
            }

            // 课表预览卡片已移除（无数据时会出现空白卡片，且原文件页重点在"原始识别文件"）

            // 原始识别文件（教务系统接口原文）
            if (this.hasFile) {
              // MaterialCard 承载：原 12vp 内边距挂内部内容容器；16vp 圆角走 cardRadius。
              MaterialCard({
                cardRadius: 16,
                cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
                cardBlur: GlassMaterial.cardBlur(),
                cardBorderW: GlassMaterial.cardBorderWidth(),
                cardBorderC: GlassMaterial.borderColor(),
                cardShadow: GlassMaterial.cardShadowStyle()
              }) {
              Column() {
                Row() {
                  Text(this.truncated
                    ? `原始识别文件（仅预览前 ${PREVIEW_MAX} 字符）`
                    : '原始识别文件（教务系统接口原文）')
                    .fontSize(11)
                    .fontColor($r('app.color.text_tertiary'))
                    .layoutWeight(1)
                  // 「复制全文」淡灰玻璃底小胶囊：同上走 MaterialButton（光感关闭回落 bg_chip 玻璃底）
                  MaterialButton({
                    btnRadius: 9,
                    btnBg: $r('app.color.bg_chip'),
                    btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
                    btnBorderW: GlassMaterial.borderWidth(),
                    btnBorderC: GlassMaterial.borderColor(),
                    btnOnClick: () => {
                      this.copyAll();
                    }
                  }) {
                    Text('复制全文')
                      .fontSize(11)
                      .fontColor(Theme.colorOf(this.themeColor))
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  }
                }
                .width('100%')
                .margin({ bottom: 8 })

                Text(this.preview)
                  .fontSize(10)
                  .fontColor($r('app.color.text_secondary'))
                  .lineHeight(15)
                  .width('100%')
                  .textSelectable(TextSelectableMode.SELECTABLE_UNFOCUSABLE)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(12)
              }
            } else {
              // MaterialCard 承载：原 16vp 内边距挂内部内容容器；16vp 圆角走 cardRadius。
              MaterialCard({
                cardRadius: 16,
                cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
                cardBlur: GlassMaterial.cardBlur(),
                cardBorderW: GlassMaterial.cardBorderWidth(),
                cardBorderC: GlassMaterial.borderColor(),
                cardShadow: GlassMaterial.cardShadowStyle()
              }) {
              Column() {
                Text('暂无课表原文件')
                  .fontSize(13)
                  .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
                  .fontColor($r('app.color.text_primary'))
                Text('原文件在每次成功拉取课表时生成。点上方「重新获取」，或回到课程表页点标题旁的刷新按钮即可生成。')
                  .fontSize(12)
                  .lineHeight(18)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ top: 6 })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(16)
              }
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 40 + this.getUIContext().px2vp(this.bottomInsetPx) })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        PageHeader({
          title: '课表原文件',
          onBack: () => {
            AppState.stack.pop();
          }
        })
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.bg_page'))
    .hideTitleBar(true)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    .width('100%')
    .height('100%')
  }
}
