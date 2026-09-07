import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Attachments, decodeImage, receiveWindows } from '../attachments.mjs';
import { validateAction } from '../server.mjs';
import { randomUUID } from 'node:crypto';
const data = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7V8AAAAASUVORK5CYII=', 'base64');
const body = { contentType: 'image/png', data: data.toString('base64') };

test('image boundary rejects disguised files, oversized uploads, and prompt path injection', () => {
  assert.deepEqual(decodeImage(body), data);
  assert.throws(() => decodeImage({ ...body, data: Buffer.from('not an image file').toString('base64') }));
  assert.throws(() => decodeImage({ ...body, contentType: 'image/svg+xml' }));
  assert.throws(() => decodeImage({ ...body, data: 'A'.repeat(4194308) }));
  assert.throws(() => validateAction({ requestId: randomUUID(), type: 'prompt', text: 'look', attachments: ['/tmp/private'] }));
  assert.throws(() => validateAction({ requestId: randomUUID(), type: 'response', sequence: 1, text: 'yes', attachments: ['a'.repeat(64)] }));
  assert.doesNotThrow(() => validateAction({ requestId: randomUUID(), type: 'prompt', text: '', attachments: ['a'.repeat(64)] }));
  assert.throws(() => receiveWindows('-oProxyCommand=bad', 'a'.repeat(64), 'png', data));
});

test('photos are durable, idempotent and bound to the originating device and terminal', async () => {
  const root = await mkdtemp(join(tmpdir(), 'herdr-photos-'));
  const runtime = { locked: async (_, work) => work(), resolve: async () => ({ agent: { kind: 'codex' }, machine: { name: 'Mac', remote: false } }) };
  const attachments = new Attachments({ attachmentPath: root }, runtime);
  try {
    const first = await attachments.upload('phone', 'mac/term1', body);
    const retry = await attachments.upload('phone', 'mac/term1', body);
    assert.equal(first.id, retry.id);
    const restarted = new Attachments({ attachmentPath: root }, runtime);
    const [path] = await restarted.paths('phone', 'mac/term1', [first.id]);
    assert.deepEqual(await readFile(path), data);
    await assert.rejects(restarted.paths('other-phone', 'mac/term1', [first.id]), /another device/);
    await assert.rejects(restarted.paths('phone', 'mac/term2', [first.id]), /another device/);
    await assert.rejects(restarted.paths('phone', 'mac/term1', ['../private']), /Invalid photo/);
  } finally { await rm(root, { recursive: true }); }
});

test('remote attachment paths exist only after worker transfer succeeds', async () => {
  const root = await mkdtemp(join(tmpdir(), 'herdr-remote-photos-'));
  const runtime = { locked: async (_, work) => work(), resolve: async () => ({ agent: { kind: 'claude' }, machine: { name: 'Home PC', remote: true, target: 'saved-worker' } }) };
  let calls = 0;
  const attachments = new Attachments({ attachmentPath: root }, runtime, async (target, id, extension, bytes) => {
    calls++; assert.equal(target, 'saved-worker'); assert.equal(extension, 'png'); assert.deepEqual(bytes, data);
    if (calls === 1) throw new Error('offline');
    return `C:\\Users\\Mark\\AppData\\Local\\HerdrShared\\attachments\\${id}.png`;
  });
  try {
    await assert.rejects(attachments.upload('phone', 'worker/term1', body), /offline/);
    const result = await attachments.upload('phone', 'worker/term1', body);
    assert.match((await attachments.paths('phone', 'worker/term1', [result.id]))[0], /^C:\\/);
    assert.equal(calls, 2);
  } finally { await rm(root, { recursive: true }); }
});
