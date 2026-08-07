/**
 * 课程表设置面板
 *  - 颜色选择器：独立 @Component ColorPickCell，用 @Link 双向绑定 hex
 *  - 滑动条/开关/单选框：纯华为官方组件，无自定义 builder
 */
import { promptAction } from '@kit.ArkUI';
import { ScheduleConfig } from '../common/ScheduleConfig';

const BG_PALETTE: string[] = [
  '#FFFFFF', '#FAF9F6', '#F0F0F0', '#F5F0E1', '#E8F0FE', '#E3F9E5',
  '#FFF3E0', '#FDE8E9', '#F3E5F5', '#E0F7FA', '#FFF8E1', '#E8EAF6',
  '#D7CCC8', '#CFD8DC'
];
const HEADER_PALETTE: string[] = [
  '#FFFFFF', '#F5F5F5', '#F0F4FF', '#E8F5E9', '#FFF8E1',
  '#FFEBEE', '#E8EAF6', '#EFEBE9', '#E0F2F1', '#F3E5F5',
  '#FFFDE7', '#ECEFF1', '#1A1D1C', '#263238'
];
const COLOR_PALETTE: string[] = [
  '#E53935', '#D81B60', '#8E24AA', '#5E35B1', '#3949AB', '#1E88E5', '#039BE5',
  '#00ACC1', '#00897B', '#43A047', '#7CB342', '#C0CA33', '#FDD835', '#FFB300'
];

/** 颜色选择器独立组件 —— 对标 CourseDetailPanel 的圆点色盘 */
@Component
struct ColorPickCell {
  @Link hex: string;
  palette: string[] = [];
  label: string = '';
  onChange: () => void = () => {};

  build() {
    Column() {
      Row() {
        Text(this.label).fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary')).layoutWeight(1)
        Column().width(22).height(22).borderRadius(6).margin({ left: 8 })
          .backgroundColor(this.hex.length > 0 ? this.hex : '#DDDDDD')
          .border({ width: 1, color: '#CCCCCC' })
      }.width('100%').margin({ bottom: 4 })
      Row() {
        TextInput({ text: this.hex, placeholder: '#RRGGBB' })
          .fontSize(12).height(32).layoutWeight(1)
          .backgroundColor($r('app.color.bg_chip'))
          .onChange((v: string) => {
            if (v.length === 0 || /^#[0-9a-fA-F]{6}$/.test(v)) { this.hex = v; this.onChange(); }
          })
      }.width('100%').margin({ bottom: 10 })

      Flex({ wrap: FlexWrap.Wrap }) {
        Column() {
          Text('🔄').fontSize(16)
        }
        .width(34).height(34).borderRadius(17)
        .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
        .backgroundColor($r('app.color.bg_chip'))
        .border({
          width: this.hex.length === 0 ? 3 : 1,
          color: this.hex.length === 0 ? $r('app.color.brand') : '#CCCCCC'
        })
        .margin({ right: 12, top: 10 })
        .onClick(() => { this.hex = ''; this.onChange(); })

        ForEach(this.palette, (p: string) => {
          Column()
            .width(34).height(34).borderRadius(17).backgroundColor(p)
            .border({
              width: p === this.hex ? 3 : 1,
              color: p === this.hex ? $r('app.color.brand') : '#CCCCCC'
            })
            .margin({ right: 12, top: 10 })
            .onClick(() => { this.hex = p; this.onChange(); })
        }, (p: string) => p)
      }.width('100%')
    }.width('100%')
  }
}

@Component
export struct ScheduleSettingsPanel {
  cfg: ScheduleConfig = new ScheduleConfig();
  scheduleBg: string = '';
  onPickBg: () => void = () => {};
  onClearBg: () => void = () => {};
  onClose: () => void = () => {};
  onCfgChange: (c: ScheduleConfig) => void = () => {};

  @State bgColor: string = '';
  @State hdrColor: string = '';
  @State txtColor: string = '';
  @State bdrColor: string = '';

  @State gridW: number = 0.5;
  @State hdrSize: number = 12;
  @State borderW: number = 0;
  @State cellH: number = 58;
  @State cellR: number = 8;
  @State cellOp: number = 100;
  @State nextOp: number = 35;
  @State textSz: number = 11;

  @State gridOn: boolean = false;
  @State secTime: boolean = false;
  @State weekend: boolean = false;
  @State nextWeek: boolean = false;
  @State textMix: boolean = false;
  @State bdrCourse: boolean = false;
  @State bdrDash: boolean = false;
  @State showTime: boolean = false;
  @State showLoc: boolean = false;
  @State showAt: boolean = false;
  @State showTch: boolean = false;
  @State vCenter: boolean = true;

  @State lineStyle: number = 1;
  @State hAlign: number = 0;

  aboutToAppear(): void {
    const c = this.cfg;
    this.bgColor = c.bgColor;
    this.hdrColor = c.headerColor;
    this.txtColor = c.textColor;
    this.bdrColor = c.borderColor;
    this.gridOn = c.gridEnabled;
    this.secTime = c.showSectionTime;
    this.weekend = c.showWeekend;
    this.nextWeek = c.showNextWeek;
    this.textMix = c.textMixWithBg;
    this.bdrCourse = c.borderUseCourseColor;
    this.bdrDash = c.borderDashed;
    this.showTime = c.showTimeInCell;
    this.showLoc = c.showLocation;
    this.showAt = c.showAtPrefix;
    this.showTch = c.showTeacher;
    this.vCenter = c.textVCenter;
    this.gridW = c.gridWidth;
    this.hdrSize = c.headerFontSize;
    this.borderW = c.borderWidth;
    this.cellH = c.cellHeight;
    this.cellR = c.cellRadius;
    this.cellOp = c.cellOpacity;
    this.nextOp = c.nextWeekOpacity;
    this.textSz = c.textSize;
    this.lineStyle = c.gridDashed ? 1 : 0;
    this.hAlign = c.textHCenter ? 0 : (c.textLeft ? 1 : 2);
  }

  private apply(): void {
    const c = this.cfg.clone();
    c.bgColor = this.bgColor;
    c.headerColor = this.hdrColor;
    c.textColor = this.txtColor;
    c.borderColor = this.bdrColor;
    c.gridEnabled = this.gridOn;
    c.showSectionTime = this.secTime;
    c.showWeekend = this.weekend;
    c.showNextWeek = this.nextWeek;
    c.textMixWithBg = this.textMix;
    c.borderUseCourseColor = this.bdrCourse;
    c.borderDashed = this.bdrDash;
    c.showTimeInCell = this.showTime;
    c.showLocation = this.showLoc;
    c.showAtPrefix = this.showAt;
    c.showTeacher = this.showTch;
    c.textVCenter = this.vCenter;
    c.gridWidth = this.gridW;
    c.gridDashed = this.lineStyle === 1;
    c.headerFontSize = this.hdrSize;
    c.borderWidth = this.borderW;
    c.cellHeight = this.cellH;
    c.cellRadius = this.cellR;
    c.cellOpacity = this.cellOp;
    c.nextWeekOpacity = this.nextOp;
    c.textSize = this.textSz;
    c.textHCenter = this.hAlign === 0;
    c.textLeft = this.hAlign === 1;
    c.textRight = this.hAlign === 2;
    this.cfg = c;
    c.save();
    this.onCfgChange(c);
  }

  build() {
    Scroll() {
      Column() {
        // ===== 整体 =====
        Text('整体').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.brand'))
          .width('100%').textAlign(TextAlign.Start).margin({ top: 16, bottom: 8 })

        ColorPickCell({ hex: $bgColor, palette: BG_PALETTE, label: '纯色背景', onChange: () => { this.apply(); } })

        Divider().color($r('app.color.divider')).margin({ top: 8, bottom: 8 })
        Row() {
          Text('背景图').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          if (this.scheduleBg.length > 0) {
            Text('清除').fontSize(12).fontColor('#F0524D')
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor('rgba(240,82,77,0.10)').borderRadius(4)
              .onClick(() => { this.onClearBg(); })
          }
        }.width('100%').margin({ top: 4, bottom: 6 })
        Row() {
          if (this.scheduleBg.length > 0) {
            Image(`data:image/jpeg;base64,${this.scheduleBg}`)
              .width(48).height(48).borderRadius(8).objectFit(ImageFit.Cover).margin({ right: 12 })
          }
          Button(this.scheduleBg.length > 0 ? '更换图片' : '选择图片')
            .fontSize(13).fontColor($r('app.color.brand_on')).backgroundColor($r('app.color.brand'))
            .height(36).layoutWeight(1).borderRadius(10)
            .onClick(() => { this.onPickBg(); })
        }.width('100%')

        // 网格
        Divider().color($r('app.color.divider'))
        Row() {
          Text('网格辅助线').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.gridOn })
            .selectedColor($r('app.color.brand'))
            .onChange((on: boolean) => { this.gridOn = on; this.apply(); })
        }.width('100%').margin({ top: 10, bottom: 10 })

        if (this.gridOn) {
          Column() {
            Row() {
              Text('线宽').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
              Blank()
              Text(`${this.gridW}vp`).fontSize(12).fontColor($r('app.color.brand'))
            }.width('100%')
            Slider({ value: this.gridW, min: 0.5, max: 3, step: 0.5, style: SliderStyle.OutSet })
              .width('100%').selectedColor($r('app.color.brand'))
              .trackColor($r('app.color.bg_chip')).blockColor(Color.White)
              .onChange((v: number) => { this.gridW = v; this.apply(); })
          }.width('100%').margin({ top: 4, bottom: 8 })

          Row() {
            Text('线型').fontSize(14).fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary')).layoutWeight(1)
            Row({ space: 16 }) {
              Row({ space: 4 }) {
                Radio({ value: 'solid', group: 'line' }).checked(this.lineStyle === 0)
                  .radioStyle({ checkedBackgroundColor: $r('app.color.brand') })
                  .onChange(() => { this.lineStyle = 0; this.apply(); })
                Text('实线').fontSize(13).fontColor($r('app.color.text_primary'))
              }
              Row({ space: 4 }) {
                Radio({ value: 'dash', group: 'line' }).checked(this.lineStyle === 1)
                  .radioStyle({ checkedBackgroundColor: $r('app.color.brand') })
                  .onChange(() => { this.lineStyle = 1; this.apply(); })
                Text('虚线').fontSize(13).fontColor($r('app.color.text_primary'))
              }
            }
          }.width('100%').margin({ top: 8, bottom: 8 })
        }

        // 表头
        Divider().color($r('app.color.divider'))
        ColorPickCell({ hex: $hdrColor, palette: HEADER_PALETTE, label: '表头颜色', onChange: () => { this.apply(); } })

        Column() {
          Row() {
            Text('表头文字大小').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.hdrSize}`).fontSize(12).fontColor($r('app.color.brand'))
          }.width('100%')
          Slider({ value: this.hdrSize, min: 10, max: 20, step: 1, style: SliderStyle.OutSet })
            .width('100%').selectedColor($r('app.color.brand'))
            .trackColor($r('app.color.bg_chip')).blockColor(Color.White)
            .onChange((v: number) => { this.hdrSize = v; this.apply(); })
        }.width('100%').margin({ top: 8, bottom: 8 })

        // 节次 / 周末 / 下周
        Divider().color($r('app.color.divider'))
        Row() {
          Text('节次栏显示时间').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.secTime })
            .selectedColor($r('app.color.brand'))
            .onChange((on: boolean) => { this.secTime = on; this.apply(); })
        }.width('100%').margin({ top: 10, bottom: 10 })
        Row() {
          Text('显示周六周日').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.weekend })
            .selectedColor($r('app.color.brand'))
            .onChange((on: boolean) => { this.weekend = on; this.apply(); })
        }.width('100%').margin({ top: 10, bottom: 10 })
        Row() {
          Text('显示下周课程').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.nextWeek })
            .selectedColor($r('app.color.brand'))
            .onChange((on: boolean) => { this.nextWeek = on; this.apply(); })
        }.width('100%').margin({ top: 10, bottom: 10 })

        // ===== 课程格子 =====
        Text('课程格子').fontSize(15).fontWeight(FontWeight.Bold).fontColor($r('app.color.brand'))
          .width('100%').textAlign(TextAlign.Start).margin({ top: 18, bottom: 8 })

        ColorPickCell({ hex: $txtColor, palette: COLOR_PALETTE, label: '文字颜色', onChange: () => { this.apply(); } })
        Row() {
          Text('文字颜色叠加格子颜色').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.textMix })
            .selectedColor($r('app.color.brand'))
            .onChange((on: boolean) => { this.textMix = on; this.apply(); })
        }.width('100%').margin({ top: 10, bottom: 10 })

        Divider().color($r('app.color.divider'))
        ColorPickCell({ hex: $bdrColor, palette: COLOR_PALETTE, label: '格子边框颜色', onChange: () => { this.apply(); } })
        Row() {
          Text('边框使用格子颜色').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.bdrCourse })
            .selectedColor($r('app.color.brand'))
            .onChange((on: boolean) => { this.bdrCourse = on; this.apply(); })
        }.width('100%').margin({ top: 10, bottom: 10 })
        Row() {
          Text('虚线边框').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.bdrDash })
            .selectedColor($r('app.color.brand'))
            .onChange((on: boolean) => { this.bdrDash = on; this.apply(); })
        }.width('100%').margin({ top: 10, bottom: 10 })

        Column() {
          Row() {
            Text('边框粗细').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.borderW}vp`).fontSize(12).fontColor($r('app.color.brand'))
          }.width('100%')
          Slider({ value: this.borderW, min: 0, max: 4, step: 0.5, style: SliderStyle.OutSet })
            .width('100%').selectedColor($r('app.color.brand'))
            .trackColor($r('app.color.bg_chip')).blockColor(Color.White)
            .onChange((v: number) => { this.borderW = v; this.apply(); })
        }.width('100%').margin({ top: 8, bottom: 8 })

        Divider().color($r('app.color.divider'))
        Column() {
          Row() {
            Text('格子高度').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.cellH}vp`).fontSize(12).fontColor($r('app.color.brand'))
          }.width('100%')
          Slider({ value: this.cellH, min: 44, max: 80, step: 2, style: SliderStyle.OutSet })
            .width('100%').selectedColor($r('app.color.brand'))
            .trackColor($r('app.color.bg_chip')).blockColor(Color.White)
            .onChange((v: number) => { this.cellH = v; this.apply(); })
        }.width('100%').margin({ top: 8, bottom: 8 })
        Column() {
          Row() {
            Text('圆角半径').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.cellR}vp`).fontSize(12).fontColor($r('app.color.brand'))
          }.width('100%')
          Slider({ value: this.cellR, min: 0, max: 16, step: 1, style: SliderStyle.OutSet })
            .width('100%').selectedColor($r('app.color.brand'))
            .trackColor($r('app.color.bg_chip')).blockColor(Color.White)
            .onChange((v: number) => { this.cellR = v; this.apply(); })
        }.width('100%').margin({ top: 8, bottom: 8 })
        Column() {
          Row() {
            Text('不透明度').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.cellOp}%`).fontSize(12).fontColor($r('app.color.brand'))
          }.width('100%')
          Slider({ value: this.cellOp, min: 30, max: 100, step: 5, style: SliderStyle.OutSet })
            .width('100%').selectedColor($r('app.color.brand'))
            .trackColor($r('app.color.bg_chip')).blockColor(Color.White)
            .onChange((v: number) => { this.cellOp = v; this.apply(); })
        }.width('100%').margin({ top: 8, bottom: 8 })
        Column() {
          Row() {
            Text('下周课程不透明度').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.nextOp}%`).fontSize(12).fontColor($r('app.color.brand'))
          }.width('100%')
          Slider({ value: this.nextOp, min: 10, max: 70, step: 5, style: SliderStyle.OutSet })
            .width('100%').selectedColor($r('app.color.brand'))
            .trackColor($r('app.color.bg_chip')).blockColor(Color.White)
            .onChange((v: number) => { this.nextOp = v; this.apply(); })
        }.width('100%').margin({ top: 8, bottom: 8 })

        Divider().color($r('app.color.divider'))
        Column() {
          Row() {
            Text('文字大小').fontSize(14).fontWeight(FontWeight.Medium).fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.textSz}`).fontSize(12).fontColor($r('app.color.brand'))
          }.width('100%')
          Slider({ value: this.textSz, min: 8, max: 16, step: 1, style: SliderStyle.OutSet })
            .width('100%').selectedColor($r('app.color.brand'))
            .trackColor($r('app.color.bg_chip')).blockColor(Color.White)
            .onChange((v: number) => { this.textSz = v; this.apply(); })
        }.width('100%').margin({ top: 8, bottom: 8 })

        Row() {
          Text('文字水平对齐').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Row({ space: 12 }) {
            Row({ space: 4 }) {
              Radio({ value: 'c', group: 'align' }).checked(this.hAlign === 0)
                .radioStyle({ checkedBackgroundColor: $r('app.color.brand') })
                .onChange(() => { this.hAlign = 0; this.apply(); })
              Text('居中').fontSize(13).fontColor($r('app.color.text_primary'))
            }
            Row({ space: 4 }) {
              Radio({ value: 'l', group: 'align' }).checked(this.hAlign === 1)
                .radioStyle({ checkedBackgroundColor: $r('app.color.brand') })
                .onChange(() => { this.hAlign = 1; this.apply(); })
              Text('靠左').fontSize(13).fontColor($r('app.color.text_primary'))
            }
            Row({ space: 4 }) {
              Radio({ value: 'r', group: 'align' }).checked(this.hAlign === 2)
                .radioStyle({ checkedBackgroundColor: $r('app.color.brand') })
                .onChange(() => { this.hAlign = 2; this.apply(); })
              Text('靠右').fontSize(13).fontColor($r('app.color.text_primary'))
            }
          }
        }.width('100%').margin({ top: 10, bottom: 10 })

        Row() {
          Text('文字垂直居中').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.vCenter })
            .selectedColor($r('app.color.brand'))
            .onChange((on: boolean) => { this.vCenter = on; this.apply(); })
        }.width('100%').margin({ top: 10, bottom: 10 })

        Divider().color($r('app.color.divider'))
        Row() {
          Text('格子内显示上课时间').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showTime })
            .selectedColor($r('app.color.brand'))
            .onChange((on: boolean) => { this.showTime = on; this.apply(); })
        }.width('100%').margin({ top: 10, bottom: 10 })
        Row() {
          Text('格子内显示上课地点').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showLoc })
            .selectedColor($r('app.color.brand'))
            .onChange((on: boolean) => { this.showLoc = on; this.apply(); })
        }.width('100%').margin({ top: 10, bottom: 10 })
        Row() {
          Text('地点前显示@').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showAt })
            .selectedColor($r('app.color.brand'))
            .onChange((on: boolean) => { this.showAt = on; this.apply(); })
        }.width('100%').margin({ top: 10, bottom: 10 })
        Row() {
          Text('格子内显示授课老师').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showTch })
            .selectedColor($r('app.color.brand'))
            .onChange((on: boolean) => { this.showTch = on; this.apply(); })
        }.width('100%').margin({ top: 10, bottom: 10 })

        Button('恢复默认设置')
          .width('100%').height(44).fontSize(15).fontColor('#F0524D')
          .backgroundColor('rgba(240,82,77,0.10)').borderRadius(12).margin({ top: 20 })
          .onClick(() => {
            this.cfg = new ScheduleConfig();
            const c = this.cfg;
            this.bgColor = c.bgColor; this.hdrColor = c.headerColor;
            this.txtColor = c.textColor; this.bdrColor = c.borderColor;
            this.gridOn = c.gridEnabled; this.secTime = c.showSectionTime;
            this.weekend = c.showWeekend; this.nextWeek = c.showNextWeek;
            this.textMix = c.textMixWithBg; this.bdrCourse = c.borderUseCourseColor;
            this.bdrDash = c.borderDashed; this.showTime = c.showTimeInCell;
            this.showLoc = c.showLocation; this.showAt = c.showAtPrefix;
            this.showTch = c.showTeacher; this.vCenter = c.textVCenter;
            this.gridW = c.gridWidth; this.hdrSize = c.headerFontSize;
            this.borderW = c.borderWidth; this.cellH = c.cellHeight;
            this.cellR = c.cellRadius; this.cellOp = c.cellOpacity;
            this.nextOp = c.nextWeekOpacity; this.textSz = c.textSize;
            this.lineStyle = c.gridDashed ? 1 : 0;
            this.hAlign = c.textHCenter ? 0 : (c.textLeft ? 1 : 2);
            this.cfg.save();
            this.onCfgChange(this.cfg);
            promptAction.showToast({ message: '已恢复默认设置' });
          })
        Button('关闭')
          .width('100%').height(44).fontSize(15).fontColor($r('app.color.brand'))
          .backgroundColor($r('app.color.brand_light')).borderRadius(12).margin({ top: 10 })
          .onClick(() => { this.onClose(); })
        Column().height(24)
      }
      .width('100%').padding({ left: 20, right: 20, top: 8 })
    }
    .width('100%').height('100%').scrollBar(BarState.Off).align(Alignment.Top)
  }
}
