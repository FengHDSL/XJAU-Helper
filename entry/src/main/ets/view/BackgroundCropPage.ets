/**
 * 背景裁剪页（外观设置 → 背景 → 更换背景）
 * —— 移植自参考项目 miha_hm（鸿米家）`pages/BackgroundCropPage.ets`
 * 对应参考文件：miha_hm `pages/BackgroundCropPage.ets`
 *
 * 核心闭环：选图 → 缩放/平移 → 完成（按屏幕比例裁剪并保存为全局壁纸）。
 *
 * 实现要点（踩坑说明）：
 * 1) 相册原图可达上亿像素，**按原始尺寸解码会失败/耗尽内存**（表现为预览空白）
 *    → 解码时用 `desiredSize` 把长边限制在 MAX_DECODE_LONG_SIDE，并保持比例；
 * 2) 裁剪框用「屏幕宽高比」的固定框，图片以 `ImageFit.Cover` 铺底再叠加缩放/平移，
 *    这样「裁剪框 → 原图像素」是纯比例换算，稳定可控；
 * 3) 裁剪用 `pixelMap.cropSync()`（API 12+）+ `ImagePacker.packToData(jpeg, 95)`，
 *    写回 `filesDir` 唯一命名的壁纸文件（复用 Wallpaper 工具，避免同路径缓存不刷新）。
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

/** 裁剪区域（原图像素坐标系） */
interface CropBox {
  x: number;
  y: number;
  w: number;
  h: number;
}

/** 尺寸（像素） */
interface Size2D {
  width: number;
  height: number;
}

/** 最大解码长边（px）：避免超大原图解码失败 / 内存耗尽 */
const MAX_DECODE_LONG_SIDE: number = 2560;
/** 最小 / 最大缩放（1 = 铺满裁剪框） */
const MIN_ZOOM: number = 1;
const MAX_ZOOM: number = 5;
/** 裁剪框距屏幕两侧留白（vp） */
const FRAME_MARGIN: number = 20;

@Component
export struct BackgroundCropPage {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  /** 预览图 uri（file://沙箱路径） */
  @State srcUri: string = '';
  /** 是否已选到图片 */
  @State hasImage: boolean = false;
  /** 缩放倍数 */
  @State zoom: number = MIN_ZOOM;
  /** 缩放滑条数值（= zoom × 100；用 state 保证「复位」时滑条同步回位） */
  @State sliderVal: number = MIN_ZOOM * 100;
  /** 平移量（vp） */
  @State tx: number = 0;
  @State ty: number = 0;
  /** 是否正在处理（裁剪保存中禁用重复点击） */
  @State busy: boolean = false;

  /** 沙箱内原图副本路径 */
  private srcPath: string = '';
  /** 原图像素尺寸 */
  private srcW: number = 0;
  private srcH: number = 0;
  /** 裁剪框实际尺寸（vp，onAreaChange 采集） */
  private frameW: number = 0;
  private frameH: number = 0;
  /** 手势起始值 */
  private startTx: number = 0;
  private startTy: number = 0;
  private startZoom: number = MIN_ZOOM;

  aboutToAppear(): void {
    this.pickImage();
  }

  /** 裁剪框宽高比（屏幕宽/高；异常回落 9:16 竖屏） */
  /** 裁剪框宽高比（改名避开 CustomComponent 自带属性 aspectRatio，否则 10505001 类型冲突） */
  private cropAspect(): number {
    try {
      const d: display.Display = display.getDefaultDisplaySync();
      const w: number = this.getUIContext().px2vp(d.width);
      const h: number = this.getUIContext().px2vp(d.height);
      if (w > 0 && h > 0) {
        return w / h;
      }
    } catch (e) {
      // 忽略：回落默认比例
    }
    return 0.5625;
  }

  /** Length → number（vp；非数值回落 0） */
  private toNum(v: Length): number {
    const n: number = Number.parseFloat(`${v}`);
    return isNaN(n) ? 0 : n;
  }

  /**
   * Cover 铺底尺寸（vp）：图片以 ImageFit.Cover 铺满裁剪框后的显示尺寸。
   * 返回 [width, height]，未就绪返回 [0, 0]。
   */
  private coverBase(): number[] {
    if (this.frameW <= 0 || this.frameH <= 0 || this.srcW <= 0 || this.srcH <= 0) {
      return [0, 0];
    }
    const s: number = Math.max(this.frameW / this.srcW, this.frameH / this.srcH);
    return [this.srcW * s, this.srcH * s];
  }

  /** 平移量夹紧：保证图片始终铺满裁剪框（不出现空白边） */
  private clampOffsets(): void {
    const base: number[] = this.coverBase();
    const bw: number = base[0] * this.zoom;
    const bh: number = base[1] * this.zoom;
    const mx: number = Math.max(0, (bw - this.frameW) / 2);
    const my: number = Math.max(0, (bh - this.frameH) / 2);
    this.tx = Math.max(-mx, Math.min(mx, this.tx));
    this.ty = Math.max(-my, Math.min(my, this.ty));
  }

  /** 设置缩放（夹紧到 [MIN_ZOOM, MAX_ZOOM]；平移量按比例同步，避免缩放后跳位） */
  private setZoom(z: number): void {
    const old: number = this.zoom;
    const nz: number = Math.max(MIN_ZOOM, Math.min(MAX_ZOOM, z));
    if (nz === old) {
      return;
    }
    const k: number = nz / old;
    this.zoom = nz;
    this.sliderVal = nz * 100;
    this.tx = this.tx * k;
    this.ty = this.ty * k;
    this.clampOffsets();
  }

  /** 复位（缩放 1、居中） */
  private resetCrop(): void {
    this.zoom = MIN_ZOOM;
    this.sliderVal = MIN_ZOOM * 100;
    this.tx = 0;
    this.ty = 0;
  }

  /**
   * 裁剪框对应的原图像素区域。
   * 推导：显示尺寸 = Cover 尺寸 × zoom；左边界 = (框宽 - 显示宽)/2 + tx；
   * 于是框内 (0,0) 对应原图 x = (0 - 左边界) / 显示宽 × 原图宽。
   */
  private cropBox(): CropBox {
    const base: number[] = this.coverBase();
    const bw: number = base[0] * this.zoom;
    const bh: number = base[1] * this.zoom;
    if (bw <= 0 || bh <= 0 || this.srcW <= 0 || this.srcH <= 0) {
      return { x: 0, y: 0, w: 0, h: 0 };
    }
    const left: number = (this.frameW - bw) / 2 + this.tx;
    const top: number = (this.frameH - bh) / 2 + this.ty;
    let w: number = this.frameW / bw * this.srcW;
    let h: number = this.frameH / bh * this.srcH;
    w = Math.min(w, this.srcW);
    h = Math.min(h, this.srcH);
    let x: number = (0 - left) / bw * this.srcW;
    let y: number = (0 - top) / bh * this.srcH;
    x = Math.max(0, Math.min(this.srcW - w, x));
    y = Math.max(0, Math.min(this.srcH - h, y));
    const box: CropBox = { x: x, y: y, w: w, h: h };
    return box;
  }

  /** 解码尺寸（长边限制在 MAX_DECODE_LONG_SIDE 内，保持比例） */
  private decodeSize(): Size2D {
    const w: number = this.srcW;
    const h: number = this.srcH;
    const long: number = Math.max(w, h);
    if (long <= MAX_DECODE_LONG_SIDE) {
      const same: Size2D = { width: w, height: h };
      return same;
    }
    const k: number = MAX_DECODE_LONG_SIDE / long;
    const small: Size2D = {
      width: Math.max(1, Math.round(w * k)),
      height: Math.max(1, Math.round(h * k))
    };
    return small;
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
      this.resetCrop();
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

  /** 完成：解码（限长边）→ 按裁剪框裁切 → JPEG 打包 → 写入壁纸文件 → 应用 */
  private confirmCrop(): void {
    if (!this.hasImage || this.srcPath.length === 0 || this.busy) {
      return;
    }
    this.busy = true;
    const box: CropBox = this.cropBox();
    if (box.w <= 0 || box.h <= 0) {
      this.busy = false;
      this.getUIContext().getPromptAction().showToast({ message: '裁剪区域无效，请调整后重试' });
      return;
    }
    this.doCrop(box).then(() => {
      this.busy = false;
    }).catch(() => {
      this.busy = false;
      this.getUIContext().getPromptAction().showToast({ message: '裁剪失败，请重试' });
    });
  }

  /** 真正的裁剪与保存（异步） */
  private async doCrop(box: CropBox): Promise<void> {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    const dec: Size2D = this.decodeSize();
    const file: fileIo.File = fileIo.openSync(this.srcPath, fileIo.OpenMode.READ_ONLY);
    const src: image.ImageSource = image.createImageSource(file.fd);
    let pm: image.PixelMap | null = null;
    let packer: image.ImagePacker | null = null;
    try {
      const opts: image.DecodingOptions = {
        desiredSize: { width: dec.width, height: dec.height }
      };
      pm = await src.createPixelMap(opts);
      const info: image.ImageInfo = await pm.getImageInfo();
      // 实际解码尺寸可能因解码器取整略有差异 → 用实际尺寸换算裁剪区域
      const aw: number = info.size.width;
      const ah: number = info.size.height;
      const sx: number = aw / this.srcW;
      const sy: number = ah / this.srcH;
      let rw: number = Math.max(1, Math.round(box.w * sx));
      let rh: number = Math.max(1, Math.round(box.h * sy));
      let rx: number = Math.round(box.x * sx);
      let ry: number = Math.round(box.y * sy);
      rx = Math.max(0, Math.min(aw - 1, rx));
      ry = Math.max(0, Math.min(ah - 1, ry));
      rw = Math.min(rw, aw - rx);
      rh = Math.min(rh, ah - ry);
      if (rw < 1 || rh < 1) {
        throw new Error('crop region invalid');
      }
      pm.cropSync({ x: rx, y: ry, size: { width: rw, height: rh } });
      packer = image.createImagePacker();
      const popts: image.PackingOption = { format: 'image/jpeg', quality: 95 };
      const packed: ArrayBuffer = await packer.packToData(pm, popts);
      // 写入唯一命名壁纸文件（避免同路径覆盖导致界面不刷新）
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

          // ── 裁剪区（屏幕比例固定框；图片 Cover 铺底 + 缩放/平移）──
          Stack() {
            if (this.hasImage) {
              Image(this.srcUri)
                .width('100%')
                .height('100%')
                .objectFit(ImageFit.Cover)
                .scale({ x: this.zoom, y: this.zoom })
                .translate({ x: this.tx, y: this.ty })
                .draggable(false)
            } else {
              Column() {
                Text(this.busy ? '正在处理…' : '请选择一张图片')
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .backgroundColor(this.isDarkModeBg())
            }
          }
          .width('100%')
          .aspectRatio(this.cropAspect())
          .clip(true)
          .borderRadius(16)
          .border({ width: 2, color: 'rgba(255,255,255,0.65)' })
          .onAreaChange((oldValue: Area, newValue: Area) => {
            this.frameW = this.toNum(newValue.width);
            this.frameH = this.toNum(newValue.height);
            this.clampOffsets();
          })
          .gesture(
            GestureGroup(GestureMode.Parallel,
              PanGesture({ fingers: 1, direction: PanDirection.All, distance: 1 })
                .onActionStart(() => {
                  this.startTx = this.tx;
                  this.startTy = this.ty;
                })
                .onActionUpdate((event: GestureEvent) => {
                  this.tx = this.startTx + event.offsetX;
                  this.ty = this.startTy + event.offsetY;
                  this.clampOffsets();
                }),
              PinchGesture({ fingers: 2 })
                .onActionStart(() => {
                  this.startZoom = this.zoom;
                })
                .onActionUpdate((event: GestureEvent) => {
                  this.setZoom(this.startZoom * event.scale);
                })
            )
          )
          .margin({ left: FRAME_MARGIN, right: FRAME_MARGIN })

          // ── 缩放滑条（1.0x ~ 5.0x）──
          Row() {
            Text('缩放')
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width(36)
            Slider({
              value: this.sliderVal,
              min: MIN_ZOOM * 100,
              max: MAX_ZOOM * 100,
              step: 1,
              style: SliderStyle.OutSet
            })
              .selectedColor($r('app.color.brand'))
              .trackColor('rgba(255,255,255,0.35)')
              .layoutWeight(1)
              .onChange((value: number, mode: SliderChangeMode) => {
                this.setZoom(value / 100);
              })
            Text(`${this.zoom.toFixed(1)}x`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .width(44)
              .textAlign(TextAlign.End)
          }
          .width('100%')
          .padding({ left: FRAME_MARGIN, right: FRAME_MARGIN })
          .margin({ top: 14 })

          // ── 操作区 ──
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

          Text('提示：拖动图片平移位置，双指捏合或拖动滑条缩放；框内区域即最终背景。')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .textAlign(TextAlign.Center)
            .width('100%')
            .padding({ left: FRAME_MARGIN, right: FRAME_MARGIN })
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
