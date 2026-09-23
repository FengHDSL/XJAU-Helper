/**
 * 沉浸光感承载层（公共组件）
 * —— 逐行照抄参考项目 miha_hm（鸿米家）`components/MaterialCard.ets` 的 `MaterialCardLayer`。
 *
 * 为什么必须用 Toggle 承载（参考 README《沉浸光感（API 26）》+《沉浸光感Toggle承载方案》）：
 * 官方《组件适配沉浸光感》把组件分成两类——
 *   - 按钮与选择类（Button / Select / **Toggle** / Slider / ChipGroup / SegmentButton）
 *     **页面内全部区域**都可生效；
 *   - 其余组件（Column / Row 等布局容器）的通用属性 systemMaterial **只在 Navigation /
 *     NavDestination 标题栏，或 barPosition 为 BarPosition.End 的底部 TabBar 中生效**。
 * 卡片位于 NavDestination 内容区，所以把 systemMaterial 直接挂在 Column/Row 上必然无效。
 *
 * 各 ToggleType 的差异（官方原文）：Checkbox 未适配（设置后无效果）；Switch 的材质参数只是
 * 「开启标记」，只覆盖开关本体那片；**Button 覆盖整块矩形** → 卡片只能用 ToggleType.Button。
 *
 * 承载层五条必需属性（缺一不可）：
 *   ① 尺寸 `LayoutPolicy.matchParent`：卡片高度由内容撑开，父容器 Stack 无确定高度，
 *      写 `height('100%')` 会按「父级可用尺寸」解析并把卡片一起顶大；
 *   ② `borderRadius(layerRadius)`：ToggleType.Button 会画自己的按钮图形（自带一圈小圆角 + 描边），
 *      圆角不透传就会在卡片里出现「更小圆角的内嵌边框」；
 *   ③ `backgroundColor(Color.Transparent)`：沉浸光感的视觉层级位于 backgroundColor 之下，
 *      不透明底色会把材质盖住（叠出灰感甚至完全遮住）；
 *   ④ `enabled(false) / focusable(false) / accessibilityLevel('no') / hitTestBehavior(None)`：
 *      承载层只是画布，不能抢走卡片的点击、焦点与无障碍；
 *   ⑤ `systemMaterial` 必须放在其他样式属性（背景色 / 边框 / 阴影）之后 → 用 attributeModifier
 *      挂在属性链最末（见下方 Toggle 的写法）。
 *
 * 本组件**不**自带沾色层：沾色必须压在材质之上、内容之下，由 `MaterialCard.cardBody()` 统一排层
 * （材质不采样同一 Stack 里的兄弟节点，所以任何贴色/流光都必须独立成层）。
 */
import { applyMaterialCarrier } from '../../common/SystemMaterial';

@Component
export struct MaterialCardLayer {
  /** 与 MaterialCard 的 cardRadius 保持一致，避免出现内嵌的小圆角边框 */
  @Prop layerRadius: Length = 20;
  /**
   * 是否让材质自带投影（`ImmersiveMaterial.applyShadow` 默认 true）。
   * 大卡片保留（投影是加分项）；成排的小卡片传 false——
   * 挨得近时投影会在卡间缝隙里叠成一条暗带，看着像「每张卡背后顶了一层影子」。
   */
  @Prop layerShadow: boolean = true;
  /**
   * **常驻材质**：为 true 时跳过「全局沉浸光感」应用内开关（`immersiveEffect`）的判定，
   * 只要 API≥26、应用级系统状态非 DISABLE 且材质构造成功就下发材质。
   *
   * 用途：顶栏按钮、登录页主按钮等要求「固定有效、不随全局开关关闭而消失」的元素
   * （语义见 `SystemMaterial.materialAvailable()`）。默认 false，行为与改动前完全一致。
   */
  @Prop layerForce: boolean = false;

  build() {
    Toggle({ type: ToggleType.Button, isOn: false })
      .width(LayoutPolicy.matchParent)
      .height(LayoutPolicy.matchParent)
      .borderRadius(this.layerRadius)
      // 必须显式透明：不透明背景色会盖在材质层之上
      .backgroundColor(Color.Transparent)
      .enabled(false)
      .focusable(false)
      .accessibilityLevel('no')
      .hitTestBehavior(HitTestMode.None)
      // systemMaterial 放在所有样式属性之后；材质不可用时由外壳自己降级（毛玻璃/纯色），
      // 所以这里 fallbackBlur 传 false，避免与外壳的 backgroundBlurStyle 叠加。
      .attributeModifier({
        applyNormalAttribute: (instance: ToggleAttribute): void => {
          applyMaterialCarrier(instance, false, false, this.layerShadow, '', this.layerForce);
        }
      })
  }
}
