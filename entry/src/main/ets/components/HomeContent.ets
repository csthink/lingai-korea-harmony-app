/**
 * 首页内容组件
 * 包含: 顶部Header(问候语+连续天数), 环形进度条, 今日任务卡片
 * 适配 ArkTS 严格模式
 */
import router from '@ohos.router';
import { COLORS } from '../utils/Constants';
import { DailyTask } from '../models/DataModels';
import TaskTrackingService from '../services/TaskTrackingService';
import { themeManager } from '../utils/ThemeManager';

@Component
export struct HomeContent {
  @State userName: string = '小明';
  @State streakDays: number = 12;
  @State todayProgress: number = 75;
  @State dailyTask: DailyTask = new DailyTask();
  @State taskVersionKey: number = 0;
  @State newWordsCount: number = 15;
  @State reviewWordsCount: number = 28;
  @State themeVersion: number = 0;

  private taskService: TaskTrackingService = TaskTrackingService.getInstance();
  private unsubscribeTheme: (() => void) | null = null;

  async aboutToAppear() {
    if (this.unsubscribeTheme === null) {
      this.unsubscribeTheme = themeManager.subscribe(() => {
        this.themeVersion++;
      });
    }

    const context = getContext(this);
    await this.taskService.init(context);
    this.dailyTask = this.taskService.getCurrentTask();
    this.reviewWordsCount = this.dailyTask.reviewCount > 0 ? this.dailyTask.reviewCount : 28;

    this.taskService.setOnUpdateCallback((task: DailyTask) => {
      this.dailyTask = task;
      this.reviewWordsCount = task.reviewCount > 0 ? task.reviewCount : 28;
      this.taskVersionKey++;
    });
  }

  aboutToDisappear() {
    if (this.unsubscribeTheme !== null) {
      this.unsubscribeTheme();
      this.unsubscribeTheme = null;
    }
  }

  build() {
    Column() {
      // 顶部Header: 问候语 + 连续天数徽章
      this.HeaderSection()

      // 环形进度条
      this.ProgressSection()

      // 今日任务标题
      Text('今日任务')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')
        .padding({ left: 24, right: 24, top: 30, bottom: 16 })

      // 任务卡片列表
      this.TaskCards()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BACKGROUND)
  }

  @Builder
  HeaderSection() {
    Row() {
      // 问候语
      Text('Hello, ' + this.userName)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .letterSpacing(-0.5)

      Blank()

      // 连续天数徽章
      Row() {
        Text('🔥')
          .fontSize(14)

        Text(this.streakDays.toString() + ' 天')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .fontColor('#fb923c')
          .margin({ left: 4 })
      }
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor('rgba(249, 115, 22, 0.15)')
      .border({ width: 1, color: 'rgba(249, 115, 22, 0.3)', radius: 100 })
    }
    .width('100%')
    .padding({ left: 24, right: 24, top: 50, bottom: 10 })
  }

  @Builder
  ProgressSection() {
    Column() {
      Stack() {
        // 背景环
        Circle()
          .width(160)
          .height(160)
          .fill(Color.Transparent)
          .stroke('rgba(0,0,0,0.06)')
          .strokeWidth(12)

        // 进度环
        Progress({ value: this.todayProgress, total: 100, type: ProgressType.Ring })
          .width(160)
          .height(160)
          .color('#6366f1')
          .backgroundColor('transparent')
          .style({ strokeWidth: 12 })

        // 中间文字
        Column() {
          Text(this.todayProgress.toString() + '%')
            .fontSize(36)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)

          Text('今日进度')
            .fontSize(14)
            .fontColor(COLORS.TEXT_SECONDARY)
            .margin({ top: 4 })
        }
      }
      .width(180)
      .height(180)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .margin({ top: 20 })
  }

  @Builder
  TaskCards() {
    Column({ space: 12 }) {
      // TOPIK 学习卡片
      Row() {
        // 左侧图标
        Column() {
          Image($r('app.media.ic_layers'))
            .width(24)
            .height(24)
            .fillColor(COLORS.PRIMARY)
        }
        .width(48)
        .height(48)
        .borderRadius(14)
        .backgroundColor('rgba(99, 102, 241, 0.15)')
        .justifyContent(FlexAlign.Center)

        // 中间文字
        Column() {
          Text('TOPIK I • 关卡 4')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLORS.TEXT_PRIMARY)

          Text(this.newWordsCount.toString() + ' 个新词 • 预计 8 分钟')
            .fontSize(12)
            .fontColor(COLORS.TEXT_SECONDARY)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 16 })

        // 开始按钮
        Button('开始')
          .type(ButtonType.Capsule)
          .backgroundColor('#0f172a')
          .fontColor('#ffffff')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .height(36)
          .padding({ left: 16, right: 16 })
          .shadow({ radius: 8, color: 'rgba(0,0,0,0.1)', offsetY: 2 })
          .onClick(() => {
            this.startLearning();
          })
      }
      .width('100%')
      .padding(18)
      .backgroundColor(COLORS.SURFACE)
      .borderRadius(24)
      .shadow({ radius: 12, color: 'rgba(148,163,184,0.15)', offsetY: 4 })

      // 智能复习卡片
      Row() {
        // 左侧图标
        Column() {
          Image($r('app.media.ic_review'))
            .width(24)
            .height(24)
            .fillColor(COLORS.SUCCESS)
        }
        .width(48)
        .height(48)
        .borderRadius(14)
        .backgroundColor('rgba(16, 185, 129, 0.15)')
        .justifyContent(FlexAlign.Center)

        // 中间文字
        Column() {
          Text('智能复习')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLORS.TEXT_PRIMARY)

          Text(this.reviewWordsCount.toString() + ' 个单词待复习')
            .fontSize(12)
            .fontColor(COLORS.TEXT_SECONDARY)
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 16 })

        // 去完成按钮
        Button('去完成')
          .type(ButtonType.Capsule)
          .backgroundColor(COLORS.SUCCESS)
          .fontColor('#ffffff')
          .fontSize(13)
          .fontWeight(FontWeight.Bold)
          .height(36)
          .padding({ left: 16, right: 16 })
          .shadow({ radius: 8, color: 'rgba(16, 185, 129, 0.3)', offsetY: 2 })
          .onClick(() => {
            this.startReview();
          })
      }
      .width('100%')
      .padding(18)
      .backgroundColor(COLORS.SURFACE)
      .borderRadius(24)
      .shadow({ radius: 12, color: 'rgba(148,163,184,0.15)', offsetY: 4 })
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
  }

  startLearning() {
    router.pushUrl({
      url: 'pages/LessonPage',
      params: {
        lessonId: 4,
        level: 1,
        title: '关卡 4'
      }
    });
  }

  startReview() {
    // TODO: 实现复习页面跳转
    router.pushUrl({
      url: 'pages/LessonPage',
      params: {
        lessonId: 1,
        level: 1,
        title: '智能复习',
        isReview: true
      }
    });
  }
}
