import router from '@ohos.router';
import { COLORS } from '../utils/Constants';
import { UI } from '../utils/UiTokens';
import { themeManager } from '../utils/ThemeManager';

class IndexRouteParams {
  tabIndex: number = 3;
  navFrom: string = 'feature_gate';
  navAt: number = Date.now();
  openSheetMode: string = 'login';
}

@Component
export struct AuthRequiredState {
  @Prop title: string = '把进步留在你的账号里';
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
      Image($r('app.media.lingai_robot'))
        .width(84)
        .height(84)
        .objectFit(ImageFit.Contain)

      Text(this.title)
        .fontSize(23)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .textAlign(TextAlign.Center)
        .margin({ top: 24 })

      Text(this.description)
        .fontSize(16)
        .lineHeight(26)
        .fontColor(COLORS.TEXT_SECONDARY)
        .textAlign(TextAlign.Center)
        .margin({ top: 12 })

      Button(this.buttonText)
        .type(ButtonType.Normal)
        .backgroundColor(COLORS.PRIMARY)
        .fontColor(UI.ON_PRIMARY)
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .height(54)
        .width('100%')
        .borderRadius(12)
        .margin({ top: 30 })
        .onClick(() => {
          void this.goLoginTab();
        })
    }
    .width('100%')
    .height('100%')
    .padding({ left: 32, right: 32, top: 32, bottom: 48 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(COLORS.BACKGROUND)
  }
}
