/**
 * 粒子消散层（删除组合卡片 / 删除登录记录等场景的过场反馈）。
 *
 * 结构：matchParent 覆盖在宿主卡片上（宿主须为 Stack），trigger>0 时从卡片**中心**
 * 爆开一圈主题色粒子（默认 14 颗：角度均分，距离/大小/延迟各带差异形成自然散开感），
 * 620ms 内飞散并淡出。hitTestBehavior(None) 不参与命中测试。
 *
 * 用法：
 *   Stack() { 卡片内容; DissolveBurst({ trigger: this.burstSeq }) }
 *   删除时：this.burstSeq++（触发爆散）+ 播放卡片收起动画 → 延时后真正移除数据。
 * 粒子颜色跟随主题色（订阅 themeColor，切色后新爆散的粒子即用新色）。
 */

import { Theme } from '../../common/ThemeUtil';

interface ParticleSpec {
  angle: number;
  distance: number;
  dotSize: number;
  delay: number;
}

const PARTICLE_COUNT: number = 14;
const PARTICLE_SPECS: ParticleSpec[] = (() => {
  const list: ParticleSpec[] = [];
  for (let i = 0; i < PARTICLE_COUNT; i++) {
    list.push({
      angle: i * (360 / PARTICLE_COUNT) + (i % 3) * 6,
      distance: 44 + (i % 4) * 11,
      dotSize: 3.5 + (i % 3) * 1.5,
      delay: i * 12
    });
  }
  return list;
})();

/** 单颗粒子：从中心沿角度飞散并淡出（延迟错开形成层次感） */
@Component
struct DissolveParticle {
  @Prop angle: number = 0;
  @Prop distance: number = 52;
  /** 粒子直径（不能叫 size——与 CustomComponent 基类的 size 属性冲突） */
  @Prop dotSize: number = 5;
  @Prop delay: number = 0;
  @State dx: number = 0;
  @State dy: number = 0;
  @State alpha: number = 1;
  @StorageProp('themeColor') themeColor: string = 'green';

  aboutToAppear(): void {
    setTimeout(() => {
      this.getUIContext().animateTo({ duration: 620, curve: Curve.EaseOut, delay: this.delay }, () => {
        this.dx = Math.cos(this.angle * Math.PI / 180) * this.distance;
        this.dy = Math.sin(this.angle * Math.PI / 180) * this.distance;
        this.alpha = 0;
      });
    }, 30);
  }

  build() {
    Circle()
      .width(this.dotSize)
      .height(this.dotSize)
      .fill(Theme.colorOf(this.themeColor))
      .translate({ x: this.dx, y: this.dy })
      .opacity(this.alpha)
  }
}

@Component
export struct DissolveBurst {
  /** 触发序号：>0 渲染粒子层；每次自增都会重建粒子并重新播放爆散 */
  @Prop trigger: number = 0;

  build() {
    Stack() {
      if (this.trigger > 0) {
        ForEach(PARTICLE_SPECS, (p: ParticleSpec) => {
          DissolveParticle({
            angle: p.angle,
            distance: p.distance,
            dotSize: p.dotSize,
            delay: p.delay
          })
        }, (p: ParticleSpec) => `dp${this.trigger}_${p.angle}_${p.distance}`)
      }
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.None)
  }
}
