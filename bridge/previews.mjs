import { execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { readFileSync, mkdirSync, writeFileSync, renameSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { createServer as createTCPServer, connect } from 'node:net';
import { createServer as createHTTPServer, request } from 'node:http';
import { RuntimeError, cleanEnvironment } from './runtime.mjs';
const execute = promisify(execFile);
const fail = message => new RuntimeError(message, 'preview_unavailable');
export function previewTarget(value) {
  let url; try { url = new URL(value); } catch { throw fail('This preview URL is invalid.'); }
  if (url.protocol !== 'http:' || !['localhost', '127.0.0.1', '0.0.0.0', '[::1]'].includes(url.hostname) || url.username || url.password) throw fail('Use an HTTP localhost development-server link. Existing Tailscale and public links open directly.');
  const port = Number(url.port || 80);
  if (!Number.isInteger(port) || port < 1024 || port > 65535 || [8790, 8791, ...Array.from({length:8}, (_,i)=>8444+i), ...Array.from({length:8}, (_,i)=>19044+i), ...Array.from({length:8}, (_,i)=>20044+i)].includes(port)) throw fail('This port is reserved. Start the project preview on its own development port.');
  return { port, suffix: url.pathname + url.search + url.hash };
}
export class Previews {
  constructor(config, runtime, runner = execute) {
    this.config = config; this.runtime = runtime; this.runner = runner; this.tunnels = new Map(); this.relays = new Map();
    this.path = config.previewPath || join(dirname(config.databasePath), 'previews.json');
    this.records = [];
    try { const saved = JSON.parse(readFileSync(this.path, 'utf8')); if (!Array.isArray(saved) || saved.length > 8 || saved.some(r => !r || !/^(mac|[a-f0-9]{32})$/.test(r.machineId) || !Number.isInteger(r.port) || r.port < 1024 || r.port > 65535 || !Number.isInteger(r.httpsPort) || r.httpsPort < 8444 || r.httpsPort > 8451 || r.localPort !== 19044 + r.httpsPort - 8444) || new Set(saved.map(r => r.httpsPort)).size !== saved.length) throw new Error(); this.records = saved; } catch (error) { if (error.code !== 'ENOENT') this.invalid = true; }
  }
  async tailscale(args) {
    try { return await this.runner(this.config.tailscalePath || '/opt/homebrew/bin/tailscale', args, { env: cleanEnvironment(), timeout: 15000, maxBuffer: 1024 * 1024 }); }
    catch { throw fail('Tailscale could not prepare this preview. Check that the Mac is connected.'); }
  }
  save() { mkdirSync(dirname(this.path), {recursive:true, mode:0o700}); writeFileSync(this.path+'.tmp', JSON.stringify(this.records), {mode:0o600}); renameSync(this.path+'.tmp',this.path); }
  async tunnel(record, machine) {
    if (!machine.remote) return;
    const prior = this.tunnels.get(record.httpsPort);
    if (prior && prior.exitCode === null && !prior.killed) return;
    if (!/^[A-Za-z0-9_][A-Za-z0-9_.@:-]*$/.test(machine.target)) throw fail('This worker needs a supported saved SSH alias.');
    // Do not replace or piggyback on another listener.
    await new Promise((resolve, reject) => { const server=createTCPServer(); server.once('error',()=>reject(fail('The preview tunnel port is busy.'))); server.listen(record.localPort+1000,'127.0.0.1',()=>server.close(resolve)); });
    const child = spawn('/usr/bin/ssh', ['-N', '-T', '-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes', '-o', 'ConnectTimeout=10', '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=2', '-L', `127.0.0.1:${record.localPort+1000}:127.0.0.1:${record.port}`, machine.target], {env:cleanEnvironment(),stdio:'ignore'});
    this.tunnels.set(record.httpsPort, child);
    child.on('error',()=>this.tunnels.delete(record.httpsPort));
    child.on('exit',()=> { if (this.tunnels.get(record.httpsPort) === child) this.tunnels.delete(record.httpsPort); });
  }
  async relay(record, machine) {
    if (this.relays.has(record.httpsPort)) return;
    const targetPort = machine.remote ? record.localPort + 1000 : record.port;
    const publicOrigin = `https://${new URL(this.config.publicURL).hostname}:${record.httpsPort}`;
    const headers = incoming => {
      const result = { ...incoming, host: `localhost:${record.port}` };
      if (result.origin === publicOrigin) result.origin = `http://localhost:${record.port}`;
      delete result['x-forwarded-host']; return result;
    };
    const server = createHTTPServer((req, res) => {
      if (!req.url?.startsWith('/')) { res.writeHead(400); return res.end(); }
      const upstream = request({hostname:'127.0.0.1',port:targetPort,path:req.url,method:req.method,headers:headers(req.headers)}, reply => {
        const outgoing = {...reply.headers};
        if (outgoing.location) {
          try { const location = new URL(outgoing.location); if (['localhost','127.0.0.1','0.0.0.0'].includes(location.hostname) && Number(location.port) === record.port) outgoing.location = publicOrigin + location.pathname + location.search + location.hash; } catch {}
        }
        res.writeHead(reply.statusCode || 502, outgoing); reply.pipe(res);
      });
      upstream.on('error',()=> { if (!res.headersSent) res.writeHead(502); res.end('The development server is unavailable.'); });
      upstream.setTimeout(30000,()=>upstream.destroy()); req.on('aborted',()=>upstream.destroy()); req.pipe(upstream);
    });
    const sockets = new Set();
    server.on('connection', socket => { sockets.add(socket); socket.on('close',()=>sockets.delete(socket)); });
    server.on('upgrade', (req, socket, head) => {
      if (!req.url?.startsWith('/')) return socket.destroy();
      const upstream = connect(targetPort,'127.0.0.1',()=> {
        const lines = Object.entries(headers(req.headers)).flatMap(([name,value]) => Array.isArray(value) ? value.map(v=>`${name}: ${v}`) : [`${name}: ${value}`]);
        upstream.write(`${req.method} ${req.url} HTTP/1.1\r\n${lines.join('\r\n')}\r\n\r\n`);
        if (head.length) upstream.write(head); socket.pipe(upstream).pipe(socket);
      });
      upstream.on('error',()=>socket.destroy()); socket.on('error',()=>upstream.destroy()); socket.on('close',()=>upstream.destroy());
    });
    await new Promise((resolve,reject)=> { server.once('error',()=>reject(fail('The private preview relay port is busy.'))); server.listen(record.localPort,'127.0.0.1',resolve); });
    this.relays.set(record.httpsPort,{server,sockets});
  }
  async reachable(port) {
    for (let i=0;i<12;i++) {
      try { const response=await fetch(`http://127.0.0.1:${port}/`, {method:'HEAD',redirect:'manual',signal:AbortSignal.timeout(2000)}); await response.body?.cancel(); if (response.status !== 502) return; } catch {}
      await new Promise(resolve=>setTimeout(resolve,250));
    }
    throw fail('The preview server is not responding. Ask the agent to start the development server, then tap the link again.');
  }
  async open(agentId, value) {
    const target = previewTarget(value);
    return this.runtime.locked('previews', async()=> {
      if (this.invalid) throw fail('The saved preview configuration needs repair on the controller.');
      const {machine} = await this.runtime.resolve(agentId);
      const host = new URL(this.config.publicURL).hostname;
      if (!host.endsWith('.ts.net')) throw fail('The controller needs its Tailscale HTTPS hostname for previews.');
      const status = JSON.parse((await this.tailscale(['serve','status','--json'])).stdout || '{}');
      let record = this.records.find(r=>r.machineId===machine.id && r.port===target.port);
      if (!record) {
        const httpsPort = Array.from({length:8},(_,i)=>8444+i).find(p=>!this.records.some(r=>r.httpsPort===p) && !status.TCP?.[p] && !status.Web?.[`${host}:${p}`] && !status.AllowFunnel?.[`${host}:${p}`]);
        if (!httpsPort) throw fail('All eight private preview slots are in use. Remove an old preview on the controller before adding another.');
        record = {machineId:machine.id,port:target.port,httpsPort,localPort:19044+httpsPort-8444};
        // Persist the reservation before changing Tailscale, so retries recover it.
        this.records.push(record); this.save();
      }
      if (!Number.isInteger(record.httpsPort) || record.httpsPort<8444 || record.httpsPort>8451 || record.port!==target.port || record.localPort!==19044+record.httpsPort-8444) throw fail('The saved preview mapping is invalid.');
      const authority=`${host}:${record.httpsPort}`;
      const backend=`http://127.0.0.1:${record.localPort}`;
      const handlers=status.Web?.[authority]?.Handlers;
      if (status.AllowFunnel?.[authority] || ((status.TCP?.[record.httpsPort] || handlers) && (!status.TCP?.[record.httpsPort]?.HTTPS || !handlers || Object.keys(handlers).length!==1 || handlers['/']?.Proxy!==backend))) throw fail('This Tailscale port now belongs to another service. Existing services were left unchanged.');
      await this.tunnel(record,machine);
      await this.relay(record, machine);
      await this.reachable(record.localPort);
      if (machine.remote && !this.tunnels.has(record.httpsPort)) throw fail('The worker tunnel disconnected. Tap the link again to reconnect.');
      if (!handlers) await this.tailscale(['serve','--bg',`--https=${record.httpsPort}`,backend]);
      const confirmed=JSON.parse((await this.tailscale(['serve','status','--json'])).stdout || '{}');
      if (confirmed.Web?.[authority]?.Handlers?.['/']?.Proxy!==backend || confirmed.AllowFunnel?.[authority]) throw fail('The private preview route could not be verified.');
      return {url:`https://${authority}${target.suffix}`,machineName:machine.name};
    });
  }
  list() {
    const host = new URL(this.config.publicURL).hostname;
    return { previews: this.records.map(r => ({ id: r.httpsPort, url: `https://${host}:${r.httpsPort}/`, port: r.port, machineName: this.runtime.machines?.find(m => m.id === r.machineId)?.name || r.machineId })) };
  }
  async remove(port) {
    return this.runtime.locked('previews', async () => {
      const record = this.records.find(r => r.httpsPort === port); if (!record) return { removed: true };
      const host = new URL(this.config.publicURL).hostname;
      const status = JSON.parse((await this.tailscale(['serve', 'status', '--json'])).stdout || '{}');
      const handlers = status.Web?.[`${host}:${port}`]?.Handlers;
      if (status.TCP?.[port]) {
        if (!handlers || Object.keys(handlers).length !== 1 || handlers['/']?.Proxy !== `http://127.0.0.1:${record.localPort}`) throw fail('This port belongs to another service; it was left unchanged.');
        await this.tailscale(['serve', `--https=${port}`, 'off']);
      }
      this.tunnels.get(port)?.kill('SIGTERM'); this.tunnels.delete(port);
      const relay = this.relays.get(port); if (relay) { for (const socket of relay.sockets) socket.destroy(); relay.server.close(); this.relays.delete(port); }
      this.records = this.records.filter(r => r !== record); this.save(); return { removed: true };
    });
  }
  async restore() {
    if (this.invalid) return;
    const status = JSON.parse((await this.tailscale(['serve', 'status', '--json'])).stdout || '{}');
    const host = new URL(this.config.publicURL).hostname;
    for (const record of this.records) {
      const machine = this.runtime.machines.find(m => m.id === record.machineId);
      if (machine && status.Web?.[`${host}:${record.httpsPort}`]?.Handlers?.['/']?.Proxy === `http://127.0.0.1:${record.localPort}` && !status.AllowFunnel?.[`${host}:${record.httpsPort}`]) {
        try { await this.tunnel(record, machine); await this.relay(record, machine); } catch {}
      }
    }
  }
  close() { for (const relay of this.relays.values()) { for (const socket of relay.sockets) socket.destroy(); relay.server.close(); } this.relays.clear(); for (const child of this.tunnels.values()) child.kill('SIGTERM'); this.tunnels.clear(); }
}
