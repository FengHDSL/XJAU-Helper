/**
 * ClassPreviewCard2x2 — 课程预告桌面卡片 2x2（移植自 HiXD）
 * 通过 LocalStorage 接收 EntryFormAbility 推送的平面数据。
 *
 * 顶部右上"日期胶囊"循环切换：
 *   今天 → 明天 → 下次有课日（M月D日）→ 今天
 * 跳过当前周次下无课程的那一组（避免空内容切过去）。
 *
 * 点击跳转到应用内"课程表"页面（按 open='schedule'）。
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
  @LocalStorageProp('nextDayNames') nextDayNames: string[] = [];
  @LocalStorageProp('nextDayTimes') nextDayTimes: string[] = [];
  @LocalStorageProp('nextDayRooms') nextDayRooms: string[] = [];
  @LocalStorageProp('nextDayCount') nextDayCount: number = 0;
  @LocalStorageProp('weekLabel') weekLabel: string = '';
  @LocalStorageProp('dateLabel') dateLabel: string = '';
  @LocalStorageProp('dayLabel') dayLabel: string = '今天';
  @LocalStorageProp('dayLabelTomorrow') dayLabelTomorrow: string = '明天';
  @LocalStorageProp('dayLabelNextDay') dayLabelNextDay: string = '';
  @LocalStorageProp('lastRefresh') lastRefresh: string = '';
  @LocalStorageProp('isEmpty') isEmpty: boolean = true;
  @LocalStorageProp('currentView') currentView: number = 0;

  /** 当前视图对应的课程数组 */
  private curNames(): string[] {
    if (this.currentView === 0) {
      return this.todayNames;
    }
    if (this.currentView === 1) {
      return this.tomorrowNames;
    }
    return this.nextDayNames;
  }

  private curTimes(): string[] {
    if (this.currentView === 0) {
      return this.todayTimes;
    }
    if (this.currentView === 1) {
      return this.tomorrowTimes;
    }
    return this.nextDayTimes;
  }

  private curRooms(): string[] {
    if (this.currentView === 0) {
      return this.todayRooms;
    }
    if (this.currentView === 1) {
      return this.tomorrowRooms;
    }
    return this.nextDayRooms;
  }

  private curCount(): number {
    if (this.currentView === 0) {
      return this.todayCount;
    }
    if (this.currentView === 1) {
      return this.tomorrowCount;
    }
    return this.nextDayCount;
  }

  /** 当前视图对应的日期胶囊文字 */
  private curDayLabel(): string {
    if (this.currentView === 0) {
      return this.dayLabel.length > 0 ? this.dayLabel : '今天';
    }
    if (this.currentView === 1) {
      return this.dayLabelTomorrow.length > 0 ? this.dayLabelTomorrow : '明天';
    }
    return this.dayLabelNextDay.length > 0 ? this.dayLabelNextDay : 'M月D日';
  }

  /**
   * 卡片一行课程：课程名 + 时间一行 + 教室一行
   */
  @Builder
  rowItem(name: string, time: string, room: string) {
    Column() {
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
          .margin({ top: 1 })
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 4 })
  }

  build() {
    Column() {
      // 顶部行：标题 + 数字徽标（左对齐） + 日期胶囊（右对齐）
      Row() {
        // 标题区
        Row() {
          Text('课程预告')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1D1C')
          // 数字徽标：固定宽度 + 高度 + 居中对齐
          Text(` ${this.curCount()} `)
            .fontSize(10)
            .fontColor('#FFFFFF')
            .backgroundColor('#2C5FA8')
            .height(16)
            .constraintSize({ minWidth: 18 })
            .borderRadius(8)
            .textAlign(TextAlign.Center)
            .padding({ left: 5, right: 5 })
            .margin({ left: 4 })
        }
        .alignItems(VerticalAlign.Center)

        Blank()

        // 右上"日期 + 箭头"胶囊：文字与箭头中线对齐（统一 lineHeight + row 垂直居中）
        Row() {
          Text(this.curDayLabel())
            .fontSize(10)
            .fontWeight(FontWeight.Medium)
            .fontColor('#2C5FA8')
            .lineHeight(13)
          Text(this.currentView === 1 ? '  ‹' : '  ›')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor('#2C5FA8')
            .lineHeight(13)
        }
        .height(20)
        .padding({ left: 8, right: 8 })
        .borderRadius(10)
        .backgroundColor('rgba(44,95,168,0.10)')
        .alignItems(VerticalAlign.Center)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          postCardAction(this, { action: 'message', params: { msgTest: 'toggle' } });
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 4 })

      // 内容区
      if (this.isEmpty) {
        // 空态：突出提示，点击进入应用课程表
        Column() {
          Text('暂无课程数据')
            .fontSize(11)
            .fontColor('#999999')
          Text('点击进入应用课程表')
            .fontSize(8)
            .fontColor('#BBBBBB')
            .margin({ top: 2 })
          Text(this.lastRefresh)
            .fontSize(8)
            .fontColor('#BBBBBB')
            .margin({ top: 6 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: { open: 'schedule' }
          });
        })
      } else {
        // 课程列表（最多展示 2 条）
        ForEach(this.curNames().slice(0, 2), (name: string, index: number) => {
          this.rowItem(name, this.curTimes()[index] ?? '', this.curRooms()[index] ?? '')
        }, (name: string, index: number) => `${index}_${name}`)

        Blank()

        Row() {
          Text(`${this.weekLabel} · ${this.curDayLabel()}`)
            .fontSize(8)
            .fontColor('#999999')
          Blank()
          Text(this.lastRefresh)
            .fontSize(8)
            .fontColor('#BBBBBB')
        }
        .width('100%')
        .margin({ top: 4 })
        .onClick(() => {
          // 列表区域点击：跳应用课程表
          postCardAction(this, {
            action: 'router',
            abilityName: 'EntryAbility',
            params: { open: 'schedule' }
          });
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#F2FFFFFF')
    .borderRadius(16)
  }
}