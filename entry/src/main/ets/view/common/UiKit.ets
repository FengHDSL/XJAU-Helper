/**
 * 通用小组件：卡片标题、标签、空状态、加载中、统计格
 */
import { Theme } from '../../common/ThemeUtil';
import { Immersive } from './Immersive';
import { WallpaperTone } from '../../common/WallpaperTone';
import { BackButton } from './BackButton';

/** 区块标题：左侧竖条 + 标题 + 右侧操作 */
@Component
export struct SectionHeader {
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  @StorageProp('barStyle') barStyle: string = 'new';
  @StorageProp('subtitleColor') subtitleColor: string = '';
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
          .color(Theme.colorOf(this.themeColor))
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
            .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
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
  color: ResourceColor = $r('app.color.brand');
  bg: ResourceColor = $r('app.color.brand_light');

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
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('barStyle') barStyle: string = 'new';
  @StorageProp('subtitleColor') subtitleColor: string = '';
  @Prop icon: string = '';
  @Prop text: string = '正在同步教务数据…';

  build() {
    Column() {
      LoadingProgress()
        .width(36)
        .height(36)
        .color(Theme.colorOf(this.themeColor))
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
  color: ResourceColor = $r('app.color.text_primary');

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
  @Prop valueColor: ResourceColor = $r('app.color.text_tertiary');
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

/** 选择行（点击弹选择器）。value 用 @Prop 单向同步：父组件 @State 变化后文本实时刷新
 *  （与 SettingRow 同款响应式机制；不能用 @Builder 值传递，否则状态更新后显示不刷新）
 *  value 过长（多选结果）时 Marquee 滚动显示，避免溢出屏幕 */
@Component
export struct PickRow {
  @Prop label: string = '';
  @Prop value: string = '';
  @Prop placeholder: string = '';
  onTap: () => void = () => {
  };

  build() {
    Row() {
      Text(this.label)
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width(86)
      Blank()
      Text(this.value.length > 0 ? this.value : this.placeholder)
        .fontSize(13)
        .fontColor(this.value.length > 0 ? $r('app.color.text_primary') : $r('app.color.text_tertiary'))
        .layoutWeight(1)
        .maxLines(1)
        .textAlign(TextAlign.End)
        .textOverflow({ overflow: TextOverflow.MARQUEE })
      Text('›')
        .fontSize(16)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ left: 6 })
    }
    .width('100%')
    .height(46)
    .padding({ left: 10, right: 10 })
    .backgroundColor($r('app.color.bg_chip'))
    .borderRadius(10)
    .margin({ bottom: 10 })
    .onClick(() => {
      this.onTap();
    })
  }
}

/** 二级页面统一头部（简约白底 + 返回）；可选右侧按钮（actionText + onAction） */
@Component
/**
 * 统一顶栏标题：大标题固定同一高度（所有页面顶端对齐），副标题独立一行位于其下。
 */
@Component
export struct BarTitle {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  /** 长标题是否跑马灯滚动（默认省略号） */
  @Prop marquee: boolean = false;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('barStyle') barStyle: string = 'new';
  @StorageProp('subtitleColor') subtitleColor: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 壁纸亮度（顶栏文字自适应用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;

  /** 顶栏文字颜色：始终按壁纸明暗自适应（两档顶栏样式均生效） */
  private titleColor(): ResourceColor {
    return WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode);
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.titleColor())
        .height(28)
        .lineHeight(28)
        .maxLines(1)
        .textOverflow({ overflow: this.marquee ? TextOverflow.MARQUEE : TextOverflow.Ellipsis })
      if (this.subtitle.length > 0) {
        Text(this.subtitle)
          .fontSize(11)
          .height(15)
          .lineHeight(15)
          .fontColor(this.subtitleColor.length > 0 ? this.subtitleColor :
            WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
          .margin({ top: 2 })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Start)
  }
}

@Component
export struct PageHeader {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  /** 壁纸亮度（文字自适应用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('immersiveEffect') immersiveEffect: boolean = true;
  @StorageProp('barStyle') barStyle: string = 'new';
  @StorageProp('subtitleColor') subtitleColor: string = '';
  @Prop title: string = '';
  @Prop subtitle: string = '';
  /** 右侧按钮文字（空 = 不显示按钮） */
  @Prop actionText: string = '';
  /** 按钮色调：'red'=警示红（默认，用于清空等）/ 'theme'=主题色（用于刷新等中性操作） */
  @Prop actionTone: string = 'red';
  /** 右侧是否显示收集开关（Toggle；与 actionText 可并存） */
  @Prop showActionToggle: boolean = false;
  /** 收集开关状态 */
  @Prop actionToggleOn: boolean = false;
  /** 开关标签文字（空 = 沿用默认「收集中 / 已暂停」，可用于「深色 / 浅色」等通用开关） */
  @Prop actionToggleLabel: string = '';
  onBack: () => void = () => {
  };
  onAction: () => void = () => {
  };
  onActionToggle: (on: boolean) => void = () => {
  };

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 中：全透明模糊层（已取消：见用户要求）
      // 顶：主题色渐变（最上层视觉）
      Column()
        .width('100%')
        .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
        .linearGradient({
          angle: 180,
          colors: Theme.barGradient(this.themeColor, this.barStyle)
        })
        .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, this.immersiveEffect && this.barStyle === 'legacy'))
      Row() {
        // 官方风格圆形返回按钮
        BackButton({
        onBack: () => {
          this.onBack();
        }
      })

      BarTitle({ title: this.title, subtitle: this.subtitle })
        .margin({ left: 6 })

      Blank()

      // 右侧操作区：文字按钮（红底白字）与收集开关可并存（如日志页：清空 + 开关）
      if (this.showActionToggle) {
        Row() {
          Text(this.actionToggleLabel.length > 0 ? this.actionToggleLabel : (this.actionToggleOn ? '收集中' : '已暂停'))
            .fontSize(11)
            .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
            .margin({ right: 8 })
          Toggle({ type: ToggleType.Switch, isOn: this.actionToggleOn })
            .selectedColor(Theme.colorOf(this.themeColor))
            .onChange((on: boolean) => {
              this.onActionToggle(on);
            })
        }
      }
      if (this.actionText.length > 0) {
        Text(this.actionText)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
          .padding({ left: 14, right: 14, top: 5, bottom: 5 })
          .backgroundColor(this.actionTone === 'theme' ? Theme.colorOf(this.themeColor) :
            (this.actionTone === 'glass' ? '#33FFFFFF' : '#DB5252'))
          .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, this.immersiveEffect))
          .borderRadius(14)
          .margin({ left: 10 })
          .onClick(() => {
            this.onAction();
          })
      }
    }
      .width('100%')
      .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
      .alignItems(VerticalAlign.Top)
      .padding({ left: 10, right: 16, bottom: 12, top: this.getUIContext().px2vp(this.topInsetPx) + 12 })
    }
    .width('100%')
    .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
  }
}
