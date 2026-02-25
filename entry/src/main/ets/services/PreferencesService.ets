/**
 * 偏好设置服务
 * 使用鸿蒙 Preferences 存储用户设置和简单状态
 */
import preferences from '@ohos.data.preferences';
import { STORAGE_KEYS } from '../utils/Constants';
import { UserSettings, LearningState } from '../models/DataModels';

// 导出数据结构
class ExportData {
  version: number = 0;
  exportTime: number = 0;
  settings: UserSettings = new UserSettings();
  state: LearningState = new LearningState();
}

/** 创建默认用户设置（每次返回新实例） */
function defaultUserSettings(): UserSettings {
  const s = new UserSettings();
  s.notificationEnabled = false;
  s.notificationTime = '09:00';
  s.autoDownloadCount = 3;
  return s;
}

/** 创建默认学习状态（每次返回新实例） */
function defaultLearningState(): LearningState {
  const s = new LearningState();
  s.currentLevel = 1;
  s.currentLesson = 1;
  s.lastOpenTime = 0;
  return s;
}

class PreferencesService {
  private static instance: PreferencesService;
  private preferencesStore: preferences.Preferences | null = null;
  private context: Context | null = null;

  private constructor() {}

  static getInstance(): PreferencesService {
    if (!PreferencesService.instance) {
      PreferencesService.instance = new PreferencesService();
    }
    return PreferencesService.instance;
  }

  /**
   * 初始化偏好设置
   */
  async init(context: Context): Promise<void> {
    this.context = context;

    try {
      this.preferencesStore = await preferences.getPreferences(context, 'lingai_prefs');
      console.info('Preferences initialized successfully');
    } catch (error) {
      const msg = (error instanceof Error) ? error.message : String(error);
      console.error('Preferences init failed:', msg);
      throw new Error('Preferences init failed: ' + msg);
    }
  }

  // ==================== 用户设置 ====================

  /**
   * 获取用户设置
   */
  async getUserSettings(): Promise<UserSettings> {
    if (!this.preferencesStore) throw new Error('Preferences not initialized');

    try {
      const settingsStr = await this.preferencesStore.get(STORAGE_KEYS.USER_SETTINGS, '');
      
      if (settingsStr) {
        return JSON.parse(settingsStr as string) as UserSettings;
      }
      
      return defaultUserSettings();
    } catch (error) {
      console.error('Get user settings failed:', error);
      return defaultUserSettings();
    }
  }

  /**
   * 保存用户设置
   */
  async saveUserSettings(settings: UserSettings): Promise<void> {
    if (!this.preferencesStore) throw new Error('Preferences not initialized');

    try {
      await this.preferencesStore.put(STORAGE_KEYS.USER_SETTINGS, JSON.stringify(settings));
      await this.preferencesStore.flush();
    } catch (error) {
      const msg = (error instanceof Error) ? error.message : String(error);
      console.error('Save user settings failed:', msg);
      throw new Error('Save user settings failed: ' + msg);
    }
  }

  // ==================== 学习状态 ====================

  /**
   * 获取学习状态
   */
  async getLearningState(): Promise<LearningState> {
    if (!this.preferencesStore) throw new Error('Preferences not initialized');

    try {
      const stateStr = await this.preferencesStore.get(STORAGE_KEYS.LEARNING_STATE, '');
      
      if (stateStr) {
        return JSON.parse(stateStr as string) as LearningState;
      }
      
      return defaultLearningState();
    } catch (error) {
      console.error('Get learning state failed:', error);
      return defaultLearningState();
    }
  }

  /**
   * 保存学习状态
   */
  async saveLearningState(state: LearningState): Promise<void> {
    if (!this.preferencesStore) throw new Error('Preferences not initialized');

    try {
      await this.preferencesStore.put(STORAGE_KEYS.LEARNING_STATE, JSON.stringify(state));
      await this.preferencesStore.flush();
    } catch (error) {
      const msg = (error instanceof Error) ? error.message : String(error);
      console.error('Save learning state failed:', msg);
      throw new Error('Save learning state failed: ' + msg);
    }
  }

  /**
   * 更新最后打开时间
   */
  async updateLastOpenTime(): Promise<void> {
    const state = await this.getLearningState();
    state.lastOpenTime = Date.now();
    await this.saveLearningState(state);
  }

  /**
   * 更新当前进度
   */
  async updateCurrentProgress(level: number, lesson: number): Promise<void> {
    const state = await this.getLearningState();
    state.currentLevel = level;
    state.currentLesson = lesson;
    state.lastOpenTime = Date.now();
    await this.saveLearningState(state);
  }

  // ==================== 通知设置 ====================

  /**
   * 设置通知开关
   */
  async setNotificationEnabled(enabled: boolean): Promise<void> {
    const settings = await this.getUserSettings();
    settings.notificationEnabled = enabled;
    await this.saveUserSettings(settings);
  }

  /**
   * 设置通知时间
   */
  async setNotificationTime(time: string): Promise<void> {
    const settings = await this.getUserSettings();
    settings.notificationTime = time;
    await this.saveUserSettings(settings);
  }

  // ==================== 下载设置 ====================

  /**
   * 设置自动下载关卡数
   */
  async setAutoDownloadCount(count: number): Promise<void> {
    const settings = await this.getUserSettings();
    settings.autoDownloadCount = count;
    await this.saveUserSettings(settings);
  }

  // ==================== 导出/导入 ====================

  /**
   * 导出设置和进度
   */
  async exportData(): Promise<string> {
    const settings = await this.getUserSettings();
    const state = await this.getLearningState();
    
    const exp = new ExportData();
    exp.version = 1;
    exp.exportTime = Date.now();
    exp.settings = settings;
    exp.state = state;
    
    return JSON.stringify(exp);
  }

  /**
   * 导入设置和进度
   */
  async importData(dataStr: string): Promise<boolean> {
    try {
      const data = JSON.parse(dataStr) as ExportData;
      
      if (data.version !== 1) {
        console.error('Unsupported backup version');
        return false;
      }
      
      if (data.settings) {
        await this.saveUserSettings(data.settings);
      }
      
      if (data.state) {
        await this.saveLearningState(data.state);
      }
      
      return true;
    } catch (error) {
      console.error('Import data failed:', error);
      return false;
    }
  }
}

export default PreferencesService;
