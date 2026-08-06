/**
 * 登录页：顶部学校徽标 + 学号密码登录 + 服务端驱动的验证码
 *
 * 登录策略（与真实教务系统一致）：
 *  - 客户端不做任何"本地校验"：用户输入完账号密码，直接 POST 到教务系统，
 *    由网页返回成功/失败。服务端响应要求验证码时（needCaptcha=true），
 *    才把验证码图片推给用户输入。
 *  - 历史登录账号：本地保存【账号+密码】（密码 XOR 0x5A + base64 编码），点击登录按钮下方的
 *    "历史账号"入口展开，可一键填充账号密码。
 */
import { KeyboardAvoidMode, promptAction } from '@kit.ArkUI';
import { mediaquery } from '@kit.ArkUI';
import { JwApi } from '../api/JwApi';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { DataStore } from '../common/DataStore';
import { LoginResult } from '../model/Models';
import { WebSurface } from './WebSurface';

@Component
export struct LoginView {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @State account: string = '';
  @State password: string = '';
  @State captchaInput: string = '';
  @State captcha: string = '';
  @State captchaImage: string = '';
  @State showCaptcha: boolean = false;
  @State remember: boolean = true;
  @State loading: boolean = false;
  @State showWeb: boolean = false;
  @State showWebLogin: boolean = false;
  @State showHistory: boolean = false;
  @State historyList: Record<string, string>[] = [];
  @State isLandscape: boolean = false;
  @State showPwd: boolean = false; // 密码明文/密文切换
  private accountController: TextInputController = new TextInputController();
  private passwordController: TextInputController = new TextInputController();
  onSuccess: () => void = () => {
  };
  private landscapeListener: mediaquery.MediaQueryListener | null = null;

  /** 页面出现：读取历史账号并填充、注册屏幕方向监听 */
  aboutToAppear(): void {
    // 键盘避让设为 RESIZE：键盘弹出时页面缩小而非上移，登录按钮可滚动到键盘上方点击
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    } catch (e) {
      // ignore
    }
    // 读取历史账号（最近登录的账号+密码）
    this.historyList = DataStore.getAccountList();
    if (this.historyList.length > 0) {
      this.account = this.historyList[0]['account'] ?? '';
      this.password = DataStore.decodePwd(this.historyList[0]['password'] ?? '');
    }
    const mq: mediaquery.MediaQueryResult = mediaquery.matchMediaSync('(orientation: landscape)');
    this.isLandscape = mq.matches;
    this.landscapeListener = mediaquery.matchMediaSync('(orientation: landscape)');
    this.landscapeListener.on('change', (res: mediaquery.MediaQueryResult) => {
      this.isLandscape = res.matches;
    });
  }

  /** 页面消失：注销监听 */
  aboutToDisappear(): void {
    this.landscapeListener = null;
  }

  /** 生成随机 4 位验证码字符（mock 模式） */
  private randomCode(): string {
    const chars: string = 'ABCDEFGHJKLMNPQRSTUVWXY23456789';
    let out: string = '';
    for (let i = 0; i < 4; i++) {
      out += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return out;
  }

  /** 加载/刷新验证码：mock 用本地随机码占位；真实模式从服务端拉取验证码图片。 */
  private loadCaptcha(): void {
    if (JwApi.USE_MOCK) {
      this.captcha = this.randomCode();
      this.captchaInput = '';
      return;
    }
    this.captchaInput = '';
    JwApi.getCaptcha().then((b64: string) => {
      this.captchaImage = b64;
    }).catch(() => {
      this.captchaImage = '';
    });
  }

  /**
   * 登录：不做本地校验，直接请求教务系统，等待网页返回结果。
   * 服务端要求验证码时，才把验证码图片推给用户输入后重试。
   */
  private async doLogin(): Promise<void> {
    if (this.account.trim().length === 0) {
      promptAction.showToast({ message: '请输入学号' });
      return;
    }
    if (this.password.length === 0) {
      promptAction.showToast({ message: '请输入密码' });
      return;
    }
    // 真实登录：强制走真实接口
    JwApi.USE_MOCK = false;
    this.loading = true;
    const captchaVal: string = this.showCaptcha ? this.captchaInput.trim() : '';
    const result: LoginResult = await JwApi.login(this.account.trim(), this.password, captchaVal);
    this.loading = false;

    if (result.success && result.profile !== null) {
      AppState.profile = result.profile;
      AppState.account = this.account.trim();
      // 记录历史账号（含密码），最近登录置顶
      DataStore.addAccount(this.account.trim(), this.password);
      this.historyList = DataStore.getAccountList();
      promptAction.showToast({ message: '登录成功' });
      this.onSuccess();
    } else {
      // 只有服务端要求验证码，才显示验证码输入框并推送图片
      if (result.needCaptcha) {
        if (!this.showCaptcha) {
          this.showCaptcha = true;
        }
        this.loadCaptcha();
      }
      promptAction.showToast({ message: result.message, duration: 2500 });
      // 登录不成功（含需要验证码/密码错误），开放"网页版登录"兜底入口
      this.showWebLogin = true;
    }
  }

  /** 在应用内 WebView 打开教务系统登录页，用于"网页版直接登录"的兜底方案。 */
  private openWebLogin(): void {
    AppState.webLoginMode = true;
    AppState.onWebLogin = () => {
      this.showWeb = false;
      this.onSuccess();
    };
    AppState.webUrl = Const.WEB_LOGIN_URL;
    AppState.webTitle = '网页版登录';
    this.showWeb = true;
  }

  /** 打开找回密码网页（学校统一身份认证平台），在应用内 WebView 中展示。 */
  private openForgotPassword(): void {
    AppState.webLoginMode = false;
    AppState.onWebLogin = null;
    AppState.webUrl = Const.FORGOT_PASSWORD_URL;
    AppState.webTitle = '找回密码';
    this.showWeb = true;
  }

  /** 功能浏览（原"游客模式"）：临时切到 mock 数据，用占位账号直接登录（无需真实学号密码）。 */
  private async demoLogin(): Promise<void> {
    JwApi.USE_MOCK = true;
    this.loading = true;
    const result: LoginResult = await JwApi.login('demo123456', 'demo123456');
    this.loading = false;
    if (result.success && result.profile !== null) {
      AppState.profile = result.profile;
      AppState.account = 'demo';
      promptAction.showToast({ message: '已进入功能浏览模式' });
      this.onSuccess();
    } else {
      promptAction.showToast({ message: '功能浏览启动失败，请重试' });
    }
  }

  /** 选中历史账号 → 填充账号密码并折叠面板 */
  private pickHistory(item: Record<string, string>): void {
    const acct: string = item['account'] ?? '';
    const pwd: string = DataStore.decodePwd(item['password'] ?? '');
    this.account = acct;
    this.password = pwd;
    // TextInput 构造器 text 参数不会响应 @State 变化，需通过 controller 强制刷新
    this.accountController.deleteText();
    if (acct.length > 0) {
      this.accountController.addText(acct);
    }
    this.passwordController.deleteText();
    if (pwd.length > 0) {
      this.passwordController.addText(pwd);
    }
    this.showHistory = false;
    this.showCaptcha = false;
    this.captchaInput = '';
  }

  /** 清空历史账号列表并持久化 */
  private clearHistory(): void {
    DataStore.put(DataStore.KEY_ACCOUNTS, '[]');
    DataStore.put(DataStore.KEY_LAST_ACCOUNT, '');
    this.historyList = [];
    this.showHistory = false;
  }

  @Builder
  inputRow(placeholder: string, value: string,
    onInput: (v: string) => void, controller: TextInputController) {
    Row() {
      TextInput({ placeholder: placeholder, controller: controller, text: value })
        .type(InputType.Normal)
        .placeholderColor($r('app.color.text_tertiary'))
        .fontColor($r('app.color.text_primary'))
        .fontSize(15)
        .backgroundColor(Color.Transparent)
        .padding({ left: 14, right: 8 })
        .layoutWeight(1)
        .height(48)
        .onChange(onInput)
    }
    .width('100%')
    .backgroundColor($r('app.color.bg_chip'))
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  /** 密码输入行：眼睛切换明文/密文 + ✕ 一键清空 */
  @Builder
  passwordRow(placeholder: string, value: string,
    onInput: (v: string) => void, controller: TextInputController) {
    Row() {
      TextInput({ placeholder: placeholder, controller: controller, text: value })
        .type(this.showPwd ? InputType.Normal : InputType.Password)
        // 隐藏系统内置的密码可见性切换图标（与自定义眼睛重复）
        .showPasswordIcon(false)
        .placeholderColor($r('app.color.text_tertiary'))
        .fontColor($r('app.color.text_primary'))
        .fontSize(15)
        .backgroundColor(Color.Transparent)
        .padding({ left: 14, right: 8 })
        .layoutWeight(1)
        .height(48)
        .onChange(onInput)

      // ✕ 一键清空（有内容时才显示）
      if (value.length > 0) {
        Text('✕')
          .fontSize(15)
          .fontColor($r('app.color.text_tertiary'))
          .width(30)
          .height(48)
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.password = '';
            onInput('');
            this.passwordController.deleteText();
          })
      }

      // 眼睛图标：切换明文/密文（睁眼=明文可见，闭眼=密文隐藏）
      Image(this.showPwd ? $r('app.media.eye') : $r('app.media.eye_off'))
        .width(20)
        .height(20)
        .fillColor($r('app.color.text_tertiary'))
        .margin({ left: 6, right: 14 })
        .onClick(() => {
          this.showPwd = !this.showPwd;
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center) // 眼睛/叉与输入框水平中线对齐
    .backgroundColor($r('app.color.bg_chip'))
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  captchaRow() {
    Row() {
      Row() {
        TextInput({ placeholder: '验证码', text: this.captchaInput })
          .placeholderColor($r('app.color.text_tertiary'))
          .fontColor($r('app.color.text_primary'))
          .fontSize(15)
          .backgroundColor(Color.Transparent)
          .padding({ left: 14, right: 8 })
          .layoutWeight(1)
          .height(48)
          .onChange((v: string) => {
            this.captchaInput = v;
          })
      }
      .layoutWeight(1)
      .backgroundColor($r('app.color.bg_chip'))
      .borderRadius(12)

      if (JwApi.USE_MOCK) {
        Text(this.captcha)
          .fontSize(19)
          .fontWeight(FontWeight.Bold)
          .fontStyle(FontStyle.Italic)
          .letterSpacing(4)
          .fontColor($r('app.color.brand'))
          .backgroundColor($r('app.color.brand_light'))
          .textAlign(TextAlign.Center)
          .width(96)
          .height(48)
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => {
            this.loadCaptcha();
          })
      } else if (this.captchaImage.length > 0) {
        Image('data:image/jpeg;base64,' + this.captchaImage)
          .width(96)
          .height(48)
          .borderRadius(12)
          .margin({ left: 10 })
          .objectFit(ImageFit.Contain)
          .onClick(() => {
            this.loadCaptcha();
          })
      } else {
        Text('点击获取验证码')
          .fontSize(13)
          .fontColor($r('app.color.brand'))
          .backgroundColor($r('app.color.brand_light'))
          .textAlign(TextAlign.Center)
          .width(96)
          .height(48)
          .borderRadius(12)
          .margin({ left: 10 })
          .onClick(() => {
            this.loadCaptcha();
          })
      }
    }
    .width('100%')
    .margin({ bottom: 6 })
  }

  /** 历史账号展开列表（点击登录按钮下方时显示） */
  @Builder
  historyPanel() {
    Column() {
      Row() {
        Text('历史账号')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Blank()
        Text('清空')
          .fontSize(11)
          .fontColor($r('app.color.brand'))
          .onClick(() => {
            this.clearHistory();
          })
      }
      .width('100%')
      .margin({ bottom: 8 })

      ForEach(this.historyList, (item: Record<string, string>, index: number) => {
        Row() {
          if (index === 0) {
            Text('最近')
              .fontSize(10)
              .fontColor($r('app.color.brand_on'))
              .backgroundColor($r('app.color.brand'))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .borderRadius(6)
              .margin({ right: 8 })
          }

          Column() {
            Text(item['account'] ?? '')
              .fontSize(14)
              .fontColor($r('app.color.text_primary'))
            Text(item['password'] !== undefined && item['password'].length > 0 ? '已保存密码' : '无密码')
              .fontSize(10)
              .fontColor($r('app.color.text_tertiary'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Button('使用')
            .fontSize(12)
            .fontColor($r('app.color.brand_on'))
            .backgroundColor($r('app.color.brand'))
            .height(30)
            .padding({ left: 12, right: 12 })
            .borderRadius(8)
            .onClick(() => {
              this.pickHistory(item);
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .backgroundColor($r('app.color.bg_chip'))
        .borderRadius(10)
        .margin({ bottom: 6 })
      }, (item: Record<string, string>): string => item['account'] ?? '')

      Text('密码仅保存在本机（加密），不上传任何服务器。')
        .fontSize(10)
        .fontColor($r('app.color.text_tertiary'))
        .margin({ top: 4 })
    }
    .width('100%')
    .padding(12)
    .backgroundColor($r('app.color.bg_page'))
    .borderRadius(12)
    .margin({ top: 10 })
  }

  build() {
    Column() {
      // 顶部背景：品牌绿色渐变 + XJAU Helper logo
      Stack({ alignContent: Alignment.Top }) {
        // 顶部背景：品牌农大绿渐变
        Column()
          .width('100%')
          .height(this.isLandscape ? 240 : 300)
          .linearGradient({
            angle: 160,
            colors: [[$r('app.color.brand'), 0], [$r('app.color.brand_light'), 1]]
          })
          .overlay(this.bannerOverlay(), { align: Alignment.TopStart })

        Scroll() {
          Column() {
            // 顶部 XJAU Helper 圆角 logo
            Column() {
              Image($r('app.media.xjau_logo'))
                .width(this.isLandscape ? 96 : 120)
                .height(this.isLandscape ? 96 : 120)
                .objectFit(ImageFit.Contain)
                .borderRadius(28)
                .backgroundColor('#FFFFFF')
              Text('XJAU-Helper')
                .fontSize(22)
                .fontWeight(FontWeight.Bold)
                .fontColor('#FFFFFF')
                .margin({ top: 14 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .padding({ top: this.isLandscape ? 22 : 48, bottom: 28 })

            // 登录卡片
            Column() {
              Text('统一身份认证登录')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .margin({ bottom: 4 })
              Text('使用教务系统学号与密码登录')
                .fontSize(12)
                .fontColor($r('app.color.text_tertiary'))
                .width('100%')
                .margin({ bottom: 18 })

              this.inputRow('学号', this.account, (v: string) => {
                this.account = v;
              }, this.accountController)
              this.passwordRow('密码', this.password, (v: string) => {
                this.password = v;
              }, this.passwordController)

              if (this.showCaptcha) {
                this.captchaRow()
              }

              Row() {
                Checkbox({ name: 'remember' })
                  .select(this.remember)
                  .selectedColor($r('app.color.brand'))
                  .width(18)
                  .height(18)
                  .onChange((checked: boolean) => {
                    this.remember = checked;
                  })
                Text('记住学号')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ left: 4 })
                Blank()
                Text('忘记密码？')
                  .fontSize(12)
                  .fontColor($r('app.color.brand'))
                  .onClick(() => {
                    this.openForgotPassword();
                  })
              }
              .width('100%')
              .margin({ top: 8, bottom: 18 })

              Button() {
                Row() {
                  if (this.loading) {
                    LoadingProgress()
                      .width(18)
                      .height(18)
                      .color($r('app.color.brand_on'))
                      .margin({ right: 8 })
                  }
                  Text(this.loading ? '正在连接教务系统…' : '登  录')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.brand_on'))
                }
              }
              .width('100%')
              .height(48)
              .backgroundColor($r('app.color.brand'))
              .borderRadius(12)
              .enabled(!this.loading)
              .onClick(() => {
                this.doLogin();
              })

              // 历史账号入口（登录按钮下方，点击才展开）
              if (this.historyList.length > 0) {
                Row() {
                  Text(this.showHistory ? '收起历史账号' : `历史账号（${this.historyList.length}）`)
                    .fontSize(12)
                    .fontColor($r('app.color.brand'))
                  Image($r('app.media.list'))
                    .width(14)
                    .height(14)
                    .fillColor($r('app.color.brand'))
                    .margin({ left: 4 })
                }
                .width('100%')
                .padding({ top: 10, bottom: 6 })
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  // 展开/收起带过渡动画，避免跳变
                  animateTo({ duration: 220, curve: Curve.EaseOut }, () => {
                    this.showHistory = !this.showHistory;
                  })
                })

                if (this.showHistory) {
                  Column() {
                    this.historyPanel()
                  }
                  .width('100%')
                  .transition(TransitionEffect.OPACITY
                    .combine(TransitionEffect.translate({ y: -10 })))
                }
              }
            }
            .width('100%')
            .padding(20)
            .backgroundColor($r('app.color.bg_card'))
            .borderRadius(20)
            .shadow({ radius: 20, color: '#14000000', offsetY: 6 })

            // 底部操作区：网页版登录（失败后）+ 功能浏览（并入 Scroll，键盘弹出时可滚动到登录按钮）
            Column() {
              if (this.showWebLogin) {
                Button() {
                  Row() {
                    Text('改用网页版登录')
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.brand'))
                  }
                }
                .width('72%')
                .height(44)
                .backgroundColor($r('app.color.brand_light'))
                .borderRadius(22)
                .margin({ bottom: 10 })
                .enabled(!this.loading)
                .onClick(() => {
                  this.openWebLogin();
                })
              }

              Button() {
                Row() {
                  Text('功能浏览')
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.brand'))
                }
              }
              .width('72%')
              .height(44)
              .backgroundColor($r('app.color.brand_light'))
              .borderRadius(22)
              .margin({ bottom: 10 })
              .enabled(!this.loading)
              .onClick(() => {
                this.demoLogin();
              })

              Text('"功能浏览"使用虚拟数据，用以展示相关功能效果。\n若多次登录失败，可尝试使用网页教务系统进行登录。')
                .fontSize(11)
                .lineHeight(18)
                .textAlign(TextAlign.Center)
                .fontColor($r('app.color.text_tertiary'))
                .margin({ bottom: 16 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
            .margin({ top: 20 })
            .padding({ left: 24, right: 24 })
          }
          .width('100%')
          .padding({ left: 24, right: 24, bottom: 32 })
        }
        .scrollBar(BarState.Off)
        .width('100%')
        .height('100%')
        .padding({ top: px2vp(this.topInsetPx) })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    .bindSheet($$this.showWeb, this.webSheet, {
      height: SheetSize.LARGE,
      dragBar: false,
      backgroundColor: $r('app.color.bg_page'),
      title: { title: AppState.webTitle }
    })
  }

  @Builder
  bannerOverlay() {
    // 暗色蒙板，让登录卡片文字更清晰
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor('#33000000')
  }

  @Builder
  webSheet() {
    WebSurface()
  }
}
