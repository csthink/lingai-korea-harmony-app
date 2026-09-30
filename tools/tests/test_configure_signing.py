"""Synthetic policy tests. No real signing configuration, password or private key is read."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('configure_signing', ROOT / 'tools/configure-signing.py')
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class SigningTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='synthetic-signing-', dir=ROOT / '.local/signing')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for relative in ('AppScope', '.local', '.local/signing', 'materials'):
            (self.root / relative).mkdir(mode=0o700)
        self.pem = b'-----BEGIN CERTIFICATE-----\nSYNTHETIC-CERTIFICATE\n-----END CERTIFICATE-----'
        self.fingerprint = signing.digest(self.pem)
        self.profile = {'type': 'debug', 'bundle-info': {
            'bundle-name': signing.BUNDLE, 'app-identifier': signing.APP_IDENTIFIER,
            'development-certificate': self.pem.decode()},
            'validity': {'not-before': time.time() - 60, 'not-after': time.time() + 3600}}
        self.write('AppScope/app.json5', json.dumps({'app': {'bundleName': signing.BUNDLE}}).encode())
        self.write('materials/fake.p12', b'SYNTHETIC-KEYSTORE-NOT-A-PRIVATE-KEY')
        self.write('materials/fake.cer', self.pem)
        self.save_profile()
        self.default = {'name': 'default', 'type': 'HarmonyOS', 'material': {
            'storeFile': 'materials/fake.p12', 'certpath': 'materials/fake.cer',
            'profile': 'materials/fake.p7b', 'keyAlias': 'synthetic',
            'storePassword': 'SYNTHETIC_STORE_PASSWORD_' * 3,
            'keyPassword': 'SYNTHETIC_KEY_PASSWORD_' * 3, 'signAlg': 'SHA256withECDSA'}}
        self.release = {'name': 'release', 'type': 'HarmonyOS',
                        'material': {'storePassword': 'SYNTHETIC_LEGACY_ONLY', 'keyPassword': 'SYNTHETIC_LEGACY_ONLY'}}
        self.document = {'app': {'signingConfigs': [self.default, self.release], 'products': [
            {'name': 'default', 'signingConfig': 'default'},
            {'name': 'appstore', 'signingConfig': 'release'}]}, 'modules': [{'name': 'entry'}]}
        self.save_source()
        # Stub only the external crypto boundary. Identity, expiry, hashes, IO and migrations run normally.
        for name, replacement in [('openssl', lambda *args, data=None: data),
                                  ('certificate_der', lambda pem: pem),
                                  ('certificate_valid', lambda pem: None),
                                  ('git_ignored', lambda root, path: True)]:
            helper = patch.object(signing, name, replacement)
            helper.start()
            self.addCleanup(helper.stop)

    def write(self, relative, content):
        path = self.root / relative
        path.write_bytes(content)
        path.chmod(0o600)

    def save_profile(self):
        self.write('materials/fake.p7b', json.dumps(self.profile).encode())

    def save_source(self):
        # Exercise JSON5 comments, unquoted keys, escaped braces and unrelated formatting.
        text = json.dumps(self.document, indent=3).replace('"app":', 'app:', 1)
        self.write('build-profile.json5', ('// SYNTHETIC ONLY\n' + text + '\n').encode())

    def migrate(self):
        return signing.migrate(self.root, self.fingerprint)

    def check(self):
        return signing.check(self.root, self.fingerprint)

    def reject_without_changes(self, code):
        before = (self.root / 'build-profile.json5').read_bytes()
        with self.assertRaisesRegex(signing.SigningError, code):
            self.migrate()
        self.assertEqual(before, (self.root / 'build-profile.json5').read_bytes())
        self.assertFalse((self.root / '.local/signing/default.json').exists())

    def test_migration_preserves_other_bytes_and_bindings(self):
        before = (self.root / 'build-profile.json5').read_text()
        start, end = signing.object_spans(before)[('app', 'signingConfigs', 0)]
        self.assertEqual('default_migrated', self.migrate()['status'])
        after = (self.root / 'build-profile.json5').read_text()
        new_start, new_end = signing.object_spans(after)[('app', 'signingConfigs', 0)]
        self.assertEqual(before[:start], after[:new_start])
        self.assertEqual(before[end:], after[new_end:])
        self.assertNotIn(self.default['material']['storePassword'], after)
        self.assertNotIn(self.default['material']['keyPassword'], after)
        result = self.check()
        self.assertTrue(result['other_signing_password_fields_remain'])
        local = self.root / '.local/signing/default.json'
        self.assertEqual(0o600, stat.S_IMODE(local.stat().st_mode))
        self.assertEqual(0o600, stat.S_IMODE((self.root / 'build-profile.json5').stat().st_mode))
        self.assertEqual(self.default, json.loads(local.read_text())['signingConfig'])

    def test_wrong_app_identity_and_bundle_are_rejected(self):
        for field, value in [('app-identifier', '9999999999999999999'), ('bundle-name', 'example.invalid')]:
            original = self.profile['bundle-info'][field]
            self.profile['bundle-info'][field] = value
            self.save_profile()
            self.reject_without_changes('PROFILE_IDENTITY_MISMATCH')
            self.profile['bundle-info'][field] = original

    def test_expired_and_release_profiles_are_rejected(self):
        self.profile['validity']['not-after'] = time.time() - 1
        self.save_profile()
        self.reject_without_changes('PROFILE_EXPIRED_OR_NOT_YET_VALID')
        self.profile['type'] = 'release'
        self.save_profile()
        self.reject_without_changes('PROFILE_IDENTITY_MISMATCH')

    def test_unapproved_or_mismatched_certificate_rejected(self):
        self.profile['bundle-info']['development-certificate'] = self.pem.decode().replace('SYNTHETIC', 'OTHER')
        self.save_profile()
        self.reject_without_changes('APPROVED_CERTIFICATE_MISMATCH')
        self.profile['bundle-info']['development-certificate'] = self.pem.decode()
        self.save_profile()
        self.write('materials/fake.cer', self.pem.replace(b'SYNTHETIC', b'OTHER'))
        self.reject_without_changes('PROFILE_CERTIFICATE_MISMATCH')

    def test_plain_short_password_config_rejected(self):
        self.default['material']['storePassword'] = 'SYNTHETIC'
        self.save_source()
        self.reject_without_changes('IDE_ENCRYPTED_PASSWORD_CONFIGURATION_REQUIRED')

    def test_changed_keystore_fails_check(self):
        self.migrate()
        self.write('materials/fake.p12', b'CHANGED-SYNTHETIC-KEYSTORE')
        with self.assertRaisesRegex(signing.SigningError, 'LOCAL_SIGNING_MATERIAL_CHANGED'):
            self.check()

    def test_private_permissions_and_symlink_rejected(self):
        self.migrate()
        local = self.root / '.local/signing/default.json'
        local.chmod(0o644)
        with self.assertRaisesRegex(signing.SigningError, 'PRIVATE_FILE_MODE_MUST_BE_0600'):
            self.check()
        local.chmod(0o600)
        moved = local.with_name('synthetic-preserved.json')
        local.rename(moved)
        local.symlink_to(moved)
        with self.assertRaisesRegex(signing.SigningError, 'MATERIAL_REGULAR_FILE_REQUIRED'):
            self.check()

    def test_existing_local_config_not_overwritten(self):
        target = self.root / '.local/signing/default.json'
        self.write('.local/signing/default.json', b'SYNTHETIC-PRESERVED')
        before = (self.root / 'build-profile.json5').read_bytes()
        with self.assertRaisesRegex(signing.SigningError, 'LOCAL_CONFIG_EXISTS_NOT_OVERWRITTEN'):
            self.migrate()
        self.assertEqual(b'SYNTHETIC-PRESERVED', target.read_bytes())
        self.assertEqual(before, (self.root / 'build-profile.json5').read_bytes())

    def test_appstore_cannot_use_default(self):
        self.document['app']['products'][1]['signingConfig'] = 'default'
        self.save_source()
        self.reject_without_changes('DEBUG_SIGNATURE_BOUND_TO_OTHER_PRODUCT')

    def test_source_change_aborts_replacement(self):
        original_read = signing.regular_file
        def concurrent_change(path, private=False):
            data = original_read(path, private)
            if path.name == 'default.json':
                with (self.root / 'build-profile.json5').open('a') as stream:
                    stream.write('\n// SYNTHETIC concurrent edit\n')
            return data
        with patch.object(signing, 'regular_file', concurrent_change):
            with self.assertRaisesRegex(signing.SigningError, 'SOURCE_CHANGED_PRIVATE_COPY_PRESERVED'):
                self.migrate()
        self.assertIn('concurrent edit', (self.root / 'build-profile.json5').read_text())
        self.assertTrue((self.root / '.local/signing/default.json').is_file())

    def test_hvigor_opt_in_and_product_guard(self):
        script = r'''
const fs=require('fs'),vm=require('vm'),assert=require('assert');
const ts=require('/Applications/DevEco-Studio.app/Contents/tools/hvigor/hvigor/node_modules/typescript');
const source=fs.readFileSync(process.argv[1],'utf8');
const code=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2020}}).outputText;
function run(flag,product='default',mode='debug',status=0){
 const hooks=[];const release={name:'release',material:{marker:'SYNTHETIC-UNCHANGED'}};
 let profile={app:{signingConfigs:[{name:'default',material:{}},release]}};let updates=0;
 const context={getCurrentProduct:()=>({getProductName:()=>product}),getBuildMode:()=>mode,
  getBuildProfileOpt:()=>profile,setBuildProfileOpt:p=>{profile=p;updates++;}};
 const node={getNodePath:()=>'/synthetic',getContext:()=>context};
 const injected={name:'default',material:{marker:'SYNTHETIC-LOCAL'}};
 const modules={'@ohos/hvigor':{hvigor:{afterNodeEvaluate:f=>hooks.push(f),getRootNode:()=>node}},
  '@ohos/hvigor-ohos-plugin':{appTasks:{},OhosPluginId:{OHOS_APP_PLUGIN:'app'}},
  fs:{readFileSync:()=>JSON.stringify({signingConfig:injected})},path:require('path'),
  child_process:{spawnSync:()=>({status})}};
 vm.runInNewContext(code,{exports:{},process:{env:{LINGAI_LOCAL_SIGNING:flag}},require:n=>modules[n]});
 if(flag!=='1'){assert.equal(hooks.length,0);return;}
 if(product!=='default'||mode!=='debug'){assert.throws(()=>hooks[0](node),/LOCAL_SIGNING_DEBUG_ONLY/);return;}
 if(status!==0){assert.throws(()=>hooks[0](node),/LOCAL_SIGNING_INVALID/);assert.equal(updates,0);return;}
 hooks[0](node);assert.equal(updates,1);assert.equal(profile.app.signingConfigs[1],release);
 assert.equal(profile.app.signingConfigs[0].material.marker,'SYNTHETIC-LOCAL');
}
run(undefined);run('1');run('1','appstore');run('1','default','release');run('1','default','debug',1);
'''
        result = subprocess.run([str(signing.DEVECO / 'tools/node/bin/node'), '-e', script,
                                 str(ROOT / 'hvigorfile.ts')], capture_output=True, text=True)
        self.assertEqual(0, result.returncode, 'Synthetic Hvigor hook validation failed')


if __name__ == '__main__':
    unittest.main()
