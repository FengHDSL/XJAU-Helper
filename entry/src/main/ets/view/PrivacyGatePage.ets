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
import { DeclarationSection, DEVELOPER_DECLARATION } from '../common/PrivacyText';
import { DataStore } from '../common/DataStore';

@Component
export struct PrivacyGatePage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 完成回调：agreed=true 已同意隐私且走完引导；false = 暂不同意（仅可使用功能浏览） */
  onDone: (agreed: boolean) => void = () => {
  };
  /** 引导步骤：0 隐私协议 → 1 开发者声明 → 2 账号风控 */
  @State step: number = 0;
  /** 步骤切换方向：1=前进，-1=后退 */
  @State stepDirection: number = 1;
  private privacyController: webview.WebviewController = new webview.WebviewController();

  aboutToAppear(): void {
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

  /** 底部操作行（等宽双按钮：左侧次要=上一步/暂不同意，右侧品牌主按钮） */
  @Builder
  actionBar(secondaryText: string, primaryText: string,
    onSecondary: () => void, onPrimary: () => void) {
    Row() {
      Button(secondaryText)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .backgroundColor($r('app.color.bg_chip'))
        .height(42)
        .layoutWeight(1)
        .borderRadius(21)
        .onClick(onSecondary)
      Button(primaryText)
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.brand_on'))
        .backgroundColor($r('app.color.brand'))
        .height(42)
        .layoutWeight(1)
        .borderRadius(21)
        .margin({ left: 12 })
        .onClick(onPrimary)
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
    Column() {
      // 顶栏：标题 + 步骤提示
      Row() {
        Text(this.stepTitle())
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
        Blank()
        Text(`第 ${this.step + 1}/3 步`)
          .fontSize(12)
          .fontColor('#CCFFFFFF')
      }
      .width('100%')
      .height(px2vp(this.topInsetPx) + 60)
      .padding({ left: 16, right: 16, bottom: 12, top: px2vp(this.topInsetPx) + 12 })
      .backgroundColor(this.isDarkMode ? '#1A1D1C' : Theme.colorOf(this.themeColor))
      .alignItems(VerticalAlign.Center)

      if (this.step === 0) {
        // ── 第 1 步：隐私协议全文 ──
        Column() {
          Text('在你使用「新农助手」前，请阅读并同意以下隐私保护指引：')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .padding({ left: 20, right: 20, top: 14, bottom: 6 })
          Web({ src: $rawfile('privacy.html'), controller: this.privacyController })
            .width('100%')
            .layoutWeight(1)
            .backgroundColor(Color.Transparent)
            .darkMode(WebDarkMode.Auto)

          Column() {
            Text('未同意将无法使用账号登录，仅可使用"功能浏览"')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
              .textAlign(TextAlign.End)
              .margin({ bottom: 8 })
            this.actionBar('暂不同意', '同意并继续', () => { this.onDecline(); }, () => { this.onAgreePrivacy(); })
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 12, bottom: 16 + px2vp(this.bottomInsetPx) })
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
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                  .width('100%')
                  .margin({ top: 14, bottom: 6 })
                Text(sec.content)
                  .fontSize(14)
                  .lineHeight(22)
                  .fontColor($r('app.color.text_secondary'))
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
          .margin({ bottom: 16 + px2vp(this.bottomInsetPx) })
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
            .backgroundColor($r('app.color.bg_card'))
            .borderRadius(16)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .padding({ left: 8, right: 8 })

          Column() {
            this.actionBar('上一步', '我知道了',
              () => { this.goStep(1); }, () => { this.onFinish(); })
          }
          .margin({ bottom: 16 + px2vp(this.bottomInsetPx) })
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
  }
}
