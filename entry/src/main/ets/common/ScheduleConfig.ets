/**
 * 课程表自定义配置：整体 + 课程格子两大类，JSON 持久化到 DataStore。
 * 所有字段均有默认值；修改后调用 save() 落盘，下次启动 load() 恢复。
 */
import { DataStore } from './DataStore';

/** 课程块背景色板 HEX（与 color.json course_bg_1..8 一一对应，用于文字叠加计算） */
export const COURSE_BG_HEX: string[] = [
  '#E4EEFD', '#E3F5EC', '#FCEEE1', '#EFE8FB',
  '#FCE8EC', '#E1F3F5', '#FAF1D8', '#E9ECF3'
];

/** 课程块文字色板 HEX（与 color.json course_fg_1..8 一一对应） */
export const COURSE_FG_HEX: string[] = [
  '#2C5FA8', '#1C7A52', '#A75E17', '#653BAF',
  '#A93A4E', '#177178', '#846311', '#49546A'
];

export class ScheduleConfig {
  // ===== 整体 =====
  /** 纯色背景 #RRGGBB，空 = 默认 bg_page */
  bgColor: string = '';
  /** 网格辅助线开关 */
  gridEnabled: boolean = false;
  /** 网格线粗细（vp） */
  gridWidth: number = 0.5;
  /** 网格线虚线（false=实线） */
  gridDashed: boolean = true;
  /** 表头（星期栏）背景色，空 = 默认 bg_card */
  headerColor: string = '';
  /** 表头文字大小 */
  headerFontSize: number = 12;
  /** 节次栏是否显示具体时刻 */
  showSectionTime: boolean = true;
  /** 是否显示周六周日 */
  showWeekend: boolean = true;
  /** 是否显示非本周课程（下周灰色半透明） */
  showNextWeek: boolean = false;

  // ===== 课程格子 =====
  /** 课程文字颜色，空 = 使用课程主题文字色 */
  textColor: string = '';
  /** 文字颜色叠加格子颜色（根据格子背景亮度自动取黑/白） */
  textMixWithBg: boolean = false;
  /** 格子边框颜色，空 = 无边框（需配合 borderWidth>0） */
  borderColor: string = '';
  /** 边框使用格子背景色 */
  borderUseCourseColor: boolean = false;
  /** 格子虚线边框 */
  borderDashed: boolean = false;
  /** 边框粗细（vp），0 = 无边框 */
  borderWidth: number = 0;
  /** 格子高度（vp） */
  cellHeight: number = 58;
  /** 圆角半径（vp） */
  cellRadius: number = 8;
  /** 格子不透明度（0-100） */
  cellOpacity: number = 100;
  /** 非本周课程不透明度（0-100） */
  nextWeekOpacity: number = 35;
  /** 格子内文字大小 */
  textSize: number = 11;
  /** 文字水平居中（与 textLeft/textRight 互斥） */
  textHCenter: boolean = true;
  /** 文字水平靠左（互斥开关） */
  textLeft: boolean = false;
  /** 文字水平靠右（互斥开关） */
  textRight: boolean = false;
  /** 文字垂直居中 */
  textVCenter: boolean = true;
  /** 格子内显示上课时间 */
  showTimeInCell: boolean = false;
  /** 格子内显示上课地点 */
  showLocation: boolean = true;
  /** 上课地点前显示 @ */
  showAtPrefix: boolean = false;
  /** 格子内显示授课老师 */
  showTeacher: boolean = false;

  /** 深拷贝（@State 赋值触发重渲染用） */
  clone(): ScheduleConfig {
    const c: ScheduleConfig = new ScheduleConfig();
    c.bgColor = this.bgColor;
    c.gridEnabled = this.gridEnabled;
    c.gridWidth = this.gridWidth;
    c.gridDashed = this.gridDashed;
    c.headerColor = this.headerColor;
    c.headerFontSize = this.headerFontSize;
    c.showSectionTime = this.showSectionTime;
    c.showWeekend = this.showWeekend;
    c.showNextWeek = this.showNextWeek;
    c.textColor = this.textColor;
    c.textMixWithBg = this.textMixWithBg;
    c.borderColor = this.borderColor;
    c.borderUseCourseColor = this.borderUseCourseColor;
    c.borderDashed = this.borderDashed;
    c.borderWidth = this.borderWidth;
    c.cellHeight = this.cellHeight;
    c.cellRadius = this.cellRadius;
    c.cellOpacity = this.cellOpacity;
    c.nextWeekOpacity = this.nextWeekOpacity;
    c.textSize = this.textSize;
    c.textHCenter = this.textHCenter;
    c.textLeft = this.textLeft;
    c.textRight = this.textRight;
    c.textVCenter = this.textVCenter;
    c.showTimeInCell = this.showTimeInCell;
    c.showLocation = this.showLocation;
    c.showAtPrefix = this.showAtPrefix;
    c.showTeacher = this.showTeacher;
    return c;
  }

  /** 从 DataStore 读取配置；无记录时用默认值（并迁移旧版网格虚线开关） */
  static load(): ScheduleConfig {
    const c: ScheduleConfig = new ScheduleConfig();
    const raw: string = DataStore.get(DataStore.KEY_SCHEDULE_CFG);
    if (raw.length === 0) {
      // 旧版 schedule_dashed 开关迁移：开启过则网格辅助线默认开启
      if (DataStore.get(DataStore.KEY_SCHEDULE_DASHED) !== '0') {
        c.gridEnabled = true;
      }
      return c;
    }
    try {
      const o: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      if (typeof o['bgColor'] === 'string') { c.bgColor = o['bgColor'] as string; }
      if (typeof o['gridEnabled'] === 'boolean') { c.gridEnabled = o['gridEnabled'] as boolean; }
      if (typeof o['gridWidth'] === 'number') { c.gridWidth = o['gridWidth'] as number; }
      if (typeof o['gridDashed'] === 'boolean') { c.gridDashed = o['gridDashed'] as boolean; }
      if (typeof o['headerColor'] === 'string') { c.headerColor = o['headerColor'] as string; }
      if (typeof o['headerFontSize'] === 'number') { c.headerFontSize = o['headerFontSize'] as number; }
      if (typeof o['showSectionTime'] === 'boolean') { c.showSectionTime = o['showSectionTime'] as boolean; }
      if (typeof o['showWeekend'] === 'boolean') { c.showWeekend = o['showWeekend'] as boolean; }
      if (typeof o['showNextWeek'] === 'boolean') { c.showNextWeek = o['showNextWeek'] as boolean; }
      if (typeof o['textColor'] === 'string') { c.textColor = o['textColor'] as string; }
      if (typeof o['textMixWithBg'] === 'boolean') { c.textMixWithBg = o['textMixWithBg'] as boolean; }
      if (typeof o['borderColor'] === 'string') { c.borderColor = o['borderColor'] as string; }
      if (typeof o['borderUseCourseColor'] === 'boolean') { c.borderUseCourseColor = o['borderUseCourseColor'] as boolean; }
      if (typeof o['borderDashed'] === 'boolean') { c.borderDashed = o['borderDashed'] as boolean; }
      if (typeof o['borderWidth'] === 'number') { c.borderWidth = o['borderWidth'] as number; }
      if (typeof o['cellHeight'] === 'number') { c.cellHeight = o['cellHeight'] as number; }
      if (typeof o['cellRadius'] === 'number') { c.cellRadius = o['cellRadius'] as number; }
      if (typeof o['cellOpacity'] === 'number') { c.cellOpacity = o['cellOpacity'] as number; }
      if (typeof o['nextWeekOpacity'] === 'number') { c.nextWeekOpacity = o['nextWeekOpacity'] as number; }
      if (typeof o['textSize'] === 'number') { c.textSize = o['textSize'] as number; }
      if (typeof o['textHCenter'] === 'boolean') { c.textHCenter = o['textHCenter'] as boolean; }
      if (typeof o['textLeft'] === 'boolean') { c.textLeft = o['textLeft'] as boolean; }
      if (typeof o['textRight'] === 'boolean') { c.textRight = o['textRight'] as boolean; }
      if (typeof o['textVCenter'] === 'boolean') { c.textVCenter = o['textVCenter'] as boolean; }
      if (typeof o['showTimeInCell'] === 'boolean') { c.showTimeInCell = o['showTimeInCell'] as boolean; }
      if (typeof o['showLocation'] === 'boolean') { c.showLocation = o['showLocation'] as boolean; }
      if (typeof o['showAtPrefix'] === 'boolean') { c.showAtPrefix = o['showAtPrefix'] as boolean; }
      if (typeof o['showTeacher'] === 'boolean') { c.showTeacher = o['showTeacher'] as boolean; }
    } catch (e) {
      // 解析失败用默认值
    }
    return c;
  }

  /** 落盘保存 */
  save(): void {
    const o: Record<string, Object> = {
      'bgColor': this.bgColor,
      'gridEnabled': this.gridEnabled,
      'gridWidth': this.gridWidth,
      'gridDashed': this.gridDashed,
      'headerColor': this.headerColor,
      'headerFontSize': this.headerFontSize,
      'showSectionTime': this.showSectionTime,
      'showWeekend': this.showWeekend,
      'showNextWeek': this.showNextWeek,
      'textColor': this.textColor,
      'textMixWithBg': this.textMixWithBg,
      'borderColor': this.borderColor,
      'borderUseCourseColor': this.borderUseCourseColor,
      'borderDashed': this.borderDashed,
      'borderWidth': this.borderWidth,
      'cellHeight': this.cellHeight,
      'cellRadius': this.cellRadius,
      'cellOpacity': this.cellOpacity,
      'nextWeekOpacity': this.nextWeekOpacity,
      'textSize': this.textSize,
      'textHCenter': this.textHCenter,
      'textLeft': this.textLeft,
      'textRight': this.textRight,
      'textVCenter': this.textVCenter,
      'showTimeInCell': this.showTimeInCell,
      'showLocation': this.showLocation,
      'showAtPrefix': this.showAtPrefix,
      'showTeacher': this.showTeacher
    };
    DataStore.setScheduleCfg(JSON.stringify(o));
  }
}
