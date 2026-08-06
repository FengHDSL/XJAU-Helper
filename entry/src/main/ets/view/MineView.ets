/**
 * 我的：学业概览 + 常用功能 + 设置
 */
import { promptAction } from '@kit.ArkUI';
import { storageStatistics } from '@kit.CoreFileKit';
import { webview } from '@kit.ArkWeb';
import { JwApi } from '../api/JwApi';
import { AppState } from '../common/AppState';
import { Const } from '../common/Constants';
import { DataStore } from '../common/DataStore';
import { Theme } from '../common/ThemeUtil';
import { AcademicReport, UserProfile } from '../model/Models';
import { EMPTY_REPORT } from '../model/Empty';
import { SettingRow } from './common/UiKit';
import { WebSurface } from './WebSurface';

@Component
export struct MineView {
  @StorageProp('topInsetPx') topInsetPx: number = 0;
  @StorageProp('bottomInsetPx') bottomInsetPx: number = 0;
  @StorageProp('themeColor') themeColor: string = 'green';
  @StorageProp('isDarkMode') isDarkMode: boolean = false;
  @StorageLink('showAvatar') showAvatar: boolean = false;
  @State report: AcademicReport = EMPTY_REPORT;
  @State loaded: boolean = false;
  @State showWeb: boolean = false;
  @State syncing: boolean = false;
  @State photo: string = '';
  @State cacheSizeText: string = '计算中…';
  @State historyList: Record<string, string>[] = [];
  onLogout: () => void = () => {
  };

  /** 页面出现：加载学业概览并刷新缓存大小 */
  aboutToAppear(): void {
    this.load();
    this.refreshCacheSize();
  }

  /** 异步刷新缓存大小（MB）
   * OS 不会立即回收磁盘空间，所以清完缓存后延迟 500ms 再读两次，
   * 让 DataStore 写回 / 系统回收都发生之后再显示新值。
   */
  /** 异步读取应用缓存大小并格式化显示（MB/KB） */
  private refreshCacheSize(delayMs: number = 0): void {
    if (delayMs > 0) {
      this.cacheSizeText = '计算中…';
      setTimeout(() => this.refreshCacheSize(0), delayMs);
      return;
    }
    storageStatistics.getCurrentBundleStats().then((stats) => {
      const mb: number = stats.cacheSize / 1024 / 1024;
      this.cacheSizeText = mb < 0.1 ? `${(stats.cacheSize / 1024).toFixed(1)} KB` : `${mb.toFixed(2)} MB`;
    }).catch(() => {
      this.cacheSizeText = '0 MB';
    });
  }

  /** 最近同步时间文案 */
  private lastSyncText(): string {
    if (this.syncing) {
      return '同步中…';
    }
    const ts: number = JwApi.lastRefreshTime();
    if (ts <= 0) {
      return '尚未同步';
    }
    const d: Date = new Date(ts);
    return `${d.getMonth() + 1}/${d.getDate()} ${d.getHours()}:${d.getMinutes() < 10 ? '0' + d.getMinutes() : d.getMinutes()}`;
  }

  /** 立即重新拉取全部数据并写入本地缓存 */
  private async syncNow(): Promise<void> {
    if (this.syncing) {
      return;
    }
    this.syncing = true;
    promptAction.showToast({ message: '正在同步教务数据…' });
    try {
      JwApi.USE_MOCK = false;
      await JwApi.refreshAll();
      this.report = JwApi.loadCachedAcademic();
      promptAction.showToast({ message: '数据已更新' });
    } catch (e) {
      promptAction.showToast({ message: '同步失败，请检查网络' });
    } finally {
      this.syncing = false;
    }
  }

  /** 在应用内打开网页（注入会话 Cookie 保持登录态），通过底部全屏弹层展示 */
  private openWeb(url: string, title: string): void {
    AppState.webUrl = url;
    AppState.webTitle = title;
    this.showWeb = true;
  }

  private async load(): Promise<void> {
    // 先用缓存秒开
    const cached: AcademicReport = JwApi.loadCachedAcademic();
    if (cached.gpa > 0 || cached.totalRequired > 0) {
      this.report = cached;
      this.loaded = true;
    }
    // 头像：先读缓存（与首页一致；功能浏览模式不读真实缓存，避免泄露）
    const cachedPhoto: string = JwApi.loadCachedPhoto();
    if (cachedPhoto.length > 0) {
      this.photo = cachedPhoto;
    }
    try {
      this.report = await JwApi.getAcademic();
      // 拉取头像（与首页一致）
      const p: string = await JwApi.getPhoto();
      if (p.length > 0) {
        this.photo = p;
      }
      // 尝试从"查询个人信息"页面补充学院等字段（若之前为空）
      if (AppState.profile !== null && AppState.profile.college.length === 0) {
        const enriched: UserProfile | null = await JwApi.fetchFullProfile();
        if (enriched !== null && enriched.college.length > 0) {
          AppState.profile = enriched;
        }
      }
      this.loaded = true;
    } catch (e) {
      // 网络异常时保持缓存
      this.loaded = true;
    }
  }

  /** 弹出退出登录确认框，确认后回调 onLogout */
  private confirmLogout(): void {    promptAction.showDialog({
      title: '退出登录',
      message: '退出后需要重新使用学号密码登录，确定退出吗？',
      buttons: [
        { text: '取消', color: '#888888' },
        { text: '退出', color: '#F0524D' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse) => {
      if (result.index === 1) {
        JwApi.logout();
        AppState.clear();
        this.onLogout();
      }
    });
  }

  /** 在系统浏览器打开网页版教务系统（已弃用，改应用内 WebView） */
  private openWebPortal(): void {
    this.openWeb(Const.WEB_PORTAL_URL, '网页版教务系统');
  }

  @Builder
  titleBar() {
    // 顶部固定标题栏：浅色=主题色（中国红/天空蓝/农大绿），深色=黑色
    // 高度与其他主题色顶栏统一（topInset + 72vp 外高，内容区 48vp）
    Row() {
      Text('我的')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
      Blank()
    }
    .width('100%')
    .height(px2vp(this.topInsetPx) + 60)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 16, right: 16, top: px2vp(this.topInsetPx) + 12, bottom: 12 })
    .backgroundColor(this.isDarkMode ? '#1A1D1C' : Theme.colorOf(this.themeColor))
  }

  @Builder
  avatarCard() {
    // 头像卡片：showAvatar 仅控制圆形头像的显示/隐藏，其余信息 + 右侧退出按钮始终显示
    Row() {
      if (this.showAvatar) {
        if (this.photo.length > 0) {
          Image('data:image/jpeg;base64,' + this.photo)
            .width(52)
            .height(52)
            .borderRadius(26)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.bg_chip'))
        } else if (JwApi.USE_MOCK) {
          // 功能浏览模式：使用默认占位头像
          Image($r('app.media.zhangsan_avatar'))
            .width(52)
            .height(52)
            .borderRadius(26)
            .objectFit(ImageFit.Cover)
            .backgroundColor($r('app.color.bg_chip'))
        } else {
          Text(AppState.avatarText())
            .fontSize(17)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.brand'))
            .width(52)
            .height(52)
            .borderRadius(26)
            .backgroundColor($r('app.color.bg_chip'))
            .textAlign(TextAlign.Center)
        }
      }

      Column() {
        Text(AppState.displayName())
          .fontSize(17)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text(this.identityLine())
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 4 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .margin({ left: this.showAvatar ? 12 : 0 })
      .layoutWeight(1)

      Blank()

      // 右侧：红色圆形退出登录按钮（用 退出.png 图标）
      Button() {
        Image($r('app.media.sign_out_alt'))
          .width(20)
          .height(20)
          .fillColor('#FFFFFF')
      }
      .width(44)
      .height(44)
      .backgroundColor($r('app.color.state_danger'))
      .borderRadius(22)
      .onClick(() => {
        this.confirmLogout();
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(16)
  }

  /** 学号 · 学院 · 班级 */
  private identityLine(): string {
    const p: UserProfile | null = AppState.profile;
    const parts: string[] = [];
    if (AppState.studentId().length > 0) {
      parts.push(AppState.studentId());
    }
    if (p !== null && p.college.length > 0) {
      parts.push(p.college);
    }
    if (p !== null && p.className.length > 0) {
      parts.push(p.className);
    }
    return parts.length > 0 ? parts.join(' · ') : '未登录';
  }

  @Builder
  academicCard() {
    Row() {
      Column() {
        Text(this.loaded ? `${this.report.totalEarned}` : '--')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.brand'))
        Text('已修学分')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 3 })
      }
      .layoutWeight(1)

      Column() {
        Text(this.loaded ? this.report.gpa.toFixed(2) : '--')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.accent_blue'))
        Text('平均绩点')
          .fontSize(11)
          .fontColor($r('app.color.text_tertiary'))
          .margin({ top: 3 })
      }
      .layoutWeight(1)

      Text('›')
        .fontSize(18)
        .fontColor($r('app.color.text_tertiary'))
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(18)
    .onClick(() => {
      AppState.stack.pushPath({ name: Const.ROUTE_ACADEMIC });
    })
  }

build() {
    Column() {
      // 顶部标题栏：固定不动 + 半透明白 + 毛玻璃
      this.titleBar()
      // 中间内容：可滚动；横屏/平板下内容限宽 720vp 并居中（一多适配）
      Row() {
        Scroll() {
          Column() {
          // 头像卡片（始终显示；圆形头像由 showAvatar 开关控制）
          Row() {
            this.avatarCard()
          }
          .margin({ bottom: 14 })

          this.academicCard()

          // 常用功能（精简：只留 考试安排 / 学业情况；删除查询个人信息）
          Column() {
            SettingRow({
              icon: '', title: '考试安排', onTap: () => {
                AppState.stack.pushPath({ name: Const.ROUTE_EXAM });
              }
            })
            Divider().color($r('app.color.divider'))
            SettingRow({
              icon: '', title: '学业情况', onTap: () => {
                AppState.stack.pushPath({ name: Const.ROUTE_ACADEMIC });
              }
            })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(18)
          .margin({ top: 14 })

          // 设置（顺序：网页版教务系统 → 数据同步 → 头像显示 → 清除缓存 → 隐私协议 → 清空数据 → 关于 → 服务备案号）
          Column() {
            // 1. 网页版教务系统（最顶上）
            SettingRow({
              icon: '', title: '网页版教务系统', value: '', onTap: () => {
                this.openWebPortal();
              }
            })
            Divider().color($r('app.color.divider'))
            // 2. 数据同步
            SettingRow({
              icon: '', title: '数据同步', value: this.lastSyncText(), onTap: () => {
                this.syncNow();
              }
            })
            Divider().color($r('app.color.divider'))
            // 3. 主题模式（顶栏颜色：中国红/天空蓝/农大绿）
            SettingRow({
              icon: '', title: '主题模式', value: this.themeColor === 'red' ? '中国红' : (this.themeColor === 'blue' ? '天空蓝' : '农大绿'), onTap: () => {
                promptAction.showActionMenu({
                  title: '顶栏主题色',
                  buttons: [
                    { text: '中国红', color: '#C3272B' },
                    { text: '天空蓝', color: '#3B82F6' },
                    { text: '农大绿', color: '#079841' }
                  ]
                }).then((res) => {
                  const themes: string[] = ['red', 'blue', 'green'];
                  if (res.index >= 0 && res.index < themes.length) {
                    Theme.apply(themes[res.index]);
                  }
                });
              }
            })
            Divider().color($r('app.color.divider'))
            // 4. 头像显示开关（不显示开启/关闭文本，仅开关）
            Row() {
              Text('头像显示')
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.showAvatar })
                .selectedColor($r('app.color.brand'))
                .onChange((isOn: boolean) => {
                  this.showAvatar = isOn;
                  DataStore.put(DataStore.KEY_SHOW_AVATAR, isOn ? '1' : '0');
                })
            }
            .width('100%')
            .height(52)
            Divider().color($r('app.color.divider'))
            // 5. 清除缓存
            SettingRow({
              icon: '', title: '清除缓存', value: this.cacheSizeText, onTap: () => {
                DataStore.remove(DataStore.KEY_PROFILE);
                DataStore.remove(DataStore.KEY_COURSES);
                DataStore.remove(DataStore.KEY_TERM_SCORES);
                DataStore.remove(DataStore.KEY_EXAMS);
                DataStore.remove(DataStore.KEY_ACADEMIC);
                DataStore.remove(DataStore.KEY_NOTICES);
                DataStore.remove(DataStore.KEY_NOTICES_JWC);
                DataStore.remove(DataStore.KEY_TEACHING_CAL);
                DataStore.remove(DataStore.KEY_JWC_CAL);
                DataStore.remove(DataStore.KEY_PHOTO);
                DataStore.remove(DataStore.KEY_CACHE_TIME);
                // 同时清除 WebView 缓存与 Cookie（否则缓存大小不变）
                try {
                  webview.WebCookieManager.clearAllCookies();
                  webview.WebStorage.deleteAllData();
                } catch (e) {
                  // ignore
                }
                promptAction.showToast({ message: '缓存已清除（含网页缓存）' });
                this.refreshCacheSize(500);
              }
            })
            Divider().color($r('app.color.divider'))
            // 6. 清空数据（确认后提示手动重启）
            SettingRow({
              icon: '', title: '清空数据', value: '', onTap: () => {
                promptAction.showDialog({
                  title: '清空数据',
                  message: '将清除全部使用记录（历史账号、缓存、个人信息等），此操作不可恢复，确认继续？',
                  buttons: [
                    { text: '取消', color: '#666666' },
                    { text: '确认清空', color: '#DB5252', primary: true }
                  ]
                }).then((res) => {
                  if (res.index === 1) {
                    DataStore.clearAll();
                    AppState.profile = null;
                    promptAction.showDialog({
                      title: '清空完成',
                      message: '全部数据已清空，请手动重启应用以刷新界面',
                      buttons: [{ text: '知道了', color: '#1B7F5F' }]
                    });
                  }
                });
              }
            })
            Divider().color($r('app.color.divider'))
            // 7. 隐私协议（打开独立页面）
            SettingRow({
              icon: '', title: '隐私协议', value: '', onTap: () => {
                AppState.stack.pushPath({ name: Const.ROUTE_PRIVACY });
              }
            })
            Divider().color($r('app.color.divider'))
            // 8. 关于（打开独立页面）
            SettingRow({
              icon: '', title: '关于', value: 'v1.1.0', onTap: () => {
                AppState.stack.pushPath({ name: Const.ROUTE_ABOUT });
              }
            })
            // 9. 服务备案号（关于下面）
            Row() {
              Text('服务备案号')
                .fontSize(15)
                .fontColor($r('app.color.text_primary'))
              Blank()
              Text('待备案')
                .fontSize(13)
                .fontColor($r('app.color.text_tertiary'))
            }
            .width('100%')
            .height(52)
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .backgroundColor($r('app.color.bg_card'))
          .borderRadius(18)
          .margin({ top: 14 })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 12, bottom: 100 }) // 底部预留悬浮底栏高度，避免内容被遮挡
        }
        .width(720)
        .constraintSize({ maxWidth: '100%' })
        .height('100%')
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center) // 横屏/平板下 Scroll 水平居中
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
  webSheet() {
    WebSurface()
  }
}
