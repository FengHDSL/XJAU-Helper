import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { mediaquery, window } from '@kit.ArkUI';
import { DataStore } from '../common/DataStore';
import { Theme } from '../common/ThemeUtil';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  /** Ability 创建：初始化数据存储、头像开关、深色模式监听 */
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 初始化本地持久化（历史账号 + 数据缓存）
    DataStore.init(this.context);
    // 头像显示开关（默认关闭，仅影响圆形头像）
    const showAvatar: boolean = DataStore.get(DataStore.KEY_SHOW_AVATAR) === '1';
    AppStorage.setOrCreate('showAvatar', showAvatar);
    // 恢复顶栏主题色（中国红/天空蓝/农大绿）
    Theme.restore();
    // 检测系统深色模式，写入 AppStorage（默认 false 即浅色模式）
    try {
      const listener = mediaquery.matchMediaSync('(prefers-color-scheme: dark)');
      AppStorage.setOrCreate('isDarkMode', listener.matches);
      listener.on('change', (result) => {
        AppStorage.setOrCreate('isDarkMode', result.matches);
      });
    } catch (e) {
      AppStorage.setOrCreate('isDarkMode', false);
    }
  }

  /** Ability 销毁回调 */
  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
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

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
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