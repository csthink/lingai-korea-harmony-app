/**
 * 生词本服务
 * 负责生词的存储、复习算法和本地持久化
 */
import preferences from '@ohos.data.preferences';
import TaskTrackingService from './TaskTrackingService';

// 复习间隔（天）：D0、D1、D3、D7、D14、D30
const REVIEW_INTERVALS: number[] = [0, 1, 3, 7, 14, 30];
const MAX_DAILY_REVIEW: number = 20;
const PREF_NAME: string = 'vocabulary_prefs';
const WORDS_KEY: string = 'vocabulary_words';

/**
 * 生词记录
 */
export class VocabularyWord {
  hangul: string = '';
  meaning: string = '';
  addedTime: number = 0;
  nextReviewTime: number = 0;
  reviewCount: number = 0;
  source: string = 'dictionary';

  constructor(hangul?: string, meaning?: string) {
    if (hangul) this.hangul = hangul;
    if (meaning) this.meaning = meaning;
    this.addedTime = Date.now();
    this.nextReviewTime = Date.now(); // 立即可复习
    this.reviewCount = 0;
  }
}

/**
 * 生词本服务类
 */
export class VocabularyService {
  private static instance: VocabularyService | null = null;
  private words: VocabularyWord[] = [];
  private context: Context | null = null;
  private initialized: boolean = false;

  private constructor() {}

  static getInstance(): VocabularyService {
    if (!VocabularyService.instance) {
      VocabularyService.instance = new VocabularyService();
    }
    return VocabularyService.instance;
  }

  /**
   * 初始化服务
   */
  async init(context: Context): Promise<void> {
    // 确保context总是被设置（不同组件可能传入不同context）
    if (!this.context) {
      this.context = context;
    }
    
    if (this.initialized) return;
    
    await this.loadWords();
    this.initialized = true;
    console.info(`[VocabularyService] Initialized with ${this.words.length} words`);
  }

  /**
   * 强制重新加载数据（用于Tab切换时刷新）
   */
  async forceReload(): Promise<void> {
    if (!this.context) return;
    await this.loadWords();
    console.info(`[VocabularyService] Force reloaded, ${this.words.length} words`);
  }

  /**
   * 从本地加载生词
   */
  private async loadWords(): Promise<void> {
    if (!this.context) return;
    try {
      const pref = await preferences.getPreferences(this.context, PREF_NAME);
      const data = await pref.get(WORDS_KEY, '[]') as string;
      const parsed = JSON.parse(data) as VocabularyWord[];
      this.words = parsed;
    } catch (error) {
      console.error('[VocabularyService] Failed to load words:', JSON.stringify(error));
      this.words = [];
    }
  }

  /**
   * 保存生词到本地
   */
  private async saveWords(): Promise<void> {
    if (!this.context) {
      console.error('[VocabularyService] saveWords failed: context is null!');
      return;
    }
    try {
      const pref = await preferences.getPreferences(this.context, PREF_NAME);
      await pref.put(WORDS_KEY, JSON.stringify(this.words));
      await pref.flush();
      console.info(`[VocabularyService] Saved ${this.words.length} words to preferences`);
    } catch (error) {
      console.error('[VocabularyService] Failed to save words:', JSON.stringify(error));
    }
  }

  /**
   * 清空所有生词数据（用于测试）
   */
  async clearAllWords(): Promise<void> {
    this.words = [];
    await this.saveWords();
    console.info('[VocabularyService] All words cleared');
  }

  /**
   * 添加生词
   * @param source 来源：'dictionary' | 'lesson' | 'selection'
   * @returns true 如果添加成功，false 如果已存在
   */
  async addWord(hangul: string, meaning: string, source: string = 'dictionary'): Promise<boolean> {
    console.info(`[VocabularyService] addWord called: ${hangul}, source: ${source}, context: ${this.context ? 'OK' : 'NULL'}, initialized: ${this.initialized}`);
    
    // 检查是否已存在
    const existingWord = this.words.find(w => w.hangul === hangul);
    if (existingWord) {
      // 如果已掌握，重置它以便重新复习
      if (existingWord.reviewCount >= REVIEW_INTERVALS.length) {
        existingWord.reviewCount = 0;
        existingWord.nextReviewTime = Date.now();
        existingWord.addedTime = Date.now();
        existingWord.source = source;
        await this.saveWords();
        console.info(`[VocabularyService] Reset mastered word: ${hangul}`);
        return true;
      }
      console.info(`[VocabularyService] Word already exists: ${hangul}`);
      return false;
    }

    const word = new VocabularyWord(hangul, meaning);
    word.source = source;
    this.words.unshift(word);
    await this.saveWords();
    console.info(`[VocabularyService] Added word: ${hangul}, source: ${source}, total words: ${this.words.length}`);
    return true;
  }

  /**
   * 获取今日待复习生词（支持分页）
   * @param offset 偏移量，默认0
   */
  getWordsToReview(offset: number = 0): VocabularyWord[] {
    const now = Date.now();
    const dueWords = this.words
      .filter(w => w.nextReviewTime <= now && w.reviewCount < REVIEW_INTERVALS.length)
      .sort((a, b) => b.addedTime - a.addedTime);  // 新添加的排在前面
    return dueWords.slice(offset, offset + MAX_DAILY_REVIEW);
  }

  /**
   * 获取待复习总数
   */
  getReviewCount(): number {
    const now = Date.now();
    return this.words.filter(w => w.nextReviewTime <= now && w.reviewCount < REVIEW_INTERVALS.length).length;
  }

  /**
   * 标记已复习 - 直接从生词本移除
   */
  async markReviewed(hangul: string): Promise<void> {
    const index = this.words.findIndex(w => w.hangul === hangul);
    if (index === -1) return;

    // 直接从生词本移除
    this.words.splice(index, 1);
    await this.saveWords();
    console.info(`[VocabularyService] Marked reviewed and removed: ${hangul}, remaining: ${this.words.length}`);
    
    // 记录今日任务进度
    TaskTrackingService.getInstance().recordReviewComplete(1);
  }
  
  /**
   * 直接标记为已掌握（完成所有复习周期）
   */
  async markMastered(hangul: string): Promise<void> {
    const word = this.words.find(w => w.hangul === hangul);
    if (!word) return;

    word.reviewCount = REVIEW_INTERVALS.length;
    word.nextReviewTime = Number.MAX_SAFE_INTEGER;

    await this.saveWords();
    console.info(`[VocabularyService] Marked mastered: ${hangul}`);
  }

  /**
   * 获取全部生词
   */
  getAllWords(): VocabularyWord[] {
    return [...this.words];
  }

  /**
   * 删除生词
   */
  async deleteWord(hangul: string): Promise<boolean> {
    console.info(`[VocabularyService] deleteWord called: ${hangul}, context: ${this.context ? 'OK' : 'NULL'}`);
    console.info(`[VocabularyService] Current words: ${this.words.map(w => w.hangul).join(', ')}`);
    
    const index = this.words.findIndex(w => w.hangul === hangul);
    if (index === -1) {
      console.info(`[VocabularyService] Word not found for deletion: ${hangul}`);
      return false;
    }

    this.words.splice(index, 1);
    await this.saveWords();
    console.info(`[VocabularyService] Deleted word: ${hangul}, remaining: ${this.words.length}`);
    return true;
  }

  /**
   * 检查生词是否存在
   */
  hasWord(hangul: string): boolean {
    return this.words.some(w => w.hangul === hangul);
  }

  /**
   * 获取生词总数
   */
  getWordCount(): number {
    return this.words.length;
  }

  /**
   * 复活生词（重新移入待复习，并移到列表最前）
   */
  async reviveWord(hangul: string): Promise<void> {
    const index = this.words.findIndex(w => w.hangul === hangul);
    if (index === -1) return;
    
    const word = this.words[index];
    // 重置为待复习状态，nextReviewTime设为0使其排序在最前
    word.reviewCount = 0;
    word.nextReviewTime = 0;
    
    // 移到列表最前（删除原位置，插入头部）
    this.words.splice(index, 1);
    this.words.unshift(word);
    
    await this.saveWords();
    console.info(`[VocabularyService] Revived word: ${hangul}, moved to front`);
  }

  /**
   * 检查生词是否在待复习状态
   */
  isWordDueForReview(hangul: string): boolean {
    const word = this.words.find(w => w.hangul === hangul);
    if (!word) return false;
    return word.nextReviewTime <= Date.now() && word.reviewCount < REVIEW_INTERVALS.length;
  }
}

export default VocabularyService;
