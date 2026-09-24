/**
 * 材质卡片与流光层 —— 忠实移植自参考项目 miha_hm（鸿米家）`components/MaterialCard.ets`
 * 对应参考文件：miha_hm `components/MaterialCard.ets`
 *   （MaterialCardLayer / MaterialCard / 流光层 / MaterialSheetPanel）
 *
 * 本文件提供三件东西：
 *   1) `MaterialCard`：沉浸材质 + 卡片沾色 + 按压流光的通用卡片容器（自带触摸跟踪）；
 *   2) `MaterialSheetPanel`：半模态（bindSheet）内容面板（材质 + 圆角，配合 backgroundColor 透明）；
 *   3) `GLOW_RADIUS`：跟手光斑半径常量（首页的页面级流光复用同一取值）。
 *
 * ── 层级（照抄参考 cardBody，自下而上）──
 *   [溢出光晕] → [材质承载层 MaterialCardLayer] → [沾色层] → [跟手光斑] → [内容]
 *   四条硬规则（参考 README《沉浸光感（API 26）》与《沉浸光感Toggle承载方案》§5）：
 *     ① 材质的视觉层级位于 backgroundColor / backgroundBlurStyle 等属性**之下** →
 *        承载层显式 Color.Transparent，外壳底色也让出；
 *     ② systemMaterial 要放在其他样式属性之后 → 承载层用 attributeModifier 挂在属性链最末；
 *     ③ 材质**不采样同一 Stack 里的兄弟节点** → 沾色 / 流光只能压在材质**之上**，
 *        不能指望穿过去被玻璃折射；
 *     ④ 材质生效时卡片只有一层可见材质（就是沉浸光感本身），内容在其上，不会出现两层卡片。
 *
 * ── 材质生效时的让出规则（全集中在 shell* 三个方法里）──
 *   外壳底色 → Color.Transparent；外壳磨砂 → BlurStyle.NONE；外壳边框 → 0；外壳阴影 → 无。
 *   材质不可用时全部回落调用方传入的 cardBg / cardBlur / cardBorderW / cardShadow（纯色或毛玻璃）。
 *
 * ── 参数（照抄参考；外观参数沿用本项目 GlassMaterial 体系，由调用方在构造时传入）──
 *   结构 / 间距：cardWidth / cardPadding / cardMargin / cardDirection / cardSpace / cardAlignItems
 *   行为：cardEnabled / cardOpacity / cardFocusable / cardHoverEffect / cardOnClick / cardGlow
 *   材质：cardRadius / cardMaterialEnabled / cardMaterialShadow
 *   外观：cardBg / cardBlur / cardBorderW / cardBorderC / cardShadow
 *
 * ArkTS 约束（参考 README「卡片迁移约定」）：**尾随闭包初始化的自定义组件之后不能继续链式加属性**
 * （`MaterialCard({...}) { ... }.onClick(...)` 会报 “Cannot find name 'onClick'”），
 * 所以原卡片容器上的 margin / padding / 点击 等一律走上面的 card* 参数。
 */
import { LengthMetrics } from '@kit.ArkUI';
import { isApi26OrAbove, materialActive, materialAvailable, pressLightColor } from '../../common/SystemMaterial';
import { GlassMaterial } from '../../common/GlassMaterial';
import { Theme } from '../../common/ThemeUtil';
import { AppearanceStore } from '../../common/AppearanceStore';
import { MaterialCardLayer } from './MaterialCarrier';
import { MaterialButton } from './MaterialButton';

/**
 * 流光光晕的半径（vp）。
 *
 * 流光不是描边：它是**跟着手指走的一小团柔光**（HdsTab 那种），
 * 半径必须收着给——130 那种尺寸会盖住大半张卡片，看起来像「整卡高亮选」；
 * 64 大致是一枚指腹的范围。首页的页面级流光复用同一取值。
 */
export const GLOW_RADIUS: number = 64;
/**
 * 光晕中心浓度。光本身不该是一块实色：压到 0.3 出头是「照亮玻璃表面」，
 * 再浓就变成往卡片上刷了一层主题色。
 */
const PRESS_GLOW_ALPHA: number = 0.32;
/**
 * 溢出光晕的半径与浓度（vp）。
 *
 * 这层是**卡片外**那圈光：它铺到相邻卡片的边缘上，隔着对方的玻璃透出来，
 * 看起来就是「光打在邻卡边缘的反光」。刻意**不抬高 zIndex**，
 * 让后画的相邻卡片盖住它——盖住之后只剩透过玻璃的一点亮度。
 */
const PRESS_SPILL_RADIUS: number = 110;
const PRESS_SPILL_ALPHA: number = 0.14;
/** 溢出光晕的画布边长：必须 ≥ 2×半径，否则光斑被画布直边切断 */
const PRESS_SPILL_SIZE: number = PRESS_SPILL_RADIUS * 2;
/** 无阴影（默认值，也用于材质生效时让出阴影） */
const NO_SHADOW: ShadowOptions = { radius: 0, color: 'rgba(0,0,0,0)', offsetX: 0, offsetY: 0 };

/**
 * 沉浸光感卡片容器。
 *
 * 材质渲染区域由**承载层**决定（承载层用 matchParent 铺满整卡），外壳刻意**不设 clip(true)**：
 * 溢出光晕要漏到卡片外面去，clip 会把它整圈切掉。需要裁切的每一层都自己带圆角
 * （材质层 layerRadius、沾色层/跟手光斑 cardRadius），效果等价。
 */
@Component
export struct MaterialCard {
  // ── 外观（本项目 GlassMaterial 体系；由调用方在构造时传入）──
  /** 卡片圆角（须与承载层圆角一致，否则出现内嵌小圆角边框） */
  @Prop cardRadius: Length = 20;
  /** 卡片底色（材质生效时让出为透明） */
  @Prop cardBg: ResourceColor = Color.Transparent;
  /**
   * 卡片磨砂。材质生效时强制 NONE（BlurStyle 的层级同样在材质之上，叠加会发灰）；
   * 不生效时用调用方传入的值（纯色卡片传 NONE，毛玻璃回退传 Thin）。
   */
  @Prop cardBlur: BlurStyle = BlurStyle.NONE;
  /** 卡片边框宽度（材质生效时强制 0） */
  @Prop cardBorderW: number = 0;
  /** 卡片边框颜色 */
  @Prop cardBorderC: ResourceColor = Color.Transparent;
  /** 卡片阴影（材质生效时让出，材质自带的投影由 cardMaterialShadow 控制） */
  @Prop cardShadow: ShadowOptions = { radius: 0, color: 'rgba(0,0,0,0)', offsetX: 0, offsetY: 0 };

  // ── 结构 / 间距（参数名与语义照抄参考 MaterialCard）──
  @Prop cardWidth: Length = '100%';
  /**
   * 卡片内容内边距。
   *
   * 刻意**不用 `Padding | Length` 这类联合类型**：ArkTS 无法为联合类型中的对象字面量定类型，
   * 传 `{ top: 12, bottom: 12 }` 会报 `arkts-no-untyped-obj-literals`。
   * 注意：padding 挂在**内部内容容器**上，卡片外层不再有 padding，
   * 承载层才能铺满整张卡片（含原 padding 区域）。
   */
  @Prop cardPadding: Length = 0;
  /** 卡片外边距——卡片之间的间距走这里（尾随闭包之后不能再链式写 .margin） */
  @Prop cardMargin: Margin = { top: 0, right: 0, bottom: 0, left: 0 };
  /** 内容主轴方向（原容器是 Row 时必须传 FlexDirection.Row，否则布局语义改变） */
  @Prop cardDirection: FlexDirection = FlexDirection.Column;
  /** 子元素主轴间距（vp），对应原容器 Row/Column 的 space 参数 */
  @Prop cardSpace: number = 0;
  /**
   * 子元素在交叉轴上的对齐方式。默认 ItemAlign.Center，对齐原 Row(VerticalAlign.Center)
   * 与 Column(HorizontalAlign.Center) 的默认行为——Flex 的默认值是 ItemAlign.Start，
   * 不显式指定会让卡片内容贴顶/贴左。
   */
  @Prop cardAlignItems: ItemAlign = ItemAlign.Center;

  // ── 行为（原卡片容器上这些属性同样不能链式补写）──
  @Prop cardEnabled: boolean = true;
  @Prop cardOpacity: number = 1;
  @Prop cardFocusable: boolean = false;
  @Prop cardHoverEffect: HoverEffect = HoverEffect.None;
  /** 对应原卡片容器上的 .onClick() */
  cardOnClick: () => void = (): void => {
  };
  /**
   * 对应原卡片容器上的 .onLongPress()：长按触发（日志页长按日志卡进入多选）。
   * 用 `.gesture(LongPressGesture())` 实现，与 `cardOnClick` 的点击互不影响。
   */
  cardOnLongPress: () => void = (): void => {
  };

  // ── 材质 ──
  /** 本卡是否承载沉浸光感（滚动长列表内可传 false 省性能） */
  @Prop cardMaterialEnabled: boolean = true;
  /** 材质自带投影是否保留：大卡片 true；成排小卡片 false（见 MaterialCardLayer.layerShadow） */
  @Prop cardMaterialShadow: boolean = true;
  /**
   * 本卡是否允许按压流光。首页把流光交给**页面级**跟手层统一绘制，
   * 所以首页每张卡片都传 false，避免与页面级光斑重复。
   */
  @Prop cardGlow: boolean = true;
  /**
   * 材质之上的**原色叠层**颜色（空串＝不叠加）。用于「材质 + 原有底色」共存的卡片：
   * 材质生效时外壳底色被让出，原来有底色的卡片（警示红卡 / 品牌绿卡 / 淡红玻璃底卡等）
   * 靠这一层半透明原色保留颜色语义。传 `#RRGGBB` 或 `rgba(...)` 字符串。
   */
  @Prop cardTintOverlay: string = '';
  /** 原色叠层的不透明度（0~1，默认 0.45，按对比度在 0.35–0.6 之间调整） */
  @Prop cardTintOverlayRatio: number = 0.45;
  /**
   * **常驻材质**：忽略应用内全局沉浸光感开关（`immersiveEffect`），固定下发材质。
   * 语义见 `SystemMaterial.materialAvailable()`；默认 false，行为与改动前一致。
   */
  @Prop cardPersistent: boolean = false;

  // ── 订阅（决定本卡片是否需要重渲染）──
  /** 全局沉浸光感开关（外观设置主开关） */
  @StorageProp('immersiveEffect') immersiveEffect: boolean = false;
  /**
   * 主题色流光开关（只用来建立依赖）。
   *
   * 真正取色走 `pressLightColor()`（纯函数）。ArkUI 按表达式登记依赖：不声明这个订阅键，
   * 拨动开关时已经画出来的卡片不会重新求值，光晕要等下一次重建才生效。
   */
  @StorageProp('immersivePressGlow') pressGlowSwitch: boolean = true;
  /** 卡片流光触感：关＝按压卡片一点光都不出现（两层一起不亮） */
  @StorageProp('cardGlowTouch') glowTouchEnabled: boolean = true;
  /** 卡片沾色开关 */
  @StorageProp('cardTint') cardTintOn: boolean = false;
  /**
   * 卡片沾色底色（广播键，空串＝沾色关闭）。
   *
   * 非材质路径的外壳底色不能只依赖 @Prop cardBg：它是父组件 build 时
   * 由 `GlassMaterial.homeCardBg()` 算出的**静态值**，父组件的表达式
   * （`cardBg: GlassMaterial.homeCardBg(...)`）不读任何状态，拨动沾色开关
   * 后父组件不会重算。广播键由 `AppearanceStore.broadcastDerived()` 在
   * 开关/主题/深色变化时重写，本卡订阅后即时刷新（参考项目 DesignTokens 机制）。
   */
  @StorageProp('cardTintBg') tintBg: string = '';
  /** 当前主题色（流光/沾色取色用） */
  @StorageProp('themeColor') themeColor: string = 'green';

  /**
   * 流光状态。`glowOn` 手指是否落在卡片上，`glowX/glowY` 光斑中心（相对卡片左上角，vp）。
   * 用 @State：它们是渲染属性，必须触发重绘才会出现、移动、消失。
   */
  @State glowOn: boolean = false;
  @State glowX: number = 0;
  @State glowY: number = 0;
  /**
   * 坐标换算用的一组普通字段（不参与渲染，所以不用 @State）。
   *
   * 光要跟着手指在屏幕上走，而触摸事件给的是窗口坐标：必须减去卡片自身在窗口中的原点
   * 才能换算成卡片内坐标。
   *   - `cardWinX/Y`：卡片左上角在窗口中的位置。按下那一瞬由 `windowX - x` 反推得到
   *     （这时组件内坐标一定是准的），之后靠 `onAreaChange` 的**位移增量**维护——
   *     列表滚动时卡片在动，增量必须跟上，否则手指不动、页面滚动，光斑会黏在卡片原处。
   *   - `lastTouchWinX/Y`：最近一次触摸的窗口坐标，卡片位置变了要拿它重算。
   *   - `lastAreaX/Y` + `areaReady`：上一次 onAreaChange 报的全局坐标，用来求增量。
   *     只取增量、不用绝对值：`globalPosition` 的原点与 `windowX/Y` 未必是同一套，
   *     但两者在滚动中的**变化量**必然一致。
   */
  private cardWinX: number = 0;
  private cardWinY: number = 0;
  private lastTouchWinX: number = 0;
  private lastTouchWinY: number = 0;
  private lastAreaX: number = 0;
  private lastAreaY: number = 0;
  private areaReady: boolean = false;

  @BuilderParam cardContent: () => void = this.emptyContent;

  @Builder
  emptyContent() {
  }

  /** 沉浸光感是否真正生效：本卡允许承载 + 应用开关开 + API≥26 + 材质构造成功 */
  private materialEffective(): boolean {
    if (!this.cardMaterialEnabled || !isApi26OrAbove()) {
      return false;
    }
    // 常驻卡（cardPersistent）：忽略应用内全局开关，只看材质能否下发
    if (this.cardPersistent) {
      return materialAvailable();
    }
    return this.immersiveEffect && materialActive();
  }

  /**
   * 是否用「主题色流光」替代系统的白色按压高亮。要求三件事同时成立：
   * 本卡承载材质、开了主题色流光开关、能取到主题色。任一条不成立就沿用原行为。
   */
  private themedLightAvailable(): boolean {
    return this.materialEffective()
      && pressLightColor(this.pressGlowSwitch, Theme.colorOf(this.themeColor)).length > 0;
  }

  /** 主题色流光当前是否可用（主题色 + 开关 + 材质都在）。空串表示不可用 */
  private glowAccent(): string {
    if (!this.cardEnabled || !this.themedLightAvailable()) {
      return '';
    }
    return pressLightColor(this.pressGlowSwitch, Theme.colorOf(this.themeColor));
  }

  /** 是否有光可画（按下 + 主题色流光可用） */
  private glowVisible(): boolean {
    return this.glowOn && this.glowAccent().length > 0;
  }

  /**
   * 「卡片流光触感」关闭时，按压卡片**一点光都不出现**——跟手光斑与溢出到卡间缝隙的环境光
   * 都不画。两层要么一起亮，要么一起不亮（只关一层的话，环境光圆心本来就跟着手指走，
   * 看起来仍是触碰反馈，开关等于没生效）。
   */
  private spillVisible(): boolean {
    return this.glowVisible() && this.glowTouchEnabled && this.cardGlow;
  }

  /** 是否画手指底下的跟手光斑：同样要求「卡片流光触感」与「本卡流光」都打开 */
  private touchGlowVisible(): boolean {
    return this.glowVisible() && this.glowTouchEnabled && this.cardGlow;
  }

  /**
   * 实际下发的悬停/按压效果。主题色流光可用时**必须把 HoverEffect.Highlight 摘掉**：
   * 那是系统画的一层白光，会和主题色流光同时出现，颜色对不上。
   * 判定只看「流光可不可用」，不能掺进按压状态——否则按下瞬间状态一变、白光又会闪一下。
   */
  private effectiveHoverEffect(): HoverEffect {
    return this.themedLightAvailable() ? HoverEffect.None : this.cardHoverEffect;
  }

  /**
   * 跟手滑动的流光。
   *
   * 触摸坐标用 `touches[0]` 的窗口坐标：它相对整个窗口，减去卡片自身在窗口中的原点
   * 就是光晕层要用的卡片内坐标（光晕锚点贴在卡片左上角）。
   * Move 也要处理：流光之所以像「光」而不像「按下高亮」，就在于手指滑动时它会跟着走。
   * 抬起与取消都必须熄灭，否则会在卡片上留一块不会消失的光斑。
   */
  private updatePressGlow(event: TouchEvent): void {
    if (this.glowAccent().length === 0) {
      return;
    }
    if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.glowOn = false;
      return;
    }
    if (event.type !== TouchType.Down && event.type !== TouchType.Move) {
      return;
    }
    if (event.touches.length === 0) {
      return;
    }
    const touch: TouchObject = event.touches[0];
    if (event.type === TouchType.Down) {
      // 按下这一瞬 x/y 一定是相对当前卡片位置的准确值，用它反推卡片原点
      this.cardWinX = touch.windowX - touch.x;
      this.cardWinY = touch.windowY - touch.y;
    }
    this.lastTouchWinX = touch.windowX;
    this.lastTouchWinY = touch.windowY;
    this.syncGlowPosition();
    this.glowOn = true;
  }

  /**
   * 用最近一次触摸的窗口坐标重算光斑位置。
   * 手指不动、页面在滚时也要调用它（onAreaChange 里同样会调），
   * 这正是「光效追随手指」与「卡片自己移动了但手指没动」两种情况的分界。
   */
  private syncGlowPosition(): void {
    this.glowX = this.lastTouchWinX - this.cardWinX;
    this.glowY = this.lastTouchWinY - this.cardWinY;
  }

  /**
   * 跟手光斑的径向渐变色标。由内到外三档淡出：中心最亮、中段已经散开、到半径处完全透明。
   * 只用一档实色会得到一个硬边圆盘，看着像贴纸而不是光。
   */
  private glowGradientColors(): Array<[ResourceColor, number]> {
    const accent: string = this.glowAccent();
    return [
      [Theme.rgba(accent, PRESS_GLOW_ALPHA), 0],
      [Theme.rgba(accent, PRESS_GLOW_ALPHA * 0.55), 0.42],
      [Theme.rgba(accent, PRESS_GLOW_ALPHA * 0.18), 0.72],
      [Color.Transparent, 1]
    ];
  }

  /** 溢出光晕的径向渐变色标：比手指光斑更柔、更淡 */
  private spillGradientColors(): Array<[ResourceColor, number]> {
    const accent: string = this.glowAccent();
    return [
      [Theme.rgba(accent, PRESS_SPILL_ALPHA), 0],
      [Theme.rgba(accent, PRESS_SPILL_ALPHA * 0.72), 0.35],
      [Theme.rgba(accent, PRESS_SPILL_ALPHA * 0.28), 0.68],
      [Color.Transparent, 1]
    ];
  }

  /** 沾色层颜色（空串=不铺）。材质生效时底色让出（透明），沾色只能独立成层压在材质之上 */
  private tintLayerColor(): string {
    if (!this.cardTintOn || !this.materialEffective()) {
      return '';
    }
    return AppearanceStore.cardTintLayer(this.themeColor);
  }

  /**
   * 溢出到卡片之外的那圈光。
   *
   * 画布比卡片大得多、以手指为圆心，靠一个 **0 尺寸锚点**甩到卡片外面去
   * （直接放一个比父容器大的子节点会把卡片撑大：Stack 的尺寸取最大子节点，position 不改布局尺寸）。
   * 它在 cardBody 里排在最前面，卡内那半被上面的材质层盖住，只有漏到卡片外的部分看得见。
   */
  @Builder
  glowSpillLayer() {
    if (this.spillVisible()) {
      Stack() {
        Column()
          .width(PRESS_SPILL_SIZE)
          .height(PRESS_SPILL_SIZE)
          .position({
            x: this.glowX - PRESS_SPILL_RADIUS,
            y: this.glowY - PRESS_SPILL_RADIUS
          })
          .radialGradient({
            center: [PRESS_SPILL_RADIUS, PRESS_SPILL_RADIUS],
            radius: PRESS_SPILL_RADIUS,
            colors: this.spillGradientColors()
          })
          .hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no')
      }
      .width(0)
      .height(0)
      .position({ x: 0, y: 0 })
      .hitTestBehavior(HitTestMode.None)
      .accessibilityLevel('no')
    }
  }

  /**
   * 跟手流光层。
   *
   * 三点约束（都是参考项目真机调出来的）：
   *   1. **尺寸跟随卡片**（matchParent）：光斑只落在卡片里，绝不溢到相邻卡片内部；
   *      超出卡片的部分由这一层自己的 borderRadius 连同圆角一起收住
   *      （外壳为了让溢出光晕漏出去已经不设 clip，裁切责任下移到每一层）；
   *   2. **压在材质之上、内容之下**：光打在玻璃表面上（实测不能放在材质之下——
   *      沉浸光感材质不采样同一 Stack 里的兄弟节点，光会被整层盖住，真机上完全看不见）；
   *   3. **只覆盖手指周围一小片**：见 GLOW_RADIUS，光斑大了就成了整卡高亮。
   */
  @Builder
  pressGlowLayer() {
    if (this.touchGlowVisible()) {
      Column()
        .width(LayoutPolicy.matchParent)
        .height(LayoutPolicy.matchParent)
        // 外壳不再 clip（要放行溢出光晕），所以这一层自己带圆角
        .borderRadius(this.cardRadius)
        .radialGradient({
          center: [this.glowX, this.glowY],
          radius: GLOW_RADIUS,
          colors: this.glowGradientColors()
        })
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
    }
  }

  @Builder
  cardBody() {
    // 溢出光晕在最底层：卡内部分由上面的材质层盖住，只留卡片外那圈
    this.glowSpillLayer()
    if (this.materialEffective()) {
      MaterialCardLayer({
        layerRadius: this.cardRadius,
        layerShadow: this.cardMaterialShadow,
        layerForce: this.cardPersistent
      })
    }
    // 显式原色叠层（cardTintOverlay）：压在材质之上、内容之下，材质照常可见、颜色语义得以保留。
    // 尺寸用 matchParent（理由同下）；圆角自己给（外壳不 clip，整块方形底色不给圆角会在四角露直角）。
    if (this.materialEffective() && this.cardTintOverlay.length > 0) {
      Column()
        .width(LayoutPolicy.matchParent)
        .height(LayoutPolicy.matchParent)
        .borderRadius(this.cardRadius)
        .backgroundColor(this.cardTintOverlay)
        .opacity(this.cardTintOverlayRatio)
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
    }
    if (this.tintLayerColor().length > 0) {
      // 沾色层：叠在材质之上、内容之下。
      // 尺寸必须用 matchParent 而不是 width/height('100%')：百分比在 Stack 内按**父级可用尺寸**解析，
      // 高度会被撑到容器满高，卡片跟着胀大；matchParent 按父级实测尺寸解析，随内容走。
      // 圆角必须自己给：外壳不 clip，这一层是整块方形底色，不给圆角就会在卡片四角露出直角。
      Column()
        .width(LayoutPolicy.matchParent)
        .height(LayoutPolicy.matchParent)
        .borderRadius(this.cardRadius)
        .backgroundColor(this.tintLayerColor())
        .hitTestBehavior(HitTestMode.None)
        .accessibilityLevel('no')
    }
    // 流光压在材质之上、内容之下：光打在玻璃表面，文字仍压在光上面保持清晰
    this.pressGlowLayer()
    Flex({
      direction: this.cardDirection,
      space: { main: LengthMetrics.vp(this.cardSpace) },
      alignItems: this.cardAlignItems
    }) {
      this.cardContent()
    }
    .width('100%')
    .padding(this.cardPadding)
  }

  /**
   * 卡片外壳底色。
   *
   * 材质生效时必须让出底色：外壳底色会垫在承载层的材质之下，叠出灰感。
   * 让出后由承载层自己负责材质；材质不可用时回落调用方传入的卡片底色（纯色/毛玻璃底）。
   */
  private shellBackground(): ResourceColor {
    if (this.materialEffective()) {
      return Color.Transparent;
    }
    // 卡片沾色（广播键）优先：@Prop cardBg 是父组件算出的静态值，
    // 沾色开关的即时生效由广播键承担（见 tintBg 字段注释）。
    if (this.tintBg.length > 0) {
      return this.tintBg;
    }
    return this.cardBg;
  }

  /** 外壳磨砂：材质生效时关掉（避免与材质叠加发灰）；关闭光感时回落**微微磨砂**（参考项目行为） */
  private shellBlurStyle(): BlurStyle {
    if (this.materialEffective()) {
      return BlurStyle.NONE;
    }
    return this.cardBlur !== BlurStyle.NONE ? this.cardBlur : BlurStyle.Thin;
  }

  /** 外壳阴影：材质生效时让出（材质自带的投影由 cardMaterialShadow 控制） */
  private shellShadow(): ShadowOptions {
    return this.materialEffective() ? NO_SHADOW : this.cardShadow;
  }

  @Builder
  cardShell() {
    Stack() {
      this.cardBody()
    }
    .width(this.cardWidth)
    .margin(this.cardMargin)
    .borderRadius(this.cardRadius)
    .backgroundColor(this.shellBackground())
    .backgroundBlurStyle(this.shellBlurStyle())
    .border({ width: this.materialEffective() ? 0 : this.cardBorderW, color: this.cardBorderC })
    .shadow(this.shellShadow())
    // 刻意**不设 clip(true)**：溢出光晕要漏到卡片外面去，clip 会把它整圈切掉。
    // 需要裁切的每一层都自己带圆角（材质层、沾色层、跟手光斑），效果等价。
    .onAreaChange((_oldArea: Area, newArea: Area): void => {
      const gx: number = typeof newArea.globalPosition.x === 'number' ? newArea.globalPosition.x : this.lastAreaX;
      const gy: number = typeof newArea.globalPosition.y === 'number' ? newArea.globalPosition.y : this.lastAreaY;
      if (this.areaReady) {
        // 只取增量：卡片被滚动带走时光斑要跟着手指重算，不然会黏在卡片原处
        this.cardWinX += gx - this.lastAreaX;
        this.cardWinY += gy - this.lastAreaY;
        if (this.glowOn) {
          this.syncGlowPosition();
        }
      }
      this.lastAreaX = gx;
      this.lastAreaY = gy;
      this.areaReady = true;
    })
    .hoverEffect(this.effectiveHoverEffect())
    // 按压跟手流光：「卡片流光触感 / 主题色流光」两个开关的消费端。
    // 此前因「写 @State 整卡重渲染 → 卡内 TextInput 丢焦点」被移除；
    // 现含输入框的卡片已全部改用普通卡 + 承载层结构（不再走 MaterialCard），恢复安全。
    // 若未来某卡要同时装输入框与 MaterialCard，给该卡传 cardGlow:false。
    .onTouch((event: TouchEvent) => {
      this.updatePressGlow(event);
    })
    .focusable(this.cardFocusable)
    .enabled(this.cardEnabled)
    .opacity(this.cardOpacity)
    .onClick(() => {
      this.cardOnClick();
    })
    // ⚠ 已移除外壳上的 `.gesture(LongPressGesture())`：父级长按手势会让卡内 TextInput
    // 无法获得焦点（"输入框点击没反应"的根因）。需要长按语义的卡片（如日志页多选）
    // 请在外层容器上自行挂手势（见 LogPage）。
  }

  build() {
    this.cardShell()
  }
}

/**
 * 半模态弹窗（向上弹出的卡片）的沉浸光感面板。
 *
 * 为什么不能只靠 `bindSheet` 的 `systemMaterial`：那个材质挂在**弹窗面板本身**上，
 * 和卡片遇到的是同一堵墙——非选择类组件的 systemMaterial 在内容区不生效，真机表现就是
 * 弹窗面板完全没有光感（内层 MaterialCard 有，面板是平的）。所以沿用与 MaterialCard
 * 完全一致的解法：用 ToggleType.Button 承载层铺满整个面板，材质由承载层渲染。
 *
 * 与 MaterialCard 只有两点差别：
 *   1. 铺满父容器（固定高度面板）。弹窗面板是固定高度（SheetSize.MEDIUM 等），材质必须裹住整块面板；
 *      只裹内容高度会让面板下半截露出系统底色。高度随内容的弹窗（SheetSize.FIT_CONTENT）
 *      传 `panelFillHeight: false` 让面板跟着内容走（见该参数说明）。
 *   2. 圆角只切上方两角。半模态从底部升起，下方两角贴着屏幕边缘；承载层仍按统一圆角绘制
 *      （它自己会画按钮图形），再靠外层的 clip 把下两角切平。
 *
 * 注意：材质层必须是**内容之下的兄弟层**（Stack 里先写）。早期实现用 `overlay()` 把承载层
 * 贴在内容之上，材质会整块盖住面板内容——不要改回去。
 */
@Component
export struct MaterialSheetPanel {
  /** 面板上方两角的圆角 */
  @Prop panelRadius: Length = 20;
  /** 内容内边距（传 0 则由内容自己控制留白） */
  @Prop panelPadding: Length = 0;
  /**
   * 是否强制铺满父容器高度（默认 true）。
   *
   * 半模态面板是**固定高度**（`SheetSize.MEDIUM` 等）时保持 true：材质承载层与内容都要裹住整块面板，
   * 只裹内容高度会让面板下半截露出系统底色。
   * `SheetSize.FIT_CONTENT`（高度随内容）的弹窗必须传 false——百分比高度在「先撑开容器、再适配子组件」
   * 的场景里会按父级可用尺寸解析，会把这种弹窗撑到系统允许的最大高度（等于换了个尺寸的弹窗）。
   * 传 false 后承载层仍用 matchParent，随内容实测高度走。
   */
  @Prop panelFillHeight: boolean = true;
  /**
   * 是否在面板右上角绘制**沉浸光感关闭按钮**（默认 false）。
   *
   * bindSheet 系统自带的 `showClose` 关闭按钮是系统渲染的，无法带沉浸光感；
   * 需要光感关闭按钮的面板传 `panelShowClose: true` + `panelOnClose`，
   * 并把宿主 bindSheet 的 `showClose` 显式改为 false（否则出现两个关闭按钮）。
   */
  @Prop panelShowClose: boolean = false;
  /** 光感关闭按钮点击回调（通常写 `this.xxxSheet = false`） */
  panelOnClose: () => void = (): void => {
  };
  @StorageProp('immersiveEffect') immersiveEffect: boolean = false;
  /** 灰字广播订阅（关闭按钮字色随灰字设置实时刷新；表达式读 this.grayTick 才登记依赖） */
  @StorageProp('grayTick') grayTick: number = 0;
  @BuilderParam panelContent: () => void = this.emptyPanel;

  @Builder
  emptyPanel() {
  }

  /** 材质是否生效（与 MaterialCard 同一判定：开关 + API≥26 + 材质构造成功） */
  private materialEffective(): boolean {
    return this.immersiveEffect && isApi26OrAbove() && materialActive();
  }

  /** 面板根背景：材质生效时让出底色，否则补卡片底色兜底（bindSheet 的 backgroundColor 通常是 Color.Transparent） */
  private panelBackground(): ResourceColor {
    return this.materialEffective() ? Color.Transparent : $r('app.color.bg_card');
  }

  /**
   * 面板标题栏右上角的沉浸光感关闭按钮。
   *
   * 位置：**面板内容首行（即面板上方标题那一栏）的右侧**——与内容同层 Stack(TopEnd) 对齐，
   * 随内容流排布（不再用 position/markAnchor 浮在面板右上角，避免与标题行错位、盖住内容）。
   */
  @Builder
  panelCloseButton() {
    if (this.panelShowClose) {
      Row() {
        MaterialButton({
          btnRadius: 15,
          btnBg: $r('app.color.bg_chip'),
          btnBlur: BlurStyle.Thin,
          btnBorderW: GlassMaterial.borderWidth(),
          btnBorderC: GlassMaterial.borderColor(),
          btnOnClick: (): void => {
            this.panelOnClose();
          }
        }) {
          Text('✕')
            .fontSize(13)
            .fontColor(GlassMaterial.graySecondary(this.grayTick, $r('app.color.text_secondary'))).fontStyle(GlassMaterial.styleItalic(this.grayTick)).fontWeight(GlassMaterial.styleWeight(this.grayTick)).backgroundColor(GlassMaterial.styleGlowBg(this.grayTick))
            .width(30)
            .height(30)
            .textAlign(TextAlign.Center)
        }
      }
      // 上边距 6：让 30vp 高的关闭按钮垂直中心（≈21）对齐面板内容首行标题的中心
      // （各面板标题上边距 8~16 → 标题中心约 20~28），即「与左上角标题同一高度」
      .padding({ right: 12, top: 6 })
    }
  }

  @Builder
  panelBody(fill: boolean) {
    if (this.materialEffective()) {
      MaterialCardLayer({ layerRadius: this.panelRadius, layerShadow: false })
    }
    // 内容与关闭按钮同层：TopEnd 对齐使关闭按钮落在内容首行右侧（= 面板标题栏）
    if (fill) {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column() {
          this.panelContent()
        }
        .width('100%')
        .height('100%')
        .padding(this.panelPadding)
        this.panelCloseButton()
      }
      .width('100%')
      .height('100%')
    } else {
      Stack({ alignContent: Alignment.TopEnd }) {
        Column() {
          this.panelContent()
        }
        .width('100%')
        .padding(this.panelPadding)
        this.panelCloseButton()
      }
      .width('100%')
    }
  }

  build() {
    if (this.panelFillHeight) {
      Stack() {
        this.panelBody(true)
      }
      .width('100%')
      .height('100%')
      .borderRadius({
        topLeft: this.panelRadius,
        topRight: this.panelRadius,
        bottomLeft: 0,
        bottomRight: 0
      })
      // 材质生效时必须让出底色，否则底色会垫在材质之下叠出灰感；
      // 不生效时补上卡片底色兜底（bindSheet 的 backgroundColor 通常是 Color.Transparent）。
      .backgroundColor(this.panelBackground())
      .clip(true)
    } else {
      Stack() {
        this.panelBody(false)
      }
      .width('100%')
      .borderRadius({
        topLeft: this.panelRadius,
        topRight: this.panelRadius,
        bottomLeft: 0,
        bottomRight: 0
      })
      .backgroundColor(this.panelBackground())
      .clip(true)
    }
  }
}
