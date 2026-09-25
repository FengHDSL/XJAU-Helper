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
import { Theme } from '../common/ThemeUtil';
import { materialAvailable, sheetBlurStyle } from '../common/SystemMaterial';
import { SheetUtil } from '../common/SheetUtil';
import { MaterialButton } from './common/MaterialButton';
import { MaterialCard, MaterialSheetPanel } from './common/MaterialCard';
import { PageHeader } from './common/UiKit';
import { WallpaperFill } from './common/WallpaperFill';

/** 公众号条目（homeUrl 非空 = 已知主页 profile_ext 直达链接：扫码/复制后微信内打开即达关注页） */
interface OAItem {
  name: string;
  wxid: string;
  desc: string;
  homeUrl: string;
  /** 分组：'通用'（校级/公共服务/学生组织）| '学院'（各学院官方号） */
  group: string;
}

/** 由 __biz 拼公众号主页链接（微信内打开/扫码直达关注页） */
function homeUrlOf(biz: string): string {
  return biz.length > 0
    ? `https://mp.weixin.qq.com/mp/profile_ext?action=home&__biz=${biz}#wechat_redirect`
    : '';
}

/** 学校官方公众号清单（名称/biz 抓取自公众号文章页 var biz 与 nickname，2026-09-25 核实）；
 *  group 为自动分类：校级部门/公共服务/学生组织归「通用」，各学院官方号归「学院」 */
const OA_LIST: OAItem[] = [
  // ── 通用 ──
  { name: '新疆农业大学', wxid: 'xjnydx1952', desc: '学校官方订阅号：校园资讯、通知公告、文化活动', homeUrl: homeUrlOf('MjM5MTY3OTEwNQ=='), group: '通用' },
  { name: '新农大小薇', wxid: '微信内搜索「新农大小薇」', desc: '迎新与学工服务号：录取查询、迎新预报到、缴费、学工服务', homeUrl: homeUrlOf('MzA5MjM5MzgyMw=='), group: '通用' },
  { name: '新疆农业大学图书馆', wxid: '', desc: '图书馆官方号：书目检索、讲座培训、开放安排', homeUrl: homeUrlOf('MzA5ODg4NTA5Mg=='), group: '通用' },
  { name: '新疆农业大学学生会', wxid: '', desc: '校学生会：二课学时、校园活动、权益服务', homeUrl: homeUrlOf('MzAwMzQ3MzEzNw=='), group: '通用' },
  { name: '新农大研究生', wxid: '', desc: '研究生教育服务：招生培养、学位学术活动', homeUrl: homeUrlOf('MzI0ODExODIwNg=='), group: '通用' },
  { name: '新农暖阳心理', wxid: '', desc: '心理健康教育中心：心理科普、咨询预约、朋辈活动', homeUrl: homeUrlOf('Mzk0NjU2OTk5OA=='), group: '通用' },
  { name: '新疆农业大学校友会', wxid: '', desc: '校友之家：校友动态、返校服务、征稿活动', homeUrl: homeUrlOf('MzU5OTEzMTIxNw=='), group: '通用' },
  { name: '新疆农业大学网信中心', wxid: '', desc: '信息化服务：上网认证、软件正版化、网络报修', homeUrl: homeUrlOf('MzkwNDU5NTEzNA=='), group: '通用' },
  { name: '新疆农业大学塔城校区', wxid: '', desc: '塔城校区官方号：校区资讯与学生活动', homeUrl: homeUrlOf('MzY5NjQ1MTI4Mg=='), group: '通用' },
  { name: '新疆农业大学学报', wxid: '', desc: '学术期刊：论文荐读、编委动态、投稿指南', homeUrl: homeUrlOf('MzE5ODE1Mjk5MA=='), group: '通用' },
  { name: '平安新农大', wxid: '', desc: '安全保卫：安全提醒、反诈宣传、户籍服务', homeUrl: homeUrlOf('MzkzMjU2MjQzNw=='), group: '通用' },
  { name: '农大科研', wxid: '', desc: '科研管理处：项目申报、学术讲座、科研政策', homeUrl: homeUrlOf('Mzg5Mjg4MjU3NQ=='), group: '通用' },
  { name: '新疆农业大学动物中心医院', wxid: '', desc: '第一动物医院：诊疗服务、行业交流', homeUrl: homeUrlOf('Mzg4OTQ1MzY5NQ=='), group: '通用' },
  // ── 学院 ──
  { name: '新疆农业大学农学院', wxid: '', desc: '农学院官方号：学院资讯、教学科研、学生活动', homeUrl: homeUrlOf('MzAxMTA5NDIzNg=='), group: '学院' },
  { name: '新疆农业大学化学化工学院', wxid: '', desc: '化学化工学院官方号：招聘宣讲、实验安全、学生活动', homeUrl: homeUrlOf('MzA3MDQ1NzUwOQ=='), group: '学院' },
  { name: '新疆农业大学外国语学院', wxid: '', desc: '外国语学院官方号：教学科研、外语竞赛、学院资讯', homeUrl: homeUrlOf('MjM5Nzc5ODk4MQ=='), group: '学院' },
  { name: '新疆农业大学国际教育学院', wxid: '', desc: '国际教育学院官方号：国际合作、留学项目、学院资讯', homeUrl: homeUrlOf('MzA4OTAxMDQxMw=='), group: '学院' },
  { name: '新疆农业大学动物科学学院', wxid: '', desc: '动物科学学院官方号：学院资讯、宣讲实践、学生活动', homeUrl: homeUrlOf('MzA3NzY0MDQxNA=='), group: '学院' },
  { name: '新疆农业大学园艺学院', wxid: '', desc: '园艺学院官方号：耕读教育、学院资讯、学生活动', homeUrl: homeUrlOf('MzkwOTI3NzU5NQ=='), group: '学院' },
  { name: '新农资环', wxid: '', desc: '资源与环境学院官方号：田间实践、科研动态、学生活动', homeUrl: homeUrlOf('MzI4MDI3MTAxNw=='), group: '学院' },
  { name: '阳光中语', wxid: '', desc: '中国语言文学与艺术学院官方号：文化活动、学院资讯', homeUrl: homeUrlOf('MzA4NTAwODU5MQ=='), group: '学院' },
  { name: '新疆农业大学生命科学学院', wxid: '', desc: '生命科学学院官方号：学院资讯、教学科研、学生活动', homeUrl: homeUrlOf('Mzg5NTY3NjkyMQ=='), group: '学院' },
  { name: '新农大动医', wxid: '', desc: '动物医学学院官方号：学院资讯、三进两联一交友、学生活动', homeUrl: homeUrlOf('MzA5MDc0MjcyNg=='), group: '学院' },
  { name: '新农ITShow', wxid: '', desc: '计算机与信息工程学院官方号：技术活动、学院资讯', homeUrl: homeUrlOf('MzI1MzE1MDM0Mw=='), group: '学院' },
  { name: '新疆农业大学机电工程学院', wxid: '', desc: '机电工程学院官方号：学院资讯、师生交流、学生活动', homeUrl: homeUrlOf('Mzg3NjE3MDI0Mg=='), group: '学院' },
  { name: '新农大淼垚之声', wxid: '', desc: '水利与土木工程学院官方号：学院资讯、文化活动', homeUrl: homeUrlOf('MzA4Mzk1OTQ5OQ=='), group: '学院' },
  // 文章页未暴露 __biz（仅 gh_ 原始 id，无法拼主页链接）→ 走「复制名称搜索」路径
  { name: '公共管理学院（法学院）', wxid: '', desc: '学院官方号：微信内搜索名称后关注', homeUrl: '', group: '学院' }
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

  /** 拉起微信（三级回落）：
   *  ① 显式 Want：bundleName + abilityName（鸿蒙微信入口 UIAbility 为 EntryAbility——
   *     只写 bundleName 时部分设备/版本解析不到入口，实测拉不起，必须补 abilityName）
   *  ② 回落 Android 包名 com.tencent.mm
   *  ③ weixin:// scheme 隐式拉起（系统路由到微信） */
  private launchWechat(copied: string, isHomeLink: boolean): void {
    const okMsg: string = isHomeLink
      ? '已复制公众号主页链接，在微信任意聊天窗口粘贴并打开，即可直达关注页'
      : `已复制「${copied}」，在微信搜索粘贴即可关注`;
    const failMsg: string = isHomeLink
      ? '已复制公众号主页链接，未检测到微信，请手动打开微信粘贴打开'
      : `已复制「${copied}」，未检测到微信，请手动打开微信搜索关注`;
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const wantHm: Want = { deviceId: '', bundleName: 'com.tencent.wechat', abilityName: 'EntryAbility' };
    ctx.startAbility(wantHm).then((): void => {
      this.getUIContext().getPromptAction().showToast({ message: okMsg });
    }).catch((): void => {
      const wantApk: Want = { deviceId: '', bundleName: 'com.tencent.mm' };
      ctx.startAbility(wantApk).then((): void => {
        this.getUIContext().getPromptAction().showToast({ message: okMsg });
      }).catch((): void => {
        const wantScheme: Want = { deviceId: '', uri: 'weixin://' };
        ctx.startAbility(wantScheme).then((): void => {
          this.getUIContext().getPromptAction().showToast({ message: okMsg });
        }).catch((): void => {
          this.getUIContext().getPromptAction().showToast({ message: failMsg });
        });
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

  /** 分组内的公众号数量 */
  private groupCount(groupName: string): number {
    let n: number = 0;
    for (const it of OA_LIST) {
      if (it.group === groupName) {
        n++;
      }
    }
    return n;
  }

  /** 分组列表卡：按 group 过滤渲染；行内不放头像徽标（用户要求），名称+简介+去关注按钮 */
  @Builder
  oaGroupCard(groupName: string) {
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
        Row() {
          Text(groupName)
            .fontSize(13)
            .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
            .fontColor(Theme.colorOf(this.themeColor))
          Blank()
          Text(`${this.groupCount(groupName)} 个`)
            .fontSize(11)
            .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
        }
        .width('100%')
        .padding({ top: 10, bottom: 4, left: 10, right: 10 })

        ForEach(OA_LIST.filter((it: OAItem): boolean => it.group === groupName), (item: OAItem, index: number) => {
          Column() {
            Row() {
              Column({ space: 3 }) {
                Text(item.name)
                  .fontSize(15)
                  .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                if (item.wxid.length > 0) {
                  Text(item.wxid)
                    .fontSize(11)
                    .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                Text(item.desc)
                  .fontSize(11)
                  .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
                  .lineHeight(16)
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

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

            if (index < this.groupCount(groupName) - 1) {
              Divider().color($r('app.color.divider'))
            }
          }
          .width('100%')
        }, (item: OAItem) => item.name)
      }
      .width('100%')
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
                Text('点击「去关注」弹出二维码：打开微信「扫一扫」扫码直达公众号主页；也可复制主页链接在微信内粘贴打开（大部分公众号已收录主页直达链接）。列表按「通用 / 学院」自动分组。')
                  .fontSize(12)
                  .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
                  .lineHeight(18)
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
            }

            // 通用组：校级 / 公共服务 / 学生组织
            this.oaGroupCard('通用')
            // 学院组：各学院官方号
            this.oaGroupCard('学院')

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
