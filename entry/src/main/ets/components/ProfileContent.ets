/**
 * 我的页面内容组件
 * 包含: 用户卡片, VIP横幅, 今日任务统计, 菜单列表
 * 适配 ArkTS 严格模式
 */
import { router } from '@kit.ArkUI';
import { COLORS } from '../utils/Constants';
import { DailyTask } from '../models/DataModels';
import TaskTrackingService from '../services/TaskTrackingService';
import ApiService, { ApiError, PhoneAuthStatus } from '../services/ApiService';
import promptAction from '@ohos.promptAction';
import { themeManager } from '../utils/ThemeManager';
import OneClickAuthService, { OneClickError } from '../services/OneClickAuthService';
import common from '@ohos.app.ability.common';

@Component
export struct ProfileContent {
  @State isLoggedIn: boolean = false;
  @State isPro: boolean = false;  // 区分Pro会员和普通会员
  @State userName: string = '点击登录/注册';
  @State userStatus: string = '登录同步学习进度';
  @State showMainSheet: boolean = false;  // 统一弹窗状态
  @State sheetMode: string = 'vip';  // 'vip' | 'login' | 'login-upgrade'
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
  @State showPaymentConfirmDialog: boolean = false;
  @State loginError: string = '';  // 登录/验证码错误提示
  @State isLoggingIn: boolean = false;  // 登录中状态锁

  // 一键登录状态
  @State oneClickEnabled: boolean = false;
  @State isOneClickLoading: boolean = false;
  @State showSmsFallback: boolean = false;
  @State oneClickErrorMsg: string = '';

  // 任务数据
  @State lessonCount: number = 13;
  @State reviewDone: boolean = true;
  @State studyDone: boolean = true;
  @State themeVersion: number = 0;

  private taskService: TaskTrackingService = TaskTrackingService.getInstance();
  private unsubscribeTheme: (() => void) | null = null;

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
    const savedToken = apiService.getToken();
    if (savedToken.length > 0) {
      this.isLoggedIn = true;
      this.userName = '已登录用户';
      this.userStatus = 'LingAI 会员';
    }

    await this.taskService.init(context);
    this.dailyTask = this.taskService.getCurrentTask();
    this.lessonCount = this.dailyTask.lessonStepDone;

    this.taskService.setOnUpdateCallback((task: DailyTask) => {
      this.dailyTask = task;
      this.lessonCount = task.lessonStepDone;
      this.taskVersionKey++;
    });

    // 初始化一键登录
    this.initOneClickLogin(context);
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
        // 开关关闭，直接显示短信登录
        this.showSmsFallback = true;
      }
    } catch (error) {
      console.error('[ProfileContent] Init one-click failed:', error);
      this.showSmsFallback = true;
    }
  }

  async performOneClickLogin() {
    if (this.isOneClickLoading) return;
    this.isOneClickLoading = true;
    this.oneClickErrorMsg = '';
    
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const oneClickService = OneClickAuthService.getInstance();
      const apiService = ApiService.getInstance();
      
      // 1. 拉起授权页获取 Token
      const accessToken = await oneClickService.requestToken(context);
      
      // 2. 调用服务端一键登录
      await apiService.loginByOneClick(accessToken, context);
      
      // 3. 登录成功处理
      this.handleLoginSuccess();
      
    } catch (error) {
      this.isOneClickLoading = false;
      console.error('[ProfileContent] One-click login failed:', error);
      
      let errorMsg = '一键登录失败，请尝试短信登录';
      
      // 错误映射
      if (error instanceof Error) {
         if (error.message === OneClickError.USER_CANCELLED) {
           errorMsg = '用户取消授权';
         } else if (error.message === OneClickError.NO_SIM) {
           errorMsg = '请检查SIM卡和网络连接';
         } else if (error.message === OneClickError.SDK_NOT_AVAILABLE) {
           errorMsg = '一键登录暂不可用'; // Stub 模式会走到这里
         } else if (error.message === OneClickError.NETWORK_ERROR) {
            errorMsg = '网络连接失败';
         }
      }
      
      this.oneClickErrorMsg = errorMsg;
      promptAction.showToast({ message: errorMsg, duration: 2000 });
      
      // 失败后展开短信登录
      this.showSmsFallback = true;
    }
  }

  handleLoginSuccess() {
    this.isLoggedIn = true;
    this.userName = '已登录用户';
    this.userStatus = 'LingAI 会员';
    this.showMainSheet = false;
    this.phoneNumber = '';
    this.verifyCode = '';
    this.isLoggingIn = false;
    this.isOneClickLoading = false;

    if (this.sheetMode === 'login-upgrade') {
      setTimeout(() => {
        this.showPaymentConfirmation();
      }, 300);
    }
  }

  aboutToDisappear() {
    if (this.unsubscribeTheme !== null) {
      this.unsubscribeTheme();
      this.unsubscribeTheme = null;
    }
  }

  build() {
    Stack() {
      Column() {
        Scroll() {
          Column({ space: 20 }) {
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
          .padding({ left: 24, right: 24, top: 0, bottom: 120 })
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(COLORS.BACKGROUND)
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

      if (this.showPaymentConfirmDialog) {
        this.PaymentConfirmDialog()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  UserCard() {
    Row() {
      // 头像（带皇冠标识）
      Stack({ alignContent: Alignment.BottomEnd }) {
        Column() {
          Image($r('app.media.ic_mine'))
            .width(28)
            .height(28)
            .fillColor(COLORS.TEXT_SECONDARY)
        }
        .width(64)
        .height(64)
        .borderRadius(32)
        .backgroundColor('#f1f5f9')
        .justifyContent(FlexAlign.Center)

        // Pro会员皇冠标识
        if (this.isPro) {
          Column() {
            Text('👑')
              .fontSize(12)
          }
          .width(22)
          .height(22)
          .borderRadius(11)
          .backgroundColor('#f59e0b')
          .justifyContent(FlexAlign.Center)
          .border({ width: 2, color: '#ffffff' })
        }
      }

      // 用户信息
      Column() {
        Text(this.userName)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)

        Text(this.userStatus)
          .fontSize(13)
          .fontColor(this.isPro ? '#f59e0b' : COLORS.TEXT_SECONDARY)
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 20 })

      // 右箭头
      Text('>')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor('#94a3b8')
    }
    .width('100%')
    .padding(24)
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(24)
    .border({ width: 1, color: 'rgba(0,0,0,0.04)' })
    .shadow({ radius: 12, color: 'rgba(148,163,184,0.15)', offsetY: 4 })
    .onClick(() => {
      if (!this.isLoggedIn) {
        if (this.isSheetAnimating) {
          // 动画进行中，记录意图，等动画结束后打开
          this.pendingSheetMode = 'login';
        } else {
          this.sheetMode = 'login';
          this.showMainSheet = true;
        }
      }
    })
  }

  @Builder
  VIPBanner() {
    // 仅在用户不是Pro会员时显示
    if (!this.isPro) {
      Row() {
        Row() {
          Text('👑')
            .fontSize(16)

          Text('升级 LingAI Pro')
            .fontSize(15)
            .fontWeight(FontWeight.Bold)
            .fontColor('#ffffff')
            .margin({ left: 10 })
        }

        Blank()

        Button('查看')
          .type(ButtonType.Capsule)
          .backgroundColor('rgba(255,255,255,0.25)')
          .fontColor('#ffffff')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .height(28)
          .padding({ left: 14, right: 14 })
          .onClick(() => {
            if (this.isSheetAnimating) {
              // 动画进行中，记录意图，等动画结束后打开
              this.pendingSheetMode = 'vip';
            } else {
              this.sheetMode = 'vip';
              this.showMainSheet = true;
            }
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 16 })
      .borderRadius(20)
      .linearGradient({
        angle: 90,
        colors: [['#4f46e5', 0], ['#818cf8', 1]]
      })
      .shadow({ radius: 20, color: 'rgba(79, 70, 229, 0.3)', offsetY: 8 })
    }
  }

  @Builder
  TaskStatsCard() {
    Row() {
      // 推进
      Column() {
        Text(this.lessonCount.toString())
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.PRIMARY)

        Text('推进')
          .fontSize(12)
          .fontColor(COLORS.TEXT_HINT)
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      // 复习
      Column() {
        if (this.reviewDone) {
          Image($r('app.media.ic_check'))
            .width(24)
            .height(24)
            .fillColor(COLORS.SUCCESS)
        } else {
          Text('—')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_HINT)
        }

        Text('复习')
          .fontSize(12)
          .fontColor(COLORS.TEXT_HINT)
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      // 学习
      Column() {
        if (this.studyDone) {
          Image($r('app.media.ic_check'))
            .width(24)
            .height(24)
            .fillColor('#fb923c')
        } else {
          Text('—')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_HINT)
        }

        Text('学习')
          .fontSize(12)
          .fontColor(COLORS.TEXT_HINT)
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .padding({ top: 25, bottom: 25 })
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(24)
    .border({ width: 1, color: 'rgba(0,0,0,0.04)' })
    .shadow({ radius: 12, color: 'rgba(148,163,184,0.15)', offsetY: 4 })
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
      // 图标容器
      Column() {
        Image(icon)
          .width(18)
          .height(18)
          .fillColor(iconColor)
      }
      .width(40)
      .height(40)
      .borderRadius(12)
      .backgroundColor(this.getIconBgColor(iconColor))
      .justifyContent(FlexAlign.Center)

      // 标题
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLORS.TEXT_PRIMARY)
        .margin({ left: 15 })

      Blank()

      // 箭头
      Image($r('app.media.ic_arrow_right'))
        .width(20)
        .height(20)
        .fillColor(COLORS.TEXT_HINT)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(20)
    .border({ width: 1, color: 'rgba(0,0,0,0.04)' })
    .shadow({ radius: 12, color: 'rgba(148,163,184,0.15)', offsetY: 4 })
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
      promptAction.showToast({ message: this.loginError, duration: 3000 });
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
      this.isLoggedIn = true;
      this.userName = '用户' + this.phoneNumber.slice(-4);
      this.userStatus = 'LingAI 会员';
      this.showMainSheet = false;
      this.phoneNumber = '';
      this.verifyCode = '';
      this.isLoggingIn = false;
    }).catch((error: Error) => {
      // 登录失败，显示后端 message
      this.isLoggingIn = false;
      if (error instanceof ApiError) {
        this.loginError = error.message;
      } else {
        this.loginError = '登录失败，请检查网络';
      }
      promptAction.showToast({ message: this.loginError, duration: 3000 });
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
      promptAction.showToast({ message: this.loginError, duration: 3000 });
    });
  }

  showPaymentConfirmation() {
    this.showPaymentConfirmDialog = true;
  }

  cancelPaymentConfirmation() {
    this.showPaymentConfirmDialog = false;
  }

  confirmPaymentSubscription() {
    this.showPaymentConfirmDialog = false;
    this.isPro = true;
    this.userStatus = 'LingAI Pro 会员';
  }

  @Builder
  PaymentConfirmDialog() {
    Column() {
      Column() {
        Column() {
          Text('确认订阅')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(themeManager.isDark() ? '#f8fafc' : '#111827')
            .textAlign(TextAlign.Center)
            .width('100%')

          Text('确认支付 ¥128/年 订阅 LingAI Pro？')
            .fontSize(16)
            .lineHeight(24)
            .fontColor(themeManager.isDark() ? '#94a3b8' : '#4b5563')
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ top: 14, bottom: 24 })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 0 })

        Divider()
          .color(themeManager.isDark() ? 'rgba(148,163,184,0.24)' : 'rgba(15,23,42,0.10)')

        Row() {
          Button('取消')
            .type(ButtonType.Normal)
            .backgroundColor(Color.Transparent)
            .fontColor(themeManager.isDark() ? '#94a3b8' : '#6b7280')
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
            .height(56)
            .borderRadius(0)
            .onClick(() => {
              this.cancelPaymentConfirmation();
            })

          Column()
            .width(1)
            .height(24)
            .backgroundColor(themeManager.isDark() ? 'rgba(148,163,184,0.24)' : 'rgba(15,23,42,0.10)')

          Button('确认支付')
            .type(ButtonType.Normal)
            .backgroundColor(Color.Transparent)
            .fontColor('#6366f1')
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
            .height(56)
            .borderRadius(0)
            .onClick(() => {
              this.confirmPaymentSubscription();
            })
        }
        .width('100%')
      }
      .width('86%')
      .backgroundColor(themeManager.isDark() ? '#1f2937' : '#ffffff')
      .borderRadius(22)
      .border({ width: 1, color: themeManager.isDark() ? 'rgba(148,163,184,0.22)' : 'rgba(15,23,42,0.06)' })
      .shadow({
        radius: 24,
        color: themeManager.isDark() ? 'rgba(0,0,0,0.50)' : 'rgba(15,23,42,0.16)',
        offsetY: 6
      })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(2,6,23,0.52)')
    .onClick(() => {
      this.cancelPaymentConfirmation();
    })
  }

  @Builder
  MainSheetBuilder() {
    Column() {
      if (this.sheetMode === 'login' || this.sheetMode === 'login-upgrade') {
        // 登录模式内容
        Column() {
          Text(this.sheetMode === 'login-upgrade' ? '登录后订阅' : '登录 / 注册')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(themeManager.isDark() ? '#f8fafc' : '#1e293b')
            .margin({ top: 10 })

          Text(this.sheetMode === 'login-upgrade' ? '登录以继续订阅 LingAI Pro' : '登录同步学习进度')
            .fontSize(14)
            .fontColor(themeManager.isDark() ? '#94a3b8' : '#64748b')
            .margin({ top: 8, bottom: 24 })

          // 一键登录入口
          if (this.oneClickEnabled) {
            Column() {
              Button(this.isOneClickLoading ? '正在启动...' : '本机号码一键登录')
                .type(ButtonType.Capsule)
                .backgroundColor('#6366f1')
                .fontColor('#ffffff')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .width('100%')
                .height(54)
                .onClick(() => {
                  this.performOneClickLogin();
                })
              
              if (!this.showSmsFallback) {
                 Row() {
                    Divider().width('35%').color(themeManager.isDark() ? '#334155' : '#e2e8f0')
                    Text('或').fontSize(12).fontColor(themeManager.isDark() ? '#64748b' : '#94a3b8').margin({ left: 10, right: 10 })
                    Divider().width('35%').color(themeManager.isDark() ? '#334155' : '#e2e8f0')
                 }.margin({ top: 24, bottom: 24 })

                 Text('其他手机号码登录 >')
                   .fontSize(14)
                   .fontColor(themeManager.isDark() ? '#94a3b8' : '#64748b')
                   .onClick(() => {
                     this.showSmsFallback = true;
                   })
                   .padding(10)
              }
            }
            .width('100%')
            .margin({ bottom: this.showSmsFallback ? 20 : 0 })
          }

          // 短信登录表单
          if (this.showSmsFallback || !this.oneClickEnabled) {
             Column() {
               // 手机号输入
               Column({ space: 8 }) {
                 Text('手机号')
                   .fontSize(14)
                   .fontColor(themeManager.isDark() ? '#94a3b8' : '#64748b')
                   .width('100%')
                 TextInput({ placeholder: '请输入手机号', text: this.phoneNumber })
                   .type(InputType.PhoneNumber)
                   .maxLength(11)
                   .height(48)
                   .borderRadius(12)
                   .backgroundColor(this.phoneError
                     ? (themeManager.isDark() ? 'rgba(127,29,29,0.25)' : '#fef2f2')
                     : (themeManager.isDark() ? 'rgba(15,23,42,0.75)' : '#f1f5f9'))
                   .border({ width: this.phoneError ? 1 : 0, color: '#ef4444' })
                   .fontColor(themeManager.isDark() ? '#f8fafc' : '#0f172a')
                   .placeholderColor(themeManager.isDark() ? '#94a3b8' : '#64748b')
                   .onChange((value: string) => {
                     // 限制只能输入数字，最多11位
                     const cleanValue = value.replace(/\D/g, '').slice(0, 11);
                     this.phoneNumber = cleanValue;
                     // 手机号格式验证
                     if (cleanValue.length > 0 && cleanValue.length < 11) {
                       this.phoneError = '请输入完整的11位手机号';
                     } else if (cleanValue.length === 11 && !/^1[3-9]\d{9}$/.test(cleanValue)) {
                       this.phoneError = '手机号格式不正确';
                     } else {
                       this.phoneError = '';
                     }
                   })
                 
                 // 错误提示
                 if (this.phoneError) {
                   Text(this.phoneError)
                     .fontSize(12)
                     .fontColor('#ef4444')
                     .width('100%')
                 }
               }
               .width('100%')
       
               // 验证码输入
               Column({ space: 8 }) {
                 Text('验证码')
                   .fontSize(14)
                   .fontColor(themeManager.isDark() ? '#94a3b8' : '#64748b')
                   .width('100%')
                 Row() {
                   TextInput({ placeholder: '请输入验证码', text: this.verifyCode })
                     .type(InputType.Number)
                     .height(48)
                     .borderRadius(12)
                     .backgroundColor(themeManager.isDark() ? 'rgba(15,23,42,0.75)' : '#f1f5f9')
                     .fontColor(themeManager.isDark() ? '#f8fafc' : '#0f172a')
                     .placeholderColor(themeManager.isDark() ? '#94a3b8' : '#64748b')
                     .layoutWeight(1)
                     .onChange((value: string) => {
                       this.verifyCode = value;
                     })
                   Button(this.countdown > 0 ? `${this.countdown}s` : '获取验证码')
                     .type(ButtonType.Capsule)
                     .backgroundColor(this.countdown > 0
                       ? (themeManager.isDark() ? '#334155' : '#e2e8f0')
                       : (themeManager.isDark() ? 'rgba(99,102,241,0.25)' : '#6366f1'))
                     .fontColor(this.countdown > 0
                       ? (themeManager.isDark() ? '#64748b' : '#94a3b8')
                       : '#ffffff')
                     .fontSize(14)
                     .height(44)
                     .margin({ left: 12 })
                     .enabled(this.phoneNumber.length === 11 && this.countdown === 0)
                     .onClick(() => {
                       this.startCountdown();
                     })
                 }
                 .width('100%')
               }
               .width('100%')
               .margin({ top: 16 })
       
               // 登录按钮
               Button(this.sheetMode === 'login-upgrade' ? '登录并订阅' : '登录')
                 .type(ButtonType.Capsule)
                 .backgroundColor('#6366f1')
                 .fontColor('#ffffff')
                 .fontSize(16)
                 .fontWeight(FontWeight.Bold)
                 .width('100%')
                 .height(54)
                 .margin({ top: 24 })
                 .enabled(this.phoneNumber.length === 11 && this.verifyCode.length >= 4)
                 .opacity(this.phoneNumber.length === 11 && this.verifyCode.length >= 4 ? 1 : 0.5)
                 .onClick(() => {
                   this.performSheetLogin();
                 })
             }
             .width('100%')
          }

          // 返回按钮（仅在login-upgrade模式显示）
          if (this.sheetMode === 'login-upgrade') {
            Button('← 返回')
              .type(ButtonType.Normal)
              .backgroundColor(Color.Transparent)
              .fontColor(themeManager.isDark() ? '#94a3b8' : '#64748b')
              .fontSize(14)
              .height(40)
              .margin({ top: 12 })
              .onClick(() => {
                this.sheetMode = 'vip';
              })
          }
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 20, bottom: 50 })
      } else {
        // VIP模式内容
        Column() {
          // 皇冠图标
          Column() {
            Text('👑')
              .fontSize(32)
          }
          .width(70)
          .height(70)
          .borderRadius(20)
          .backgroundColor('#6366f1')
          .justifyContent(FlexAlign.Center)
          .margin({ top: 10 })

          // 标语
          Text('提升 3 倍学习效率')
            .fontSize(16)
            .fontColor(themeManager.isDark() ? '#94a3b8' : '#64748b')
            .margin({ top: 20, bottom: 24 })

          // 价格卡片
          Stack({ alignContent: Alignment.TopEnd }) {
            Column() {
              // 价格
              Row() {
                Text('¥')
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#6366f1')
                  .margin({ right: 2 })
                Text('128')
                  .fontSize(42)
                  .fontWeight(FontWeight.Bold)
                  .fontColor('#6366f1')
                Text(' / 年')
                  .fontSize(14)
                  .fontColor(themeManager.isDark() ? '#94a3b8' : '#64748b')
                  .margin({ left: 4, bottom: 8 })
              }
              .alignItems(VerticalAlign.Bottom)

              // 功能列表
              Column({ space: 12 }) {
                this.FeatureItem('无限体力')
                this.FeatureItem('离线学习模式')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .margin({ top: 16 })
            }
            .width('100%')
            .padding(24)
            .borderRadius(20)
            .border({ width: 2, color: '#6366f1' })

            // 推荐标签
            Text('推荐')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor('#ffffff')
              .backgroundColor('#f59e0b')
              .borderRadius(8)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .margin({ top: -1, right: 16 })
          }
          .width('100%')

          // 立即升级按钮
          Button('立即升级 →')
            .type(ButtonType.Capsule)
            .backgroundColor('#6366f1')
            .fontColor('#ffffff')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .width('100%')
            .height(54)
            .margin({ top: 24 })
            .shadow({ radius: 15, color: 'rgba(99, 102, 241, 0.4)', offsetY: 4 })
            .onClick(() => {
              if (!this.isLoggedIn) {
                // 未登录，切换到登录升级模式
                this.sheetMode = 'login-upgrade';
              } else {
                // 已登录，关闭弹窗后弹出支付确认对话框
                this.showMainSheet = false;
                setTimeout(() => {
                  this.showPaymentConfirmation();
                }, 300);
              }
            })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 20, bottom: 50 })
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
        .fontColor('#10b981')
      Text(text)
        .fontSize(15)
        .fontColor(themeManager.isDark() ? '#f8fafc' : '#0f172a')
        .margin({ left: 10 })
    }
  }
}
