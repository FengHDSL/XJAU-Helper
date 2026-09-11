import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { mediaquery, window } from '@kit.ArkUI';
import { fileIo } from '@kit.CoreFileKit';
import { AppState } from '../common/AppState';
import { DataStore } from '../common/DataStore';
import { WallpaperTone } from '../common/WallpaperTone';
import { Theme } from '../common/ThemeUtil';
import { NewsApi } from '../api/NewsApi';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
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
    // 深色模式：手动开关优先；未手动设置时跟随系统（mediaquery 实时监听）
    try {
      const darkListener = mediaquery.matchMediaSync('(prefers-color-scheme: dark)');
      const manual: boolean = DataStore.hasDarkSetting();
      const initial: boolean = manual ? DataStore.isDarkOn() : darkListener.matches;
      AppStorage.setOrCreate('isDarkMode', initial);
    // 顶栏样式：新版渐变（默认）/ 旧版实色
    AppStorage.setOrCreate('barStyle', DataStore.barStyle());
    // 顶栏副标题颜色（空=自动）
    AppStorage.setOrCreate('subtitleColor', DataStore.subtitleColor());
    // 沉浸光感开关（个性主题可切换）
    AppStorage.setOrCreate('immersiveEffect', true); // 沉浸光感默认开启（已移除开关）
    // 壁纸蒙版开关（默认为开）
    AppStorage.setOrCreate('wallpaperMask', DataStore.wallpaperMaskOn());
    // 壁纸明暗（对比度自动适配用，-1=未分析）
    AppStorage.setOrCreate('wallpaperTone', WallpaperTone.load());
      // 让 $r() 资源色与之一致（文字/背景资源随 colorMode 切换）
      AppStorage.setOrCreate('darkManual', manual);
      AppStorage.setOrCreate('systemDark', darkListener.matches);
      this.applyColorMode(initial);
      darkListener.on('change', (result: mediaquery.MediaQueryResult) => {
        AppStorage.setOrCreate('systemDark', result.matches);
        // 仅未手动设置时随系统变化
        if (!AppStorage.get<boolean>('darkManual')) {
          AppStorage.setOrCreate('isDarkMode', result.matches);
          this.applyColorMode(result.matches);
        }
      });
    } catch (e) {
      AppStorage.setOrCreate('isDarkMode', false);
    }
  }

  /** 应用颜色模式（使 $r 资源切换到对应深浅色） */
  private applyColorMode(dark: boolean): void {
    try {
      this.context.getApplicationContext()
        .setColorMode(dark ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
          : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
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
      // 手动设置过深色 → 应用该模式；否则跟随系统
      const manual: boolean = DataStore.hasDarkSetting();
      this.context.getApplicationContext()
        .setColorMode(manual
          ? (DataStore.isDarkOn() ? ConfigurationConstant.ColorMode.COLOR_MODE_DARK
            : ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT)
          : ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
  }

  /** 窗口销毁回调 */
  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  /** 应用进入前台回调 */
  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  /** 应用进入后台回调 */
  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}