/**
 * LingAI 常量定义
 * 适配 ArkTS 严格模式
 */

import { UNIFIED_BASE_URL_DEV } from '../local/Secret.dev';

// ---- API 基址（开发/联调切换） ----
// 直连 FastAPI（仅本地调试用）
export const FASTAPI_DIRECT_URL: string = 'http://192.168.1.59:8000';
// Unified Service 网关（联调 & 生产）
export const UNIFIED_BASE_URL: string = UNIFIED_BASE_URL_DEV.trim();
// 当前生效基址由受控本地配置指定，客户端只访问 Unified
export const API_BASE_URL: string = UNIFIED_BASE_URL;

// ---- Unified 网关常量 ----
export const APP_ID: string = 'lingai-harmony';
export const AUTH_APP_ID: string = '1';
// ---- 请求签名 ----
// 默认拒绝未配置的请求；真实本地密钥由 EntryAbility 从忽略文件注入。
export const APP_KEY: string = '';
export const APP_PRIVATE_KEY: string = '';
// ---- 一键登录（阿里云 PNVS）----
// 缺少真实 SDK 密钥时拒绝初始化和登录，不回退到占位值。
export const PNVS_AUTH_SECRET: string = '';
export const BIZ_API_PREFIX: string = '/api/app/biz';
export const AUTH_API_PREFIX: string = '/api/app/auth';

// 学习配置
export const WORDS_PER_LESSON: number = 20;
export const MASTERY_THRESHOLD: number = 0.85;
export const CORRECT_COUNT_REQUIRED: number = 2;
export const MAX_SKIP_WORDS: number = 10;

// 复习间隔（天）
export const REVIEW_INTERVALS: number[] = [0, 1, 3, 7, 14, 30];

// 每日任务
export const DAILY_REVIEW_LIMIT: number = 20;
export const DAILY_STUDY_GOAL_MINUTES: number = 60;

// TOPIK 等级配置 - 使用类定义
export class TopikLevelConfig {
  level: number = 0;
  name: string = '';
  lessonStart: number = 0;
  lessonEnd: number = 0;
  lessonCount: number = 0;

  constructor(level: number, name: string, lessonStart: number, lessonEnd: number, lessonCount: number) {
    this.level = level;
    this.name = name;
    this.lessonStart = lessonStart;
    this.lessonEnd = lessonEnd;
    this.lessonCount = lessonCount;
  }
}

export const TOPIK_LEVELS: TopikLevelConfig[] = [
  new TopikLevelConfig(1, 'TOPIK I', 1, 78, 78),      // 1559词 / 20 = 78关
  new TopikLevelConfig(2, 'TOPIK II', 1, 189, 189),   // 3764词 / 20 = 189关
  new TopikLevelConfig(0, '常考单词', 1, 61, 61),     // 1203词 / 20 = 61关
];

// 题型配置
export const QUIZ_TYPE_BASIC_RECOGNITION: string = 'basic_recognition';
export const QUIZ_TYPE_CONTEXT_SENSE: string = 'context_sense';
export const QUIZ_TYPE_CONFUSION_WORDS: string = 'confusion_words';
export const QUIZ_TYPE_COLLOCATION_FILL: string = 'collocation_fill';

// 浅色主题色彩
export class LightTheme {
  // 背景色
  static readonly BG_BODY: string = '#f8fafc';
  static readonly BG_FRAME: string = '#f1f5f9';
  static readonly GLASS_SURFACE: string = '#ffffff';
  static readonly GLASS_SURFACE_ALPHA: string = 'rgba(255,255,255,0.95)';

  // 文字色
  static readonly TEXT_MAIN: string = '#0f172a';
  static readonly TEXT_SUB: string = '#475569';
  static readonly TEXT_DIM: string = '#94a3b8';

  // 品牌色
  static readonly PRIMARY: string = '#6366f1';
  static readonly PRIMARY_LIGHT: string = '#818cf8';
  static readonly PRIMARY_DARK: string = '#4f46e5';
  static readonly ACCENT: string = '#06b6d4';
  static readonly SUCCESS: string = '#10b981';
  static readonly WARNING: string = '#f59e0b';
  static readonly ERROR: string = '#f43f5e';

  // 边框和阴影
  static readonly BORDER: string = '#e2e8f0';
  static readonly GLASS_BORDER: string = 'rgba(0,0,0,0.06)';
  static readonly CARD_SHADOW: string = '0 8px 24px rgba(148,163,184,0.15)';

  // 导航栏
  static readonly NAV_BG: string = 'rgba(255,255,255,0.9)';
}

// 深色主题色彩
export class DarkTheme {
  // 背景色
  static readonly BG_BODY: string = '#050505';
  static readonly BG_FRAME: string = '#0f172a';
  static readonly GLASS_SURFACE: string = '#1e293b';
  static readonly GLASS_SURFACE_ALPHA: string = 'rgba(30,41,59,0.7)';

  // 文字色
  static readonly TEXT_MAIN: string = '#f8fafc';
  static readonly TEXT_SUB: string = '#94a3b8';
  static readonly TEXT_DIM: string = '#64748b';

  // 品牌色 (保持一致)
  static readonly PRIMARY: string = '#6366f1';
  static readonly PRIMARY_LIGHT: string = '#a78bfa';
  static readonly PRIMARY_DARK: string = '#4f46e5';
  static readonly ACCENT: string = '#06b6d4';
  static readonly SUCCESS: string = '#10b981';
  static readonly WARNING: string = '#f59e0b';
  static readonly ERROR: string = '#f43f5e';

  // 边框和阴影
  static readonly BORDER: string = '#334155';
  static readonly GLASS_BORDER: string = 'rgba(255,255,255,0.08)';
  static readonly CARD_SHADOW: string = '0 4px 20px rgba(0,0,0,0.2)';

  // 导航栏
  static readonly NAV_BG: string = 'rgba(15,23,42,0.9)';
}

// 动态主题类 - 根据isDark返回对应颜色
export class ThemeColors {
  private isDark: boolean;

  constructor(isDark: boolean = false) {
    this.isDark = isDark;
  }

  get BG_BODY(): string { return this.isDark ? DarkTheme.BG_BODY : LightTheme.BG_BODY; }
  get BG_FRAME(): string { return this.isDark ? DarkTheme.BG_FRAME : LightTheme.BG_FRAME; }
  get GLASS_SURFACE(): string { return this.isDark ? DarkTheme.GLASS_SURFACE : LightTheme.GLASS_SURFACE; }
  get GLASS_SURFACE_ALPHA(): string { return this.isDark ? DarkTheme.GLASS_SURFACE_ALPHA : LightTheme.GLASS_SURFACE_ALPHA; }

  get TEXT_MAIN(): string { return this.isDark ? DarkTheme.TEXT_MAIN : LightTheme.TEXT_MAIN; }
  get TEXT_SUB(): string { return this.isDark ? DarkTheme.TEXT_SUB : LightTheme.TEXT_SUB; }
  get TEXT_DIM(): string { return this.isDark ? DarkTheme.TEXT_DIM : LightTheme.TEXT_DIM; }

  get PRIMARY(): string { return this.isDark ? DarkTheme.PRIMARY : LightTheme.PRIMARY; }
  get PRIMARY_LIGHT(): string { return this.isDark ? DarkTheme.PRIMARY_LIGHT : LightTheme.PRIMARY_LIGHT; }
  get PRIMARY_DARK(): string { return this.isDark ? DarkTheme.PRIMARY_DARK : LightTheme.PRIMARY_DARK; }
  get ACCENT(): string { return this.isDark ? DarkTheme.ACCENT : LightTheme.ACCENT; }
  get SUCCESS(): string { return this.isDark ? DarkTheme.SUCCESS : LightTheme.SUCCESS; }
  get WARNING(): string { return this.isDark ? DarkTheme.WARNING : LightTheme.WARNING; }
  get ERROR(): string { return this.isDark ? DarkTheme.ERROR : LightTheme.ERROR; }

  get BORDER(): string { return this.isDark ? DarkTheme.BORDER : LightTheme.BORDER; }
  get GLASS_BORDER(): string { return this.isDark ? DarkTheme.GLASS_BORDER : LightTheme.GLASS_BORDER; }
  get CARD_SHADOW(): string { return this.isDark ? DarkTheme.CARD_SHADOW : LightTheme.CARD_SHADOW; }
  get NAV_BG(): string { return this.isDark ? DarkTheme.NAV_BG : LightTheme.NAV_BG; }
}

// 全局主题运行时状态（由 ThemeManager 同步）
let runtimeIsDarkMode: boolean = false;

export function setRuntimeDarkMode(isDark: boolean): void {
  runtimeIsDarkMode = isDark;
}

export function isRuntimeDarkMode(): boolean {
  return runtimeIsDarkMode;
}

// 保持向后兼容 - AppColors 改为运行时动态主题
export class AppColors {
  static get PRIMARY(): string { return runtimeIsDarkMode ? DarkTheme.PRIMARY : LightTheme.PRIMARY; }
  static get PRIMARY_LIGHT(): string { return runtimeIsDarkMode ? DarkTheme.PRIMARY_LIGHT : LightTheme.PRIMARY_LIGHT; }
  static get PRIMARY_DARK(): string { return runtimeIsDarkMode ? DarkTheme.PRIMARY_DARK : LightTheme.PRIMARY_DARK; }
  static get SECONDARY(): string { return runtimeIsDarkMode ? DarkTheme.SUCCESS : LightTheme.SUCCESS; }
  static get ACCENT(): string { return runtimeIsDarkMode ? DarkTheme.WARNING : LightTheme.WARNING; }
  static get SUCCESS(): string { return runtimeIsDarkMode ? DarkTheme.SUCCESS : LightTheme.SUCCESS; }
  static get WARNING(): string { return runtimeIsDarkMode ? DarkTheme.WARNING : LightTheme.WARNING; }
  static get ERROR(): string { return runtimeIsDarkMode ? DarkTheme.ERROR : LightTheme.ERROR; }
  static get BACKGROUND(): string { return runtimeIsDarkMode ? DarkTheme.BG_BODY : LightTheme.BG_BODY; }
  static get SURFACE(): string { return runtimeIsDarkMode ? DarkTheme.GLASS_SURFACE : LightTheme.GLASS_SURFACE; }
  static get TEXT_PRIMARY(): string { return runtimeIsDarkMode ? DarkTheme.TEXT_MAIN : LightTheme.TEXT_MAIN; }
  static get TEXT_SECONDARY(): string { return runtimeIsDarkMode ? DarkTheme.TEXT_SUB : LightTheme.TEXT_SUB; }
  static get TEXT_HINT(): string { return runtimeIsDarkMode ? DarkTheme.TEXT_DIM : LightTheme.TEXT_DIM; }
  static get BORDER(): string { return runtimeIsDarkMode ? DarkTheme.BORDER : LightTheme.BORDER; }
  static get NAV_BG(): string { return runtimeIsDarkMode ? DarkTheme.NAV_BG : LightTheme.NAV_BG; }
}

// 兼容代理类 —— 避免 class 直接作为 object 导出（arkts-no-classes-as-obj）
class ColorsCompat {
  get PRIMARY(): string { return AppColors.PRIMARY; }
  get PRIMARY_LIGHT(): string { return AppColors.PRIMARY_LIGHT; }
  get PRIMARY_DARK(): string { return AppColors.PRIMARY_DARK; }
  get SECONDARY(): string { return AppColors.SECONDARY; }
  get ACCENT(): string { return AppColors.ACCENT; }
  get SUCCESS(): string { return AppColors.SUCCESS; }
  get WARNING(): string { return AppColors.WARNING; }
  get ERROR(): string { return AppColors.ERROR; }
  get BACKGROUND(): string { return AppColors.BACKGROUND; }
  get SURFACE(): string { return AppColors.SURFACE; }
  get TEXT_PRIMARY(): string { return AppColors.TEXT_PRIMARY; }
  get TEXT_SECONDARY(): string { return AppColors.TEXT_SECONDARY; }
  get TEXT_HINT(): string { return AppColors.TEXT_HINT; }
  get BORDER(): string { return AppColors.BORDER; }
  get NAV_BG(): string { return AppColors.NAV_BG; }
}

// 为了兼容性，保留 COLORS 对象
export const COLORS = new ColorsCompat();

// 存储 Key（聚合对象，与 PreferencesService 保持一致）
export class STORAGE_KEYS {
  static readonly USER_SETTINGS: string = 'user_settings';
  static readonly LEARNING_STATE: string = 'learning_state';
  static readonly DAILY_TASK: string = 'daily_task';
  static readonly AUTH_TOKEN: string = 'auth_token';
  static readonly REFRESH_TOKEN: string = 'refresh_token';
  static readonly DEVICE_ID: string = 'device_id';
}

// 数据库配置
export const DB_NAME: string = 'LingAI.db';
export const DB_VERSION: number = 1;

export class DB_CONFIG {
  static readonly DB_NAME: string = 'LingAI.db';
  static readonly DB_VERSION: number = 1;
}
