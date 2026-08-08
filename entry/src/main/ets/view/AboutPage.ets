/**
 * 关于页：应用图标 + 版本号 + 更新日志 + 项目链接（独立页面）
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { PageHeader } from './common/UiKit';

@Component
export struct AboutPage {
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;

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

      Text('开源等级：MIT License')
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
          subtitle: 'XJAU-Helper',
          onBack: () => {
            AppState.stack.pop();
          }
        })

        Scroll() {
          Column() {
            // 应用图标 + 名称 + 版本
            Column() {
              Image($r('app.media.startIcon'))
                .width(88)
                .height(88)
                .borderRadius(20)
                .backgroundColor('#FFFFFF')
              Text('XJAU-Helper')
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .margin({ top: 12 })
              Text('版本 1.2.0')
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

            this.changelog('1.2.0', '2026-08-08', [
              '新增「外部链接」页面：校历信息/成绩参考/我的-网页端教务系统/空教室网页端/农大新闻网页端等入口跳转；页面右上角集成「复制/分享」胶囊按钮；标题自动同步为网页自身标题',
              '我的页面新增「学校官网」入口；「主题模式」更名为「主题颜色」',
              '课程表支持左右滑动切换上一周/下一周',
              '首页日历胶囊（未开学/开学日期/结束日期）间距加大',
              '隐私协议全面重写为 10 节规范版本（单一事实源，登录弹窗与「我的」页共用）',
              '登录页「重登方式」：首次启动默认「自动重登」；新增固定入口（可随时切换，切换后实时刷新）；问号图标说明两种方式区别',
              '清理项目废弃代码与未用资源（10 个文件净删 600+ 行）',
              '关于页版本号下方加「仅供学习交流使用，严禁用于商业用途！」；应用简介文案更新',
              '修复若干已知 bug：空闲教室导出 502、校历通知点击跳转等',
              '优化部分文本显示效果与交互细节'
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
              '修复了一些已知问题'
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
  }
}