/**
 * 课程详情面板（独立组件）——本地 @State 镜像驱动 UI，回调同步父组件：
 *  - 颜色 map 用 @State disp 镜像驱动：点击色块 → 立即更新 disp → 面板实时重渲染（选中圆圈立刻包裹）
 *  - 通过 onColorsChange 回调父组件 → 父 @State customColors 更新 → 课表格子实时变色
 * 不依赖 bindSheet/@Link 的刷新行为（该场景实测均不刷新，这是最终解法）。
 */
import { promptAction } from '@kit.ArkUI';
import { JwApi } from '../api/JwApi';
import { DataStore } from '../common/DataStore';
import { COURSE_BG_HEX } from '../common/ScheduleConfig';
import { CourseItem } from '../model/Models';
import { EMPTY_COURSE } from '../model/Empty';

/** 课程独立颜色：3 套 × 20 色（套1 鲜艳 / 套2 柔和浅色 / 套3 深邃） */
const COURSE_PALETTES: string[][] = [
  [
    '#E53935', '#D81B60', '#8E24AA', '#5E35B1', '#3949AB',
    '#1E88E5', '#039BE5', '#00ACC1', '#00897B', '#43A047',
    '#7CB342', '#C0CA33', '#FDD835', '#FFB300', '#FB8C00',
    '#F4511E', '#6D4C41', '#757575', '#546E7A', '#212121'
  ],
  [
    '#FFCDD2', '#F8BBD0', '#E1BEE7', '#D1C4E9', '#C5CAE9',
    '#BBDEFB', '#B3E5FC', '#B2EBF2', '#B2DFDB', '#C8E6C9',
    '#DCEDC8', '#F0F4C3', '#FFF9C4', '#FFECB3', '#FFE0B2',
    '#FFCCBC', '#D7CCC8', '#F5F5F5', '#CFD8DC', '#ECEFF1'
  ],
  [
    '#B71C1C', '#880E4F', '#4A148C', '#311B92', '#1A237E',
    '#0D47A1', '#01579B', '#006064', '#004D40', '#1B5E20',
    '#33691E', '#827717', '#F57F17', '#FF6F00', '#E65100',
    '#BF360C', '#3E2723', '#424242', '#263238', '#000000'
  ]
];

@Component
export struct CourseDetailPanel {
  /** 当前课程（只读展示 + 颜色选择目标） */
  @Prop selected: CourseItem = EMPTY_COURSE;
  /** 父组件颜色 map（只读输入，初始化镜像用） */
  customColors: Record<string, string> = {};
  /** 课程名列表（一键分配用） */
  courseNames: string[] = [];
  /** 上课时间行文本（父组件用学期/周次计算后传入） */
  timeText: string = '';
  /** 关闭弹窗回调 */
  onClose: () => void = () => {
  };
  /** 颜色变更回调（父组件 @State 赋值，驱动课表实时刷新） */
  onColorsChange: (m: Record<string, string>) => void = () => {
  };

  /** 本地镜像：驱动面板 UI 实时刷新（圆圈包裹） */
  @State disp: Record<string, string> = {};
  /** 当前色板套（0/1/2） */
  @State colorTab: number = 0;

  aboutToAppear(): void {
    this.disp = this.copyMap(this.customColors);
  }

  /** 深拷贝 Record */
  private copyMap(src: Record<string, string>): Record<string, string> {
    const m: Record<string, string> = {};
    const keys: string[] = Object.keys(src);
    for (const k of keys) {
      m[k] = src[k];
    }
    return m;
  }

  /** 课程当前生效颜色：自定义 > hash 默认 */
  private colorOf(): string {
    const custom: string = this.disp[this.selected.name] ?? '';
    if (custom.length > 0) {
      return custom;
    }
    return COURSE_BG_HEX[JwApi.ensureColorIndex(this.selected.name)];
  }

  /** 设置/清除课程颜色：更新镜像（面板实时）→ 落盘 → 回调父（课表实时） */
  private setCourseColor(name: string, hex: string): void {
    const m: Record<string, string> = this.copyMap(this.disp);
    if (hex.length === 0) {
      // 恢复默认：重建 map 跳过该课程（ArkTS 不支持 delete）
      const n: Record<string, string> = {};
      const keys: string[] = Object.keys(m);
      for (const k of keys) {
        if (k !== name) {
          n[k] = m[k];
        }
      }
      this.disp = n;
      DataStore.setCourseCustomColors(JSON.stringify(n));
      this.onColorsChange(n);
      promptAction.showToast({ message: '已恢复默认颜色' });
    } else {
      m[name] = hex;
      this.disp = m;
      DataStore.setCourseCustomColors(JSON.stringify(m));
      this.onColorsChange(m);
      promptAction.showToast({ message: `已设置《${name}》颜色` });
    }
  }

  /** 该颜色已被哪门课程使用（排除当前课程），未使用返回空串 */
  private colorUsedBy(hex: string): string {
    const keys: string[] = Object.keys(this.disp);
    for (const k of keys) {
      if (k !== this.selected.name && this.disp[k] === hex) {
        return k;
      }
    }
    return '';
  }

  /** 一键为所有课程分配颜色（按课程名列表顺序轮流取当前套 20 色） */
  private assignAllColors(): void {
    const m: Record<string, string> = this.copyMap(this.disp);
    const palette: string[] = COURSE_PALETTES[this.colorTab];
    for (let i = 0; i < this.courseNames.length; i++) {
      m[this.courseNames[i]] = palette[i % palette.length];
    }
    this.disp = m;
    DataStore.setCourseCustomColors(JSON.stringify(m));
    this.onColorsChange(m);
    promptAction.showToast({ message: `已为 ${this.courseNames.length} 门课程分配颜色` });
  }

  @Builder
  infoRow(label: string, value: string) {
    Row() {
      Column()
        .width(6)
        .height(6)
        .borderRadius(3)
        .backgroundColor(this.colorOf())
        .margin({ right: 10 })
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .width(62)
      Text(value)
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 8, bottom: 8 })
  }

  build() {
    Scroll() {
      Column() {
        if (this.selected.id.length > 0) {
          Row() {
            Column()
              .width(4)
              .height(20)
              .borderRadius(2)
              .backgroundColor(this.colorOf())
            Text(this.selected.name)
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .margin({ left: 8 })
              .layoutWeight(1)
          }
          .width('100%')
          .margin({ bottom: 16 })

          this.infoRow('任课教师', this.selected.teacher)
          this.infoRow('上课地点', this.selected.location)
          this.infoRow('上课时间', this.timeText)
          this.infoRow('上课周次', this.selected.weeksText)
          this.infoRow('课程属性', `${this.selected.courseType} · ${this.selected.credit} 学分`)

          // 课程独立颜色：3 套 × 20 色
          Divider().color($r('app.color.divider'))
          Row() {
            Text('课程颜色')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Column()
              .width(22)
              .height(22)
              .borderRadius(6)
              .backgroundColor(this.colorOf())
              .border({ width: 1, color: '#CCCCCC' })
              .margin({ left: 8 })
            Blank()
            // 一键为所有课程分配颜色
            Text('一键分配')
              .fontSize(12)
              .fontColor($r('app.color.brand'))
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .backgroundColor($r('app.color.brand_light'))
              .borderRadius(4)
              .margin({ right: 8 })
              .onClick(() => {
                this.assignAllColors();
              })
            if ((this.disp[this.selected.name] ?? '').length > 0) {
              Text('恢复默认')
                .fontSize(12)
                .fontColor('#F0524D')
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                .backgroundColor('rgba(240,82,77,0.10)')
                .borderRadius(4)
                .onClick(() => {
                  this.setCourseColor(this.selected.name, '');
                })
            }
          }
          .width('100%')
          .margin({ top: 12, bottom: 4 })

          Text('为当前课程单独设置颜色（空=按课程名自动取色）')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .margin({ bottom: 6 })

          // 3 套色板 tab
          Row() {
            ForEach(['套1 鲜艳', '套2 柔和', '套3 深邃'], (label: string, i: number) => {
              Text(label)
                .fontSize(12)
                .fontColor(this.colorTab === i ? $r('app.color.brand_on') : $r('app.color.text_primary'))
                .layoutWeight(1)
                .height(30)
                .textAlign(TextAlign.Center)
                .backgroundColor(this.colorTab === i ? $r('app.color.brand') : $r('app.color.bg_chip'))
                .borderRadius(8)
                .margin({ right: i < 2 ? 6 : 0 })
                .onClick(() => {
                  this.colorTab = i;
                })
            }, (label: string) => label)
          }
          .width('100%')

          // 20 色网格
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(COURSE_PALETTES[this.colorTab], (p: string) => {
              Column()
                .width(34)
                .height(34)
                .borderRadius(17)
                .backgroundColor(p)
                .border({
                  width: p === this.disp[this.selected.name] ? 3 : 1,
                  color: p === this.disp[this.selected.name] ? $r('app.color.brand') : '#CCCCCC'
                })
                .margin({ right: 12, top: 10 })
                .onClick(() => {
                  // 该颜色已被其它课程使用：拒绝并提示
                  const usedBy: string = this.colorUsedBy(p);
                  if (usedBy.length > 0) {
                    promptAction.showToast({ message: `《${usedBy}》已使用此颜色` });
                    return;
                  }
                  this.setCourseColor(this.selected.name, p);
                })
            }, (p: string) => `${this.colorTab}-${p}`)
          }
          .width('100%')
          .margin({ bottom: 6 })

          // 关闭
          Button('关闭')
            .width('100%')
            .height(44)
            .fontSize(15)
            .fontColor($r('app.color.brand'))
            .backgroundColor($r('app.color.brand_light'))
            .borderRadius(12)
            .margin({ top: 12 })
            .onClick(() => {
              this.onClose();
            })
        }
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
  }
}
