/**
 * 空闲教室查询（纯 UI 模板，不依赖网络）
 * 查询条件自上而下：学年学期 / 校区 / 楼号 / 场地类别(一级) → 场地二级类别(联动) /
 * 周次(多选) / 星期(多选) / 节次(多选) / 座位数范围 / 场地名称，右上角一键清空（保留学年学期+校区）。
 *
 * 模板说明：
 * - 学年学期：本地生成（buildLocalTerms，纯计算无网络）
 * - 校区/楼号/场地类别/场地二级类别：页面内静态数据，二级随一级联动
 * - 周次/星期/节次：多选（FlowRow 横排换行，至少选 1 项），选中项回显到选项框（PickRow Marquee 滚动防溢出）
 * - 查询按钮：点击后生成本地模拟教室数据，整页可滚动查看结果，底部左右翻页 + 页数指示
 * - 结果卡片：场地名称 / 座位数 / 是否可用；点击弹详情（编号/校区/类别/楼号/楼层/借用类型/备注/使用部门/使用班级）
 * - 不发起任何真实网络请求、不注入 Cookie、无网页版兜底
 */
import { promptAction } from '@kit.ArkUI';
import { JwApi } from '../api/JwApi';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { Theme } from '../common/ThemeUtil';
import { EmptyRoomCondition, EmptyRoomItem, TermInfo } from '../model/Models';
import { EmptyTip, LoadingTip, PickRow } from './common/UiKit';
import { WebSurface } from './WebSurface';

/** 静态条件数据（模板演示用，后续接真实接口时替换为服务端下发的选项） */
const STATIC_CAMPUS: EmptyRoomCondition[] = [
  { code: '', name: '全部' },
  { code: '1', name: '老满城校区' },
  { code: '2', name: '亚心校区' },
  { code: '3', name: '塔城校区' }
];
const STATIC_BUILDING: EmptyRoomCondition[] = [
  { code: '', name: '全部' },
  { code: '01', name: '主教学楼' },
  { code: '02', name: '综合实验楼' },
  { code: '03', name: '博学楼' },
  { code: '04', name: '图书馆' }
];
const STATIC_ROOM_TYPE: EmptyRoomCondition[] = [
  { code: '', name: '全部' },
  { code: '1', name: '普通教室' },
  { code: '2', name: '多媒体教室' },
  { code: '3', name: '实验室' },
  { code: '4', name: '机房' },
  { code: '5', name: '报告厅' }
];
/** 场地二级类别（按一级类别 code 联动） */
const STATIC_SUB_TYPES: Record<string, EmptyRoomCondition[]> = {
  '1': [{ code: '11', name: '普通小教室' }, { code: '12', name: '普通大教室' }],
  '2': [{ code: '21', name: '多媒体小教室' }, { code: '22', name: '多媒体大教室' }, { code: '23', name: '智慧教室' }],
  '3': [{ code: '31', name: '化学实验室' }, { code: '32', name: '物理实验室' }, { code: '33', name: '计算机实验室' }],
  '4': [{ code: '41', name: '公共机房' }, { code: '42', name: '专业机房' }],
  '5': [{ code: '51', name: '大型报告厅' }, { code: '52', name: '中型报告厅' }]
};

@Component
export struct KxjsPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  // 学年学期（本地生成）
  @State terms: TermInfo[] = [];
  @State selectedTermIndex: number = 0;
  @State termLabel: string = '加载中…';
  // 条件列表（静态模板数据）
  @State campusList: EmptyRoomCondition[] = STATIC_CAMPUS;
  @State buildingList: EmptyRoomCondition[] = STATIC_BUILDING;
  @State roomTypeList: EmptyRoomCondition[] = STATIC_ROOM_TYPE;
  @State subTypeList: EmptyRoomCondition[] = [];
  @State campusIndex: number = 0;
  @State buildingIndex: number = 0;
  @State roomTypeIndex: number = 0;
  @State subTypeIndex: number = 0;
  @State campusLabel: string = '';
  @State buildingLabel: string = '';
  @State roomTypeLabel: string = '';
  @State subTypeLabel: string = '未选择';
  // 多选集合（默认选第 1 项，满足"至少选一个"）
  @State weeksSet: number[] = [1];
  @State weekdaysSet: number[] = [1];
  @State sectionsSet: number[] = [1];
  @State weekLabel: string = '第 1 周';
  @State weekdayLabel: string = '周一';
  @State sectionLabel: string = '第 1 节';
  // 座位数范围 + 场地名称
  @State seatMinText: string = '';
  @State seatMaxText: string = '';
  @State roomName: string = '';
  // 结果
  @State rooms: EmptyRoomItem[] = [];
  @State resultMessage: string = '';
  @State loading: boolean = false;
  // 翻页（每页 15 条）
  @State pageIndex: number = 1;
  private readonly pageSize: number = 15;
  // 多选弹窗（bindSheet，挂外层）
  @State showMultiPicker: boolean = false;
  @State multiPickerTitle: string = '';
  @State multiPickerOptions: string[] = [];
  @State multiPickerAllValues: number[] = [];
  @State multiPickerTempSet: number[] = [];
  // 单选弹窗（bindSheet 自定义列表；挂内层，TextPickerDialog 的 onAccept 闭包修改 @State 不刷新 UI，改用手动列表）
  @State showSingleSheet: boolean = false;
  @State singlePickerTitle: string = '';
  @State singlePickerOptions: string[] = [];
  @State singlePickerKind: string = ''; // term / campus / building / roomType / subType
  @State singlePickerSelected: number = 0;
  // 详情弹窗（bindSheet，挂底部安全区）
  @State showDetail: boolean = false;
  @State selectedRoom: EmptyRoomItem | null = null;
  // 网页版查询（WebView 弹层，共享登录 Cookie）
  @State showWeb: boolean = false;

  aboutToAppear(): void {
    this.initLocalData();
    this.loadRemoteConditions();
  }

  /** 初始化本地数据（无网络，秒开学期与静态条件） */
  private initLocalData(): void {
    // 学年学期：本地生成
    this.terms = JwApi.buildLocalTerms();
    if (this.terms.length > 0) {
      const targetIdx: number = this.terms.findIndex((t: TermInfo) => t.id === AppState.term.id);
      this.selectedTermIndex = targetIdx >= 0 ? targetIdx : 0;
      this.termLabel = this.terms[this.selectedTermIndex].label;
    }
    // 条件列表：先用静态数据秒开
    this.campusIndex = 0;
    this.buildingIndex = 0;
    this.roomTypeIndex = 0;
    this.campusLabel = this.campusList.length > 0 ? this.campusList[0].name : '全部';
    this.buildingLabel = this.buildingList.length > 0 ? this.buildingList[0].name : '全部';
    this.roomTypeLabel = this.roomTypeList.length > 0 ? this.roomTypeList[0].name : '全部';
    if (this.roomTypeList.length > 0) {
      this.loadSubTypes(this.roomTypeList[0].code);
    }
  }

  /** 异步加载服务端条件选项（校区/楼号/场地类别），成功替换静态数据，失败保留静态 */
  private async loadRemoteConditions(): Promise<void> {
    try {
      const conds = await JwApi.getEmptyRoomConditions();
      if (conds.campus.length > 0) {
        this.campusList = conds.campus;
        this.campusIndex = 0;
        this.campusLabel = conds.campus[0].name;
      }
      if (conds.building.length > 0) {
        this.buildingList = conds.building;
        this.buildingIndex = 0;
        this.buildingLabel = conds.building[0].name;
      }
      if (conds.roomType.length > 0) {
        this.roomTypeList = conds.roomType;
        this.roomTypeIndex = 0;
        this.roomTypeLabel = conds.roomType[0].name;
        this.loadSubTypes(conds.roomType[0].code);
      }
    } catch (e) {
      // 网络失败保留静态数据，无提示
    }
  }

  private currentTerm(): TermInfo {
    if (this.selectedTermIndex >= 0 && this.selectedTermIndex < this.terms.length) {
      return this.terms[this.selectedTermIndex];
    }
    return AppState.term;
  }

  /** 选完一级场地类别后联动加载二级类别（先真实接口，失败降级静态映射） */
  private async loadSubTypes(parentCode: string): Promise<void> {
    this.subTypeList = STATIC_SUB_TYPES[parentCode] ?? [];
    this.subTypeIndex = 0;
    this.subTypeLabel = this.subTypeList.length > 0 ? this.subTypeList[0].name : '全部';
    try {
      const remote = await JwApi.getSubRoomTypes(parentCode);
      if (remote.length > 0) {
        this.subTypeList = remote;
        this.subTypeIndex = 0;
        this.subTypeLabel = remote[0].name;
      }
    } catch (e) {
      // 失败保留静态数据
    }
  }

  private codeOf(list: EmptyRoomCondition[], index: number): string {
    if (index >= 0 && index < list.length) {
      return list[index].code;
    }
    return '';
  }

  private async query(): Promise<void> {
    this.loading = true;
    this.resultMessage = '';
    this.pageIndex = 1;
    try {
      const res = await JwApi.queryEmptyRooms({
        termId: this.currentTerm().id,
        campus: this.codeOf(this.campusList, this.campusIndex),
        building: this.codeOf(this.buildingList, this.buildingIndex),
        roomType: this.codeOf(this.roomTypeList, this.roomTypeIndex),
        roomSubType: this.codeOf(this.subTypeList, this.subTypeIndex),
        seatMin: this.seatMinText,
        seatMax: this.seatMaxText,
        roomName: this.roomName,
        weeks: this.weeksSet,
        weekdays: this.weekdaysSet,
        sections: this.sectionsSet
      });
      this.rooms = res.rooms;
      this.resultMessage = res.message;
      if (this.rooms.length === 0 && this.resultMessage.length === 0) {
        this.resultMessage = '该条件下暂无可用的空闲教室，可尝试调整条件';
      }
    } catch (e) {
      this.resultMessage = '查询失败，请检查网络或稍后重试';
    } finally {
      this.loading = false;
    }
  }

  /** 一键清空（保留学年学期 + 校区，其余全部重置/清空） */
  private resetAll(): void {
    this.buildingIndex = 0;
    this.roomTypeIndex = 0;
    this.buildingLabel = this.buildingList.length > 0 ? this.buildingList[0].name : '全部';
    this.roomTypeLabel = this.roomTypeList.length > 0 ? this.roomTypeList[0].name : '全部';
    // 二级类别随一级重置
    this.subTypeList = [];
    this.subTypeIndex = 0;
    this.subTypeLabel = '未选择';
    if (this.roomTypeList.length > 0) {
      this.loadSubTypes(this.roomTypeList[0].code);
    }
    // 多选重置为默认第 1 项（至少选 1 个）
    this.weeksSet = [1];
    this.weekdaysSet = [1];
    this.sectionsSet = [1];
    this.weekLabel = '第 1 周';
    this.weekdayLabel = '周一';
    this.sectionLabel = '第 1 节';
    // 座位数范围 + 场地名称
    this.seatMinText = '';
    this.seatMaxText = '';
    this.roomName = '';
    this.pageIndex = 1;
    this.rooms = [];
    this.resultMessage = '';
    promptAction.showToast({ message: '已清空', duration: 1500 });
  }

  /** 打开网页版空闲教室查询（WebView 共享登录 Cookie） */
  private openWebQuery(): void {
    if (JwApi.USE_MOCK) {
      promptAction.showToast({ message: '当前模式暂不支持' });
      return;
    }
    AppState.webUrl =
      `https://jwxt.xjau.edu.cn/jwglxt/cdjy/cdjy_cxKxcdlb.html?gnmkdm=N2155&layout=default&su=${AppState.account}`;
    AppState.webTitle = '空教室查询（网页版）';
    this.showWeb = true;
  }

  /** 总页数（至少 1） */
  private pageCount(): number {
    return Math.max(1, Math.ceil(this.rooms.length / this.pageSize));
  }

  /** 当前页的房间列表 */
  private pagedRooms(): EmptyRoomItem[] {
    const start: number = (this.pageIndex - 1) * this.pageSize;
    return this.rooms.slice(start, start + this.pageSize);
  }

  /** 打开单选弹窗：填充数据后置 showSingleSheet=true（在弹窗点击项内直接修改 @State，确保 UI 刷新） */
  private openSingleSheet(title: string, kind: string, options: string[], selected: number): void {
    this.singlePickerTitle = title;
    this.singlePickerKind = kind;
    this.singlePickerOptions = options;
    this.singlePickerSelected = selected;
    this.showSingleSheet = true;
  }

  /** 单选弹窗内点击选项：根据 kind 直接修改对应 @State 字段（不走闭包回调，响应式正常触发） */
  private selectSingleOption(index: number): void {
    const kind: string = this.singlePickerKind;
    if (kind === 'term') {
      this.selectedTermIndex = index;
      this.termLabel = this.terms[index].label;
    } else if (kind === 'campus') {
      this.campusIndex = index;
      this.campusLabel = this.campusList[index].name;
    } else if (kind === 'building') {
      this.buildingIndex = index;
      this.buildingLabel = this.buildingList[index].name;
    } else if (kind === 'roomType') {
      this.roomTypeIndex = index;
      this.roomTypeLabel = this.roomTypeList[index].name;
      this.loadSubTypes(this.roomTypeList[index].code);
    } else if (kind === 'subType') {
      this.subTypeIndex = index;
      this.subTypeLabel = this.subTypeList[index].name;
    }
    this.showSingleSheet = false;
  }

  /** 学年学期 */
  private openTermPicker(): void {
    if (this.terms.length === 0) {
      return;
    }
    this.openSingleSheet('选择学年-学期', 'term', this.terms.map((t: TermInfo) => t.label), this.selectedTermIndex);
  }

  /** 校区 */
  private openCampusPicker(): void {
    if (this.campusList.length === 0) {
      return;
    }
    this.openSingleSheet('选择校区', 'campus', this.campusList.map((c: EmptyRoomCondition) => c.name), this.campusIndex);
  }

  /** 楼号 */
  private openBuildingPicker(): void {
    if (this.buildingList.length === 0) {
      return;
    }
    this.openSingleSheet('选择楼号', 'building', this.buildingList.map((c: EmptyRoomCondition) => c.name), this.buildingIndex);
  }

  /** 场地类别（一级）：选完联动加载二级 */
  private openRoomTypePicker(): void {
    if (this.roomTypeList.length === 0) {
      return;
    }
    this.openSingleSheet('选择场地类别', 'roomType', this.roomTypeList.map((c: EmptyRoomCondition) => c.name), this.roomTypeIndex);
  }

  /** 场地二级类别（须先选一级） */
  private openSubTypePicker(): void {
    if (this.subTypeList.length === 0) {
      promptAction.showToast({ message: '请先选择场地类别' });
      return;
    }
    this.openSingleSheet('选择场地二级类别', 'subType', this.subTypeList.map((c: EmptyRoomCondition) => c.name), this.subTypeIndex);
  }

  /** 周次 */
  private openWeekPicker(): void {
    const total: number = this.currentTerm().totalWeeks > 0 ? this.currentTerm().totalWeeks : 20;
    const options: string[] = [];
    const allValues: number[] = [];
    for (let w: number = 1; w <= total; w++) {
      options.push(`第${w}周`);
      allValues.push(w);
    }
    this.openMultiPicker('选择周次', options, allValues, this.weeksSet);
  }

  /** 星期 */
  private openWeekdayPicker(): void {
    const allValues: number[] = [1, 2, 3, 4, 5, 6, 7];
    this.openMultiPicker('选择星期', Const.WEEK_LABELS, allValues, this.weekdaysSet);
  }

  /** 节次 */
  private openSectionPicker(): void {
    const options: string[] = [];
    const allValues: number[] = [];
    for (let s: number = 1; s <= Const.SECTION_COUNT; s++) {
      options.push(`第${s}节`);
      allValues.push(s);
    }
    this.openMultiPicker('选择节次', options, allValues, this.sectionsSet);
  }

  /** 多选弹窗：bindSheet + FlowRow 横排（TextPicker 不支持多选） */
  private openMultiPicker(title: string, options: string[], allValues: number[], initialSet: number[]): void {
    this.multiPickerTitle = title;
    this.multiPickerOptions = options;
    this.multiPickerAllValues = allValues;
    this.multiPickerTempSet = [...initialSet];
    this.showMultiPicker = true;
  }

  private toggleMultiPicker(index: number): void {
    const val: number = this.multiPickerAllValues[index];
    const idx: number = this.multiPickerTempSet.indexOf(val);
    if (idx >= 0) {
      const copy: number[] = [...this.multiPickerTempSet];
      copy.splice(idx, 1);
      this.multiPickerTempSet = copy;
    } else {
      this.multiPickerTempSet = [...this.multiPickerTempSet, val];
    }
  }

  private togglePickAll(): void {
    if (this.multiPickerTempSet.length === this.multiPickerAllValues.length) {
      this.multiPickerTempSet = [];
    } else {
      this.multiPickerTempSet = [...this.multiPickerAllValues];
    }
  }

  private confirmMultiPicker(): void {
    if (this.multiPickerTempSet.length === 0) {
      promptAction.showToast({ message: '请至少选择 1 项' });
      return;
    }
    const t: string = this.multiPickerTitle;
    const sorted: number[] = [...this.multiPickerTempSet].sort((a: number, b: number) => a - b);
    if (t === '选择周次') {
      this.weeksSet = sorted;
      this.weekLabel = sorted.map((w: number) => `第${w}周`).join(' · ');
    } else if (t === '选择星期') {
      this.weekdaysSet = sorted;
      this.weekdayLabel = sorted.map((w: number) => Const.WEEK_LABELS[w - 1]).join(' · ');
    } else if (t === '选择节次') {
      this.sectionsSet = sorted;
      this.sectionLabel = sorted.map((s: number) => `第${s}节`).join(' · ');
    }
    this.showMultiPicker = false;
  }

  /** 字段是否全空 */
  private hasField(arr: string[]): boolean {
    for (let i: number = 0; i < arr.length; i++) {
      if (arr[i].length > 0) {
        return true;
      }
    }
    return false;
  }

  /** 是否可借用 */
  private isBorrowable(sfkfy: string): boolean {
    const v: string = sfkfy.trim();
    return v === '1' || v === '是' || v === 'true' || v === 'Y';
  }

  private borrowableLabel(sfkfy: string): string {
    return this.isBorrowable(sfkfy) ? '可借用' : '不可借用';
  }

  private borrowableColor(sfkfy: string): Resource {
    return this.isBorrowable(sfkfy) ? $r('app.color.brand') : $r('app.color.text_tertiary');
  }

  private borrowableBg(sfkfy: string): string {
    return this.isBorrowable(sfkfy) ? '#E6F7EC' : '#F2F2F2';
  }

  /** 翻页控件（左右按钮 + 页数指示，普通翻页样式） */
  @Builder
  pageControl() {
    Row() {
      Button('‹')
        .fontSize(18)
        .fontColor(this.pageIndex > 1 ? $r('app.color.brand') : $r('app.color.text_tertiary'))
        .backgroundColor(this.pageIndex > 1 ? $r('app.color.brand_light') : $r('app.color.bg_chip'))
        .borderRadius(8)
        .width(40)
        .height(34)
        .enabled(this.pageIndex > 1)
        .onClick(() => {
          if (this.pageIndex > 1) {
            this.pageIndex--;
          }
        })
      Blank()
      Text(
        this.rooms.length > 0
          ? `${this.pageIndex} / ${this.pageCount()}`
          : ''
      )
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
      Blank()
      Button('›')
        .fontSize(18)
        .fontColor(this.pageIndex < this.pageCount() ? $r('app.color.brand') : $r('app.color.text_tertiary'))
        .backgroundColor(this.pageIndex < this.pageCount() ? $r('app.color.brand_light') : $r('app.color.bg_chip'))
        .borderRadius(8)
        .width(40)
        .height(34)
        .enabled(this.pageIndex < this.pageCount())
        .onClick(() => {
          if (this.pageIndex < this.pageCount()) {
            this.pageIndex++;
          }
        })
    }
    .width('100%')
    .padding({ top: 10, bottom: 4 })
  }

  /** 房间卡片：精简为 场地名称 / 座位数 / 是否可用，点击看详情 */
  @Builder
  roomCard(item: EmptyRoomItem) {
    Column() {
      Row() {
        Text(item.cdmc)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        if (item.sfkfy.length > 0) {
          Text(this.borrowableLabel(item.sfkfy))
            .fontSize(11)
            .fontColor(this.borrowableColor(item.sfkfy))
            .backgroundColor(this.borrowableBg(item.sfkfy))
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(10)
            .margin({ left: 8 })
        }
      }
      .width('100%')

      Row() {
        Column()
          .width(6)
          .height(6)
          .borderRadius(3)
          .backgroundColor($r('app.color.brand'))
          .margin({ right: 6 })
        Text(`${item.sjzws} 人`)
          .fontSize(12)
          .fontColor($r('app.color.brand'))
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor($r('app.color.brand_light'))
          .borderRadius(4)
        Column()
          .width(6)
          .height(6)
          .borderRadius(3)
          .backgroundColor($r('app.color.text_tertiary'))
          .margin({ left: 12, right: 6 })
        Text(item.time)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding(14)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(14)
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.selectedRoom = item;
      this.showDetail = true;
    })
  }

  build() {
    NavDestination() {
      Column() {
        // 顶栏：返回 + 标题 + 右上角 网页版 / 清空
        Row() {
          Text('‹')
            .fontSize(26)
            .fontColor(this.isDarkMode ? $r('app.color.text_primary') : Color.White)
            .width(34)
            .height(34)
            .textAlign(TextAlign.Center)
            .onClick(() => {
              AppState.stack.pop();
            })
          Text('空闲教室查询')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isDarkMode ? $r('app.color.text_primary') : Color.White)
            .margin({ left: 6 })
            .layoutWeight(1)
          Text('网页版')
            .fontSize(13)
            .fontColor(this.isDarkMode ? $r('app.color.text_secondary') : Color.White)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor(this.isDarkMode ? $r('app.color.bg_chip') : '#26FFFFFF')
            .borderRadius(14)
            .onClick(() => {
              this.openWebQuery();
            })
          Text('清空')
            .fontSize(13)
            .fontColor(this.isDarkMode ? $r('app.color.text_secondary') : Color.White)
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor(this.isDarkMode ? $r('app.color.bg_chip') : '#26FFFFFF')
            .borderRadius(14)
            .margin({ left: 8 })
            .onClick(() => {
              this.resetAll();
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .padding({ left: 10, right: 16, bottom: 14, top: px2vp(this.topInsetPx) + 10 })
        .backgroundColor(this.isDarkMode ? '#1A1D1C' : Theme.colorOf(this.themeColor))
        // 详情弹窗（挂顶栏 Row，与单选/多选弹窗分离避免 bindSheet 相互覆盖）
        .bindSheet($$this.showDetail, this.detailSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          backgroundColor: $r('app.color.bg_card'),
          title: { title: '场地详情' }
        })

        // 内容区：整页可滚动（条件卡 + 结果列表 + 底部翻页）
        Column() {
          Scroll() {
            Column() {
              // 查询条件卡
              Column() {
                // 单选：学年学期 / 校区 / 楼号 / 场地类别 / 场地二级类别（PickRow 为 @Component + @Prop，状态变化实时刷新）
                PickRow({ label: '学年学期', value: this.termLabel, placeholder: '请选择', onTap: () => this.openTermPicker() })
                PickRow({ label: '校区', value: this.campusLabel, placeholder: '请选择', onTap: () => this.openCampusPicker() })
                PickRow({ label: '楼号', value: this.buildingLabel, placeholder: '全部', onTap: () => this.openBuildingPicker() })
                PickRow({ label: '场地类别', value: this.roomTypeLabel, placeholder: '请选择', onTap: () => this.openRoomTypePicker() })
                PickRow({ label: '场地二级类别', value: this.subTypeLabel, placeholder: '请先选场地类别', onTap: () => this.openSubTypePicker() })

                // 多选：周次 / 星期 / 节次（至少选 1 项）
                PickRow({ label: '周次', value: this.weekLabel, placeholder: '请选择', onTap: () => this.openWeekPicker() })
                PickRow({ label: '星期', value: this.weekdayLabel, placeholder: '请选择', onTap: () => this.openWeekdayPicker() })
                PickRow({ label: '节次', value: this.sectionLabel, placeholder: '请选择', onTap: () => this.openSectionPicker() })

                // 座位数范围（从 ~ 至）
                Row() {
                  Text('座位数')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .width(86)
                  Blank()
                  TextInput({ placeholder: '不限', text: this.seatMinText })
                    .type(InputType.Number)
                    .fontSize(13)
                    .placeholderColor($r('app.color.text_tertiary'))
                    .backgroundColor($r('app.color.bg_page'))
                    .borderRadius(8)
                    .height(36)
                    .width(72)
                    .onChange((v: string) => {
                      this.seatMinText = v;
                    })
                  Text('至')
                    .fontSize(13)
                    .fontColor($r('app.color.text_tertiary'))
                    .margin({ left: 6, right: 6 })
                  TextInput({ placeholder: '不限', text: this.seatMaxText })
                    .type(InputType.Number)
                    .fontSize(13)
                    .placeholderColor($r('app.color.text_tertiary'))
                    .backgroundColor($r('app.color.bg_page'))
                    .borderRadius(8)
                    .height(36)
                    .width(72)
                    .onChange((v: string) => {
                      this.seatMaxText = v;
                    })
                  Text('人')
                    .fontSize(13)
                    .fontColor($r('app.color.text_tertiary'))
                    .margin({ left: 6 })
                }
                .width('100%')
                .height(46)
                .padding({ left: 10, right: 10 })
                .backgroundColor($r('app.color.bg_chip'))
                .borderRadius(10)
                .margin({ bottom: 10 })

                // 场地名称
                Row() {
                  Text('场地名称')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                    .width(86)
                  Blank()
                  TextInput({ placeholder: '场地名称或编号', text: this.roomName })
                    .fontSize(13)
                    .textAlign(TextAlign.End)
                    .placeholderColor($r('app.color.text_tertiary'))
                    .backgroundColor($r('app.color.bg_page'))
                    .borderRadius(8)
                    .height(36)
                    .layoutWeight(1)
                    .onChange((v: string) => {
                      this.roomName = v;
                    })
                }
                .width('100%')
                .height(46)
                .padding({ left: 10, right: 10 })
                .backgroundColor($r('app.color.bg_chip'))
                .borderRadius(10)
                .margin({ bottom: 10 })

                Button(this.loading ? '查询中…' : '查询空闲教室')
                  .width('100%')
                  .height(44)
                  .fontSize(15)
                  .fontColor($r('app.color.brand_on'))
                  .backgroundColor($r('app.color.brand'))
                  .borderRadius(12)
                  .margin({ top: 4 })
                  .enabled(!this.loading)
                  .onClick(() => {
                    this.query();
                  })
              }
              .width('100%')
              .padding(16)
              .backgroundColor($r('app.color.bg_card'))
              .borderRadius(18)
              .margin({ bottom: 14 })

              // 查询结果
              Row() {
                Text('查询结果')
                  .fontSize(14)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Text(this.rooms.length > 0 ? `共 ${this.rooms.length} 间空闲教室` : '')
                  .fontSize(11)
                  .fontColor($r('app.color.text_tertiary'))
              }
              .width('100%')
              .margin({ bottom: 10 })

              if (this.loading) {
                LoadingTip({ text: '正在查询空闲教室…' })
                  .width('100%')
                  .height(140)
                  .backgroundColor($r('app.color.bg_card'))
                  .borderRadius(18)
              } else if (this.rooms.length > 0) {
                // 当前页卡片
                ForEach(this.pagedRooms(), (item: EmptyRoomItem) => {
                  Column() {
                    this.roomCard(item)
                  }
                  .margin({ bottom: 10 })
                }, (item: EmptyRoomItem) => `${item.cdbh}-${item.cdmc}-${item.time}`)
                // 底部翻页（左右按钮 + 页数）
                this.pageControl()
              } else {
                Column() {
                  EmptyTip({ text: this.resultMessage.length > 0 ? this.resultMessage : '点击上方"查询"获取空闲教室情况' })
                  Text(`当前条件：${this.weekLabel} ${this.weekdayLabel} ${this.sectionLabel}`)
                    .fontSize(11)
                    .fontColor($r('app.color.text_tertiary'))
                    .margin({ top: 8 })
                }
                .width('100%')
                .padding(20)
                .backgroundColor($r('app.color.bg_card'))
                .borderRadius(18)
              }
              // 底部抬高（参考学业情况页，避免内容贴底）
              Column()
                .height(px2vp(this.bottomInsetPx) + 24)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 14 })
          }
          .scrollBar(BarState.Off)
          .layoutWeight(1)
          .align(Alignment.Top)
          .edgeEffect(EdgeEffect.Spring)
          // 网页版查询弹层（挂 Scroll，与顶栏详情/单选/多选弹窗分离）
          .bindSheet($$this.showWeb, this.webSheet(), {
            height: SheetSize.LARGE,
            dragBar: false,
            backgroundColor: $r('app.color.bg_page'),
            title: { title: AppState.webTitle }
          })
        }
        .layoutWeight(1)
        .width('100%')
        .backgroundColor($r('app.color.bg_page'))
        // 单选弹窗（挂内层容器，与外层多选弹窗分离避免 bindSheet 相互覆盖）
        .bindSheet($$this.showSingleSheet, this.singlePickerSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: true,
          backgroundColor: $r('app.color.bg_card'),
          title: { title: this.singlePickerTitle }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
      // 多选弹窗（bindSheet，组件上挂不同 bindSheet 避免冲突）
      .bindSheet($$this.showMultiPicker, this.multiPickerSheet(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        backgroundColor: $r('app.color.bg_card'),
        title: { title: this.multiPickerTitle }
      })
    }
    .hideTitleBar(true)
  }

  /** 单选弹窗（bindSheet + 自定义 List，点击项直接修改 @State 并关闭） */
  @Builder
  singlePickerSheet() {
    Column() {
      Scroll() {
        Column() {
          ForEach(this.singlePickerOptions, (opt: string, index: number) => {
            Row() {
              Text(opt)
                .fontSize(14)
                .fontColor(this.singlePickerSelected === index ? $r('app.color.brand_on') : $r('app.color.text_primary'))
                .layoutWeight(1)
              if (this.singlePickerSelected === index) {
                Text('✓')
                  .fontSize(16)
                  .fontColor($r('app.color.brand_on'))
              }
            }
            .width('100%')
            .height(46)
            .padding({ left: 16, right: 16 })
            .backgroundColor(this.singlePickerSelected === index ? $r('app.color.brand') : $r('app.color.bg_chip'))
            .borderRadius(10)
            .margin({ bottom: 8 })
            .onClick(() => {
              this.selectSingleOption(index);
            })
          }, (opt: string, index: number) => `${opt}-${index}`)
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: 360 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
  }

  /** 多选弹窗：Flex 横排换行 + 底部全选/确定（避免右上角与关闭按钮遮挡） */
  @Builder
  multiPickerSheet() {
    Column() {
      Scroll() {
        Column() {
          // 固定宽度均分布局：每行 5 个，Flex 自动均分间距，整齐对齐
          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.SpaceBetween }) {
            ForEach(this.multiPickerOptions, (opt: string, index: number) => {
              Row() {
                Text(opt)
                  .fontSize(13)
                  .fontColor(this.multiPickerTempSet.indexOf(this.multiPickerAllValues[index]) >= 0
                    ? $r('app.color.brand_on')
                    : $r('app.color.text_primary'))
              }
              .width('18%')
              .height(34)
              .justifyContent(FlexAlign.Center)
              .backgroundColor(this.multiPickerTempSet.indexOf(this.multiPickerAllValues[index]) >= 0
                ? $r('app.color.brand')
                : $r('app.color.bg_chip'))
              .borderRadius(17)
              .margin({ bottom: 10 })
              .onClick(() => {
                this.toggleMultiPicker(index);
              })
            }, (opt: string, index: number) => `${opt}-${index}`)
          }
          .width('100%')
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: 300 })

      // 底部操作行（全选/全清 + 已选数 + 确定）
      Row() {
        Text(this.multiPickerTempSet.length <= 0 ? '请至少选择 1 项' : `已选 ${this.multiPickerTempSet.length} 项`)
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
        Blank()
        Text(this.multiPickerTempSet.length === this.multiPickerAllValues.length ? '全清' : '全选')
          .fontSize(13)
          .fontColor($r('app.color.brand'))
          .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.brand_light'))
          .borderRadius(16)
          .onClick(() => {
            this.togglePickAll();
          })
        Button('确定')
          .fontSize(14)
          .fontColor($r('app.color.brand_on'))
          .backgroundColor($r('app.color.brand'))
          .borderRadius(18)
          .height(36)
          .padding({ left: 20, right: 20 })
          .margin({ left: 12 })
          .onClick(() => {
            this.confirmMultiPicker();
          })
      }
      .width('100%')
      .margin({ top: 8 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
  }

  /** 网页版空教室查询（WebView 共享登录 Cookie） */
  @Builder
  webSheet() {
    Column() {
      WebSurface()
    }
    .width('100%')
    .height('100%')
  }

  /** 详情弹窗：场地编号/校区/场地类别/楼号/楼层/借用类型/备注/使用部门/使用班级 */
  @Builder
  detailSheet() {
    Column() {
      if (this.selectedRoom !== null) {
        Row() {
          Column()
            .width(4)
            .height(20)
            .borderRadius(2)
            .backgroundColor($r('app.color.brand'))
          Text(this.selectedRoom.cdmc)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 8 })
            .layoutWeight(1)
          if (this.selectedRoom.sfkfy.length > 0) {
            Text(this.borrowableLabel(this.selectedRoom.sfkfy))
              .fontSize(11)
              .fontColor(this.borrowableColor(this.selectedRoom.sfkfy))
              .backgroundColor(this.borrowableBg(this.selectedRoom.sfkfy))
              .padding({ left: 8, right: 8, top: 3, bottom: 3 })
              .borderRadius(10)
          }
        }
        .width('100%')
        .margin({ bottom: 16 })

        this.detailRow('场地编号', this.selectedRoom.cdbh, '#079841')
        this.detailRow('校区', this.selectedRoom.xqmc, '#3B82F6')
        this.detailRow('场地类别', this.selectedRoom.cdlbmc, '#FF9800')
        this.detailRow('楼号', this.selectedRoom.jxlmc, '#8B5CF6')
        this.detailRow('楼层号', this.selectedRoom.lch.length > 0 ? `${this.selectedRoom.lch} 层` : '', '#06B6D4')
        this.detailRow('场地借用类型', this.borrowableLabel(this.selectedRoom.sfkfy), '#EC4899')
        this.detailRow('场地备注', this.selectedRoom.bz, '#9E9E9E')
        this.detailRow('使用部门', this.selectedRoom.sybmmc, '#14B8A6')
        this.detailRow('使用班级', this.selectedRoom.sybj, '#A16207')
        this.detailRow('空闲时间', this.selectedRoom.time, '#079841')

        Button('关闭')
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor($r('app.color.bg_chip'))
          .height(42)
          .borderRadius(12)
          .width('100%')
          .margin({ top: 18 })
          .onClick(() => {
            this.showDetail = false;
          })
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 8, bottom: 24 })
  }

  /** 详情行：彩色圆点 + 标签 + 值（与课程表/考试详情同款） */
  @Builder
  detailRow(label: string, value: string, dotColor: string) {
    Row() {
      Column()
        .width(6)
        .height(6)
        .borderRadius(3)
        .backgroundColor(dotColor)
        .margin({ right: 10 })
      Text(label)
        .fontSize(13)
        .fontColor($r('app.color.text_tertiary'))
        .width(96)
      Text(value.length > 0 ? value : '—')
        .fontSize(13)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .textAlign(TextAlign.End)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({ top: 7, bottom: 7 })
  }
}
