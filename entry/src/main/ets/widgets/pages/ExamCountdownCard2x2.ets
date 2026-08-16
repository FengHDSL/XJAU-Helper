/**
 * ExamCountdownCard2x2 — 考试倒计时桌面卡片 2x2（移植自 HiXD）
 *
 * 数据来源（EntryFormAbility 推送）：
 *  - 优先显示用户主动选择的考试（持久化在 DataStore.KEY_PICKED_EXAM）
 *  - 用户没选时，显示最近一场未开始的考试
 *  - 没有任何考试安排时：显示一个示例作为演示
 *
 * 交互：点击卡片跳转到「考试安排」页面，让用户挑选要倒计时的考试。
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
  @LocalStorageProp('isDemo') isDemo: boolean = false;
  @LocalStorageProp('lastRefresh') lastRefresh: string = '';

  /** 跳转到「考试安排」页面，并打开挑选弹窗 */
  private openExamPicker(): void {
    postCardAction(this, {
      action: 'router',
      abilityName: 'EntryAbility',
      params: { open: 'exam-pick' }
    });
  }

  build() {
    Column() {
      // 顶部行：标题 + 更新时间
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
        // 正常展示：倒计时数字 + 课程名 + 时间 + 教室
        Text(this.examDays)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FF9800')
          .margin({ top: 2 })
          .textAlign(TextAlign.Center)

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
      } else if (this.isDemo) {
        // 空态但有示例数据：演示卡片（让用户知道点击后会进入选择页）
        // 半透效果区分
        Text(this.examDays)
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFB74D')
          .opacity(0.85)
          .margin({ top: 2 })
          .textAlign(TextAlign.Center)

        Text(this.examName)
          .fontSize(11)
          .fontWeight(FontWeight.Medium)
          .fontColor('#888888')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 2 })

        Text(this.examTime)
          .fontSize(8)
          .fontColor('#AAAAAA')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 2 })

        Text(this.examLocation)
          .fontSize(8)
          .fontColor('#BBBBBB')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 2 })

        Text('点击选择要倒计时的考试')
          .fontSize(8)
          .fontColor('#2C5FA8')
          .margin({ top: 4 })
          .textAlign(TextAlign.Center)
      } else {
        // 真正空态：无任何考试安排（既无真实也无示例）
        Column() {
          Text('暂无考试安排')
            .fontSize(12)
            .fontColor('#999999')
          Text('点击选择要倒计时的考试')
            .fontSize(9)
            .fontColor('#2C5FA8')
            .margin({ top: 4 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#F2FFFFFF')
    .borderRadius(16)
    .onClick(() => {
      // 整个卡片都可点击，进入 ExamPage 选考试
      this.openExamPicker();
    })
  }
}
