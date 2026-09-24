/**
 * 外观设置页（二级页）：顶栏主题色 + 全局壁纸 + 沉浸光感 + 字体（移植自参考项目 miha_hm 外观设置）
 *  - 顶栏主题色：中国红/天空蓝/农大绿/自定义 #RRGGBB（输入 hex 即用）
 *  - 全局壁纸：自定义图片（选择 → 裁剪页裁切后应用）/ 图像地址导入 / 蒙版开关
 *  - 沉浸光感：全局开关（API≥26）+ 卡片沾色 / 主题色流光 / 卡片流光触感 / 高权限自定义主题色
 *  - 字体：字体管理入口（上传/选择/删除）+ 字重模式 + 字号大小（跟随系统 / 自定义）
 *  - 交互：主页页面平滑切换开关
 */
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { promptAction } from '@kit.ArkUI';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { DataStore, ThemeCombo } from '../common/DataStore';
import { DateUtil } from '../common/DateUtil';
import { WallpaperTone } from '../common/WallpaperTone';
import { Immersive } from './common/Immersive';
import { Theme } from '../common/ThemeUtil';
import { Wallpaper } from '../common/Wallpaper';
import { AppearanceStore } from '../common/AppearanceStore';
import { PageHeader } from './common/UiKit';
import { WallpaperFill } from './common/WallpaperFill';
import { GlassMaterial } from '../common/GlassMaterial';
import { isApi26OrAbove, materialAvailable, materialDiagnostics } from '../common/SystemMaterial';
import { MaterialCardLayer } from './common/MaterialCarrier';
import { MaterialButton } from './common/MaterialButton';

@Component
export struct WallpaperPage {
  /** 全局壁纸 id（'b1'..'b6' 预置 / 'c:<path>' 自定义 / 'none'=未启用） */
  @StorageProp('wallpaperId') wallpaperId: string = 'none';
  /** 壁纸蒙版开关 */
  @StorageProp('wallpaperMask') wallpaperMask: boolean = true;
  /** URL 导入输入框内容 */
  @State urlText: string = '';
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  /** 顶栏主题色（'green' | 'red' | 'blue' | 'orange' | 'purple' | '#RRGGBB'） */
  @StorageProp('themeColor') themeColor: string = 'green';
  /** 顶栏样式：new=渐变色（默认）/ legacy=毛玻璃 */
  @StorageProp('barStyle') barStyle: string = 'new';
  @StorageProp('immersiveEffect') immersiveEffect: boolean = true;
  /** 跟随系统深色（只读展示用） */
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 壁纸亮度（文字自适应用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  /** 自定义主题色输入（rrggbb，可不带 #） */
  @StorageProp('subtitleColor') subtitleColor: string = '';
  /** 已保存的主题组合（背景+顶栏颜色+副标题颜色） */
  @State combos: ThemeCombo[] = [];
  @State comboName: string = '';
  /** 副标题自定义颜色输入 */
  @State subHex: string = '';
  @State hexInput: string = '';
  @State hexOk: boolean = false;
  /** 卡片沾色：卡片底色混入 10% 主题色（沉浸光感增强） */
  @StorageProp('cardTint') cardTint: boolean = false;
  /** 主题色流光：按压沉浸光感卡片的流光/光晕改用主题色 */
  @StorageProp('immersivePressGlow') pressGlow: boolean = true;
  /** 卡片流光触感：按压卡片出现跟手流光 */
  @StorageProp('cardGlowTouch') cardGlowTouch: boolean = true;
  /** 高权限自定义主题色：自定义 hex 也参与页面背景染色 */
  @StorageProp('customAccentFull') customAccentFull: boolean = false;
  /** 字重方案（follow/thin/light/regular/medium/bold） */
  @StorageProp('fontWeightMode') fontWeightMode: string = 'follow';
  /** 字号方案（follow=跟随系统 / custom=自定义） */
  @StorageProp('fontSizeMode') fontSizeMode: string = 'follow';
  /** 自定义字号值（12~28，基准 16） */
  @StorageProp('fontSizeValue') fontSizeValue: number = 16;
  /** 主页页面平滑切换（页签切换滑动过渡） */
  @StorageProp('smoothPageSwitch') smoothPage: boolean = true;

  aboutToAppear(): void {
    this.combos = DataStore.combos();
    // 打开外观设置即恢复字号缩放（自定义字号持久化后应用级生效）
    AppearanceStore.applyFontSizeScale();
  }

  /** 全局沉浸光感开关（AppStorage 实时 + DataStore 持久化，重启后保持） */
  private setImmersive(on: boolean): void {
    AppStorage.setOrCreate('immersiveEffect', on);
    DataStore.setImmersive(on);
  }

  /**
   * 本页卡片底色（接入「卡片沾色」开关，让设置在本页立即可见）：
   * 材质让出（materialAvailable）时——沾色开=保留沾色底（材质半透明可透出）/ 关=透明让材质渲染；
   * 材质不可用时——沾色开=沾色底 / 关=原卡片色兜底。
   */
  private cardBg(orig: ResourceColor): ResourceColor {
    // 必须读 this.cardTint（@StorageProp 订阅）而不是 AppearanceStore.cardTintOn()：
    // ArkUI 按属性表达式登记依赖，静态函数内读 AppStorage 不登记，拨开关本页不会重算。
    const tintOn: boolean = this.cardTint;
    if (materialAvailable()) {
      return tintOn ? AppearanceStore.cardBackground(this.isDarkMode, this.themeColor) : Color.Transparent;
    }
    return tintOn ? AppearanceStore.cardBackground(this.isDarkMode, this.themeColor) : orig;
  }

  /** 跳转壁纸裁剪页（选图 → 缩放/平移 → 按屏幕比例裁切应用） */
  private openCropPage(): void {
    AppState.stack.pushPath({ name: Const.ROUTE_BG_CROP });
  }

  /** 跳转字体管理页（上传 / 选择中英文字体 / 删除已上传字体） */
  private openFontManage(): void {
    AppState.stack.pushPath({ name: Const.ROUTE_FONT_MANAGE });
  }

  /** 当前主题显示名（三色枚举 / 自定义 hex 大写） */
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

  /** 应用主题（三色枚举 / hex） */
  private applyTheme(t: string): void {
    if (this.themeColor === t) {
      return;
    }
    Theme.apply(t);
    this.getUIContext().getPromptAction().showToast({ message: t.startsWith('#') ? `已应用自定义主题 ${t.toUpperCase()}` : `已切换为${Theme.label()}` });
  }

  /** 应用输入的 rrggbb 自定义主题 */
  private applyHexTheme(): void {
    let raw: string = this.hexInput.trim();
    if (raw.startsWith('#')) {
      raw = raw.substring(1);
    }
    const hex: string = `#${raw.toLowerCase()}`;
    if (!Theme.isHex(hex)) {
      this.getUIContext().getPromptAction().showToast({ message: '格式有误：请输入 6 位 rrggbb，例如 3b82f6' });
      return;
    }
    this.applyTheme(hex);
    this.hexInput = '';
    this.hexOk = false;
  }

  /** 校验输入是否可能为合法 hex（辅助按钮可用态） */
  private validateHex(v: string): void {
    this.hexInput = v;
    let raw: string = v.trim();
    if (raw.startsWith('#')) {
      raw = raw.substring(1);
    }
    this.hexOk = Theme.isHex(`#${raw}`);
  }

  /** 当前壁纸摘要（设置行/提示用） */
  private wallpaperDesc(): string {
    const id: string = this.wallpaperId;
    if (id === 'none' || id.length === 0) {
      return '未设置（默认纯色背景）';
    }
    if (id.startsWith('c:')) {
      return '使用自定义壁纸';
    }
    return `使用内置壁纸 ${id.substring(1)}`;
  }

  /** 应用壁纸（全局响应式 + 持久化） */
  private applyWallpaper(id: string): void {
    if (this.wallpaperId === id) {
      return;
    }
    AppStorage.setOrCreate('wallpaperId', id);
    DataStore.saveWallpaper(id);
    this.getUIContext().getPromptAction().showToast({ message: '壁纸已应用' });
  }

  /** 取消壁纸：无背景（'none'），并删除自定义壁纸文件 */
  private cancelWallpaper(): void {
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const p: string = `${ctx.filesDir}/wallpaper_user.dat`;
      if (fileIo.accessSync(p)) {
        fileIo.unlinkSync(p);
      }
    } catch (e) {
      // 文件不存在等忽略
    }
    this.applyWallpaper('none');
    this.getUIContext().getPromptAction().showToast({ message: '已取消壁纸背景' });
  }

  /** URL 图片导入壁纸（下载到 filesDir，持久化，无需相册权限） */
  private importByUrl(): void {
    const url: string = this.urlText.trim();
    if (url.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入图片 URL' });
      return;
    }
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      this.getUIContext().getPromptAction().showToast({ message: 'URL 需以 http(s):// 开头' });
      return;
    }
    const req: http.HttpRequest = http.createHttp();
    req.request(url, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      readTimeout: 20000
    }).then((resp: http.HttpResponse) => {
      if (resp.responseCode !== 200) {
        this.getUIContext().getPromptAction().showToast({ message: `下载失败(${resp.responseCode})` });
        req.destroy();
        return;
      }
      const arr: ArrayBuffer = resp.result as ArrayBuffer;
      try {
        const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
        const dstPath: string = `${ctx.filesDir}/wallpaper_user.dat`;
        const file: fileIo.File = fileIo.openSync(dstPath,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.READ_WRITE);
        fileIo.writeSync(file.fd, arr);
        fileIo.closeSync(file);
        // 自动分析壁纸明暗 → 适配文字对比度
        WallpaperTone.analyze(arr).then((tone: number) => {
          WallpaperTone.save(tone);
        });
        this.applyWallpaper(`c:${dstPath}`);
        // 记录图像地址与更新日期：之后每天首次启动自动下载新壁纸
        DataStore.saveWallpaperUrl(url);
        DataStore.setWallpaperUrlDate(DateUtil.format(new Date()));
        this.getUIContext().getPromptAction().showToast({ message: '壁纸已应用，之后每天自动更新' });
      } catch (e) {
        this.getUIContext().getPromptAction().showToast({ message: '保存壁纸失败' });
      }
      req.destroy();
    }).catch(() => {
      this.getUIContext().getPromptAction().showToast({ message: '下载失败，请检查 URL/网络' });
      req.destroy();
    });
  }

  /** 设置顶栏副标题文字颜色（空=自动） */
  private applySubtitle(color: string): void {
    AppStorage.setOrCreate('subtitleColor', color);
    DataStore.setSubtitleColor(color);
  }

  /** 自定义副标题颜色（#RRGGBB；留空=自动） */
  private applySubtitleHex(): void {
    const v: string = this.subHex.trim();
    if (v.length === 0) {
      this.applySubtitle('');
      return;
    }
    const hex: string = v.startsWith('#') ? v : `#${v}`;
    if (!Theme.isHex(hex)) {
      this.getUIContext().getPromptAction().showToast({ message: '颜色码格式应为 #RRGGBB' });
      return;
    }
    this.applySubtitle(hex);
  }

  /** 保存当前组合（背景 + 顶栏颜色 + 副标题颜色） */
  private saveCombo(): void {
    const name: string = this.comboName.trim();
    if (name.length === 0) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入组合名称' });
      return;
    }
    const c: ThemeCombo = {
      name: name,
      wallpaper: this.wallpaperId,
      theme: this.themeColor,
      subtitle: this.subtitleColor
    };
    DataStore.saveCombo(c);
    this.combos = DataStore.combos();
    this.comboName = '';
    this.getUIContext().getPromptAction().showToast({ message: `已保存组合「${name}」` });
  }

  /** 应用组合（一次性设置背景/顶栏颜色/副标题颜色） */
  private applyCombo(c: ThemeCombo): void {
    AppStorage.setOrCreate('wallpaperId', c.wallpaper);
    DataStore.saveWallpaper(c.wallpaper);
    Theme.apply(c.theme);
    AppStorage.setOrCreate('subtitleColor', c.subtitle);
    DataStore.setSubtitleColor(c.subtitle);
    this.getUIContext().getPromptAction().showToast({ message: `已应用「${c.name}」` });
  }

  /** 删除组合 */
  private deleteCombo(name: string): void {
    DataStore.removeCombo(name);
    this.combos = DataStore.combos();
  }

  /** 副标题颜色胶囊 */
  @Builder
  subtitleChip(label: string, color: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.subtitleColor === color ? Color.White : $r('app.color.text_primary'))
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .backgroundColor(this.subtitleColor === color ? Theme.colorOf(this.themeColor) : $r('app.color.bg_chip'))
      .borderRadius(12)
      .onClick(() => {
        this.applySubtitle(color);
      })
  }

  /** 单张主题色预置块 */
  @Builder
  themeSwatch(key: string, color: string, name: string) {
    Column() {
      Stack({ alignContent: Alignment.Center }) {
        Row()
          .width(32)
          .height(32)
          .backgroundColor(color)
          .borderRadius(16)
          .border({
            width: this.themeColor === key ? 2.5 : 0,
            color: this.themeColor === key ? Theme.colorOf(this.themeColor) : Color.Transparent
          })
        // 选中主题色：居中打勾（统一勾图标）
        if (this.themeColor === key) {
          Image($r('app.media.checkmark_sel'))
            .width(18)
            .height(18)
            .fillColor(Color.White)
        }
      }
      .width(32)
      .height(32)
      Text(name)
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 6 })
    }
    .onClick(() => {
      this.applyTheme(key);
    })
  }

  /** 顶栏主题色节：三色预设 + 自定义 rrggbb */
  @Builder
  themeSection() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (materialAvailable()) {
        MaterialCardLayer({ layerRadius: 16, layerShadow: false, layerForce: true })
      }
    Column() {
      Row() {
        Text('顶栏主题色')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(`当前：${this.themeNameText()}`)
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
      }
      .width('100%')
      .margin({ bottom: 12 })

      // 顶栏样式：新版（默认渐变）/ 旧版 1.3.1 实色
      Row() {
        Text('顶栏样式')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('毛玻璃')
          .fontSize(12)
          .fontColor(this.barStyle === 'legacy' ? Color.White : $r('app.color.text_primary'))
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .backgroundColor(this.barStyle === 'legacy' ? Theme.colorOf(this.themeColor) : $r('app.color.bg_chip'))
          .borderRadius(12)
          .onClick(() => {
            AppStorage.setOrCreate('barStyle', 'legacy');
            DataStore.setBarStyle('legacy');
          })
        Text('渐变色')
          .fontSize(12)
          .fontColor(this.barStyle === 'new' ? Color.White : $r('app.color.text_primary'))
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .backgroundColor(this.barStyle === 'new' ? Theme.colorOf(this.themeColor) : $r('app.color.bg_chip'))
          .borderRadius(12)
          .margin({ left: 8 })
          .onClick(() => {
            AppStorage.setOrCreate('barStyle', 'new');
            DataStore.setBarStyle('new');
          })
      }
      .width('100%')
      .margin({ bottom: 12 })


      // 顶栏副标题文字颜色（自动=跟随顶栏样式）
      Row() {
        Text('副标题颜色')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Row({ space: 8 }) {
          this.subtitleChip('自动', '')
          this.subtitleChip('黑色', '#1B1B1B')
          this.subtitleChip('灰色', '#8A9199')
          this.subtitleChip('白色', '#FFFFFF')
        }
      }
      .width('100%')
      .margin({ bottom: 12 })

      // 副标题自定义颜色（#RRGGBB）
      Row() {
        Text('自定义副标题色')
          .fontSize(12)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ right: 10 })
        TextInput({ text: this.subHex, placeholder: '#RRGGBB' })
          .height(48)
          .enterKeyType(EnterKeyType.Done)
          .borderRadius($r('sys.float.corner_radius_level12'))
          .fontSize($r('sys.float.Body_L'))
          .fontWeight(FontWeight.Regular)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .caretStyle({ color: $r('sys.color.font_emphasize') })
          .type(InputType.Normal)
          .fontColor('rgba(0, 85, 255, 1.0)')
          .placeholderFont({ size: $r('sys.float.Body_L'), weight: FontWeight.Regular })
          .layoutWeight(1)
          .onChange((v: string) => {
            this.subHex = v;
          })
        Button('应用')
          .fontSize(13)
          .height(36)
          .borderRadius(18)
          .fontColor(Color.White)
          .backgroundColor(Theme.colorOf(this.themeColor))
          .margin({ left: 10 })
          .onClick(() => {
            this.applySubtitleHex();
          })
      }
      .width('100%')
      .margin({ bottom: 12 })

      // 5 个预置色一排、整体居中（紧凑间距，保证窄屏也能放下）
      Row({ space: 12 }) {
        this.themeSwatch('red', '#C3272B', '中国红')
        this.themeSwatch('blue', '#3B82F6', '天空蓝')
        this.themeSwatch('green', '#079841', '农大绿')
        this.themeSwatch('orange', '#E0603A', '落日橙')
        this.themeSwatch('purple', '#7C5CE0', '紫罗兰')
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 12 })

      // 自定义 rrggbb 输入
      Row() {
        Text('自定义')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ right: 10 })
        TextInput({ text: $$this.hexInput, placeholder: '#RRGGBB' })
          .height(48)
          .enterKeyType(EnterKeyType.Done)
          .borderRadius($r('sys.float.corner_radius_level12'))
          .fontSize($r('sys.float.Body_L'))
          .fontWeight(FontWeight.Regular)
          .backgroundColor($r('sys.color.comp_background_tertiary'))
          .caretStyle({ color: $r('sys.color.font_emphasize') })
          .type(InputType.Normal)
          .fontColor('rgba(0, 85, 255, 1.0)')
          .placeholderFont({ size: $r('sys.float.Body_L'), weight: FontWeight.Regular })
          .layoutWeight(1)
          .onChange((v: string) => {
            this.validateHex(v);
          })
        Button(this.hexOk ? '应用' : '应用')
          .fontSize(13)
          .fontColor($r('app.color.brand_on'))
          .backgroundColor(Theme.colorOf(this.themeColor))
          .height(38)
          .borderRadius(19)
          .margin({ left: 10 })
          .enabled(this.hexOk)
          .onClick(() => {
            this.applyHexTheme();
          })
      }
      .width('100%')
      .padding(16)
      }
    }
    .width('100%')
    .borderRadius(16)
    .clip(true)
    .backgroundColor(this.cardBg($r('app.color.bg_card')))
    .backgroundBlurStyle(materialAvailable() ? BlurStyle.NONE : GlassMaterial.bgBlur(this.immersiveEffect), GlassMaterial.blurOptions())
    .border({ width: materialAvailable() ? 0 : (this.immersiveEffect ? GlassMaterial.borderWidth() : 0), color: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent })
    .margin({ top: 14 })
  }

  /** 沉浸光感节：全局开关 + 真机诊断行（API≥26 才显示；开关写入后全站卡片/按钮跟随切换） */
  @Builder
  immersiveSection() {
    if (isApi26OrAbove()) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (materialAvailable()) {
          MaterialCardLayer({ layerRadius: 16, layerShadow: false, layerForce: true })
        }
        Column() {
          Row() {
            Column({ space: 3 }) {
              Text('全局沉浸光感')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
              Text('开启后卡片与按钮使用沉浸光感材质，关闭后回退为毛玻璃效果')
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.immersiveEffect })
              .selectedColor(Theme.colorOf(this.themeColor))
              .onChange((on: boolean) => {
                this.setImmersive(on);
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          if (this.immersiveEffect) {
            Text(materialDiagnostics(this.pressGlow, Theme.colorOf(this.themeColor)))
              .fontSize(10)
              .fontColor($r('app.color.text_tertiary'))
              .width('100%')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 10 })
          }
        }
        .padding(16)
      }
      .width('100%')
      .borderRadius(16)
      .clip(true)
      .backgroundColor(this.cardBg($r('app.color.bg_card')))
      .backgroundBlurStyle(materialAvailable() ? BlurStyle.NONE : GlassMaterial.bgBlur(this.immersiveEffect), GlassMaterial.blurOptions())
      .border({ width: materialAvailable() ? 0 : (this.immersiveEffect ? GlassMaterial.borderWidth() : 0), color: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent })
      .margin({ top: 14 })
    }
  }

  /** 沉浸光感增强节：卡片沾色 / 主题色流光 / 卡片流光触感 / 高权限自定义主题色（参考项目同款 4 开关） */
  @Builder
  glowExtraSection() {
    if (isApi26OrAbove()) {
      Stack({ alignContent: Alignment.TopStart }) {
        if (materialAvailable()) {
          MaterialCardLayer({ layerRadius: 16, layerShadow: false, layerForce: true })
        }
        Column() {
          Row() {
            Column({ space: 3 }) {
              Text('卡片沾色')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('开启后所有卡片底色混入 10% 主题色')
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.cardTint })
              .selectedColor(Theme.colorOf(this.themeColor))
              .onChange((on: boolean) => {
                AppearanceStore.setCardTint(on);
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Divider()
            .color($r('app.color.divider'))
            .margin({ top: 12, bottom: 12 })

          Row() {
            Column({ space: 3 }) {
              Text('主题色流光')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('按压卡片的流光与光晕改用主题色；关闭后为系统默认白光')
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.pressGlow })
              .selectedColor(Theme.colorOf(this.themeColor))
              .onChange((on: boolean) => {
                AppearanceStore.setPressGlow(on);
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Divider()
            .color($r('app.color.divider'))
            .margin({ top: 12, bottom: 12 })

          Row() {
            Column({ space: 3 }) {
              Text('卡片流光触感')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('开启后按压卡片出现跟手流光；关闭只有卡间缝隙的环境光')
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.cardGlowTouch })
              .selectedColor(Theme.colorOf(this.themeColor))
              .onChange((on: boolean) => {
                AppearanceStore.setCardGlowTouch(on);
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)

          Divider()
            .color($r('app.color.divider'))
            .margin({ top: 12, bottom: 12 })

          Row() {
            Column({ space: 3 }) {
              Text('高权限自定义主题色')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
              Text('默认只有内置主题色会染到页面背景；开启后自定义颜色也会')
                .fontSize(11)
                .fontColor($r('app.color.text_tertiary'))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Toggle({ type: ToggleType.Switch, isOn: this.customAccentFull })
              .selectedColor(Theme.colorOf(this.themeColor))
              .onChange((on: boolean) => {
                AppearanceStore.setCustomAccentFull(on);
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .padding(16)
      }
      .width('100%')
      .borderRadius(16)
      .clip(true)
      .backgroundColor(this.cardBg($r('app.color.bg_card')))
      .backgroundBlurStyle(materialAvailable() ? BlurStyle.NONE : GlassMaterial.bgBlur(this.immersiveEffect), GlassMaterial.blurOptions())
      .border({ width: materialAvailable() ? 0 : (this.immersiveEffect ? GlassMaterial.borderWidth() : 0), color: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent })
      .margin({ top: 14 })
    }
  }

  /** 字重模式胶囊（选中=主题色底白字） */
  @Builder
  fontWeightChip(mode: string, label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.fontWeightMode === mode ? Color.White : $r('app.color.text_primary'))
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .backgroundColor(this.fontWeightMode === mode ? Theme.colorOf(this.themeColor) : $r('app.color.bg_chip'))
      .borderRadius(12)
      .onClick(() => {
        AppearanceStore.setFontWeightMode(mode);
      })
  }

  /** 字号模式胶囊（切换后立即应用全局字号缩放） */
  @Builder
  fontSizeChip(mode: string, label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.fontSizeMode === mode ? Color.White : $r('app.color.text_primary'))
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .backgroundColor(this.fontSizeMode === mode ? Theme.colorOf(this.themeColor) : $r('app.color.bg_chip'))
      .borderRadius(12)
      .onClick(() => {
        AppearanceStore.setFontSizeMode(mode);
        AppearanceStore.applyFontSizeScale();
      })
  }

  /** 字体节：字体管理入口 + 字重模式 + 字号大小（跟随系统 / 自定义 Slider） */
  @Builder
  fontSection() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (materialAvailable()) {
        MaterialCardLayer({ layerRadius: 16, layerShadow: false, layerForce: true })
      }
      Column() {
        // 字体管理入口（上传 / 选择中英文字体 / 删除）
        Row() {
          Column({ space: 3 }) {
            Text('字体管理')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text('上传字体 / 选择中英文字体 / 删除已上传字体')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text('前往 ›')
            .fontSize(13)
            .fontColor(Theme.colorOf(this.themeColor))
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.openFontManage();
        })

        Divider()
          .color($r('app.color.divider'))
          .margin({ top: 12, bottom: 12 })

        // 字重模式（跟随 / 细 / 轻 / 常规 / 中等 / 粗）
        Text('字体粗细')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
        Row({ space: 8 }) {
          this.fontWeightChip('follow', '跟随')
          this.fontWeightChip('thin', '细')
          this.fontWeightChip('light', '轻')
          this.fontWeightChip('regular', '常规')
          this.fontWeightChip('medium', '中等')
          this.fontWeightChip('bold', '粗')
        }
        .width('100%')
        .margin({ top: 8 })

        Divider()
          .color($r('app.color.divider'))
          .margin({ top: 12, bottom: 12 })

        // 字号模式
        Row() {
          Text('字体大小')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Blank()
          Row({ space: 8 }) {
            this.fontSizeChip('follow', '跟随系统')
            this.fontSizeChip('custom', '自定义')
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // 自定义字号滑杆（12~28，基准 16，应用级缩放即时生效）
        if (this.fontSizeMode === 'custom') {
          Row() {
            Text('字号')
              .fontSize(12)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ right: 10 })
            Slider({
              value: this.fontSizeValue,
              min: 12,
              max: 28,
              step: 1,
              style: SliderStyle.OutSet
            })
              .layoutWeight(1)
              .showSteps(true)
              .onChange((value: number) => {
                AppearanceStore.setFontSizeValue(value);
                AppearanceStore.applyFontSizeScale();
              })
            Text(`${this.fontSizeValue}`)
              .fontSize(13)
              .fontColor(Theme.colorOf(this.themeColor))
              .width(30)
              .textAlign(TextAlign.End)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: 10 })
        }
      }
      .padding(16)
    }
    .width('100%')
    .borderRadius(16)
    .clip(true)
    .backgroundColor(this.cardBg($r('app.color.bg_card')))
    .backgroundBlurStyle(materialAvailable() ? BlurStyle.NONE : GlassMaterial.bgBlur(this.immersiveEffect), GlassMaterial.blurOptions())
    .border({ width: materialAvailable() ? 0 : (this.immersiveEffect ? GlassMaterial.borderWidth() : 0), color: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent })
    .margin({ top: 14 })
  }

  /** 交互细节节：主页页面平滑切换 */
  @Builder
  toggleSection() {
    Stack({ alignContent: Alignment.TopStart }) {
      if (materialAvailable()) {
        MaterialCardLayer({ layerRadius: 16, layerShadow: false, layerForce: true })
      }
      Column() {
        Row() {
          Column({ space: 3 }) {
            Text('页面平滑切换')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
            Text('底部页签切换时页面平滑滑动过渡，关闭后立即切换')
              .fontSize(11)
              .fontColor($r('app.color.text_tertiary'))
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Toggle({ type: ToggleType.Switch, isOn: this.smoothPage })
            .selectedColor(Theme.colorOf(this.themeColor))
            .onChange((on: boolean) => {
              AppearanceStore.setSmoothPageSwitch(on);
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
      .padding(16)
    }
    .width('100%')
    .borderRadius(16)
    .clip(true)
    .backgroundColor(this.cardBg($r('app.color.bg_card')))
    .backgroundBlurStyle(materialAvailable() ? BlurStyle.NONE : GlassMaterial.bgBlur(this.immersiveEffect), GlassMaterial.blurOptions())
    .border({ width: materialAvailable() ? 0 : (this.immersiveEffect ? GlassMaterial.borderWidth() : 0), color: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent })
    .margin({ top: 14 })
  }


  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // 二级页壁纸底层（本页自身也能看到当前壁纸背景）
        WallpaperFill()
        Column() {
        Scroll() {
          Column() {
            // 悬浮顶栏让位（正文默认从顶栏下方开始，上滑可滚入其渐变下层透出）
            Column().width('100%').height(this.getUIContext().px2vp(this.topInsetPx) + 60)
            // 顶栏主题色（三色预设 + 自定义 rrggbb）
            this.themeSection()

            // 沉浸光感（全局开关 + 真机诊断）
            this.immersiveSection()

            // 沉浸光感增强（卡片沾色 / 主题色流光 / 卡片流光触感 / 高权限自定义主题色）
            this.glowExtraSection()


            // ── 壁纸（卡片）：选择 / 取消 / 蒙版 / 图像地址 ──
            Column() {
              Text('全局壁纸')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .margin({ bottom: 10 })
            // 自定义壁纸（已启用时预览）
            if (this.wallpaperId.startsWith('c:')) {
              Text('自定义壁纸')
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .margin({ top: 8, bottom: 10 })

              Image(`file://${this.wallpaperId.substring(2)}`)
                .width('100%')
                .height(160)
                .objectFit(ImageFit.Cover)
                .borderRadius(12)
                .backgroundColor($r('app.color.bg_chip'))

              Text('已使用自定义壁纸')
                .fontSize(12)
                .fontColor(Theme.colorOf(this.themeColor))
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ top: 8 })
            }
            // 操作区：选择图片 → 裁剪页（缩放/平移 → 按屏幕比例裁切应用）
            Row() {
              Button('选择图片并裁剪')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.brand_on'))
                .backgroundColor(Theme.colorOf(this.themeColor))
                .height(42)
                .layoutWeight(1)
                .borderRadius(21)
                .onClick(() => {
                  this.openCropPage();
                })
            }
            .width('100%')
            .margin({ top: 18 })
            // 取消壁纸：恢复默认纯色背景（粉红按钮）
            Button('取消壁纸')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .backgroundColor('#F2A0B5')
              .height(42)
              .width('100%')
              .borderRadius(21)
              .margin({ top: 12 })
              .onClick(() => {
                this.cancelWallpaper();
              })
            // 壁纸蒙版开关：关闭后不叠加可读性遮罩（文字仍会自动适配颜色）
            Row() {
              Column() {
                Text('壁纸蒙版')
                  .fontSize(13)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
                Text('在壁纸上叠加可读性遮罩，保证文字清晰')
                  .fontSize(11)
                  .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
                  .margin({ top: 2 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.wallpaperMask })
                .selectedColor(Theme.colorOf(this.themeColor))
                .onChange((on: boolean) => {
                  AppStorage.setOrCreate('wallpaperMask', on);
                  DataStore.setWallpaperMask(on);
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            .margin({ top: 12 })
            // URL 导入壁纸：直接填图片链接，下载到应用目录并应用
            Row() {
              TextInput({ text: this.urlText, placeholder: '编辑图像地址（支持API地址）' })
                .height(48)
                .enterKeyType(EnterKeyType.Done)
                .borderRadius($r('sys.float.corner_radius_level12'))
                .fontSize($r('sys.float.Body_L'))
                .fontWeight(FontWeight.Regular)
                .backgroundColor($r('sys.color.comp_background_tertiary'))
                .caretStyle({ color: $r('sys.color.font_emphasize') })
                .type(InputType.Normal)
                .fontColor('rgba(0, 85, 255, 1.0)')
                .placeholderFont({ size: $r('sys.float.Body_L'), weight: FontWeight.Regular })
                .layoutWeight(1)
                .onChange((v: string) => {
                  this.urlText = v;
                })
                .onSubmit(() => {
                  this.importByUrl();
                })
              Button('保存')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.brand_on'))
                .backgroundColor(Theme.colorOf(this.themeColor))
                .height(42)
                .width(96)
                .borderRadius(21)
                .margin({ left: 12 })
                .onClick(() => {
                  this.importByUrl();
                })
            }
            .width('100%')
            .margin({ top: 12 })
            .alignItems(VerticalAlign.Center)
            // URL 行上移到提示文本上方；提示放其下
            Text('提示：壁纸应用在主界面五个 Tab 与多数二级页背景，切换后即时生效；课程表页保持纯色底不受影响；各功能卡片保持原有底色以保证可读性。取消壁纸即恢复默认纯色背景。')
              .fontSize(11)
              .lineHeight(18)
              .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
              .width('100%')
              .margin({ top: 12 })
            }
            .width('100%')
            .padding(16)
            .backgroundColor(this.cardBg($r('app.color.bg_card')))
            .borderRadius(16)
            .margin({ top: 14 })

            // ── 字体（字体管理入口 + 字重 + 字号）──
            this.fontSection()

            // ── 交互细节（页面平滑切换）──
            this.toggleSection()

            // ── 主题组合（卡片）──
            Column() {
            // ── 主题组合：保存/应用（背景 + 顶栏颜色 + 副标题颜色）──
            Text('主题组合')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
              .margin({ top: 4, bottom: 10 })
            Row() {
              TextInput({ text: this.comboName, placeholder: '组合名称（如：夜间阅读）' })
                .height(48)
                .enterKeyType(EnterKeyType.Done)
                .borderRadius($r('sys.float.corner_radius_level12'))
                .fontSize($r('sys.float.Body_L'))
                .fontWeight(FontWeight.Regular)
                .backgroundColor($r('sys.color.comp_background_tertiary'))
                .caretStyle({ color: $r('sys.color.font_emphasize') })
                .type(InputType.Normal)
                .fontColor('rgba(0, 85, 255, 1.0)')
                .placeholderFont({ size: $r('sys.float.Body_L'), weight: FontWeight.Regular })
                .layoutWeight(1)
                .onChange((v: string) => {
                  this.comboName = v;
                })
              Button('保存当前组合')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
                .backgroundColor(Theme.colorOf(this.themeColor))
                .height(40)
                .borderRadius(20)
                .margin({ left: 10 })
                .onClick(() => {
                  this.saveCombo();
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
            ForEach(this.combos, (c: ThemeCombo) => {
              Row() {
                // 壁纸缩略图（自定义壁纸走 file://；未设置时显示占位块）
                if (c.wallpaper.startsWith('c:')) {
                  Image(`file://${c.wallpaper.substring(2)}`)
                    .width(40)
                    .height(40)
                    .borderRadius(10)
                    .objectFit(ImageFit.Cover)
                    .backgroundColor($r('app.color.bg_chip'))
                    .margin({ right: 12 })
                } else if (c.wallpaper !== 'none' && c.wallpaper.length > 0) {
                  // 旧内置壁纸 id（已移除资源）：仅显示占位块
                  Column()
                    .width(40)
                    .height(40)
                    .borderRadius(10)
                    .backgroundColor($r('app.color.bg_chip'))
                    .margin({ right: 12 })
                } else {
                  Column()
                    .width(40)
                    .height(40)
                    .borderRadius(10)
                    .backgroundColor($r('app.color.bg_chip'))
                    .margin({ right: 12 })
                }
                Column() {
                  Text(c.name)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                  // 颜色预览点：顶栏色 + 副标题色（空=自动，显示描边空点）
                  Row({ space: 6 }) {
                    Row()
                      .width(12)
                      .height(12)
                      .borderRadius(6)
                      .backgroundColor(Theme.colorOf(c.theme))
                    Row()
                      .width(12)
                      .height(12)
                      .borderRadius(6)
                      .backgroundColor(c.subtitle.length > 0 ? c.subtitle : Color.Transparent)
                      .border({ width: 1, color: $r('app.color.divider') })
                  }
                  .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)
                Text('应用')
                  .fontSize(12)
                  .fontColor(Color.White)
                  .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                  .backgroundColor(Theme.colorOf(this.themeColor))
                  .borderRadius(12)
                  .onClick(() => {
                    this.applyCombo(c);
                  })
                Text('删除')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                  .backgroundColor($r('app.color.bg_chip'))
                  .borderRadius(12)
                  .margin({ left: 8 })
                  .onClick(() => {
                    this.deleteCombo(c.name);
                  })
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .margin({ top: 10 })
              .backgroundColor($r('app.color.bg_chip'))
              .borderRadius(14)
            }, (c: ThemeCombo) => c.name)
            }
            .width('100%')
            .padding(16)
            .backgroundColor(this.cardBg($r('app.color.bg_card')))
            .borderRadius(16)
            .margin({ top: 14 })

          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 14, bottom: 24 })
        }
        .width(720)
        .constraintSize({ maxWidth: '100%' })
        .height('100%')
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Center)

        // 顶栏悬浮（最上层）：正文顶部已让位，上滑可滚入其渐变下层透出
        PageHeader({
          title: '外观设置',
          subtitle: '主题色 · 壁纸 · 光感 · 字体',
          onBack: () => {
            AppState.stack.pop();
          }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_page'))
  }
}
