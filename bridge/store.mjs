import { DatabaseSync } from 'node:sqlite';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { chmodSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

export const digest = value => createHash('sha256').update(value).digest('hex');
export const now = () => Date.now() / 1000;
export const defaultPreferences = { attention: true, completion: true, connection: true, previews: false };

export class Store {
  constructor(path) {
    if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
    this.db = new DatabaseSync(path);
    if (path !== ':memory:') chmodSync(path, 0o600);
    this.db.exec(`
      PRAGMA journal_mode = WAL;
      CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, name TEXT NOT NULL, token_hash TEXT UNIQUE NOT NULL,
        created_at REAL NOT NULL, last_seen REAL NOT NULL, preferences TEXT NOT NULL, push_token TEXT, push_environment TEXT, read_through INTEGER NOT NULL DEFAULT 0);
      CREATE TABLE IF NOT EXISTS pairing (code_hash TEXT PRIMARY KEY, expires_at REAL NOT NULL);
      CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, agent_id TEXT, machine_id TEXT NOT NULL,
        title TEXT NOT NULL, body TEXT NOT NULL, created_at REAL NOT NULL);
      CREATE TABLE IF NOT EXISTS observations (id TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS operations (id TEXT PRIMARY KEY, device_id TEXT NOT NULL, fingerprint TEXT NOT NULL, state TEXT NOT NULL,
        result TEXT, created_at REAL NOT NULL);
      CREATE TABLE IF NOT EXISTS outbox (event_id INTEGER NOT NULL, device_id TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
        next_at REAL NOT NULL, last_error TEXT, PRIMARY KEY(event_id,device_id));
    `);
    // A process can die after a worker accepted input. Never replay an interrupted action.
    this.db.prepare("UPDATE operations SET state='uncertain' WHERE state='sending'").run();
  }
  pairCode() {
    const code = randomBytes(5).toString('hex').toUpperCase();
    this.db.prepare('DELETE FROM pairing WHERE expires_at < ?').run(now());
    this.db.prepare('INSERT INTO pairing VALUES (?,?)').run(digest(code), now() + 600);
    return { code, expiresAt: now() + 600 };
  }
  pair(code, name) {
    const row = this.db.prepare('DELETE FROM pairing WHERE code_hash=? AND expires_at>? RETURNING code_hash').get(digest(code.toUpperCase()), now());
    if (!row) return null;
    const token = randomBytes(32).toString('base64url');
    const id = randomUUID();
    this.db.prepare('INSERT INTO devices(id,name,token_hash,created_at,last_seen,preferences) VALUES (?,?,?,?,?,?)')
      .run(id, name, digest(token), now(), now(), JSON.stringify(defaultPreferences));
    return { deviceId: id, token };
  }
  authenticate(token) {
    if (!token || token.length > 256) return null;
    const row = this.db.prepare('SELECT * FROM devices WHERE token_hash=?').get(digest(token));
    if (row) this.db.prepare('UPDATE devices SET last_seen=? WHERE id=?').run(now(), row.id);
    return row;
  }
  devices() { return this.db.prepare('SELECT id,name,created_at,last_seen,push_token IS NOT NULL AS push_registered FROM devices').all(); }
  revoke(id) {
    this.db.prepare('DELETE FROM outbox WHERE device_id=?').run(id);
    this.db.prepare('DELETE FROM devices WHERE id=?').run(id);
  }
  preferences(device) { return { ...defaultPreferences, ...JSON.parse(device.preferences) }; }
  setPreferences(id, preferences) {
    this.db.prepare('UPDATE devices SET preferences=? WHERE id=?').run(JSON.stringify(preferences), id);
  }
  registerPush(id, token, environment) {
    this.db.prepare('UPDATE devices SET push_token=NULL WHERE push_token=? AND push_environment=? AND id<>?').run(token, environment, id);
    this.db.prepare('UPDATE devices SET push_token=?,push_environment=? WHERE id=?').run(token, environment, id);
  }
  events(device) {
    return this.db.prepare('SELECT * FROM events ORDER BY id DESC LIMIT 200').all().map(row => ({
      id: row.id, kind: row.kind, agentId: row.agent_id, machineId: row.machine_id, title: row.title,
      body: row.body, createdAt: row.created_at, read: row.id <= device.read_through
    }));
  }
  markRead(id, through) { this.db.prepare('UPDATE devices SET read_through=MAX(read_through,?) WHERE id=?').run(through, id); }
  addEvent({ kind, agentId = null, machineId, title, body }) {
    const createdAt = now();
    const result = this.db.prepare('INSERT INTO events(kind,agent_id,machine_id,title,body,created_at) VALUES (?,?,?,?,?,?)')
      .run(kind, agentId, machineId, title, body, createdAt);
    const id = Number(result.lastInsertRowid);
    for (const device of this.db.prepare('SELECT * FROM devices WHERE push_token IS NOT NULL').all()) {
      if (this.preferences(device)[kind]) this.db.prepare('INSERT OR IGNORE INTO outbox(event_id,device_id,next_at) VALUES (?,?,?)').run(id, device.id, createdAt);
    }
    return id;
  }
  observe(id, value) {
    const previous = this.db.prepare('SELECT value FROM observations WHERE id=?').get(id)?.value;
    this.db.prepare('INSERT INTO observations VALUES (?,?) ON CONFLICT(id) DO UPDATE SET value=excluded.value').run(id, value);
    return previous;
  }
  beginOperation(id, deviceId, payload) {
    const fingerprint = digest(JSON.stringify(payload));
    const prior = this.db.prepare('SELECT * FROM operations WHERE id=?').get(id);
    if (prior) {
      if (prior.device_id !== deviceId || prior.fingerprint !== fingerprint) throw new Error('Request ID already belongs to a different action.');
      return this.operation(id, deviceId);
    }
    this.db.prepare('INSERT INTO operations(id,device_id,fingerprint,state,created_at) VALUES (?,?,?,?,?)').run(id, deviceId, fingerprint, 'sending', now());
    return null;
  }
  finishOperation(id, state, result) {
    this.db.prepare('UPDATE operations SET state=?,result=? WHERE id=?').run(state, JSON.stringify(result), id);
  }
  operation(id, deviceId) {
    const row = this.db.prepare('SELECT * FROM operations WHERE id=? AND device_id=?').get(id, deviceId);
    return row ? { id, state: row.state, result: row.result ? JSON.parse(row.result) : null } : null;
  }
  close() { this.db.close(); }
}
