/**
 * ExamCountdownCard2x2 — 考试倒计时桌面卡片 2x2（移植自 HiXD）
 * 展示最近一场考试的科目、倒计时、时间与地点，点击卡片刷新。
 */
let localStorageExam = new LocalStorage();

@Entry(localStorageExam)
@Component
struct ExamCountdownCard2x2 {
  @LocalStorageProp('examName') examName: string = '';
  @LocalStorageProp('examDays') examDays: string = '';
  @LocalStorageProp('examTime') examTime: string = '';
  @LocalStorageProp('examLocation') examLocation: string = '';
  @LocalStorageProp('hasExam') hasExam: boolean = false;
  @LocalStorageProp('lastRefresh') lastRefresh: string = '';

  build() {
    Column() {
      Row() {
        Text('考试倒计时')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#1A1D1C')
        Blank()
        Text(this.lastRefresh)
          .fontSize(8)
          .fontColor('#BBBBBB')
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 4 })

      if (this.hasExam) {
        // 倒计时主数字
        Text(this.examDays)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FF9800')
          .margin({ top: 2 })

        Text(this.examName)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#1A1D1C')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 2 })

        Text(this.examTime)
          .fontSize(8)
          .fontColor('#666666')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 2 })

        Text(this.examLocation)
          .fontSize(8)
          .fontColor('#888888')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 2 })
      } else {
        Column() {
          Text('暂无考试安排')
            .fontSize(12)
            .fontColor('#999999')
          Text('点击刷新')
            .fontSize(9)
            .fontColor('#BBBBBB')
            .margin({ top: 4 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#F2FFFFFF')
    .borderRadius(16)
    .onClick(() => {
      postCardAction(this, { action: 'message', params: { msgTest: 'refresh' } });
    })
  }
}
