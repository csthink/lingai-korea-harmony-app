/**
 * 关卡学习页面
 * 包含预习-练习-通关结算三个阶段
 * 适配 ArkTS 严格模式
 */
import router from '@ohos.router';
import { COLORS, MASTERY_THRESHOLD, MAX_SKIP_WORDS, QUIZ_TYPE_BASIC_RECOGNITION } from '../utils/Constants';
import { WordEntry, Quiz, QuizOption, QuizStem, LessonStatus, ExampleSentence } from '../models/DataModels';
import { FlashCard } from '../components/FlashCard';
import { QuizCard } from '../components/QuizCard';
import ApiService, { ApiError } from '../services/ApiService';
import AudioService from '../services/AudioService';
import { VocabularyService } from '../services/VocabularyService';
import { DictContent } from '../components/DictContent';
import { FloatingSpirit } from '../components/FloatingSpirit';
import { SpiritChatPanel } from '../components/SpiritChatPanel';
import TaskTrackingService from '../services/TaskTrackingService';
import PreferencesService from '../services/PreferencesService';
import preferences from '@ohos.data.preferences';
import { WORDS_PER_LESSON } from '../utils/Constants';
import { UI } from '../utils/UiTokens';

// 学习阶段
enum LearningPhase {
  PREVIEW = 0,
  PRACTICE = 1,
  RESULT = 2,
  LOADING = 3,
}

// 路由参数类
class LessonParams {
  lessonId: number = 1;
  level: number = 1;
  title: string = '';
}

class IndexRouteParams {
  tabIndex: number = 0;
  navFrom: string = '';
  navAt: number = 0;
}

@Entry
@Component
struct LessonPage {
  @State phase: LearningPhase = LearningPhase.LOADING;
  @State lessonInfo: LessonParams = new LessonParams();
  @State words: WordEntry[] = [];
  @State currentWordIndex: number = 0;
  @State loadingError: string = '';
  @State loadingErrorHint: string = '';
  @State loadingNeedLogin: boolean = false;
  @State loadingQuotaBlocked: boolean = false;
  @State navigatingToLogin: boolean = false;

  // 预习相关
  @State skippedCount: number = 0;
  @State cardOpacity: number = 1; // 卡片透明度用于淡入淡出动画
  @State vocabVersionKey: number = 0; // 用于触发FlashCard重新检查生词状态
  @State wordsPerLesson: number = 20; // 每关单词数（从设置读取）

  // 练习相关
  @State quizzes: Quiz[] = [];
  @State currentQuizIndex: number = 0;
  @State correctCount: number = 0;
  @State wrongCount: number = 0;
  @State wrongQuizzes: Quiz[] = [];  // 存储答错的题目

  // 结算相关
  @State masteredThisRound: number = 0;
  @State isPassed: boolean = false;
  
  // 查词相关
  @State showDictSheet: boolean = false;
  @State dictQuery: string = '';
  @State showSkipPreviewDialog: boolean = false;

  @State showSpiritPanel: boolean = false;

  private audioService: AudioService = AudioService.getInstance();
  private vocabularyService: VocabularyService = VocabularyService.getInstance();
  private taskService: TaskTrackingService = TaskTrackingService.getInstance();
  private preferencesService: PreferencesService = PreferencesService.getInstance();
  private lessonStepRecorded: boolean = false;
  private learningProgressAdvanced: boolean = false;

  async addToVocabulary(hangul: string, meaning: string) {
    await this.vocabularyService.addWord(hangul, meaning, 'lesson');
  }

  async removeFromVocabulary(hangul: string) {
    await this.vocabularyService.deleteWord(hangul);
  }

  playAudio(text: string) {
    console.info(`LessonPage: Playing audio for: ${text}`);
    this.audioService.playKorean(text);
  }

  stopAudio() {
    console.info('LessonPage: Stopping audio');
    this.audioService.stop();
  }

  aboutToAppear() {
    // 获取路由参数
    const params = router.getParams() as LessonParams;
    if (params) {
      this.lessonInfo = params;
    }

    // 设置音频缓存目录（使用应用Temp目录）
    const context = getContext(this);
    const cacheDir = context.tempDir;
    this.audioService.setCacheDir(cacheDir);
    console.info(`LessonPage: Set audio cache dir to ${cacheDir}`);
    
    // 初始化生词本服务
    this.vocabularyService.init(context);
    
    // 初始化任务追踪服务并开始计时
    this.taskService.init(context).then(() => {
      this.taskService.startStudyTimer();
    });

    // 加载关卡数据
    this.loadLessonData();
  }

  onPageShow() {
    // 页面显示时重新加载生词数据并刷新状态（从生词本返回时同步状态）
    this.vocabularyService.forceReload().then(() => {
      this.vocabVersionKey++;
    });
  }

  aboutToDisappear() {
    // 停止音频
    this.stopAudio();
    // 暂停学习计时
    this.taskService.pauseStudyTimer();
  }

  async loadLessonData() {
    this.phase = LearningPhase.LOADING;
    this.loadingError = '';
    this.loadingErrorHint = '';
    this.loadingNeedLogin = false;
    this.loadingQuotaBlocked = false;
    
    // 读取用户设置的每关单词数
    try {
      const context = getContext(this);
      const pref = await preferences.getPreferences(context, 'user_settings');
      this.wordsPerLesson = await pref.get('wordsPerLesson', WORDS_PER_LESSON) as number;
    } catch (e) {
      this.wordsPerLesson = WORDS_PER_LESSON;
    }
    
    try {
      const api = ApiService.getInstance();
      if (!api.getToken()) {
        this.loadingNeedLogin = true;
        this.setLoadingErrorState('登录状态已失效或未登录', '登录后即可继续学习当前关卡');
        return;
      }
      const response = await api.getLessonWords(this.lessonInfo.level, this.lessonInfo.lessonId, this.wordsPerLesson);
      
      if (response && response.words && response.words.length > 0) {
        // 转换API数据为WordEntry对象
        const wordList: WordEntry[] = [];
        for (let i = 0; i < response.words.length; i++) {
          const wordData = response.words[i] as Record<string, Object>;
          const word = new WordEntry();
          word.id = (wordData['id'] as number) || i + 1;
          word.hangul = (wordData['hangul'] as string) || '';
          word.romanization = (wordData['romanization'] as string) || '';
          word.pos = (wordData['pos'] as string) || '';
          word.primaryMeaning = (wordData['primaryMeaning'] as string) || '';
          word.collocations = (wordData['collocations'] as string[]) || [];
          word.topikLevel = (wordData['topikLevel'] as number) || 1;
          word.freqRank = (wordData['freqRank'] as number) || i + 1;
          word.lessonId = this.lessonInfo.lessonId;
          
          // 转换examples
          const examples = wordData['examples'] as object[];
          if (examples && examples.length > 0) {
            const exampleList: ExampleSentence[] = [];
            for (let j = 0; j < examples.length && j < 3; j++) {
              const ex = examples[j] as Record<string, string>;
              exampleList.push(new ExampleSentence(ex['ko'] || '', ex['zh'] || ''));
            }
            word.examples = exampleList;
          }
          
          wordList.push(word);
        }
        
        this.words = wordList;
        this.generateQuizzes();
        this.phase = LearningPhase.PREVIEW;
        console.info(`Loaded ${this.words.length} words from API`);
      } else {
        this.setLoadingErrorState('当前关卡暂无词表数据', '这关内容还在整理中，可以先学习其他关卡');
        // 保持 LOADING 状态，不进入学习流程
      }
    } catch (error) {
      console.error('Failed to load lesson data:', JSON.stringify(error));
      if (error instanceof ApiError && (error.code === 401 || error.code === 2001 || error.code === 2002)) {
        this.loadingNeedLogin = true;
        this.setLoadingErrorState('登录状态已失效，请重新登录', '登录后即可继续学习当前关卡');
        return;
      }
      if (error instanceof ApiError) {
        if (error.code === 4006) {
          this.loadingQuotaBlocked = true;
          this.setLoadingErrorState(error.message, '基础会员今日学习额度已用完，明天会自动恢复');
          return;
        }
        this.setLoadingErrorState(error.message, this.resolveLoadingErrorHint(error.message));
        return;
      }
      this.setLoadingErrorState('当前服务暂时不可用，请稍后重试', '可能正在短暂维护或网络波动，请稍后再试');
      // 保持 LOADING 状态，用户可通过重试按钮重新加载
    }
  }

  private setLoadingErrorState(message: string, hint: string = ''): void {
    this.loadingError = message;
    this.loadingErrorHint = hint;
  }

  private resolveLoadingErrorHint(message: string): string {
    if (this.loadingQuotaBlocked) {
      return '基础会员今日学习额度已用完，明天会自动恢复';
    }

    if (message.indexOf('服务') >= 0 || message.indexOf('网络') >= 0 || message.indexOf('重试') >= 0) {
      return '可能正在短暂维护或网络波动，请稍后再试';
    }

    if (message.indexOf('暂无词表') >= 0) {
      return '这关内容还在整理中，可以先学习其他关卡';
    }

    return '你可以点击下方按钮重新加载本关内容';
  }

  private loadingActionLabel(): string {
    if (this.loadingNeedLogin) {
      return '去登录';
    }
    if (this.loadingQuotaBlocked) {
      return '返回学习页';
    }
    return '重试';
  }

  private loadingTitleColor(): string {
    if (this.loadingNeedLogin || this.loadingQuotaBlocked) {
      return COLORS.WARNING;
    }
    return COLORS.TEXT_PRIMARY;
  }

  private loadingIconColor(): string {
    if (this.loadingNeedLogin || this.loadingQuotaBlocked) {
      return COLORS.WARNING;
    }
    return COLORS.PRIMARY;
  }

  private async goLoginTab(): Promise<void> {
    if (this.navigatingToLogin) {
      return;
    }
    this.navigatingToLogin = true;
    const targetParams = new IndexRouteParams();
    targetParams.tabIndex = 3;
    targetParams.navFrom = 'lesson_login';
    targetParams.navAt = Date.now();

    try {
      await router.replaceUrl({
        url: 'pages/Index',
        params: targetParams
      });
    } catch (replaceErr) {
      console.warn('[LessonPage] replaceUrl to login tab failed, fallback pushUrl:', JSON.stringify(replaceErr));
      try {
        await router.pushUrl({
          url: 'pages/Index',
          params: targetParams
        });
      } catch (pushErr) {
        console.error('[LessonPage] pushUrl fallback failed:', JSON.stringify(pushErr));
      }
    } finally {
      this.navigatingToLogin = false;
    }
  }


  generateQuizzes() {
    const quizList: Quiz[] = [];

    for (let i = 0; i < this.words.length; i++) {
      const word = this.words[i];
      const quiz = new Quiz();
      quiz.type = QUIZ_TYPE_BASIC_RECOGNITION;
      quiz.wordId = word.id;
      quiz.stem = new QuizStem(word.hangul, '');

      // 生成选项
      const options: QuizOption[] = [];
      options.push(new QuizOption('A', word.primaryMeaning, true));

      // 添加错误选项
      let optionIndex = 1;
      for (let j = 0; j < this.words.length && optionIndex < 4; j++) {
        if (j !== i) {
          const letter = String.fromCharCode(65 + optionIndex);
          options.push(new QuizOption(letter, this.words[j].primaryMeaning, false));
          optionIndex++;
        }
      }

      // 简单打乱选项
      this.shuffleOptions(options);

      // 重新分配字母
      for (let k = 0; k < options.length; k++) {
        options[k].id = String.fromCharCode(65 + k);
      }

      quiz.options = options;
      quizList.push(quiz);
    }

    this.quizzes = quizList;
  }

  shuffleOptions(options: QuizOption[]) {
    for (let i = options.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      const temp = options[i];
      options[i] = options[j];
      options[j] = temp;
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
      // 顶部导航栏
      this.TopBar()

      // 主内容区
      Column() {
      if (this.phase === LearningPhase.LOADING) {
        this.LoadingContent()
      } else if (this.phase === LearningPhase.PREVIEW) {
        this.PreviewContent()
      } else if (this.phase === LearningPhase.PRACTICE) {
        this.PracticeContent()
      } else {
        this.ResultContent()
      }
      }
      .width('100%')
      .layoutWeight(1)
      .margin({ bottom: 112 })
      .clip(true)
    }
    .width('100%')
    .height('100%')
      .backgroundColor(COLORS.BACKGROUND)

      // 悬浮精灵
      FloatingSpirit({
        onPress: () => {
          this.showSpiritPanel = true;
        }
      })
      .margin({ right: 20, bottom: 32 })
      .align(Alignment.BottomEnd)

      // 精灵对话面板
      if (this.showSpiritPanel) {
        SpiritChatPanel({
          currentContext: this.getSpiritContext(),
          onClose: () => {
            this.showSpiritPanel = false;
          }
        })
      }

      if (this.showSkipPreviewDialog) {
        this.SkipPreviewDialog()
      }
    }
    .width('100%')
    .height('100%')
    .bindSheet($$this.showDictSheet, this.DictSheetBuilder(), {
      height: SheetSize.MEDIUM,
      dragBar: true,
      backgroundColor: COLORS.SURFACE,
      onDisappear: () => { this.showDictSheet = false; }
    })
  }

  getSpiritContext(): string {
    let context = `当前正在学习: ${this.lessonInfo.title} (TOPIK ${this.lessonInfo.level === 0 ? '常考' : (this.lessonInfo.level <= 2 ? 'I' : 'II')})`;
    
    if (this.phase === LearningPhase.PREVIEW && this.words.length > 0) {
      const word = this.words[this.currentWordIndex];
      context += `\n当前单词: ${word.hangul} (${word.primaryMeaning})`;
      if (word.examples && word.examples.length > 0) {
        context += `\n例句: ${word.examples[0].ko}`;
      }
    } else if (this.phase === LearningPhase.PRACTICE && this.quizzes.length > 0) {
      const quiz = this.quizzes[this.currentQuizIndex];
      context += `\n当前练习: ${quiz.stem.display}`;
    }
    
    return context;
  }
  
  @Builder
  DictSheetBuilder() {
    Column() {
      DictContent({ 
        embedMode: true, 
        searchWordFromExternal: this.dictQuery 
      })
    }
    .width('100%')
    .height('100%')
  }

  // 打开词典搜索
  openDictionary(query: string) {
    this.dictQuery = query;
    this.showDictSheet = true;
  }

  @Builder
  LoadingContent() {
    Column() {
      if (this.loadingError === '') {
        LoadingProgress()
          .width(48)
          .height(48)
          .color(COLORS.PRIMARY)

        Text('正在加载词表...')
          .fontSize(UI.BODY_SIZE)
          .fontColor(COLORS.TEXT_SECONDARY)
          .margin({ top: 16 })
      } else {
        Image(this.loadingNeedLogin ? $r('app.media.ic_lock') : $r('app.media.ic_retry'))
          .width(64)
          .height(64)
          .fillColor(this.loadingIconColor())
          .opacity(0.8)

        Text(this.loadingError)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.loadingTitleColor())
          .margin({ top: 16 })
          .textAlign(TextAlign.Center)

        if (this.loadingErrorHint !== '') {
          Text(this.loadingErrorHint)
            .fontSize(13)
            .fontColor(COLORS.TEXT_SECONDARY)
            .lineHeight(20)
            .margin({ top: 8, left: 36, right: 36 })
            .textAlign(TextAlign.Center)
        }

        Button(this.loadingActionLabel())
          .type(ButtonType.Capsule)
          .backgroundColor(COLORS.PRIMARY)
          .fontColor(UI.ON_PRIMARY)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .height(UI.TOUCH_MIN)
          .padding({ left: 32, right: 32 })
          .margin({ top: 24 })
          .onClick(() => {
            if (this.loadingNeedLogin) {
              this.goLoginTab();
              return;
            }
            if (this.loadingQuotaBlocked) {
              router.back();
              return;
            }
            this.loadLessonData();
          })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)  
  }

  @Builder
  TopBar() {
    Row() {
      Button() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor(COLORS.TEXT_PRIMARY)
      }
      .type(ButtonType.Circle)
      .width(UI.TOUCH_MIN)
      .height(UI.TOUCH_MIN)
      .backgroundColor(UI.SURFACE_MUTED)
      .onClick(() => {
        router.back();
      })

      Column() {
        Text(this.lessonInfo.title)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)

        Text(this.getPhaseLabel())
          .fontSize(UI.CAPTION_SIZE)
          .fontColor(COLORS.PRIMARY)
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .backgroundColor(UI.GREEN_SOFT)
          .borderRadius(10)
          .margin({ top: 5 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      if (this.phase === LearningPhase.PREVIEW) {
        Button('直接练习')
          .fontSize(UI.CAPTION_SIZE)
          .fontColor(COLORS.TEXT_SECONDARY)
          .backgroundColor(UI.BLUE_SOFT)
          .height(UI.TOUCH_MIN)
          .borderRadius(14)
          .onClick(() => {
            this.showSkipPreviewDialog = true;
          })
      } else {
        Blank()
          .width(UI.TOUCH_MIN)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: UI.CONTENT_TOP, bottom: 16 })
    .backgroundColor(COLORS.SURFACE)
  }

  @Builder
  SkipPreviewDialog() {
    Column() {
      Column() {
        Column() {
          Text('跳过预习')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
            .textAlign(TextAlign.Center)
            .width('100%')

          Text('确定要跳过单词预习直接开始练习吗？')
            .fontSize(UI.BODY_SIZE)
            .lineHeight(24)
            .fontColor(COLORS.TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ top: 14, bottom: 24 })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 0 })

        Divider()
          .color(COLORS.BORDER)

        Row() {
          Button('取消')
            .type(ButtonType.Normal)
            .backgroundColor(Color.Transparent)
            .fontColor(COLORS.TEXT_SECONDARY)
            .fontSize(19)
            .fontWeight(FontWeight.Medium)
            .layoutWeight(1)
            .height(56)
            .borderRadius(0)
            .onClick(() => {
              this.showSkipPreviewDialog = false;
            })

          Column()
            .width(1)
            .height(24)
            .backgroundColor(COLORS.BORDER)

          Button('确定')
            .type(ButtonType.Normal)
            .backgroundColor(Color.Transparent)
            .fontColor(COLORS.PRIMARY)
            .fontSize(19)
            .fontWeight(FontWeight.Bold)
            .layoutWeight(1)
            .height(56)
            .borderRadius(0)
            .onClick(() => {
              this.showSkipPreviewDialog = false;
              this.skipPreview();
            })
        }
        .width('100%')
      }
      .width('86%')
      .backgroundColor(COLORS.SURFACE)
      .borderRadius(22)
      .border({ width: 1, color: COLORS.BORDER })
      .shadow({ radius: 24, color: UI.SHADOW, offsetY: 6 })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor('rgba(2,6,23,0.52)')
    .onClick(() => {
      this.showSkipPreviewDialog = false;
    })
  }

  getPhaseLabel(): string {
    if (this.phase === LearningPhase.PREVIEW) {
      return '预习阶段';
    } else if (this.phase === LearningPhase.PRACTICE) {
      return '练习阶段';
    } else {
      return '学习结算';
    }
  }

  @Builder
  PreviewContent() {
    Column() {

      if (this.words.length > 0 && this.currentWordIndex < this.words.length) {
        FlashCard({
          word: this.words[this.currentWordIndex],
          index: this.currentWordIndex,
          total: this.words.length,
          contentOpacity: this.cardOpacity,
          vocabVersionKey: this.vocabVersionKey,
          onPlayAudio: (text: string) => {
            this.playAudio(text);
          },
          onStopAudio: () => {
            this.stopAudio();
          },
          onNext: () => {
            this.nextPreviewWord();
          },
          onPrevious: () => {
            this.prevPreviewWord();
          },
          onSkip: () => {
            this.skipPreviewWord();
          },
          onAddVocabulary: (hangul: string, meaning: string) => {
            this.addToVocabulary(hangul, meaning);
          },
          onRemoveVocabulary: (hangul: string) => {
            this.removeFromVocabulary(hangul);
          },
          isInVocabulary: (hangul: string): boolean => {
            return this.vocabularyService.hasWord(hangul);
          },
          onSearch: (text: string) => {
            this.openDictionary(text);
          },
        })
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }

  skipPreview() {
    this.phase = LearningPhase.PRACTICE;
    this.currentQuizIndex = 0;
  }

  private recordLessonStepOnce() {
    if (this.lessonStepRecorded) {
      return;
    }

    this.lessonStepRecorded = true;
    this.taskService.recordLessonStep().catch((error: Object) => {
      this.lessonStepRecorded = false;
      console.error('[LessonPage] recordLessonStep failed:', JSON.stringify(error));
    });
  }

  private async advanceLearningProgressIfCurrent(): Promise<void> {
    if (!this.isPassed || this.learningProgressAdvanced) {
      return;
    }

    try {
      const context = getContext(this);
      await this.preferencesService.init(context);
      const state = await this.preferencesService.getLearningState();
      if (state.currentLevel !== this.lessonInfo.level || state.currentLesson !== this.lessonInfo.lessonId) {
        return;
      }

      await this.preferencesService.updateCurrentProgress(this.lessonInfo.level, this.lessonInfo.lessonId + 1);
      this.learningProgressAdvanced = true;
      console.info(`[LessonPage] learning progress advanced to lesson ${this.lessonInfo.lessonId + 1}`);
    } catch (error) {
      console.error('[LessonPage] advanceLearningProgressIfCurrent failed:', JSON.stringify(error));
    }
  }

  nextPreviewWord() {
    // 记录关卡步骤（首次完成预习步骤时）
    this.recordLessonStepOnce();
    
    if (this.currentWordIndex < this.words.length - 1) {
      // 淡出动画
      animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
        this.cardOpacity = 0;
      });
      // 延迟切换内容并淡入
      setTimeout(() => {
        this.currentWordIndex++;
        animateTo({ duration: 150, curve: Curve.EaseIn }, () => {
          this.cardOpacity = 1;
        });
      }, 150);
    } else {
      this.phase = LearningPhase.PRACTICE;
      this.currentQuizIndex = 0;
    }
  }
  
  prevPreviewWord() {
    if (this.currentWordIndex > 0) {
      // 淡出动画
      animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
        this.cardOpacity = 0;
      });
      // 延迟切换内容并淡入
      setTimeout(() => {
        this.currentWordIndex--;
        animateTo({ duration: 150, curve: Curve.EaseIn }, () => {
          this.cardOpacity = 1;
        });
      }, 150);
    }
  }

  skipPreviewWord() {
    this.skippedCount++;
    this.nextPreviewWord();
  }

  @Builder
  PracticeContent() {
    Column() {
      Row() {
        Progress({ value: this.currentQuizIndex + 1, total: this.quizzes.length, type: ProgressType.Linear })
          .width('100%')
          .height(4)
          .color(COLORS.PRIMARY)
          .backgroundColor(UI.GREEN_SOFT)
      }
      .width('100%')
      .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 12 })

      Row() {
        Row() {
          Image($r('app.media.ic_check'))
            .width(16)
            .height(16)
            .fillColor(COLORS.SUCCESS)
          Text(`${this.correctCount}`)
            .fontSize(UI.CAPTION_SIZE)
            .fontColor(COLORS.SUCCESS)
            .margin({ left: 4 })
        }

        Row() {
          Image($r('app.media.ic_close'))
            .width(16)
            .height(16)
            .fillColor(COLORS.ERROR)
          Text(`${this.wrongCount}`)
            .fontSize(UI.CAPTION_SIZE)
            .fontColor(COLORS.ERROR)
            .margin({ left: 4 })
        }
        .margin({ left: 16 })
      }
      .width('100%')
      .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 12 })

      if (this.quizzes.length > 0 && this.currentQuizIndex < this.quizzes.length) {
        QuizCard({
          quiz: this.quizzes[this.currentQuizIndex],
          onPlayAudio: (text: string) => {
            this.playAudio(text);
          },
          onAnswer: (isCorrect: boolean) => {
            if (isCorrect) {
              this.correctCount++;
            } else {
              this.wrongCount++;
              // 存储答错的题目
              this.wrongQuizzes.push(this.quizzes[this.currentQuizIndex]);
            }
          },
          onNext: () => {
            this.nextQuiz();
          },
        })
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }

  async nextQuiz() {
    if (this.currentQuizIndex < this.quizzes.length - 1) {
      this.currentQuizIndex++;
    } else {
      this.calculateResult();
      await this.advanceLearningProgressIfCurrent();
      this.recordLessonStepOnce();
      this.phase = LearningPhase.RESULT;
    }
  }

  calculateResult() {
    const totalQuestions = this.quizzes.length;
    const accuracy = this.correctCount / totalQuestions;
    this.isPassed = accuracy >= MASTERY_THRESHOLD;
    this.masteredThisRound = this.correctCount;
  }

  @Builder
  ResultContent() {
    Scroll() {
    Column() {
      Blank().height(UI.TOUCH_MIN)

      Image(this.isPassed ? $r('app.media.ic_trophy') : $r('app.media.ic_retry'))
        .width(100)
        .height(100)
        .fillColor(this.isPassed ? UI.WARM : COLORS.TEXT_SECONDARY)

      Text(this.isPassed ? '恭喜通关！' : '继续加油！')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .margin({ top: 24 })

      Row() {
        Text('正确率')
          .fontSize(UI.BODY_SIZE)
          .fontColor(COLORS.TEXT_SECONDARY)

        Text(`${Math.round(this.correctCount / this.quizzes.length * 100)}%`)
          .fontSize(36)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.isPassed ? COLORS.SUCCESS : COLORS.WARNING)
          .margin({ left: 12 })
      }
      .margin({ top: 24 })

      Row() {
        this.StatItem('答对', `${this.correctCount}`, COLORS.SUCCESS)
        
        // 答错可点击重练
        Column() {
          Text(`${this.wrongCount}`)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.ERROR)

          Row() {
            Text('答错')
              .fontSize(UI.CAPTION_SIZE)
              .fontColor(COLORS.TEXT_SECONDARY)
            if (this.wrongCount > 0) {
              Text(' ▶')
                .fontSize(UI.CAPTION_SIZE)
                .fontColor(COLORS.ERROR)
            }
          }
          .margin({ top: 4 })
        }
        .onClick(() => {
          if (this.wrongCount > 0) {
            this.retryWrongQuizzes();
          }
        })
        
        this.StatItem('本轮掌握', `${this.masteredThisRound}`, COLORS.PRIMARY)
      }
      .width('100%')
      .padding({ top: 20, bottom: 20 })
      .backgroundColor(COLORS.SURFACE)
      .borderRadius(UI.CARD_RADIUS)
      .border({ width: 1, color: COLORS.BORDER })
      .margin({ top: 24 })
      .justifyContent(FlexAlign.SpaceEvenly)

      Blank()

      Column() {
        if (this.isPassed) {
          Button('进入下一关')
            .type(ButtonType.Capsule)
            .width('100%')
            .height(52)
            .backgroundColor(COLORS.PRIMARY)
            .fontSize(UI.BODY_SIZE)
            .fontColor(UI.ON_PRIMARY)
            .onClick(() => {
              // 直接进入下一关
              const nextLessonId = this.lessonInfo.lessonId + 1;
              router.replaceUrl({
                url: 'pages/LessonPage',
                params: {
                  lessonId: nextLessonId,
                  level: this.lessonInfo.level,
                  title: `第${nextLessonId}关`
                }
              });
            })
        } else {
          Button('再练一次')
            .type(ButtonType.Capsule)
            .width('100%')
            .height(52)
            .backgroundColor(COLORS.PRIMARY)
            .fontSize(UI.BODY_SIZE)
            .fontColor(UI.ON_PRIMARY)
            .onClick(() => {
              this.restartPractice();
            })
        }

        Button('返回关卡列表')
          .type(ButtonType.Capsule)
          .width('100%')
          .height(52)
          .backgroundColor('transparent')
          .fontColor(COLORS.TEXT_SECONDARY)
          .fontSize(UI.BODY_SIZE)
          .border({ width: 1, color: COLORS.BORDER })
          .margin({ top: 12 })
          .onClick(() => {
            router.back();
          })
      }
      .width('100%')
      .padding({ top: 24, bottom: 24 })
    }
    .width('100%')
    .constraintSize({ minHeight: 560 })
    .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, bottom: 48 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
  }

  @Builder
  StatItem(label: string, value: string, color: string) {
    Column() {
      Text(value)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)

      Text(label)
        .fontSize(UI.CAPTION_SIZE)
        .fontColor(COLORS.TEXT_SECONDARY)
        .margin({ top: 4 })
    }
  }

  restartPractice() {
    this.currentQuizIndex = 0;
    this.correctCount = 0;
    this.wrongCount = 0;
    this.wrongQuizzes = [];
    this.phase = LearningPhase.PRACTICE;
  }
  
  // 只重练答错的题目
  retryWrongQuizzes() {
    if (this.wrongQuizzes.length > 0) {
      this.quizzes = [...this.wrongQuizzes];
      this.wrongQuizzes = [];
      this.currentQuizIndex = 0;
      this.correctCount = 0;
      this.wrongCount = 0;
      this.phase = LearningPhase.PRACTICE;
    }
  }
}
