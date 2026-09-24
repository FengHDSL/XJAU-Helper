/**
 * 课程表设置面板
 *  - 颜色选择器：独立 @Component ColorPickCell，用 @Link 双向绑定 hex
 *  - 滑动条/开关/单选框：纯华为官方组件，无自定义 builder
 */
import { promptAction } from '@kit.ArkUI';
import { ScheduleConfig } from '../common/ScheduleConfig';
import { DataStore } from '../common/DataStore';
import { Const, SectionTime } from '../common/Constants';
import { SectionUtil } from '../common/SectionUtil';
import { DateUtil } from '../common/DateUtil';
import { Theme } from '../common/ThemeUtil';
import { AppearanceStore } from '../common/AppearanceStore';
import { GlassMaterial } from '../common/GlassMaterial';
import { ChevronRight } from './common/ChevronRight';
// 沉浸光感：面板内胶囊/圆角按钮走 MaterialButton（有色按钮用 btnTint 叠回原色），
// 节次编辑半模态内容套 MaterialSheetPanel
import { MaterialSheetPanel } from './common/MaterialCard';
import { MaterialButton } from './common/MaterialButton';
import { materialActive, sheetBlurStyle } from '../common/SystemMaterial';
import { MaterialCardLayer } from './common/MaterialCarrier';

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
  @StorageProp('themeColor') themeColor: string = 'green';
  /** 全局字重响应式订阅：表达式读 this.fwMode 才登记依赖，fwValue 声明即订阅 */
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  palette: string[] = [];
  label: string = '';
  onChange: () => void = () => {};


  build() {
    Column() {
      Row() {
        Text(this.label).fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
          .fontColor($r('app.color.text_primary')).layoutWeight(1)
        Column().width(22).height(22).borderRadius(6).margin({ left: 8 })
          .backgroundColor(this.hex.length > 0 ? this.hex : '#DDDDDD')
          .border({ width: 1, color: '#CCCCCC' })
      }.width('100%').margin({ bottom: 4 })
      Row() {
        // 十六进制色值输入框：TextInput 属表单控件，不能走 Toggle 承载层 → Stack 兄弟结构：
        // MaterialCardLayer 纯视觉承载层画沉浸光感（受全局开关控制），输入框自身透明底；
        // 材质关闭时回落原 comp_background_tertiary 实色底。
        Stack() {
          if (materialActive()) {
            MaterialCardLayer({ layerRadius: $r('sys.float.corner_radius_level12'), layerShadow: false })
          }
          TextInput({ text: this.hex, placeholder: '#RRGGBB' })
            .height(48)
            .enterKeyType(EnterKeyType.Done)
            .borderRadius($r('sys.float.corner_radius_level12'))
            .fontSize($r('sys.float.Body_L'))
            .fontWeight(this.fwMode === 'follow' ? FontWeight.Regular : AppearanceStore.fontWeight(FontWeight.Regular))
            .backgroundColor(materialActive() ? Color.Transparent : $r('sys.color.comp_background_tertiary'))
            .caretStyle({ color: $r('sys.color.font_emphasize') })
            .type(InputType.Normal)
            .fontColor(Theme.colorOf(this.themeColor))
            .placeholderFont({ size: $r('sys.float.Body_L'), weight: FontWeight.Regular })
            .width('100%')
            .onChange((v: string) => {
              if (v.length === 0 || /^#[0-9a-fA-F]{6}$/.test(v)) { this.hex = v; this.onChange(); }
            })
        }
        .layoutWeight(1)
        .borderRadius($r('sys.float.corner_radius_level12'))
      }.width('100%').margin({ bottom: 10 })

      Flex({ wrap: FlexWrap.Wrap }) {
        // 「恢复默认（无颜色）」圆钮：材质走 MaterialButton 的 Toggle 承载层（圆形=大圆角）。
        // 选中态的描边（未选色时高亮 3vp）画在内容层上，材质生效时不会被让出的边框吃掉。
        MaterialButton({
          btnRadius: 17,
          btnBg: $r('app.color.bg_chip'),
          btnBlur: GlassMaterial.bgBlur(AppStorage.get<boolean>('immersiveEffect') ?? false),
          btnBorderW: GlassMaterial.borderWidth(),
          btnBorderC: GlassMaterial.borderColor(),
          btnMargin: { right: 12, top: 10 },
          btnOnClick: () => { this.hex = ''; this.onChange(); }
        }) {
          Column() {
            Image($r('app.media.icon_restore')).width(18).height(18).fillColor($r('app.color.text_secondary'))
          }
          .width(34).height(34).borderRadius(17)
          .justifyContent(FlexAlign.Center).alignItems(HorizontalAlign.Center)
          .border({
            width: this.hex.length === 0 ? 3 : 1,
            color: this.hex.length === 0 ? Theme.colorOf(this.themeColor) : '#CCCCCC'
          })
        }

        ForEach(this.palette, (p: string) => {
          Column()
            .width(34).height(34).borderRadius(17).backgroundColor(p)
            .border({
              width: p === this.hex ? 3 : 1,
              color: p === this.hex ? Theme.colorOf(this.themeColor) : '#CCCCCC'
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
  @StorageProp('themeColor') themeColor: string = 'green';
  /** 灰字广播订阅：颜色表达式需传 this.grayTick 才登记响应式依赖（否则改色不实时刷新） */
  @StorageProp('grayTick') grayTick: number = 0;
  /** 沉浸光感开关（登记依赖：拨动后按钮的玻璃底/材质即时重渲染） */
  @StorageProp('immersiveEffect') immersiveEffect: boolean = false;
  /** 全局字重响应式订阅：表达式读 this.fwMode 才登记依赖，fwValue 声明即订阅 */
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  /** 响应式依赖：玻璃/灰字设置变化时触发本页重渲染（取值经 GlassMaterial 静态方法读取） */
  @StorageProp('glassStrength') glassStrength: number = 70;
  @StorageProp('cardMaterial') cardMaterial: boolean = false;
  @StorageProp('grayTextMode') grayTextMode: string = 'default';
  @StorageProp('grayTextColor') grayTextColor: string = '';
  cfg: ScheduleConfig = new ScheduleConfig();
  scheduleBg: string = '';
  onPickBg: () => void = () => {};
  onClearBg: () => void = () => {};
  onClose: () => void = () => {};
  onCfgChange: (c: ScheduleConfig) => void = () => {};
  // 自定义开学时间：当前学期 id / 当前开学日（含已自定义值）/ 变更回调（空串=恢复默认）
  currentTermId: string = '';
  currentTermStart: string = '';
  onTermStartChange: (date: string) => void = () => {};

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
  @State weekend: boolean = true;
  @State nextWeek: boolean = false;
  @State textMix: boolean = false;
  /** 课程格子沉浸光感（格子挂材质承载层，与全局沉浸光感开关联动） */
  @State cellMaterial: boolean = false;
  @State bdrCourse: boolean = false;
  @State bdrDash: boolean = false;
  @State showTime: boolean = false;
  @State showLoc: boolean = false;
  @State showAt: boolean = false;
  @State showTch: boolean = false;
  @State vCenter: boolean = true;
  // ===== 节次与上课时间编辑（半模态覆盖层）=====
  @State secCount: number = 10;
  @State secTimeText: string = '';
  /** 节次编辑面板（bindSheet）显隐 */
  @State showSecSheet: boolean = false;
  /** 面板内页面切换：false=主页（节数+列表） true=子页（单节时间编辑） */
  @State secPageFlag: boolean = false;
  /** 子页页面宽度（用于整页滑动位移，onAreaChange 实测） */
  @State secPageWidth: number = 0;
  /** 子页正在编辑的节序号（0 基） */
  @State editingIndex: number = 0;
  @State editTimes: string[] = [];

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
    this.cellMaterial = c.cellMaterial;
    this.vCenter = c.textVCenter;
    this.secCount = c.sectionCount;
    this.secTimeText = c.sectionTimeText;
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

  // ===== 节次与上课时间编辑 =====
  /** 打开编辑器：用当前配置初始化编辑缓冲 */
  private openSectionEditor(): void {
    const list: string[] = SectionUtil.list(this.cfg).map((x) => `${x.start}-${x.end}`);
    this.secCount = SectionUtil.count(this.cfg);
    this.editTimes = list.slice(0, this.secCount);
    this.secPageFlag = false;
    this.showSecSheet = true;
  }

  /** 编辑器内的节序号数组（供 ForEach 使用） */
  private secIndexes(): number[] {
    const out: number[] = [];
    for (let i = 0; i < this.secCount; i++) {
      out.push(i);
    }
    return out;
  }

  /** 调整节数（1~15），同步编辑缓冲 */
  private changeSecCount(delta: number): void {
    let n: number = this.secCount + delta;
    if (n < 1) {
      n = 1;
    }
    if (n > 15) {
      n = 15;
    }
    this.secCount = n;
    const next: string[] = [];
    for (let i = 0; i < n; i++) {
      if (i < this.editTimes.length && this.editTimes[i].length > 0) {
        next.push(this.editTimes[i]);
      } else {
        // 新增节次：以上一节为基础顺延（默认 45 分钟课 + 10 分钟间隔）
        const prev: string = next.length > 0 ? next[next.length - 1] : '08:00-08:45';
        const parts: string[] = prev.split('-');
        next.push(`${SectionUtil.addMinutesText(parts[1], 10)}-${SectionUtil.addMinutesText(SectionUtil.addMinutesText(parts[1], 10), 45)}`);
      }
    }
    this.editTimes = next;
  }

  /** 修改某一节的开/下课时间（which: 0=开始 1=结束） */
  private setEditTime(idx: number, which: number, value: string): void {
    const arr: string[] = this.editTimes.slice(0);
    const cur: string = arr[idx] ?? '00:00-00:00';
    const p: string[] = cur.split('-');
    const start: string = p.length > 0 ? p[0] : '00:00';
    const end: string = p.length > 1 ? p[1] : '00:00';
    arr[idx] = which === 0 ? `${value}-${end}` : `${start}-${value}`;
    this.editTimes = arr;
  }

  /** 恢复默认作息（清空自定义） */
  private resetSectionEditor(): void {
    this.secCount = Const.SECTION_COUNT;
    this.editTimes = Const.SECTIONS.map((x: SectionTime) => `${x.start}-${x.end}`);
    this.getUIContext().getPromptAction().showToast({ message: '已恢复默认作息，点击保存后生效' });
  }

  /** 保存：写回配置并通知外部刷新 */
  private saveSectionEditor(): void {
    for (let i = 0; i < this.editTimes.length; i++) {
      const p: string[] = (this.editTimes[i] ?? '').split('-');
      if (p.length !== 2 || !SectionUtil.isTime(p[0]) || !SectionUtil.isTime(p[1])) {
        this.getUIContext().getPromptAction().showToast({ message: `第 ${i + 1} 节时间格式应为 HH:MM-HH:MM` });
        return;
      }
    }
    const list: SectionTime[] = [];
    for (let i = 0; i < this.editTimes.length; i++) {
      const p: string[] = this.editTimes[i].split('-');
      list.push({ index: i + 1, start: p[0], end: p[1] } as SectionTime);
    }
    this.cfg.sectionCount = this.secCount;
    this.cfg.sectionTimeText = SectionUtil.toText(list);
    this.secTimeText = this.cfg.sectionTimeText;
    this.onCfgChange(this.cfg);
    this.showSecSheet = false;
    this.getUIContext().getPromptAction().showToast({ message: '课程节数与上课时间已保存' });
  }

  /** 首次开启沉浸光感前的风险确认弹窗（与全局沉浸光感共用"已确认"标记，确认一次后不再提示） */
  private confirmCellMaterial(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '开启沉浸光感',
      message: '该效果依赖鸿蒙7（API26+），请确保设备升级至鸿蒙7及以上版本，同时该效果可能导致设备发热、使用应用时卡顿掉帧、部分界面可读性严重降低，请酌情考虑开启！满血沉浸光感需设备为麒麟9020/T92及以上版本的处理器。',
      buttons: [
        { text: '仍要开启', color: Theme.colorOf(this.themeColor) },
        { text: '取消', color: '#666666' }
      ]
    }).then((res) => {
      if (res.index === 0) {
        this.cellMaterial = true;
        this.apply();
        DataStore.markImmersiveHintShown();
      }
    });
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
    c.cellMaterial = this.cellMaterial;
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

  /** 打开日期选择器，修改当前学期的开学日 */
  private openTermStartPicker(): void {
    const base: string = this.currentTermStart.length > 0
      ? this.currentTermStart
      : DateUtil.defaultTermStart(this.currentTermId);
    const sel: Date = DateUtil.parse(base);
    DatePickerDialog.show({
      start: new Date(2000, 0, 1),
      end: new Date(2035, 11, 31),
      selected: sel,
      onAccept: (value: DatePickerResult) => {
        const y: number = value.year ?? 2000;
        const m: number = value.month ?? 0;
        const d: number = value.day ?? 1;
        this.onTermStartChange(DateUtil.format(new Date(y, m, d)));
      }
    });
  }

  // ===== 节次编辑面板：同一面板内页面转换（参考官方 BindSheetExample）=====
  /** 面板主页：节数调整 + 每节时间列表（点击某节进入子页编辑） */
  @Builder
  secSheetMain() {
    Column() {
      Row() {
        Text('课程节数').fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
        // 「－」减节数圆角小按钮：材质走 MaterialButton（光感关闭回落原淡灰玻璃底）
        MaterialButton({
          btnRadius: 8,
          btnBg: $r('app.color.bg_chip'),
          btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
          btnBorderW: GlassMaterial.borderWidth(),
          btnBorderC: GlassMaterial.borderColor(),
          btnOnClick: () => { this.changeSecCount(-1); }
        }) {
          Text('－')
            .fontSize(18).fontColor($r('app.color.text_primary'))
            .width(34).height(30).textAlign(TextAlign.Center)
        }
        Text(`${this.secCount}`)
          .fontSize(15).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
          .fontColor($r('app.color.text_primary'))
          .width(46).textAlign(TextAlign.Center)
        // 「＋」加节数圆角小按钮：同上
        MaterialButton({
          btnRadius: 8,
          btnBg: $r('app.color.bg_chip'),
          btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
          btnBorderW: GlassMaterial.borderWidth(),
          btnBorderC: GlassMaterial.borderColor(),
          btnOnClick: () => { this.changeSecCount(1); }
        }) {
          Text('＋')
            .fontSize(18).fontColor($r('app.color.text_primary'))
            .width(34).height(30).textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Divider().color($r('app.color.divider')).margin({ top: 12, bottom: 4 })

      List() {
        ForEach(this.secIndexes(), (idx: number) => {
          ListItem() {
            Row() {
              Text(`第 ${idx + 1} 节`)
                .fontSize(14).fontColor($r('app.color.text_primary')).layoutWeight(1)
              Text((this.editTimes[idx] ?? '').replace('-', ' ~ '))
                .fontSize(13).fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
              ChevronRight({ iconSize: 18 }).margin({ left: 6 })
            }
            .width('100%')
            .height(46)
            .alignItems(VerticalAlign.Center)
          }
          .onClick(() => {
            this.editingIndex = idx;
            this.getUIContext().animateTo({ duration: 320, curve: Curve.EaseOut }, () => {
              this.secPageFlag = true;
            });
          })
        }, (idx: number) => `secrow${idx}`)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .divider({ strokeWidth: 0.5, color: $r('app.color.divider') })

      Row({ space: 12 }) {
        // 等宽双按钮：layoutWeight 放在外层 Column 上（MaterialButton 内部是 Stack，layoutWeight 需放外层）
        Column() {
          // 「恢复默认」：主题色文字 + 淡灰玻璃底 → MaterialButton（光感关闭回落同款玻璃底）
          MaterialButton({
            btnRadius: 21,
            btnBg: $r('app.color.bg_chip'),
            btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
            btnBorderW: GlassMaterial.borderWidth(),
            btnBorderC: GlassMaterial.borderColor(),
            btnOnClick: () => { this.resetSectionEditor(); }
          }) {
            Text('恢复默认')
              .fontSize(14).fontColor(Theme.colorOf(this.themeColor))
              .height(42).width('100%').textAlign(TextAlign.Center)
          }
        }
        .layoutWeight(1)
        Column() {
          // 「保存」主题色实底 + 白字 → 材质生效时靠 btnTint 叠回主题色（比例 0.85，承载白字对比度）
          MaterialButton({
            btnRadius: 21,
            btnBg: Theme.colorOf(this.themeColor),
            btnTint: Theme.colorOf(this.themeColor),
            btnTintRatio: 0.85,
            btnOnClick: () => { this.saveSectionEditor(); }
          }) {
            Text('保存')
              .fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium)).fontColor(Color.White)
              .height(42).width('100%').textAlign(TextAlign.Center)
          }
        }
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 8 })
  }

  /** 面板子页：编辑单节上课/下课时间（左上角返回，整页滑回主页） */
  @Builder
  secSheetDetail() {
    Column() {
      Row() {
        Image($r('app.media.back_arrow'))
          .width(18)
          .height(18)
          .fillColor($r('app.color.text_primary'))
        Text(`第 ${this.editingIndex + 1} 节时间`)
          .fontSize(15).fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 10 })
      }
      .width('100%')
      .height(44)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.getUIContext().animateTo({ duration: 320, curve: Curve.EaseOut }, () => {
          this.secPageFlag = false;
        });
      })

      Column() {
        Row() {
          Text('上课时间').fontSize(13).fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) }).width(72)
          // 时间输入框：TextInput 属表单控件、不能走 Toggle 承载层 → Stack 兄弟结构（承载层画沉浸光感，
          // 受全局开关控制；材质关闭回落原 comp_background_tertiary 实色底）。原 layoutWeight(1) 由外壳承担。
          Stack() {
            if (materialActive()) {
              MaterialCardLayer({ layerRadius: $r('sys.float.corner_radius_level12'), layerShadow: false })
            }
            TextInput({ text: (this.editTimes[this.editingIndex] ?? '').split('-')[0], placeholder: 'HH:MM' })
              .height(48)
              .enterKeyType(EnterKeyType.Done)
              .borderRadius($r('sys.float.corner_radius_level12'))
              .fontSize($r('sys.float.Body_L'))
              .fontWeight(this.fwMode === 'follow' ? FontWeight.Regular : AppearanceStore.fontWeight(FontWeight.Regular))
              .backgroundColor(materialActive() ? Color.Transparent : $r('sys.color.comp_background_tertiary'))
              .caretStyle({ color: $r('sys.color.font_emphasize') })
              .type(InputType.Normal)
              .fontColor(Theme.colorOf(this.themeColor))
              .placeholderFont({ size: $r('sys.float.Body_L'), weight: FontWeight.Regular })
              .width('100%')
              .onChange((v: string) => { this.setEditTime(this.editingIndex, 0, v); })
          }
          .layoutWeight(1)
          .borderRadius($r('sys.float.corner_radius_level12'))
        }
        .width('100%').margin({ top: 12 }).alignItems(VerticalAlign.Center)

        Row() {
          Text('下课时间').fontSize(13).fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) }).width(72)
          // 同「上课时间」输入框：Stack 兄弟结构承载沉浸光感
          Stack() {
            if (materialActive()) {
              MaterialCardLayer({ layerRadius: $r('sys.float.corner_radius_level12'), layerShadow: false })
            }
            TextInput({ text: (this.editTimes[this.editingIndex] ?? '').split('-')[1], placeholder: 'HH:MM' })
              .height(48)
              .enterKeyType(EnterKeyType.Done)
              .borderRadius($r('sys.float.corner_radius_level12'))
              .fontSize($r('sys.float.Body_L'))
              .fontWeight(this.fwMode === 'follow' ? FontWeight.Regular : AppearanceStore.fontWeight(FontWeight.Regular))
              .backgroundColor(materialActive() ? Color.Transparent : $r('sys.color.comp_background_tertiary'))
              .caretStyle({ color: $r('sys.color.font_emphasize') })
              .type(InputType.Normal)
              .fontColor(Theme.colorOf(this.themeColor))
              .placeholderFont({ size: $r('sys.float.Body_L'), weight: FontWeight.Regular })
              .width('100%')
              .onChange((v: string) => { this.setEditTime(this.editingIndex, 1, v); })
          }
          .layoutWeight(1)
          .borderRadius($r('sys.float.corner_radius_level12'))
        }
        .width('100%').margin({ top: 14 }).alignItems(VerticalAlign.Center)

        Text('时间格式：HH:MM，例如 08:00 ~ 08:45')
          .fontSize(11).fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
          .width('100%').margin({ top: 10 })

        // 「返回列表」主题色实底 + 白字 → MaterialButton，btnTint 叠回主题色（比例 0.85）
        MaterialButton({
          btnRadius: 21,
          btnMargin: { top: 20 },
          btnBg: Theme.colorOf(this.themeColor),
          btnTint: Theme.colorOf(this.themeColor),
          btnTintRatio: 0.85,
          btnOnClick: () => {
            this.getUIContext().animateTo({ duration: 320, curve: Curve.EaseOut }, () => {
              this.secPageFlag = false;
            });
          }
        }) {
          Text('返回列表')
            .fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium)).fontColor(Color.White)
            .height(42).width('100%').textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 8 })
  }

  /** 面板容器：两页叠加，用 translate + animateTo 实现同一面板内页面转换 */
  @Builder
  secSheet() {
    // 半模态内容套 MaterialSheetPanel：bindSheet 自身的 systemMaterial 挂在面板上、内容区不生效，
    // 由 MaterialSheetPanel 的 Toggle 承载层渲染材质。配套硬要求（见 build 里的 bindSheet）：
    // 显式 backgroundColor: Color.Transparent。面板高度 detents [MEDIUM, LARGE] 为固定高度
    // → panelFillHeight 保持默认 true（承载层铺满整块面板）。
    MaterialSheetPanel({ panelRadius: 20, panelPadding: 0, panelTitle: '课程节数与上课时间', panelShowClose: true, panelOnClose: (): void => { this.showSecSheet = false; } }) {
    Stack() {
      Column() {
        this.secSheetMain()
      }
      .width('100%')
      .height('100%')
      .translate({ x: this.secPageFlag ? (0 - this.secPageWidth) : 0 })

      Column() {
        this.secSheetDetail()
      }
      .width('100%')
      .height('100%')
      .translate({ x: this.secPageFlag ? 0 : this.secPageWidth })
      .onAreaChange((_o: Area, n: Area) => {
        this.secPageWidth = Number(n.width);
      })
    }
    .width('100%')
    .height('100%')
    .clip(true)
    }
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Scroll() {
      Column() {
        // ===== 整体 =====
        Text('整体').fontSize(17).fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold)).fontColor(Theme.colorOf(this.themeColor))
          .width('100%').textAlign(TextAlign.Start).margin({ top: 16, bottom: 8 })

        // 自定义开学时间（覆盖默认 9-01/3-01 推算，用于修正周次）
        Divider().color($r('app.color.divider')).margin({ top: 12, bottom: 12 })
        Row() {
          Text('自定义开学时间').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          if (this.currentTermStart.length > 0 && this.currentTermStart !== DateUtil.defaultTermStart(this.currentTermId)) {
            // 「恢复默认」淡红小胶囊：材质走 MaterialButton，btnTint 叠回警示红（比例 0.35，保持淡红观感）
            MaterialButton({
              btnRadius: 4,
              btnBg: 'rgba(240,82,77,0.10)',
              btnTint: '#F0524D',
              btnTintRatio: 0.35,
              btnOnClick: () => { this.onTermStartChange(''); }
            }) {
              Text('恢复默认')
                .fontSize(12).fontColor('#F0524D')
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            }
          }
        }.width('100%').margin({ top: 4, bottom: 6 })
        Row() {
          Text(this.currentTermStart.length > 0 ? this.currentTermStart : DateUtil.defaultTermStart(this.currentTermId))
            .fontSize(15).fontColor($r('app.color.text_primary')).layoutWeight(1)
          ChevronRight({ iconSize: 20 })
        }.width('100%')
        .onClick(() => { this.openTermStartPicker(); })

        // 课程节数
        Divider().color($r('app.color.divider')).margin({ top: 12, bottom: 12 })
        Row() {
          Text('课程节数').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Text(`${this.secCount} 节`).fontSize(13).fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
          ChevronRight({ iconSize: 20 }).margin({ left: 6 })
        }.width('100%')
        .onClick(() => { this.openSectionEditor(); })

        // 每节课上课时间
        Divider().color($r('app.color.divider')).margin({ top: 12, bottom: 12 })
        Row() {
          Text('每节课时间').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Text(this.secTimeText.length > 0 ? '已自定义' : '默认作息').fontSize(13)
            .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
          ChevronRight({ iconSize: 20 }).margin({ left: 6 })
        }.width('100%')
        .onClick(() => { this.openSectionEditor(); })

        // 背景图（第一位）
        Divider().color($r('app.color.divider')).margin({ top: 12, bottom: 12 })
        Row() {
          Text('背景图').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          if (this.scheduleBg.length > 0) {
            // 「清除」淡红小胶囊：同「恢复默认」，btnTint 叠回警示红（比例 0.35）
            MaterialButton({
              btnRadius: 4,
              btnBg: 'rgba(240,82,77,0.10)',
              btnTint: '#F0524D',
              btnTintRatio: 0.35,
              btnOnClick: () => { this.onClearBg(); }
            }) {
              Text('清除')
                .fontSize(12).fontColor('#F0524D')
                .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            }
          }
        }.width('100%').margin({ top: 4, bottom: 6 })
        Row() {
          if (this.scheduleBg.length > 0) {
            Image(`data:image/jpeg;base64,${this.scheduleBg}`)
              .width(48).height(48).borderRadius(8).objectFit(ImageFit.Cover).margin({ right: 12 })
          }
          // 「选择/更换图片」主题色实底 + brand_on 文字 → MaterialButton，btnTint 叠回主题色（比例 0.85）
          Column() {
            MaterialButton({
              btnRadius: 10,
              btnBg: Theme.colorOf(this.themeColor),
              btnTint: Theme.colorOf(this.themeColor),
              btnTintRatio: 0.85,
              btnOnClick: () => { this.onPickBg(); }
            }) {
              Text(this.scheduleBg.length > 0 ? '更换图片' : '选择图片')
                .fontSize(13).fontColor($r('app.color.brand_on'))
                .height(36).width('100%').textAlign(TextAlign.Center)
            }
          }
          .layoutWeight(1)
        }.width('100%')

        // 网格
        Divider().color($r('app.color.divider'))
        Row() {
          Text('网格辅助线').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.gridOn })
            .selectedColor(Theme.colorOf(this.themeColor))
            .onChange((on: boolean) => {
              // 展开/收起带动画
              this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
                this.gridOn = on;
                this.apply();
              });
            })
        }.width('100%').margin({ top: 14, bottom: 14 })

        if (this.gridOn) {
          Column() {
            Row() {
              Text('线宽').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium)).fontColor($r('app.color.text_primary'))
              Blank()
              Text(`${this.gridW}vp`).fontSize(12).fontColor(Theme.colorOf(this.themeColor))
            }.width('100%')
            Slider({ value: this.gridW, min: 0.5, max: 3, step: 0.5, style: SliderStyle.OutSet })
              .width('100%').selectedColor(Theme.colorOf(this.themeColor))
              .trackColor($r('app.color.bg_chip')).blockColor(Color.White)
              .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
              .onChange((v: number) => { this.gridW = v; this.apply(); })
          }
          .width('100%').margin({ top: 4, bottom: 12 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 250 })
            .combine(TransitionEffect.translate({ y: -6 }).animation({ duration: 250 })))

          Row() {
            Text('线型').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
              .fontColor($r('app.color.text_primary')).layoutWeight(1)
            Row({ space: 16 }) {
              Row({ space: 4 }) {
                Radio({ value: 'solid', group: 'line' }).checked(this.lineStyle === 0)
                  .radioStyle({ checkedBackgroundColor: Theme.colorOf(this.themeColor) })
                  .onChange(() => { this.lineStyle = 0; this.apply(); })
                Text('实线').fontSize(13).fontColor($r('app.color.text_primary'))
              }
              Row({ space: 4 }) {
                Radio({ value: 'dash', group: 'line' }).checked(this.lineStyle === 1)
                  .radioStyle({ checkedBackgroundColor: Theme.colorOf(this.themeColor) })
                  .onChange(() => { this.lineStyle = 1; this.apply(); })
                Text('虚线').fontSize(13).fontColor($r('app.color.text_primary'))
              }
            }
          }.width('100%').margin({ top: 12, bottom: 12 })
          .transition(TransitionEffect.OPACITY.animation({ duration: 250 })
            .combine(TransitionEffect.translate({ y: -6 }).animation({ duration: 250 })))
        }

        // 整体背景
        Divider().color($r('app.color.divider'))
        ColorPickCell({ hex: $bgColor, palette: BG_PALETTE, label: '纯色背景', onChange: () => { this.apply(); } })

        // 表头
        Divider().color($r('app.color.divider'))
        ColorPickCell({ hex: $hdrColor, palette: HEADER_PALETTE, label: '表头颜色', onChange: () => { this.apply(); } })

        Column() {
          Row() {
            Text('表头文字大小').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium)).fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.hdrSize}`).fontSize(12).fontColor(Theme.colorOf(this.themeColor))
          }.width('100%')
          Slider({ value: this.hdrSize, min: 10, max: 20, step: 1, style: SliderStyle.OutSet })
            .width('100%').selectedColor(Theme.colorOf(this.themeColor))
            .trackColor($r('app.color.bg_chip')).blockColor(Color.White)
              .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
              .onChange((v: number) => { this.hdrSize = v; this.apply(); })
        }.width('100%').margin({ top: 12, bottom: 12 })

        // 节次 / 周末 / 下周
        Divider().color($r('app.color.divider'))
        Row() {
          Text('节次栏显示时间').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.secTime })
            .selectedColor(Theme.colorOf(this.themeColor))
            .onChange((on: boolean) => { this.secTime = on; this.apply(); })
        }.width('100%').margin({ top: 14, bottom: 14 })
        Row() {
          Column() {
            Text('显示周六周日').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            Text('关闭后，若当周周六/周日确实有课仍会显示，避免漏课').fontSize(11)
              .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
              .width('100%')
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.weekend })
            .selectedColor(Theme.colorOf(this.themeColor))
            .onChange((on: boolean) => { this.weekend = on; this.apply(); })
        }.width('100%').margin({ top: 14, bottom: 14 })
        Row() {
          Text('显示下周课程').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.nextWeek })
            .selectedColor(Theme.colorOf(this.themeColor))
            .onChange((on: boolean) => { this.nextWeek = on; this.apply(); })
        }.width('100%').margin({ top: 14, bottom: 14 })

        // ===== 课程格子 =====
        Text('课程格子').fontSize(17).fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold)).fontColor(Theme.colorOf(this.themeColor))
          .width('100%').textAlign(TextAlign.Start).margin({ top: 18, bottom: 8 })

        ColorPickCell({ hex: $txtColor, palette: COLOR_PALETTE, label: '文字颜色', onChange: () => { this.apply(); } })
        Row() {
          Text('文字颜色叠加格子颜色').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.textMix })
            .selectedColor(Theme.colorOf(this.themeColor))
            .onChange((on: boolean) => { this.textMix = on; this.apply(); })
        }.width('100%').margin({ top: 14, bottom: 14 })
        Row() {
          Column() {
            Text('课程格子沉浸光感').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
              .fontColor($r('app.color.text_primary'))
              .width('100%')
            Text('课程格子改用沉浸光感材质渲染（API 26+），课程底色以半透明叠层保留；受全局沉浸光感开关影响')
              .fontSize(11)
              .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).linearGradient({ angle: 90, colors: GlassMaterial.styleGlowColors(this.grayTick) })
              .width('100%')
              .margin({ top: 2 })
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
          Toggle({ type: ToggleType.Switch, isOn: this.cellMaterial })
            .selectedColor(Theme.colorOf(this.themeColor))
            .onChange((on: boolean) => {
              // 首次开启前弹风险确认（确认一次后不再提示）；取消时 isOn 受控回弹
              if (on && !DataStore.immersiveHintShown()) {
                this.confirmCellMaterial();
              } else {
                this.cellMaterial = on;
                this.apply();
              }
            })
        }.width('100%').margin({ top: 14, bottom: 14 })

        Divider().color($r('app.color.divider'))
        ColorPickCell({ hex: $bdrColor, palette: COLOR_PALETTE, label: '格子边框颜色', onChange: () => { this.apply(); } })
        Row() {
          Text('边框使用格子颜色').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.bdrCourse })
            .selectedColor(Theme.colorOf(this.themeColor))
            .onChange((on: boolean) => { this.bdrCourse = on; this.apply(); })
        }.width('100%').margin({ top: 14, bottom: 14 })
        Row() {
          Text('虚线边框').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.bdrDash })
            .selectedColor(Theme.colorOf(this.themeColor))
            .onChange((on: boolean) => { this.bdrDash = on; this.apply(); })
        }.width('100%').margin({ top: 14, bottom: 14 })

        Column() {
          Row() {
            Text('边框粗细').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium)).fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.borderW}vp`).fontSize(12).fontColor(Theme.colorOf(this.themeColor))
          }.width('100%')
          Slider({ value: this.borderW, min: 0, max: 4, step: 0.5, style: SliderStyle.OutSet })
            .width('100%').selectedColor(Theme.colorOf(this.themeColor))
            .trackColor($r('app.color.bg_chip')).blockColor(Color.White)
              .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
              .onChange((v: number) => { this.borderW = v; this.apply(); })
        }.width('100%').margin({ top: 12, bottom: 12 })

        Divider().color($r('app.color.divider'))
        Column() {
          Row() {
            Text('格子高度').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium)).fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.cellH}vp`).fontSize(12).fontColor(Theme.colorOf(this.themeColor))
          }.width('100%')
          Slider({ value: this.cellH, min: 44, max: 80, step: 2, style: SliderStyle.OutSet })
            .width('100%').selectedColor(Theme.colorOf(this.themeColor))
            .trackColor($r('app.color.bg_chip')).blockColor(Color.White)
              .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
              .onChange((v: number) => { this.cellH = v; this.apply(); })
        }.width('100%').margin({ top: 12, bottom: 12 })
        Column() {
          Row() {
            Text('圆角半径').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium)).fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.cellR}vp`).fontSize(12).fontColor(Theme.colorOf(this.themeColor))
          }.width('100%')
          Slider({ value: this.cellR, min: 0, max: 16, step: 1, style: SliderStyle.OutSet })
            .width('100%').selectedColor(Theme.colorOf(this.themeColor))
            .trackColor($r('app.color.bg_chip')).blockColor(Color.White)
              .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
              .onChange((v: number) => { this.cellR = v; this.apply(); })
        }.width('100%').margin({ top: 12, bottom: 12 })
        Column() {
          Row() {
            Text('不透明度').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium)).fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.cellOp}%`).fontSize(12).fontColor(Theme.colorOf(this.themeColor))
          }.width('100%')
          Slider({ value: this.cellOp, min: 30, max: 100, step: 5, style: SliderStyle.OutSet })
            .width('100%').selectedColor(Theme.colorOf(this.themeColor))
            .trackColor($r('app.color.bg_chip')).blockColor(Color.White)
              .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
              .onChange((v: number) => { this.cellOp = v; this.apply(); })
        }.width('100%').margin({ top: 12, bottom: 12 })
        Column() {
          Row() {
            Text('下周课程不透明度').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium)).fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.nextOp}%`).fontSize(12).fontColor(Theme.colorOf(this.themeColor))
          }.width('100%')
          Slider({ value: this.nextOp, min: 10, max: 70, step: 5, style: SliderStyle.OutSet })
            .width('100%').selectedColor(Theme.colorOf(this.themeColor))
            .trackColor($r('app.color.bg_chip')).blockColor(Color.White)
              .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
              .onChange((v: number) => { this.nextOp = v; this.apply(); })
        }.width('100%').margin({ top: 12, bottom: 12 })

        Divider().color($r('app.color.divider'))
        Column() {
          Row() {
            Text('文字大小').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium)).fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${this.textSz}`).fontSize(12).fontColor(Theme.colorOf(this.themeColor))
          }.width('100%')
          Slider({ value: this.textSz, min: 8, max: 16, step: 1, style: SliderStyle.OutSet })
            .width('100%').selectedColor(Theme.colorOf(this.themeColor))
            .trackColor($r('app.color.bg_chip')).blockColor(Color.White)
              .sliderInteractionMode(SliderInteraction.SLIDE_ONLY)
              .onChange((v: number) => { this.textSz = v; this.apply(); })
        }.width('100%').margin({ top: 12, bottom: 12 })

        Row() {
          Text('文字水平对齐').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Row({ space: 12 }) {
            Row({ space: 4 }) {
              Radio({ value: 'c', group: 'align' }).checked(this.hAlign === 0)
                .radioStyle({ checkedBackgroundColor: Theme.colorOf(this.themeColor) })
                .onChange(() => { this.hAlign = 0; this.apply(); })
              Text('居中').fontSize(13).fontColor($r('app.color.text_primary'))
            }
            Row({ space: 4 }) {
              Radio({ value: 'l', group: 'align' }).checked(this.hAlign === 1)
                .radioStyle({ checkedBackgroundColor: Theme.colorOf(this.themeColor) })
                .onChange(() => { this.hAlign = 1; this.apply(); })
              Text('靠左').fontSize(13).fontColor($r('app.color.text_primary'))
            }
            Row({ space: 4 }) {
              Radio({ value: 'r', group: 'align' }).checked(this.hAlign === 2)
                .radioStyle({ checkedBackgroundColor: Theme.colorOf(this.themeColor) })
                .onChange(() => { this.hAlign = 2; this.apply(); })
              Text('靠右').fontSize(13).fontColor($r('app.color.text_primary'))
            }
          }
        }.width('100%').margin({ top: 14, bottom: 14 })

        Row() {
          Text('文字垂直居中').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.vCenter })
            .selectedColor(Theme.colorOf(this.themeColor))
            .onChange((on: boolean) => { this.vCenter = on; this.apply(); })
        }.width('100%').margin({ top: 14, bottom: 14 })

        Divider().color($r('app.color.divider'))
        Row() {
          Text('格子内显示上课时间').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showTime })
            .selectedColor(Theme.colorOf(this.themeColor))
            .onChange((on: boolean) => { this.showTime = on; this.apply(); })
        }.width('100%').margin({ top: 14, bottom: 14 })
        Row() {
          Text('格子内显示上课地点').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showLoc })
            .selectedColor(Theme.colorOf(this.themeColor))
            .onChange((on: boolean) => { this.showLoc = on; this.apply(); })
        }.width('100%').margin({ top: 14, bottom: 14 })
        Row() {
          Text('地点前显示@').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showAt })
            .selectedColor(Theme.colorOf(this.themeColor))
            .onChange((on: boolean) => { this.showAt = on; this.apply(); })
        }.width('100%').margin({ top: 14, bottom: 14 })
        Row() {
          Text('格子内显示授课老师').fontSize(14).fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor($r('app.color.text_primary')).layoutWeight(1)
          Toggle({ type: ToggleType.Switch, isOn: this.showTch })
            .selectedColor(Theme.colorOf(this.themeColor))
            .onChange((on: boolean) => { this.showTch = on; this.apply(); })
        }.width('100%').margin({ top: 14, bottom: 14 })

        // 「恢复默认设置」：警示红文字 + 淡红玻璃底 → MaterialButton，btnTint 叠回警示红（比例 0.4）
        MaterialButton({
          btnRadius: 12,
          btnMargin: { top: 20 },
          btnBg: 'rgba(240,82,77,0.10)',
          btnTint: '#F0524D',
          btnTintRatio: 0.4,
          btnOnClick: () => {
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
            this.cellMaterial = c.cellMaterial;
            this.gridW = c.gridWidth; this.hdrSize = c.headerFontSize;
            this.borderW = c.borderWidth; this.cellH = c.cellHeight;
            this.cellR = c.cellRadius; this.cellOp = c.cellOpacity;
            this.nextOp = c.nextWeekOpacity; this.textSz = c.textSize;
            this.lineStyle = c.gridDashed ? 1 : 0;
            this.hAlign = c.textHCenter ? 0 : (c.textLeft ? 1 : 2);
            this.cfg.save();
            this.onCfgChange(this.cfg);
            this.getUIContext().getPromptAction().showToast({ message: '已恢复默认设置' });
          }
        }) {
          Text('恢复默认设置')
            .width('100%').height(44).fontSize(15).fontColor('#F0524D').textAlign(TextAlign.Center)
        }
        // 「关闭」：主题色文字 + brand_light 淡绿底 → MaterialButton，btnTint 叠回 brand_light（比例 0.7）
        MaterialButton({
          btnRadius: 12,
          btnMargin: { top: 10 },
          btnBg: $r('app.color.brand_light'),
          btnTint: '#E4F2EC',
          btnTintRatio: 0.7,
          btnOnClick: () => { this.onClose(); }
        }) {
          Text('关闭')
            .width('100%').height(44).fontSize(15).fontColor(Theme.colorOf(this.themeColor)).textAlign(TextAlign.Center)
        }
        Column().height(24)
      }
      .width('100%').padding({ left: 20, right: 20, top: 8 })
    }
    .width('100%').height('100%').scrollBar(BarState.Off).align(Alignment.Top)

    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showSecSheet, this.secSheet(), {
      detents: [SheetSize.MEDIUM, SheetSize.LARGE],
      // 关闭按钮由 MaterialSheetPanel 自绘（沉浸光感），系统 showClose 必须关掉避免双按钮
      showClose: false,
      preferType: SheetType.BOTTOM,
      // 标题改由面板内 MaterialSheetPanel 自绘（panelTitle），系统 title 不再传
      // 必须显式透明：BindOptions.backgroundColor 默认是 Color.White，
      // 而沉浸光感的视觉层级位于 backgroundColor **之下**，白底会把 MaterialSheetPanel 的材质整块盖住。
      backgroundColor: Color.Transparent,
      blurStyle: sheetBlurStyle(),
      onDisappear: () => {
        this.secPageFlag = false;
      }
    })
  }
}
