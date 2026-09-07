import { createHash } from 'node:crypto';
import { mkdir, readFile, writeFile, rename, readdir, stat } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { execFile } from 'node:child_process';
import { RuntimeError, cleanEnvironment } from './runtime.mjs';

export const imageLimit = 3 * 1024 * 1024;
const hash = value => createHash('sha256').update(value).digest('hex');
const invalid = message => new RuntimeError(message, 'invalid_attachment');
export function decodeImage(body) {
  if (!['image/jpeg', 'image/png'].includes(body.contentType) || typeof body.data !== 'string' || body.data.length > Math.ceil(imageLimit / 3) * 4 || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(body.data)) throw invalid('Choose a JPEG or PNG image up to 3 MB.');
  const bytes = Buffer.from(body.data, 'base64');
  const valid = body.contentType === 'image/png' ? bytes.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex')) : bytes[0] === 255 && bytes[1] === 216 && bytes[2] === 255;
  if (!valid || bytes.length < 16 || bytes.length > imageLimit) throw invalid('This file is not a supported image.');
  return bytes;
}

// Only a fixed file receiver is exposed. The SSH target comes from Herdr's saved
// machine list, never from the HTTP body; filenames are controller-owned hashes.
export function receiveWindows(target, id, extension, bytes) {
  if (!/^[A-Za-z0-9_][A-Za-z0-9_.@:-]*$/.test(target)) throw invalid('This worker needs a supported SSH alias before receiving photos.');
  const script = `$ErrorActionPreference='Stop'; $p=[Console]::In.ReadToEnd() | ConvertFrom-Json; $root=Join-Path $env:LOCALAPPDATA 'HerdrShared\\attachments'; [IO.Directory]::CreateDirectory($root) | Out-Null; $file=Join-Path $root ($p.id+'.'+$p.ext); $bytes=[Convert]::FromBase64String($p.data); $tmp=$file+'.upload'; [IO.File]::WriteAllBytes($tmp,$bytes); Move-Item -LiteralPath $tmp -Destination $file -Force; $sha=[Security.Cryptography.SHA256]::Create(); $digest=([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($file)))).Replace('-','').ToLower(); @{path=$file;sha256=$digest} | ConvertTo-Json -Compress`;
  return new Promise((resolve, reject) => {
    const child = execFile('/usr/bin/ssh', ['-T', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', target, 'powershell.exe', '-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(script, 'utf16le').toString('base64')], { env: cleanEnvironment(), timeout: 45000, maxBuffer: 16000 }, (error, stdout) => {
      if (error) return reject(invalid('Photo upload could not be confirmed. Retry the upload; no terminal input was sent.'));
      try { const result = JSON.parse(stdout.trim()); if (result.sha256 !== hash(bytes) || typeof result.path !== 'string' || !/^[A-Za-z]:\\/.test(result.path) || /[\r\n\0]/.test(result.path)) throw new Error(); resolve(result.path); }
      catch { reject(invalid('The worker could not verify the photo. No terminal input was sent.')); }
    });
    child.stdin.on('error', () => {});
    child.stdin.end(JSON.stringify({ id, ext: extension, data: bytes.toString('base64') }));
  });
}

export class Attachments {
  constructor(config, runtime, transfer = receiveWindows) {
    this.root = config.attachmentPath || join(dirname(config.databasePath), 'attachments');
    this.runtime = runtime; this.transfer = transfer;
  }
  async upload(deviceId, agentId, body) {
    const bytes = decodeImage(body);
    return this.runtime.locked('attachments', async () => {
      const { agent, machine } = await this.runtime.resolve(agentId);
      if (!['codex', 'claude'].includes(agent.kind)) throw invalid('Photo messages currently support Codex and Claude sessions.');
      const id = hash(`${deviceId}\0${agentId}\0${hash(bytes)}`);
      const extension = body.contentType === 'image/png' ? 'png' : 'jpg';
      await mkdir(this.root, { recursive: true, mode: 0o700 });
      const file = join(this.root, `${id}.${extension}`);
      let total = 0;
      for (const entry of await readdir(this.root)) if (/^[a-f0-9]{64}\.(jpg|png)$/.test(entry)) total += (await stat(join(this.root, entry))).size;
      // Bound retained storage. Re-uploading an existing image remains possible at the limit.
      let exists = false; try { exists = (await stat(file)).isFile(); } catch {}
      if (!exists && total + bytes.length > 100 * 1024 * 1024) throw invalid('Photo storage is full. Remove old Herdr attachments on the controller and worker before uploading more.');
      await writeFile(file, bytes, { mode: 0o600 });
      const path = machine.remote ? await this.transfer(machine.target, id, extension, bytes) : file;
      const record = { id, deviceId, agentId, kind: agent.kind, path, contentType: body.contentType, size: bytes.length };
      const metadata = join(this.root, `${id}.json`);
      await writeFile(`${metadata}.tmp`, JSON.stringify(record), { mode: 0o600 });
      await rename(`${metadata}.tmp`, metadata);
      return { id, contentType: record.contentType, size: record.size, machineName: machine.name };
    });
  }
  async paths(deviceId, agentId, ids) {
    const paths = [];
    for (const id of ids || []) {
      if (!/^[a-f0-9]{64}$/.test(id)) throw invalid('Invalid photo attachment.');
      let record; try { record = JSON.parse(await readFile(join(this.root, `${id}.json`), 'utf8')); } catch { throw invalid('This photo is unavailable. Attach it again.'); }
      if (record.deviceId !== deviceId || record.agentId !== agentId) throw invalid('This photo belongs to another device or session. Attach it again here.');
      paths.push(record.path);
    }
    return paths;
  }
}
