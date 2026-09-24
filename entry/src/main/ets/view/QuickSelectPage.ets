/**
 * 快捷选课（BETA）—— 移植自参考项目 zhengfang-apk 的正方选课/抢课模块。
 * 入口：「我的」→ 学业情况下方「快捷选课」；每次进入弹出 BETA 提示。
 *
 * 能力（对齐参考项目）：
 *  - 选课轮次上下文读取（正方 V9 兼容 xkkz_xh / xkkz_id）
 *  - 按课程名/课程代码查询教学班（教师、时间、地点、学分、容量/已选）
 *  - 选课 / 退选 / 已选课程列表
 *  - **抢课队列**（多目标排队）+ **定时策略**（轮询间隔、最大轮次、成功后是否继续）+ **开始/停止按钮**
 *
 * 说明：选课需学校开放选课轮次，且不同版本正方字段略有差异；本实现按参考项目移植，未经真机验证。
 *
 * 卡片外观接入（照首页 HomeView / 关于页 AboutPage 的写法推广）：
 *  - 页面级卡片（状态说明 / 抢课队列+定时策略 / 课程查询 / 已选课程 / 运行日志）与结果卡片
 *    （教学班卡片）统一用 `MaterialCard` 承载（材质层在卡片内部、位于内容之下），材质生效时卡片自身的
 *    底色/磨砂/亮边/阴影一并让出，每张卡只有一层视觉；关闭光感回落为原来的纯色/毛玻璃卡片；
 *  - 教学班卡片是**相邻列表卡**（卡间 10vp）→ 传 `cardMaterialShadow: false`（防投影在卡间叠成暗带）；
 *  - 原卡片上的 `.padding(...)` / `.borderRadius(...)` / `.margin(...)` / `.alignItems(...)`
 *    一律改走 `cardPadding` / `cardRadius` / `cardMargin` / `cardAlignItems`
 *    （尾随闭包初始化的自定义组件之后不能再链式加属性）；
 *  - 胶囊小按钮（选课/入队/退选/查询/筛选/清空/停用/移除/开始抢课…）改走 `MaterialButton`；
 *    **带选中态的档位胶囊保持实色**（重试间隔 / 最大重试次数 / 并行处理 / 轮次分类切换）——
 *    选中态完全靠实色背景表达，材质会让出底色、把选中态吃掉；
 *    输入框（TextInput）与列表行内子容器保持原自绘玻璃写法（材质卡内部不再叠第二层材质）。
 */
import { AppState } from '../common/AppState';
import { Theme } from '../common/ThemeUtil';
import { AppearanceStore } from '../common/AppearanceStore';
import { GlassMaterial } from '../common/GlassMaterial';
import { LogStore } from '../common/LogStore';
import { ClassFilter, GrabPolicy, GrabTarget, SelectableClass, SelectedCourseItem, SelectContext, SelectScope } from '../model/Models';
import { SelectApi, SelectResult } from '../api/SelectApi';
import { PageHeader } from './common/UiKit';
import { WallpaperFill } from './common/WallpaperFill';
// 沉浸光感：卡片统一走 MaterialCard（材质承载层在卡片内容之下，材质生效时卡片底色/磨砂/亮边/阴影
// 一并让出，每张卡只剩一层视觉），胶囊小按钮走 MaterialButton
import { MaterialCard } from './common/MaterialCard';
import { MaterialButton } from './common/MaterialButton';
import { MaterialCardLayer } from './common/MaterialCarrier';
import { materialAvailable } from '../common/SystemMaterial';

@Component
export struct QuickSelectPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  /** 灰字广播订阅：颜色表达式需传 this.grayTick 才登记响应式依赖（否则改色不实时刷新） */
  @StorageProp('grayTick') grayTick: number = 0;
  /** 响应式依赖：玻璃/灰字设置变化时即时刷新本页（取值经 GlassMaterial 静态方法读取） */
  @StorageProp('glassStrength') glassStrength: number = 70;
  @StorageProp('cardMaterial') cardMaterial: boolean = false;
  /** 卡片沾色底色（广播键）：沾色开关变化时由 AppearanceStore.broadcastDerived() 重写 */
  @StorageProp('cardTintBg') tintBg: string = '';
  @StorageProp('grayTextMode') grayTextMode: string = 'default';
  @StorageProp('grayTextColor') grayTextColor: string = '';
  @StorageProp('immersiveEffect') immersiveEffect: boolean = false;
  /** 全局字重响应式订阅：表达式读 this.fwMode 才登记依赖，fwValue 声明即订阅 */
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  /** 选课上下文是否就绪 */
  @State ctxReady: boolean = false;
  /** 上下文摘要（轮次/类别） */
  @State ctxInfo: string = '正在读取选课轮次…';
  /** 查询关键字（课程名或课程代码） */
  @State keyword: string = '';
  /** 查询结果（教学班） */
  @State classes: SelectableClass[] = [];
  /** 已选课程 */
  @State chosen: SelectedCourseItem[] = [];
  /** 抢课队列 */
  @State queue: GrabTarget[] = [];
  /** 定时策略：轮询间隔（秒） */
  @State intervalSec: number = 3;
  /** 定时策略：最大轮次（0 = 不限） */
  @State maxRounds: number = 200;
  /** 抢到一门后是否继续抢队列其它课程 */
  @State continueAfterSuccess: boolean = true;
  /** 并行处理目标数（1=顺序，2/3=并行，对应参考项目 parallel mode） */
  @State parallelWorkers: number = 1;
  /** 延时启动秒数（0=立即；对应参考项目定时启动） */
  @State delaySec: number = 0;
  /** 捡漏模式：监测"已选人数下降"立即抢占 */
  @State leakMode: boolean = false;
  /** 运行统计 */
  @State successCount: number = 0;
  @State failCount: number = 0;
  @State retryCount: number = 0;
  /** 首页解析出的轮次/分类（新正方：每个 queryCourse 分类一个 scope） */
  @State scopes: SelectScope[] = [];
  @State roundIndex: number = 0;
  /** 定时启动时间（0=立即；>0 为绝对毫秒时间戳） */
  @State startAtMs: number = 0;
  @State startAtText: string = '';
  /** 筛选条件 */
  @State fTeacher: string = '';
  @State fTime: string = '';
  @State fLoc: string = '';
  @State fCredit: string = '';
  @State onlyAvailable: boolean = false;
  @State showFilter: boolean = false;
  @State querying: boolean = false;
  @State busy: boolean = false;
  /** 抢课进行中 */
  @State grabbing: boolean = false;
  /** 运行日志 */
  @State logText: string = '';
  private ctx: SelectContext | null = null;
  /** 抢课取消标志（非状态，仅内部使用） */
  private cancelled: boolean = false;
  /** 当前运行中的队列（运行时与 @State 同步） */
  private runQueue: GrabTarget[] = [];

  aboutToAppear(): void {
    this.showBetaTip();
    this.queue = SelectApi.loadQueue();
    const p: GrabPolicy = SelectApi.loadPolicy();
    this.intervalSec = p.intervalSec;
    this.maxRounds = p.maxRounds;
    this.continueAfterSuccess = p.continueAfterSuccess;
    this.parallelWorkers = p.parallelWorkers;
    this.delaySec = p.delaySec;
    this.leakMode = p.leakMode;
    this.init();
  }

  aboutToDisappear(): void {
    this.cancelled = true;
  }

  /** 每次进入都提示 BETA */
  private showBetaTip(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: 'BETA 功能',
      message: '「快捷选课」为 BETA 功能：选课/退选/抢课接口按正方教务系统移植，'
        + '需学校开放选课轮次方可使用，且不同版本字段可能存在差异，请谨慎操作。',
      buttons: [
        { text: '我知道了', color: Theme.colorOf(this.themeColor) }
      ]
    }).then(() => {
      // 仅提示
    });
  }

  /** 初始化：读取选课上下文 + 已选课程 */
  private async init(): Promise<void> {
    this.busy = true;
    try {
      const ctx: SelectContext = await SelectApi.loadContext(false);
      this.ctx = ctx;
      this.ctxReady = ctx.xkkzId.length > 0;
      this.scopes = SelectApi.scopeList();
      this.roundIndex = 0;
      this.ctxInfo = this.ctxReady
        ? `轮次已就绪（${ctx.xkkzKey}=${ctx.xkkzId} · 类别 ${ctx.kklxdm} · 学年 ${ctx.xkxnm} 学期 ${ctx.xkxqm}）`
        : '未获取到选课轮次（可能当前不在选课开放期）';
      await this.loadChosen();
    } catch (e) {
      this.ctxReady = false;
      this.ctxInfo = `选课轮次读取失败：${LogStore.errorOf(e as Object)}`;
    } finally {
      this.busy = false;
    }
  }

  /** 当前选中的轮次（无则 null） */
  private currentScope(): SelectScope | null {
    if (this.scopes.length === 0) {
      return null;
    }
    const idx: number = this.roundIndex >= 0 && this.roundIndex < this.scopes.length ? this.roundIndex : 0;
    return this.scopes[idx];
  }

  /** 加载已选课程 */
  private async loadChosen(): Promise<void> {
    const scope: SelectScope | null = this.currentScope();
    if (scope === null) {
      return;
    }
    try {
      this.chosen = await SelectApi.selectedCourses(scope);
      this.log(`已选课程 ${this.chosen.length} 门`);
    } catch (e) {
      this.log(`已选课程读取失败：${LogStore.errorOf(e as Object)}`);
    }
  }

  private log(text: string): void {
    this.logText = `${text}\n${this.logText}`.substring(0, 1500);
  }

  /** 查询教学班（新正方：PartDisplay + 白名单参数 + 关键字 + 分页） */
  private async doQuery(): Promise<void> {
    const scope: SelectScope | null = this.currentScope();
    if (scope === null || this.querying) {
      return;
    }
    if (this.keyword.trim().length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入课程名或课程代码' });
      return;
    }
    this.querying = true;
    try {
      const raw: SelectableClass[] = await SelectApi.queryClasses(scope, this.keyword.trim(), '1', '200');
      const filter: ClassFilter = {
        teacher: this.fTeacher,
        time: this.fTime,
        location: this.fLoc,
        credit: this.fCredit,
        onlyAvailable: this.onlyAvailable
      };
      this.classes = SelectApi.filterClasses(raw, filter);
      this.log(`查询「${this.keyword.trim()}」→ ${raw.length} 个教学班，筛选后 ${this.classes.length} 个`);
      if (this.classes.length === 0) {
        this.getUIContext().getPromptAction().showToast({
          message: raw.length > 0 ? '筛选后无结果（可放宽筛选条件）' : '未查询到教学班（轮次/关键字可能不匹配）'
        });
      }
    } catch (e) {
      this.log(`查询失败：${LogStore.errorOf(e as Object)}`);
      this.getUIContext().getPromptAction().showToast({ message: '查询失败，请稍后重试' });
    } finally {
      this.querying = false;
    }
  }

  /** 选课（先取该课程的教学班，再按教学班提交；带确认） */
  private async doChoose(cls: SelectableClass): Promise<void> {
    const scope: SelectScope | null = this.currentScope();
    if (scope === null) {
      return;
    }
    this.getUIContext().getPromptAction().showDialog({
      title: '确认选课',
      message: `确定要选「${cls.courseName}」${cls.className.length > 0 ? `（${cls.className}）` : ''} 吗？`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '选课', color: Theme.colorOf(this.themeColor) }
      ]
    }).then(async (res) => {
      if (res.index !== 1) {
        return;
      }
      this.busy = true;
      try {
        // 新正方：必须用"教学班行参数+课程行参数"合并提交 → 先拉教学班
        const sections: SelectableClass[] = await SelectApi.loadSections(scope, cls);
        if (sections.length === 0) {
          this.log(`「${cls.courseName}」未取到教学班，无法选课`);
          this.getUIContext().getPromptAction().showToast({ message: '未取到教学班，无法选课' });
          return;
        }
        let target: SelectableClass = sections[0];
        for (let i: number = 0; i < sections.length; i++) {
          const s: SelectableClass = sections[i];
          if (cls.doJxbId.length > 0 && (s.doJxbId === cls.doJxbId || s.jxbId === cls.jxbId)) {
            target = s;
            break;
          }
        }
        const r: SelectResult = await SelectApi.chooseClass(scope, cls.kchId, cls.courseName, target);
        this.log(r.message);
        this.getUIContext().getPromptAction().showToast({ message: r.message });
        if (r.ok) {
          await this.loadChosen();
        }
      } catch (e) {
        this.log(`选课异常：${LogStore.errorOf(e as Object)}`);
      } finally {
        this.busy = false;
      }
    });
  }

  /** 加入抢课队列（mode: 'exact' 指定教学班 / 'fuzzy' 按课程名模糊捡漏） */
  private doEnqueue(cls: SelectableClass, mode: string): void {
    const target: GrabTarget = {
      kchId: cls.kchId,
      courseName: cls.courseName,
      teacher: mode === 'exact' ? cls.teacher : '',
      time: mode === 'exact' ? cls.time : '',
      jxbId: mode === 'exact' ? cls.jxbId : '',
      doJxbId: mode === 'exact' ? cls.doJxbId : '',
      enabled: true,
      status: 'waiting',
      attempts: 0,
      matchMode: mode
    };
    const ok: boolean = SelectApi.enqueue(this.queue, target);
    this.queue = SelectApi.copyQueue(this.queue);
    const label: string = mode === 'exact' ? '精确' : '模糊';
    this.log(ok ? `已加入队列（${label}）：${cls.courseName}` : `队列中已存在：${cls.courseName}`);
    this.getUIContext().getPromptAction().showToast({
      message: ok ? `已加入队列（${label}）：${cls.courseName}` : '该课程已在队列中'
    });
  }

  /** 按课程名模糊入队（不指定教学班：任意教学班有空位即抢 → 对应参考项目模糊匹配/捡漏） */
  private enqueueByKeyword(): void {
    const kw: string = this.keyword.trim();
    let name: string = kw;
    let kchId: string = '';
    for (let i: number = 0; i < this.classes.length; i++) {
      if (this.classes[i].courseName.indexOf(kw) >= 0 || this.classes[i].kchId === kw) {
        name = this.classes[i].courseName;
        kchId = this.classes[i].kchId;
        break;
      }
    }
    if (name.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请先输入课程名并查询' });
      return;
    }
    const target: GrabTarget = {
      kchId: kchId,
      courseName: name,
      teacher: '',
      time: '',
      jxbId: '',
      doJxbId: '',
      enabled: true,
      status: 'waiting',
      attempts: 0,
      matchMode: 'fuzzy'
    };
    const ok: boolean = SelectApi.enqueue(this.queue, target);
    this.queue = SelectApi.copyQueue(this.queue);
    this.log(ok ? `已按课程名加入队列（模糊）：${name}` : `队列中已存在：${name}`);
  }

  /** 移除队列项 */
  private doDequeue(target: GrabTarget): void {
    SelectApi.dequeue(this.queue, target);
    this.queue = SelectApi.copyQueue(this.queue);
    this.log(`已移出队列：${target.courseName}`);
  }

  /** 切换队列项启用状态 */
  private toggleEnabled(target: GrabTarget): void {
    target.enabled = !target.enabled;
    SelectApi.saveQueue(this.queue);
    this.queue = SelectApi.copyQueue(this.queue);
  }

  /** 清空队列 */
  private clearQueue(): void {
    this.queue = [];
    SelectApi.saveQueue(this.queue);
    this.log('已清空抢课队列');
  }

  /** 退选（带确认） */
  private async doDrop(item: SelectedCourseItem): Promise<void> {
    this.getUIContext().getPromptAction().showDialog({
      title: '确认退选',
      message: `确定要退选「${item.courseName}」吗？退课后可能无法再次选上此课程。`,
      buttons: [
        { text: '取消', color: $r('app.color.text_secondary') },
        { text: '退选', color: '#DB5252' }
      ]
    }).then(async (res) => {
      if (res.index !== 1) {
        return;
      }
      this.busy = true;
      try {
        const r: SelectResult = await SelectApi.dropClass(item);
        this.log(r.message);
        this.getUIContext().getPromptAction().showToast({ message: r.message });
        if (r.ok) {
          await this.loadChosen();
        }
      } finally {
        this.busy = false;
      }
    });
  }

  /** 由当前界面状态构造抢课策略（唯一构造点，避免字段遗漏） */
  private currentPolicy(): GrabPolicy {
    const policy: GrabPolicy = {
      intervalSec: this.intervalSec,
      maxRounds: this.maxRounds,
      continueAfterSuccess: this.continueAfterSuccess,
      parallelWorkers: this.parallelWorkers,
      delaySec: this.delaySec,
      leakMode: this.leakMode
    };
    return policy;
  }

  /** 选择定时启动时间：先选日期，再选时分（对应参考项目定时启动） */
  private pickStartTime(): void {
    const now: Date = new Date();
    DatePickerDialog.show({
      start: now,
      end: new Date(now.getFullYear() + 1, now.getMonth(), now.getDate()),
      selected: now,
      onAccept: (value: DatePickerResult) => {
        const y: number = value.year ?? now.getFullYear();
        const mo: number = value.month ?? now.getMonth();
        const d: number = value.day ?? now.getDate();
        this.pickStartClock(y, mo, d);
      }
    });
  }

  /** 选择定时启动的时分 */
  private pickStartClock(y: number, mo: number, d: number): void {
    TimePickerDialog.show({
      selected: new Date(),
      format: TimePickerFormat.HOUR_MINUTE,
      onAccept: (value: TimePickerResult) => {
        const hh: number = value.hour ?? 0;
        const mm: number = value.minute ?? 0;
        const dt: Date = new Date(y, mo, d, hh, mm, 0);
        if (dt.getTime() <= new Date().getTime()) {
          this.getUIContext().getPromptAction().showToast({ message: '启动时间需晚于当前时间' });
          return;
        }
        this.startAtMs = dt.getTime();
        const p = (n: number): string => n < 10 ? `0${n}` : `${n}`;
        this.startAtText = `${y}-${p(mo + 1)}-${p(d)} ${p(hh)}:${p(mm)}`;
        const left: number = Math.ceil((this.startAtMs - new Date().getTime()) / 1000);
        this.delaySec = left > 0 ? left : 0;
        this.savePolicy();
        this.getUIContext().getPromptAction().showToast({ message: `已设定启动时间：${this.startAtText}` });
      }
    });
  }

  /** 保存定时策略 */
  private savePolicy(): void {
    SelectApi.savePolicy(this.currentPolicy());
  }

  /** 开始抢课（队列 + 定时/重试策略） */
  private async startGrab(): Promise<void> {
    const scope: SelectScope | null = this.currentScope();
    if (scope === null || this.grabbing) {
      return;
    }
    const targets: GrabTarget[] = SelectApi.copyQueue(this.queue);
    let enabled: number = 0;
    for (let i: number = 0; i < targets.length; i++) {
      if (targets[i].enabled) {
        enabled++;
      }
    }
    if (enabled === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请先把要抢的课程加入队列' });
      return;
    }
    // 定时启动：由绝对时间戳换算延时秒数（0=立即）
    if (this.startAtMs > 0) {
      const leftMs: number = this.startAtMs - new Date().getTime();
      if (leftMs <= 0) {
        this.delaySec = 0;
        this.startAtMs = 0;
        this.startAtText = '';
      } else {
        this.delaySec = Math.ceil(leftMs / 1000);
      }
    } else {
      this.delaySec = 0;
    }
    this.savePolicy();
    this.cancelled = false;
    this.grabbing = true;
    this.runQueue = targets;
    this.queue = SelectApi.copyQueue(targets);
    this.successCount = 0;
    this.failCount = 0;
    this.retryCount = 0;
    this.log(`开始抢课：队列 ${enabled} 门 · 每 ${this.intervalSec} 秒一轮 · `
      + `${this.maxRounds > 0 ? `最多 ${this.maxRounds} 轮` : '不限轮次'} · `
      + `${this.parallelWorkers > 1 ? `并行 ${this.parallelWorkers} 路` : '顺序'}`
      + `${this.delaySec > 0 ? ` · 延时 ${this.delaySec} 秒启动` : ''}`
      + `${this.leakMode ? ' · 捡漏开启' : ''}`);
    try {
      const policy: GrabPolicy = this.currentPolicy();
      const r: SelectResult = await SelectApi.runQueue(scope, targets, policy,
        () => this.cancelled,
        (text: string) => {
          this.log(text);
        },
        (list: GrabTarget[]) => {
          this.queue = list;
        });
      this.log(`抢课结束：${r.message}`);
      // 运行统计（成功 / 未成功 / 累计尝试次数）
      let okCount: number = 0;
      let failCount: number = 0;
      let retryCount: number = 0;
      for (let i: number = 0; i < targets.length; i++) {
        retryCount += targets[i].attempts;
        if (targets[i].status === 'success') {
          okCount++;
        } else {
          failCount++;
        }
      }
      this.successCount = okCount;
      this.failCount = failCount;
      this.retryCount = retryCount;
      this.log(`统计：成功 ${okCount} 门 · 未成功 ${failCount} 门 · 累计尝试 ${retryCount} 次`);
      this.getUIContext().getPromptAction().showToast({ message: r.message });
      await this.loadChosen();
    } finally {
      this.grabbing = false;
      this.queue = SelectApi.copyQueue(SelectApi.loadQueue());
    }
  }

  /** 停止抢课 */
  private stopGrab(): void {
    this.cancelled = true;
    this.log('已请求停止抢课…');
  }

  /** 队列项状态文案/颜色 */
  private statusText(status: string): string {
    if (status === 'success') {
      return '已抢到';
    }
    if (status === 'failed') {
      return '失败重试中';
    }
    return '待抢';
  }

  private statusColor(status: string): ResourceColor {
    if (status === 'success') {
      return $r('app.color.brand');
    }
    if (status === 'failed') {
      return $r('app.color.accent_orange');
    }
    return GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'));
  }

  /** 单个教学班卡片 */
  @Builder
  classCard(cls: SelectableClass) {
    // MaterialCard 承载：材质层是卡片内部底层、与卡片同尺寸同圆角，材质生效时卡片底色/磨砂/亮边/阴影让出；
    // 原 12vp 内边距走 cardPadding、12vp 圆角走 cardRadius、10vp 下间距走 cardMargin、
    // 左对齐走 cardAlignItems；相邻列表卡 → cardMaterialShadow: false 防投影在卡间叠成暗带。
    MaterialCard({
      cardRadius: 12,
      cardPadding: 12,
      cardAlignItems: ItemAlign.Start,
      cardBg: $r('app.color.bg_chip'),
      cardBlur: GlassMaterial.cardBlur(),
      cardBorderW: GlassMaterial.cardBorderWidth(),
      cardBorderC: GlassMaterial.borderColor(),
      cardShadow: GlassMaterial.cardShadowStyle(),
      cardMargin: { bottom: 10 },
      cardMaterialShadow: false
    }) {
    Column() {
      Row() {
        Text(cls.courseName)
          .fontSize(14)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
        Text(cls.credit.length > 0 ? `${cls.credit} 学分` : '')
          .fontSize(11)
          .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
      }
      .width('100%')

      if (cls.className.length > 0) {
        Text(cls.className)
          .fontSize(11)
          .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
          .width('100%')
          .margin({ top: 2 })
      }
      if (cls.teacher.length > 0) {
        Text(`教师：${cls.teacher}`)
          .fontSize(11)
          .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
          .width('100%')
          .margin({ top: 4 })
      }
      if (cls.time.length > 0) {
        Text(cls.time)
          .fontSize(11)
          .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
          .width('100%')
          .margin({ top: 2 })
      }
      if (cls.location.length > 0) {
        Text(cls.location)
          .fontSize(11)
          .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
          .width('100%')
          .margin({ top: 2 })
      }

      Row() {
        Text(cls.capacity > 0
          ? `容量 ${cls.selected}/${cls.capacity}${cls.selected >= cls.capacity ? '（已满）' : ''}`
          : `已选 ${cls.selected}`)
          .fontSize(11)
          .fontColor(cls.capacity > 0 && cls.selected >= cls.capacity
            ? '#DB5252' : GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
          .layoutWeight(1)
        if (cls.chosen) {
          // 「已选」是状态标签（无点击）：保留实色底
          Text('已选')
            .fontSize(11)
            .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
            .padding({ left: 10, right: 10, top: 5, bottom: 5 })
            .backgroundColor($r('app.color.bg_chip')).backgroundBlurStyle(GlassMaterial.cardBlur()).border({ width: GlassMaterial.cardBorderWidth(), color: GlassMaterial.borderColor() }).shadow(GlassMaterial.cardShadowStyle()).clip(true)
            .borderRadius(10)
        } else {
          // 结果项里的小按钮：材质走 MaterialButton 的 Toggle 承载层（普通 Button/Text 挂材质真机不渲染）
          MaterialButton({
            btnRadius: 12,
            btnBg: Theme.colorOf(this.themeColor),
            btnBlur: GlassMaterial.cardBlur(),
            btnBorderW: GlassMaterial.cardBorderWidth(),
            btnBorderC: GlassMaterial.borderColor(),
            btnOnClick: () => {
              this.doChoose(cls);
            }
          }) {
            Text('选课')
              .fontSize(12)
              .fontColor(Color.White)
              .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          }
          MaterialButton({
            btnRadius: 12,
            btnBg: $r('app.color.bg_chip'),
            btnBlur: GlassMaterial.cardBlur(),
            btnBorderW: GlassMaterial.cardBorderWidth(),
            btnBorderC: GlassMaterial.borderColor(),
            btnMargin: { left: 8 },
            btnOnClick: () => {
              this.doEnqueue(cls, 'exact');
            }
          }) {
            Text('精确入队')
              .fontSize(12)
              .fontColor(Theme.colorOf(this.themeColor))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          }
          MaterialButton({
            btnRadius: 12,
            btnBg: $r('app.color.bg_chip'),
            btnBlur: GlassMaterial.cardBlur(),
            btnBorderW: GlassMaterial.cardBorderWidth(),
            btnBorderC: GlassMaterial.borderColor(),
            btnMargin: { left: 6 },
            btnOnClick: () => {
              this.doEnqueue(cls, 'fuzzy');
            }
          }) {
            Text('模糊入队')
              .fontSize(12)
              .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
          }
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    }
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        WallpaperFill()

        Scroll() {
          Column() {
            // 顶栏让位（额外留 12vp，避免首张卡片贴住悬浮顶栏）
            Column()
              .width('100%')
              .height(this.getUIContext().px2vp(this.topInsetPx) + 72)

            // 状态 + BETA 说明
            // MaterialCard 承载：材质层是卡片内部底层、与卡片同尺寸同圆角，材质生效时卡片底色/磨砂/亮边/阴影让出；
            // 原 16vp 内边距走 cardPadding、18vp 圆角走 cardRadius、左对齐走 cardAlignItems
            MaterialCard({
              cardRadius: 18,
              cardPadding: 16,
              cardAlignItems: ItemAlign.Start,
              cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
              cardBlur: GlassMaterial.cardBlur(),
              cardBorderW: GlassMaterial.cardBorderWidth(),
              cardBorderC: GlassMaterial.borderColor(),
              cardShadow: GlassMaterial.cardShadowStyle()
            }) {
            Column() {
              Row() {
                Text('BETA')
                  .fontSize(11)
                  .fontColor(Color.White)
                  .padding({ left: 8, right: 8, top: 2, bottom: 2 })
                  .backgroundColor($r('app.color.accent_orange'))
                  .borderRadius(8)
                Text('快捷选课')
                  .fontSize(15)
                  .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
                  .fontColor($r('app.color.text_primary'))
                  .margin({ left: 8 })
              }
              .width('100%')
              Text(this.ctxInfo)
                .fontSize(11)
                .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                .width('100%')
                .margin({ top: 8 })
              if (this.busy) {
                Text('处理中…')
                  .fontSize(11)
                  .fontColor(Theme.colorOf(this.themeColor))
                  .width('100%')
                  .margin({ top: 6 })
              }
              if (this.successCount > 0 || this.retryCount > 0) {
                Text(`运行统计：成功 ${this.successCount} 门 · 未成功 ${this.failCount} 门 · 累计尝试 ${this.retryCount} 次`)
                  .fontSize(11)
                  .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                  .width('100%')
                  .margin({ top: 6 })
              }
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            }

            // ══════ 抢课队列 + 定时策略 + 开始按钮 ══════
            // MaterialCard 承载：原 16vp 内边距走 cardPadding、18vp 圆角走 cardRadius、12vp 上间距走 cardMargin
            MaterialCard({
              cardRadius: 18,
              cardPadding: 16,
              cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
              cardBlur: GlassMaterial.cardBlur(),
              cardBorderW: GlassMaterial.cardBorderWidth(),
              cardBorderC: GlassMaterial.borderColor(),
              cardShadow: GlassMaterial.cardShadowStyle(),
              cardMargin: { top: 12 }
            }) {
            Column() {
              Row() {
                Text('抢课队列')
                  .fontSize(16)
                  .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Text(`${this.queue.length} 门`)
                  .fontSize(11)
                  .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                if (this.queue.length > 0 && !this.grabbing) {
                  // 「清空」胶囊小按钮：材质走 MaterialButton 的 Toggle 承载层
                  MaterialButton({
                    btnRadius: 9,
                    btnBg: $r('app.color.bg_chip'),
                    btnBlur: GlassMaterial.cardBlur(),
                    btnBorderW: GlassMaterial.cardBorderWidth(),
                    btnBorderC: GlassMaterial.borderColor(),
                    btnMargin: { left: 8 },
                    btnOnClick: () => {
                      this.clearQueue();
                    }
                  }) {
                    Text('清空')
                      .fontSize(11)
                      .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                      .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  }
                }
              }
              .width('100%')
              .margin({ bottom: 10 })

              if (this.queue.length === 0) {
                Text('队列为空：先在下方查询课程，点「加入队列」把要抢的课程排队')
                  .fontSize(12)
                  .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                  .width('100%')
              } else {
                ForEach(this.queue, (item: GrabTarget) => {
                  Row() {
                    Column() {
                      Text(item.courseName)
                        .fontSize(13)
                        .fontColor($r('app.color.text_primary'))
                        .width('100%')
                      Text(`${item.teacher.length > 0 ? item.teacher : '教师未知'}`
                        + `${item.time.length > 0 ? ` · ${item.time}` : ''}`
                        + ` · ${item.matchMode === 'fuzzy' ? '模糊' : '精确'}`
                        + ` · 第 ${item.attempts} 次`)
                        .fontSize(11)
                        .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                        .width('100%')
                        .margin({ top: 2 })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    Text(this.statusText(item.status))
                      .fontSize(11)
                      .fontColor(this.statusColor(item.status))
                      .margin({ right: 8 })
                    // 停用/启用 + 移除：结果项小按钮 → MaterialButton（材质走 Toggle 承载层）
                    MaterialButton({
                      btnRadius: 9,
                      btnBg: $r('app.color.bg_chip'),
                      btnBlur: GlassMaterial.cardBlur(),
                      btnBorderW: GlassMaterial.cardBorderWidth(),
                      btnBorderC: GlassMaterial.borderColor(),
                      btnOnClick: () => {
                        this.toggleEnabled(item);
                      }
                    }) {
                      Text(item.enabled ? '停用' : '启用')
                        .fontSize(11)
                        .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                    }
                    MaterialButton({
                      btnRadius: 9,
                      btnBg: 'rgba(219,82,82,0.10)',
                      btnBlur: (AppStorage.get<boolean>('immersiveEffect') ?? false) ? BlurStyle.Thin : BlurStyle.NONE,
                      btnBorderW: 1,
                      btnBorderC: 'rgba(255,255,255,0.28)',
                      btnMargin: { left: 6 },
                      btnOnClick: () => {
                        this.doDequeue(item);
                      }
                    }) {
                      Text('移除')
                        .fontSize(11)
                        .fontColor('#DB5252')
                        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                    }
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                  .padding({ top: 7, bottom: 7 })
                }, (item: GrabTarget) => `${item.kchId}-${item.doJxbId}${item.jxbId}`)
              }

              // 定时设置：启动时间（日期 + 时间选择）
              Divider().color($r('app.color.divider')).margin({ top: 4, bottom: 10 })
              Text('定时设置')
                .fontSize(13)
                .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .margin({ bottom: 8 })
              Row() {
                Text('启动时间')
                  .fontSize(12)
                  .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                Blank()
                Text(this.startAtText.length > 0 ? this.startAtText : '立即开始')
                  .fontSize(12)
                  .fontColor(this.startAtText.length > 0
                    ? Theme.colorOf(this.themeColor) : GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
                // 「选择」「清除」：胶囊小按钮 → MaterialButton（材质走 Toggle 承载层）
                MaterialButton({
                  btnRadius: 10,
                  btnBg: Theme.colorOf(this.themeColor),
                  btnBlur: GlassMaterial.cardBlur(),
                  btnBorderW: GlassMaterial.cardBorderWidth(),
                  btnBorderC: GlassMaterial.borderColor(),
                  btnMargin: { left: 10 },
                  btnOnClick: () => {
                    this.pickStartTime();
                  }
                }) {
                  Text('选择')
                    .fontSize(12)
                    .fontColor(Color.White)
                    .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                }
                if (this.startAtText.length > 0) {
                  MaterialButton({
                    btnRadius: 10,
                    btnBg: $r('app.color.bg_chip'),
                    btnBlur: GlassMaterial.cardBlur(),
                    btnBorderW: GlassMaterial.cardBorderWidth(),
                    btnBorderC: GlassMaterial.borderColor(),
                    btnMargin: { left: 6 },
                    btnOnClick: () => {
                      this.startAtMs = 0;
                      this.startAtText = '';
                      this.delaySec = 0;
                      this.savePolicy();
                    }
                  }) {
                    Text('清除')
                      .fontSize(12)
                      .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                      .padding({ left: 10, right: 10, top: 5, bottom: 5 })
                  }
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)

              // 高级设置
              Text('高级设置')
                .fontSize(13)
                .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .margin({ top: 16, bottom: 8 })
              Row() {
                Text('重试间隔')
                  .fontSize(12)
                  .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                  .layoutWeight(1)
                // 档位胶囊保留实色底：选中态靠实色背景（选中=主题色 / 未选中=浅灰）+ 白字表达，
                // 沉浸光感材质会让出底色、把选中态吃掉，故这一组不改为材质按钮。
                ForEach([0.5, 1, 2, 3, 5], (sec: number) => {
                  Text(`${sec}s`)
                    .fontSize(12)
                    .fontColor(this.intervalSec === sec ? Color.White : GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
                    .padding({ left: 11, right: 11, top: 5, bottom: 5 })
                    .backgroundColor(this.intervalSec === sec
                      ? Theme.colorOf(this.themeColor) : $r('app.color.bg_chip'))
                    .borderRadius(10)
                    .margin({ left: 5 })
                    .onClick(() => {
                      this.intervalSec = sec;
                      this.savePolicy();
                    })
                }, (sec: number) => `sec${sec}`)
              }
              .width('100%')

              Row() {
                Text('最大重试次数')
                  .fontSize(12)
                  .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                  .layoutWeight(1)
                // 档位胶囊保留实色底（选中态靠实色背景表达，原因同「重试间隔」）
                ForEach([50, 200, 500, 0], (r: number) => {
                  Text(r === 0 ? '不限' : `${r}`)
                    .fontSize(12)
                    .fontColor(this.maxRounds === r ? Color.White : GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
                    .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                    .backgroundColor(this.maxRounds === r
                      ? Theme.colorOf(this.themeColor) : $r('app.color.bg_chip'))
                    .borderRadius(10)
                    .margin({ left: 6 })
                    .onClick(() => {
                      this.maxRounds = r;
                      this.savePolicy();
                    })
                }, (r: number) => `mr${r}`)
              }
              .width('100%')
              .margin({ top: 8 })

              Row() {
                Text('并行处理')
                  .fontSize(12)
                  .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                  .layoutWeight(1)
                // 档位胶囊保留实色底（选中态靠实色背景表达，原因同「重试间隔」）
                ForEach([1, 2, 3], (w: number) => {
                  Text(w === 1 ? '顺序' : `${w} 路`)
                    .fontSize(12)
                    .fontColor(this.parallelWorkers === w ? Color.White : GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
                    .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                    .backgroundColor(this.parallelWorkers === w
                      ? Theme.colorOf(this.themeColor) : $r('app.color.bg_chip'))
                    .borderRadius(10)
                    .margin({ left: 6 })
                    .onClick(() => {
                      this.parallelWorkers = w;
                      this.savePolicy();
                    })
                }, (w: number) => `pw${w}`)
              }
              .width('100%')
              .margin({ top: 8 })

              Row() {
                Text('捡漏模式（有人退课立即抢）')
                  .fontSize(12)
                  .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.leakMode })
                  .selectedColor(Theme.colorOf(this.themeColor))
                  .onChange((on: boolean) => {
                    this.leakMode = on;
                    this.savePolicy();
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .margin({ top: 10 })

              Row() {
                Text('抢到后继续抢队列其它课程')
                  .fontSize(12)
                  .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                  .layoutWeight(1)
                Toggle({ type: ToggleType.Switch, isOn: this.continueAfterSuccess })
                  .selectedColor(Theme.colorOf(this.themeColor))
                  .onChange((on: boolean) => {
                    this.continueAfterSuccess = on;
                    this.savePolicy();
                  })
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .margin({ top: 10 })

              // 开始 / 停止
              Row() {
                // 整宽主按钮：材质走 MaterialButton 的 Toggle 承载层；
                // 原底色表达运行状态（运行中=红 / 待机=主题色），改走 btnBg；
                // 原按钮无边框、无磨砂 → 光感关闭时按原样回落。
                MaterialButton({
                  btnRadius: 14,
                  btnBg: this.grabbing ? '#DB5252' : Theme.colorOf(this.themeColor),
                  btnBlur: BlurStyle.NONE,
                  btnOnClick: () => {
                    if (this.grabbing) {
                      this.stopGrab();
                    } else {
                      this.startGrab();
                    }
                  }
                }) {
                  Text(this.grabbing ? '停止抢课' : '开始抢课')
                    .fontSize(15)
                    .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
                    .fontColor(Color.White)
                    .textAlign(TextAlign.Center)
                    .width('100%')
                    .padding({ top: 12, bottom: 12 })
                }
              }
              .width('100%')
              .margin({ top: 14 })

              Text(this.grabbing
                ? `运行中：每 ${this.intervalSec} 秒一轮 · ${this.maxRounds > 0 ? `最多 ${this.maxRounds} 轮` : '不限轮次'}`
                : '点击「开始抢课」后按上述定时策略轮询空位并自动提交；抢课期间请保持页面打开')
                .fontSize(11)
                .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                .width('100%')
                .margin({ top: 8 })
            }
            .width('100%')
            }

            // 课程查询
            // 最小光感卡结构：Stack{ 材质承载层(常驻) + 内容列 }——含 TextInput，绕开 MaterialCard
            // 包装对输入焦点的影响；原 16vp 内边距走内容列 padding、18vp 圆角走外壳 borderRadius、
            // 12vp 上间距走外壳 margin，间距不变。
            Stack({ alignContent: Alignment.TopStart }) {
              if (materialAvailable()) {
                MaterialCardLayer({ layerRadius: 18, layerShadow: false, layerForce: true })
              }
              Column() {
              Row() {
                TextInput({ placeholder: '输入课程名或课程代码', text: this.keyword })
                  .height(48)
                  .enterKeyType(EnterKeyType.Done)
                  .borderRadius($r('sys.float.corner_radius_level12'))
                  .fontSize($r('sys.float.Body_L'))
                  .fontWeight(this.fwMode === 'follow' ? FontWeight.Regular : AppearanceStore.fontWeight(FontWeight.Regular))
                  .backgroundColor($r('sys.color.comp_background_tertiary'))
                  .caretStyle({ color: $r('sys.color.font_emphasize') })
                  .type(InputType.Normal)
                  .fontColor(Theme.colorOf(this.themeColor))
                  .placeholderFont({ size: $r('sys.float.Body_L'), weight: FontWeight.Regular })
                  .layoutWeight(1)
                  .onChange((v: string) => {
                    this.keyword = v;
                  })
                // 「查询」：胶囊小按钮 → MaterialButton（材质走 Toggle 承载层）
                MaterialButton({
                  btnRadius: 10,
                  btnBg: Theme.colorOf(this.themeColor),
                  btnBlur: GlassMaterial.cardBlur(),
                  btnBorderW: GlassMaterial.cardBorderWidth(),
                  btnBorderC: GlassMaterial.borderColor(),
                  btnMargin: { left: 10 },
                  btnOnClick: () => {
                    this.doQuery();
                  }
                }) {
                  Text(this.querying ? '查询中…' : '查询')
                    .fontSize(13)
                    .fontColor(Color.White)
                    .padding({ left: 18, right: 18, top: 10, bottom: 10 })
                }
              }
              .width('100%')

              // 筛选 / 模糊入队
              Row() {
                MaterialButton({
                  btnRadius: 10,
                  btnBg: $r('app.color.bg_chip'),
                  btnBlur: GlassMaterial.cardBlur(),
                  btnBorderW: GlassMaterial.cardBorderWidth(),
                  btnBorderC: GlassMaterial.borderColor(),
                  btnOnClick: () => {
                    this.showFilter = !this.showFilter;
                  }
                }) {
                  Text(this.showFilter ? '收起筛选' : '筛选')
                    .fontSize(12)
                    .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                    .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                }
                MaterialButton({
                  btnRadius: 10,
                  btnBg: $r('app.color.bg_chip'),
                  btnBlur: GlassMaterial.cardBlur(),
                  btnBorderW: GlassMaterial.cardBorderWidth(),
                  btnBorderC: GlassMaterial.borderColor(),
                  btnMargin: { left: 8 },
                  btnOnClick: () => {
                    this.enqueueByKeyword();
                  }
                }) {
                  Text('按课程名模糊入队')
                    .fontSize(12)
                    .fontColor(Theme.colorOf(this.themeColor))
                    .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                }
                Blank()
                if (this.scopes.length > 0) {
                  Text(`轮次 ${this.roundIndex + 1}/${this.scopes.length}`)
                    .fontSize(11)
                    .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                }
              }
              .width('100%')
              .alignItems(VerticalAlign.Center)
              .margin({ top: 10 })

              // 轮次/分类切换（新正方：入口页每个分类一个 scope）
              if (this.scopes.length > 1) {
                Row() {
                  // 轮次胶囊保留实色底：当前轮次靠实色背景 + 白字表达（材质会让出底色、吃掉选中态）
                  ForEach(this.scopes, (scope: SelectScope, index: number) => {
                    Text(scope.label)
                      .fontSize(12)
                      .fontColor(this.roundIndex === index ? Color.White : GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
                      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                      .backgroundColor(this.roundIndex === index
                        ? Theme.colorOf(this.themeColor) : $r('app.color.bg_chip'))
                      .borderRadius(10)
                      .margin({ right: 6 })
                      .onClick(() => {
                        this.roundIndex = index;
                        SelectApi.applyScope(index);
                        this.classes = [];
                        this.log(`已切换轮次：${scope.label}（kklxdm=${scope.params['kklxdm'] !== undefined ? scope.params['kklxdm'] : ''}）`);
                        this.getUIContext().getPromptAction().showToast({ message: `已切换：${scope.label}` });
                        this.loadChosen();
                      })
                  }, (scope: SelectScope, index: number) => `sc${index}${scope.id}`)
                }
                .width('100%')
                .margin({ top: 10 })
              }

              // 筛选条件
              if (this.showFilter) {
                Column() {
                  Row() {
                    TextInput({ placeholder: '教师', text: this.fTeacher })
                      .height(48)
                      .enterKeyType(EnterKeyType.Done)
                      .borderRadius($r('sys.float.corner_radius_level12'))
                      .fontSize($r('sys.float.Body_L'))
                      .fontWeight(this.fwMode === 'follow' ? FontWeight.Regular : AppearanceStore.fontWeight(FontWeight.Regular))
                      .backgroundColor($r('sys.color.comp_background_tertiary'))
                      .caretStyle({ color: $r('sys.color.font_emphasize') })
                      .type(InputType.Normal)
                      .fontColor(Theme.colorOf(this.themeColor))
                      .placeholderFont({ size: $r('sys.float.Body_L'), weight: FontWeight.Regular })
                      .layoutWeight(1)
                      .onChange((v: string) => {
                        this.fTeacher = v;
                      })
                    TextInput({ placeholder: '时间（如 星期一）', text: this.fTime })
                      .height(48)
                      .enterKeyType(EnterKeyType.Done)
                      .borderRadius($r('sys.float.corner_radius_level12'))
                      .fontSize($r('sys.float.Body_L'))
                      .fontWeight(this.fwMode === 'follow' ? FontWeight.Regular : AppearanceStore.fontWeight(FontWeight.Regular))
                      .backgroundColor($r('sys.color.comp_background_tertiary'))
                      .caretStyle({ color: $r('sys.color.font_emphasize') })
                      .type(InputType.Normal)
                      .fontColor(Theme.colorOf(this.themeColor))
                      .placeholderFont({ size: $r('sys.float.Body_L'), weight: FontWeight.Regular })
                      .layoutWeight(1)
                      .margin({ left: 8 })
                      .onChange((v: string) => {
                        this.fTime = v;
                      })
                  }
                  .width('100%')
                  Row() {
                    TextInput({ placeholder: '地点（如 主楼）', text: this.fLoc })
                      .height(48)
                      .enterKeyType(EnterKeyType.Done)
                      .borderRadius($r('sys.float.corner_radius_level12'))
                      .fontSize($r('sys.float.Body_L'))
                      .fontWeight(this.fwMode === 'follow' ? FontWeight.Regular : AppearanceStore.fontWeight(FontWeight.Regular))
                      .backgroundColor($r('sys.color.comp_background_tertiary'))
                      .caretStyle({ color: $r('sys.color.font_emphasize') })
                      .type(InputType.Normal)
                      .fontColor(Theme.colorOf(this.themeColor))
                      .placeholderFont({ size: $r('sys.float.Body_L'), weight: FontWeight.Regular })
                      .layoutWeight(1)
                      .onChange((v: string) => {
                        this.fLoc = v;
                      })
                    TextInput({ placeholder: '学分（如 2）', text: this.fCredit })
                      .height(48)
                      .enterKeyType(EnterKeyType.Done)
                      .borderRadius($r('sys.float.corner_radius_level12'))
                      .fontSize($r('sys.float.Body_L'))
                      .fontWeight(this.fwMode === 'follow' ? FontWeight.Regular : AppearanceStore.fontWeight(FontWeight.Regular))
                      .backgroundColor($r('sys.color.comp_background_tertiary'))
                      .caretStyle({ color: $r('sys.color.font_emphasize') })
                      .type(InputType.Normal)
                      .fontColor(Theme.colorOf(this.themeColor))
                      .placeholderFont({ size: $r('sys.float.Body_L'), weight: FontWeight.Regular })
                      .layoutWeight(1)
                      .margin({ left: 8 })
                      .onChange((v: string) => {
                        this.fCredit = v;
                      })
                  }
                  .width('100%')
                  .margin({ top: 8 })
                  Row() {
                    Text('仅看有空位')
                      .fontSize(12)
                      .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                      .layoutWeight(1)
                    Toggle({ type: ToggleType.Switch, isOn: this.onlyAvailable })
                      .selectedColor(Theme.colorOf(this.themeColor))
                      .onChange((on: boolean) => {
                        this.onlyAvailable = on;
                      })
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                  .margin({ top: 10 })
                  Text('筛选在本次查询结果上生效，改条件后点「查询」重新过滤')
                    .fontSize(11)
                    .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                    .width('100%')
                    .margin({ top: 6 })
                }
                .width('100%')
                .margin({ top: 10 })
              }

              if (this.classes.length > 0) {
                Column() {
                  ForEach(this.classes, (cls: SelectableClass) => {
                    this.classCard(cls)
                  }, (cls: SelectableClass) => `${cls.kchId}-${cls.jxbId}-${cls.doJxbId}`)
                }
                .width('100%')
                .margin({ top: 12 })
              }
              }
              .width(LayoutPolicy.matchParent)
              .padding(16)
            }
            .width('100%')
            .borderRadius(18)
            .clip(true)
            .backgroundColor(materialAvailable() ? Color.Transparent
              : (this.tintBg.length > 0 ? this.tintBg : GlassMaterial.homeCardBg($r('app.color.bg_card'))))
            .backgroundBlurStyle(materialAvailable() ? BlurStyle.NONE : GlassMaterial.cardBlur())
            .border({ width: materialAvailable() ? 0 : GlassMaterial.cardBorderWidth(), color: GlassMaterial.borderColor() })
            .margin({ top: 12 })

            // 已选课程
            // MaterialCard 承载：原 16vp 内边距走 cardPadding、18vp 圆角走 cardRadius、12vp 上间距走 cardMargin
            MaterialCard({
              cardRadius: 18,
              cardPadding: 16,
              cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
              cardBlur: GlassMaterial.cardBlur(),
              cardBorderW: GlassMaterial.cardBorderWidth(),
              cardBorderC: GlassMaterial.borderColor(),
              cardShadow: GlassMaterial.cardShadowStyle(),
              cardMargin: { top: 12 }
            }) {
            Column() {
              Row() {
                Text('已选课程')
                  .fontSize(16)
                  .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Text(`${this.chosen.length} 门`)
                  .fontSize(11)
                  .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
              }
              .width('100%')
              .margin({ bottom: 10 })

              if (this.chosen.length === 0) {
                Text('暂无已选课程（或当前不在选课期）')
                  .fontSize(12)
                  .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                  .width('100%')
              } else {
                ForEach(this.chosen, (item: SelectedCourseItem) => {
                  Row() {
                    Column() {
                      Text(item.courseName)
                        .fontSize(13)
                        .fontColor($r('app.color.text_primary'))
                        .width('100%')
                      Text(`${item.teacher}${item.time.length > 0 ? ` · ${item.time}` : ''}`)
                        .fontSize(11)
                        .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                        .width('100%')
                        .margin({ top: 2 })
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    // 「退选」：结果项小按钮 → MaterialButton（原为浅红玻璃底 + 亮边 + 磨砂，回落值按原值写）
                    MaterialButton({
                      btnRadius: 12,
                      btnBg: 'rgba(219,82,82,0.10)',
                      btnBlur: (AppStorage.get<boolean>('immersiveEffect') ?? false) ? BlurStyle.Thin : BlurStyle.NONE,
                      btnBorderW: 1,
                      btnBorderC: 'rgba(255,255,255,0.28)',
                      btnOnClick: () => {
                        this.doDrop(item);
                      }
                    }) {
                      Text('退选')
                        .fontSize(12)
                        .fontColor('#DB5252')
                        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                    }
                  }
                  .width('100%')
                  .alignItems(VerticalAlign.Center)
                  .padding({ top: 7, bottom: 7 })
                }, (item: SelectedCourseItem) => `${item.kchId}-${item.jxbId}`)
              }
            }
            .width('100%')
            }

            // 运行日志
            if (this.logText.length > 0) {
              // MaterialCard 承载：原 12vp 内边距走 cardPadding、16vp 圆角走 cardRadius、
              // 12vp 上间距走 cardMargin、左对齐走 cardAlignItems
              MaterialCard({
                cardRadius: 16,
                cardPadding: 12,
                cardAlignItems: ItemAlign.Start,
                cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
                cardBlur: GlassMaterial.cardBlur(),
                cardBorderW: GlassMaterial.cardBorderWidth(),
                cardBorderC: GlassMaterial.borderColor(),
                cardShadow: GlassMaterial.cardShadowStyle(),
                cardMargin: { top: 12 }
              }) {
              Column() {
                Row() {
                  Text('运行日志')
                    .fontSize(13)
                    .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                  if (this.grabbing) {
                    // 「停止抢课」：小按钮 → MaterialButton（浅红玻璃底，回落值按原值写）
                    MaterialButton({
                      btnRadius: 9,
                      btnBg: 'rgba(219,82,82,0.10)',
                      btnBlur: (AppStorage.get<boolean>('immersiveEffect') ?? false) ? BlurStyle.Thin : BlurStyle.NONE,
                      btnBorderW: 1,
                      btnBorderC: 'rgba(255,255,255,0.28)',
                      btnOnClick: () => {
                        this.stopGrab();
                      }
                    }) {
                      Text('停止抢课')
                        .fontSize(11)
                        .fontColor('#DB5252')
                        .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                    }
                  }
                }
                .width('100%')
                .margin({ bottom: 6 })
                Text(this.logText)
                  .fontSize(10)
                  .lineHeight(15)
                  .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
                  .width('100%')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              }
            }

            Column()
              .height(this.getUIContext().px2vp(this.bottomInsetPx) + 30)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .height('100%')
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)

        PageHeader({
          title: '快捷选课',
          subtitle: 'BETA · 移植自 zhengfang-apk',
          onBack: () => {
            AppState.stack.pop();
          }
        })
      }
      .width('100%')
      .height('100%')
    }
    .backgroundColor($r('app.color.bg_page'))
    .hideTitleBar(true)
    .systemTransition(NavigationSystemTransitionType.SLIDE_RIGHT)
    .width('100%')
    .height('100%')
  }
}
