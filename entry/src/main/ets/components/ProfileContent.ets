/**
 * 我的页面内容组件
 * 包含: 用户卡片, VIP横幅, 今日任务统计, 菜单列表
 * 适配 ArkTS 严格模式
 */
import { router } from '@kit.ArkUI';
import { COLORS } from '../utils/Constants';
import { UI } from '../utils/UiTokens';
import { DailyTask } from '../models/DataModels';
import TaskTrackingService from '../services/TaskTrackingService';
import ApiService, { ApiError, PhoneAuthStatus } from '../services/ApiService';
import promptAction from '@ohos.promptAction';
import { themeManager } from '../utils/ThemeManager';
import OneClickAuthService, { OneClickError } from '../services/OneClickAuthService';
import common from '@ohos.app.ability.common';

@Component
export struct ProfileContent {
  @Prop externalSheetMode: string = '';
  @Prop @Watch('onExternalSheetRequestChange') externalSheetRequestAt: number = 0;
  @Prop @Watch('onActiveTabIndexChange') activeTabIndex: number = -1;
  @State isLoggedIn: boolean = false;
  @State isPro: boolean = false;  // 区分Pro会员和普通会员
  @State userName: string = '点击登录/注册';
  @State userAvatar: string = '';
  @State userStatus: string = '注册后解锁学习与词典';
  @State showMainSheet: boolean = false;  // 统一弹窗状态
  @State sheetMode: string = 'vip';  // 'vip' | 'login'
  @State isSheetAnimating: boolean = false;  // 弹窗动画状态锁
  @State pendingSheetMode: string = '';  // 待打开的弹窗模式
  @State dailyTask: DailyTask = new DailyTask();
  @State taskVersionKey: number = 0;

  // 登录表单状态
  @State phoneNumber: string = ''
  @State phoneError: string = '';  // 手机号错误提示
  @State verifyCode: string = '';
  @State isGettingCode: boolean = false;
  @State countdown: number = 0;
  @State loginError: string = '';  // 登录/验证码错误提示
  @State isLoggingIn: boolean = false;  // 登录中状态锁

  // 一键登录状态
  @State oneClickEnabled: boolean = false;
  @State isOneClickLoading: boolean = false;
  @State showSmsFallback: boolean = false;
  @State oneClickErrorMsg: string = '';
  @State oneClickCooldownSec: number = 0;  // 一键登录冷却倒计时
  private oneClickCooldownTimer: number = -1;


  // 任务数据
  @State lessonCount: number = 13;
  @State reviewDone: boolean = true;
  @State studyDone: boolean = true;
  @State themeVersion: number = 0;

  private taskService: TaskTrackingService = TaskTrackingService.getInstance();
  private unsubscribeTheme: (() => void) | null = null;
  private unsubscribeTaskUpdate: (() => void) | null = null;
  private lastHandledExternalSheetRequestAt: number = 0;

  // 获取图标背景色（添加15%透明度）
  getIconBgColor(iconColor: string): string {
    // 将十六进制颜色转为 rgba
    if (iconColor === '#6366f1') {
      return 'rgba(99, 102, 241, 0.15)';
    } else if (iconColor === '#06b6d4') {
      return 'rgba(6, 182, 212, 0.15)';
    }
    return 'rgba(99, 102, 241, 0.15)';
  }

  onActiveTabIndexChange(): void {
    if (this.activeTabIndex !== 3) {
      return;
    }
    void this.syncLoginStateFromToken();
  }

  async aboutToAppear() {
    if (this.unsubscribeTheme === null) {
      this.unsubscribeTheme = themeManager.subscribe(() => {
        this.themeVersion++;
      });
    }

    const context = getContext(this);

    // 初始化 API 服务并检查登录态
    const apiService = ApiService.getInstance();
    await apiService.init(context);
    await this.syncLoginStateFromToken();

    await this.taskService.init(context);
    this.dailyTask = await this.taskService.refreshTask();
    this.lessonCount = this.dailyTask.lessonStepDone;

    if (this.unsubscribeTaskUpdate === null) {
      this.unsubscribeTaskUpdate = this.taskService.subscribeOnUpdate((task: DailyTask) => {
        this.dailyTask = task;
        this.lessonCount = task.lessonStepDone;
        this.taskVersionKey++;
      });
    }

    // 初始化一键登录
    this.initOneClickLogin(context);
    this.tryOpenExternalSheet();
  }

  async syncLoginStateFromToken() {
    const apiService = ApiService.getInstance();
    const hasToken = apiService.getToken().length > 0;
    
    if (hasToken) {
      this.isLoggedIn = true;
      try {
        const userInfo = await apiService.getCurrentUserInfo();
        this.userName = userInfo.phone || userInfo.nickname || '点击登录/注册';
        this.userAvatar = userInfo.avatar;
        
        if (userInfo.memberLevel === 'PRO') {
          this.isPro = true;
          this.userStatus = userInfo.memberLevelLabel;
        } else {
          this.isPro = false;
          this.userStatus = userInfo.memberLevelLabel;
        }
      } catch (error) {
        console.warn('[ProfileContent] Sync login info failed:', error);
        // Token 可能失效，视为未登录
        this.resetLoggedOutState();
        await apiService.clearToken(getContext(this));
      }
    } else {
      this.resetLoggedOutState();
    }
  }

  private resetLoggedOutState(): void {
    this.isLoggedIn = false;
    this.isPro = false;
    this.userName = '点击登录/注册';
    this.userAvatar = '';
    this.userStatus = '注册后解锁学习与词典';
  }

  async initOneClickLogin(context: Context) {
    const apiService = ApiService.getInstance();
    const oneClickService = OneClickAuthService.getInstance();
    
    try {
      // 检查服务端开关
      const status = await apiService.checkPhoneAuthStatus();
      this.oneClickEnabled = status.oneClickLoginEnabled;
      
      if (this.oneClickEnabled) {
        // 初始化 SDK 并预取号
        // 注意：context 需要转换为 UIAbilityContext
        await oneClickService.init(context as common.UIAbilityContext);
        await oneClickService.prefetch();
      } else {
        this.showSmsFallback = false;
        this.oneClickErrorMsg = '当前环境暂不支持本机一键登录，请联系测试负责人';
      }
    } catch (error) {
      console.error('[ProfileContent] Init one-click failed:', error);
      this.showSmsFallback = false;
      this.oneClickEnabled = false;
      if (error instanceof ApiError) {
        if (error.code === 1002) {
          this.oneClickErrorMsg = '客户端签名校验失败，请安装最新调试包后重试';
        } else {
          this.oneClickErrorMsg = error.message || '一键登录初始化失败，请稍后重试';
        }
      } else {
        this.oneClickErrorMsg = '一键登录初始化失败，请稍后重试';
      }
    }
  }

  async performOneClickLogin() {
    if (this.isOneClickLoading) return;
    this.isOneClickLoading = true;
    this.oneClickErrorMsg = '';
    
    const apiService = ApiService.getInstance();
    const hasTokenBefore = apiService.getToken().length > 0;
    
    const oneClickService = OneClickAuthService.getInstance();
    
    try {
      const context = getContext(this) as common.UIAbilityContext;
      // 1. 拉起授权页获取 Token
      const accessToken = await oneClickService.requestToken(context);
      
      // 记录下本次的 attemptId
      const currentAttemptId = oneClickService.getCurrentAttemptId();
      
      // 2. 调用服务端一键登录
      await apiService.loginByOneClick(accessToken, context, currentAttemptId);
      
      // 3. 登录成功处理
      this.handleLoginSuccess();
      
    } catch (error) {
      this.isOneClickLoading = false;
      console.error('[ProfileContent] One-click login failed:', error);

       // 强制回滚：如果登录前未登录，且本次失败，确保清除可能存在的中间态 Token
       if (!hasTokenBefore) {
         await apiService.clearToken(getContext(this));
         this.syncLoginStateFromToken();
       }
      
      let toastMsg = '一键登录失败，请稍后重试';
      let shouldCooldown = false;

      if (error instanceof ApiError) {
        // 后端业务错误
        toastMsg = `一键登录失败（${error.message}）`;
        console.error(`[ProfileContent] Backend Error traceId=${error.traceId}`);
        
        // 3008: 请求过于频繁
        if (error.code === 3008) {
           shouldCooldown = true;
        }
      } else {
        // SDK/网络错误 (格式: TYPE:CODE)
        const rawMsg = (error as Error).message || ''; 
        const parts = rawMsg.split(':');
        const type = parts[0];
        const code = parts[1] || '';

        switch (type) {
          case OneClickError.SUPERSEDED:
            // 被新请求顶替，静默忽略，不弹 Toast，不断开 loading
            return;
          case OneClickError.AUTH_PAGE_CLOSED:
            this.isOneClickLoading = false;
            if (this.showMainSheet) {
              toastMsg = '授权页已关闭';
              this.safeShowToast(toastMsg, 3000);
            } else {
              console.info('[ProfileContent] Auth page closed and returned to profile silently.');
            }
            return;
          case OneClickError.USER_CANCELLED:
            toastMsg = '用户取消授权';
            break;
          case OneClickError.NO_SIM:
            toastMsg = '未检测到 SIM 卡，无法本机一键登录';
            break;
          case OneClickError.NETWORK_ERROR:
            toastMsg = `网络连接失败（${code}）`;
            break;
          case OneClickError.TIMEOUT:
            if (oneClickService.isAuthPageVisible()) {
              console.warn('[ProfileContent] Ignored timeout because auth page is still actively presented.');
              this.isOneClickLoading = false;
              return;
            }
            toastMsg = `请求超时（${code}）`;
            break;
          case OneClickError.CARRIER_ERROR:
            toastMsg = `运营商鉴权失败（${code}）`;
            break;
          case OneClickError.SDK_NOT_AVAILABLE:
            toastMsg = `环境不支持一键登录（${code}）`;
            break;
          case OneClickError.RATE_LIMIT:
            toastMsg = '请求过于频繁，请稍后重试';
            shouldCooldown = true;
            break;
          default:
            toastMsg = `一键登录失败（${rawMsg}）`;
            break;
        }
      }
      
      if (shouldCooldown) {
        this.startOneClickCooldown();
        toastMsg = '请求频繁，请 8 秒后重试';
      }
      
      this.oneClickErrorMsg = toastMsg;
      this.safeShowToast(toastMsg, 3000);
    }
  }

  handleLoginSuccess() {
    this.showMainSheet = false;
    this.isOneClickLoading = false;
    this.isLoggingIn = false;
    this.oneClickCooldownSec = 0;

    if (this.oneClickCooldownTimer !== -1) {
      clearInterval(this.oneClickCooldownTimer);
      this.oneClickCooldownTimer = -1;
    }
    this.showSmsFallback = false;

    // 同步最新用户信息
    this.syncLoginStateFromToken();
    
    // 刷新任务列表
    this.taskService.refreshTask().then(task => {
      this.dailyTask = task;
    });
    
    this.safeShowToast('登录成功');
  }

  aboutToDisappear() {
    if (this.unsubscribeTaskUpdate !== null) {
      this.unsubscribeTaskUpdate();
      this.unsubscribeTaskUpdate = null;
    }
    if (this.unsubscribeTheme !== null) {
      this.unsubscribeTheme();
      this.unsubscribeTheme = null;
    }
    if (this.oneClickCooldownTimer !== -1) {
      clearInterval(this.oneClickCooldownTimer);
      this.oneClickCooldownTimer = -1;
    }
  }

  startOneClickCooldown() {
    this.oneClickCooldownSec = 8;
    this.oneClickCooldownTimer = setInterval(() => {
      this.oneClickCooldownSec--;
      if (this.oneClickCooldownSec <= 0) {
        clearInterval(this.oneClickCooldownTimer);
        this.oneClickCooldownTimer = -1;
      }
    }, 1000);
  }

  private safeShowToast(message: string, duration: number = 3000): void {
    try {
      promptAction.showToast({ message, duration });
    } catch (e) {
      console.error('[ProfileContent] showToast failed:', e);
    }
  }

  private async goMemberPage(): Promise<void> {
    try {
      await router.pushUrl({ url: 'pages/MemberPage' });
    } catch (e) {
      console.error('[ProfileContent] go member page failed:', JSON.stringify(e));
    }
  }

  private onExternalSheetRequestChange(): void {
    this.tryOpenExternalSheet();
  }

  private tryOpenExternalSheet(): void {
    if (this.externalSheetMode !== 'login') {
      return;
    }
    if (this.externalSheetRequestAt <= 0 || this.externalSheetRequestAt === this.lastHandledExternalSheetRequestAt) {
      return;
    }

    this.lastHandledExternalSheetRequestAt = this.externalSheetRequestAt;
    if (this.isLoggedIn) {
      return;
    }

    this.openMainSheet('login');
  }

  private openMainSheet(mode: string): void {
    if (this.isSheetAnimating) {
      this.pendingSheetMode = mode;
      return;
    }

    this.sheetMode = mode;
    this.showMainSheet = true;
  }

  build() {
    Stack() {
      Column() {
        Scroll() {
          Column({ space: 20 }) {
            Row() {
              Column({ space: 6 }) {
                Text('我的学习')
                  .fontSize(UI.TITLE_SIZE)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(COLORS.TEXT_PRIMARY)
                Text('今天也向韩语更近一点')
                  .fontSize(14)
                  .fontColor(COLORS.TEXT_SECONDARY)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Image($r('app.media.lingai_robot'))
                .width(64)
                .height(64)
                .objectFit(ImageFit.Contain)
            }
            .width('100%')
            .margin({ bottom: 4 })

            // 用户信息卡片
            this.UserCard()

            // VIP 横幅
            this.VIPBanner()

            // 今日任务标签
            Text('今日任务')
              .fontSize(14)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
              .width('100%')
              .padding({ left: 5 })

            // 今日任务统计
            this.TaskStatsCard()

            // 菜单列表
            this.MenuList()
          }
          .width('100%')
          .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 0, bottom: 192 })
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ top: UI.CONTENT_TOP })
        .clipContent(ContentClipMode.CONTENT_ONLY)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BACKGROUND)
      .onAppear(() => {
        // Tabs 切换返回时强制同步，避免登录态 UI 残留
        this.syncLoginStateFromToken();
        this.tryOpenExternalSheet();
      })
      .bindSheet($$this.showMainSheet, this.MainSheetBuilder(), {
        height: SheetSize.FIT_CONTENT,
        dragBar: true,
        showClose: false,
        backgroundColor: COLORS.SURFACE,
        onWillAppear: () => {
          this.isSheetAnimating = true;
        },
        onAppear: () => {
          this.isSheetAnimating = false;
        },
        onWillDisappear: () => {
          this.isSheetAnimating = true;
        },
        onDisappear: () => {
          // 弹窗关闭时重置动画状态
          this.isSheetAnimating = false;

          // 检查是否有待打开的弹窗
          if (this.pendingSheetMode !== '') {
            const mode = this.pendingSheetMode;
            this.pendingSheetMode = '';
            // 延迟打开，确保关闭动画完全结束
            setTimeout(() => {
              this.sheetMode = mode;
              this.showMainSheet = true;
            }, 50);
          } else {
            // 没有待打开的弹窗，重置模式为vip
            this.sheetMode = 'vip';
          }
        }
      })

    }
    .width('100%')
    .height('100%')
  }

  @Builder
  UserCard() {
    Column({ space: 18 }) {
      Row() {
        Stack({ alignContent: Alignment.BottomEnd }) {
          Column() {
            Image($r('app.media.ic_mine'))
              .width(26)
              .height(26)
              .fillColor(COLORS.PRIMARY)
          }
          .width(60)
          .height(60)
          .borderRadius(20)
          .backgroundColor(COLORS.SURFACE)
          .justifyContent(FlexAlign.Center)

          if (this.isPro) {
            Text('Pro')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor(UI.WARM)
              .padding({ left: 7, right: 7, top: 4, bottom: 4 })
              .backgroundColor(UI.WARM_SOFT)
              .borderRadius(8)
          }
        }

        Column({ space: 6 }) {
          Text(this.userName)
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .maxLines(2)
          Text(this.userStatus)
            .fontSize(13)
            .lineHeight(20)
            .fontColor(this.isPro ? UI.WARM : COLORS.TEXT_SECONDARY)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 16 })

        Image($r('app.media.ic_arrow_right'))
          .width(20)
          .height(20)
          .fillColor(COLORS.PRIMARY)
      }
      .width('100%')

      Divider()
        .color('rgba(19,127,100,0.12)')

      Text('账号与学习权益')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLORS.PRIMARY)
        .width('100%')
    }
    .width('100%')
    .padding(22)
    .backgroundColor(UI.GREEN_SOFT)
    .borderRadius(UI.CARD_RADIUS)
    .onClick(() => {
      if (this.isLoggedIn) {
        void this.goMemberPage();
      } else {
        this.openMainSheet('login');
      }
    })
  }

  @Builder
  VIPBanner() {
    if (!this.isPro) {
      Row({ space: 12 }) {
        Image($r('app.media.ic_study'))
          .width(24)
          .height(24)
          .fillColor(UI.BLUE)
        Column({ space: 4 }) {
          Text('LingAI Pro 即将上线')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text('先把今天的学习做好')
            .fontSize(12)
            .fontColor(COLORS.TEXT_SECONDARY)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button('详情')
          .type(ButtonType.Normal)
          .backgroundColor(COLORS.SURFACE)
          .fontColor(UI.BLUE)
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .height(UI.TOUCH_MIN)
          .borderRadius(14)
          .padding({ left: 16, right: 16 })
          .onClick(() => {
            this.openMainSheet('vip');
          })
      }
      .width('100%')
      .padding(18)
      .borderRadius(20)
      .backgroundColor(UI.BLUE_SOFT)
    }
  }

  @Builder
  TaskStatsCard() {
    Row() {
      Column({ space: 8 }) {
        Text(this.lessonCount.toString())
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.PRIMARY)
        Text('推进')
          .fontSize(13)
          .fontColor(COLORS.TEXT_SECONDARY)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 8 }) {
        Row({ space: 6 }) {
          Text(this.dailyTask.reviewCount.toString())
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(UI.BLUE)
          if (this.reviewDone) {
            Image($r('app.media.ic_check'))
              .width(14)
              .height(14)
              .fillColor(COLORS.SUCCESS)
          } else {
            Text('-')
              .fontSize(14)
              .fontColor(COLORS.TEXT_HINT)
          }
        }
        Text('复习')
          .fontSize(13)
          .fontColor(COLORS.TEXT_SECONDARY)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      Column({ space: 8 }) {
        Row({ space: 6 }) {
          Text(this.dailyTask.studyMinutes.toString())
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.PRIMARY)
          if (this.studyDone) {
            Image($r('app.media.ic_check'))
              .width(14)
              .height(14)
              .fillColor(COLORS.SUCCESS)
          } else {
            Text('-')
              .fontSize(14)
              .fontColor(COLORS.TEXT_HINT)
          }
        }
        Text('学习分钟')
          .fontSize(13)
          .fontColor(COLORS.TEXT_SECONDARY)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .padding({ top: 24, bottom: 24 })
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(UI.CARD_RADIUS)
    .border({ width: 1, color: COLORS.BORDER })
  }

  @Builder
  MenuList() {
    Column({ space: 12 }) {
      // 学习统计
      this.MenuItem('学习统计', $r('app.media.ic_stats'), '#6366f1', () => {
        router.pushUrl({ url: 'pages/StatisticsPage' });
      })

      // 设置
      this.MenuItem('设置', $r('app.media.ic_settings'), '#06b6d4', () => {
        router.pushUrl({ url: 'pages/SettingsPage' });
      })
    }
    .width('100%')
  }

  @Builder
  MenuItem(title: string, icon: Resource, iconColor: string, onClick: () => void) {
    Row() {
      Column() {
        Image(icon)
          .width(22)
          .height(22)
          .fillColor(UI.BLUE)
      }
      .width(48)
      .height(48)
      .borderRadius(16)
      .backgroundColor(UI.BLUE_SOFT)
      .justifyContent(FlexAlign.Center)

      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLORS.TEXT_PRIMARY)
        .margin({ left: 16 })

      Blank()

      Image($r('app.media.ic_arrow_right'))
        .width(18)
        .height(18)
        .fillColor(COLORS.TEXT_HINT)
    }
    .width('100%')
    .padding(18)
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(20)
    .border({ width: 1, color: COLORS.BORDER })
    .onClick(onClick)
  }

  @Builder
  LoginSheetBuilder() {
    Column() {
      // 标题
      Text('登录 / 注册')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor('#0f172a')
        .margin({ top: 10, bottom: 30 })

      // 手机号输入框
      TextInput({ placeholder: '请输入手机号', text: this.phoneNumber })
        .type(InputType.PhoneNumber)
        .placeholderColor('#94a3b8')
        .placeholderFont({ size: 16 })
        .fontSize(16)
        .fontColor('#0f172a')
        .backgroundColor('#f1f5f9')
        .borderRadius(16)
        .padding({ left: 20, right: 20, top: 18, bottom: 18 })
        .width('100%')
        .onChange((value: string) => {
          this.phoneNumber = value;
        })

      // 验证码输入框和按钮
      Row() {
        TextInput({ placeholder: '验证码', text: this.verifyCode })
          .type(InputType.Number)
          .placeholderColor('#94a3b8')
          .placeholderFont({ size: 16 })
          .fontSize(16)
          .fontColor('#0f172a')
          .backgroundColor('#f1f5f9')
          .borderRadius(16)
          .padding({ left: 20, right: 20, top: 18, bottom: 18 })
          .layoutWeight(1)
          .onChange((value: string) => {
            this.verifyCode = value;
          })

        Button(this.countdown > 0 ? this.countdown.toString() + 's' : '获取验证码')
          .type(ButtonType.Normal)
          .backgroundColor(this.countdown > 0 ? '#e2e8f0' : '#f1f5f9')
          .fontColor(this.countdown > 0 ? '#94a3b8' : '#0f172a')
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .height(54)
          .borderRadius(16)
          .padding({ left: 16, right: 16 })
          .margin({ left: 12 })
          .enabled(this.countdown === 0 && this.phoneNumber.length === 11)
          .onClick(() => {
            this.startCountdown();
          })
      }
      .width('100%')
      .margin({ top: 16 })

      // 登录按钮
      Button('登录')
        .type(ButtonType.Capsule)
        .backgroundColor('#6366f1')
        .fontColor('#ffffff')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .width('100%')
        .height(54)
        .margin({ top: 24 })
        .shadow({ radius: 15, color: 'rgba(99, 102, 241, 0.4)', offsetY: 4 })
        .enabled(this.phoneNumber.length === 11 && this.verifyCode.length >= 4)
        .onClick(() => {
          this.performLogin();
        })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 20, bottom: 50 })
  }

  startCountdown() {
    this.loginError = '';
    const apiService = ApiService.getInstance();

    apiService.sendSmsCode(this.phoneNumber).then(() => {
      // 发送成功，启动倒计时
      this.isGettingCode = true;
      this.countdown = 60;
      const timer = setInterval(() => {
        this.countdown--;
        if (this.countdown <= 0) {
          clearInterval(timer);
          this.isGettingCode = false;
        }
      }, 1000);
    }).catch((error: Error) => {
      // 发送失败，显示后端 message
      if (error instanceof ApiError) {
        this.loginError = error.message;
      } else {
        this.loginError = '发送验证码失败，请检查网络';
      }
      this.safeShowToast(this.loginError, 3000);
    });
  }

  performLogin() {
    if (this.isLoggingIn) return;
    this.isLoggingIn = true;
    this.loginError = '';
    const context = getContext(this);
    const apiService = ApiService.getInstance();

    apiService.loginBySms(this.phoneNumber, this.verifyCode, context).then(() => {
      // 登录成功
      this.handleLoginSuccess();
    }).catch((error: Error) => {
      // 登录失败，显示后端 message
      this.isLoggingIn = false;
      if (error instanceof ApiError) {
        this.loginError = error.message;
      } else {
        this.loginError = '登录失败，请检查网络';
      }
      this.safeShowToast(this.loginError, 3000);
    });
  }

  performSheetLogin() {
    if (this.isLoggingIn) return;
    this.isLoggingIn = true;
    this.loginError = '';
    const context = getContext(this);
    const apiService = ApiService.getInstance();
    
    apiService.loginBySms(this.phoneNumber, this.verifyCode, context).then(() => {
      this.handleLoginSuccess();
    }).catch((error: Error) => {
      this.isLoggingIn = false;
      if (error instanceof ApiError) {
        this.loginError = error.message;
      } else {
        this.loginError = '登录失败，请检查网络';
      }
      this.safeShowToast(this.loginError, 3000);
    });
  }

  @Builder
  MainSheetBuilder() {
    Column() {
      if (this.sheetMode === 'login') {
        // 登录模式内容
        Column() {
          Image($r('app.media.lingai_robot'))
            .width(88)
            .height(88)
            .objectFit(ImageFit.Contain)
            .margin({ top: 8, bottom: 12 })
          Text('登录 / 注册')
            .fontSize(26)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .margin({ top: 10 })

          Text('登录后即可解锁学习、词典和基础会员权益')
            .fontSize(15)
            .fontColor(COLORS.TEXT_SECONDARY)
            .margin({ top: 8, bottom: 24 })

          // 仅保留“本机号码一键登录”入口
          if (this.oneClickEnabled) {
            Button(
              this.isOneClickLoading ? '正在启动...' :
              (this.oneClickCooldownSec > 0 ? `${this.oneClickCooldownSec}s 后重试` : '本机号码一键登录')
            )
              .type(ButtonType.Normal)
              .borderRadius(UI.CONTROL_RADIUS)
              .backgroundColor(this.oneClickCooldownSec > 0 ? COLORS.BORDER : COLORS.PRIMARY)
              .fontColor(UI.ON_PRIMARY)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .width('100%')
              .height(54)
              .enabled(!this.isOneClickLoading && this.oneClickCooldownSec <= 0)
              .onClick(() => {
                this.performOneClickLogin();
              })
          } else {
            Text(this.oneClickErrorMsg.length > 0
              ? this.oneClickErrorMsg
              : '当前环境暂不支持本机一键登录，请联系测试负责人')
              .fontSize(15)
              .fontColor(COLORS.TEXT_SECONDARY)
              .textAlign(TextAlign.Center)
              .margin({ top: 8, bottom: 12 })
              .width('100%')

            Button('重新检测一键登录')
              .type(ButtonType.Normal)
              .backgroundColor(UI.BLUE_SOFT)
              .fontColor(UI.BLUE)
              .fontSize(15)
              .height(UI.TOUCH_MIN)
              .borderRadius(14)
              .width('100%')
              .onClick(() => {
                this.oneClickErrorMsg = '';
                this.initOneClickLogin(getContext(this));
              })
          }

        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 20, bottom: 40 })
      } else {
        // VIP模式内容
        Column() {
          // 皇冠图标
          Column() {
            Image($r('app.media.lingai_robot'))
              .width(64)
              .height(64)
              .objectFit(ImageFit.Contain)
          }
          .width(70)
          .height(70)
          .borderRadius(20)
          .backgroundColor(UI.BLUE_SOFT)
          .justifyContent(FlexAlign.Center)
          .margin({ top: 10 })

          // 标语
          Text('当前先开放基础会员，Pro 会员功能即将上线')
            .fontSize(16)
            .fontColor(COLORS.TEXT_SECONDARY)
            .margin({ top: 20, bottom: 24 })

          // 会员说明卡片
          Column() {
            Column() {
              Text('当前已开放')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLORS.TEXT_SECONDARY)
                .width('100%')

              // 功能列表
              Column({ space: 12 }) {
                this.FeatureItem('注册后解锁学习与词典')
                this.FeatureItem('同步基础账号身份')
                this.FeatureItem('查看会员详情与后续升级说明')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .margin({ top: 14 })
            }
            .width('100%')
            .padding(24)
            .borderRadius(20)
            .border({ width: 1, color: COLORS.BORDER })

            Text('敬请期待')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor(UI.ON_PRIMARY)
              .backgroundColor(UI.WARM)
              .borderRadius(8)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .margin({ top: 12 })
          }
          .width('100%')

          Text('当前版本不开放价格展示、收费提醒与支付流程。')
            .fontSize(13)
            .lineHeight(20)
            .fontColor(COLORS.TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .margin({ top: 18 })

          Button(this.isLoggedIn ? '我知道了' : '去登录 / 注册')
            .type(ButtonType.Normal)
              .borderRadius(UI.CONTROL_RADIUS)
            .backgroundColor(COLORS.PRIMARY)
            .fontColor(UI.ON_PRIMARY)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .width('100%')
            .height(54)
            .margin({ top: 24 })
            .shadow({ radius: 10, color: UI.SHADOW, offsetY: 4 })
            .onClick(() => {
              if (!this.isLoggedIn) {
                this.sheetMode = 'login';
              } else {
                this.showMainSheet = false;
              }
            })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 20, bottom: 40 })
      }
    }
    .width('100%')
  }

  @Builder
  FeatureItem(text: string) {
    Row() {
      Text('✓')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.SUCCESS)
      Text(text)
        .fontSize(15)
        .fontColor(COLORS.TEXT_PRIMARY)
        .margin({ left: 10 })
    }
  }
}
