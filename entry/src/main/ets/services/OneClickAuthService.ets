/**
 * 一键登录服务（阿里云 PNVS SDK 适配层）
 * 封装 SDK 初始化、预取号、拉起授权页等操作
 */
import common from '@ohos.app.ability.common';
import { PNVS_AUTH_SECRET } from '../utils/Constants';
import PhoneNumberAuthHelper, { TokenResultListener, AuthUiConfig, PageOrientation } from 'numberauth_standard';

export enum OneClickError {
  USER_CANCELLED = 'USER_CANCELLED',          // 用户取消授权
  NETWORK_ERROR = 'NETWORK_ERROR',            // 网络问题
  CARRIER_ERROR = 'CARRIER_ERROR',            // 运营商校验失败
  CONFIG_MISMATCH = 'CONFIG_MISMATCH',        // SDK 密钥/方案配置错误（600017 等）
  NO_SIM = 'NO_SIM',                          // 无 SIM / 飞行模式
  SDK_NOT_AVAILABLE = 'SDK_NOT_AVAILABLE',    // SDK 不可用
  UNKNOWN = 'UNKNOWN',                        // 未知错误
  TIMEOUT = 'TIMEOUT',                        // 请求超时
  RATE_LIMIT = 'RATE_LIMIT',                  // 请求过于频繁 (Throttling.User)
}

export class OneClickAuthService {
  private static instance: OneClickAuthService;
  private initialized: boolean = false;
  private authHelper: PhoneNumberAuthHelper | undefined;
  
  // 当前请求的 Promise Resolver
  private tokenResolve: ((value: string) => void) | undefined;
  private tokenReject: ((reason?: Error) => void) | undefined;
  private timeoutTimer: number = -1;
  // 运行时密钥覆盖（优先于 Constants 中的占位值）
  private secretOverride: string = '';



  private constructor() {}

  /**
   * 运行时注入真实密钥（用于本地调试，不提交到仓库）
   */
  overrideSecret(secret: string): void {
    this.secretOverride = secret.trim();
  }

  /**
   * 获取生效的 SDK 密钥（优先 override > Constants）
   * 为空或占位值则抛出 CONFIG_MISMATCH
   */
  private getValidatedSecret(): string {
    const sdkInfo = this.secretOverride.length > 0
      ? this.secretOverride
      : PNVS_AUTH_SECRET.trim();
    if (sdkInfo.length === 0 || sdkInfo === '__PNVS_SECRET_PLACEHOLDER__') {
      throw new Error(`${OneClickError.CONFIG_MISMATCH}:EMPTY_SECRET`);
    }
    return sdkInfo;
  }

  /**
   * 脱敏日志：长度 + 前后各 4 位摘要
   */


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
      // 校验密钥
      const sdkInfo = this.getValidatedSecret();

      // 获取实例并设置密钥 (Init 需要 Listener，传入空实现)
      this.authHelper = PhoneNumberAuthHelper.getInstance(context, {
        onSuccess: (msg) => console.debug('[OneClick] Init Listener success:', msg),
        onFailure: (ret) => console.debug('[OneClick] Init Listener failure:', ret)
      });

      this.authHelper.setAuthSDKInfo(sdkInfo);
      
      // 环境检查 (2: 一键登录)
      this.authHelper.checkEnvAvailable(2);


      
      console.info('[OneClickAuthService] Initialized');
      this.initialized = true;
    } catch (error) {
      console.error('[OneClickAuthService] Init failed:', JSON.stringify(error));
      this.initialized = false;
      // 如果是 CONFIG_MISMATCH 直接向上抛
      if (error instanceof Error && error.message.startsWith(OneClickError.CONFIG_MISMATCH)) {
        throw error;
      }
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
          this.clearTimeoutTimer();
          try {
             // 兼容 _code/code, _token/token, _requestId/requestId, _msg/msg
             const res = JSON.parse(msg) as Record<string, Object>;
             const code = (res['_code'] || res['code']) as string;
             const token = (res['_token'] || res['token']) as string;
             const requestId = (res['_requestId'] || res['requestId']) as string;
             
             if (code === '600000' && token) {
                if (this.tokenResolve) this.tokenResolve(token);
                this.cleanup();
             } else if (code === '600001') {
                // Auth page presented
             } else {
                // 将配置类错误码映射为 CONFIG_MISMATCH
                const errorType = this.classifyErrorCode(code);
                console.warn(`[OneClickAuthService] Unexpected success code=${code}, requestId=${requestId}, mapped=${errorType}`);
                if (this.tokenReject) this.tokenReject(new Error(`${errorType}:${code}`));
                this.cleanup();
             }
          } catch (e) {
             console.error('[OneClickAuthService] Parse success msg failed');
             if (this.tokenReject) this.tokenReject(new Error(`${OneClickError.UNKNOWN}:PARSE_ERROR`));
             this.cleanup();
          }
        },
        onFailure: (ret: string) => {
          this.clearTimeoutTimer();
          
          let errorType = OneClickError.UNKNOWN;
          let rawCode = 'UNKNOWN';
          
          try {
             const res = JSON.parse(ret) as Record<string, Object>;
             rawCode = (res['_code'] || res['code'] || 'UNKNOWN') as string;
             const requestId = (res['_requestId'] || res['requestId'] || '') as string;
             
             console.warn(`[OneClickAuthService] onFailure code=${rawCode}, requestId=${requestId}`);
             
             // 检查是否为限流 (Throttling.User 或 消息包含 flow control)
             const rawMsg = (res['_msg'] || res['msg'] || res['message'] || '') as string;
             if (rawCode === 'Throttling.User' || rawMsg.toLowerCase().includes('flow control')) {
               errorType = OneClickError.RATE_LIMIT;
             } else {
               errorType = this.classifyErrorCode(rawCode);
             }
          } catch (e) {
             console.error('[OneClickAuthService] Parse failure msg failed');
          }

          if (this.tokenReject) this.tokenReject(new Error(`${errorType}:${rawCode}`));
          this.cleanup();
        }
      };

      // 超时保护
      this.timeoutTimer = setTimeout(() => {
        if (this.tokenReject) {
            console.warn('[OneClickAuthService] requestToken timeout');
            this.tokenReject(new Error(`${OneClickError.TIMEOUT}:5000`));
            this.cleanup();
        }
      }, 5000);

      // 重新绑定监听器并确保密钥注入
      try {
        // 校验密钥
        const sdkInfo = this.getValidatedSecret();

        this.authHelper = PhoneNumberAuthHelper.getInstance(context, listener);
        
        // 每次 requestToken 都重新注入密钥，防止 getInstance 重建后丢失
        this.authHelper.setAuthSDKInfo(sdkInfo);
        
        // SDK 默认全屏授权页（先验证布局基线，后续再定制）
        this.authHelper.setDialog(false);

        let uiConfig = new AuthUiConfig();
        uiConfig.pageScreenOrientation = PageOrientation.PORTRAIT;

        // 顶部导航
        uiConfig.navColor = '#FFFFFF';
        uiConfig.navFontColor = '#111111';
        uiConfig.navFontSize = 26;
        uiConfig.navMarginTop = 16;

        // 号码文本（避免“看不见/位置异常”）
        uiConfig.numberFontColor = '#111111';
        uiConfig.numberFontSize = 30;
        uiConfig.numberMargin = { top: 220 };
        uiConfig.numberAlignRuleOption = {
          middle: { anchor: '__container__', align: HorizontalAlign.Center },
          top: { anchor: '__container__', align: VerticalAlign.Top },
        };

        // 登录按钮
        uiConfig.loginBtnText = '本机号码一键登录';
        uiConfig.loginBtnFontColor = '#FFFFFF';
        uiConfig.loginBtnBackGroundColor = '#4F46E5';
        uiConfig.loginBtnDisableBackGroundColor = '#BDBDF6';
        uiConfig.loginBtnHeight = '52vp';
        uiConfig.loginBtnMargin = { left: 24, top: 320, right: 24 };
        uiConfig.loginBtnAlignRuleOption = {
          middle: { anchor: '__container__', align: HorizontalAlign.Center },
          top: { anchor: '__container__', align: VerticalAlign.Top },
        };

        // 协议区域上移，避免底部被裁
        uiConfig.privacyFontColor = '#333333';
        uiConfig.privacyFontSize = 16;
        uiConfig.privacyMargin = { left: 40, right: 40, bottom: 96 };
        uiConfig.privacyAlignRuleOption = {
          bottom: { anchor: '__container__', align: VerticalAlign.Bottom },
        };
        uiConfig.privacyCbMargin = { left: 16, bottom: 96 };
        uiConfig.privacyCbAlignRuleOption = {
          top: { anchor: 'clause_text', align: VerticalAlign.Top },
          left: { anchor: '__container__', align: HorizontalAlign.Start },
        };
        this.authHelper.setAuthConfig(uiConfig);
        
        // 拉起授权页
        this.authHelper.getLoginToken(5000);
      } catch (err) {
        this.clearTimeoutTimer();
        console.error('[OneClickAuthService] getLoginToken exception:', err);
        // 区分密钥为空 vs SDK 异常
        const errMsg = (err instanceof Error) ? err.message : '';
        if (errMsg.startsWith(OneClickError.CONFIG_MISMATCH)) {
          reject(err as Error);
        } else {
          reject(new Error(`${OneClickError.SDK_NOT_AVAILABLE}:EXCEPTION`));
        }
        this.cleanup();
      }
    });
  }

  /**
   * 将 SDK 错误码归类为 OneClickError 枚举
   */
  private classifyErrorCode(code: string): OneClickError {
    switch (code) {
      case '700000': return OneClickError.USER_CANCELLED;
      case '600004':
      case '600010':
      case '600011': return OneClickError.CARRIER_ERROR;
      case '600016':  // 配置项无效
      case '600017':  // 密钥/方案不匹配
      case '600020':  // 方案不存在
      case '600021': return OneClickError.CONFIG_MISMATCH;  // 方案状态异常
      case '600005':
      case '600007':
      case '600008':
      case '600013':
      case '600014':
      case '600015':
      case '600028': return OneClickError.NETWORK_ERROR;
      case '600024':
      case '600025': return OneClickError.SDK_NOT_AVAILABLE;
      default: return OneClickError.UNKNOWN;
    }
  }

  private cleanup() {
    this.clearTimeoutTimer();
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

  private clearTimeoutTimer() {
    if (this.timeoutTimer !== -1) {
      clearTimeout(this.timeoutTimer);
      this.timeoutTimer = -1;
    }
  }



}

export default OneClickAuthService;
