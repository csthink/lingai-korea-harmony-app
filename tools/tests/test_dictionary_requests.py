"""Exercise actual DictContent request/cache methods without ArkUI or network access.

This checks request ordering and direction cache boundaries, not native layout,
input methods, server contracts, or provider behavior. Node 24 is used for TypeScript stdin execution.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'entry/src/main/ets/components/DictContent.ets'
METHODS = (
    'invalidateSearch', 'performSearch', 'performSearchWithoutHistory',
    'normalizeQuery', 'saveSearchResultCache', 'tryApplyCachedResult',
    'releaseStream', 'onSearchTextChange', 'performStreamingSearch',
)


def extracted_methods():
    source = SOURCE.read_text()
    methods = []
    for name in METHODS:
        match = re.search(r'^  (?:private |async )*' + name + r'\(', source, re.M)
        if match is None:
            raise AssertionError(f'Cannot locate production method: {name}')
        end = source.index('\n  }', match.start()) + 4
        methods.append(source[match.start():end])
    return '\n'.join(methods)


class DictionaryRequestTests(unittest.TestCase):
    def test_direction_cache_and_out_of_order_responses(self):
        bundled_node = Path.home() / '.nvm/versions/node/v24.14.0/bin/node'
        node = os.environ.get('LINGAI_TEST_NODE') or (
            str(bundled_node) if bundled_node.is_file() else shutil.which('node'))
        self.assertIsNotNone(node, 'Node 24 is required for the extracted ArkTS method test')
        harness = r"""
import assert from 'node:assert/strict';
class DictQueryCacheEntry {}
class ApiError extends Error {}
let toasts = 0;
const promptAction = {showToast() { toasts++; }};
const API_BASE_URL = 'http://test.invalid'; const BIZ_API_PREFIX = '';
const util = {TextDecoder: {create: () => ({decodeToString: bytes => new TextDecoder().decode(bytes)})}};
let rejectSigning = false; let lastStream;
const signingService = {async buildSignedHeaders() { if (rejectSigning) throw new Error('signing unavailable'); return {}; }};
class ApiService { static getInstance() { return signingService; } }
const http = {
  RequestMethod: {GET: 'GET'}, HttpDataType: {STRING: 'string'},
  createHttp() {
    lastStream = {destroyed: false, callbacks: {}, requestCallback: null,
      destroy() { this.destroyed = true; },
      on(name, callback) { this.callbacks[name] = callback; },
      requestInStream(url, options, callback) { this.requestCallback = callback; }
    };
    return lastStream;
  }
};
class Harness {
  searchEpoch = 0; activeHttpRequest = null; isLoading = false; isStreaming = false;
  searchText = ''; searchDirection = 'auto'; requiresLogin = false; searchResultCache = new Map();
  searchResults = []; aiSupplement = null; resultSource = ''; resultDirection = '';
  apiService; vocabularyService = {hasWord: () => false};
  cloneWordEntries(value) { return value; }
  cloneAiSupplement(value) { return value; }
  addToHistory() {} addToBrowseHistory() {} refreshQuotaInfo() {}
  getUIContext() { return {getPromptAction: () => promptAction}; }
""" + extracted_methods() + r"""
}
const h = new Harness();
h.saveSearchResultCache('same', [{hangul: 'KO'}], null, 'local', 'ko2zh', 'ko2zh');
h.saveSearchResultCache('same', [{hangul: 'ZH'}], null, 'local', 'zh2ko', 'zh2ko');
h.searchDirection = 'ko2zh';
assert.equal(h.tryApplyCachedResult('same', false, false), true);
assert.equal(h.searchResults[0].hangul, 'KO');
h.searchDirection = 'zh2ko';
assert.equal(h.tryApplyCachedResult('same', false, false), true);
assert.equal(h.searchResults[0].hangul, 'ZH');

let resolveOld; let calls = 0;
h.apiService = {searchDict: () => {
  calls++; return new Promise(resolve => { resolveOld = resolve; });
}};
h.searchText = 'old'; h.searchDirection = 'ko2zh';
const pending = h.performSearch();
h.searchText = 'same'; h.searchDirection = 'zh2ko';
await h.performSearch();
resolveOld({results: [{hangul: 'STALE'}], aiSupplement: null, source: 'local', direction: 'ko2zh'});
await pending;
assert.equal(h.searchResults[0].hangul, 'ZH', 'late ordinary response cannot overwrite cached next query');
assert.equal(h.isLoading, false);

const obsolete = h.searchEpoch;
h.invalidateSearch();
await h.performSearch('obsolete', 'ko2zh', obsolete);
assert.equal(calls, 1, 'obsolete fallback must not start a request');

let destroyed = false;
h.activeHttpRequest = {destroy() { destroyed = true; }};
h.searchText = 'same'; h.searchDirection = 'ko2zh';
await h.performSearch();
assert.equal(destroyed, true, 'a cache hit must still cancel the previous stream');
assert.equal(h.searchResults[0].hangul, 'KO');

let resolveWithoutHistory;
h.apiService = {searchDict: () => new Promise(resolve => { resolveWithoutHistory = resolve; })};
h.searchText = 'uncached';
const earlier = h.performSearchWithoutHistory();
h.invalidateSearch(); h.searchResults = [{hangul: 'CURRENT'}];
resolveWithoutHistory({results: [{hangul: 'STALE'}], aiSupplement: null, source: 'local', direction: 'auto'});
await earlier;
assert.equal(h.searchResults[0].hangul, 'CURRENT', 'late history response cannot overwrite current view');
h.searchText = 'clear-me';
const toClear = h.performSearch();
h.onSearchTextChange('');
resolveWithoutHistory({results: [{hangul: 'STALE'}], aiSupplement: null, source: 'local', direction: 'auto'});
await toClear;
assert.equal(h.hasSearched, false); assert.deepEqual(h.searchResults, []);

rejectSigning = true; h.searchText = 'signing-failure';
await h.performStreamingSearch();
assert.equal(h.isStreaming, false); assert.equal(h.isLoading, false);
assert.equal(lastStream.destroyed, true); assert.equal(h.activeHttpRequest, null); assert.equal(toasts, 1);
rejectSigning = false; h.searchText = 'stream-complete';
await h.performStreamingSearch();
h.sseGotResult = true; lastStream.callbacks.dataEnd();
assert.equal(lastStream.destroyed, true); assert.equal(h.activeHttpRequest, null);

h.apiService = {searchDict: async () => ({results: [{hangul: 'FALLBACK'}], aiSupplement: null, source: 'local', direction: 'ko2zh'})};
h.searchText = 'stream-error'; await h.performStreamingSearch();
const failedStream = lastStream; failedStream.requestCallback(new Error('network'), 0);
await Promise.resolve(); await Promise.resolve();
assert.equal(failedStream.destroyed, true); assert.equal(h.activeHttpRequest, null);
assert.equal(h.searchResults[0].hangul, 'FALLBACK');
let resolveChunkFallback; let tokenParseCount = 0;
h.apiService = {searchDict: () => new Promise(resolve => { resolveChunkFallback = resolve; })};
h.parseStreamingContent = () => { tokenParseCount++; };
h.searchText = 'error-followed-by-token'; await h.performStreamingSearch();
const eventChunk = 'data: ' + JSON.stringify({type: 'error', message: 'stream failed'}) + '\n\n' +
  'data: ' + JSON.stringify({type: 'token', data: 'OBSOLETE_TOKEN'}) + '\n\n';
lastStream.callbacks.dataReceive(new TextEncoder().encode(eventChunk).buffer);
assert.equal(tokenParseCount, 0, 'tokens after the error in the same chunk must not be parsed');
assert.equal(h.streamingText, '');
resolveChunkFallback({results: [{hangul: 'CHUNK_FALLBACK'}], aiSupplement: null, source: 'local', direction: 'ko2zh'});
await Promise.resolve(); await Promise.resolve();
assert.equal(h.searchResults[0].hangul, 'CHUNK_FALLBACK');
console.log('PASS: directions, stale responses, cancellation, manual clear, signing failure, stream release, error chunk');
"""
        result = subprocess.run(
            [node, '--experimental-strip-types', '--input-type=module-typescript'],
            input=harness, text=True, capture_output=True, timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS:', result.stdout)


if __name__ == '__main__':
    unittest.main()
