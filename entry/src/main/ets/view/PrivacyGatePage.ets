/**
 * 首次启动引导页（独立全屏页面，非弹窗）：依次展示
 *   ① 隐私保护指引（Web 加载 rawfile/privacy.html）
 *   ② 开发者声明
 *   ③ 账号风控提醒
 * Index 冷启动时若隐私协议未同意，则覆盖显示本页；全部确认后进入登录/主界面。
 * 同意后标记本地持久化（setPrivacyAgreed / setDeclarationShown），下次启动不再展示。
 *
 * 交互（2026-09-03 定稿）：
 *  - 各步正文铺满剩余空间，底部操作行放「次要(上一步/暂不同意) + 主按钮」；
 *  - 开发者声明/账号风控提供「上一步」回退，步骤切换带左右滑动过渡动画。
 */
import { webview } from '@kit.ArkWeb';
import { privacyManager } from '@kit.AppGalleryKit';
import { Theme } from '../common/ThemeUtil';
import { GlassMaterial } from '../common/GlassMaterial';
import { Immersive } from './common/Immersive';
import { IconCircleButton } from './common/IconCircleButton';
import { WallpaperTone } from '../common/WallpaperTone';
import { DeclarationSection, DEVELOPER_DECLARATION } from '../common/PrivacyText';
import { DataStore } from '../common/DataStore';
import { common } from '@kit.AbilityKit';
// 沉浸光感：按钮走 MaterialButton（有色主按钮用 btnTint 叠回品牌绿），正文卡片走 MaterialCard
import { MaterialCard } from './common/MaterialCard';
import { MaterialButton } from './common/MaterialButton';
import { AppearanceStore } from '../common/AppearanceStore';

@Component
export struct PrivacyGatePage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  /** 灰字广播订阅：颜色表达式需传 this.grayTick 才登记响应式依赖（否则改色不实时刷新） */
  @StorageProp('grayTick') grayTick: number = 0;
  /** 响应式依赖：玻璃/灰字设置变化时触发本页重渲染（取值经 GlassMaterial 静态方法读取） */
  @StorageProp('glassStrength') glassStrength: number = 70;
  @StorageProp('cardMaterial') cardMaterial: boolean = false;
  @StorageProp('grayTextMode') grayTextMode: string = 'default';
  @StorageProp('grayTextColor') grayTextColor: string = '';
  /** 全局字重响应式订阅：表达式读 this.fwMode 才登记依赖，fwValue 声明即订阅 */
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('barStyle') barStyle: string = 'new';
  @StorageProp('immersiveEffect') immersiveEffect: boolean = false;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 壁纸亮度（顶栏文字自适应用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  /** 完成回调：agreed=true 已同意隐私且走完引导；false = 暂不同意（仅可使用功能浏览） */
  onDone: (agreed: boolean) => void = () => {
  };
  /** 引导步骤：0 隐私协议 → 1 开发者声明 → 2 账号风控 */
  @State step: number = 0;
  /** 步骤切换方向：1=前进，-1=后退 */
  @State stepDirection: number = 1;
  /** 首次进入动画：淡入 + 轻微右移归位 */
  @State enterIn: boolean = false;
  /** 协议勾选：用户协议 / 隐私政策（需全部同意） */
  @State agreeTerms: boolean = false;
  @State agreePrivacy: boolean = false;
  /** 正在查看的文档：'' / 'terms' / 'privacy' */
  @State showDoc: string = '';
  private termsController: webview.WebviewController = new webview.WebviewController();
  private privacyDocController: webview.WebviewController = new webview.WebviewController();
  private privacyController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
    // 进入动画
    this.getUIContext().animateTo({ duration: 280, curve: Curve.EaseOut }, () => {
      this.enterIn = true;
    });
    // 已接入华为托管隐私协议且用户已同意（FULL_MODE_AGREED）：跳过自带协议页，直接从开发者声明开始
    try {
      const results = privacyManager.getAppPrivacyResult();
      for (const r of results) {
        if (r.result === 1) {
          DataStore.setPrivacyAgreed();
          this.step = 1;
          break;
        }
      }
    } catch (e) {
      // 未接入隐私托管服务或 API 不可用：正常展示应用自带隐私协议
    }
  }

  private stepTitle(): string {
    if (this.step === 1) {
      return '开发者声明';
    }
    if (this.step === 2) {
      return '账号风控提醒';
    }
    return '隐私保护指引';
  }

  /** 步骤切换（带动画）：animateTo 内更新 step，触发内容分支的 .transition 插入/移除动画 */
  private goStep(next: number): void {
    if (next < 0 || next > 2 || this.step === next) {
      return;
    }
    this.stepDirection = next > this.step ? 1 : -1;
    this.getUIContext().animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
      this.step = next;
    });
  }

  /** 同意隐私协议 → 进入开发者声明 */
  private onAgreePrivacy(): void {
    DataStore.setPrivacyAgreed();
    this.goStep(1);
  }

  /** 开发者声明"我已知晓" → 进入账号风控（标记已展示，避免重复） */
  private onKnowDeclaration(): void {
    DataStore.setDeclarationShown();
    this.goStep(2);
  }

  /** 账号风控完成：通知 Index 关闭引导 */
  private onFinish(): void {
    this.onDone(true);
  }

  /** 暂不同意隐私：仅功能浏览可用 */
  private onDecline(): void {
    this.onDone(false);
  }

  /** 不同意：询问是否清除数据 → 退出应用（不同意则无法使用） */
  private declineAgreement(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '不同意',
      message: '不同意用户协议与隐私政策将无法使用本应用。是否清除本地数据？',
      buttons: [
        { text: '清除数据并退出', color: '#DB5252' },
        { text: '保留数据并退出', color: '#666666' },
        { text: '取消', color: '#666666' }
      ]
    }).then((res) => {
      if (res.index === 2) {
        return;
      }
      if (res.index === 0) {
        DataStore.clearAll();
      }
      DataStore.clearPrivacyAgreed();
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.terminateSelf();
    });
  }

  /** 底部操作行（等宽双按钮：左侧次要=上一步/暂不同意，右侧品牌主按钮） */
  @Builder
  actionBar(secondaryText: string, primaryText: string,
    onSecondary: () => void, onPrimary: () => void) {
    Row() {
      // 次要按钮：等宽（layoutWeight 放在外层 Column 上——MaterialButton 内部是 Stack，layoutWeight 需放外层）。
      // 材质走 MaterialButton 的 Toggle 承载层；原淡灰玻璃底在 btnBg 兜底（光感关闭时回落同款玻璃底）。
      Column() {
        MaterialButton({
          btnRadius: 21,
          btnBg: $r('app.color.bg_chip'),
          btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
          btnBorderW: GlassMaterial.borderWidth(),
          btnBorderC: GlassMaterial.borderColor(),
          btnOnClick: () => {
            onSecondary();
          }
        }) {
          Text(secondaryText)
            .fontSize(14)
            .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
            .height(42)
            .width('100%')
            .textAlign(TextAlign.Center)
        }
      }
      .layoutWeight(1)

      // 品牌主按钮：材质生效时靠 btnTint 叠回品牌绿（比例 0.8，保证 Theme.onBrand() 深色文字对比度），
      // 既看到沉浸光感、也保留品牌色语义；光感关闭时回落 btnBg 品牌实底。
      Column() {
        MaterialButton({
          btnRadius: 21,
          btnBg: $r('app.color.brand'),
          btnTint: '#079841',
          btnTintRatio: 0.8,
          btnOnClick: () => {
            onPrimary();
          }
        }) {
          Text(primaryText)
            .fontSize(14)
            .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor(Theme.onBrand())
            .height(42)
            .width('100%')
            .textAlign(TextAlign.Center)
        }
      }
      .layoutWeight(1)
      .margin({ left: 12 })
    }
    .width('100%')
  }

  /** 步骤内容转场：前进时新页从右滑入、旧页向左滑出；后退时反向 */
  private stepTransition(): TransitionEffect {
    if (this.stepDirection > 0) {
      return TransitionEffect.asymmetric(
        TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: '100%' })),
        TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: '-100%' }))
      );
    }
    return TransitionEffect.asymmetric(
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: '-100%' })),
      TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: '100%' }))
    );
  }

  build() {
    Stack() {
      Column() {
      // 顶栏（两层）：内容(底)/主题渐变(顶)；标题+步骤提示（模糊层已取消）
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
        Text(this.stepTitle())
          .fontSize(19)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
        Blank()
        Text(`第 ${this.step + 1}/3 步`)
          .fontSize(12)
          .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
      }
      .width('100%')
      .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
      .padding({ left: 16, right: 16, bottom: 12, top: this.getUIContext().px2vp(this.topInsetPx) + 12 })
      .alignItems(VerticalAlign.Center)
      }
      .width('100%')
      // 顶栏悬浮：正文上滑可从渐变下层透出显示
      .position({ x: 0, y: 0 })
      .zIndex(2)

      // 顶栏高度占位（正文默认从顶栏下方开始）
      Column()
        .width('100%')
        .height(this.getUIContext().px2vp(this.topInsetPx) + 60)

      if (this.step === 0) {
        // ── 第 1 步：隐私协议全文 ──
        Column() {
          Text('在你使用「新农助手」前，请阅读并同意以下隐私保护指引：')
            .fontSize(13)
            .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
            .width('100%')
            .padding({ left: 20, right: 20, top: 14, bottom: 6 })
          Web({ src: $rawfile('privacy.html'), controller: this.privacyController })
            .width('100%')
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .darkMode(WebDarkMode.Auto)

          Column() {
            Row() {
              Checkbox({ name: 'agreeTerms', group: 'agreement' })
                .select(this.agreeTerms)
                .selectedColor(Theme.colorOf(this.themeColor))
                .onChange((v: boolean) => { this.agreeTerms = v; })
              Text('我已阅读并同意')
                .fontSize(12)
                .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
              Text('《用户协议》')
                .fontSize(12)
                .fontColor(Theme.colorOf(this.themeColor))
                .onClick(() => { this.showDoc = 'terms'; })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)

            Row() {
              Checkbox({ name: 'agreePrivacy', group: 'agreement' })
                .select(this.agreePrivacy)
                .selectedColor(Theme.colorOf(this.themeColor))
                .onChange((v: boolean) => { this.agreePrivacy = v; })
              Text('我已阅读并同意')
                .fontSize(12)
                .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
              Text('《隐私政策》')
                .fontSize(12)
                .fontColor(Theme.colorOf(this.themeColor))
                .onClick(() => { this.showDoc = 'privacy'; })
            }
            .width('100%')
            .margin({ top: 4 })
            .alignItems(VerticalAlign.Center)

            Text(this.agreeTerms && this.agreePrivacy
              ? '点击"同意并继续"进入下一步'
              : '需同时勾选《用户协议》与《隐私政策》后方可继续')
              .fontSize(11)
              .fontColor(this.agreeTerms && this.agreePrivacy ? $r('app.color.text_tertiary') : $r('app.color.accent_orange'))
              .width('100%')
              .margin({ top: 8, bottom: 8 })

            Row({ space: 12 }) {
              // 「不同意」：淡灰玻璃底小按钮，材质走 MaterialButton（光感关闭回落同款玻璃底）
              Column() {
                MaterialButton({
                  btnRadius: 21,
                  btnBg: $r('app.color.bg_chip'),
                  btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
                  btnBorderW: GlassMaterial.borderWidth(),
                  btnBorderC: GlassMaterial.borderColor(),
                  btnOnClick: () => {
                    this.declineAgreement();
                  }
                }) {
                  Text('不同意')
                    .fontSize(14)
                    .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
                    .height(42)
                    .width('100%')
                    .textAlign(TextAlign.Center)
                }
              }
              .layoutWeight(1)

              // 「同意并继续」：勾选后是品牌绿实底（深色文字）、未勾选是中性灰底（禁用）。
              // 材质生效时靠 btnTint 叠回品牌绿（比例 0.8），保留品牌色语义；未勾选时 btnTint 为空、不叠色。
              Column() {
                MaterialButton({
                  btnRadius: 21,
                  btnEnabled: this.agreeTerms && this.agreePrivacy,
                  btnBg: this.agreeTerms && this.agreePrivacy ? $r('app.color.brand') : $r('app.color.bg_chip'),
                  btnTint: this.agreeTerms && this.agreePrivacy ? '#079841' : '',
                  btnTintRatio: 0.8,
                  btnOnClick: () => {
                    this.onAgreePrivacy();
                  }
                }) {
                  Text('同意并继续')
                    .fontSize(14)
                    .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
                    // 文字色按背景亮度自动取深/浅（品牌绿上深色文字对比度更高）；
                    // 未勾选时改为「中性底 + 次级文字」，避免用半透明表达禁用导致文字看不清
                    .fontColor(this.agreeTerms && this.agreePrivacy
                      ? Theme.onBrand()
                      : $r('app.color.text_secondary'))
                    .height(42)
                    .width('100%')
                    .textAlign(TextAlign.Center)
                }
              }
              .layoutWeight(1)
            }
            .width('100%')
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 12, bottom: 16 + this.getUIContext().px2vp(this.bottomInsetPx) })
          .backgroundColor($r('app.color.bg_card'))
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('app.color.bg_page'))
        .transition(this.stepTransition())
      } else if (this.step === 1) {
        // ── 第 2 步：开发者声明 ──
        Column() {
          Scroll() {
            Column() {
              ForEach(DEVELOPER_DECLARATION, (sec: DeclarationSection) => {
                Text(sec.title)
                  .fontSize(15)
                  .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')
                  .margin({ top: 14, bottom: 6 })
                Text(sec.content)
                  .fontSize(14)
                  .lineHeight(22)
                  .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
                  .width('100%')
              }, (sec: DeclarationSection) => sec.title)
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 8, bottom: 16 })
          }
          .layoutWeight(1)
          .width('100%')
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)

          Column() {
            this.actionBar('上一步', '我已知晓',
              () => { this.goStep(0); }, () => { this.onKnowDeclaration(); })
          }
          .margin({ bottom: 16 + this.getUIContext().px2vp(this.bottomInsetPx) })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 20, right: 20, top: 10 })
        .backgroundColor($r('app.color.bg_page'))
        .transition(this.stepTransition())
      } else {
        // ── 第 3 步：账号风控提醒 ──
        Column() {
          // 正文区域：铺满剩余空间并整体居中（聚焦提示内容）
          Column() {
            // MaterialCard 承载：原 20vp 内边距挂内部内容容器（承载层才能铺满整块卡片）；16vp 圆角走 cardRadius。
            // 材质生效时卡片底色/磨砂/亮边/阴影一并让出，光感关闭回落原 bg_card 纯色卡。
            MaterialCard({
              cardRadius: 16,
              cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
              cardBlur: GlassMaterial.cardBlur(),
              cardBorderW: GlassMaterial.cardBorderWidth(),
              cardBorderC: GlassMaterial.borderColor(),
              cardShadow: GlassMaterial.cardShadowStyle()
            }) {
            Column() {
              Text('请勿频繁登录与退出教务系统，以免导致账号风控无法使用！' +
                '建议将应用锁定在后台，以免被清除。\n\n' +
                '若账号风控导致应用无法使用，请清除应用数据，等待24小时及以上，风控将自动解除。\n\n' +
                '若此时应用还是无法登录，则可能是学校服务器更新，应用不一定还能登录，' +
                '请关注更新动态（没有更新就说明应用已无法使用）。')
                .fontSize(14)
                .lineHeight(22)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .padding(20)
            }
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding({ left: 8, right: 8 })

          Column() {
            this.actionBar('上一步', '我知道了',
              () => { this.goStep(1); }, () => { this.onFinish(); })
          }
          .margin({ bottom: 16 + this.getUIContext().px2vp(this.bottomInsetPx) })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12, top: 10 })
        .backgroundColor($r('app.color.bg_page'))
        .transition(this.stepTransition())
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    .opacity(this.enterIn ? 1 : 0)
    .translate({ x: this.enterIn ? 0 : 28 })

      // 协议全文查看（覆盖层）：点击《用户协议》/《隐私政策》后展示
      if (this.showDoc.length > 0) {
        Column() {
          Row() {
            Text(this.showDoc === 'terms' ? '用户协议' : '隐私政策')
              .fontSize(16)
              .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)
            IconCircleButton({
              symbol: $r('sys.symbol.xmark'),
              buttonSize: 34,
              iconSize: 16,
              tint: $r('app.color.text_secondary'),
              onAction: (): void => {
                this.showDoc = '';
              }
            })
          }
          .width('100%')
          .height(52)
          .padding({ left: 16, right: 16, top: this.getUIContext().px2vp(this.topInsetPx) })
          .alignItems(VerticalAlign.Center)

          if (this.showDoc === 'terms') {
            Web({ src: $rawfile('terms.html'), controller: this.termsController })
              .width('100%')
              .layoutWeight(1)
              .backgroundColor($r('app.color.bg_page'))
              .darkMode(WebDarkMode.Auto)
          } else {
            Web({ src: $rawfile('privacy.html'), controller: this.privacyDocController })
              .width('100%')
              .layoutWeight(1)
              .backgroundColor($r('app.color.bg_page'))
              .darkMode(WebDarkMode.Auto)
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.bg_page'))
      }
    }
  }
}
