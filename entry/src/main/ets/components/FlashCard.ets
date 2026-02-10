/**
 * 预习闪卡组件
 * 用于关卡预习阶段展示单词
 * 适配 ArkTS 严格模式
 */
import { COLORS } from '../utils/Constants';
import { WordEntry, ExampleSentence } from '../models/DataModels';
import promptAction from '@ohos.promptAction';

@Component
export struct FlashCard {
  @Prop @Watch('onWordChange') word: WordEntry = new WordEntry();
  @Prop index: number = 0;
  @Prop total: number = 0;
  @Prop contentOpacity: number = 1; // 内容区域透明度，用于淡入淡出动画
  @Prop @Watch('onVocabVersionChange') vocabVersionKey: number = 0; // 触发重新检查生词状态
  @State isFlipped: boolean = false;
  @State isPlaying: boolean = false;
  @State animationAngle: number = 0;

  onPlayAudio?: (text: string) => void;
  onStopAudio?: () => void;
  onNext?: () => void;
  onPrevious?: () => void;
  onSkip?: () => void;
  onAddVocabulary?: (hangul: string, meaning: string) => void;
  onRemoveVocabulary?: (hangul: string) => void;
  isInVocabulary?: (hangul: string) => boolean;
  onSearch?: (text: string) => void;
  
  @State isAddedToVocab: boolean = false;
  @State selectedText: string = '';
  
  aboutToAppear() {
    // 初始化时检查当前单词是否已在生词本
    this.checkVocabularyStatus();
    // 自动播放单词读音
    this.autoPlayAudio();
  }
  
  // 单词变化时重置翻转状态并检查收录状态
  onWordChange() {
    this.isFlipped = false;
    this.stopAnimation();
    this.checkVocabularyStatus();
    this.selectedText = ''; // 清空选区状态
    // 自动播放新单词读音
    this.autoPlayAudio();
  }

  // 生词状态版本变化时重新检查（从生词本返回时触发）
  onVocabVersionChange() {
    this.checkVocabularyStatus();
  }
  
  autoPlayAudio() {
    // 延迟播放，等待UI渲染完成
    setTimeout(() => {
      if (this.onPlayAudio && this.word.hangul) {
        this.startAnimation();
        this.onPlayAudio(this.word.hangul);
        // 3秒后停止动画
        setTimeout(() => {
          this.stopAnimation();
        }, 3000);
      }
    }, 300);
  }
  
  checkVocabularyStatus() {
    if (this.isInVocabulary) {
      this.isAddedToVocab = this.isInVocabulary(this.word.hangul);
    } else {
      this.isAddedToVocab = false;
    }
  }

  // 播放动画定时器
  private animationTimer: number = -1;

  aboutToDisappear() {
    this.stopAnimation();
  }

  startAnimation() {
    this.isPlaying = true;
    this.animationAngle = 0;
    // 使用定时器创建旋转动画
    this.animationTimer = setInterval(() => {
      this.animationAngle = (this.animationAngle + 30) % 360;
    }, 100);
  }

  stopAnimation() {
    this.isPlaying = false;
    if (this.animationTimer !== -1) {
      clearInterval(this.animationTimer);
      this.animationTimer = -1;
    }
    this.animationAngle = 0;
  }

  handleSpeakerClick() {
    if (this.isPlaying) {
      // 正在播放，停止
      this.stopAnimation();
      if (this.onStopAudio) {
        this.onStopAudio();
      }
    } else {
      // 开始播放
      this.startAnimation();
      if (this.onPlayAudio) {
        this.onPlayAudio(this.word.hangul);
      }
      // 3秒后自动停止动画（估计播放时间）
      setTimeout(() => {
        this.stopAnimation();
      }, 3000);
    }
  }

  build() {
    Column() {
      Row() {
        Text(`${this.index + 1} / ${this.total}`)
          .fontSize(14)
          .fontColor(COLORS.TEXT_SECONDARY)

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })

      Stack() {
        // 正面 - 韩文
        Column() {
          // 单词区域 - 只有这部分应用透明度动画
          Column() {
            Text(this.word.hangul)
              .fontSize(48)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
              .copyOption(CopyOptions.LocalDevice)
              .onTextSelectionChange((start, end) => {
                 if (start >= 0 && end > start && end <= this.word.hangul.length) {
                   this.selectedText = this.word.hangul.substring(start, end);
                 }
              })
              .bindSelectionMenu(TextSpanType.TEXT, this.SelectionMenuBuilder, TextResponseType.LONG_PRESS)

            Text(this.word.romanization)
              .fontSize(18)
              .fontColor(COLORS.TEXT_SECONDARY)
              .margin({ top: 8 })
          }
          .opacity(this.contentOpacity)

          // 喇叭按钮 - 固定大小，只改变内部颜色
          Stack() {
            // 背景圆圈 - 固定大小56x56
            Circle()
              .width(56)
              .height(56)
              .fill(this.isPlaying ? COLORS.PRIMARY : COLORS.PRIMARY + '20')

            // 喇叭图标
            Image($r('app.media.ic_speaker'))
              .width(28)
              .height(28)
              .fillColor(this.isPlaying ? '#FFFFFF' : COLORS.PRIMARY)
          }
          .width(56)
          .height(56)
          .margin({ top: 24 })
          .onClick(() => {
            this.handleSpeakerClick();
          })

          // 固定高度的提示区域 - 不使用条件渲染避免布局跳动
          Row() {
            if (this.isPlaying) {
              LoadingProgress()
                .width(16)
                .height(16)
                .color(COLORS.PRIMARY)
            }
            Text(this.isPlaying ? '播放中...' : '点击喇叭听发音')
              .fontSize(14)
              .fontColor(this.isPlaying ? COLORS.PRIMARY : COLORS.TEXT_HINT)
              .margin({ left: this.isPlaying ? 8 : 0 })
          }
          .height(24)
          .margin({ top: 16 })
          .justifyContent(FlexAlign.Center)

          Text('点击卡片查看释义')
            .fontSize(14)
            .fontColor(COLORS.TEXT_HINT)
            .margin({ top: 16 })
          
          // 导航按钮 - 不应用透明度动画
          Row({ space: 16 }) {
            Button('上一个')
              .type(ButtonType.Capsule)
              .width(120)
              .height(44)
              .backgroundColor(this.index > 0 ? COLORS.SURFACE : '#E0E0E0')
              .fontSize(16)
              .fontColor(this.index > 0 ? COLORS.TEXT_PRIMARY : COLORS.TEXT_HINT)
              .border({ width: 1, color: COLORS.BORDER })
              .enabled(this.index > 0)
              .onClick(() => {
                this.isFlipped = false;
                this.stopAnimation();
                if (this.onPrevious) {
                  this.onPrevious();
                }
              })
            
            Button('下一个')
              .type(ButtonType.Capsule)
              .width(120)
              .height(44)
              .backgroundColor(COLORS.PRIMARY)
              .fontSize(16)
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.isFlipped = false;
                this.stopAnimation();
                if (this.onNext) {
                  this.onNext();
                }
              })
          }
          .margin({ top: 24 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .visibility(this.isFlipped ? Visibility.Hidden : Visibility.Visible)
        // 背面 - 释义
        Column() {
          // 内容区域 - 应用透明度动画
          Column() {
            Text(this.word.hangul)
              .fontSize(32)
              .fontWeight(FontWeight.Medium)
              .fontColor(COLORS.TEXT_PRIMARY)
              .copyOption(CopyOptions.LocalDevice)
              .onTextSelectionChange((start, end) => {
                 if (start >= 0 && end > start && end <= this.word.hangul.length) {
                   this.selectedText = this.word.hangul.substring(start, end);
                 }
              })
              .bindSelectionMenu(TextSpanType.TEXT, this.SelectionMenuBuilder, TextResponseType.LONG_PRESS)

            Text(this.word.primaryMeaning)
              .fontSize(24)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.PRIMARY)
              .margin({ top: 16 })

            if (this.word.pos !== '') {
              Text(`[${this.word.pos}]`)
                .fontSize(14)
                .fontColor(COLORS.TEXT_SECONDARY)
                .margin({ top: 8 })
            }

            if (this.word.examples.length > 0) {
              Column() {
                Text(this.word.examples[0].ko)
                  .fontSize(16)
                  .fontColor(COLORS.TEXT_PRIMARY)
                  .textAlign(TextAlign.Center)
                  .copyOption(CopyOptions.LocalDevice)
                  .onTextSelectionChange((start, end) => {
                     const text = this.word.examples[0].ko;
                     if (start >= 0 && end > start && end <= text.length) {
                       this.selectedText = text.substring(start, end);
                     }
                  })
                  .bindSelectionMenu(TextSpanType.TEXT, this.SelectionMenuBuilder, TextResponseType.LONG_PRESS)

                Text(this.word.examples[0].zh)
                  .fontSize(14)
                  .fontColor(COLORS.TEXT_SECONDARY)
                  .margin({ top: 4 })
              }
              .width('100%')
              .margin({ top: 24 })
              .padding({ left: 20, right: 20 })
            }
            
            // 收录/取消生词按钮
            Button(this.isAddedToVocab ? '✕ 取消收录' : '📖 收录生词')
              .type(ButtonType.Capsule)
              .height(36)
              .padding({ left: 16, right: 16 })
              .backgroundColor(this.isAddedToVocab ? COLORS.TEXT_SECONDARY + '20' : COLORS.WARNING + '20')
              .fontColor(this.isAddedToVocab ? COLORS.TEXT_SECONDARY : COLORS.WARNING)
              .fontSize(14)
              .margin({ top: 20 })
              .onClick(() => {
                if (this.isAddedToVocab) {
                  // 取消收录
                  if (this.onRemoveVocabulary) {
                    this.onRemoveVocabulary(this.word.hangul);
                    this.isAddedToVocab = false;
                    promptAction.showToast({ message: '已从生词本移除' });
                  }
                } else {
                  // 收录生词
                  if (this.onAddVocabulary) {
                    this.onAddVocabulary(this.word.hangul, this.word.primaryMeaning);
                    this.isAddedToVocab = true;
                    promptAction.showToast({ message: '已添加到生词本' });
                  }
                }
              })
          }
          .opacity(this.contentOpacity)

          // 导航按钮 - 不应用透明度动画
          Row({ space: 16 }) {
            // 上一个按钮
            Button('上一个')
              .type(ButtonType.Capsule)
              .width(120)
              .height(44)
              .backgroundColor(this.index > 0 ? COLORS.SURFACE : '#E0E0E0')
              .fontSize(16)
              .fontColor(this.index > 0 ? COLORS.TEXT_PRIMARY : COLORS.TEXT_HINT)
              .border({ width: 1, color: COLORS.BORDER })
              .enabled(this.index > 0)
              .onClick(() => {
                this.isFlipped = false;
                this.stopAnimation();
                if (this.onPrevious) {
                  this.onPrevious();
                }
              })
            
            // 下一个按钮
            Button('下一个')
              .type(ButtonType.Capsule)
              .width(120)
              .height(44)
              .backgroundColor(COLORS.PRIMARY)
              .fontSize(16)
              .fontColor('#FFFFFF')
              .onClick(() => {
                this.isFlipped = false;
                this.stopAnimation();
                if (this.onNext) {
                  this.onNext();
                }
              })
          }
          .margin({ top: 32 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .visibility(this.isFlipped ? Visibility.Visible : Visibility.Hidden)
      }
      .width('100%')
      .layoutWeight(1)
      .margin({ top: 16, left: 16, right: 16 })
      .padding(24)
      .backgroundColor(COLORS.SURFACE)
      .borderRadius(24)
      .shadow({ radius: 8, color: '#0000001A', offsetY: 4 })
      .onClick(() => {
        this.isFlipped = !this.isFlipped;
      })
    }
    .width('100%')
    .height('100%')
  }
  @Builder
  SelectionMenuBuilder() {
    Menu() {
      MenuItem({ content: "🔍 查词" })
        .onClick(() => {
          if (this.onSearch) {
            // 优先使用选中的文本，否则使用主单词
            const query = (this.selectedText && this.selectedText.length > 0) ? this.selectedText : this.word.hangul;
            this.onSearch(query);
            // 查词后清空选区（可选，避免切卡片后残留）
            this.selectedText = ''; 
          }
        })
    }
  }
}
