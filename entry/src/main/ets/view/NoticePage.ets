/**
 * 消息：原"课程通知"，汇总显示教务通知（不做分类）
 */
import { JwApi } from '../api/JwApi';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { NoticeItem } from '../model/Models';
import { EMPTY_NOTICE } from '../model/Empty';
import { EmptyTip, LoadingTip, TagChip } from './common/UiKit';

@Component
export struct NoticePage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @State notices: NoticeItem[] = [];
  @State loading: boolean = true;

  /** 页面出现：加载通知公告 */
  aboutToAppear(): void {
    this.load();
  }

  private async load(): Promise<void> {
    // 先用缓存秒开
    const cached: NoticeItem[] = JwApi.loadCachedNotices();
    if (cached.length > 0) {
      this.notices = cached;
      this.loading = false;
    }
    try {
      this.notices = await JwApi.getNotices();
    } catch (e) {
      // 网络异常时保持缓存
    }
    this.loading = false;
  }

  /** 未读通知数量 */
  private unreadCount(): number {
    let n: number = 0;
    for (const item of this.notices) {
      if (!item.read) {
        n++;
      }
    }
    return n;
  }

  /** 打开通知详情弹层 */
  private openDetail(item: NoticeItem): void {
    item.read = true;
    this.notices = this.notices.slice(0);
    AppState.currentNotice = item;
    AppState.stack.pushPath({ name: Const.ROUTE_NOTICE_DETAIL });
  }

  @Builder
  noticeCard(item: NoticeItem) {
    Column() {
      Row() {
        if (item.isTop) {
          TagChip({ text: '置顶', color: $r('app.color.state_danger'), bg: $r('app.color.bg_chip') })
            .margin({ right: 6 })
        }
        Text(item.source)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .layoutWeight(1)
        if (!item.read) {
          Circle()
            .width(7)
            .height(7)
            .fill($r('app.color.state_danger'))
        }
      }
      .width('100%')

      Text(item.title)
        .fontSize(15)
        .fontWeight(item.read ? FontWeight.Normal : FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .margin({ top: 10 })

      Row() {
        Blank()
        Text(item.date)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .margin({ top: 10 })
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(16)
    .margin({ bottom: 12 })
    .onClick(() => {
      this.openDetail(item);
    })
  }

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('‹')
            .fontSize(26)
            .fontColor($r('app.color.text_primary'))
            .width(34)
            .height(34)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              AppState.stack.pop();
            })

          Column() {
            Text('消息')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text(`教务通知汇总 · 共 ${this.notices.length} 条 · ${this.unreadCount()} 条未读`)
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 3 })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 6 })
          .layoutWeight(1)

          Blank()
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 10, right: 16, bottom: 14, top: px2vp(this.topInsetPx) + 10 })
        .backgroundColor($r('app.color.bg_page'))

        if (this.loading) {
          LoadingTip()
        } else if (this.notices.length === 0) {
          Scroll() {
            Column() {
              EmptyTip({ text: '暂无消息' })
              Text('消息来源：教务系统 /jwglxt/xtgl/index_cxDbsy.html?flag=1')
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
                .margin({ top: 16, bottom: 24 })
            }
            .width('100%')
            .padding({ top: 14, left: 16, right: 16 })
          }
        } else {
          Scroll() {
            Column() {
              ForEach(this.notices, (item: NoticeItem) => {
                this.noticeCard(item)
              }, (item: NoticeItem) => `${item.id}-${item.read}`)
              Column()
                .height(px2vp(this.bottomInsetPx) + 16)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14 })
          }
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .align(Alignment.Top)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .hideTitleBar(true)
  }
}

/** 消息详情 */
@Component
export struct NoticeDetailPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @State notice: NoticeItem = AppState.currentNotice !== null ? AppState.currentNotice : EMPTY_NOTICE;

  build() {
    NavDestination() {
      Column() {
        Row() {
          Text('‹')
            .fontSize(26)
            .fontColor($r('app.color.text_primary'))
            .width(34)
            .height(34)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              AppState.stack.pop();
            })

          Column() {
            Text('消息详情')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 6 })
          .layoutWeight(1)

          Blank()
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 10, right: 16, bottom: 14, top: px2vp(this.topInsetPx) + 10 })
        .backgroundColor($r('app.color.bg_page'))

        Scroll() {
          Column() {
            if (this.notice.id.length > 0) {
              Text(this.notice.title)
                .fontSize(19)
                .fontWeight(FontWeight.Bold)
                .lineHeight(28)
                .fontColor($r('app.color.text_primary'))
                .width('100%')

              Row() {
                Text(this.notice.source)
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                Text('·')
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ left: 6, right: 6 })
                Text(this.notice.date)
                  .fontSize(12)
                  .fontColor($r('app.color.text_tertiary'))
              }
              .width('100%')
              .margin({ top: 12, bottom: 14 })

              Divider()
                .color($r('app.color.divider'))

              Text(this.notice.content.length > 0 ? this.notice.content : '暂无详细内容，点击消息查看完整公告。')
                .fontSize(14)
                .lineHeight(26)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .margin({ top: 16 })
            } else {
              EmptyTip({ text: '消息内容不存在' })
            }

            Column()
              .height(px2vp(this.bottomInsetPx) + 24)
          }
          .width('100%')
          .padding({ left: 18, right: 18, top: 18 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .align(Alignment.Top)
        .backgroundColor($r('app.color.bg_card'))
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_card'))
    }
    .hideTitleBar(true)
  }
}