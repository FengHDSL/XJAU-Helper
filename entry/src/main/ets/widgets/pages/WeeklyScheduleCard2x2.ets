/**
 * WeeklyScheduleCard2x2 — 周视图桌面卡片 2x2
 * 显示一整周的课程（7 天 × 每天最多 3 节课）。
 * 高级功能专属（显示课程名/时间/教室的精简版）。
 *
 * 数据来源：EntryFormAbility 推送的 weeklyJson（7 天课程数组的 JSON 字符串）。
 */
let localStorageWeek = new LocalStorage();

@Entry(localStorageWeek)
@Component
struct WeeklyScheduleCard2x2 {
  @LocalStorageProp('weekLabel') weekLabel: string = '';
  @LocalStorageProp('lastRefresh') lastRefresh: string = '';
  @LocalStorageProp('weeklyJson') weeklyJson: string = '[]';

  /** 解析 weeklyJson → 7 天 × 3 节课 */
  private parseDays(): string[][] {
    try {
      const arr: Object[] = JSON.parse(this.weeklyJson) as Object[];
      const out: string[][] = [];
      for (let i: number = 0; i < 7; i++) {
        const day: Object[] = (arr[i] as Object[]) ?? [];
        const items: string[] = [];
        for (const it of day) {
          const obj: Record<string, Object> = it as Record<string, Object>;
          const name: string = (obj['n'] as string) ?? '';
          const time: string = (obj['t'] as string) ?? '';
          const color: number = (obj['c'] as number) ?? 0;
          if (name.length > 0) {
            items.push(`${name}#${color}#${time}`);
          }
        }
        out.push(items);
      }
      return out;
    } catch (e) {
      return [[], [], [], [], [], [], []];
    }
  }

  private daysLength(): number {
    return 7;
  }

  private dayItemCount(dayIdx: number): number {
    const days: string[][] = this.parseDays();
    if (dayIdx < 0 || dayIdx >= days.length) {
      return 0;
    }
    return days[dayIdx].length;
  }

  private dayItemAt(dayIdx: number, itemIdx: number): string[] {
    const days: string[][] = this.parseDays();
    if (dayIdx < 0 || dayIdx >= days.length) {
      return ['', '0', ''];
    }
    const item: string = days[dayIdx][itemIdx] ?? '';
    return item.split('#');
  }

  private dayLabelsList(): string[] {
    return ['一', '二', '三', '四', '五', '六', '日'];
  }

  @Builder
  weekCell(dayIdx: number, itemIdx: number) {
    Text(this.cellText(dayIdx, itemIdx))
      .fontSize(8)
      .fontColor('#FFFFFF')
      .fontWeight(FontWeight.Medium)
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .width('100%')
      .height(18)
      .textAlign(TextAlign.Center)
      .backgroundColor(this.bgColor(this.cellColor(dayIdx, itemIdx)))
      .borderRadius(3)
      .padding({ left: 2, right: 2 })
      .margin({ bottom: 1 })
  }

  private cellText(dayIdx: number, itemIdx: number): string {
    const parts: string[] = this.dayItemAt(dayIdx, itemIdx);
    return parts[0] ?? '';
  }

  private cellColor(dayIdx: number, itemIdx: number): number {
    const parts: string[] = this.dayItemAt(dayIdx, itemIdx);
    return Number.parseInt(parts[1] ?? '0', 10);
  }

  build() {
    Column() {
      // 顶部：周次标签 + 数字徽标
      Row() {
        Row() {
          Text('周视图')
            .fontSize(13)
            .fontWeight(FontWeight.Bold)
            .fontColor('#1A1D1C')
        }
        .alignItems(VerticalAlign.Center)
        Blank()
        Text(this.weekLabel)
          .fontSize(10)
          .fontColor('#888888')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 6 })
      if (this.weeklyJson === '[]' || this.weeklyJson.length === 0 ||
        this.weekLabel.startsWith('距开学') || this.weekLabel === '即将开学' ||
        this.weekLabel === '已放假') {
        // 空态
        Column() {
          Text('暂无课程数据')
            .fontSize(11)
            .fontColor('#999999')
          Text('点击进入应用课表')
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
        // 7 天 × 3 行网格
        Row() {
          ForEach(this.dayLabelsList(), (label: string, i: number) => {
            Column() {
              // 星期标题
              Text(`周${label}`)
                .fontSize(8)
                .fontColor('#666666')
                .margin({ bottom: 2 })
              // 3 个课程格（每天最多 3 节）
              ForEach([0, 1, 2], (row: number) => {
                if (i < this.daysLength() && row < this.dayItemCount(i)) {
                  this.weekCell(i, row)
                } else {
                  // 空槽：浅灰底
                  Column()
                    .width('100%')
                    .height(18)
                    .backgroundColor('#F5F5F5')
                    .borderRadius(3)
                    .margin({ bottom: 1 })
                }
              }, (row: number) => `r${i}_${row}`)
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Center)
          }, (label: string, i: number) => `d${i}`)
        }
        .width('100%')
        .layoutWeight(1)
        .alignItems(VerticalAlign.Top)

        Row() {
          Text(this.lastRefresh)
            .fontSize(8)
            .fontColor('#BBBBBB')
        }
        .width('100%')
        .margin({ top: 4 })
      }
    }
    .width('100%')
    .height('100%')
    .padding(10)
    .backgroundColor('#F2FFFFFF')
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, {
        action: 'router',
        abilityName: 'EntryAbility',
        params: { open: 'schedule' }
      });
    })
  }

  /** 8 色色板（与 Const.COURSE_BG 对齐：1=草绿, 2=青, 3=蓝, 4=紫, 5=粉, 6=橙, 7=黄, 0=深绿） */
  private bgColor(idx: number): string {
    const arr: string[] = ['#079841', '#26C485', '#2C5FA8', '#7B5FC9', '#E76FA1', '#FF9800', '#F4C724', '#5DADE2'];
    return arr[idx % 8];
  }
}
