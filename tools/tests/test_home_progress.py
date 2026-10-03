"""Race tests execute HomeContent's actual method with delayed read-only API replies."""
import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
NODE = '/Applications/DevEco-Studio.app/Contents/tools/node/bin/node'
TYPESCRIPT = '/Applications/DevEco-Studio.app/Contents/tools/arktsdoc/node_modules/typescript/lib/typescript.js'


class HomeProgressTest(unittest.TestCase):
    def test_latest_snapshot_wins(self):
        script = r"""
const fs = require('fs'), vm = require('vm'), assert = require('assert/strict');
const ts = require(process.argv[1]);
const source = fs.readFileSync(process.argv[2], 'utf8');
const start = source.indexOf('  private async loadLearningProgress(context: Context) {');
const end = source.indexOf('\n  aboutToDisappear()', start);
assert(start > 0 && end > start);
let settings = 20;
let state = {currentLevel:1,currentLesson:79};
const pending = [];
const api = { init:async()=>{}, getToken:()=> 'local-test', getLevelInfo:()=>new Promise((resolve,reject)=>pending.push({resolve,reject})) };
const metadata = {levels:[{level:1,word_count:1559,lesson_count:78},{level:2,word_count:3764,lesson_count:189}]};
const harness = 'class HomeHarness { learningSnapshotRequest=0; lessonInfoReady=false; currentLevel=1; currentLessonId=1; courseComplete=false; newWordsCount=0; lessonTitle=""; ' + source.slice(start,end) + '} exports.HomeHarness=HomeHarness;';
const compiled = ts.transpileModule(harness,{compilerOptions:{target:ts.ScriptTarget.ES2021}}).outputText;
const exports = {};
vm.runInNewContext(compiled, {exports,console,Math,WORDS_PER_LESSON:20,
  PreferencesService:{getInstance:()=>({init:async()=>{},getLearningState:async()=>({...state})})},
  ApiService:{getInstance:()=>api}, preferences:{getPreferences:async()=>({get:async()=>settings})}});
async function waitFor(count) { for(let i=0; i<30 && pending.length<count; i++) await new Promise(setImmediate); assert.equal(pending.length,count); }
(async()=>{
 const home = new exports.HomeHarness();
 const first = home.loadLearningProgress({}); await waitFor(1);
 const second = home.loadLearningProgress({}); await waitFor(2);
 pending[1].resolve(metadata); await second;
 assert.equal(home.courseComplete,true); assert.equal(home.currentLessonId,78); assert.equal(home.newWordsCount,19);
 pending[0].resolve(metadata); await first;
 assert.equal(home.courseComplete,true); assert.equal(home.currentLessonId,78);
 // A delayed 20-word snapshot must not overwrite the newer 100-word course layout.
 const oldSettings = home.loadLearningProgress({}); await waitFor(3);
 settings=100;
 const newSettings = home.loadLearningProgress({}); await waitFor(4);
 pending[3].resolve(metadata); await newSettings;
 pending[2].resolve(metadata); await oldSettings;
 assert.equal(home.currentLessonId,16); assert.equal(home.newWordsCount,59); assert.equal(home.courseComplete,true);
 // Course selection and its cursor travel together; an older course cannot replace them.
 const oldCourse = home.loadLearningProgress({}); await waitFor(5);
 state={currentLevel:2,currentLesson:2}; settings=10;
 const newCourse = home.loadLearningProgress({}); await waitFor(6);
 pending[5].resolve(metadata); await newCourse; pending[4].resolve(metadata); await oldCourse;
 assert.equal(home.currentLevel,2); assert.equal(home.currentLessonId,2); assert.equal(home.newWordsCount,10); assert.equal(home.courseComplete,false);
 // Failure disables navigation; an explicit retry restores the same real course.
 const failed = home.loadLearningProgress({}); await waitFor(7); pending[6].reject(new Error('offline')); await failed;
 assert.equal(home.lessonInfoReady,false);
 const retry = home.loadLearningProgress({}); await waitFor(8); pending[7].resolve(metadata); await retry;
 assert.equal(home.lessonInfoReady,true); assert.equal(home.currentLevel,2);
 console.log('PASS: concurrent completion, settings race, course race, offline retry');
})().catch(error=>{console.error(error);process.exitCode=1;});
"""
        result = subprocess.run([NODE, '-e', script, TYPESCRIPT,
                                 str(ROOT / 'entry/src/main/ets/components/HomeContent.ets')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        print(result.stdout.strip())

    def test_cold_start_account_and_quota_states(self):
        script = r"""
const fs=require('fs'),vm=require('vm'),assert=require('assert/strict'),ts=require(process.argv[1]);
const source=fs.readFileSync(process.argv[2],'utf8');
function section(start,end) { const a=source.indexOf(start),b=source.indexOf(end,a); assert(a>0&&b>a); return source.slice(a,b); }
const account=section('  private async loadUserInfo(context: Context) {','  /**\n   * 从本地偏好');
const label=section('  private learningActionLabel(): string {','  async startLearning()');
const quota=section('  private lessonQuotaHint(): string {','  private async goLoginTab');
let token='',releaseInit;
let initPromise=new Promise(resolve=>releaseInit=resolve);
const accountReplies=[];
const api={init:()=>initPromise,getToken:()=>token,getCurrentUserInfo:()=>new Promise((resolve,reject)=>accountReplies.push({resolve,reject}))};
const exports={};
const code='class HomeHarness { authReady=false;isLoggedIn=false;quotaReady=false;quotaLoadFailed=false;userName="";userInfo={dailyLessonLimit:0};lessonInfoReady=true;courseComplete=false;currentLessonId=1;todayProgress=0;resolveFriendlyUserName(){return "test";}'+account+label+quota+'} exports.HomeHarness=HomeHarness;';
vm.runInNewContext(ts.transpileModule(code,{compilerOptions:{target:ts.ScriptTarget.ES2021}}).outputText,{exports,console,ApiService:{getInstance:()=>api},UserInfo:class{},COLORS:{PRIMARY:'green',TEXT_SECONDARY:'muted'},UI:{DANGER_TEXT:'red',DANGER_SOFT:'redSoft',GREEN_SOFT:'greenSoft',SURFACE_MUTED:'mutedSoft'}});
async function tick(){await new Promise(setImmediate);}
(async()=>{
 const home=new exports.HomeHarness();
 const cold=home.loadUserInfo({});
 assert.equal(home.learningActionLabel(),'正在加载账号');
 assert.equal(home.lessonQuotaHint(),'正在加载账号信息');
 token='saved-local-token'; releaseInit(); await tick();
 assert.equal(home.isLoggedIn,true); assert.equal(home.authReady,true);
 assert.equal(home.learningActionLabel(),'开始学习');
 assert.equal(home.lessonQuotaHint(),'正在加载今日学习额度');
 accountReplies[0].resolve({nickname:'test',phone:'',dailyLessonLimit:2,dailyLessonRemaining:0,dailyLessonUsed:2}); await cold;
 assert.equal(home.lessonQuotaHint(),'今日额度已用完 · 已使用 2/2 关额度');
 assert.equal(home.lessonQuotaTextColor(),'red');
 const offline=home.loadUserInfo({}); await tick(); accountReplies[1].reject(new Error('offline')); await offline;
 assert.equal(home.isLoggedIn,true); assert.equal(home.quotaReady,false);
 assert.equal(home.lessonQuotaHint(),'学习额度暂时无法读取，请稍后重试。');
 assert.equal(home.lessonQuotaTextColor(),'muted');
 const restored=home.loadUserInfo({}); await tick(); accountReplies[2].resolve({nickname:'test',phone:'',dailyLessonLimit:0,dailyLessonRemaining:0,dailyLessonUsed:0}); await restored;
 assert.equal(home.lessonQuotaHint(),'当前会员今日学习不限量');
 token=''; await home.loadUserInfo({});
 assert.equal(home.isLoggedIn,false); assert.equal(home.learningActionLabel(),'登录后开始学习');
 console.log('PASS: saved-token cold start, quota loading, real used quota, offline unknown, real unlimited, guest');
})().catch(error=>{console.error(error);process.exitCode=1;});
"""
        result = subprocess.run([NODE, '-e', script, TYPESCRIPT,
                                 str(ROOT / 'entry/src/main/ets/components/HomeContent.ets')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        print(result.stdout.strip())


if __name__ == '__main__':
    unittest.main()
