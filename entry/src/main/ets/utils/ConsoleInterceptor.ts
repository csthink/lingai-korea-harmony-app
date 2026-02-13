/**
 * 全局 Console 拦截器
 * 用于过滤 SDK 内部的敏感日志（如密钥、Token 等）
 */

export class ConsoleInterceptor {
  private static isInstalled = false;
  private static originalConsole = {
    log: console.log,
    debug: console.debug,
    info: console.info,
    warn: console.warn,
    error: console.error
  };

  /**
   * 初始化拦截器 (建议在 Ability onCreate 最早期调用)
   */
  public static init() {
    if (ConsoleInterceptor.isInstalled) {
      return;
    }

    try {
      // 定义敏感关键词
      const sensitiveKeywords = [
        'setAuthSDKInfo',
        'secretInfo',
        'accessCode',
        'token',
        '_token',
        'secret',
        'oy+' // 常见密钥前缀
      ];

      // 包装函数
      const wrap = (original: Function) => {
        return (...args: any[]) => {
          if (ConsoleInterceptor.shouldSuppress(args, sensitiveKeywords)) {
            return;
          }
          original(...args);
        };
      };

      // 覆盖全局 console 方法
      // @ts-ignore: 允许覆盖 console 方法
      console.log = wrap(ConsoleInterceptor.originalConsole.log);
      // @ts-ignore
      console.debug = wrap(ConsoleInterceptor.originalConsole.debug);
      // @ts-ignore
      console.info = wrap(ConsoleInterceptor.originalConsole.info);
      // @ts-ignore
      console.warn = wrap(ConsoleInterceptor.originalConsole.warn);
      // @ts-ignore
      console.error = wrap(ConsoleInterceptor.originalConsole.error);

      ConsoleInterceptor.isInstalled = true;
      ConsoleInterceptor.originalConsole.info('[ConsoleInterceptor] Global log filter installed.');
    } catch (e) {
      ConsoleInterceptor.originalConsole.warn('[ConsoleInterceptor] Failed to install:', e);
    }
  }

  /**
   * 检查是否包含敏感信息
   */
  private static shouldSuppress(args: any[], keywords: string[]): boolean {
    if (!args || args.length === 0) return false;

    try {
      // 将所有参数拼接成字符串检测
      const msg = args.map(a => {
        if (typeof a === 'object') {
          try {
            return JSON.stringify(a);
          } catch (e) {
            return String(a);
          }
        }
        return String(a);
      }).join(' ');

      // 只要包含任一敏感词，即拦截
      for (const keyword of keywords) {
        if (msg.includes(keyword)) {
          return true;
        }
      }
    } catch (e) {
      // 异常情况不拦截，避免丢日志
    }
    return false;
  }
}
