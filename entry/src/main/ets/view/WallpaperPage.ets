/**
 * 个性主题页（二级页）：顶栏主题色 + 全局壁纸
 *  - 顶栏主题色：中国红/天空蓝/农大绿/自定义 #RRGGBB（输入 hex 即用）
 *  - 全局壁纸：6 张内置缩略网格（点击即应用，全局即时生效）
 *  - 相册/文档选择导入自定义图片（存应用 filesDir，持久化）
 *  - 取消壁纸：恢复默认纯色背景（同时删除自定义壁纸文件）
 */
import { common } from '@kit.AbilityKit';
import { fileIo, picker, fileUri } from '@kit.CoreFileKit';
import { http } from '@kit.NetworkKit';
import { promptAction } from '@kit.ArkUI';
import { AppState } from '../common/AppState';
import { DataStore, ThemeCombo } from '../common/DataStore';
import { DateUtil } from '../common/DateUtil';
import { WallpaperTone } from '../common/WallpaperTone';
import { Immersive } from './common/Immersive';
import { Theme } from '../common/ThemeUtil';
import { Wallpaper } from '../common/Wallpaper';
import { PageHeader } from './common/UiKit';
import { WallpaperFill } from './common/WallpaperFill';

@Component
export struct WallpaperPage {
  /** 全局壁纸 id（'b1'..'b6' 预置 / 'c:<path>' 自定义 / 'none'=未启用） */
  @StorageProp('wallpaperId') wallpaperId: string = 'none';
  /** 壁纸蒙版开关 */
  @StorageProp('wallpaperMask') wallpaperMask: boolean = true;
  /** URL 导入输入框内容 */
  @State urlText: string = '';
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  /** 顶栏主题色（'red' | 'blue' | 'green' | '#RRGGBB'） */
  @StorageProp('themeColor') themeColor: string = 'green';
  /** 顶栏样式：new=新版渐变（默认）/ legacy=旧版实色 */
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
          const dstPath: string = `${ctx.filesDir}/wallpaper_user.dat`;
          const file: fileIo.File = fileIo.openSync(dstPath,
            fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.READ_WRITE);
          fileIo.writeSync(file.fd, buf);
          fileIo.closeSync(file);
          // 自动分析壁纸明暗 → 适配文字对比度（正文 ≥ 4.5:1 / 标题 ≥ 3:1）
          WallpaperTone.analyze(buf).then((tone: number) => {
            WallpaperTone.save(tone);
          });
          this.applyWallpaper(`c:${dstPath}`);
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
        Text('旧版实色')
          .fontSize(12)
          .fontColor(this.barStyle === 'legacy' ? Color.White : $r('app.color.text_primary'))
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .backgroundColor(this.barStyle === 'legacy' ? Theme.colorOf(this.themeColor) : $r('app.color.bg_chip'))
          .borderRadius(12)
          .onClick(() => {
            AppStorage.setOrCreate('barStyle', 'legacy');
            DataStore.setBarStyle('legacy');
          })
        Text('新版渐变')
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
          .fontSize(13)
          .height(36)
          .layoutWeight(1)
          .backgroundColor($r('app.color.bg_chip'))
          .borderRadius(10)
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

      Row({ space: 18 }) {
        this.themeSwatch('red', '#C3272B', '中国红')
        this.themeSwatch('blue', '#3B82F6', '天空蓝')
        this.themeSwatch('green', '#079841', '农大绿')
      }
      .margin({ bottom: 12 })

      // 自定义 rrggbb 输入
      Row() {
        Text('自定义')
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .margin({ right: 10 })
        TextInput({ text: $$this.hexInput, placeholder: '#RRGGBB' })
          .fontSize(13)
          .height(38)
          .layoutWeight(1)
          // 颜色码输入框：实色底 + 细描边
          .backgroundColor(this.isDarkMode ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.05)')
          .border({ width: 1, color: this.isDarkMode ? 'rgba(255,255,255,0.20)' : 'rgba(0,0,0,0.12)' })
          .borderRadius(10)
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
    }
    .width('100%')
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
            // 顶栏主题色（三色预设 + 自定义 rrggbb）
            this.themeSection()


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

            // 操作区
            Row() {
              Button('从相册选择图片')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.brand_on'))
                .backgroundColor(Theme.colorOf(this.themeColor))
                .height(42)
                .layoutWeight(1)
                .borderRadius(21)
                .onClick(() => {
                  this.pickCustomWallpaper();
                })
            }
            .width('100%')
            .margin({ top: 18 })

            // URL 导入壁纸：直接填图片链接，下载到应用目录并应用
            Row() {
              TextInput({ text: this.urlText, placeholder: '编辑图像地址（支持API地址）' })
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .placeholderColor($r('app.color.text_tertiary'))
                .backgroundColor($r('app.color.bg_chip'))
                .borderRadius(12)
                .height(40)
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
            .margin({ top: 14 })

            // 取消壁纸：恢复默认纯色背景（粉红按钮）
            Button('取消壁纸')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
              .backgroundColor('#F2A0B5')
              .height(42)
              .width('100%')
              .borderRadius(21)
              .margin({ top: 10 })
              .onClick(() => {
                this.cancelWallpaper();
              })

            // URL 行上移到提示文本上方；提示放其下
            Text('提示：壁纸应用在主界面五个 Tab 与多数二级页背景，切换后即时生效；课程表页保持纯色底不受影响；各功能卡片保持原有底色以保证可读性。取消壁纸即恢复默认纯色背景。')
              .fontSize(11)
              .lineHeight(18)
              .fontColor(WallpaperTone.onWallpaperSecondary(this.wallpaperTone, this.isDarkMode))
              .width('100%')
              .margin({ top: 16, bottom: 20 })

            // ── 主题组合：保存/应用（背景 + 顶栏颜色 + 副标题颜色）──
            Text('主题组合')
              .fontSize(15)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.text_primary'))
              .width('100%')
              .margin({ top: 4, bottom: 10 })

            Row() {
              TextInput({ text: this.comboName, placeholder: '组合名称（如：夜间阅读）' })
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .placeholderColor($r('app.color.text_tertiary'))
                .backgroundColor($r('app.color.bg_chip'))
                .borderRadius(12)
                .height(40)
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
              .backgroundColor($r('app.color.bg_card'))
              .borderRadius(14)
            }, (c: ThemeCombo) => c.name)

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
          title: '个性主题',
          subtitle: '顶栏颜色 · 背景壁纸',
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
