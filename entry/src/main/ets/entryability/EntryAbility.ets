import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { display } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { AppState } from '../common/AppState';
import { AppearanceStore } from '../common/AppearanceStore';
import { DataStore } from '../common/DataStore';
import { GlassMaterial } from '../common/GlassMaterial';
import { WallpaperTone } from '../common/WallpaperTone';
import { Theme } from '../common/ThemeUtil';
import { NewsApi } from '../api/NewsApi';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  /**
   * 计算并广播"窗口化"状态到 AppStorage('winFloating')：
   * 非全屏 且 窗口矩形小于屏幕（PC 上拖动缩放的浮动窗口）→ true。
   * 全屏 / 最大化时窗口尺寸铺满屏幕，返回 false（底栏保持原有贴底样式）。
   */
  private static publishFloating(win: window.Window): void {
    try {
      const props: window.WindowProperties = win.getWindowProperties();
      const d = display.getDefaultDisplaySync();
      const smaller: boolean = props.windowRect.width < d.width || props.windowRect.height < d.height;
      AppStorage.setOrCreate('winFloating', !props.isFullScreen && smaller);
    } catch (err) {
      AppStorage.setOrCreate('winFloating', false);
    }
  }

  /** Ability 创建：初始化数据存储、头像开关、深色模式监听 */
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 初始化本地持久化（历史账号 + 数据缓存），并保存全局 Context
    DataStore.init(this.context);
    AppState.context = this.context;
    // 处理桌面卡片跳转意图（params.open = 'home' | 'exam-pick'）
    const open: string = (want.parameters?.['open'] as string) ?? '';
    if (open.length > 0) {
      AppState.openPageRequest = open;
    }
    // 头像显示开关（默认关闭，仅影响圆形头像）
    const showAvatar: boolean = DataStore.get(DataStore.KEY_SHOW_AVATAR) === '1';
    AppStorage.setOrCreate('showAvatar', showAvatar);
    // 全局壁纸 id（'b1'..'b6' 预置 / 'c:<path>' 自定义 / 'none'=未启用；默认不启用保持原观感）
    const wp: string = DataStore.loadWallpaper();
    AppStorage.setOrCreate('wallpaperId', wp.length > 0 ? wp : 'none');
    // 恢复顶栏主题色（中国红/天空蓝/农大绿/自定义 #RRGGBB）
    Theme.restore();
    // 恢复应用内字体缩放（外观设置页可调；1.0 = 标准）
    try {
      this.context.getApplicationContext().setFontSizeScale(DataStore.loadFontScale());
    } catch (e) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set fontSizeScale. Cause: %{public}s', JSON.stringify(e));
    }
    // 通透程度滑条（外观设置页可调：0~100 连续控制毛玻璃模糊强度与透明度）
    AppStorage.setOrCreate('glassStrength', DataStore.loadGlassStrength());
    // 灰色字体颜色覆盖（default/white/black/custom）
    AppStorage.setOrCreate('grayTextMode', DataStore.loadGrayMode());
    AppStorage.setOrCreate('grayTextColor', DataStore.loadGrayCustom());
    // 深色模式：默认为浅色（isDarkOn 返回 false 即表示浅色）
    AppStorage.setOrCreate('isDarkMode', DataStore.isDarkOn());
    // 顶栏样式：新版渐变（默认）/ 旧版实色
    AppStorage.setOrCreate('barStyle', DataStore.barStyle());
    // 顶栏副标题颜色（空=自动）
    AppStorage.setOrCreate('subtitleColor', DataStore.subtitleColor());
    // 全局沉浸光感（外观设置主开关，外观设置页可切换）：从持久化恢复，默认开启
    AppStorage.setOrCreate('immersiveEffect', DataStore.immersiveOn());
    // 壁纸蒙版开关（默认为开）
    AppStorage.setOrCreate('wallpaperMask', DataStore.wallpaperMaskOn());
    // 新闻封面缩略图开关（默认开启）
    AppStorage.setOrCreate('newsThumb', DataStore.newsThumbOn());
    // 壁纸明暗（对比度自动适配用，-1=未分析）
    AppStorage.setOrCreate('wallpaperTone', WallpaperTone.load());

    // ── 外观设置恢复（移植自参考项目：卡片沾色 / 主题色流光 / 卡片流光触感 /
    //    高权限自定义主题色 / 字体管理与自定义字体注册）──
    // 对应参考文件：miha_hm `pages/AppearanceSettingsPage.ets` + `utils/CustomFonts.ets`
    // 在 DataStore.init + AppState.context 之后调用，保证自定义字体可读沙箱目录并完成注册。
    AppearanceStore.init();
    // 灰体文本覆盖启动恢复：模式/自定义色先回 AppStorage（此前冷启动会丢失设置），
    // 再载入每页单独色 map、文字样式，并广播（含灰字调用的页面订阅 grayTick，见 GlassMaterial.broadcastGray）
    AppStorage.setOrCreate('grayTextMode', DataStore.loadGrayMode());
    AppStorage.setOrCreate('grayTextColor', DataStore.loadGrayCustom());
    GlassMaterial.loadTextStyle();
    GlassMaterial.loadTextGlowColor();
    AppearanceStore.loadPageBgTint();
    AppearanceStore.loadCardFallback();
    GlassMaterial.loadGrayPageMap();
    GlassMaterial.broadcastGray();
    // 「自动」灰字色：按壁纸亮度计算对比度更高的颜色（1.5s 防抖，壁纸刚变化时先静止再切换）
    GlassMaterial.scheduleAutoGray();
    try {
      this.context.getApplicationContext()
        .setColorMode(DataStore.isDarkOn() ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  /** 应用回到前台：重新应用当前颜色模式 */
  onForeground(): void {
    try {
      this.context.getApplicationContext()
        .setColorMode(DataStore.isDarkOn() ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } catch (e) {
      // ignore
    }
  }

  /** Ability 已存在时再次被拉起（桌面卡片点击） */
  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    const open: string = (want.parameters?.['open'] as string) ?? '';
    if (open.length > 0) {
      AppState.openPageRequest = open;
    }
  }

  /** Ability 销毁回调 */
  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
    // 清理农大新闻图片缓存
    NewsApi.clearCache();
    // 删除空闲教室导出 Excel 临时文件（含解压目录）
    try {
      const cacheDir: string = this.context.cacheDir;
      const files: string[] = [
        `${cacheDir}/kxcdlb_export.xlsx`,
        `${cacheDir}/kxcdlb_xlsx`
      ];
      for (let i = 0; i < files.length; i++) {
        try {
          if (fileIo.accessSync(files[i])) {
            if (fileIo.statSync(files[i]).isDirectory()) {
              fileIo.rmdirSync(files[i]);
            } else {
              fileIo.unlinkSync(files[i]);
            }
          }
        } catch (e) {
          // 单文件清理失败可忽略
        }
      }
    } catch (e) {
      // ignore
    }
  }

  /** 窗口创建：加载主页面并设置沉浸式状态栏 */
  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    // 沉浸式：内容延伸到状态栏，并把状态栏/导航条高度存入 AppStorage 供页面避让
    try {
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      mainWindow.setWindowLayoutFullScreen(true);
      const topArea: window.AvoidArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      AppStorage.setOrCreate('topInsetPx', topArea.topRect.height);
      const bottomArea: window.AvoidArea =
        mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
      AppStorage.setOrCreate('bottomInsetPx', bottomArea.bottomRect.height);
      mainWindow.on('avoidAreaChange', (data) => {
        if (data.type === window.AvoidAreaType.TYPE_SYSTEM) {
          AppStorage.setOrCreate('topInsetPx', data.area.topRect.height);
        } else if (data.type === window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR) {
          AppStorage.setOrCreate('bottomInsetPx', data.area.bottomRect.height);
        }
      });
      // 是否"窗口化"（PC 上拖动缩放的浮动窗口，非全屏/最大化）：
      // 浮动窗口底部没有系统安全区，悬浮底栏固定贴底会显得过低 → 需要额外留白
      EntryAbility.publishFloating(mainWindow);
      mainWindow.on('windowStatusChange', () => {
        EntryAbility.publishFloating(mainWindow);
      });
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set full screen. Cause: %{public}s', JSON.stringify(err));
    }

    windowStage.loadContent('pages/Splash', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    try {
      // 应用当前深色模式设置
      this.context.getApplicationContext()
        .setColorMode(DataStore.isDarkOn() ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  /** 窗口销毁回调 */
  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  /** 应用进入后台回调 */
  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}