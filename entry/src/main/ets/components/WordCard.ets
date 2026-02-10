/**
 * 词条卡片组件
 * 用于词典结果展示和生词本查看
 * 适配 ArkTS 严格模式
 */
import { COLORS } from '../utils/Constants';
import { WordEntry, DictAIResponse, Sense, ExampleSentence } from '../models/DataModels';
import { PlayButton, PlayIcon } from './PlayButton';

@Component
export struct WordCard {
  @Prop word: WordEntry = new WordEntry();
  @Prop aiResponse: DictAIResponse | null = null;
  @Prop showAddButton: boolean = true;
  @State isExpanded: boolean = false;

  onPlayAudio?: (text: string) => void;
  onAddToWordbook?: () => void;

  build() {
    Column() {
      Row() {
        Column() {
          Row() {
            Text(this.word.hangul)
              .fontSize(28)
              .fontWeight(FontWeight.Bold)
              .fontColor(COLORS.TEXT_PRIMARY)

            // 使用带动画的PlayButton
            PlayButton({
              text: this.word.hangul,
              buttonSize: 44,
              iconBtnSize: 24,
              color: COLORS.PRIMARY,
              onPlay: (text: string) => {
                if (this.onPlayAudio) {
                  this.onPlayAudio(text);
                }
              }
            })
              .margin({ left: 12 })
          }

          Text(this.word.romanization)
            .fontSize(14)
            .fontColor(COLORS.TEXT_SECONDARY)
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)

        Blank()

        if (this.showAddButton) {
          Button() {
            Image($r('app.media.ic_add'))
              .width(20)
              .height(20)
              .fillColor(COLORS.PRIMARY)
          }
          .type(ButtonType.Circle)
          .width(40)
          .height(40)
          .backgroundColor(COLORS.SURFACE)
          .border({ width: 1, color: COLORS.PRIMARY })
          .onClick(() => {
            if (this.onAddToWordbook) {
              this.onAddToWordbook();
            }
          })
        }
      }
      .width('100%')

      Text(this.word.primaryMeaning)
        .fontSize(20)
        .fontWeight(FontWeight.Medium)
        .fontColor(COLORS.PRIMARY)
        .margin({ top: 16 })
        .width('100%')

      if (this.word.pos !== '') {
        Row() {
          Text(this.word.pos)
            .fontSize(12)
            .fontColor(COLORS.TEXT_SECONDARY)
            .padding({ left: 8, right: 8, top: 2, bottom: 2 })
            .backgroundColor(COLORS.BORDER)
            .borderRadius(4)
        }
        .width('100%')
        .margin({ top: 8 })
      }

      if (this.word.examples.length > 0) {
        Column() {
          Text('例句')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(COLORS.TEXT_SECONDARY)
            .width('100%')

          ForEach(this.word.examples.slice(0, 2), (example: ExampleSentence) => {
            Column() {
              Row() {
                Text(example.ko)
                  .fontSize(15)
                  .fontColor(COLORS.TEXT_PRIMARY)
                  .layoutWeight(1)

                // 使用带动画的PlayIcon
                PlayIcon({
                  text: example.ko,
                  iconSize: 20,
                  color: COLORS.TEXT_HINT,
                  onPlay: (text: string) => {
                    if (this.onPlayAudio) {
                      this.onPlayAudio(text);
                    }
                  }
                })
              }
              .width('100%')

              Text(example.zh)
                .fontSize(13)
                .fontColor(COLORS.TEXT_SECONDARY)
                .margin({ top: 2 })
                .width('100%')
            }
            .width('100%')
            .padding(12)
            .margin({ top: 8 })
            .backgroundColor(COLORS.BACKGROUND)
            .borderRadius(8)
          })
        }
        .width('100%')
        .margin({ top: 16 })
      }

      if (this.word.senses.length > 1 || this.word.collocations.length > 0) {
        Button(this.isExpanded ? '收起' : '查看更多')
          .type(ButtonType.Normal)
          .backgroundColor('transparent')
          .fontColor(COLORS.PRIMARY)
          .fontSize(14)
          .height(36)
          .margin({ top: 12 })
          .onClick(() => {
            this.isExpanded = !this.isExpanded;
          })
      }

      if (this.isExpanded) {
        Column() {
          if (this.word.senses.length > 1) {
            Column() {
              Text('其他义项')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLORS.TEXT_SECONDARY)
                .width('100%')

              ForEach(this.word.senses.slice(1), (sense: Sense) => {
                Text(`• ${sense.meaning}`)
                  .fontSize(14)
                  .fontColor(COLORS.TEXT_PRIMARY)
                  .width('100%')
                  .margin({ top: 6 })
              })
            }
            .width('100%')
            .margin({ top: 12 })
          }

          if (this.word.collocations.length > 0) {
            Column() {
              Text('常用搭配')
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(COLORS.TEXT_SECONDARY)
                .width('100%')

              Flex({ wrap: FlexWrap.Wrap }) {
                ForEach(this.word.collocations, (collocation: string) => {
                  Text(collocation)
                    .fontSize(13)
                    .fontColor(COLORS.TEXT_PRIMARY)
                    .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                    .margin({ right: 8, top: 8 })
                    .backgroundColor(COLORS.BORDER)
                    .borderRadius(12)
                })
              }
              .width('100%')
            }
            .width('100%')
            .margin({ top: 12 })
          }
        }
      }

      if (this.aiResponse !== null && this.aiResponse.aiMeaning !== '') {
        Column() {
          Row() {
            Image($r('app.media.ic_ai'))
              .width(16)
              .height(16)
              .fillColor(COLORS.SECONDARY)

            Text('AI 补充')
              .fontSize(12)
              .fontColor(COLORS.SECONDARY)
              .margin({ left: 4 })
          }

          if (this.aiResponse.synonyms.length > 0) {
            Row() {
              Text('同义词: ')
                .fontSize(13)
                .fontColor(COLORS.TEXT_SECONDARY)

              Text(this.aiResponse.synonyms.join(', '))
                .fontSize(13)
                .fontColor(COLORS.TEXT_PRIMARY)
            }
            .width('100%')
            .margin({ top: 8 })
          }

          if (this.aiResponse.antonyms.length > 0) {
            Row() {
              Text('反义词: ')
                .fontSize(13)
                .fontColor(COLORS.TEXT_SECONDARY)

              Text(this.aiResponse.antonyms.join(', '))
                .fontSize(13)
                .fontColor(COLORS.TEXT_PRIMARY)
            }
            .width('100%')
            .margin({ top: 4 })
          }
        }
        .width('100%')
        .margin({ top: 16 })
        .padding(12)
        .backgroundColor(COLORS.SECONDARY + '10')
        .borderRadius(8)
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(16)
    .shadow({ radius: 4, color: '#0000000A', offsetY: 2 })
  }
}
