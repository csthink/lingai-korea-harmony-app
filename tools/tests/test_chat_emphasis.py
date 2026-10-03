"""Exercise the real native-chat emphasis parser without ArkUI or network calls.

Only paired inline ** emphasis is supported. This is not a Markdown renderer.
"""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'entry/src/main/ets/components/SpiritChatPanel.ets'


class ChatEmphasisTests(unittest.TestCase):
    def test_inline_emphasis_preserves_unsupported_and_literal_input(self):
        source = SOURCE.read_text()
        run_start = source.index('class ChatTextRun {')
        run_end = source.index('\n}', run_start) + 2
        method_start = source.index('  private assistantTextRuns(')
        method_end = source.index('\n  }', method_start) + 4
        node_path = Path.home() / '.nvm/versions/node/v24.14.0/bin/node'
        node = os.environ.get('LINGAI_TEST_NODE') or (
            str(node_path) if node_path.is_file() else shutil.which('node'))
        self.assertIsNotNone(node, 'Node 24 is required for TypeScript stdin execution')
        code = "import assert from 'node:assert/strict';\n" + source[run_start:run_end]
        code += '\nclass Harness {\n' + source[method_start:method_end] + '\n}\n'
        code += r'''
const h = new Harness();
const parse = text => h.assistantTextRuns(text);
const visible = text => parse(text).map(run => run.text).join('');
const bold = text => parse(text).filter(run => run.emphasized).map(run => run.text);
assert.deepEqual(bold('可以说 **고마워**，也可以说 **감사합니다**。'), ['고마워', '감사합니다']);
assert.equal(visible('可以说 **고마워**\n第二行'), '可以说 고마워\n第二行');
assert.equal(visible('line 1\nline 2'), 'line 1\nline 2');
for (const text of ['**unfinished', '** **', '***triple***', '2 * 3 = 6', '\\**literal**', '**one\ntwo**']) {
  assert.equal(visible(text), text);
  assert.deepEqual(bold(text), []);
}
const inline = '`**code**` 和 **韩语**';
assert.equal(visible(inline), '`**code**` 和 韩语');
assert.deepEqual(bold(inline), ['韩语']);
const fenced = '```text\n**literal**\n```\n**韩语**';
assert.equal(visible(fenced), '```text\n**literal**\n```\n韩语');
assert.deepEqual(bold(fenced), ['韩语']);
assert.equal(visible('`**unclosed code**'), '`**unclosed code**');
assert.equal(visible('<script>**literal HTML text**</script>'), '<script>literal HTML text</script>');
assert.equal(visible(''), '');
console.log('PASS: paired emphasis, Korean, lines, escapes, unpaired delimiters, code, literal HTML');
'''
        result = subprocess.run(
            [node, '--experimental-strip-types', '--input-type=module-typescript'],
            input=code, text=True, capture_output=True, timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('PASS:', result.stdout)
        # Copy, persistence, and sent contents retain the original message string.
        self.assertIn('this.copyText(msg.content);', source)
        self.assertIn('this.chatService.addMessage(assistantMsg.role, assistantMsg.content)', source)
        self.assertNotIn('RichText(', source)


if __name__ == '__main__':
    unittest.main()
