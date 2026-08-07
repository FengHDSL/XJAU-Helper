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
import { HttpClient } from '../api/HttpClient';
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
  @State remember: boolean = false; // 默认不勾选（用户隐私优先，每次启动重新输入密码）
  @State loading: boolean = false;
  @State showWeb: boolean = false;
  @State showHistory: boolean = false;
  @State historyList: Record<string, string>[] = [];
  @State isLandscape: boolean = false;
  @State showPwd: boolean = false; // 密码明文/密文切换
  @State showPrivacy: boolean = false; // 隐私协议弹窗（首次启动未同意时显示）
  @State privacyAgreedAt: string = ''; // 隐私协议同意时间（右下角展示用）
  private accountController: TextInputController = new TextInputController();
  private passwordController: TextInputController = new TextInputController();
  onSuccess: () => void = () => {
  };
  /** 自动重登模式（冷启动恢复登录态）：显示加载符号、禁用交互、静默登录 */
  autoRelogin: boolean = false;
  /** 前往登录页模式（不退出登录）：左上角显示返回按钮 */
  showBack: boolean = false;
  /** 返回按钮回调（showBack 时显示，点击返回应用首页） */
  onBack: () => void = () => {
  };
  private landscapeListener: mediaquery.MediaQueryListener | null = null;

  /** 页面出现：读取历史账号并填充、注册屏幕方向监听、检查隐私协议 */
  aboutToAppear(): void {
    // 键盘避让设为 RESIZE：键盘弹出时页面缩小而非上移，登录按钮可滚动到键盘上方点击
    try {
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    } catch (e) {
      // ignore
    }
    // 隐私协议：未同意时强制弹出（不同意时只能使用"功能浏览"）
    this.privacyAgreedAt = DataStore.getPrivacyAgreedAt();
    if (!DataStore.isPrivacyAgreed()) {
      this.showPrivacy = true;
    }
    // 自动重登模式：用保存的凭据静默登录（显示加载、禁用交互），不再让用户手动输入
    if (this.autoRelogin) {
      const autoAcct: string = DataStore.get(DataStore.KEY_AUTO_ACCOUNT);
      const autoPwd: string = DataStore.decodePwd(DataStore.get(DataStore.KEY_AUTO_PWD));
      if (autoAcct.length > 0 && autoPwd.length > 0) {
        this.account = autoAcct;
        this.password = autoPwd;
        this.accountController.addText(autoAcct);
        this.passwordController.addText(autoPwd);
        this.loading = true;
        // 延迟一帧让 loading 先渲染，再发起自动登录
        setTimeout(() => {
          this.doLogin();
        }, 150);
      }
      return;
    }
    // 读取历史账号（最近登录的账号+密码）。注意：默认不勾选"记住密码"，
    // 因此即使有历史记录也只填账号、不填密码，避免出现"取消勾选却仍然保存了密码"的体验割裂。
    this.historyList = DataStore.getAccountList();
    if (this.historyList.length > 0) {
      this.account = this.historyList[0]['account'] ?? '';
      if (this.remember) {
        this.password = DataStore.decodePwd(this.historyList[0]['password'] ?? '');
      }
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
    // 必须先同意隐私协议
    if (!DataStore.isPrivacyAgreed()) {
      this.showPrivacy = true;
      return;
    }
    // 首次登录：让用户选择登录方式（默认值）
    if (DataStore.getLoginMode().length === 0) {
      const picked: number = await new Promise<number>((resolve) => {
        promptAction.showDialog({
          title: '选择登录方式',
          message: '「自动重新登录」会在每次打开应用时用账号密码重新登录，确保服务可用（推荐）。\n\n「旧版本登录」不会自动重新登录，遇到「首页底部校历为空」等情况，可点左上角「重登」按钮手动重新登录。',
          buttons: [
            { text: '旧版本登录', color: '#888888' },
            { text: '自动重新登录', color: '#079841' }
          ]
        }).then((r: promptAction.ShowDialogSuccessResponse) => {
          resolve(r.index);
        }).catch(() => {
          resolve(0);
        });
      });
      // picked=0 = 旧版本；picked=1 = 自动重新登录
      DataStore.setLoginMode(picked === 1 ? 'auto' : 'legacy');
    }
    if (this.account.trim().length === 0) {
      promptAction.showToast({ message: '请输入学号' });
      return;
    }
    if (this.password.length === 0) {
      promptAction.showToast({ message: '请输入密码' });
      return;
    }
    // 真实登录：强制走真实接口，关闭离线模式
    JwApi.USE_MOCK = false;
    HttpClient.setOfflineMode(false);
    this.loading = true;
    const captchaVal: string = this.showCaptcha ? this.captchaInput.trim() : '';
    const result: LoginResult = await JwApi.login(this.account.trim(), this.password, captchaVal);
    this.loading = false;

    if (result.success && result.profile !== null) {
      AppState.profile = result.profile;
      AppState.account = this.account.trim();
      // 记录历史账号：勾选"记住密码"保存密码；未勾选时保留该账号已保存的密码（不覆盖为空）
      const historyPwd: string = this.savedPasswordOf(this.account.trim());
      const pwdToSave: string = this.remember ? this.password : historyPwd;
      DataStore.addAccount(this.account.trim(), pwdToSave);
      this.historyList = DataStore.getAccountList();
      // 保存自动重登凭据（冷启动时静默重新登录刷新会话，否则服务端会话过期后功能不可用）
      DataStore.put(DataStore.KEY_AUTO_ACCOUNT, this.account.trim());
      DataStore.put(DataStore.KEY_AUTO_PWD, DataStore.encodePwd(this.password));
      DataStore.setLoginMethod('pwd');
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
    }
  }

  /** 在应用内 WebView 打开教务系统登录页，用于"网页版直接登录"的兜底方案。 */
  private openWebLogin(): void {
    if (JwApi.USE_MOCK) {
      promptAction.showToast({ message: '当前模式暂不支持' });
      return;
    }
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
    if (JwApi.USE_MOCK) {
      promptAction.showToast({ message: '当前模式暂不支持' });
      return;
    }
    AppState.webLoginMode = false;
    AppState.onWebLogin = null;
    AppState.webUrl = Const.FORGOT_PASSWORD_URL;
    AppState.webTitle = '找回密码';
    this.showWeb = true;
  }

  /** 功能浏览（原"游客模式"）：临时切到 mock 数据，用占位账号直接登录（无需真实学号密码）。 */
  private async demoLogin(): Promise<void> {
    JwApi.USE_MOCK = true;
    HttpClient.setOfflineMode(true); // 禁用所有网络请求
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

  /** 同意隐私协议：记录时间、关闭弹窗 */
  private agreePrivacy(): void {
    DataStore.setPrivacyAgreed();
    this.privacyAgreedAt = DataStore.getPrivacyAgreedAt();
    this.showPrivacy = false;
  }

  /** 暂不同意隐私协议：关闭弹窗，未登录账号前仅可使用"功能浏览" */
  private declinePrivacy(): void {
    this.showPrivacy = false;
  }

  /** 查询某账号在历史记录中已保存的密码（无则空串） */
  private savedPasswordOf(account: string): string {
    const list: Record<string, string>[] = DataStore.getAccountList();
    for (const it of list) {
      if (it['account'] === account) {
        return DataStore.decodePwd(it['password'] ?? '');
      }
    }
    return '';
  }

  /** 选中历史账号 → 填充账号密码并折叠面板
   *  历史记录中保存了密码（勾选"记住密码"登录）则一并填充，否则只填账号 */
  private pickHistory(item: Record<string, string>): void {
    const acct: string = item['account'] ?? '';
    this.account = acct;
    const savedPwd: string = DataStore.decodePwd(item['password'] ?? '');
    this.password = savedPwd;
    // TextInput 构造器 text 参数不会响应 @State 变化，必须通过 controller 强制刷新
    this.accountController.deleteText();
    if (acct.length > 0) {
      this.accountController.addText(acct);
    }
    this.passwordController.deleteText();
    if (savedPwd.length > 0) {
      this.passwordController.addText(savedPwd);
    }
    this.showHistory = false;
    this.showCaptcha = false;
    this.captchaInput = '';
  }

  /** 删除单个历史账号（带动画，swipeAction 滑动删除） */
  private deleteHistory(index: number): void {
    if (index < 0 || index >= this.historyList.length) {
      return;
    }
    const removedAcct: string = this.historyList[index]['account'] ?? '';
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      this.historyList.splice(index, 1);
    });
    // 持久化剩余列表
    DataStore.put(DataStore.KEY_ACCOUNTS, JSON.stringify(this.historyList));
    // 若删除的是"最近登录"，回退到剩余列表第一个
    if (DataStore.get(DataStore.KEY_LAST_ACCOUNT) === removedAcct) {
      DataStore.put(DataStore.KEY_LAST_ACCOUNT,
        this.historyList.length > 0 ? (this.historyList[0]['account'] ?? '') : '');
    }
    // 全部删完时收起面板
    if (this.historyList.length === 0) {
      this.showHistory = false;
    }
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

      List({ space: 6 }) {
        ForEach(this.historyList, (item: Record<string, string>, index: number) => {
          ListItem() {
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
          }
          .swipeAction({
            end: this.swipeDeleteButton(index)
          })
        }, (item: Record<string, string>): string => item['account'] ?? '')
      }
      .width('100%')
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: 340 })

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

  /** 历史账号左滑删除按钮（SwipeAction end 侧） */
  @Builder
  swipeDeleteButton(index: number) {
    Row() {
      Text('删除')
        .fontSize(13)
        .fontColor('#FFFFFF')
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('#F0524D')
    .borderRadius(10)
    .onClick(() => {
      this.deleteHistory(index);
    })
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

        // 前往登录页模式：登录按钮左侧显示灰色返回按钮（见登录按钮区域）
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
                Text('记住密码')
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

              Row() {
                // 前往登录页模式：灰色返回按钮（左侧，与登录按钮等宽等高，合计与原登录按钮相同）
                if (this.showBack) {
                  Button() {
                    Text('‹ 返回')
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.text_secondary'))
                  }
                  .layoutWeight(1)
                  .height(48)
                  .backgroundColor($r('app.color.bg_chip'))
                  .borderRadius(12)
                  .margin({ right: 10 })
                  .enabled(!this.loading)
                  .onClick(() => {
                    this.onBack();
                  })
                }
                // 登录按钮
                Button() {
                  Row() {
                    if (this.loading) {
                      LoadingProgress()
                        .width(18)
                        .height(18)
                        .color($r('app.color.brand_on'))
                        .margin({ right: 8 })
                    }
                    Text(this.loading ? '正在登录' : '登  录')
                      .fontSize(16)
                      .fontWeight(FontWeight.Medium)
                      .fontColor($r('app.color.brand_on'))
                  }
                }
                .layoutWeight(1)
                .height(48)
                .backgroundColor($r('app.color.brand'))
                .borderRadius(12)
                .enabled(!this.loading)
                .onClick(() => {
                  this.doLogin();
                })
              }
              .width('100%')

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

            // 底部操作区：网页版登录（默认显示）+ 功能浏览
            Column() {
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
      // 网页版登录/找回密码弹窗（挂内层 Stack，与外层隐私弹窗分离避免同组件多 bindSheet 失效）
      .bindSheet($$this.showWeb, this.webSheet, {
        height: SheetSize.LARGE,
        dragBar: false,
        backgroundColor: $r('app.color.bg_page'),
        title: { title: AppState.webTitle }
      })

      // 自动重登提示：居中弹窗样式（不遮罩页面、不拦截点击）
      if (this.autoRelogin && this.loading) {
        Column() {
          Text('正在自动登录…')
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
        }
        .padding({ left: 28, right: 28, top: 18, bottom: 18 })
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius(14)
        .shadow({ radius: 24, color: '#33000000', offsetY: 6 })
        .position({ x: '50%', y: '45%' })
        .translate({ x: '-50%' })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
    // 隐私协议全屏弹窗（挂外层 Column；网页版登录挂内层 Stack，避免 bindSheet 互相覆盖）
    .bindSheet($$this.showPrivacy, this.privacySheet(), {
      height: SheetSize.LARGE,
      dragBar: true,
      backgroundColor: $r('app.color.bg_page'),
      showClose: true
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

  /** 隐私协议全屏弹窗：协议正文 + 底部"同意"按钮 + 右下角已同意时间 */
  @Builder
  privacySheet() {
    Column() {
      // 标题
      Row() {
        Text('隐私协议')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 12 })

      // 协议正文（可滚动）
      Scroll() {
        Column() {
          this.privacySection('1. 信息收集',
            '本应用仅在您主动登录时收集学号与密码，用于访问学校教务系统获取课表、成绩、考试等数据。' +
              '密码使用教务系统 RSA 公钥加密传输，本地仅保存登录状态标识，不存储明文密码。')
          this.privacySection('2. 信息存储',
            '课表、成绩、考试、头像等数据缓存仅保存在您设备本地（应用私有目录），不上传任何服务器。' +
              '您可在"我的-清除缓存"中随时删除全部本地数据。')
          this.privacySection('3. 权限使用',
            '本应用仅申请网络权限（联网获取教务数据）与日历权限（将考试安排写入系统日历提醒）。' +
              '不申请位置、相册、通讯录、麦克风等与教务功能无关的权限。')
          this.privacySection('4. 数据安全',
            '本地缓存不进行二次上传；登录会话仅用于教务系统接口调用。应用被卸载时，本地缓存将被系统一并清除。')
          this.privacySection('5. 第三方服务',
            '桌面卡片、快捷方式等系统能力仅在本机展示应用自身数据，不涉及第三方 SDK 数据共享。')
          this.privacySection('6. 功能浏览',
            '未同意本协议时，您仍可使用"功能浏览"模式查看应用界面布局，但该模式不连接任何服务器，' +
              '使用本地虚拟数据，不读取、存储任何真实个人信息。')
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 4, bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      // 底部操作行：左侧"暂不同意" + 右侧"同意并继续"；左下角显示已同意时间
      Column() {
        // 已同意时间（未同意时显示提示）
        if (this.privacyAgreedAt.length > 0) {
          Text('已签订时间：' + this.privacyAgreedAt)
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .textAlign(TextAlign.End)
            .margin({ bottom: 8 })
        } else {
          Text('未同意将无法使用账号登录，仅可使用"功能浏览"')
            .fontSize(11)
            .fontColor($r('app.color.text_tertiary'))
            .width('100%')
            .textAlign(TextAlign.End)
            .margin({ bottom: 8 })
        }
        Row() {
          Button('暂不同意')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .backgroundColor($r('app.color.bg_chip'))
            .height(42)
            .layoutWeight(1)
            .borderRadius(21)
            .onClick(() => {
              this.declinePrivacy();
            })
          Button('同意并继续')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand_on'))
            .backgroundColor($r('app.color.brand'))
            .height(42)
            .layoutWeight(1)
            .borderRadius(21)
            .margin({ left: 12 })
            .onClick(() => {
              this.agreePrivacy();
            })
        }
        .width('100%')
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 20 })
      .backgroundColor($r('app.color.bg_card'))
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_page'))
  }

  @Builder
  privacySection(title: string, content: string) {
    Column() {
      Text(title)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 6 })
      Text(content)
        .fontSize(13)
        .lineHeight(22)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 16 })
  }
}
