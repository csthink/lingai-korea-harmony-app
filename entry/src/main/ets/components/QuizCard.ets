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

          Column() {
            Text(this.quiz.stem.display)
              .fontSize(38)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)
              .textAlign(TextAlign.Center)

            if (this.quiz.context !== '') {
              Text(this.quiz.context)
                .fontSize(UI.BODY_SIZE)
                .fontColor(COLORS.TEXT_SECONDARY)
                .margin({ top: 12 })
                .textAlign(TextAlign.Center)
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, top: 32, bottom: 32 })
          .margin({ top: 16 })
          .backgroundColor(COLORS.SURFACE)
          .borderRadius(UI.CARD_RADIUS)
          .border({ width: 1, color: COLORS.BORDER })

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
          Column() {

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
            Button('确认')
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
        .textAlign(TextAlign.Center)
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
    .borderRadius(UI.CONTROL_RADIUS)
    .border({
      width: 2,
      color: this.getOptionBorderColor(option),
    })
    .enabled(!this.showResult)
    .onClick(() => {
      this.selectedOption = option.id;
    })
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
      return this.selectedOption === option.id ? COLORS.PRIMARY : 'transparent';
    }
    if (option.isCorrect) return COLORS.SUCCESS;
    if (this.selectedOption === option.id) return COLORS.ERROR;
    return 'transparent';
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
