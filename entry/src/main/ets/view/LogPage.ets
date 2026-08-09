/**
 * 日志详情页（Navigation 二级页）——展示 log 调试模式收集的功能使用日志与联网反馈
 *  - 标题栏右上角：收集开关（暂停/继续收集）+ 清空按钮
 *  - 操作栏（标题栏下方常驻）：时间排序（最新/最旧）+ 全部导出 / 多选导出（原地切换）
 *  - 分类：Tabs 左右滑动切换（全部 + 各模块），分类条全宽无黑区
 *  - 日志卡片：模块色块 + 结果徽章 + 动作 + 时间；点击展开完整详情
 *  - 详情含：Method / URL / HTTP / 耗时 / 请求头 / 响应头 / 参数 / 异常 / 响应片段
 *  - 长按进入多选导出（导出栏原地切换为 已选 N 条/取消/导出选中）
 */
import { fileIo, picker } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { AppState } from '../common/AppState';
import { LogStore, LogEntry } from '../common/LogStore';
import { PageHeader } from './common/UiKit';

@Component
export struct LogPage {
  /** 日志列表（全量） */
  @State logs: LogEntry[] = [];
  /** 收集开关状态（@StorageProp 同步 LogStore.collecting 对应 UI） */
  @State collecting: boolean = true;
  /** 当前筛选的模块 index（对应 moduleList） */
  @State filterIdx: number = 0;
  /** 时间排序：true=最新在前（倒序），false=最旧在前（正序） */
  @State sortDesc: boolean = true;
  /** 展开查看详情的日志索引集合（数组模拟） */
  @State expanded: number[] = [];
  /** 是否处于多选导出模式 */
  @State selecting: boolean = false;
  /** 已勾选导出的日志索引集合（数组模拟） */
  @State selectedIdx: number[] = [];

  aboutToAppear(): void {
    this.refresh();
  }

  /** 重新读取日志 */
  private refresh(): void {
    this.logs = LogStore.all();
    this.collecting = LogStore.collecting;
    this.expanded = [];
    this.selectedIdx = [];
    this.selecting = false;
  }

  /** 当前筛选的模块名 */
  private currentFilter(): string {
    return this.moduleList()[this.filterIdx] ?? '全部';
  }

  /** 筛选后的可见日志（含原始 index，用于展开/勾选定位）；按时间排序（sortDesc） */
  private visibleLogs(): LogEntry[] {
    const f: string = this.currentFilter();
    const out: LogEntry[] = [];
    const n: number = this.logs.length;
    for (let k = 0; k < n; k++) {
      const i: number = this.sortDesc ? n - 1 - k : k; // 倒序=最新在前，正序=最早在前
      if (f === '全部' || this.logs[i].module === f) {
        out.push(this.logs[i]);
      }
    }
    return out;
  }

  /** 可见日志的原始 index 列表（与 visibleLogs 一一对应） */
  private visibleIndexes(): number[] {
    const f: string = this.currentFilter();
    const idxs: number[] = [];
    const n: number = this.logs.length;
    for (let k = 0; k < n; k++) {
      const i: number = this.sortDesc ? n - 1 - k : k;
      if (f === '全部' || this.logs[i].module === f) {
        idxs.push(i);
      }
    }
    return idxs;
  }

  /** 获取可见日志的原始索引 */
  private getRealIndex(visIdx: number): number {
    return this.visibleIndexes()[visIdx];
  }

  /** 模块列表（去重 + 固定顺序） */
  private moduleList(): string[] {
    const order: string[] = ['网络', '登录', '课表', '成绩', '考试', '新闻', '学业', '日志调试'];
    const seen: string[] = [];
    for (const log of this.logs) {
      if (seen.indexOf(log.module) < 0 && log.module.length > 0) {
        seen.push(log.module);
      }
    }
    const out: string[] = ['全部'];
    for (const m of order) {
      if (seen.indexOf(m) >= 0) {
        out.push(m);
      }
    }
    for (const m of seen) {
      if (out.indexOf(m) < 0) {
        out.push(m);
      }
    }
    return out;
  }

  /** 收集开关切换 */
  private toggleCollecting(on: boolean): void {
    LogStore.collecting = on;
    this.collecting = on;
    promptAction.showToast({ message: on ? '已恢复收集' : '已暂停收集' });
  }

  /** 切换时间排序（最新在前 / 最旧在前） */
  private toggleSort(): void {
    this.sortDesc = !this.sortDesc;
    this.expanded = [];
  }

  /** 清空日志（标题栏右上角） */
  private clearLogs(): void {
    promptAction.showDialog({
      title: '清空日志',
      message: '确定清空全部日志记录吗？',
      buttons: [
        { text: '取消', color: '#888888' },
        { text: '清空', color: '#DB5252', primary: true }
      ]
    }).then((res) => {
      if (res.index === 1) {
        LogStore.clear();
        this.refresh();
        promptAction.showToast({ message: '日志已清空' });
      }
    });
  }

  /** 点击日志：切换展开详情（带动画过渡）；多选模式下切换勾选（index 为原始索引） */
  private tapLog(index: number): void {
    if (this.selecting) {
      this.toggleSelected(index);
      return;
    }
    animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
      const pos: number = this.expanded.indexOf(index);
      if (pos >= 0) {
        this.expanded.splice(pos, 1);
      } else {
        this.expanded.push(index);
      }
      this.expanded = this.expanded.slice();
    });
  }

  /** 长按日志：进入多选模式并勾选该项 */
  private longPressLog(index: number): void {
    if (!this.selecting) {
      this.selecting = true;
      this.selectedIdx = [];
    }
    this.toggleSelected(index);
  }

  /** 切换勾选状态（数组模拟集合） */
  private toggleSelected(index: number): void {
    const pos: number = this.selectedIdx.indexOf(index);
    if (pos >= 0) {
      this.selectedIdx.splice(pos, 1);
    } else {
      this.selectedIdx.push(index);
    }
    this.selectedIdx = this.selectedIdx.slice();
  }

  /** 退出多选模式 */
  private exitSelect(): void {
    this.selecting = false;
    this.selectedIdx = [];
  }

  /** 结果是否异常/失败（用于红色徽章） */
  private isBad(result: string): boolean {
    return result.indexOf('异常') >= 0 || result.indexOf('失败') >= 0 || result.indexOf('错误') >= 0;
  }

  /** 模块标签色块背景（按模块名取固定色） */
  private moduleColor(module: string): string {
    const m: string = module;
    if (m.indexOf('登录') >= 0) {
      return '#2C5FA8';
    }
    if (m.indexOf('课表') >= 0) {
      return '#1C7A52';
    }
    if (m.indexOf('考试') >= 0) {
      return '#A75E17';
    }
    if (m.indexOf('成绩') >= 0) {
      return '#653BAF';
    }
    if (m.indexOf('新闻') >= 0) {
      return '#A93A4E';
    }
    if (m.indexOf('网络') >= 0) {
      return '#177178';
    }
    if (m.indexOf('学业') >= 0) {
      return '#846311';
    }
    if (m.indexOf('通知') >= 0) {
      return '#2F855A';
    }
    if (m.indexOf('校历') >= 0) {
      return '#B7791F';
    }
    return '#49546A';
  }

  /** 单条日志 → 文本（导出用，结构化多行） */
  private entryToText(log: LogEntry): string {
    let out: string = `[${log.time}] [${log.module}] ${log.action} — ${log.result}\n`;
    if (log.method.length > 0) {
      out += `Method: ${log.method}\n`;
    }
    if (log.url.length > 0) {
      out += `URL: ${log.url}\n`;
    }
    if (log.status.length > 0) {
      out += `HTTP: ${log.status}\n`;
    }
    if (log.cost.length > 0) {
      out += `耗时: ${log.cost}\n`;
    }
    if (log.error.length > 0) {
      out += `异常: ${log.error}\n`;
    }
    if (log.reqHeaders.length > 0) {
      out += `请求头: ${log.reqHeaders}\n`;
    }
    if (log.respHeaders.length > 0) {
      out += `响应头: ${log.respHeaders}\n`;
    }
    if (log.params.length > 0) {
      out += `参数: ${log.params}\n`;
    }
    if (log.detail.length > 0) {
      out += `详情: ${log.detail}\n`;
    }
    if (log.bodyPreview.length > 0 || log.fullBody.length > 0) {
      out += `响应体: ${log.fullBody.length > 0 ? log.fullBody : log.bodyPreview}\n`;
    }
    return out;
  }

  /** 全部日志 → 文本 */
  private allToText(): string {
    let out: string = `XJAU-Helper 日志导出 ${new Date().toLocaleString()}\n共 ${this.logs.length} 条\n\n`;
    for (const log of this.logs) {
      out += this.entryToText(log) + '\n';
    }
    return out;
  }

  /** 选中日志 → 文本 */
  private selectedToText(): string {
    let out: string = `XJAU-Helper 日志导出（选中 ${this.selectedIdx.length} 条）\n\n`;
    const idxs: number[] = this.selectedIdx.slice().sort((a: number, b: number) => a - b);
    for (const i of idxs) {
      if (i >= 0 && i < this.logs.length) {
        out += this.entryToText(this.logs[i]) + '\n';
      }
    }
    return out;
  }

  /** 导出文本到用户选择的文件（txt） */
  private exportText(content: string, name: string): void {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [name];
      options.fileSuffixChoices = ['.txt'];
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      docPicker.save(options).then((uris: string[]) => {
        if (uris.length === 0) {
          promptAction.showToast({ message: '已取消导出' });
          return;
        }
        try {
          const file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
          fileIo.writeSync(file.fd, content);
          fileIo.closeSync(file);
          promptAction.showToast({ message: '日志已导出' });
        } catch (e) {
          promptAction.showToast({ message: '导出失败' });
        }
      }).catch(() => {
        promptAction.showToast({ message: '导出失败' });
      });
    } catch (e) {
      promptAction.showToast({ message: '导出失败' });
    }
  }

  /** 全部导出 */
  private exportAll(): void {
    if (this.logs.length === 0) {
      promptAction.showToast({ message: '暂无日志可导出' });
      return;
    }
    const stamp: string = `${new Date().getHours()}_${new Date().getMinutes()}`;
    this.exportText(this.allToText(), `xjau-helper_logs_${stamp}.txt`);
  }

  /** 导出选中（无选中提示） */
  private exportSelected(): void {
    if (this.selectedIdx.length === 0) {
      promptAction.showToast({ message: '请先选择要导出的日志' });
      return;
    }
    const stamp: string = `${new Date().getHours()}_${new Date().getMinutes()}`;
    this.exportText(this.selectedToText(), `xjau-helper_logs_${stamp}.txt`);
  }

  /** 单个分类的日志列表（TabContent 内容） */
  @Builder
  logListTab(f: string) {
    Column() {
      if (this.logs.length === 0) {
        Column() {
          Text('暂无日志')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('开启日志调试后，这里会展示各功能模块的使用日志与联网反馈')
            .fontSize(12)
            .fontColor($r('app.color.text_tertiary'))
            .margin({ top: 8 })
            .textAlign(TextAlign.Center)
            .padding({ left: 30, right: 30 })
        }
        .width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
      } else {
        List({ space: 8 }) {
          ForEach(this.visibleLogs(), (log: LogEntry, visIdx: number) => {
            ListItem() {
              Column() {
                // 标题行：展开箭头/勾选 + 模块色块 + 结果徽章 + 动作 + 时间
                Row() {
                  if (this.selecting) {
                    Text(this.selectedIdx.indexOf(this.getRealIndex(visIdx)) >= 0 ? '✓' : '')
                      .fontSize(14)
                      .fontWeight(FontWeight.Bold)
                      .fontColor(Color.White)
                      .width(20).height(20)
                      .textAlign(TextAlign.Center)
                      .backgroundColor(this.selectedIdx.indexOf(this.getRealIndex(visIdx)) >= 0 ? $r('app.color.brand') : '#33000000')
                      .borderRadius(10)
                  } else {
                    // 展开箭头：默认朝右，展开后顺时针旋转 90°（朝下）
                    Image($r('app.media.next'))
                      .width(20)
                      .height(20)
                      .rotate({ angle: this.expanded.indexOf(this.getRealIndex(visIdx)) >= 0 ? 90 : 0 })
                      .margin({ right: 8 })
                  }
                  Text(log.module)
                    .fontSize(10)
                    .fontColor(Color.White)
                    .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                    .backgroundColor(this.moduleColor(log.module))
                    .borderRadius(6)
                    .margin({ left: 10 })
                  Text(log.result)
                    .fontSize(10)
                    .fontColor(Color.White)
                    .padding({ left: 7, right: 7, top: 2, bottom: 2 })
                    .backgroundColor(this.isBad(log.result) ? '#DB5252' : $r('app.color.brand'))
                    .borderRadius(6)
                    .margin({ left: 12 })
                  Text(log.action)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)
                    .margin({ left: 12 })
                  Text(log.time)
                    .fontSize(11)
                    .fontColor($r('app.color.text_tertiary'))
                }
                .width('100%')

                // 展开详情（带透明度 + 微缩放过渡动画）
                if (this.expanded.indexOf(this.getRealIndex(visIdx)) >= 0) {
                  Column() {
                    Divider().color($r('app.color.divider')).margin({ top: 8, bottom: 8 })
                    this.detailRows(log)
                  }
                  .transition(TransitionEffect.asymmetric(
                    TransitionEffect.OPACITY.combine(TransitionEffect.scale({ x: 0.97, y: 0.97 })),
                    TransitionEffect.OPACITY
                  ))
                }
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(12)
              .backgroundColor(this.selectedIdx.indexOf(this.getRealIndex(visIdx)) >= 0 ? $r('app.color.brand_light') : $r('app.color.bg_card'))
              .borderRadius(14)
              .onClick(() => {
                this.tapLog(this.getRealIndex(visIdx));
              })
              .gesture(
                LongPressGesture()
                  .onAction(() => {
                    this.longPressLog(this.getRealIndex(visIdx));
                  })
              )
            }
          }, (log: LogEntry, visIdx: number) => `${log.time}_${log.detail}_${visIdx}`)
        }
        .width('100%').layoutWeight(1)
        .padding({ left: 16, right: 16, bottom: 8 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .width('100%').height('100%')
  }

  /** 分类栏 tabBar（chips 样式，胶囊之间留 8 间距） */
  @Builder
  tabBarItem(name: string, index: number) {
    Text(name)
      .fontSize(12)
      .fontColor(this.filterIdx === index ? $r('app.color.brand_on') : $r('app.color.text_secondary'))
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .backgroundColor(this.filterIdx === index ? $r('app.color.brand') : $r('app.color.bg_chip'))
      .borderRadius(14)
      .margin({ right: 8 })
  }

  /** 日志详情展开区（对齐开发者工具网络面板信息量） */
  @Builder
  detailRows(log: LogEntry) {
    Column() {
      if (log.method.length > 0) {
        this.row('方法', log.method)
      }
      if (log.url.length > 0) {
        this.row('URL', log.url)
      }
      if (log.status.length > 0) {
        this.row('状态', `HTTP ${log.status}`)
      }
      if (log.cost.length > 0) {
        this.row('耗时', log.cost)
      }
      if (log.params.length > 0) {
        this.row('参数', log.params)
      }
      if (log.error.length > 0) {
        this.row('异常', log.error)
      }
      if (log.reqHeaders.length > 0) {
        this.row('请求头', log.reqHeaders)
      }
      if (log.respHeaders.length > 0) {
        this.row('响应头', log.respHeaders)
      }
      if (log.detail.length > 0) {
        this.row('详情', log.detail)
      }
      if (log.bodyPreview.length > 0 || log.fullBody.length > 0) {
        this.row('响应体', log.fullBody.length > 0 ? log.fullBody : log.bodyPreview)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 8 })
  }

  /** 详情行：label 左对齐（靠左放）+ 固定列宽，value 从统一位置开始；行高统一避免高度参差 */
  @Builder
  row(label: string, value: string) {
    Row() {
      Text(label)
        .fontSize(11)
        .lineHeight(17)
        .fontColor($r('app.color.text_tertiary'))
        .width(52)
        .margin({ right: 10 })
      Text(value)
        .fontSize(11)
        .lineHeight(17)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
        .copyOption(CopyOptions.InApp)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: 4 })
  }

  /** 标题栏下方的操作栏：常驻显示。
   *   - 排序按钮（最新↓ / 最旧↑）随时可切
   *   - 普通模式：长按提示 + 全部导出
   *   - 多选模式：已选 N 条 + 取消 + 导出选中（原地切换，不位移到底部） */
  @Builder
  exportBar() {
    Row() {
      // 时间排序切换（正 / 反）
      Text(this.sortDesc ? '最新 ↓' : '最旧 ↑')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .padding({ left: 12, right: 12, top: 6, bottom: 6 })
        .backgroundColor($r('app.color.bg_chip'))
        .borderRadius(14)
        .onClick(() => {
          this.toggleSort();
        })
      Text(this.selecting ? `已选 ${this.selectedIdx.length} 条` : '长按日志可多选导出')
        .fontSize(11)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ left: 10 })
      Blank()
      if (this.selecting) {
        Text('取消')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.bg_chip'))
          .borderRadius(16)
          .onClick(() => {
            this.exitSelect();
          })
        Text('导出选中')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.brand_on'))
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.brand'))
          .borderRadius(16)
          .margin({ left: 10 })
          .onClick(() => {
            this.exportSelected();
          })
      } else {
        Text('全部导出')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.brand_on'))
          .padding({ left: 14, right: 14, top: 6, bottom: 6 })
          .backgroundColor($r('app.color.brand'))
          .borderRadius(16)
          .onClick(() => {
            this.exportAll();
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 10, bottom: 4 })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: '日志详情',
          subtitle: LogStore.enabled() ? (this.collecting ? '正在收集' : '已暂停') : '日志调试未开启',
          actionText: '清空',
          showActionToggle: true,
          actionToggleOn: this.collecting,
          onBack: () => {
            AppState.stack.pop();
          },
          onAction: () => {
            this.clearLogs();
          },
          onActionToggle: (on: boolean) => {
            this.toggleCollecting(on);
          }
        })

        // 操作栏（标题栏下方常驻：排序 + 全部导出/多选导出；不跑到底部）
        this.exportBar()

        // 分类 Tabs：左右滑动切换分类，分类条全宽延伸屏幕（无黑区）
        Tabs({ barPosition: BarPosition.Start, index: this.filterIdx }) {
          ForEach(this.moduleList(), (m: string, i: number) => {
            TabContent() {
              this.logListTab(m)
            }
            .tabBar(this.tabBarItem(m, i))
          }, (m: string) => m)
        }
        .vertical(false)
        .scrollable(true) // 支持左右滑动切换分类
        .barMode(BarMode.Scrollable, { margin: 8 })
        .barBackgroundColor($r('app.color.bg_page'))
        .barHeight(44)
        .width('100%')
        .layoutWeight(1)
        .onChange((index: number) => {
          this.filterIdx = index;
          this.expanded = [];
        })
      }
      .width('100%').height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .hideTitleBar(true)
    .width('100%').height('100%')
  }
}
