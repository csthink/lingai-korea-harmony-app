/**
 * 设置页面
 * 提供外观切换、学习配置和退出登录功能
 */
import router from '@ohos.router';
import { WORDS_PER_LESSON } from '../utils/Constants';
import { COLORS } from '../utils/Constants';
import { UI } from '../utils/UiTokens';
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
  private isSwitchingTab: boolean = false;

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
            .fontColor(COLORS.TEXT_PRIMARY)
        }
        .width(UI.TOUCH_MIN)
        .height(UI.TOUCH_MIN)
        .borderRadius(15)
        .backgroundColor(COLORS.SURFACE)
        .justifyContent(FlexAlign.Center)
        .border({ width: 1, color: COLORS.BORDER })
        .onClick(() => {
          router.back();
        })

        Text('设置')
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .margin({ left: 16 })

        Blank()
      }
      .width('100%')
      .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: UI.CONTENT_TOP, bottom: 20 })

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
            // ========== 学习设置区块 ==========
            Row() {
              Column({ space: 6 }) {
                Text('学习节奏')
                  .fontSize(20)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(COLORS.TEXT_PRIMARY)
                Text('选择适合自己的每关单词数')
                  .fontSize(14)
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
            .padding({ bottom: 20 })

            Text('学习设置')
              .fontSize(14)
              .fontColor(COLORS.TEXT_SECONDARY)
              .width('100%')
              .padding({ left: 4, bottom: 12 })

            // 每关单词数卡片
            Column() {
              Row() {
                Image($r('app.media.ic_study'))
                  .width(22)
                  .height(22)
                  .fillColor(COLORS.PRIMARY)
                Text('每关单词数')
                  .fontSize(16)
                  .fontColor(COLORS.TEXT_PRIMARY)
                  .margin({ left: 12 })

                Blank()

                Text(`${this.wordsPerLesson}`)
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(COLORS.TEXT_PRIMARY)
              }
              .width('100%')

              Slider({
                value: this.wordsPerLesson,
                min: 10,
                max: 100,
                step: 10,
                style: SliderStyle.OutSet
              })
                .blockColor(COLORS.PRIMARY)
                .trackColor(COLORS.BORDER)
                .selectedColor(COLORS.PRIMARY)
                .width('100%')
                .margin({ top: 16 })
                .onChange((value: number) => {
                  this.wordsPerLesson = value;
                  this.saveSettings();
                })

              Row() {
                Text('10')
                  .fontSize(12)
                  .fontColor(COLORS.TEXT_HINT)
                Blank()
                Text('100')
                  .fontSize(12)
                  .fontColor(COLORS.TEXT_HINT)
              }
              .width('100%')
              .margin({ top: 4 })
            }
            .width('100%')
            .padding(22)
            .backgroundColor(COLORS.SURFACE)
            .borderRadius(UI.CARD_RADIUS)
            .shadow({ radius: 8, color: UI.SHADOW, offsetY: 2 })
            .margin({ bottom: 32 })

            // ========== 退出登录按钮 - 浅粉色背景 ==========
            Row() {
              Text('退出登录')
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor(UI.DANGER_TEXT)
            }
            .width('100%')
            .height(54)
            .justifyContent(FlexAlign.Center)
            .backgroundColor(UI.DANGER_SOFT)
            .borderRadius(20)
            .border({ width: 1, color: UI.DANGER_SOFT })
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
          .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, bottom: 32 })
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
    .backgroundColor(COLORS.BACKGROUND)
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
    .height(UI.NAV_HEIGHT)
    .padding({ left: 8, right: 8, top: 6, bottom: 16 })
    .backgroundColor(COLORS.SURFACE)
    .border({ width: { top: 1 }, color: COLORS.BORDER })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

  }

  @Builder
  BottomTabItem(title: string, icon: Resource, index: number) {
    Column() {
      Row() {
        Image(icon)
          .width(22)
          .height(22)
          .fillColor(this.currentTabIndex === index ? COLORS.PRIMARY : COLORS.TEXT_HINT)
      }
      .width(54)
      .height(32)
      .justifyContent(FlexAlign.Center)
      .borderRadius(12)
      .backgroundColor(this.currentTabIndex === index ? UI.GREEN_SOFT : Color.Transparent)

      Text(title)
        .fontSize(12)
        .fontWeight(this.currentTabIndex === index ? FontWeight.Bold : FontWeight.Medium)
        .fontColor(this.currentTabIndex === index ? COLORS.PRIMARY : COLORS.TEXT_HINT)
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.switchMainTab(index);
    })
  }

  private async switchMainTab(index: number) {
    if (this.isSwitchingTab) return;
    this.isSwitchingTab = true;
    this.currentTabIndex = index;
    try {
      await router.replaceUrl({
        url: 'pages/Index',
        params: {
          tabIndex: index
        }
      });
    } catch (e) {
      console.error('[SettingsPage] switchMainTab failed:', e);
    } finally {
      this.isSwitchingTab = false;
    }
  }
}
