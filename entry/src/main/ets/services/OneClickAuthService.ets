/**
 * 一键登录服务（阿里云 PNVS SDK 适配层）
 * 封装 SDK 初始化、预取号、拉起授权页等操作
 */
import common from '@ohos.app.ability.common';
import { PNVS_AUTH_SECRET } from '../utils/Constants';
import PhoneNumberAuthHelper, { TokenResultListener, AuthUiConfig, PageOrientation, AuthUIControlClickListener } from 'numberauth_standard';

export enum OneClickError {
  USER_CANCELLED = 'USER_CANCELLED',          // 用户取消授权
  AUTH_PAGE_CLOSED = 'AUTH_PAGE_CLOSED',      // 授权页被关闭
  NETWORK_ERROR = 'NETWORK_ERROR',            // 网络问题
  CARRIER_ERROR = 'CARRIER_ERROR',            // 运营商校验失败
  CONFIG_MISMATCH = 'CONFIG_MISMATCH',        // SDK 密钥/方案配置错误（600017 等）
  NO_SIM = 'NO_SIM',                          // 无 SIM / 飞行模式
  SDK_NOT_AVAILABLE = 'SDK_NOT_AVAILABLE',    // SDK 不可用
  TIMEOUT = 'TIMEOUT',                        // 请求超时
  RATE_LIMIT = 'RATE_LIMIT',                  // 请求过于频繁 (Throttling.User)
  SUPERSEDED = 'SUPERSEDED',                  // 被新的请求顶替
  UNKNOWN = 'UNKNOWN',                        // 未知错误
}

// 事件映射与状态机：
// | SDK Code / Event | User Action | Semantic | State Transition | Promise Action |
// | 700000 / .authpage.return | Click back on Auth Page | AUTH_PAGE_CLOSED | AUTH_PAGE -> FAILED | reject(AUTH_PAGE_CLOSED) |
// | .dialog.cancel / 700004 | Click Cancel on Protocol Dialog | PROTOCOL_CANCELLED | PROTOCOL_DIALOG -> AUTH_PAGE | Do nothing to Promise |
// | 600000 | Token fetch success | SUCCESS | * -> SUCCESS | resolve(token) |
// | 600001 | Auth page presented | N/A | IDLE -> AUTH_PAGE | None |
// | .dialog.agree / 600006 | Click Agree / Start Fetch | SUBMITTING | PROTOCOL_DIALOG/AUTH_PAGE -> SUBMITTING | Do nothing to Promise |
// | UI Click Events | Pure UI interactions | N/A | No changes | Do nothing to Promise |
// | Unrecognized / Default | Terminal Error | FAILED | * -> FAILED | reject(Error) |

export enum AuthState {
  IDLE = 'IDLE',
  AUTH_PAGE = 'AUTH_PAGE',
  PROTOCOL_DIALOG = 'PROTOCOL_DIALOG',
  SUBMITTING = 'SUBMITTING',
  SUCCESS = 'SUCCESS',
  FAILED = 'FAILED'
}

export class OneClickAuthService {
  private static instance: OneClickAuthService;
  private initialized: boolean = false;
  private authHelper: PhoneNumberAuthHelper | undefined;
  
  // 状态机与并发控制
  private currentState: AuthState = AuthState.IDLE;
  private requestCounter: number = 0;
  private currentAttemptId: number = -1;
  private authPageVisibility: boolean = false;

  // 当前请求的 Promise Resolver
  private tokenResolve: ((value: string) => void) | undefined;
  private tokenReject: ((reason?: Error) => void) | undefined;
  private timeoutTimer: number = -1;
  // 运行时密钥覆盖（优先于 Constants 中的占位值）
  private secretOverride: string = '';

  private constructor() {}

  /**
   * 是否正处于授权页展示状态
   */
  public isAuthPageVisible(): boolean {
    return this.authPageVisibility || this.currentState === AuthState.PROTOCOL_DIALOG;
  }

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
   * 统一结束单次一键登录流程
   */
  private finalizeAttempt(attemptId: number, isSuccess: boolean, result: string | Error) {
    if (this.currentAttemptId !== attemptId) {
      console.warn(`[OneClickAuthService] finalizeAttempt dropped: target=${attemptId}, current=${this.currentAttemptId}`);
      return;
    }

    this.clearSubmittingTimeoutTimer();
    const finalState = isSuccess ? AuthState.SUCCESS : AuthState.FAILED;
    this.currentState = finalState;

    if (isSuccess && this.tokenResolve) {
      const token = result as string;
      console.info(`[OneClick] attemptId=${attemptId} state=${finalState} semantic=TOKEN_FETCH_SUCCESS code=600000 traceId=N/A`);
      // 仅成功时且授权页仍可见时关闭，防竞态
      if (this.authPageVisibility) {
        try {
          this.authHelper?.quitLoginPage();
        } catch (e) {
          console.error(`[OneClickAuthService] quitLoginPage error: ${e}`);
        }
      }
      this.authPageVisibility = false;
      this.tokenResolve(token);
    } else if (!isSuccess && this.tokenReject) {
      const err = result as Error;
      let rawCode = 'UNKNOWN';
      try {
        const parts = err.message.split(':');
        if (parts.length > 1) rawCode = parts[1];
      } catch (e) {}
      console.error(`[OneClick] attemptId=${attemptId} state=${finalState} semantic=${err.message.split(':')[0]} code=${rawCode} traceId=N/A`);
      
      this.authPageVisibility = false; // 错误流由 SDK 控制关闭，或用户主动关闭
      this.tokenReject(err);
    }

    // 清理状态
    this.currentAttemptId = -1;
    this.tokenResolve = undefined;
    this.tokenReject = undefined;
    
    try {
      this.authHelper?.setAuthListener({
        onSuccess: (_msg: string) => {},
        onFailure: (_ret: string) => {}
      });
    } catch (e) {
      console.warn('[OneClickAuthService] Cleanup error:', e);
    }
  }

  /**
   * 拉起授权页并获取 Token
   */
  async requestToken(context: common.UIAbilityContext): Promise<string> {
    if (!this.initialized) await this.init(context);
    
    if (!this.authHelper) {
      throw new Error(OneClickError.SDK_NOT_AVAILABLE);
    }

    // 并发顶替：如果有未决定的请求，直接终结为 SUPERSEDED
    if (this.currentAttemptId !== -1) {
      console.warn(`[OneClickAuthService] concurrent call detected. Superseding attemptId=${this.currentAttemptId}`);
      this.finalizeAttempt(this.currentAttemptId, false, new Error(`${OneClickError.SUPERSEDED}:CONCURRENT_CALL`));
    }

    this.currentState = AuthState.IDLE;
    const thisAttemptId = ++this.requestCounter;
    this.currentAttemptId = thisAttemptId;

    // 监听 UI 点击事件
    const uiClickListener: AuthUIControlClickListener = {
      onClick: (code: string, jsonString: string) => {
        console.info(`[OneClickAuthService] UI Click: code=${code}`);
        if (code === '700000' || code === '.authpage.return' || code === 'sdk.quit.auth') {
           // 会在 onFailure 里抛错，这里只做预标记（如有需要）
        } else if (code === '700004' || code === '700007' || code === '700009' || code === '.dialog.cancel') {
           this.currentState = AuthState.AUTH_PAGE;
           this.clearSubmittingTimeoutTimer();
           console.info(`[OneClickAuthService] Protocol cancel. state returned to AUTH_PAGE`);
        } else if (code === '700006' || code === '.dialog.open') {
           this.currentState = AuthState.PROTOCOL_DIALOG;
        } else if (code === '.dialog.agree') {
           this.currentState = AuthState.SUBMITTING;
           this.startSubmittingTimeoutTimer(thisAttemptId);
        }
      }
    };
    this.authHelper.setUIClickListener(uiClickListener);

    return new Promise((resolve, reject) => {
      this.tokenResolve = resolve;
      this.tokenReject = reject;
      
      const listener: TokenResultListener = {
        onSuccess: (msg: string) => {
          if (this.currentAttemptId !== thisAttemptId) return;

          try {
             const res = JSON.parse(msg) as Record<string, Object>;
             const code = (res['_code'] || res['code']) as string;
             const token = (res['_token'] || res['token']) as string;
             
             if (code === '600000' && token) {
                this.finalizeAttempt(thisAttemptId, true, token);
             } else if (code === '600001') {
                this.authPageVisibility = true;
                this.currentState = AuthState.AUTH_PAGE;
             } else if (code === '600006') {
                this.currentState = AuthState.SUBMITTING;
                this.startSubmittingTimeoutTimer(thisAttemptId);
             } else {
                // Ignore unexpected codes instead of failing early, or map carefully
             }
          } catch (e) {
             console.error('[OneClickAuthService] Parse success msg failed');
             this.finalizeAttempt(thisAttemptId, false, new Error(`${OneClickError.UNKNOWN}:PARSE_ERROR`));
          }
        },
        onFailure: (ret: string) => {
          if (this.currentAttemptId !== thisAttemptId) return;
          
          let errorType = OneClickError.UNKNOWN;
          let rawCode = 'UNKNOWN';
          
          try {
             const res = JSON.parse(ret) as Record<string, Object>;
             rawCode = (res['_code'] || res['code'] || 'UNKNOWN') as string;
             
             console.warn(`[OneClickAuthService] onFailure code=${rawCode} state=${this.currentState}`);
             
             // 过滤纯 UI 事件与非终态取消
             if (rawCode === '700004' || rawCode === '700007' || rawCode === '700009' || rawCode === '.dialog.cancel') {
                this.currentState = AuthState.AUTH_PAGE;
                this.clearSubmittingTimeoutTimer();
                return; // 不决议 promise
             }
             if (rawCode.startsWith('70000') && rawCode !== '700000') {
                return; // 忽略其它 UI click 事件 (如 700002 切换登录方式埋点等，避免阻断)
             }
             
             const rawMsg = (res['_msg'] || res['msg'] || res['message'] || '') as string;
             if (rawCode === 'Throttling.User' || rawMsg.toLowerCase().includes('flow control')) {
               errorType = OneClickError.RATE_LIMIT;
             } else {
               errorType = this.classifyErrorCode(rawCode);
             }
          } catch (e) {
             console.error('[OneClickAuthService] Parse failure msg failed');
          }

          this.finalizeAttempt(thisAttemptId, false, new Error(`${errorType}:${rawCode}`));
        }
      };
      // 移除原有的全局超时保护，此超时已平移到 SUBMITTING 阶段
      
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
        if (this.currentAttemptId === thisAttemptId) {
          const errMsg = (err instanceof Error) ? err.message : '';
          const isConfigMismatch = errMsg.startsWith(OneClickError.CONFIG_MISMATCH);
          const errorToThrow = isConfigMismatch 
            ? (err as Error) 
            : new Error(`${OneClickError.SDK_NOT_AVAILABLE}:EXCEPTION`);
            
          this.finalizeAttempt(thisAttemptId, false, errorToThrow);
        }
      }
    });
  }

  private classifyErrorCode(code: string): OneClickError {
    switch (code) {
      case '700000': 
      case '.authpage.return':
        return OneClickError.AUTH_PAGE_CLOSED;
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

  private clearSubmittingTimeoutTimer() {
    if (this.timeoutTimer !== -1) {
      clearTimeout(this.timeoutTimer);
      this.timeoutTimer = -1;
    }
  }

  private startSubmittingTimeoutTimer(attemptId: number) {
    this.clearSubmittingTimeoutTimer();
    this.timeoutTimer = setTimeout(() => {
      // 严格门禁：必须仍在 SUBMITTING 态且为同一 attempt
      if (this.currentAttemptId === attemptId && this.currentState === AuthState.SUBMITTING) {
          console.warn(`[OneClickAuthService] submitting timeout attemptId=${attemptId}`);
          this.finalizeAttempt(attemptId, false, new Error(`${OneClickError.TIMEOUT}:5000`));
      }
    }, 5000);
  }



}

export default OneClickAuthService;
