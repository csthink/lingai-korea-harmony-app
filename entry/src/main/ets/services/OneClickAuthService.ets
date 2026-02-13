/**
 * 一键登录服务（阿里云 PNVS SDK 适配层）
 * 封装 SDK 初始化、预取号、拉起授权页等操作
 */
import common from '@ohos.app.ability.common';
import { PNVS_AUTH_SECRET } from '../utils/Constants';
import PhoneNumberAuthHelper, { TokenResultListener, AuthUiConfig } from 'numberauth_standard';

export enum OneClickError {
  USER_CANCELLED = 'USER_CANCELLED',          // 用户取消授权
  NETWORK_ERROR = 'NETWORK_ERROR',            // 网络问题
  CARRIER_ERROR = 'CARRIER_ERROR',            // 运营商校验失败
  NO_SIM = 'NO_SIM',                          // 无 SIM / 飞行模式
  SDK_NOT_AVAILABLE = 'SDK_NOT_AVAILABLE',    // SDK 不可用
  UNKNOWN = 'UNKNOWN',                        // 未知错误
  TIMEOUT = 'TIMEOUT',                        // 请求超时
}

export class OneClickAuthService {
  private static instance: OneClickAuthService;
  private initialized: boolean = false;
  private authHelper: PhoneNumberAuthHelper | undefined;
  
  // 当前请求的 Promise Resolver
  private tokenResolve: ((value: string) => void) | undefined;
  private tokenReject: ((reason?: Error) => void) | undefined;

  private constructor() {}

  static getInstance(): OneClickAuthService {
    if (!OneClickAuthService.instance) {
      OneClickAuthService.instance = new OneClickAuthService();
    }
    return OneClickAuthService.instance;
  }

  /**
   * 初始化 SDK
   */
  async init(context: common.UIAbilityContext): Promise<void> {
    if (this.initialized) return;
    
    try {
      // 获取实例并设置密钥 (Init 需要 Listener，传入空实现)
      this.authHelper = PhoneNumberAuthHelper.getInstance(context, {
        onSuccess: (msg) => console.debug('[OneClick] Init Listener success:', msg),
        onFailure: (ret) => console.debug('[OneClick] Init Listener failure:', ret)
      });
      this.authHelper.setAuthSDKInfo(PNVS_AUTH_SECRET);
      
      // 环境检查 (2: 一键登录)
      this.authHelper.checkEnvAvailable(2);
      
      console.info('[OneClickAuthService] Initialized');
      this.initialized = true;
    } catch (error) {
      console.error('[OneClickAuthService] Init failed:', JSON.stringify(error));
      this.initialized = false;
    }
  }

  /**
   * 预取号（加速授权页拉起）
   */
  async prefetch(): Promise<void> {
    if (!this.initialized || !this.authHelper) return;
    
    try {
      console.info('[OneClickAuthService] Prefetching...');
      this.authHelper.accelerateLoginPage(5000, {
        onTokenSuccess: (vendor) => {
          console.info('[OneClickAuthService] Prefetch success:', vendor);
        },
        onTokenFailed: (vendor, ret) => {
          console.warn('[OneClickAuthService] Prefetch failed:', vendor, ret);
        }
      });
    } catch (error) {
      console.error('[OneClickAuthService] Prefetch exception:', JSON.stringify(error));
    }
  }

  /**
   * 拉起授权页并获取 Token
   */
  async requestToken(context: common.UIAbilityContext): Promise<string> {
    if (!this.initialized) await this.init(context);
    
    // 如果 SDK 仍未初始化成功（可能是环境问题），抛出 SDK 不可用异常
    if (!this.authHelper) {
      throw new Error(OneClickError.SDK_NOT_AVAILABLE);
    }

    return new Promise((resolve, reject) => {
      this.tokenResolve = resolve;
      this.tokenReject = reject;
      
      // 定义监听器
      const listener: TokenResultListener = {
        onSuccess: (msg: string) => {
          console.info('[OneClickAuthService] onSuccess:', msg);
          try {
             // msg 格式: {"_code":"600000", "_token":"...", "_requestId": "..."}
             const res = JSON.parse(msg) as Record<string, Object>;
             const code = res['_code'] as string;
             const token = res['_token'] as string;
             const requestId = res['_requestId'] as string;
             console.info(`[OneClickAuthService] onSuccess code=${code}, requestId=${requestId}`);
             
             if (code === '600000' && token) {
                if (this.tokenResolve) this.tokenResolve(token);
                this.cleanup();
             } else if (code === '600001') {
                // 唤起授权页成功，等待用户操作，不 resolve
                console.info('[OneClickAuthService] Auth page presented');
             } else {
                console.warn('[OneClickAuthService] Unexpected success code:', code);
             }
          } catch (e) {
             console.error('[OneClickAuthService] Parse success msg failed:', e);
             if (this.tokenReject) this.tokenReject(new Error(OneClickError.UNKNOWN));
             this.cleanup();
          }
        },
        onFailure: (ret: string) => {
          console.warn('[OneClickAuthService] onFailure:', ret);
          // ret 格式: {"_code":"...", "_msg":"..."}
          let errorType = OneClickError.UNKNOWN;
          try {
             const res = JSON.parse(ret) as Record<string, Object>;
             const code = res['_code'] as string;
             
             // 错误码映射
             switch (code) {
               case '700000': // 用户点击返回/取消
                 errorType = OneClickError.USER_CANCELLED;
                 break;
               case '600004': // 获取 Token 失败
               case '600010': // 运营商未知错误
               case '600011': // 获取 token 失败
                 errorType = OneClickError.CARRIER_ERROR;
                 break;
               case '600005': // 手机号校验失败
               case '600007': // 网络错误
               case '600008': // 无蜂窝网络
               case '600013': // 运营商维护
               case '600014': // 运营商维护
               case '600015': // 接口超时
               case '600028': // 唤起授权页失败
                 errorType = OneClickError.NETWORK_ERROR;
                 break;
               case '600024': // 终端环境检查失败
               case '600025': // 环境检测失败
                 errorType = OneClickError.SDK_NOT_AVAILABLE;
                 break;
               default:
                 errorType = OneClickError.UNKNOWN;
                 break;
             }
          } catch (e) {
             console.error('[OneClickAuthService] Parse failure msg failed:', e);
          }

          if (this.tokenReject) this.tokenReject(new Error(errorType));
          this.cleanup();
        }
      };

      // 超时保护
      const timer = setTimeout(() => {
        if (this.tokenReject) {
            console.warn('[OneClickAuthService] requestToken timeout');
            this.tokenReject(new Error(OneClickError.TIMEOUT));
            this.cleanup();
        }
      }, 5000);

      // 重新绑定监听器
      try {
        this.authHelper = PhoneNumberAuthHelper.getInstance(context, listener);
        
        // 配置 UI（必调方法）
        let uiConfig = new AuthUiConfig();
        // ... ui config ...
        this.authHelper.setAuthConfig(uiConfig);
        
        // 拉起授权页
        this.authHelper.getLoginToken(5000);
      } catch (err) {
        clearTimeout(timer); // 清除定时器
        console.error('[OneClickAuthService] getLoginToken exception:', err);
        reject(new Error(OneClickError.SDK_NOT_AVAILABLE));
        this.cleanup();
      }
    });
  }

  private cleanup() {
    try {
      this.authHelper?.quitLoginPage();
      this.authHelper?.setAuthListener({
        onSuccess: (_msg: string) => {},
        onFailure: (_ret: string) => {}
      });
    } catch (e) {
      console.warn('[OneClickAuthService] Cleanup error:', e);
    }
    this.tokenResolve = undefined;
    this.tokenReject = undefined;
  }
}

export default OneClickAuthService;
