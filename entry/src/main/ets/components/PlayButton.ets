/**
 * 可复用的播放按钮组件
 * 带波纹动画效果 - 与FlashCard保持一致
 * 适配 ArkTS 严格模式
 */
import { COLORS } from '../utils/Constants';

@Component
export struct PlayButton {
  @Prop text: string = '';
  @Prop buttonSize: number = 56;
  @Prop iconBtnSize: number = 28;
  @Prop color: string = COLORS.PRIMARY;
  @Prop showStatusText: boolean = false;
  @State isPlaying: boolean = false;

  onPlay?: (text: string) => void;
  onStop?: () => void;

  // 播放动画定时器
  private animationTimer: number = -1;

  aboutToDisappear() {
    this.stopAnimation();
  }

  startAnimation() {
    this.isPlaying = true;
    // 3秒后自动停止动画
    this.animationTimer = setTimeout(() => {
      this.stopAnimation();
    }, 3000);
  }

  stopAnimation() {
    this.isPlaying = false;
    if (this.animationTimer !== -1) {
      clearTimeout(this.animationTimer);
      this.animationTimer = -1;
    }
  }

  handleClick() {
    if (this.isPlaying) {
      // 正在播放，停止
      this.stopAnimation();
      if (this.onStop) {
        this.onStop();
      }
    } else {
      // 开始播放
      this.startAnimation();
      if (this.onPlay) {
        this.onPlay(this.text);
      }
    }
  }

  build() {
    Column() {
      Stack() {
        // 背景圆圈
        Circle()
          .width(this.buttonSize)
          .height(this.buttonSize)
          .fill(this.isPlaying ? this.color : this.color + '20')

        // 波纹动画（播放时显示）- 与FlashCard一致
        if (this.isPlaying) {
          Circle()
            .width(this.buttonSize + 16)
            .height(this.buttonSize + 16)
            .fill('transparent')
            .stroke(this.color)
            .strokeWidth(2)
            .opacity(0.6)

          Circle()
            .width(this.buttonSize + 32)
            .height(this.buttonSize + 32)
            .fill('transparent')
            .stroke(this.color)
            .strokeWidth(1)
            .opacity(0.3)
        }

        // 喇叭图标
        Image($r('app.media.ic_speaker'))
          .width(this.iconBtnSize)
          .height(this.iconBtnSize)
          .fillColor(this.isPlaying ? '#FFFFFF' : this.color)
      }
      .onClick(() => {
        this.handleClick();
      })

      // 播放状态提示 - 与FlashCard一致
      if (this.showStatusText) {
        if (this.isPlaying) {
          Row() {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(this.color)
            Text('播放中...')
              .fontSize(12)
              .fontColor(this.color)
              .margin({ left: 6 })
          }
          .margin({ top: 8 })
        }
      }
    }
  }
}

// 小型播放图标（用于例句等）- 带动画
@Component
export struct PlayIcon {
  @Prop text: string = '';
  @Prop iconSize: number = 20;
  @Prop color: string = COLORS.TEXT_HINT;
  @State isPlaying: boolean = false;

  onPlay?: (text: string) => void;

  // 播放动画定时器
  private animationTimer: number = -1;

  aboutToDisappear() {
    this.stopAnimation();
  }

  startAnimation() {
    this.isPlaying = true;
    this.animationTimer = setTimeout(() => {
      this.stopAnimation();
    }, 3000);
  }

  stopAnimation() {
    this.isPlaying = false;
    if (this.animationTimer !== -1) {
      clearTimeout(this.animationTimer);
      this.animationTimer = -1;
    }
  }

  build() {
    Stack() {
      // 播放时的背景圆圈
      Circle()
        .width(this.iconSize + 12)
        .height(this.iconSize + 12)
        .fill(this.isPlaying ? COLORS.PRIMARY + '30' : 'transparent')

      // 波纹动画（播放时显示）
      if (this.isPlaying) {
        Circle()
          .width(this.iconSize + 20)
          .height(this.iconSize + 20)
          .fill('transparent')
          .stroke(COLORS.PRIMARY)
          .strokeWidth(1.5)
          .opacity(0.6)

        Circle()
          .width(this.iconSize + 28)
          .height(this.iconSize + 28)
          .fill('transparent')
          .stroke(COLORS.PRIMARY)
          .strokeWidth(1)
          .opacity(0.3)
      }

      Image($r('app.media.ic_speaker'))
        .width(this.iconSize)
        .height(this.iconSize)
        .fillColor(this.isPlaying ? COLORS.PRIMARY : this.color)
    }
    .onClick(() => {
      if (!this.isPlaying) {
        this.startAnimation();
        if (this.onPlay) {
          this.onPlay(this.text);
        }
      } else {
        this.stopAnimation();
      }
    })
  }
}
