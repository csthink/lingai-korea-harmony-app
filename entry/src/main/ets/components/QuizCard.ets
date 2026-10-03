/**
 * 练习题卡片组件
 * 用于关卡练习阶段展示题目
 * 适配 ArkTS 严格模式
 */
import { COLORS, QUIZ_TYPE_BASIC_RECOGNITION, QUIZ_TYPE_CONTEXT_SENSE, QUIZ_TYPE_CONFUSION_WORDS, QUIZ_TYPE_COLLOCATION_FILL } from '../utils/Constants';
import { UI } from '../utils/UiTokens';
import { Quiz, QuizOption } from '../models/DataModels';

@Component
export struct QuizCard {
  @Prop quiz: Quiz = new Quiz();
  @State selectedOption: string = '';
  @State showResult: boolean = false;
  @State isCorrect: boolean = false;
  @State showHint: boolean = false; // 显示请选择答案提示

  onPlayAudio?: (text: string) => void;
  onAnswer?: (isCorrect: boolean) => void;
  onNext?: () => void;

  build() {
    Column() {
      Scroll() {
        Column() {
          Row() {
            Text(this.getQuizTypeLabel())
              .fontSize(UI.CAPTION_SIZE)
              .fontColor(COLORS.PRIMARY)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor(UI.GREEN_SOFT)
              .borderRadius(10)
          }
          .width('100%')

          Column({ space: 10 }) {
            Row() {
            Text(this.quiz.stem.display)
              .fontSize(32)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
              .textAlign(TextAlign.Start).layoutWeight(1)
            Button() {
              Image($r('app.media.ic_speaker')).width(21).height(21).fillColor(COLORS.PRIMARY)
            }.type(ButtonType.Normal).width(44).height(44).borderRadius(12).backgroundColor(UI.GREEN_SOFT)
            .accessibilityText('播放题目').onClick(() => { if (this.onPlayAudio) { this.onPlayAudio(this.quiz.stem.display); } })
            }.width('100%')
            Text('选择正确的答案').fontSize(13).fontColor(COLORS.TEXT_SECONDARY).width('100%')

            if (this.quiz.context !== '') {
              Text(this.quiz.context)
                .fontSize(UI.BODY_SIZE)
                .fontColor(COLORS.TEXT_SECONDARY)
                .margin({ top: 12 })
                .textAlign(TextAlign.Start)
            }
          }
          .width('100%')
          .padding({ left: 0, right: 0, top: 22, bottom: 22 })
          .margin({ top: 16 })
          .backgroundColor(COLORS.BACKGROUND)

          Column({ space: 12 }) {
            ForEach(this.quiz.options, (option: QuizOption) => {
              this.OptionButton(option)
            })
          }
          .width('100%')
          .margin({ top: 24 })
        }
        .width('100%')
        .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 20, bottom: 20 })
      }
      .width('100%')
      .layoutWeight(1)
      .clipContent(ContentClipMode.CONTENT_ONLY)
      .scrollBar(BarState.Off)

      Column() {
        // 答错时显示反馈（答对时直接跳过，不显示这个区域）
        if (this.showResult) {
          Column({ space: 10 }) {
            Text('再记一下这个表达').fontSize(14).fontWeight(FontWeight.Bold).fontColor(UI.DANGER_TEXT).width('100%')
            Text(this.correctAnswerText()).fontSize(13).fontColor(COLORS.TEXT_PRIMARY).width('100%')
            Button('继续')
              .type(ButtonType.Normal)
              .borderRadius(UI.CONTROL_RADIUS)
              .width('100%')
              .height(52)
              .backgroundColor(COLORS.PRIMARY)
              .fontSize(UI.BODY_SIZE)
              .fontColor(UI.ON_PRIMARY)
              .onClick(() => {
                this.resetState();
                if (this.onNext) {
                  this.onNext();
                }
              })
          }
          .width('100%')
        } else {
          // 确认按钮始终显示
          Column() {
            if (this.showHint) {
              Text('请先选择一个答案')
                .fontSize(UI.CAPTION_SIZE)
                .fontColor(COLORS.WARNING)
                .margin({ bottom: 8 })
            }
            Button('确认答案')
              .type(ButtonType.Normal)
              .borderRadius(UI.CONTROL_RADIUS)
              .width('100%')
              .height(52)
              .backgroundColor(this.selectedOption !== '' ? COLORS.PRIMARY : COLORS.BORDER)
              .fontSize(UI.BODY_SIZE)
              .fontColor(this.selectedOption !== '' ? UI.ON_PRIMARY : COLORS.TEXT_SECONDARY)
              .onClick(() => {
                if (this.selectedOption === '') {
                  this.showHint = true;
                } else {
                  this.showHint = false;
                  this.checkAnswer();
                }
              })
          }
          .width('100%')
        }
      }
      .width('100%')
      .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 12, bottom: 16 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  OptionButton(option: QuizOption) {
    Row() {
      Text(option.id)
        .fontSize(UI.BODY_SIZE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.getOptionLetterColor(option))
        .width(32)
        .height(32)
        .textAlign(TextAlign.Start)
        .borderRadius(16)
        .backgroundColor(this.getOptionBgColor(option))

      Text(option.text)
        .fontSize(UI.BODY_SIZE)
        .fontColor(this.getOptionTextColor(option))
        .margin({ left: 12 })
        .layoutWeight(1)

      if (this.showResult && option.isCorrect) {
        Image($r('app.media.ic_check'))
          .width(20)
          .height(20)
          .fillColor(COLORS.SUCCESS)
      } else if (this.showResult && this.selectedOption === option.id && !option.isCorrect) {
        Image($r('app.media.ic_close'))
          .width(20)
          .height(20)
          .fillColor(COLORS.ERROR)
      }
    }
    .width('100%')
    .constraintSize({ minHeight: 60 })
    .padding({ left: 14, right: 16, top: 12, bottom: 12 })
    .backgroundColor(this.getOptionCardBg(option))
    .border({
      width: 1,
      color: this.getOptionBorderColor(option),
    })
    .borderRadius(UI.CONTROL_RADIUS).clip(true)
    .enabled(!this.showResult)
    .onClick(() => {
      this.selectedOption = option.id;
    })
  }

  private correctAnswerText(): string {
    const correct = this.quiz.options.find((option: QuizOption) => option.isCorrect);
    return correct ? `${this.quiz.stem.display}：${correct.text}` : '';
  }

  getQuizTypeLabel(): string {
    if (this.quiz.type === QUIZ_TYPE_BASIC_RECOGNITION) {
      return '看词选义';
    } else if (this.quiz.type === QUIZ_TYPE_CONTEXT_SENSE) {
      return '语境义项';
    } else if (this.quiz.type === QUIZ_TYPE_CONFUSION_WORDS) {
      return '易混词辨析';
    } else if (this.quiz.type === QUIZ_TYPE_COLLOCATION_FILL) {
      return '搭配填空';
    } else {
      return '选择题';
    }
  }

  getOptionLetterColor(option: QuizOption): string {
    if (!this.showResult) {
      return this.selectedOption === option.id ? UI.ON_PRIMARY : COLORS.TEXT_SECONDARY;
    }
    if (option.isCorrect) return UI.ON_PRIMARY;
    if (this.selectedOption === option.id) return UI.ON_PRIMARY;
    return COLORS.TEXT_SECONDARY;
  }

  getOptionBgColor(option: QuizOption): string {
    if (!this.showResult) {
      return this.selectedOption === option.id ? COLORS.PRIMARY : COLORS.BORDER;
    }
    if (option.isCorrect) return COLORS.SUCCESS;
    if (this.selectedOption === option.id) return COLORS.ERROR;
    return COLORS.BORDER;
  }

  getOptionTextColor(option: QuizOption): string {
    if (this.showResult && option.isCorrect) return COLORS.SUCCESS;
    if (this.showResult && this.selectedOption === option.id && !option.isCorrect) return COLORS.ERROR;
    return COLORS.TEXT_PRIMARY;
  }

  getOptionCardBg(option: QuizOption): string {
    if (!this.showResult) return COLORS.SURFACE;
    if (option.isCorrect) return UI.GREEN_SOFT;
    if (this.selectedOption === option.id) return UI.DANGER_SOFT;
    return COLORS.SURFACE;
  }

  getOptionBorderColor(option: QuizOption): string {
    if (!this.showResult) {
      return this.selectedOption === option.id ? COLORS.PRIMARY : COLORS.BORDER;
    }
    if (option.isCorrect) return COLORS.SUCCESS;
    if (this.selectedOption === option.id) return COLORS.ERROR;
    return COLORS.BORDER;
  }

  resetState() {
    this.selectedOption = '';
    this.showResult = false;
    this.isCorrect = false;
    this.showHint = false;
  }

  checkAnswer() {
    const selected = this.quiz.options.find(opt => opt.id === this.selectedOption);
    if (selected) {
      this.isCorrect = selected.isCorrect;
      if (this.onAnswer) {
        this.onAnswer(this.isCorrect);
      }
      
      if (this.isCorrect) {
        // 答对直接进入下一题，不显示反馈
        this.resetState();
        if (this.onNext) {
          this.onNext();
        }
      } else {
        // 答错显示反馈，需要用户手动点击继续
        this.showResult = true;
      }
    }
  }
}
