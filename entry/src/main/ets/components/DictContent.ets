/**
 * 词典内容组件
 * 内嵌于Tab中展示词典搜索功能
 * 适配 ArkTS 严格模式
 */
import { COLORS, API_BASE_URL, BIZ_API_PREFIX } from '../utils/Constants';
import { AssistantAvatar } from './AssistantAvatar';
import { UI } from '../utils/UiTokens';
import { WordEntry, DictAIResponse, DictSearchResponse, ExampleSentence, Sense, MeaningDetail, Collocation, SynonymWord, RelatedWord, CategoryExample, UserInfo } from '../models/DataModels';
import { WordCard } from './WordCard';
import { PlayButton, PlayIcon } from './PlayButton';
import { SelectableText, SelectableTextCallbacks } from './SelectableText';
import ApiService, { ApiError } from '../services/ApiService';
import AudioService from '../services/AudioService';
import { VocabularyService, VocabularyWord } from '../services/VocabularyService';
import preferences from '@ohos.data.preferences';
import promptAction from '@ohos.promptAction';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { themeManager } from '../utils/ThemeManager';
import { AuthRequiredState } from './AuthRequiredState';

// 最近添加单词的数据类
class RecentWordItem {
  hangul: string = '';
  roman: string = '';
  meaning: string = '';

  constructor(hangul: string, roman: string, meaning: string) {
    this.hangul = hangul;
    this.roman = roman;
    this.meaning = meaning;
  }
}

class DictQueryCacheEntry {
  resultSource: string = '';
  resultDirection: string = '';
  results: WordEntry[] = [];
  aiSupplement: DictAIResponse | null = null;
  cachedAt: number = 0;
}

@Component
export struct DictContent {
  // 外部传入的搜索词（从其他Tab跳转过来，或嵌入模式下初始词）
  @Prop @Watch('onExternalSearchChange') searchWordFromExternal: string = '';
  @Prop @Watch('onActiveTabIndexChange') activeTabIndex: number = -1;
  // 嵌入模式：隐藏标题，适配底部弹窗
  @Prop embedMode: boolean = false;
  
  @State searchText: string = '';
  @State searchDirection: string = 'auto';
  @State isLoading: boolean = false;
  @State searchResults: WordEntry[] = [];
  @State aiSupplement: DictAIResponse | null = null;
  @State resultSource: string = '';
  @State resultDirection: string = '';
  @State hasSearched: boolean = false;
  @State showAddDialog: boolean = false;
  @State selectedWord: WordEntry | null = null;
  @State searchHistory: string[] = [];
  @State showHistory: boolean = false;
  @State isInVocabulary: boolean = false;
  // 长按翻译相关
  @State showTranslateToast: boolean = false;
  @State translateWord: string = '';
  @State translateResult: string = '';
  @State translateSource: string = '';
  @State isTranslating: boolean = false;
  // 浏览历史导航
  @State browseHistory: string[] = [];
  @State currentHistoryIndex: number = -1;
  private static readonly MAX_BROWSE_HISTORY: number = 10;
  // 流式响应相关
  @State isStreaming: boolean = false;
  @State streamingText: string = '';  // 原始文本累积
  @State streamingMeaning: string = '';  // 逐字显示的释义
  @State streamingWordType: string = '';  // 逐字显示的词性
  @State streamingTips: string = '';  // 逐字显示的Tips
  
  // 页面切换状态
  @State showFavoritesPage: boolean = false;  // 显示收藏列表页
  @State showDetailPage: boolean = false;     // 显示详情页
  @State detailWord: string = '';             // 详情页要显示的单词
  @State favoriteCount: number = 0;           // 收藏数量
  @State recentWords: RecentWordItem[] = [];  // 最近添加
  @State recentWordsLimit: number = 3;         // 最近添加显示数量
  @State themeVersion: number = 0;
  @State authChecked: boolean = false;
  @State requiresLogin: boolean = false;
  @State userInfo: UserInfo = new UserInfo();
  
  // 外部搜索词变化时触发搜索
  onExternalSearchChange() {
    if (this.requiresLogin) {
      return;
    }
    if (this.searchWordFromExternal && this.searchWordFromExternal.length > 0) {
      console.info(`[DictContent] External search triggered: ${this.searchWordFromExternal}`);
      this.searchDirection = 'auto';
      this.searchText = this.searchWordFromExternal;
      this.performStreamingSearch();
    }
  }

  onActiveTabIndexChange(): void {
    if (this.activeTabIndex !== 2 || this.embedMode) {
      return;
    }
    void this.refreshForVisibleTab();
  }

  private apiService: ApiService = ApiService.getInstance();
  private audioService: AudioService = AudioService.getInstance();
  private vocabularyService: VocabularyService = VocabularyService.getInstance();
  private textInputController: TextInputController = new TextInputController();
  private static readonly HISTORY_KEY: string = 'dict_search_history';
  private static readonly MAX_HISTORY: number = 10;
  private unsubscribeTheme: (() => void) | null = null;
  private searchResultCache: Map<string, DictQueryCacheEntry> = new Map();
  // SSE 并发保护 & 状态追踪
  private activeHttpRequest: http.HttpRequest | null = null;
  private sseBuffer: string = '';
  private sseGotResult: boolean = false;
  private sseFallbackTriggered: boolean = false;
  private searchEpoch: number = 0;

  private invalidateSearch(): number {
    this.searchEpoch += 1;
    if (this.activeHttpRequest !== null) {
      this.releaseStream(this.activeHttpRequest);
    }
    this.isLoading = false;
    this.isStreaming = false;
    return this.searchEpoch;
  }

  private releaseStream(request: http.HttpRequest): void {
    if (this.activeHttpRequest === request) this.activeHttpRequest = null;
    try { request.destroy(); } catch (_error) { /* Request already closed. */ }
  }

  async aboutToAppear() {
    if (this.unsubscribeTheme === null) {
      this.unsubscribeTheme = themeManager.subscribe(() => {
        this.themeVersion++;
      });
    }

    // 设置音频缓存目录
    const context = getContext(this);
    await this.refreshAccessState(context);
    if (this.requiresLogin) {
      return;
    }
    await this.loadUserInfo(context);
    const cacheDir = context.tempDir;
    this.audioService.setCacheDir(cacheDir);
    console.info(`DictContent: Set audio cache dir to ${cacheDir}`);
    
    // 初始化生词本服务 - 必须await确保context正确设置
    await this.vocabularyService.init(context);
    
    // 加载搜索历史
    this.loadSearchHistory();
    
    // 加载收藏数量和最近添加的单词
    this.loadFavoriteData();
    
    // 如果有初始搜索词，执行搜索
    if (this.searchWordFromExternal && this.searchWordFromExternal.length > 0) {
      console.info(`[DictContent] Initial search triggered: ${this.searchWordFromExternal}`);
      this.searchDirection = 'auto';
      this.searchText = this.searchWordFromExternal;
      this.performStreamingSearch();
    }
  }

  private async refreshForVisibleTab(): Promise<void> {
    const context = getContext(this);
    await this.refreshAccessState(context);
    if (this.requiresLogin) {
      return;
    }
    await this.prepareAuthorizedContent(context);
  }

  aboutToDisappear() {
    this.invalidateSearch();
    if (this.unsubscribeTheme !== null) {
      this.unsubscribeTheme();
      this.unsubscribeTheme = null;
    }
  }

  private async refreshAccessState(context: Context): Promise<void> {
    await this.apiService.init(context);
    this.requiresLogin = this.apiService.getToken().length === 0;
    if (this.requiresLogin) {
      this.userInfo = new UserInfo();
    }
    this.authChecked = true;
  }

  private async loadUserInfo(context: Context): Promise<void> {
    try {
      await this.apiService.init(context);
      if (!this.apiService.getToken()) {
        this.userInfo = new UserInfo();
        return;
      }
      this.userInfo = await this.apiService.getCurrentUserInfo();
    } catch (_error) {
      console.warn('[DictContent] loadUserInfo failed, using default quota');
      this.requiresLogin = this.apiService.getToken().length === 0;
      this.userInfo = new UserInfo();
    }
  }

  private async prepareAuthorizedContent(context: Context): Promise<void> {
    await this.loadUserInfo(context);
    if (this.requiresLogin) {
      return;
    }
    this.audioService.setCacheDir(context.tempDir);
    await this.vocabularyService.init(context);
    this.loadSearchHistory();
    this.loadFavoriteData();
  }

  private async refreshQuotaInfo(): Promise<void> {
    if (this.requiresLogin) {
      return;
    }
    await this.loadUserInfo(getContext(this));
  }

  // 加载收藏数据
  loadFavoriteData() {
    const words: VocabularyWord[] = this.vocabularyService.getAllWords();
    this.favoriteCount = words.length;
    
    // 获取最近添加的单词（根据limit数量）
    const recent = words.slice(0, this.recentWordsLimit);
    const recentItems: RecentWordItem[] = [];
    for (let i = 0; i < recent.length; i++) {
      const w = recent[i];
      recentItems.push(new RecentWordItem(w.hangul, this.toRoman(w.hangul), w.meaning));
    }
    this.recentWords = recentItems;
  }

  // 简单的韩文转罗马音（占位实现）
  toRoman(hangul: string): string {
    // 简单的占位实现，实际应使用专业转换库
    const romanMap: Record<string, string> = {
      '구름': 'Gureum',
      '행복': 'Haengbok',
      '사랑': 'Sarang',
      '학교': 'Hakgyo',
      '친구': 'Chingu'
    };
    return romanMap[hangul] || hangul;
  }

  // 判断是否为单词（不含空格、标点）
  isSingleWord(text: string): boolean {
    const trimmed = text.trim();
    // 不含空格，且只包含韩文或中文字符
    if (trimmed.includes(' ')) return false;
    // 检查是否包含韩文或中文
    const koreanOrChinese = /^[\uAC00-\uD7AF\u1100-\u11FF\u4E00-\u9FFF]+$/;
    return koreanOrChinese.test(trimmed);
  }

  // 显示添加到生词本的弹窗
  showAddToVocabularyDialog(word: string, meaning: string) {
    // 检查是否已在生词本中
    if (this.vocabularyService.hasWord(word)) {
      console.info(`[DictContent] Word already in vocabulary: ${word}`);
      return;
    }

    AlertDialog.show({
      title: '加入生词本',
      message: `加入「${word}」到生词本用于复习提醒？`,
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '加入',
        fontColor: '#007AFF',
        action: async () => {
          const success = await this.vocabularyService.addWord(word, meaning);
          if (success) {
            console.info(`[DictContent] Added to vocabulary: ${word}`);
          }
        }
      }
    });
  }

  // 加载搜索历史
  async loadSearchHistory() {
    try {
      const context = getContext(this);
      const pref = await preferences.getPreferences(context, 'dict_prefs');
      const history = await pref.get(DictContent.HISTORY_KEY, '[]') as string;
      this.searchHistory = JSON.parse(history) as string[];
      console.info(`[DictContent] Loaded ${this.searchHistory.length} history items`);
    } catch (error) {
      console.error('[DictContent] Failed to load search history:', JSON.stringify(error));
      this.searchHistory = [];
    }
  }

  // 保存搜索历史
  async saveSearchHistory() {
    try {
      const context = getContext(this);
      const pref = await preferences.getPreferences(context, 'dict_prefs');
      await pref.put(DictContent.HISTORY_KEY, JSON.stringify(this.searchHistory));
      await pref.flush();
    } catch (error) {
      console.error('[DictContent] Failed to save search history:', JSON.stringify(error));
    }
  }

  // 添加搜索记录
  addToHistory(query: string) {
    // 如果已存在，先移除
    const index = this.searchHistory.indexOf(query);
    if (index !== -1) {
      this.searchHistory.splice(index, 1);
    }
    // 添加到开头
    this.searchHistory.unshift(query);
    // 限制数量
    if (this.searchHistory.length > DictContent.MAX_HISTORY) {
      this.searchHistory = this.searchHistory.slice(0, DictContent.MAX_HISTORY);
    }
    this.saveSearchHistory();
  }

  // 点击历史记录
  onHistoryItemClick(query: string) {
    this.searchDirection = 'auto';
    this.searchText = query;
    this.showHistory = false;
    // 隐藏键盘
    this.textInputController.stopEditing();
    this.performStreamingSearch();
  }

  playAudio(text: string) {
    console.info(`DictContent: Playing audio for: ${text}`);
    this.audioService.playKorean(text);
  }

  // 判断文本是否包含韩文字符
  isKorean(text: string): boolean {
    // 韩文Unicode范围: AC00-D7AF (韩文音节), 1100-11FF (韩文字母)
    const koreanRegex = /[\uAC00-\uD7AF\u1100-\u11FF]/;
    return koreanRegex.test(text);
  }

  // 浅色卡片（如 #FAFAFA）中的文字颜色，在深色模式下避免浅底浅字
  getLightCardMainTextColor(): string {
    return themeManager.isDark() ? '#1e293b' : COLORS.TEXT_PRIMARY;
  }

  getLightCardSecondaryTextColor(): string {
    return themeManager.isDark() ? '#475569' : COLORS.TEXT_SECONDARY;
  }

  getLightCardHintTextColor(): string {
    return themeManager.isDark() ? '#64748b' : COLORS.TEXT_HINT;
  }

  // 长按翻译处理
  async onLongPressTranslate(word: string) {
    if (this.isTranslating || word.length === 0) {
      return;
    }
    
    console.info(`[DictContent] Long press translate: ${word}`);
    this.translateWord = word;
    this.translateResult = '';
    this.translateSource = '';
    this.isTranslating = true;
    this.showTranslateToast = true;
    
    try {
      const result = await this.apiService.quickTranslate(word, 'auto');
      if (result !== null) {
        this.translateResult = result.translation;
        this.translateSource = result.source;
      } else {
        this.translateResult = '翻译失败';
        this.translateSource = 'error';
      }
    } catch (error) {
      console.error('[DictContent] Translate error:', JSON.stringify(error));
      if (error instanceof ApiError) {
        this.translateResult = error.message;
      } else {
        this.translateResult = '翻译失败';
      }
      this.translateSource = 'error';
    } finally {
      this.isTranslating = false;
      void this.refreshQuotaInfo();
    }
  }

  // 关闭翻译Toast
  closeTranslateToast() {
    this.showTranslateToast = false;
    this.translateWord = '';
    this.translateResult = '';
  }

  // 查看AI详解 - 填充搜索框并搜索
  viewAIDetail() {
    if (this.translateWord.length > 0) {
      this.searchText = this.translateWord;
      this.closeTranslateToast();
      this.textInputController.stopEditing();
      this.performStreamingSearch();
    }
  }

  // 获取可选文本的回调处理
  getSelectableCallbacks(): SelectableTextCallbacks {
    return {
      onPlay: (text: string) => {
        this.playAudio(text);
      },
      onAddToVocabulary: async (text: string) => {
        // 直接将选中文本加入生词本
        try {
          // 先获取翻译
          const result = await this.apiService.quickTranslate(text, 'auto');
          const meaning = result !== null ? result.translation : '';
          
          await this.vocabularyService.addWord(text, meaning, 'selection');
          console.info(`[DictContent] Added to vocabulary from selection: ${text} - ${meaning}`);
          
          // 提示用户
          promptAction.showToast({ message: `已加入生词本: ${text}`, duration: 2000 });
        } catch (error) {
          console.error('[DictContent] Add to vocabulary failed:', JSON.stringify(error));
          if (error instanceof ApiError) {
            promptAction.showToast({ message: error.message, duration: 2500 });
          }
        } finally {
          void this.refreshQuotaInfo();
        }
      },
      onViewDetail: (text: string) => {
        // 填充搜索框并执行搜索
        this.searchText = text;
        this.textInputController.stopEditing();
        this.performStreamingSearch();
      }
    };
  }

  // 添加到浏览历史
  addToBrowseHistory(word: string) {
    const trimmed = word.trim();
    if (trimmed.length === 0) return;
    
    // 如果已存在则移除旧的
    const existingIndex = this.browseHistory.indexOf(trimmed);
    if (existingIndex !== -1) {
      this.browseHistory.splice(existingIndex, 1);
    }
    
    // 添加到末尾
    this.browseHistory.push(trimmed);
    
    // 限制最大数量
    if (this.browseHistory.length > DictContent.MAX_BROWSE_HISTORY) {
      this.browseHistory.shift();
    }
    
    // 更新当前索引
    this.currentHistoryIndex = this.browseHistory.length - 1;
  }

  // 点击历史导航项
  onBrowseHistoryClick(word: string, index: number) {
    this.currentHistoryIndex = index;
    this.searchDirection = 'auto';
    this.searchText = word;
    this.textInputController.stopEditing();
    // 直接执行搜索，不再添加到历史（避免重复）
    this.performSearchWithoutHistory();
  }

  // 执行搜索但不添加到浏览历史
  async performSearchWithoutHistory() {
    if (this.requiresLogin) {
      return;
    }
    const requestEpoch = this.invalidateSearch();
    const query = this.searchText.trim();
    const requestDirection = this.searchDirection;
    if (query.length === 0) {
      return;
    }

    if (this.tryApplyCachedResult(query, false, false, requestDirection)) {
      return;
    }
    
    this.isLoading = true;
    this.hasSearched = true;
    this.searchResults = [];
    this.aiSupplement = null;

    try {
      const response = await this.apiService.searchDict(query, requestDirection);
      if (requestEpoch !== this.searchEpoch) return;

      if (response !== null) {
        this.searchResults = response.results;
        this.aiSupplement = response.aiSupplement;
        this.resultSource = response.source;
        this.resultDirection = response.direction;
        this.saveSearchResultCache(query, response.results, response.aiSupplement, response.source, response.direction, requestDirection);

        if (this.searchResults.length > 0) {
          const firstWord = this.searchResults[0];
          this.isInVocabulary = this.vocabularyService.hasWord(firstWord.hangul);
        }
      }
    } catch (error) {
      if (requestEpoch !== this.searchEpoch) return;
      if (error instanceof ApiError && (error.code === 2001 || error.code === 2006)) {
        this.requiresLogin = true;
      }
      if (error instanceof ApiError) {
        promptAction.showToast({ message: error.message, duration: 2500 });
      }
      console.error('Search failed:', JSON.stringify(error));
    } finally {
      if (requestEpoch === this.searchEpoch) {
        this.isLoading = false;
        void this.refreshQuotaInfo();
      }
    }
  }

  async performSearch(queryOverride: string = '', directionOverride: string = '', inheritedEpoch: number = -1) {
    if (this.requiresLogin) {
      return;
    }
    if (inheritedEpoch >= 0 && inheritedEpoch !== this.searchEpoch) return;
    const requestEpoch = inheritedEpoch >= 0 ? inheritedEpoch : this.invalidateSearch();
    if (inheritedEpoch >= 0 && this.activeHttpRequest !== null) {
      this.releaseStream(this.activeHttpRequest);
      this.isStreaming = false;
    }
    const query = queryOverride || this.searchText.trim();
    const requestDirection = directionOverride || this.searchDirection;
    if (query.length === 0) {
      this.searchResults = [];
      this.aiSupplement = null;
      this.hasSearched = false;
      return;
    }

    if (this.tryApplyCachedResult(query, true, true, requestDirection)) {
      return;
    }

    this.isLoading = true;
    this.hasSearched = true;
    this.showHistory = false;

    try {
      const response = await this.apiService.searchDict(query, requestDirection);
      if (requestEpoch !== this.searchEpoch) return;
      if (response !== null) {
        this.searchResults = response.results;
        this.aiSupplement = response.aiSupplement;
        this.resultSource = response.source;
        this.resultDirection = response.direction;
        this.saveSearchResultCache(query, response.results, response.aiSupplement, response.source, response.direction, requestDirection);
        
        // 搜索成功后添加到历史
        this.addToHistory(query);
        
        // 添加到浏览历史
        this.addToBrowseHistory(query);
        
        // 检查是否已在生词本中
        this.isInVocabulary = this.vocabularyService.hasWord(query);
        
        // Debug: 打印AI响应数据
        if (this.aiSupplement !== null) {
          console.info('[DictContent] AI supplement received');
        }
      } else {
        this.searchResults = [];
        this.aiSupplement = null;
        this.resultSource = '';
      }
    } catch (error) {
      if (requestEpoch !== this.searchEpoch) return;
      if (error instanceof ApiError && (error.code === 2001 || error.code === 2006)) {
        this.requiresLogin = true;
      }
      if (error instanceof ApiError) {
        promptAction.showToast({ message: error.message, duration: 2500 });
      }
      console.error('Search failed:', JSON.stringify(error));
      this.searchResults = [];
      this.aiSupplement = null;
    } finally {
      if (requestEpoch === this.searchEpoch) {
        this.isLoading = false;
        void this.refreshQuotaInfo();
      }
    }
  }

  /**
   * 流式词典搜索 - 使用SSE实现打字机效果
   * 缓存命中时直接显示完整结果
   * 缓存未命中时流式显示LLM生成过程
   */
  async performStreamingSearch(): Promise<void> {
    if (this.requiresLogin) {
      return;
    }
    const requestEpoch = this.invalidateSearch();
    const query = this.searchText.trim();
    const requestDirection = this.searchDirection;
    if (query.length === 0) {
      this.searchResults = [];
      this.aiSupplement = null;
      this.hasSearched = false;
      return;
    }

    if (this.tryApplyCachedResult(query, true, true, requestDirection)) {
      return;
    }

    // 直接显示“AI正在分析”
    this.isLoading = false;
    this.isStreaming = true;
    this.streamingText = '';
    this.streamingMeaning = '';
    this.streamingWordType = '';
    this.streamingTips = '';
    this.hasSearched = true;
    this.showHistory = false;
    this.aiSupplement = null;

    // 重置 SSE 状态
    this.sseBuffer = '';
    this.sseGotResult = false;
    this.sseFallbackTriggered = false;

    const encodedQuery = encodeURIComponent(query);
    const url = `${API_BASE_URL}${BIZ_API_PREFIX}/api/dict/search/stream?query=${encodedQuery}&direction=${requestDirection}`;

    const httpRequest = http.createHttp();
    this.activeHttpRequest = httpRequest;
    let fullText = '';

    // ===== dataReceive：缓冲区累积 + \n\n 分割完整事件 =====
    httpRequest.on('dataReceive', (data: ArrayBuffer) => {
      // 并发保护：如果已不是当前活跃请求，忽略回调
      if (requestEpoch !== this.searchEpoch || this.activeHttpRequest !== httpRequest) return;

      const textDecoder = util.TextDecoder.create('utf-8');
      const uint8Array = new Uint8Array(data);
      const chunk = textDecoder.decodeToString(uint8Array);
      this.sseBuffer += chunk;

      // 按 \n\n 切分完整事件
      const events = this.sseBuffer.split('\n\n');
      // 最后一段可能不完整，留在缓冲区
      this.sseBuffer = events[events.length - 1];

      for (let e = 0; e < events.length - 1; e++) {
        const eventBlock = events[e].trim();
        if (eventBlock.length === 0) continue;

        // 每个事件块可能有多行，取 data: 行
        const blockLines = eventBlock.split('\n');
        for (let i = 0; i < blockLines.length; i++) {
          const line = blockLines[i];
          // 前缀兼容："data: " 或 "data:"
          if (!line.startsWith('data:')) continue;
          const payload = line.substring(5).trimStart();
          if (payload.length === 0) continue;

          try {
            const json = JSON.parse(payload) as Record<string, Object>;
            const type = json['type'] as string;
            const eventData = json['data'];

            if (type === 'cached') {
              console.info('[DictContent] SSE: Cache hit');
              this.sseGotResult = true;
              this.handleSearchResult(eventData as Record<string, Object>, query, requestDirection);
              this.isLoading = false;
              this.isStreaming = false;
            } else if (type === 'token') {
              const token = eventData as string;
              fullText += token;
              this.streamingText = fullText;
              this.parseStreamingContent(fullText);
            } else if (type === 'done') {
              console.info('[DictContent] SSE: Streaming done');
              this.sseGotResult = true;
              this.isStreaming = false;
              this.handleSearchResult(eventData as Record<string, Object>, query, requestDirection);
            } else if (type === 'error') {
              const errorMsg = json['message'] as string || 'Unknown error';
              console.error('[DictContent] SSE error: ' + errorMsg);
              this.isLoading = false;
              this.isStreaming = false;
              // 错误回退：仅触发一次
              if (!this.sseFallbackTriggered) {
                this.sseFallbackTriggered = true;
                this.performSearch(query, requestDirection, requestEpoch);
              }
              return;
            }
          } catch (_parseErr) {
            // 忽略单条解析错误
          }
        }
      }
    });

    // ===== dataEnd：结束兔底 =====
    httpRequest.on('dataEnd', () => {
      if (requestEpoch !== this.searchEpoch || this.activeHttpRequest !== httpRequest) return;
      console.info('[DictContent] SSE: Stream ended');
      if (!this.sseFallbackTriggered) this.isLoading = false;
      this.isStreaming = false;

      // 尝试解析缓冲区中残余数据
      if (this.sseBuffer.trim().length > 0) {
        const remaining = this.sseBuffer.trim();
        const remainLines = remaining.split('\n');
        for (let i = 0; i < remainLines.length; i++) {
          const line = remainLines[i];
          if (!line.startsWith('data:')) continue;
          const payload = line.substring(5).trimStart();
          if (payload.length === 0) continue;
          try {
            const json = JSON.parse(payload) as Record<string, Object>;
            const type = json['type'] as string;
            const eventData = json['data'];
            if (type === 'cached' || type === 'done') {
              this.sseGotResult = true;
              this.handleSearchResult(eventData as Record<string, Object>, query, requestDirection);
            }
          } catch (_e) { /* ignore */ }
        }
        this.sseBuffer = '';
      }

      // 如果整个流未收到 cached/done 且无结果，回退普通搜索
      if (!this.sseGotResult && this.aiSupplement === null && !this.sseFallbackTriggered) {
        console.warn('[DictContent] SSE: No result received, fallback to normal search');
        this.sseFallbackTriggered = true;
        this.performSearch(query, requestDirection, requestEpoch);
      } else {
        this.addToHistory(query);
        this.addToBrowseHistory(query);
        this.isInVocabulary = this.vocabularyService.hasWord(query);
      }

      // 完成后释放网络资源；fallback 已释放时不重复处理。
      if (this.activeHttpRequest === httpRequest) this.releaseStream(httpRequest);
    });

    try {
      // 构建签名鉴权请求头
      const apiService = ApiService.getInstance();
      const sseHeaders = await apiService.buildSignedHeaders('', true);
      if (requestEpoch !== this.searchEpoch || this.activeHttpRequest !== httpRequest) return;
      sseHeaders['Accept'] = 'text/event-stream';
      sseHeaders['Cache-Control'] = 'no-cache';
      sseHeaders['Content-Type'] = '';

      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        header: sseHeaders,
        expectDataType: http.HttpDataType.STRING
      };

      httpRequest.requestInStream(url, options, (err: BusinessError, data: number) => {
        if (requestEpoch !== this.searchEpoch || this.activeHttpRequest !== httpRequest) return;
        if (err) {
          console.error('[DictContent] SSE request error: ' + JSON.stringify(err));
          this.isLoading = false;
          this.isStreaming = false;
          this.releaseStream(httpRequest);
          // SSE请求失败回退（仅一次）
          if (!this.sseFallbackTriggered) {
            this.sseFallbackTriggered = true;
            this.performSearch(query, requestDirection, requestEpoch);
          }
        }
      });
    } catch (_error) {
      if (requestEpoch !== this.searchEpoch || this.activeHttpRequest !== httpRequest) return;
      this.releaseStream(httpRequest);
      this.isLoading = false;
      this.isStreaming = false;
      try {
        this.getUIContext().getPromptAction().showToast({ message: '查询暂时无法发送，请稍后重试', duration: 2500 });
      } catch (_toastError) { /* The page may have already closed. */ }
    }
  }

  /**
   * 实时解析流式内容 - 逐步构建aiSupplement以实现无缝过渡
   */
  private parseStreamingContent(text: string): void {
    // 确保aiSupplement存在
    if (this.aiSupplement === null) {
      this.aiSupplement = new DictAIResponse();
    }
    
    let needsUpdate = false;
    
    // 提取 ai_meaning 字段
    const meaningMatch = text.match(/"ai_meaning"\s*:\s*"([^"]+)"/);
    if (meaningMatch && meaningMatch[1] && this.aiSupplement.aiMeaning !== meaningMatch[1]) {
      this.aiSupplement.aiMeaning = meaningMatch[1];
      needsUpdate = true;
    }
    
    // 提取 word_type 字段
    const wordTypeMatch = text.match(/"word_type"\s*:\s*"([^"]+)"/);
    if (wordTypeMatch && wordTypeMatch[1] && this.aiSupplement.wordType !== wordTypeMatch[1]) {
      this.aiSupplement.wordType = wordTypeMatch[1];
      needsUpdate = true;
    }
    
    // 提取 hanja 字段
    const hanjaMatch = text.match(/"hanja"\s*:\s*"([^"]+)"/);
    if (hanjaMatch && hanjaMatch[1] && this.aiSupplement.hanja !== hanjaMatch[1]) {
      this.aiSupplement.hanja = hanjaMatch[1];
      needsUpdate = true;
    }
    
    // 提取 composition 字段
    const compositionMatch = text.match(/"composition"\s*:\s*"([^"]+)"/);
    if (compositionMatch && compositionMatch[1] && this.aiSupplement.composition !== compositionMatch[1]) {
      this.aiSupplement.composition = compositionMatch[1];
      needsUpdate = true;
    }
    
    // 提取 tips 字段
    const tipsMatch = text.match(/"tips"\s*:\s*"([^"]+)"/);
    if (tipsMatch && tipsMatch[1] && this.aiSupplement.tips !== tipsMatch[1]) {
      this.aiSupplement.tips = tipsMatch[1];
      needsUpdate = true;
    }
    
    // 触发UI更新：通过创建新对象
    if (needsUpdate) {
      const newAi = new DictAIResponse();
      newAi.aiMeaning = this.aiSupplement.aiMeaning;
      newAi.wordType = this.aiSupplement.wordType;
      newAi.hanja = this.aiSupplement.hanja;
      newAi.composition = this.aiSupplement.composition;
      newAi.tips = this.aiSupplement.tips;
      newAi.meanings = this.aiSupplement.meanings;
      newAi.collocations = this.aiSupplement.collocations;
      newAi.aiExamples = this.aiSupplement.aiExamples;
      newAi.synonyms = this.aiSupplement.synonyms;
      newAi.antonyms = this.aiSupplement.antonyms;
      newAi.relatedWords = this.aiSupplement.relatedWords;
      this.aiSupplement = newAi;
    }
  }

  /**
   * 处理搜索结果 - 解析JSON并更新状态
   */
  private handleSearchResult(data: Record<string, Object>, query: string, requestDirection: string): void {
    this.resultSource = data['source'] as string || '';
    this.resultDirection = data['direction'] as string || '';
    this.searchResults = [];
    
    // 解析aiSupplement
    const aiSupplement = data['aiSupplement'] as Record<string, Object> | null;
    if (aiSupplement) {
      const ai = new DictAIResponse();
      ai.aiMeaning = aiSupplement['aiMeaning'] as string || '';
      ai.wordType = aiSupplement['wordType'] as string || '';
      ai.hanja = aiSupplement['hanja'] as string || '';
      ai.composition = aiSupplement['composition'] as string || '';
      ai.tips = aiSupplement['tips'] as string || '';
      
      // 解析meanings
      const meanings = aiSupplement['meanings'] as Record<string, string>[];
      if (meanings) {
        const meaningList: MeaningDetail[] = [];
        for (let i = 0; i < meanings.length; i++) {
          const m = meanings[i];
          const md = new MeaningDetail();
          md.type = m['type'] || '';
          md.explanation = m['explanation'] || '';
          meaningList.push(md);
        }
        ai.meanings = meaningList;
      }
      
      // 解析collocations
      const collocations = aiSupplement['collocations'] as Record<string, string>[];
      if (collocations) {
        const colList: Collocation[] = [];
        for (let i = 0; i < collocations.length; i++) {
          const c = collocations[i];
          const col = new Collocation();
          col.phrase = c['phrase'] || '';
          col.meaning = c['meaning'] || '';
          col.exampleKo = c['example_ko'] || c['exampleKo'] || '';
          col.exampleZh = c['example_zh'] || c['exampleZh'] || '';
          colList.push(col);
        }
        ai.collocations = colList;
      }
      
      // 解析aiExamples
      const examples = aiSupplement['aiExamples'] as Record<string, string>[];
      if (examples) {
        const exList: CategoryExample[] = [];
        for (let i = 0; i < examples.length; i++) {
          const ex = examples[i];
          const catEx = new CategoryExample();
          catEx.category = ex['category'] || '';
          catEx.ko = ex['ko'] || '';
          catEx.zh = ex['zh'] || '';
          exList.push(catEx);
        }
        ai.aiExamples = exList;
      }
      
      // 解析synonyms
      const synonyms = aiSupplement['synonyms'] as Record<string, string>[];
      if (synonyms) {
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
      
      // 解析antonyms
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
      
      // 解析relatedWords
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
      
      this.aiSupplement = ai;
      this.streamingText = '';  // 清除流式文本，显示正式结果
    }

    this.saveSearchResultCache(
      query,
      this.searchResults,
      this.aiSupplement,
      this.resultSource,
      this.resultDirection,
      requestDirection
    );

    void this.refreshQuotaInfo();
  }

  onSearchTextChange(value: string) {
    this.searchText = value;
    // 不再自动搜索，等待用户手动触发
    if (value.trim().length === 0) {
      this.invalidateSearch();
      this.searchResults = [];
      this.aiSupplement = null;
      this.hasSearched = false;
    }
  }

  clearSearch() {
    this.invalidateSearch();
    this.searchText = '';
    this.searchResults = [];
    this.aiSupplement = null;
    this.hasSearched = false;
    this.resultSource = '';
  }

  showAddToWordbookDialog(word: WordEntry) {
    this.selectedWord = word;
    this.showAddDialog = true;
  }

  async confirmAddToWordbook() {
    if (this.selectedWord !== null) {
      const hangul = this.selectedWord.hangul;
      const meaning = this.selectedWord.primaryMeaning;
      const success = await this.vocabularyService.addWord(hangul, meaning, 'dictionary');
      if (success) {
        console.info(`[DictContent] Added word to wordbook: ${hangul}`);
        // 刷新收藏数据和生词本状态
        this.loadFavoriteData();
        if (this.searchText.trim() === hangul) {
          this.isInVocabulary = true;
        }
      } else {
        console.warn(`[DictContent] Failed to add word: ${hangul}`);
      }
    }
    this.showAddDialog = false;
    this.selectedWord = null;
  }

  private normalizeQuery(query: string): string {
    return query.trim().replace(/\s+/g, ' ').toLowerCase();
  }

  private cloneExampleSentence(item: ExampleSentence): ExampleSentence {
    return new ExampleSentence(item.ko, item.zh);
  }

  private cloneSense(item: Sense): Sense {
    const examples: ExampleSentence[] = [];
    for (let i = 0; i < item.examples.length; i++) {
      examples.push(this.cloneExampleSentence(item.examples[i]));
    }
    return new Sense(item.meaning, examples);
  }

  private cloneWordEntry(item: WordEntry): WordEntry {
    const entry = new WordEntry();
    entry.id = item.id;
    entry.hangul = item.hangul;
    entry.romanization = item.romanization;
    entry.pos = item.pos;
    entry.primaryMeaning = item.primaryMeaning;
    entry.topikLevel = item.topikLevel;
    entry.freqRank = item.freqRank;
    entry.lessonId = item.lessonId;
    entry.collocations = item.collocations.slice();

    const examples: ExampleSentence[] = [];
    for (let i = 0; i < item.examples.length; i++) {
      examples.push(this.cloneExampleSentence(item.examples[i]));
    }
    entry.examples = examples;

    const senses: Sense[] = [];
    for (let i = 0; i < item.senses.length; i++) {
      senses.push(this.cloneSense(item.senses[i]));
    }
    entry.senses = senses;
    return entry;
  }

  private cloneWordEntries(items: WordEntry[]): WordEntry[] {
    const entries: WordEntry[] = [];
    for (let i = 0; i < items.length; i++) {
      entries.push(this.cloneWordEntry(items[i]));
    }
    return entries;
  }

  private cloneMeaningDetail(item: MeaningDetail): MeaningDetail {
    return new MeaningDetail(item.type, item.explanation);
  }

  private cloneCollocation(item: Collocation): Collocation {
    const collocation = new Collocation();
    collocation.phrase = item.phrase;
    collocation.meaning = item.meaning;
    collocation.exampleKo = item.exampleKo;
    collocation.exampleZh = item.exampleZh;
    return collocation;
  }

  private cloneSynonymWord(item: SynonymWord): SynonymWord {
    const synonym = new SynonymWord();
    synonym.word = item.word;
    synonym.meaning = item.meaning;
    synonym.difference = item.difference;
    return synonym;
  }

  private cloneRelatedWord(item: RelatedWord): RelatedWord {
    const related = new RelatedWord();
    related.word = item.word;
    related.meaning = item.meaning;
    return related;
  }

  private cloneCategoryExample(item: CategoryExample): CategoryExample {
    const example = new CategoryExample();
    example.ko = item.ko;
    example.zh = item.zh;
    example.category = item.category;
    return example;
  }

  private cloneAiSupplement(aiSupplement: DictAIResponse | null): DictAIResponse | null {
    if (aiSupplement === null) {
      return null;
    }

    const ai = new DictAIResponse();
    ai.aiMeaning = aiSupplement.aiMeaning;
    ai.wordType = aiSupplement.wordType;
    ai.hanja = aiSupplement.hanja;
    ai.composition = aiSupplement.composition;
    ai.tips = aiSupplement.tips;

    const meanings: MeaningDetail[] = [];
    for (let i = 0; i < aiSupplement.meanings.length; i++) {
      meanings.push(this.cloneMeaningDetail(aiSupplement.meanings[i]));
    }
    ai.meanings = meanings;

    const collocations: Collocation[] = [];
    for (let i = 0; i < aiSupplement.collocations.length; i++) {
      collocations.push(this.cloneCollocation(aiSupplement.collocations[i]));
    }
    ai.collocations = collocations;

    const aiExamples: CategoryExample[] = [];
    for (let i = 0; i < aiSupplement.aiExamples.length; i++) {
      aiExamples.push(this.cloneCategoryExample(aiSupplement.aiExamples[i]));
    }
    ai.aiExamples = aiExamples;

    const synonyms: SynonymWord[] = [];
    for (let i = 0; i < aiSupplement.synonyms.length; i++) {
      synonyms.push(this.cloneSynonymWord(aiSupplement.synonyms[i]));
    }
    ai.synonyms = synonyms;

    const antonyms: RelatedWord[] = [];
    for (let i = 0; i < aiSupplement.antonyms.length; i++) {
      antonyms.push(this.cloneRelatedWord(aiSupplement.antonyms[i]));
    }
    ai.antonyms = antonyms;

    const relatedWords: RelatedWord[] = [];
    for (let i = 0; i < aiSupplement.relatedWords.length; i++) {
      relatedWords.push(this.cloneRelatedWord(aiSupplement.relatedWords[i]));
    }
    ai.relatedWords = relatedWords;

    return ai;
  }

  private saveSearchResultCache(
    query: string,
    results: WordEntry[],
    aiSupplement: DictAIResponse | null,
    resultSource: string,
    resultDirection: string,
    requestDirection: string
  ): void {
    const normalizedQuery = this.normalizeQuery(query);
    if (normalizedQuery.length === 0) {
      return;
    }

    const cacheEntry = new DictQueryCacheEntry();
    cacheEntry.resultSource = resultSource;
    cacheEntry.resultDirection = resultDirection;
    cacheEntry.results = this.cloneWordEntries(results);
    cacheEntry.aiSupplement = this.cloneAiSupplement(aiSupplement);
    cacheEntry.cachedAt = Date.now();
    this.searchResultCache.set(`${requestDirection}:${normalizedQuery}`, cacheEntry);
  }

  private tryApplyCachedResult(query: string, updateHistory: boolean, updateBrowseHistory: boolean, direction: string = this.searchDirection): boolean {
    const normalizedQuery = this.normalizeQuery(query);
    if (normalizedQuery.length === 0) {
      return false;
    }

    const cacheEntry = this.searchResultCache.get(`${direction}:${normalizedQuery}`);
    if (cacheEntry === undefined) {
      return false;
    }

    this.isLoading = false;
    this.isStreaming = false;
    this.hasSearched = true;
    this.showHistory = false;
    this.resultSource = cacheEntry.resultSource;
    this.resultDirection = cacheEntry.resultDirection;
    this.searchResults = this.cloneWordEntries(cacheEntry.results);
    this.aiSupplement = this.cloneAiSupplement(cacheEntry.aiSupplement);
    this.streamingText = '';
    this.streamingMeaning = '';
    this.streamingWordType = '';
    this.streamingTips = '';

    if (updateHistory) {
      this.addToHistory(query);
    }
    if (updateBrowseHistory) {
      this.addToBrowseHistory(query);
    }

    if (this.searchResults.length > 0) {
      this.isInVocabulary = this.vocabularyService.hasWord(this.searchResults[0].hangul);
    } else {
      this.isInVocabulary = this.vocabularyService.hasWord(query.trim());
    }
    return true;
  }

  build() {
    if (!this.authChecked) {
      Column() {
        LoadingProgress()
          .width(42)
          .height(42)
          .color(COLORS.PRIMARY)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .backgroundColor(COLORS.BACKGROUND)
      .onAppear(() => {
        void this.refreshAccessState(getContext(this));
      })
    } else if (this.requiresLogin) {
      AuthRequiredState({
        title: '注册后解锁词典查询',
        description: '试运行阶段需要先登录 / 注册，才能使用词典搜索、收藏与最近添加。',
        source: 'dict_tab_gate',
      })
        .onAppear(() => {
          void this.refreshAccessState(getContext(this));
        })
    } else if (this.showFavoritesPage) {
      // 收藏列表页面
      this.FavoritesListPage()
    } else {
      // 主内容
      Column() {
        if (!this.embedMode) {
          Column({ space: 8 }) {
            Row() {
              Text('一个词，更多表达')
                .fontSize(UI.TITLE_SIZE).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
              Blank()
              Text('LingAI').fontSize(12).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
            }.width('100%')
            Text('中韩双向查词，随手积累')
              .fontSize(12).fontColor(COLORS.TEXT_SECONDARY).width('100%')
          }
          .width('100%')
          .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: UI.CONTENT_TOP, bottom: 18 })
          .backgroundColor(UI.HEADER_BG)
          .border({ width: { bottom: 1 }, color: COLORS.BORDER })
        }
        Flex({ wrap: FlexWrap.Wrap }) {
          this.DirectionChip('自动识别', 'auto')
          this.DirectionChip('韩语 → 中文', 'ko2zh')
          this.DirectionChip('中文 → 韩语', 'zh2ko')
        }
        .width('100%')
        .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 14 })
        Text(this.searchDirection === 'ko2zh' ? '输入韩语单词' : this.searchDirection === 'zh2ko' ? '输入中文释义' : '输入韩语单词或中文释义')
          .width('100%').fontSize(12).fontColor(COLORS.TEXT_SECONDARY)
          .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 18, bottom: 7 })

      // Search bar
      Row() {
        Row() {
          Image($r('app.media.lg145_search'))
            .width(22)
            .height(22)
            .margin({ left: 16 })

          TextInput({ text: this.searchText, placeholder: '输入中文或韩文搜索', controller: this.textInputController })
            .layoutWeight(1)
            .height(52)
            .backgroundColor('transparent')
            .padding({ left: 8, right: 8 })
            .fontSize(16)
            .fontColor(COLORS.TEXT_PRIMARY)
            .placeholderColor(COLORS.TEXT_HINT)
            .onChange((value: string) => {
              this.onSearchTextChange(value);
            })
            .onSubmit(() => {
              this.performStreamingSearch();
            })
            .onFocus(() => {
              if (this.searchHistory.length > 0) {
                this.showHistory = true;
              }
            })
            .onBlur(() => {
              // 延迟隐藏，以便点击历史项时能触发
              setTimeout(() => {
                this.showHistory = false;
              }, 200);
            })

          // 搜索按钮
          Button() {
            Text('搜索')
              .fontSize(13)
              .fontWeight(FontWeight.Medium)
              .fontColor(UI.ON_BLUE)
          }
          .type(ButtonType.Normal)
          .width(56)
          .height(UI.TOUCH_MIN)
          .borderRadius(14)
          .backgroundColor(this.searchText.trim().length > 0 ? COLORS.PRIMARY : COLORS.TEXT_HINT)
          .margin({ right: 6 })
          .enabled(this.searchText.trim().length > 0)
          .onClick(() => {
            // 隐藏键盘并执行搜索
            this.textInputController.stopEditing();
            this.performStreamingSearch();
          })

          if (this.searchText.length > 0) {
            Button() {
              Image($r('app.media.ic_close'))
                .width(16)
                .height(16)
                .fillColor(COLORS.TEXT_HINT)
            }
            .type(ButtonType.Circle)
            .width(UI.TOUCH_MIN)
            .height(UI.TOUCH_MIN)
            .backgroundColor('transparent')
            .margin({ right: 4 })
            .onClick(() => {
              this.clearSearch();
            })
          }
        }
        .width('100%')
        .height(56)
        .backgroundColor(COLORS.SURFACE)
        .border({ width: 1, color: COLORS.BORDER })
        .borderRadius(UI.CONTROL_RADIUS)
      }
      .width('100%')
      .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, bottom: 12 })

      this.DictQuotaBanner()

      // 浏览历史导航条
      this.HistoryNavBar()

      // Content area
      if (this.isLoading) {
        // Loading state
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(COLORS.PRIMARY)

          Text('搜索中...')
            .fontSize(14)
            .fontColor(COLORS.TEXT_HINT)
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.isStreaming && this.aiSupplement === null) {
        // 流式刚开始，还没有任何内容
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(COLORS.PRIMARY)
          
          AssistantAvatar({ avatarSize: 56, expression: 'thinking' })
          Text('AI 正在分析…')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLORS.PRIMARY)
            .margin({ top: 12 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (!this.hasSearched) {
        // 主页内容：收藏卡片 + 最近添加
        Scroll() {
          Column() {
            // 收藏单词卡片
            this.FavoritesCard()

            this.SearchHistorySection()
            this.RecentWordsSection()
          }
          .width('100%')
          .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 12, bottom: 80 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)
      } else if (this.searchResults.length === 0 && this.aiSupplement === null) {
        // No results
        Column() {
          Image($r('app.media.lg145_search'))
            .width(48)
            .height(48)
            .opacity(0.5)

          Text('未找到相关结果')
            .fontSize(14)
            .fontColor(COLORS.TEXT_HINT)
            .margin({ top: 16 })

          Text('尝试其他关键词')
            .fontSize(12)
            .fontColor(COLORS.TEXT_HINT)
            .margin({ top: 4 })
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        // Results
        Scroll() {
          Column() {
            // Result hint
            if (this.resultSource !== '') {
              Row() {
                Text(this.resultDirection === 'ko2zh' ? '韩 → 中' : '中 → 韩')
                  .fontSize(12)
                  .fontColor(UI.BLUE)
                  .padding({ left: 10, right: 10, top: 6, bottom: 6 })
                  .backgroundColor(UI.BLUE_SOFT)
                  .borderRadius(10)

                if (this.resultSource === 'ai') {
                  Row() {
                    Image($r('app.media.lingai_assistant_twin_lights'))
                      .width(20)
                      .height(20)
                      .objectFit(ImageFit.Contain)

                    Text('AI 结果')
                      .fontSize(12)
                      .fontColor(COLORS.SECONDARY)
                      .margin({ left: 4 })
                  }
                  .margin({ left: 8 })
                }

                Blank()

                // 添加/移除生词本开关按钮
                if (this.isSingleWord(this.searchText.trim()) && this.aiSupplement !== null) {
                  Button() {
                    Row() {
                      Text(this.isInVocabulary ? '✅' : '📚')
                        .fontSize(14)
                      Text(this.isInVocabulary ? '已收录' : '生词本')
                        .fontSize(12)
                        .fontColor(this.isInVocabulary ? COLORS.SUCCESS : COLORS.PRIMARY)
                        .margin({ left: 4 })
                    }
                  }
                  .height(UI.TOUCH_MIN)
                  .backgroundColor(this.isInVocabulary ? UI.GREEN_SOFT : UI.BLUE_SOFT)
                  .borderRadius(14)
                  .padding({ left: 10, right: 10 })
                  .onClick(async () => {
                    const word = this.searchText.trim();
                    console.info(`[DictContent] Vocabulary button clicked, word: ${word}, isInVocabulary: ${this.isInVocabulary}`);
                    if (this.isInVocabulary) {
                      // 移除
                      console.info(`[DictContent] Deleting word: ${word}`);
                      const deleted = await this.vocabularyService.deleteWord(word);
                      console.info(`[DictContent] Delete result: ${deleted}`);
                      this.isInVocabulary = false;
                    } else {
                      // 添加
                      console.info(`[DictContent] Adding word: ${word}`);
                      const added = await this.vocabularyService.addWord(word, this.aiSupplement?.aiMeaning || '');
                      console.info(`[DictContent] Add result: ${added}`);
                      this.isInVocabulary = true;
                    }
                  })
                  .margin({ right: 8 })
                }

                Text(this.searchResults.length > 0
                  ? `${this.searchResults.length} 个词条`
                  : this.aiSupplement !== null && this.aiSupplement.aiMeaning.trim().length > 0
                    ? '已有释义'
                    : this.isStreaming ? '生成中' : '查看详解')
                  .fontSize(12)
                  .fontColor(COLORS.TEXT_HINT)
              }
              .width('100%')
              .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 8, bottom: 12 })
            }

            // Local results
            ForEach(this.searchResults, (word: WordEntry) => {
              Column() {
                WordCard({
                  word: word,
                  aiResponse: null,
                  showAddButton: true,
                  onPlayAudio: (text: string) => {
                    this.playAudio(text);
                  },
                  onAddToWordbook: () => {
                    this.showAddToWordbookDialog(word);
                  }
                })
              }
              .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 12 })
            })

            // AI supplement (always show when available)
            if (this.aiSupplement !== null) {
              Column() {
                this.AISupplementCard()
              }
              .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 12 })
            }

            // Bottom spacing
            Row()
              .height(80)
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }

      // Add to wordbook dialog
      if (this.showAddDialog) {
        this.AddWordbookDialog()
      }

      // Translate Toast overlay
      if (this.showTranslateToast) {
        Column() {
          // 背景遮罩 - 点击关闭
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('transparent')
            .onClick(() => {
              this.closeTranslateToast();
            })
          
          // Toast内容 - 居中显示
          Column() {
            this.TranslateToast()
          }
          .position({ x: '50%', y: '40%' })
          .translate({ x: '-50%', y: '-50%' })
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })
        .zIndex(9999)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BACKGROUND)
    .onAppear(() => {
      const context = getContext(this);
      void this.refreshAccessState(context);
      void this.loadUserInfo(context);
    })
    }
  }

  // ===== 新增Builder方法 =====

  @Builder
  DirectionChip(label: string, direction: string) {
    Button(label)
      .type(ButtonType.Normal).height(UI.TOUCH_MIN).fontSize(12)
      .fontColor(this.searchDirection === direction ? UI.ON_PRIMARY : COLORS.TEXT_SECONDARY)
      .backgroundColor(this.searchDirection === direction ? COLORS.PRIMARY : UI.SURFACE_MUTED)
      .borderRadius(10).padding({ left: 10, right: 10 }).margin({ right: 7, bottom: 4 })
      .onClick(() => {
        if (this.searchDirection === direction) return;
        this.invalidateSearch();
        this.searchDirection = direction;
        this.hasSearched = false;
        this.searchResults = [];
        this.aiSupplement = null;
        this.resultSource = '';
        this.resultDirection = '';
      })
  }

  @Builder
  FavoritesCard() {
    Row() {
      Text('随手查一查').fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
      Blank()
      Button() {
        Row({ space: 5 }) {
          Image($r('app.media.ic_bookmark')).width(16).height(16).fillColor(COLORS.PRIMARY)
          Text(`收藏 ${this.favoriteCount}`).fontSize(12).fontColor(COLORS.PRIMARY)
        }
      }
      .height(UI.TOUCH_MIN).type(ButtonType.Normal).backgroundColor(Color.Transparent)
      .onClick(() => { this.showFavoritesPage = true; })
    }.width('100%')
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(['안녕하세요', '감사합니다', '커피', '친구'], (word: string) => {
        Button(word)
          .type(ButtonType.Normal).height(UI.TOUCH_MIN).fontSize(13)
          .fontColor(COLORS.TEXT_PRIMARY).backgroundColor(UI.SURFACE_MUTED).borderRadius(10)
          .margin({ right: 7, bottom: 7 }).padding({ left: 12, right: 12 })
          .onClick(() => {
            this.searchDirection = 'ko2zh';
            this.searchText = word;
            this.performStreamingSearch();
          })
      })
    }.width('100%')
  }

  @Builder
  SearchHistorySection() {
    Row() {
      Text('最近查过').fontSize(17).fontWeight(FontWeight.Bold).fontColor(COLORS.TEXT_PRIMARY)
      Blank()
      Button('清空').height(UI.TOUCH_MIN).fontSize(12).fontColor(COLORS.PRIMARY)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.searchHistory = [];
          this.saveSearchHistory();
          this.showHistory = false;
        })
    }.width('100%').margin({ top: 15, bottom: 6 })
    if (this.searchHistory.length === 0) {
      Text('还没有查询记录。查过的词会留在这里。')
        .width('100%').fontSize(12).fontColor(COLORS.TEXT_SECONDARY).lineHeight(20)
    } else {
      ForEach(this.searchHistory, (word: string) => {
        Row({ space: 12 }) {
          Image($r('app.media.lg145_search')).width(18).height(18)
          Text(word).fontSize(14).fontColor(COLORS.TEXT_PRIMARY).layoutWeight(1)
          Text('↖').fontSize(18).fontColor(COLORS.TEXT_SECONDARY)
        }
        .width('100%').constraintSize({ minHeight: 60 })
        .padding({ top: 12, bottom: 12 })
        .border({ width: { bottom: 1 }, color: COLORS.BORDER })
        .onClick(() => { this.onHistoryItemClick(word); })
      })
    }
  }

  @Builder
  DictQuotaBanner() {
    Text(this.dictQuotaSummary())
      .fontSize(11).fontColor(COLORS.TEXT_SECONDARY).width('100%')
      .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, bottom: 8 })
  }

  @Builder
  RecentWordsSection() {
    Column() {
      // 标题
      Text('最近添加')
        .fontSize(17)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .margin({ bottom: 12 })
        .alignSelf(ItemAlign.Start)  // 标题左对齐

      // 单词列表
      if (this.recentWords.length > 0) {
        ForEach(this.recentWords, (word: RecentWordItem) => {
          Column() {
            Row() {
              Text(word.hangul)
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .fontColor(COLORS.TEXT_PRIMARY)
            }
            Text(word.roman)
              .fontSize(UI.CAPTION_SIZE)
              .fontColor(UI.BLUE)
              .margin({ top: 3 })
            Text(word.meaning)
              .fontSize(UI.BODY_SIZE)
              .fontColor(COLORS.TEXT_SECONDARY)
              .lineHeight(23)
              .margin({ top: 8 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ top: 15, bottom: 15 })
          .border({ width: { bottom: 1 }, color: COLORS.BORDER })
          .onClick(() => {
            this.detailWord = word.hangul;
            this.searchDirection = 'ko2zh';
            this.searchText = word.hangul;
            this.performStreamingSearch();
          })
        })
      } else {
        Text('暂无收藏单词')
          .fontSize(14)
          .fontColor(COLORS.TEXT_HINT)
          .padding({ top: 20, bottom: 20 })
          .alignSelf(ItemAlign.Start)
      }

      // 查看更多按钮（始终显示，仅当有收藏单词时）
      if (this.recentWords.length > 0) {
        // 分割线
        Divider()
          .color(COLORS.BORDER)
          .margin({ top: 16, bottom: 17 })

        // 按钮居中容器
        Row() {
          Button('查看更多 ▼')
            .type(ButtonType.Capsule)
            .height(UI.TOUCH_MIN)
            .backgroundColor(UI.BLUE_SOFT)
            .fontColor(UI.BLUE)
            .fontSize(14)
            .onClick(() => {
              if (this.recentWords.length < this.favoriteCount) {
                // 还有更多，加载更多
                this.recentWordsLimit += 3;
                this.loadFavoriteData();
              } else {
                // 已经到底，提示用户
                promptAction.showToast({ message: '已经到底了~', duration: 1500 });
              }
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)  // 内容左对齐
    .margin({ top: UI.SECTION_GAP })
  }

  private dictQuotaSummary(): string {
    if (this.userInfo.dailyDictLimit <= 0) {
      return '当前会员今日查词不限量';
    }
    if (this.userInfo.dailyDictRemaining <= 0) {
      return `今天的 ${this.userInfo.dailyDictLimit} 次查词额度已用完`;
    }
    return `今天还可免费查询 ${this.userInfo.dailyDictRemaining}/${this.userInfo.dailyDictLimit} 个词`;
  }

  private dictQuotaCaption(): string {
    if (this.userInfo.dailyDictLimit <= 0) {
      return '搜索、流式词典和快速翻译都会按统一会员规则放行。';
    }
    if (this.userInfo.dailyDictRemaining <= 0) {
      return '明天会自动恢复额度，同一词当天重复查看不重复扣减。';
    }
    return '搜索、流式词典和快速翻译共用额度，同一词当天重复查看不重复扣减。';
  }

  private dictQuotaBadge(): string {
    if (this.userInfo.dailyDictLimit <= 0) {
      return '不限量';
    }
    if (this.userInfo.dailyDictRemaining <= 0) {
      return '已用完';
    }
    return `剩 ${this.userInfo.dailyDictRemaining} 词`;
  }

  private dictQuotaBadgeTextColor(): string {
    if (this.userInfo.dailyDictLimit > 0 && this.userInfo.dailyDictRemaining <= 0) {
      return UI.DANGER_TEXT;
    }
    return COLORS.PRIMARY;
  }

  private dictQuotaBadgeBackground(): string {
    if (this.userInfo.dailyDictLimit > 0 && this.userInfo.dailyDictRemaining <= 0) {
      return UI.DANGER_SOFT;
    }
    return UI.GREEN_SOFT;
  }

  @Builder
  FavoritesListPage() {
    Column() {
      // 顶部导航
      Row() {
        Image($r('app.media.ic_back'))
          .width(UI.TOUCH_MIN)
          .height(UI.TOUCH_MIN)
          .padding(10)
          .fillColor(UI.BLUE)
          .backgroundColor(UI.BLUE_SOFT)
          .borderRadius(UI.CONTROL_RADIUS)
          .onClick(() => {
            this.showFavoritesPage = false;
          })
        Text('收藏单词')
          .fontSize(UI.TITLE_SIZE)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .margin({ left: 12 })
        Blank()
      }
      .width('100%')
      .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: UI.CONTENT_TOP, bottom: 20 })

      // 收藏列表
      Scroll() {
        Column() {
          ForEach(this.vocabularyService.getAllWords(), (word: VocabularyWord) => {
            Row() {
              Column() {
                Text(word.hangul)
                  .fontSize(22)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(COLORS.TEXT_PRIMARY)
                Text(word.meaning)
                  .fontSize(14)
                  .fontColor(COLORS.TEXT_SECONDARY)
                  .lineHeight(22)
                  .margin({ top: 6 })
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text('›')
                .fontSize(26)
                .fontColor(UI.BLUE)
            }
            .width('100%')
            .padding(20)
            .backgroundColor(COLORS.SURFACE)
            .borderRadius(UI.CARD_RADIUS)
            .margin({ bottom: 12 })
            .onClick(() => {
              this.showFavoritesPage = false;
              this.detailWord = word.hangul;
              this.searchDirection = 'ko2zh';
              this.searchText = word.hangul;
              this.performStreamingSearch();
            })
          })
        }
        .width('100%')
        .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, bottom: 80 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.Top)  // 内容紧靠顶部
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BACKGROUND)
  }

  @Builder
  HistoryNavBar() {
    if (this.browseHistory.length >= 2) {
      Row() {
        // 左箭头指示
        Text('‹')
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLORS.TEXT_HINT)
          .opacity(0.85)
          .margin({ right: 6 })
        
        // 可滑动的历史词条
        Scroll() {
          Row({ space: 10 }) {
            ForEach(this.browseHistory, (word: string, index: number) => {
              Text(word)
                .fontSize(13)
                .fontColor(index === this.currentHistoryIndex
                  ? UI.ON_PRIMARY
                  : (themeManager.isDark() ? '#cbd5e1' : COLORS.TEXT_SECONDARY))
                .backgroundColor(index === this.currentHistoryIndex
                  ? COLORS.PRIMARY
                  : (themeManager.isDark() ? 'rgba(148,163,184,0.18)' : COLORS.BORDER))
                .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                .textAlign(TextAlign.Center)
                .borderRadius(14)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .constraintSize({ maxWidth: 100, minHeight: UI.TOUCH_MIN })
                .onClick(() => {
                  this.onBrowseHistoryClick(word, index);
                })
            })
          }
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off)
        .layoutWeight(1)
        
        // 右箭头指示
        Text('›')
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLORS.TEXT_HINT)
          .opacity(0.85)
          .margin({ left: 6 })
      }
      .width('100%')
      .height(56)
      .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET })
      .backgroundColor(COLORS.BACKGROUND)
    }
  }

  @Builder
  TranslateToast() {
    Column() {
      // 翻译结果
      if (this.isTranslating) {
        Row() {
          LoadingProgress()
            .width(20)
            .height(20)
            .color(UI.BLUE)
          Text('翻译中...')
            .fontSize(14)
            .fontColor(COLORS.TEXT_PRIMARY)
            .margin({ left: 8 })
        }
      } else {
        Column() {
          // 原词
          Text(this.translateWord)
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
          
          // 翻译结果
          Text(this.translateResult)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.PRIMARY)
            .lineHeight(24)
            .margin({ top: 8 })
          
          // 查看详解链接
          Text('查看 AI 详解')
            .fontSize(13)
            .fontColor(UI.BLUE)
            .constraintSize({ minHeight: UI.TOUCH_MIN })
            .margin({ top: 8 })
            .onClick(() => {
              this.viewAIDetail();
            })
        }
        .alignItems(HorizontalAlign.Start)
      }
    }
    .padding(20)
    .backgroundColor(COLORS.SURFACE)
    .border({ width: 1, color: UI.BLUE_SOFT })
    .borderRadius(UI.CARD_RADIUS)
    .shadow({ radius: 12, color: UI.SHADOW, offsetY: 4 })
  }

  @Builder
  AISupplementCard() {
    Column() {
      Row({ space: 8 }) {
        AssistantAvatar({ avatarSize: 36, expression: this.isStreaming ? 'thinking' : 'happy', motionEnabled: this.isStreaming })
        Text('AI 词典')
          .fontSize(UI.CAPTION_SIZE)
          .fontWeight(FontWeight.Medium)
          .fontColor(UI.BLUE)
      }
      .width('100%')
      .margin({ bottom: 16 })
      // 标题栏：搜索词 + 词性 + 播放按钮
      Row() {
        Column() {
          Column({ space: 8 }) {
            Text(this.searchText.trim())
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
              .width('100%')

            if (this.aiSupplement !== null && this.aiSupplement.wordType !== '') {
              Text(this.aiSupplement.wordType)
                .fontSize(12)
                .fontColor(UI.BLUE)
                .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                .backgroundColor(UI.BLUE_SOFT)
                .borderRadius(8)
            }
            
            // 流式加载指示器
            if (this.isStreaming) {
              Row() {
                LoadingProgress()
                  .width(14)
                  .height(14)
                  .color(COLORS.PRIMARY)
                Text('分析中...')
                  .fontSize(12)
                  .fontColor(COLORS.PRIMARY)
                  .margin({ left: 4 })
              }
            }
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')

          // 汉字（如果有）
          if (this.aiSupplement !== null && this.aiSupplement.hanja !== '') {
            Text(`汉字: ${this.aiSupplement.hanja}`)
              .fontSize(15)
              .fontColor(COLORS.TEXT_SECONDARY)
              .margin({ top: 4 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 播放按钮
        if (this.searchText.trim().length > 0 && this.isKorean(this.searchText)) {
          PlayButton({
            text: this.searchText.trim(),
            buttonSize: 48,
            iconBtnSize: 24,
            color: COLORS.PRIMARY,
            onPlay: (text: string) => {
              this.playAudio(text);
            }
          })
        }
      }
      .width('100%')

      // 主要释义
      if (this.aiSupplement !== null && this.aiSupplement.aiMeaning !== '') {
        Text(this.aiSupplement.aiMeaning)
          .fontSize(22)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLORS.PRIMARY)
          .lineHeight(30)
          .width('100%')
          .margin({ top: 16 })
      }

      // 分隔线
      Divider()
        .color(COLORS.BORDER)
        .margin({ top: 16, bottom: 16 })

      // 词语构成
      if (this.aiSupplement !== null && this.aiSupplement.composition !== '') {
        this.SectionCard('词语构成', this.aiSupplement.composition)
      }

      // 含义详解
      if (this.aiSupplement !== null && this.aiSupplement.meanings.length > 0) {
        Column() {
          Text('含义详解')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLORS.TEXT_PRIMARY)
            .width('100%')

          ForEach(this.aiSupplement.meanings, (meaning: MeaningDetail, index: number) => {
            Column({ space: 8 }) {
              Text(`${index + 1}. [${meaning.type}]`)
                .fontSize(14)
                .fontColor(COLORS.SECONDARY)
                .fontWeight(FontWeight.Medium)
                .width('100%')

              Text(meaning.explanation)
                .fontSize(15)
                .fontColor(COLORS.TEXT_PRIMARY)
                .width('100%')
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .margin({ top: 16 })
          })
        }
        .width('100%')
        .padding(16)
        .margin({ top: 16 })
        .backgroundColor('transparent')
        .borderRadius(0)
      }

      // 常用搭配
      if (this.aiSupplement !== null && this.aiSupplement.collocations.length > 0) {
        Column() {
          Text('常用搭配')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLORS.TEXT_PRIMARY)
            .width('100%')

          ForEach(this.aiSupplement.collocations, (coll: Collocation) => {
            Column() {
              // 第一行：短语和播放按钮
              Row() {
                SelectableText({
                  text: coll.phrase,
                  fontSize: 17,
                  fontColor: this.getLightCardMainTextColor(),
                  fontWeight: FontWeight.Medium,
                  callbacks: this.getSelectableCallbacks()
                })

                  .layoutWeight(1)

                PlayIcon({
                  text: coll.phrase,
                  iconSize: 16,
                  color: COLORS.TEXT_HINT,
                  onPlay: (text: string) => {
                    this.playAudio(text);
                  }
                })
                  .margin({ left: 6 })

                Blank()
              }
              .width('100%')

              // 第二行：含义
              Text(coll.meaning)
                .fontSize(14)
                .fontColor(this.getLightCardSecondaryTextColor())
                .width('100%')
                .margin({ top: 4 })

              // 第三行：例句（如果有）
              if (coll.exampleKo !== '') {
                Text(coll.exampleKo)
                  .fontSize(12)
                  .fontColor(this.getLightCardHintTextColor())
                  .fontStyle(FontStyle.Italic)
                  .width('100%')
                  .margin({ top: 4 })
              }
            }
            .width('100%')
            .padding(10)
            .margin({ top: 8 })
            .backgroundColor(UI.SURFACE_MUTED)
            .borderRadius(12)
          })
        }
        .width('100%')
        .padding(16)
        .margin({ top: 16 })
        .backgroundColor('transparent')
        .borderRadius(0)
      }

      // 例句（分场景）
      if (this.aiSupplement !== null && this.aiSupplement.aiExamples.length > 0) {
        Column() {
          Text('例句')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLORS.TEXT_PRIMARY)
            .width('100%')

          ForEach(this.aiSupplement.aiExamples, (example: CategoryExample) => {
            Column() {
              Row() {
                if (example.category !== '') {
                  Text(example.category)
                    .fontSize(12)
                    .fontColor(UI.ON_BLUE)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .backgroundColor(UI.BLUE)
                    .borderRadius(8)
                }

                Blank()

                PlayIcon({
                  text: example.ko,
                  iconSize: 18,
                  color: COLORS.TEXT_HINT,
                  onPlay: (text: string) => {
                    this.playAudio(text);
                  }
                })
              }
              .width('100%')

              SelectableText({
                text: example.ko,
                fontSize: 18,
                fontColor: this.getLightCardMainTextColor(),
                callbacks: this.getSelectableCallbacks()
              })
                .width('100%')
                .margin({ top: 6 })

              Text(example.zh)
                .fontSize(14)
                .fontColor(this.getLightCardSecondaryTextColor())
                .margin({ top: 4 })
                .width('100%')
            }
            .width('100%')
            .padding(16)
            .margin({ top: 8 })
            .backgroundColor(UI.BLUE_SOFT)
            .borderRadius(14)
          })
        }
        .width('100%')
        .padding(16)
        .margin({ top: 16 })
        .backgroundColor('transparent')
        .borderRadius(0)
      }

      // 近义词（含区别说明）
      if (this.aiSupplement !== null && this.aiSupplement.synonyms.length > 0) {
        Column() {
          Text('近义词')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLORS.TEXT_PRIMARY)
            .width('100%')

          ForEach(this.aiSupplement.synonyms, (syn: SynonymWord) => {
            Column() {
              // 第一行：词语和播放按钮
              Row() {
                Text(syn.word)
                  .fontSize(15)
                  .fontColor(this.getLightCardMainTextColor())
                  .fontWeight(FontWeight.Medium)
                  .layoutWeight(1)

                PlayIcon({
                  text: syn.word,
                  iconSize: 14,
                  color: this.getLightCardHintTextColor(),
                  onPlay: (text: string) => {
                    this.playAudio(text);
                  }
                })
                  .margin({ left: 4 })

                Blank()
              }
              .width('100%')

              // 第二行：含义
              Text(syn.meaning)
                .fontSize(14)
                .fontColor(this.getLightCardSecondaryTextColor())
                .width('100%')
                .margin({ top: 4 })

              // 第三行：区别说明（如果有）
              if (syn.difference !== '') {
                Text(`区别: ${syn.difference}`)
                  .fontSize(12)
                  .fontColor(this.getLightCardHintTextColor())
                  .width('100%')
                  .margin({ top: 4 })
              }
            }
            .width('100%')
            .padding(10)
            .margin({ top: 6 })
            .backgroundColor(UI.GREEN_SOFT)
            .borderRadius(12)
            .alignItems(HorizontalAlign.Start)
          })
        }
        .width('100%')
        .margin({ top: 16 })
      }

      // 反义词
      if (this.aiSupplement !== null && this.aiSupplement.antonyms.length > 0) {
        Column() {
          Text('反义词')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLORS.TEXT_PRIMARY)
            .width('100%')

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.aiSupplement.antonyms, (ant: RelatedWord) => {
              Row() {
                Text(ant.word)
                  .fontSize(14)
                  .fontColor(this.getLightCardMainTextColor())
                  .layoutWeight(1)

                Text(ant.meaning)
                  .fontSize(12)
                  .fontColor(this.getLightCardHintTextColor())
                  .margin({ left: 4 })
                  .layoutWeight(1)

                PlayIcon({
                  text: ant.word,
                  iconSize: 12,
                  color: this.getLightCardHintTextColor(),
                  onPlay: (text: string) => {
                    this.playAudio(text);
                  }
                })
                  .margin({ left: 4 })
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .margin({ right: 8, top: 8 })
              .backgroundColor(UI.SURFACE_MUTED)
              .borderRadius(12)
            })
          }
          .width('100%')
        }
        .width('100%')
        .margin({ top: 16 })
      }

      // 扩展词汇
      if (this.aiSupplement !== null && this.aiSupplement.relatedWords.length > 0) {
        Column() {
          Text('扩展词汇')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLORS.TEXT_PRIMARY)
            .width('100%')

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.aiSupplement.relatedWords, (rel: RelatedWord) => {
              Row() {
                Text(rel.word)
                  .fontSize(14)
                  .fontColor(this.getLightCardMainTextColor())
                  .layoutWeight(1)

                Text(rel.meaning)
                  .fontSize(12)
                  .fontColor(this.getLightCardHintTextColor())
                  .margin({ left: 4 })
                  .layoutWeight(1)

                PlayIcon({
                  text: rel.word,
                  iconSize: 12,
                  color: this.getLightCardHintTextColor(),
                  onPlay: (text: string) => {
                    this.playAudio(text);
                  }
                })
                  .margin({ left: 4 })
              }
              .width('100%')
              .padding({ left: 10, right: 10, top: 6, bottom: 6 })
              .margin({ right: 8, top: 8 })
              .backgroundColor(UI.BLUE_SOFT)
              .borderRadius(12)
            })
          }
          .width('100%')
        }
        .width('100%')
        .margin({ top: 16 })
      }

      // 实用知识/提示
      if (this.aiSupplement !== null && this.aiSupplement.tips !== '') {
        Row() {
          Image($r('app.media.lingai_assistant_twin_lights'))
            .width(28)
            .height(28)
            .objectFit(ImageFit.Contain)

          Text(this.aiSupplement.tips)
            .fontSize(14)
            .fontColor(COLORS.TEXT_SECONDARY)
            .margin({ left: 8 })
            .layoutWeight(1)
        }
        .width('100%')
        .padding(16)
        .margin({ top: 16 })
        .backgroundColor(UI.GREEN_SOFT)
        .borderRadius(UI.CONTROL_RADIUS)
      }
    }
    .width('100%')
    .padding(UI.PAGE_INSET)
    .backgroundColor(COLORS.SURFACE)
    .border({ width: 1, color: COLORS.BORDER })
    .borderRadius(UI.CARD_RADIUS)
    .shadow({ radius: 6, color: UI.SHADOW, offsetY: 2 })
  }

  @Builder
  SectionCard(title: string, content: string) {
    Column() {
      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLORS.TEXT_PRIMARY)
        .width('100%')

      Text(content)
        .fontSize(15)
        .fontColor(COLORS.TEXT_SECONDARY)
        .width('100%')
        .margin({ top: 8 })
    }
    .width('100%')
    .padding(16)
    .margin({ top: 16 })
    .backgroundColor(UI.SURFACE_MUTED)
    .borderRadius(UI.CONTROL_RADIUS)
  }

  @Builder
  AddWordbookDialog() {
    Column() {
      // Overlay
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#00000066')
        .onClick(() => {
          this.showAddDialog = false;
          this.selectedWord = null;
        })
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .zIndex(100)

    // Dialog content
    Column() {
      Text('加入生词本')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLORS.TEXT_PRIMARY)

      if (this.selectedWord !== null) {
        Text(this.selectedWord.hangul)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.PRIMARY)
          .margin({ top: 12 })

        Text(this.selectedWord.primaryMeaning)
          .fontSize(16)
          .fontColor(COLORS.TEXT_SECONDARY)
          .margin({ top: 4 })
      }

      Text('加入单词本用于复习提醒')
        .fontSize(14)
        .fontColor(COLORS.TEXT_HINT)
        .margin({ top: 16 })

      Row() {
        Button('取消')
          .type(ButtonType.Normal)
          .backgroundColor(UI.SURFACE_MUTED)
          .fontColor(COLORS.TEXT_PRIMARY)
          .fontSize(16)
          .height(44)
          .layoutWeight(1)
          .borderRadius(UI.CONTROL_RADIUS)
          .onClick(() => {
            this.showAddDialog = false;
            this.selectedWord = null;
          })

        Button('确认添加')
          .type(ButtonType.Normal)
          .backgroundColor(COLORS.PRIMARY)
          .fontColor(UI.ON_PRIMARY)
          .fontSize(16)
          .height(44)
          .layoutWeight(1)
          .borderRadius(UI.CONTROL_RADIUS)
          .margin({ left: 12 })
          .onClick(() => {
            this.confirmAddToWordbook();
          })
      }
      .width('100%')
      .margin({ top: 24 })
    }
    .width('85%')
    .padding(24)
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(UI.CARD_RADIUS)
    .position({ x: '7.5%', y: '35%' })
    .zIndex(101)
  }
}
