/**
 * 灰字高级调整（二级页）—— 从「外观设置 → 灰体文本显示增强 → 高级调整」进入。
 *
 * 设计（2026-09-24 用户需求第二轮修订）：
 *  - **直接展示各个页面的完整界面预览**（不是一小段示意文本）：每页一个缩略界面
 *    （顶栏 + 各卡片/列表行），页面里的灰字按当前设置实时渲染 —— 预览所见即实际所得；
 *  - **点击预览里的一段文字即可单独设置那一段**：点哪段文本就设置它所属的「文本角色」
 *    （次要文字 / 辅助文字），粒度 = 每页 × 角色；也可切到「整页」统一设置该页所有灰字；
 *  - 半模态面板：范围切换（整页 / 次要文字 / 辅助文字）+ 预置色（**点击即时生效**）
 *    + hex 输入 + 清除/应用；
 *  - 解析优先级由 GlassMaterial 统一实现：角色 → 整页 → 全局灰字模式。
 */
import { AppState } from '../common/AppState';
import { Theme } from '../common/ThemeUtil';
import { AppearanceStore } from '../common/AppearanceStore';
import { GlassMaterial } from '../common/GlassMaterial';
import { SheetUtil } from '../common/SheetUtil';
import { materialAvailable, sheetBlurStyle } from '../common/SystemMaterial';
import { GRAY_ADV_PAGES, GRAY_ADV_COLORS, GrayAdvPage } from '../common/GrayAdvMeta';
import { MaterialCardLayer } from './common/MaterialCarrier';
import { MaterialButton } from './common/MaterialButton';
import { PageHeader } from './common/UiKit';
import { WallpaperFill } from './common/WallpaperFill';

/** 预览界面的一个内容块（卡片/列表行）：title=主文字（不受灰字设置影响），secondary=次要文字，meta=辅助文字 */
interface MockBlock {
  title: string;
  secondary: string;
  meta: string[];
}

/** 一个页面的完整界面预览数据 */
interface MockPage {
  key: string;
  /** 顶栏标题（主文字） */
  barTitle: string;
  /** 顶栏右侧辅助文字（辅助角色，可点） */
  barMeta: string;
  blocks: MockBlock[];
}

/** 编辑范围：整页 / 次要文字 / 辅助文字 */
const SCOPE_PAGE: string = 'page';

/** 各页面的完整界面预览（按真实页面结构缩略：顶栏 + 卡片/列表行） */
const MOCK_PAGES: MockPage[] = [
  {
    key: 'home', barTitle: '首页', barMeta: '第 3 周',
    blocks: [
      { title: '高等数学（下）', secondary: '第 1-2 节 · 新教学楼 A201', meta: ['08:00 - 09:40 · 张老师'] },
      { title: '关于 2026 年国庆节放假安排的通知', secondary: '教务处', meta: ['2026-09-20 · 通知公告'] },
      { title: '快捷入口', secondary: '课表 · 成绩 · 考试', meta: ['空教室查询 · 学期校历'] }
    ]
  },
  {
    key: 'schedule', barTitle: '课程表', barMeta: '第 3 周',
    blocks: [
      { title: '周一 · 高等数学', secondary: '第 1-2 节 · A201', meta: ['张老师 · 1-16 周'] },
      { title: '周三 · 大学英语', secondary: '第 3-4 节 · B305', meta: ['李老师 · 1-16 周'] },
      { title: '周五 · 大学物理', secondary: '第 5-6 节 · C108', meta: ['王老师 · 1-8 周'] }
    ]
  },
  {
    key: 'score', barTitle: '成绩查询', barMeta: '2025-2026 学年 第二学期',
    blocks: [
      { title: '绩点 3.62 · 平均分 86.4', secondary: '已修学分 62.0', meta: ['专业排名 12 / 58 · 无挂科'] },
      { title: '高等数学（下）', secondary: '92 · 绩点 4.0', meta: ['4.0 学分 · 必修'] },
      { title: '大学英语（四）', secondary: '81 · 绩点 3.0', meta: ['3.0 学分 · 必修'] }
    ]
  },
  {
    key: 'exam', barTitle: '考试安排', barMeta: '2025-2026 学年',
    blocks: [
      { title: '高等数学（下）', secondary: '2026-11-12 09:00', meta: ['新教学楼 A201 · 座位 18'] },
      { title: '大学物理', secondary: '2026-11-18 15:30', meta: ['新教学楼 B305 · 座位 22'] }
    ]
  },
  {
    key: 'news', barTitle: '校园资讯', barMeta: '已收藏 3 篇',
    blocks: [
      { title: '学校召开新学期教学工作会议', secondary: '校园动态', meta: ['2026-09-22 · 阅读 320'] },
      { title: '我校学子在国家级竞赛中获奖', secondary: '学生风采', meta: ['2026-09-20 · 阅读 188'] }
    ]
  },
  {
    key: 'notice', barTitle: '通知公告', barMeta: '共 26 条',
    blocks: [
      { title: '关于 2026 年国庆节放假安排的通知', secondary: '教务处', meta: ['2026-09-20'] },
      { title: '关于开展本学期期中教学检查的通知', secondary: '教学质量科', meta: ['2026-09-18'] }
    ]
  },
  {
    key: 'kxjs', barTitle: '空教室', barMeta: '第 3 周 周一',
    blocks: [
      { title: '查询条件', secondary: '第 3 周 周一 · 第 1-2 节', meta: ['新教学楼 · 可容纳 60 人'] },
      { title: 'A201', secondary: '空闲 · 座位 60', meta: ['多媒体 · 新教学楼 2 层'] },
      { title: 'B305', secondary: '空闲 · 座位 45', meta: ['无多媒体 · 新教学楼 3 层'] }
    ]
  },
  {
    key: 'mine', barTitle: '我的', barMeta: '已同步',
    blocks: [
      { title: '示例同学', secondary: '示例班级 2301 班', meta: ['学号 2023XXXXXXX'] },
      { title: '网页端教务系统', secondary: '服务大厅 · 智慧学工', meta: ['上次同步 2026-09-24 18:20'] },
      { title: '外观设置', secondary: '主题色 · 壁纸 · 字体', meta: ['沉浸光感 · 灰体文本'] }
    ]
  }
];

@Component
export struct GrayAdvancedPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('immersiveEffect') immersiveEffect: boolean = false;
  @StorageProp('cardTint') cardTint: boolean = false;
  /** 全局字重订阅（表达式读 this.fwMode 才登记依赖） */
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  /** 灰字广播依赖登记：外部改色（外观设置页）/ 本页改色都经 grayTick 触发整页重算 */
  @StorageProp('grayTick') grayTick: number = 0;
  /** 本页改色后的本地刷新计数（预览界面用静态 API 取色，需本地依赖登记才重绘） */
  @State localTick: number = 0;

  /** 半模态面板开关 */
  @State sheetOpen: boolean = false;
  /** 当前编辑的页面 key */
  @State editPageKey: string = 'home';
  /** 当前编辑范围：'page' | 'secondary' | 'tertiary' */
  @State editScope: string = SCOPE_PAGE;
  /** hex 输入草稿 */
  @State draft: string = '';

  aboutToAppear(): void {
    // 首屏：默认选中第一个页面的整页范围
    this.editPageKey = MOCK_PAGES[0].key;
    this.syncDraft();
  }

  // ── 数据读写 ──

  /** 把草稿同步为「当前页面 + 当前范围」已设置的色 */
  private syncDraft(): void {
    this.draft = this.colorOfScope(this.editPageKey, this.editScope);
  }

  /** 读取某页某范围已设置的色（rrggbb；整页范围读整页键，角色范围读角色键） */
  private colorOfScope(pageKey: string, scope: string): string {
    return scope === SCOPE_PAGE
      ? GlassMaterial.grayPageColor(pageKey)
      : GlassMaterial.grayRoleColor(pageKey, scope);
  }

  /** 某页是否已有任何单独设置（整页或角色） */
  private pageTouched(pageKey: string): boolean {
    return this.colorOfScope(pageKey, SCOPE_PAGE) !== ''
      || this.colorOfScope(pageKey, GlassMaterial.GRAY_ROLE_SECONDARY) !== ''
      || this.colorOfScope(pageKey, GlassMaterial.GRAY_ROLE_TERTIARY) !== '';
  }

  /** 页面显示名 */
  private pageName(pageKey: string): string {
    for (let i: number = 0; i < GRAY_ADV_PAGES.length; i++) {
      const p: GrayAdvPage = GRAY_ADV_PAGES[i];
      if (p.key === pageKey) {
        return p.name;
      }
    }
    return pageKey;
  }

  /** 范围显示名 */
  private scopeName(scope: string): string {
    if (scope === SCOPE_PAGE) {
      return '整页灰字';
    }
    return scope === GlassMaterial.GRAY_ROLE_SECONDARY ? '次要文字' : '辅助文字';
  }

  /** 打开面板：pageKey + 点击的文本角色（scope='page' 表示整页按钮） */
  private openAdjust(pageKey: string, scope: string): void {
    this.editPageKey = pageKey;
    this.editScope = scope;
    this.syncDraft();
    this.sheetOpen = true;
  }

  /** 切换编辑范围（面板内胶囊） */
  private switchScope(scope: string): void {
    this.editScope = scope;
    this.syncDraft();
  }

  /** 应用颜色到「当前页面 + 当前范围」：持久化 + 广播 + 预览即时刷新 */
  private applyColor(raw: string): void {
    const v: string = raw.trim();
    const hex: string = v.startsWith('#') ? v.substring(1) : v;
    if (hex.length < 6) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入 6 位十六进制颜色（如 9AA0A6）' });
      return;
    }
    const key: string = this.editScope === SCOPE_PAGE
      ? this.editPageKey
      : GlassMaterial.grayKeyOf(this.editPageKey, this.editScope);
    GlassMaterial.setGrayPageColor(key, hex);
    this.draft = hex;
    this.localTick++;
    this.getUIContext().getPromptAction().showToast({
      message: `已应用到「${this.pageName(this.editPageKey)} · ${this.scopeName(this.editScope)}」`
    });
  }

  /** 清除当前范围的单独色（回落上一级：角色 → 整页 → 全局） */
  private clearColor(): void {
    const key: string = this.editScope === SCOPE_PAGE
      ? this.editPageKey
      : GlassMaterial.grayKeyOf(this.editPageKey, this.editScope);
    GlassMaterial.setGrayPageColor(key, '');
    this.draft = '';
    this.localTick++;
    this.getUIContext().getPromptAction().showToast({
      message: `已清除「${this.pageName(this.editPageKey)} · ${this.scopeName(this.editScope)}」`
    });
  }

  // ── 视觉工具（与外观设置页同款：材质受全局沉浸光感开关控制） ──

  private matOn(): boolean {
    return this.immersiveEffect && materialAvailable();
  }

  private tintLayer(): string {
    if (!this.cardTint || !this.matOn()) {
      return '';
    }
    return AppearanceStore.cardTintLayer(this.themeColor);
  }

  private cardBg(orig: ResourceColor): ResourceColor {
    if (this.matOn()) {
      return Color.Transparent;
    }
    return this.cardTint ? AppearanceStore.cardBackground(this.isDarkMode, this.themeColor) : orig;
  }

  @Builder
  tintOverlayLayer() {
    if (this.tintLayer().length > 0) {
      Column()
        .width(LayoutPolicy.matchParent)
        .height(LayoutPolicy.matchParent)
        .borderRadius(16)
        .backgroundColor(this.tintLayer())
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
    }
  }

  // ── 预览界面（完整页面缩略） ──

  /** 可点的灰字（次要/辅助角色）：点它即设置该角色颜色（虚下划线提示可点）。
   *  注意：@Builder 调用后不能链式加属性（同自定义组件规则），故上边距做参数传入。 */
  @Builder
  mockGrayText(pageKey: string, role: string, text: string, size: number, topMargin: number) {
    Text(text)
      .fontSize(size)
      .fontColor(GlassMaterial.grayTextFor(pageKey, role, this.defaultColorOf(role)))
      .decoration({
        type: TextDecorationType.Underline,
        color: this.matOn() ? '#40FFFFFF' : '#33000000',
        style: TextDecorationStyle.DASHED
      })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      .margin({ top: topMargin })
      .onClick(() => {
        this.openAdjust(pageKey, role);
      })
  }

  /** 角色默认色（预览里未被覆盖时的原色） */
  private defaultColorOf(role: string): ResourceColor {
    return role === GlassMaterial.GRAY_ROLE_SECONDARY
      ? $r('app.color.text_secondary')
      : $r('app.color.text_tertiary');
  }

  /** 一个页面的完整界面预览 */
  @Builder
  mockScreen(p: MockPage) {
    Column() {
      // 缩略顶栏：页面标题（主文字）+ 右侧辅助文字（辅助角色，可点）
      Row() {
        Text(p.barTitle)
          .fontSize(13)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontColor(Color.White)
        Blank()
        Text(p.barMeta)
          .fontSize(10)
          .fontColor(GlassMaterial.grayTextFor(p.key, GlassMaterial.GRAY_ROLE_TERTIARY, Color.White))
          .decoration({
            type: TextDecorationType.Underline,
            color: '#40FFFFFF',
            style: TextDecorationStyle.DASHED
          })
          .maxLines(1)
          .onClick(() => {
            this.openAdjust(p.key, GlassMaterial.GRAY_ROLE_TERTIARY);
          })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .linearGradient({ angle: 180, colors: Theme.barGradient(this.themeColor, 'new') })

      // 内容区：每个块 = 一张卡片（主标题 + 次要行 + 辅助行）
      Column() {
        ForEach(p.blocks, (b: MockBlock) => {
          Column() {
            Text(b.title)
              .fontSize(12)
              .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
              .fontColor($r('app.color.text_primary'))
              .width('100%')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            this.mockGrayText(p.key, GlassMaterial.GRAY_ROLE_SECONDARY, b.secondary, 10, 3)
            ForEach(b.meta, (m: string) => {
              this.mockGrayText(p.key, GlassMaterial.GRAY_ROLE_TERTIARY, m, 9, 3)
            }, (m: string) => m)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding(10)
          .borderRadius(10)
          .backgroundColor(this.matOn() ? '#14FFFFFF' : $r('app.color.bg_chip'))
          .margin({ bottom: 8 })
        }, (b: MockBlock) => b.title)
      }
      .width('100%')
      .padding(10)
    }
    .width('100%')
    .borderRadius(14)
    .clip(true)
    .backgroundColor(this.matOn() ? '#0AFFFFFF' : $r('app.color.bg_page'))
    .border({ width: 1, color: this.matOn() ? '#26FFFFFF' : $r('app.color.divider') })
  }

  /** 单个页面区块：标题行（右上角「整页」按钮）+ 完整界面预览 */
  @Builder
  pageSection(p: MockPage) {
    Column() {
      Row() {
        Text(this.pageName(p.key))
          .fontSize(14)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontColor($r('app.color.text_primary'))
        if (this.pageTouched(p.key)) {
          Text('已设置')
            .fontSize(10)
            .fontColor(Theme.colorOf(this.themeColor))
            .margin({ left: 6 })
        }
        Blank()
        // 右上角：整页调整
        MaterialButton({
          btnRadius: 14,
          btnBg: $r('app.color.bg_chip'),
          btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
          btnBorderW: GlassMaterial.borderWidth(),
          btnBorderC: GlassMaterial.borderColor(),
          btnTint: '',
          btnTintRatio: 0,
          btnOnClick: (): void => {
            this.openAdjust(p.key, SCOPE_PAGE);
          }
        }) {
          Text('整页调整')
            .fontSize(11)
            .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor(Theme.colorOf(this.themeColor))
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
        }
      }
      .width('100%')
      .margin({ bottom: 8 })

      this.mockScreen(p)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 16 })
  }

  // ── 半模态调整面板 ──

  @Builder
  adjustSheet() {
    Column() {
      Row() {
        Text(`调整「${this.pageName(this.editPageKey)}」`)
          .fontSize(16)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('✕')
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .padding(6)
          .onClick(() => {
            this.sheetOpen = false;
          })
      }
      .width('100%')

      Text('点预览界面里的灰字可直接设置该段文字所属角色；下方可切换范围并选色（点击色块即时生效）。')
        .fontSize(11)
        .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
        .width('100%')
        .margin({ top: 4 })

      // 范围切换：整页 / 次要文字 / 辅助文字
      Row({ space: 8 }) {
        this.scopeChip('整页灰字', SCOPE_PAGE)
        this.scopeChip('次要文字', GlassMaterial.GRAY_ROLE_SECONDARY)
        this.scopeChip('辅助文字', GlassMaterial.GRAY_ROLE_TERTIARY)
      }
      .width('100%')
      .margin({ top: 12 })

      // 预置色块：点击即应用（实时生效）
      Row({ space: 10 }) {
        ForEach(GRAY_ADV_COLORS, (c: string) => {
          Column()
            .width(30)
            .height(30)
            .borderRadius(15)
            .backgroundColor(`#${c}`)
            .border({
              width: this.colorOfScope(this.editPageKey, this.editScope).toLowerCase() === c.toLowerCase() ? 2.5 : 1,
              color: this.colorOfScope(this.editPageKey, this.editScope).toLowerCase() === c.toLowerCase()
                ? Theme.colorOf(this.themeColor) : GlassMaterial.borderColor()
            })
            .onClick(() => {
              this.applyColor(c);
            })
        }, (c: string) => c)
      }
      .width('100%')
      .margin({ top: 12 })

      // 自定义 hex（材质承载层与输入框做兄弟 Stack）
      Row() {
        Stack({ alignContent: Alignment.TopStart }) {
          if (this.matOn()) {
            MaterialCardLayer({ layerRadius: $r('sys.float.corner_radius_level12'), layerShadow: false })
          }
          TextInput({ text: this.draft, placeholder: 'RRGGBB（如 9AA0A6）' })
            .height(48)
            .enterKeyType(EnterKeyType.Done)
            .borderRadius($r('sys.float.corner_radius_level12'))
            .fontSize($r('sys.float.Body_L'))
            .fontWeight(this.fwMode === 'follow' ? FontWeight.Regular : AppearanceStore.fontWeight(FontWeight.Regular))
            .backgroundColor(this.matOn() ? Color.Transparent : $r('sys.color.comp_background_tertiary'))
            .caretStyle({ color: $r('sys.color.font_emphasize') })
            .type(InputType.Normal)
            .fontColor('rgba(0, 85, 255, 1.0)')
            .placeholderFont({ size: $r('sys.float.Body_L'), weight: FontWeight.Regular })
            .width('100%')
            .onChange((v: string) => {
              this.draft = v;
            })
            .onSubmit(() => {
              this.applyColor(this.draft);
            })
        }
        .layoutWeight(1)
        MaterialButton({
          btnRadius: 18,
          btnBg: $r('app.color.bg_chip'),
          btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
          btnBorderW: GlassMaterial.borderWidth(),
          btnBorderC: GlassMaterial.borderColor(),
          btnTint: '',
          btnTintRatio: 0,
          btnMargin: { top: 0, right: 0, bottom: 0, left: 8 },
          btnOnClick: (): void => {
            this.clearColor();
          }
        }) {
          Text('清除')
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        }
        MaterialButton({
          btnRadius: 18,
          btnBg: Theme.colorOf(this.themeColor),
          btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
          btnBorderW: GlassMaterial.borderWidth(),
          btnBorderC: GlassMaterial.borderColor(),
          btnTint: Theme.colorOf(this.themeColor),
          btnTintRatio: 0.55,
          btnMargin: { top: 0, right: 0, bottom: 0, left: 8 },
          btnOnClick: (): void => {
            this.applyColor(this.draft);
          }
        }) {
          Text('应用')
            .fontSize(13)
            .fontColor(Color.White)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
        }
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 24 })
  }

  /** 面板内的范围胶囊 */
  @Builder
  scopeChip(label: string, scope: string) {
    MaterialButton({
      btnRadius: 12,
      btnBg: this.editScope === scope ? Theme.colorOf(this.themeColor) : $r('app.color.bg_chip'),
      btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
      btnBorderW: GlassMaterial.borderWidth(),
      btnBorderC: GlassMaterial.borderColor(),
      btnTint: this.editScope === scope ? Theme.colorOf(this.themeColor) : '',
      btnTintRatio: 0.85,
      btnOnClick: (): void => {
        this.switchScope(scope);
      }
    }) {
      Text(label)
        .fontSize(12)
        .fontColor(this.editScope === scope ? Color.White : $r('app.color.text_primary'))
        .padding({ left: 12, right: 12, top: 5, bottom: 5 })
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        WallpaperFill()

        Column() {
          Scroll() {
            Column() {
              // 悬浮顶栏让位
              Column().width('100%').height(this.getUIContext().px2vp(this.topInsetPx) + 60)

              Text('点下方任意预览界面里的灰字（带虚下划线）即可单独设置那一段文字的颜色；每页右上角可按整页统一设置。')
                .fontSize(11)
                .lineHeight(17)
                .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
                .width('100%')
                .padding({ left: 4, right: 4 })

              ForEach(MOCK_PAGES, (p: MockPage) => {
                this.pageSection(p)
              }, (p: MockPage) => p.key)

              Column().width('100%').height(this.getUIContext().px2vp(this.topInsetPx) + 40)
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')

        PageHeader({
          title: '灰字高级调整',
          subtitle: '点预览中的文字单独设色',
          onBack: () => {
            AppState.stack.pop();
          }
        })
      }
      .width('100%')
      .height('100%')
      // 灰字广播依赖登记（外部改色）+ 本页改色后的本地刷新（恒真，不改变视觉）
      .opacity((this.grayTick >= 0 && this.localTick >= 0) ? 1 : 1)
    }
    .hideTitleBar(true)
    .bindSheet($$this.sheetOpen, this.adjustSheet(), {
      width: SheetUtil.sheetWidth(),
      preferType: SheetType.BOTTOM,
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      showClose: false,
      backgroundColor: Color.Transparent,
      blurStyle: sheetBlurStyle(),
      onDisappear: () => {
        this.sheetOpen = false;
      }
    })
  }
}
