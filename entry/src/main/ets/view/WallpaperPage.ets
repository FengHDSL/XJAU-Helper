/**
 * 外观设置页（二级页）：顶栏主题色 + 全局壁纸 + 外观设置
 *  - 顶栏主题色：中国红/天空蓝/农大绿/自定义 #RRGGBB（输入 hex 即用）
 *  - 全局壁纸：6 张内置缩略网格（点击即应用，全局即时生效）
 *  - 相册/文档选择导入自定义图片（存应用 filesDir，持久化）
 *  - 取消壁纸：恢复默认纯色背景（同时删除自定义壁纸文件）
 *
 * 外观设置区（本次移植，对应参考文件 miha_hm `pages/AppearanceSettingsPage.ets`）按四组分列：
 *   主题：顶栏主题色 / 顶栏样式 / 副标题颜色 / **高权限自定义主题色**
 *   卡片：全局沉浸光感 + 诊断行 / 通透程度 / **卡片沾色** / **主题色流光** /
 *        **卡片流光触感** / 灰色字体颜色
 *   字体：**字体管理入口**（粗细 · 中英文字体 · 上传与管理）
 *   —— 说明：字号（字体大小）调节与「字体管理」页功能重复，已统一收敛到 `FontManagePage`，
 *      本页不再提供调节入口（只保留进入「字体管理」页的入口与摘要）
 *   背景：背景壁纸（**更换背景（裁剪）** / 从相册直接应用 / 清空背景 / 蒙版 / 图像地址）
 *   —— 以及原有的主题组合（保存 / 应用 / 删除）
 *
 * 卡片外观接入（照首页 HomeView 的写法推广）：
 *  - 五张卡片（顶栏主题色 / 外观设置 / 字体 / 背景壁纸 / 主题组合）统一用 `MaterialCard` 承载
 *    （材质层在卡片内部、位于内容之下）；材质生效时卡片自身底色/磨砂/亮边/阴影一并让出，
 *    关闭光感回落为原来的纯色/毛玻璃卡片。原卡片的 16vp 内边距走 `cardPadding`、
 *    14vp 上间距走 `cardMargin`，值不变；
 *  - 页面内的胶囊按钮（进入 / 应用 / 更换背景 / 从相册直接应用 / 清空背景 / 保存 / 保存当前组合 /
 *    组合的应用·删除）改走 `MaterialButton`；带选中态的档位胶囊（主题色块 / 副标题色 / 灰字色 /
 *    顶栏样式）保留实色文字胶囊（材质会让出底色、会把选中态吃掉），它们所在的小卡已是材质卡；
 *  - Toggle / Slider / TextInput 等控件与所有点击、跳转、值变更逻辑均未改动。
 */
import { common } from '@kit.AbilityKit';
import { fileIo, picker, fileUri } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { promptAction } from '@kit.ArkUI';
import { AppState } from '../common/AppState';
import { AppearanceStore } from '../common/AppearanceStore';
import { Const } from '../common/Constants';
import { DataStore, ThemeCombo } from '../common/DataStore';
import { DateUtil } from '../common/DateUtil';
import { WallpaperTone } from '../common/WallpaperTone';
import { Immersive } from './common/Immersive';
import { Theme } from '../common/ThemeUtil';
import { Wallpaper } from '../common/Wallpaper';
import { GlassMaterial } from '../common/GlassMaterial';
import { materialAvailable, materialDiagnostics } from '../common/SystemMaterial';
import { MaterialCardLayer } from './common/MaterialCarrier';
import { PageHeader } from './common/UiKit';
import { WallpaperFill } from './common/WallpaperFill';
// 沉浸光感：卡片统一走 MaterialCard（材质承载层在卡片内容之下，材质生效时卡片底色/磨砂/亮边/阴影一并让出，
// 每张卡只剩一层视觉），页面内的胶囊按钮走 MaterialButton（Toggle 承载层 + 内容）。
// 注：带「选中态」的档位胶囊（主题色块 / 副标题色 / 灰字色 / 顶栏样式）仍用实色文字胶囊——
// 选中态靠实底色表达，而材质会让出底色、把选中态吃掉（与字体管理页的档位胶囊同一处理），
// 它们所在的小卡已迁到 MaterialCard 承载材质。
import { MaterialCard } from './common/MaterialCard';
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
  /**
   * 全局沉浸光感（外观设置核心开关，唯一事实源）：
   * 用 @StorageLink 双向绑定 → 开关即时写入 AppStorage，首页等已接入页面立即重渲染（真实时，无需重启）。
   */
  @StorageLink('immersiveEffect') immersiveEffect: boolean = true;
  /** 主页页面平滑切换（移植自参考项目；开启后页签切换带页面滑动过渡，实时生效） */
  @StorageLink('smoothPageSwitch') smoothPageSwitch: boolean = true;
  /** 跟随系统深色（只读展示用） */
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 壁纸亮度（文字自适应用） */
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  /** 自定义主题色输入（rrggbb，可不带 #） */
  @StorageProp('subtitleColor') subtitleColor: string = '';
  /** 灰字模式（default/white/black/custom）与自定义色 */
  @StorageProp('grayTextMode') grayTextMode: string = 'default';
  @StorageProp('grayTextColor') grayTextColor: string = '';
  /** 通透程度（0~100 滑条：连续控制毛玻璃模糊强度与透明度，实时生效） */
  @StorageProp('glassStrength') glassStrength: number = 70;
  /** 已保存的主题组合（背景+顶栏颜色+副标题颜色） */
  @State combos: ThemeCombo[] = [];
  @State comboName: string = '';
  /** 副标题自定义颜色输入 */
  @State subHex: string = '';
  @State hexInput: string = '';
  @State hexOk: boolean = false;

  // ── 移植自参考项目的卡片外观开关（@StorageLink：开关即时生效，无需重启）──
  /** 卡片沾色：卡片底色混入 10% 主题色 */
  @StorageLink('cardTint') cardTint: boolean = false;
  /** 主题色流光：按压沉浸光感卡片的流光/光晕改用主题色 */
  @StorageLink('immersivePressGlow') pressGlow: boolean = true;
  /** 卡片流光触感：开启后按压卡片才出现流光 */
  @StorageLink('cardGlowTouch') glowTouch: boolean = true;
  /** 高权限自定义主题色：自定义 hex 也染页面背景 */
  @StorageLink('customAccentFull') customAccentFull: boolean = false;
  /** 字重方案（字体组摘要显示用） */
  @StorageProp('fontWeightMode') weightMode: string = 'follow';
  /** 中/英数字体族（字体组摘要显示用） */
  @StorageProp('fontFamilyZh') fontFamilyZh: string = '';
  @StorageProp('fontFamilyEn') fontFamilyEn: string = '';

  aboutToAppear(): void {
    this.combos = DataStore.combos();
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

  /** 清空背景：无背景（'none'），并删除所有历史自定义壁纸文件与裁剪临时文件 */
  private cancelWallpaper(): void {
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      // 删除全部自定义壁纸文件（含早期固定命名的 wallpaper_user.dat）
      Wallpaper.cleanupUserWallpapers(ctx.filesDir, '');
    } catch (e) {
      // 文件不存在等忽略
    }
    this.applyWallpaper('none');
    this.getUIContext().getPromptAction().showToast({ message: '已清空背景' });
  }

  /** 导入自定义壁纸（文档选择器，免相册权限；jpg/jpeg/png/webp） */
  private pickCustomWallpaper(): void {
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['jpg', 'jpeg', 'png', 'webp'];
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      docPicker.select(options).then((uris: string[]) => {
        if (uris.length === 0) {
          return;
        }
        try {
          const srcPath: string = new fileUri.FileUri(uris[0]).path;
          // openSync + readSync 读取图片字节（fileIo 无 readFileSync）
          const srcFile: fileIo.File = fileIo.openSync(srcPath, fileIo.OpenMode.READ_ONLY);
          const st: fileIo.Stat = fileIo.statSync(srcPath);
          const buf: ArrayBuffer = new ArrayBuffer(st.size);
          fileIo.readSync(srcFile.fd, buf);
          fileIo.closeSync(srcFile);
          // 唯一命名：避免覆盖同一路径导致 Image 命中缓存而不刷新（修复"已选壁纸再选无法应用"）
          const dstPath: string = Wallpaper.newUserWallpaperPath(ctx.filesDir);
          const file: fileIo.File = fileIo.openSync(dstPath,
            fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.READ_WRITE);
          fileIo.writeSync(file.fd, buf);
          fileIo.closeSync(file);
          // 自动分析壁纸明暗 → 适配文字对比度（正文 ≥ 4.5:1 / 标题 ≥ 3:1）
          WallpaperTone.analyze(buf).then((tone: number) => {
            WallpaperTone.save(tone);
          });
          this.applyWallpaper(`c:${dstPath}`);
          // 清理历史自定义壁纸文件（保留当前使用的）
          Wallpaper.cleanupUserWallpapers(ctx.filesDir, dstPath);
        } catch (e) {
          this.getUIContext().getPromptAction().showToast({ message: '图片导入失败' });
        }
      }).catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: '选择文件失败' });
      });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '选择文件失败' });
    }
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
        // 唯一命名：避免覆盖同一路径导致 Image 命中缓存而不刷新
        const dstPath: string = Wallpaper.newUserWallpaperPath(ctx.filesDir);
        const file: fileIo.File = fileIo.openSync(dstPath,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.READ_WRITE);
        fileIo.writeSync(file.fd, arr);
        fileIo.closeSync(file);
        // 自动分析壁纸明暗 → 适配文字对比度
        WallpaperTone.analyze(arr).then((tone: number) => {
          WallpaperTone.save(tone);
        });
        this.applyWallpaper(`c:${dstPath}`);
        // 清理历史自定义壁纸文件（保留当前使用的）
        Wallpaper.cleanupUserWallpapers(ctx.filesDir, dstPath);
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
      .backgroundColor(this.subtitleColor === color ? Theme.colorOf(this.themeColor) : GlassMaterial.cardBg($r('app.color.bg_chip'), AppStorage.get<boolean>('isDarkMode') ?? false))
      .backgroundBlurStyle(BlurStyle.Thin)
      .border({ width: 1, color: GlassMaterial.BORDER })
      .shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 })
      .clip(true)
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
        .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
        .margin({ top: 6 })
    }
    .onClick(() => {
      this.applyTheme(key);
    })
  }

  /** 字体管理入口节（字号调节已统一收敛到「字体管理」页，本页不再重复提供档位/滑条） */
  @Builder
  fontSection() {
    // MaterialCard 承载：材质层是卡片内部底层、与卡片同尺寸同圆角，材质生效时卡片底色/磨砂/亮边/阴影让出
    // （关闭光感则回落为原来的纯色/毛玻璃卡片）；原 16vp 内边距走 cardPadding、14vp 上间距走 cardMargin。
    MaterialCard({
      cardRadius: 16,
      cardPadding: 16,
      cardBg: $r('app.color.bg_card'),
      cardBlur: GlassMaterial.bgBlur(this.immersiveEffect),
      cardBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
      cardBorderC: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent,
      cardMargin: { top: 14 }
    }) {
    Column() {
      Row() {
        Text('字体')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .margin({ bottom: 12 })

      // ── 字体管理入口（大小 / 粗细 / 中文字体 / 英数字体 / 上传与管理字体）──
      // 对应参考项目 `FontManagePage`，本页只放入口与摘要
      Row() {
        Column({ space: 3 }) {
          Text('字体管理')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(`粗细：${this.weightLabelText()} · 中文：${this.familyLabelText(this.fontFamilyZh)} · 英数：${this.familyLabelText(this.fontFamilyEn)}`)
            .fontSize(11)
            .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 胶囊按钮：材质走 MaterialButton 的 Toggle 承载层（跳转行为不变）
        MaterialButton({
          btnRadius: 17,
          btnBg: Theme.colorOf(this.themeColor),
          btnBlur: GlassMaterial.cardBlur(),
          btnBorderW: GlassMaterial.borderWidth(),
          btnBorderC: GlassMaterial.borderColor(),
          btnOnClick: () => {
            AppState.stack.pushPath({ name: Const.ROUTE_FONT_MANAGE });
          }
        }) {
          Text('进入')
            .fontSize(13)
            .fontColor(Color.White)
            .height(34)
            .padding({ left: 16, right: 16 })
            .textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 14 })
    }
    .width('100%')
    }
  }

  /** 字重方案文案（字体组摘要用；与 FontManagePage 的 WEIGHT_OPTIONS 文案一致） */
  private weightLabelText(): string {
    const m: string = this.weightMode;
    if (m === 'thin') {
      return '细';
    }
    if (m === 'light') {
      return '较轻';
    }
    if (m === 'regular') {
      return '常规';
    }
    if (m === 'medium') {
      return '中等';
    }
    if (m === 'bold') {
      return '粗';
    }
    if (m === 'custom') {
      return '自定义';
    }
    return '跟随原样式';
  }

  /** 字体族文案（空=跟随系统） */
  private familyLabelText(name: string): string {
    return name.length > 0 ? name : '跟随系统';
  }

  /**
   * 外观设置（本页核心分组，与顶栏主题色 / 背景壁纸同页）：
   * 全局沉浸光感 = 卡片/顶栏毛玻璃的统一开关（唯一键 immersiveEffect，实时生效）+ 通透程度。
   * 原「卡片材质」「材质风格（云母/光感）」已移除。
   */
  @Builder
  appearanceSection() {
    // 最小光感卡结构：Stack{ 材质承载层(常驻) + 内容列 }——材质生效时卡片底色/磨砂/亮边让出；
    // 含 TextInput（灰字自定义）。原 16vp 内边距走内容列 padding、14vp 上间距走外壳 margin，间距不变。
    Stack({ alignContent: Alignment.TopStart }) {
      if (materialAvailable()) {
        MaterialCardLayer({ layerRadius: 16, layerShadow: false, layerForce: true })
      }
      Column() {
      Row() {
        Column({ space: 4 }) {
          Text('全局沉浸光感')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
          Text('开启后卡片与顶栏使用毛玻璃光感；关闭后为纯色卡片（首页已接入，实时生效）')
            .fontSize(11)
            .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.immersiveEffect })
          .selectedColor(Theme.colorOf(this.themeColor))
          .onChange((on: boolean) => {
            this.immersiveEffect = on;
            AppStorage.setOrCreate('immersiveEffect', on);
            DataStore.setImmersive(on);
            this.getUIContext().getPromptAction().showToast({
              message: on ? '已开启全局沉浸光感' : '已关闭全局沉浸光感（纯色卡片）'
            });
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      // 诊断行（移植自参考项目「排查工具」）：
      // 形如 `API≥26 材质=已构造 状态=非DISABLE(ENABLE) 开关=开 流光=#079841 承载=下发材质`
      Text(materialDiagnostics(this.pressGlow, Theme.colorOf(this.themeColor)))
        .fontSize(11)
        .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
        .width('100%')
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 6 })

      // 主页页面平滑切换（移植自参考项目）：页签切换时页面平滑滑动过渡，实时生效
      Row() {
        Column({ space: 4 }) {
          Text('主页页面平滑切换')
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('开启后主页各页签切换时页面平滑滑动过渡')
            .fontSize(11)
            .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.smoothPageSwitch })
          .selectedColor(Theme.colorOf(this.themeColor))
          .onChange((on: boolean) => {
            this.smoothPageSwitch = on;
            AppearanceStore.setSmoothPageSwitch(on);
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 14 })

      // ── 卡片沾色：卡片底色混入 10% 主题色（移植自参考项目「卡片沾色」）──
      Row() {
        Column({ space: 3 }) {
          Text('卡片沾色')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('所有卡片底色混入 10% 主题色，观感更统一')
            .fontSize(11)
            .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.cardTint })
          .selectedColor(Theme.colorOf(this.themeColor))
          .onChange((on: boolean) => {
            AppearanceStore.setCardTint(on);
            this.getUIContext().getPromptAction().showToast({ message: on ? '已开启卡片沾色' : '已关闭卡片沾色' });
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 14 })

      // ── 主题色流光：按压沉浸光感卡片的流光/光晕改用主题色（移植自参考项目「主题色流光」）──
      Row() {
        Column({ space: 3 }) {
          Text('主题色流光')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('按压卡片时的光斑/光晕使用当前主题色')
            .fontSize(11)
            .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.pressGlow })
          .selectedColor(Theme.colorOf(this.themeColor))
          .onChange((on: boolean) => {
            AppearanceStore.setPressGlow(on);
            this.getUIContext().getPromptAction().showToast({ message: on ? '流光已改用主题色' : '流光已恢复默认颜色' });
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 14 })

      // ── 卡片流光触感：关闭后按压卡片不再出现流光（移植自参考项目「卡片流光触感」）──
      Row() {
        Column({ space: 3 }) {
          Text('卡片流光触感')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text('开启后按压卡片才出现流光；关闭则按压无光')
            .fontSize(11)
            .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.glowTouch })
          .selectedColor(Theme.colorOf(this.themeColor))
          .onChange((on: boolean) => {
            AppearanceStore.setCardGlowTouch(on);
            this.getUIContext().getPromptAction().showToast({ message: on ? '已开启卡片流光触感' : '已关闭卡片流光触感' });
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: 14 })

      // 通透程度滑条：越高越通透透明（磨砂越轻），越低越白越模糊（拖动实时生效）
      Row() {
        Text('通透程度')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(`${this.glassStrength}`)
          .fontSize(12)
          .fontColor(GlassMaterial.graySecondary($r('app.color.text_secondary')))
          .margin({ left: 8 })
        Blank()
      }
      .width('100%')
      .margin({ top: 14 })

      Slider({ value: this.glassStrength, min: 0, max: 100, step: 1, style: SliderStyle.OutSet })
        .selectedColor(Theme.colorOf(this.themeColor))
        .width('100%')
        .onChange((value: number, mode: SliderChangeMode) => {
          if (mode === SliderChangeMode.End || mode === SliderChangeMode.Click) {
            this.glassStrength = Math.round(value);
            AppStorage.setOrCreate('glassStrength', this.glassStrength);
            DataStore.saveGlassStrength(this.glassStrength);
          }
        })

      // 灰色字体颜色：默认灰 / 白 / 黑 / 自定义（提升壁纸上灰色文字的可读性）
      Row() {
        Text('灰色字体颜色')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Row({ space: 6 }) {
          this.grayChip('默认', 'default')
          this.grayChip('白', 'white')
          this.grayChip('黑', 'black')
          this.grayChip('自定义', 'custom')
        }
      }
      .width('100%')
      .margin({ top: 14 })

      if (this.grayTextMode === 'custom') {
        TextInput({ text: this.grayTextColor, placeholder: 'RRGGBB（如 9AA0A6）' })
          .width('100%')
          .height(40)
          .fontSize(13)
          .margin({ top: 10 })
          .onChange((v: string) => {
            this.grayTextColor = v;
            AppStorage.setOrCreate('grayTextColor', v);
            DataStore.saveGrayCustom(v);
          })
      }
      }
      .width(LayoutPolicy.matchParent)
      .padding(16)
    }
    .width('100%')
    .borderRadius(16)
    .clip(true)
    .backgroundColor(materialAvailable() ? Color.Transparent : $r('app.color.bg_card'))
    .backgroundBlurStyle(materialAvailable() ? BlurStyle.NONE : GlassMaterial.bgBlur(this.immersiveEffect))
    .border({ width: materialAvailable() ? 0 : (this.immersiveEffect ? GlassMaterial.borderWidth() : 0), color: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent })
    .margin({ top: 14 })
  }

  /** 分组标题（主题 / 卡片 / 字体 / 背景） */
  @Builder
  groupLabel(text: string) {
    Text(text)
      .fontSize(12)
      .fontWeight(FontWeight.Medium)
      .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
      .width('100%')
      .margin({ top: 18 })
  }

  /** 灰字模式胶囊（选中=主题色底白字） */
  @Builder
  grayChip(label: string, mode: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.grayTextMode === mode ? Color.White : $r('app.color.text_primary'))
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .backgroundColor(this.grayTextMode === mode ? Theme.colorOf(this.themeColor) : GlassMaterial.cardBg($r('app.color.bg_chip'), AppStorage.get<boolean>('isDarkMode') ?? false))
      .backgroundBlurStyle(BlurStyle.Thin)
      .border({ width: 1, color: GlassMaterial.BORDER })
      .shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 })
      .clip(true)
      .borderRadius(12)
      .onClick(() => {
        this.grayTextMode = mode;
        AppStorage.setOrCreate('grayTextMode', mode);
        DataStore.saveGrayMode(mode);
      })
  }

  /** 顶栏主题色节：三色预设 + 自定义 rrggbb
   *  ⚠ 对照实验：最小结构 = Stack{ 材质承载层(常驻) + 内容 Column }，不含 MaterialCard 的
   *  onClick/hoverEffect/onAreaChange/Flex 等包装——用于定位"卡内输入框无法输入"的拦截环节。
   *  若输入与光感同时成立 → 拦截者在 MaterialCard 其余包装中，逐个加回定位；
   *  若输入仍失效 → Stack+承载层 本身与 TextInput 冲突，含输入框的卡退回普通卡。 */
  @Builder
  themeSection() {
    Column() {
      Row() {
        Text('顶栏主题色')
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text(`当前：${this.themeNameText()}`)
          .fontSize(11)
          .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
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
          // 统一按钮质感（细亮边 + 微阴影 + 磨砂；大小与颜色不变）
          .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, this.immersiveEffect))
          .border({ width: 1, color: 'rgba(255,255,255,0.28)' })
          .shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
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
          .backgroundBlurStyle(Immersive.blur(BlurStyle.Thin, this.immersiveEffect))
          .border({ width: 1, color: 'rgba(255,255,255,0.28)' })
          .shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 }).clip(true)
          .margin({ left: 8 })
          .onClick(() => {
            AppStorage.setOrCreate('barStyle', 'new');
            DataStore.setBarStyle('new');
          })
      }
      .width('100%')
      .margin({ bottom: 12 })


      // 高权限自定义主题色：默认仅内置主题色染页面背景；开启后自定义 hex 也染背景
      // （移植自参考项目「高权限自定义主题色」）
      Row() {
        Column({ space: 3 }) {
          Text('高权限自定义主题色')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_primary'))
          Text(this.customAccentFull ? '自定义主题色同时染色页面背景' : '仅内置主题色染页面背景（默认）')
            .fontSize(11)
            .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.customAccentFull })
          .selectedColor(Theme.colorOf(this.themeColor))
          .onChange((on: boolean) => {
            AppearanceStore.setCustomAccentFull(on);
            this.getUIContext().getPromptAction().showToast({
              message: on ? '自定义主题色已可染页面背景' : '已恢复：仅内置主题色染页面背景'
            });
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
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
          .fontColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
          .margin({ right: 10 })
        TextInput({ text: this.subHex, placeholder: '#RRGGBB' })
  .fontSize(13)
  .fontColor($r('app.color.text_primary'))
  .placeholderColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
  .backgroundColor(this.isDarkMode ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.05)')
  .border({ width: 1, color: this.isDarkMode ? 'rgba(255,255,255,0.20)' : 'rgba(0,0,0,0.12)' })
  .borderRadius(10)
  .height(40)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.subHex = v;
          })
        // 胶囊按钮：材质走 MaterialButton 的 Toggle 承载层；原 .margin({ left: 10 }) 走 btnMargin
        MaterialButton({
          btnRadius: 18,
          btnBg: Theme.colorOf(this.themeColor),
          btnBlur: GlassMaterial.cardBlur(),
          btnBorderW: GlassMaterial.borderWidth(),
          btnBorderC: GlassMaterial.borderColor(),
          btnMargin: { left: 10 },
          btnOnClick: () => {
            this.applySubtitleHex();
          }
        }) {
          Text('应用')
            .fontSize(13)
            .fontColor(Color.White)
            .height(36)
            .padding({ left: 16, right: 16 })
            .textAlign(TextAlign.Center)
        }
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
          .fontColor(GlassMaterial.graySecondary($r('app.color.text_secondary')))
          .margin({ right: 10 })
        TextInput({ text: $$this.hexInput, placeholder: '#RRGGBB' })
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .placeholderColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
          .backgroundColor(this.isDarkMode ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.05)')
          .border({ width: 1, color: this.isDarkMode ? 'rgba(255,255,255,0.20)' : 'rgba(0,0,0,0.12)' })
          .borderRadius(10)
          .height(40)
          .layoutWeight(1)
          .onChange((v: string) => {
            this.validateHex(v);
          })
        // 胶囊按钮：材质走 MaterialButton；原来的 .enabled(this.hexOk) 走 btnEnabled、.margin 走 btnMargin
        MaterialButton({
          btnRadius: 19,
          btnBg: Theme.colorOf(this.themeColor),
          btnBlur: GlassMaterial.cardBlur(),
          btnBorderW: GlassMaterial.borderWidth(),
          btnBorderC: GlassMaterial.borderColor(),
          btnEnabled: this.hexOk,
          btnMargin: { left: 10 },
          btnOnClick: () => {
            this.applyHexTheme();
          }
        }) {
          Text('应用')
            .fontSize(13)
            .fontColor($r('app.color.brand_on'))
            .height(38)
            .padding({ left: 16, right: 16 })
            .textAlign(TextAlign.Center)
        }
      }
      .width('100%')
    }
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(16)
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
            // ═══ 组 1/4：主题（顶栏主题色 · 顶栏样式 · 副标题色 · 高权限自定义主题色）═══
            this.groupLabel('主题')
            this.themeSection()

            // ═══ 组 2/4：卡片（沉浸光感 · 通透程度 · 沾色 · 流光 · 灰字色）═══
            this.groupLabel('卡片')
            this.appearanceSection()

            // ═══ 组 3/4：字体（字体管理入口；字号调节已收敛到「字体管理」页）═══
            this.groupLabel('字体')
            this.fontSection()

            // ═══ 组 4/4：背景（背景壁纸卡片，见下）═══
            this.groupLabel('背景')
            // ── 壁纸（卡片）：更换背景（裁剪）/ 直接应用 / 清空 / 蒙版 / 图像地址 ──
            // 最小光感卡结构：Stack{ 材质承载层(常驻) + 内容列 }——材质生效时卡片底色/磨砂/亮边让出；
            // 含 TextInput（图像地址）。原 16vp 内边距走内容列 padding、14vp 上间距走外壳 margin，间距不变。
            Stack({ alignContent: Alignment.TopStart }) {
              if (materialAvailable()) {
                MaterialCardLayer({ layerRadius: 16, layerShadow: false, layerForce: true })
              }
              Column() {
              Text('背景壁纸')
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
                .backgroundColor($r('app.color.bg_chip')).backgroundBlurStyle(GlassMaterial.cardBlur()).border({ width: GlassMaterial.cardBorderWidth(), color: GlassMaterial.borderColor() }).shadow(GlassMaterial.cardShadowStyle()).clip(true)

              Text('已使用自定义壁纸')
                .fontSize(12)
                .fontColor(Theme.colorOf(this.themeColor))
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ top: 8 })
            }
            // 操作区：更换背景（进裁剪页，可缩放/平移后应用） / 从相册直接应用
            Row({ space: 10 }) {
              // 胶囊按钮：材质走 MaterialButton 的 Toggle 承载层。
              // 原 Button 的 layoutWeight 移到外层 Column（MaterialButton 的 Stack 内部不支持 layoutWeight），
              // 内容自己写 width('100%') 撑满；Row 的 10vp 间距不变。
              Column() {
                MaterialButton({
                  btnRadius: 21,
                  btnBg: Theme.colorOf(this.themeColor),
                  btnBlur: GlassMaterial.cardBlur(),
                  btnBorderW: GlassMaterial.borderWidth(),
                  btnBorderC: GlassMaterial.borderColor(),
                  btnOnClick: () => {
                    AppState.stack.pushPath({ name: Const.ROUTE_BG_CROP });
                  }
                }) {
                  Text('更换背景（裁剪）')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.brand_on'))
                    .width('100%')
                    .height(42)
                    .textAlign(TextAlign.Center)
                }
              }
              .layoutWeight(1)
              Column() {
                MaterialButton({
                  btnRadius: 21,
                  btnBg: $r('app.color.bg_chip'),
                  btnBlur: GlassMaterial.cardBlur(),
                  btnBorderW: GlassMaterial.borderWidth(),
                  btnBorderC: GlassMaterial.borderColor(),
                  btnOnClick: () => {
                    this.pickCustomWallpaper();
                  }
                }) {
                  Text('从相册直接应用')
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .width('100%')
                    .height(42)
                    .textAlign(TextAlign.Center)
                }
              }
              .layoutWeight(1)
            }
            .width('100%')
            .margin({ top: 18 })
            // 清空背景：恢复默认纯色背景（粉红按钮）
            // 胶囊按钮（整宽）：材质走 MaterialButton；原 .margin({ top: 12 }) 走 btnMargin
            MaterialButton({
              btnRadius: 21,
              btnBg: 'rgba(242,160,181,0.85)',
              btnBlur: BlurStyle.Thin,
              btnBorderW: GlassMaterial.borderWidth(),
              btnBorderC: GlassMaterial.borderColor(),
              btnMargin: { top: 12 },
              btnOnClick: () => {
                this.cancelWallpaper();
              }
            }) {
              Text('清空背景')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
                .width('100%')
                .height(42)
                .textAlign(TextAlign.Center)
            }
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
  .fontSize(13)
  .fontColor($r('app.color.text_primary'))
  .placeholderColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
  .backgroundColor(this.isDarkMode ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.05)')
  .border({ width: 1, color: this.isDarkMode ? 'rgba(255,255,255,0.20)' : 'rgba(0,0,0,0.12)' })
  .borderRadius(10)
  .height(40)
                .layoutWeight(1)
                .onChange((v: string) => {
                  this.urlText = v;
                })
                .onSubmit(() => {
                  this.importByUrl();
                })
              // 胶囊按钮（定宽 96）：材质走 MaterialButton；宽高由内容承担，原 .margin({ left: 12 }) 走 btnMargin
              MaterialButton({
                btnRadius: 21,
                btnBg: Theme.colorOf(this.themeColor),
                btnBlur: GlassMaterial.cardBlur(),
                btnBorderW: GlassMaterial.borderWidth(),
                btnBorderC: GlassMaterial.borderColor(),
                btnMargin: { left: 12 },
                btnOnClick: () => {
                  this.importByUrl();
                }
              }) {
                Text('保存')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.brand_on'))
                  .width(96)
                  .height(42)
                  .textAlign(TextAlign.Center)
              }
            }
            .width('100%')
            .margin({ top: 12 })
            .alignItems(VerticalAlign.Center)
            // URL 行上移到提示文本上方；提示放其下
            Text('提示：壁纸应用在主界面五个 Tab 与多数二级页背景，切换后即时生效；课程表页保持纯色底不受影响。「更换背景（裁剪）」可先缩放/平移再按屏幕比例裁剪保存；「清空背景」恢复默认纯色背景。')
              .fontSize(11)
              .lineHeight(18)
              .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
              .width('100%')
              .margin({ top: 12 })
            }
            .width(LayoutPolicy.matchParent)
            .padding(16)
            }
            .width('100%')
            .borderRadius(16)
            .clip(true)
            .backgroundColor(materialAvailable() ? Color.Transparent : $r('app.color.bg_card'))
            .backgroundBlurStyle(materialAvailable() ? BlurStyle.NONE : GlassMaterial.bgBlur(this.immersiveEffect))
            .border({ width: materialAvailable() ? 0 : (this.immersiveEffect ? GlassMaterial.borderWidth() : 0), color: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent })
            .margin({ top: 14 })

            // ── 主题组合（卡片）──
            // 最小光感卡结构：Stack{ 材质承载层(常驻) + 内容列 }——含 TextInput（组合名称）；
            // 原 16vp 内边距走内容列 padding、14vp 上间距走外壳 margin，间距不变。
            Stack({ alignContent: Alignment.TopStart }) {
              if (materialAvailable()) {
                MaterialCardLayer({ layerRadius: 16, layerShadow: false, layerForce: true })
              }
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
  .fontSize(13)
  .fontColor($r('app.color.text_primary'))
  .placeholderColor(GlassMaterial.grayTertiary($r('app.color.text_tertiary')))
  .backgroundColor(this.isDarkMode ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.05)')
  .border({ width: 1, color: this.isDarkMode ? 'rgba(255,255,255,0.20)' : 'rgba(0,0,0,0.12)' })
  .borderRadius(10)
  .height(40)
                .layoutWeight(1)
                .onChange((v: string) => {
                  this.comboName = v;
                })
              // 胶囊按钮：材质走 MaterialButton；原 .margin({ left: 10 }) 走 btnMargin
              MaterialButton({
                btnRadius: 20,
                btnBg: Theme.colorOf(this.themeColor),
                btnBlur: GlassMaterial.cardBlur(),
                btnBorderW: GlassMaterial.borderWidth(),
                btnBorderC: GlassMaterial.borderColor(),
                btnMargin: { left: 10 },
                btnOnClick: () => {
                  this.saveCombo();
                }
              }) {
                Text('保存当前组合')
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
                  .height(40)
                  .padding({ left: 16, right: 16 })
                  .textAlign(TextAlign.Center)
              }
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
                    .backgroundColor($r('app.color.bg_chip')).backgroundBlurStyle(GlassMaterial.cardBlur()).border({ width: GlassMaterial.cardBorderWidth(), color: GlassMaterial.borderColor() }).shadow(GlassMaterial.cardShadowStyle()).clip(true)
                    .margin({ right: 12 })
                } else if (c.wallpaper !== 'none' && c.wallpaper.length > 0) {
                  // 旧内置壁纸 id（已移除资源）：仅显示占位块
                  Column()
                    .width(40)
                    .height(40)
                    .borderRadius(10)
                    .backgroundColor($r('app.color.bg_chip')).backgroundBlurStyle(GlassMaterial.cardBlur()).border({ width: GlassMaterial.cardBorderWidth(), color: GlassMaterial.borderColor() }).shadow(GlassMaterial.cardShadowStyle()).clip(true)
                    .margin({ right: 12 })
                } else {
                  Column()
                    .width(40)
                    .height(40)
                    .borderRadius(10)
                    .backgroundColor($r('app.color.bg_chip')).backgroundBlurStyle(GlassMaterial.cardBlur()).border({ width: GlassMaterial.cardBorderWidth(), color: GlassMaterial.borderColor() }).shadow(GlassMaterial.cardShadowStyle()).clip(true)
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
                // 组合操作胶囊：材质走 MaterialButton 的 Toggle 承载层（点击行为不变）
                MaterialButton({
                  btnRadius: 12,
                  btnBg: Theme.colorOf(this.themeColor),
                  btnBlur: GlassMaterial.cardBlur(),
                  btnBorderW: GlassMaterial.borderWidth(),
                  btnBorderC: GlassMaterial.borderColor(),
                  btnOnClick: () => {
                    this.applyCombo(c);
                  }
                }) {
                  Text('应用')
                    .fontSize(12)
                    .fontColor(Color.White)
                    .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                }
                MaterialButton({
                  btnRadius: 12,
                  btnBg: $r('app.color.bg_chip'),
                  btnBlur: GlassMaterial.cardBlur(),
                  btnBorderW: GlassMaterial.borderWidth(),
                  btnBorderC: GlassMaterial.borderColor(),
                  btnMargin: { left: 8 },
                  btnOnClick: () => {
                    this.deleteCombo(c.name);
                  }
                }) {
                  Text('删除')
                    .fontSize(12)
                    .fontColor(GlassMaterial.graySecondary($r('app.color.text_secondary')))
                    .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                }
              }
              .width('100%')
              .padding({ left: 14, right: 14, top: 10, bottom: 10 })
              .margin({ top: 10 })
              .backgroundColor($r('app.color.bg_chip')).backgroundBlurStyle(GlassMaterial.cardBlur()).border({ width: GlassMaterial.cardBorderWidth(), color: GlassMaterial.borderColor() }).shadow(GlassMaterial.cardShadowStyle()).clip(true)
              .borderRadius(14)
            }, (c: ThemeCombo) => c.name)
            }
            .width(LayoutPolicy.matchParent)
            .padding(16)
            }
            .width('100%')
            .borderRadius(16)
            .clip(true)
            .backgroundColor(materialAvailable() ? Color.Transparent : $r('app.color.bg_card'))
            .backgroundBlurStyle(materialAvailable() ? BlurStyle.NONE : GlassMaterial.bgBlur(this.immersiveEffect))
            .border({ width: materialAvailable() ? 0 : (this.immersiveEffect ? GlassMaterial.borderWidth() : 0), color: this.immersiveEffect ? GlassMaterial.borderColor() : Color.Transparent })
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
          subtitle: '顶栏颜色 · 背景壁纸',
          onBack: () => {
            AppState.stack.pop();
          }
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(AppearanceStore.pageBackground(this.isDarkMode, this.themeColor))
    }
    .hideTitleBar(true)
    .backgroundColor(AppearanceStore.pageBackground(this.isDarkMode, this.themeColor))
  }
}
