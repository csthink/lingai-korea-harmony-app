/**
 * 设置页面
 * 提供外观切换、学习配置和退出登录功能
 */
import router from '@ohos.router';
import { LightTheme, DarkTheme, WORDS_PER_LESSON } from '../utils/Constants';
import { globalTheme, themeManager } from '../utils/ThemeManager';
import preferences from '@ohos.data.preferences';
import ApiService from '../services/ApiService';
import promptAction from '@ohos.promptAction';

const PREF_NAME = 'user_settings';
const WORDS_PER_LESSON_KEY = 'wordsPerLesson';

@Entry
@Component
struct SettingsPage {
  @State wordsPerLesson: number = 20;
  @State isLoading: boolean = true;
  @State isDarkMode: boolean = false;
  @State isLightModeOn: boolean = true;
  @State currentTabIndex: number = 3;
  private context: Context | null = null;
  private isInitialized: boolean = false;

  async aboutToAppear() {
    this.context = getContext(this);
    this.isDarkMode = globalTheme.isDarkMode;
    this.isLightModeOn = !this.isDarkMode;
    await this.loadSettings();
    setTimeout(() => {
      this.isInitialized = true;
    }, 100);
  }

  async loadSettings() {
    if (!this.context) return;
    try {
      const pref = await preferences.getPreferences(this.context, PREF_NAME);
      this.wordsPerLesson = await pref.get(WORDS_PER_LESSON_KEY, WORDS_PER_LESSON) as number;
    } catch (error) {
      console.error('Failed to load settings:', error);
    }
    this.isLoading = false;
  }

  async saveSettings() {
    if (!this.context) return;
    try {
      const pref = await preferences.getPreferences(this.context, PREF_NAME);
      await pref.put(WORDS_PER_LESSON_KEY, this.wordsPerLesson);
      await pref.flush();
    } catch (error) {
      console.error('Failed to save settings:', error);
    }
  }

  async handleThemeToggle(isOn: boolean) {
    if (!this.isInitialized) return;
    if (!this.context) return;
    
    const newDarkMode = !isOn;
    if (newDarkMode !== this.isDarkMode) {
      this.isDarkMode = newDarkMode;
      this.isLightModeOn = isOn;
      await themeManager.setDarkMode(this.context, this.isDarkMode);
    }
  }

  build() {
    Column() {
      // Header - 匹配原型图样式
      Row() {
        // 圆形返回按钮
        Row() {
          Text('←')
            .fontSize(18)
            .fontColor(this.isDarkMode ? DarkTheme.TEXT_MAIN : LightTheme.TEXT_MAIN)
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(this.isDarkMode ? DarkTheme.GLASS_SURFACE : '#ffffff')
        .justifyContent(FlexAlign.Center)
        .shadow({ radius: 4, color: 'rgba(0,0,0,0.08)', offsetY: 2 })
        .onClick(() => {
          router.back();
        })

        Text('设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isDarkMode ? DarkTheme.TEXT_MAIN : LightTheme.TEXT_MAIN)
          .margin({ left: 16 })

        Blank()
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 42, bottom: 16 })

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column() {
            // ========== 外观区块 ==========
            Text('外观')
              .fontSize(14)
              .fontColor(this.isDarkMode ? DarkTheme.TEXT_SUB : LightTheme.TEXT_SUB)
              .width('100%')
              .padding({ left: 4, bottom: 12 })

            // 浅色模式卡片
            Row() {
              Text('⚙')
                .fontSize(18)
              Text('浅色模式')
                .fontSize(16)
                .fontColor(this.isDarkMode ? DarkTheme.TEXT_MAIN : LightTheme.TEXT_MAIN)
                .margin({ left: 12 })

              Blank()

              Toggle({ type: ToggleType.Switch, isOn: this.isLightModeOn })
                .selectedColor('#6366f1')
                .switchPointColor('#ffffff')
                .onChange((isOn: boolean) => {
                  this.handleThemeToggle(isOn);
                })
            }
            .width('100%')
            .padding(20)
            .backgroundColor(this.isDarkMode ? DarkTheme.GLASS_SURFACE : '#ffffff')
            .borderRadius(16)
            .shadow({ radius: 8, color: this.isDarkMode ? 'rgba(0,0,0,0.3)' : 'rgba(148,163,184,0.12)', offsetY: 2 })
            .margin({ bottom: 24 })

            // ========== 学习设置区块 ==========
            Text('学习设置')
              .fontSize(14)
              .fontColor(this.isDarkMode ? DarkTheme.TEXT_SUB : LightTheme.TEXT_SUB)
              .width('100%')
              .padding({ left: 4, bottom: 12 })

            // 每关单词数卡片
            Column() {
              Row() {
                Text('📚')
                  .fontSize(18)
                Text('每关单词数')
                  .fontSize(16)
                  .fontColor(this.isDarkMode ? DarkTheme.TEXT_MAIN : LightTheme.TEXT_MAIN)
                  .margin({ left: 12 })

                Blank()

                Text(`${this.wordsPerLesson}`)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(this.isDarkMode ? DarkTheme.TEXT_MAIN : LightTheme.TEXT_MAIN)
              }
              .width('100%')

              Slider({
                value: this.wordsPerLesson,
                min: 10,
                max: 100,
                step: 10,
                style: SliderStyle.OutSet
              })
                .blockColor('#6366f1')
                .trackColor(this.isDarkMode ? DarkTheme.BORDER : '#e2e8f0')
                .selectedColor('#6366f1')
                .width('100%')
                .margin({ top: 16 })
                .onChange((value: number) => {
                  this.wordsPerLesson = value;
                  this.saveSettings();
                })

              Row() {
                Text('10')
                  .fontSize(12)
                  .fontColor(this.isDarkMode ? DarkTheme.TEXT_DIM : LightTheme.TEXT_DIM)
                Blank()
                Text('100')
                  .fontSize(12)
                  .fontColor(this.isDarkMode ? DarkTheme.TEXT_DIM : LightTheme.TEXT_DIM)
              }
              .width('100%')
              .margin({ top: 4 })
            }
            .width('100%')
            .padding(20)
            .backgroundColor(this.isDarkMode ? DarkTheme.GLASS_SURFACE : '#ffffff')
            .borderRadius(16)
            .shadow({ radius: 8, color: this.isDarkMode ? 'rgba(0,0,0,0.3)' : 'rgba(148,163,184,0.12)', offsetY: 2 })
            .margin({ bottom: 32 })

            // ========== 退出登录按钮 - 浅粉色背景 ==========
            Row() {
              Text('退出登录')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor('#f43f5e')
            }
            .width('100%')
            .height(54)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(this.isDarkMode ? 'rgba(244, 63, 94, 0.12)' : '#fef2f2')
            .borderRadius(20)
            .border({ width: 1, color: this.isDarkMode ? '#f43f5e' : '#fecaca' })
            .margin({ bottom: 40 })
            .onClick(() => {
              AlertDialog.show({
                title: '退出登录',
                message: '确定要退出当前账号吗？',
                autoCancel: true,
                alignment: DialogAlignment.Center,
                primaryButton: {
                  value: '取消',
                  action: () => {}
                },
                secondaryButton: {
                  value: '确定',
                  fontColor: '#ef4444',
                  action: async () => {
                    const context = getContext(this);
                    await ApiService.getInstance().logout(context);
                    promptAction.showToast({ message: '退出登录成功' });
                    router.replaceUrl({
                      url: 'pages/Index',
                      params: { tabIndex: 3 }
                    });
                  }
                }
              });
            })
          }
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 110 })
        }
        .layoutWeight(1)
        .width('100%')
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
      }

      this.BottomTabBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.isDarkMode ? DarkTheme.BG_BODY : LightTheme.BG_BODY)
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
        .fillColor(this.currentTabIndex === index ? '#6366f1' : (this.isDarkMode ? DarkTheme.TEXT_DIM : LightTheme.TEXT_DIM))

      Text(title)
        .fontSize(11)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.currentTabIndex === index ? '#6366f1' : (this.isDarkMode ? DarkTheme.TEXT_DIM : LightTheme.TEXT_DIM))
        .margin({ top: 6 })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.switchMainTab(index);
    })
  }

  private switchMainTab(index: number) {
    this.currentTabIndex = index;
    router.replaceUrl({
      url: 'pages/Index',
      params: {
        tabIndex: index
      }
    });
  }
}
