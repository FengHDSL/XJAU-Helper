/**
 * 沉浸光感（系统材质 systemMaterial）工具
 * —— 移植自参考项目 miha_hm（鸿米家）`utils/SystemMaterial.ets`，
 *    规则以其 README「沉浸光感（API 26）」章节为权威。
 * 对应参考文件：miha_hm `utils/SystemMaterial.ets`（本文件为其本项目版，
 * 保留原导出语义并按本项目 AppStorage 键名（immersiveEffect / themeColor）适配）。
 *
 * 四铁律（踩过的坑）：
 * 1. `entry/module.json5` 必须显式配 `ohos.arkui.UIMaterial.state = enable`；若为 disable，
 *    **主动设置的材质也一并失效且代码绕不过**（本项目已配）。
 * 2. `systemMaterial` 通用属性**只对按钮/选择类组件（Button/Select/Toggle/Slider/ChipGroup/
 *    SegmentButton/bindSheet）在页面任意区域生效**；布局容器挂在内容区无效（仅 Navigation /
 *    NavDestination 标题栏与 BarPosition.End 的底部 TabBar 例外）
 *    → 卡片必须用透明 Toggle 承载层（见 view/common/MaterialCarrier.ets）。
 * 3. **不得自锁**：不能用 `MaterialState.DISABLE` 判定"本应用不能渲染"而返回 `Material.empty`
 *    （那等于显式不画、把失败伪装成静默失效）。材质**构造成功即下发**，构造失败返回 null 并降级毛玻璃。
 * 4. `systemMaterial` 必须放在属性链**最后**（本文件通过 attributeModifier 由承载层附加）。
 *
 * 另一条实测结论（README）：静态材质**只传 style**；
 * `ImmersiveMaterial({ interactive: true, lightEffect: {} })` 组合在 HarmonyOS 7.0.0.105 / API 26 上
 * **完全不渲染**。故本项目按压流光不依赖材质自身光效，而是自绘「跟手光斑 + 溢出光晕」两层
 * （见 view/common/MaterialCard.ets），流光颜色由 `pressLightColor()` 提供。
 */
import { uiMaterial } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';

// ── 模块级状态（惰性构造，避免低版本启动即解引用 API 26 接口）──

/** 静态材质缓存（interactive=false） */
let materialCache: uiMaterial.Material | null = null;
/** 静态材质是否已尝试构造（失败也不反复重试，避免每帧构造开销） */
let staticTried: boolean = false;
/** 去阴影静态材质缓存（withShadow=false） */
let flatMaterialCache: uiMaterial.Material | null = null;
/** 去阴影材质是否已尝试构造 */
let flatTried: boolean = false;
/** 可交互材质缓存：key = `i{interactive}s{withShadow}l{lightColor}`（构造开销大且必须按颜色区分） */
const interactiveCache: Map<string, uiMaterial.Material | null> = new Map<string, uiMaterial.Material | null>();
/** 最近一次构造失败原因（诊断用，空串=未失败） */
let lastError: string = '';
/** 设备支持检测缓存：-1 未检测 / 0 不支持 / 1 支持 */
let supportState: number = -1;

/** 设备 API 版本是否 ≥ 26（沉浸光感材质最低要求） */
export function isApi26OrAbove(): boolean {
  try {
    return deviceInfo.sdkApiVersion >= 26;
  } catch (e) {
    return false;
  }
}

/** 设备是否支持沉浸材质（惰性检测，异常按不支持处理） */
export function immersiveSupported(): boolean {
  if (supportState < 0) {
    let ok: boolean = false;
    try {
      ok = uiMaterial.isImmersiveMaterialSupported();
    } catch (e) {
      ok = false;
    }
    supportState = ok ? 1 : 0;
  }
  return supportState === 1;
}

/**
 * 应用级材质开关状态（读 module.json5 的 metadata，仅 API≥26 可读）。
 * 返回 'ENABLE' / 'DISABLE' / 'DEFAULT' / 'UNSUPPORTED'（读取失败或低版本）。
 */
export function systemMaterialState(): string {
  if (!isApi26OrAbove()) {
    return 'UNSUPPORTED';
  }
  try {
    const info: uiMaterial.MaterialInfo = uiMaterial.getMaterialInfo();
    if (info.state === uiMaterial.MaterialState.ENABLE) {
      return 'ENABLE';
    }
    if (info.state === uiMaterial.MaterialState.DISABLE) {
      return 'DISABLE';
    }
    return 'DEFAULT';
  } catch (e) {
    return 'UNSUPPORTED';
  }
}

/** 应用级材质是否被显式关闭（此时任何材质设置都不生效，代码绕不过） */
export function isSystemMaterialDisabled(): boolean {
  return systemMaterialState() === 'DISABLE';
}

/** 应用级材质状态读取异常信息（诊断用，正常返回空串） */
export function systemMaterialError(): string {
  if (!isApi26OrAbove()) {
    return 'API<26';
  }
  try {
    uiMaterial.getMaterialInfo();
    return '';
  } catch (e) {
    return `${e}`;
  }
}

/** 最近一次材质构造失败原因（诊断用，空串=未失败） */
export function immersiveMaterialError(): string {
  return lastError;
}

/** 全局沉浸光感开关（外观设置主开关；缺失/异常时按开启处理） */
export function immersiveOn(): boolean {
  const on: boolean | undefined = AppStorage.get<boolean>('immersiveEffect');
  return on === undefined ? true : on;
}

/**
 * 构造沉浸材质（含缓存）。
 *
 * @param interactive 是否启用材质自身交互变形（**实测该组合在 API 26 上完全不渲染，默认 false**）
 * @param withShadow  是否启用材质自带阴影（默认 true，与 ImmersiveOptions.applyShadow 默认值一致）
 * @param lightColor  流光颜色（#RRGGBB，空串=不设置光效）；仅 interactive=true 时透传给材质光效
 * @returns 材质对象；不可用或构造失败返回 **null**（绝不返回 Material.empty，避免自锁）
 */
export function getImmersiveMaterial(interactive: boolean, withShadow: boolean, lightColor: string): uiMaterial.Material | null {
  // 缓存键（静态材质只用两档，无颜色维度）
  const key: string = interactive ? `i1s${withShadow ? '1' : '0'}l${lightColor}` : '';
  // 先查缓存：命中直接返回，避免每次重渲染都做设备检测 / 应用级状态读取
  if (!interactive) {
    if (withShadow) {
      if (staticTried) {
        return materialCache;
      }
    } else {
      if (flatTried) {
        return flatMaterialCache;
      }
    }
  } else {
    if (interactiveCache.has(key)) {
      const cached: uiMaterial.Material | null | undefined = interactiveCache.get(key);
      return cached === undefined ? null : cached;
    }
  }
  let built: uiMaterial.Material | null = null;
  // 判定只保留「API 版本」与「应用级关闭」两条：
  //   - **刻意不再要求 `immersiveSupported()`**（曾经的写法是 `!isApi26OrAbove() || !immersiveSupported() || ...`）。
  //     那是与参考 README 所记「自锁」同类的问题：`uiMaterial.isImmersiveMaterialSupported()`
  //     在部分设备 / 模拟器上会返回 false（或读取失败），一旦如此材质**永远不会被构造**，
  //     表现为「沉浸光感完全没有效果」，而代码层面看不出任何异常。
  //     权威实现（参考 `utils/SystemMaterial.ets`）的做法是不做这项预检：材质只要构造成功就下发，
  //     画不画由系统按「生效范围」决定。构造抛错时下面的 catch 仍会返回 null 并走降级。
  //   - `isSystemMaterialDisabled()` 保留：module.json5 配成 disable 时材质必定不渲染，
  //     此时提前判定可以直接降级为毛玻璃（而不是让卡片变成一块透明色）。
  if (!isApi26OrAbove() || isSystemMaterialDisabled()) {
    // 环境不支持 → 记为"已尝试且失败"，避免反复检测
    built = null;
  } else {
    try {
      const opts: uiMaterial.ImmersiveOptions = {
        style: uiMaterial.ImmersiveStyle.THIN,
        applyShadow: withShadow
      };
      if (interactive) {
        opts.interactive = true;
        // 光效选项必须先声明带类型标注的常量再赋值（ArkTS 对象字面量限制）
        const lightOptions: uiMaterial.LightEffectOptions = {};
        if (lightColor.length > 0) {
          lightOptions.color = lightColor;
        }
        opts.lightEffect = lightOptions;
      }
      built = new uiMaterial.ImmersiveMaterial(opts);
      lastError = '';
    } catch (e) {
      built = null;
      lastError = `${e}`;
    }
  }
  if (!interactive) {
    if (withShadow) {
      materialCache = built;
      staticTried = true;
    } else {
      flatMaterialCache = built;
      flatTried = true;
    }
  } else {
    interactiveCache.set(key, built);
  }
  return built;
}

/**
 * 流光颜色：主题色流光开启时返回主题色，否则返回空串（= 用系统默认流光色）。
 *
 * **纯函数**：必须由调用方传入已订阅的值（ArkUI 只按组件属性表达式登记依赖，
 * 在函数内部读 AppStorage 登记不上依赖，开关变化不会触发刷新）。
 *
 * @param themedLightOn 主题色流光开关（组件里用 @StorageProp 订阅后传入）
 * @param accentColor   当前主题色（组件里用 @StorageProp('themeColor') 推导后传入）
 */
export function pressLightColor(themedLightOn: boolean, accentColor: string): string {
  if (!themedLightOn) {
    return '';
  }
  return /^#([0-9a-fA-F]{6})$/.test(accentColor) ? accentColor : '';
}

/** 承载层是否已具备挂载材质的条件（诊断/条件渲染用） */
export function materialActive(): boolean {
  return immersiveOn() && getImmersiveMaterial(false, true, '') !== null;
}

/** 材质是否真正在生效（等价于 materialActive，命名对齐参考项目） */
export function immersiveMaterialActive(): boolean {
  return materialActive();
}

/**
 * 材质**是否可下发**——忽略应用内的全局沉浸光感开关（`immersiveEffect`），
 * 只看 API 版本、应用级系统状态与材质能否构造成功。
 *
 * 用途：**常驻材质**（顶栏按钮、登录页主按钮等要求「固定有效、不随全局开关关闭而消失」的元素）。
 * 与 `materialActive()` 的唯一差别是不参与 `immersiveOn()` 判定：
 * 全局开关关掉后，普通卡片 / 按钮回落毛玻璃或纯色，而走常驻路径的元素仍下发材质。
 */
export function materialAvailable(): boolean {
  return isApi26OrAbove() && getImmersiveMaterial(false, true, '') !== null;
}

/**
 * 给承载层挂沉浸光感材质；不可用时按需降级为毛玻璃。
 * 必须在属性链最后调用（内部通过 systemMaterial 设置，优先级高于原有背景/模糊/阴影/边框）。
 *
 * @param instance 承载层组件属性实例（Toggle/Button 等选择类组件）
 * @param fallbackBlur 材质不可用时是否补一层毛玻璃兜底
 * @param interactive 是否启用材质自身交互（默认 false，见 getImmersiveMaterial 说明）
 * @param withShadow 是否启用材质自带阴影（默认 true）
 * @param lightColor 流光颜色（默认空串）
 * @param force 是否**强制下发**（常驻材质；为 true 时跳过 `immersiveOn()` 应用内开关判定，
 *              只受 API 版本 / 应用级系统状态 / 构造结果约束）。默认 false，行为与改动前完全一致。
 */
export function applyMaterialCarrier(instance: CommonAttribute, fallbackBlur: boolean = true,
  interactive: boolean = false, withShadow: boolean = true, lightColor: string = '',
  force: boolean = false): void {
  const material: uiMaterial.Material | null = getImmersiveMaterial(interactive, withShadow, lightColor);
  if ((force || immersiveOn()) && material !== null) {
    instance.systemMaterial(material);
  } else if (fallbackBlur) {
    instance.backgroundBlurStyle(BlurStyle.Thin);
  }
}

/** 按钮类组件的材质下发（Button/Select 等可在页面任意区域直接生效，无需承载层） */
export function applyButtonMaterial(instance: CommonAttribute, fallbackBlur: boolean = true): void {
  applyMaterialCarrier(instance, fallbackBlur, false, true, '');
}

/** 承载层材质是否处于激活态（供承载组件条件渲染用，与 materialActive 同义） */
export function materialCarrierActive(): boolean {
  return materialActive();
}

/**
 * 半模态（bindSheet）模糊样式。
 * bindSheet 属于 MaterialState.ENABLE 下**默认启用材质**的组件，
 * 材质生效时叠加 BlurStyle 会让材质发灰 → 返回 NONE；材质不可用时用 Thin 兜底。
 * （bindSheet 必须显式 `backgroundColor: Color.Transparent`，否则不透明白底会挡住材质）
 */
export function sheetBlurStyle(): BlurStyle {
  return materialActive() ? BlurStyle.NONE : BlurStyle.Thin;
}

/** 半模态内容面板可用的沉浸材质（不生效返回 null，由调用方兜底毛玻璃） */
export function sheetSystemMaterial(): uiMaterial.Material | null {
  return getImmersiveMaterial(false, true, '');
}

/**
 * 诊断文案（显示在「外观设置 → 全局沉浸光感」下方，便于真机排查"为什么没生效"）。
 * 形如：`API=26 材质=已构造 状态=非DISABLE 开关=开 流光=#0A59F7 承载=下发材质`
 *
 * @param themedLightOn 主题色流光开关（可选）
 * @param accentColor   当前主题色（可选）
 */
export function materialDiagnostics(themedLightOn: boolean = false, accentColor: string = ''): string {
  const api: string = isApi26OrAbove() ? 'API≥26' : `API=${deviceInfo.sdkApiVersion}(<26)`;
  const material: uiMaterial.Material | null = getImmersiveMaterial(false, true, '');
  const built: string = material !== null ? '已构造' : '构造失败';
  const state: string = systemMaterialState();
  const stateText: string = state === 'DISABLE' ? 'DISABLE(应用级关闭)' : `非DISABLE`;
  const on: string = immersiveOn() ? '开' : '关';
  const light: string = pressLightColor(themedLightOn, accentColor);
  const lightText: string = light.length > 0 ? light : '默认';
  const carrier: string = materialActive() ? '下发材质' : '降级毛玻璃';
  const err: string = lastError.length > 0 ? ` 错误=${lastError.substring(0, 60)}` : '';
  return `${api} 材质=${built} 状态=${stateText}(${state}) 开关=${on} 流光=${lightText} 承载=${carrier}${err}`;
}
