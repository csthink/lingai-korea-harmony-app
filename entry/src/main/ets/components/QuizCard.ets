/**
 * 练习题卡片组件
 * 用于关卡练习阶段展示题目
 * 适配 ArkTS 严格模式
 */
import { COLORS, QUIZ_TYPE_BASIC_RECOGNITION, QUIZ_TYPE_CONTEXT_SENSE, QUIZ_TYPE_CONFUSION_WORDS, QUIZ_TYPE_COLLOCATION_FILL } from '../utils/Constants';
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
      Row() {
        Text(this.getQuizTypeLabel())
          .fontSize(12)
          .fontColor(COLORS.PRIMARY)
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(COLORS.PRIMARY + '20')
          .borderRadius(4)
      }
      .width('100%')

      Column() {
        Text(this.quiz.stem.display)
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor(COLORS.TEXT_PRIMARY)
          .textAlign(TextAlign.Center)

        if (this.quiz.context !== '') {
          Text(this.quiz.context)
            .fontSize(16)
            .fontColor(COLORS.TEXT_SECONDARY)
            .margin({ top: 12 })
            .textAlign(TextAlign.Center)
        }
      }
      .width('100%')
      .padding(24)
      .margin({ top: 16 })
      .backgroundColor(COLORS.SURFACE)
      .borderRadius(16)

      Column({ space: 12 }) {
        ForEach(this.quiz.options, (option: QuizOption) => {
          this.OptionButton(option)
        })
      }
      .width('100%')
      .margin({ top: 24 })

      // 答错时显示反馈（答对时直接跳过，不显示这个区域）
      if (this.showResult) {
        Column() {

          Button('继续')
            .type(ButtonType.Capsule)
            .width('100%')
            .height(48)
            .backgroundColor(COLORS.PRIMARY)
            .fontSize(16)
            .fontColor('#FFFFFF')
            .onClick(() => {
              this.resetState();
              if (this.onNext) {
                this.onNext();
              }
            })
        }
        .width('100%')
        .padding(16)
        .margin({ top: 24 })
      } else {
        // 确认按钮始终显示
        Column() {
          if (this.showHint) {
            Text('请先选择一个答案')
              .fontSize(14)
              .fontColor(COLORS.WARNING)
              .margin({ bottom: 8 })
          }
          Button('确认')
            .type(ButtonType.Capsule)
            .width('100%')
            .height(48)
            .backgroundColor(this.selectedOption !== '' ? COLORS.PRIMARY : COLORS.BORDER)
            .fontSize(16)
            .fontColor(this.selectedOption !== '' ? '#FFFFFF' : COLORS.TEXT_SECONDARY)
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
        .padding(16)
        .margin({ top: 24 })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 16, right: 16, top: 16, bottom: 24 })
  }

  @Builder
  OptionButton(option: QuizOption) {
    Row() {
      Text(option.id)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.getOptionLetterColor(option))
        .width(32)
        .height(32)
        .textAlign(TextAlign.Center)
        .borderRadius(16)
        .backgroundColor(this.getOptionBgColor(option))

      Text(option.text)
        .fontSize(16)
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
    .height(56)
    .padding({ left: 12, right: 16 })
    .backgroundColor(this.getOptionCardBg(option))
    .borderRadius(12)
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
      return this.selectedOption === option.id ? '#FFFFFF' : COLORS.TEXT_SECONDARY;
    }
    if (option.isCorrect) return '#FFFFFF';
    if (this.selectedOption === option.id) return '#FFFFFF';
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
    if (option.isCorrect) return COLORS.SUCCESS + '10';
    if (this.selectedOption === option.id) return COLORS.ERROR + '10';
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
