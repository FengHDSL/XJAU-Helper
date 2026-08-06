/**
 * 隐私协议页：以独立页面展示协议全文
 */
import { AppState } from '../common/AppState';
import { PageHeader } from './common/UiKit';

@Component
export struct PrivacyPage {
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;

  @Builder
  section(title: string, content: string) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 8 })
      Text(content)
        .fontSize(13)
        .lineHeight(22)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 18 })
  }

  build() {
    NavDestination() {
      Column() {
        PageHeader({
          title: '隐私协议',
          onBack: () => {
            AppState.stack.pop();
          }
        })

        Scroll() {
          Column() {
            this.section('1. 信息收集',
              '本应用仅在您主动登录时收集学号与密码，用于访问学校教务系统获取课表、成绩、考试等数据。' +
              '密码使用教务系统 RSA 公钥加密传输，本地仅保存登录状态标识，不存储明文密码。')
            this.section('2. 信息存储',
              '课表、成绩、考试、头像等数据缓存仅保存在您设备本地（应用私有目录），不上传任何服务器。' +
              '您可在"我的-清除缓存"中随时删除全部本地数据。')
            this.section('3. 权限使用',
              '本应用仅申请网络权限（联网获取教务数据）与日历权限（将考试安排写入系统日历提醒）。' +
              '不申请位置、相册、通讯录、麦克风等与教务功能无关的权限。')
            this.section('4. 数据安全',
              '本地缓存不进行二次上传；登录会话仅用于教务系统接口调用。应用被卸载时，本地缓存将被系统一并清除。')
            this.section('5. 第三方服务',
              '桌面卡片、快捷方式等系统能力仅在本机展示应用自身数据，不涉及第三方 SDK 数据共享。')

            Column()
              .height(px2vp(this.bottomInsetPx) + 24)
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 4 })
        }
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_page'))
    }
    .hideTitleBar(true)
    .width('100%')
    .height('100%')
  }
}
