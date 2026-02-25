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
import ApiService from '../services/ApiService';
import AudioService from '../services/AudioService';
import { VocabularyService } from '../services/VocabularyService';
import { DictContent } from '../components/DictContent';
import { FloatingSpirit } from '../components/FloatingSpirit';
import { SpiritChatPanel } from '../components/SpiritChatPanel';
import TaskTrackingService from '../services/TaskTrackingService';
import preferences from '@ohos.data.preferences';
import { WORDS_PER_LESSON } from '../utils/Constants';

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

@Entry
@Component
struct LessonPage {
  @State phase: LearningPhase = LearningPhase.LOADING;
  @State lessonInfo: LessonParams = new LessonParams();
  @State words: WordEntry[] = [];
  @State currentWordIndex: number = 0;
  @State loadingError: string = '';

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
  private lessonStepRecorded: boolean = false;

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
        this.loadingError = '当前关卡暂无词表数据';
        // 保持 LOADING 状态，不进入学习流程
      }
    } catch (error) {
      console.error('Failed to load lesson data');
      this.loadingError = '加载失败，请检查网络后重试';
      // 保持 LOADING 状态，用户可通过重试按钮重新加载
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
          .fontSize(16)
          .fontColor(COLORS.TEXT_SECONDARY)
          .margin({ top: 16 })
      } else {
        Image($r('app.media.ic_retry'))
          .width(64)
          .height(64)
          .fillColor(COLORS.TEXT_SECONDARY)
          .opacity(0.5)

        Text(this.loadingError)
          .fontSize(16)
          .fontColor(COLORS.WARNING)
          .margin({ top: 16 })
          .textAlign(TextAlign.Center)

        Button('重试')
          .type(ButtonType.Capsule)
          .backgroundColor(COLORS.PRIMARY)
          .fontColor('#ffffff')
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .height(40)
          .padding({ left: 32, right: 32 })
          .margin({ top: 24 })
          .onClick(() => {
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
      .width(40)
      .height(40)
      .backgroundColor('transparent')
      .onClick(() => {
        router.back();
      })

      Column() {
        Text(this.lessonInfo.title)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLORS.TEXT_PRIMARY)

        Text(this.getPhaseLabel())
          .fontSize(12)
          .fontColor(COLORS.TEXT_SECONDARY)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Center)

      if (this.phase === LearningPhase.PREVIEW) {
        Button('直接练习')
          .fontSize(14)
          .fontColor(COLORS.TEXT_SECONDARY)
          .backgroundColor('transparent')
          .onClick(() => {
            this.showSkipPreviewDialog = true;
          })
      } else {
        Blank()
          .width(40)
      }
    }
    .width('100%')
    .padding({ left: 8, right: 8, top: 42, bottom: 8 })
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
            .fontSize(16)
            .lineHeight(24)
            .fontColor(COLORS.TEXT_SECONDARY)
            .textAlign(TextAlign.Center)
            .width('100%')
            .margin({ top: 14, bottom: 24 })
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 24, bottom: 0 })

        Divider()
          .color('rgba(148,163,184,0.24)')

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
            .backgroundColor('rgba(148,163,184,0.24)')

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
      .border({ width: 1, color: 'rgba(148,163,184,0.22)' })
      .shadow({ radius: 24, color: 'rgba(0,0,0,0.50)', offsetY: 6 })
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

  nextPreviewWord() {
    // 记录关卡步骤（首次完成预习步骤时）
    if (!this.lessonStepRecorded) {
      this.taskService.recordLessonStep();
      this.lessonStepRecorded = true;
    }
    
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
          .backgroundColor(COLORS.BORDER)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })

      Row() {
        Row() {
          Image($r('app.media.ic_check'))
            .width(16)
            .height(16)
            .fillColor(COLORS.SUCCESS)
          Text(`${this.correctCount}`)
            .fontSize(14)
            .fontColor(COLORS.SUCCESS)
            .margin({ left: 4 })
        }

        Row() {
          Image($r('app.media.ic_close'))
            .width(16)
            .height(16)
            .fillColor(COLORS.ERROR)
          Text(`${this.wrongCount}`)
            .fontSize(14)
            .fontColor(COLORS.ERROR)
            .margin({ left: 4 })
        }
        .margin({ left: 16 })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8 })

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

  nextQuiz() {
    if (this.currentQuizIndex < this.quizzes.length - 1) {
      this.currentQuizIndex++;
    } else {
      this.calculateResult();
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
    Column() {
      Blank().height(40)

      Image(this.isPassed ? $r('app.media.ic_trophy') : $r('app.media.ic_retry'))
        .width(100)
        .height(100)

      Text(this.isPassed ? '恭喜通关！' : '继续加油！')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(COLORS.TEXT_PRIMARY)
        .margin({ top: 24 })

      Row() {
        Text('正确率')
          .fontSize(16)
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
              .fontSize(14)
              .fontColor(COLORS.TEXT_SECONDARY)
            if (this.wrongCount > 0) {
              Text(' ▶')
                .fontSize(12)
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
      .margin({ top: 32 })
      .justifyContent(FlexAlign.SpaceEvenly)

      Blank()

      Column() {
        if (this.isPassed) {
          Button('进入下一关')
            .type(ButtonType.Capsule)
            .width('100%')
            .height(48)
            .backgroundColor(COLORS.PRIMARY)
            .fontSize(16)
            .fontColor('#FFFFFF')
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
            .height(48)
            .backgroundColor(COLORS.PRIMARY)
            .fontSize(16)
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.restartPractice();
            })
        }

        Button('返回关卡列表')
          .type(ButtonType.Capsule)
          .width('100%')
          .height(48)
          .backgroundColor('transparent')
          .fontColor(COLORS.TEXT_SECONDARY)
          .fontSize(16)
          .border({ width: 1, color: COLORS.BORDER })
          .margin({ top: 12 })
          .onClick(() => {
            router.back();
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24, bottom: 24 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  StatItem(label: string, value: string, color: string) {
    Column() {
      Text(value)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(color)

      Text(label)
        .fontSize(14)
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
