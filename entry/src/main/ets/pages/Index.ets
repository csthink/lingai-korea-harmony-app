/**
 * LingAI 首页 - Tab 容器
 * 包含: 首页、学习、词典、我的 四个Tab
 * 适配 ArkTS 严格模式
 * 遵循原型图设计规范
 */
import router from '@ohos.router';
import { COLORS, TOPIK_LEVELS, TopikLevelConfig, WORDS_PER_LESSON, LightTheme, DarkTheme } from '../utils/Constants';
import { LessonInfo, LessonStatus, DailyTask } from '../models/DataModels';
import { HomeContent } from '../components/HomeContent';
import { StudyContent } from '../components/StudyContent';
import { DictContent } from '../components/DictContent';
import { ProfileContent } from '../components/ProfileContent';
import { FloatingSpirit } from '../components/FloatingSpirit';
import { SpiritChatPanel } from '../components/SpiritChatPanel';
import promptAction from '@ohos.promptAction';
import TaskTrackingService from '../services/TaskTrackingService';
import preferences from '@ohos.data.preferences';
import { themeManager } from '../utils/ThemeManager';

@Entry
@Component
struct Index {
  @State currentTabIndex: number = 0;  // 默认首页
  @State dictSearchWord: string = '';
  @State showSpiritPanel: boolean = false;
  @State isDarkMode: boolean = false;

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

    // 初始化任务服务
    await this.taskService.init(context);

    this.applyRouteTabIndex();
  }

  onPageShow() {
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

      this.currentTabIndex = targetIndex;
      this.tabController.changeIndex(targetIndex);
    } catch (e) {
      // Ignore invalid route params.
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      // Tab内容区
      Tabs({ barPosition: BarPosition.End, controller: this.tabController }) {
        // 首页 Tab
        TabContent() {
          HomeContent()
        }
        .tabBar(this.TabBarItem('首页', $r('app.media.ic_home'), 0))

        // 学习 Tab
        TabContent() {
          StudyContent()
        }
        .tabBar(this.TabBarItem('学习', $r('app.media.ic_study'), 1))

        // 词典 Tab
        TabContent() {
          this.DictTabContent()
        }
        .tabBar(this.TabBarItem('词典', $r('app.media.ic_dict'), 2))

        // 我的 Tab
        TabContent() {
          ProfileContent()
        }
        .tabBar(this.TabBarItem('我的', $r('app.media.ic_mine'), 3))
      }
      .barMode(BarMode.Fixed)
      .barWidth('100%')
      .barHeight(0)
      .barBackgroundColor(this.isDarkMode ? DarkTheme.NAV_BG : LightTheme.NAV_BG)
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
      .margin({ right: 20, bottom: 105 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDarkMode ? DarkTheme.BG_BODY : LightTheme.BG_BODY)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .bindSheet($$this.showSpiritPanel, this.SpiritPanelBuilder(), {
      height: '85%',
      dragBar: false,
      showClose: false,
      backgroundColor: Color.Transparent
    })
  }

  @Builder
  SpiritPanelBuilder() {
    SpiritChatPanel({
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
        .fillColor(this.currentTabIndex === index
          ? COLORS.PRIMARY
          : (this.isDarkMode ? DarkTheme.TEXT_DIM : LightTheme.TEXT_DIM))

      Text(title)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.currentTabIndex === index
          ? COLORS.PRIMARY
          : (this.isDarkMode ? DarkTheme.TEXT_DIM : LightTheme.TEXT_DIM))
        .margin({ top: 6 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ bottom: 20 })  // 适配安全区
  }

  @Builder
  DictTabContent() {
    DictContent({ searchWordFromExternal: this.dictSearchWord })
  }

  @Builder
  BottomTabBar() {
    Row() {
      this.BottomTabItem('首页', $r('app.media.ic_home'), 0)
      this.BottomTabItem('学习', $r('app.media.ic_study'), 1)
      this.BottomTabItem('词典', $r('app.media.ic_dict'), 2)
      this.BottomTabItem('我的', $r('app.media.ic_mine'), 3)
    }
    .width('100%')
    .height(74)
    .padding({ bottom: 14 })
    .backgroundColor(this.isDarkMode ? DarkTheme.NAV_BG : LightTheme.NAV_BG)
    .border({ width: 1, color: this.isDarkMode ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)' })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    .translate({ y: 8 })
  }

  @Builder
  BottomTabItem(title: string, icon: Resource, index: number) {
    Column() {
      Image(icon)
        .width(24)
        .height(24)
        .fillColor(this.currentTabIndex === index
          ? COLORS.PRIMARY
          : (this.isDarkMode ? DarkTheme.TEXT_DIM : LightTheme.TEXT_DIM))

      Text(title)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.currentTabIndex === index
          ? COLORS.PRIMARY
          : (this.isDarkMode ? DarkTheme.TEXT_DIM : LightTheme.TEXT_DIM))
        .margin({ top: 6 })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.currentTabIndex = index;
      this.tabController.changeIndex(index);
    })
  }
}
