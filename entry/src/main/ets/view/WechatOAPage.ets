/**
 * 校公众号页（我的 → 校园服务 → 校公众号）：
 *  - 展示学校各官方微信公众号（名称 / 微信号 / 简介），点击「去关注」：
 *    复制公众号名称到剪贴板 → 尝试拉起微信（鸿蒙版 com.tencent.wechat，回落 com.tencent.mm）；
 *    未能拉起时提示手动打开微信搜索。
 *  - 为什么不直接跳公众号主页：微信未对外开放公众号主页的跨应用直达能力，
 *    mp.weixin.qq.com 的 profile_ext 主页链接只能在微信客户端内打开（外部浏览器提示"请在微信打开"），
 *    且 __biz 参数需从公众号「查看历史消息」链接中提取。因此采用「复制名称 + 拉起微信」的通行做法。
 */
import { common, Want } from '@kit.AbilityKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { AppState } from '../common/AppState';
import { AppearanceStore } from '../common/AppearanceStore';
import { GlassMaterial } from '../common/GlassMaterial';
import { materialAvailable } from '../common/SystemMaterial';
import { Theme } from '../common/ThemeUtil';
import { MaterialButton } from './common/MaterialButton';
import { MaterialCard } from './common/MaterialCard';
import { PageHeader } from './common/UiKit';
import { WallpaperFill } from './common/WallpaperFill';

/** 公众号条目 */
interface OAItem {
  name: string;
  wxid: string;
  desc: string;
}

/** 学校官方公众号清单（数据来源：学校官网/招生网公示） */
const OA_LIST: OAItem[] = [
  {
    name: '新疆农业大学',
    wxid: 'xjnydx1952',
    desc: '学校官方订阅号：校园资讯、通知公告、校史馆预约等'
  },
  {
    name: '新农大小薇',
    wxid: '微信内搜索「新农大小薇」',
    desc: '迎新与学工服务号：录取查询、迎新预报到、缴费、学工服务'
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

  /** 复制公众号名称并尝试拉起微信 */
  private follow(name: string): void {
    const pasteData: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, name);
    pasteboard.getSystemPasteboard().setData(pasteData).then(() => {
      this.launchWechat(name);
    }).catch(() => {
      // 剪贴板失败不阻断：仍尝试拉起微信
      this.launchWechat(name);
    });
  }

  /** 拉起微信：先试鸿蒙版包名，回落 Android 包名，均失败则提示手动搜索 */
  private launchWechat(name: string): void {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const wantHm: Want = { bundleName: 'com.tencent.wechat' };
    ctx.startAbility(wantHm).then((): void => {
      this.getUIContext().getPromptAction().showToast({ message: `已复制「${name}」，在微信搜索粘贴即可关注` });
    }).catch((): void => {
      const wantApk: Want = { bundleName: 'com.tencent.mm' };
      ctx.startAbility(wantApk).then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: `已复制「${name}」，在微信搜索粘贴即可关注` });
      }).catch((): void => {
        this.getUIContext().getPromptAction()
          .showToast({ message: `已复制「${name}」，未检测到微信，请手动打开微信搜索关注` });
      });
    });
  }

  /** 公众号材质是否生效（与其它页 matOn 同判定链） */
  private matOn(): boolean {
    return this.immersiveEffect && materialAvailable();
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
                Text('微信未开放从外部应用直达公众号主页，点击「去关注」会复制公众号名称并尝试打开微信，在微信搜索框粘贴名称即可关注。')
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
                      // 左：公众号头像占位（首字圆形徽标）
                      Text(item.name.substring(0, 1))
                        .fontSize(20)
                        .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
                        .fontColor(Theme.onColor('#079841'))
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
                          this.follow(item.name);
                        }
                      }) {
                        Text('去关注')
                          .fontSize(12)
                          .fontColor(Theme.onColor('#079841'))
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
    }
    .backgroundColor($r('app.color.bg_page'))
    .hideTitleBar(true)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
  }
}
