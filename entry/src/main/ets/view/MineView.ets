/**
 * 我的：学业概览 + 常用功能 + 设置
 *
 * 卡片外观接入（照首页 HomeView 的写法推广）：
 *  - 卡片统一用 `MaterialCard` 承载，材质层在卡片内部、位于内容之下；材质生效时卡片自身的
 *    底色/磨砂/亮边/阴影一并让出，因此每张卡片只有一层视觉（就是沉浸光感材质本身），
 *    关闭光感则回落为原来的纯色/毛玻璃卡片；
 *  - 卡片之间的间距走 `cardMargin`（迁移前挂在卡片自身的 margin），卡片内边距走 `cardPadding`
 *    或内部内容容器的 padding（承载层才能铺满整张卡片）；
 *  - 设置行整卡（外观设置 / 常用功能 / 校园服务 / 设置）各作为一张材质卡，行与行之间的
 *    Divider 与 SettingRow 点击行为原样保留；
 *  - 半模态弹窗（恢复备份）内容套 `MaterialSheetPanel`，`bindSheet` 显式 `backgroundColor: Color.Transparent`。
 */
import { promptAction, mediaquery } from '@kit.ArkUI';
import { ResponsiveUtil } from '../common/ResponsiveUtil';
import { common, contextConstant, ConfigurationConstant, Want } from '@kit.AbilityKit';
import { storageStatistics, fileIo, picker, fileUri } from '@kit.CoreFileKit';
import { webview } from '@kit.ArkWeb';
import { JwApi } from '../api/JwApi';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { DataStore } from '../common/DataStore';
import { Theme } from '../common/ThemeUtil';
import { AppearanceStore } from '../common/AppearanceStore';
import { GlassMaterial } from '../common/GlassMaterial';
import { WallpaperTone } from '../common/WallpaperTone';
import { Immersive } from './common/Immersive';
import { AcademicReport, UserProfile } from '../model/Models';
import { EMPTY_REPORT } from '../model/Empty';
import { BarTitle, SettingRow } from './common/UiKit';
// 沉浸光感：卡片统一走 MaterialCard（材质承载层在卡片内容之下，材质生效时卡片底色/磨砂/亮边/阴影一并让出，
// 所以每张卡只有一层视觉），胶囊按钮走 MaterialButton，半模态弹窗内容走 MaterialSheetPanel
import { MaterialCard, MaterialSheetPanel } from './common/MaterialCard';
import { MaterialButton } from './common/MaterialButton';
import { sheetBlurStyle } from '../common/SystemMaterial';

@Component
export struct MineView {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('barStyle') barStyle: string = 'new';
  /** 响应式依赖：玻璃/灰字设置变化时触发本页重渲染（取值经 GlassMaterial 静态方法读取） */
  @StorageProp('glassStrength') glassStrength: number = 70;
  @StorageProp('cardMaterial') cardMaterial: boolean = false;
  @StorageProp('grayTextMode') grayTextMode: string = 'default';
  @StorageProp('grayTextColor') grayTextColor: string = '';
  /** 灰字广播依赖登记：根容器 opacity 恒真表达式登记依赖，广播时本页重算灰字色 */
  @StorageProp('grayTick') grayTick: number = 0;
  @StorageProp('immersiveEffect') immersiveEffect: boolean = false;
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 壁纸亮度（文字自适应用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  /** 全局字重响应式订阅：表达式读 this.fwMode 才登记依赖，fwValue 声明即订阅（custom 调值触发重渲染） */
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  /** 日志调试开关（AppStorage 响应式）：开启后显示「日志详情」入口 */
  @StorageProp('logEnabled') logEnabled: boolean = false;
  /** 日志收集状态（AppStorage 响应式）：收集中=亮绿灯，暂停=灰灯 */
  @StorageProp('logCollecting') logCollecting: boolean = true;
  @StorageLink('showAvatar') showAvatar: boolean = false;
  /** 全局壁纸 id（我的页入口显示当前状态） */
  @StorageProp('wallpaperId') wallpaperId: string = 'none';
  @State report: AcademicReport = EMPTY_REPORT;
  @State loaded: boolean = false;
  @State syncing: boolean = false;
  @State photo: string = '';
  @State cacheSizeText: string = '计算中…';
  @State isLandscape: boolean = false;
  /** 恢复备份：半模态面板 */
  @State showBackupSheet: boolean = false;
  private landscapeListener: mediaquery.MediaQueryListener | null = null;
  /** 窗口宽度断点监听（PC 窗口缩放时切换布局） */
  private wideListener: mediaquery.MediaQueryListener | null = null;
  /** 当前窗口是否横向 / 是否宽 ≥ 600vp（两者组合出布局判定） */
  private landscapeMq: boolean = false;
  private wideMq: boolean = false;
  onLogout: () => void = () => {
  };
  /** 前往登录页（不退出登录，从"我的"页退出弹窗第二项触发） */
  onGotoLogin: () => void = () => {
  };

  /** 当前主题显示名（三色枚举 / 自定义 hex 原样大写） */
  private themeNameText(): string {
    const t: string = this.themeColor;
    if (Theme.isHex(t)) {
      return t.toUpperCase();
    }
    if (t === 'red') {
      return '中国红';
    }
    if (t === 'blue') {
      return '天空蓝';
    }
    if (t === 'orange') {
      return '落日橙';
    }
    if (t === 'purple') {
      return '紫罗兰';
    }
    return '农大绿';
  }

  /** 壁纸摘要（跟随全局 wallpaperId 实时刷新） */
  private wallpaperValueText(): string {
    const id: string = this.wallpaperId;
    if (id === 'none' || id.length === 0) {
      return '未设置';
    }
    if (id.startsWith('c:')) {
      return '自定义';
    }
    return `内置 ${id.substring(1)}`;
  }

  /** 外观设置行右侧摘要：主题色 · 壁纸状态（未设置壁纸时只显示主题色） */
  private personaValueText(): string {
    const wp: string = this.wallpaperValueText();
    if (wp === '未设置') {
      return this.themeNameText();
    }
    return `${this.themeNameText()} · ${wp}`;
  }

  /** 切换应用颜色模式：使 $r() 资源（文字/背景）与深色状态一致，保证可读性 */
  private applyColorMode(dark: boolean): void {
    try {
      const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
      ctx.getApplicationContext()
        .setColorMode(dark ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } catch (e) {
      // ignore
    }
    // 深色模式变化 → 卡片沾色/页面背景派生色重算并广播（订阅端即时刷新）
    AppearanceStore.broadcastDerived();
  }

  /** 页面出现：加载学业概览并刷新缓存大小 */
  aboutToAppear(): void {
    this.load();
    this.refreshCacheSize();
    this.listenLandscape();
  }

  aboutToDisappear(): void {
    this.landscapeListener = null;
    this.wideListener = null;
  }

  /** 监听窗口尺寸/方向变化：窗口缩放或旋转时实时切换布局（判定规则见 ResponsiveUtil） */
  private listenLandscape(): void {
    const mq = this.getUIContext().getMediaQuery();
    this.landscapeMq = mq.matchMediaSync(ResponsiveUtil.QUERY_LANDSCAPE).matches;
    this.wideMq = mq.matchMediaSync(ResponsiveUtil.QUERY_WIDE).matches;
    this.applyLayout();
    this.landscapeListener = mq.matchMediaSync(ResponsiveUtil.QUERY_LANDSCAPE);
    this.landscapeListener.on('change', (res: mediaquery.MediaQueryResult) => {
      this.landscapeMq = res.matches;
      this.applyLayout();
    });
    this.wideListener = mq.matchMediaSync(ResponsiveUtil.QUERY_WIDE);
    this.wideListener.on('change', (res: mediaquery.MediaQueryResult) => {
      this.wideMq = res.matches;
      this.applyLayout();
    });
  }

  /** 组合出布局判定：宽 ≥ 600vp 且横向 → 大屏布局，否则手机端布局（见 ResponsiveUtil.isWideLayout） */
  private applyLayout(): void {
    this.isLandscape = ResponsiveUtil.isWideLayout(this.wideMq, this.landscapeMq);
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
      const curContext: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
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
        const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
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
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const d: Date = new Date();
      const stamp: string = `${d.getFullYear()}${(d.getMonth() + 1).toString().padStart(2, '0')}${d.getDate().toString().padStart(2, '0')}_${d.getHours().toString().padStart(2, '0')}${d.getMinutes().toString().padStart(2, '0')}`;
      const options: picker.DocumentSaveOptions = new picker.DocumentSaveOptions();
      options.newFileNames = [`xjau-helper_backup_${stamp}.txt`];
      options.fileSuffixChoices = ['.txt'];
      // 打包备份数据：应用全部信息（设置项 + 数据缓存 + 个人化内容；不含账号、密码与登录 Cookie）
      const payload: string = JSON.stringify(DataStore.exportAll());
      const d2: Date = new Date();
      const exportTs: string = `${d2.getFullYear()}-${(d2.getMonth() + 1).toString().padStart(2, '0')}-${d2.getDate().toString().padStart(2, '0')} ${d2.getHours().toString().padStart(2, '0')}:${d2.getMinutes().toString().padStart(2, '0')}`;
      const data: Record<string, string> = {
        'app': 'xjau-helper',
        'type': 'full-backup',
        'version': '2',
        'exportedAt': exportTs,
        'themeColor': Theme.current(),
        'payload': payload
      };
      const content: string = JSON.stringify(data);
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      docPicker.save(options).then((uris: string[]) => {
        if (uris.length === 0) {
          this.getUIContext().getPromptAction().showToast({ message: '已取消导出' });
          return;
        }
        try {
          const file: fileIo.File = fileIo.openSync(uris[0], fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
          fileIo.writeSync(file.fd, content);
          fileIo.closeSync(file);
          this.getUIContext().getPromptAction().showToast({ message: '备份已导出（不含账号与登录 Cookie）' });
        } catch (e) {
          this.getUIContext().getPromptAction().showToast({ message: '导出失败' });
        }
      }).catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: '导出失败' });
      });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '导出失败' });
    }
  }

  /** 导入备份：选择 txt → 解析 → 恢复课表内容/课程表设置项/主题颜色 */
  private importBackup(): void {
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['txt'];
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      docPicker.select(options).then((uris: string[]) => {
        if (uris.length === 0) {
          this.getUIContext().getPromptAction().showToast({ message: '已取消导入' });
          return;
        }
        try {
          const content: string = fileIo.readTextSync(new fileUri.FileUri(uris[0]).path);
          const obj: Record<string, string> = JSON.parse(content) as Record<string, string>;
          const btype: string = obj['type'] ?? '';
          // 校验备份格式（v2 全量备份 / v1 旧版课表备份）
          if (obj['app'] !== 'xjau-helper' || (btype !== 'full-backup' && btype !== 'schedule-backup')) {
            this.getUIContext().getPromptAction().showToast({ message: '不是有效的备份文件' });
            return;
          }
          if (btype === 'full-backup') {
            // 全量恢复：设置项 + 数据缓存 + 个人化内容（自动跳过账号、密码、Cookie）
            const payloadText: string = obj['payload'] ?? '{}';
            const payload: Record<string, string> = JSON.parse(payloadText) as Record<string, string>;
            const n: number = DataStore.importAll(payload);
            // 主题色（旧字段，兼容）
            const theme0: string = obj['themeColor'] ?? '';
            if (Theme.isBuiltin(theme0)) {
              Theme.apply(theme0);
            } else {
              Theme.restore();
            }
            // 关键项即时同步到 AppStorage（避免需重启才生效）
            AppStorage.setOrCreate('barStyle', DataStore.barStyle());
            AppStorage.setOrCreate('subtitleColor', DataStore.subtitleColor());
            AppStorage.setOrCreate('wallpaperMask', DataStore.wallpaperMaskOn());
            const wp: string = DataStore.loadWallpaper();
            AppStorage.setOrCreate('wallpaperId', wp.length > 0 ? wp : 'none');
            if (DataStore.hasDarkSetting()) {
              AppStorage.setOrCreate('isDarkMode', DataStore.isDarkOn());
            }
            // 备份里的深色设置可能变化 → 派生色（沾色/页面背景）重算并广播
            AppearanceStore.broadcastDerived();
            this.getUIContext().getPromptAction().showToast({ message: `已恢复 ${n} 项数据（不含账号与登录 Cookie）` });
          } else {
            // 旧版 v1：仅课表内容 + 课程表设置项 + 主题颜色
            DataStore.put(DataStore.KEY_COURSES, obj['courses'] ?? '');
            DataStore.setScheduleCfg(obj['scheduleCfg'] ?? '');
            DataStore.setScheduleBg(obj['scheduleBg'] ?? '');
            DataStore.put(DataStore.KEY_SCHEDULE_DASHED, obj['scheduleDashed'] ?? '');
            DataStore.put(DataStore.KEY_COURSE_COLOR_MAP, obj['courseColorMap'] ?? '');
            DataStore.setCourseCustomColors(obj['courseCustomColor'] ?? '');
            const theme: string = obj['themeColor'] ?? '';
            if (Theme.isBuiltin(theme)) {
              Theme.apply(theme);
            }
            this.getUIContext().getPromptAction().showToast({ message: '恢复成功（旧版备份），重新进入课程表查看' });
          }
        } catch (e) {
          this.getUIContext().getPromptAction().showToast({ message: '导入失败，文件格式不正确' });
        }
      }).catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: '导入失败' });
      });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '导入失败' });
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
    this.getUIContext().getPromptAction().showToast({ message: '正在同步教务数据…' });
    try {
      JwApi.USE_MOCK = false;
      await JwApi.refreshAll();
      this.report = JwApi.loadCachedAcademic();
      this.getUIContext().getPromptAction().showToast({ message: '数据已更新' });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '同步失败，请检查网络' });
    } finally {
      this.syncing = false;
    }
  }

  /** 加载我的页数据（成绩报告/头像等，先用缓存秒开再刷新） */
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

  /** 当前登录方式文案（退出登录弹窗提示用）：教务登录 / 服务大厅登录 / 功能浏览模式 / 登录超时（异常）
   *  判定以「实际登录方式」loginMethod 为准（pwd=教务直登 / cas=服务大厅 CAS / web=网页版），
   *  缺失时回退登录系统标记（KEY_LOGIN_SYSTEM），均无则视为会话异常。 */
  private loginMethodText(): string {
    // 功能浏览模式（mock 数据、无真实会话）：统一显示"功能浏览模式"
    if (JwApi.USE_MOCK) {
      return '功能浏览模式';
    }
    const method: string = DataStore.getLoginMethod();
    if (method === 'cas') {
      return '服务大厅登录';
    }
    if (method === 'pwd') {
      return '教务登录';
    }
    if (method === 'web') {
      // 网页版登录：按登录目标归类（教务系统 / 服务大厅）
      return DataStore.get(DataStore.KEY_LOGIN_SYSTEM) === 'original' ? '教务登录' : '服务大厅登录';
    }
    // 回退：登录方式未记录时按登录系统标记归类（冷启动自动重登等场景）
    const sys: string = DataStore.get(DataStore.KEY_LOGIN_SYSTEM);
    if (sys === 'original') {
      return '教务登录';
    }
    if (sys === 'service') {
      return '服务大厅登录';
    }
    // 无有效登录方式记录：会话异常或登录态已过期
    return '登录超时（异常）';
  }

  /** 弹出退出登录确认框：取消 / 前往登录页（不退出）/ 退出；并提示当前登录方式 */
  private confirmLogout(): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '退出登录',
      message: `当前登录方式：${this.loginMethodText()}\n\n退出后需要重新使用学号密码登录，确定退出吗？`,
      buttons: [
        { text: '取消', color: '#888888' },
        { text: '前往登录页', color: '#079841' },
        { text: '退出', color: '#F0524D' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        // 前往登录页：不退出登录，仅跳转登录界面（可返回）
        this.onGotoLogin();
      } else if (result.index === 2) {
        JwApi.logout();
        // 同步清除 WebView 登录痕迹（Cookie + 站点存储）：
        // 否则退出登录后网页版/服务大厅仍显示已登录，与应用"已退出"状态冲突
        try {
          webview.WebCookieManager.clearAllCookiesSync(false);
          webview.WebStorage.deleteAllData();
        } catch (e) {
          // ignore：清理失败不影响退出流程
        }
        AppState.clear();
        this.onLogout();
      }
    });
  }

  /** 长按退出按钮：功能浏览模式提示模式名称（调试模式提示调试模式），真实登录提示登录方式 / 日志调试 */
  private showLoginMethod(): void {
    if (JwApi.USE_MOCK) {
      this.getUIContext().getPromptAction().showToast({ message: AppState.debugNetwork ? '调试模式' : '功能浏览模式', duration: 2000 });
      return;
    }
    if (AppState.logEnabled) {
      this.getUIContext().getPromptAction().showToast({ message: 'log 调试', duration: 2000 });
      return;
    }
    const method: string = DataStore.getLoginMethod();
    const text: string = method === 'web' ? '当前为网页登录' : (method === 'pwd' ? '当前为密码登录' : '当前登录方式未知');
    this.getUIContext().getPromptAction().showToast({ message: text, duration: 2000 });
  }

  /** 打开网页端教务系统（在"外部链接"页面中访问，自动注入会话 Cookie 保持登录态） */
  private openWebPortal(): void {
    if (JwApi.USE_MOCK && !AppState.debugNetwork) {
      this.getUIContext().getPromptAction().showToast({ message: '当前模式禁止使用' });
      return;
    }
    AppState.webUrl = Const.WEB_PORTAL_URL;
    AppState.webTitle = '网页端教务系统';
    AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
  }

  @Builder
  titleBar() {
    // 顶部固定标题栏（三层）：最下内容 → 中全透明模糊层 → 顶主题色渐变
    Stack({ alignContent: Alignment.TopStart }) {
      // 顶：主题色渐变
      Column()
        .width('100%')
        .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
        .linearGradient({
          angle: 180,
          colors: Theme.barGradient(this.themeColor, this.barStyle)
        })
        .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, this.immersiveEffect && this.barStyle === 'legacy'))
    Row() {
      BarTitle({ title: '我的' })
      Blank()
    }
    .width('100%')
    .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
    .alignItems(VerticalAlign.Top)
    .padding({ left: 16, right: 16, top: this.getUIContext().px2vp(this.topInsetPx) + 12, bottom: 12 })
    }
    .width('100%')
    // 内容穿透：整个三层标题栏悬浮最上层、不占布局空间，内容可滚入其下层
    .position({ x: 0, y: 0 })
    .zIndex(2)
  }

  @Builder
  avatarCard() {
    // 头像卡片（MaterialCard 承载：材质层是卡片内部底层、与卡片同尺寸同圆角，材质生效时卡片底色让出，
    // 关闭光感则回落为原来的纯色/毛玻璃卡片）：
    // showAvatar 仅控制圆形头像的显示/隐藏，其余信息 + 右侧退出按钮始终显示
    MaterialCard({
      cardRadius: 16,
      cardPadding: 16,
      cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
      cardBlur: GlassMaterial.cardBlurSolid(),
      cardBorderW: GlassMaterial.cardBorderWidth(),
      cardBorderC: GlassMaterial.borderColor(),
      cardShadow: GlassMaterial.cardShadowStyle()
    }) {
    Row() {
      if (this.showAvatar) {
        if (this.photo.length > 0) {
          Image('data:image/jpeg;base64,' + this.photo)
            .width(52)
            .height(52)
            .borderRadius(26)
            .objectFit(ImageFit.Cover)
            // 圆形头像底：原 .systemMaterial(GlassMaterial.sysMaterial()) 是恒 undefined 的无效旧写法、
            // GlassMaterial.withMaterial() 恒返回传入色——两者均为死代码，已移除，观感不变
            // （头像在 MaterialCard 内部、非点击元素，不需要再叠 Toggle 承载层）。
            .backgroundColor($r('app.color.bg_chip')).backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? false) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
        } else if (JwApi.USE_MOCK) {
          // 功能浏览模式：使用默认占位头像（死代码清理同上，观感不变）
          Image($r('app.media.default_avatar'))
            .width(52)
            .height(52)
            .borderRadius(26)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.bg_chip')).backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? false) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
        } else {
          Text(AppState.avatarText())
            .fontSize(17)
            .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
            .fontColor(Theme.colorOf(this.themeColor))
            .width(52)
            .height(52)
            .borderRadius(26)
            .backgroundColor($r('app.color.bg_chip')).backgroundBlurStyle((AppStorage.get<boolean>('immersiveEffect') ?? false) ? BlurStyle.Thin : BlurStyle.NONE).border({ width: 1, color: 'rgba(255,255,255,0.28)' }).shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
            .textAlign(TextAlign.Center)
        }
      }

      Column() {
        Text(AppState.displayName())
          .fontSize(17)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontColor($r('app.color.text_primary'))
        Text(this.identityLine())
          .fontSize(12)
          .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
          .margin({ top: 4 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: this.showAvatar ? 12 : 0 })
      .layoutWeight(1)

      Blank()

      // 右侧：红色圆形退出登录按钮（用 退出.png 图标）
      // → MaterialButton（Toggle 承载层）：材质生效时 btnTint（半透明警示红）叠在材质之上保住红色语义，
      //   材质关闭回落 state_danger 实底；长按提示手势挂外壳 Row
      //   （MaterialButton 尾随闭包后不能链式属性，gesture 只能挂外层容器）。
      Row() {
        MaterialButton({
          btnRadius: 22,
          btnBg: $r('app.color.state_danger'),
          btnBlur: (this.immersiveEffect) ? BlurStyle.Thin : BlurStyle.NONE,
          btnBorderW: 1,
          btnBorderC: 'rgba(255,255,255,0.28)',
          btnTint: this.isDarkMode ? '#EE7B7B' : '#F0524D',
          btnTintRatio: 0.55,
          btnOnClick: (): void => {
            this.confirmLogout();
          }
        }) {
          Row() {
            Image($r('app.media.power'))
              .width(20)
              .height(20)
              .fillColor('#FFFFFF')
          }
          .width(44)
          .height(44)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        }
      }
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
    }
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
    // 学业概览卡（MaterialCard 承载；原卡片自身的 .onClick 改走 cardOnClick——尾随闭包之后不能再链式加属性）
    MaterialCard({
      cardRadius: 18,
      cardPadding: 16,
      cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
      cardBlur: GlassMaterial.cardBlurSolid(),
      cardBorderW: GlassMaterial.cardBorderWidth(),
      cardBorderC: GlassMaterial.borderColor(),
      cardShadow: GlassMaterial.cardShadowStyle(),
      cardOnClick: () => {
        AppState.stack.pushPath({ name: Const.ROUTE_ACADEMIC });
      }
    }) {
    Row() {
      Column() {
        Text(this.loaded ? `${this.report.totalEarned}` : '--')
          .fontSize(18)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontColor(Theme.colorOf(this.themeColor))
        Text('已修学分')
          .fontSize(11)
          .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
          .margin({ top: 3 })
      }
      .layoutWeight(1)

      Column() {
        Text(this.loaded ? this.report.gpa.toFixed(2) : '--')
          .fontSize(18)
          .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
          .fontColor($r('app.color.accent_blue'))
        Text('平均绩点')
          .fontSize(11)
          .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
          .margin({ top: 3 })
      }
      .layoutWeight(1)

      Text('›')
        .fontSize(18)
        .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
    }
    .width('100%')
    }
  }

  /** 恢复备份：半模态面板（说明 + 导出/导入） */
  @Builder
  backupSheet() {
    // 弹窗内容套 MaterialSheetPanel：bindSheet 自身的 systemMaterial 挂在面板上、内容区不生效，
    // 由 MaterialSheetPanel 的 Toggle 承载层渲染材质；配套要求是 bindSheet 显式 backgroundColor: Color.Transparent。
    // 本弹窗高度随内容（SheetSize.FIT_CONTENT），故 panelFillHeight: false（不写 height('100%')，避免被撑成整屏）。
    MaterialSheetPanel({ panelRadius: 24, panelPadding: 0, panelFillHeight: false, panelShowClose: true, panelOnClose: (): void => { this.showBackupSheet = false; } }) {
    Column() {
      Text('备份包含：课程表、成绩、考试、学业情况、消息与新闻缓存，以及课表设置、主题颜色、深色模式、壁纸、日历与收藏等全部应用信息。\n'
        + '出于安全考虑，备份文件不包含账号、密码与登录 Cookie。导入会覆盖当前对应数据，请确认后再恢复。')
        .fontSize(12)
        .lineHeight(19)
        .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
        .width('100%')
        .margin({ top: 10 })

      Row({ space: 12 }) {
        // 胶囊按钮：材质走 MaterialButton 的 Toggle 承载层（普通 Button 直接挂材质真机不渲染）。
        // 原 Button 的 layoutWeight 移到外层 Column（MaterialButton 的 Stack 内部不支持 layoutWeight），
        // 内容自己写 width('100%') 把点击区撑满。
        Column() {
          MaterialButton({
            btnRadius: 21,
            btnBg: Theme.colorOf(this.themeColor),
            btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
            btnBorderW: GlassMaterial.borderWidth(),
            btnBorderC: GlassMaterial.borderColor(),
            btnOnClick: () => {
              this.showBackupSheet = false;
              this.exportBackup();
            }
          }) {
            Text('导出备份')
              .fontSize(14)
              .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
              .fontColor(Color.White)
              .width('100%')
              .height(42)
              .textAlign(TextAlign.Center)
          }
        }
        .layoutWeight(1)
        // 胶囊按钮：与「导出备份」同款（材质走 MaterialButton 的 Toggle 承载层）
        Column() {
          MaterialButton({
            btnRadius: 21,
            btnBg: $r('app.color.bg_chip'),
            btnBlur: GlassMaterial.bgBlur(this.immersiveEffect),
            btnBorderW: GlassMaterial.borderWidth(),
            btnBorderC: GlassMaterial.borderColor(),
            btnOnClick: () => {
              this.showBackupSheet = false;
              this.importBackup();
            }
          }) {
            Text('导入备份')
              .fontSize(14)
              .fontWeight(this.fwMode === 'follow' ? FontWeight.Medium : AppearanceStore.fontWeight(FontWeight.Medium))
              .fontColor(Theme.colorOf(this.themeColor))
              .width('100%')
              .height(42)
              .textAlign(TextAlign.Center)
          }
        }
        .layoutWeight(1)
      }
      .width('100%')
      .margin({ top: 18 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 6, bottom: 26 })
    }
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
          // 顶栏占位（随内容滚走）：内容初始位于悬浮渐变标题栏下方，上滑后进入其下层
          Column()
            .width('100%')
            .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
          // 头像卡片（始终显示；圆形头像由 showAvatar 开关控制）
          Row() {
            this.avatarCard()
          }
          .margin({ bottom: 14 })

          this.academicCard()

          // 外观设置（主题色/全局壁纸）→ 深色模式 → 头像显示
          // MaterialCard 承载：材质层是卡片内部底层、与卡片同尺寸同圆角，材质生效时卡片底色/磨砂/亮边/阴影一并让出；
          // 卡片内边距（左右 16）改挂在内部内容容器上（承载层才能铺满整张卡片），原 14vp 上间距走 cardMargin。
          MaterialCard({
            cardRadius: 18,
            cardMargin: { top: 14 },
            cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
            cardBlur: GlassMaterial.cardBlurSolid(),
            cardBorderW: GlassMaterial.cardBorderWidth(),
            cardBorderC: GlassMaterial.borderColor(),
            cardShadow: GlassMaterial.cardShadowStyle()
          }) {
          Column() {
            SettingRow({
              icon: '', title: '外观设置', value: this.personaValueText(), onTap: () => {
                AppState.stack.pushPath({ name: Const.ROUTE_WALLPAPER });
              }
            })
            Divider().color($r('app.color.divider'))
            // 深色模式：开关切换，即时生效（默认浅色）
            Row() {
              Text('深色模式')
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.isDarkMode })
                .selectedColor(Theme.colorOf(this.themeColor))
                .onChange((isOn: boolean) => {
                  AppStorage.setOrCreate('isDarkMode', isOn);
                  DataStore.setDark(isOn);
                  this.applyColorMode(isOn);
                })
            }
            .width('100%')
            .height(52)
            Divider().color($r('app.color.divider'))

            Row() {
              Text('头像显示')
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.showAvatar })
                .selectedColor(Theme.colorOf(this.themeColor))
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
          }

          // 常用功能：空闲教室查询 / 考试查询 / 学业情况
          // MaterialCard 承载（设置行整卡作为一张材质卡；间距/内边距承载方式同上）
          MaterialCard({
            cardRadius: 18,
            cardMargin: { top: 14 },
            cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
            cardBlur: GlassMaterial.cardBlurSolid(),
            cardBorderW: GlassMaterial.cardBorderWidth(),
            cardBorderC: GlassMaterial.borderColor(),
            cardShadow: GlassMaterial.cardShadowStyle()
          }) {
          Column() {
            SettingRow({
              icon: '', title: '教室查询', onTap: () => {
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
            Divider().color($r('app.color.divider'))
            // 快捷选课（BETA）：移植自参考项目 zhengfang-apk 的正方选课/抢课模块
            SettingRow({
              icon: '', title: '快捷选课', value: 'BETA', onTap: () => {
                AppState.stack.pushPath({ name: Const.ROUTE_QUICK_SELECT });
              }
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          }

          // 校园服务（网页端教务系统 / 服务大厅 / 智慧学工 / 学校官网，独立卡片避免设置区臃肿）
          // MaterialCard 承载（设置行整卡作为一张材质卡；间距/内边距承载方式同上）
          MaterialCard({
            cardRadius: 18,
            cardMargin: { top: 14 },
            cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
            cardBlur: GlassMaterial.cardBlurSolid(),
            cardBorderW: GlassMaterial.cardBorderWidth(),
            cardBorderC: GlassMaterial.borderColor(),
            cardShadow: GlassMaterial.cardShadowStyle()
          }) {
          Column() {
            // 1. 网页端教务系统
            SettingRow({
              icon: '', title: '教务系统', value: '', onTap: () => {
                this.openWebPortal();
              }
            })
            Divider().color($r('app.color.divider'))
            // 2. 服务大厅（外部链接页打开，注入 SSO 会话保持登录态）
            SettingRow({
              icon: '', title: '服务大厅', value: '', onTap: () => {
                if (JwApi.USE_MOCK && !AppState.debugNetwork) {
                  this.getUIContext().getPromptAction().showToast({ message: '当前模式禁止使用' });
                  return;
                }
                AppState.webUrl = Const.CAS_LOGIN_URL;
                AppState.webTitle = '服务大厅';
                AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
              }
            })
            Divider().color($r('app.color.divider'))
            // 3. 智慧学工（外部链接页打开，注入 SSO 会话保持登录态）
            SettingRow({
              icon: '', title: '智慧学工', value: '', onTap: () => {
                if (JwApi.USE_MOCK && !AppState.debugNetwork) {
                  this.getUIContext().getPromptAction().showToast({ message: '当前模式禁止使用' });
                  return;
                }
                AppState.webUrl = Const.ZHIHUI_XUEGONG_URL;
                AppState.webTitle = '智慧学工';
                AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
              }
            })
            Divider().color($r('app.color.divider'))
            // 4. 学校官网（外部链接页打开）
            SettingRow({
              icon: '', title: '学校官网', value: '', onTap: () => {
                if (JwApi.USE_MOCK && !AppState.debugNetwork) {
                  this.getUIContext().getPromptAction().showToast({ message: '当前模式禁止使用' });
                  return;
                }
                AppState.webUrl = 'https://www.xjau.edu.cn/';
                AppState.webTitle = '学校官网';
                AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
              }
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          }

          // 设置（数据同步 → 清除缓存 → 恢复备份 → 清空数据 → 隐私协议 → 关于）
          // MaterialCard 承载（设置行整卡作为一张材质卡；间距/内边距承载方式同上）
          MaterialCard({
            cardRadius: 18,
            cardMargin: { top: 14 },
            cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
            cardBlur: GlassMaterial.cardBlurSolid(),
            cardBorderW: GlassMaterial.cardBorderWidth(),
            cardBorderC: GlassMaterial.borderColor(),
            cardShadow: GlassMaterial.cardShadowStyle()
          }) {
          Column() {
            // 1. 数据同步
            SettingRow({
              icon: '', title: '数据同步', value: this.lastSyncText(), onTap: () => {
                this.syncNow();
              }
            })
            Divider().color($r('app.color.divider'))
            // 5. 清除缓存（低配版清除数据：保留登录信息/登录 Cookie/用户设置，只删数据缓存）
            SettingRow({
              icon: '', title: '清除缓存', value: this.cacheSizeText, onTap: () => {
                this.getUIContext().getPromptAction().showDialog({
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
                    // 课表"每天只查询一次"标记：清除后下次进入课表会重新查询识别
                    DataStore.remove(DataStore.KEY_COURSES_FETCH);
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
                    this.getUIContext().getPromptAction().showToast({ message: '已清除缓存（保留登录信息与设置）' });
                    this.refreshCacheSize(500);
                  }
                });
              }
            })
            Divider().color($r('app.color.divider'))
            // 6. 恢复备份（导出/导入：课表内容 + 课程表设置项 + 主题颜色，打包为 txt）
            SettingRow({
              icon: '', title: '恢复备份', value: '', onTap: () => {
                this.showBackupSheet = true;
              }
            })
            Divider().color($r('app.color.divider'))
            // 7. 清空数据（确认后自动重启应用）
            SettingRow({
              icon: '', title: '清空数据', value: '', onTap: () => {
                this.getUIContext().getPromptAction().showDialog({
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
                    this.getUIContext().getPromptAction().showToast({ message: '数据已清空，正在重启…' });
                    const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
                    const want: Want = {
                      bundleName: 'com.xndhelper.lzb',
                      abilityName: 'EntryAbility'
                    };
                    ctx.restartApp(want);
                  }
                });
              }
            })
            Divider().color($r('app.color.divider'))
            // 8. 关于（打开独立页面）
            SettingRow({
              icon: '', title: '关于应用', value: 'v1.3.9', onTap: () => {
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
                valueColor: this.logCollecting ? Theme.colorOf(this.themeColor) : $r('app.color.text_tertiary'),
                onTap: () => {
                  AppState.stack.pushPath({ name: Const.ROUTE_LOG });
                }
              })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          }

        // 数据来源（Scroll 大 Column 内部）
        Column() {
          Text('数据来源: 新疆农业大学教务系统').fontSize(11)
            .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
          Text('新疆农业大学新闻网').fontSize(11)
            .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
            .margin({ top: 3 })
          Text('新疆农业大学教务处').fontSize(11)
            .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
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
    // 壁纸功能：页面根背景透明，让主框架底层的全局壁纸透出（无壁纸时由 MainView 底层 bg_page 兜底）
    .backgroundColor(Color.Transparent)
        .bindSheet($$this.showBackupSheet, this.backupSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      // 关闭按钮由 MaterialSheetPanel 自绘（沉浸光感），系统 showClose 必须关掉避免双按钮
      showClose: false,
      title: { title: '恢复备份' },
      // 必须显式透明：BindOptions.backgroundColor 默认 Color.White，而沉浸光感材质的视觉层级位于
      // backgroundColor **之下**，白底会把面板材质整块盖住（表现为「弹窗一点光感都没有」）。
      backgroundColor: Color.Transparent,
      blurStyle: sheetBlurStyle()
    })
    // 灰字广播依赖登记：grayTick 变化触发整页重算 graySecondary/grayTertiary 文本色（恒真不改变视觉）
    .opacity(this.grayTick >= 0 ? 1 : 1)
  }

  @Builder
  mineLandscape() {
    Row() {
      // 左列：个人信息 + 常用功能
      Scroll() {
        Column() {
          // 顶栏占位（随内容滚走）：内容从悬浮渐变标题栏下方开始
          Column()
            .width('100%')
            .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
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
          // 顶栏占位（随内容滚走）：内容从悬浮渐变标题栏下方开始
          Column()
            .width('100%')
            .height(this.getUIContext().px2vp(this.topInsetPx) + 60)
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

    // 外观设置（主题色/全局壁纸）→ 深色模式 → 头像显示
    // MaterialCard 承载（横屏列同样走材质卡；内边距挂内部内容容器、上间距走 cardMargin）
    MaterialCard({
      cardRadius: 18,
      cardMargin: { top: 14 },
      cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
      cardBlur: GlassMaterial.cardBlurSolid(),
      cardBorderW: GlassMaterial.cardBorderWidth(),
      cardBorderC: GlassMaterial.borderColor(),
      cardShadow: GlassMaterial.cardShadowStyle()
    }) {
    Column() {
      SettingRow({
        icon: '', title: '外观设置', value: this.personaValueText(), onTap: () => {
          AppState.stack.pushPath({ name: Const.ROUTE_WALLPAPER });
        }
      })
      Divider().color($r('app.color.divider'))
      // 深色模式：开关切换，即时生效（默认浅色）
      Row() {
        Text('深色模式')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.isDarkMode })
          .selectedColor(Theme.colorOf(this.themeColor))
          .onChange((isOn: boolean) => {
            AppStorage.setOrCreate('isDarkMode', isOn);
            DataStore.setDark(isOn);
            this.applyColorMode(isOn);
          })
      }
      .width('100%')
      .height(52)
      Divider().color($r('app.color.divider'))
      Row() {
        Text('头像显示')
          .fontSize(15)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.showAvatar })
          .selectedColor(Theme.colorOf(this.themeColor))
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
    }

    // 常用功能：空闲教室查询 / 考试查询 / 学业情况
    // MaterialCard 承载（横屏列同样走材质卡；内边距挂内部内容容器、上间距走 cardMargin）
    MaterialCard({
      cardRadius: 18,
      cardMargin: { top: 14 },
      cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
      cardBlur: GlassMaterial.cardBlurSolid(),
      cardBorderW: GlassMaterial.cardBorderWidth(),
      cardBorderC: GlassMaterial.borderColor(),
      cardShadow: GlassMaterial.cardShadowStyle()
    }) {
    Column() {
      SettingRow({
        icon: '', title: '教室查询', onTap: () => {
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
      Divider().color($r('app.color.divider'))
      // 快捷选课（BETA）：移植自参考项目 zhengfang-apk 的正方选课/抢课模块
      SettingRow({
        icon: '', title: '快捷选课', value: 'BETA', onTap: () => {
          AppState.stack.pushPath({ name: Const.ROUTE_QUICK_SELECT });
        }
      })
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    }
  }

  @Builder
  mineSettingsSection() {
    // MaterialCard 承载：横屏右侧列（校园服务 + 设置）整卡作为一张材质卡；
    // 内边距（左右 16）挂内部内容容器，原 14vp 上间距走 cardMargin。
    MaterialCard({
      cardRadius: 18,
      cardMargin: { top: 14 },
      cardBg: GlassMaterial.homeCardBg($r('app.color.bg_card')),
      cardBlur: GlassMaterial.cardBlurSolid(),
      cardBorderW: GlassMaterial.cardBorderWidth(),
      cardBorderC: GlassMaterial.borderColor(),
      cardShadow: GlassMaterial.cardShadowStyle()
    }) {
    Column() {
      // 1. 网页端教务系统（最顶上）
      SettingRow({
        icon: '', title: '教务系统', value: '', onTap: () => {
          this.openWebPortal();
        }
      })
      Divider().color($r('app.color.divider'))
      // 1.1 服务大厅（外部链接页打开，注入 SSO 会话保持登录态）
      SettingRow({
        icon: '', title: '服务大厅', value: '', onTap: () => {
          if (JwApi.USE_MOCK && !AppState.debugNetwork) {
            this.getUIContext().getPromptAction().showToast({ message: '当前模式禁止使用' });
            return;
          }
          AppState.webUrl = Const.CAS_LOGIN_URL;
          AppState.webTitle = '服务大厅';
          AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
        }
      })
      Divider().color($r('app.color.divider'))
      // 1.2 智慧学工（外部链接页打开，注入 SSO 会话保持登录态）
      SettingRow({
        icon: '', title: '智慧学工', value: '', onTap: () => {
          if (JwApi.USE_MOCK && !AppState.debugNetwork) {
            this.getUIContext().getPromptAction().showToast({ message: '当前模式禁止使用' });
            return;
          }
          AppState.webUrl = Const.ZHIHUI_XUEGONG_URL;
          AppState.webTitle = '智慧学工';
          AppState.stack.pushPath({ name: Const.ROUTE_WEB_PAGE });
        }
      })
      Divider().color($r('app.color.divider'))
      // 1.3 学校官网（外部链接页打开）
      SettingRow({
        icon: '', title: '学校官网', value: '', onTap: () => {
          if (JwApi.USE_MOCK && !AppState.debugNetwork) {
            this.getUIContext().getPromptAction().showToast({ message: '当前模式禁止使用' });
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
          this.getUIContext().getPromptAction().showDialog({
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
              // 课表"每天只查询一次"标记：清除后下次进入课表会重新查询识别
              DataStore.remove(DataStore.KEY_COURSES_FETCH);
              try {
                webview.WebStorage.deleteAllData();
              } catch (e) {
                // ignore
              }
              this.trimWebMemory();
              this.clearAllCache();
              this.getUIContext().getPromptAction().showToast({ message: '已清除缓存（保留登录信息与设置）' });
              this.refreshCacheSize(500);
            }
          });
        }
      })
      Divider().color($r('app.color.divider'))
      // 6. 恢复备份（导出/导入：课表内容 + 课程表设置项 + 主题颜色，打包为 txt）
      SettingRow({
        icon: '', title: '恢复备份', value: '', onTap: () => {
          this.showBackupSheet = true;
        }
      })
      Divider().color($r('app.color.divider'))
      // 7. 清空数据（确认后自动重启应用）
      SettingRow({
        icon: '', title: '清空数据', value: '', onTap: () => {
          this.getUIContext().getPromptAction().showDialog({
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
              this.getUIContext().getPromptAction().showToast({ message: '数据已清空，正在重启…' });
              const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
              const want: Want = {
                bundleName: 'com.xndhelper.lzb',
                abilityName: 'EntryAbility'
              };
              ctx.restartApp(want);
            }
          });
        }
      })
      Divider().color($r('app.color.divider'))
      // 8. 关于（打开独立页面）
      SettingRow({
        icon: '', title: '关于应用', value: 'v1.3.9', onTap: () => {
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
          valueColor: this.logCollecting ? Theme.colorOf(this.themeColor) : $r('app.color.text_tertiary'),
          onTap: () => {
            AppState.stack.pushPath({ name: Const.ROUTE_LOG });
          }
        })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
    }
  }
}
