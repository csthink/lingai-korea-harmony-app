/**
 * 学习地图内容组件
 * 包含: 分段选择器(TOPIK I/II/必备单词), 关卡地图路径
 * 适配 ArkTS 严格模式
 */
import router from '@ohos.router';
import { COLORS, TOPIK_LEVELS, WORDS_PER_LESSON } from '../utils/Constants';
import preferences from '@ohos.data.preferences';
import { themeManager } from '../utils/ThemeManager';
import { UI } from '../utils/UiTokens';
import ApiService from '../services/ApiService';
import PreferencesService from '../services/PreferencesService';
import { AuthRequiredState } from './AuthRequiredState';
import { UserInfo } from '../models/DataModels';

class IndexRouteParams {
  tabIndex: number = 3;
  navFrom: string = 'study_gate';
  navAt: number = Date.now();
  openSheetMode: string = 'login';
}

// 关卡状态枚举
export enum LevelStatus {
  LOCKED,
  CURRENT,
  COMPLETED
}

// 关卡节点数据
export class LevelNodeData {
  id: number = 0;
  status: LevelStatus = LevelStatus.LOCKED;
  stars: number = 0;  // 0-3 颗星
  posX: number = 0;   // 节点X位置百分比
  posY: number = 0;   // 节点Y位置

  constructor(id: number, status: LevelStatus, stars: number = 0) {
    this.id = id;
    this.status = status;
    this.stars = stars;
  }
}

@Component
export struct StudyContent {
  @Prop @Watch('onActiveTabIndexChange') activeTabIndex: number = -1;
  @State selectedTabIndex: number = 0;  // 0: TOPIK I, 1: TOPIK II, 2: 必备单词
  @State currentLevel: number = 1;
  @State levels: LevelNodeData[] = [];
  @State wordsPerLesson: number = WORDS_PER_LESSON;
  @State breathScale: number = 1.0;  // 第1层波纹缩放
  @State breathOpacity: number = 0.6;  // 第1层波纹透明度
  @State ripple2Scale: number = 1.0;  // 第2层波纹缩放
  @State ripple2Opacity: number = 0.4;  // 第2层波纹透明度
  @State ripple3Scale: number = 1.0;  // 第3层波纹缩放
  @State ripple3Opacity: number = 0.2;  // 第3层波纹透明度
  @State themeVersion: number = 0;
  @State authChecked: boolean = false;
  @State requiresLogin: boolean = false;
  @State userInfo: UserInfo = new UserInfo();

  private isNavigating: boolean = false;
  private navigatingToLogin: boolean = false;
  // 从 API 加载的每个 level 的数据（key: level值）
  private levelLessonCounts: Map<number, number> = new Map();  // 接口 lesson_count
  private levelWordCounts: Map<number, number> = new Map();    // 接口 word_count（兆底）
  // 当前学习进度（本地 LearningState）
  @State currentLessonId: number = 1;
  @State currentProgressLevel: number = 1;
  private breathTimer: number = -1;
  private ripplePhase: number = 0;  // 波纹相位
  private unsubscribeTheme: (() => void) | null = null;

  onActiveTabIndexChange(): void {
    if (this.activeTabIndex !== 1) {
      return;
    }
    void this.refreshForVisibleTab();
  }

  async aboutToAppear() {
    if (this.unsubscribeTheme === null) {
      this.unsubscribeTheme = themeManager.subscribe(() => {
        this.themeVersion++;
      });
    }

    const context = getContext(this);
    await this.refreshAccessState(context);
    if (this.requiresLogin) {
      return;
    }
    await this.prepareAuthorizedContent(context);
  }

  private async refreshForVisibleTab(): Promise<void> {
    const context = getContext(this);
    await this.refreshAccessState(context);
    if (this.requiresLogin) {
      return;
    }
    await this.prepareAuthorizedContent(context);
  }

  private async refreshAccessState(context: Context): Promise<void> {
    const api = ApiService.getInstance();
    await api.init(context);
    this.requiresLogin = api.getToken().length === 0;
    if (this.requiresLogin) {
      this.userInfo = new UserInfo();
    }
    this.authChecked = true;
  }

  private async loadUserInfo(context: Context): Promise<void> {
    try {
      const api = ApiService.getInstance();
      await api.init(context);
      if (!api.getToken()) {
        this.userInfo = new UserInfo();
        return;
      }
      this.userInfo = await api.getCurrentUserInfo();
    } catch (e) {
      console.warn('[StudyContent] loadUserInfo failed, using default quota');
      this.requiresLogin = ApiService.getInstance().getToken().length === 0;
      this.userInfo = new UserInfo();
    }
  }

  private async prepareAuthorizedContent(context: Context): Promise<void> {
    await this.loadUserInfo(context);
    if (this.requiresLogin) {
      return;
    }

    // 读取每关单词数设置
    try {
      const pref = await preferences.getPreferences(context, 'user_settings');
      this.wordsPerLesson = await pref.get('wordsPerLesson', WORDS_PER_LESSON) as number;
    } catch (e) {
      this.wordsPerLesson = WORDS_PER_LESSON;
    }

    // 读取本地学习进度
    try {
      const prefService = PreferencesService.getInstance();
      await prefService.init(context);
      const state = await prefService.getLearningState();
      this.currentLessonId = state.currentLesson;
      this.currentProgressLevel = state.currentLevel;
    } catch (e) {
      console.warn('[StudyContent] getLearningState failed, using defaults');
    }

    // 从后端加载关卡配置
    await this.loadLevelInfoFromApi(context);

    this.loadLevels();
    this.startRippleAnimation();
  }

  /**
   * 从后端加载关卡总配置，填充 levelWordCounts
   */
  private async loadLevelInfoFromApi(context: Context) {
    try {
      const api = ApiService.getInstance();
      await api.init(context);
      const levelInfo = await api.getLevelInfo();
      if (levelInfo && levelInfo.levels && levelInfo.levels.length > 0) {
        for (let i = 0; i < levelInfo.levels.length; i++) {
          const lv = levelInfo.levels[i] as Record<string, Object>;
          const lvValue = (lv['level'] as number) || 0;
          const wordCount = (lv['word_count'] as number) || 0;
          const lessonCount = (lv['lesson_count'] as number) || 0;
          if (lvValue >= 0) {
            if (lessonCount > 0) {
              this.levelLessonCounts.set(lvValue, lessonCount);
            }
            if (wordCount > 0) {
              this.levelWordCounts.set(lvValue, wordCount);
            }
          }
        }
        // 如果 API 返回了 words_per_lesson，作为回退值
        if (levelInfo.words_per_lesson > 0 && this.wordsPerLesson === WORDS_PER_LESSON) {
          this.wordsPerLesson = levelInfo.words_per_lesson;
        }
        console.info('[StudyContent] Loaded level info from API, levels:', levelInfo.levels.length);
      }
    } catch (e) {
      console.warn('[StudyContent] loadLevelInfoFromApi failed, using fallback');
    }
  }

  aboutToDisappear() {
    if (this.breathTimer !== -1) {
      clearInterval(this.breathTimer);
      this.breathTimer = -1;
    }
    if (this.unsubscribeTheme !== null) {
      this.unsubscribeTheme();
      this.unsubscribeTheme = null;
    }
  }

  startRippleAnimation() {
    if (this.breathTimer !== -1) {
      clearInterval(this.breathTimer);
      this.breathTimer = -1;
    }
    // 水波纹向外扩散动画：3层波纹循环扩散
    this.breathTimer = setInterval(() => {
      this.ripplePhase += 0.025;  // 降低速度，更柔和的扩散节奏

      // 第1层波纹 - 最内层，先扩散
      const phase1 = this.ripplePhase % 1;
      this.breathScale = 1.0 + phase1 * 0.25;  // 1.0 -> 1.25
      this.breathOpacity = 0.6 * (1 - phase1);  // 0.6 -> 0

      // 第2层波纹 - 中层，延迟0.33个周期
      const phase2 = (this.ripplePhase + 0.67) % 1;
      this.ripple2Scale = 1.0 + phase2 * 0.25;
      this.ripple2Opacity = 0.4 * (1 - phase2);

      // 第3层波纹 - 外层，延迟0.67个周期
      const phase3 = (this.ripplePhase + 0.33) % 1;
      this.ripple3Scale = 1.0 + phase3 * 0.25;
      this.ripple3Opacity = 0.3 * (1 - phase3);
    }, 60);  // 增加间隔时间
  }

  loadLevels() {
    // 根据当前选择的 Tab 获取 level 值
    const levelValues: number[] = [1, 2, 0];  // TOPIK I, TOPIK II, 常考单词
    this.currentLevel = levelValues[this.selectedTabIndex];

    // 优先使用 API lesson_count，其次用 word_count 计算，最后回退到默认 10
    let lessonCount: number;
    const apiLessonCount = this.levelLessonCounts.get(this.currentLevel) || 0;
    if (apiLessonCount > 0) {
      lessonCount = apiLessonCount;
    } else {
      const wordCount = this.levelWordCounts.get(this.currentLevel) || 0;
      if (wordCount > 0) {
        lessonCount = Math.ceil(wordCount / this.wordsPerLesson);
      } else {
        lessonCount = 10;  // API 未加载时的最小回退
      }
    }

    // 确定当前 Tab 下的学习进度（只有当前选中的 level 与学习进度的 level 匹配时才显示进度）
    const isCurrentProgressTab = (this.currentLevel === this.currentProgressLevel);
    const progressLesson = isCurrentProgressTab ? this.currentLessonId : 0;

    // 生成关卡节点
    const newLevels: LevelNodeData[] = [];
    const displayCount = Math.min(lessonCount, 10);  // 显示前 10 关
    for (let i = 1; i <= displayCount; i++) {
      const node = new LevelNodeData(i, LevelStatus.LOCKED, 0);

      if (isCurrentProgressTab) {
        if (i < progressLesson) {
          node.status = LevelStatus.COMPLETED;
          node.stars = 3;
        } else if (i === progressLesson) {
          node.status = LevelStatus.CURRENT;
          node.stars = 2;
        }
        // i > progressLesson 保持 LOCKED
      }
      // 非当前进度的 Tab，全部保持 LOCKED

      newLevels.push(node);
    }
    this.levels = newLevels;
  }

  build() {
    Column() {
      if (!this.authChecked) {
        Column() {
          LoadingProgress()
            .width(42)
            .height(42)
            .color(COLORS.PRIMARY)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.requiresLogin) {
        AuthRequiredState({
          title: '注册后开始学习',
          description: '试运行阶段需要先登录 / 注册，才能解锁学习路径与关卡内容。',
          source: 'study_tab_gate',
        })
      } else {
        this.StudyHeader()
        // 分段选择器
        Column() {
          this.TabSelector()
          this.MemberQuotaBanner()
        }
        .width('100%')
        .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET })

        // 关卡地图
        this.LevelMap()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BACKGROUND)
    .onAppear(() => {
      const context = getContext(this);
      void this.refreshAccessState(context);
      void this.loadUserInfo(context);
    })
  }

  @Builder
  StudyHeader() {
    Row({ space: 12 }) {
      Column({ space: 6 }) {
        Text('学习地图')
          .fontSize(UI.TITLE_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
        Text('把韩语学习，变成每天的小进步')
          .fontSize(UI.CAPTION_SIZE)
          .fontColor(COLORS.TEXT_SECONDARY)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Image($r('app.media.lingai_robot'))
        .width(56)
        .height(56)
        .objectFit(ImageFit.Contain)
    }
    .width('100%')
    .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: UI.CONTENT_TOP, bottom: 16 })
  }

  @Builder
  TabSelector() {
    Stack() {
      // 滑块指示器（底层）
      Row()
        .width('33%')
        .height('100%')
        .backgroundColor(COLORS.PRIMARY)
        .borderRadius(16)
        .shadow({ radius: 6, color: UI.SHADOW, offsetY: 2 })
        .margin({ left: this.getSliderMargin() })
        .animation({ duration: 300, curve: Curve.EaseOut })

      // Tab文字（上层）
      Row() {
        ForEach(['TOPIK I', 'TOPIK II', '必备单词'], (tab: string, index: number) => {
          Text(tab)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.selectedTabIndex === index ? UI.ON_PRIMARY : COLORS.TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height('100%')
            .onClick(() => {
              this.selectedTabIndex = index;
              this.loadLevels();
            })
        })
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height(52)
    .padding(4)
    .margin({ bottom: 16 })
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(20)
    .border({ width: 1, color: COLORS.BORDER })
    .shadow({ radius: 8, color: UI.SHADOW, offsetY: 2 })
    .alignContent(Alignment.Start)
  }

  // 计算滑块左边距
  getSliderMargin(): Length {
    // 每个Tab占33%，根据选中的index计算margin
    const margins: Length[] = [0, '33%', '66%'];
    return margins[this.selectedTabIndex];
  }

  // 预定义的蜿蜒X位置百分比（增大差异以增加蜿蜒弧度）
  private readonly NODE_POSITIONS: number[] = [0.12, 0.85, 0.3, 0.7, 0.15, 0.8, 0.25, 0.75, 0.2, 0.85];

  getNodeXPosition(index: number): number {
    return this.NODE_POSITIONS[index % this.NODE_POSITIONS.length];
  }

  @Builder
  MemberQuotaBanner() {
    Row() {
      Column() {
        Text('今日学习额度')
          .fontSize(12)
          .fontColor(COLORS.TEXT_SECONDARY)

        Text(this.lessonQuotaSummary())
          .fontSize(UI.BODY_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLORS.TEXT_PRIMARY)
          .margin({ top: 4 })

        Text(this.lessonQuotaCaption())
          .fontSize(UI.CAPTION_SIZE)
          .lineHeight(19)
          .fontColor(COLORS.TEXT_HINT)
          .margin({ top: 6 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Text(this.lessonQuotaBadge())
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.lessonQuotaBadgeTextColor())
        .padding({ left: 10, right: 10, top: 6, bottom: 6 })
        .backgroundColor(this.lessonQuotaBadgeBackground())
        .borderRadius(999)
    }
    .width('100%')
    .padding(18)
    .margin({ bottom: 12 })
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(20)
    .border({ width: 1, color: COLORS.BORDER })
  }

  @Builder
  LevelMap() {
    Scroll() {
      Column({ space: 0 }) {
        // 反转顺序：从上往下显示锁定→当前→完成
        // 使用索引直接计算而不是const
        ForEach(this.levels.slice().reverse(), (level: LevelNodeData, reverseIndex: number) => {
          Column() {
            // 连接线（第一个节点上方不需要）
            if (reverseIndex > 0) {
              this.ConnectionLine(this.levels.length - 1 - reverseIndex)
            }

            // 节点 - 使用计算的原始索引
            Row() {
              Blank().layoutWeight(this.getNodeXPosition(this.levels.length - 1 - reverseIndex))
              this.LevelNode(level)
              Blank().layoutWeight(1 - this.getNodeXPosition(this.levels.length - 1 - reverseIndex))
            }
            .width('100%')
          }
        })
      }
      .width('100%')
      .padding({ left: 30, right: 30, top: 30, bottom: 192 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  // 辅助方法：计算插值位置（让路径端点恰好接触节点边缘，不进入内部）
  getInterpolatedX(index: number, step: number): number {
    const currentX = this.getNodeXPosition(index);
    const prevX = this.getNodeXPosition(index + 1);
    // 路径从15%到85%之间插值，让端点恰好接触节点边缘
    const tMin = 0.12;   // 起始偏移
    const tMax = 0.88;   // 结束偏移
    const t = tMin + (tMax - tMin) * (step / 6);
    return prevX + (currentX - prevX) * t;
  }

  @Builder
  ConnectionLine(index: number) {
    // 曲线虚线连接节点，使用椭圆形脚印（7个点延伸到节点中心）
    Column({ space: 5 }) {
      Row() {
        Blank().layoutWeight(this.getInterpolatedX(index, 0))
        Ellipse().width(12).height(7).fill(COLORS.BORDER)
        Blank().layoutWeight(1 - this.getInterpolatedX(index, 0))
      }.width('100%')

      Row() {
        Blank().layoutWeight(this.getInterpolatedX(index, 1))
        Ellipse().width(12).height(7).fill(COLORS.BORDER)
        Blank().layoutWeight(1 - this.getInterpolatedX(index, 1))
      }.width('100%')

      Row() {
        Blank().layoutWeight(this.getInterpolatedX(index, 2))
        Ellipse().width(11).height(6).fill(COLORS.BORDER)
        Blank().layoutWeight(1 - this.getInterpolatedX(index, 2))
      }.width('100%')

      Row() {
        Blank().layoutWeight(this.getInterpolatedX(index, 3))
        Ellipse().width(11).height(6).fill(COLORS.BORDER)
        Blank().layoutWeight(1 - this.getInterpolatedX(index, 3))
      }.width('100%')

      Row() {
        Blank().layoutWeight(this.getInterpolatedX(index, 4))
        Ellipse().width(10).height(6).fill(COLORS.BORDER)
        Blank().layoutWeight(1 - this.getInterpolatedX(index, 4))
      }.width('100%')

      Row() {
        Blank().layoutWeight(this.getInterpolatedX(index, 5))
        Ellipse().width(10).height(5).fill(COLORS.BORDER)
        Blank().layoutWeight(1 - this.getInterpolatedX(index, 5))
      }.width('100%')

      Row() {
        Blank().layoutWeight(this.getInterpolatedX(index, 6))
        Ellipse().width(10).height(5).fill(COLORS.BORDER)
        Blank().layoutWeight(1 - this.getInterpolatedX(index, 6))
      }.width('100%')
    }
    .width('100%')
    .height(50)
  }

  @Builder
  LevelNode(level: LevelNodeData) {
    Stack() {
      // 水波纹扩散动画（仅当前关卡）
      if (level.status === LevelStatus.CURRENT) {
        // 第3层波纹 - 最外层
        Circle()
          .width(84)
          .height(84)
          .fill(Color.Transparent)
          .stroke(UI.BLUE)
          .opacity(this.ripple3Opacity)
          .strokeWidth(2)
          .scale({ x: this.ripple3Scale, y: this.ripple3Scale })

        // 第2层波纹 - 中层
        Circle()
          .width(84)
          .height(84)
          .fill(Color.Transparent)
          .stroke(UI.BLUE)
          .opacity(this.ripple2Opacity)
          .strokeWidth(2)
          .scale({ x: this.ripple2Scale, y: this.ripple2Scale })

        // 第1层波纹 - 内层
        Circle()
          .width(84)
          .height(84)
          .fill(Color.Transparent)
          .stroke(UI.BLUE)
          .opacity(this.breathOpacity)
          .strokeWidth(2)
          .scale({ x: this.breathScale, y: this.breathScale })

        // 固定内层光环
        Circle()
          .width(88)
          .height(88)
          .fill(Color.Transparent)
          .stroke(COLORS.SURFACE)
          .strokeWidth(3)
      }

      // 主圆形节点
      Circle()
        .width(80)
        .height(80)
        .fill(this.getNodeColor(level.status))

      // 节点内容
      if (level.status === LevelStatus.LOCKED) {
        // 锁定：显示锁图标
        Image($r('app.media.ic_lock'))
          .width(32)
          .height(32)
          .fillColor(COLORS.TEXT_HINT)
      } else if (level.status === LevelStatus.COMPLETED) {
        // 已完成：显示白色对勾
        Image($r('app.media.ic_check'))
          .width(36)
          .height(36)
          .fillColor(UI.ON_PRIMARY)
      } else {
        // 当前关卡：显示关卡号和星星
        Column() {
          Row({ space: 4 }) {
            Image($r('app.media.lingai_robot'))
              .width(26)
              .height(26)
            Text(level.id.toString())
              .fontSize(26)
              .fontWeight(FontWeight.Bold)
              .fontColor(UI.ON_BLUE)
          }

          Row({ space: 3 }) {
            Text('⭐')
              .fontSize(12)
            Text('⭐')
              .fontSize(12)
          }
          .margin({ top: 4 })
        }
      }
    }
    .width(100)
    .height(100)
    .onClick(() => {
      if (level.status !== LevelStatus.LOCKED) {
        this.goToLesson(level.id);
      }
    })
  }

  getNodeColor(status: LevelStatus): ResourceColor {
    switch (status) {
      case LevelStatus.COMPLETED:
        return COLORS.SUCCESS;  // 绿色
      case LevelStatus.CURRENT:
        return UI.BLUE;  // 当前关卡
      default:
        return UI.SURFACE_MUTED;  // 锁定
    }
  }

  private lessonQuotaSummary(): string {
    if (this.userInfo.dailyLessonLimit <= 0) {
      return '当前会员今日学习不限量';
    }
    if (this.userInfo.dailyLessonRemaining <= 0) {
      return `今天的 ${this.userInfo.dailyLessonLimit} 关额度已用完`;
    }
    return `今天还可学习 ${this.userInfo.dailyLessonRemaining}/${this.userInfo.dailyLessonLimit} 关`;
  }

  private lessonQuotaCaption(): string {
    if (this.userInfo.dailyLessonLimit <= 0) {
      return '升级权益开放后，这里会同步展示最新会员规则。';
    }
    if (this.userInfo.dailyLessonRemaining <= 0) {
      return '明天会自动恢复额度，当前关卡重复进入不会额外扣减。';
    }
    return '同一关当天重复进入不重复扣减，适合放心回看。';
  }

  private lessonQuotaBadge(): string {
    if (this.userInfo.dailyLessonLimit <= 0) {
      return '不限量';
    }
    if (this.userInfo.dailyLessonRemaining <= 0) {
      return '已用完';
    }
    return `剩 ${this.userInfo.dailyLessonRemaining} 关`;
  }

  private lessonQuotaBadgeTextColor(): string {
    if (this.userInfo.dailyLessonLimit > 0 && this.userInfo.dailyLessonRemaining <= 0) {
      return UI.DANGER_TEXT;
    }
    return COLORS.PRIMARY;
  }

  private lessonQuotaBadgeBackground(): string {
    if (this.userInfo.dailyLessonLimit > 0 && this.userInfo.dailyLessonRemaining <= 0) {
      return UI.DANGER_SOFT;
    }
    return UI.GREEN_SOFT;
  }

  async goToLesson(lessonId: number) {
    if (this.requiresLogin) {
      await this.goLoginTab();
      return;
    }
    if (this.isNavigating) return;
    this.isNavigating = true;
    try {
      await router.pushUrl({
        url: 'pages/LessonPage',
        params: {
          lessonId: lessonId,
          level: this.currentLevel,
          title: '关卡 ' + lessonId.toString()
        }
      });
    } catch (e) {
      console.error('[StudyContent] navigation failed:', e);
    } finally {
      this.isNavigating = false;
    }
  }

  private async goLoginTab(): Promise<void> {
    if (this.navigatingToLogin) {
      return;
    }
    this.navigatingToLogin = true;

    const params = new IndexRouteParams();
    params.tabIndex = 3;
    params.navFrom = 'study_tab_gate';
    params.navAt = Date.now();
    params.openSheetMode = 'login';

    try {
      await router.replaceUrl({
        url: 'pages/Index',
        params,
      });
    } catch (replaceErr) {
      console.warn('[StudyContent] replaceUrl failed:', JSON.stringify(replaceErr));
      try {
        await router.pushUrl({
          url: 'pages/Index',
          params,
        });
      } catch (pushErr) {
        console.error('[StudyContent] pushUrl failed:', JSON.stringify(pushErr));
      }
    } finally {
      this.navigatingToLogin = false;
    }
  }
}
