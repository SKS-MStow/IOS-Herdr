// Creates only its own temporary verification workspaces, then closes them.
import { readFileSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { cleanEnvironment } from '../bridge/runtime.mjs';
const run = promisify(execFile);
const config = JSON.parse(readFileSync(process.env.HOME + '/.config/herdr-iphone/config.json', 'utf8'));
const request = async (path, method = 'GET', body, token) => {
  const response = await fetch(config.publicURL + path, { method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) }, body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(65000) });
  const data = await response.json(); if (!response.ok) throw new Error(data.error?.message || `HTTP ${response.status}`); return data;
};
const code = await (await fetch('http://127.0.0.1:8790/operator/pair', { method: 'POST', headers: { Authorization: 'Bearer ' + config.adminToken, 'Content-Type': 'application/json' }, body: '{}' })).json();
const pair = await request('/api/pair', 'POST', { code: code.code, name: 'Temporary native integration verification' });
try {
  const state = await request('/api/state', 'GET', undefined, pair.token);
  for (const machine of state.machines.filter(m => m.state === 'online')) {
    let workspaceId;
    try {
      const operation = (path, body) => request(path, 'POST', { requestId: randomUUID(), ...body }, pair.token);
      const created = await operation('/api/workspaces', { machineId: machine.id, label: 'iPhone verification', cwd: machine.id === 'mac' ? '/Users/mark/Documents/Herdr/Scratch' : 'C:\\Users\\Mark\\Documents\\Herdr\\Scratch' });
      if (created.state !== 'accepted') throw new Error(created.result?.message || created.state);
      workspaceId = created.result.workspaceId;
      console.log(`${machine.name}: verification workspace created`);
      const started = await operation('/api/agents/start', { machineId: machine.id, paneId: created.result.paneId, name: 'iphone-check-' + randomUUID().slice(0, 8), kind: machine.id === 'mac' ? 'codex' : 'claude' });
      if (started.state !== 'accepted') throw new Error(started.result?.message || started.state);
      const agentId = started.result.agentId;
      console.log(`${machine.name}: agent started`);
      const path = '/api/agents/' + encodeURIComponent(agentId);
      const prompt = await operation(path + '/actions', { type: 'prompt', text: 'Reply with exactly HERDR_IPHONE_VERIFIED. Do not use tools or read or change files.' });
      if (prompt.state !== 'accepted') throw new Error(prompt.result?.message || prompt.state);
      let verified = false;
      for (let attempt = 0; attempt < 20; attempt++) {
        const output = await request(path + '/output', 'GET', undefined, pair.token);
        if (/^\s*(?:[●•›>\-]\s*)?HERDR_IPHONE_VERIFIED\s*$/m.test(output.text)) { verified = true; break; }
        await new Promise(resolve => setTimeout(resolve, 2000));
      }
      if (!verified) throw new Error('The expected reply was not observed.');
      console.log(`${machine.name}: real reply verified through the HTTPS controller`);
    } finally {
      if (workspaceId) {
        const args = ['--session', 'shared', ...(machine.id === 'mac' ? [] : ['machine', 'exec', machine.id, '--']), 'workspace', 'close', workspaceId];
        await run(config.herdrPath, args, { env: cleanEnvironment(), timeout: 20000 });
        console.log(`${machine.name}: verification workspace closed`);
      }
    }
  }
} finally { await request('/api/device', 'DELETE', undefined, pair.token); }
