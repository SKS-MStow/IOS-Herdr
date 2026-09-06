import { createServer } from 'node:http';
import { readFileSync, writeFileSync, renameSync, mkdirSync } from 'node:fs';
import { createPrivateKey } from 'node:crypto';
import { dirname, join } from 'node:path';
import { homedir } from 'node:os';
import { pathToFileURL } from 'node:url';
import { Store, digest, now, defaultPreferences } from './store.mjs';
import { Runtime } from './runtime.mjs';
import { Notifications } from './notifications.mjs';

export class HTTPError extends Error { constructor(status, message, code = 'invalid_request') { super(message); this.status = status; this.code = code; } }
const string = (value, label, max = 256) => {
  if (typeof value !== 'string' || !value.trim() || value.length > max || value.includes('\0')) throw new HTTPError(400, `Invalid ${label}.`);
  return value;
};
const uuid = value => { if (!/^[a-f0-9-]{36}$/i.test(value || '')) throw new HTTPError(400, 'A unique request ID is required.'); return value; };
export function validateAction(body) {
  uuid(body.requestId);
  if (!['prompt', 'response', 'key'].includes(body.type)) throw new HTTPError(400, 'Unsupported action.');
  if (body.type === 'prompt' || body.type === 'response') string(body.text, 'message', 16000);
  if (body.type === 'key' && !['esc', 'tab', 'enter', 'up', 'down', 'left', 'right', 'ctrl+c'].includes(body.key)) throw new HTTPError(400, 'Unsupported key.');
  if (body.type !== 'prompt' && !Number.isSafeInteger(body.sequence)) throw new HTTPError(400, 'Refresh the session before responding.');
  return body;
}
async function readJSON(req) {
  if (!req.headers['content-type']?.startsWith('application/json')) throw new HTTPError(415, 'JSON is required.');
  let body = ''; let size = 0;
  for await (const chunk of req) { size += chunk.length; if (size > 65536) throw new HTTPError(413, 'Request is too large.'); body += chunk; }
  try { const result = JSON.parse(body); if (!result || Array.isArray(result) || typeof result !== 'object') throw new Error(); return result; }
  catch { throw new HTTPError(400, 'Invalid JSON.'); }
}
const json = (res, status, body) => { res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' }); res.end(JSON.stringify(body)); };
const escape = value => String(value).replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);

function connectPage(config) {
  return `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Connect Herdr</title>
  <style>body{font:17px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#111413;color:#f1f5f2;margin:0}main{max-width:580px;margin:8vh auto;padding:28px}h1{font-size:36px;letter-spacing:-.04em}p{color:#aab5ae;line-height:1.6}a{color:#b5e4c9}button,.button{display:inline-block;border:0;border-radius:12px;background:#b5e4c9;color:#111413;padding:16px 22px;font:inherit;font-weight:650;cursor:pointer;text-decoration:none}code{word-break:break-all}#code{font-size:30px;letter-spacing:.12em;color:#b5e4c9}#result{margin-top:32px}.muted{font-size:14px}button:disabled{opacity:.5}</style>
  <main><h1>Connect your iPhone.</h1><p>Herdr runs through your Mac. Open this page on your iPhone with Tailscale connected, then pair the native app.</p>
  <p class="muted">Controller<br><code>${escape(config.publicURL)}</code></p><button id="pair">Create a pairing code</button><section id="result" aria-live="polite"></section>
  <p class="muted">Codes expire after 10 minutes and work once. Your agent sign-ins stay on their execution machines.</p><p><a href="${escape(config.reviewURL || 'http://100.103.121.43:8765/')}">View the iPhone designs</a></p></main>
  <script>document.getElementById('pair').onclick=async()=>{const button=document.getElementById('pair');button.disabled=true;const result=document.getElementById('result');result.textContent='Creating code…';try{const response=await fetch('/operator/pair',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});const data=await response.json();if(!response.ok)throw new Error(data.error.message);result.replaceChildren();const code=document.createElement('p');code.id='code';code.textContent=data.code;const link=document.createElement('a');link.className='button';link.textContent='Open Herdr and connect';link.href='herdr-shared://pair?server='+encodeURIComponent(data.server)+'&code='+encodeURIComponent(data.code);const note=document.createElement('p');note.textContent='Or enter this code in the Herdr iPhone app.';result.append(code,link,note);}catch(error){result.textContent=error.message;}finally{button.disabled=false;}};</script></html>`;
}

function setupPage() {
  return `<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Herdr push setup</title>
  <style>body{font:17px -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;background:#111413;color:#f1f5f2;margin:0}main{max-width:600px;margin:6vh auto;padding:24px}h1{font-size:34px}p,li{line-height:1.6;color:#aab5ae}a{color:#b5e4c9}label{display:block;margin:22px 0 10px}input{display:block;box-sizing:border-box;width:100%;padding:14px;background:#1c211e;border:1px solid #4f5d54;border-radius:10px;color:#f1f5f2;font:inherit}button{margin:24px 0 12px;border:0;border-radius:12px;padding:16px 22px;background:#b5e4c9;color:#111413;font:inherit;font-weight:650}#message{line-height:1.5}small{color:#aab5ae}</style>
  <main><h1>Set up iPhone alerts.</h1><p>The Mac sends notifications through Apple. Add a dedicated Apple Push Notification service (APNs) key here. An App Store Connect API key is a different credential.</p>
  <ol><li>Open <a href="https://developer.apple.com/account/resources/authkeys/list" target="_blank" rel="noopener">Apple Developer → Keys</a>.</li><li>Create an APNs key named <strong>Herdr iPhone</strong>. Enable production delivery for <code>xyz.verdalecres.herdr</code>. TestFlight uses production APNs.</li><li>Download the .p8 file and note its Key ID. Upload it below.</li></ol>
  <form id="form"><label for="keyId">Apple Key ID</label><input id="keyId" name="keyId" maxlength="10" pattern="[A-Za-z0-9]{10}" required autocomplete="off"><label for="file">APNs private key (.p8)</label><input id="file" type="file" accept=".p8" required><button type="submit">Save push key on the Mac</button></form><div id="message" role="status"></div>
  <p><small>The key travels over your Tailscale HTTPS connection and is stored privately on the Mac. It is never put in the iPhone app, source repository, notification payload or chat.</small></p><p><a href="/connect">Pair your iPhone</a></p></main>
  <script>document.getElementById('form').onsubmit=async(event)=>{event.preventDefault();const button=event.target.querySelector('button');button.disabled=true;const message=document.getElementById('message');message.textContent='Saving key…';try{const file=document.getElementById('file').files[0];if(!file||file.size>16384)throw new Error('Choose the APNs .p8 file.');const response=await fetch('/operator/apns',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({keyId:document.getElementById('keyId').value.trim().toUpperCase(),privateKey:await file.text()})});const data=await response.json();if(!response.ok)throw new Error(data.error.message);event.target.reset();message.textContent='Key saved. After pairing the iPhone, enable notifications in Herdr Settings and send a test alert to verify delivery.';}catch(error){message.textContent=error.message;}finally{button.disabled=false;}};</script></html>`;
}

export function createApp(config, { store = new Store(config.databasePath), runtime, notifications } = {}) {
  runtime ||= new Runtime(config, store); notifications ||= new Notifications(config, store);
  const rateLimits = new Map();
  function limit(key, max = 8) {
    const bucket = Math.floor(now() / 60); const current = rateLimits.get(key);
    const next = current?.bucket === bucket ? { bucket, count: current.count + 1 } : { bucket, count: 1 };
    rateLimits.set(key, next);
    if (rateLimits.size > 5000) for (const [k, v] of rateLimits) if (v.bucket < bucket) rateLimits.delete(k);
    if (next.count > max) throw new HTTPError(429, 'Too many attempts. Wait one minute before trying again.', 'rate_limited');
  }
  function operator(req) {
    const bearer = req.headers.authorization?.replace(/^Bearer /, '');
    if (bearer && digest(bearer) === digest(config.adminToken)) return true;
    // The service listens only on loopback. Tailscale Serve supplies authenticated identity.
    const identity = req.headers['tailscale-user-login'];
    return Boolean(config.allowedLogin && identity === config.allowedLogin && req.headers.host === new URL(config.publicURL).host);
  }
  async function operation(device, body, work, recoverMetadata = false) {
    uuid(body.requestId);
    let prior;
    try { prior = store.beginOperation(body.requestId, device.id, body); }
    catch (error) { throw new HTTPError(409, error.message, 'request_conflict'); }
    if (prior && (!recoverMetadata || ['accepted', 'rejected'].includes(prior.state))) return prior;
    try { const result = await work(); store.finishOperation(body.requestId, 'accepted', result); }
    catch (error) { store.finishOperation(body.requestId, error.uncertain ? 'uncertain' : 'rejected', { message: error.message, code: error.code || 'runtime_error' }); }
    return store.operation(body.requestId, device.id);
  }
  const server = createServer(async (req, res) => {
    res.setHeader('Cache-Control', 'no-store'); res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('Referrer-Policy', 'no-referrer'); res.setHeader('X-Frame-Options', 'DENY');
    // No cross-origin control requests and no cookies; mobile uses bearer tokens.
    if (req.headers.origin && req.headers.origin !== config.publicURL) return json(res, 403, { error: { code: 'origin', message: 'Cross-origin requests are not allowed.' } });
    try {
      const url = new URL(req.url, 'http://localhost');
      if (req.method === 'GET' && url.pathname === '/health') return json(res, 200, { service: 'herdr-iphone', version: '0.1.0' });
      if (req.method === 'GET' && url.pathname === '/setup') {
        if (!operator(req)) throw new HTTPError(403, 'Open this page using the controller owner’s Tailscale account.', 'operator_required');
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'" }); return res.end(setupPage());
      }
      if (url.pathname === '/connect' || url.pathname === '/') {
        if (req.method !== 'GET') throw new HTTPError(405, 'Method not allowed.');
        res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'" });
        return res.end(connectPage(config));
      }
      if (url.pathname.startsWith('/operator/')) {
        if (!operator(req)) throw new HTTPError(403, 'Open this page through your own Tailscale account, or create a code on the Mac.', 'operator_required');
        if (req.method === 'POST' && url.pathname === '/operator/pair') { limit('operator'); await readJSON(req); return json(res, 201, { ...store.pairCode(), server: config.publicURL }); }
        if (req.method === 'GET' && url.pathname === '/operator/devices') return json(res, 200, { devices: store.devices() });
        if (req.method === 'POST' && url.pathname === '/operator/apns') {
          limit('operator-apns', 5);
          const body = await readJSON(req);
          if (!/^[A-Z0-9]{10}$/.test(body.keyId || '') || body.keyId === 'Y3JLHLYZD5') throw new HTTPError(400, 'Use an APNs Key ID, not the App Store Connect API key.');
          string(body.privateKey, 'APNs private key', 16384);
          let key; try { key = createPrivateKey(body.privateKey); } catch { throw new HTTPError(400, 'This file is not a valid private key.'); }
          if (key.asymmetricKeyType !== 'ec' || key.asymmetricKeyDetails?.namedCurve !== 'prime256v1') throw new HTTPError(400, 'APNs requires an Apple P-256 signing key.');
          if (!config.configPath) throw new HTTPError(503, 'The configuration location is unavailable.');
          const keyDir = join(dirname(config.configPath), 'keys'); mkdirSync(keyDir, { recursive: true, mode: 0o700 });
          const keyPath = join(keyDir, `AuthKey_${body.keyId}.p8`);
          writeFileSync(keyPath, key.export({ type: 'pkcs8', format: 'pem' }), { mode: 0o600, flag: 'wx' });
          const next = { ...config, apns: { keyPath, keyId: body.keyId, teamId: 'V8W579ZBVB', topic: 'xyz.verdalecres.herdr' } };
          const temporary = config.configPath + '.next'; writeFileSync(temporary, JSON.stringify(next, null, 2), { mode: 0o600 }); renameSync(temporary, config.configPath);
          config.apns = next.apns; notifications.lastError = null; return json(res, 200, { configured: true });
        }
        if (req.method === 'DELETE' && url.pathname.startsWith('/operator/devices/')) { store.revoke(url.pathname.split('/').at(-1)); return json(res, 200, { revoked: true }); }
        throw new HTTPError(404, 'Not found.');
      }
      if (req.method === 'POST' && url.pathname === '/api/pair') {
        limit('pair-global', 20); const input = await readJSON(req);
        string(input.code, 'pairing code', 20); string(input.name, 'device name', 80);
        const result = store.pair(input.code.replace(/\s|-/g, ''), input.name);
        if (!result) throw new HTTPError(401, 'The pairing code is incorrect, expired, or already used.', 'invalid_code');
        return json(res, 201, result);
      }
      const device = store.authenticate(req.headers.authorization?.replace(/^Bearer /, ''));
      if (!device) throw new HTTPError(401, 'Pair this iPhone with the Mac to continue.', 'unauthorized');
      limit(`device:${device.id}`, 180);
      if (req.method === 'GET' && url.pathname === '/api/state') { if (!runtime.machines.length) await runtime.refresh(); return json(res, 200, { ...runtime.state(), notifications: notifications.status() }); }
      if (req.method === 'GET' && url.pathname === '/api/inbox') return json(res, 200, { events: store.events(device) });
      if (req.method === 'POST' && url.pathname === '/api/inbox/read') {
        const body = await readJSON(req); if (!Number.isSafeInteger(body.through) || body.through < 0) throw new HTTPError(400, 'Invalid event ID.');
        store.markRead(device.id, body.through); return json(res, 200, { ok: true });
      }
      if (req.method === 'GET' && url.pathname === '/api/settings') return json(res, 200, { preferences: store.preferences(device), push: notifications.status(), pushRegistered: Boolean(device.push_token), deviceId: device.id });
      if (req.method === 'PUT' && url.pathname === '/api/settings') {
        const body = await readJSON(req); const preferences = Object.fromEntries(Object.keys(defaultPreferences).map(key => {
          if (typeof body[key] !== 'boolean') throw new HTTPError(400, 'Invalid notification preference.'); return [key, body[key]];
        })); store.setPreferences(device.id, preferences); return json(res, 200, { preferences });
      }
      if (req.method === 'POST' && url.pathname === '/api/push/register') {
        const body = await readJSON(req);
        if (!/^[a-f0-9]{32,512}$/i.test(body.token || '') || !['sandbox', 'production'].includes(body.environment)) throw new HTTPError(400, 'Invalid push registration.');
        store.registerPush(device.id, body.token, body.environment); return json(res, 200, { registered: true, providerConfigured: notifications.configured });
      }
      if (req.method === 'POST' && url.pathname === '/api/push/test') {
        limit(`push:${device.id}`, 3); await readJSON(req);
        if (!device.push_token) throw new HTTPError(409, 'Enable notifications on this iPhone first.', 'push_unregistered');
        if (!notifications.configured) throw new HTTPError(503, 'The Mac still needs an APNs signing key.', 'push_unconfigured');
        return json(res, 200, await notifications.send(device.push_token, device.push_environment, { aps: { alert: { title: 'Herdr is connected', body: 'Your iPhone can receive agent alerts.' }, sound: 'default' } }, `test-${device.id}`));
      }
      if (req.method === 'DELETE' && url.pathname === '/api/device') { store.revoke(device.id); return json(res, 200, { revoked: true }); }
      const opMatch = url.pathname.match(/^\/api\/operations\/([a-f0-9-]+)$/i);
      if (req.method === 'GET' && opMatch) { const result = store.operation(opMatch[1], device.id); if (!result) throw new HTTPError(404, 'This command was not recorded by the controller.', 'operation_missing'); return json(res, 200, result); }
      const agentMatch = url.pathname.match(/^\/api\/agents\/([^/]+)\/(output|actions)$/);
      if (agentMatch) {
        const id = decodeURIComponent(agentMatch[1]);
        if (req.method === 'GET' && agentMatch[2] === 'output') return json(res, 200, await runtime.output(id));
        if (req.method === 'POST' && agentMatch[2] === 'actions') {
          const body = validateAction(await readJSON(req));
          return json(res, 200, await operation(device, { ...body, agentId: id }, () => runtime.action(id, body)));
        }
      }
      if (req.method === 'POST' && url.pathname === '/api/workspaces') {
        const body = await readJSON(req); string(body.machineId, 'machine'); string(body.label, 'workspace label', 80); string(body.cwd, 'folder path', 1024);
        return json(res, 200, await operation(device, body, () => runtime.createWorkspace(body)));
      }
      if (req.method === 'POST' && url.pathname === '/api/shared-workspaces/change') {
        const body = await readJSON(req);
        if (!Number.isSafeInteger(body.expectedRevision) || body.expectedRevision < 0 || !['create', 'rename', 'delete', 'add', 'remove'].includes(body.action)) throw new HTTPError(400, 'Invalid workspace change.', 'invalid_request');
        const input = { requestId: body.requestId, expectedRevision: body.expectedRevision, action: body.action };
        if (body.action !== 'create') { string(body.id, 'shared workspace'); input.id = body.id; }
        if (['create', 'rename'].includes(body.action)) { string(body.label, 'workspace name', 128); input.label = body.label; }
        if (['add', 'remove'].includes(body.action)) {
          const member = body.member || {};
          string(member.machineId, 'machine'); string(member.terminalId, 'terminal', 128); string(member.session, 'session', 128);
          input.member = { machineId: member.machineId, terminalId: member.terminalId, session: member.session };
        }
        return json(res, 200, await operation(device, { ...input, operation: 'shared-workspace-change' }, () => runtime.changeSharedWorkspace(input), true));
      }
      if (req.method === 'POST' && url.pathname === '/api/agents/start') {
        const body = await readJSON(req); string(body.machineId, 'machine'); string(body.paneId, 'pane');
        if (!/^[a-z][a-z0-9_-]{0,31}$/.test(body.name || '') || !['codex', 'claude', 'gemini', 'hermes'].includes(body.kind)) throw new HTTPError(400, 'Choose a supported agent and a lowercase name.');
        return json(res, 200, await operation(device, body, () => runtime.startAgent(body)));
      }
      throw new HTTPError(404, 'Not found.');
    } catch (error) {
      if (!res.headersSent) json(res, error.status || (error.code ? 409 : 500), { error: { code: error.code || 'internal_error', message: error.status || error.code ? error.message : 'The controller could not complete this request.' } });
      else res.end();
    }
  });
  server.requestTimeout = 65000; server.headersTimeout = 10000;
  return { server, store, runtime, notifications };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const path = process.env.HERDR_IPHONE_CONFIG || `${homedir()}/.config/herdr-iphone/config.json`;
  const config = JSON.parse(readFileSync(path, 'utf8'));
  config.configPath = path;
  if (!config.publicURL?.startsWith('https://') || !config.adminToken || config.adminToken.length < 32) throw new Error('Configure HTTPS and a strong local admin token.');
  const app = createApp(config);
  app.server.listen(config.port || 8790, '127.0.0.1', () => console.log('Herdr iPhone controller listening on loopback.'));
  await app.runtime.refresh();
  const timer = setInterval(() => { app.runtime.refresh().catch(() => {}); app.notifications.drain().catch(() => {}); }, 5000);
  function stop() { clearInterval(timer); app.server.close(() => { app.store.close(); process.exit(0); }); setTimeout(() => process.exit(0), 3000).unref(); }
  process.on('SIGTERM', stop); process.on('SIGINT', stop);
}
