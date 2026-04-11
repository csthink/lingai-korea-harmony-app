import router from '@ohos.router';
import { COLORS } from '../utils/Constants';
import { themeManager } from '../utils/ThemeManager';

class IndexRouteParams {
  tabIndex: number = 3;
  navFrom: string = 'feature_gate';
  navAt: number = Date.now();
  openSheetMode: string = 'login';
}

@Component
export struct AuthRequiredState {
  @Prop title: string = '注册后解锁完整功能';
  @Prop description: string = '试运行阶段需要先登录 / 注册，才能开始使用该功能。';
  @Prop buttonText: string = '去登录 / 注册';
  @Prop source: string = 'feature_gate';
  @State themeVersion: number = 0;

  private navigating: boolean = false;
  private unsubscribeTheme: (() => void) | null = null;

  aboutToAppear() {
    if (this.unsubscribeTheme === null) {
      this.unsubscribeTheme = themeManager.subscribe(() => {
        this.themeVersion++;
      });
    }
  }

  aboutToDisappear() {
    if (this.unsubscribeTheme !== null) {
      this.unsubscribeTheme();
      this.unsubscribeTheme = null;
    }
  }

  private async goLoginTab(): Promise<void> {
    if (this.navigating) {
      return;
    }

    this.navigating = true;
    const params = new IndexRouteParams();
    params.tabIndex = 3;
    params.navFrom = this.source;
    params.navAt = Date.now();
    params.openSheetMode = 'login';

    try {
      await router.replaceUrl({
        url: 'pages/Index',
        params,
      });
    } catch (replaceErr) {
      console.warn('[AuthRequiredState] replaceUrl failed:', JSON.stringify(replaceErr));
      try {
        await router.pushUrl({
          url: 'pages/Index',
          params,
        });
      } catch (pushErr) {
        console.error('[AuthRequiredState] pushUrl failed:', JSON.stringify(pushErr));
      }
    } finally {
      this.navigating = false;
    }
  }

  build() {
    Column() {
      Column() {
        Image($r('app.media.ic_lock'))
          .width(34)
          .height(34)
          .fillColor(COLORS.PRIMARY)
      }
      .width(72)
      .height(72)
      .borderRadius(36)
      .backgroundColor('rgba(99, 102, 241, 0.12)')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      Text(this.title)
        .fontSize(22)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .textAlign(TextAlign.Center)
        .margin({ top: 22 })

      Text(this.description)
        .fontSize(14)
        .lineHeight(22)
        .fontColor(COLORS.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .margin({ top: 12 })

      Button(this.buttonText)
        .type(ButtonType.Capsule)
        .backgroundColor(COLORS.PRIMARY)
        .fontColor('#ffffff')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .height(50)
        .margin({ top: 26 })
        .padding({ left: 24, right: 24 })
        .onClick(() => {
          void this.goLoginTab();
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 28, right: 28, top: 32, bottom: 32 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(COLORS.BACKGROUND)
  }
}
