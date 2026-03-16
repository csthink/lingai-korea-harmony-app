/**
 * 任务追踪服务
 * 追踪今日任务进度：推进关卡、复习单词、学习时长
 */
import DatabaseService from './DatabaseService';
import { DailyTask } from '../models/DataModels';

/**
 * 任务进度数据
 */
export class TaskProgress {
  current: number = 0;
  total: number = 1;

  constructor(current: number = 0, total: number = 1) {
    this.current = current;
    this.total = total;
  }
}

class TaskTrackingService {
  private static instance: TaskTrackingService;
  private dbService: DatabaseService;
  private currentTask: DailyTask = new DailyTask();
  private studyStartTime: number = 0;
  private isStudying: boolean = false;
  private initialized: boolean = false;
  private onUpdateCallback: ((task: DailyTask) => void) | null = null;
  private updateSubscribers: Array<(task: DailyTask) => void> = [];

  private constructor() {
    this.dbService = DatabaseService.getInstance();
  }

  static getInstance(): TaskTrackingService {
    if (!TaskTrackingService.instance) {
      TaskTrackingService.instance = new TaskTrackingService();
    }
    return TaskTrackingService.instance;
  }

  /**
   * 设置任务更新回调
   */
  setOnUpdateCallback(callback: ((task: DailyTask) => void) | null): void {
    this.onUpdateCallback = callback;
  }

  /**
   * 订阅任务更新，支持首页/我的等多个组件同时监听
   */
  subscribeOnUpdate(callback: (task: DailyTask) => void): () => void {
    this.updateSubscribers.push(callback);
    return () => {
      this.updateSubscribers = this.updateSubscribers.filter((item: (task: DailyTask) => void) => item !== callback);
    };
  }

  /**
   * 初始化服务，加载今日任务
   */
  async init(context?: Context): Promise<void> {
    if (this.initialized) return;
    
    try {
      // 如果传入context，确保数据库已初始化
      if (context) {
        await this.dbService.init(context);
      }
      this.currentTask = await this.dbService.getTodayTask();
      this.initialized = true;
      console.info('TaskTrackingService initialized, task:', JSON.stringify(this.currentTask));
    } catch (error) {
      console.error('TaskTrackingService init failed:', error);
    }
  }

  /**
   * 获取当前任务状态
   */
  getCurrentTask(): DailyTask {
    return this.currentTask;
  }

  /**
   * 刷新任务数据（用于 Tab 切换时）
   */
  async refreshTask(): Promise<DailyTask> {
    this.currentTask = await this.dbService.getTodayTask();
    this.notifyTaskUpdated();
    return this.currentTask;
  }

  /**
   * 记录关卡步骤完成
   * 每次进入关卡并完成任意预习/练习步骤时调用
   */
  async recordLessonStep(): Promise<void> {
    if (!this.initialized) await this.init();
    
    // 累加关卡完成次数
    this.currentTask.lessonStepDone += 1;
    await this.saveTask();
    console.info('Lesson step recorded, lessonStepDone:', this.currentTask.lessonStepDone);
  }

  /**
   * 记录复习完成
   * @param count 本次完成的复习数量
   */
  async recordReviewComplete(count: number = 1): Promise<void> {
    if (!this.initialized) await this.init();
    
    this.currentTask.reviewCount += count;
    await this.saveTask();
    console.info('Review recorded, reviewCount:', this.currentTask.reviewCount);
  }

  /**
   * 开始学习计时
   */
  startStudyTimer(): void {
    if (this.isStudying) return;
    
    this.studyStartTime = Date.now();
    this.isStudying = true;
    console.info('Study timer started');
  }

  /**
   * 暂停学习计时并保存时长
   */
  async pauseStudyTimer(): Promise<void> {
    if (!this.isStudying) return;
    
    const elapsed = Date.now() - this.studyStartTime;
    const minutes = Math.floor(elapsed / 60000);
    
    if (minutes > 0) {
      if (!this.initialized) await this.init();
      this.currentTask.studyMinutes += minutes;
      await this.saveTask();
      console.info('Study timer paused, added minutes:', minutes, 'total:', this.currentTask.studyMinutes);
    }
    
    this.isStudying = false;
    this.studyStartTime = 0;
  }

  /**
   * 检查任务是否完成
   */
  isTaskCompleted(taskType: string): boolean {
    if (taskType === 'lesson') {
      return this.currentTask.lessonStepDone >= 1;
    } else if (taskType === 'review') {
      return this.currentTask.reviewCount >= 20;
    } else if (taskType === 'study') {
      return this.currentTask.studyMinutes >= 10;
    }
    return false;
  }

  /**
   * 获取任务进度
   */
  getTaskProgress(taskType: string): TaskProgress {
    if (taskType === 'lesson') {
      return new TaskProgress(Math.min(this.currentTask.lessonStepDone, 1), 1);
    } else if (taskType === 'review') {
      return new TaskProgress(Math.min(this.currentTask.reviewCount, 20), 20);
    } else if (taskType === 'study') {
      return new TaskProgress(Math.min(this.currentTask.studyMinutes, 10), 10);
    }
    return new TaskProgress(0, 1);
  }

  /**
   * 计算连续学习天数（从今天往前数，有任意学习活动的连续天数）
   * 活动定义：lessonStepDone > 0 或 reviewCount > 0 或 studyMinutes > 0
   */
  async getStreakDays(): Promise<number> {
    try {
      const recentTasks = await this.dbService.getRecentDailyTasks(30);
      if (recentTasks.length === 0) return 0;

      // 按日期降序排列（getRecentDailyTasks 已 orderByDesc）
      let streak = 0;
      const today = new Date();

      for (let i = 0; i < recentTasks.length; i++) {
        const task = recentTasks[i];
        const hasActivity = task.lessonStepDone > 0 || task.reviewCount > 0 || task.studyMinutes > 0;

        // 计算期望日期（今天 - i 天）
        const expectedDate = new Date(today);
        expectedDate.setDate(today.getDate() - i);
        const expectedDateStr = expectedDate.toISOString().split('T')[0];

        if (task.date === expectedDateStr && hasActivity) {
          streak++;
        } else {
          break;
        }
      }
      return streak;
    } catch (error) {
      console.error('getStreakDays failed:', error);
      return 0;
    }
  }

  /**
   * 计算今日学习进度（0-100）
   * 三个子目标各占 1/3 权重：
   *   - 关卡学习 (lessonStepDone >= 1)
   *   - 复习 (reviewCount >= 20)
   *   - 学习时长 (studyMinutes >= 10)
   */
  calculateTodayProgress(): number {
    let progress = 0;
    // 关卡进度（完成 1 步即满分）
    progress += Math.min(this.currentTask.lessonStepDone, 1) * 33;
    // 复习进度
    progress += Math.min(this.currentTask.reviewCount / 20, 1) * 33;
    // 学习时长进度
    progress += Math.min(this.currentTask.studyMinutes / 10, 1) * 34;
    return Math.round(progress);
  }

  /**
   * 保存任务到数据库
   */
  private async saveTask(): Promise<void> {
    try {
      await this.dbService.updateTodayTask(this.currentTask);
      this.notifyTaskUpdated();
    } catch (error) {
      console.error('Failed to save task:', error);
    }
  }

  private notifyTaskUpdated(): void {
    if (this.onUpdateCallback) {
      this.onUpdateCallback(this.currentTask);
    }

    for (let i = 0; i < this.updateSubscribers.length; i++) {
      try {
        this.updateSubscribers[i](this.currentTask);
      } catch (error) {
        console.error('Task update subscriber failed:', error);
      }
    }
  }
}

export default TaskTrackingService;
