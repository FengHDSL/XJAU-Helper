/**
 * 关于页：应用图标 + 版本号 + 更新日志 + 项目链接（独立页面）
 * 隐藏调试入口：连点应用图标 5 次，输入密码 admin——
 *  - 功能浏览模式（USE_MOCK）：开启/关闭调试联网（debugNetwork）
 *  - 真实登录模式：开启/关闭日志调试（logEnabled）
 *
 * 卡片外观接入（照首页 HomeView 的写法推广）：
 *  - 卡片统一用 `MaterialCard` 承载（材质层在卡片内部、位于内容之下），材质生效时卡片自身的
 *    底色/磨砂/亮边/阴影一并让出，每张卡只有一层视觉；关闭光感回落为原来的纯色/毛玻璃卡片；
 *  - 更新日志卡为共享组件 `ChangelogCard`（关于页「最近 5 条」与更新日志页共用），该组件已迁到
 *    `MaterialCard`，两页的更新日志卡因此都带沉浸光感；
 *  - 半模态弹窗（调试模式密码）内容套 `MaterialSheetPanel`，`bindSheet` 显式 `backgroundColor: Color.Transparent`。
 */
import { SheetUtil } from '../common/SheetUtil';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { AppState } from '../common/AppState';
import { Theme } from '../common/ThemeUtil';
import { GlassMaterial } from '../common/GlassMaterial';
import { Const } from '../common/Constants';
import { LogStore } from '../common/LogStore';
import { JwApi } from '../api/JwApi';
import { DataStore } from '../common/DataStore';
import { common } from '@kit.AbilityKit';
import { WallpaperTone } from '../common/WallpaperTone';
import { PageHeader } from './common/UiKit';
import { WallpaperFill } from './common/WallpaperFill';
import { ChangelogCard } from './common/ChangelogCard';
// 沉浸光感：卡片统一走 MaterialCard（材质承载层在卡片内容之下，材质生效时卡片底色/磨砂/亮边/阴影一并让出，
// 每张卡只剩一层视觉），胶囊按钮走 MaterialButton，半模态弹窗内容走 MaterialSheetPanel
import { MaterialCard, MaterialSheetPanel } from './common/MaterialCard';
import { MaterialButton } from './common/MaterialButton';
import { sheetBlurStyle } from '../common/SystemMaterial';
import { CHANGELOG_ALL, CHANGELOG_MAX, ChangelogItem } from '../common/Changelog';


@Component
export struct AboutPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  /** 响应式依赖：玻璃/灰字设置变化时触发本页重渲染（取值经 GlassMaterial 静态方法读取） */
  @StorageProp('glassStrength') glassStrength: number = 70;
  @StorageProp('cardMaterial') cardMaterial: boolean = false;
  @StorageProp('grayTextMode') grayTextMode: string = 'default';
  @StorageProp('grayTextColor') grayTextColor: string = '';
  @StorageProp('themeColor') themeColor: string = 'green';
  /** 壁纸亮度（文字自适应用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 应用图标连点计数（5 次内有效） */
  @State iconTapCount: number = 0;
  /** 调试模式密码输入弹窗开关 */
  @State showDebugSheet: boolean = false;
  @State debugPwd: string = '';
  /** 连点计时器（超时重置计数） */
  private iconTapTimer: number = -1;

  /** 应用图标连点：5 次内累计，满 5 次——
   *  已开启对应模式 → 弹"是否退出"；未开启 → 弹密码输入 */
  private onIconTapped(): void {
    this.iconTapCount++;
    if (this.iconTapTimer >= 0) {
      clearTimeout(this.iconTapTimer);
    }
    // 3 秒内未继续点击则重置计数
    this.iconTapTimer = setTimeout(() => {
      this.iconTapCount = 0;
    }, 3000);
    if (this.iconTapCount < 5) {
      return;
    }
    this.iconTapCount = 0;
    const active: boolean = AppState.logEnabled || AppState.debugNetwork;
    if (active) {
      // 已开启：询问是否退出（按当前生效的模式提示）
      const isLog: boolean = AppState.logEnabled;
      const isNet: boolean = AppState.debugNetwork;
      this.getUIContext().getPromptAction().showDialog({
        title: isLog ? '日志调试已开启' : '调试模式已开启',
        message: isLog && isNet ? '当前正在收集使用日志，且功能浏览模式允许联网。是否退出调试模式？' :
          (isLog ? '当前正在收集功能使用日志。是否退出日志调试？' : '当前功能浏览模式允许联网。是否退出调试模式？'),
        buttons: [
          { text: '取消', color: '#888888' },
          { text: '退出调试模式', color: '#DB5252', primary: true }
        ]
      }).then((res) => {
        if (res.index === 1) {
          AppState.logEnabled = false;
          AppState.debugNetwork = false;
          LogStore.clearAll(); // 退出调试：自动删除已收集日志与附件
          this.getUIContext().getPromptAction().showToast({ message: '已退出调试模式，日志已清除' });
        }
      });
    } else {
      // 未开启：弹密码输入
      this.debugPwd = '';
      this.showDebugSheet = true;
    }
  }

  /** 提交调试模式密码：admin——
   *  功能浏览模式（USE_MOCK）开启调试联网 + 日志收集；真实登录模式开启日志调试 */
  private submitDebugPwd(): void {
    if (this.debugPwd !== 'admin') {
      this.getUIContext().getPromptAction().showToast({ message: '密码错误' });
      return;
    }
    this.showDebugSheet = false;
    if (AppState.logEnabled || AppState.debugNetwork) {
      // 已开启：提示已开启，避免重复开启
      this.getUIContext().getPromptAction().showToast({ message: AppState.logEnabled ? '日志调试已开启' : '调试模式已开启' });
      return;
    }
    if (JwApi.USE_MOCK) {
      // 功能浏览模式：开启调试联网 + 日志收集（联网请求与使用日志一并收集）
      AppState.debugNetwork = true;
      AppState.logEnabled = true;
      LogStore.log('日志调试', '开启', '成功', '功能浏览模式调试开启（联网 + 日志收集）');
      this.getUIContext().getPromptAction().showToast({ message: '调试模式已开启：功能浏览允许联网并收集日志' });
    } else {
      // 真实登录：开启日志调试
      AppState.logEnabled = true;
      LogStore.log('日志调试', '开启', '成功', '真实登录模式');
      this.getUIContext().getPromptAction().showToast({ message: '日志调试已开启，开始收集使用日志' });
    }
  }

  /** 底部链接 + 开源等级 */
  @Builder
  footer() {
    // MaterialCard 承载：材质层是卡片内部底层、与卡片同尺寸同圆角，材质生效时卡片底色/磨砂/亮边/阴影让出；
    // 原卡片上的 padding / alignItems / margin 改走 cardPadding / cardAlignItems / cardMargin
    // （尾随闭包初始化的自定义组件之后不能再链式加属性）。
    MaterialCard({
      cardRadius: 16,
      cardPadding: 16,
      cardAlignItems: ItemAlign.Start,
      cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
      cardBlur: GlassMaterial.cardBlur(),
      cardBorderW: GlassMaterial.cardBorderWidth(),
      cardBorderC: GlassMaterial.borderColor(),
      cardShadow: GlassMaterial.cardShadowStyle(),
      cardMargin: { top: 0 }
    }) {
    Column() {
      Text('项目链接')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 10 })
      this.linkRow('XJAU-Helper（本项目）', 'https://github.com/FengHDSL/XJAU-Helper', true)
      this.linkRow('miha_hm（参考）', 'https://github.com/MrCashmere/miha_hm')
      this.linkRow('zhengfang-apk（参考）', 'https://github.com/znjhahaha/zhengfang-apk')
      this.linkRow('HiXD（参考）', 'https://github.com/PollenWang6/HiXD')
      this.linkRow('Traintime PDA（参考）', 'https://github.com/BenderBlog/traintime_pda')

      Text('开源等级: MIT License')
        .fontSize(12)
        .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 18 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    }
  }

  @Builder
  linkRow(title: string, url: string, openInApp: boolean = false) {
    Row() {
      Text(title)
        .fontSize(13)
        .fontColor(GlassMaterial.graySecondary($r('app.color.text_secondary')))
        .layoutWeight(1)
      Text(url.replace('https://github.com/', ''))
        .fontSize(12)
        .fontColor(Theme.colorOf(this.themeColor))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(38)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 4, right: 4 })
    .borderRadius(8)
    .onClick(() => {
      if (openInApp) {
        // 本项目的链接：打开应用内"外部链接"页面（WebView）直接访问
        AppState.webUrl = url;
        AppState.webTitle = '项目链接';
        AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
      } else {
        // 参考链接：复制到剪贴板，方便用户在浏览器中打开
        pasteboard.getSystemPasteboard().setDataSync(pasteboard.createPlainTextData(url));
        this.getUIContext().getPromptAction().showToast({ message: '链接已复制' });
      }
    })
  }

  /** 取消同意：询问是否清除数据 → 取消同意并退出应用（功能浏览模式不提供） */
  private cancelAgreement(): void {
    if (JwApi.USE_MOCK) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '取消同意',
      message: '取消同意后将无法使用本应用，下次打开需重新同意。是否同时清除本地数据？',
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

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // 二级页壁纸底层（无壁纸回 bg_page，不透下层）
        WallpaperFill()
        // 内容全屏：顶部占位随内容滚走，让上滑的内容进入悬浮顶栏下层
        Scroll() {
          Column() {
            // 顶栏占位（滚动时随内容滚走）：初始内容位于渐变顶栏下方
            Column()
              .width('100%')
              .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
            // 应用图标 + 名称 + 版本（连点 5 次进入隐藏调试模式）
            Column() {
              Image($r('app.media.startIcon'))
                .width(88)
                .height(88)
                .borderRadius(20)
                .backgroundColor('#FFFFFF').backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? true) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
                .onClick(() => {
                  this.onIconTapped();
                })
              Text('新农助手')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
                .margin({ top: 12 })
              Text('版本 1.3.9')
                .fontSize(12)
                .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
                .margin({ top: 4 })
              Text('仅供学习交流使用，严禁用于商业用途！')
                .fontSize(11)
                .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
                .margin({ top: 8 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 10, bottom: 16 })

            // 应用简介（单独卡片）
            // MaterialCard 承载：材质层是卡片内部底层、与卡片同尺寸同圆角，材质生效时卡片底色让出；
            // 原来的 16vp 内边距走 cardPadding、12vp 下间距走 cardMargin。
            MaterialCard({
              cardRadius: 16,
              cardPadding: 16,
              cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
              cardBlur: GlassMaterial.cardBlur(),
              cardBorderW: GlassMaterial.cardBorderWidth(),
              cardBorderC: GlassMaterial.borderColor(),
              cardShadow: GlassMaterial.cardShadowStyle(),
              cardMargin: { bottom: 12 }
            }) {
            Column() {
              Text('新农助手（XJAU Helper）是一款专为新疆农业大学学生打造的校园工具，原生鸿蒙开发，完全开源，完全免费，轻量小巧，集成个人课表、成绩查询、考试安排、学业情况、教室查询等功能于一体！数据来源于学校网页，数据不经过也不保存于非学校官方服务器。新农助手，让你的校园生活更便利！')
                .fontSize(12)
                .lineHeight(20)
                .fontColor(GlassMaterial.graySecondary($r('app.color.text_secondary')))
                .textAlign(TextAlign.Center)
                .width('100%')
            }
            .width('100%')
            }

            // 更新日志：固定只显示最近 CHANGELOG_MAX（5）条；完整历史在「更新日志」页查看
            ForEach(CHANGELOG_ALL.slice(0, CHANGELOG_MAX), (e: ChangelogItem) => {
              ChangelogCard({ version: e.version, date: e.date, items: e.items })
            }, (e: ChangelogItem) => e.version)

            // 入口：查看全部历史更新日志
            Row() {
              Text('查看全部更新日志 ›')
                .fontSize(12)
                .fontColor(Theme.colorOf(this.themeColor))
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: 2, bottom: 10 })
            .onClick(() => {
              AppState.stack.pushPath({ name: Const.ROUTE_CHANGELOG });
            })

            this.footer()

            // 用户协议 & 隐私政策（居中，可分别查看）
            // MaterialCard 承载（居中卡片同样走材质卡；内边距挂内部内容容器、上下间距走 cardMargin）
            MaterialCard({
              cardRadius: 16,
              cardAlignItems: ItemAlign.Center,
              cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
              cardBlur: GlassMaterial.cardBlur(),
              cardBorderW: GlassMaterial.cardBorderWidth(),
              cardBorderC: GlassMaterial.borderColor(),
              cardShadow: GlassMaterial.cardShadowStyle(),
              cardMargin: { top: 14, bottom: 12 }
            }) {
            Column() {
              Row({ space: 22 }) {
                Text('《用户协议》')
                  .fontSize(12)
                  .fontColor(Theme.colorOf(this.themeColor))
                  .onClick(() => {
                    AppState.stack.pushPath({ name: Const.ROUTE_TERMS });
                  })
                Text('《隐私政策》')
                  .fontSize(12)
                  .fontColor(Theme.colorOf(this.themeColor))
                  .onClick(() => {
                    AppState.stack.pushPath({ name: Const.ROUTE_PRIVACY });
                  })
              }
              .margin({ top: 8 })

              // 取消同意（胶囊按钮：材质走 MaterialButton 的 Toggle 承载层，点击行为不变；
              // 原 .margin({ top: 12 }) 改走 btnMargin——尾随闭包之后不能再链式加属性）
              if (!JwApi.USE_MOCK) {
                MaterialButton({
                  btnRadius: 14,
                  btnBg: 'rgba(219,82,82,0.10)',
                  btnBlur: GlassMaterial.bgBlur(AppStorage.get<boolean>('immersiveEffect') ?? true),
                  btnBorderW: GlassMaterial.borderWidth(),
                  btnBorderC: GlassMaterial.borderColor(),
                  btnMargin: { top: 12 },
                  btnOnClick: () => {
                    this.cancelAgreement();
                  }
                }) {
                  Text('取消同意并退出')
                    .fontSize(12)
                    .fontColor('#DB5252')
                    .padding({ left: 16, right: 16, top: 6, bottom: 6 })
                }
              }
            }
            .width('100%')
            .padding({ top: 12, bottom: 12, left: 16, right: 16 })
            }

            Column()
              .height(this.getUIContext().px2vp(this.bottomInsetPx) + 24)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4 })
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)

        // 悬浮顶栏：主题色渐变到透明，内容可滚入其下层
        PageHeader({
          title: '关于应用',
          subtitle: '新农助手',
          onBack: () => {
            AppState.stack.pop();
          }
        })
      }
      .width('100%')
      .height('100%')
      // 全局壁纸：二级页根背景透明，透出主框架底层壁纸（无壁纸时由 MainView 底层纯色兜底）
      .backgroundColor(Color.Transparent)
    }
    .backgroundColor($r('app.color.bg_page'))
    .hideTitleBar(true)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    .width('100%')
    .height('100%')
    // 调试模式密码输入弹窗（连点图标 5 次触发）
    .bindSheet($$this.showDebugSheet, this.debugSheet(), {
      width: SheetUtil.sheetWidth(),
      preferType: SheetType.BOTTOM,
      height: SheetSize.FIT_CONTENT,
      dragBar: false,
      showClose: true,
      // 必须显式透明：BindOptions.backgroundColor 默认 Color.White，而沉浸光感材质的视觉层级位于
      // backgroundColor **之下**，白底会把面板材质整块盖住（表现为「弹窗一点光感都没有」）。
      backgroundColor: Color.Transparent,
      blurStyle: sheetBlurStyle()
    })
  }

  /** 隐藏调试入口：输入密码开启对应模式的调试能力（功能浏览=联网；真实登录=日志） */
  @Builder
  debugSheet() {
    // 弹窗内容套 MaterialSheetPanel：bindSheet 自身的 systemMaterial 挂在面板上、内容区不生效，
    // 由 MaterialSheetPanel 的 Toggle 承载层渲染材质；配套要求是 bindSheet 显式 backgroundColor: Color.Transparent。
    // 本弹窗高度随内容（SheetSize.FIT_CONTENT），传 panelFillHeight: false（不写 height('100%')，避免被撑成整屏）。
    MaterialSheetPanel({ panelRadius: 20, panelPadding: 0, panelFillHeight: false }) {
    Column() {
      Text('调试模式')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ top: 16, bottom: 8 })

      Text(JwApi.USE_MOCK ? '输入密码以开启功能浏览模式的联网能力' : '输入密码以开启日志调试（收集使用日志）')
        .fontSize(12)
        .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
        .width('100%')
        .margin({ bottom: 12 })

      TextInput({ text: this.debugPwd, placeholder: '请输入密码' })
        .height(48)
        .enterKeyType(EnterKeyType.Done)
        .borderRadius($r('sys.float.corner_radius_level12'))
        .fontSize($r('sys.float.Body_L'))
        .fontWeight(FontWeight.Regular)
        .backgroundColor($r('sys.color.comp_background_tertiary'))
        .caretStyle({ color: $r('sys.color.font_emphasize') })
        .type(InputType.Normal)
        .fontColor('rgba(0, 85, 255, 1.0)')
        .placeholderFont({ size: $r('sys.float.Body_L'), weight: FontWeight.Regular })
        .width('100%')
        .onChange((v: string) => {
          this.debugPwd = v;
        })
        .onSubmit(() => {
          this.submitDebugPwd();
        })

      // 确认按钮：材质走 MaterialButton 的 Toggle 承载层（普通 Button 直接挂材质真机不渲染）；
      // 原 .width('100%') / .height(40) / .margin 由内容与 btnMargin 承担，点击行为不变
      MaterialButton({
        btnRadius: 20,
        btnBg: $r('app.color.brand'),
        btnBlur: GlassMaterial.bgBlur(AppStorage.get<boolean>('immersiveEffect') ?? true),
        btnBorderW: GlassMaterial.borderWidth(),
        btnBorderC: GlassMaterial.borderColor(),
        btnMargin: { top: 12, bottom: 16 },
        btnOnClick: () => {
          this.submitDebugPwd();
        }
      }) {
        Text('确认')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.brand_on'))
          .width('100%')
          .height(40)
          .textAlign(TextAlign.Center)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
    }
  }
}