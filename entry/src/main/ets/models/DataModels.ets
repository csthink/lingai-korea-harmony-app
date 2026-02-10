/**
 * LingAI 数据模型定义
 * 适配 ArkTS 严格模式 - 使用 class 替代 interface + object literal
 */

/**
 * 例句
 */
export class ExampleSentence {
  ko: string = '';
  zh: string = '';

  constructor(ko: string = '', zh: string = '') {
    this.ko = ko;
    this.zh = zh;
  }
}

/**
 * 词义项
 */
export class Sense {
  meaning: string = '';
  examples: ExampleSentence[] = [];

  constructor(meaning: string = '', examples: ExampleSentence[] = []) {
    this.meaning = meaning;
    this.examples = examples;
  }
}

/**
 * 词条
 */
export class WordEntry {
  id: number = 0;
  hangul: string = '';
  romanization: string = '';
  pos: string = '';
  primaryMeaning: string = '';
  senses: Sense[] = [];
  collocations: string[] = [];
  examples: ExampleSentence[] = [];
  topikLevel: number = 1;
  freqRank: number = 0;
  lessonId: number = 1;

  constructor() {}
}

/**
 * 关卡状态
 */
export enum LessonStatus {
  LOCKED = 0,
  IN_PROGRESS = 1,
  COMPLETED = 2,
}

/**
 * 关卡信息
 */
export class LessonInfo {
  lessonId: number = 0;
  level: number = 1;
  title: string = '';
  wordCount: number = 50;
  status: LessonStatus = LessonStatus.LOCKED;
  masteredCount: number = 0;
  progress: number = 0;

  constructor() {}
}

/**
 * 关卡进度
 */
export class LessonProgress {
  lessonId: number = 0;
  level: number = 1;
  status: LessonStatus = LessonStatus.LOCKED;
  masteredCount: number = 0;
  masteredWordIds: number[] = [];
  skippedWordIds: number[] = [];
  correctCounts: Map<number, number> = new Map();
  updatedAt: number = 0;

  constructor() {}
}

/**
 * 练习题选项
 */
export class QuizOption {
  id: string = '';
  text: string = '';
  isCorrect: boolean = false;

  constructor(id: string = '', text: string = '', isCorrect: boolean = false) {
    this.id = id;
    this.text = text;
    this.isCorrect = isCorrect;
  }
}

/**
 * 题干
 */
export class QuizStem {
  display: string = '';
  audioUrl: string = '';

  constructor(display: string = '', audioUrl: string = '') {
    this.display = display;
    this.audioUrl = audioUrl;
  }
}

/**
 * 练习题
 */
export class Quiz {
  type: string = '';
  wordId: number = 0;
  stem: QuizStem = new QuizStem();
  options: QuizOption[] = [];
  context: string = '';

  constructor() {}
}

/**
 * 用户设置
 */
export class UserSettings {
  notificationEnabled: boolean = false;
  notificationTime: string = '09:00';
  autoDownloadCount: number = 3;

  constructor() {}
}

/**
 * 学习状态
 */
export class LearningState {
  currentLevel: number = 1;
  currentLesson: number = 1;
  lastOpenTime: number = 0;

  constructor() {}
}

/**
 * 每日任务
 */
export class DailyTask {
  date: string = '';
  lessonStepDone: number = 0;
  reviewCount: number = 0;
  studyMinutes: number = 0;
  updatedAt: number = 0;

  constructor() {}
}

/**
 * 生词本条目
 */
export class WordbookEntry {
  id: number = 0;
  wordId: number = 0;
  source: string = 'dictionary';
  createdAt: number = 0;
  nextReviewAt: number = 0;
  reviewStage: number = 0;
  aiMnemonic: string = '';

  constructor() {}
}

/**
 * 学习概览统计
 */
export class LearningOverview {
  studyDays: number = 0;          // 学习天数
  totalMinutes: number = 0;       // 总学习时长（分钟）
  lessonsCompleted: number = 0;   // 完成关卡数
  wordsReviewed: number = 0;      // 复习单词数

  constructor() {}
}

/**
 * 每日统计数据
 */
export class DailyStats {
  date: string = '';              // 日期 YYYY-MM-DD
  studyMinutes: number = 0;       // 学习时长（分钟）
  lessonsCompleted: number = 0;   // 完成关卡数
  reviewCount: number = 0;        // 复习单词数

  constructor() {}
}

/**
 * 生词本统计
 */
export class VocabStats {
  reviewPending: number = 0;      // 待复习单词数
  totalWords: number = 0;         // 全部生词数

  constructor() {}
}

/**
 * 词典 AI 响应 - 详细解析
 */
export class MeaningDetail {
  type: string = '';       // 含义类型（具体义/抽象义等）
  explanation: string = ''; // 详细解释

  constructor(type: string = '', explanation: string = '') {
    this.type = type;
    this.explanation = explanation;
  }
}

export class Collocation {
  phrase: string = '';     // 韩语搭配
  meaning: string = '';    // 中文含义
  exampleKo: string = '';  // 韩语例句
  exampleZh: string = '';  // 中文翻译

  constructor() {}
}

export class SynonymWord {
  word: string = '';       // 韩语词
  meaning: string = '';    // 中文含义
  difference: string = ''; // 与原词区别

  constructor() {}
}

export class RelatedWord {
  word: string = '';
  meaning: string = '';

  constructor() {}
}

export class CategoryExample {
  ko: string = '';
  zh: string = '';
  category: string = '';   // 场景分类

  constructor() {}
}

export class DictAIResponse {
  aiMeaning: string = '';              // 主要释义
  wordType: string = '';               // 词性
  hanja: string = '';                  // 对应汉字
  composition: string = '';            // 词语构成
  meanings: MeaningDetail[] = [];      // 含义详解
  collocations: Collocation[] = [];    // 常用搭配
  aiExamples: CategoryExample[] = [];  // 分类例句
  synonyms: SynonymWord[] = [];        // 近义词（含区别）
  antonyms: RelatedWord[] = [];        // 反义词
  relatedWords: RelatedWord[] = [];    // 扩展词汇
  tips: string = '';                   // 实用知识

  constructor() {}
}

/**
 * 词典搜索响应
 */
export class DictSearchResponse {
  source: string = '';  // 'local' | 'ai'
  query: string = '';
  direction: string = '';  // 'ko2zh' | 'zh2ko'
  results: WordEntry[] = [];
  aiSupplement: DictAIResponse | null = null;

  constructor() {}
}
