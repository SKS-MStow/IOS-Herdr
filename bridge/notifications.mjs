import { connect } from 'node:http2';
import { readFileSync, existsSync } from 'node:fs';
import { sign } from 'node:crypto';
import { now } from './store.mjs';

export class Notifications {
  constructor(config, store) { this.config = config; this.store = store; this.sending = false; this.lastError = null; }
  get configured() { const c = this.config.apns; return Boolean(c?.keyPath && c.keyId && c.teamId && existsSync(c.keyPath)); }
  status() { return { configured: this.configured, lastError: this.lastError, topic: this.config.apns?.topic || 'xyz.verdalecres.herdr' }; }
  async send(token, environment, payload, collapseId) {
    if (!this.configured) throw new Error('APNs signing key has not been configured on the Mac.');
    const { keyPath, keyId, teamId, topic } = this.config.apns;
    const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
    const input = `${encode({ alg: 'ES256', kid: keyId })}.${encode({ iss: teamId, iat: Math.floor(now()) })}`;
    const signature = sign('sha256', Buffer.from(input), { key: readFileSync(keyPath), dsaEncoding: 'ieee-p1363' }).toString('base64url');
    const host = environment === 'sandbox' ? 'https://api.sandbox.push.apple.com' : 'https://api.push.apple.com';
    return new Promise((resolve, reject) => {
      const client = connect(host);
      const timer = setTimeout(() => { client.destroy(); reject(new Error('APNs response timed out.')); }, 15000);
      const finish = (error, value) => { clearTimeout(timer); client.close(); error ? reject(error) : resolve(value); };
      client.on('error', error => finish(error));
      const req = client.request({ ':method': 'POST', ':path': `/3/device/${token}`, authorization: `bearer ${input}.${signature}`,
        'apns-topic': topic, 'apns-push-type': 'alert', 'apns-priority': '10', 'apns-expiration': String(Math.floor(now()) + 3600), 'apns-collapse-id': collapseId });
      let status; let apnsId; let text = '';
      req.on('response', headers => { status = headers[':status']; apnsId = headers['apns-id']; });
      req.setEncoding('utf8'); req.on('data', data => { text += data; });
      req.on('error', error => finish(error));
      req.on('end', () => {
        if (status === 200) return finish(null, { accepted: true, apnsId });
        let reason = 'Rejected'; try { reason = JSON.parse(text).reason; } catch {}
        const error = new Error(`APNs ${status}: ${reason}`); error.status = status; error.reason = reason; finish(error);
      });
      req.end(JSON.stringify(payload));
    });
  }
  async drain() {
    if (!this.configured || this.sending) return;
    this.sending = true;
    try {
      const rows = this.store.db.prepare(`SELECT o.*,d.push_token,d.push_environment,d.preferences,e.kind,e.title,e.body,e.agent_id,e.machine_id,e.created_at
        FROM outbox o JOIN devices d ON d.id=o.device_id JOIN events e ON e.id=o.event_id WHERE next_at<=? LIMIT 10`).all(now());
      for (const row of rows) {
        if (now() - row.created_at > 3600 || !row.push_token) { this.remove(row); continue; }
        const preferences = JSON.parse(row.preferences);
        if (!preferences[row.kind]) { this.remove(row); continue; }
        const payload = { aps: { alert: { title: row.title, body: preferences.previews ? row.body : 'Open Herdr to review the latest activity.' }, sound: 'default', 'thread-id': 'herdr-activity' }, agentId: row.agent_id, machineId: row.machine_id, eventId: row.event_id };
        try {
          await this.send(row.push_token, row.push_environment, payload, `herdr-${row.event_id}`);
          this.remove(row); this.lastError = null;
        } catch (error) {
          this.lastError = error.message;
          if (error.status === 410 || error.reason === 'BadDeviceToken' || error.reason === 'DeviceTokenNotForTopic') {
            this.store.db.prepare('UPDATE devices SET push_token=NULL WHERE id=?').run(row.device_id); this.remove(row);
          } else if ((error.status && error.status < 500 && error.status !== 429) || row.attempts >= 5) this.remove(row);
          else this.store.db.prepare('UPDATE outbox SET attempts=attempts+1,next_at=?,last_error=? WHERE event_id=? AND device_id=?')
            .run(now() + Math.min(300, 10 * 2 ** row.attempts), error.message, row.event_id, row.device_id);
        }
      }
    } finally { this.sending = false; }
  }
  remove(row) { this.store.db.prepare('DELETE FROM outbox WHERE event_id=? AND device_id=?').run(row.event_id, row.device_id); }
}
