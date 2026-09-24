/**
 * 背景裁剪页（外观设置 → 背景 → 更换背景）
 * —— 裁剪交互组件直接移植自参考项目 miha_hm `pages/BackgroundCropPage.ets`：
 *    图片 Contain 居中固定 + 4 块遮罩 + 白色裁剪框拖动 + 圆形把手缩放框。
 *
 * 与参考项目的差异（管线保留本项目）：
 * 1) 选图：参考项目由上游页选好图传 sourceUri 进来；本项目进入页面后自动弹文档选择器
 *    （WallpaperPage 只 pushPath 不带参），拷贝进沙箱后读取；
 * 2) 保存：裁剪结果仍走本项目壁纸管线（Wallpaper.newUserWallpaperPath 唯一命名 +
 *    WallpaperTone.analyze 明暗分析 + DataStore.saveWallpaper），并保留「清空背景」入口；
 * 3) 路由：参考项目 @Entry + router.back()；本项目 NavDestination + AppState.stack.pop()。
 *
 * 实现要点（踩坑说明，来自参考项目）：
 * 1) 相册原图可达上亿像素，按原始尺寸解码会失败/耗尽内存（表现为预览一片空白，
 *    getImageInfo 只读文件头、尺寸看起来正常，极易误判成路径问题）
 *    → 预览与裁剪统一基于降采样尺寸（长边 MAX_DECODE_LONG_SIDE）；
 * 2) 预览 Image 用 sourceSize 按目标尺寸解码，避免整张上亿像素图解进内存；
 * 3) 裁剪框坐标（屏幕 vp）与解码像素坐标通过 displayScale（Contain 缩放比）互转，
 *    预览和裁剪用同一套坐标，「框住哪里就裁哪里」才成立；
 * 4) 裁剪比例用物理屏幕宽高比（本项目未发布窗口尺寸键，折叠屏/PC 分屏后续再适配）。
 */
import { common } from '@kit.AbilityKit';
import { fileIo, fileUri, picker } from '@kit.CoreFileKit';
import { display } from '@kit.ArkUI';
import { image } from '@kit.ImageKit';
import { AppState } from '../common/AppState';
import { DataStore } from '../common/DataStore';
import { Wallpaper } from '../common/Wallpaper';
import { WallpaperTone } from '../common/WallpaperTone';
import { PageHeader } from './common/UiKit';
import { WallpaperFill } from './common/WallpaperFill';
import { GlassMaterial } from '../common/GlassMaterial';

/** 裁剪框最小宽度（vp），防止把手把框拖没了 */
const MIN_CROP_WIDTH: number = 80;
/** 解码长边上限（px）：避免超大原图解码失败 / 内存耗尽 */
const MAX_DECODE_LONG_SIDE: number = 2560;

@Component
export struct BackgroundCropPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  /** 灰字广播订阅：颜色表达式需传 this.grayTick 才登记响应式依赖（否则改色不实时刷新） */
  @StorageProp('grayTick') grayTick: number = 0;
  /** 预览图 uri（file:// 沙箱路径） */
  @State srcUri: string = '';
  /** 是否已选到图片 */
  @State hasImage: boolean = false;
  /** 是否正在处理（保存中禁用重复点击） */
  @State busy: boolean = false;
  /** 原图像素尺寸（getImageInfo 只读文件头，不解码整图） */
  @State srcW: number = 0;
  @State srcH: number = 0;
  /**
   * 降采样后的解码尺寸：预览与裁剪都基于它，保证「所见即所裁」。
   * 必须是 @State —— 预览图的 sourceSize 依赖它，普通字段变化不会让 Image 重新求值。
   */
  @State decodedW: number = 0;
  @State decodedH: number = 0;
  /** 预览区实际尺寸（vp，onAreaChange 采集） */
  @State areaWidth: number = 0;
  @State areaHeight: number = 0;
  /** 裁剪框位置/尺寸（vp，预览区坐标系） */
  @State cropX: number = 0;
  @State cropY: number = 0;
  @State cropWidth: number = 0;

  /** 裁剪框宽高比（物理屏幕宽/高） */
  private cropAspectRatio: number = 0.5625;
  /** 图片 Contain 显示缩放比（预览 vp ↔ 解码 px 的换算桥梁） */
  private displayScale: number = 1;
  /** 图片显示区域（vp，预览区坐标系） */
  private displayX: number = 0;
  private displayY: number = 0;
  private displayWidth: number = 0;
  private displayHeight: number = 0;
  /** 沙箱内原图副本路径 */
  private srcPath: string = '';
  /** 手势起始值 */
  private gestureStartX: number = 0;
  private gestureStartY: number = 0;
  private gestureStartWidth: number = 0;

  aboutToAppear(): void {
    this.resolveAspectRatio();
    this.pickImage();
  }

  /** 解析裁剪框的长宽比：物理屏幕宽/高（宽高比与单位无关，px 相除即可） */
  private resolveAspectRatio(): void {
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      if (d.width > 0 && d.height > 0) {
        this.cropAspectRatio = d.width / d.height;
      }
    } catch (e) {
      // 忽略：保留默认 9:16 竖屏比例
    }
  }

  /** 裁剪框高（vp）：宽 ÷ 屏幕比例 */
  private cropHeight(): number {
    return this.cropWidth / this.cropAspectRatio;
  }

  /** 裁剪框最大宽（vp）：不超过图片显示区域 */
  private maxCropWidth(): number {
    return Math.min(this.displayWidth, this.displayHeight * this.cropAspectRatio);
  }

  /** 复位：按 Contain 重算图片显示区域，并把裁剪框置最大、居中 */
  private resetCrop(): void {
    if (this.decodedW <= 0 || this.decodedH <= 0 ||
      this.areaWidth <= 0 || this.areaHeight <= 0) {
      return;
    }
    // 用解码尺寸而非原图尺寸：预览就是按这个尺寸解码出来的，
    // 两边用同一套坐标，「框住哪里就裁哪里」才成立。
    this.displayScale = Math.min(this.areaWidth / this.decodedW,
      this.areaHeight / this.decodedH);
    this.displayWidth = this.decodedW * this.displayScale;
    this.displayHeight = this.decodedH * this.displayScale;
    this.displayX = (this.areaWidth - this.displayWidth) / 2;
    this.displayY = (this.areaHeight - this.displayHeight) / 2;
    const maxWidth: number = this.maxCropWidth();
    this.cropWidth = Math.max(MIN_CROP_WIDTH, maxWidth);
    this.cropX = this.displayX + (this.displayWidth - this.cropWidth) / 2;
    this.cropY = this.displayY +
      (this.displayHeight - this.cropHeight()) / 2;
  }

  /** 解码尺寸就绪后：预览区已量到尺寸就立即布框 */
  private onImageInfoReady(): void {
    if (this.areaWidth > 0 && this.areaHeight > 0) {
      this.resetCrop();
    }
  }

  /** 预览区尺寸变化 → 记录并重新布框 */
  private onPreviewAreaChange(oldValue: Area, newValue: Area): void {
    const rawWidth: Length = newValue.width;
    const rawHeight: Length = newValue.height;
    const width: number = typeof rawWidth === 'number' ? rawWidth : Number.parseFloat(`${rawWidth}`);
    const height: number = typeof rawHeight === 'number' ? rawHeight : Number.parseFloat(`${rawHeight}`);
    if (Number.isNaN(width) || Number.isNaN(height) || width <= 0 || height <= 0) {
      return;
    }
    this.areaWidth = width;
    this.areaHeight = height;
    this.resetCrop();
  }

  // ── 手势：白框拖动（改位置）──
  private onCropBoxGestureStart(event: GestureEvent): void {
    this.gestureStartX = this.cropX;
    this.gestureStartY = this.cropY;
  }

  private onCropBoxGestureUpdate(event: GestureEvent): void {
    const maxX: number = this.displayX + this.displayWidth - this.cropWidth;
    const maxY: number = this.displayY + this.displayHeight - this.cropHeight();
    this.cropX = Math.min(Math.max(this.gestureStartX + event.offsetX, this.displayX),
      Math.max(maxX, this.displayX));
    this.cropY = Math.min(Math.max(this.gestureStartY + event.offsetY, this.displayY),
      Math.max(maxY, this.displayY));
  }

  // ── 手势：圆形把手（改大小）──
  private onHandleGestureStart(event: GestureEvent): void {
    this.gestureStartWidth = this.cropWidth;
  }

  private onHandleGestureUpdate(event: GestureEvent): void {
    const maxWidth: number = this.maxCropWidth();
    const minWidth: number = Math.min(MIN_CROP_WIDTH, maxWidth);
    this.cropWidth = Math.min(Math.max(this.gestureStartWidth + event.offsetX, minWidth),
      maxWidth);
    const h: number = this.cropHeight();
    if (this.cropX + this.cropWidth > this.displayX + this.displayWidth) {
      this.cropX = this.displayX + this.displayWidth - this.cropWidth;
    }
    if (this.cropY + h > this.displayY + this.displayHeight) {
      this.cropY = this.displayY + this.displayHeight - h;
    }
  }

  /** 按长边上限等比算出解码尺寸；原图不超限时就是原尺寸 */
  private computeDecodedSize(): void {
    const longSide: number = Math.max(this.srcW, this.srcH);
    if (longSide <= MAX_DECODE_LONG_SIDE) {
      this.decodedW = this.srcW;
      this.decodedH = this.srcH;
      return;
    }
    const ratio: number = MAX_DECODE_LONG_SIDE / longSide;
    this.decodedW = Math.max(1, Math.round(this.srcW * ratio));
    this.decodedH = Math.max(1, Math.round(this.srcH * ratio));
  }

  /** 选择图片：文档选择器（免相册权限）→ 拷贝到沙箱 → 读原图尺寸 → 进入裁剪 */
  private pickImage(): void {
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const options: picker.DocumentSelectOptions = new picker.DocumentSelectOptions();
      options.maxSelectNumber = 1;
      options.fileSuffixFilters = ['jpg', 'jpeg', 'png', 'webp', 'bmp'];
      const docPicker: picker.DocumentViewPicker = new picker.DocumentViewPicker(ctx);
      docPicker.select(options).then((uris: string[]) => {
        if (uris.length === 0) {
          // 用户取消：直接返回上一页
          AppState.stack.pop();
          return;
        }
        this.loadPicked(uris[0], ctx);
      }).catch(() => {
        this.getUIContext().getPromptAction().showToast({ message: '选择文件失败' });
        AppState.stack.pop();
      });
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '选择文件失败' });
      AppState.stack.pop();
    }
  }

  /** 读取所选图片 → 拷贝进沙箱 → 用 ImageSource 读原图尺寸（不整图解码，开销小） */
  private loadPicked(uri: string, ctx: common.UIAbilityContext): void {
    let srcSrc: image.ImageSource | null = null;
    let probe: fileIo.File | null = null;
    try {
      const pickedPath: string = new fileUri.FileUri(uri).path;
      // 1) 拷贝到沙箱（选择器授权为临时授权，拷贝后读写更稳）
      const srcFile: fileIo.File = fileIo.openSync(pickedPath, fileIo.OpenMode.READ_ONLY);
      const st: fileIo.Stat = fileIo.statSync(pickedPath);
      const buf: ArrayBuffer = new ArrayBuffer(st.size);
      fileIo.readSync(srcFile.fd, buf);
      fileIo.closeSync(srcFile);
      const tmpPath: string = `${ctx.filesDir}/crop_src_${Date.now()}.dat`;
      const dstFile: fileIo.File = fileIo.openSync(tmpPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.READ_WRITE);
      fileIo.writeSync(dstFile.fd, buf);
      fileIo.closeSync(dstFile);
      // 2) 读原图尺寸（getImageInfoSync 只读文件头，不解码整图）
      probe = fileIo.openSync(tmpPath, fileIo.OpenMode.READ_ONLY);
      srcSrc = image.createImageSource(probe.fd);
      const info: image.ImageInfo = srcSrc.getImageInfoSync();
      fileIo.closeSync(probe);
      probe = null;
      const w: number = info.size.width;
      const h: number = info.size.height;
      if (w <= 0 || h <= 0) {
        throw new Error('image size invalid');
      }
      this.cleanupTemp(ctx.filesDir, tmpPath);
      this.srcPath = tmpPath;
      this.srcW = w;
      this.srcH = h;
      this.srcUri = `file://${tmpPath}`;
      this.computeDecodedSize();
      this.onImageInfoReady();
      this.hasImage = true;
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '图片读取失败（格式不支持或文件过大）' });
    } finally {
      if (probe !== null) {
        try {
          fileIo.closeSync(probe);
        } catch (e) {
          // 忽略关闭失败
        }
      }
      if (srcSrc !== null) {
        try {
          srcSrc.release();
        } catch (e) {
          // 忽略释放失败
        }
      }
    }
  }

  /** 清理历史裁剪临时原图（保留 keepPath） */
  private cleanupTemp(filesDir: string, keepPath: string): void {
    try {
      const names: string[] = fileIo.listFileSync(filesDir);
      for (let i = 0; i < names.length; i++) {
        const n: string = names[i];
        if (n.indexOf('crop_src_') !== 0) {
          continue;
        }
        const p: string = `${filesDir}/${n}`;
        if (p === keepPath) {
          continue;
        }
        try {
          fileIo.unlinkSync(p);
        } catch (e) {
          // 单个文件删除失败忽略
        }
      }
    } catch (e) {
      // 目录读取失败忽略
    }
  }

  /** 完成：裁剪框坐标经 displayScale 换算回解码像素 → 裁切 → JPEG 打包 → 本项目壁纸管线 */
  private confirmCrop(): void {
    if (!this.hasImage || this.busy || this.cropWidth <= 0 || this.srcPath.length === 0) {
      return;
    }
    this.busy = true;
    // 屏幕坐标 → 解码像素坐标（预览与裁剪同一套坐标：框住哪里就裁哪里）
    const scale: number = this.displayScale;
    const ix: number = Math.max(0, Math.round((this.cropX - this.displayX) / scale));
    const iy: number = Math.max(0, Math.round((this.cropY - this.displayY) / scale));
    const iw: number = Math.max(1, Math.min(Math.round(this.cropWidth / scale),
      this.decodedW - ix));
    const ih: number = Math.max(1, Math.min(Math.round(this.cropHeight() / scale),
      this.decodedH - iy));
    this.doCrop(ix, iy, iw, ih).then(() => {
      this.busy = false;
    }).catch(() => {
      this.busy = false;
      this.getUIContext().getPromptAction().showToast({ message: '裁剪失败，请重试' });
    });
  }

  /** 真正的裁剪与保存（异步）：解码（限长边）→ crop → 打包 → 壁纸管线 */
  private async doCrop(ix: number, iy: number, iw: number, ih: number): Promise<void> {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const file: fileIo.File = fileIo.openSync(this.srcPath, fileIo.OpenMode.READ_ONLY);
    const src: image.ImageSource = image.createImageSource(file.fd);
    let pm: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      // 关键：按降采样后的尺寸解码，不要用原始尺寸
      //（上亿像素图按原尺寸解码会失败或耗尽内存，背景本来也不需要那么大）
      const opts: image.DecodingOptions = {
        desiredSize: { width: this.decodedW, height: this.decodedH }
      };
      pm = await src.createPixelMap(opts);
      const region: image.Region = { size: { width: iw, height: ih }, x: ix, y: iy };
      await pm.crop(region);
      packer = image.createImagePacker();
      const popts: image.PackingOption = { format: 'image/jpeg', quality: 95 };
      const packed: ArrayBuffer = await packer.packToData(pm, popts);
      // ── 以下为本项目壁纸管线（唯一命名 + 明暗分析 + 清理旧文件）──
      const dstPath: string = Wallpaper.newUserWallpaperPath(ctx.filesDir);
      const out: fileIo.File = fileIo.openSync(dstPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC | fileIo.OpenMode.READ_WRITE);
      fileIo.writeSync(out.fd, packed);
      fileIo.closeSync(out);
      // 明暗分析 → 文字对比度自适应
      WallpaperTone.analyze(packed).then((tone: number) => {
        WallpaperTone.save(tone);
      });
      AppStorage.setOrCreate('wallpaperId', `c:${dstPath}`);
      DataStore.saveWallpaper(`c:${dstPath}`);
      Wallpaper.cleanupUserWallpapers(ctx.filesDir, dstPath);
      this.cleanupTemp(ctx.filesDir, '');
      this.getUIContext().getPromptAction().showToast({ message: '背景已应用' });
      AppState.stack.pop();
    } finally {
      fileIo.closeSync(file);
      try {
        if (pm !== null) {
          await pm.release();
        }
      } catch (e) {
        // 忽略释放失败
      }
      try {
        await src.release();
      } catch (e) {
        // 忽略释放失败
      }
      if (packer !== null) {
        try {
          await packer.release();
        } catch (e) {
          // 忽略释放失败
        }
      }
    }
  }

  /** 清空背景（恢复纯色页面底色，并删除自定义壁纸文件与裁剪临时文件） */
  private clearBackground(): void {
    try {
      const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
      Wallpaper.cleanupUserWallpapers(ctx.filesDir, '');
      this.cleanupTemp(ctx.filesDir, '');
    } catch (e) {
      // 文件不存在等忽略
    }
    AppStorage.setOrCreate('wallpaperId', 'none');
    DataStore.saveWallpaper('none');
    this.getUIContext().getPromptAction().showToast({ message: '已清空背景' });
    AppState.stack.pop();
  }

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        WallpaperFill()
        Column() {
          // 悬浮顶栏让位
          Column().width('100%').height(this.getUIContext().px2vp(this.topInsetPx) + 60)

          // ── 预览区：图片 Contain 居中固定，遮罩/裁剪框/把手叠加其上（移植参考项目）──
          Stack({ alignContent: Alignment.TopStart }) {
            // 等解码尺寸就绪再渲染：首帧 decodedW 还是 0，此时给 sourceSize 传 0
            // 会让解码器无从下手，图照样出不来。
            if (this.hasImage && this.decodedW > 0 && this.decodedH > 0) {
              // sourceSize 让解码器直接按目标尺寸解码，避免整张上亿像素图解进内存
              Image(this.srcUri)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Contain)
                .sourceSize({ width: this.decodedW, height: this.decodedH })
                .draggable(false)
            } else {
              Column() {
                Text(this.busy ? '正在处理…' : '请选择一张图片')
                  .fontSize(14)
                  .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .backgroundColor(this.isDarkModeBg())
            }

            // 遮罩 ×4：上 / 下 / 左 / 右（#66000000，与参考项目一致）
            Column()
              .width('100%')
              .height(this.cropY)
              .backgroundColor('#66000000')

            Column()
              .width('100%')
              .height(Math.max(0, this.areaHeight - this.cropY - this.cropHeight()))
              .position({ x: 0, y: this.cropY + this.cropHeight() })
              .backgroundColor('#66000000')

            Column()
              .width(this.cropX)
              .height(this.cropHeight())
              .position({ x: 0, y: this.cropY })
              .backgroundColor('#66000000')

            Column()
              .width(Math.max(0, this.areaWidth - this.cropX - this.cropWidth))
              .height(this.cropHeight())
              .position({ x: this.cropX + this.cropWidth, y: this.cropY })
              .backgroundColor('#66000000')

            // 白色裁剪框：单指拖动改位置
            Column()
              .width(this.cropWidth)
              .height(this.cropHeight())
              .position({ x: this.cropX, y: this.cropY })
              .border({ width: 2, color: Color.White })
              .gesture(
                PanGesture({ fingers: 1, distance: 1 })
                  .onActionStart((event: GestureEvent) => {
                    this.onCropBoxGestureStart(event);
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    this.onCropBoxGestureUpdate(event);
                  })
              )

            // 圆形把手（右下角）：拖动改大小
            Column()
              .width(32)
              .height(32)
              .borderRadius(16)
              .backgroundColor(Color.White)
              .border({ width: 3, color: $r('app.color.brand') })
              .position({
                x: this.cropX + this.cropWidth - 16,
                y: this.cropY + this.cropHeight() - 16
              })
              .gesture(
                PanGesture({ fingers: 1, distance: 1 })
                  .onActionStart((event: GestureEvent) => {
                    this.onHandleGestureStart(event);
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    this.onHandleGestureUpdate(event);
                  })
              )
          }
          .width('100%')
          .layoutWeight(1)
          .clip(true)
          .onAreaChange((oldValue: Area, newValue: Area) => {
            this.onPreviewAreaChange(oldValue, newValue);
          })

          // ── 底部操作（本项目功能保留：换图 / 复位 / 清空背景）──
          Row({ space: 10 }) {
            Text('重新选择')
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
              .height(38)
              .padding({ left: 16, right: 16 })
              .backgroundColor('rgba(255,255,255,0.55)')
              .borderRadius(19)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.pickImage();
              })
            Text('复位')
              .fontSize(13)
              .fontColor($r('app.color.text_primary'))
              .height(38)
              .padding({ left: 16, right: 16 })
              .backgroundColor('rgba(255,255,255,0.55)')
              .borderRadius(19)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.resetCrop();
              })
            Text('清空背景')
              .fontSize(13)
              .fontColor('#FFFFFF')
              .height(38)
              .padding({ left: 16, right: 16 })
              .backgroundColor('#DB5252')
              .borderRadius(19)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.clearBackground();
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 16 })

          Text('提示：拖动白色框调整裁剪区域，拖动右下角圆形把手调整大小；框内区域即最终背景。')
            .fontSize(11)
            .fontColor(GlassMaterial.grayTertiary(this.grayTick, $r('app.color.text_tertiary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding({ left: 16, right: 16 })
            .margin({ top: 12, bottom: 24 })
        }
        .width('100%')
        .height('100%')

        // ── 顶栏（返回 / 完成）──
        PageHeader({
          title: '裁剪背景',
          subtitle: this.hasImage ? `${this.srcW}×${this.srcH}` : '选择图片后裁剪',
          actionText: this.busy ? '处理中' : '完成',
          actionTone: 'theme',
          onBack: () => {
            try {
              const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
              this.cleanupTemp(ctx.filesDir, '');
            } catch (e) {
              // 忽略
            }
            AppState.stack.pop();
          },
          onAction: () => {
            this.confirmCrop();
          }
        })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
  }

  /** 未选图时的占位底色（深色模式适配） */
  private isDarkModeBg(): ResourceColor {
    const dark: boolean | undefined = AppStorage.get<boolean>('isDarkMode');
    return dark === true ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)';
  }
}
