/**
 * 关于页：应用图标 + 版本号 + 更新日志（独立页面）
 */
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
              Text('版本 1.0.0')
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

            this.changelog('1.0.0', '2026-08-05', [
              '教务数据接入：统一身份认证登录、课表、成绩、考试安排、学业情况、通知公告',
              '沉浸悬浮底栏 + 深浅色模式自适应',
              '顶栏主题色：中国红 / 天空蓝 / 农大绿，一键切换',
              '桌面卡片：课程预告、考试倒计时，今日/明日一键切换',
              '深色模式全界面适配，顶栏深色下为黑色',
              '横屏/平板内容自适应（限宽居中）',
              '课程详情、成绩详情按课程属性着色标记',
              '考试倒计时提醒、考试安排写入系统日历',
              '登录体验：密码明文切换、一键清空、历史账号、验证码、功能浏览模式',
              '隐私保护：数据仅存本地，不收集无关权限'
            ])

            this.changelog('0.9.0', '2026-07-28', [
              '学业情况：GPA、学分完成度、课程分类统计、学业预警',
              '通知公告：列表 + 详情阅读',
              '成绩查询：学期切换、绩点排序、等级/百分制展示'
            ])

            this.changelog('0.8.0', '2026-07-20', [
              '课程表：周视图、周次选择、学期切换、课程详情',
              '考试安排：倒计时、日历导入',
              '首页：今日课程、最近考试、快捷入口'
            ])

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
