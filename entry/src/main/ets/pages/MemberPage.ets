import router from '@ohos.router';
import { COLORS } from '../utils/Constants';
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
          .padding({ left: 20, right: 20, top: 12, bottom: 36 })
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
        .width(24)
        .height(24)
        .fillColor(COLORS.TEXT_PRIMARY)
        .onClick(() => {
          router.back();
        })

      Text('会员详情')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .margin({ left: 16 })

      Blank()
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 50, bottom: 12 })
  }

  @Builder
  CurrentMemberCard() {
    Column() {
      Row() {
        Column() {
          Text('当前会员')
            .fontSize(14)
            .fontColor(COLORS.TEXT_SECONDARY)

          Text(this.userInfo.memberLevelLabel)
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .margin({ top: 6 })
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        Text('已注册')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ffffff')
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(COLORS.PRIMARY)
          .borderRadius(999)
      }
      .width('100%')

      Text(this.currentName())
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')
        .margin({ top: 20 })

      Text('试运行阶段，基础会员可使用学习、词典、生词本与学习统计，并按当日额度解锁。')
        .fontSize(14)
        .lineHeight(22)
        .fontColor(COLORS.TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(22)
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(24)
    .shadow({ radius: 12, color: 'rgba(148,163,184,0.15)', offsetY: 4 })
  }

  @Builder
  TodayQuotaCard() {
    Column({ space: 14 }) {
      Text('今日基础会员额度')
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
    .shadow({ radius: 12, color: 'rgba(148,163,184,0.15)', offsetY: 4 })
  }

  @Builder
  ActiveBenefitsCard() {
    Column({ space: 12 }) {
      Text('当前已开放权益')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')

      this.BenefitItem('学习路径解锁', '基础会员每日可学习 2 关，支持智能复习')
      this.BenefitItem('词典与收藏', '基础会员每日可免费查询 50 个词，支持生词本与最近添加')
      this.BenefitItem('小语灵助手', '基础会员每日可向 AI 助手提问 10 次，同一问题短时间重复提问不重复扣减')
      this.BenefitItem('学习统计', '同步查看任务进度与连续学习情况')
      this.BenefitItem('账号同步', '登录后同步你的基础学习身份')
    }
    .width('100%')
    .padding(22)
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(24)
    .shadow({ radius: 12, color: 'rgba(148,163,184,0.15)', offsetY: 4 })
  }

  @Builder
  ProPreviewCard() {
    Column() {
      Row() {
        Text('👑')
          .fontSize(22)

        Text('LingAI Pro 即将上线')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ffffff')
          .margin({ left: 10 })
      }
      .width('100%')

      Text('当前版本先不开放购买与付费提醒。后续正式开放时，我们会在这里更新权益与开通方式。')
        .fontSize(14)
        .lineHeight(22)
        .fontColor('rgba(255,255,255,0.88)')
        .width('100%')
        .margin({ top: 14 })

      Column({ space: 10 }) {
        this.ProPreviewItem('更完整的会员权益说明与专属入口')
        this.ProPreviewItem('更强的学习陪练与个性化能力')
        this.ProPreviewItem('后续统一会员体系接入')
      }
      .width('100%')
      .margin({ top: 18 })
    }
    .width('100%')
    .padding(22)
    .borderRadius(24)
    .linearGradient({
      angle: 90,
      colors: [['#4f46e5', 0], ['#818cf8', 1]],
    })
    .shadow({ radius: 18, color: 'rgba(79, 70, 229, 0.28)', offsetY: 8 })
  }

  @Builder
  BenefitItem(title: string, description: string) {
    Row() {
      Text('✓')
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor('#10b981')

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
        .fontColor('#ffffff')

      Text(text)
        .fontSize(14)
        .fontColor('#ffffff')
        .margin({ left: 8 })
    }
    .width('100%')
  }
}

export default MemberPage;
