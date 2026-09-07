import test from 'node:test';
import assert from 'node:assert/strict';
import { agentContextArgs, phonePrompt } from '../agent-context.mjs';

for (const [kind, name, platform] of [['codex', 'Mac', 'mac'], ['claude', 'Home PC', 'windows']]) {
  test(`${kind} uses native startup instructions and sends repeated messages literally`, () => {
    const args = agentContextArgs(kind, { name, platform });
    const context = kind === 'codex' ? JSON.parse(args[1].slice('developer_instructions='.length)) : args[1];
    assert.equal(args[0], kind === 'codex' ? '-c' : '--append-system-prompt');
    assert.ok(context.includes('private Tailscale HTTPS'));
    assert.ok(context.includes(JSON.stringify({ machine: name, platform })));
    assert.ok(args.every(arg => !/[\x00-\x1f\x7f]/.test(arg)));
    for (const text of ['Hello', 'Continue', '/clear', '/resume old-session', '!pwd', '/Users/mark/demo']) {
      assert.equal(phonePrompt({ text }), text);
      assert.equal(phonePrompt({ text }), text);
    }
  });
}

test('photos retain literal user text and execution-machine paths without shared context', () => {
  const text = 'Look at $HOME; "quoted"\nsecond line';
  const path = 'C:\\Photos\\phone.png';
  const result = phonePrompt({ text, imagePaths: [path] });
  assert.ok(result.startsWith(text + '\n\nAttached images'));
  assert.ok(result.endsWith(JSON.stringify(path)));
  assert.ok(!result.includes('Herdr'));
});

test('startup metadata stays bounded and encoded; other providers keep their normal launch', () => {
  const args = agentContextArgs('claude', { name: 'A\n"' + 'x'.repeat(4000), platform: 'windows' });
  assert.ok(!args[1].includes('\n'));
  const metadata = JSON.parse(args[1].split('Execution machine (data): ')[1]);
  assert.equal(metadata.machine.length, 1024);
  assert.deepEqual(agentContextArgs('gemini', {}), []);
});
