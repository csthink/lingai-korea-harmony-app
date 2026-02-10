/**
 * 主题管理器
 * 管理应用的浅色/深色模式切换和持久化
 */
import preferences from '@ohos.data.preferences';
import { LightTheme, DarkTheme, setRuntimeDarkMode } from './Constants';

// 全局主题状态管理
@Observed
export class ThemeState {
  isDarkMode: boolean = false;
}

// 全局主题实例
export const globalTheme: ThemeState = new ThemeState();

/**
 * 主题管理器类
 * 单例模式，管理主题切换和持久化
 */
export class ThemeManager {
  private static instance: ThemeManager | null = null;
  private static readonly PREF_NAME: string = 'theme_settings';
  private static readonly KEY_IS_DARK: string = 'is_dark_mode';
  private listeners: Array<(isDark: boolean) => void> = [];

  private constructor() {}

  static getInstance(): ThemeManager {
    if (ThemeManager.instance === null) {
      ThemeManager.instance = new ThemeManager();
    }
    return ThemeManager.instance;
  }

  /**
   * 初始化主题（从持久化存储读取）
   */
  async init(context: Context): Promise<void> {
    try {
      const pref = await preferences.getPreferences(context, ThemeManager.PREF_NAME);
      const isDark = await pref.get(ThemeManager.KEY_IS_DARK, false) as boolean;
      globalTheme.isDarkMode = isDark;
      setRuntimeDarkMode(isDark);
      this.notifyListeners();
    } catch (e) {
      console.error('ThemeManager: Failed to init theme:', JSON.stringify(e));
      globalTheme.isDarkMode = false;
      setRuntimeDarkMode(false);
      this.notifyListeners();
    }
  }

  /**
   * 切换主题
   */
  async toggleTheme(context: Context): Promise<boolean> {
    const newValue = !globalTheme.isDarkMode;
    await this.setDarkMode(context, newValue);
    return newValue;
  }

  /**
   * 设置深色模式
   */
  async setDarkMode(context: Context, isDark: boolean): Promise<void> {
    globalTheme.isDarkMode = isDark;
    setRuntimeDarkMode(isDark);
    this.notifyListeners();
    try {
      const pref = await preferences.getPreferences(context, ThemeManager.PREF_NAME);
      await pref.put(ThemeManager.KEY_IS_DARK, isDark);
      await pref.flush();
    } catch (e) {
      console.error('ThemeManager: Failed to save theme:', JSON.stringify(e));
    }
  }

  /**
   * 获取当前是否为深色模式
   */
  isDark(): boolean {
    return globalTheme.isDarkMode;
  }

  // ============ 颜色获取方法 ============

  get bgBody(): string {
    return globalTheme.isDarkMode ? DarkTheme.BG_BODY : LightTheme.BG_BODY;
  }

  get bgFrame(): string {
    return globalTheme.isDarkMode ? DarkTheme.BG_FRAME : LightTheme.BG_FRAME;
  }

  get glassSurface(): string {
    return globalTheme.isDarkMode ? DarkTheme.GLASS_SURFACE : LightTheme.GLASS_SURFACE;
  }

  get textMain(): string {
    return globalTheme.isDarkMode ? DarkTheme.TEXT_MAIN : LightTheme.TEXT_MAIN;
  }

  get textSub(): string {
    return globalTheme.isDarkMode ? DarkTheme.TEXT_SUB : LightTheme.TEXT_SUB;
  }

  get textDim(): string {
    return globalTheme.isDarkMode ? DarkTheme.TEXT_DIM : LightTheme.TEXT_DIM;
  }

  get primary(): string {
    return globalTheme.isDarkMode ? DarkTheme.PRIMARY : LightTheme.PRIMARY;
  }

  get primaryLight(): string {
    return globalTheme.isDarkMode ? DarkTheme.PRIMARY_LIGHT : LightTheme.PRIMARY_LIGHT;
  }

  get primaryDark(): string {
    return globalTheme.isDarkMode ? DarkTheme.PRIMARY_DARK : LightTheme.PRIMARY_DARK;
  }

  get accent(): string {
    return globalTheme.isDarkMode ? DarkTheme.ACCENT : LightTheme.ACCENT;
  }

  get success(): string {
    return globalTheme.isDarkMode ? DarkTheme.SUCCESS : LightTheme.SUCCESS;
  }

  get warning(): string {
    return globalTheme.isDarkMode ? DarkTheme.WARNING : LightTheme.WARNING;
  }

  get error(): string {
    return globalTheme.isDarkMode ? DarkTheme.ERROR : LightTheme.ERROR;
  }

  get border(): string {
    return globalTheme.isDarkMode ? DarkTheme.BORDER : LightTheme.BORDER;
  }

  get glassBorder(): string {
    return globalTheme.isDarkMode ? DarkTheme.GLASS_BORDER : LightTheme.GLASS_BORDER;
  }

  get navBg(): string {
    return globalTheme.isDarkMode ? DarkTheme.NAV_BG : LightTheme.NAV_BG;
  }

  subscribe(listener: (isDark: boolean) => void): () => void {
    this.listeners.push(listener);
    return () => {
      this.listeners = this.listeners.filter((l) => l !== listener);
    };
  }

  private notifyListeners(): void {
    const isDark = globalTheme.isDarkMode;
    this.listeners.forEach((listener) => {
      listener(isDark);
    });
  }
}

// 导出单例
export const themeManager = ThemeManager.getInstance();
