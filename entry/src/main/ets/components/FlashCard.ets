/**
 * 预习闪卡组件
 * 用于关卡预习阶段展示单词
 * 适配 ArkTS 严格模式
 */
import { COLORS } from '../utils/Constants';
import { UI } from '../utils/UiTokens';
import { WordEntry, ExampleSentence } from '../models/DataModels';

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

  private showVocabularyNotice(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message });
    } catch (error) {
      console.warn('[FlashCard] vocabulary notification unavailable');
    }
  }

  private toggleVocabulary(): void {
    if (this.isAddedToVocab) {
      if (this.onRemoveVocabulary) {
        this.onRemoveVocabulary(this.word.hangul);
        this.isAddedToVocab = false;
        this.showVocabularyNotice('已从生词本移除');
      }
    } else if (this.onAddVocabulary) {
      this.onAddVocabulary(this.word.hangul, this.word.primaryMeaning);
      this.isAddedToVocab = true;
      this.showVocabularyNotice('已添加到生词本');
    }
  }

  build() {
    Column() {
      Row() {
        Text('轻点词卡，查看释义').fontSize(12).fontColor(COLORS.TEXT_SECONDARY)
        Blank()
        Text(`${this.index + 1} / ${this.total}`).fontSize(13).fontWeight(FontWeight.Medium).fontColor(COLORS.TEXT_PRIMARY)
      }.width('100%').padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 16, bottom: 10 })
      Progress({ value: this.index + 1, total: Math.max(1, this.total), type: ProgressType.Linear })
        .width('88%').height(5).color(UI.BLUE).backgroundColor(UI.BLUE_SOFT)
      Scroll() {
        Column({ space: 18 }) {
          Column({ space: 16 }) {
            if (this.word.pos !== '') {
              Text(this.word.pos).fontSize(12).fontColor(COLORS.PRIMARY)
                .padding({ left: 10, right: 10, top: 5, bottom: 5 }).backgroundColor(COLORS.SURFACE).borderRadius(9)
            }
            if (this.isFlipped) {
              Text(this.word.primaryMeaning).fontSize(29).fontWeight(FontWeight.Bold)
                .fontColor(COLORS.TEXT_PRIMARY).textAlign(TextAlign.Center)
            }
            Text(this.word.hangul).fontSize(this.isFlipped ? 24 : 42).fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY).textAlign(TextAlign.Center)
              .copyOption(CopyOptions.LocalDevice)
              .onTextSelectionChange((start, end) => {
                if (start >= 0 && end > start && end <= this.word.hangul.length) {
                  this.selectedText = this.word.hangul.substring(start, end);
                }
              })
              .bindSelectionMenu(TextSpanType.TEXT, this.SelectionMenuBuilder, TextResponseType.LONG_PRESS)
            if (this.word.romanization !== '') {
              Text(this.word.romanization).fontSize(13).fontColor(COLORS.TEXT_SECONDARY)
            }
            Text(this.isFlipped ? '再点一下，回到韩语' : '轻点翻面').fontSize(12).fontColor(COLORS.TEXT_SECONDARY)
          }
          .width('100%').constraintSize({ minHeight: 248 }).padding(24).borderRadius(22)
          .backgroundColor(UI.GREEN_SOFT).justifyContent(FlexAlign.Center).opacity(this.contentOpacity)
          .onClick(() => { this.isFlipped = !this.isFlipped; })
          Row({ space: 16 }) {
            Button() {
              Image($r('app.media.ic_speaker')).width(22).height(22).fillColor(this.isPlaying ? UI.ON_BLUE : COLORS.PRIMARY)
            }.type(ButtonType.Normal).width(46).height(46).borderRadius(12)
            .backgroundColor(this.isPlaying ? UI.BLUE : UI.GREEN_SOFT)
            .accessibilityText(this.isPlaying ? '停止发音' : '播放单词')
            .onClick(() => { this.handleSpeakerClick(); })
            Button(this.isAddedToVocab ? '已收藏' : '收藏').type(ButtonType.Normal).height(46).borderRadius(12)
              .backgroundColor(UI.GREEN_SOFT).fontColor(COLORS.PRIMARY).fontSize(13)
              .onClick(() => { this.toggleVocabulary(); })
            Button('查词').type(ButtonType.Normal).height(46).borderRadius(12)
              .backgroundColor(UI.GREEN_SOFT).fontColor(COLORS.PRIMARY).fontSize(13)
              .onClick(() => { if (this.onSearch) { this.onSearch(this.word.hangul); } })
          }.width('100%').justifyContent(FlexAlign.Center)
          if (this.isFlipped && this.word.examples.length > 0) {
            Column({ space: 8 }) {
              Text(this.word.examples[0].ko).fontSize(17).lineHeight(26).fontColor(COLORS.TEXT_PRIMARY)
                .copyOption(CopyOptions.LocalDevice)
                .onTextSelectionChange((start, end) => {
                  const text = this.word.examples[0].ko;
                  if (start >= 0 && end > start && end <= text.length) { this.selectedText = text.substring(start, end); }
                })
                .bindSelectionMenu(TextSpanType.TEXT, this.SelectionMenuBuilder, TextResponseType.LONG_PRESS)
              Text(this.word.examples[0].zh).fontSize(13).lineHeight(21).fontColor(COLORS.TEXT_SECONDARY)
            }.alignItems(HorizontalAlign.Start).width('100%').padding({ top: 15, bottom: 15 })
            .border({ width: { top: 1 }, color: COLORS.BORDER })
          } else {
            Text('先在心里说一遍，再看看答案。').fontSize(12).fontColor(COLORS.TEXT_SECONDARY)
          }
        }.width('100%').padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 20, bottom: 20 })
      }.width('100%').layoutWeight(1).scrollBar(BarState.Off).clipContent(ContentClipMode.CONTENT_ONLY)
      Row({ space: 12 }) {
        Button('上一个').type(ButtonType.Normal).layoutWeight(1).height(50).borderRadius(UI.CONTROL_RADIUS)
          .enabled(this.index > 0).backgroundColor(UI.GREEN_SOFT).fontColor(COLORS.PRIMARY).fontSize(15)
          .onClick(() => { this.isFlipped = false; this.stopAnimation(); if (this.onPrevious) { this.onPrevious(); } })
        Button(this.index === this.total - 1 ? '开始练习' : '下一个').type(ButtonType.Normal).layoutWeight(1).height(50)
          .borderRadius(UI.CONTROL_RADIUS).backgroundColor(COLORS.PRIMARY).fontColor(UI.ON_PRIMARY).fontSize(15)
          .onClick(() => { this.isFlipped = false; this.stopAnimation(); if (this.onNext) { this.onNext(); } })
      }.width('100%').padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 12, bottom: 16 })
      .backgroundColor(COLORS.SURFACE)
    }.width('100%').height('100%')
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
