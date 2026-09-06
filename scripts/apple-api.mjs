import { readFileSync } from 'node:fs';
import { sign } from 'node:crypto';
import { homedir } from 'node:os';
import { pathToFileURL } from 'node:url';

export async function appleAPI(path, { method = 'GET', body } = {}) {
  const keyID = process.env.APP_STORE_CONNECT_KEY_ID || 'Y3JLHLYZD5';
  const issuer = process.env.APP_STORE_CONNECT_ISSUER_ID || 'e570c4cf-e394-458c-8cbd-1c2cba6a400f';
  const keyPath = process.env.APP_STORE_CONNECT_KEY_PATH || `${homedir()}/.appstoreconnect/private_keys/AuthKey_${keyID}.p8`;
  const now = Math.floor(Date.now() / 1000);
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const input = `${encode({ alg: 'ES256', kid: keyID, typ: 'JWT' })}.${encode({ iss: issuer, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' })}`;
  const signature = sign('sha256', Buffer.from(input), { key: readFileSync(keyPath), dsaEncoding: 'ieee-p1363' }).toString('base64url');
  const response = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method, headers: { Authorization: `Bearer ${input}.${signature}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined, signal: AbortSignal.timeout(30000)
  });
  const text = await response.text();
  const data = text ? JSON.parse(text) : null;
  if (!response.ok) throw new Error(`Apple API ${response.status}: ${JSON.stringify(data?.errors || data)}`);
  return data;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const [, , path, method = 'GET', bodyFile] = process.argv;
  if (!path?.startsWith('/v1/') && !path?.startsWith('/v2/')) throw new Error('Provide a /v1/ or /v2/ path.');
  const data = await appleAPI(path, { method, body: bodyFile ? JSON.parse(readFileSync(bodyFile, 'utf8')) : undefined });
  console.log(JSON.stringify(data, null, 2));
}
