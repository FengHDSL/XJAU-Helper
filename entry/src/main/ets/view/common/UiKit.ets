/**
 * 通用小组件：卡片标题、标签、空状态、加载中、统计格
 *
 * SectionHeader / SettingRow / BarTitle 的标题接入全局字体设置
 * （移植自参考项目 miha_hm `pages/FontManagePage.ets` 的字体应用逻辑）：
 *   fontWeightMode/fontWeightValue/fontFamilyZh/fontFamilyEn 变化即时刷新。
 */
import { Theme } from '../../common/ThemeUtil';
import { AppearanceStore } from '../../common/AppearanceStore';
import { Immersive } from './Immersive';
import { GlassMaterial } from '../../common/GlassMaterial';
import { MaterialButton } from './MaterialButton';
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
  // ── 字体管理联动（字体管理页设置后全局生效；这几个键用于登记依赖）──
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  @StorageProp('fontFamilyZh') ffZh: string = '';
  @StorageProp('fontFamilyEn') ffEn: string = '';
  @Prop title: string = '';
  @Prop action: string = '';
  onAction: () => void = () => {
  };

  /** 标题字体族：读 this.ffZh/this.ffEn 登记依赖（字体族切换即时刷新）；空串=跟随系统 */
  private titleFontFamily(): string {
    return AppearanceStore.hasCjk(this.title) ? this.ffZh : this.ffEn;
  }

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
          // 表达式必须读 this.fwMode 才登记依赖（静态函数内读 AppStorage 不登记）
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontFamily(this.titleFontFamily())
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
            .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
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
        .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
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
        .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
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
  /** 全局字重响应式订阅：表达式读 this.fwMode 才登记依赖，fwValue 声明即订阅 */
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;

  build() {
    Column() {
      Text(this.value)
        .fontSize(20)
        // 表达式必须读 this.fwMode 才登记依赖（静态函数内读 AppStorage 不登记）
        .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
        .fontColor(this.color)
      Text(this.label)
        .fontSize(11)
        .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
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
  // ── 字体管理联动（登记依赖，字体管理页改动后本行实时刷新）──
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  @StorageProp('fontFamilyZh') ffZh: string = '';
  @StorageProp('fontFamilyEn') ffEn: string = '';
  onTap: () => void = () => {
  };

  /** 标题字体族：读 this.ffZh/this.ffEn 登记依赖（字体族切换即时刷新）；空串=跟随系统 */
  private titleFontFamily(): string {
    return AppearanceStore.hasCjk(this.title) ? this.ffZh : this.ffEn;
  }

  build() {
    Row() {
      if (this.icon.length > 0) {
        Text(this.icon)
          .fontSize(16)
          .width(28)
      }
      Text(this.title)
        .fontSize(15)
        // 表达式必须读 this.fwMode 才登记依赖（静态函数内读 AppStorage 不登记）
        .fontWeight(this.fwMode === 'follow' ? FontWeight.Normal : AppearanceStore.fontWeight(FontWeight.Normal))
        .fontFamily(this.titleFontFamily())
        .fontColor(this.titleColor)
      Blank()
      Text(this.value)
        .fontSize(13)
        .fontColor(GlassMaterial.grayTertiary(this.valueColor))
      if (this.showArrow) {
        Text('›')
          .fontSize(16)
          .fontColor(GlassMaterial.grayTertiary(this.valueColor))
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
  /** 卡片沾色底色（广播键）：沾色开关变化时由 AppearanceStore.broadcastDerived() 重写 */
  @StorageProp('cardTintBg') tintBg: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  onTap: () => void = () => {
  };

  build() {
    Row() {
      Text(this.label)
        .fontSize(13)
        .fontColor(GlassMaterial.graySecondary($r('app.color.text_secondary')))
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
        .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
        .margin({ left: 6 })
    }
    .width('100%')
    .height(46)
    .padding({ left: 10, right: 10 })
    // 玻璃底（半透明，磨砂才可见；开关关闭时回落原 bg_chip 实色）。
    // 沾色广播键优先：拨「卡片沾色」开关时本行底色即时刷新。
    .backgroundColor(this.tintBg.length > 0
      ? this.tintBg
      : GlassMaterial.cardBg($r('app.color.bg_chip'), this.isDarkMode))
    // 玻璃质感：磨砂 + 亮边 + 微阴影 + 圆角裁剪
    .backgroundBlurStyle(GlassMaterial.cardBlur())
    .border({ width: GlassMaterial.cardBorderWidth(), color: GlassMaterial.borderColor() })
    .shadow(GlassMaterial.cardShadowStyle())
    .clip(true)
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
  /** 副标题右侧是否显示下拉图标（学期选择入口） */
  @Prop showChevron: boolean = false;
  /** 副标题（学年学期）点击回调（如打开学期选择） */
  onSubtitleTap: () => void = () => {
  };
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('barStyle') barStyle: string = 'new';
  @StorageProp('subtitleColor') subtitleColor: string = '';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 壁纸亮度（顶栏文字自适应用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  // ── 字体管理联动（字体管理页设置后，各页顶栏标题实时刷新）──
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  @StorageProp('fontFamilyZh') ffZh: string = '';
  @StorageProp('fontFamilyEn') ffEn: string = '';

  /** 顶栏文字颜色：始终按壁纸明暗自适应（两档顶栏样式均生效） */
  private titleColor(): ResourceColor {
    return WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode);
  }

  /** 标题字体族：读 this.ffZh/this.ffEn 登记依赖（字体族切换即时刷新）；空串=跟随系统 */
  private titleFontFamily(): string {
    return AppearanceStore.hasCjk(this.title) ? this.ffZh : this.ffEn;
  }

  build() {
    Column() {
      Text(this.title)
        .fontSize(20)
        // 表达式必须读 this.fwMode 才登记依赖（静态函数内读 AppStorage 不登记）
        .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
        .fontFamily(this.titleFontFamily())
        .fontColor(this.titleColor())
        .height(28)
        .lineHeight(28)
        .maxLines(1)
        .textOverflow({ overflow: this.marquee ? TextOverflow.MARQUEE : TextOverflow.Ellipsis })
      if (this.subtitle.length > 0) {
        Row() {
          Text(this.subtitle)
            .fontSize(11)
            .height(15)
            .lineHeight(15)
            .fontColor(this.subtitleColor.length > 0 ? this.subtitleColor :
              WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
          if (this.showChevron) {
            Image($r('app.media.list_bullet'))
              .width(14)
              .height(14)
              .fillColor(this.subtitleColor.length > 0 ? this.subtitleColor :
                WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
              .margin({ left: 3 })
          }
        }
        .height(15)
        .alignItems(VerticalAlign.Center)
        .margin({ top: 2 })
        .onClick(() => {
          this.onSubtitleTap();
        })
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
      // 整体高 34 与左侧返回按钮一致 → 中心中线对齐
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
        .height(34)
        .alignItems(VerticalAlign.Center)
      }
      if (this.actionText.length > 0) {
        // 顶栏操作按钮：沉浸光感**常驻**（btnPersistent=true，不随全局开关/按压消失），
        // 且保留原色语义：theme=主题色 / red=警示红（经 btnTint 叠层与材质共存，见 MaterialButton 注释）
        MaterialButton({
          btnRadius: 17,
          btnPersistent: true,
          btnTint: this.actionTone === 'theme' ? Theme.colorOf(this.themeColor) :
            (this.actionTone === 'red' ? '#DB5252' : ''),
          btnTintRatio: this.actionTone === 'glass' ? 0 : 0.85,
          btnMargin: { left: 10 },
          btnOnClick: (): void => {
            this.onAction();
          }
        }) {
          Text(this.actionText)
            .fontSize(13)
            // 表达式必须读 this.fwMode 才登记依赖（静态函数内读 AppStorage 不登记）
            .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            // 实底语义（主题色/警示红）用白字；玻璃底用顶栏自适应字色，保证可读
            .fontColor(this.actionTone === 'glass' ? WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode) : Color.White)
            .height(34)
            .padding({ left: 14, right: 14 })
            .textAlign(TextAlign.Center)
        }
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
