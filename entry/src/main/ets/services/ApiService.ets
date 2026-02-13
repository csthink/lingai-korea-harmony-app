/**
 * API 服务层
 * 负责与后端 API 通信（经由 Unified Service 网关）
 * 适配 ArkTS 严格模式
 */
import http from '@ohos.net.http';
import preferences from '@ohos.data.preferences';
import deviceInfo from '@ohos.deviceInfo';
import { API_BASE_URL, BIZ_API_PREFIX, AUTH_API_PREFIX, APP_ID, AUTH_APP_ID, STORAGE_KEYS } from '../utils/Constants';
import { DictAIResponse, DictSearchResponse, WordEntry, ExampleSentence, Sense, MeaningDetail, Collocation, SynonymWord, RelatedWord, CategoryExample, UserInfo } from '../models/DataModels';

// ==================== 响应 & 错误类型 ====================

// Unified Service 统一响应格式
class UnifiedResult {
  code: number = 0;
  message: string = '';
  data: Object | null = null;
  traceId: string = '';
}

// 一键登录开关状态
// 一键登录开关状态
class PhoneAuthStatus {
  oneClickLoginEnabled: boolean = false;
  verifyMobileEnabled: boolean = false;
  mockMode: boolean = false; 
}

// API 响应类型
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

// Spirit 对话消息
class SpiritChatMessageItem {
  role: string = '';
  content: string = '';

  constructor(role: string, content: string) {
    this.role = role;
    this.content = content;
  }
}

// Spirit 对话响应
class SpiritChatResponseData {
  reply: string = '';
  success: boolean = true;
}

// 自定义错误类
class ApiError extends Error {
  code: number = 0;
  traceId: string = '';

  constructor(message: string, code: number = 0, traceId: string = '') {
    super(message);
    this.code = code;
    this.traceId = traceId;
  }
}

// ==================== ApiService ====================

class ApiService {
  private static instance: ApiService;
  private httpClient: http.HttpRequest;

  // 鉴权状态（内存）
  private token: string = '';
  private deviceId: string = '';
  private initialized: boolean = false;

  private constructor() {
    this.httpClient = http.createHttp();
  }

  static getInstance(): ApiService {
    if (!ApiService.instance) {
      ApiService.instance = new ApiService();
    }
    return ApiService.instance;
  }

  // ==================== 初始化 & Token 管理 ====================

  /**
   * 初始化：从 Preferences 加载 token 和 deviceId
   * 应在 App 入口（Index.aboutToAppear）调用一次
   */
  async init(context: Context): Promise<void> {
    if (this.initialized) return;

    try {
      const pref = await preferences.getPreferences(context, 'lingai_prefs');

      // 加载 token
      const savedToken = await pref.get(STORAGE_KEYS.AUTH_TOKEN, '') as string;
      if (savedToken) {
        this.token = savedToken;
        console.info('[ApiService] Token loaded from preferences');
      }

      // 加载或生成 deviceId
      let savedDeviceId = await pref.get(STORAGE_KEYS.DEVICE_ID, '') as string;
      if (!savedDeviceId) {
        savedDeviceId = this.generateUUID();
        await pref.put(STORAGE_KEYS.DEVICE_ID, savedDeviceId);
        await pref.flush();
        console.info('[ApiService] Generated new deviceId: ' + savedDeviceId);
      }
      this.deviceId = savedDeviceId;

      this.initialized = true;
      console.info('[ApiService] Initialized (deviceId=' + this.deviceId + ', hasToken=' + (this.token.length > 0) + ')');
    } catch (error) {
      console.error('[ApiService] Init failed:', JSON.stringify(error));
    }
  }

  /**
   * 设置 token（登录成功后调用）
   */
  async setToken(token: string, context?: Context): Promise<void> {
    this.token = token;
    if (context) {
      try {
        const pref = await preferences.getPreferences(context, 'lingai_prefs');
        await pref.put(STORAGE_KEYS.AUTH_TOKEN, token);
        await pref.flush();
      } catch (error) {
        console.error('[ApiService] Save token failed:', JSON.stringify(error));
      }
    }
  }

  /**
   * 清除 token（退出登录时调用）
   */
  async clearToken(context?: Context): Promise<void> {
    this.token = '';
    if (context) {
      try {
        const pref = await preferences.getPreferences(context, 'lingai_prefs');
        await pref.delete(STORAGE_KEYS.AUTH_TOKEN);
        await pref.flush();
      } catch (error) {
        console.error('[ApiService] Clear token failed:', JSON.stringify(error));
      }
    }
  }

  /** 获取当前 token */
  getToken(): string {
    return this.token;
  }

  /** 获取设备 ID */
  getDeviceId(): string {
    return this.deviceId;
  }

  // ==================== 内部工具方法 ====================

  /**
   * 构建统一鉴权请求头
   */
  private getAuthHeaders(): Record<string, string> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      'X-App-Id': APP_ID,
    };
    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`;
    }
    if (this.deviceId) {
      headers['X-Device-Id'] = this.deviceId;
    }
    return headers;
  }

  /**
   * 构建完整业务 API URL
   * 路径自动追加网关前缀：/api/dict/search → /api/app/biz/api/dict/search
   */
  private buildUrl(path: string): string {
    return `${API_BASE_URL}${BIZ_API_PREFIX}${path}`;
  }

  /**
   * 解包 Unified Service 统一响应
   * { code, message, data, traceId }  —— code === 0 为成功
   */
  private unwrapResult(jsonStr: string): Object {
    const result = JSON.parse(jsonStr) as UnifiedResult;
    if (result.code !== 0) {
      throw new ApiError(result.message || `Biz error (code=${result.code})`, result.code, result.traceId);
    }
    return result.data as Object;
  }

  /**
   * 生成简易 UUID（v4 格式）
   */
  private generateUUID(): string {
    const hex = '0123456789abcdef';
    const segments: number[] = [8, 4, 4, 4, 12];
    const parts: string[] = [];
    for (let s = 0; s < segments.length; s++) {
      let part = '';
      for (let i = 0; i < segments[s]; i++) {
        part += hex.charAt(Math.floor(Math.random() * 16));
      }
      parts.push(part);
    }
    return parts.join('-');
  }

  // ==================== HTTP 基础方法 ====================

  /**
   * 发送 GET 请求（自动鉴权 + 解包）
   */
  private async get(path: string, extendedTimeout: boolean = false): Promise<string> {
    const url = this.buildUrl(path);
    const timeout = extendedTimeout ? 60000 : 15000;

    try {
      const response = await this.httpClient.request(url, {
        method: http.RequestMethod.GET,
        header: this.getAuthHeaders(),
        connectTimeout: 10000,
        readTimeout: timeout,
      });

      if (response.responseCode === 200) {
        const rawBody = response.result as string;
        const data = this.unwrapResult(rawBody);
        return JSON.stringify(data);
      } else {
        throw new ApiError(`HTTP ${response.responseCode}`, response.responseCode);
      }
    } catch (error) {
      if (error instanceof ApiError) {
        console.error(`[ApiService] GET ${path} biz error: code=${error.code}, msg=${error.message}, traceId=${error.traceId}`);
        throw error;
      }
      console.error(`[ApiService] GET ${path} failed:`, JSON.stringify(error));
      throw new ApiError(`Request failed: ${path}`);
    }
  }

  /**
   * 发送 POST 请求（自动鉴权 + 解包）
   */
  private async post(path: string, data: string): Promise<string> {
    const url = this.buildUrl(path);

    try {
      const response = await this.httpClient.request(url, {
        method: http.RequestMethod.POST,
        header: this.getAuthHeaders(),
        extraData: data,
        connectTimeout: 10000,
        readTimeout: 30000,
      });

      if (response.responseCode === 200) {
        const rawBody = response.result as string;
        const unwrapped = this.unwrapResult(rawBody);
        return JSON.stringify(unwrapped);
      } else {
        throw new ApiError(`HTTP ${response.responseCode}`, response.responseCode);
      }
    } catch (error) {
      if (error instanceof ApiError) {
        console.error(`[ApiService] POST ${path} biz error: code=${error.code}, msg=${error.message}, traceId=${error.traceId}`);
        throw error;
      }
      console.error(`[ApiService] POST ${path} failed:`, JSON.stringify(error));
      throw new ApiError(`Request failed: ${path}`);
    }
  }

  // ==================== Auth API（不走 BIZ_API_PREFIX）====================

  /**
   * 发送短信验证码
   */
  async sendSmsCode(phone: string): Promise<void> {
    const url = `${API_BASE_URL}${AUTH_API_PREFIX}/sms/send`;
    const body = JSON.stringify({ phone: phone });

    try {
      const response = await this.httpClient.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'X-App-Id': AUTH_APP_ID,
        },
        extraData: body,
        connectTimeout: 10000,
        readTimeout: 15000,
      });

      if (response.responseCode === 200) {
        const result = JSON.parse(response.result as string) as UnifiedResult;
        if (result.code !== 0) {
          throw new ApiError(result.message || '发送验证码失败', result.code, result.traceId);
        }
        console.info('[ApiService] SMS code sent successfully');
      } else {
        throw new ApiError(`HTTP ${response.responseCode}`, response.responseCode);
      }
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
      console.error('[ApiService] sendSmsCode failed:', JSON.stringify(error));
      throw new ApiError('发送验证码失败，请检查网络');
    }
  }

  /**
   * 短信验证码登录
   * 登录成功后自动持久化 token
   */
  async loginBySms(phone: string, code: string, context: Context): Promise<string> {
    const url = `${API_BASE_URL}${AUTH_API_PREFIX}/login/sms`;

    const body = JSON.stringify({
      phone: phone,
      code: code,
      deviceId: this.deviceId,
      deviceName: deviceInfo.marketName || deviceInfo.productModel || 'HarmonyOS Device',
      deviceType: 'HARMONY',
      osVersion: deviceInfo.osFullName || 'HarmonyOS',
      appVersion: '1.0.0',
    });

    try {
      const response = await this.httpClient.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'X-App-Id': AUTH_APP_ID,
          'X-Device-Id': this.deviceId,
        },
        extraData: body,
        connectTimeout: 10000,
        readTimeout: 15000,
      });

      if (response.responseCode === 200) {
        const result = JSON.parse(response.result as string) as UnifiedResult;
        if (result.code !== 0) {
          throw new ApiError(result.message || '登录失败', result.code, result.traceId);
        }
        // 解析 data 中的 accessToken
        const data = result.data as Record<string, Object>;
        const accessToken = data['accessToken'] as string || '';
        if (!accessToken) {
          throw new ApiError('登录成功但未获取到 token');
        }

        // 持久化 token
        await this.setToken(accessToken, context);
        console.info('[ApiService] Login success, token saved');

        return accessToken;
      } else {
        throw new ApiError(`HTTP ${response.responseCode}`, response.responseCode);
      }
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
      console.error('[ApiService] loginBySms failed:', JSON.stringify(error));
      throw new ApiError('登录失败，请检查网络');
    }
  }

  /**
   * 检查一键登录开关状态
   */
  async checkPhoneAuthStatus(): Promise<PhoneAuthStatus> {
    const url = `${API_BASE_URL}${AUTH_API_PREFIX}/phone-auth/status`;
    try {
      const response = await this.httpClient.request(url, {
        method: http.RequestMethod.GET,
        header: {
          'X-App-Id': AUTH_APP_ID,
          'X-Device-Id': this.deviceId,
        },
        connectTimeout: 5000,
        readTimeout: 5000,
      });

      if (response.responseCode === 200) {
        const result = JSON.parse(response.result as string) as UnifiedResult;
        if (result.code !== 0) return new PhoneAuthStatus();
        
        // 解析 data
        const data = result.data as Record<string, boolean>;
        const status = new PhoneAuthStatus();

        if (data) {
          status.oneClickLoginEnabled = data['oneClickLoginEnabled'] || false;
          status.verifyMobileEnabled = data['verifyMobileEnabled'] || false;
          status.mockMode = data['mockMode'] || false;
        }
        return status;
      }
      return new PhoneAuthStatus();
    } catch (error) {
      console.warn('[ApiService] Check phone auth status failed, default to SMS');
      return new PhoneAuthStatus();
    }
  }

  /**
   * 一键登录
   */
  async loginByOneClick(accessToken: string, context: Context): Promise<string> {
    const url = `${API_BASE_URL}${AUTH_API_PREFIX}/login/one-click`;
    
    const body = JSON.stringify({
      accessToken: accessToken,
      deviceId: this.deviceId,
      deviceName: deviceInfo.marketName || 'HarmonyOS Device',
      deviceType: 'HARMONY',
      osVersion: deviceInfo.osFullName || 'HarmonyOS',
      appVersion: '1.0.0'
    });

    try {
      const response = await this.httpClient.request(url, {
        method: http.RequestMethod.POST,
        header: {
          'Content-Type': 'application/json',
          'X-App-Id': AUTH_APP_ID,
          'X-Device-Id': this.deviceId,
        },
        extraData: body,
        connectTimeout: 10000,
        readTimeout: 15000,
      });

      if (response.responseCode === 200) {
        const result = JSON.parse(response.result as string) as UnifiedResult;
        if (result.code !== 0) {
          throw new ApiError(result.message || '一键登录失败', result.code, result.traceId);
        }
        
        const data = result.data as Record<string, Object>;
        const token = data['accessToken'] as string || '';
        if (!token) throw new ApiError('未获取到 Token');
        
        await this.setToken(token, context);
        return token;
      } else {
        throw new ApiError(`HTTP ${response.responseCode}`, response.responseCode);
      }
    } catch (error) {
      if (error instanceof ApiError) throw error;
      console.error('[ApiService] loginByOneClick failed:', JSON.stringify(error));
      throw new ApiError('登录失败，请检查网络');
    }
  }

  // ==================== User API ====================

  /**
   * 获取当前用户信息
   */
  async getCurrentUserInfo(): Promise<UserInfo> {
    // 直连 Unified 用户接口 (该接口不走 /biz 前缀)
    const url = `${API_BASE_URL}/api/app/user/info`;

    try {
      const response = await this.httpClient.request(url, {
        method: http.RequestMethod.GET,
        header: this.getAuthHeaders(),
        connectTimeout: 5000,
        readTimeout: 5000,
      });

      if (response.responseCode === 200) {
        // 解包 UnifiedResult
        const result = JSON.parse(response.result as string) as UnifiedResult;
        if (result.code !== 0) {
           throw new ApiError(result.message || 'Get user info failed', result.code, result.traceId);
        }
        
        const data = result.data as Record<string, Object>;
        const userInfo = new UserInfo();
        userInfo.id = data['id'] as number || 0;
        userInfo.phone = data['phone'] as string || '';
        userInfo.nickname = data['nickname'] as string || '';
        userInfo.avatar = data['avatar'] as string || '';
        userInfo.vipStatus = data['vipStatus'] as string || 'NORMAL';
        
        return userInfo;
      } else {
         throw new ApiError(`HTTP ${response.responseCode}`, response.responseCode);
      }
    } catch (error) {
      if (error instanceof ApiError) throw error;
      console.error('[ApiService] Get user info failed:', JSON.stringify(error));
      throw error as Error;
    }
  }

  /**
   * 退出登录
   * 调用后端接口并清除本地 Token
   */
  async logout(context: Context): Promise<void> {
    const url = `${API_BASE_URL}${AUTH_API_PREFIX}/logout`;
    try {
      if (this.token) {
        await this.httpClient.request(url, {
          method: http.RequestMethod.POST,
          header: {
            'Content-Type': 'application/json',
            'X-App-Id': AUTH_APP_ID,
            'X-Device-Id': this.deviceId,
            'Authorization': `Bearer ${this.token}`
          },
          extraData: '{}',
          connectTimeout: 5000,
          readTimeout: 5000,
        });
        console.info('[ApiService] Logout request success');
      }
    } catch (error) {
      console.warn('[ApiService] Logout request failed (ignored):', JSON.stringify(error));
    } finally {
      await this.clearToken(context);
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
      console.warn('[ApiService] TTS API failed, silent fallback');
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
      console.warn('[ApiService] Dict AI API failed, silent fallback');
      return null;
    }
  }

  /**
   * 词典搜索
   */
  async searchDict(query: string, direction: string = 'auto'): Promise<DictSearchResponse | null> {
    try {
      const encodedQuery = encodeURIComponent(query);
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
      if (aiSupplement) {
        const ai = new DictAIResponse();
        ai.aiMeaning = aiSupplement['aiMeaning'] as string || '';
        ai.wordType = aiSupplement['wordType'] as string || '';
        ai.hanja = aiSupplement['hanja'] as string || '';
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
        if (synonyms && synonyms.length > 0) {
          const synList: SynonymWord[] = [];
          for (let i = 0; i < synonyms.length; i++) {
            const s = synonyms[i];
            const syn = new SynonymWord();
            syn.word = s['word'] || '';
            syn.meaning = s['meaning'] || '';
            syn.difference = s['difference'] || '';
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
      console.warn('[ApiService] Dict search API failed, silent fallback');
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
      console.error('[ApiService] Get level info failed');
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
      console.error(`[ApiService] Get lesson ${lessonId} content failed`);
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
      console.error('[ApiService] Get quiz config failed');
      throw new ApiError('Get quiz config failed');
    }
  }

  /**
   * 获取 TOPIK 等级词表
   */
  async getTopikWords(level: number): Promise<LessonWordsResponse> {
    try {
      const result = await this.get(`/api/content/words/topik/${level}`);
      return JSON.parse(result) as LessonWordsResponse;
    } catch (error) {
      console.error(`[ApiService] Get TOPIK ${level} words failed`);
      throw new ApiError(`Get TOPIK ${level} words failed`);
    }
  }

  /**
   * 获取关卡词表
   */
  async getLessonWords(level: number, lessonId: number, wordsPerLesson: number = 20): Promise<LessonWordsResponse> {
    try {
      const result = await this.get(`/api/content/words/level/${level}/lesson/${lessonId}?words_per_lesson=${wordsPerLesson}`);
      return JSON.parse(result) as LessonWordsResponse;
    } catch (error) {
      console.error(`[ApiService] Get level ${level} lesson ${lessonId} words failed`);
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
      console.warn('[ApiService] Stats report failed, will retry later');
    }
  }

  // ==================== Quick Translate API ====================

  /**
   * 快速翻译单词
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
   * AI 精灵对话
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
export { LessonWordsResponse, LevelInfo, QuizConfigResponse, ApiError, QuickTranslateResult, PhoneAuthStatus };
