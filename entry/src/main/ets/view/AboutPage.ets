/**
 * 关于页：应用图标 + 版本号 + 更新日志 + 项目链接（独立页面）
 * 隐藏调试入口：连点应用图标 5 次，输入密码 admin——
 *  - 功能浏览模式（USE_MOCK）：开启/关闭调试联网（debugNetwork）
 *  - 真实登录模式：开启/关闭日志调试（logEnabled）
 */
import { SheetUtil } from '../common/SheetUtil';
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { LogStore } from '../common/LogStore';
import { JwApi } from '../api/JwApi';
import { PageHeader } from './common/UiKit';

@Component
export struct AboutPage {
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
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
      promptAction.showDialog({
        title: isLog ? '日志调试已开启' : '调试模式已开启',
        message: isLog ? '当前正在收集功能使用日志。是否退出日志调试？' : '当前功能浏览模式允许联网。是否退出调试模式？',
        buttons: [
          { text: '取消', color: '#888888' },
          { text: isLog ? '退出日志调试' : '退出调试模式', color: '#DB5252', primary: true }
        ]
      }).then((res) => {
        if (res.index === 1) {
          if (isLog) {
            AppState.logEnabled = false;
            LogStore.clear(); // 退出日志调试：自动删除已收集日志
            promptAction.showToast({ message: '已退出日志调试，日志已清除' });
          } else {
            AppState.debugNetwork = false;
            promptAction.showToast({ message: '已退出调试模式，功能浏览模式恢复断网' });
          }
        }
      });
    } else {
      // 未开启：弹密码输入
      this.debugPwd = '';
      this.showDebugSheet = true;
    }
  }

  /** 提交调试模式密码：admin——
   *  功能浏览模式（USE_MOCK）开启调试联网；真实登录模式开启日志调试 */
  private submitDebugPwd(): void {
    if (this.debugPwd !== 'admin') {
      promptAction.showToast({ message: '密码错误' });
      return;
    }
    this.showDebugSheet = false;
    if (AppState.logEnabled || AppState.debugNetwork) {
      // 已开启：提示已开启，避免重复开启
      promptAction.showToast({ message: AppState.logEnabled ? '日志调试已开启' : '调试模式已开启' });
      return;
    }
    if (JwApi.USE_MOCK) {
      // 功能浏览模式：开启调试联网
      AppState.debugNetwork = true;
      promptAction.showToast({ message: '调试模式已开启，功能浏览模式允许联网' });
    } else {
      // 真实登录：开启日志调试
      AppState.logEnabled = true;
      LogStore.log('日志调试', '开启', '成功', '真实登录模式');
      promptAction.showToast({ message: '日志调试已开启，开始收集使用日志' });
    }
  }

  @Builder
  changelog(version: string, date: string, items: string[]) {
    Column() {
      Row() {
        Text(`v${version}`)
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(`  ${date}`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .margin({ bottom: 8 })

      ForEach(items, (item: string) => {
        // 分组标题（@新增@ / @修复@ 开头 → 渲染为品牌色加粗小标题）
        if (item.startsWith('@新增@') || item.startsWith('@修复@')) {
          Text(item.substring(3))
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.brand'))
            .width('100%')
            .margin({ top: 6, bottom: 2 })
        } else {
          Row() {
            Text('·')
              .fontSize(13)
              .fontColor($r('app.color.brand'))
              .margin({ right: 8 })
            Text(item)
              .fontSize(13)
              .lineHeight(20)
              .fontColor($r('app.color.text_secondary'))
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Top)
          .margin({ bottom: 6 })
        }
      }, (item: string) => item)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(16)
    .margin({ bottom: 14 })
  }

  /** 底部链接 + 开源等级 */
  @Builder
  footer() {
    Column() {
      Text('项目链接')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 10 })
      this.linkRow('XJAU-Helper（本项目）', 'https://github.com/FengHDSL/XJAU-Helper', true)
      this.linkRow('HiXD（参考）', 'https://github.com/PollenWang6/HiXD')
      this.linkRow('Traintime PDA（参考）', 'https://github.com/BenderBlog/traintime_pda')

      Text('开源等级: MIT License')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 18 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(16)
    .margin({ top: 6 })
  }

  @Builder
  linkRow(title: string, url: string, openInApp: boolean = false) {
    Row() {
      Text(title)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
      Text(url.replace('https://github.com/', ''))
        .fontSize(12)
        .fontColor($r('app.color.brand'))
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
        promptAction.showToast({ message: '链接已复制' });
      }
    })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: '关于',
          subtitle: '新农助手',
          onBack: () => {
            AppState.stack.pop();
          }
        })

        Scroll() {
          Column() {
            // 应用图标 + 名称 + 版本（连点 5 次进入隐藏调试模式）
            Column() {
              Image($r('app.media.startIcon'))
                .width(88)
                .height(88)
                .borderRadius(20)
                .backgroundColor('#FFFFFF')
                .onClick(() => {
                  this.onIconTapped();
                })
              Text('新农助手')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .margin({ top: 12 })
              Text('版本 1.2.5')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
                .margin({ top: 4 })
              Text('仅供学习交流使用，严禁用于商业用途！')
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
                .margin({ top: 8 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 10, bottom: 16 })

            // 应用简介（用户可快速了解功能）
            Column() {
              Text('XJAU-Helper（新农大助手）是一款专为新疆农业大学学生打造的鸿蒙原生校园工具，集课表、成绩、考试、学业情况、校历、通知公告、空闲教室查询、农大新闻于一体。数据来自学校服务网页，不经过第三方服务器，不上传、不存储任何个人信息，完全开源。让校园学习更高效！')
                .fontSize(12)
                .lineHeight(20)
                .fontColor($r('app.color.text_secondary'))
                .textAlign(TextAlign.Center)
                .width('100%')
            }
            .width('100%')
            .padding({ left: 20, right: 20, bottom: 20 })

            this.changelog('1.2.5', '2026-08-18', [
              '修复平板横屏状态下成绩查询页面闪退的问题',
              '修复空闲教室查询无法使用的问题'
            ])

            this.changelog('1.2.4', '2026-08-17', [
              '更多页面适配平板',
              '课程表周次选择现在可以显示点阵图了',
              '多个地方文本和UI微调'
            ])

            this.changelog('1.2.3', '2026-08-16', [
              '兼容 API 24（鸿蒙 6.1），现在鸿蒙 6.1 的设备也可以安装了',
              '适配平板端，课程表界面初步对大屏进行适配'
            ])

            this.changelog('1.2.2', '2026-08-12', [
              '一些功能完善与问题修复'
            ])

            this.changelog('1.2.1', '2026-08-09', [
              '修复了一些已知问题'
            ])

            this.changelog('1.2.0', '2026-08-08', [
              '修复了一些已知问题'
            ])

            this.changelog('1.1.9', '2026-08-07', [
              '修复了一些已知问题'
            ])

            this.changelog('1.1.6', '2026-08-07', [
              '修复了一些已知问题'
            ])

            this.changelog('1.1.5', '2026-08-06', [
              '修复了一些已知问题'
            ])

            this.changelog('1.1.0', '2026-08-06', [
              '修复了一些已知问题'
            ])

            this.changelog('1.0.1', '2026-08-05', [
              '修复了一些已知问题'
            ])

            this.changelog('1.0.0', '2026-08-05', [
              '第一版上线'
            ])

            this.footer()

            Column()
              .height(px2vp(this.bottomInsetPx) + 24)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
    // 调试模式密码输入弹窗（连点图标 5 次触发）
    .bindSheet($$this.showDebugSheet, this.debugSheet(), {
      width: SheetUtil.sheetWidth(),
      preferType: SheetType.BOTTOM,
      height: SheetSize.FIT_CONTENT,
      dragBar: false,
      showClose: true,
      backgroundColor: $r('app.color.bg_page')
    })
  }

  /** 隐藏调试入口：输入密码开启对应模式的调试能力（功能浏览=联网；真实登录=日志） */
  @Builder
  debugSheet() {
    Column() {
      Text('调试模式')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ top: 16, bottom: 8 })

      Text(JwApi.USE_MOCK ? '输入密码以开启功能浏览模式的联网能力' : '输入密码以开启日志调试（收集使用日志）')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .margin({ bottom: 12 })

      TextInput({ text: this.debugPwd, placeholder: '请输入密码' })
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.bg_chip'))
        .borderRadius(10)
        .height(44)
        .width('100%')
        .onChange((v: string) => {
          this.debugPwd = v;
        })
        .onSubmit(() => {
          this.submitDebugPwd();
        })

      Button('确认')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.brand_on'))
        .backgroundColor($r('app.color.brand'))
        .height(40)
        .width('100%')
        .borderRadius(20)
        .margin({ top: 12, bottom: 16 })
        .onClick(() => {
          this.submitDebugPwd();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
    .backgroundColor($r('app.color.bg_page'))
  }
}