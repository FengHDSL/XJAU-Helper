/**
 * 关于页：应用图标 + 版本号 + 更新日志 + 项目链接（独立页面）
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { AppState } from '../common/AppState';
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
      this.linkRow('XJAU-Helper（本校）', 'https://github.com/FengHDSL/XJAU-Helper')
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
  linkRow(title: string, url: string) {
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
      // 复制到剪贴板，方便用户在浏览器中打开
      pasteboard.getSystemPasteboard().setDataSync(pasteboard.createPlainTextData(url));
      promptAction.showToast({ message: '链接已复制' });
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
              Text('新疆农业大学教务助手 · 校园微服务客户端')
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
                .margin({ top: 8 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: 10, bottom: 16 })

            // 应用简介（用户可快速了解功能）
            Column() {
              Text('新农大小助手，支持查询课程表、考试成绩、考试信息、学业情况、校历和空闲教室。应用数据不经过第三方服务器，通过教务系统网页获取数据，经整理后直观呈现。不修改、不上传，完全开源。方便你的校园生活！')
                .fontSize(12)
                .lineHeight(20)
                .fontColor($r('app.color.text_secondary'))
                .textAlign(TextAlign.Center)
                .width('100%')
            }
            .width('100%')
            .padding({ left: 20, right: 20, bottom: 20 })

            this.changelog('1.2.0', '2026-08-08', [
              '完善空闲教室查询功能',
              '优化课程表设置使用体验',
              '优化部分文本显示效果',
              '替换部分图标',
              '修复一些已知 bug'
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