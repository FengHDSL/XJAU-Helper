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
import { KeyboardAvoidMode, promptAction, display } from '@kit.ArkUI';
import { mediaquery } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { HttpClient } from '../api/HttpClient';
import { JwApi } from '../api/JwApi';
import { CasCaptchaRequiredError } from '../api/CasApi';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { DataStore } from '../common/DataStore';
import { LogStore } from '../common/LogStore';
import { DEVELOPER_DECLARATION, DeclarationSection } from '../common/PrivacyText';
import { LoginResult } from '../model/Models';
import { LogPage } from './LogPage';
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
  /** 7天免登录：勾选后网页版/服务大厅登录成功会持久化教务系统会话 Cookie，便于下次自动重登 */
  @State remember7d: boolean = AppState.remember7d;
  @State loading: boolean = false;
  @State showWeb: boolean = false;
  /** 网页版登录目标（jw=教务系统直登 / hall=服务大厅），标题栏切换用 */
  @State webLoginTarget: string = AppState.webLoginTarget;
  /** 网页版登录 WebView 控制器（标题栏切换网址时重新加载用） */
  private webCtrl: webview.WebviewController | null = null;
  @State showHistory: boolean = false;
  @State historyList: Record<string, string>[] = [];
  @State isLandscape: boolean = false;
  @State showPwd: boolean = false; // 密码明文/密文切换
  @State showPrivacy: boolean = false; // 隐私协议弹窗（首次启动未同意时显示）
  @State showDeclaration: boolean = false; // 开发者声明弹窗（同意隐私协议后首次展示）
  @State privacyAgreedAt: string = ''; // 隐私协议同意时间（右下角展示用）
  @State showRiskTip: boolean = false; // 账号风控提醒弹窗（开发者声明之后首次展示）
  @State loginMode: string = 'auto'; // 重登方式（auto=自动重登 / legacy=手动重登），切换后实时刷新显示
  @State loginSystem: string = 'service'; // 登录系统（service=服务大厅登录（新版）CAS / original=教务登录（原版）RSA 直登），默认服务大厅登录
  @State sheetWidth: Dimension = '100%'; // 半模态面板宽度（≥600vp 视为平板，与课程表页面一致）
  /** 日志调试模式（AppStorage 响应式）：登录页连点图标 5 次 + 密码可开启；功能浏览模式同样生效 */
  @StorageProp('logEnabled') logEnabled: boolean = false;
  @StorageProp('logCollecting') logCollecting: boolean = true;
  /** 应用图标连点计数（5 次内有效） */
  @State logTapCount: number = 0;
  /** 日志调试密码输入弹窗开关 */
  @State showLogSheet: boolean = false;
  @State logPwd: string = '';
  /** 连点计时器（超时重置计数） */
  private logTapTimer: number = -1;
  /** 登录是否已取消（侧滑返回 / 20s 超时自动取消） */
  private loginCancelled: boolean = false;
  /** 登录超时计时器（20s 无响应自动取消，便于日志收集） */
  private loginTimer: number = -1;
  /** 是否内嵌展示日志详情页（登录页不在 Navigation 栈，不能 pushPath，改用内嵌切换） */
  @State showLogPage: boolean = false;

  private privacyController: webview.WebviewController = new webview.WebviewController();
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
    // 半模态面板宽度：平板（≥600vp）取 min(屏宽*0.7, 840)vp 加宽并封顶；手机全宽。与课程表页面一致。
    try {
      const d = display.getDefaultDisplaySync();
      const screenVp: number = px2vp(d.width);
      this.sheetWidth = screenVp >= 600 ? `${Math.min(Math.round(screenVp * 0.7), 840)}vp` : '100%';
    } catch (e) {
      this.sheetWidth = '100%';
    }
    // 隐私协议：未同意时强制弹出（不同意时只能使用"功能浏览"）
    this.privacyAgreedAt = DataStore.getPrivacyAgreedAt();
    if (!DataStore.isPrivacyAgreed()) {
      this.showPrivacy = true;
    }
    // 重登方式：读取本地配置（未设置默认自动重登）
    this.loginMode = DataStore.getLoginMode().length > 0 ? DataStore.getLoginMode() : 'auto';
    // 登录系统：恢复上次登录方式（"重新登录"时沿用教务登录/服务大厅登录，避免用错方式）
    const savedSystem: string = DataStore.get(DataStore.KEY_LOGIN_SYSTEM);
    if (savedSystem === 'service' || savedSystem === 'original') {
      this.loginSystem = savedSystem;
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

  /** 页面消失（侧滑返回 / 路由离开）：若登录进行中则取消登录（方便收集日志，避免后台残留请求） */
  aboutToDisappear(): void {
    this.landscapeListener = null;
    if (this.loading) {
      this.cancelLogin('页面返回取消登录');
    }
  }

  /** 取消登录：置取消标志、停止 loading、清除超时计时器、记录日志 */
  private cancelLogin(reason: string): void {
    this.loginCancelled = true;
    this.loading = false;
    if (this.loginTimer >= 0) {
      clearTimeout(this.loginTimer);
      this.loginTimer = -1;
    }
    LogStore.log('登录', '登录', '取消', reason);
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

  /** 加载/刷新验证码：mock 用本地随机码占位；真实模式从服务端拉取验证码图片。
   *  日志调试开启时把验证码图片保存为附件（供日志导出 zip 收集，辅助定位登录失败原因）。 */
  private loadCaptcha(): void {
    if (JwApi.USE_MOCK) {
      this.captcha = this.randomCode();
      this.captchaInput = '';
      return;
    }
    this.captchaInput = '';
    JwApi.getCaptcha().then((b64: string) => {
      this.captchaImage = b64;
      this.saveCaptchaAttachment(b64);
    }).catch(() => {
      this.captchaImage = '';
    });
  }

  /** 验证码 base64 存为附件文件（仅日志调试开启时；供日志导出打包 zip） */
  private saveCaptchaAttachment(b64: string): void {
    if (!LogStore.enabled() || b64.length === 0) {
      return;
    }
    try {
      const ctx: common.Context | null = AppState.context;
      if (ctx === null) {
        return;
      }
      const dir: string = `${ctx.cacheDir}/${LogStore.ATTACH_DIR}`;
      try {
        fileIo.mkdirSync(dir);
      } catch (e) {
        // 目录已存在，忽略
      }
      const b64Helper: util.Base64Helper = new util.Base64Helper();
      const bytes: Uint8Array = b64Helper.decodeSync(b64);
      const path: string = `${dir}/captcha_${new Date().getTime()}.jpg`;
      const file = fileIo.openSync(path,
        fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      fileIo.writeSync(file.fd, bytes.buffer);
      fileIo.closeSync(file);
      LogStore.addAttachment(path);
    } catch (e) {
      // ignore（附件保存失败不影响登录）
    }
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
    // 首次登录：未设置重登方式时默认使用"自动重登"（用户可在登录卡片下方的固定入口随时更改）
    if (DataStore.getLoginMode().length === 0) {
      DataStore.setLoginMode('auto');
      this.loginMode = 'auto';
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
    this.loginCancelled = false;
    // 登录 20s 无响应自动取消（便于收集日志定位原因；超时后按取消处理，不再继续等待）
    if (this.loginTimer >= 0) {
      clearTimeout(this.loginTimer);
    }
    this.loginTimer = setTimeout(() => {
      if (this.loading) {
        this.cancelLogin('登录等待超时（20s），已自动取消');
        promptAction.showToast({ message: '登录超时，已自动取消' });
      }
    }, 20000);
    const captchaVal: string = this.showCaptcha ? this.captchaInput.trim() : '';
    let result: LoginResult;
    try {
      result = await JwApi.login(this.account.trim(), this.password, captchaVal, this.loginSystem);
    } catch (e) {
      if (this.loginTimer >= 0) {
        clearTimeout(this.loginTimer);
        this.loginTimer = -1;
      }
      if (this.loginCancelled) {
        return;
      }
      this.loading = false;
      // 该账号被要求图形验证码：原生登录无法处理，自动打开网页版（WebView）CAS 页兜底，
      // 不作为可选登录模式暴露给用户（用户明确要求不要「网页登录」选项）。
      if (e instanceof CasCaptchaRequiredError) {
        promptAction.showToast({ message: '该账号需要验证码，正在打开网页版登录…', duration: 2000 });
        this.openWebLogin();
      } else {
        promptAction.showToast({ message: '登录失败，请检查账号密码或网络', duration: 2500 });
      }
      return;
    }
    if (this.loginTimer >= 0) {
      clearTimeout(this.loginTimer);
      this.loginTimer = -1;
    }
    // 已被侧滑返回/超时取消：不再处理结果（防止返回后仍弹 Toast / 跳转）
    if (this.loginCancelled) {
      return;
    }
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
      // 登录方式：教务登录→pwd；服务大厅登录（CAS）已在 loginViaCas 内写 cas，勿覆盖
      if (this.loginSystem === 'original') {
        DataStore.setLoginMethod('pwd');
      }
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

  /** 打开网页版登录（WebView）：标题栏可切换"教务系统 / 服务大厅"两个登录网址，
   *  登录成功后按目标类型取 Cookie 并自动登录教务系统（服务大厅模式由 WebSurface 桥接 jwglxt）。 */
  private openWebLogin(): void {
    if (JwApi.USE_MOCK && !AppState.debugNetwork) {
      promptAction.showToast({ message: '当前模式禁止使用' });
      return;
    }
    AppState.webLoginMode = true;
    AppState.onWebLogin = () => {
      this.showWeb = false;
      this.onSuccess();
    };
    this.webLoginTarget = AppState.webLoginTarget;
    // 服务大厅 = authserver CAS 登录页（service=rhmh）；教务系统 = jwxt 登录页
    AppState.webUrl = this.webLoginTarget === 'hall' ? Const.CAS_LOGIN_URL : Const.WEB_LOGIN_URL;
    AppState.webTitle = '网页版登录';
    this.showWeb = true;
  }

  /** 网页版登录标题栏切换目标（服务大厅 ↔ 教务系统）：更新目标并让 WebView 重新加载对应网址 */
  private switchWebTarget(target: string): void {
    if (this.webLoginTarget === target) {
      return;
    }
    this.webLoginTarget = target;
    AppState.webLoginTarget = target;
    AppState.webUrl = target === 'hall' ? Const.CAS_LOGIN_URL : Const.WEB_LOGIN_URL;
    if (this.webCtrl !== null) {
      this.webCtrl.loadUrl(AppState.webUrl);
    }
  }

  /** 当前重登方式文案（自动重登 / 手动重登） */
  private loginModeText(): string {
    return this.loginMode === 'auto' ? '自动重登' : '手动重登';
  }

  /** 切换登录系统（service=服务大厅登录（新版）CAS / original=教务登录（原版）RSA 直登），切换后实时刷新显示
   *  重登方式联动：教务登录默认自动重登；服务大厅登录为手动重登（教务会话不可持久化，靠 CASTGC 静默桥接）。 */
  private setLoginSystem(system: string): void {
    this.loginSystem = system;
    if (system === 'service') {
      // 服务大厅登录：手动重登（冷启动用 CASTGC 从服务大厅重新打开教务系统，不依赖账号密码自动重登）
      DataStore.setLoginMode('legacy');
      this.loginMode = 'legacy';
    } else {
      // 教务登录：自动重登（保存的账号密码自动登录教务系统）
      DataStore.setLoginMode('auto');
      this.loginMode = 'auto';
    }
  }

  /** 更改重登方式（固定入口，可随时切换，切换后立即刷新显示） */
  private changeLoginMode(): void {
    const current: string = this.loginModeText();
    promptAction.showActionMenu({
      title: `选择重登方式（当前：${current}）`,
      buttons: [
        { text: '自动重登', color: '#079841' },
        { text: '手动重登', color: '#888888' }
      ]
    }).then((res: promptAction.ActionMenuSuccessResponse) => {
      if (res.index === 0) {
        DataStore.setLoginMode('auto');
        this.loginMode = 'auto';
        promptAction.showToast({ message: '已切换为自动重登' });
      } else if (res.index === 1) {
        DataStore.setLoginMode('legacy');
        this.loginMode = 'legacy';
        promptAction.showToast({ message: '已切换为手动重登' });
      }
    }).catch(() => {
      // 取消选择
    });
  }

  /** 弹窗说明两种重登方式的区别（问号图标点击） */
  private showLoginModeInfo(): void {
    promptAction.showDialog({
      title: '重登方式说明',
      message: '「教务登录」默认自动重登：每次重新打开应用用保存的账号密码自动登录教务系统，免去手动点击。\n\n「服务大厅登录」为手动重登：教务系统会话不可持久化，重新打开应用会自动从服务大厅重新打开教务系统刷新（无需重新输入密码）；仅当该刷新失败时才需在首页点击「重登」按钮。\n\n重登方式可在下方随时手动更改。',
      buttons: [
        { text: '我知道了', color: '#079841', primary: true }
      ]
    });
  }

  /** 打开找回密码网页（学校统一身份认证平台），在应用内 WebView 中展示。 */
  private openForgotPassword(): void {
    if (JwApi.USE_MOCK && !AppState.debugNetwork) {
      promptAction.showToast({ message: '当前模式禁止使用' });
      return;
    }
    AppState.webLoginMode = false;
    AppState.onWebLogin = null;
    AppState.webUrl = Const.FORGOT_PASSWORD_URL;
    AppState.webTitle = '找回密码';
    this.showWeb = true;
  }

  /** 日志调试：应用图标连点 5 次触发开关（已开启 → 退出确认；未开启 → 密码输入）。
   *  开启后真实登录/功能浏览模式都会正常收集日志，管理在"我的 → 日志详情"。 */
  private onLogoTapped(): void {
    this.logTapCount++;
    if (this.logTapTimer >= 0) {
      clearTimeout(this.logTapTimer);
    }
    // 3 秒内未继续点击则重置计数
    this.logTapTimer = setTimeout(() => {
      this.logTapCount = 0;
    }, 3000);
    if (this.logTapCount < 5) {
      return;
    }
    this.logTapCount = 0;
    this.toggleLogDebug();
  }

  /** 日志调试开关（日志入口点击 / 连点图标满 5 次共用）：
   *  已开启 → 弹"是否退出"；未开启 → 弹密码输入（admin） */
  private toggleLogDebug(): void {
    if (AppState.logEnabled) {
      // 已开启：询问是否退出（同时关闭功能浏览联网，清除已收集日志与附件）
      promptAction.showDialog({
        title: '日志调试已开启',
        message: '当前正在收集登录与使用日志，且功能浏览模式允许联网。是否退出调试模式？',
        buttons: [
          { text: '取消', color: '#888888' },
          { text: '退出调试模式', color: '#DB5252', primary: true }
        ]
      }).then((res) => {
        if (res.index === 1) {
          AppState.logEnabled = false;
          AppState.debugNetwork = false;
          LogStore.clearAll(); // 退出日志调试：自动删除已收集日志与附件
          promptAction.showToast({ message: '已退出调试模式，日志已清除' });
        }
      });
    } else {
      // 未开启：弹密码输入
      this.logPwd = '';
      this.showLogSheet = true;
    }
  }

  /** 提交日志调试密码：admin（登录页入口——开启日志收集，并同时允许功能浏览模式联网） */
  private submitLogPwd(): void {
    if (this.logPwd !== 'admin') {
      promptAction.showToast({ message: '密码错误' });
      return;
    }
    this.showLogSheet = false;
    if (AppState.logEnabled) {
      promptAction.showToast({ message: '日志调试已开启' });
      return;
    }
    AppState.logEnabled = true;
    // 功能浏览模式允许联网（debugNetwork）：进入功能浏览时网络请求不再被离线模式拦截
    AppState.debugNetwork = true;
    LogStore.log('日志调试', '开启', '成功', '登录页入口开启（日志收集 + 功能浏览允许联网）');
    promptAction.showToast({ message: '日志调试已开启，开始收集登录与使用日志' });
  }

  /** 日志调试密码输入弹窗 */
  @Builder
  logDebugSheet() {
    Column() {
      Text('日志调试')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ top: 16, bottom: 8 })

      Text('输入密码以开启日志调试（收集登录与使用日志，用于定位登录失败等问题的原因）')
        .fontSize(12)
        .fontColor($r('app.color.text_tertiary'))
        .width('100%')
        .margin({ bottom: 12 })

      TextInput({ text: this.logPwd, placeholder: '请输入密码' })
        .fontSize(15)
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_tertiary'))
        .backgroundColor($r('app.color.bg_chip'))
        .borderRadius(10)
        .height(44)
        .width('100%')
        .onChange((v: string) => {
          this.logPwd = v;
        })
        .onSubmit(() => {
          this.submitLogPwd();
        })

      Button('确认')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.brand_on'))
        .backgroundColor($r('app.color.brand'))
        .height(40)
        .width('100%')
        .borderRadius(20)
        .margin({ top: 12, bottom: 16 })
        .onClick(() => {
          this.submitLogPwd();
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
    .backgroundColor($r('app.color.bg_page'))
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

  /** 同意隐私协议：记录时间、关闭弹窗，随后展示开发者声明（仅首次） */
  private agreePrivacy(): void {
    DataStore.setPrivacyAgreed();
    this.privacyAgreedAt = DataStore.getPrivacyAgreedAt();
    this.showPrivacy = false;
    // 切换展示开发者声明（本应用由新疆农业大学学生独立开发等）
    setTimeout(() => {
      this.showDeclaration = true;
    }, 300);
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
    // 日志调试开启后，从登录页内嵌查看日志详情（登录页不在 Navigation 栈，不能 pushPath）
    Stack() {
      if (this.showLogPage) {
        LogPage({
          embedded: true,
          onBackCallback: () => {
            this.showLogPage = false;
          }
        })
      } else {
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
            // 顶部 XJAU Helper 圆角 logo（连点 5 次开启日志调试：登录页亦可收集登录数据定位登录失败）
            Column() {
              Image($r('app.media.startIcon'))
                .width(this.isLandscape ? 96 : 120)
                .height(this.isLandscape ? 96 : 120)
                .objectFit(ImageFit.Contain)
                .borderRadius(28)
                .backgroundColor('#FFFFFF')
                .onClick(() => {
                  this.onLogoTapped();
                })
              Text('新农助手')
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
              Text(this.loginSystem === 'service' ? '服务大厅登录' : '教务登录')
                .fontSize(17)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .margin({ bottom: 4 })
              Text(this.loginSystem === 'service' ? '通过统一身份认证登录，登录后自动打开教务系统' : '使用教务系统学号与密码登录')
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
                // 7天免登录（CASTGC）仅属于新版（服务大厅/CAS）登录系统，原版不显示
                if (this.loginSystem === 'service') {
                  Checkbox({ name: 'remember7d' })
                    .select(this.remember7d)
                    .selectedColor($r('app.color.brand'))
                    .width(18)
                    .height(18)
                    .margin({ left: 10 })
                    .onChange((checked: boolean) => {
                      this.remember7d = checked;
                      AppState.remember7d = checked;
                    })
                  Text('7天免登录')
                    .fontSize(12)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ left: 4 })
                }
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
                  Image($r('app.media.list_bullet'))
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

            // 底部操作区：重登方式 + 登录系统切换（服务大厅登录 ↔ 教务登录）+ 网页版登录 + 功能浏览
            Column() {
              // 重登方式（固定入口，可随时更改）
              Row() {
                Image($r('app.media.question'))
                  .width(14)
                  .height(14)
                  .margin({ right: 4 })
                  .fillColor($r('app.color.text_tertiary'))
                  .onClick(() => {
                    this.showLoginModeInfo();
                  })
                Text('重登方式')
                  .fontSize(13)
                  .fontColor($r('app.color.text_secondary'))
                Blank()
                Text(this.loginModeText())
                  .fontSize(13)
                  .fontColor($r('app.color.brand'))
                Text('›')
                  .fontSize(13)
                  .fontColor($r('app.color.text_tertiary'))
                  .margin({ left: 2 })
              }
              .width('72%')
              .padding({ left: 18, right: 14, top: 10, bottom: 10 })
              .backgroundColor($r('app.color.bg_chip'))
              .borderRadius(22)
              .margin({ bottom: 10 })
              .enabled(!this.loading)
              .onClick(() => {
                this.changeLoginMode();
              })

              // 登录系统切换按钮：显示要切换到的目标模式（当前服务大厅登录 → 点按切教务登录，反之亦然）
              Button() {
                Row() {
                  Text(this.loginSystem === 'service' ? '教务登录' : '服务大厅登录')
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
                this.setLoginSystem(this.loginSystem === 'service' ? 'original' : 'service');
              })

              // 网页版登录：在 WebView 打开统一身份认证（CAS）登录页（验证码等场景兜底）
              Button() {
                Row() {
                  Text('网页版登录')
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

              // 日志调试入口（功能浏览按钮下方）：仅日志调试开启后显示；点击进入日志查看页
              // （开启方式：连点顶部应用图标 5 次 + 密码 admin；真实登录/功能浏览模式均收集日志）
              if (this.logEnabled) {
                Row() {
                  Text('日志调试')
                    .fontSize(13)
                    .fontColor($r('app.color.text_secondary'))
                  Blank()
                  Text(this.logCollecting ? '● 收集中' : '○ 已暂停')
                    .fontSize(12)
                    .fontColor(this.logCollecting ? $r('app.color.brand') : $r('app.color.text_tertiary'))
                  Text('›')
                    .fontSize(13)
                    .fontColor($r('app.color.text_tertiary'))
                    .margin({ left: 2 })
                }
                .width('72%')
                .padding({ left: 18, right: 14, top: 10, bottom: 10 })
                .backgroundColor($r('app.color.bg_chip'))
                .borderRadius(22)
                .margin({ bottom: 10 })
                .onClick(() => {
                  // 登录页不在 Navigation 栈：内嵌展示日志详情（embedded 模式），不走 pushPath
                  this.showLogPage = true;
                })
              }

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
        preferType: SheetType.BOTTOM,
        width: this.sheetWidth,
        showClose: true,
        backgroundColor: $r('app.color.bg_page'),
        title: () => {
          this.webSheetTitle();
        }
      })

      // 开发者声明弹窗（同意隐私协议后首次展示）：挂独立占位组件，避免与其它弹窗同宿主冲突
      Column()
        .width('100%')
        .height(1)
        .bindSheet($$this.showDeclaration, this.declarationSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: false,
          preferType: SheetType.BOTTOM,
          width: this.sheetWidth,
          showClose: true,
          backgroundColor: $r('app.color.bg_page')
        })

      // 账号风控提醒弹窗（开发者声明之后首次展示）：另挂独立占位组件，避免同宿主 bindSheet 冲突
      Column()
        .width('100%')
        .height(1)
        .bindSheet($$this.showRiskTip, this.riskTipSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: false,
          preferType: SheetType.BOTTOM,
          width: this.sheetWidth,
          showClose: true,
          backgroundColor: $r('app.color.bg_page')
        })

      // 日志调试密码弹窗（连点图标 5 次 / 点日志调试入口触发）：另挂独立占位组件，避免同宿主 bindSheet 冲突
      Column()
        .width('100%')
        .height(1)
        .bindSheet($$this.showLogSheet, this.logDebugSheet(), {
          height: SheetSize.FIT_CONTENT,
          dragBar: false,
          preferType: SheetType.BOTTOM,
          width: this.sheetWidth,
          showClose: true,
          backgroundColor: $r('app.color.bg_page')
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
      showClose: false,
      enableOutsideInteractive: true,
      preferType: SheetType.BOTTOM,
      width: this.sheetWidth
    })
      }
    }
    .width('100%')
    .height('100%')
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
    WebSurface({
      onControllerReady: (ctrl: webview.WebviewController) => {
        this.webCtrl = ctrl;
      }
    })
  }

  /** 网页版登录弹窗标题栏：标题 + 右侧"教务系统 / 服务大厅"切换（仅网页版登录模式显示，找回密码不显示） */
  @Builder
  webSheetTitle() {
    Row() {
      Text(AppState.webTitle)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      Blank()
      if (AppState.webLoginMode) {
        Row() {
          Text('服务大厅')
            .fontSize(13)
            .fontColor(this.webLoginTarget === 'hall' ? $r('app.color.brand_on') : $r('app.color.text_secondary'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(this.webLoginTarget === 'hall' ? $r('app.color.brand') : Color.Transparent)
            .borderRadius(13)
            .onClick(() => {
              this.switchWebTarget('hall');
            })
          Text('教务系统')
            .fontSize(13)
            .fontColor(this.webLoginTarget === 'jw' ? $r('app.color.brand_on') : $r('app.color.text_secondary'))
            .padding({ left: 12, right: 12, top: 6, bottom: 6 })
            .backgroundColor(this.webLoginTarget === 'jw' ? $r('app.color.brand') : Color.Transparent)
            .borderRadius(13)
            .onClick(() => {
              this.switchWebTarget('jw');
            })
        }
        .backgroundColor($r('app.color.bg_chip'))
        .borderRadius(16)
        .padding(3)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }

  /** 隐私协议全屏弹窗：协议正文 + 底部"同意"按钮 + 右下角已同意时间 */
  @Builder
  privacySheet() {
    Column() {
      Text('隐私协议')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 12 })

      // 协议正文（可滚动；正文取自 rawfile/privacy.html 单一事实源，跟随系统深色）；拦截外链点击：在应用内 WebView 打开，不跳转系统浏览器
      Web({ src: $rawfile('privacy.html'), controller: this.privacyController })
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(Color.Transparent)
        .darkMode(WebDarkMode.Auto)
        .onLoadIntercept((event) => {
          if (event && event.data) {
            const url: string = event.data.getRequestUrl();
            if (url.startsWith('http://') || url.startsWith('https://')) {
              AppState.webUrl = url;
              AppState.webTitle = 'GitHub 开源仓库';
              AppState.webLoginMode = false;
              AppState.onWebLogin = null;
              this.showWeb = true;
              return true;
            }
          }
          return false;
        })

      // 底部操作行：左侧"暂不同意" + 右侧"同意并继续"；左下角显示已同意时间
      Column() {
        // 已同意时间（未同意时显示提示）
        if (this.privacyAgreedAt.length > 0) {
          Text('已签订时间: ' + this.privacyAgreedAt)
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

  /** 开发者声明弹窗（同意隐私协议后首次展示：独立开发声明，标题加粗 + 正文排版） */
  @Builder
  declarationSheet() {
    Column() {
      // 标题
      Row() {
        Text('开发者声明')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 18, bottom: 10 })

      // 声明正文（分段：标题加粗、正文正常）
      Scroll() {
        Column() {
          ForEach(DEVELOPER_DECLARATION, (sec: DeclarationSection) => {
            Column() {
              Text(sec.title)
                .fontSize(15)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.text_primary'))
                .width('100%')
                .margin({ bottom: 4 })
              Text(sec.content)
                .fontSize(13)
                .lineHeight(22)
                .fontColor($r('app.color.text_secondary'))
                .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .margin({ bottom: 14 })
          }, (sec: DeclarationSection) => sec.title)
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 4, bottom: 16 })
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      // 底部按钮（宽度适配内容，居中）
      Button('我已知晓')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.brand_on'))
        .backgroundColor($r('app.color.brand'))
        .height(40)
        .width(160)
        .borderRadius(20)
        .margin({ bottom: 20 })
        .onClick(() => {
          this.showDeclaration = false;
          // 开发者声明之后（仅首次）：展示账号风控提醒
          if (!DataStore.isRiskTipShown()) {
            DataStore.setRiskTipShown();
            setTimeout(() => {
              this.showRiskTip = true;
            }, 300);
          }
        })
    }
    .width('100%')
    .backgroundColor($r('app.color.bg_page'))
    .alignItems(HorizontalAlign.Center)
  }

  /** 账号风控提醒弹窗（开发者声明之后首次展示：频繁登录退出的风险提示） */
  @Builder
  riskTipSheet() {
    Column() {
      // 标题
      Row() {
        Text('账号风控提醒')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Blank()
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 18, bottom: 10 })

      // 提醒正文
      Column() {
        Text('请勿频繁登录与退出教务系统，以免导致账号风控无法使用！' +
          '建议将应用锁定在后台，以免被清除。\n\n' +
          '若账号风控导致应用无法使用，请清除应用数据，等待24小时及以上，风控将自动解除。\n\n' +
          '若此时应用还是无法登录，则可能是学校服务器更新，应用不一定还能登录，' +
          '请关注更新动态（没有更新就说明应用已无法使用）。')
          .fontSize(14)
          .lineHeight(22)
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 4, bottom: 16 })
      .alignItems(HorizontalAlign.Start)

      // 底部按钮
      Button('我知道了')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.brand_on'))
        .backgroundColor($r('app.color.brand'))
        .height(40)
        .width(160)
        .borderRadius(20)
        .margin({ bottom: 20 })
        .onClick(() => {
          this.showRiskTip = false;
        })
    }
    .width('100%')
    .backgroundColor($r('app.color.bg_page'))
    .alignItems(HorizontalAlign.Center)
  }
}
