import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

import ApiService from '../services/ApiService';
import OneClickAuthService from '../services/OneClickAuthService';
import { APP_KEY_DEV, APP_PRIVATE_KEY_DEV, PNVS_AUTH_SECRET_DEV } from '../local/Secret.dev';
import { ConsoleInterceptor } from '../utils/ConsoleInterceptor';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 尽早初始化日志拦截器
    ConsoleInterceptor.init();

    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    
    // 初始化一键登录 SDK (不阻断启动)
    try {
      // 启动时注入 App 验签密钥（来自本地忽略文件，不入库）
      if (APP_KEY_DEV && APP_KEY_DEV.trim().length > 0 && APP_PRIVATE_KEY_DEV && APP_PRIVATE_KEY_DEV.trim().length > 0) {
        ApiService.getInstance().overrideSignConfig(APP_KEY_DEV.trim(), APP_PRIVATE_KEY_DEV);
      }

      // 启动时注入真实密钥 (来自本地忽略文件)
      if (PNVS_AUTH_SECRET_DEV && PNVS_AUTH_SECRET_DEV.trim().length > 0) {
        OneClickAuthService.getInstance().overrideSecret(PNVS_AUTH_SECRET_DEV.trim());
        OneClickAuthService.getInstance().init(this.context).catch(() => {
          hilog.error(DOMAIN, 'testTag', '%{public}s', 'OneClickAuthService initialization failed');
        });
      } else {
        // 缺少真实配置时保持 SDK 未初始化，登录由 CONFIG_MISMATCH 明确拒绝。
        hilog.warn(DOMAIN, 'testTag', '%{public}s', 'OneClickAuthService CONFIG_MISMATCH:EMPTY_SECRET');
      }
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'OneClickAuthService init failed: %{public}s', JSON.stringify(err));
    }

    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    // Main window is created, set main page for this ability
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.getMainWindow().then((mainWindow: window.Window) => {
      mainWindow.setWindowLayoutFullScreen(true).then(() => {
        hilog.info(DOMAIN, 'testTag', '%{public}s', 'Succeeded in setting full screen layout.');
      }).catch((error: BusinessError) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to set full screen layout. Cause: %{public}s', JSON.stringify(error));
      });
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, 'testTag', 'Failed to get main window. Cause: %{public}s', JSON.stringify(error));
    });

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    // Main window is destroyed, release UI related resources
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    // Ability has brought to foreground
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    // Ability has back to background
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
