/**
 * LingAI 首页 - Tab 容器
 * 包含: 首页、学习、词典、我的 四个Tab
 * 适配 ArkTS 严格模式
 * 遵循原型图设计规范
 */
import router from '@ohos.router';
import { COLORS, TOPIK_LEVELS, TopikLevelConfig, WORDS_PER_LESSON } from '../utils/Constants';
import { LessonInfo, LessonStatus, DailyTask } from '../models/DataModels';
import { HomeContent } from '../components/HomeContent';
import { StudyContent } from '../components/StudyContent';
import { DictContent } from '../components/DictContent';
import { ProfileContent } from '../components/ProfileContent';
import { VocabularyContent } from '../components/VocabularyContent';
import { FloatingSpirit } from '../components/FloatingSpirit';
import { SpiritChatPanel } from '../components/SpiritChatPanel';
import promptAction from '@ohos.promptAction';
import TaskTrackingService from '../services/TaskTrackingService';
import preferences from '@ohos.data.preferences';
import { themeManager } from '../utils/ThemeManager';
import ApiService from '../services/ApiService';
import { UI } from '../utils/UiTokens';

@Entry
@Component
struct Index {
  @State learningRefreshVersion: number = 0;
  @State currentTabIndex: number = 0;  // 默认首页
  @State dictSearchWord: string = '';
  @State showSpiritPanel: boolean = false;
  @State showVocabulary: boolean = false;
  @State isDarkMode: boolean = false;
  @State profileSheetMode: string = '';
  @State profileSheetRequestAt: number = 0;

  private tabController: TabsController = new TabsController();
  private taskService: TaskTrackingService = TaskTrackingService.getInstance();
  private unsubscribeTheme: (() => void) | null = null;

  async aboutToAppear() {
    this.isDarkMode = themeManager.isDark();

    if (this.unsubscribeTheme === null) {
      this.unsubscribeTheme = themeManager.subscribe((isDark: boolean) => {
        this.isDarkMode = isDark;
      });
    }

    // 初始化主题管理器
    const context = getContext(this);
    await themeManager.init(context);
    this.isDarkMode = themeManager.isDark();

    // 初始化 API 服务（加载本地 token/设备信息）
    await ApiService.getInstance().init(context);

    // 初始化任务服务
    await this.taskService.init(context);

    this.applyRouteTabIndex();
  }

  onPageShow() {
    this.learningRefreshVersion += 1;
    const context = getContext(this);
    this.isDarkMode = themeManager.isDark();
    themeManager.init(context).then(() => {
      this.isDarkMode = themeManager.isDark();
    });
    this.applyRouteTabIndex();
  }

  private applyRouteTabIndex() {
    try {
      const params = router.getParams() as Record<string, Object>;
      if (!params) {
        return;
      }

      const tabObj = params['tabIndex'];
      if (tabObj === undefined || tabObj === null) {
        return;
      }

      const targetIndex = Number(tabObj);
      if (Number.isNaN(targetIndex) || targetIndex < 0 || targetIndex > 3) {
        return;
      }

      this.switchToTab(targetIndex);

      const openSheetMode = this.readRouteString(params['openSheetMode']);
      const navAt = this.readRouteNumber(params['navAt']);
      if (targetIndex === 3 && openSheetMode === 'login' && navAt > 0 && this.profileSheetRequestAt !== navAt) {
        this.profileSheetMode = 'login';
        this.profileSheetRequestAt = navAt;
      }
    } catch (e) {
      // Ignore invalid route params.
    }
  }

  private switchToTab(targetIndex: number): void {
    this.currentTabIndex = targetIndex;

    try {
      this.tabController.changeIndex(targetIndex);
    } catch (e) {
      console.warn('[Index] changeIndex immediate failed:', JSON.stringify(e));
    }

    setTimeout(() => {
      try {
        this.tabController.changeIndex(targetIndex);
      } catch (e) {
        console.warn('[Index] changeIndex deferred failed:', JSON.stringify(e));
      }
    }, 30);
  }

  private readRouteNumber(value: Object | null | undefined): number {
    if (value === undefined || value === null) {
      return Number.NaN;
    }
    return Number(value);
  }

  private readRouteString(value: Object | null | undefined): string {
    if (value === undefined || value === null) {
      return '';
    }
    return String(value);
  }

  onBackPress(): boolean {
    if (this.showVocabulary) {
      this.showVocabulary = false;
      this.learningRefreshVersion += 1;
      return true;
    }
    return false;
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      // Tab内容区
      Tabs({ barPosition: BarPosition.End, controller: this.tabController }) {
        // 首页 Tab
        TabContent() {
          HomeContent({
            refreshVersion: this.learningRefreshVersion,
            activeTabIndex: this.currentTabIndex,
            onOpenVocabulary: () => { this.showVocabulary = true; }
          })
        }
        .tabBar(this.TabBarItem('首页', $r('app.media.lg145_nav_home'), 0))

        // 学习 Tab
        TabContent() {
          StudyContent({
            refreshVersion: this.learningRefreshVersion,
            activeTabIndex: this.currentTabIndex,
            onOpenVocabulary: () => { this.showVocabulary = true; }
          })
        }
        .tabBar(this.TabBarItem('学习', $r('app.media.lg145_nav_study'), 1))

        // 词典 Tab
        TabContent() {
          this.DictTabContent()
        }
        .tabBar(this.TabBarItem('词典', $r('app.media.lg145_nav_dict'), 2))

        // 我的 Tab
        TabContent() {
          ProfileContent({
            refreshVersion: this.learningRefreshVersion,
            externalSheetMode: this.profileSheetMode,
            externalSheetRequestAt: this.profileSheetRequestAt,
            activeTabIndex: this.currentTabIndex,
            onOpenVocabulary: () => { this.showVocabulary = true; },
            onOpenStudy: () => { this.switchToTab(1); }
          })
        }
        .tabBar(this.TabBarItem('我的', $r('app.media.lg145_nav_mine'), 3))
      }
      .barMode(BarMode.Fixed)
      .barWidth('100%')
      .barHeight(0)
      .barBackgroundColor(themeManager.navBg)
      .onChange((index: number) => {
        this.currentTabIndex = index;
      })

      this.BottomTabBar()

      // 悬浮精灵按钮
      FloatingSpirit({
        onPress: () => {
          this.showSpiritPanel = true;
        }
      })
      .margin({
        right: 12,
        bottom: 89
      })

      if (this.showVocabulary) {
        this.VocabularyPage()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(themeManager.bgBody)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .bindSheet($$this.showSpiritPanel, this.SpiritPanelBuilder(), {
      height: '85%',
      dragBar: false,
      showClose: false,
      keyboardAvoidMode: SheetKeyboardAvoidMode.RESIZE_ONLY,
      backgroundColor: Color.Transparent
    })
  }

  @Builder
  SpiritPanelBuilder() {
    SpiritChatPanel({
      panelHeight: '100%',
      onClose: () => {
        this.showSpiritPanel = false;
      }
    })
  }

  @Builder
  TabBarItem(title: string, icon: Resource, index: number) {
    Column() {
      Image(icon)
        .width(24)
        .height(24)

      Text(title)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.currentTabIndex === index
          ? COLORS.PRIMARY
          : themeManager.textDim)
        .margin({ top: 6 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ bottom: 20 })  // 适配安全区
  }

  @Builder
  DictTabContent() {
    Column() {
      DictContent({
        searchWordFromExternal: this.dictSearchWord,
        activeTabIndex: this.currentTabIndex
      })
      .layoutWeight(1)

      // 保留固定助手空间，长词条滚动到中段也不会位于悬浮按钮后。
      Blank().height(UI.NAV_HEIGHT + 76)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  VocabularyPage() {
    Column() {
      Row({ space: 8 }) {
        Button() {
          Image($r('app.media.ic_back')).width(20).height(20).fillColor(COLORS.TEXT_PRIMARY)
        }
        .width(UI.TOUCH_MIN).height(UI.TOUCH_MIN)
        .backgroundColor(Color.Transparent)
        .accessibilityText('返回')
        .onClick(() => { this.showVocabulary = false;
      this.learningRefreshVersion += 1; })
        Text('我的生词本').fontSize(18).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
        Blank()
      }
      .width('100%')
      .padding({ left: 12, right: UI.PAGE_INSET, top: UI.CONTENT_TOP, bottom: 15 })
      .backgroundColor(UI.HEADER_BG)
      .border({ width: { bottom: 1 }, color: COLORS.BORDER })
      VocabularyContent({
        isActive: this.showVocabulary,
        onSearchWord: (word: string) => {
          this.dictSearchWord = word;
          this.showVocabulary = false;
      this.learningRefreshVersion += 1;
          this.switchToTab(2);
        }
      })
      .layoutWeight(1)
      Blank().height(24)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BACKGROUND)
    .zIndex(10)
  }

  @Builder
  BottomTabBar() {
    Row() {
      this.BottomTabItem('首页', $r('app.media.lg145_nav_home'), 0)
      this.BottomTabItem('学习', $r('app.media.lg145_nav_study'), 1)
      this.BottomTabItem('词典', $r('app.media.lg145_nav_dict'), 2)
      this.BottomTabItem('我的', $r('app.media.lg145_nav_mine'), 3)
    }
    .width('100%')
    .height(UI.NAV_HEIGHT)
    .padding({ left: 13, right: 13, top: 8, bottom: 13 })
    .backgroundColor(themeManager.navBg)
    .border({ width: { top: 1 }, color: themeManager.glassBorder })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }

  @Builder
  BottomTabItem(title: string, icon: Resource, index: number) {
    Column() {
      Row() {
        Image(icon)
          .width(20)
          .height(20)
      }
      .width(54)
      .height(32)
      .justifyContent(FlexAlign.Center)
      .borderRadius(12)

      Text(title)
        .fontSize(12)
        .fontWeight(this.currentTabIndex === index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.currentTabIndex === index
          ? COLORS.PRIMARY
          : themeManager.textDim)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .height('100%')
    .borderRadius(11)
    .backgroundColor(this.currentTabIndex === index ? UI.GREEN_SOFT : Color.Transparent)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentTabIndex = index;
      this.tabController.changeIndex(index);
    })
  }
}
