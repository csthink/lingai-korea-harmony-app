/**
 * 可选文本组件
 * 支持长按选词、自定义菜单（翻译/朗读/复制/加入生词本/AI详解）
 * 翻译结果直接显示在工具栏下方
 */
import pasteboard from '@ohos.pasteboard';
import promptAction from '@ohos.promptAction';
import ApiService, { ApiError } from '../services/ApiService';
import { COLORS } from '../utils/Constants';
import { UI } from '../utils/UiTokens';

// 操作回调接口
export interface SelectableTextCallbacks {
  onPlay: (text: string) => void;
  onAddToVocabulary: (text: string) => void;
  onViewDetail: (text: string) => void; // 查看AI详解
}

@Component
export struct SelectableText {
  @Prop text: string = '';
  @Prop fontSize: number = 15;
  @Prop fontColor: string | Resource = '#333333';
  @Prop fontWeight: FontWeight = FontWeight.Normal;
  
  // 回调
  callbacks: SelectableTextCallbacks = {
    onPlay: () => {},
    onAddToVocabulary: () => {},
    onViewDetail: () => {}
  };

  @State selectedText: string = '';
  @State translateResult: string = '';
  @State isTranslating: boolean = false;
  @State showTranslation: boolean = false;

  private apiService: ApiService = ApiService.getInstance();

  // 检查选区是否有效（必须包含韩文或中文字符）
  isSelectionValid(): boolean {
    const text = this.selectedText.trim();
    if (text.length === 0) {
      return false;
    }
    // 必须包含韩文或中文字符，不能只是标点符号
    const koreanOrChinese = /[\uAC00-\uD7AF\u1100-\u11FF\u4E00-\u9FFF]/;
    return koreanOrChinese.test(text);
  }

  private safeShowToast(message: string, duration: number = 1500): void {
    try {
      promptAction.showToast({ message, duration });
    } catch (e) {
      console.error('[SelectableText] showToast failed:', e);
    }
  }

  // 显示空选区或无效选区提示
  showInvalidSelectionTip() {
    this.safeShowToast('请选择韩文或中文字符', 1500);
  }

  // 复制到剪贴板
  async copyToClipboard(text: string) {
    if (!this.isSelectionValid()) {
      this.showInvalidSelectionTip();
      return;
    }
    try {
      const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteboardData);
      this.safeShowToast('已复制', 1500);
    } catch (error) {
      console.error('[SelectableText] Copy failed:', JSON.stringify(error));
    }
  }

  // 翻译选中文本
  async translateSelectedText() {
    if (!this.isSelectionValid()) {
      this.showInvalidSelectionTip();
      return;
    }
    
    if (this.isTranslating) {
      return;
    }
    
    this.isTranslating = true;
    this.showTranslation = true;
    this.translateResult = '翻译中...';
    
    try {
      const result = await this.apiService.quickTranslate(this.selectedText.trim(), 'auto');
      if (result !== null) {
        this.translateResult = result.translation;
      } else {
        this.translateResult = '翻译失败';
      }
    } catch (error) {
      console.error('[SelectableText] Translate failed:', JSON.stringify(error));
      if (error instanceof ApiError) {
        this.translateResult = error.message;
      } else {
        this.translateResult = '翻译失败';
      }
    } finally {
      this.isTranslating = false;
    }
  }

  @Builder
  SelectionMenu() {
    Column() {
      // 工具栏按钮行
      Row() {
        // 翻译按钮
        Column() {
          Text('译')
            .fontSize(14)
            .fontColor(COLORS.TEXT_PRIMARY)
          Text('翻译')
            .fontSize(11)
            .fontColor(COLORS.TEXT_SECONDARY)
            .margin({ top: 2 })
        }
        .width(48)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.showTranslation ? UI.GREEN_SOFT : UI.BLUE_SOFT)
        .borderRadius(12)
        .onClick(() => {
          this.translateSelectedText();
        })

        // 朗读按钮
        Column() {
          Text('🔊')
            .fontSize(16)
          Text('朗读')
            .fontSize(11)
            .fontColor(COLORS.TEXT_SECONDARY)
            .margin({ top: 2 })
        }
        .width(48)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(UI.BLUE_SOFT)
        .borderRadius(12)
        .margin({ left: 6 })
        .onClick(() => {
          if (this.isSelectionValid()) {
            this.callbacks.onPlay(this.selectedText.trim());
          } else {
            this.showInvalidSelectionTip();
          }
        })

        // 复制按钮
        Column() {
          Text('📋')
            .fontSize(16)
          Text('复制')
            .fontSize(11)
            .fontColor(COLORS.TEXT_SECONDARY)
            .margin({ top: 2 })
        }
        .width(48)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(UI.BLUE_SOFT)
        .borderRadius(12)
        .margin({ left: 6 })
        .onClick(() => {
          this.copyToClipboard(this.selectedText.trim());
        })

        // 加入生词本按钮
        Column() {
          Text('📚')
            .fontSize(16)
          Text('生词')
            .fontSize(11)
            .fontColor(COLORS.TEXT_SECONDARY)
            .margin({ top: 2 })
        }
        .width(48)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(UI.BLUE_SOFT)
        .borderRadius(12)
        .margin({ left: 6 })
        .onClick(() => {
          if (this.isSelectionValid()) {
            this.callbacks.onAddToVocabulary(this.selectedText.trim());
          } else {
            this.showInvalidSelectionTip();
          }
        })

        // AI详解按钮
        Column() {
          Text('🔍')
            .fontSize(16)
          Text('详解')
            .fontSize(11)
            .fontColor(COLORS.TEXT_SECONDARY)
            .margin({ top: 2 })
        }
        .width(48)
        .height(56)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(UI.BLUE_SOFT)
        .borderRadius(12)
        .margin({ left: 6 })
        .onClick(() => {
          if (this.isSelectionValid()) {
            this.callbacks.onViewDetail(this.selectedText.trim());
          } else {
            this.showInvalidSelectionTip();
          }
        })
      }

      // 翻译结果显示区域 - 限制宽度与工具栏一致
      if (this.showTranslation) {
        Column() {
          Text(this.translateResult)
            .fontSize(14)
            .fontColor(COLORS.TEXT_PRIMARY)
            .fontWeight(FontWeight.Medium)
            .textAlign(TextAlign.Center)
            .maxLines(3)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width(270) // 5个按钮宽度: 48*5 + 6*4 = 264, 加padding
        .padding({ top: 10, bottom: 6, left: 12, right: 12 })
        .margin({ top: 8 })
        .backgroundColor(UI.GREEN_SOFT)
        .borderRadius(12)
      }
    }
    .padding(8)
    .backgroundColor(COLORS.SURFACE)
    .borderRadius(UI.CONTROL_RADIUS)
    .border({ width: 1, color: COLORS.BORDER })
    .shadow({ radius: 12, color: UI.SHADOW, offsetY: 4 })
  }

  build() {
    Text(this.text)
      .fontSize(this.fontSize)
      .fontColor(this.fontColor)
      .fontWeight(this.fontWeight)
      .lineHeight(this.fontSize * 1.5)
      .copyOption(CopyOptions.InApp)
      .onTextSelectionChange((start: number, end: number) => {
        if (start >= 0 && end > start && end <= this.text.length) {
          this.selectedText = this.text.substring(start, end);
          // 重置翻译状态
          this.showTranslation = false;
          this.translateResult = '';
          console.info(`[SelectableText] Selection changed: "${this.selectedText}"`);
        } else {
          this.selectedText = '';
        }
      })
      .bindSelectionMenu(TextSpanType.TEXT, this.SelectionMenu(), TextResponseType.LONG_PRESS)
  }
}
