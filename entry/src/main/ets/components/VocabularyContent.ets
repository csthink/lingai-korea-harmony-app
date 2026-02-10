/**
 * 生词本内容组件
 * 显示待复习生词和全部生词列表
 */
import { COLORS } from '../utils/Constants';
import { VocabularyService, VocabularyWord } from '../services/VocabularyService';
import AudioService from '../services/AudioService';
import curves from '@ohos.curves';
import promptAction from '@ohos.promptAction';

@Component
export struct VocabularyContent {
  @Prop @Watch('onActiveChange') isActive: boolean = false;
  @State reviewWords: VocabularyWord[] = [];
  @State allWords: VocabularyWord[] = [];
  @State currentTab: number = 0; // 0=待复习, 1=全部
  @State reviewCount: number = 0;
  @State isLoading: boolean = true;
  @State searchKeyword: string = ''; // 搜索关键词
  @State reviewOffset: number = 0; // 复习分页偏移量
  @State isRefreshing: boolean = false; // 下拉刷新状态
  @State listOpacity: number = 1; // 列表透明度（用于翻页动画）
  @State listTranslateY: number = 0; // 列表垂直位移（用于翻页动画）
  @State allWordsOffset: number = 0; // 全部列表分页偏移量
  @State allWordsTotalCount: number = 0; // 全部生词总数
  @State isAllRefreshing: boolean = false; // 全部列表下拉刷新状态
  @State allListOpacity: number = 1; // 全部列表透明度
  @State allListTranslateY: number = 0; // 全部列表垂直位移

  // 点击生词跳转到词典搜索的回调
  onSearchWord?: (word: string) => void;

  private vocabularyService: VocabularyService = VocabularyService.getInstance();
  private audioService: AudioService = AudioService.getInstance();

  // 当Tab切换到生词本时刷新数据
  onActiveChange() {
    if (this.isActive) {
      console.info('[VocabularyContent] Tab activated, refreshing data');
      this.loadData();
    }
  }

  async aboutToAppear() {
    const context = getContext(this);
    await this.vocabularyService.init(context);
    this.audioService.setCacheDir(context.tempDir);
    // 直接从单例加载数据，内存中的数据已是最新
    this.loadData();
  }

  loadData() {
    this.reviewWords = this.vocabularyService.getWordsToReview(this.reviewOffset);
    this.allWordsTotalCount = this.vocabularyService.getWordCount();
    this.allWords = this.vocabularyService.getAllWords().slice(this.allWordsOffset, this.allWordsOffset + 20);
    this.reviewCount = this.vocabularyService.getReviewCount();
    this.isLoading = false;
  }

  // 重置分页并重新加载
  resetAndLoad() {
    this.reviewOffset = 0;
    this.loadData();
  }

  // 平滑翻页加载（向下翻页）
  loadNextPage() {
    if (this.reviewOffset + this.reviewWords.length >= this.reviewCount) return;
    
    // 淡出 + 上滑（较慢，让用户感知）
    animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      this.listOpacity = 0;
      this.listTranslateY = -60;
    });
    
    // 延迟加载数据并淡入（弹簧效果）
    setTimeout(() => {
      this.reviewOffset += 20;
      this.reviewWords = this.vocabularyService.getWordsToReview(this.reviewOffset);
      this.listTranslateY = 80; // 从更远的下方进入
      animateTo({ 
        duration: 350, 
        curve: curves.springMotion(0.5, 0.8) // 弹簧曲线
      }, () => {
        this.listOpacity = 1;
        this.listTranslateY = 0;
      });
    }, 200);
  }

  // 平滑翻页加载（向上翻页）
  loadPreviousPage() {
    if (this.reviewOffset <= 0) return;
    
    // 淡出 + 下滑（较慢，让用户感知）
    animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      this.listOpacity = 0;
      this.listTranslateY = 60;
    });
    
    // 延迟加载数据并淡入（弹簧效果）
    setTimeout(() => {
      this.reviewOffset = Math.max(0, this.reviewOffset - 20);
      this.reviewWords = this.vocabularyService.getWordsToReview(this.reviewOffset);
      this.listTranslateY = -80; // 从更远的上方进入
      animateTo({ 
        duration: 350, 
        curve: curves.springMotion(0.5, 0.8) // 弹簧曲线
      }, () => {
        this.listOpacity = 1;
        this.listTranslateY = 0;
      });
    }, 200);
  }

  // 全部列表 - 向下翻页
  loadAllNextPage() {
    if (this.allWordsOffset + this.allWords.length >= this.allWordsTotalCount) return;
    
    animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      this.allListOpacity = 0;
      this.allListTranslateY = -60;
    });
    
    setTimeout(() => {
      this.allWordsOffset += 20;
      this.allWords = this.vocabularyService.getAllWords().slice(this.allWordsOffset, this.allWordsOffset + 20);
      this.allListTranslateY = 80;
      animateTo({ 
        duration: 350, 
        curve: curves.springMotion(0.5, 0.8)
      }, () => {
        this.allListOpacity = 1;
        this.allListTranslateY = 0;
      });
    }, 200);
  }

  // 全部列表 - 向上翻页
  loadAllPreviousPage() {
    if (this.allWordsOffset <= 0) return;
    
    animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      this.allListOpacity = 0;
      this.allListTranslateY = 60;
    });
    
    setTimeout(() => {
      this.allWordsOffset = Math.max(0, this.allWordsOffset - 20);
      this.allWords = this.vocabularyService.getAllWords().slice(this.allWordsOffset, this.allWordsOffset + 20);
      this.allListTranslateY = -80;
      animateTo({ 
        duration: 350, 
        curve: curves.springMotion(0.5, 0.8)
      }, () => {
        this.allListOpacity = 1;
        this.allListTranslateY = 0;
      });
    }, 200);
  }

  playAudio(text: string) {
    this.audioService.playKorean(text);
  }

  async markReviewed(word: VocabularyWord) {
    await this.vocabularyService.markReviewed(word.hangul);
    this.loadData();
  }

  async deleteWord(word: VocabularyWord) {
    await this.vocabularyService.deleteWord(word.hangul);
    this.loadData();
  }

  async reviveWord(word: VocabularyWord) {
    await this.vocabularyService.reviveWord(word.hangul);
    this.loadData();
  }

  // 获取过滤后的待复习词列表
  getFilteredReviewWords(): VocabularyWord[] {
    if (this.searchKeyword.trim().length === 0) {
      return this.reviewWords;
    }
    const keyword = this.searchKeyword.trim().toLowerCase();
    return this.reviewWords.filter(w =>
      w.hangul.toLowerCase().includes(keyword) ||
      w.meaning.toLowerCase().includes(keyword)
    );
  }

  // 获取过滤后的全部词列表
  getFilteredAllWords(): VocabularyWord[] {
    if (this.searchKeyword.trim().length === 0) {
      return this.allWords;
    }
    const keyword = this.searchKeyword.trim().toLowerCase();
    return this.allWords.filter(w =>
      w.hangul.toLowerCase().includes(keyword) ||
      w.meaning.toLowerCase().includes(keyword)
    );
  }

  formatDate(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getMonth() + 1}/${date.getDate()}`;
  }

  getNextReviewText(word: VocabularyWord): string {
    if (word.reviewCount >= 6) {
      return '已完成';
    }
    const now = Date.now();
    if (word.nextReviewTime <= now) {
      return '待复习';
    }
    const days = Math.ceil((word.nextReviewTime - now) / (24 * 60 * 60 * 1000));
    return `${days}天后`;
  }

  // 获取复习阶段标签
  getReviewStageText(reviewCount: number): string {
    const stages = ['D0', 'D1', 'D3', 'D7', 'D14', 'D30'];
    if (reviewCount >= stages.length) {
      return '✓';
    }
    return stages[reviewCount];
  }

  // 获取来源文本
  getSourceText(source: string): string {
    if (source === 'dictionary') return '词典';
    if (source === 'lesson') return '学习';
    if (source === 'selection') return '选词';
    return '添加';
  }

  build() {
    Column() {
      // 标题
      Row() {
        Text('生词本')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
        
        Blank()
        
        // 清空数据按钮（测试用）
        Button('清空数据')
          .type(ButtonType.Normal)
          .height(32)
          .padding({ left: 12, right: 12 })
          .backgroundColor(COLORS.ERROR + '20')
          .fontColor(COLORS.ERROR)
          .fontSize(12)
          .borderRadius(16)
          .onClick(() => {
            promptAction.showDialog({
              title: '清空生词本',
              message: '确定要清空所有生词数据吗？此操作不可恢复。',
              buttons: [
                { text: '取消', color: COLORS.TEXT_SECONDARY },
                { text: '确定', color: COLORS.ERROR }
              ]
            }).then((resp: promptAction.ShowDialogSuccessResponse) => {
              if (resp.index === 1) {
                this.vocabularyService.clearAllWords().then(() => {
                  this.loadData();
                  promptAction.showToast({ message: '生词本已清空' });
                });
              }
            });
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 16, bottom: 8 })

      // Tab切换
      Row() {
        this.TabButton('待复习', this.reviewCount, 0)
        this.TabButton('全部', this.allWords.length, 1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      // 搜索框
      Row() {
        TextInput({ placeholder: '搜索单词或释义...', text: this.searchKeyword })
          .height(40)
          .layoutWeight(1)
          .backgroundColor(COLORS.SURFACE)
          .borderRadius(20)
          .padding({ left: 16, right: 16 })
          .onChange((value: string) => {
            this.searchKeyword = value;
          })

        if (this.searchKeyword.length > 0) {
          Button() {
            Text('✕')
              .fontSize(16)
              .fontColor(COLORS.TEXT_HINT)
          }
          .type(ButtonType.Circle)
          .width(32)
          .height(32)
          .backgroundColor('transparent')
          .margin({ left: 8 })
          .onClick(() => {
            this.searchKeyword = '';
          })
        }
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 8 })

      // 内容区
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(COLORS.PRIMARY)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.currentTab === 0) {
        this.ReviewList()
      } else {
        this.AllWordsList()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(COLORS.BACKGROUND)
  }

  @Builder
  TabButton(title: string, count: number, index: number) {
    Column() {
      Row() {
        Text(title)
          .fontSize(14)
          .fontColor(this.currentTab === index ? COLORS.PRIMARY : COLORS.TEXT_SECONDARY)
        if (count > 0) {
          Text(` (${count})`)
            .fontSize(12)
            .fontColor(this.currentTab === index ? COLORS.PRIMARY : COLORS.TEXT_HINT)
        }
      }

      Divider()
        .width('100%')
        .height(2)
        .backgroundColor(this.currentTab === index ? COLORS.PRIMARY : 'transparent')
        .margin({ top: 4 })
    }
    .layoutWeight(1)
    .padding({ top: 8, bottom: 4 })
    .onClick(() => {
      this.currentTab = index;
    })
  }

  @Builder
  ReviewList() {
    if (this.getFilteredReviewWords().length === 0) {
      Column() {
        Text('🎉')
          .fontSize(48)
        Text('今日复习已完成')
          .fontSize(16)
          .fontColor(COLORS.TEXT_SECONDARY)
          .margin({ top: 12 })
        Text('继续添加新词汇或明天再来')
          .fontSize(14)
          .fontColor(COLORS.TEXT_HINT)
          .margin({ top: 4 })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      Column() {
        // 分页信息提示
        Row() {
          Text(`📋 待复习 ${this.reviewCount} 个`)
            .fontSize(12)
            .fontColor(COLORS.TEXT_HINT)
          if (this.reviewCount > 20) {
            Text(` · 当前 ${this.reviewOffset + 1}-${Math.min(this.reviewOffset + this.reviewWords.length, this.reviewCount)}`)
              .fontSize(12)
              .fontColor(COLORS.TEXT_HINT)
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 4, bottom: 8 })

        // 下拉返回上一页 + 列表
        Refresh({ refreshing: $$this.isRefreshing }) {
          List({ space: 8 }) {
            ForEach(this.getFilteredReviewWords(), (word: VocabularyWord) => {
              ListItem() {
                this.WordCard(word, true)
              }
            })
          }
          .width('100%')
          .height('100%')
          .padding({ left: 16, right: 16 })
          .opacity(this.listOpacity)
          .translate({ y: this.listTranslateY })
          .onReachEnd(() => {
            // 滚动到底部，平滑加载下一批
            this.loadNextPage();
          })
        }
        .onRefreshing(() => {
          // 下拉刷新，平滑加载上一批
          this.loadPreviousPage();
          this.isRefreshing = false;
        })
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .layoutWeight(1)
    }
  }

  @Builder
  AllWordsList() {
    if (this.getFilteredAllWords().length === 0) {
      Column() {
        Text('📚')
          .fontSize(48)
        Text('生词本是空的')
          .fontSize(16)
          .fontColor(COLORS.TEXT_SECONDARY)
          .margin({ top: 12 })
        Text('在词典中搜索并添加生词')
          .fontSize(14)
          .fontColor(COLORS.TEXT_HINT)
          .margin({ top: 4 })
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
    } else {
      Column() {
        // 分页信息提示
        Row() {
          Text(`📚 全部 ${this.allWordsTotalCount} 个`)
            .fontSize(12)
            .fontColor(COLORS.TEXT_HINT)
          if (this.allWordsTotalCount > 20) {
            Text(` · 当前 ${this.allWordsOffset + 1}-${Math.min(this.allWordsOffset + this.allWords.length, this.allWordsTotalCount)}`)
              .fontSize(12)
              .fontColor(COLORS.TEXT_HINT)
          }
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ top: 4, bottom: 8 })

        // 下拉返回上一页 + 列表
        Refresh({ refreshing: $$this.isAllRefreshing }) {
          List({ space: 8 }) {
            ForEach(this.getFilteredAllWords(), (word: VocabularyWord) => {
              ListItem() {
                this.WordCard(word, false)
              }
              .swipeAction({
                end: {
                  builder: () => { this.DeleteSwipeButton(word) }
                },
                start: this.vocabularyService.isWordDueForReview(word.hangul) ? undefined : {
                  builder: () => { this.ReviveSwipeButton(word) }
                }
              })
            })
          }
          .width('100%')
          .height('100%')
          .padding({ left: 16, right: 16 })
          .opacity(this.allListOpacity)
          .translate({ y: this.allListTranslateY })
          .onReachEnd(() => {
            this.loadAllNextPage();
          })
        }
        .onRefreshing(() => {
          this.loadAllPreviousPage();
          this.isAllRefreshing = false;
        })
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .layoutWeight(1)
    }
  }

  @Builder
  DeleteSwipeButton(word: VocabularyWord) {
    Row() {
      Button() {
        Text('删除')
          .fontSize(14)
          .fontColor('#FFFFFF')
      }
      .width(70)
      .height('100%')
      .backgroundColor('#FF3B30')
      .type(ButtonType.Normal)
      .onClick(() => {
        this.deleteWord(word);
      })
    }
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  ReviveSwipeButton(word: VocabularyWord) {
    Row() {
      Button() {
        Text('复习')
          .fontSize(14)
          .fontColor('#FFFFFF')
      }
      .width(70)
      .height('100%')
      .backgroundColor(COLORS.SUCCESS)
      .type(ButtonType.Normal)
      .onClick(() => {
        this.reviveWord(word);
      })
    }
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  WordCard(word: VocabularyWord, showReviewButton: boolean) {
    Row() {
      // 播放按钮
      Button() {
        Text('🔊')
          .fontSize(18)
      }
      .type(ButtonType.Circle)
      .width(40)
      .height(40)
      .backgroundColor(COLORS.SURFACE)
      .onClick(() => {
        this.playAudio(word.hangul);
      })

      // 词汇信息
      Column() {
        Row() {
          Text(word.hangul)
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLORS.TEXT_PRIMARY)
          
          // 复习阶段徽章
          Text(this.getReviewStageText(word.reviewCount))
            .fontSize(10)
            .fontColor(word.reviewCount >= 6 ? COLORS.SUCCESS : COLORS.PRIMARY)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .backgroundColor(word.reviewCount >= 6 ? '#E8F8E8' : '#E8F4FD')
            .borderRadius(8)
            .margin({ left: 8 })
        }
        Text(word.meaning)
          .fontSize(14)
          .fontColor(COLORS.TEXT_SECONDARY)
          .margin({ top: 2 })
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 12 })

      // 状态/操作
      if (showReviewButton) {
        Button('已复习')
          .fontSize(12)
          .height(32)
          .backgroundColor(COLORS.PRIMARY)
          .onClick(() => {
            this.markReviewed(word);
          })
      } else {
        Column() {
          Text(this.getNextReviewText(word))
            .fontSize(12)
            .fontColor(word.reviewCount >= 6 ? COLORS.SUCCESS : COLORS.TEXT_HINT)
          Row() {
            Text(this.getSourceText(word.source))
              .fontSize(10)
              .fontColor(COLORS.TEXT_HINT)
            Text(` · ${this.formatDate(word.addedTime)}`)
              .fontSize(10)
              .fontColor(COLORS.TEXT_HINT)
          }
          .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.End)
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(12)
    .onClick(() => {
      // 点击卡片跳转到词典搜索
      if (this.onSearchWord) {
        this.onSearchWord(word.hangul);
      }
    })
  }
}
