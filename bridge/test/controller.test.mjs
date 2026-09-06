import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { once } from 'node:events';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Store } from '../store.mjs';
import { Runtime, RuntimeError } from '../runtime.mjs';
import { createApp, validateAction } from '../server.mjs';
import { Notifications } from '../notifications.mjs';

const config = { herdrPath: '/private/herdr', databasePath: ':memory:', adminToken: 'test-admin-token-only-for-fixtures', publicURL: 'https://controller.example:8443', allowedLogin: '' };
function fixture() {
  const state = { writes: [], status: 'working', sequence: 1, terminal: 'term-1', offline: false };
  const agent = () => ({ agent: 'codex', agent_status: state.status, terminal_id: state.terminal, pane_id: 'w1:p1', workspace_id: 'w1', tab_id: 'w1:t1', name: 'mac-codex', cwd: '/tmp/scratch', interactive_ready: true, state_change_seq: state.sequence });
  const runner = async (binary, argv, options) => {
    assert.equal(binary, config.herdrPath); assert.equal(options.shell, undefined);
    const args = argv.slice(2);
    if (args[0] === 'machine' && args[1] === 'list') return { stdout: '' };
    if (state.offline) throw new Error('offline');
    let result;
    if (args[0] === 'api') result = { snapshot: { version: 'test', agents: [agent()], workspaces: [{ workspace_id: 'w1', label: 'Scratch', pane_count: 1 }], tabs: [], panes: [{ pane_id: 'w1:p1', terminal_id: state.terminal, cwd: '/tmp/scratch', workspace_id: 'w1' }] } };
    else if (args[0] === 'agent' && args[1] === 'get') result = { agent: agent() };
    else if (args[0] === 'agent' && args[1] === 'read') { assert.equal(args[4], 'visible'); return { stdout: 'Example output\n' }; }
    else { state.writes.push(args); result = { agent: agent() }; }
    return { stdout: JSON.stringify({ result }) };
  };
  const store = new Store(':memory:'); const runtime = new Runtime(config, store, runner);
  return { state, runner, store, runtime };
}

test('pair codes are single-use, only token hashes are stored, revoked devices lose access', () => {
  const store = new Store(':memory:');
  const code = store.pairCode().code; const pair = store.pair(code, 'Test iPhone');
  assert.ok(store.authenticate(pair.token)); assert.equal(store.pair(code, 'Second device'), null);
  assert.notEqual(store.db.prepare('SELECT token_hash FROM devices').get().token_hash, pair.token);
  store.revoke(pair.deviceId); assert.equal(store.authenticate(pair.token), undefined); store.close();
});

test('an interrupted persisted command remains uncertain after restart', () => {
  const root = mkdtempSync(join(tmpdir(), 'herdr-operation-')); const file = join(root, 'store.sqlite'); const id = randomUUID();
  let store = new Store(file); store.beginOperation(id, 'device', { text: 'go' }); store.close();
  store = new Store(file); assert.equal(store.operation(id, 'device').state, 'uncertain');
  assert.equal(store.beginOperation(id, 'device', { text: 'go' }).state, 'uncertain');
  assert.throws(() => store.beginOperation(id, 'device', { text: 'different' }));
  store.close(); rmSync(root, { recursive: true });
});

test('live discovery separates pending worker, preserves offline agents as stale, and emits transitions once', async () => {
  const { runtime, state, store } = fixture();
  await runtime.refresh(); assert.equal(runtime.agents.length, 1); assert.equal(runtime.machines.at(-1).state, 'pending');
  assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM events').get().n, 0);
  state.status = 'blocked'; state.sequence++; await runtime.refresh(); await runtime.refresh();
  assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM events').get().n, 1);
  state.offline = true; await runtime.refresh(); assert.equal(runtime.agents[0].stale, true);
  await assert.rejects(runtime.action('mac/term-1', { type: 'prompt', text: 'hello' }), /offline/);
  assert.equal(state.writes.length, 0); store.close();
});

test('prompt data is passed literally and reads never change the selected desktop pane', async () => {
  const { runtime, state, store } = fixture(); await runtime.refresh();
  const text = 'Describe $HOME; $(touch /tmp/not-executed) "quoted"\nsecond line';
  await runtime.action('mac/term-1', { type: 'prompt', text });
  assert.deepEqual(state.writes, [['agent', 'prompt', 'w1:p1', text]]);
  const output = await runtime.output('mac/term-1'); assert.equal(output.text, 'Example output\n'); assert.equal(output.sequence, 1);
  assert.ok(!state.writes.flat().includes('focus')); store.close();
});

test('stale approval input and a replaced terminal cannot receive a command', async () => {
  const { runtime, state, store } = fixture(); await runtime.refresh();
  state.status = 'blocked'; state.sequence = 2;
  await assert.rejects(runtime.action('mac/term-1', { type: 'key', key: 'enter', sequence: 1 }), /changed since/);
  await assert.rejects(runtime.action('mac/term-1', { type: 'prompt', text: 'yes' }), /question or approval/);
  state.terminal = 'different'; await assert.rejects(runtime.action('mac/term-1', { type: 'key', key: 'enter', sequence: 2 }), /ended or moved/);
  assert.equal(state.writes.length, 0); store.close();
});

test('unsupported controls and oversized prompts are rejected', () => {
  assert.throws(() => validateAction({ requestId: randomUUID(), type: 'shell', text: 'rm' }));
  assert.throws(() => validateAction({ requestId: randomUUID(), type: 'key', key: 'ctrl+d', sequence: 1 }));
  assert.throws(() => validateAction({ requestId: randomUUID(), type: 'prompt', text: 'x'.repeat(16001) }));
});

test('a connection failure after typing a response remains uncertain and does not press Enter', async () => {
  const { runtime, state, store, runner } = fixture();
  state.status = 'blocked';
  runtime.runner = async (...args) => {
    if (state.writes.length) throw new Error('Connection lost after typing');
    return runner(...args);
  };
  await assert.rejects(runtime.action('mac/term-1', { type: 'response', text: 'yes', sequence: 1 }), error => error.uncertain === true);
  assert.deepEqual(state.writes, [['pane', 'send-text', 'w1:p1', 'yes']]); store.close();
});

test('push delivery respects privacy, changed preferences, revoked tokens and transient retries', async () => {
  const store = new Store(':memory:');
  const pair = store.pair(store.pairCode().code, 'Test iPhone');
  store.registerPush(pair.deviceId, 'test-token', 'production');
  const sent = [];
  class TestNotifications extends Notifications {
    get configured() { return true; }
    async send(...args) { sent.push(args); if (this.failure) throw this.failure; return { accepted: true }; }
  }
  const push = new TestNotifications({}, store);
  const event = () => store.addEvent({ kind: 'attention', agentId: 'mac/terminal', machineId: 'mac', title: 'An agent needs you', body: 'Private name · Mac' });
  event(); await push.drain();
  assert.equal(sent.length, 1); assert.equal(sent[0][1], 'production');
  assert.equal(sent[0][2].aps.alert.body, 'Open Herdr to review the latest activity.');
  assert.ok(!JSON.stringify(sent[0][2]).includes('Private name'));
  event(); store.setPreferences(pair.deviceId, { attention: false, completion: true, connection: true, previews: false });
  await push.drain(); assert.equal(sent.length, 1);
  store.setPreferences(pair.deviceId, { attention: true, completion: true, connection: true, previews: false });
  event(); push.failure = Object.assign(new Error('Temporary'), { status: 503 }); await push.drain();
  assert.equal(store.db.prepare('SELECT attempts FROM outbox').get().attempts, 1);
  store.db.prepare('UPDATE outbox SET next_at=0').run();
  push.failure = Object.assign(new Error('Invalid token'), { status: 410 }); await push.drain();
  assert.equal(store.db.prepare('SELECT COUNT(*) AS n FROM outbox').get().n, 0);
  assert.equal(store.db.prepare('SELECT push_token FROM devices').get().push_token, null);
  store.close();
});

test('HTTP authentication, cross-origin protection, command deduplication, and delivery lookup work together', async () => {
  const { runtime, store, state } = fixture(); await runtime.refresh();
  const app = createApp(config, { runtime, store }); app.server.listen(0, '127.0.0.1'); await once(app.server, 'listening');
  const base = `http://127.0.0.1:${app.server.address().port}`;
  const request = async (path, { method = 'GET', token, body, origin } = {}) => {
    const res = await fetch(base + path, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(origin ? { Origin: origin } : {}) }, body: body ? JSON.stringify(body) : undefined });
    return { status: res.status, data: await res.json() };
  };
  try {
    assert.equal((await request('/api/state')).status, 401);
    assert.equal((await request('/operator/pair', { method: 'POST', body: {} })).status, 403);
    const pair = await request('/api/pair', { method: 'POST', body: { code: store.pairCode().code, name: 'iPhone' } });
    assert.equal(pair.status, 201); const token = pair.data.token;
    assert.equal((await request('/api/state', { token })).data.agents.length, 1);
    const action = { requestId: randomUUID(), type: 'prompt', text: 'Hello' };
    const path = '/api/agents/mac%2Fterm-1/actions';
    assert.equal((await request(path, { method: 'POST', token, body: action, origin: 'https://evil.example' })).status, 403);
    const first = await request(path, { method: 'POST', token, body: action });
    assert.equal(first.data.state, 'accepted');
    const repeat = await request(path, { method: 'POST', token, body: action });
    assert.equal(repeat.data.state, 'accepted'); assert.equal(state.writes.length, 1);
    assert.equal((await request(path, { method: 'POST', token, body: { ...action, text: 'different' } })).status, 409);
    assert.equal((await request(`/api/operations/${action.requestId}`, { token })).data.state, 'accepted');
    runtime.action = async () => { state.writes.push('uncertain'); throw new RuntimeError('uncertain', 'network', true); };
    const unknown = { ...action, requestId: randomUUID() };
    assert.equal((await request(path, { method: 'POST', token, body: unknown })).data.state, 'uncertain');
    await request(path, { method: 'POST', token, body: unknown }); assert.equal(state.writes.length, 2);
    assert.equal((await request('/api/settings', { token })).data.push.configured, false);
    await request('/api/device', { method: 'DELETE', token }); assert.equal((await request('/api/state', { token })).status, 401);
  } finally { await new Promise(resolve => app.server.close(resolve)); store.close(); }
});
