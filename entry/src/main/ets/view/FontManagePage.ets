/**
 * 字体管理页（外观设置 → 字体 → 字体管理）
 * —— 移植自参考项目 miha_hm（鸿米家）`pages/FontManagePage.ets`
 * 对应参考文件：miha_hm `pages/FontManagePage.ets` + `utils/CustomFonts.ets`
 *
 * 六项能力：
 *   1) 字体大小：全局字号缩放（沿用 fontScale，重启由 EntryAbility 恢复）
 *   2) 字体粗细：跟随原样式 / 细 / 较轻 / 常规 / 中等 / 粗 / 自定义数值
 *   3) 中文字体：跟随系统 或 选择系统字体 / 已上传字体（文本含中文时用此族）
 *   4) 英数字体：跟随系统 或 选择系统字体 / 已上传字体（文本不含中文时用此族）
 *   5) 上传字体：文档选择器选 .ttf/.otf/.ttc → 拷入 filesDir/custom_fonts → 注册到系统字体库
 *   6) 管理字体：已上传字体列表（应用为中文/英数字体 / 删除）
 *
 * 字体 API（本工程 targetSdkVersion 26 可用，见 @ohos.graphics.text）：
 *   FontCollection.getGlobalInstance().loadFontSyncWithCheck(alias, 'file://path') / unloadFontSync(alias)
 *   getSystemFontFullNamesByType(SystemFontType.ALL) → 可枚举系统字体全名
 */
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { AppearanceStore } from '../common/AppearanceStore';
import { CustomFontItem, DataStore } from '../common/DataStore';
import { GlassMaterial } from '../common/GlassMaterial';
import { sheetBlurStyle } from '../common/SystemMaterial';
import { Theme } from '../common/ThemeUtil';
import { AppState } from '../common/AppState';
import { MaterialCard, MaterialSheetPanel } from './common/MaterialCard';
import { PageHeader } from './common/UiKit';
import { WallpaperFill } from './common/WallpaperFill';

/** 字重方案（key 需与 AppearanceStore.fontWeight 的分支保持一致） */
interface WeightOption {
  key: string;
  label: string;
}

const WEIGHT_OPTIONS: WeightOption[] = [
  { key: 'follow', label: '跟随原样式' },
  { key: 'thin', label: '细' },
  { key: 'light', label: '较轻' },
  { key: 'regular', label: '常规' },
  { key: 'medium', label: '中等' },
  { key: 'bold', label: '粗' },
  { key: 'custom', label: '自定义' }
];

/** 系统字体枚举上限（列表过长影响滚动性能，取前 300 条） */
const SYSTEM_FONT_LIMIT: number = 300;

/**
 * 区块卡片：统一材质底 + 标题行 + 内容插槽（用 @BuilderParam 承载内容，
 * 避免 @Builder 传函数参数的写法——ArkTS 不支持）。
 */
@Component
struct SectionCard {
  @Prop title: string = '';
  @Prop subtitle: string = '';
  /** 灰字广播订阅：颜色表达式需传 this.grayTick 才登记响应式依赖（否则改色不实时刷新） */
  @StorageProp('grayTick') grayTick: number = 0;
  @StorageProp('immersiveEffect') immersiveEffect: boolean = false;
  /** 全局字重响应式订阅：表达式读 this.fwMode 才登记依赖，fwValue 声明即订阅 */
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  @BuilderParam content: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  build() {
    // 注意：ArkTS 不允许在「尾随闭包初始化的自定义组件」之后继续链式加属性
    // （`MaterialCard({...}) { ... }.margin(...)` 会报 "Cannot find name 'margin'"），
    // 故外层再包一个 Column 承载间距。
    Column() {
      MaterialCard({
        cardRadius: 16,
        cardBg: $r('app.color.bg_card'),
        cardBlur: GlassMaterial.bgBlur(this.immersiveEffect),
        cardBorderW: this.immersiveEffect ? GlassMaterial.borderWidth() : 0,
        cardBorderC: GlassMaterial.borderColor(),
        cardShadow: GlassMaterial.cardShadowStyle()
      }) {
        Column() {
          Row() {
            Text(this.title)
              .fontSize(15)
              .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
              .fontColor($r('app.color.text_primary'))
            Blank()
            if (this.subtitle.length > 0) {
              Text(this.subtitle)
                .fontSize(11)
                .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .width('100%')
          .margin({ bottom: 12 })

          this.content()
        }
        .width('100%')
        .padding(16)
      }
    }
    .width('100%')
    .margin({ top: 14 })
  }
}

@Component
export struct FontManagePage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  /** 灰字广播订阅：颜色表达式需传 this.grayTick 才登记响应式依赖（否则改色不实时刷新） */
  @StorageProp('grayTick') grayTick: number = 0;
  /** 全局字重响应式订阅：表达式读 this.fwMode 才登记依赖，fwValue 声明即订阅 */
  @StorageProp('fontWeightMode') fwMode: string = 'follow';
  @StorageProp('fontWeightValue') fwValue: number = 400;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  /** 已上传字体别名列表（AppStorage 实时联动：上传/删除后列表立即刷新） */
  @StorageLink('customFonts') customFonts: string[] = [];
  /** 中文字体族（空=跟随系统） */
  @StorageLink('fontFamilyZh') fontFamilyZh: string = '';
  /** 英数字体族（空=跟随系统） */
  @StorageLink('fontFamilyEn') fontFamilyEn: string = '';
  /** 字重方案与自定义数值 */
  @StorageLink('fontWeightMode') weightMode: string = 'follow';
  @StorageLink('fontWeightValue') weightValue: number = 400;
  /** 字号缩放 */
  @State fontScale: number = DataStore.loadFontScale();
  /** 可枚举的系统字体全名（异步获取） */
  @State systemFonts: string[] = [];
  /** 字体族选择面板开关 */
  @State showFamilySheet: boolean = false;
  /** 选择目标：'zh' / 'en' */
  @State pickTarget: string = 'zh';
  /** 已上传字体条目（含文件名，用于删除文件） */
  @State fontItems: CustomFontItem[] = [];
  @State busy: boolean = false;

  aboutToAppear(): void {
    this.fontItems = AppearanceStore.customFontItems();
    this.loadSystemFonts();
  }

  /** 加载系统字体全名（失败保持空数组，面板给出提示） */
  private loadSystemFonts(): void {
    AppearanceStore.systemFontNames().then((names: string[]) => {
      const list: string[] = [];
      const n: number = Math.min(names.length, SYSTEM_FONT_LIMIT);
      for (let i = 0; i < n; i++) {
        list.push(names[i]);
      }
      this.systemFonts = list;
    });
  }

  /** 刷新已上传字体列表（持久化 → AppStorage 联动，页面列表随之刷新） */
  private refreshFonts(): void {
    this.fontItems = AppearanceStore.customFontItems();
    AppearanceStore.syncFontAliases();
  }

  // ══════════════════════════════════════════════════════════════
  // 1) 字体大小
  // ══════════════════════════════════════════════════════════════

  /** 应用字号缩放（全局生效 + 持久化） */
  private applyFontScale(v: number): void {
    this.fontScale = v;
    DataStore.saveFontScale(v);
    try {
      const ctx = getContext(this) as common.UIAbilityContext;
      ctx.getApplicationContext().setFontSizeScale(v);
    } catch (e) {
      // 忽略：设置失败不影响已保存的偏好
    }
  }

  /** 字号档位文案 */
  private fontScaleText(v: number): string {
    if (v <= 0.95) {
      return '小';
    }
    if (v <= 1.05) {
      return '标准';
    }
    if (v <= 1.2) {
      return '大';
    }
    return '特大';
  }

  // ══════════════════════════════════════════════════════════════
  // 2) 字体粗细
  // ══════════════════════════════════════════════════════════════

  /** 字重显示文案 */
  private weightLabel(): string {
    if (this.weightMode === 'custom') {
      return `${this.weightValue}`;
    }
    for (let i = 0; i < WEIGHT_OPTIONS.length; i++) {
      const o: WeightOption = WEIGHT_OPTIONS[i];
      if (o.key === this.weightMode) {
        return o.label;
      }
    }
    return '跟随原样式';
  }

  /** 设置字重方案 */
  private applyWeightMode(mode: string): void {
    AppearanceStore.setFontWeightMode(mode);
  }

  /** 设置自定义字重数值 */
  private applyWeightValue(v: number): void {
    AppearanceStore.setFontWeightValue(v);
  }

  // ══════════════════════════════════════════════════════════════
  // 3/4) 中文字体 / 英数字体
  // ══════════════════════════════════════════════════════════════

  /** 字体族显示名（空=跟随系统） */
  private familyLabel(name: string): string {
    return name.length > 0 ? name : '跟随系统';
  }

  /** 当前选择目标是否已选中该字体族（面板里高亮用） */
  private isCurrentFamily(name: string): boolean {
    return this.pickTarget === 'zh' ? this.fontFamilyZh === name : this.fontFamilyEn === name;
  }

  /** 设置字体族（空串=跟随系统） */
  private applyFamily(name: string): void {
    if (this.pickTarget === 'zh') {
      AppearanceStore.setFontFamilyZh(name);
    } else {
      AppearanceStore.setFontFamilyEn(name);
    }
    this.showFamilySheet = false;
    this.getUIContext().getPromptAction().showToast({
      message: name.length > 0 ? `已应用字体「${name}」` : '已恢复跟随系统字体'
    });
  }

  /** 打开字体族选择面板 */
  private openFamilySheet(target: string): void {
    this.pickTarget = target;
    this.showFamilySheet = true;
  }

  // ══════════════════════════════════════════════════════════════
  // 5) 上传字体
  // ══════════════════════════════════════════════════════════════

  /** 上传字体：选文件（免相册权限）→ 拷入 filesDir/custom_fonts → 注册 */
  private uploadFont(): void {
    if (this.busy) {
      return;
    }
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const dir: string = `${ctx.filesDir}/custom_fonts`;
      try {
        fileIo.mkdirSync(dir);
      } catch (e) {
        // 目录已存在
      }
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['ttf', 'otf', 'ttc'];
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      this.busy = true;
      docPicker.select(options).then((uris: string[]) => {
        this.busy = false;
        if (uris.length === 0) {
          return;
        }
        this.copyFontFile(uris[0], dir);
      }).catch(() => {
        this.busy = false;
        this.getUIContext().getPromptAction().showToast({ message: '选择文件失败' });
      });
    } catch (e) {
      this.busy = false;
      this.getUIContext().getPromptAction().showToast({ message: '选择文件失败' });
    }
  }

  /** 拷贝字体文件并注册（同名文件视为替换，别名沿用原文件名去扩展名） */
  private copyFontFile(uri: string, dir: string): void {
    try {
      const pickedPath: string = new fileUri.FileUri(uri).path;
      const slash: number = pickedPath.lastIndexOf('/');
      const rawName: string = slash >= 0 ? pickedPath.substring(slash + 1) : `font_${Date.now()}.ttf`;
      const alias: string = AppearanceStore.aliasOf(rawName);
      if (alias.length === 0) {
        this.getUIContext().getPromptAction().showToast({ message: '字体文件名无效' });
        return;
      }
      const srcFile: fileIo.File = fileIo.openSync(pickedPath, fileIo.OpenMode.READ_ONLY);
      const st: fileIo.Stat = fileIo.statSync(pickedPath);
      const buf: ArrayBuffer = new ArrayBuffer(st.size);
      fileIo.readSync(srcFile.fd, buf);
      fileIo.closeSync(srcFile);
      const dstPath: string = `${dir}/${rawName}`;
      const dstFile: fileIo.File = fileIo.openSync(dstPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.READ_WRITE);
      fileIo.writeSync(dstFile.fd, buf);
      fileIo.closeSync(dstFile);
      if (AppearanceStore.addCustomFont(rawName)) {
        this.refreshFonts();
        this.getUIContext().getPromptAction().showToast({ message: `已添加字体「${alias}」` });
      } else {
        this.getUIContext().getPromptAction().showToast({ message: '字体注册失败（格式不支持？）' });
      }
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '字体导入失败' });
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 6) 管理字体
  // ══════════════════════════════════════════════════════════════

  /** 删除已上传字体（注销别名 + 删除文件 + 清理引用） */
  private deleteFont(alias: string): void {
    let fileName: string = '';
    for (let i = 0; i < this.fontItems.length; i++) {
      const it: CustomFontItem = this.fontItems[i];
      if (it.alias === alias) {
        fileName = it.fileName;
      }
    }
    AppearanceStore.removeCustomFont(alias);
    if (fileName.length > 0) {
      try {
        const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
        fileIo.unlinkSync(`${ctx.filesDir}/custom_fonts/${fileName}`);
      } catch (e) {
        // 文件不存在等忽略
      }
    }
    this.refreshFonts();
    this.getUIContext().getPromptAction().showToast({ message: `已删除字体「${alias}」` });
  }

  // ══════════════════════════════════════════════════════════════
  // 通用胶囊按钮
  // ══════════════════════════════════════════════════════════════

  /** 字重方案胶囊（选中态=主题色实底） */
  @Builder
  weightChip(key: string, label: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.weightMode === key ? Color.White : $r('app.color.text_primary'))
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .backgroundColor(this.weightMode === key ? Theme.colorOf(this.themeColor) : $r('app.color.bg_chip'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .border({ width: 1, color: GlassMaterial.BORDER })
      .shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 })
      .clip(true)
      .borderRadius(12)
      .margin({ right: 8, bottom: 8 })
      .onClick(() => {
        this.applyWeightMode(key);
      })
  }

  /** 字号档位胶囊 */
  @Builder
  fontScaleChip(label: string, value: number) {
    Text(label)
      .fontSize(12)
      .fontColor(Math.abs(this.fontScale - value) < 0.01 ? Color.White : $r('app.color.text_primary'))
      .padding({ left: 12, right: 12, top: 5, bottom: 5 })
      .backgroundColor(Math.abs(this.fontScale - value) < 0.01 ? Theme.colorOf(this.themeColor) : $r('app.color.bg_chip'))
      .backgroundBlurStyle(BlurStyle.Thin)
      .border({ width: 1, color: GlassMaterial.BORDER })
      .shadow({ radius: 6, color: 'rgba(0,0,0,0.10)', offsetY: 1 })
      .clip(true)
      .borderRadius(12)
      .margin({ right: 8 })
      .onClick(() => {
        this.applyFontScale(value);
      })
  }

  // ══════════════════════════════════════════════════════════════
  // 字体族选择面板
  // ══════════════════════════════════════════════════════════════

  @Builder
  familySheet() {
    MaterialSheetPanel({ panelRadius: 24, panelPadding: 16 }) {
      Column() {
        Row() {
          Text(this.pickTarget === 'zh' ? '选择中文字体' : '选择英数字体')
            .fontSize(16)
            .fontWeight(this.fwMode === 'follow' ? FontWeight.Bold : AppearanceStore.fontWeight(FontWeight.Bold))
            .fontColor($r('app.color.text_primary'))
          Blank()
          Text('关闭')
            .fontSize(13)
            .fontColor(Theme.colorOf(this.themeColor))
            .onClick(() => {
              this.showFamilySheet = false;
            })
        }
        .width('100%')
        .margin({ bottom: 10 })

        Scroll() {
          Column() {
            Text('跟随系统')
              .fontSize(14)
              .fontColor(Theme.colorOf(this.themeColor))
              .width('100%')
              .height(44)
              .onClick(() => {
                this.applyFamily('');
              })
            Divider().color($r('app.color.divider'))

            if (this.customFonts.length > 0) {
              Text('已上传字体')
                .fontSize(11)
                .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
                .width('100%')
                .margin({ top: 10, bottom: 4 })
              ForEach(this.customFonts, (alias: string) => {
                Text(alias)
                  .fontSize(14)
                  .fontColor(this.isCurrentFamily(alias) ? Theme.colorOf(this.themeColor) : $r('app.color.text_primary'))
                  .width('100%')
                  .height(44)
                  .onClick(() => {
                    this.applyFamily(alias);
                  })
              }, (alias: string) => `cf_${alias}`)
              Divider().color($r('app.color.divider'))
            }

            Text('系统字体')
              .fontSize(11)
              .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
              .width('100%')
              .margin({ top: 10, bottom: 4 })
            if (this.systemFonts.length === 0) {
              Text('系统未提供可枚举字体（仍可用「跟随系统」或已上传字体）')
                .fontSize(12)
                .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
                .width('100%')
                .padding({ top: 6, bottom: 6 })
            }
            ForEach(this.systemFonts, (name: string) => {
              Text(name)
                .fontSize(14)
                .fontColor(this.isCurrentFamily(name) ? Theme.colorOf(this.themeColor) : $r('app.color.text_primary'))
                .width('100%')
                .height(44)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .onClick(() => {
                  this.applyFamily(name);
                })
            }, (name: string) => `sf_${name}`)
          }
          .width('100%')
        }
        .width('100%')
        .height(400)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      }
      .width('100%')
    }
  }

  // ══════════════════════════════════════════════════════════════
  // 各区块主体
  // ══════════════════════════════════════════════════════════════

  /** 1) 字体大小主体 */
  @Builder
  fontSizeBody() {
    Column() {
      Row() {
        Text('小')
          .fontSize(12)
          .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
        Slider({
          value: this.fontScale * 100,
          min: 80,
          max: 160,
          step: 5,
          style: SliderStyle.OutSet
        })
          .selectedColor(Theme.colorOf(this.themeColor))
          .trackColor($r('app.color.bg_chip'))
          .layoutWeight(1)
          .onChange((value: number, mode: SliderChangeMode) => {
            this.applyFontScale(value / 100);
          })
        Text('特大')
          .fontSize(12)
          .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
      }
      .width('100%')

      Row() {
        this.fontScaleChip('小', 0.9)
        this.fontScaleChip('标准', 1.0)
        this.fontScaleChip('大', 1.15)
        this.fontScaleChip('特大', 1.3)
      }
      .width('100%')
      .margin({ top: 6 })
    }
    .width('100%')
  }

  /** 2) 字体粗细主体 */
  @Builder
  weightBody() {
    Column() {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(WEIGHT_OPTIONS, (o: WeightOption) => {
          this.weightChip(o.key, o.label)
        }, (o: WeightOption) => o.key)
      }
      .width('100%')

      if (this.weightMode === 'custom') {
        Row() {
          Text('数值')
            .fontSize(12)
            .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
            .width(36)
          Slider({
            value: this.weightValue,
            min: 100,
            max: 900,
            step: 100,
            style: SliderStyle.OutSet
          })
            .selectedColor(Theme.colorOf(this.themeColor))
            .trackColor($r('app.color.bg_chip'))
            .layoutWeight(1)
            .onChange((value: number, mode: SliderChangeMode) => {
              this.applyWeightValue(value);
            })
          Text(`${this.weightValue}`)
            .fontSize(12)
            .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
            .width(40)
            .textAlign(TextAlign.End)
        }
        .width('100%')
        .margin({ top: 4 })
      }
    }
    .width('100%')
  }

  /** 3/4) 字体族主体（中/英数共用） */
  @Builder
  familyBody(target: string) {
    Column() {
      Row() {
        Text('当前：' + (target === 'zh' ? this.familyLabel(this.fontFamilyZh) : this.familyLabel(this.fontFamilyEn)))
          .fontSize(12)
          .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary')))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('选择')
          .fontSize(13)
          .fontColor(Color.White)
          .height(34)
          .padding({ left: 16, right: 16 })
          .backgroundColor(Theme.colorOf(this.themeColor))
          .borderRadius(17)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.openFamilySheet(target);
          })
        Text('跟随系统')
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .height(34)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.bg_chip'))
          .borderRadius(17)
          .textAlign(TextAlign.Center)
          .margin({ left: 8 })
          .onClick(() => {
            this.pickTarget = target;
            this.applyFamily('');
          })
      }
      .width('100%')
    }
    .width('100%')
  }

  /** 5) 上传字体主体 */
  @Builder
  uploadBody() {
    Column() {
      Text('支持 .ttf / .otf / .ttc；上传后自动注册，可在上方「中文字体 / 英数字体」中选择。')
        .fontSize(11)
        .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
        .width('100%')
        .margin({ bottom: 10 })
      Text(this.busy ? '处理中…' : '选择字体文件')
        .fontSize(13)
        .fontColor(Color.White)
        .height(38)
        .padding({ left: 18, right: 18 })
        .backgroundColor(Theme.colorOf(this.themeColor))
        .borderRadius(19)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.uploadFont();
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  /** 6) 管理字体主体 */
  @Builder
  manageBody() {
    Column() {
      if (this.fontItems.length === 0) {
        Text('尚未上传字体。上方「上传字体」可添加 .ttf / .otf 文件。')
          .fontSize(12)
          .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
          .width('100%')
      }
      ForEach(this.fontItems, (it: CustomFontItem) => {
        Row() {
          Column() {
            Text(it.alias)
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Text(it.fileName)
              .fontSize(10)
              .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary')))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text('设为中文')
            .fontSize(11)
            .fontColor(Theme.colorOf(this.themeColor))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .onClick(() => {
              this.pickTarget = 'zh';
              this.applyFamily(it.alias);
            })
          Text('设为英数')
            .fontSize(11)
            .fontColor(Theme.colorOf(this.themeColor))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .onClick(() => {
              this.pickTarget = 'en';
              this.applyFamily(it.alias);
            })
          Text('删除')
            .fontSize(11)
            .fontColor('#DB5252')
            .padding({ left: 8, right: 4, top: 4, bottom: 4 })
            .onClick(() => {
              this.deleteFont(it.alias);
            })
        }
        .width('100%')
        .height(52)
      }, (it: CustomFontItem) => `ff_${it.alias}`)
    }
    .width('100%')
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // 二级页壁纸底层：跟随全局壁纸 / 自定义背景（未启用壁纸时回落页面底色，与其它二级页一致）
        WallpaperFill()

        Column() {
          Scroll() {
            Column() {
              // 悬浮顶栏让位
              Column().width('100%').height(this.getUIContext().px2vp(this.topInsetPx) + 60)

              SectionCard({ title: '字体大小', subtitle: `当前：${this.fontScaleText(this.fontScale)}` }) {
                this.fontSizeBody()
              }
              SectionCard({ title: '字体粗细', subtitle: this.weightLabel() }) {
                this.weightBody()
              }
              SectionCard({ title: '中文字体', subtitle: this.familyLabel(this.fontFamilyZh) }) {
                this.familyBody('zh')
              }
              SectionCard({ title: '英数字体', subtitle: this.familyLabel(this.fontFamilyEn) }) {
                this.familyBody('en')
              }
              SectionCard({ title: '上传字体', subtitle: '' }) {
                this.uploadBody()
              }
              SectionCard({ title: '管理字体', subtitle: `${this.fontItems.length} 个` }) {
                this.manageBody()
              }

              Column().width('100%').height(this.getUIContext().px2vp(this.topInsetPx) + 40)
            }
            .width('100%')
            .padding({ left: 14, right: 14 })
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Off)
          .align(Alignment.Top)
          // 滑动动效：与其它二级页（CourseRawPage / AcademicPage）统一——隐藏滚动条 + 边缘回弹
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')

        PageHeader({
          title: '字体管理',
          subtitle: '大小 · 粗细 · 中英文字体',
          onBack: () => {
            AppState.stack.pop();
          }
        })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .bindSheet($$this.showFamilySheet, this.familySheet(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      showClose: false,
      backgroundColor: Color.Transparent,
      blurStyle: sheetBlurStyle(),
      onDisappear: () => {
        this.showFamilySheet = false;
      }
    })
  }
}
