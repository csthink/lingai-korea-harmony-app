/**
 * 悬浮精灵按钮组件
 * 右下角固定悬浮，点击触发对话面板
 */
import { COLORS } from '../utils/Constants';

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
          .width(64)
          .height(64)
          .fill('rgba(88, 86, 214, 0.2)')
          .scale({ x: this.breathScale, y: this.breathScale })
      }
      
      // 主按钮
      Button() {
        Text('🧚')
          .fontSize(this.subtle ? 24 : 28)
      }
      .width(this.subtle ? 48 : 56)
      .height(this.subtle ? 48 : 56)
      .type(ButtonType.Circle)
      .backgroundColor(COLORS.PRIMARY)
      .shadow({
        radius: this.subtle ? 8 : 12,
        color: this.subtle ? 'rgba(88, 86, 214, 0.18)' : 'rgba(88, 86, 214, 0.4)',
        offsetX: 0,
        offsetY: this.subtle ? 2 : 4
      })
      .opacity(this.subtle ? 0.78 : 1)
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
