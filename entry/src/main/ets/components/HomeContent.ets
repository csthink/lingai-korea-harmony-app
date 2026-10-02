/**
 * 首页内容组件
 * 包含: 顶部Header(问候语+连续天数), 环形进度条, 今日任务卡片
 * 适配 ArkTS 严格模式
 */
import router from '@ohos.router';
import { COLORS, WORDS_PER_LESSON } from '../utils/Constants';
import { DailyTask, UserInfo } from '../models/DataModels';
import TaskTrackingService from '../services/TaskTrackingService';
import ApiService from '../services/ApiService';
import PreferencesService from '../services/PreferencesService';
import { themeManager } from '../utils/ThemeManager';
import { UI } from '../utils/UiTokens';
import preferences from '@ohos.data.preferences';

class IndexRouteParams {
  tabIndex: number = 3;
  navFrom: string = 'home_gate';
  navAt: number = Date.now();
  openSheetMode: string = 'login';
}

@Component
export struct HomeContent {
  @State userName: string = '';
  @State streakDays: number = 0;
  @State todayProgress: number = 0;
  @State dailyTask: DailyTask = new DailyTask();
  @State taskVersionKey: number = 0;
  @State newWordsCount: number = 0;
  @State reviewWordsCount: number = 0;
  @State currentLevel: number = 1;
  @State currentLessonId: number = 1;
  @State lessonTitle: string = '关卡 1';
  @State userInfo: UserInfo = new UserInfo();
  @State themeVersion: number = 0;

  private isNavigating: boolean = false;
  private navigatingToLogin: boolean = false;
  private taskService: TaskTrackingService = TaskTrackingService.getInstance();
  private unsubscribeTheme: (() => void) | null = null;
  private unsubscribeTaskUpdate: (() => void) | null = null;
  
  private async refreshLearningSnapshot(context: Context) {
    await this.loadLearningProgress(context);
    this.streakDays = await this.taskService.getStreakDays();
  }

  private resolveFriendlyUserName(nickname: string, phone: string): string {
    const trimmedNickname = nickname.trim();
    if (trimmedNickname && !/^用户\d{3,}$/.test(trimmedNickname) && !/^user\d{3,}$/i.test(trimmedNickname)) {
      return trimmedNickname;
    }

    if (phone.trim() && !phone.includes('*')) {
      return phone.trim();
    }

    return '小灵友';
  }

  async aboutToAppear() {
    if (this.unsubscribeTheme === null) {
      this.unsubscribeTheme = themeManager.subscribe(() => {
        this.themeVersion++;
      });
    }

    const context = getContext(this);
    await this.taskService.init(context);
    this.dailyTask = await this.taskService.refreshTask();
    this.refreshHomeStats();

    if (this.unsubscribeTaskUpdate === null) {
      this.unsubscribeTaskUpdate = this.taskService.subscribeOnUpdate((task: DailyTask) => {
        this.dailyTask = task;
        this.refreshHomeStats();
        this.taskVersionKey++;
        void this.refreshLearningSnapshot(context);
      });
    }

    // 加载真实用户信息
    await this.loadUserInfo(context);
    // 加载学习进度（确定当前关卡）和连续学习状态
    await this.refreshLearningSnapshot(context);
  }

  /**
   * 刷新首页统计数据（streakDays 由异步方法单独加载）
   */
  private refreshHomeStats() {
    // 今日进度
    this.todayProgress = this.taskService.calculateTodayProgress();
    // 复习词数 — 直接取任务中真实值
    this.reviewWordsCount = this.dailyTask.reviewCount;
  }

  /**
   * 从后端获取用户信息，失败时使用默认值
   */
  private async loadUserInfo(context: Context) {
    try {
      const api = ApiService.getInstance();
      await api.init(context);
      if (!api.getToken()) {
        this.userName = '小灵友';
        this.userInfo = new UserInfo();
        return;
      }
      const userInfo = await api.getCurrentUserInfo();
      this.userInfo = userInfo;
      this.userName = this.resolveFriendlyUserName(userInfo.nickname, userInfo.phone);
    } catch (e) {
      console.warn('[HomeContent] loadUserInfo failed, using default');
      const api = ApiService.getInstance();
      this.userInfo = new UserInfo();
      if (!api.getToken()) {
        this.userName = '小灵友';
      } else if (!this.userName) {
        this.userName = '小灵友';
      }
    }
  }

  /**
   * 从本地偏好读取学习进度，并基于设置估算当前关卡词数。
   * 首页不预取真实关卡词表，避免浏览首页时提前消耗正式额度。
   */
  private async loadLearningProgress(context: Context) {
    try {
      const prefService = PreferencesService.getInstance();
      await prefService.init(context);
      const state = await prefService.getLearningState();
      this.currentLevel = state.currentLevel;
      this.currentLessonId = state.currentLesson;
      this.lessonTitle = `关卡 ${this.currentLessonId}`;
    } catch (e) {
      console.warn('[HomeContent] loadLearningProgress pref failed, using defaults');
    }

    // 读取用户设置的每关单词数
    let wordsPerLesson = WORDS_PER_LESSON;
    try {
      const context2 = getContext(this);
      const pref = await preferences.getPreferences(context2, 'user_settings');
      wordsPerLesson = await pref.get('wordsPerLesson', WORDS_PER_LESSON) as number;
    } catch (_e) {
      // 使用默认值
    }

    const api = ApiService.getInstance();
    await api.init(context);
    if (!api.getToken()) {
      this.newWordsCount = 0;
      return;
    }

    this.newWordsCount = wordsPerLesson;
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
  }

  build() {
    Column() {
      Scroll() {
        Column({ space: UI.SECTION_GAP }) {
          this.HeaderSection()
          this.ProgressSection()
          Column({ space: 14 }) {
            Text('今日任务')
              .fontSize(20)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
              .width('100%')
            this.TaskCards()
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 0, bottom: 192 })
      }
      .width('100%')
      .layoutWeight(1)
      .margin({ top: UI.CONTENT_TOP })
      .clip(true)
      .clipContent(ContentClipMode.CONTENT_ONLY)
      .scrollBar(BarState.Off)
      .backgroundColor(COLORS.BACKGROUND)
      .onAppear(() => {
        void this.loadUserInfo(getContext(this));
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BACKGROUND)
  }

  @Builder
  HeaderSection() {
    Row({ space: 14 }) {
      Column({ space: 8 }) {
        Text('你好，' + this.userName)
          .fontSize(UI.TITLE_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .width('100%')
        Row({ space: 6 }) {
          Image($r('app.media.ic_footprint'))
            .width(16)
            .height(16)
            .fillColor(COLORS.PRIMARY)
          Text('连续学习 ' + this.streakDays.toString() + ' 天')
            .fontSize(UI.CAPTION_SIZE)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLORS.PRIMARY)
        }
        .padding({ left: 10, right: 10, top: 7, bottom: 7 })
        .backgroundColor(UI.GREEN_SOFT)
        .borderRadius(12)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Image($r('app.media.lingai_robot'))
        .width(76)
        .height(76)
        .objectFit(ImageFit.Contain)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  ProgressSection() {
    Row({ space: 18 }) {
      Stack() {
        Progress({ value: this.todayProgress, total: 100, type: ProgressType.Ring })
          .width(88)
          .height(88)
          .color(COLORS.PRIMARY)
          .backgroundColor(UI.GREEN_SOFT)
          .style({ strokeWidth: 8 })
        Text(this.todayProgress.toString() + '%')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
      }
      .width(88)
      .height(88)
      Column({ space: 6 }) {
        Text('今日进度')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
        Text('跟着小语灵，继续今天的韩语学习')
          .fontSize(UI.CAPTION_SIZE)
          .lineHeight(20)
          .fontColor(COLORS.TEXT_SECONDARY)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(UI.CARD_RADIUS)
    .border({ width: 1, color: COLORS.BORDER })
  }

  @Builder
  TaskCards() {
    Column({ space: 16 }) {
      Column({ space: 16 }) {
        Row({ space: 12 }) {
          Image($r('app.media.ic_layers'))
            .width(52)
            .height(52)
            .fillColor(COLORS.PRIMARY)
            .padding(12)
            .backgroundColor(UI.GREEN_SOFT)
            .borderRadius(UI.CONTROL_RADIUS)
          Column({ space: 5 }) {
            Text(`TOPIK ${this.currentLevel <= 2 ? 'I' : 'II'} • ${this.lessonTitle}`)
              .fontSize(19)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
            Text(this.newWordsCount.toString() + ' 个新词 • 预计 ' + this.estimateMinutes().toString() + ' 分钟')
              .fontSize(UI.CAPTION_SIZE)
              .fontColor(COLORS.TEXT_SECONDARY)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
        }
        .width('100%')
        Text(this.lessonQuotaHint())
          .fontSize(UI.CAPTION_SIZE)
          .lineHeight(20)
          .fontColor(this.lessonQuotaTextColor())
          .width('100%')
          .padding(12)
          .backgroundColor(this.lessonQuotaBackgroundColor())
          .borderRadius(12)
        Button('开始')
          .type(ButtonType.Normal)
          .backgroundColor(COLORS.PRIMARY)
          .fontColor(UI.ON_PRIMARY)
          .fontSize(UI.BODY_SIZE)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .height(50)
          .borderRadius(UI.CONTROL_RADIUS)
          .onClick(() => {
            this.startLearning();
          })
      }
      .width('100%')
      .padding(20)
      .backgroundColor(COLORS.SURFACE)
      .borderRadius(UI.CARD_RADIUS)
      .border({ width: 1, color: COLORS.BORDER })
      .shadow({ radius: 12, color: UI.SHADOW, offsetY: 4 })

      Row({ space: 12 }) {
        Image($r('app.media.ic_review'))
          .width(48)
          .height(48)
          .fillColor(UI.BLUE)
          .padding(12)
          .backgroundColor(UI.BLUE_SOFT)
          .borderRadius(UI.CONTROL_RADIUS)
        Column({ space: 5 }) {
          Text('智能复习')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text(this.reviewWordsCount.toString() + ' 个单词待复习')
            .fontSize(UI.CAPTION_SIZE)
            .fontColor(COLORS.TEXT_SECONDARY)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button('去完成')
          .type(ButtonType.Normal)
          .backgroundColor(UI.BLUE)
          .fontColor(UI.ON_BLUE)
          .fontSize(14)
          .fontWeight(FontWeight.Bold)
          .height(UI.TOUCH_MIN)
          .padding({ left: 14, right: 14 })
          .borderRadius(14)
          .onClick(() => {
            this.startReview();
          })
      }
      .width('100%')
      .padding(18)
      .backgroundColor(COLORS.SURFACE)
      .borderRadius(UI.CARD_RADIUS)
      .border({ width: 1, color: COLORS.BORDER })
    }
    .width('100%')
  }

  async startLearning() {
    if (!ApiService.getInstance().getToken()) {
      await this.goLoginTab('home_start_learning');
      return;
    }
    if (this.isNavigating) return;
    this.isNavigating = true;
    try {
      await router.pushUrl({
        url: 'pages/LessonPage',
        params: {
          lessonId: this.currentLessonId,
          level: this.currentLevel,
          title: this.lessonTitle
        }
      });
    } catch (e) {
      console.error('[HomeContent] navigation failed:', e);
    } finally {
      this.isNavigating = false;
    }
  }

  async startReview() {
    if (!ApiService.getInstance().getToken()) {
      await this.goLoginTab('home_start_review');
      return;
    }
    if (this.isNavigating) return;
    this.isNavigating = true;
    try {
      await router.pushUrl({
        url: 'pages/LessonPage',
        params: {
          lessonId: this.currentLessonId,
          level: this.currentLevel,
          title: '智能复习',
          isReview: true
        }
      });
    } catch (e) {
      console.error('[HomeContent] navigation failed:', e);
    } finally {
      this.isNavigating = false;
    }
  }

  /**
   * 根据新词数量估算学习时长（分钟）
   * 按每词约 30 秒估算，最少 1 分钟
   */
  private estimateMinutes(): number {
    if (this.newWordsCount <= 0) return 1;
    return Math.max(1, Math.round(this.newWordsCount * 0.5));
  }

  private lessonQuotaHint(): string {
    if (!ApiService.getInstance().getToken()) {
      return '登录后可解锁今日 2 关学习额度';
    }
    if (this.userInfo.dailyLessonLimit <= 0) {
      return '当前会员今日学习不限量';
    }
    if (this.userInfo.dailyLessonRemaining <= 0) {
      return `今日额度已用完 · 已完成 ${this.userInfo.dailyLessonUsed}/${this.userInfo.dailyLessonLimit} 关`;
    }
    return `今日还可学习 ${this.userInfo.dailyLessonRemaining}/${this.userInfo.dailyLessonLimit} 关`;
  }

  private lessonQuotaTextColor(): string {
    if (!ApiService.getInstance().getToken()) {
      return COLORS.PRIMARY;
    }
    if (this.userInfo.dailyLessonLimit > 0 && this.userInfo.dailyLessonRemaining <= 0) {
      return UI.DANGER_TEXT;
    }
    return COLORS.TEXT_SECONDARY;
  }

  private lessonQuotaBackgroundColor(): string {
    if (!ApiService.getInstance().getToken()) {
      return UI.GREEN_SOFT;
    }
    if (this.userInfo.dailyLessonLimit > 0 && this.userInfo.dailyLessonRemaining <= 0) {
      return UI.DANGER_SOFT;
    }
    return UI.SURFACE_MUTED;
  }

  private async goLoginTab(navFrom: string): Promise<void> {
    if (this.navigatingToLogin) {
      return;
    }
    this.navigatingToLogin = true;

    const params = new IndexRouteParams();
    params.tabIndex = 3;
    params.navFrom = navFrom;
    params.navAt = Date.now();
    params.openSheetMode = 'login';

    try {
      await router.replaceUrl({
        url: 'pages/Index',
        params,
      });
    } catch (replaceErr) {
      console.warn('[HomeContent] replaceUrl to login tab failed:', JSON.stringify(replaceErr));
      try {
        await router.pushUrl({
          url: 'pages/Index',
          params,
        });
      } catch (pushErr) {
        console.error('[HomeContent] pushUrl to login tab failed:', JSON.stringify(pushErr));
      }
    } finally {
      this.navigatingToLogin = false;
    }
  }
}
