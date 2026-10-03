import router from '@ohos.router';
import { COLORS } from '../utils/Constants';
import { UI } from '../utils/UiTokens';
import { UserInfo } from '../models/DataModels';
import ApiService from '../services/ApiService';
import { themeManager } from '../utils/ThemeManager';

@Entry
@Component
struct MemberPage {
  @State loadError: string = '';
  @State loading: boolean = true;
  @State themeVersion: number = 0;
  @State userInfo: UserInfo = new UserInfo();

  private unsubscribeTheme: (() => void) | null = null;

  async aboutToAppear() {
    if (this.unsubscribeTheme === null) {
      this.unsubscribeTheme = themeManager.subscribe(() => {
        this.themeVersion++;
      });
    }

    this.loading = true;
    this.loadError = '';
    const context = getContext(this);
    const apiService = ApiService.getInstance();
    await apiService.init(context);

    if (!apiService.getToken()) {
      this.loadError = '登录后可查看当前身份和今日额度。';
      this.loading = false;
      return;
    }

    try {
      this.userInfo = await apiService.getCurrentUserInfo();
    } catch (error) {
      console.error('[MemberPage] load user info failed:', JSON.stringify(error));
      this.loadError = '会员信息暂时没有加载出来，请重试。';
    } finally {
      this.loading = false;
    }
  }

  aboutToDisappear() {
    if (this.unsubscribeTheme !== null) {
      this.unsubscribeTheme();
      this.unsubscribeTheme = null;
    }
  }

  private currentName(): string {
    if (this.userInfo.nickname.trim().length > 0) {
      return this.userInfo.nickname;
    }
    if (this.userInfo.phone.trim().length > 0) {
      return this.userInfo.phone;
    }
    return '小灵友';
  }

  build() {
    Column() {
      this.Header()

      if (this.loading) {
        Column() {
          LoadingProgress()
            .width(42)
            .height(42)
            .color(COLORS.PRIMARY)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
      } else if (this.loadError.length > 0) {
        Column({ space: 20 }) {
          Text(this.loadError).fontSize(15).lineHeight(24).fontColor(COLORS.TEXT_SECONDARY).textAlign(TextAlign.Center)
          Button('重新加载')
            .type(ButtonType.Normal)
            .height(48)
            .borderRadius(UI.CONTROL_RADIUS)
            .backgroundColor(COLORS.PRIMARY)
            .fontColor(UI.ON_PRIMARY)
            .onClick(() => { void this.aboutToAppear(); })
        }
        .layoutWeight(1)
        .padding(UI.PAGE_INSET)
        .justifyContent(FlexAlign.Center)
      } else {
        Scroll() {
          Column({ space: 16 }) {
            this.CurrentMemberCard()
            this.TodayQuotaCard()
            this.ProPreviewCard()
          }
          .width('100%')
          .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 8, bottom: 36 })
        }
        .layoutWeight(1)
        .width('100%')
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BACKGROUND)
  }

  @Builder
  Header() {
    Row() {
      Image($r('app.media.ic_back'))
        .width(UI.TOUCH_MIN)
        .height(UI.TOUCH_MIN)
        .padding(10)
        .backgroundColor(COLORS.SURFACE)
        .borderRadius(15)
        .border({ width: 1, color: COLORS.BORDER })
        .fillColor(COLORS.TEXT_PRIMARY)
        .onClick(() => {
          router.back();
        })

      Text('会员与额度')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .margin({ left: 16 })

      Blank()
    }
    .width('100%')
    .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: UI.CONTENT_TOP, bottom: 20 })
      .backgroundColor(COLORS.SURFACE)
  }

  @Builder
  CurrentMemberCard() {
    Column({ space: 18 }) {
      Row() {
        Column({ space: 6 }) {
          Text('当前身份')
            .fontSize(13)
            .fontColor(COLORS.TEXT_SECONDARY)
          Text(this.userInfo.memberLevelLabel)
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text(this.currentName())
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLORS.PRIMARY)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Image($r('app.media.ic_mine'))
          .width(30)
          .height(30)
          .fillColor(COLORS.PRIMARY)
      }
      .width('100%')

      Text('今天也有值得期待的一点进步。')
        .fontSize(14)
        .lineHeight(23)
        .fontColor(COLORS.TEXT_SECONDARY)
        .width('100%')
    }
    .width('100%')
    .padding(24)
    .backgroundColor(UI.GREEN_SOFT)
    .borderRadius(UI.CARD_RADIUS)
  }

  @Builder
  TodayQuotaCard() {
    Column({ space: 14 }) {
      Text('今日可用额度')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')

      this.QuotaItem('关卡学习', this.userInfo.dailyLessonLimit, this.userInfo.dailyLessonUsed, this.userInfo.dailyLessonRemaining, '关')
      this.QuotaItem('词典查询', this.userInfo.dailyDictLimit, this.userInfo.dailyDictUsed, this.userInfo.dailyDictRemaining, '次')
      this.QuotaItem('AI 助手', this.userInfo.dailyAiLimit, this.userInfo.dailyAiUsed, this.userInfo.dailyAiRemaining, '次')
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .backgroundColor(COLORS.SURFACE)
  }

  @Builder
  QuotaItem(title: string, limit: number, used: number, remaining: number, unit: string) {
    Column({ space: 10 }) {
      Row({ space: 12 }) {
        Text(title).fontSize(14).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
        Text(limit <= 0 ? `已使用 ${used} ${unit} · 不限量` : `剩余 ${remaining} / ${limit} ${unit}`)
          .fontSize(12)
          .fontColor(COLORS.TEXT_SECONDARY)
      }
      .width('100%')
      Progress({ value: limit <= 0 ? 1 : Math.max(0, remaining), total: Math.max(1, limit), type: ProgressType.Linear })
        .width('100%')
        .height(6)
        .color(COLORS.PRIMARY)
        .backgroundColor(UI.GREEN_SOFT)
    }
    .width('100%')
    .padding({ top: 10, bottom: 10 })
  }

  @Builder
  ProPreviewCard() {
    Column({ space: 18 }) {
      Row() {
        Text('会员计划')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)
        Text('敬请期待')
          .fontSize(12)
          .fontColor(COLORS.PRIMARY)
          .padding({ left: 10, right: 10, top: 5, bottom: 5 })
          .backgroundColor(UI.GREEN_SOFT)
          .borderRadius(8)
      }
      .width('100%')
      Text('更多学习额度、更完整的陪练体验，正在准备中。')
        .fontSize(14)
        .lineHeight(23)
        .fontColor(COLORS.TEXT_SECONDARY)
        .width('100%')
      Row({ space: 12 }) {
        this.MemberPreviewBenefit('持续积累词汇', $r('app.media.ic_study'))
        this.MemberPreviewBenefit('练习真实表达', $r('app.media.ic_dict'))
      }
      .width('100%')
      Button('查看会员说明')
        .type(ButtonType.Normal)
        .width('100%')
        .constraintSize({ minHeight: 50 })
        .borderRadius(UI.CONTROL_RADIUS)
        .fontColor(COLORS.TEXT_PRIMARY)
        .backgroundColor(COLORS.SURFACE)
        .border({ width: 1, color: COLORS.BORDER })
        .onClick(() => {
          this.getUIContext().getPromptAction().showDialog({
            title: '会员正在准备中',
            message: '当前展示已有额度与会员预告。暂不开放购买，不会扣费；正式权益与价格以后续产品发布为准。',
            buttons: [{ text: '知道了', color: COLORS.PRIMARY }]
          });
        })
      Text('当前没有购买或支付操作。')
        .fontSize(12)
        .fontColor(COLORS.TEXT_SECONDARY)
        .width('100%')
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
  }

  @Builder
  MemberPreviewBenefit(title: string, icon: Resource) {
    Column({ space: 12 }) {
      Image(icon).width(26).height(26).fillColor(COLORS.PRIMARY)
      Text(title).fontSize(13).fontColor(COLORS.TEXT_SECONDARY)
    }
    .layoutWeight(1)
    .padding(18)
    .backgroundColor(UI.GREEN_SOFT)
    .borderRadius(16)
  }

}

export default MemberPage;
