/** 四个主页面共用的双灯机器人入口。 */
import { AssistantAvatar } from './AssistantAvatar';
import { UI } from '../utils/UiTokens';

@Component
export struct FloatingSpirit {
  onPress?: () => void;
  @Prop subtle: boolean = false;

  build() {
    Button() {
      AssistantAvatar({ avatarSize: 56, expression: 'idle' })
    }
    .width(58)
    .height(58)
    .type(ButtonType.Circle)
    .backgroundColor(Color.Transparent)
    .shadow({ radius: 3, color: UI.SHADOW, offsetY: 3 })
    .accessibilityText('打开小灵 AI 助手')
    .onClick(() => {
      if (this.onPress) this.onPress();
    })
  }
}
