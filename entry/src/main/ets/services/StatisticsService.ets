/**
 * 统计服务
 * 提供学习数据统计与聚合
 */
import DatabaseService from './DatabaseService';
import { VocabularyService } from './VocabularyService';
import { LearningOverview, DailyStats, VocabStats } from '../models/DataModels';

class StatisticsService {
  private static instance: StatisticsService;
  private dbService: DatabaseService;
  private vocabularyService: VocabularyService;

  private constructor() {
    this.dbService = DatabaseService.getInstance();
    this.vocabularyService = VocabularyService.getInstance();
  }

  static getInstance(): StatisticsService {
    if (!StatisticsService.instance) {
      StatisticsService.instance = new StatisticsService();
    }
    return StatisticsService.instance;
  }

  /**
   * 获取学习概览数据
   */
  async getOverview(): Promise<LearningOverview> {
    const overview = new LearningOverview();
    
    try {
      const allTasks = await this.dbService.getAllDailyTasks();
      
      const studyDaysSet = new Set<string>();
      let totalMinutes = 0;
      let lessonsCompleted = 0;
      let wordsReviewed = 0;

      for (let i = 0; i < allTasks.length; i++) {
        const task = allTasks[i];
        studyDaysSet.add(task.date);
        totalMinutes += task.studyMinutes;
        lessonsCompleted += task.lessonStepDone;
        wordsReviewed += task.reviewCount;
      }

      overview.studyDays = studyDaysSet.size;
      overview.totalMinutes = totalMinutes;
      overview.lessonsCompleted = lessonsCompleted;
      overview.wordsReviewed = wordsReviewed;
    } catch (error) {
      console.error('Failed to get overview:', error);
    }
    
    return overview;
  }

  /**
   * 获取最近30日学习数据（用于日历打卡）
   */
  async getMonthlyTrend(): Promise<DailyStats[]> {
    const trends: DailyStats[] = [];
    
    try {
      const recentTasks = await this.dbService.getRecentDailyTasks(30);
      
      for (let i = 0; i < recentTasks.length; i++) {
        const task = recentTasks[i];
        const stats = new DailyStats();
        stats.date = task.date;
        stats.studyMinutes = task.studyMinutes;
        stats.lessonsCompleted = task.lessonStepDone;
        stats.reviewCount = task.reviewCount;
        trends.push(stats);
      }
      
      // 反转数组，使日期从旧到新排列
      trends.reverse();
    } catch (error) {
      console.error('Failed to get monthly trend:', error);
    }
    
    return trends;
  }

  /**
   * 获取生词本统计
   */
  async getVocabularyStats(): Promise<VocabStats> {
    const stats = new VocabStats();
    
    try {
      const allWords = await this.vocabularyService.getAllWords();
      stats.totalWords = allWords.length;
      
      // 待复习的单词：nextReviewTime <= 当前时间
      const now = Date.now();
      stats.reviewPending = allWords.filter(word => word.nextReviewTime <= now).length;
    } catch (error) {
      console.error('Failed to get vocabulary stats:', error);
    }
    
    return stats;
  }

  /**
   * 格式化学习时长为可读格式
   */
  formatStudyTime(minutes: number): string {
    if (minutes < 60) {
      return `${minutes}分钟`;
    }
    const hours = Math.floor(minutes / 60);
    const mins = minutes % 60;
    if (mins === 0) {
      return `${hours}小时`;
    }
    return `${hours}小时${mins}分钟`;
  }

  /**
   * 获取今天的日期字符串 YYYY-MM-DD
   */
  getTodayDateString(): string {
    const now = new Date();
    const year = now.getFullYear();
    const month = String(now.getMonth() + 1).padStart(2, '0');
    const day = String(now.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
}

export default StatisticsService;

