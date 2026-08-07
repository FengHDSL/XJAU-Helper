/**
 * TodayScheduleCard2x2 — 今日课程桌面卡片（支持 1x2 / 2x2 两种尺寸）
 * 显示今天要上的课程：日期/星期 + 课程名 + 时间 + 教室。
 * 学期外时显示"距离开学 N 天"。
 *
 * 数据来源：EntryFormAbility 推送的 todayJson（今日课程数组的 JSON 字符串）。
 */
let localStorageToday = new LocalStorage();

@Entry(localStorageToday)
@Component
struct TodayScheduleCard2x2 {
  @LocalStorageProp('todayJson') todayJson: string = '[]';
  @LocalStorageProp('todayLabel') todayLabel: string = '';
  @LocalStorageProp('lastRefresh') lastRefresh: string = '';
  @LocalStorageProp('weekLabel') weekLabel: string = '';

  /** 解析 todayJson → [{name, time, room, color}] */
  private parseCourses(): CourseSlot[] {
    try {
      const arr: Object[] = JSON.parse(this.todayJson) as Object[];
      const out: CourseSlot[] = [];
      for (const it of arr) {
        const obj: Record<string, Object> = it as Record<string, Object>;
        out.push({
          name: (obj['n'] as string) ?? '',
          time: (obj['t'] as string) ?? '',
          room: (obj['r'] as string) ?? '',
          color: (obj['c'] as number) ?? 0
        });
      }
      return out;
    } catch (e) {
      return [];
    }
  }

  private coursesList(): CourseSlot[] {
    return this.parseCourses();
  }

  build() {
    Column() {
      // 顶部：标题 + 日期 + 装饰图标
      Row() {
        Text('今日课程')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1D1C')
        Blank()
        if (this.todayLabel.length > 0) {
          Text(this.todayLabel)
            .fontSize(11)
            .fontColor('#666666')
            .margin({ right: 4 })
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 6 })

      if (this.weekLabel.startsWith('距开学') || this.weekLabel === '即将开学') {
        // 学期外空态
        Column() {
          Text('学期未开始')
            .fontSize(13)
            .fontColor('#999999')
          Text(this.weekLabel.length > 0 ? this.weekLabel : '距离开学还有 N 天')
            .fontSize(11)
            .fontColor('#BBBBBB')
            .margin({ top: 4 })
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
        // 课程列表
        if (this.coursesList().length === 0) {
          Column() {
            Text('今日无课')
              .fontSize(14)
              .fontColor('#999999')
            Text('享受悠闲的一天 ☕')
              .fontSize(10)
              .fontColor('#BBBBBB')
              .margin({ top: 4 })
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
          Column() {
            ForEach(this.coursesList().slice(0, 4), (c: CourseSlot, idx: number) => {
              this.courseRow(c, idx)
            }, (c: CourseSlot, idx: number) => `c${idx}_${c.name}`)

            Blank()

            Text(this.lastRefresh)
              .fontSize(8)
              .fontColor('#BBBBBB')
              .width('100%')
              .textAlign(TextAlign.End)
          }
          .width('100%')
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          .onClick(() => {
            postCardAction(this, {
              action: 'router',
              abilityName: 'EntryAbility',
              params: { open: 'schedule' }
            });
          })
        }
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#F2FFFFFF')
    .borderRadius(16)
  }

  @Builder
  courseRow(c: CourseSlot, idx: number) {
    Row() {
      // 左侧色块（按课程名 hash 取色）
      Column()
        .width(4)
        .height(32)
        .borderRadius(2)
        .backgroundColor(this.bgColor(c.color))
        .margin({ right: 8 })
      // 中间：课程名 + 教室
      Column() {
        Text(c.name)
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1A1D1C')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
        Text(c.room)
          .fontSize(9)
          .fontColor('#888888')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .margin({ top: 1 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      Blank()
      // 右侧：时间
      Text(c.time)
        .fontSize(10)
        .fontColor('#2C5FA8')
        .flexShrink(0)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: 6 })
  }

  private bgColor(idx: number): string {
    const arr: string[] = ['#079841', '#26C485', '#2C5FA8', '#7B5FC9', '#E76FA1', '#FF9800', '#F4C724', '#5DADE2'];
    return arr[idx % 8];
  }
}

interface CourseSlot {
  name: string;
  time: string;
  room: string;
  color: number;
}
