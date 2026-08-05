/**
 * ClassPreviewCard2x2 — 课程预告桌面卡片 2x2（移植自 HiXD）
 * 通过 LocalStorage 接收 EntryFormAbility 推送的平面数据，
 * postCardAction 与卡片交互：↔ 切换今天/明天。
 */
let localStorage2x2 = new LocalStorage();

@Entry(localStorage2x2)
@Component
struct ClassPreviewCard2x2 {
  @LocalStorageProp('todayNames') todayNames: string[] = [];
  @LocalStorageProp('todayTimes') todayTimes: string[] = [];
  @LocalStorageProp('todayRooms') todayRooms: string[] = [];
  @LocalStorageProp('todayCount') todayCount: number = 0;
  @LocalStorageProp('tomorrowNames') tomorrowNames: string[] = [];
  @LocalStorageProp('tomorrowTimes') tomorrowTimes: string[] = [];
  @LocalStorageProp('tomorrowRooms') tomorrowRooms: string[] = [];
  @LocalStorageProp('tomorrowCount') tomorrowCount: number = 0;
  @LocalStorageProp('weekLabel') weekLabel: string = '';
  @LocalStorageProp('dateLabel') dateLabel: string = '';
  @LocalStorageProp('lastRefresh') lastRefresh: string = '';
  @LocalStorageProp('isEmpty') isEmpty: boolean = true;
  @LocalStorageProp('showTomorrow') showTomorrow: boolean = false;

  private curNames(): string[] {
    return this.showTomorrow ? this.tomorrowNames : this.todayNames;
  }

  private curTimes(): string[] {
    return this.showTomorrow ? this.tomorrowTimes : this.todayTimes;
  }

  private curRooms(): string[] {
    return this.showTomorrow ? this.tomorrowRooms : this.todayRooms;
  }

  private curCount(): number {
    return this.showTomorrow ? this.tomorrowCount : this.todayCount;
  }

  @Builder
  rowItem(name: string, time: string, room: string) {
    Row() {
      Text(name)
        .fontSize(11)
        .fontWeight(FontWeight.Bold)
        .fontColor('#1A1D1C')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
        .margin({ right: 4 })
      Text(time)
        .fontSize(9)
        .fontColor('#2C5FA8')
        .flexShrink(0)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)

    if (room.length > 0) {
      Text(room)
        .fontSize(8)
        .fontColor('#888888')
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ left: 2 })
        .margin({ bottom: 2 })
    }
  }

  build() {
    Column() {
      Row() {
        Text('课程预告')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1D1C')
        Text(` ${this.curCount()}`)
          .fontSize(9)
          .fontColor('#FFFFFF')
          .backgroundColor('#2C5FA8')
          .height(14)
          .borderRadius(7)
          .textAlign(TextAlign.Center)
          .padding({ left: 3, right: 3 })
        Blank()
        // 今天/明天切换
        Row() {
          Text(this.showTomorrow ? '←' : '→')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor('#2C5FA8')
        }
        .width(22)
        .height(22)
        .borderRadius(11)
        .backgroundColor('rgba(44,95,168,0.10)')
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          postCardAction(this, { action: 'message', params: { msgTest: 'toggle' } });
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 2 })

      if (this.isEmpty) {
        // 无数据：显示空态，点击刷新
        Column() {
          Text('暂无课程数据')
            .fontSize(11)
            .fontColor('#999999')
          Text(this.lastRefresh)
            .fontSize(8)
            .fontColor('#BBBBBB')
            .margin({ top: 2 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          postCardAction(this, { action: 'message', params: { msgTest: 'toggle' } });
        })
      } else {
        // 课程列表（最多展示 2 条）
        ForEach(this.curNames().slice(0, 2), (name: string, index: number) => {
          this.rowItem(name, this.curTimes()[index] ?? '', this.curRooms()[index] ?? '')
        }, (name: string, index: number) => `${index}_${name}`)

        Blank()

        Row() {
          Text(`${this.weekLabel} · ${this.dateLabel}`)
            .fontSize(8)
            .fontColor('#999999')
          Blank()
          Text(this.lastRefresh)
            .fontSize(8)
            .fontColor('#BBBBBB')
        }
        .width('100%')
        .margin({ top: 2 })
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#F2FFFFFF')
    .borderRadius(16)
  }
}
