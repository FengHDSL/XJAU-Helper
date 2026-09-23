/**
 * 材质按钮（圆角 / 胶囊承载按钮）—— 公共组件
 * —— 对应参考项目 miha_hm（鸿米家）README《沉浸光感（API 26）》「按钮的沉浸光感」一节，
 *    以及参考 `components/IconCircleButton.ets`（圆形按钮 = **ToggleType.Button 承载层**
 *    + `SymbolGlyph` 图标叠在承载层之上）。
 *
 * 为什么不能直接给普通 `Button` 挂 `systemMaterial`：官方虽然写了 `Button` 支持沉浸光感，
 * 但**真机实测普通 Button 挂材质不渲染**（HarmonyOS 7.0.0.105 / API 26）；
 * 全仓统一走「透明 Toggle 承载层 + 内容」这条路——与 `MaterialCard` 完全同源。
 * 需要圆形图标按钮时，同样是本组件的形态：承载层画材质，图标/文字叠在内容里。
 *
 * ── 结构（照抄参考 README 的按钮写法）──
 *   Stack {
 *     MaterialCardLayer({ layerRadius })   // Toggle 承载层：只画材质，不参与交互
 *     内容                                   // 叠在材质之上
 *   }
 *
 * ── 两条必须遵守的约定 ──
 *   ① **内容不能自带不透明底色/磨砂**：材质的视觉层级位于 `backgroundColor` /
 *      `backgroundBlurStyle` 之下，内容又是承载层的兄弟节点、画在其上，
 *      任何不透明底都会把材质整块盖住（选中态实底按钮请改走 `btnBg`，并接受「该按钮不显示材质」）；
 *   ② 承载层五条必需属性一条都不能删（见 `view/common/MaterialCarrier.ets`）。
 *
 * ── 尺寸约定 ──
 *   本组件不自带宽高：按钮尺寸由内容撑开（Stack 取最大子节点）。
 *   需要**整宽按钮**时让内容自己写 `width('100%')`；内容**不要写 `height('100%')`**，
 *   百分比高度在 Stack 内按「父级可用尺寸」解析，会把按钮撑满父容器高度
 *   （参考 README《沉浸光感Toggle承载方案》§6）。
 *
 * ── 有色按钮「材质 + 原色」共存（btnTint / btnTintRatio）──
 *   材质生效时承载层会让出底色（不透明底会盖住材质），原来有底色的按钮会变透明、丧失颜色语义。
 *   解法：在**材质承载层之上、内容之下**再叠一层半透明原色（`btnTint` + `btnTintRatio`，
 *   默认 alpha 0.45，按对比度在 0.35–0.6 之间调整）。材质仍照常渲染，颜色也被保留。
 *   「选中态实色」同样走这里：选中时把 `btnTintRatio` 调高（如 0.85～1）即可更实、更醒目。
 *   非材质环境下（材质不可用 / API<26）本层不渲染，按钮自动回落调用方传入的 `btnBg` 实底。
 *
 * ── 常驻材质（btnPersistent）──
 *   顶栏按钮、登录页主按钮等要求「固定生效、不随按压才出现、也不因全局沉浸光感开关关闭而消失」，
 *   传 `btnPersistent: true`：判定走 `materialAvailable()`（忽略应用内全局开关），
 *   语义见 `SystemMaterial.materialAvailable()`；其余按钮保持默认 false（随全局开关回落）。
 *
 * ArkTS：尾随闭包初始化的自定义组件之后不能继续链式加属性
 * （`MaterialButton({...}) { ... }.margin(...)` 会报 “Cannot find name 'margin'”），
 * 所以外边距 / 圆角 / 点击等一律走下面的 `btn*` 参数（与 `MaterialCard` 的 `card*` 约定一致）。
 */
import { isApi26OrAbove, materialActive, materialAvailable } from '../../common/SystemMaterial';
import { MaterialCardLayer } from './MaterialCarrier';

@Component
export struct MaterialButton {
  /** 按钮圆角（胶囊按钮传大值，如 999；与承载层圆角一致，避免出现内嵌小圆角边框） */
  @Prop btnRadius: Length = 17;
  /**
   * 材质自带投影（`ImmersiveMaterial.applyShadow`，系统默认 true）是否保留。
   *
   * 默认 **false**：小按钮尺寸小、挨得近，投影看起来像「按钮背后顶了一层影子」；
   * 大按钮想保留投影时传 true。
   */
  @Prop btnMaterialShadow: boolean = false;
  @Prop btnEnabled: boolean = true;
  /** 材质不可用时的回落底色（材质生效时让出为透明） */
  @Prop btnBg: ResourceColor = Color.Transparent;
  /** 材质不可用时的回落磨砂（材质生效时强制 NONE，避免叠在材质上发灰） */
  @Prop btnBlur: BlurStyle = BlurStyle.NONE;
  /** 材质不可用时的回落边框宽度（材质生效时强制 0） */
  @Prop btnBorderW: number = 0;
  /** 回落边框颜色 */
  @Prop btnBorderC: ResourceColor = Color.Transparent;
  /** 按钮外边距（尾随闭包之后不能再链式写 .margin） */
  @Prop btnMargin: Margin = { top: 0, right: 0, bottom: 0, left: 0 };
  /**
   * 材质之上的**原色叠层**颜色（空串＝不叠加）。用于「材质 + 原有底色」共存的按钮：
   * 材质让出底色后，靠这一层半透明原色保留原本的颜色语义（警示红 / 品牌绿 / 淡红玻璃底等）。
   * 传 `#RRGGBB` 或 `rgba(...)` 字符串（如 `Theme.colorOf(themeColor)` / `'#F0524D'`）。
   */
  @Prop btnTint: string = '';
  /** 原色叠层的不透明度（0~1，默认 0.45）。选中态实色可调高（如 0.85～1）。 */
  @Prop btnTintRatio: number = 0.45;
  /**
   * **常驻材质**：固定生效、不随按压才出现，也不因全局「沉浸光感」开关关闭而消失
   * （判定走 `materialAvailable()`，只受 API / 应用级系统状态 / 构造结果约束）。
   * 顶栏按钮、登录页主按钮等传 true；其余按钮默认 false（随全局开关回落毛玻璃/纯色）。
   */
  @Prop btnPersistent: boolean = false;
  /** 全局沉浸光感开关（登记依赖：拨动开关后已画出的按钮立即重渲染） */
  @StorageProp('immersiveEffect') immersiveEffect: boolean = true;

  /** 对应原有按钮上的 `.onClick()`；空实现即纯展示胶囊 */
  btnOnClick: () => void = (): void => {
  };

  @BuilderParam btnContent: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  /**
   * 材质是否真正生效。两条路径：
   *   - 常驻（btnPersistent=true）：忽略应用内全局开关，只看材质能否下发；
   *   - 普通：应用开关开 + API≥26 + 材质构造成功（与 MaterialCard 同一判定链）。
   */
  private materialEffective(): boolean {
    if (this.btnPersistent) {
      return isApi26OrAbove() && materialAvailable();
    }
    return this.immersiveEffect && isApi26OrAbove() && materialActive();
  }

  /** 原色叠层颜色：显式 btnTint 优先；未传时自动取 btnBg（仅支持 #/rgba/rgb 字符串），实现"材质+原色"自动共存 */
  private autoTint(): string {
    if (this.btnTint.length > 0) {
      return this.btnTint;
    }
    const bg: ResourceColor = this.btnBg;
    const isStr: boolean = typeof bg === 'string';
    const b: string = isStr ? bg as string : '';
    return b.startsWith('#') || b.startsWith('rgba') || b.startsWith('rgb') ? b : '';
  }

  /** 原色叠层不透明度：显式 btnTintRatio 优先；自动取色时用 0.55（保留颜色语义且不盖住材质） */
  private tintRatio(): number {
    return this.btnTint.length > 0 ? this.btnTintRatio : 0.55;
  }

  /** 是否需要画原色叠层（材质生效 + 有可用原色） */
  private tintVisible(): boolean {
    return this.materialEffective() && this.autoTint().length > 0;
  }

  build() {
    Stack() {
      if (this.materialEffective()) {
        MaterialCardLayer({
          layerRadius: this.btnRadius,
          layerShadow: this.btnMaterialShadow,
          layerForce: this.btnPersistent
        })
      }
      // 原色叠层：压在材质之上、内容之下，材质照常可见、颜色语义得以保留（比例见 btnTintRatio）
      if (this.tintVisible()) {
        Column()
          .width(LayoutPolicy.matchParent)
          .height(LayoutPolicy.matchParent)
          .borderRadius(this.btnRadius)
          .backgroundColor(this.autoTint())
          .opacity(this.tintRatio())
          .hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no')
      }
      this.btnContent()
    }
    .margin(this.btnMargin)
    .borderRadius(this.btnRadius)
    // 材质生效时让出底色与磨砂（不透明底会盖住材质），否则用调用方传入的玻璃底兜底
    .backgroundColor(this.materialEffective() ? Color.Transparent : this.btnBg)
    .backgroundBlurStyle(this.materialEffective() ? BlurStyle.NONE : this.btnBlur)
    .border({ width: this.materialEffective() ? 0 : this.btnBorderW, color: this.btnBorderC })
    .clip(true)
    .enabled(this.btnEnabled)
    .onClick(() => {
      this.btnOnClick();
    })
  }
}
