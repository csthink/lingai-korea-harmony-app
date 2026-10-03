/**
 * 学习统计页面
 * 展示学习数据概览、趋势和进度
 */
import router from '@ohos.router';
import { COLORS } from '../utils/Constants';
import { UI } from '../utils/UiTokens';
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
  @State trendDays: number = 7;
  @State trendChartWidth: number = 0;
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
          .width(UI.TOUCH_MIN)
          .height(UI.TOUCH_MIN)
          .padding(10)
          .backgroundColor(COLORS.SURFACE)
          .border({ width: 1, color: COLORS.BORDER })
          .borderRadius(15).clip(true)
          .fillColor(COLORS.TEXT_PRIMARY)
          .onClick(() => {
            router.back();
          })

        Text('学习统计')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .margin({ left: 12 })

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
        List() {
          // 模块1：学习概览卡片
          ListItem() {
            this.TrendCard()
          }
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
        .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 4, bottom: 32 })
        .divider({ strokeWidth: 0 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BACKGROUND)
  }

  private getTrendData(): DailyStats[] {
    const map = this.getDailyStatsMap();
    const values: DailyStats[] = [];
    for (let offset = this.trendDays - 1; offset >= 0; offset--) {
      const day = new Date();
      day.setDate(day.getDate() - offset);
      const date = this.formatDateToString(day);
      const value = map.get(date) || new DailyStats();
      value.date = date;
      values.push(value);
    }
    return values;
  }

  private getTrendMinutes(): number {
    return this.getTrendData().reduce((total: number, day: DailyStats) => total + day.studyMinutes, 0);
  }

  private getBarHeight(minutes: number): number {
    let maximum = 1;
    this.getTrendData().forEach((day: DailyStats) => {
      maximum = Math.max(maximum, day.studyMinutes);
    });
    return Math.max(2, Math.round(minutes / maximum * 100));
  }

  @Builder
  TrendCard() {
    Column({ space: 20 }) {
      Row({ space: 4 }) {
        this.PeriodButton(7, '最近 7 天')
        this.PeriodButton(30, '最近 30 天')
      }
      .width('100%')
      .padding(4)
      .backgroundColor(UI.GREEN_SOFT)
      .borderRadius(12)
      Column({ space: 8 }) {
        Text('学习时长').fontSize(13).fontColor(COLORS.TEXT_SECONDARY)
        Row({ space: 8 }) {
          Text(this.getTrendMinutes().toString())
            .fontSize(38)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text('分钟').fontSize(14).fontColor(COLORS.TEXT_SECONDARY)
        }
        .alignItems(VerticalAlign.Bottom)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      Row({ space: this.trendDays === 7 ? 10 : 3 }) {
        ForEach(this.getTrendData(), (day: DailyStats, index: number) => {
          Column({ space: 7 }) {
            if (this.trendDays === 7) {
              Text(day.studyMinutes.toString()).fontSize(11).fontColor(COLORS.TEXT_SECONDARY)
            }
            Row()
              .width('100%')
              .height(this.getBarHeight(day.studyMinutes))
              .backgroundColor(day.studyMinutes > 0 ? COLORS.PRIMARY : COLORS.BORDER)
              .borderRadius(4)
            if (this.trendDays === 7) {
              Text(day.date.substring(8))
                .fontSize(10).fontColor(COLORS.TEXT_SECONDARY).height(16)
            } else {
              Blank().height(16)
            }
          }
          .layoutWeight(1)
          .height(146)
          .justifyContent(FlexAlign.End)
          .accessibilityText(`${day.date}，学习 ${day.studyMinutes} 分钟`)
        }, (day: DailyStats) => `${this.trendDays}:${day.date}:${day.studyMinutes}`)
      }
      .width('100%')
      .onAreaChange((_oldArea, newArea) => {
        const width = Number(newArea.width);
        if (Number.isFinite(width) && width > 0 && width !== this.trendChartWidth) {
          this.trendChartWidth = width;
        }
      })
      .overlay(this.TrendDateLabels(), { align: Alignment.BottomStart })
      Text('统计来自本机学习记录，空白日期按 0 分钟显示。')
        .fontSize(12)
        .lineHeight(19)
        .fontColor(COLORS.TEXT_SECONDARY)
        .width('100%')
    }
    .width('100%')
    .padding({ top: 8, bottom: 12 })
  }

  private trendLabelX(index: number): number {
    const barWidth = Math.max(0, (this.trendChartWidth - 29 * 3) / 30);
    const centeredX = index * (barWidth + 3) + barWidth / 2 - 16;
    return Math.max(0, Math.min(centeredX, this.trendChartWidth - 32));
  }

  @Builder
  TrendDateLabels() {
    if (this.trendDays === 30 && this.trendChartWidth > 0) {
      Stack({ alignContent: Alignment.TopStart }) {
        ForEach(this.getTrendData(), (day: DailyStats, index: number) => {
          if (index % 5 === 0) {
            Text(day.date.substring(8))
              .fontSize(10).fontColor(COLORS.TEXT_SECONDARY)
              .width(32).height(16).textAlign(TextAlign.Center)
              // Match each bar's center, including the 29 three-vp gaps in the row.
              .position({ x: this.trendLabelX(index), y: 0 })
          }
        }, (day: DailyStats) => `label:${day.date}`)
      }.width('100%').height(16).hitTestBehavior(HitTestMode.None)
    }
  }

  @Builder
  PeriodButton(days: number, label: string) {
    Button(label)
      .type(ButtonType.Normal)
      .layoutWeight(1)
      .height(UI.TOUCH_MIN)
      .fontSize(13)
      .fontColor(this.trendDays === days ? COLORS.PRIMARY : COLORS.TEXT_SECONDARY)
      .backgroundColor(this.trendDays === days ? COLORS.SURFACE : Color.Transparent)
      .borderRadius(8)
      .onClick(() => { this.trendDays = days; })
  }

  @Builder
  OverviewCard() {
    Column({ space: 20 }) {
      Column({ space: 12 }) {
        Row() {
          this.StatItem('学习天数', `${this.overview.studyDays}`, '天')
          this.StatItem('学习时长', this.formatTime(this.overview.totalMinutes), '')
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        Row() {
          this.StatItem('学习步骤', `${this.overview.lessonsCompleted}`, '步')
          this.StatItem('复习单词', `${this.overview.wordsReviewed}`, '词')
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .backgroundColor(COLORS.SURFACE)
    .margin({ bottom: 20 })
  }

  @Builder
  StatItem(label: string, value: string, unit: string) {
    Column({ space: 8 }) {
      Row({ space: 4 }) {
        Text(value)
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.PRIMARY)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)
        Text(unit.length > 0 ? unit : ' ')
          .fontSize(12)
          .fontColor(COLORS.TEXT_SECONDARY)
          .opacity(unit.length > 0 ? 1 : 0)
      }
      .width('100%')
      Text(label)
        .fontSize(13)
        .fontColor(COLORS.TEXT_SECONDARY)
    }
    .alignItems(HorizontalAlign.Start)
    .justifyContent(FlexAlign.Center)
    .width('48%')
    .height(96)
    .padding(16)
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(16)
  }

  @Builder
  TodayTaskCard() {
    Column({ space: 14 }) {
      Text('今日任务')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')

      this.TaskProgressItem('完成一个关卡步骤', this.todayTask.lessonStepDone, 1, COLORS.PRIMARY)
      this.TaskProgressItem('复习单词', this.todayTask.reviewCount, 20, COLORS.SECONDARY)
      this.TaskProgressItem('学习时长（分钟）', this.todayTask.studyMinutes, 10, COLORS.ACCENT)
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .backgroundColor(COLORS.SURFACE)
    .margin({ bottom: 20 })
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
        .color(current >= target ? COLORS.PRIMARY : current > 0 ? UI.BLUE : COLORS.BORDER)
        .backgroundColor(UI.GREEN_SOFT)
    }
    .width('100%')
    .margin({ bottom: 12 })
  }

  @Builder
  CalendarCheckInCard() {
    Column() {
      Text('学习日历')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
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
      .border({ width: 1, color: COLORS.BORDER })
      .borderRadius(14).clip(true)

      // 按日期与数值重建详情视图，避免保留初次传入的数据。
      ForEach([this.getSelectedDayStats()], (stats: DailyStats) => {
        this.SelectedDayDetailCard(stats)
      }, (stats: DailyStats) => `${stats.date}:${stats.lessonsCompleted}:${stats.reviewCount}:${stats.studyMinutes}`)
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .backgroundColor(COLORS.SURFACE)
    .margin({ bottom: 20 })
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
    .width(UI.TOUCH_MIN)
    .height(UI.TOUCH_MIN)
    .backgroundColor(UI.BLUE_SOFT)
    .borderRadius(14)
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
          .fontColor(this.selectedDate === day.date ? UI.ON_BLUE : COLORS.TEXT_PRIMARY)

        Row()
          .width(4)
          .height(4)
          .borderRadius(2)
          .backgroundColor(day.studyMinutes > 0
            ? (this.selectedDate === day.date ? UI.ON_BLUE : UI.BLUE)
            : Color.Transparent)
          .margin({ top: 4 })
      }
      .layoutWeight(1)
      .aspectRatio(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor(this.selectedDate === day.date ? UI.BLUE : Color.Transparent)
      .borderRadius(12)
      .onClick(() => {
        this.selectedDate = day.date;
      })
    }
  }

  @Builder
  SelectedDayDetailCard(stats: DailyStats) {
    Column({ space: 16 }) {
      Row() {
        Column({ space: 4 }) {
          Text(this.getSelectedDateLabel())
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text('学习详情')
            .fontSize(13)
            .fontColor(COLORS.TEXT_SECONDARY)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.isDayCompleted(stats) ? '已完成' : '未完成')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.isDayCompleted(stats) ? COLORS.PRIMARY : COLORS.TEXT_SECONDARY)
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(this.isDayCompleted(stats) ? UI.GREEN_SOFT : UI.SURFACE_MUTED)
          .borderRadius(10)
      }
      .width('100%')

      Row({ space: 12 }) {
        this.DayDetailMetricCard(`${stats.lessonsCompleted}`, '学习步骤', COLORS.PRIMARY)
        this.DayDetailMetricCard(`${stats.reviewCount}`, '复习单词', UI.BLUE)
      }
      .width('100%')

      Text(`学习时长 ${stats.studyMinutes} 分钟`)
        .fontSize(13)
        .fontColor(COLORS.TEXT_SECONDARY)
        .width('100%')
    }
    .alignItems(HorizontalAlign.Start)
    .width('100%')
    .padding(18)
    .margin({ top: 16 })
    .backgroundColor(UI.GREEN_SOFT)
    .borderRadius(18)
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
    .border({ width: 1, color: COLORS.BORDER })
    .borderRadius(10).clip(true)
  }

  @Builder
  VocabularyStatsCard() {
    Column() {
      Text('生词本统计')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
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
    .padding({ top: 16, bottom: 16 })
    .backgroundColor(COLORS.SURFACE)
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
