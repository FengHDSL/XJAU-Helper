/**
 * 农大新闻收藏页（Navigation 二级页）——展示收藏的新闻（纯文字行），点击进详情，支持取消收藏
 */
import { promptAction } from '@kit.ArkUI';
import { NewsApi, NewsItem } from '../api/NewsApi';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { DataStore } from '../common/DataStore';
import { Theme } from '../common/ThemeUtil';
import { WallpaperTone } from '../common/WallpaperTone';
import { Immersive } from './common/Immersive';
import { BackButton } from './common/BackButton';
import { WallpaperFill } from './common/WallpaperFill';

@Component
export struct NewsFavPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('barStyle') barStyle: string = 'new';
  @StorageProp('immersiveEffect') immersiveEffect: boolean = true;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 壁纸亮度（顶栏文字自适应用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  /** 收藏列表（NewsItem） */
  @State items: NewsItem[] = [];

  aboutToAppear(): void {
    this.reload();
  }

  /** 从 DataStore 读取收藏并解析为 NewsItem 列表 */
  private reload(): void {
    const raws: string[] = DataStore.loadNewsFavs();
    const list: NewsItem[] = [];
    for (const raw of raws) {
      try {
        const o: Record<string, string> = JSON.parse(raw) as Record<string, string>;
        const it: NewsItem = new NewsItem();
        it.title = o['title'] ?? '';
        it.url = o['url'] ?? '';
        it.date = o['date'] ?? '';
        it.thumb = o['thumb'] ?? '';
        if (it.url.length > 0) {
          list.push(it);
        }
      } catch (e) {
        // ignore
      }
    }
    this.items = list;
  }

  /** 取消收藏（按 url）并刷新列表 */
  private removeFav(item: NewsItem): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '取消收藏',
      message: '确定将该新闻从收藏中移除吗？',
      buttons: [
        { text: '取消', color: '#888888' },
        { text: '取消收藏', color: '#DB5252', primary: true }
      ]
    }).then((res) => {
      if (res.index === 1) {
        DataStore.removeNewsFav(item.url);
        this.getUIContext().getPromptAction().showToast({ message: '已取消收藏' });
        this.reload();
      }
    });
  }

  /** 打开新闻：本站走详情页，外链用 WebView 打开 */
  private openDetail(item: NewsItem): void {
    if (NewsApi.isLocalUrl(item.url)) {
      AppState.currentNewsUrl = item.url;
      AppState.stack.pushPath({ name: Const.ROUTE_NEWS_DETAIL });
    } else {
      AppState.webUrl = item.url;
      AppState.webTitle = '外部链接';
      AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
    }
  }

  build() {
    NavDestination() {
      // 二级页壁纸底层（无壁纸回 bg_page，不透下层）
      Stack({ alignContent: Alignment.TopStart }) {
        WallpaperFill()
      Column() {
        // 顶栏（两层）：内容(底)/主题渐变(顶)；模糊层已取消
        Stack({ alignContent: Alignment.TopStart }) {
          Column()
            .width('100%')
            .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
            .linearGradient({
              angle: 180,
              colors: Theme.barGradient(this.themeColor, this.barStyle)
            })
            .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, this.immersiveEffect && this.barStyle === 'legacy'))
        Row() {
          BackButton({ onBack: () => { AppState.stack.pop(); } })
          Text('我的收藏')
            .fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
            .margin({ left: 6 })
            .layoutWeight(1)
          Text('刷新')
            .fontSize(12)
            .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .backgroundColor('#33FFFFFF')
            .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, this.immersiveEffect))
            .borderRadius(14)
            .onClick(() => { this.reload(); })
        }
        .width('100%').alignItems(VerticalAlign.Center)
        .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
        .padding({ left: 16, right: 16, bottom: 12, top: this.getUIContext().px2vp(this.topInsetPx) + 12 })
        }
        .width('100%')

        if (this.items.length === 0) {
          Column() {
            Text('暂无收藏')
              .fontSize(14)
              .fontColor($r('app.color.text_tertiary'))
            Text('在新闻详情页点击"收藏"即可收藏')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 8 })
          }
          .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else {
          List({ space: 0 }) {
            ForEach(this.items, (item: NewsItem, i: number) => {
              ListItem() {
                Column() {
                  Row() {
                    Column() {
                      Text(item.title).fontSize(15).fontWeight(FontWeight.Medium)
                        .fontColor($r('app.color.text_primary')).maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                      Text(item.date).fontSize(11).fontColor($r('app.color.text_tertiary'))
                        .margin({ top: 6 }).width('100%')
                    }
                    .layoutWeight(1).alignItems(HorizontalAlign.Start)

                    // 取消收藏按钮
                    Text('取消')
                      .fontSize(12)
                      .fontColor('#DB5252')
                      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                      .backgroundColor('#14DB5252')
                      .borderRadius(12)
                      .margin({ left: 8 })
                      .onClick(() => { this.removeFav(item); })
                  }
                  .width('100%')
                  .padding({ left: 16, right: 16, top: 12, bottom: 12 })
                  .onClick(() => { this.openDetail(item); })

                  if (i < this.items.length - 1) {
                    Divider().color($r('app.color.divider')).margin({ left: 16, right: 16 })
                  }
                }
              }
            }, (item: NewsItem) => item.url)
          }
          .width('100%').layoutWeight(1)
          .scrollBar(BarState.Off).edgeEffect(EdgeEffect.Spring)
        }
      }
      .width('100%').height('100%')
      // 全局壁纸：二级页根背景透明，透出主框架底层壁纸（无壁纸时由 MainView 底层纯色兜底）
      .backgroundColor(Color.Transparent)
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.bg_page'))
    .hideTitleBar(true)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    .width('100%').height('100%')
  }
}
