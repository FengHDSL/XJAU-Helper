/**
 * 灰字高级调整（二级页）—— 从「外观设置 → 灰体文本显示增强」进入。
 *
 * 设计（2026-09-24 用户需求）：
 *  - 独立页面列出**全部含灰字的页面**（GRAY_ADV_PAGES），每行显示：页面名 + 当前单独色状态/色样
 *    + **右上角「调整」按钮**；
 *  - 点「调整」弹**半模态面板**，为该页面设置单独的次要/辅助文字颜色（预置色块 + hex 输入 + 清除/应用）；
 *  - **预置色点击即时生效**（不再需要二次确认），应用后列表与全站立刻刷新（GlassMaterial 广播 grayTick）；
 *  - 每页单独色优先于「外观设置」里的全局灰字模式生效。
 */
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
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
  /** 灰字广播依赖登记：广播时本页整体重算（列表色样 / 预览色跟随刷新） */
  @StorageProp(GlassMaterial.KEY_GRAY_TICK) grayTick: number = 0;

  /** 半模态面板开关 */
  @State sheetOpen: boolean = false;
  /** 当前正在调整的页面 key */
  @State editKey: string = 'home';
  /** hex 输入草稿（rrggbb，可带 #） */
  @State draft: string = '';
  /** 各页已设色缓存（key -> rrggbb）：静态 map 变更不触发重绘，用 @State 副本驱动列表刷新 */
  @State colors: Record<string, string> = {};

  aboutToAppear(): void {
    this.reloadColors();
  }

  /** 从 GlassMaterial 每页单独色 map 读回本页 @State 副本（列表即时刷新） */
  private reloadColors(): void {
    const m: Record<string, string> = {};
    for (let i: number = 0; i < GRAY_ADV_PAGES.length; i++) {
      const c: string = GlassMaterial.grayPageColor(GRAY_ADV_PAGES[i].key);
      if (c.length >= 6) {
        m[GRAY_ADV_PAGES[i].key] = c;
      }
    }
    this.colors = m;
  }

  /** 某页当前单独色（rrggbb；未设置为空串） */
  private colorOf(key: string): string {
    const c: string | undefined = this.colors[key];
    return c === undefined ? '' : c;
  }

  /** 某页状态文案 */
  private statusOf(key: string): string {
    const c: string = this.colorOf(key);
    return c.length >= 6 ? `已单独设置 #${c}` : '跟随全局灰字设置';
  }

  /** 某页显示名 */
  private nameOf(key: string): string {
    for (let i: number = 0; i < GRAY_ADV_PAGES.length; i++) {
      if (GRAY_ADV_PAGES[i].key === key) {
        return GRAY_ADV_PAGES[i].name;
      }
    }
    return key;
  }

  /** 面板预览色：草稿合法用草稿，否则用该页当前生效色（全局兜底） */
  private previewColor(): ResourceColor {
    const v: string = this.draft.trim();
    const hex: string = v.startsWith('#') ? v.substring(1) : v;
    if (hex.length >= 6) {
      return `#${hex}`;
    }
    return GlassMaterial.grayTertiary($r('app.color.text_tertiary'));
  }

  /** 打开某页的调整面板 */
  private openAdjust(key: string): void {
    this.editKey = key;
    this.draft = this.colorOf(key);
    this.sheetOpen = true;
  }

  /** 应用颜色（rrggbb，可带 #）：持久化 + 广播 + 刷新列表（预置色点击即时生效） */
  private applyColor(raw: string): void {
    const v: string = raw.trim();
    const hex: string = v.startsWith('#') ? v.substring(1) : v;
    if (hex.length < 6) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入 6 位十六进制颜色（如 9AA0A6）' });
      return;
    }
    GlassMaterial.setGrayPageColor(this.editKey, hex);
    this.draft = hex;
    this.reloadColors();
    this.getUIContext().getPromptAction().showToast({ message: `已应用到「${this.nameOf(this.editKey)}」` });
  }

  /** 清除该页单独色（回落全局灰字设置） */
  private clearColor(): void {
    GlassMaterial.setGrayPageColor(this.editKey, '');
    this.draft = '';
    this.reloadColors();
    this.getUIContext().getPromptAction().showToast({ message: `已清除「${this.nameOf(this.editKey)}」的单独设置` });
  }

  /** 本页手写卡材质是否生效（受全局沉浸光感开关控制） */
  private matOn(): boolean {
    return this.immersiveEffect && materialAvailable();
  }

  /** 手写卡沾色叠层色（空串=不铺；必须叠在材质之上，垫底会被玻璃滤镜压黑） */
  private tintLayer(): string {
    if (!this.cardTint || !this.matOn()) {
      return '';
    }
    return AppearanceStore.cardTintLayer(this.themeColor);
  }

  /** 手写卡底色：材质生效 → 透明让材质渲染；否则沾色底 / 原底色 */
  private cardBg(orig: ResourceColor): ResourceColor {
    if (this.matOn()) {
      return Color.Transparent;
    }
    return this.cardTint ? AppearanceStore.cardBackground(this.isDarkMode, this.themeColor) : orig;
  }

  /** 沾色叠层（压在材质承载层之上、内容之下） */
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

  /** 单个页面行：页面名 + 状态 + 色样 + 右上角「调整」按钮 */
  @Builder
  pageRow(p: GrayAdvPage) {
    Row() {
      Column() {
        Text(p.name)
          .fontSize(15)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Text(this.statusOf(p.key))
          .fontSize(11)
          .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
          .width('100%')
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 已设置时显示色样圆点
      if (this.colorOf(p.key).length >= 6) {
        Row()
          .width(20)
          .height(20)
          .borderRadius(10)
          .backgroundColor(`#${this.colorOf(p.key)}`)
          .border({ width: 1, color: GlassMaterial.borderColor() })
          .margin({ right: 10 })
          .hitTestBehavior(HitTestMode.None)
      }

      // 右上角：调整按钮
      MaterialButton({
        btnRadius: 14,
        btnBg: $r('app.color.bg_chip'),
        btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
        btnBorderW: GlassMaterial.borderWidth(),
        btnBorderC: GlassMaterial.borderColor(),
        btnTint: '',
        btnTintRatio: 0,
        btnOnClick: (): void => {
          this.openAdjust(p.key);
        }
      }) {
        Text('调整')
          .fontSize(12)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
          .fontColor(Theme.colorOf(this.themeColor))
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ top: 10, bottom: 10 })
  }

  /** 半模态调整面板：预置色（点击即时生效）+ hex 输入 + 清除/应用 + 实时预览 */
  @Builder
  adjustSheet() {
    Column() {
      Row() {
        Text(`调整「${this.nameOf(this.editKey)}」灰字颜色`)
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

      Text('该设置只作用于所选页面的次要/辅助灰字，优先于全局灰字模式；点击色块即时生效。')
        .fontSize(11)
        .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
        .width('100%')
        .margin({ top: 4 })

      // 预置色块：点击即应用（实时生效）
      Row({ space: 10 }) {
        ForEach(GRAY_ADV_COLORS, (c: string) => {
          Column()
            .width(30)
            .height(30)
            .borderRadius(15)
            .backgroundColor(`#${c}`)
            .border({
              width: this.colorOf(this.editKey).toLowerCase() === c.toLowerCase() ? 2.5 : 1,
              color: this.colorOf(this.editKey).toLowerCase() === c.toLowerCase()
                ? Theme.colorOf(this.themeColor) : GlassMaterial.borderColor()
            })
            .onClick(() => {
              this.applyColor(c);
            })
        }, (c: string) => c)
      }
      .width('100%')
      .margin({ top: 12 })

      // 自定义 hex：材质承载层与输入框做兄弟（Stack）
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

      // 实时预览（模拟数据：次要/辅助文字用当前生效色渲染）
      Column() {
        Text(`预览 · ${this.nameOf(this.editKey)}`)
          .fontSize(12)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontColor($r('app.color.text_primary'))
        Column() {
          Row() {
            Text('高等数学（下）')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Text('92 · 绩点 4.0')
              .fontSize(12)
              .fontColor(this.previewColor())
          }
          .width('100%')
          Text('第 1-4 节 · 新教学楼 A201')
            .fontSize(11)
            .fontColor(this.previewColor())
            .width('100%')
            .margin({ top: 4 })
          Text('教务处 · 2026-09-20')
            .fontSize(11)
            .fontColor(this.previewColor())
            .width('100%')
            .margin({ top: 10 })
        }
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor($r('app.color.bg_chip'))
        .margin({ top: 8 })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 14 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 24 })
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // 二级页壁纸底层（跟随全局壁纸）
        WallpaperFill()

        Column() {
          Scroll() {
            Column() {
              // 悬浮顶栏让位
              Column().width('100%').height(this.getUIContext().px2vp(this.topInsetPx) + 60)

              // 页面清单卡（手写 Stack 结构：材质承载层 + 沾色叠层 + 内容）
              Stack({ alignContent: Alignment.TopStart }) {
                if (this.matOn()) {
                  MaterialCardLayer({ layerRadius: 16, layerShadow: false })
                }
                this.tintOverlayLayer()
                Column() {
                  Text('灰字单独调整')
                    .fontSize(15)
                    .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
                    .fontColor($r('app.color.text_primary'))
                    .width('100%')
                  Text('为指定页面单独设置次要/辅助文字颜色，优先于全局灰字模式；点右侧「调整」选择颜色。')
                    .fontSize(11)
                    .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
                    .width('100%')
                    .margin({ top: 3 })

                  ForEach(GRAY_ADV_PAGES, (p: GrayAdvPage) => {
                    Divider()
                      .color($r('app.color.divider'))
                      .margin({ top: 2 })
                    this.pageRow(p)
                  }, (p: GrayAdvPage) => p.key)
                }
                .width('100%')
                .padding(16)
              }
              .width('100%')
              .borderRadius(16)
              .clip(true)
              .backgroundColor(this.cardBg($r('app.color.bg_card')))
              .backgroundBlurStyle(this.matOn() ? BlurStyle.NONE : GlassMaterial.bgBlur(this.immersiveEffect), GlassMaterial.blurOptions())
              .border({
                width: this.matOn() ? 0 : (this.immersiveEffect ? GlassMaterial.borderWidth() : 0),
                color: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent
              })
              .margin({ top: 14 })

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
          subtitle: '按页面单独设置灰字颜色',
          onBack: () => {
            AppState.stack.pop();
          }
        })
      }
      .width('100%')
      .height('100%')
      // 灰字广播依赖登记（恒真，不改变视觉）
      .opacity(this.grayTick >= 0 ? 1 : 1)
    }
    .hideTitleBar(true)
    // 调整面板：半模态（透明底 + 模糊，避免不透明底色盖死材质）
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
