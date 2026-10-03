"""Execute the actual PreferencesService with an in-memory Harmony Preferences adapter.

Run: python3 -B tools/tests/test_course_progress.py
No device, application data, or provider calls are used.
"""
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
NODE = '/Applications/DevEco-Studio.app/Contents/tools/node/bin/node'
TYPESCRIPT = '/Applications/DevEco-Studio.app/Contents/tools/arktsdoc/node_modules/typescript/lib/typescript.js'


class CourseProgressTest(unittest.TestCase):
    def test_real_service_persistence_and_backup_contract(self):
        script = r"""
const fs = require('fs');
const vm = require('vm');
const path = require('path');
const assert = require('assert/strict');
const ts = require(process.argv[1]);
const root = process.argv[2];
const values = new Map();
const storage = { get: async (key, fallback) => values.has(key) ? values.get(key) : fallback,
  put: async (key, value) => values.set(key, value), flush: async () => {} };
const modules = new Map();
function load(file) {
  if (modules.has(file)) return modules.get(file).exports;
  const source = fs.readFileSync(file, 'utf8');
  const compiled = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2021, module: ts.ModuleKind.CommonJS } }).outputText;
  const module = { exports: {} }; modules.set(file, module);
  const localRequire = (name) => {
    if (name === '@ohos.data.preferences') return { default: { getPreferences: async () => storage } };
    if (name.endsWith('/Constants')) return { STORAGE_KEYS: { LEARNING_STATE: 'state', USER_SETTINGS: 'settings' } };
    return load(path.resolve(path.dirname(file), name + '.ets'));
  };
  vm.runInNewContext('(function(require,module,exports){' + compiled + '\n})', { console, Date, Map, Number, Array, Math, JSON })(localRequire, module, module.exports);
  return module.exports;
}
const file = path.join(root, 'entry/src/main/ets/services/PreferencesService.ets');
const model = load(file);
(async () => {
  let service = model.default.getInstance(); await service.init({});
  // A real older backup has only one current course. It must retain its exact cursor.
  values.set('state', JSON.stringify({ currentLevel: 2, currentLesson: 7, lastOpenTime: 100 }));
  let state = await service.getLearningState();
  assert.equal(model.courseLesson(state, 2), 7);
  assert.equal(model.courseLesson(state, 1), 1);
  assert.equal(model.courseLesson(state, 0), 1);
  await service.selectCourse(0);
  assert.equal((await service.getLearningState()).currentLesson, 1);
  await service.updateCurrentProgress(0, 2);
  await service.selectCourse(1);
  await service.updateCurrentProgress(1, 3);
  await service.selectCourse(2);
  state = await service.getLearningState();
  assert.equal(state.currentLesson, 7);
  assert.equal(model.courseLesson(state, 0), 2);
  assert.equal(model.courseLesson(state, 1), 3);
  // Replaying an earlier lesson must never move a course cursor backwards.
  await service.updateCurrentProgress(2, 2);
  assert.equal((await service.getLearningState()).currentLesson, 7);
  // Concurrent page activity must serialize entire read-modify-write transactions.
  await Promise.all([service.updateCurrentProgress(0, 5), service.selectCourse(1), service.updateLastOpenTime(), service.updateCurrentProgress(1, 6)]);
  state = await service.getLearningState();
  assert.equal(model.courseLesson(state, 0), 5);
  assert.equal(model.courseLesson(state, 1), 6);
  assert.equal(model.courseLesson(state, 2), 7);
  const recovered = model.normalizeCourseState({currentLevel:2,currentLesson:7,courses:[null,{level:0,lesson:5},{level:0,lesson:3},{level:-1,lesson:9},{level:1,lesson:6},{}]});
  assert.equal(model.courseLesson(recovered, 0), 5);
  assert.equal(model.courseLesson(recovered, 1), 6);
  assert.equal(model.courseLesson(recovered, 2), 7);
  // A fresh module instance simulates restarting the app against persisted bytes.
  modules.clear();
  const restarted = load(file); service = restarted.default.getInstance(); await service.init({});
  state = await service.getLearningState();
  assert.deepEqual(JSON.parse(JSON.stringify(state.courses)), [{level:2,lesson:7},{level:0,lesson:5},{level:1,lesson:6}]);
  const backup = await service.exportData();
  values.clear();
  assert.equal(await service.importData(backup), true);
  state = await service.getLearningState();
  assert.equal(restarted.courseLesson(state, 2), 7);
  assert.equal(restarted.courseLesson(state, 1), 6);
  assert.equal(restarted.courseLesson(state, 0), 5);
  // Import of the original v1 format deliberately replaces progress, as it did before.
  assert.equal(await service.importData(JSON.stringify({version:1,state:{currentLevel:1,currentLesson:4,lastOpenTime:0}})), true);
  state = await service.getLearningState();
  assert.equal(restarted.courseLesson(state, 1), 4);
  assert.equal(restarted.courseLesson(state, 2), 1);
  const before = await service.exportData();
  assert.equal(await service.importData(JSON.stringify({version:99,state:{currentLevel:0,currentLesson:90}})), false);
  assert.equal(JSON.parse(await service.exportData()).state.currentLesson, JSON.parse(before).state.currentLesson);
  assert.equal(values.size, 2); // only existing learning state and settings keys; no quota key writes.
  console.log('PASS: legacy cursor, independent progression, switching, replay, restart, full backup, legacy import, invalid backup');
})().catch(error => { console.error(error); process.exitCode = 1; });
"""
        result = subprocess.run([NODE, '-e', script, TYPESCRIPT, str(ROOT)], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS:', result.stdout)
        print(result.stdout.strip())


if __name__ == '__main__':
    unittest.main()
