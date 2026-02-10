/**
 * 学习统计页面
 * 展示学习数据概览、趋势和进度
 */
import router from '@ohos.router';
import { COLORS } from '../utils/Constants';
import { LearningOverview, DailyStats, VocabStats, DailyTask } from '../models/DataModels';
import StatisticsService from '../services/StatisticsService';
import TaskTrackingService from '../services/TaskTrackingService';

// 日历日期数据类
class CalendarDay {
  date: string = '';
  dayOfMonth: number = 0;
  studyMinutes: number = 0;
  lessonsCompleted: number = 0;
  reviewCount: number = 0;
}

@Entry
@Component
struct StatisticsPage {
  @State overview: LearningOverview = new LearningOverview();
  @State weeklyTrend: DailyStats[] = [];
  @State vocabStats: VocabStats = new VocabStats();
  @State todayTask: DailyTask = new DailyTask();
  @State isLoading: boolean = true;
  @State selectedDate: string = '';
  @State displayedYear: number = new Date().getFullYear();
  @State displayedMonth: number = new Date().getMonth();

  private statisticsService: StatisticsService = StatisticsService.getInstance();
  private taskService: TaskTrackingService = TaskTrackingService.getInstance();

  async aboutToAppear() {
    await this.loadData();
  }

  async loadData() {
    this.isLoading = true;
    try {
      // 加载数据
      const overview = await this.statisticsService.getOverview();
      const trend = await this.statisticsService.getMonthlyTrend();
      const vocab = await this.statisticsService.getVocabularyStats();
      
      this.overview = overview;
      this.weeklyTrend = trend;
      this.vocabStats = vocab;
      this.todayTask = this.taskService.getCurrentTask();
      if (this.selectedDate === '') {
        this.selectedDate = this.statisticsService.getTodayDateString();
      }
    } catch (error) {
      console.error('Failed to load statistics:', error);
    }
    this.isLoading = false;
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor(COLORS.TEXT_PRIMARY)
          .onClick(() => {
            router.back();
          })

        Text('学习统计')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLORS.TEXT_PRIMARY)
          .margin({ left: 12 })

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 42, bottom: 16 })
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
        List() {
          // 模块1：学习概览卡片
          ListItem() {
            this.OverviewCard()
          }

          // 模块2：今日任务进度
          ListItem() {
            this.TodayTaskCard()
          }

          // 模块3：学习打卡日历
          ListItem() {
            this.CalendarCheckInCard()
          }

          // 模块4：生词本统计
          ListItem() {
            this.VocabularyStatsCard()
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 16 })
        .divider({ strokeWidth: 0 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BACKGROUND)
  }

  @Builder
  OverviewCard() {
    Column() {
      Text('学习概览')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')
        .margin({ bottom: 16 })

      // 4个指标网格
      Column() {
        Row() {
          this.StatItem('学习天数', `${this.overview.studyDays}`, '天')
          this.StatItem('学习时长', this.formatTime(this.overview.totalMinutes), '')
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)

        Row() {
          this.StatItem('完成关卡', `${this.overview.lessonsCompleted}`, '关')
          this.StatItem('复习单词', `${this.overview.wordsReviewed}`, '词')
        }
        .width('100%')
        .margin({ top: 12 })
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  StatItem(label: string, value: string, unit: string) {
    Column() {
      Text(value)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .height(34)
        .textAlign(TextAlign.Center)

      Text(unit.length > 0 ? unit : ' ')
        .fontSize(12)
        .fontColor(COLORS.TEXT_HINT)
        .opacity(unit.length > 0 ? 1 : 0)
        .height(18)
        .margin({ top: 4 })

      Text(label)
        .fontSize(14)
        .fontColor(COLORS.TEXT_SECONDARY)
        .margin({ top: 8 })
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .width('48%')
    .height(118)
    .padding(12)
    .backgroundColor(COLORS.BACKGROUND)
    .borderRadius(8)
  }

  @Builder
  TodayTaskCard() {
    Column() {
      Text('今日任务')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')
        .margin({ bottom: 16 })

      this.TaskProgressItem('推进1关', this.todayTask.lessonStepDone, 1, COLORS.PRIMARY)
      this.TaskProgressItem('复习20词', this.todayTask.reviewCount, 20, COLORS.SECONDARY)
      this.TaskProgressItem('学习10分', this.todayTask.studyMinutes, 10, COLORS.ACCENT)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  TaskProgressItem(label: string, current: number, target: number, color: string) {
    Column() {
      Row() {
        Text(label)
          .fontSize(14)
          .fontColor(COLORS.TEXT_PRIMARY)

        Blank()

        Text(`${current}/${target}`)
          .fontSize(14)
          .fontColor(COLORS.TEXT_SECONDARY)
      }
      .width('100%')
      .margin({ bottom: 8 })

      Progress({ value: Math.min(current, target), total: target, type: ProgressType.Linear })
        .width('100%')
        .height(6)
        .color(color)
        .backgroundColor(COLORS.BORDER)
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  @Builder
  CalendarCheckInCard() {
    Column() {
      Text('学习打卡日历')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')
        .margin({ bottom: 12 })

      Column() {
        Row() {
          this.MonthNavButton(false)

          Blank()

          Text(this.getDisplayedMonthLabel())
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLORS.TEXT_PRIMARY)

          Blank()

          this.MonthNavButton(true)
        }
        .width('100%')
        .margin({ bottom: 12 })

        this.WeekdayHeader()
        this.CalendarMonthGrid()
      }
      .width('100%')
      .padding(14)
      .backgroundColor(COLORS.BACKGROUND)
      .borderRadius(14)
      .border({ width: 1, color: 'rgba(148,163,184,0.16)' })

      this.SelectedDayDetailCard(this.getSelectedDayStats())
    }
    .width('100%')
    .padding(16)
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  @Builder
  MonthNavButton(isNext: boolean) {
    Button() {
      Image($r('app.media.ic_back'))
        .width(14)
        .height(14)
        .fillColor(COLORS.TEXT_SECONDARY)
        .rotate({ angle: isNext ? 180 : 0 })
    }
    .type(ButtonType.Normal)
    .width(30)
    .height(30)
    .backgroundColor(COLORS.BORDER)
    .borderRadius(8)
    .enabled(!isNext || this.canGoNextMonth())
    .opacity(!isNext || this.canGoNextMonth() ? 1 : 0.4)
    .onClick(() => {
      this.shiftDisplayedMonth(isNext ? 1 : -1);
    })
  }

  @Builder
  WeekdayHeader() {
    Row() {
      ForEach(['日', '一', '二', '三', '四', '五', '六'], (weekday: string) => {
        Text(weekday)
          .fontSize(11)
          .fontColor(COLORS.TEXT_HINT)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)
      })
    }
    .width('100%')
    .margin({ bottom: 8 })
  }

  @Builder
  CalendarMonthGrid() {
    Column({ space: 6 }) {
      ForEach(this.buildMonthCalendar(), (week: CalendarDay[]) => {
        Row({ space: 6 }) {
          ForEach(week, (day: CalendarDay) => {
            this.CalendarMonthCell(day)
          })
        }
        .width('100%')
      })
    }
    .width('100%')
  }

  @Builder
  CalendarMonthCell(day: CalendarDay) {
    if (day.dayOfMonth === 0) {
      Column()
        .layoutWeight(1)
        .aspectRatio(1)
    } else {
      Column() {
        Text(day.dayOfMonth.toString())
          .fontSize(14)
          .fontWeight(this.selectedDate === day.date ? FontWeight.Bold : FontWeight.Medium)
          .fontColor(this.selectedDate === day.date ? '#FFFFFF' : COLORS.TEXT_PRIMARY)

        Row()
          .width(4)
          .height(4)
          .borderRadius(2)
          .backgroundColor(day.studyMinutes > 0
            ? (this.selectedDate === day.date ? '#FFFFFF' : '#22d3ee')
            : Color.Transparent)
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .aspectRatio(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.selectedDate === day.date ? COLORS.PRIMARY : Color.Transparent)
      .borderRadius(12)
      .onClick(() => {
        this.selectedDate = day.date;
      })
    }
  }

  @Builder
  SelectedDayDetailCard(stats: DailyStats) {
    Row() {
      Column()
        .width(3)
        .height(150)
        .backgroundColor(COLORS.PRIMARY)
        .borderRadius(2)
        .margin({ right: 12 })

      Column() {
        Row() {
          Column() {
            Text(this.getSelectedDateLabel())
              .fontSize(22)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)

            Text('学习详情')
              .fontSize(12)
              .fontColor(COLORS.TEXT_HINT)
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)

          Blank()

          Text(this.isDayCompleted(stats) ? '已完成' : '未完成')
            .fontSize(12)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.isDayCompleted(stats) ? '#10b981' : COLORS.TEXT_HINT)
            .padding({ left: 10, right: 10, top: 4, bottom: 4 })
            .backgroundColor(this.isDayCompleted(stats) ? 'rgba(16,185,129,0.16)' : COLORS.BORDER)
            .borderRadius(12)
        }
        .width('100%')

        Row({ space: 12 }) {
          this.DayDetailMetricCard(`${stats.lessonsCompleted}`, '关卡数', COLORS.PRIMARY)
          this.DayDetailMetricCard(`${stats.reviewCount}`, '单词数', '#22d3ee')
        }
        .width('100%')
        .margin({ top: 12 })

        Text(`学习时长 ${stats.studyMinutes} 分钟`)
          .fontSize(12)
          .fontColor(COLORS.TEXT_SECONDARY)
          .margin({ top: 10 })
          .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .alignItems(VerticalAlign.Top)
    .width('100%')
    .padding(14)
    .margin({ top: 14 })
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(14)
    .border({ width: 1, color: 'rgba(148,163,184,0.16)' })
  }

  @Builder
  DayDetailMetricCard(value: string, label: string, color: string) {
    Column() {
      Text(value)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)

      Text(label)
        .fontSize(12)
        .fontColor(COLORS.TEXT_SECONDARY)
        .margin({ top: 3 })
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Start)
    .padding({ left: 14, right: 14, top: 12, bottom: 12 })
    .backgroundColor(COLORS.BACKGROUND)
    .borderRadius(10)
    .border({ width: 1, color: 'rgba(148,163,184,0.14)' })
  }

  @Builder
  VocabularyStatsCard() {
    Column() {
      Text('生词本统计')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')
        .margin({ bottom: 16 })

      Row() {
        this.VocabStatItem('待复习', this.vocabStats.reviewPending, COLORS.WARNING)
        this.VocabStatItem('全部生词', this.vocabStats.totalWords, COLORS.PRIMARY)
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceAround)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(12)
  }

  @Builder
  VocabStatItem(label: string, count: number, color: string) {
    Column() {
      Text(`${count}`)
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)

      Text(label)
        .fontSize(14)
        .fontColor(COLORS.TEXT_SECONDARY)
        .margin({ top: 8 })
    }
  }

  // 辅助方法
  formatTime(minutes: number): string {
    if (minutes < 60) {
      return `${minutes}分`;
    }
    const hours = Math.floor(minutes / 60);
    const mins = minutes % 60;
    if (mins === 0) {
      return `${hours}小时`;
    }
    return `${hours}时${mins}分`;
  }

  getDisplayedMonthLabel(): string {
    return `${this.displayedYear}年${this.displayedMonth + 1}月`;
  }

  canGoNextMonth(): boolean {
    const today = new Date();
    if (this.displayedYear < today.getFullYear()) {
      return true;
    }
    if (this.displayedYear === today.getFullYear() && this.displayedMonth < today.getMonth()) {
      return true;
    }
    return false;
  }

  shiftDisplayedMonth(offset: number): void {
    if (offset > 0 && !this.canGoNextMonth()) {
      return;
    }
    let year = this.displayedYear;
    let month = this.displayedMonth + offset;
    while (month < 0) {
      month += 12;
      year--;
    }
    while (month > 11) {
      month -= 12;
      year++;
    }
    this.displayedYear = year;
    this.displayedMonth = month;

    if (!this.isDateInMonth(this.selectedDate, year, month)) {
      this.selectedDate = this.getDefaultSelectedDateForMonth(year, month);
    }
  }

  isDateInMonth(dateStr: string, year: number, month: number): boolean {
    if (dateStr.length === 0) {
      return false;
    }
    const parts = dateStr.split('-');
    if (parts.length !== 3) {
      return false;
    }
    const y = Number(parts[0]);
    const m = Number(parts[1]) - 1;
    return y === year && m === month;
  }

  getDefaultSelectedDateForMonth(year: number, month: number): string {
    const today = new Date();
    if (year === today.getFullYear() && month === today.getMonth()) {
      return this.formatDateToString(today);
    }
    return `${year}-${String(month + 1).padStart(2, '0')}-01`;
  }

  getDailyStatsMap(): Map<string, DailyStats> {
    const statsMap = new Map<string, DailyStats>();
    for (let i = 0; i < this.weeklyTrend.length; i++) {
      const stat = this.weeklyTrend[i];
      statsMap.set(stat.date, stat);
    }
    return statsMap;
  }

  buildMonthCalendar(): CalendarDay[][] {
    const calendar: CalendarDay[][] = [];
    const statsMap = this.getDailyStatsMap();
    const firstDay = new Date(this.displayedYear, this.displayedMonth, 1);
    const startWeekday = firstDay.getDay();
    const daysInMonth = new Date(this.displayedYear, this.displayedMonth + 1, 0).getDate();
    const cells: CalendarDay[] = [];

    for (let i = 0; i < startWeekday; i++) {
      cells.push(new CalendarDay());
    }

    for (let day = 1; day <= daysInMonth; day++) {
      const date = new Date(this.displayedYear, this.displayedMonth, day);
      const dateStr = this.formatDateToString(date);
      const stats = statsMap.get(dateStr);
      const cell = new CalendarDay();
      cell.date = dateStr;
      cell.dayOfMonth = day;
      cell.studyMinutes = stats ? stats.studyMinutes : 0;
      cell.lessonsCompleted = stats ? stats.lessonsCompleted : 0;
      cell.reviewCount = stats ? stats.reviewCount : 0;
      cells.push(cell);
    }

    while (cells.length % 7 !== 0) {
      cells.push(new CalendarDay());
    }

    for (let i = 0; i < cells.length; i += 7) {
      calendar.push(cells.slice(i, i + 7));
    }

    return calendar;
  }

  getSelectedDayStats(): DailyStats {
    const fallback = new DailyStats();
    fallback.date = this.selectedDate;
    if (this.selectedDate.length === 0) {
      return fallback;
    }
    const statsMap = this.getDailyStatsMap();
    const stats = statsMap.get(this.selectedDate);
    return stats ? stats : fallback;
  }

  isDayCompleted(stats: DailyStats): boolean {
    return stats.studyMinutes > 0 || stats.lessonsCompleted > 0 || stats.reviewCount > 0;
  }

  getSelectedDateLabel(): string {
    if (this.selectedDate.length === 0) {
      return '今日';
    }
    const parts = this.selectedDate.split('-');
    if (parts.length !== 3) {
      return this.selectedDate;
    }
    const month = Number(parts[1]);
    const day = Number(parts[2]);
    return `${month}月${day}日`;
  }

  formatDateToString(date: Date): string {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
}
