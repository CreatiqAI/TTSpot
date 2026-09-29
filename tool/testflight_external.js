// Sends a TestFlight build to the external "Beta testers" group (the public
// link) and submits it for Beta App Review. Internal testers ("Team") get
// every build on their own; external testers only get builds that are added
// to their group and approved by Apple.
//
//   node tool/testflight_external.js <build number>
//
// Env: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_P8 (the .p8 contents). Locally,
// ASC_KEY_P8_PATH can point at the file instead. Waits up to 45 min for the
// build to finish processing, puts the newest block of
// lib/core/config/release_notes.dart into "What to Test", and is safe to
// re-run (skips what is already done).
const crypto = require('crypto');
const fs = require('fs');
const https = require('https');
const path = require('path');

const APP = '6815672400';
const GROUP = 'Beta testers';
const build = process.argv[2];
if (!/^\d+$/.test(build || '')) {
  console.error('usage: node tool/testflight_external.js <build number>');
  process.exit(2);
}
const KEY_ID = process.env.ASC_KEY_ID;
const ISSUER = process.env.ASC_ISSUER_ID;
const P8 = process.env.ASC_KEY_P8 || (process.env.ASC_KEY_P8_PATH && fs.readFileSync(process.env.ASC_KEY_P8_PATH, 'utf8'));
if (!KEY_ID || !ISSUER || !P8) {
  console.error('ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 (or ASC_KEY_P8_PATH) are required');
  process.exit(2);
}

// A fresh token per request: the processing wait outlives one token (20 min max).
function token() {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const head = b64({ alg: 'ES256', kid: KEY_ID, typ: 'JWT' });
  const body = b64({ iss: ISSUER, iat: now, exp: now + 1100, aud: 'appstoreconnect-v1' });
  const sig = crypto.sign('sha256', Buffer.from(`${head}.${body}`), { key: P8, dsaEncoding: 'ieee-p1363' }).toString('base64url');
  return `${head}.${body}.${sig}`;
}

function api(method, p, data) {
  return new Promise((resolve, reject) => {
    const req = https.request(
      { host: 'api.appstoreconnect.apple.com', path: p, method, headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' } },
      (res) => {
        let d = '';
        res.on('data', (c) => (d += c));
        res.on('end', () => {
          const j = d ? JSON.parse(d) : {};
          if (res.statusCode >= 400) {
            const err = new Error(`${method} ${p} ${res.statusCode}: ${(j.errors || []).map((e) => e.detail || e.title).join('; ')}`);
            err.status = res.statusCode;
            reject(err);
          } else resolve(j);
        });
      },
    );
    req.on('error', reject);
    if (data) req.write(JSON.stringify({ data }));
    req.end();
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/// Title and points of the newest ReleaseNote, as TestFlight's "What to Test".
function whatsNew() {
  const src = fs.readFileSync(path.join(__dirname, '..', 'lib', 'core', 'config', 'release_notes.dart'), 'utf8');
  const first = src.slice(src.indexOf('ReleaseNote('), src.indexOf('),', src.indexOf('points:')));
  const title = (first.match(/title:\s*'((?:\\'|[^'])*)'/) || [])[1] || '';
  const points = [...first.slice(first.indexOf('points:')).matchAll(/'((?:\\'|[^'])*)'/g)].map((m) => m[1]);
  const text = [title, ...points.map((p) => `• ${p}`)].join('\n').replace(/\\'/g, "'");
  return text.slice(0, 3900) || 'Bug fixes and improvements.';
}

(async () => {
  // 1. Wait for the build to finish processing.
  let b;
  for (let i = 0; i < 45; i++) {
    const r = await api('GET', `/v1/builds?filter[app]=${APP}&filter[version]=${build}&limit=1&fields[builds]=version,processingState`);
    b = r.data[0];
    const state = b?.attributes.processingState;
    if (state === 'VALID') break;
    if (state === 'FAILED' || state === 'INVALID') throw new Error(`build ${build} is ${state}`);
    console.log(`build ${build}: ${state || 'not in App Store Connect yet'}, waiting…`);
    b = null;
    await sleep(60000);
  }
  if (!b) throw new Error(`build ${build} did not finish processing in 45 min`);
  console.log(`build ${build} is ready`);

  // 2. What to Test.
  const text = whatsNew();
  const locs = await api('GET', `/v1/builds/${b.id}/betaBuildLocalizations`);
  const en = (locs.data || []).find((l) => l.attributes.locale.startsWith('en'));
  if (en) await api('PATCH', `/v1/betaBuildLocalizations/${en.id}`, { type: 'betaBuildLocalizations', id: en.id, attributes: { whatsNew: text } });
  else await api('POST', '/v1/betaBuildLocalizations', { type: 'betaBuildLocalizations', attributes: { locale: 'en-US', whatsNew: text }, relationships: { build: { data: { type: 'builds', id: b.id } } } });
  console.log('what to test:\n' + text);

  // 3. Add to the external group.
  const groups = await api('GET', `/v1/betaGroups?filter[app]=${APP}&fields[betaGroups]=name,isInternalGroup`);
  const group = groups.data.find((g) => !g.attributes.isInternalGroup && g.attributes.name === GROUP);
  if (!group) throw new Error(`external group "${GROUP}" not found`);
  await api('POST', `/v1/betaGroups/${group.id}/relationships/builds`, [{ type: 'builds', id: b.id }]);
  console.log(`added to "${GROUP}"`);

  // 4. Submit for Beta App Review (Apple approves each new version for external testers).
  try {
    const sub = await api('POST', '/v1/betaAppReviewSubmissions', { type: 'betaAppReviewSubmissions', relationships: { build: { data: { type: 'builds', id: b.id } } } });
    console.log(`submitted for beta review: ${sub.data.attributes.betaReviewState}`);
  } catch (e) {
    // 409: already submitted, or approved without review (same version as an approved build).
    if (e.status === 409) console.log(`not submitted: ${e.message}`);
    else throw e;
  }
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
