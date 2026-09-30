import { hvigor } from '@ohos/hvigor';
import { appTasks, OhosAppContext, OhosPluginId } from '@ohos/hvigor-ohos-plugin';
import { readFileSync } from 'fs';
import { join } from 'path';
import { spawnSync } from 'child_process';

// Explicit opt-in keeps ordinary IDE Sync and other products unchanged.
if (process.env.LINGAI_LOCAL_SIGNING === '1') {
  hvigor.afterNodeEvaluate((node) => {
    if (node.getNodePath() !== hvigor.getRootNode().getNodePath()) {
      return;
    }
    const context = node.getContext(OhosPluginId.OHOS_APP_PLUGIN) as OhosAppContext;
    if (!context || context.getCurrentProduct().getProductName() !== 'default' ||
        context.getBuildMode() !== 'debug') {
      throw new Error('LOCAL_SIGNING_DEBUG_ONLY');
    }
    const root = node.getNodePath();
    const validation = spawnSync('python3', [
      join(root, 'tools/configure-signing.py'), 'check', '--project-root', root
    ], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    if (validation.status !== 0) {
      // Do not forward configuration or subprocess diagnostics into build logs.
      throw new Error('LOCAL_SIGNING_INVALID: run tools/configure-signing.py check');
    }
    try {
      const local = JSON.parse(readFileSync(join(root, '.local/signing/default.json'), 'utf8'));
      const profile = context.getBuildProfileOpt();
      const configurations = profile.app.signingConfigs || [];
      const index = configurations.findIndex((item) => item.name === 'default');
      if (index < 0 || configurations.filter((item) => item.name === 'default').length !== 1) {
        throw new Error('LOCAL_SIGNING_DEFAULT_MISSING');
      }
      // Never assign default signing to appstore or change release material.
      profile.app.signingConfigs = configurations.map((item, position) =>
        position === index ? local.signingConfig : item);
      context.setBuildProfileOpt(profile);
    } catch (_) {
      throw new Error('LOCAL_SIGNING_INJECTION_FAILED');
    }
  });
}

export default { system: appTasks, plugins: [] };
