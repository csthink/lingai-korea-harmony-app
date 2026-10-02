/**
 * 悬浮精灵按钮组件
 * 右下角固定悬浮，点击触发对话面板
 */
import { COLORS } from '../utils/Constants';
import { UI } from '../utils/UiTokens';

@Component
export struct FloatingSpirit {
  // 点击回调
  onPress?: () => void;
  subtle?: boolean;
  
  @State isPressed: boolean = false;
  @State breathScale: number = 1.0;
  
  private breathTimer: number = -1;
  
  aboutToAppear() {
    // 呼吸灯动画
    if (!this.subtle) {
      this.startBreathAnimation();
    }
  }
  
  aboutToDisappear() {
    if (this.breathTimer !== -1) {
      clearInterval(this.breathTimer);
    }
  }
  
  startBreathAnimation() {
    let growing = true;
    this.breathTimer = setInterval(() => {
      if (growing) {
        this.breathScale += 0.01;
        if (this.breathScale >= 1.05) growing = false;
      } else {
        this.breathScale -= 0.01;
        if (this.breathScale <= 1.0) growing = true;
      }
    }, 50);
  }

  build() {
    Stack() {
      // 外圈光晕
      if (!this.subtle) {
        Circle()
          .width(72)
          .height(72)
          .fill(UI.GREEN_SOFT)
          .scale({ x: this.breathScale, y: this.breathScale })
      }
      
      // 主按钮
      Button() {
        Column({ space: 0 }) {
          Image($r('app.media.lingai_robot'))
            .width(this.subtle ? 32 : 38)
            .height(this.subtle ? 32 : 38)
            .objectFit(ImageFit.Contain)
          Text('AI')
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(UI.BLUE)
        }
      }
      .width(this.subtle ? 52 : 64)
      .height(this.subtle ? 52 : 64)
      .type(ButtonType.Normal)
      .backgroundColor(COLORS.SURFACE)
      .border({ width: 1, color: UI.GREEN_SOFT })
      // border() 会重置默认圆角，显式圆角必须在它之后设置。
      .borderRadius(this.subtle ? 18 : 22)
      .clip(true)
      .shadow({
        radius: this.subtle ? 8 : 12,
        color: UI.SHADOW,
        offsetX: 0,
        offsetY: this.subtle ? 2 : 4
      })
      .opacity(this.subtle ? 0.94 : 1)
      .scale({ x: this.isPressed ? 0.9 : 1.0, y: this.isPressed ? 0.9 : 1.0 })
      .animation({ duration: 100 })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.isPressed = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.isPressed = false;
        }
      })
      .onClick(() => {
        if (this.onPress) {
          this.onPress();
        }
      })
    }
  }
}
