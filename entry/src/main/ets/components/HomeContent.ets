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
  @Prop @Watch('onRefreshVersion') refreshVersion: number = 0;
  @Prop @Watch('onActiveTabChange') activeTabIndex: number = -1;
  onOpenVocabulary?: () => void;
  @State userName: string = '';
  @State authReady: boolean = false;
  @State isLoggedIn: boolean = false;
  @State quotaReady: boolean = false;
  @State quotaLoadFailed: boolean = false;
  @State streakDays: number = 0;
  @State todayProgress: number = 0;
  @State dailyTask: DailyTask = new DailyTask();
  @State taskVersionKey: number = 0;
  @State newWordsCount: number = 0;
  @State reviewWordsCount: number = 0;
  @State currentLevel: number = 1;
  @State currentLessonId: number = 1;
  @State lessonTitle: string = '关卡 1';
  @State courseComplete: boolean = false;
  @State lessonInfoReady: boolean = false;
  @State userInfo: UserInfo = new UserInfo();
  @State themeVersion: number = 0;

  private isNavigating: boolean = false;
  private learningSnapshotRequest: number = 0;
  private navigatingToLogin: boolean = false;
  private taskService: TaskTrackingService = TaskTrackingService.getInstance();
  private unsubscribeTheme: (() => void) | null = null;
  private unsubscribeTaskUpdate: (() => void) | null = null;
  
  onRefreshVersion(): void {
    const context = this.getUIContext().getHostContext();
    if (!context) { return; }
    void this.refreshLearningSnapshot(context);
    void this.loadUserInfo(context);
  }

  onActiveTabChange(): void {
    if (this.activeTabIndex === 0) {
      const context = this.getUIContext().getHostContext();
      if (!context) { return; }
      void this.refreshLearningSnapshot(context);
      void this.loadUserInfo(context);
      void this.taskService.refreshTask();
    }
  }

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

    const context = this.getUIContext().getHostContext();
    if (!context) { return; }
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
    // 复习词数 - 直接取任务中真实值
    this.reviewWordsCount = this.dailyTask.reviewCount;
  }

  /**
   * 从后端获取用户信息，失败时使用默认值
   */
  private async loadUserInfo(context: Context) {
    this.quotaReady = false;
    this.quotaLoadFailed = false;
    try {
      const api = ApiService.getInstance();
      await api.init(context);
      this.isLoggedIn = api.getToken().length > 0;
      this.authReady = true;
      if (!this.isLoggedIn) {
        this.userName = '小灵友';
        this.userInfo = new UserInfo();
        return;
      }
      const userInfo = await api.getCurrentUserInfo();
      this.userInfo = userInfo;
      this.quotaReady = true;
      this.userName = this.resolveFriendlyUserName(userInfo.nickname, userInfo.phone);
    } catch (e) {
      console.warn('[HomeContent] account or quota information unavailable');
      const api = ApiService.getInstance();
      this.isLoggedIn = api.getToken().length > 0;
      this.authReady = true;
      this.quotaLoadFailed = true;
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
    const request = ++this.learningSnapshotRequest;
    this.lessonInfoReady = false;
    let level = 1;
    let lesson = 1;
    try {
      const prefService = PreferencesService.getInstance();
      await prefService.init(context);
      const state = await prefService.getLearningState();
      level = state.currentLevel;
      lesson = state.currentLesson;
    } catch (error) {
      console.warn('[HomeContent] learning state unavailable');
    }

    let wordsPerLesson = WORDS_PER_LESSON;
    try {
      const pref = await preferences.getPreferences(context, 'user_settings');
      wordsPerLesson = await pref.get('wordsPerLesson', WORDS_PER_LESSON) as number;
    } catch (error) {
      // 沿用已定义默认值，不改变保存的学习设置。
    }

    const api = ApiService.getInstance();
    await api.init(context);
    if (request !== this.learningSnapshotRequest) { return; }
    this.isLoggedIn = api.getToken().length > 0;
    this.authReady = true;
    if (!this.isLoggedIn) {
      this.newWordsCount = 0;
      this.courseComplete = false;
      return;
    }

    try {
      const info = await api.getLevelInfo();
      if (request !== this.learningSnapshotRequest) { return; }
      for (const raw of info.levels) {
        const course = raw as Record<string, Object>;
        if (course['level'] as number === level) {
          const wordCount = (course['word_count'] as number) || 0;
          const total = wordCount > 0 ? Math.ceil(wordCount / wordsPerLesson) : (course['lesson_count'] as number) || 0;
          if (total > 0) {
            const displayLesson = Math.min(lesson, total);
            this.currentLevel = level;
            this.currentLessonId = displayLesson;
            this.courseComplete = lesson > total;
            this.lessonTitle = `关卡 ${displayLesson}`;
            this.newWordsCount = wordCount > 0 ? Math.min(wordsPerLesson, wordCount - (displayLesson - 1) * wordsPerLesson) : wordsPerLesson;
            this.lessonInfoReady = true;
          }
          break;
        }
      }
    } catch (error) {
      if (request !== this.learningSnapshotRequest) { return; }
      console.warn('[HomeContent] course metadata unavailable');
    }
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

  private courseName(): string {
    return this.currentLevel === 0 ? '必备单词' : (this.currentLevel === 2 ? 'TOPIK II' : 'TOPIK I');
  }

  build() {
    Column() {
      this.HeaderSection()
      Scroll() {
        Column({ space: 24 }) {
          this.ProgressSection()
          this.TaskCards()
          Text('每天认识一点，\n把韩语带进今天。')
            .fontSize(13).lineHeight(21).fontColor(COLORS.TEXT_SECONDARY).width('100%')
        }
        .width('100%')
        .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 20, bottom: 170 })
      }
      .width('100%').layoutWeight(1).clip(true)
      .clipContent(ContentClipMode.CONTENT_ONLY).scrollBar(BarState.Off)
    }
    .width('100%').height('100%').backgroundColor(COLORS.BACKGROUND)
  }

  @Builder
  HeaderSection() {
    Column({ space: 9 }) {
      Row() {
        Text('你好，' + this.userName)
          .fontSize(UI.TITLE_SIZE).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('LingAI').fontSize(13).fontWeight(FontWeight.Bold).fontColor(COLORS.PRIMARY)
      }.width('100%')
      Row({ space: 6 }) {
        Image($r('app.media.ic_footprint')).width(14).height(14).fillColor(COLORS.PRIMARY)
        Text('连续学习 ' + this.streakDays + ' 天').fontSize(12).fontColor(COLORS.TEXT_SECONDARY)
      }
    }
    .alignItems(HorizontalAlign.Start).width('100%')
    .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: UI.CONTENT_TOP, bottom: 18 })
    .backgroundColor(COLORS.SURFACE)
  }

  private goalValue(field: string): number {
    if (field === 'step') { return this.dailyTask.lessonStepDone; }
    if (field === 'review') { return this.dailyTask.reviewCount; }
    return this.dailyTask.studyMinutes;
  }

  @Builder
  GoalItem(label: string, field: string, total: number, unit: string) {
    Column({ space: 8 }) {
      Text(label).fontSize(11).fontColor(COLORS.TEXT_SECONDARY)
      Text(`${Math.min(this.goalValue(field), total)} / ${total} ${unit}`)
        .fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLORS.TEXT_PRIMARY)
      Progress({ value: Math.min(this.goalValue(field), total), total: total, type: ProgressType.Linear })
        .width('100%').height(6)
        .style({ strokeWidth: 6, enableSmoothEffect: true, enableScanEffect: this.goalValue(field) > 0 && this.goalValue(field) < total })
        .color(this.goalValue(field) >= total ? COLORS.PRIMARY : (this.goalValue(field) > 0 ? UI.BLUE : COLORS.TEXT_HINT))
        .backgroundColor(this.goalValue(field) > 0 && this.goalValue(field) < total ? UI.BLUE_SOFT : UI.SURFACE_MUTED)
    }.alignItems(HorizontalAlign.Start).layoutWeight(1)
  }

  @Builder
  ProgressSection() {
    Column({ space: 15 }) {
      Row() {
        Text('今日目标').fontSize(15).fontWeight(FontWeight.Medium).fontColor(COLORS.TEXT_PRIMARY)
        Blank()
        Text(this.todayProgress >= 100 ? '已完成 100%' : `${this.todayProgress}%`)
          .fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(this.todayProgress >= 100 ? COLORS.PRIMARY : COLORS.TEXT_PRIMARY)
      }.width('100%')
      Row({ space: 13 }) {
        this.GoalItem('关卡步骤', 'step', 1, '步')
        this.GoalItem('复习单词', 'review', 20, '个')
        this.GoalItem('学习时长', 'minutes', 10, '分')
      }.width('100%')
    }.width('100%')
  }

  @Builder
  TaskCards() {
    Column({ space: 12 }) {
      Column({ space: 16 }) {
        Row() {
          Text(this.courseName()).fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLORS.PRIMARY)
          Blank()
          Text(this.lessonTitle).fontSize(13).fontColor(COLORS.TEXT_SECONDARY)
        }.width('100%')
        Text(this.courseComplete ? '这个课程，已学完一遍' : (this.todayProgress === 0 ? '从这一关开始' : '接着上次，继续学'))
          .fontSize(28).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY).width('100%')
        Text('按自己的节奏，认识新的韩语表达。')
          .fontSize(14).lineHeight(22).fontColor(COLORS.TEXT_SECONDARY).width('100%')
        Text(!this.authReady ? '正在加载学习信息' : !this.isLoggedIn ? '登录后开始今天的学习' : this.newWordsCount > 0 ? `本关 ${this.newWordsCount} 个词 · 约 ${this.estimateMinutes()} 分钟` : '准备当前课程，按自己的节奏开始。')
          .fontSize(12).fontColor(COLORS.TEXT_SECONDARY).width('100%')
        Button(this.learningActionLabel())
          .enabled(this.authReady)
          .type(ButtonType.Normal).width('100%').height(52).borderRadius(UI.CONTROL_RADIUS)
          .backgroundColor(COLORS.PRIMARY).fontColor(UI.ON_PRIMARY).fontSize(16).fontWeight(FontWeight.Bold)
          .onClick(() => { this.startLearning(); })
      }
      .width('100%').padding(21).backgroundColor(COLORS.SURFACE)
      .border({ width: 1, color: COLORS.BORDER }).borderRadius(UI.CARD_RADIUS).clip(true)
      Text(this.lessonQuotaHint()).fontSize(11).lineHeight(18).fontColor(this.lessonQuotaTextColor()).width('100%')
      Column({ space: 12 }) {
        Row({ space: 12 }) {
          Column({ space: 6 }) {
            Text('智能复习').fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
            Text(`今日已复习 ${this.reviewWordsCount} 个单词`).fontSize(12).fontColor(COLORS.TEXT_SECONDARY)
          }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          Button('去复习 ›').enabled(this.authReady).type(ButtonType.Normal).height(44).borderRadius(12)
            .backgroundColor(UI.GREEN_SOFT).fontColor(COLORS.PRIMARY).fontSize(13)
            .onClick(() => { this.startReview(); })
        }.width('100%')
        Text('把想记住的词，再看一遍。').fontSize(13).fontColor(COLORS.TEXT_SECONDARY).width('100%')
      }
      .width('100%').padding({ top: 20, bottom: 20 }).margin({ top: 8 })
      .border({ width: { top: 1, bottom: 1 }, color: COLORS.BORDER })
    }.width('100%')
  }

  private learningActionLabel(): string {
    if (!this.authReady) { return '正在加载账号'; }
    if (!this.isLoggedIn) { return '登录后开始学习'; }
    if (!this.lessonInfoReady) { return '重新加载课程'; }
    if (this.courseComplete) { return '再练习一遍'; }
    return this.currentLessonId > 1 || this.todayProgress > 0 ? '继续学习' : '开始学习';
  }

  async startLearning() {
    if (!ApiService.getInstance().getToken()) {
      await this.goLoginTab('home_start_learning');
      return;
    }
    if (!this.lessonInfoReady) {
      const context = this.getUIContext().getHostContext();
      if (context) { await this.loadLearningProgress(context); }
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
    if (this.onOpenVocabulary) {
      this.onOpenVocabulary();
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
    if (!this.authReady) { return '正在加载账号信息'; }
    if (!this.isLoggedIn) {
      return '登录后可解锁今日 2 关学习额度';
    }
    if (!this.quotaReady) {
      return this.quotaLoadFailed ? '学习额度暂时无法读取，请稍后重试。' : '正在加载今日学习额度';
    }
    if (this.userInfo.dailyLessonLimit <= 0) {
      return '当前会员今日学习不限量';
    }
    if (this.userInfo.dailyLessonRemaining <= 0) {
      return `今日额度已用完 · 已使用 ${this.userInfo.dailyLessonUsed}/${this.userInfo.dailyLessonLimit} 关额度`;
    }
    return `今日还可学习 ${this.userInfo.dailyLessonRemaining}/${this.userInfo.dailyLessonLimit} 关`;
  }

  private lessonQuotaTextColor(): string {
    if (!this.authReady || !this.quotaReady) { return COLORS.TEXT_SECONDARY; }
    if (!this.isLoggedIn) {
      return COLORS.PRIMARY;
    }
    if (this.userInfo.dailyLessonLimit > 0 && this.userInfo.dailyLessonRemaining <= 0) {
      return UI.DANGER_TEXT;
    }
    return COLORS.TEXT_SECONDARY;
  }

  private lessonQuotaBackgroundColor(): string {
    if (!this.authReady || !this.quotaReady) { return UI.SURFACE_MUTED; }
    if (!this.isLoggedIn) {
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
