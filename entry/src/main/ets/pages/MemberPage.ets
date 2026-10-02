import router from '@ohos.router';
import { COLORS } from '../utils/Constants';
import { UI } from '../utils/UiTokens';
import { UserInfo } from '../models/DataModels';
import ApiService from '../services/ApiService';
import { themeManager } from '../utils/ThemeManager';

@Entry
@Component
struct MemberPage {
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

    const context = getContext(this);
    const apiService = ApiService.getInstance();
    await apiService.init(context);

    if (!apiService.getToken()) {
      this.loading = false;
      return;
    }

    try {
      this.userInfo = await apiService.getCurrentUserInfo();
    } catch (error) {
      console.error('[MemberPage] load user info failed:', JSON.stringify(error));
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

  private quotaText(limit: number, used: number, remaining: number, unit: string): string {
    if (limit <= 0) {
      return `已使用 ${used}${unit} · 不限量`;
    }
    return `今日已用 ${used}/${limit}${unit} · 剩余 ${remaining}${unit}`;
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
      } else {
        Scroll() {
          Column({ space: 16 }) {
            this.CurrentMemberCard()
            this.TodayQuotaCard()
            this.ActiveBenefitsCard()
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

      Text('会员详情')
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .margin({ left: 16 })

      Blank()
    }
    .width('100%')
    .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: UI.CONTENT_TOP, bottom: 20 })
  }

  @Builder
  CurrentMemberCard() {
    Column({ space: 18 }) {
      Row() {
        Column({ space: 6 }) {
          Text('当前会员')
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
        Image($r('app.media.lingai_robot'))
          .width(76)
          .height(76)
          .objectFit(ImageFit.Contain)
      }
      .width('100%')

      Text('试运行阶段，基础会员可使用学习、词典、生词本与学习统计，并按当日额度解锁。')
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

      this.BenefitItem(
        '关卡学习',
        this.quotaText(
          this.userInfo.dailyLessonLimit,
          this.userInfo.dailyLessonUsed,
          this.userInfo.dailyLessonRemaining,
          '关'
        )
      )
      this.BenefitItem(
        '词典查询',
        this.quotaText(
          this.userInfo.dailyDictLimit,
          this.userInfo.dailyDictUsed,
          this.userInfo.dailyDictRemaining,
          '词'
        )
      )
      this.BenefitItem(
        'AI 助手',
        this.quotaText(
          this.userInfo.dailyAiLimit,
          this.userInfo.dailyAiUsed,
          this.userInfo.dailyAiRemaining,
          '次'
        )
      )
    }
    .width('100%')
    .padding(22)
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(24)
    .border({ width: 1, color: COLORS.BORDER })
  }

  @Builder
  ActiveBenefitsCard() {
    Column({ space: 12 }) {
      Text('当前已开放权益')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')

      this.BenefitItem('学习路径解锁', '学习关卡与智能复习，每日额度见上方')
      this.BenefitItem('词典与收藏', '查询韩语词条，收藏生词与查看最近添加')
      this.BenefitItem('小语灵助手', '提问与韩语学习相关的问题，每日额度见上方')
      this.BenefitItem('学习统计', '查看本机任务进度与连续学习情况')
      this.BenefitItem('账号同步', '登录后同步你的基础学习身份')
    }
    .width('100%')
    .padding(22)
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(24)
    .border({ width: 1, color: COLORS.BORDER })
  }

  @Builder
  ProPreviewCard() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        Image($r('app.media.ic_study'))
          .width(24)
          .height(24)
          .fillColor(UI.BLUE)
        Text('LingAI Pro 即将上线')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
      }
      .width('100%')

      Text('当前版本暂不开放购买与付费提醒。正式开放后，这里会更新权益与开通方式。')
        .fontSize(14)
        .lineHeight(23)
        .fontColor(COLORS.TEXT_SECONDARY)
        .width('100%')

      Column({ space: 10 }) {
        this.ProPreviewItem('更完整的会员权益说明与专属入口')
        this.ProPreviewItem('更强的学习陪练与个性化能力')
        this.ProPreviewItem('后续统一会员体系接入')
      }
      .width('100%')
    }
    .width('100%')
    .padding(22)
    .borderRadius(UI.CARD_RADIUS)
    .backgroundColor(UI.BLUE_SOFT)
  }

  @Builder
  BenefitItem(title: string, description: string) {
    Row() {
      Text('✓')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.PRIMARY)

      Column() {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLORS.TEXT_PRIMARY)
          .width('100%')

        Text(description)
          .fontSize(13)
          .lineHeight(20)
          .fontColor(COLORS.TEXT_SECONDARY)
          .width('100%')
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: 12 })
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
  }

  @Builder
  ProPreviewItem(text: string) {
    Row() {
      Text('•')
        .fontSize(16)
        .fontColor(UI.BLUE)

      Text(text)
        .fontSize(14)
        .fontColor(UI.BLUE)
        .margin({ left: 8 })
    }
    .width('100%')
  }
}

export default MemberPage;
