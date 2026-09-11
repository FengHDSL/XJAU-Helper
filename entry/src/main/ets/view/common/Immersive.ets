/**
 * 沉浸光感工具（无 API 26 依赖的通用实现）
 *
 * 背景：系统沉浸光感材质（@kit.ArkUI 的 uiMaterial / 组件属性 systemMaterial）属 API 26 能力，
 * 在 API < 26 的真机上不可用（调用会抛 "isImmersiveMaterialSupported is not callable" 甚至导致启动失败）。
 * 因此本项目改用通用属性 backgroundBlurStyle（API 9+，全设备可用）实现等效"玻璃"观感。
 */
export class Immersive {
  /**
   * 通用背景模糊：开启时返回指定模糊档位，关闭时返回 BlurStyle.NONE
   * @param style 模糊档位（BlurStyle.Thin / Regular / Thick ...）
   * @param on 应用内开关（个性主题 → 沉浸光感）
   */
  static blur(style: BlurStyle, on: boolean): BlurStyle {
    return on ? style : BlurStyle.NONE;
  }
}
