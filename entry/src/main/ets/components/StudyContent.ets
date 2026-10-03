/**
 * 学习地图内容组件
 * 包含: 分段选择器(TOPIK I/II/必备单词), 关卡地图路径
 * 适配 ArkTS 严格模式
 */
import router from '@ohos.router';
import { COLORS, WORDS_PER_LESSON } from '../utils/Constants';
import preferences from '@ohos.data.preferences';
import { themeManager } from '../utils/ThemeManager';
import { UI } from '../utils/UiTokens';
import ApiService from '../services/ApiService';
import PreferencesService, { CourseLearningState, courseLesson } from '../services/PreferencesService';
import { AuthRequiredState } from './AuthRequiredState';
import { UserInfo } from '../models/DataModels';

class IndexRouteParams {
  tabIndex: number = 3;
  navFrom: string = 'study_gate';
  navAt: number = Date.now();
  openSheetMode: string = 'login';
}

class CourseInfo {
  level: number = 1;
  name: string = '';
  words: number = 0;
  lessons: number = 0;
  constructor(level: number, name: string, words: number, lessons: number) {
    this.level = level;
    this.name = level === 0 ? '必备单词' : name;
    this.words = words;
    this.lessons = lessons;
  }
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

class LessonDataSource implements IDataSource {
  private items: LevelNodeData[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.items.length; }
  getData(index: number): LevelNodeData { return this.items[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { this.listeners.push(listener); }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) { this.listeners.splice(index, 1); }
  }
  replace(items: LevelNodeData[]): void {
    this.items = items;
    this.listeners.forEach((listener: DataChangeListener) => listener.onDataReloaded());
  }
}

@Component
export struct StudyContent {
  @Prop @Watch('onRefreshVersion') refreshVersion: number = 0;
  @Prop @Watch('onActiveTabIndexChange') activeTabIndex: number = -1;
  @State selectedTabIndex: number = 0;  // 0: TOPIK I, 1: TOPIK II, 2: 必备单词
  @State currentLevel: number = 1;
  @State levels: LevelNodeData[] = [];
  @State wordsPerLesson: number = WORDS_PER_LESSON;
  @State themeVersion: number = 0;
  @State authChecked: boolean = false;
  @State requiresLogin: boolean = false;
  @State userInfo: UserInfo = new UserInfo();

  private isNavigating: boolean = false;
  private navigatingToLogin: boolean = false;
  onOpenVocabulary?: () => void;
  @State courses: CourseInfo[] = [];
  @State courseState: CourseLearningState = new CourseLearningState();
  @State showCourseSheet: boolean = false;
  @State courseHeaderContentWidth: number = 280;
  @State contentError: string = '';
  private refreshing: boolean = false;
  @State loadingCourses: boolean = false;
  private lessonData: LessonDataSource = new LessonDataSource();
  private mapScroller: Scroller = new Scroller();
  private unsubscribeTheme: (() => void) | null = null;

  onRefreshVersion(): void {
    void this.refreshForVisibleTab();
  }

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

    await this.refreshForVisibleTab();
  }

  private async refreshForVisibleTab(): Promise<void> {
    if (this.refreshing) { return; }
    this.refreshing = true;
    this.loadingCourses = this.courses.length === 0;
    try {
      const context = getContext(this);
      await this.refreshAccessState(context);
      if (!this.requiresLogin) { await this.prepareAuthorizedContent(context); }
    } finally {
      this.refreshing = false;
      this.loadingCourses = false;
    }
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

    // 先完成远端读取，再读取当前选择，避免旧快照覆盖用户刚切换的课程。
    await this.loadLevelInfoFromApi(context);

    // 读取本地学习进度
    try {
      const prefService = PreferencesService.getInstance();
      await prefService.init(context);
      const state = await prefService.getLearningState();
      this.courseState = state;
      this.currentLevel = state.currentLevel;
    } catch (e) {
      console.warn('[StudyContent] getLearningState failed, using defaults');
    }

    this.loadLevels();

  }

  /**
   * 从后端加载关卡总配置，填充 levelWordCounts
   */
  private async loadLevelInfoFromApi(context: Context) {
    this.contentError = '';
    try {
      const api = ApiService.getInstance();
      await api.init(context);
      const info = await api.getLevelInfo();
      const courses: CourseInfo[] = [];
      for (const raw of info.levels) {
        const item = raw as Record<string, Object>;
        const level = item['level'] as number;
        const words = (item['word_count'] as number) || 0;
        const lessons = words > 0 ? Math.ceil(words / this.wordsPerLesson) : (item['lesson_count'] as number) || 0;
        if (Number.isInteger(level) && level >= 0 && lessons > 0) {
          courses.push(new CourseInfo(level, item['name'] as string, words, lessons));
        }
      }
      this.courses = courses;
      if (courses.length === 0) {
        this.contentError = '课程内容暂时不可用，请稍后重新加载。';

      }
    } catch (error) {
      this.contentError = '课程没有加载出来，请检查连接后重试。';
    }
  }

  aboutToDisappear() {
    if (this.unsubscribeTheme !== null) {
      this.unsubscribeTheme();
      this.unsubscribeTheme = null;
    }
  }

  loadLevels() {
    const course = this.courses.find((item: CourseInfo) => item.level === this.currentLevel);
    const cursor = courseLesson(this.courseState, this.currentLevel);
    const nodes: LevelNodeData[] = [];
    if (course) {
      for (let id = 1; id <= course.lessons; id++) {
        nodes.push(new LevelNodeData(id, id < cursor ? LevelStatus.COMPLETED : (id === cursor ? LevelStatus.CURRENT : LevelStatus.LOCKED)));
      }
    }
    this.levels = nodes;
    this.lessonData.replace(nodes);
  }

  private selectedCourse(): CourseInfo {
    return this.courses.find((item: CourseInfo) => item.level === this.currentLevel) || new CourseInfo(1, '选择课程', 0, 0);
  }

  private completedCount(course: CourseInfo): number {
    return Math.min(course.lessons, Math.max(0, courseLesson(this.courseState, course.level) - 1));
  }

  private courseDescription(level: number): string {
    return level === 1 ? '初级 · 日常表达与基础词汇' : (level === 2 ? '中高级 · 丰富表达与观点词汇' : '专项词汇 · 生活常用表达');
  }

  private wordsInLesson(id: number): number {
    const course = this.selectedCourse();
    return course.words > 0 ? Math.max(0, Math.min(this.wordsPerLesson, course.words - (id - 1) * this.wordsPerLesson)) : this.wordsPerLesson;
  }

  private courseHeading(level: number): string {
    return level === 1 ? '从日常表达，慢慢开始' : (level === 2 ? '让表达，变得更丰富' : '把常用词，带进生活');
  }

  private async selectCourse(course: CourseInfo): Promise<void> {
    try {
      if (course.level !== this.currentLevel) {
        await PreferencesService.getInstance().selectCourse(course.level);
        this.courseState = await PreferencesService.getInstance().getLearningState();
        this.currentLevel = course.level;
        this.loadLevels();
        this.mapScroller.scrollTo({ xOffset: 0, yOffset: 0 });
      }
      this.showCourseSheet = false;
    } catch (error) {
      try {
        this.getUIContext().getPromptAction().showToast({ message: '课程选择没有保存，请重试。' });
      } catch (toastError) {
        console.warn('[StudyContent] course selection notification unavailable');
      }
    }
  }

  build() {
    Column() {
      if (!this.authChecked) {
        LoadingProgress().width(42).height(42).color(COLORS.PRIMARY)
      } else if (this.requiresLogin) {
        AuthRequiredState({ title: '注册后开始学习', description: '登录后，选择课程开始学习。', source: 'study_tab_gate' })
      } else {
        this.StudyHeader()
        this.LevelMap()
      }
    }
    .width('100%').height('100%').backgroundColor(COLORS.BACKGROUND)
    .bindSheet($$this.showCourseSheet, this.CourseSheet(), {
      height: '76%', showClose: true, dragBar: false, backgroundColor: COLORS.SURFACE,
      title: { title: '选择课程' }, onDisappear: () => { this.showCourseSheet = false; }
    })
  }

  @Builder
  StudyHeader() {
    Row({ space: 12 }) {
      Button() {
        Row({ space: 8 }) {
          Text(this.selectedCourse().name).fontSize(18).fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
            .constraintSize({ maxWidth: Math.max(44, this.courseHeaderContentWidth - 135) })
          Image($r('app.media.lg145_chevron_down'))
            .width(18).height(18).objectFit(ImageFit.Contain)
            .rotate({ angle: this.showCourseSheet ? 180 : 0 })
        }.justifyContent(FlexAlign.Start).alignItems(VerticalAlign.Center)
      }
      .type(ButtonType.Normal).backgroundColor(UI.GREEN_SOFT)
      .padding({ left: 12, right: 12 }).height(44).borderRadius(12)
      .constraintSize({ maxWidth: Math.max(94, this.courseHeaderContentWidth - 85) })
      .accessibilityText(`当前课程 ${this.selectedCourse().name}，选择课程`)
      .onClick(() => { this.showCourseSheet = true; })
      Blank().layoutWeight(1)
      Button('生词本').type(ButtonType.Normal).height(44).padding({ left: 10, right: 0 })
        .backgroundColor(Color.Transparent).fontColor(COLORS.PRIMARY).fontSize(13)
        .onClick(() => { if (this.onOpenVocabulary) { this.onOpenVocabulary(); } })
    }
    .width('100%').padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: UI.CONTENT_TOP, bottom: 12 })
    .backgroundColor(COLORS.SURFACE)
    .onAreaChange((_oldArea, newArea) => {
      const width = Number(newArea.width) - UI.PAGE_INSET * 2;
      if (Number.isFinite(width) && width > 0 && width !== this.courseHeaderContentWidth) {
        this.courseHeaderContentWidth = width;
      }
    })
  }

  @Builder
  CourseSheet() {
    Scroll() {
      Column({ space: 12 }) {
        ForEach(['等级课程', '专项词汇'], (group: string, groupIndex: number) => {
          Text(group).fontSize(12).fontColor(COLORS.TEXT_SECONDARY).width('100%').margin({ top: 12 })
          ForEach(this.courses.filter((course: CourseInfo) => groupIndex === 0 ? course.level !== 0 : course.level === 0), (course: CourseInfo) => {
            Button() {
              Row({ space: 10 }) {
                Column({ space: 6 }) {
                  Text(course.name).fontSize(16).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
                  Text(this.courseDescription(course.level)).fontSize(11).fontColor(COLORS.TEXT_SECONDARY)
                  Text(`已完成 ${this.completedCount(course)} / ${course.lessons} 关`).fontSize(11).fontColor(COLORS.PRIMARY)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Text(course.level === this.currentLevel ? '✓ 当前' : '›').fontSize(12).fontColor(COLORS.PRIMARY)
              }.width('100%').padding(15)
            }
            .type(ButtonType.Normal).width('100%').padding(0)
            .backgroundColor(course.level === this.currentLevel ? UI.GREEN_SOFT : COLORS.SURFACE)
            .border({ width: 1, color: course.level === this.currentLevel ? COLORS.PRIMARY : COLORS.BORDER })
            .borderRadius(15).clip(true)
            .onClick(() => { void this.selectCourse(course); })
          }, (course: CourseInfo) => course.level.toString())
        })
      }.width('100%').justifyContent(FlexAlign.Start)
      .padding({ left: 22, right: 22, bottom: 32 })
    }.width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.Off)
  }

  @Builder
  LevelMap() {
    List({ space: 12, scroller: this.mapScroller }) {
      ListItem() {
        Column({ space: 12 }) {
        if (this.loadingCourses) {
          LoadingProgress().width(40).height(40).color(COLORS.PRIMARY)
          Text('正在加载课程').fontSize(13).fontColor(COLORS.TEXT_SECONDARY)
        } else if (this.contentError !== '') {
          Text(this.contentError).fontSize(14).fontColor(COLORS.TEXT_SECONDARY).lineHeight(22)
          Button('重新加载').onClick(() => { void this.refreshForVisibleTab(); })
        } else {
          Column({ space: 12 }) {
            Text(this.courseDescription(this.currentLevel)).fontSize(11).fontColor(COLORS.PRIMARY).width('100%')
            Text(this.courseHeading(this.currentLevel)).fontSize(22).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY).width('100%')
            Row({ space: 13 }) {
              Progress({ value: this.completedCount(this.selectedCourse()), total: Math.max(1, this.selectedCourse().lessons), type: ProgressType.Linear })
                .layoutWeight(1).height(5).color(COLORS.PRIMARY).backgroundColor(COLORS.BORDER)
              Text(`已完成 ${this.completedCount(this.selectedCourse())} / ${this.selectedCourse().lessons} 关`)
                .fontSize(11).fontColor(COLORS.PRIMARY)
            }.width('100%')
          }.width('100%').padding(18).backgroundColor(UI.GREEN_SOFT).borderRadius(20)
          Text(this.lessonQuotaSummary()).fontSize(11).fontColor(COLORS.TEXT_SECONDARY).width('100%')
          Row() {
            Text('学习路线').fontSize(16).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
            Blank()
            Text(`${this.levels.length} 个关卡`).fontSize(12).fontColor(COLORS.TEXT_SECONDARY)
          }.width('100%').margin({ top: 7, bottom: 2 })
        }
        }.width('100%')
      }
      if (!this.loadingCourses && this.contentError === '') {
        LazyForEach(this.lessonData, (level: LevelNodeData) => {
          ListItem() { this.LevelNode(level) }
        }, (level: LevelNodeData) => `${this.currentLevel}-${level.id}-${level.status}`)
        ListItem() {
          Text('每个课程，按自己的节奏学。\n学习进度分别保存，今日额度共同使用。')
            .fontSize(12).lineHeight(20).fontColor(COLORS.TEXT_SECONDARY).width('100%')
            .padding({ top: 8, bottom: 170 })
        }
      }
    }
    .width('100%').layoutWeight(1).scrollBar(BarState.Off).cachedCount(5)
    .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 18 })
    .clipContent(ContentClipMode.CONTENT_ONLY)
  }

  @Builder
  LevelNode(level: LevelNodeData) {
    Button() {
      Row({ space: 12 }) {
        Stack() {
          if (level.status === LevelStatus.LOCKED) {
            Image($r('app.media.ic_lock')).width(18).height(18).fillColor(COLORS.TEXT_HINT)
          } else if (level.status === LevelStatus.COMPLETED) {
            Image($r('app.media.ic_check')).width(20).height(20).fillColor(COLORS.PRIMARY)
          } else {
            Text(level.id.toString()).fontSize(17).fontWeight(FontWeight.Bold).fontColor(UI.BLUE)
          }
        }.width(40).height(44).borderRadius(12)
        .backgroundColor(level.status === LevelStatus.CURRENT ? UI.BLUE_SOFT : UI.GREEN_SOFT)
        Column({ space: 5 }) {
          Text('关卡 ' + level.id).fontSize(14).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
          Text(`${this.wordsInLesson(level.id)} 个词 · ${level.status === LevelStatus.COMPLETED ? '已完成，可再练习' : (level.status === LevelStatus.CURRENT ? '可以开始' : '完成前一关后继续')}`)
            .fontSize(11).lineHeight(18).fontColor(COLORS.TEXT_SECONDARY)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text('›').fontSize(20).fontColor(COLORS.TEXT_SECONDARY)
      }.width('100%').padding(14)
    }
    .type(ButtonType.Normal).width('100%').padding(0).constraintSize({ minHeight: 83 })
    .backgroundColor(level.status === LevelStatus.CURRENT ? UI.BLUE_SOFT : COLORS.SURFACE)
    .border({ width: 1, color: level.status === LevelStatus.CURRENT ? UI.BLUE : COLORS.BORDER })
    .borderRadius(16).clip(true)
    .onClick(() => { if (level.status !== LevelStatus.LOCKED) { this.goToLesson(level.id); } })
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
