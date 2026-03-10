/**
 * 数据库服务
 * 使用鸿蒙 RDB 存储词表、进度、生词本等数据
 */
import relationalStore from '@ohos.data.relationalStore';
import { DB_CONFIG } from '../utils/Constants';
import { WordEntry, LessonProgress, LessonStatus, WordbookEntry, DailyTask } from '../models/DataModels';

// 数据库表定义
const SQL_CREATE_WORD_ENTRY = `
CREATE TABLE IF NOT EXISTS word_entry (
  id INTEGER PRIMARY KEY,
  hangul TEXT NOT NULL,
  romanization TEXT,
  pos TEXT,
  primary_meaning TEXT NOT NULL,
  senses TEXT,
  collocations TEXT,
  examples TEXT,
  topik_level INTEGER NOT NULL,
  freq_rank INTEGER,
  lesson_id INTEGER NOT NULL
)`;

const SQL_CREATE_LESSON_PROGRESS = `
CREATE TABLE IF NOT EXISTS lesson_progress (
  lesson_id INTEGER PRIMARY KEY,
  level INTEGER NOT NULL,
  status INTEGER DEFAULT 0,
  mastered_count INTEGER DEFAULT 0,
  mastered_words TEXT,
  skipped_words TEXT,
  correct_counts TEXT,
  updated_at INTEGER
)`;

const SQL_CREATE_WORDBOOK = `
CREATE TABLE IF NOT EXISTS wordbook (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  word_id INTEGER NOT NULL,
  source TEXT DEFAULT 'dictionary',
  created_at INTEGER NOT NULL,
  next_review_at INTEGER,
  review_stage INTEGER DEFAULT 0,
  ai_mnemonic TEXT
)`;

const SQL_CREATE_DAILY_TASK = `
CREATE TABLE IF NOT EXISTS daily_task (
  date TEXT PRIMARY KEY,
  lesson_step_done INTEGER DEFAULT 0,
  review_count INTEGER DEFAULT 0,
  study_minutes INTEGER DEFAULT 0,
  updated_at INTEGER
)`;

const SQL_CREATE_STAT_EVENT = `
CREATE TABLE IF NOT EXISTS stat_event (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_name TEXT NOT NULL,
  event_data TEXT,
  created_at INTEGER NOT NULL
)`;

class DatabaseService {
  private static instance: DatabaseService;
  private rdbStore: relationalStore.RdbStore | null = null;
  private context: Context | null = null;

  private constructor() {}

  static getInstance(): DatabaseService {
    if (!DatabaseService.instance) {
      DatabaseService.instance = new DatabaseService();
    }
    return DatabaseService.instance;
  }

  /**
   * 安全关闭结果集，吞掉异常避免掩盖外层真实错误
   */
  private closeQuietly(resultSet: relationalStore.ResultSet | null): void {
    try {
      if (resultSet) {
        resultSet.close();
      }
    } catch (e) {
      console.error('[DatabaseService] closeQuietly error:', e);
    }
  }

  /**
   * 初始化数据库
   */
  async init(context: Context): Promise<void> {
    this.context = context;

    const config: relationalStore.StoreConfig = {
      name: DB_CONFIG.DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1,
    };

    try {
      this.rdbStore = await relationalStore.getRdbStore(context, config);
      
      // 创建表
      await this.rdbStore.executeSql(SQL_CREATE_WORD_ENTRY);
      await this.rdbStore.executeSql(SQL_CREATE_LESSON_PROGRESS);
      await this.rdbStore.executeSql(SQL_CREATE_WORDBOOK);
      await this.rdbStore.executeSql(SQL_CREATE_DAILY_TASK);
      await this.rdbStore.executeSql(SQL_CREATE_STAT_EVENT);

      console.info('Database initialized successfully');
    } catch (error) {
      console.error('Database init failed:', error);
      throw new Error('Database init failed');
    }
  }

  // ==================== 词条操作 ====================

  /**
   * 批量插入词条
   */
  async insertWords(words: WordEntry[]): Promise<void> {
    if (!this.rdbStore) throw new Error('Database not initialized');

    try {
      for (const word of words) {
        const valueBucket: relationalStore.ValuesBucket = {
          id: word.id,
          hangul: word.hangul,
          romanization: word.romanization,
          pos: word.pos,
          primary_meaning: word.primaryMeaning,
          senses: JSON.stringify(word.senses),
          collocations: JSON.stringify(word.collocations),
          examples: JSON.stringify(word.examples),
          topik_level: word.topikLevel,
          freq_rank: word.freqRank,
          lesson_id: word.lessonId,
        };

        await this.rdbStore.insert('word_entry', valueBucket);
      }
    } catch (e) {
      console.error('[DatabaseService] insertWords error:', e);
      throw e instanceof Error ? e : new Error(String(e));
    }
  }

  /**
   * 获取关卡词条
   */
  async getWordsByLesson(lessonId: number): Promise<WordEntry[]> {
    if (!this.rdbStore) {
      console.error('[DatabaseService] getWordsByLesson failed: rdbStore is null');
      return [];
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      const predicates = new relationalStore.RdbPredicates('word_entry');
      predicates.equalTo('lesson_id', lessonId);

      resultSet = await this.rdbStore.query(predicates);
      const words: WordEntry[] = [];

      while (resultSet.goToNextRow()) {
        words.push(this.parseWordEntry(resultSet));
      }

      return words;
    } catch (e) {
      console.error('[DatabaseService] getWordsByLesson error:', e);
      return [];
    } finally {
      this.closeQuietly(resultSet);
    }
  }

  /**
   * 根据韩文查词
   */
  async searchWord(hangul: string): Promise<WordEntry | null> {
    if (!this.rdbStore) {
      console.error('[DatabaseService] searchWord failed: rdbStore is null');
      return null;
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      const predicates = new relationalStore.RdbPredicates('word_entry');
      predicates.equalTo('hangul', hangul);

      resultSet = await this.rdbStore.query(predicates);
      
      if (resultSet.goToNextRow()) {
        return this.parseWordEntry(resultSet);
      }

      return null;
    } catch (e) {
      console.error('[DatabaseService] searchWord error:', e);
      return null;
    } finally {
      this.closeQuietly(resultSet);
    }
  }

  /**
   * 安全解析 WordEntry，字段异常不中断整条记录
   */
  private parseWordEntry(resultSet: relationalStore.ResultSet): WordEntry {
    const word = new WordEntry();

    // 基础字段
    try {
      word.id = resultSet.getLong(resultSet.getColumnIndex('id'));
      word.hangul = resultSet.getString(resultSet.getColumnIndex('hangul'));
      word.romanization = resultSet.getString(resultSet.getColumnIndex('romanization'));
      word.pos = resultSet.getString(resultSet.getColumnIndex('pos'));
      word.primaryMeaning = resultSet.getString(resultSet.getColumnIndex('primary_meaning'));
      word.topikLevel = resultSet.getLong(resultSet.getColumnIndex('topik_level'));
      word.freqRank = resultSet.getLong(resultSet.getColumnIndex('freq_rank'));
      word.lessonId = resultSet.getLong(resultSet.getColumnIndex('lesson_id'));
    } catch (e) {
      console.error('[DatabaseService] parseWordEntry basic fields error:', e);
    }

    // JSON 字段逐个解析，失败使用默认空数组
    try {
      word.senses = JSON.parse(resultSet.getString(resultSet.getColumnIndex('senses')) || '[]');
    } catch (_) {
      word.senses = [];
    }
    try {
      word.collocations = JSON.parse(resultSet.getString(resultSet.getColumnIndex('collocations')) || '[]');
    } catch (_) {
      word.collocations = [];
    }
    try {
      word.examples = JSON.parse(resultSet.getString(resultSet.getColumnIndex('examples')) || '[]');
    } catch (_) {
      word.examples = [];
    }

    return word;
  }

  // ==================== 进度操作 ====================

  /**
   * 获取关卡进度
   */
  async getLessonProgress(lessonId: number): Promise<LessonProgress | null> {
    if (!this.rdbStore) {
      console.error('[DatabaseService] getLessonProgress failed: rdbStore is null');
      return null;
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      const predicates = new relationalStore.RdbPredicates('lesson_progress');
      predicates.equalTo('lesson_id', lessonId);

      resultSet = await this.rdbStore.query(predicates);

      if (resultSet.goToNextRow()) {
        const progress = new LessonProgress();
        progress.lessonId = resultSet.getLong(resultSet.getColumnIndex('lesson_id'));
        progress.level = resultSet.getLong(resultSet.getColumnIndex('level'));
        progress.status = resultSet.getLong(resultSet.getColumnIndex('status')) as LessonStatus;
        progress.masteredCount = resultSet.getLong(resultSet.getColumnIndex('mastered_count'));

        try {
          progress.masteredWordIds = JSON.parse(resultSet.getString(resultSet.getColumnIndex('mastered_words')) || '[]') as number[];
        } catch (_) {
          progress.masteredWordIds = [];
        }

        try {
          progress.skippedWordIds = JSON.parse(resultSet.getString(resultSet.getColumnIndex('skipped_words')) || '[]') as number[];
        } catch (_) {
          progress.skippedWordIds = [];
        }

        // 手动解析 correctCounts
        try {
          const countsJson = resultSet.getString(resultSet.getColumnIndex('correct_counts')) || '{}';
          const countsObj = JSON.parse(countsJson) as Record<string, number>;
          progress.correctCounts = new Map<number, number>();
          const keys = Object.keys(countsObj);
          for (let i = 0; i < keys.length; i++) {
            const key = keys[i];
            progress.correctCounts.set(parseInt(key), countsObj[key]);
          }
        } catch (_) {
          progress.correctCounts = new Map<number, number>();
        }

        progress.updatedAt = resultSet.getLong(resultSet.getColumnIndex('updated_at'));
        return progress;
      }

      return null;
    } catch (e) {
      console.error('[DatabaseService] getLessonProgress error:', e);
      return null;
    } finally {
      this.closeQuietly(resultSet);
    }
  }

  /**
   * 更新关卡进度
   */
  async updateLessonProgress(progress: LessonProgress): Promise<void> {
    if (!this.rdbStore) throw new Error('Database not initialized');

    // 手动序列化 correctCounts Map
    let countsStr = '{';
    let first = true;
    progress.correctCounts.forEach((value: number, key: number) => {
      if (!first) countsStr += ',';
      countsStr += `"${key}":${value}`;
      first = false;
    });
    countsStr += '}';

    const valueBucket: relationalStore.ValuesBucket = {
      lesson_id: progress.lessonId,
      level: progress.level,
      status: progress.status,
      mastered_count: progress.masteredCount,
      mastered_words: JSON.stringify(progress.masteredWordIds),
      skipped_words: JSON.stringify(progress.skippedWordIds),
      correct_counts: countsStr,
      updated_at: Date.now(),
    };

    const predicates = new relationalStore.RdbPredicates('lesson_progress');
    predicates.equalTo('lesson_id', progress.lessonId);

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      const exists = resultSet.goToNextRow();
      // 关闭后再执行写操作
      this.closeQuietly(resultSet);
      resultSet = null;

      if (exists) {
        await this.rdbStore.update(valueBucket, predicates);
      } else {
        await this.rdbStore.insert('lesson_progress', valueBucket);
      }
    } catch (e) {
      console.error('[DatabaseService] updateLessonProgress error:', e);
      throw e instanceof Error ? e : new Error(String(e));
    } finally {
      this.closeQuietly(resultSet);
    }
  }

  // ==================== 生词本操作（已废弃）====================
  // ⚠️ 生词本业务已统一到 VocabularyService（Preferences 存储）
  // 下列方法仅保留供未来 RDB 迁移参考，不参与当前业务链路

  /**
   * @deprecated 请使用 VocabularyService.addWord()
   * 添加到生词本（RDB wordbook 表）
   */
  async addToWordbook(wordId: number, source: string = 'dictionary'): Promise<void> {
    if (!this.rdbStore) throw new Error('Database not initialized');

    try {
      const now = Date.now();
      const valueBucket: relationalStore.ValuesBucket = {
        word_id: wordId,
        source: source,
        created_at: now,
        next_review_at: now,  // D0: 立即复习
        review_stage: 0,
      };

      await this.rdbStore.insert('wordbook', valueBucket);
    } catch (e) {
      console.error('[DatabaseService] addToWordbook error:', e);
      throw e instanceof Error ? e : new Error(String(e));
    }
  }

  /**
   * @deprecated 请使用 VocabularyService.getWordsToReview()
   * 获取待复习词汇（RDB wordbook 表）
   */
  async getWordsToReview(limit: number = 20): Promise<WordbookEntry[]> {
    if (!this.rdbStore) {
      console.error('[DatabaseService] getWordsToReview failed: rdbStore is null');
      return [];
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      const predicates = new relationalStore.RdbPredicates('wordbook');
      predicates.lessThanOrEqualTo('next_review_at', Date.now());
      predicates.orderByAsc('next_review_at');
      predicates.limitAs(limit);

      resultSet = await this.rdbStore.query(predicates);
      const entries: WordbookEntry[] = [];

      while (resultSet.goToNextRow()) {
        try {
          entries.push({
            id: resultSet.getLong(resultSet.getColumnIndex('id')),
            wordId: resultSet.getLong(resultSet.getColumnIndex('word_id')),
            source: resultSet.getString(resultSet.getColumnIndex('source')),
            createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at')),
            nextReviewAt: resultSet.getLong(resultSet.getColumnIndex('next_review_at')),
            reviewStage: resultSet.getLong(resultSet.getColumnIndex('review_stage')),
            aiMnemonic: resultSet.getString(resultSet.getColumnIndex('ai_mnemonic')),
          });
        } catch (rowErr) {
          console.error('[DatabaseService] getWordsToReview parse row error:', rowErr);
        }
      }

      return entries;
    } catch (e) {
      console.error('[DatabaseService] getWordsToReview error:', e);
      return [];
    } finally {
      this.closeQuietly(resultSet);
    }
  }

  // ==================== 每日任务操作 ====================

  /**
   * 获取今日任务
   */
  async getTodayTask(): Promise<DailyTask> {
    const today = new Date().toISOString().split('T')[0];

    if (!this.rdbStore) {
      console.error('[DatabaseService] getTodayTask failed: rdbStore is null');
      const fallback = new DailyTask();
      fallback.date = today;
      fallback.updatedAt = Date.now();
      return fallback;
    }

    console.info('[DatabaseService] getTodayTask for date:', today);

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      const predicates = new relationalStore.RdbPredicates('daily_task');
      predicates.equalTo('date', today);

      resultSet = await this.rdbStore.query(predicates);

      if (resultSet.goToNextRow()) {
        const task = new DailyTask();
        task.date = resultSet.getString(resultSet.getColumnIndex('date'));
        task.lessonStepDone = resultSet.getLong(resultSet.getColumnIndex('lesson_step_done'));
        task.reviewCount = resultSet.getLong(resultSet.getColumnIndex('review_count'));
        task.studyMinutes = resultSet.getLong(resultSet.getColumnIndex('study_minutes'));
        task.updatedAt = resultSet.getLong(resultSet.getColumnIndex('updated_at'));
        console.info('[DatabaseService] Found existing task:', JSON.stringify(task));
        return task;
      }

      // 返回默认任务
      const defaultTask = new DailyTask();
      defaultTask.date = today;
      defaultTask.lessonStepDone = 0;
      defaultTask.reviewCount = 0;
      defaultTask.studyMinutes = 0;
      defaultTask.updatedAt = Date.now();
      console.info('[DatabaseService] Created default task:', JSON.stringify(defaultTask));
      return defaultTask;
    } catch (e) {
      console.error('[DatabaseService] getTodayTask error:', e);
      const fallback = new DailyTask();
      fallback.date = today;
      fallback.updatedAt = Date.now();
      return fallback;
    } finally {
      this.closeQuietly(resultSet);
    }
  }

  /**
   * 更新今日任务
   */
  async updateTodayTask(task: DailyTask): Promise<void> {
    if (!this.rdbStore) {
      console.error('[DatabaseService] updateTodayTask failed: rdbStore is null');
      throw new Error('Database not initialized');
    }

    console.info('[DatabaseService] updateTodayTask:', JSON.stringify(task));

    const valueBucket: relationalStore.ValuesBucket = {
      date: task.date,
      lesson_step_done: task.lessonStepDone,
      review_count: task.reviewCount,
      study_minutes: task.studyMinutes,
      updated_at: Date.now(),
    };

    const predicates = new relationalStore.RdbPredicates('daily_task');
    predicates.equalTo('date', task.date);

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      resultSet = await this.rdbStore.query(predicates);
      const exists = resultSet.goToNextRow();
      // 关闭后再执行写操作
      this.closeQuietly(resultSet);
      resultSet = null;

      if (exists) {
        await this.rdbStore.update(valueBucket, predicates);
        console.info('[DatabaseService] Updated existing task');
      } else {
        await this.rdbStore.insert('daily_task', valueBucket);
        console.info('[DatabaseService] Inserted new task');
      }
    } catch (e) {
      console.error('[DatabaseService] updateTodayTask error:', e);
      throw e instanceof Error ? e : new Error(String(e));
    } finally {
      this.closeQuietly(resultSet);
    }
  }

  /**
   * 获取所有每日任务记录（用于统计）
   */
  async getAllDailyTasks(): Promise<DailyTask[]> {
    if (!this.rdbStore) {
      console.error('[DatabaseService] getAllDailyTasks failed: rdbStore is null');
      return [];
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      const tasks: DailyTask[] = [];
      const predicates = new relationalStore.RdbPredicates('daily_task');
      resultSet = await this.rdbStore.query(predicates);

      while (resultSet.goToNextRow()) {
        try {
          const task = new DailyTask();
          task.date = resultSet.getString(resultSet.getColumnIndex('date'));
          task.lessonStepDone = resultSet.getLong(resultSet.getColumnIndex('lesson_step_done'));
          task.reviewCount = resultSet.getLong(resultSet.getColumnIndex('review_count'));
          task.studyMinutes = resultSet.getLong(resultSet.getColumnIndex('study_minutes'));
          task.updatedAt = resultSet.getLong(resultSet.getColumnIndex('updated_at'));
          tasks.push(task);
        } catch (rowErr) {
          console.error('[DatabaseService] getAllDailyTasks parse row error:', rowErr);
        }
      }

      return tasks;
    } catch (e) {
      console.error('[DatabaseService] getAllDailyTasks error:', e);
      return [];
    } finally {
      this.closeQuietly(resultSet);
    }
  }

  /**
   * 获取最近N天的每日任务记录
   */
  async getRecentDailyTasks(days: number = 7): Promise<DailyTask[]> {
    if (!this.rdbStore) {
      console.error('[DatabaseService] getRecentDailyTasks failed: rdbStore is null');
      return [];
    }

    let resultSet: relationalStore.ResultSet | null = null;
    try {
      const tasks: DailyTask[] = [];
      const predicates = new relationalStore.RdbPredicates('daily_task');
      predicates.orderByDesc('date').limitAs(days);
      resultSet = await this.rdbStore.query(predicates);

      while (resultSet.goToNextRow()) {
        try {
          const task = new DailyTask();
          task.date = resultSet.getString(resultSet.getColumnIndex('date'));
          task.lessonStepDone = resultSet.getLong(resultSet.getColumnIndex('lesson_step_done'));
          task.reviewCount = resultSet.getLong(resultSet.getColumnIndex('review_count'));
          task.studyMinutes = resultSet.getLong(resultSet.getColumnIndex('study_minutes'));
          task.updatedAt = resultSet.getLong(resultSet.getColumnIndex('updated_at'));
          tasks.push(task);
        } catch (rowErr) {
          console.error('[DatabaseService] getRecentDailyTasks parse row error:', rowErr);
        }
      }

      return tasks;
    } catch (e) {
      console.error('[DatabaseService] getRecentDailyTasks error:', e);
      return [];
    } finally {
      this.closeQuietly(resultSet);
    }
  }
}

export default DatabaseService;
