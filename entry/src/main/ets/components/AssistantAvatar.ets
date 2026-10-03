/**
 * 已认可双灯机器人，素材原始字节保留。
 * 面屏位置与 LG-145 完整原型一致；表情由实际输入和请求状态驱动。
 */
@Component
export struct AssistantAvatar {
  @Prop avatarSize: number = 56;
  @Prop expression: string = 'idle'; // idle / focus / thinking / happy
  @Prop motionEnabled: boolean = true;
  @State blink: boolean = false;
  @State lookRight: boolean = false;
  private expressionTimer: number = -1;
  private blinkTimer: number = -1;
  private tick: number = 0;

  aboutToAppear(): void {
    if (!this.motionEnabled) return;
    this.expressionTimer = setInterval(() => {
      if (!this.motionEnabled) return;
      this.lookRight = !this.lookRight;
      this.tick += 1;
      if (this.expression === 'idle' && this.tick % 7 === 0) {
        this.blink = true;
        this.blinkTimer = setTimeout(() => { this.blink = false; }, 160);
      }
    }, 800);
  }

  aboutToDisappear(): void {
    if (this.expressionTimer !== -1) clearInterval(this.expressionTimer);
    if (this.blinkTimer !== -1) clearTimeout(this.blinkTimer);
  }

  private eyeHeight(): number {
    if (this.expression === 'focus') return this.avatarSize * 0.114;
    if (this.expression === 'thinking') return this.avatarSize * 0.078;
    if (this.expression === 'idle' && this.motionEnabled && this.blink) return this.avatarSize * 0.012;
    return this.avatarSize * 0.098;
  }

  @Builder
  Eye() {
    if (this.expression === 'happy') {
      Row()
        .width(this.avatarSize * 0.097)
        .height(this.avatarSize * 0.07)
        .border({ width: { top: this.avatarSize * 0.029 }, color: '#FFF0D9' })
        .borderRadius({ topLeft: this.avatarSize * 0.06, topRight: this.avatarSize * 0.06 })
    } else {
      Ellipse()
        .width(this.avatarSize * (this.expression === 'focus' ? 0.086 : 0.097))
        .height(this.eyeHeight())
        .fill('#FFF0D9')
        .translate({ x: this.expression === 'thinking' && this.motionEnabled ? (this.lookRight ? 0.8 : -0.8) : 0 })
        .animation({ duration: this.expression === 'thinking' ? 700 : 100 })
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Image($r('app.media.lingai_assistant_twin_lights'))
        .width(this.avatarSize)
        .height(this.avatarSize)
        .objectFit(ImageFit.Contain)
      Stack({ alignContent: Alignment.TopStart }) {
        Row() {
          this.Eye()
          Blank()
          this.Eye()
        }
        .width('80%')
        .height(this.avatarSize * 0.12)
        .alignItems(VerticalAlign.Center)
        .position({ x: '10%', y: '16%' })
        Row()
          .width(this.avatarSize * (this.expression === 'happy' ? 0.134 : this.expression === 'thinking' ? 0.059 : 0.102))
          .height(this.avatarSize * (this.expression === 'happy' ? 0.062 : this.expression === 'thinking' ? 0.06 : 0.044))
          .backgroundColor(this.expression === 'happy' ? '#FFF0D9' : Color.Transparent)
          .border({ width: this.expression === 'thinking' ? 1.1 : { bottom: 1.3 }, color: '#FFF0D9' })
          .borderRadius(this.expression === 'thinking' ? this.avatarSize : { bottomLeft: this.avatarSize * 0.05, bottomRight: this.avatarSize * 0.05 })
          .position({ x: this.expression === 'happy' ? '38%' : this.expression === 'thinking' ? '46%' : '41%', y: '64%' })
      }
      .width(this.avatarSize * 0.536)
      .height(this.avatarSize * 0.259)
      .linearGradient({ angle: 135, colors: [['#243E52', 0], ['#1C3447', 0.62], ['#213A4F', 1]] })
      .borderRadius(this.avatarSize * 0.093)
      .clip(true)
      .rotate({ angle: 8 })
      .position({ x: this.avatarSize * 0.243, y: this.avatarSize * 0.49 })
    }
    .width(this.avatarSize)
    .height(this.avatarSize)
    .accessibilityLevel('no')
    .hitTestBehavior(HitTestMode.None)
  }
}
