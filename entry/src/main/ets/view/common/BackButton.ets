/**
 * 官方风格圆形返回按钮：沉浸光感承载（**常驻**）+ 白色左箭头
 * 用于各页顶栏返回（替代纯文本 '‹'），浅/深色主题渐变顶栏上均可见。
 *
 * 材质承载走 `MaterialCardLayer`（透明 Toggle 承载层，`layerForce:true` 常驻）：
 * - 材质可用 → 只渲染沉浸光感材质（底色/磨砂/亮边全部让出）；
 * - 材质不可用（API<26 / 构造失败）→ 回落原来的半透明白玻璃圆底 + 磨砂 + 亮边。
 * 常驻语义：不随应用内「全局沉浸光感」开关关闭而消失（顶栏按钮固定有光感）。
 */
import { WallpaperTone } from '../../common/WallpaperTone';
import { GlassMaterial } from '../../common/GlassMaterial';
import { MaterialCardLayer } from './MaterialCarrier';
import { materialAvailable } from '../../common/SystemMaterial';

@Component
export struct BackButton {
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageProp('wallpaperTone') wallpaperTone: number = -1;
  /** 沉浸光感：材质不可用时的磨砂回落随该开关 */
  @StorageProp('immersiveEffect') immersiveEffect: boolean = false;
  /** 返回回调（默认 pop，由调用页决定） */
  onBack: () => void = () => {
  };

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 沉浸光感承载层（常驻：材质可用即下发）
      if (materialAvailable()) {
        MaterialCardLayer({ layerRadius: 17, layerShadow: false, layerForce: true })
      }
      Image($r('app.media.back_arrow'))
        .width(18)
        .height(18)
        .fillColor(WallpaperTone.onWallpaper(this.wallpaperTone, this.isDarkMode))
    }
    .width(34)
    .height(34)
    .borderRadius(17)
    // 材质生效时让出底色/磨砂/亮边（材质优先级最高）；否则回落玻璃胶囊
    .backgroundColor(materialAvailable() ? Color.Transparent : GlassMaterial.surface(this.isDarkMode))
    .backgroundBlurStyle(materialAvailable() ? BlurStyle.NONE
      : GlassMaterial.bgBlur(this.immersiveEffect), GlassMaterial.blurOptions())
    .border({
      width: materialAvailable() ? 0 : GlassMaterial.borderWidth(),
      color: GlassMaterial.borderColor()
    })
    .shadow(GlassMaterial.capsuleShadow()).clip(true)
    .onClick(() => {
      this.onBack();
    })
  }
}
