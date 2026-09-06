// Deliver a one-use pairing link directly to a local simulator, without printing it.
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { homedir } from 'node:os';
const simulator = process.argv[2];
if (!/^[a-f0-9-]{36}$/i.test(simulator || '')) throw new Error('Provide the simulator UUID.');
const config = JSON.parse(readFileSync(`${homedir()}/.config/herdr-iphone/config.json`, 'utf8'));
const response = await fetch('http://127.0.0.1:8790/operator/pair', { method: 'POST', headers: { Authorization: `Bearer ${config.adminToken}`, 'Content-Type': 'application/json' }, body: '{}' });
if (!response.ok) throw new Error(`Pairing request failed: ${response.status}`);
const data = await response.json();
const link = new URL('herdr-shared://pair'); link.searchParams.set('server', config.publicURL); link.searchParams.set('code', data.code);
execFileSync('xcrun', ['simctl', 'openurl', simulator, link.href], { stdio: 'ignore' });
console.log('One-time pairing link delivered to the simulator.');
