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
    if (args[0] === 'shared-workspace' && args[1] === 'list') return { stdout: JSON.stringify({ result: state.catalog || { revision: 0, workspaces: [] } }) };
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
  assert.deepEqual(state.writes[0].slice(0, 3), ['agent', 'prompt', 'w1:p1']);
  assert.ok(state.writes[0][3].startsWith('[Herdr phone context v1]'));
  assert.ok(state.writes[0][3].endsWith('\n\n' + text));
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

test('shared catalog is additive, reflects desktop edits, and retains stale membership', async () => {
  const { runtime, state, store } = fixture();
  state.catalog = { revision: 3, workspaces: [{ id: 'group', label: 'Website', members: [
    { machineId: 'mac', session: 'shared', terminalId: 'term-1' },
    { machineId: '0123456789abcdef0123456789abcdef', session: 'shared', terminalId: 'term-1' }
  ] }] };
  await runtime.refresh();
  assert.equal(runtime.state().sharedWorkspaceCatalog.workspaces[0].members.length, 2);
  assert.equal(runtime.agents[0].workspaceId, 'w1');
  state.catalog.workspaces[0].label = 'Renamed on desktop'; state.catalog.revision++;
  await runtime.refresh(); assert.equal(runtime.state().sharedWorkspaceCatalog.workspaces[0].label, 'Renamed on desktop');
  runtime.runner = async () => { throw new Error('controller unavailable'); };
  await runtime.refresh();
  assert.equal(runtime.state().sharedWorkspaceCatalog.stale, true);
  assert.equal(runtime.state().sharedWorkspaceCatalog.workspaces[0].members.length, 2);
  assert.equal(runtime.agents[0].stale, true);
  store.close();
});

test('metadata retry recovers an interrupted receipt and cannot become a different command', async () => {
  const { runtime, store } = fixture();
  const app = createApp(config, { runtime, store }); app.server.listen(0, '127.0.0.1'); await once(app.server, 'listening');
  const pair = store.pair(store.pairCode().code, 'Test phone');
  const body = { requestId: randomUUID(), expectedRevision: 0, action: 'create', label: 'Website' };
  const fingerprint = { ...body, operation: 'shared-workspace-change' };
  store.beginOperation(body.requestId, pair.deviceId, fingerprint);
  store.finishOperation(body.requestId, 'uncertain', { message: 'bridge restarted' });
  let calls = 0;
  runtime.changeSharedWorkspace = async input => { calls++; assert.deepEqual(input, body); return { sharedWorkspaceId: 'stable-group', revision: 1 }; };
  const send = async payload => {
    const r = await fetch(`http://127.0.0.1:${app.server.address().port}/api/shared-workspaces/change`, { method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${pair.token}` }, body: JSON.stringify(payload) });
    return { status: r.status, data: await r.json() };
  };
  try {
    assert.equal((await send(body)).data.result.sharedWorkspaceId, 'stable-group');
    assert.equal((await send(body)).data.state, 'accepted'); assert.equal(calls, 1);
    assert.equal((await send({ ...body, action: 'delete', id: 'different' })).status, 409);
    assert.equal(calls, 1);
  } finally { await new Promise(resolve => app.server.close(resolve)); store.close(); }
});


test('overlapping catalog reads cannot undo newer state or mark it stale', async () => {
  const { runtime, store } = fixture();
  const reads = [];
  runtime.command = () => new Promise((resolve, reject) => reads.push({ resolve, reject }));
  const first = runtime.refreshSharedWorkspaces();
  const second = runtime.refreshSharedWorkspaces();
  reads[1].resolve({ revision: 2, workspaces: [{ id: 'group', label: 'New name', members: [] }] });
  await second;
  reads[0].resolve({ revision: 1, workspaces: [{ id: 'group', label: 'Old name', members: [] }] });
  await first;
  assert.equal(runtime.state().sharedWorkspaceCatalog.revision, 2);
  assert.equal(runtime.state().sharedWorkspaceCatalog.workspaces[0].label, 'New name');
  const older = runtime.refreshSharedWorkspaces();
  const newer = runtime.refreshSharedWorkspaces();
  reads[3].resolve({ revision: 3, workspaces: [] }); await newer;
  reads[2].reject(new Error('old connection failed')); await older;
  assert.equal(runtime.state().sharedWorkspaceCatalog.stale, false);
  store.close();
});


test('catalog storage failure stays uncertain while intrinsic mutation rejection is final', async () => {
  const { runtime, store } = fixture();
  for (const [code, uncertain] of [['shared_workspace_error', true], ['workspace_rejected', false]]) {
    runtime.runner = async () => { const error = new Error('CLI failed'); error.stdout = JSON.stringify({ error: { code, message: 'Catalog write result' } }); throw error; };
    await assert.rejects(runtime.command({ remote: false }, ['shared-workspace', 'apply', '{}'], { mutation: true }), error => error.code === code && error.uncertain === uncertain);
  }
  store.close();
});

test('HTTP photos require pairing, reach the prompt once, and reject cross-device reuse', async () => {
  const { runtime, store, state } = fixture();
  const root = mkdtempSync(join(tmpdir(), 'herdr-http-photos-'));
  const app = createApp({ ...config, attachmentPath: root }, { runtime, store });
  app.server.listen(0, '127.0.0.1'); await once(app.server, 'listening');
  const pair = store.pair(store.pairCode().code, 'Photo phone');
  const other = store.pair(store.pairCode().code, 'Other phone');
  const send = async (path, body, token) => {
    const response = await fetch(`http://127.0.0.1:${app.server.address().port}${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(body) });
    return { status: response.status, data: await response.json() };
  };
  try {
    const image = { contentType: 'image/png', data: 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a7V8AAAAASUVORK5CYII=' };
    const base = '/api/agents/mac%2Fterm-1';
    assert.equal((await send(base + '/attachments', image)).status, 401);
    const photo = await send(base + '/attachments', image, pair.token);
    assert.equal(photo.status, 201); assert.equal(state.writes.length, 0);
    const action = { requestId: randomUUID(), type: 'prompt', text: 'Read the image', attachments: [photo.data.id] };
    assert.equal((await send(base + '/actions', action, pair.token)).data.state, 'accepted');
    assert.equal((await send(base + '/actions', action, pair.token)).data.state, 'accepted');
    assert.equal(state.writes.length, 1);
    assert.ok(state.writes[0][3].includes(root));
    assert.ok(state.writes[0][3].includes('image-reading tool'));
    const rejected = await send(base + '/actions', { ...action, requestId: randomUUID() }, other.token);
    assert.equal(rejected.data.state, 'rejected'); assert.equal(state.writes.length, 1);
  } finally { await new Promise(r => app.server.close(r)); store.close(); rmSync(root, { recursive: true }); }
});
