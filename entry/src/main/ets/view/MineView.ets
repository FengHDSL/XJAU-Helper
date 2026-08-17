/**
 * 我的：学业概览 + 常用功能 + 设置
 */
import { SheetUtil } from '../common/SheetUtil';
import { promptAction, mediaquery } from '@kit.ArkUI';
import { common, contextConstant } from '@kit.AbilityKit';
import { storageStatistics, fileIo, picker, fileUri } from '@kit.CoreFileKit';
import { webview } from '@kit.ArkWeb';
import { JwApi } from '../api/JwApi';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { DataStore } from '../common/DataStore';
import { Theme } from '../common/ThemeUtil';
import { AcademicReport, UserProfile } from '../model/Models';
import { EMPTY_REPORT } from '../model/Empty';
import { SettingRow } from './common/UiKit';
import { WebSurface } from './WebSurface';

@Component
export struct MineView {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 日志调试开关（AppStorage 响应式）：开启后显示「日志详情」入口 */
  @StorageProp('logEnabled') logEnabled: boolean = false;
  /** 日志收集状态（AppStorage 响应式）：收集中=亮绿灯，暂停=灰灯 */
  @StorageProp('logCollecting') logCollecting: boolean = true;
  @StorageLink('showAvatar') showAvatar: boolean = false;
  @State report: AcademicReport = EMPTY_REPORT;
  @State loaded: boolean = false;
  @State showWeb: boolean = false;
  @State syncing: boolean = false;
  @State photo: string = '';
  @State cacheSizeText: string = '计算中…';
  @State isLandscape: boolean = false;
  private landscapeListener: mediaquery.MediaQueryListener | null = null;
  onLogout: () => void = () => {
  };
  /** 前往登录页（不退出登录，从"我的"页退出弹窗第二项触发） */
  onGotoLogin: () => void = () => {
  };

  /** 页面出现：加载学业概览并刷新缓存大小 */
  aboutToAppear(): void {
    this.load();
    this.refreshCacheSize();
    this.listenLandscape();
  }

  aboutToDisappear(): void {
    this.landscapeListener = null;
  }

  /** 监听屏幕方向变化（横屏时拆分为两列铺满屏幕） */
  private listenLandscape(): void {
    const mq: mediaquery.MediaQueryResult = mediaquery.matchMediaSync('(orientation: landscape)');
    this.isLandscape = mq.matches;
    this.landscapeListener = mediaquery.matchMediaSync('(orientation: landscape)');
    this.landscapeListener.on('change', (res: mediaquery.MediaQueryResult) => {
      this.isLandscape = res.matches;
    });
  }

  /** 异步刷新缓存大小（MB）
   * OS 不会立即回收磁盘空间，所以清完缓存后延迟 500ms 再读两次，
   * 让 DataStore 写回 / 系统回收都发生之后再显示新值。
   */
  /** 异步读取应用缓存大小并格式化显示（MB/KB） */
  private refreshCacheSize(delayMs: number = 0): void {
    if (delayMs > 0) {
      this.cacheSizeText = '计算中…';
      setTimeout(() => this.refreshCacheSize(0), delayMs);
      return;
    }
    storageStatistics.getCurrentBundleStats().then((stats) => {
      const mb: number = stats.cacheSize / 1024 / 1024;
      this.cacheSizeText = mb < 0.1 ? `${(stats.cacheSize / 1024).toFixed(1)} KB` : `${mb.toFixed(2)} MB`;
    }).catch(() => {
      this.cacheSizeText = '0 MB';
    });
  }

  /** 递归清空目录下全部内容（文件/子目录），用于清理 WebView 磁盘缓存等 */
  private clearDirRecursive(dir: string): void {
    let names: string[] = [];
    try {
      names = fileIo.listFileSync(dir);
    } catch (e) {
      // 目录不存在等情况直接忽略
      return;
    }
    for (const name of names) {
      const child: string = `${dir}/${name}`;
      // 跳过 WebView Cookie 目录（教务登录会话依赖，与 DailyNic 不同：本应用必须保留 Cookie）
      if (name === 'Cookies' && child.indexOf('/web/') >= 0) {
        continue;
      }
      try {
        const stat: fileIo.Stat = fileIo.statSync(child);
        if (stat.isDirectory()) {
          this.clearDirRecursive(child);
          fileIo.rmdirSync(child);
        } else {
          fileIo.unlinkSync(child);
        }
      } catch (e) {
        // 单个文件失败不影响整体（如 WebView 正在占用）
      }
    }
  }

  /** 清除应用全部缓存（模块级 + 应用级，EL1 + EL2 四个缓存目录，官方文档思路） */
  private clearAllCache(): void {
    const cacheDirs: string[] = [];
    try {
      const curContext: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const originArea: contextConstant.AreaMode = curContext.area;

      // 1. 模块级当前加密级别的缓存目录（默认 EL2）
      cacheDirs.push(curContext.cacheDir);

      // 2. 切换 area 获取另一个加密级别的模块级缓存目录
      if (originArea === contextConstant.AreaMode.EL2) {
        curContext.area = contextConstant.AreaMode.EL1;
      } else {
        curContext.area = contextConstant.AreaMode.EL2;
      }
      cacheDirs.push(curContext.cacheDir);
      // 恢复原始加密级别
      curContext.area = originArea;

      // 3. 获取应用级 Context 的缓存目录
      const applicationContext: common.ApplicationContext = curContext.getApplicationContext();
      const originAppArea: contextConstant.AreaMode = applicationContext.area;
      cacheDirs.push(applicationContext.cacheDir);

      // 4. 切换应用级 area 获取另一个加密级别的缓存目录
      if (originAppArea === contextConstant.AreaMode.EL2) {
        applicationContext.area = contextConstant.AreaMode.EL1;
      } else {
        applicationContext.area = contextConstant.AreaMode.EL2;
      }
      cacheDirs.push(applicationContext.cacheDir);
      // 恢复原始加密级别
      applicationContext.area = originAppArea;
    } catch (e) {
      // 获取目录失败时退化为仅当前 cacheDir
      try {
        const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
        cacheDirs.push(ctx.cacheDir);
      } catch (e2) {
        // ignore
      }
    }

    // 5. 逐个清除所有缓存目录
    for (let i = 0; i < cacheDirs.length; i++) {
      this.clearDirRecursive(cacheDirs[i]);
    }
  }

  /** 释放 WebView 内存（参考 DailyNic_HMOS：trimMemoryByPressureLevel） */
  private trimWebMemory(): void {
    try {
      webview.WebviewController.trimMemoryByPressureLevel(webview.PressureLevel.MEMORY_PRESSURE_LEVEL_MODERATE);
    } catch (e) {
      // ignore
    }
  }

  /** 导出备份：课表内容 + 课程表设置项 + 主题颜色 → 打包 txt */
  private exportBackup(): void {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const d: Date = new Date();
      const stamp: string = `${d.getFullYear()}${(d.getMonth() + 1).toString().padStart(2, '0')}${d.getDate().toString().padStart(2, '0')}_${d.getHours().toString().padStart(2, '0')}${d.getMinutes().toString().padStart(2, '0')}`;
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [`xjau-helper_backup_${stamp}.txt`];
      options.fileSuffixChoices = ['.txt'];
      // 打包备份数据（课程表内容 / 课程表设置项 / 主题颜色）
      const data: Record<string, string> = {
        'app': 'xjau-helper',
        'type': 'schedule-backup',
        'version': '1',
        'themeColor': Theme.current(),
        'courses': DataStore.get(DataStore.KEY_COURSES),
        'scheduleCfg': DataStore.get(DataStore.KEY_SCHEDULE_CFG),
        'scheduleBg': DataStore.getScheduleBg(),
        'scheduleDashed': DataStore.get(DataStore.KEY_SCHEDULE_DASHED),
        'courseColorMap': DataStore.get(DataStore.KEY_COURSE_COLOR_MAP),
        'courseCustomColor': DataStore.getCourseCustomColors()
      };
      const content: string = JSON.stringify(data);
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
          promptAction.showToast({ message: '备份已导出' });
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

  /** 导入备份：选择 txt → 解析 → 恢复课表内容/课程表设置项/主题颜色 */
  private importBackup(): void {
    try {
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['txt'];
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      docPicker.select(options).then((uris: string[]) => {
        if (uris.length === 0) {
          promptAction.showToast({ message: '已取消导入' });
          return;
        }
        try {
          const content: string = fileIo.readTextSync(new fileUri.FileUri(uris[0]).path);
          const obj: Record<string, string> = JSON.parse(content) as Record<string, string>;
          // 校验备份格式
          if (obj['app'] !== 'xjau-helper' || obj['type'] !== 'schedule-backup') {
            promptAction.showToast({ message: '不是有效的备份文件' });
            return;
          }
          // 恢复课程表内容
          DataStore.put(DataStore.KEY_COURSES, obj['courses'] ?? '');
          // 恢复课程表设置项
          DataStore.setScheduleCfg(obj['scheduleCfg'] ?? '');
          DataStore.setScheduleBg(obj['scheduleBg'] ?? '');
          DataStore.put(DataStore.KEY_SCHEDULE_DASHED, obj['scheduleDashed'] ?? '');
          DataStore.put(DataStore.KEY_COURSE_COLOR_MAP, obj['courseColorMap'] ?? '');
          DataStore.setCourseCustomColors(obj['courseCustomColor'] ?? '');
          // 恢复主题颜色（写入 AppStorage + 持久化）
          const theme: string = obj['themeColor'] ?? '';
          if (theme === 'red' || theme === 'blue' || theme === 'green') {
            Theme.apply(theme);
          }
          promptAction.showToast({ message: '恢复成功，重新进入课程表查看' });
        } catch (e) {
          promptAction.showToast({ message: '导入失败，文件格式不正确' });
        }
      }).catch(() => {
        promptAction.showToast({ message: '导入失败' });
      });
    } catch (e) {
      promptAction.showToast({ message: '导入失败' });
    }
  }

  /** 最近同步时间文案 */
  private lastSyncText(): string {
    if (this.syncing) {
      return '同步中…';
    }
    const ts: number = JwApi.lastRefreshTime();
    if (ts <= 0) {
      return '尚未同步';
    }
    const d: Date = new Date(ts);
    return `${d.getMonth() + 1}/${d.getDate()} ${d.getHours()}:${d.getMinutes() < 10 ? '0' + d.getMinutes() : d.getMinutes()}`;
  }

  /** 立即重新拉取全部数据并写入本地缓存 */
  private async syncNow(): Promise<void> {
    if (this.syncing) {
      return;
    }
    this.syncing = true;
    promptAction.showToast({ message: '正在同步教务数据…' });
    try {
      JwApi.USE_MOCK = false;
      await JwApi.refreshAll();
      this.report = JwApi.loadCachedAcademic();
      promptAction.showToast({ message: '数据已更新' });
    } catch (e) {
      promptAction.showToast({ message: '同步失败，请检查网络' });
    } finally {
      this.syncing = false;
    }
  }

  /** 在应用内打开网页（注入会话 Cookie 保持登录态），通过底部全屏弹层展示 */
  private openWeb(url: string, title: string): void {
    if (JwApi.USE_MOCK && !AppState.debugNetwork) {
      promptAction.showToast({ message: '当前模式禁止使用' });
      return;
    }
    AppState.webUrl = url;
    AppState.webTitle = title;
    this.showWeb = true;
  }

  private async load(): Promise<void> {
    // 先用缓存秒开
    const cached: AcademicReport = JwApi.loadCachedAcademic();
    if (cached.gpa > 0 || cached.totalRequired > 0) {
      this.report = cached;
      this.loaded = true;
    }
    // 头像：先读缓存（与首页一致；功能浏览模式不读真实缓存，避免泄露）
    const cachedPhoto: string = JwApi.loadCachedPhoto();
    if (cachedPhoto.length > 0) {
      this.photo = cachedPhoto;
    }
    try {
      this.report = await JwApi.getAcademic();
      // 拉取头像（与首页一致）
      const p: string = await JwApi.getPhoto();
      if (p.length > 0) {
        this.photo = p;
      }
      // 尝试从"查询个人信息"页面补充学院等字段（若之前为空）
      if (AppState.profile !== null && AppState.profile.college.length === 0) {
        const enriched: UserProfile | null = await JwApi.fetchFullProfile();
        if (enriched !== null && enriched.college.length > 0) {
          AppState.profile = enriched;
        }
      }
      this.loaded = true;
    } catch (e) {
      // 网络异常时保持缓存
      this.loaded = true;
    }
  }

  /** 弹出退出登录确认框：取消 / 前往登录页（不退出）/ 退出 */
  private confirmLogout(): void {
    promptAction.showDialog({
      title: '退出登录',
      message: '退出后需要重新使用学号密码登录，确定退出吗？',
      buttons: [
        { text: '取消', color: '#888888' },
        { text: '前往登录页', color: '#888888' },
        { text: '退出', color: '#F0524D' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        // 前往登录页：不退出登录，仅跳转登录界面（可返回）
        this.onGotoLogin();
      } else if (result.index === 2) {
        JwApi.logout();
        AppState.clear();
        this.onLogout();
      }
    });
  }

  /** 长按退出按钮：功能浏览模式提示模式名称（调试模式提示调试模式），真实登录提示登录方式 / 日志调试 */
  private showLoginMethod(): void {
    if (JwApi.USE_MOCK) {
      promptAction.showToast({ message: AppState.debugNetwork ? '调试模式' : '功能浏览模式', duration: 2000 });
      return;
    }
    if (AppState.logEnabled) {
      promptAction.showToast({ message: 'log 调试', duration: 2000 });
      return;
    }
    const method: string = DataStore.getLoginMethod();
    const text: string = method === 'web' ? '当前为网页登录' : (method === 'pwd' ? '当前为密码登录' : '当前登录方式未知');
    promptAction.showToast({ message: text, duration: 2000 });
  }

  /** 打开网页端教务系统（在"外部链接"页面中访问，自动注入会话 Cookie 保持登录态） */
  private openWebPortal(): void {
    if (JwApi.USE_MOCK && !AppState.debugNetwork) {
      promptAction.showToast({ message: '当前模式禁止使用' });
      return;
    }
    AppState.webUrl = Const.WEB_PORTAL_URL;
    AppState.webTitle = '网页端教务系统';
    AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
  }

  @Builder
  titleBar() {
    // 顶部固定标题栏：浅色=主题色（中国红/天空蓝/农大绿），深色=黑色
    // 高度与其他主题色顶栏统一（topInset + 72vp 外高，内容区 48vp）
    Row() {
      Text('我的')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
      Blank()
    }
    .width('100%')
    .height(px2vp(this.topInsetPx) + 60)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16, top: px2vp(this.topInsetPx) + 12, bottom: 12 })
    .backgroundColor(this.isDarkMode ? '#1A1D1C' : Theme.colorOf(this.themeColor))
  }

  @Builder
  avatarCard() {
    // 头像卡片：showAvatar 仅控制圆形头像的显示/隐藏，其余信息 + 右侧退出按钮始终显示
    Row() {
      if (this.showAvatar) {
        if (this.photo.length > 0) {
          Image('data:image/jpeg;base64,' + this.photo)
            .width(52)
            .height(52)
            .borderRadius(26)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.bg_chip'))
        } else if (JwApi.USE_MOCK) {
          // 功能浏览模式：使用默认占位头像
          Image($r('app.media.default_avatar'))
            .width(52)
            .height(52)
            .borderRadius(26)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.bg_chip'))
        } else {
          Text(AppState.avatarText())
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand'))
            .width(52)
            .height(52)
            .borderRadius(26)
            .backgroundColor($r('app.color.bg_chip'))
            .textAlign(TextAlign.Center)
        }
      }

      Column() {
        Text(AppState.displayName())
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.identityLine())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: this.showAvatar ? 12 : 0 })
      .layoutWeight(1)

      Blank()

      // 右侧：红色圆形退出登录按钮（用 退出.png 图标）
      Button() {
        Image($r('app.media.power'))
          .width(20)
          .height(20)
          .fillColor('#FFFFFF')
      }
      .width(44)
      .height(44)
      .backgroundColor($r('app.color.state_danger'))
      .borderRadius(22)
      .onClick(() => {
        this.confirmLogout();
      })
      // 长按提示当前登录方式（密码登录 / 网页登录）
      .gesture(
        LongPressGesture()
          .onAction(() => {
            this.showLoginMethod();
          })
      )
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(16)
  }

  /** 学号 · 学院 · 班级 */
  private identityLine(): string {
    const p: UserProfile | null = AppState.profile;
    const parts: string[] = [];
    if (AppState.studentId().length > 0) {
      parts.push(AppState.studentId());
    }
    if (p !== null && p.college.length > 0) {
      parts.push(p.college);
    }
    if (p !== null && p.className.length > 0) {
      parts.push(p.className);
    }
    return parts.length > 0 ? parts.join(' · ') : '未登录';
  }

  @Builder
  academicCard() {
    Row() {
      Column() {
        Text(this.loaded ? `${this.report.totalEarned}` : '--')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand'))
        Text('已修学分')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 3 })
      }
      .layoutWeight(1)

      Column() {
        Text(this.loaded ? this.report.gpa.toFixed(2) : '--')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.accent_blue'))
        Text('平均绩点')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 3 })
      }
      .layoutWeight(1)

      Text('›')
        .fontSize(18)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
    .onClick(() => {
      AppState.stack.pushPath({ name: Const.ROUTE_ACADEMIC });
    })
  }

  build() {
    Column() {
      this.titleBar()
      if (this.isLandscape) {
        this.mineLandscape()
      } else {
      // 中间内容：可滚动；横屏/平板下内容限宽 720vp 并居中（一多适配）
      Row() {
        Scroll() {
          Column() {
          // 头像卡片（始终显示；圆形头像由 showAvatar 开关控制）
          Row() {
            this.avatarCard()
          }
          .margin({ bottom: 14 })

          this.academicCard()

          // 主题颜色 + 头像显示（上移到个人卡片区，学业情况下方）
          Column() {
            SettingRow({
              icon: '', title: '主题颜色', value: this.themeColor === 'red' ? '中国红' : (this.themeColor === 'blue' ? '天空蓝' : '农大绿'), onTap: () => {
                promptAction.showActionMenu({
                  title: '顶栏主题色',
                  buttons: [
                    { text: '中国红', color: '#C3272B' },
                    { text: '天空蓝', color: '#3B82F6' },
                    { text: '农大绿', color: '#079841' }
                  ]
                }).then((res) => {
                  const themes: string[] = ['red', 'blue', 'green'];
                  if (res.index >= 0 && res.index < themes.length) {
                    Theme.apply(themes[res.index]);
                  }
                });
              }
            })
            Divider().color($r('app.color.divider'))
            Row() {
              Text('头像显示')
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.showAvatar })
                .selectedColor($r('app.color.brand'))
                .onChange((isOn: boolean) => {
                  this.showAvatar = isOn;
                  DataStore.put(DataStore.KEY_SHOW_AVATAR, isOn ? '1' : '0');
                })
            }
            .width('100%')
            .height(52)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(18)
          .margin({ top: 14 })

          // 常用功能：空闲教室查询 / 考试查询 / 学业情况
          Column() {
            SettingRow({
              icon: '', title: '空闲教室查询', onTap: () => {
                AppState.stack.pushPath({ name: Const.ROUTE_EMPTY_ROOM });
              }
            })
            Divider().color($r('app.color.divider'))
            SettingRow({
              icon: '', title: '考试查询', onTap: () => {
                AppState.stack.pushPath({ name: Const.ROUTE_EXAM });
              }
            })
            Divider().color($r('app.color.divider'))
            SettingRow({
              icon: '', title: '学业情况', onTap: () => {
                AppState.stack.pushPath({ name: Const.ROUTE_ACADEMIC });
              }
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(18)
          .margin({ top: 14 })

          // 设置（顺序：网页版教务系统 → 数据同步 → 头像显示 → 清除缓存 → 恢复备份 → 清空数据 → 隐私协议 → 关于）
          Column() {
            // 1. 网页端教务系统（最顶上）
            SettingRow({
              icon: '', title: '网页端教务系统', value: '', onTap: () => {
                this.openWebPortal();
              }
            })
            Divider().color($r('app.color.divider'))
            // 1.1 学校官网（外部链接页打开）
            SettingRow({
              icon: '', title: '学校官网', value: '', onTap: () => {
                if (JwApi.USE_MOCK && !AppState.debugNetwork) {
                  promptAction.showToast({ message: '当前模式禁止使用' });
                  return;
                }
                AppState.webUrl = 'https://www.xjau.edu.cn/';
                AppState.webTitle = '学校官网';
                AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
              }
            })
            Divider().color($r('app.color.divider'))
            // 2. 数据同步
            SettingRow({
              icon: '', title: '数据同步', value: this.lastSyncText(), onTap: () => {
                this.syncNow();
              }
            })
            Divider().color($r('app.color.divider'))
            // 5. 清除缓存（低配版清除数据：保留登录信息/登录 Cookie/用户设置，只删数据缓存）
            SettingRow({
              icon: '', title: '清除缓存', value: this.cacheSizeText, onTap: () => {
                promptAction.showDialog({
                  title: '清除缓存',
                  message: '将删除课表、成绩、考试、通知、校历、头像等数据缓存，\n并释放网页内存与磁盘缓存，\n保留登录信息、登录 Cookie 与您的个性化设置。确认继续？',
                  buttons: [
                    { text: '取消', color: '#666666' },
                    { text: '确认清除', color: '#DB5252', primary: true }
                  ]
                }).then((res) => {
                  if (res.index === 1) {
                    // 数据缓存（登录信息/历史账号/登录凭据/用户设置等一律保留）
                    DataStore.remove(DataStore.KEY_PROFILE);
                    DataStore.remove(DataStore.KEY_COURSES);
                    DataStore.remove(DataStore.KEY_TERM_SCORES);
                    DataStore.remove(DataStore.KEY_EXAMS);
                    DataStore.remove(DataStore.KEY_ACADEMIC);
                    DataStore.remove(DataStore.KEY_NOTICES);
                    DataStore.remove(DataStore.KEY_NOTICES_JWC);
                    DataStore.remove(DataStore.KEY_TEACHING_CAL);
                    DataStore.remove(DataStore.KEY_JWC_CAL);
                    DataStore.remove(DataStore.KEY_PHOTO);
                    DataStore.remove(DataStore.KEY_CACHE_TIME);
                    // 清 WebView DOM 存储（新闻等网页缓存），保留 Cookie（教务登录会话）
                    try {
                      webview.WebStorage.deleteAllData();
                    } catch (e) {
                      // ignore
                    }
                    // 释放 WebView 内存（参考 DailyNic_HMOS trimMemoryByPressureLevel）
                    this.trimWebMemory();
                    // 清空应用磁盘缓存（模块级+应用级，EL1+EL2 四个目录：WebView HTTP 缓存、导出临时文件等）
                    this.clearAllCache();
                    promptAction.showToast({ message: '已清除缓存（保留登录信息与设置）' });
                    this.refreshCacheSize(500);
                  }
                });
              }
            })
            Divider().color($r('app.color.divider'))
            // 6. 恢复备份（导出/导入：课表内容 + 课程表设置项 + 主题颜色，打包为 txt）
            SettingRow({
              icon: '', title: '恢复备份', value: '', onTap: () => {
                promptAction.showActionMenu({
                  title: '恢复备份',
                  buttons: [
                    { text: '导出备份', color: '#1B7F5F' },
                    { text: '导入备份', color: '#3B82F6' }
                  ]
                }).then((res) => {
                  if (res.index === 0) {
                    this.exportBackup();
                  } else if (res.index === 1) {
                    this.importBackup();
                  }
                });
              }
            })
            Divider().color($r('app.color.divider'))
            // 7. 清空数据（确认后提示手动重启）
            SettingRow({
              icon: '', title: '清空数据', value: '', onTap: () => {
                promptAction.showDialog({
                  title: '清空数据',
                  message: '将清除全部使用记录（历史账号、缓存、个人信息等），此操作不可恢复，确认继续？',
                  buttons: [
                    { text: '取消', color: '#666666' },
                    { text: '确认清空', color: '#DB5252', primary: true }
                  ]
                }).then((res) => {
                  if (res.index === 1) {
                    DataStore.clearAll();
                    AppState.profile = null;
                    promptAction.showDialog({
                      title: '清空完成',
                      message: '全部数据已清空，请手动重启应用以刷新界面',
                      buttons: [{ text: '知道了', color: '#1B7F5F' }]
                    });
                  }
                });
              }
            })
            Divider().color($r('app.color.divider'))
            // 8. 隐私协议（打开独立页面）
            SettingRow({
              icon: '', title: '隐私协议', value: '', onTap: () => {
                AppState.stack.pushPath({ name: Const.ROUTE_PRIVACY });
              }
            })
            Divider().color($r('app.color.divider'))
            // 9. 关于（打开独立页面）
            SettingRow({
              icon: '', title: '关于', value: 'v1.2.4', onTap: () => {
                AppState.stack.pushPath({ name: Const.ROUTE_ABOUT });
              }
            })
            // 10. 日志详情（仅登录账号且开启日志调试时显示，分隔线一并条件渲染；
            //     收集中=亮绿灯，暂停=灰色灭灯）
            if (this.logEnabled && AppState.profile !== null) {
              Divider().color($r('app.color.divider'))
              SettingRow({
                icon: '',
                title: '日志详情',
                value: this.logCollecting ? '● 收集中' : '○ 已暂停',
                valueColor: this.logCollecting ? $r('app.color.brand') : $r('app.color.text_tertiary'),
                onTap: () => {
                  AppState.stack.pushPath({ name: Const.ROUTE_LOG });
                }
              })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(18)
          .margin({ top: 14 })

        // 数据来源（Scroll 大 Column 内部）
        Column() {
          Text('数据来源: 新疆农业大学教务系统').fontSize(11)
            .fontColor($r('app.color.text_tertiary')).width('100%').textAlign(TextAlign.Center)
          Text('新疆农业大学新闻网').fontSize(11)
            .fontColor($r('app.color.text_tertiary')).width('100%').textAlign(TextAlign.Center)
            .margin({ top: 3 })
          Text('新疆农业大学教务处').fontSize(11)
            .fontColor($r('app.color.text_tertiary')).width('100%').textAlign(TextAlign.Center)
            .margin({ top: 3 })
        }
        .width('100%')
        .margin({ top: 8, bottom: 12 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 100 }) // 底部预留悬浮底栏高度，避免内容被遮挡
    }
    .width(720)
    .constraintSize({ maxWidth: '100%' })
    .height('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center) // 横屏/平板下 Scroll 水平居中
    }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    .bindSheet($$this.showWeb, this.webSheet, {
      width: SheetUtil.sheetWidth(),
      preferType: SheetType.BOTTOM,
      height: SheetSize.LARGE,
      dragBar: false,
      backgroundColor: $r('app.color.bg_page'),
      title: { title: AppState.webTitle }
    })
  }

  @Builder
  mineLandscape() {
    Row() {
      // 左列：个人信息 + 常用功能
      Scroll() {
        Column() {
          this.minePersonalSection()
        }
        .width('100%')
        .padding({ left: 16, right: 8, top: 12, bottom: 100 })
      }
      .layoutWeight(1)
      .height('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)

      // 右列：设置
      Scroll() {
        Column() {
          this.mineSettingsSection()
        }
        .width('100%')
        .padding({ left: 8, right: 16, top: 12, bottom: 100 })
      }
      .layoutWeight(1)
      .height('100%')
      .scrollBar(BarState.Off)
      .align(Alignment.Top)
      .edgeEffect(EdgeEffect.Spring)
    }
    .width('100%')
    .layoutWeight(1)
    .align(Alignment.Top)
  }

  @Builder
  minePersonalSection() {
    // 头像卡片（始终显示；圆形头像由 showAvatar 开关控制）
    Row() {
      this.avatarCard()
    }
    .margin({ bottom: 14 })

    this.academicCard()

    // 主题颜色 + 头像显示（上移到个人卡片区，学业情况下方）
    Column() {
      SettingRow({
        icon: '', title: '主题颜色', value: this.themeColor === 'red' ? '中国红' : (this.themeColor === 'blue' ? '天空蓝' : '农大绿'), onTap: () => {
          promptAction.showActionMenu({
            title: '顶栏主题色',
            buttons: [
              { text: '中国红', color: '#C3272B' },
              { text: '天空蓝', color: '#3B82F6' },
              { text: '农大绿', color: '#079841' }
            ]
          }).then((res) => {
            const themes: string[] = ['red', 'blue', 'green'];
            if (res.index >= 0 && res.index < themes.length) {
              Theme.apply(themes[res.index]);
            }
          });
        }
      })
      Divider().color($r('app.color.divider'))
      Row() {
        Text('头像显示')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.showAvatar })
          .selectedColor($r('app.color.brand'))
          .onChange((isOn: boolean) => {
            this.showAvatar = isOn;
            DataStore.put(DataStore.KEY_SHOW_AVATAR, isOn ? '1' : '0');
          })
      }
      .width('100%')
      .height(52)
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
    .margin({ top: 14 })

    // 常用功能：空闲教室查询 / 考试查询 / 学业情况
    Column() {
      SettingRow({
        icon: '', title: '空闲教室查询', onTap: () => {
          AppState.stack.pushPath({ name: Const.ROUTE_EMPTY_ROOM });
        }
      })
      Divider().color($r('app.color.divider'))
      SettingRow({
        icon: '', title: '考试查询', onTap: () => {
          AppState.stack.pushPath({ name: Const.ROUTE_EXAM });
        }
      })
      Divider().color($r('app.color.divider'))
      SettingRow({
        icon: '', title: '学业情况', onTap: () => {
          AppState.stack.pushPath({ name: Const.ROUTE_ACADEMIC });
        }
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
    .margin({ top: 14 })
  }

  @Builder
  mineSettingsSection() {
    Column() {
      // 1. 网页端教务系统（最顶上）
      SettingRow({
        icon: '', title: '网页端教务系统', value: '', onTap: () => {
          this.openWebPortal();
        }
      })
      Divider().color($r('app.color.divider'))
      // 1.1 学校官网（外部链接页打开）
      SettingRow({
        icon: '', title: '学校官网', value: '', onTap: () => {
          if (JwApi.USE_MOCK && !AppState.debugNetwork) {
            promptAction.showToast({ message: '当前模式禁止使用' });
            return;
          }
          AppState.webUrl = 'https://www.xjau.edu.cn/';
          AppState.webTitle = '学校官网';
          AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
        }
      })
      Divider().color($r('app.color.divider'))
      // 2. 数据同步
      SettingRow({
        icon: '', title: '数据同步', value: this.lastSyncText(), onTap: () => {
          this.syncNow();
        }
      })
      Divider().color($r('app.color.divider'))
      // 5. 清除缓存（低配版清除数据：保留登录信息/登录 Cookie/用户设置，只删数据缓存）
      SettingRow({
        icon: '', title: '清除缓存', value: this.cacheSizeText, onTap: () => {
          promptAction.showDialog({
            title: '清除缓存',
            message: '将删除课表、成绩、考试、通知、校历、头像等数据缓存，\n并释放网页内存与磁盘缓存，\n保留登录信息、登录 Cookie 与您的个性化设置。确认继续？',
            buttons: [
              { text: '取消', color: '#666666' },
              { text: '确认清除', color: '#DB5252', primary: true }
            ]
          }).then((res) => {
            if (res.index === 1) {
              DataStore.remove(DataStore.KEY_PROFILE);
              DataStore.remove(DataStore.KEY_COURSES);
              DataStore.remove(DataStore.KEY_TERM_SCORES);
              DataStore.remove(DataStore.KEY_EXAMS);
              DataStore.remove(DataStore.KEY_ACADEMIC);
              DataStore.remove(DataStore.KEY_NOTICES);
              DataStore.remove(DataStore.KEY_NOTICES_JWC);
              DataStore.remove(DataStore.KEY_TEACHING_CAL);
              DataStore.remove(DataStore.KEY_JWC_CAL);
              DataStore.remove(DataStore.KEY_PHOTO);
              DataStore.remove(DataStore.KEY_CACHE_TIME);
              try {
                webview.WebStorage.deleteAllData();
              } catch (e) {
                // ignore
              }
              this.trimWebMemory();
              this.clearAllCache();
              promptAction.showToast({ message: '已清除缓存（保留登录信息与设置）' });
              this.refreshCacheSize(500);
            }
          });
        }
      })
      Divider().color($r('app.color.divider'))
      // 6. 恢复备份（导出/导入：课表内容 + 课程表设置项 + 主题颜色，打包为 txt）
      SettingRow({
        icon: '', title: '恢复备份', value: '', onTap: () => {
          promptAction.showActionMenu({
            title: '恢复备份',
            buttons: [
              { text: '导出备份', color: '#1B7F5F' },
              { text: '导入备份', color: '#3B82F6' }
            ]
          }).then((res) => {
            if (res.index === 0) {
              this.exportBackup();
            } else if (res.index === 1) {
              this.importBackup();
            }
          });
        }
      })
      Divider().color($r('app.color.divider'))
      // 7. 清空数据（确认后提示手动重启）
      SettingRow({
        icon: '', title: '清空数据', value: '', onTap: () => {
          promptAction.showDialog({
            title: '清空数据',
            message: '将清除全部使用记录（历史账号、缓存、个人信息等），此操作不可恢复，确认继续？',
            buttons: [
              { text: '取消', color: '#666666' },
              { text: '确认清空', color: '#DB5252', primary: true }
            ]
          }).then((res) => {
            if (res.index === 1) {
              DataStore.clearAll();
              AppState.profile = null;
              promptAction.showDialog({
                title: '清空完成',
                message: '全部数据已清空，请手动重启应用以刷新界面',
                buttons: [{ text: '知道了', color: '#1B7F5F' }]
              });
            }
          });
        }
      })
      Divider().color($r('app.color.divider'))
      // 8. 隐私协议（打开独立页面）
      SettingRow({
        icon: '', title: '隐私协议', value: '', onTap: () => {
          AppState.stack.pushPath({ name: Const.ROUTE_PRIVACY });
        }
      })
      Divider().color($r('app.color.divider'))
      // 9. 关于（打开独立页面）
      SettingRow({
        icon: '', title: '关于', value: 'v1.2.4', onTap: () => {
          AppState.stack.pushPath({ name: Const.ROUTE_ABOUT });
        }
      })
      // 10. 日志详情（仅登录账号且开启日志调试时显示，分隔线一并条件渲染；
      //     收集中=亮绿灯，暂停=灰色灭灯）
      if (this.logEnabled && AppState.profile !== null) {
        Divider().color($r('app.color.divider'))
        SettingRow({
          icon: '',
          title: '日志详情',
          value: this.logCollecting ? '● 收集中' : '○ 已暂停',
          valueColor: this.logCollecting ? $r('app.color.brand') : $r('app.color.text_tertiary'),
          onTap: () => {
            AppState.stack.pushPath({ name: Const.ROUTE_LOG });
          }
        })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
    .margin({ top: 14 })
  }

  @Builder
  webSheet() {
    WebSurface()
  }
}
