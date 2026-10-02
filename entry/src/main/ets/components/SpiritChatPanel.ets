/**
 * AI精灵对话面板组件
 * 底部弹出半屏卡片，支持多轮对话
 */
import { COLORS } from '../utils/Constants';
import { UI } from '../utils/UiTokens';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import ApiService, { ApiError } from '../services/ApiService';
import SpiritChatService from '../services/SpiritChatService';
import { UserInfo } from '../models/DataModels';
import pasteboard from '@ohos.pasteboard';
import promptAction from '@ohos.promptAction';
import http from '@ohos.net.http';

// API消息类型
class SpiritChatMessageItem {
  role: string = '';
  content: string = '';
  
  constructor(role: string, content: string) {
    this.role = role;
    this.content = content;
  }
}

// 消息类型
class ChatMessage {
  id: string = '';
  role: string = 'user'; // 'user' | 'assistant'
  content: string = '';
  timestamp: number = 0;
  
  constructor(role: string, content: string) {
    this.id = `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    this.role = role;
    this.content = content;
    this.timestamp = Date.now();
  }
}

@Component
export struct SpiritChatPanel {
  // 关闭回调
  onClose?: () => void;
  
  @Prop currentContext: string = '';
  @Prop panelHeight: string = '70%';
  
  @State messages: ChatMessage[] = [];
  @State inputText: string = '';
  @State isLoading: boolean = false;
  @State canStop: boolean = false;
  @State userInfo: UserInfo = new UserInfo();
  
  private listScroller: Scroller = new Scroller();
  private apiService: ApiService = ApiService.getInstance();
  private chatService: SpiritChatService = SpiritChatService.getInstance();
  private activeChatRequest: http.HttpRequest | null = null;
  private chatRequestVersion: number = 0;
  private savedKeyboardAvoidMode: KeyboardAvoidMode | undefined = undefined;

  private applyKeyboardResize(): void {
    if (this.savedKeyboardAvoidMode !== undefined) return;
    const uiContext = this.getUIContext();
    this.savedKeyboardAvoidMode = uiContext.getKeyboardAvoidMode();
    uiContext.setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
  }

  private restoreKeyboardAvoidMode(): void {
    if (this.savedKeyboardAvoidMode === undefined) return;
    this.getUIContext().setKeyboardAvoidMode(this.savedKeyboardAvoidMode);
    this.savedKeyboardAvoidMode = undefined;
  }
  
  private safeShowToast(message: string, duration: number = 1500): void {
    try {
      promptAction.showToast({ message, duration });
    } catch (e) {
      console.error('[SpiritChatPanel] showToast failed:', e);
    }
  }

  // 复制文本
  async copyText(text: string) {
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      // 显示提示
      this.safeShowToast('已复制到剪贴板');
    } catch (error) {
      console.error('[SpiritChatPanel] Copy failed:', JSON.stringify(error));
    }
  }
  
  async aboutToAppear() {
    // 初始化并加载历史
    const context = getContext(this);
    await this.chatService.init(context);
    await this.apiService.init(context);
    await this.refreshQuotaInfo(context);
    
    // 加载历史消息
    const storedMessages = this.chatService.getMessages();
    if (storedMessages.length > 0) {
      // 有历史记录，转换为ChatMessage
      const loadedMsgs: ChatMessage[] = [];
      for (let i = 0; i < storedMessages.length; i++) {
        const stored = storedMessages[i];
        const msg = new ChatMessage(stored.role, stored.content);
        msg.id = stored.id;
        msg.timestamp = stored.timestamp;
        loadedMsgs.push(msg);
      }
      this.messages = loadedMsgs;
      // 滚动到底部
      setTimeout(() => {
        this.listScroller.scrollEdge(Edge.Bottom);
      }, 100);
    } else {
      // 没有历史，添加欢迎消息并保存
      const welcome = new ChatMessage('assistant', '你好！我是小语灵 🤖\n有任何韩语学习问题都可以问我哦~');
      this.messages.push(welcome);
      await this.chatService.addMessage(welcome.role, welcome.content);
    }
  }

  private async refreshQuotaInfo(context: Context): Promise<void> {
    try {
      if (!this.apiService.getToken()) {
        this.userInfo = new UserInfo();
        return;
      }
      this.userInfo = await this.apiService.getCurrentUserInfo();
    } catch (error) {
      console.warn('[SpiritChatPanel] load quota info failed:', JSON.stringify(error));
    }
  }

  aboutToDisappear() {
    this.cancelActiveRequest(false);
  }

  private cancelActiveRequest(showToast: boolean): void {
    this.chatRequestVersion += 1;
    this.isLoading = false;
    this.canStop = false;

    if (this.activeChatRequest !== null) {
      try {
        this.activeChatRequest.destroy();
      } catch (e) {
        console.error('[SpiritChatPanel] Cancel request failed:', JSON.stringify(e));
      }
      this.activeChatRequest = null;
    }

    if (showToast) {
      this.safeShowToast('已停止生成');
    }
  }

  private finalizeRequest(request: http.HttpRequest): void {
    if (this.activeChatRequest === request) {
      this.activeChatRequest = null;
    }

    try {
      request.destroy();
    } catch (_e) {
      // ignore repeated destroy
    }
  }
  
  // 发送消息
  async sendMessage() {
    const text = this.inputText.trim();
    if (!text || this.isLoading) return;
    
    // 添加用户消息
    const userMsg = new ChatMessage('user', text);
    this.messages.push(userMsg);
    this.inputText = '';
    this.isLoading = true;
    this.canStop = true;
    
    // 保存用户消息
    await this.chatService.addMessage(userMsg.role, userMsg.content);
    
    // 滚动到底部
    setTimeout(() => {
      this.listScroller.scrollEdge(Edge.Bottom);
    }, 100);
    
    // 构建API所需的消息列表（不包含欢迎消息）
    const apiMessages: SpiritChatMessageItem[] = [];
    for (let i = 1; i < this.messages.length; i++) { // 跳过欢迎消息
      const msg = this.messages[i];
      let content = msg.content;
      // 如果是最后一条消息（刚刚发送的）且有上下文
      if (i === this.messages.length - 1 && this.currentContext) {
          content = `【上下文信息：\n${this.currentContext}】\n\n${content}`;
      }
      apiMessages.push(new SpiritChatMessageItem(msg.role, content));
    }

    const requestVersion = ++this.chatRequestVersion;
    const request = http.createHttp();
    this.activeChatRequest = request;

    // 调用API获取回复
    try {
      const reply = await this.apiService.spiritChat(apiMessages, request);
      if (requestVersion !== this.chatRequestVersion || this.activeChatRequest !== request) {
        return;
      }

      if (reply) {
        const assistantMsg = new ChatMessage('assistant', reply);
        this.messages.push(assistantMsg);
        await this.chatService.addMessage(assistantMsg.role, assistantMsg.content);
      } else {
        const errorMsg = new ChatMessage('assistant', '抱歉，我暂时无法回答，请稍后再试 🙏');
        this.messages.push(errorMsg);
        await this.chatService.addMessage(errorMsg.role, errorMsg.content);
      }
    } catch (e) {
      if (requestVersion !== this.chatRequestVersion || this.activeChatRequest !== request) {
        return;
      }

      let errorText = '网络异常，请检查连接后重试 📡';
      if (e instanceof ApiError) {
        errorText = e.message;
      }
      const errorMsg = new ChatMessage('assistant', errorText);
      this.messages.push(errorMsg);
      await this.chatService.addMessage(errorMsg.role, errorMsg.content);
    } finally {
      const shouldResetUi = requestVersion === this.chatRequestVersion && this.activeChatRequest === request;
      this.finalizeRequest(request);
      await this.refreshQuotaInfo(getContext(this));

      if (shouldResetUi) {
        this.isLoading = false;
        this.canStop = false;
        setTimeout(() => {
          this.listScroller.scrollEdge(Edge.Bottom);
        }, 100);
      }
    }
  }
  
  // 停止生成
  stopGeneration() {
    this.cancelActiveRequest(true);
  }
  
  // 清空对话历史
  async clearHistory() {
    this.cancelActiveRequest(false);
    await this.chatService.clearSession();
    this.messages = [];
    // 添加新的欢迎消息
    const welcome = new ChatMessage('assistant', '你好！我是小语灵 🤖\n有任何韩语学习问题都可以问我哦~');
    this.messages.push(welcome);
    await this.chatService.addMessage(welcome.role, welcome.content);
  }

  private aiQuotaSummary(): string {
    if (this.userInfo.dailyAiLimit <= 0) {
      return '当前会员今日可不限量向小语灵提问';
    }
    if (this.userInfo.dailyAiRemaining <= 0) {
      return `今日 ${this.userInfo.dailyAiLimit} 次提问额度已用完`;
    }
    return `今日还可提问 ${this.userInfo.dailyAiRemaining}/${this.userInfo.dailyAiLimit} 次`;
  }

  private aiQuotaCaption(): string {
    if (this.userInfo.dailyAiLimit <= 0) {
      return '后续会员能力开放后，这里会同步展示最新提问规则。';
    }
    if (this.userInfo.dailyAiRemaining <= 0) {
      return '明天会自动恢复额度，可以先继续课程学习或使用词典。';
    }
    if (this.userInfo.dailyAiRemaining <= 3) {
      return '剩余次数不多了，优先问当前关卡最关键的问题更划算。';
    }
    return '同一学习上下文里，10 分钟内重复提问相同问题不重复扣减。';
  }

  private aiQuotaBadge(): string {
    if (this.userInfo.dailyAiLimit <= 0) {
      return '不限量';
    }
    if (this.userInfo.dailyAiRemaining <= 0) {
      return '已用完';
    }
    return `剩 ${this.userInfo.dailyAiRemaining} 次`;
  }

  private aiQuotaTextColor(): string {
    if (this.userInfo.dailyAiLimit > 0 && this.userInfo.dailyAiRemaining <= 0) {
      return UI.DANGER_TEXT;
    }
    if (this.userInfo.dailyAiRemaining <= 3) {
      return UI.WARM;
    }
    return COLORS.TEXT_SECONDARY;
  }

  private aiQuotaBadgeTextColor(): string {
    if (this.userInfo.dailyAiLimit > 0 && this.userInfo.dailyAiRemaining <= 0) {
      return UI.DANGER_TEXT;
    }
    if (this.userInfo.dailyAiRemaining <= 3) {
      return UI.WARM;
    }
    return COLORS.PRIMARY;
  }

  private aiQuotaBadgeBackground(): string {
    if (this.userInfo.dailyAiLimit > 0 && this.userInfo.dailyAiRemaining <= 0) {
      return UI.DANGER_SOFT;
    }
    if (this.userInfo.dailyAiRemaining <= 3) {
      return UI.WARM_SOFT;
    }
    return UI.GREEN_SOFT;
  }
  
  build() {
    Column() {
      // 标题与对话操作
      Row({ space: 8 }) {
        Image($r('app.media.lingai_robot'))
          .width(40)
          .height(40)
          .objectFit(ImageFit.Contain)
          .padding(4)
          .backgroundColor(UI.GREEN_SOFT)
          .borderRadius(18)
        Column({ space: 4 }) {
          Text('小语灵助手')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text('韩语学习 AI')
            .fontSize(12)
            .fontColor(UI.BLUE)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 清空对话按钮
        Button() {
          Text('清空')
            .fontSize(12)
            .fontColor(COLORS.TEXT_SECONDARY)
        }
        .width(UI.TOUCH_MIN)
        .height(UI.TOUCH_MIN)
        .backgroundColor(UI.SURFACE_MUTED)
        .borderRadius(UI.CONTROL_RADIUS)
        .onClick(() => {
          this.clearHistory();
        })

        // 关闭按钮
        Button() {
          Text('✕')
            .fontSize(18)
            .fontColor(COLORS.TEXT_SECONDARY)
        }
        .width(UI.TOUCH_MIN)
        .height(UI.TOUCH_MIN)
        .type(ButtonType.Circle)
        .backgroundColor(UI.SURFACE_MUTED)
        .onClick(() => {
          if (this.onClose) {
            this.onClose();
          }
        })
      }
      .width('100%')
      .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 12, bottom: 12 })

      Row({ space: 8 }) {
        Text(this.aiQuotaSummary())
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor(COLORS.TEXT_PRIMARY)
          .layoutWeight(1)

        Text(this.aiQuotaBadge())
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.aiQuotaBadgeTextColor())
          .padding({ left: 10, right: 10, top: 6, bottom: 6 })
          .backgroundColor(this.aiQuotaBadgeBackground())
          .borderRadius(999)
      }
      .width(`calc(100% - ${UI.PAGE_INSET * 2}vp)`)
      .margin({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, bottom: 12 })
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(UI.BLUE_SOFT)
      .borderRadius(UI.CONTROL_RADIUS)
      
      // 消息列表
      List({ scroller: this.listScroller, space: 16 }) {
        ListItem() {
          Text(this.aiQuotaCaption())
            .fontSize(12)
            .fontColor(this.aiQuotaTextColor())
            .lineHeight(18)
            .width('100%')
        }

        ForEach(this.messages, (msg: ChatMessage) => {
          ListItem() {
            this.MessageBubble(msg)
          }
        })
        
        // 加载中指示器
        if (this.isLoading) {
          ListItem() {
            Row() {
              LoadingProgress()
                .width(20)
                .height(20)
                .color(COLORS.PRIMARY)
              Text('思考中...')
                .fontSize(14)
                .fontColor(COLORS.TEXT_HINT)
                .margin({ left: 8 })
            }
            .padding(12)
          }
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET })
      
      // 底部输入区
      Row() {
        // 输入框
        TextInput({ placeholder: '输入问题...', text: this.inputText })
          .layoutWeight(1)
          .height(48)
          .backgroundColor(COLORS.SURFACE)
          .borderRadius(UI.CONTROL_RADIUS)
          .fontSize(UI.BODY_SIZE)
          .fontColor(COLORS.TEXT_PRIMARY)
          .placeholderColor(COLORS.TEXT_HINT)
          .border({ width: 1, color: COLORS.BORDER })
          .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET })
          .onChange((value: string) => {
            this.inputText = value;
          })
          .onSubmit(() => {
            this.sendMessage();
          })
        
        // 发送/停止按钮
        if (this.canStop) {
          Button() {
            Text('⏹')
              .fontSize(18)
              .fontColor(UI.DANGER_TEXT)
          }
          .width(48)
          .height(48)
          .type(ButtonType.Normal)
          .borderRadius(UI.CONTROL_RADIUS)
          .backgroundColor(UI.DANGER_SOFT)
          .margin({ left: 8 })
          .onClick(() => {
            this.stopGeneration();
          })
        } else {
          Button() {
            Text('➤')
              .fontSize(18)
              .fontColor(this.inputText.trim() ? UI.ON_BLUE : COLORS.TEXT_HINT)
          }
          .width(48)
          .height(48)
          .type(ButtonType.Normal)
          .borderRadius(UI.CONTROL_RADIUS)
          .backgroundColor(this.inputText.trim() ? UI.BLUE : UI.SURFACE_MUTED)
          .margin({ left: 8 })
          .enabled(this.inputText.trim().length > 0)
          .onClick(() => {
            this.sendMessage();
          })
        }
      }
      .width('100%')
      .padding({ left: UI.PAGE_INSET, right: UI.PAGE_INSET, top: 12, bottom: 24 })
      .backgroundColor(COLORS.BACKGROUND)
      .border({ width: { top: 1 }, color: COLORS.BORDER })
    }
    .width('100%')
    .height(this.panelHeight)
    .backgroundColor(COLORS.BACKGROUND)
    .borderRadius({ topLeft: 28, topRight: 28 })
    .onAppear(() => {
      this.applyKeyboardResize();
    })
    .onDisAppear(() => {
      this.restoreKeyboardAvoidMode();
    })
  }
  
  @Builder
  MessageBubble(msg: ChatMessage) {
    Row() {
      if (msg.role === 'user') {
        Blank()
      }
      if (msg.role === 'assistant') {
        Image($r('app.media.lingai_robot'))
          .width(32)
          .height(32)
          .objectFit(ImageFit.Contain)
          .padding(3)
          .backgroundColor(UI.GREEN_SOFT)
          .borderRadius(11)
          .margin({ right: 8 })
          .alignSelf(ItemAlign.Start)
      }
      
      Column() {
        Text(msg.content)
          .fontSize(UI.BODY_SIZE)
          .fontColor(msg.role === 'user' ? UI.ON_BLUE : COLORS.TEXT_PRIMARY)
          .lineHeight(24)
          .copyOption(CopyOptions.LocalDevice)
        
        // 助手消息显示复制按钮
        if (msg.role === 'assistant' && msg.content.indexOf('你好！我是小语灵') === -1) {
          Row() {
            // 复制按钮
            Button() {
              Text('复制')
                .fontSize(12)
                .fontColor(UI.BLUE)
            }
            .width(52)
            .height(UI.TOUCH_MIN)
            .type(ButtonType.Normal)
            .borderRadius(12)
            .backgroundColor(UI.BLUE_SOFT)
            .onClick(() => {
              this.copyText(msg.content);
            })
          }
          .margin({ top: 8 })
        }
      }
      .padding(16)
      .backgroundColor(msg.role === 'user' ? UI.BLUE : COLORS.SURFACE)
      .borderRadius({ topLeft: msg.role === 'user' ? 20 : 4, topRight: msg.role === 'user' ? 4 : 20, bottomLeft: 20, bottomRight: 20 })
      .constraintSize({ maxWidth: '78%' })
      .alignItems(HorizontalAlign.Start)
      
    }
    .width('100%')
  }
}
