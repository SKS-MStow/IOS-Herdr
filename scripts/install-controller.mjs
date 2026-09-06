import { mkdirSync, readFileSync, writeFileSync, existsSync, realpathSync, chmodSync } from 'node:fs';
import { homedir } from 'node:os';
import { resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';

if (process.platform !== 'darwin') throw new Error('Install the controller on the Mac.');
const home = homedir(); const root = resolve(import.meta.dirname, '..');
const configDir = `${home}/.config/herdr-iphone`; const stateDir = `${home}/.local/share/herdr-iphone`; const logDir = `${home}/Library/Logs/HerdrIPhone`;
for (const dir of [configDir, stateDir, logDir]) mkdirSync(dir, { recursive: true, mode: 0o700 });
const configPath = `${configDir}/config.json`;
let config;
if (existsSync(configPath)) config = JSON.parse(readFileSync(configPath, 'utf8'));
else {
  const tailscale = JSON.parse(execFileSync('/opt/homebrew/bin/tailscale', ['status', '--json'], { encoding: 'utf8' }));
  const login = tailscale.User?.[tailscale.Self?.UserID]?.LoginName;
  if (!login) throw new Error('Could not identify this Mac’s Tailscale account.');
  config = { port: 8790, publicURL: `https://${tailscale.Self.DNSName.replace(/\.$/, '')}:8443`,
    reviewURL: 'http://100.103.121.43:8765/', herdrPath: `${home}/.local/share/herdr-shared/bin/herdr`,
    databasePath: `${stateDir}/controller.sqlite`, adminToken: randomBytes(32).toString('base64url'), allowedLogin: login,
    apns: { keyPath: '', keyId: '', teamId: 'V8W579ZBVB', topic: 'xyz.verdalecres.herdr' } };
  writeFileSync(configPath, JSON.stringify(config, null, 2), { mode: 0o600 });
}
chmodSync(configPath, 0o600);
const escape = value => value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const label = 'com.mark.herdr-iphone'; const plist = `${home}/Library/LaunchAgents/${label}.plist`;
const xml = `<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>Label</key><string>${label}</string><key>ProgramArguments</key><array><string>${escape(realpathSync(process.execPath))}</string><string>${escape(root)}/bridge/server.mjs</string></array>
<key>WorkingDirectory</key><string>${escape(root)}</string><key>RunAtLoad</key><true/><key>KeepAlive</key><true/><key>ThrottleInterval</key><integer>10</integer>
<key>EnvironmentVariables</key><dict><key>HERDR_IPHONE_CONFIG</key><string>${escape(configPath)}</string><key>HOME</key><string>${escape(home)}</string></dict>
<key>StandardOutPath</key><string>${escape(logDir)}/controller.log</string><key>StandardErrorPath</key><string>${escape(logDir)}/controller-error.log</string></dict></plist>`;
if (existsSync(plist)) { try { execFileSync('launchctl', ['bootout', `gui/${process.getuid()}`, plist], { stdio: 'pipe' }); } catch {} }
writeFileSync(plist, xml, { mode: 0o600 });
execFileSync('launchctl', ['bootstrap', `gui/${process.getuid()}`, plist]);
execFileSync('/opt/homebrew/bin/tailscale', ['serve', '--bg', '--https=8443', 'http://127.0.0.1:8790'], { stdio: 'inherit' });
console.log(`Controller installed: ${config.publicURL}`);
console.log('Pairing page: ' + config.publicURL + '/connect');
