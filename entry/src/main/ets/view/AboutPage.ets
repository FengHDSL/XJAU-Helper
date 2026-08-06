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
              Text('版本 1.1.0')
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
            .padding({ top: 10, bottom: 24 })

            this.changelog('1.1.0', '2026-08-06', [
              '启用新应用图标，登录页与顶栏统一农大绿，忘记密码跳转学校官网',
              '成绩查询自动换算平均分与GPA（按学校「课程及学分」办法）',
              '首页新增校历（正常日历样式，默认当月可展开）、通知卡对接教务处学期校历',
              '首页顶栏显示学年学期与当前周次，支持全局切换学期（各页自动同步）',
              '无课时展示"当前没课了哦！"+ 下次课卡片（课程/时间/教室，居中布局）',
              '消息时间精确到时分秒，标题正文重复时只显示标题，顶部统一主题色',
              '所有详情页圆点文字垂直居中，菜单/退出按钮图标优化',
              '清除缓存同时清理 WebView 缓存',
              '功能浏览与真实登录数据完全隔离，固定周次确保全功能有数据；张三信息占位化',
              '首页无课时"下次课"卡片精简为课程名称/上课时间/教室地点',
              '首页顶栏显示当前教学周，日历改为左右滑动查看月份，学期外日期灰色',
              '登录页历史账号展开带过渡动画，输入框提示精简为"学号/密码"',
              '考试页更名"考试查询"，倒计时按剩余天数分级配色（红/黄/绿）',
              '功能浏览模式头像使用占位头像，我的页不再显示教务网址',
              '日历月份高度固定（不再随天数增减上下抽动），通知卡更名"校历信息"',
              '登录页历史账号"最近"标记移至行首',
              '底栏切换页面时按钮文字颜色即时变化，不再等待滑动动画完成'
            ])

            this.changelog('1.0.1', '2026-08-05', [
              '修复考试页面和消息页面的显示效果'
            ])

            this.changelog('1.0.0', '2026-08-05', [
              '第一个正式版',
              '增加并确认了基础功能的正常运行'
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