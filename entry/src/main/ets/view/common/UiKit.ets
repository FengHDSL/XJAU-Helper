/**
 * 通用小组件：卡片标题、标签、空状态、加载中、统计格
 */
import { Theme } from '../../common/ThemeUtil';

/** 区块标题：左侧竖条 + 标题 + 右侧操作 */
@Component
export struct SectionHeader {
  @Prop title: string = '';
  @Prop action: string = '';
  onAction: () => void = () => {
  };

  build() {
    Row() {
      Row() {
        Divider()
          .vertical(true)
          .strokeWidth(3)
          .color($r('app.color.brand'))
          .height(14)
          .margin({ right: 8 })
        Text(this.title)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }

      Blank()

      if (this.action.length > 0) {
        Row() {
          Text(this.action)
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
          Text('›')
            .fontSize(14)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ left: 2 })
        }
        .onClick(() => {
          this.onAction();
        })
      }
    }
    .width('100%')
    .padding({ bottom: 10 })
  }
}

/** 彩色小标签 */
@Component
export struct TagChip {
  @Prop text: string = '';
  color: Resource = $r('app.color.brand');
  bg: Resource = $r('app.color.brand_light');

  build() {
    Text(this.text)
      .fontSize(10)
      .fontColor(this.color)
      .backgroundColor(this.bg)
      .borderRadius(4)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
  }
}

/** 空状态 */
@Component
export struct EmptyTip {
  @Prop icon: string = '';
  @Prop text: string = '暂无数据';

  build() {
    Column() {
      if (this.icon.length > 0) {
        Text(this.icon)
          .fontSize(40)
          .margin({ bottom: 10 })
      }
      Text(this.text)
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 40, bottom: 40 })
    .justifyContent(FlexAlign.Center)
  }
}

/** 加载中 */
@Component
export struct LoadingTip {
  @Prop icon: string = '';
  @Prop text: string = '正在同步教务数据…';

  build() {
    Column() {
      LoadingProgress()
        .width(36)
        .height(36)
        .color($r('app.color.brand'))
      Text(this.text)
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 10 })
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 40, bottom: 40 })
    .justifyContent(FlexAlign.Center)
  }
}

/** 统计格：数值 + 说明 */
@Component
export struct StatCell {
  @Prop value: string = '';
  @Prop label: string = '';
  color: Resource = $r('app.color.text_primary');

  build() {
    Column() {
      Text(this.value)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.color)
      Text(this.label)
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }
}

/** 设置项 */
@Component
export struct SettingRow {
  @Prop icon: string = '';
  @Prop title: string = '';
  @Prop value: string = '';
  @Prop showArrow: boolean = true;
  @Prop titleColor: Resource = $r('app.color.text_primary');
  @Prop valueColor: Resource = $r('app.color.text_tertiary');
  onTap: () => void = () => {
  };

  build() {
    Row() {
      if (this.icon.length > 0) {
        Text(this.icon)
          .fontSize(16)
          .width(28)
      }
      Text(this.title)
        .fontSize(15)
        .fontColor(this.titleColor)
      Blank()
      Text(this.value)
        .fontSize(13)
        .fontColor(this.valueColor)
      if (this.showArrow) {
        Text('›')
          .fontSize(16)
          .fontColor(this.valueColor)
          .margin({ left: 6 })
      }
    }
    .width('100%')
    .height(52)
    .onClick(() => {
      this.onTap();
    })
  }
}

/** 二级页面统一头部（简约白底 + 返回） */
@Component
export struct PageHeader {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('themeColor') themeColor: string = 'green';
  @Prop title: string = '';
  @Prop subtitle: string = '';
  onBack: () => void = () => {
  };

  build() {
    Row() {
      Text('‹')
        .fontSize(26)
        .fontColor(Color.White)
        .width(34)
        .height(34)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.onBack();
        })

      Column() {
        Text(this.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Color.White)
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(11)
            .fontColor(this.isDarkMode ? $r('app.color.text_tertiary') : '#CCFFFFFF')
            .margin({ top: 3 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 6 })

      Blank()
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ left: 10, right: 16, bottom: 12, top: px2vp(this.topInsetPx) + 12 })
    .backgroundColor(this.isDarkMode ? '#1A1D1C' : Theme.colorOf(this.themeColor))
  }
}
