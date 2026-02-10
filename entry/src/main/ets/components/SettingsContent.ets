/**
 * 设置内容组件 - 极简版本用于调试
 */
import { LightTheme, DarkTheme } from '../utils/Constants';

@Component
export struct SettingsContent {
  // 回调函数
  onClose: () => void = () => {};
  onLogout: () => void = () => {};

  aboutToAppear() {
    console.info('SettingsContent: aboutToAppear called');
  }

  build() {
    Column() {
      // Header
      Row() {
        // 返回按钮
        Row() {
          Text('←')
            .fontSize(20)
            .fontColor(LightTheme.TEXT_MAIN)
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(LightTheme.GLASS_SURFACE)
        .justifyContent(FlexAlign.Center)
        .onClick(() => {
          console.info('SettingsContent: Back button clicked');
          this.onClose();
        })

        Text('设置')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(LightTheme.TEXT_MAIN)
          .margin({ left: 16 })

        Blank()
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 16 })

      // 简单内容
      Column() {
        Text('设置页面内容')
          .fontSize(18)
          .fontColor(LightTheme.TEXT_MAIN)
          .margin({ top: 40 })

        Text('这是一个测试页面')
          .fontSize(14)
          .fontColor(LightTheme.TEXT_SUB)
          .margin({ top: 12 })
      }
      .layoutWeight(1)
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(LightTheme.BG_BODY)
  }
}
