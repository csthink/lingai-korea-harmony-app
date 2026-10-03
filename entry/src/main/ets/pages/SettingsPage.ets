/**
 * 设置页面
 * 提供学习配置和退出登录功能
 */
import router from '@ohos.router';
import { WORDS_PER_LESSON } from '../utils/Constants';
import { COLORS } from '../utils/Constants';
import { UI } from '../utils/UiTokens';
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
  private context: Context | null = null;

  async aboutToAppear() {
    this.context = getContext(this);
    await this.loadSettings();
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
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .margin({ left: 16 })

        Blank()
      }
      .width('100%')
      .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: UI.CONTENT_TOP, bottom: 20 })
      .backgroundColor(COLORS.SURFACE)

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
            Text('学习偏好')
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
              .width('100%')
              .margin({ bottom: 20 })

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

                Select([
                  { value: '10 个' }, { value: '20 个' }, { value: '30 个' },
                  { value: '40 个' }, { value: '50 个' }, { value: '60 个' },
                  { value: '70 个' }, { value: '80 个' }, { value: '90 个' },
                  { value: '100 个' }
                ])
                  .selected(Math.max(0, Math.min(9, this.wordsPerLesson / 10 - 1)))
                  .value(`${this.wordsPerLesson} 个`)
                  .font({ size: 15 })
                  .fontColor(COLORS.PRIMARY)
                  .backgroundColor(UI.GREEN_SOFT)
                  .onSelect((index: number) => {
                    this.wordsPerLesson = (index + 1) * 10;
                    void this.saveSettings();
                  })
              }
              .width('100%')
              Text('按自己的节奏调整，每关可选择 10 至 100 个单词。')
                .fontSize(13)
                .lineHeight(21)
                .fontColor(COLORS.TEXT_SECONDARY)
                .width('100%')
                .margin({ top: 12 })
            }
            .width('100%')
            .padding({ top: 12, bottom: 20 })
            .border({ width: { bottom: 1 }, color: COLORS.BORDER })
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
            .backgroundColor(COLORS.SURFACE)
            .borderRadius(UI.CONTROL_RADIUS)
            .border({ width: 1, color: COLORS.BORDER })
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

    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BACKGROUND)
  }

}
