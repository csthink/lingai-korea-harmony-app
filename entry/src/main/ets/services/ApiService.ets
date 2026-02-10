/**
 * API 服务层
 * 负责与后端 API 通信
 * 适配 ArkTS 严格模式
 */
import http from '@ohos.net.http';
import { API_BASE_URL } from '../utils/Constants';
import { DictAIResponse, DictSearchResponse, WordEntry, ExampleSentence, Sense, MeaningDetail, Collocation, SynonymWord, RelatedWord, CategoryExample } from '../models/DataModels';

// API响应类型
class LevelInfo {
  levels: object[] = [];
  total_lessons: number = 0;
  words_per_lesson: number = 0;
}

class LessonWordsResponse {
  lessonId: number = 0;
  level: number = 0;
  wordCount: number = 0;
  words: object[] = [];
}

class QuizConfigResponse {
  lesson_id: number = 0;
  mastery_threshold: number = 0;
  correct_count_required: number = 0;
  max_skip: number = 0;
}

class TTSResponse {
  audio_url: string = '';
}

// 快速翻译结果
interface QuickTranslateResult {
  word: string;
  translation: string;
  source: string;
}

// Spirit对话消息
class SpiritChatMessageItem {
  role: string = '';
  content: string = '';
  
  constructor(role: string, content: string) {
    this.role = role;
    this.content = content;
  }
}

// Spirit对话响应
class SpiritChatResponseData {
  reply: string = '';
  success: boolean = true;
}

// 自定义错误类
class ApiError extends Error {
  code: number = 0;
  
  constructor(message: string, code: number = 0) {
    super(message);
    this.code = code;
  }
}

class ApiService {
  private static instance: ApiService;
  private httpClient: http.HttpRequest;

  private constructor() {
    this.httpClient = http.createHttp();
  }

  static getInstance(): ApiService {
    if (!ApiService.instance) {
      ApiService.instance = new ApiService();
    }
    return ApiService.instance;
  }

  /**
   * 发送 GET 请求
   */
  private async get(path: string, extendedTimeout: boolean = false): Promise<string> {
    const url = `${API_BASE_URL}${path}`;
    // AI查询需要更长超时时间
    const timeout = extendedTimeout ? 60000 : 15000;
    
    try {
      const response = await this.httpClient.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'Content-Type': 'application/json',
        },
        connectTimeout: 10000,
        readTimeout: timeout,
      });

      if (response.responseCode === 200) {
        return response.result as string;
      } else {
        throw new ApiError(`HTTP ${response.responseCode}`, response.responseCode);
      }
    } catch (error) {
      console.error(`API GET ${path} failed:`, JSON.stringify(error));
      throw new ApiError(`Request failed: ${path}`);
    }
  }

  /**
   * 发送 POST 请求
   */
  private async post(path: string, data: string): Promise<string> {
    const url = `${API_BASE_URL}${path}`;

    try {
      const response = await this.httpClient.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
        },
        extraData: data,
        connectTimeout: 10000,
        readTimeout: 30000,
      });

      if (response.responseCode === 200) {
        return response.result as string;
      } else {
        throw new ApiError(`HTTP ${response.responseCode}`, response.responseCode);
      }
    } catch (error) {
      console.error(`API POST ${path} failed:`, JSON.stringify(error));
      throw new ApiError(`Request failed: ${path}`);
    }
  }

  // ==================== TTS API ====================

  /**
   * 获取 TTS 音频 URL
   */
  async getTTSAudio(text: string, lang: string = 'ko'): Promise<string | null> {
    try {
      const body = JSON.stringify({ text: text, lang: lang });
      const result = await this.post('/api/tts', body);
      const parsed = JSON.parse(result) as TTSResponse;
      return parsed.audio_url;
    } catch (error) {
      console.warn('TTS API failed, silent fallback');
      return null;
    }
  }

  // ==================== Dictionary API ====================

  /**
   * 获取词典 AI 补充信息
   */
  async getDictAI(word: string, direction: string = 'ko2zh'): Promise<DictAIResponse | null> {
    try {
      const body = JSON.stringify({ word: word, direction: direction });
      const result = await this.post('/api/dict/ai', body);
      const parsed = JSON.parse(result) as DictAIResponse;
      return parsed;
    } catch (error) {
      console.warn('Dict AI API failed, silent fallback');
      return null;
    }
  }

  /**
   * 词典搜索
   */
  async searchDict(query: string, direction: string = 'auto'): Promise<DictSearchResponse | null> {
    try {
      const encodedQuery = encodeURIComponent(query);
      // 使用扩展超时，因为AI查询可能需要较长时间
      const result = await this.get(`/api/dict/search?query=${encodedQuery}&direction=${direction}`, true);
      const parsed = JSON.parse(result) as Record<string, Object>;

      // Parse response into DictSearchResponse
      const response = new DictSearchResponse();
      response.source = parsed['source'] as string || '';
      response.query = parsed['query'] as string || '';
      response.direction = parsed['direction'] as string || '';

      // Parse results array
      const resultsArray = parsed['results'] as Record<string, Object>[];
      if (resultsArray && resultsArray.length > 0) {
        const wordEntries: WordEntry[] = [];
        for (let i = 0; i < resultsArray.length; i++) {
          const item = resultsArray[i];
          const entry = new WordEntry();
          entry.id = item['id'] as number || 0;
          entry.hangul = item['hangul'] as string || '';
          entry.romanization = item['romanization'] as string || '';
          entry.pos = item['pos'] as string || '';
          entry.primaryMeaning = item['primary_meaning'] as string || '';
          entry.topikLevel = item['topik_level'] as number || 1;
          entry.freqRank = item['freq_rank'] as number || 0;
          entry.lessonId = item['lesson_id'] as number || 1;

          // Parse collocations
          const collocations = item['collocations'] as string[];
          if (collocations) {
            entry.collocations = collocations;
          }

          // Parse examples
          const examples = item['examples'] as Record<string, string>[];
          if (examples) {
            const exampleList: ExampleSentence[] = [];
            for (let j = 0; j < examples.length; j++) {
              const ex = examples[j];
              exampleList.push(new ExampleSentence(ex['ko'] || '', ex['zh'] || ''));
            }
            entry.examples = exampleList;
          }

          // Parse senses
          const senses = item['senses'] as Record<string, Object>[];
          if (senses) {
            const senseList: Sense[] = [];
            for (let k = 0; k < senses.length; k++) {
              const s = senses[k];
              const senseExamples = s['examples'] as Record<string, string>[];
              const senseExList: ExampleSentence[] = [];
              if (senseExamples) {
                for (let m = 0; m < senseExamples.length; m++) {
                  const se = senseExamples[m];
                  senseExList.push(new ExampleSentence(se['ko'] || '', se['zh'] || ''));
                }
              }
              senseList.push(new Sense(s['meaning'] as string || '', senseExList));
            }
            entry.senses = senseList;
          }

          wordEntries.push(entry);
        }
        response.results = wordEntries;
      }

      // Parse AI supplement if present
      const aiSupplement = parsed['aiSupplement'] as Record<string, Object> | null;
      console.info('[ApiService] aiSupplement present: ' + (aiSupplement ? 'YES' : 'NO'));
      if (aiSupplement) {
        console.info('[ApiService] aiSupplement keys: ' + Object.keys(aiSupplement).join(', '));
        const ai = new DictAIResponse();
        ai.aiMeaning = aiSupplement['aiMeaning'] as string || '';
        ai.wordType = aiSupplement['wordType'] as string || '';
        ai.hanja = aiSupplement['hanja'] as string || '';
        console.info('[ApiService] Parsed aiMeaning: ' + ai.aiMeaning);
        ai.composition = aiSupplement['composition'] as string || '';
        ai.tips = aiSupplement['tips'] as string || '';

        // Parse meanings
        const meanings = aiSupplement['meanings'] as Record<string, string>[];
        if (meanings) {
          const meaningList: MeaningDetail[] = [];
          for (let i = 0; i < meanings.length; i++) {
            const m = meanings[i];
            meaningList.push(new MeaningDetail(m['type'] || '', m['explanation'] || ''));
          }
          ai.meanings = meaningList;
        }

        // Parse collocations
        const collocations = aiSupplement['collocations'] as Record<string, string>[];
        if (collocations) {
          const collList: Collocation[] = [];
          for (let i = 0; i < collocations.length; i++) {
            const c = collocations[i];
            const coll = new Collocation();
            coll.phrase = c['phrase'] || '';
            coll.meaning = c['meaning'] || '';
            coll.exampleKo = c['exampleKo'] || '';
            coll.exampleZh = c['exampleZh'] || '';
            collList.push(coll);
          }
          ai.collocations = collList;
        }

        // Parse aiExamples with category
        const aiExamples = aiSupplement['aiExamples'] as Record<string, string>[];
        if (aiExamples) {
          const exList: CategoryExample[] = [];
          for (let n = 0; n < aiExamples.length; n++) {
            const ae = aiExamples[n];
            const ex = new CategoryExample();
            ex.ko = ae['ko'] || '';
            ex.zh = ae['zh'] || '';
            ex.category = ae['category'] || '';
            exList.push(ex);
          }
          ai.aiExamples = exList;
        }

        // Parse synonyms with difference
        const synonyms = aiSupplement['synonyms'] as Record<string, string>[];
        console.info('[ApiService] Raw synonyms: ' + JSON.stringify(synonyms));
        if (synonyms && synonyms.length > 0) {
          const synList: SynonymWord[] = [];
          for (let i = 0; i < synonyms.length; i++) {
            const s = synonyms[i];
            console.info('[ApiService] Synonym item ' + i + ': ' + JSON.stringify(s));
            const syn = new SynonymWord();
            syn.word = s['word'] || '';
            syn.meaning = s['meaning'] || '';
            syn.difference = s['difference'] || '';
            console.info('[ApiService] Parsed synonym: word=' + syn.word + ', meaning=' + syn.meaning);
            synList.push(syn);
          }
          ai.synonyms = synList;
        }

        // Parse antonyms
        const antonyms = aiSupplement['antonyms'] as Record<string, string>[];
        if (antonyms) {
          const antList: RelatedWord[] = [];
          for (let i = 0; i < antonyms.length; i++) {
            const a = antonyms[i];
            const ant = new RelatedWord();
            ant.word = a['word'] || '';
            ant.meaning = a['meaning'] || '';
            antList.push(ant);
          }
          ai.antonyms = antList;
        }

        // Parse relatedWords
        const relatedWords = aiSupplement['relatedWords'] as Record<string, string>[];
        if (relatedWords) {
          const relList: RelatedWord[] = [];
          for (let i = 0; i < relatedWords.length; i++) {
            const r = relatedWords[i];
            const rel = new RelatedWord();
            rel.word = r['word'] || '';
            rel.meaning = r['meaning'] || '';
            relList.push(rel);
          }
          ai.relatedWords = relList;
        }

        response.aiSupplement = ai;
      }

      return response;
    } catch (error) {
      console.warn('Dict search API failed, silent fallback');
      return null;
    }
  }

  // ==================== Content API ====================

  /**
   * 获取 TOPIK 等级信息
   */
  async getLevelInfo(): Promise<LevelInfo> {
    try {
      const result = await this.get('/api/content/levels');
      return JSON.parse(result) as LevelInfo;
    } catch (error) {
      console.error('Get level info failed');
      throw new ApiError('Get level info failed');
    }
  }

  /**
   * 获取关卡内容
   */
  async getLessonContent(lessonId: number): Promise<string> {
    try {
      return await this.get(`/api/content/lesson/${lessonId}`);
    } catch (error) {
      console.error(`Get lesson ${lessonId} content failed`);
      throw new ApiError(`Get lesson ${lessonId} content failed`);
    }
  }

  /**
   * 获取练习配置
   */
  async getQuizConfig(lessonId: number): Promise<QuizConfigResponse> {
    try {
      const result = await this.get(`/api/content/lesson/${lessonId}/quiz-config`);
      return JSON.parse(result) as QuizConfigResponse;
    } catch (error) {
      console.error('Get quiz config failed');
      throw new ApiError('Get quiz config failed');
    }
  }

  /**
   * 获取TOPIK等级词表
   */
  async getTopikWords(level: number): Promise<LessonWordsResponse> {
    try {
      const result = await this.get(`/api/content/words/topik/${level}`);
      return JSON.parse(result) as LessonWordsResponse;
    } catch (error) {
      console.error(`Get TOPIK ${level} words failed`);
      throw new ApiError(`Get TOPIK ${level} words failed`);
    }
  }

  /**
   * 获取关卡词表
   * @param level TOPIK等级 (0=常考单词, 1=TOPIK I, 2=TOPIK II)
   * @param lessonId 关卡ID (从1开始)
   * @param wordsPerLesson 每关单词数 (默认20)
   */
  async getLessonWords(level: number, lessonId: number, wordsPerLesson: number = 20): Promise<LessonWordsResponse> {
    try {
      const result = await this.get(`/api/content/words/level/${level}/lesson/${lessonId}?words_per_lesson=${wordsPerLesson}`);
      return JSON.parse(result) as LessonWordsResponse;
    } catch (error) {
      console.error(`Get level ${level} lesson ${lessonId} words failed`);
      throw new ApiError(`Get level ${level} lesson ${lessonId} words failed`);
    }
  }

  // ==================== Stats API ====================

  /**
   * 上报统计事件
   */
  async reportStats(deviceId: string, events: string): Promise<void> {
    try {
      const body = JSON.stringify({ device_id: deviceId, events: events });
      await this.post('/api/stats/batch', body);
    } catch (error) {
      console.warn('Stats report failed, will retry later');
    }
  }

  // ==================== Quick Translate API ====================

  /**
   * 快速翻译单词
   * @param word 要翻译的词
   * @param direction 翻译方向 auto/ko2zh/zh2ko
   * @returns 翻译结果
   */
  async quickTranslate(word: string, direction: string = 'auto'): Promise<QuickTranslateResult | null> {
    try {
      const response = await this.get(`/api/dict/quick-translate?word=${encodeURIComponent(word)}&direction=${direction}`);
      const parsed = JSON.parse(response) as Record<string, Object>;
      
      return {
        word: parsed['word'] as string || word,
        translation: parsed['translation'] as string || '',
        source: parsed['source'] as string || 'unknown'
      };
    } catch (error) {
      console.error('[ApiService] Quick translate failed:', JSON.stringify(error));
      return null;
    }
  }

  // ==================== Spirit Chat API ====================

  /**
   * AI精灵对话
   * @param messages 对话消息列表
   */
  async spiritChat(messages: SpiritChatMessageItem[]): Promise<string | null> {
    try {
      const body = JSON.stringify({ messages: messages });
      const result = await this.post('/api/spirit/chat', body);
      const parsed = JSON.parse(result) as SpiritChatResponseData;
      if (parsed.success) {
        return parsed.reply;
      }
      return parsed.reply || null;
    } catch (error) {
      console.error('[ApiService] Spirit chat failed:', JSON.stringify(error));
      return null;
    }
  }

  /**
   * 销毁 HTTP 客户端
   */
  destroy() {
    this.httpClient.destroy();
  }
}

export default ApiService;
export { LessonWordsResponse, LevelInfo, QuizConfigResponse, ApiError, QuickTranslateResult };
