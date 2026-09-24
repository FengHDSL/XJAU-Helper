/*
 * 鸿米家（miha）— HarmonyOS NEXT native Xiaomi Home / MIoT control client.
 *
 * Copyright (C) 2026 鸿米家（miha）项目开发者
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: GPL-3.0-or-later
 */

import { applyMaterialCarrier, pressLightColor } from '../../common/SystemMaterial';
import { Theme } from '../../common/ThemeUtil';

/**
 * 圆形沉浸光感图标按钮（移植自 miha_hm components/IconCircleButton.ets，GPL-3.0-or-later）。
 *
 * 载体必须是 ToggleType.Button：真机实测普通 Button 挂 systemMaterial 不渲染，
 * 而同尺寸的 ToggleType.Button 正常出材质。图标用 SymbolGlyph 叠在承载层上、
 * hitTestBehavior(None) 让触摸穿透——按压弹性形变（interactive）与跟手流光
 * （lightEffect，即"拖拽光感"）都由 Toggle 本体响应。
 *
 * 相对参考版的适配：
 *   - 主题色键为本项目 themeColor，流光取色走 pressLightColor(pressGlowSwitch, Theme.colorOf(...))；
 *   - tint 放宽为 ResourceColor（可传 $r 资源色做深浅色自适应）；
 *   - 新增 buttonForce：true 时材质常驻（顶栏返回按钮不随全局沉浸光感开关消失）。
 */
@Component
export struct IconCircleButton {
  @Prop buttonSize: number = 40;
  @Prop iconSize: number = 20;
  @Prop buttonEnabled: boolean = true;
  @Prop tint: ResourceColor = '#182431';
  /**
   * 是否开启交互形变 + 流光（类 HdsTab 的灵动反馈）。
   * 依赖设备算力档位对 ImmersiveOptions.interactive / lightEffect 的支持；
   * 若开启后发现材质整块消失，说明该设备不支持，传 false。
   */
  @Prop buttonInteractive: boolean = true;
  /** 材质常驻：true 时不随应用内「全局沉浸光感」开关关闭而消失 */
  @Prop buttonForce: boolean = false;
  /**
   * 按钮底色（如警示红 '#DB5252'）。非空时在承载层下垫一层同尺寸圆，
   * 材质呈红玻璃观感、材质不可用时为实色红底；空串 = 无底色（默认玻璃/材质）。
   */
  @Prop fill: string = '';
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('immersivePressGlow') pressGlowSwitch: boolean = true;
  /** 刷新类按钮：true 时图标持续旋转表示加载中 */
  @Prop @Watch('onSpinningChanged') spinning: boolean = false;
  /**
   * 图标改用图片资源（如 chevron_left.svg）：true 时渲染 Image(this.image) 而非 SymbolGlyph。
   * 图片同样触摸穿透、fillColor 用 tint 染色（SVG 单色路径可跟随深浅色）。
   */
  hasImage: boolean = false;
  image: Resource = $r('app.media.chevron_left');
  symbol: Resource = $r('sys.symbol.house');
  onAction: () => void = (): void => {
  };
  @State private spinAngle: number = 0;
  private spinTimer: number = -1;

  aboutToAppear(): void {
    this.syncSpinTimer();
  }

  aboutToDisappear(): void {
    this.stopSpin();
  }

  private syncSpinTimer(): void {
    if (this.spinning) {
      this.startSpin();
    } else {
      this.stopSpin();
    }
  }

  onSpinningChanged(): void {
    this.syncSpinTimer();
  }

  private startSpin(): void {
    if (this.spinTimer !== -1) {
      return;
    }
    this.spinTimer = setInterval((): void => {
      // 每 900ms 转一整圈：分 3 段推进，避免单次大角度动画在中低端机上掉帧
      this.getUIContext().animateTo({ duration: 300, curve: Curve.Linear }, (): void => {
        this.spinAngle += 120;
      });
    }, 300);
  }

  private stopSpin(): void {
    if (this.spinTimer !== -1) {
      clearInterval(this.spinTimer);
      this.spinTimer = -1;
    }
    this.spinAngle = 0;
  }

  /**
   * 材质承载修饰器。必须写成方法并在 build 里调用（不能内联对象字面量）：
   * 流光颜色要在渲染期现读订阅变量才会登记依赖，切主题色/拨流光开关时组件才会重建。
   */
  private carrierModifier(): AttributeModifier<ToggleAttribute> {
    const lightColor: string = pressLightColor(this.pressGlowSwitch, Theme.colorOf(this.themeColor));
    return {
      applyNormalAttribute: (instance: ToggleAttribute): void => {
        applyMaterialCarrier(instance, false, this.buttonInteractive, true, lightColor, this.buttonForce);
      }
    };
  }

  build() {
    Stack() {
      // 底色层（fill 非空时）：垫在承载层之下，材质盖在上面呈彩色玻璃
      if (this.fill.length > 0) {
        Circle()
          .width(this.buttonSize)
          .height(this.buttonSize)
          .fill(this.fill)
      }
      // 材质 + 交互层：ToggleType.Button
      Toggle({ type: ToggleType.Button, isOn: false })
        .width(this.buttonSize)
        .height(this.buttonSize)
        .borderRadius(this.buttonSize / 2)
        .clip(true)
        // 必须显式透明：不透明背景会盖在材质层之上
        .backgroundColor(Color.Transparent)
        // 关掉按压/选中的主题色填充（按下会闪一层蓝底；isOn 恒为 false 也挡不住）
        .selectedColor(Color.Transparent)
        .enabled(this.buttonEnabled)
        // systemMaterial 放在所有样式属性之后
        .attributeModifier(this.carrierModifier())
        .onChange(() => {
          this.onAction();
        })

      // 图标层：触摸穿透到下面的 Toggle，保证按压与流光响应在材质上
      if (this.hasImage) {
        Image(this.image)
          .width(this.iconSize)
          .height(this.iconSize)
          .objectFit(ImageFit.Cover)
          .fillColor(this.tint)
          .draggable(false)
          .hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no')
      } else {
        SymbolGlyph(this.symbol)
          .fontSize(this.iconSize)
          .fontColor([this.tint])
          .rotate({ angle: this.spinAngle })
          .hitTestBehavior(HitTestMode.None)
          .accessibilityLevel('no')
      }
    }
    .width(this.buttonSize)
    .height(this.buttonSize)
    .onAppear((): void => {
      this.syncSpinTimer();
    })
  }
}
