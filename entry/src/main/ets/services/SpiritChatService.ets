/**
 * AI精灵对话服务
 * 管理对话历史的本地存储
 */
import dataPreferences from '@ohos.data.preferences';

// 存储的消息格式
class StoredMessage {
  id: string = '';
  role: string = '';
  content: string = '';
  timestamp: number = 0;
}

// 存储的会话格式
class StoredSession {
  id: string = '';
  messages: StoredMessage[] = [];
  createdAt: number = 0;
  updatedAt: number = 0;
}

const PREFERENCES_NAME = 'spirit_chat';
const CURRENT_SESSION_KEY = 'current_session';

class SpiritChatService {
  private static instance: SpiritChatService;
  private preferences: dataPreferences.Preferences | null = null;
  private currentSession: StoredSession | null = null;
  
  private constructor() {}
  
  static getInstance(): SpiritChatService {
    if (!SpiritChatService.instance) {
      SpiritChatService.instance = new SpiritChatService();
    }
    return SpiritChatService.instance;
  }
  
  async init(context: Context): Promise<void> {
    try {
      this.preferences = await dataPreferences.getPreferences(context, PREFERENCES_NAME);
      await this.loadCurrentSession();
      console.info('[SpiritChatService] Initialized');
    } catch (e) {
      console.error('[SpiritChatService] Init failed:', JSON.stringify(e));
    }
  }
  
  // 加载当前会话
  private async loadCurrentSession(): Promise<void> {
    if (!this.preferences) return;
    
    try {
      const sessionStr = await this.preferences.get(CURRENT_SESSION_KEY, '') as string;
      if (sessionStr) {
        const parsed = JSON.parse(sessionStr) as StoredSession;
        this.currentSession = parsed;
        console.info(`[SpiritChatService] Loaded session with ${this.currentSession.messages.length} messages`);
      }
    } catch (e) {
      console.error('[SpiritChatService] Load session failed:', JSON.stringify(e));
    }
  }
  
  // 获取当前会话消息
  getMessages(): StoredMessage[] {
    if (!this.currentSession) {
      return [];
    }
    return this.currentSession.messages;
  }
  
  // 添加消息并保存
  async addMessage(role: string, content: string): Promise<StoredMessage> {
    const msg = new StoredMessage();
    msg.id = `msg_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    msg.role = role;
    msg.content = content;
    msg.timestamp = Date.now();
    
    if (!this.currentSession) {
      this.currentSession = new StoredSession();
      this.currentSession.id = `session_${Date.now()}`;
      this.currentSession.messages = [];
      this.currentSession.createdAt = Date.now();
    }
    
    this.currentSession.messages.push(msg);
    this.currentSession.updatedAt = Date.now();
    
    await this.saveCurrentSession();
    return msg;
  }
  
  // 保存当前会话
  private async saveCurrentSession(): Promise<void> {
    if (!this.preferences || !this.currentSession) return;
    
    try {
      await this.preferences.put(CURRENT_SESSION_KEY, JSON.stringify(this.currentSession));
      await this.preferences.flush();
    } catch (e) {
      console.error('[SpiritChatService] Save session failed:', JSON.stringify(e));
    }
  }
  
  // 清空当前会话
  async clearSession(): Promise<void> {
    this.currentSession = null;
    if (this.preferences) {
      try {
        await this.preferences.delete(CURRENT_SESSION_KEY);
        await this.preferences.flush();
        console.info('[SpiritChatService] Session cleared');
      } catch (e) {
        console.error('[SpiritChatService] Clear session failed:', JSON.stringify(e));
      }
    }
  }
}

export default SpiritChatService;
export { StoredMessage, StoredSession };
