/**
 * 校公众号页（我的 → 校园服务 → 校公众号）：
 *  - 展示学校各官方微信公众号（名称 / 微信号 / 简介），点击「去关注」：
 *    - 已知主页直达链接的公众号（homeUrl 非空，__biz 取自公众号文章源码 var biz）：
 *      弹出「扫码关注」面板，内置 QRCode 渲染 mp.weixin.qq.com/mp/profile_ext 主页链接，
 *      微信「扫一扫」扫码直达公众号主页（可点关注）；面板内保留「复制链接并打开微信」兜底
 *      （profile_ext 链接仅微信内可开，外部浏览器提示"请在微信客户端打开"）。
 *    - 无直达链接的公众号：复制名称并拉起微信，在微信搜索框粘贴搜索关注。
 *  - 拉起微信：先试鸿蒙版包名 com.tencent.wechat，回落 com.tencent.mm，均失败提示手动操作。
 */
import { common, Want } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { AppState } from '../common/AppState';
import { AppearanceStore } from '../common/AppearanceStore';
import { GlassMaterial } from '../common/GlassMaterial';
import { materialAvailable, sheetBlurStyle } from '../common/SystemMaterial';
import { SheetUtil } from '../common/SheetUtil';
import { MaterialButton } from './common/MaterialButton';
import { MaterialCard, MaterialSheetPanel } from './common/MaterialCard';
import { PageHeader } from './common/UiKit';
import { WallpaperFill } from './common/WallpaperFill';

/** 公众号条目（homeUrl 非空 = 已知主页 profile_ext 直达链接：复制后微信内粘贴打开即达关注页） */
interface OAItem {
  name: string;
  wxid: string;
  desc: string;
  homeUrl: string;
}

/** 学校官方公众号清单（数据来源：学校官网/招生网公示；主页链接 __biz 取自公众号文章源码 var biz） */
const OA_LIST: OAItem[] = [
  {
    name: '新疆农业大学',
    wxid: 'xjnydx1952',
    desc: '学校官方订阅号：校园资讯、通知公告、校史馆预约等',
    homeUrl: ''
  },
  {
    name: '新农大小薇',
    wxid: '微信内搜索「新农大小薇」',
    desc: '迎新与学工服务号：录取查询、迎新预报到、缴费、学工服务',
    // profile_ext 主页链接：微信内打开即达公众号主页（可点关注）
    homeUrl: 'https://mp.weixin.qq.com/mp/profile_ext?action=home&__biz=MzA5MjM5MzgyMw==#wechat_redirect'
  }
];

@Component
export struct WechatOAPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  /** 灰字广播订阅：颜色表达式需传 this.grayTick 才登记响应式依赖 */
  @StorageProp('grayTick') grayTick: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('barStyle') barStyle: string = 'new';
  /** 沉浸光感订阅：公众号卡片材质判定（订阅与使用点须在同一 struct） */
  @StorageProp('immersiveEffect') immersiveEffect: boolean = false;
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;

  /** 扫码关注面板：showQrSheet 控制显隐，qrItem 记录当前公众号（仅 homeUrl 非空时弹出） */
  @State showQrSheet: boolean = false;
  @State qrItem: OAItem | null = null;

  /** 去关注入口：有主页直达链接 → 弹二维码面板（微信扫一扫直达）；无 → 复制名称拉起微信搜索 */
  private follow(item: OAItem): void {
    if (item.homeUrl.length > 0) {
      this.qrItem = item;
      this.showQrSheet = true;
      return;
    }
    this.copyTextAndLaunch(item.name, false);
  }

  /** 复制文本并拉起微信（二维码面板的兜底按钮与无链接公众号共用） */
  private copyTextAndLaunch(copyText: string, isHomeLink: boolean): void {
    const pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, copyText);
    pasteboard.getSystemPasteboard().setData(pasteData).then(() => {
      this.launchWechat(copyText, isHomeLink);
    }).catch(() => {
      // 剪贴板失败不阻断：仍尝试拉起微信
      this.launchWechat(copyText, isHomeLink);
    });
  }

  /** 拉起微信：先试鸿蒙版包名，回落 Android 包名，均失败则提示手动操作 */
  private launchWechat(copied: string, isHomeLink: boolean): void {
    const okMsg: string = isHomeLink
      ? '已复制公众号主页链接，在微信任意聊天窗口粘贴并打开，即可直达关注页'
      : `已复制「${copied}」，在微信搜索粘贴即可关注`;
    const failMsg: string = isHomeLink
      ? '已复制公众号主页链接，未检测到微信，请手动打开微信粘贴打开'
      : `已复制「${copied}」，未检测到微信，请手动打开微信搜索关注`;
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const wantHm: Want = { bundleName: 'com.tencent.wechat' };
    ctx.startAbility(wantHm).then((): void => {
      this.getUIContext().getPromptAction().showToast({ message: okMsg });
    }).catch((): void => {
      const wantApk: Want = { bundleName: 'com.tencent.mm' };
      ctx.startAbility(wantApk).then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: okMsg });
      }).catch((): void => {
        this.getUIContext().getPromptAction().showToast({ message: failMsg });
      });
    });
  }

  /** 公众号材质是否生效（与其它页 matOn 同判定链） */
  private matOn(): boolean {
    return this.immersiveEffect && materialAvailable();
  }

  /** 扫码关注面板：白色码区 + QRCode（黑点白底确保微信扫一扫可识别）+ 复制链接兜底按钮 */
  @Builder
  qrSheet() {
    MaterialSheetPanel({ panelRadius: 20, panelPadding: 0, panelFillHeight: false, panelTitle: '扫码关注', panelShowClose: true, panelOnClose: (): void => { this.showQrSheet = false; } }) {
      Column() {
        if (this.qrItem !== null) {
          Text(this.qrItem.name)
            .fontSize(16)
            .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .textAlign(TextAlign.Center)
          // 白底码区：QRCode 黑点在白底上对比度最高，深色模式下也保证扫码可识别
          Column() {
            QRCode(this.qrItem.homeUrl)
              .width(200)
              .height(200)
              .color('#000000')
          }
          .backgroundColor(Color.White)
          .borderRadius(12)
          .padding(10)
          .margin({ top: 12 })

          Text('打开微信「扫一扫」，扫描上方二维码直达公众号主页')
            .fontSize(12)
            .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
            .width('100%')
            .textAlign(TextAlign.Center)
            .margin({ top: 12 })

          // 兜底：复制主页链接并拉起微信（扫一扫不便时在微信聊天窗口粘贴打开）
          // margin 必须走 btnMargin 参数——MaterialButton 尾随闭包后不能再链式属性
          MaterialButton({
            btnRadius: 21,
            btnMargin: { top: 14 },
            btnBg: '#079841',
            btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
            btnBorderW: GlassMaterial.borderWidth(),
            btnBorderC: GlassMaterial.borderColor(),
            btnOnClick: (): void => {
              if (this.qrItem !== null) {
                this.showQrSheet = false;
                this.copyTextAndLaunch(this.qrItem.homeUrl, true);
              }
            }
          }) {
            Text('复制链接并打开微信')
              .fontSize(14)
              .fontColor($r('sys.color.font_primary'))
              .width('100%')
              .textAlign(TextAlign.Center)
              .height(42)
          }
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)
      .padding({ left: 20, right: 20, top: 8, bottom: 24 })
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // 二级页壁纸底层（无壁纸回 bg_page，不透下层）
        WallpaperFill()
        Scroll() {
          Column() {
            // 顶栏让位 spacer（与学业页同款）
            Column()
              .width('100%')
              .height(this.getUIContext().px2vp(this.topInsetPx) + 60 + (this.barStyle === 'legacy' ? 14 : 0))

            // 说明卡
            MaterialCard({
              cardRadius: 18,
              cardPadding: 16,
              cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
              cardBlur: GlassMaterial.cardBlur(),
              cardBorderW: GlassMaterial.cardBorderWidth(),
              cardBorderC: GlassMaterial.borderColor(),
              cardShadow: GlassMaterial.cardShadowStyle()
            }) {
              Column({ space: 6 }) {
                Text('关注学校官方公众号')
                  .fontSize(15)
                  .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
                  .fontColor($r('app.color.text_primary'))
                Text('点击「去关注」会复制并尝试打开微信：新农大小薇已内置主页直达链接，在微信任意聊天窗口粘贴打开即达关注页；其他公众号复制名称后在微信搜索关注。')
                  .fontSize(12)
                  .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
                  .lineHeight(18)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }

            // 公众号列表卡
            MaterialCard({
              cardRadius: 18,
              cardPadding: 6,
              cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
              cardBlur: GlassMaterial.cardBlur(),
              cardBorderW: GlassMaterial.cardBorderWidth(),
              cardBorderC: GlassMaterial.borderColor(),
              cardShadow: GlassMaterial.cardShadowStyle(),
              cardMargin: { top: 14 }
            }) {
              Column() {
                ForEach(OA_LIST, (item: OAItem, index: number) => {
                  Column() {
                    Row() {
                      // 左：公众号头像占位（首字圆形徽标）；文字随系统深浅色自动黑白
                      Text(item.name.substring(0, 1))
                        .fontSize(20)
                        .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
                        .fontColor($r('sys.color.font_primary'))
                        .width(46)
                        .height(46)
                        .textAlign(TextAlign.Center)
                        .backgroundColor('#22079841')
                        .borderRadius(23)
                      // 中：名称 / 微信号 / 简介
                      Column({ space: 3 }) {
                        Text(item.name)
                          .fontSize(15)
                          .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
                          .fontColor($r('app.color.text_primary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(item.wxid)
                          .fontSize(11)
                          .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                        Text(item.desc)
                          .fontSize(11)
                          .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
                          .lineHeight(16)
                      }
                      .layoutWeight(1)
                      .alignItems(HorizontalAlign.Start)
                      .margin({ left: 12 })

                      // 右：去关注（绿色实底，文字黑白自动对比度）
                      MaterialButton({
                        btnRadius: 15,
                        btnBg: '#079841',
                        btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
                        btnBorderW: GlassMaterial.borderWidth(),
                        btnBorderC: GlassMaterial.borderColor(),
                        btnMargin: { left: 10 },
                        btnOnClick: (): void => {
                          this.follow(item);
                        }
                      }) {
                        Text('去关注')
                          .fontSize(12)
                          .fontColor($r('sys.color.font_primary'))
                          .padding({ left: 12, right: 12, top: 7, bottom: 7 })
                      }
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)
                    .padding({ top: 12, bottom: 12, left: 10, right: 10 })

                    if (index < OA_LIST.length - 1) {
                      Divider().color($r('app.color.divider'))
                    }
                  }
                  .width('100%')
                }, (item: OAItem) => item.name)
              }
              .width('100%')
            }

            Column()
              .height(this.getUIContext().px2vp(this.bottomInsetPx) + 24)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Transparent)

        // 顶栏悬浮（最上层）
        PageHeader({
          title: '校公众号',
          onBack: () => {
            AppState.stack.pop();
          }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(Color.Transparent)
      // 扫码关注面板：挂最外层 Stack（本页唯一 bindSheet，无同组件多次挂载互相覆盖问题）
      .bindSheet($$this.showQrSheet, this.qrSheet(), {
        width: SheetUtil.sheetWidth(),
        preferType: SheetType.BOTTOM,
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        // 关闭按钮由 MaterialSheetPanel 自绘（沉浸光感），系统 showClose 必须关掉避免双按钮
        showClose: false,
        // 必须显式透明：BindOptions.backgroundColor 默认白底会把 MaterialSheetPanel 的材质整块盖住
        backgroundColor: Color.Transparent,
        blurStyle: sheetBlurStyle()
      })
    }
    .backgroundColor($r('app.color.bg_page'))
    .hideTitleBar(true)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
  }
}
