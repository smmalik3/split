// Split — backend: Express + libSQL (Turso hosted, or local file) + tesseract.js OCR.
// Serves the Flutter web build, the REST API, and receipt images.
// Guest use needs no account. Optional Google login (server-side OAuth
// redirect flow) is configured with GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET
// env vars; without them the auth endpoints 503 and guests are unaffected.
// DB config comes from env; without it, a local file DB
// in data/ is used so local dev keeps working unchanged.
// Receipt photos are stored as BLOBs in the database (Render's free tier has
// an ephemeral filesystem, so on-disk uploads would vanish on restart).

const express = require('express');
const multer = require('multer');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const fs = require('fs');
const { createClient } = require('@libsql/client');
const { createWorker } = require('tesseract.js');

const PORT = process.env.PORT || 8787;
const ROOT = path.join(__dirname, '..');
const DATA_DIR = path.join(ROOT, 'data');
// OCR language data: overridable so a Docker image can bake the cache in
// outside the persistent-volume mount (a mount at /app/data would shadow
// anything baked into the image under /app/data).
const TESS_CACHE = process.env.TESSERACT_CACHE || path.join(DATA_DIR, 'tesseract-cache');
const DB_PATH = path.join(DATA_DIR, 'db', 'split.db');
const WEB_DIR = path.join(ROOT, 'build', 'web');

// ---- database ----
// Production (Render): TURSO_DATABASE_URL=libsql://<db>.turso.io, TURSO_AUTH_TOKEN=...
// Local dev: env unset -> local SQLite file (same file the old node:sqlite
// server used, so existing local data keeps working).
const TURSO_URL = process.env.TURSO_DATABASE_URL;
const TURSO_TOKEN = process.env.TURSO_AUTH_TOKEN;
const db = TURSO_URL
  ? createClient({ url: TURSO_URL, authToken: TURSO_TOKEN })
  : createClient({ url: 'file:' + DB_PATH });

if (!TURSO_URL) fs.mkdirSync(path.dirname(DB_PATH), { recursive: true });

const SCHEMA = `
  CREATE TABLE IF NOT EXISTS groups (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    code TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE TABLE IF NOT EXISTS members (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    group_id INTEGER NOT NULL REFERENCES groups(id),
    nickname TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(group_id, nickname)
  );
  CREATE TABLE IF NOT EXISTS expenses (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    group_id INTEGER NOT NULL REFERENCES groups(id),
    member_id INTEGER NOT NULL REFERENCES members(id),
    merchant TEXT NOT NULL DEFAULT 'Expense',
    total_cents INTEGER NOT NULL,
    note TEXT NOT NULL DEFAULT '',
    receipt TEXT,
    expense_date TEXT NOT NULL DEFAULT (date('now')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE TABLE IF NOT EXISTS receipts (
    filename TEXT PRIMARY KEY,
    data BLOB NOT NULL,
    mime TEXT NOT NULL DEFAULT 'image/jpeg',
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE TABLE IF NOT EXISTS settlements (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    group_code TEXT NOT NULL,
    from_member_id INTEGER NOT NULL,
    to_member_id INTEGER NOT NULL,
    amount REAL NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE TABLE IF NOT EXISTS nudges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    group_code TEXT NOT NULL,
    from_member_id INTEGER NOT NULL,
    to_member_id INTEGER NOT NULL,
    amount REAL NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE TABLE IF NOT EXISTS users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    google_sub TEXT UNIQUE NOT NULL,
    email TEXT,
    name TEXT,
    picture_url TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE TABLE IF NOT EXISTS sessions (
    token TEXT PRIMARY KEY,
    user_id INTEGER NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at TEXT NOT NULL
  );
`;

// Columns added after the initial schema landed (expenses split/tax/tip,
// member payment handles). ALTER TABLE is guarded: re-running the server
// must never error if a column already exists.
async function ensureColumn(table, column, definition) {
  try {
    const cols = await qAll(`PRAGMA table_info(${table})`);
    if (cols.some(c => c.name === column)) return;
  } catch (e) {
    // PRAGMA unsupported on this driver — fall through to the ALTER attempt.
  }
  try {
    await qRun(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
  } catch (e) {
    if (!/duplicate column/i.test(e.message || '')) throw e;
  }
}
async function runMigrations() {
  await ensureColumn('expenses', 'split_mode', "TEXT NOT NULL DEFAULT 'equal'");
  await ensureColumn('expenses', 'split_data', 'TEXT');
  await ensureColumn('expenses', 'tax', 'REAL NOT NULL DEFAULT 0');
  await ensureColumn('expenses', 'tip', 'REAL NOT NULL DEFAULT 0');
  await ensureColumn('members', 'venmo_handle', 'TEXT');
  await ensureColumn('members', 'cashapp_handle', 'TEXT');
  await ensureColumn('members', 'user_id', 'INTEGER');
}

// ---- tiny query helpers (libSQL is async; rows come back as objects) ----
async function qAll(sql, args = []) {
  const r = await db.execute(sql, args);
  return r.rows;
}
async function qGet(sql, args = []) {
  const r = await db.execute(sql, args);
  return r.rows[0];
}
async function qRun(sql, args = []) {
  return db.execute(sql, args);
}
// BLOBs come back as ArrayBuffer (local file mode) or Uint8Array / base64
// string (remote mode) depending on the driver — normalize to a Buffer.
function toBuffer(v) {
  if (Buffer.isBuffer(v)) return v;
  if (v instanceof Uint8Array) return Buffer.from(v);
  if (v instanceof ArrayBuffer) return Buffer.from(v);
  if (typeof v === 'string') return Buffer.from(v, 'base64');
  return Buffer.from(v);
}

const app = express();
app.set('trust proxy', true); // behind Render's proxy, req.protocol honors X-Forwarded-Proto
app.use(express.json({ limit: '2mb' }));

// ---- helpers ----
const CODE_CHARS = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
function makeCode() {
  let code = '';
  for (let i = 0; i < 6; i++) code += CODE_CHARS[Math.floor(Math.random() * CODE_CHARS.length)];
  return code;
}
function cents(n) { return Math.round(Number(n) * 100); }
function dollars(c) { return (c / 100).toFixed(2); }

async function getGroup(code) {
  return qGet('SELECT * FROM groups WHERE code = ?', [String(code).toUpperCase()]);
}
// split_data is stored as a JSON string; the API returns the parsed
// object (or null), never the raw string.
function parseSplitData(v) {
  if (v == null) return null;
  if (typeof v === 'object') return v;
  try { return JSON.parse(v); } catch { return null; }
}
function memberJson(m) {
  return {
    id: m.id, nickname: m.nickname,
    venmo_handle: m.venmo_handle ?? null,
    cashapp_handle: m.cashapp_handle ?? null,
    created_at: m.created_at,
  };
}
function transferJson(row) {
  return {
    id: row.id,
    from_member_id: row.from_member_id,
    to_member_id: row.to_member_id,
    amount: Number(row.amount),
    created_at: row.created_at,
  };
}
async function groupPayload(group) {
  const members = await qAll('SELECT id, nickname, venmo_handle, cashapp_handle, created_at FROM members WHERE group_id = ? ORDER BY id', [group.id]);
  const expenses = await qAll(`
    SELECT e.*, m.nickname AS payer
    FROM expenses e JOIN members m ON m.id = e.member_id
    WHERE e.group_id = ? ORDER BY e.expense_date DESC, e.id DESC`, [group.id]);
  const settlements = await qAll('SELECT * FROM settlements WHERE group_code = ? ORDER BY id DESC', [group.code]);
  const nudges = await qAll('SELECT * FROM nudges WHERE group_code = ? ORDER BY id DESC', [group.code]);
  const totalCents = expenses.reduce((s, e) => s + e.total_cents, 0);
  return {
    code: group.code,
    name: group.name,
    created_at: group.created_at,
    members: members.map(memberJson),
    expenses: expenses.map(e => ({
      id: e.id, merchant: e.merchant, total: dollars(e.total_cents),
      total_cents: e.total_cents, note: e.note, receipt: e.receipt,
      date: e.expense_date, payer: e.payer, payer_id: e.member_id,
      split_mode: e.split_mode || 'equal',
      split_data: parseSplitData(e.split_data),
      tax: e.tax == null ? 0 : Number(e.tax),
      tip: e.tip == null ? 0 : Number(e.tip),
      created_at: e.created_at,
    })),
    settlements: settlements.map(transferJson),
    nudges: nudges.map(transferJson),
    total: dollars(totalCents),
    total_cents: totalCents,
  };
}

async function computeBalances(group) {
  const members = await qAll('SELECT id, nickname FROM members WHERE group_id = ? ORDER BY id', [group.id]);
  const expenses = await qAll('SELECT member_id, total_cents FROM expenses WHERE group_id = ?', [group.id]);
  const total = expenses.reduce((s, e) => s + e.total_cents, 0);
  const n = Math.max(members.length, 1);
  const share = Math.floor(total / n);
  const remainder = total - share * n; // distribute leftover cents to first members
  const paid = Object.fromEntries(members.map(m => [m.id, 0]));
  for (const e of expenses) paid[e.member_id] = (paid[e.member_id] || 0) + e.total_cents;
  const rows = members.map((m, i) => {
    const myShare = share + (i < remainder ? 1 : 0);
    return { member_id: m.id, nickname: m.nickname, paid_cents: paid[m.id] || 0, share_cents: myShare, net_cents: (paid[m.id] || 0) - myShare };
  });
  // Minimal settle-up: debtors pay creditors (greedy).
  const creditors = rows.filter(r => r.net_cents > 0).map(r => ({ ...r })).sort((a, b) => b.net_cents - a.net_cents);
  const debtors = rows.filter(r => r.net_cents < 0).map(r => ({ ...r })).sort((a, b) => a.net_cents - b.net_cents);
  const transfers = [];
  let ci = 0, di = 0;
  while (ci < creditors.length && di < debtors.length) {
    const c = creditors[ci], d = debtors[di];
    const amt = Math.min(c.net_cents, -d.net_cents);
    transfers.push({ from: d.nickname, from_id: d.member_id, to: c.nickname, to_id: c.member_id, amount_cents: amt, amount: dollars(amt) });
    c.net_cents -= amt; d.net_cents += amt;
    if (c.net_cents === 0) ci++;
    if (d.net_cents === 0) di++;
  }
  return {
    total_cents: total,
    total: dollars(total),
    member_count: members.length,
    share_cents: share,
    balances: rows.map(r => ({ ...r, paid: dollars(r.paid_cents), share: dollars(r.share_cents), net: dollars(r.net_cents) })),
    transfers,
  };
}

// ---- OCR ----
let ocrWorker = null;
async function getWorker() {
  if (ocrWorker) return ocrWorker;
  ocrWorker = await createWorker('eng', 1, {
    cachePath: TESS_CACHE,
    // Language data is pre-downloaded locally; the CDN fetch hangs in this
    // environment, so point the worker at the local copy.
    langPath: TESS_CACHE,
    logger: () => {},
  });
  return ocrWorker;
}

// Parse OCR text into merchant / total / date / items.
function parseReceipt(text) {
  const lines = text.split('\n').map(l => l.trim()).filter(Boolean);
  const moneyRe = /\$?\s?(\d{1,3}(?:,\d{3})*\.\d{2})\b/g;
  const amounts = [];
  lines.forEach((line, idx) => {
    let m;
    while ((m = moneyRe.exec(line)) !== null) {
      amounts.push({ value: parseFloat(m[1].replace(/,/g, '')), line: idx, text: line });
    }
  });
  // Merchant: first line that looks like a name (no digits, decent length).
  let merchant = '';
  for (const line of lines.slice(0, 4)) {
    const clean = line.replace(/[^A-Za-z0-9 &'.-]/g, '').trim();
    if (clean.length >= 3 && !/\d/.test(clean)) { merchant = clean; break; }
  }
  if (!merchant && lines.length) merchant = lines[0].slice(0, 40);
  // Total: prefer a line labelled TOTAL / AMOUNT DUE / BALANCE / GRAND TOTAL.
  let total = null;
  const totalLabel = /total|amount due|balance due|amount payable|grand total|to pay|please pay/i;
  for (const a of amounts) {
    if (totalLabel.test(a.text)) total = a.value;
  }
  if (total === null && amounts.length) {
    // Else the largest amount in the bottom third of the receipt.
    const bottomStart = Math.floor(lines.length * 0.66);
    const bottom = amounts.filter(a => a.line >= bottomStart);
    const pool = bottom.length ? bottom : amounts;
    total = Math.max(...pool.map(a => a.value));
  }
  // Date: common formats.
  let date = '';
  const dateRe = /(\d{1,2}[\/\-.]\d{1,2}[\/\-.]\d{2,4})|((?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+\d{1,2},?\s+\d{2,4})/i;
  for (const line of lines) {
    const m = line.match(dateRe);
    if (m) { date = m[0]; break; }
  }
  // Items: lines ending in a price that are not total/tax/tip/subtotal lines.
  const skipRe = /total|subtotal|tax|tip|gratuity|change|cash|card|visa|mastercard|balance|amount due/i;
  const items = [];
  for (const a of amounts) {
    const line = a.text;
    if (skipRe.test(line)) continue;
    const name = line.replace(moneyRe, '').replace(/[^A-Za-z0-9 &'.-]+/g, ' ').trim();
    if (name.length >= 2) items.push({ name: name.slice(0, 60), price: a.value });
  }
  return { merchant, total, date, items: items.slice(0, 30), rawText: text };
}

// ---- API ----
app.get('/api/health', (req, res) => res.json({ ok: true, app: 'Split' }));

// ---- Google auth (optional) ----
// Login is optional: guests keep working exactly as before. The flow is
// the server-side OAuth redirect flow — no client secret ever leaves the
// server. Config comes from env; without it the auth endpoints 503.
// The redirect URI is derived from the incoming request so the same code
// works on Render and localhost (both URIs must be registered in Google
// Cloud Console).
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID;
const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET;
const OAUTH_STATE_COOKIE = 'oauth_state';

function googleConfigured() {
  return Boolean(GOOGLE_CLIENT_ID && GOOGLE_CLIENT_SECRET);
}
function appOrigin(req) {
  return `${req.protocol}://${req.get('host')}`;
}
function googleRedirectUri(req) {
  return `${appOrigin(req)}/api/auth/google/callback`;
}
function parseCookies(req) {
  const out = {};
  const header = req.get('cookie');
  if (!header) return out;
  for (const part of header.split(';')) {
    const i = part.indexOf('=');
    if (i < 0) continue;
    out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  }
  return out;
}
// 'YYYY-MM-DD HH:MM:SS' — the same format as SQLite's datetime('now'),
// so string comparison against expires_at works.
function sqliteDate(d) {
  return d.toISOString().slice(0, 19).replace('T', ' ');
}
async function createSession(userId) {
  const token = crypto.randomBytes(32).toString('hex');
  const expires = sqliteDate(new Date(Date.now() + 30 * 24 * 60 * 60 * 1000));
  await qRun('INSERT INTO sessions (token, user_id, expires_at) VALUES (?, ?, ?)', [token, userId, expires]);
  return token;
}
function userJson(u) {
  return { id: u.id, email: u.email ?? null, name: u.name ?? null, picture_url: u.picture_url ?? null };
}

// Optional auth: a valid Bearer session attaches req.user; a missing or
// bad token is ignored (guests keep working).
async function optionalAuth(req, res, next) {
  try {
    const header = req.get('authorization') || '';
    const m = header.match(/^Bearer\s+(.+)$/i);
    if (!m) return next();
    const row = await qGet(
      `SELECT u.id, u.google_sub, u.email, u.name, u.picture_url
       FROM sessions s JOIN users u ON u.id = s.user_id
       WHERE s.token = ? AND s.expires_at > datetime('now')`,
      [m[1]]);
    if (row) req.user = { id: row.id, google_sub: row.google_sub, email: row.email, name: row.name, picture_url: row.picture_url };
  } catch (e) {
    console.error('optionalAuth error:', e.message);
  }
  next();
}
function requireAuth(req, res, next) {
  if (!req.user) return res.status(401).json({ error: 'Login required' });
  next();
}

// Step 1: redirect the browser to Google's consent screen.
app.get('/api/auth/google/start', (req, res) => {
  if (!googleConfigured()) return res.status(503).json({ error: 'Google login is not configured' });
  const state = crypto.randomBytes(16).toString('hex');
  const url = new URL('https://accounts.google.com/o/oauth2/v2/auth');
  url.searchParams.set('client_id', GOOGLE_CLIENT_ID);
  url.searchParams.set('redirect_uri', googleRedirectUri(req));
  url.searchParams.set('response_type', 'code');
  url.searchParams.set('scope', 'openid email profile');
  url.searchParams.set('prompt', 'select_account');
  url.searchParams.set('state', state);
  const cookie = [
    `${OAUTH_STATE_COOKIE}=${state}`,
    'HttpOnly',
    'Max-Age=600',
    'SameSite=Lax',
    'Path=/api/auth',
    ...(req.protocol === 'https' ? ['Secure'] : []),
  ].join('; ');
  res.set('Set-Cookie', cookie);
  res.redirect(302, url.toString());
});

// Step 2: Google redirects back here with ?code=&state=.
app.get('/api/auth/google/callback', async (req, res) => {
  const origin = appOrigin(req);
  const fail = () => res.redirect(302, `${origin}/?auth_error=1`);
  const cookies = parseCookies(req);
  const expectedState = cookies[OAUTH_STATE_COOKIE];
  // Clear the state cookie either way.
  res.set('Set-Cookie', `${OAUTH_STATE_COOKIE}=; HttpOnly; Max-Age=0; SameSite=Lax; Path=/api/auth`);
  const { code, state } = req.query || {};
  if (!expectedState || !state || state !== expectedState) {
    return res.status(400).json({ error: 'Invalid or missing OAuth state' });
  }
  if (!code) return fail();
  if (!googleConfigured()) return fail();
  try {
    const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code: String(code),
        client_id: GOOGLE_CLIENT_ID,
        client_secret: GOOGLE_CLIENT_SECRET,
        redirect_uri: googleRedirectUri(req),
        grant_type: 'authorization_code',
      }),
    });
    if (!tokenRes.ok) return fail();
    const tokenJson = await tokenRes.json();
    if (!tokenJson.id_token) return fail();
    const infoRes = await fetch(`https://oauth2.googleapis.com/tokeninfo?id_token=${encodeURIComponent(tokenJson.id_token)}`);
    if (!infoRes.ok) return fail();
    const info = await infoRes.json();
    const nowSec = Math.floor(Date.now() / 1000);
    if (info.aud !== GOOGLE_CLIENT_ID) return fail();
    if (info.iss !== 'https://accounts.google.com' && info.iss !== 'accounts.google.com') return fail();
    if (!info.exp || Number(info.exp) <= nowSec) return fail();
    if (!info.sub) return fail();
    const existing = await qGet('SELECT id FROM users WHERE google_sub = ?', [info.sub]);
    let userId;
    if (existing) {
      await qRun('UPDATE users SET email = ?, name = ?, picture_url = ? WHERE id = ?',
        [info.email || null, info.name || null, info.picture || null, existing.id]);
      userId = existing.id;
    } else {
      const ins = await qRun('INSERT INTO users (google_sub, email, name, picture_url) VALUES (?, ?, ?, ?)',
        [info.sub, info.email || null, info.name || null, info.picture || null]);
      userId = Number(ins.lastInsertRowid);
    }
    const token = await createSession(userId);
    return res.redirect(302, `${origin}/?token=${token}`);
  } catch (e) {
    console.error('Google callback error:', e.message);
    return fail();
  }
});

app.get('/api/me', optionalAuth, requireAuth, (req, res) => {
  res.json({ user: userJson(req.user) });
});

app.get('/api/me/groups', optionalAuth, requireAuth, async (req, res) => {
  const rows = await qAll(
    `SELECT g.code, g.name, m.nickname, m.id AS memberId
     FROM members m JOIN groups g ON g.id = m.group_id
     WHERE m.user_id = ? ORDER BY g.created_at DESC, g.code`,
    [req.user.id]);
  res.json({ groups: rows.map(r => ({ code: r.code, name: r.name, nickname: r.nickname, memberId: r.memberId })) });
});

app.post('/api/me/link', optionalAuth, requireAuth, async (req, res) => {
  const { code, memberId } = req.body || {};
  if (!code || memberId == null) return res.status(400).json({ error: 'code and memberId required' });
  const group = await getGroup(code);
  if (!group) return res.status(404).json({ error: 'Group not found' });
  const member = await qGet('SELECT id, nickname, venmo_handle, cashapp_handle, created_at, user_id FROM members WHERE id = ? AND group_id = ?', [memberId, group.id]);
  if (!member) return res.status(404).json({ error: 'Member not found' });
  if (member.user_id != null && Number(member.user_id) !== Number(req.user.id)) {
    return res.status(409).json({ error: 'That member is already linked to another account' });
  }
  if (member.user_id == null) {
    await qRun('UPDATE members SET user_id = ? WHERE id = ?', [req.user.id, member.id]);
  }
  const updated = await qGet('SELECT id, nickname, venmo_handle, cashapp_handle, created_at FROM members WHERE id = ?', [member.id]);
  res.json({ ok: true, member: memberJson(updated) });
});

app.post('/api/groups', optionalAuth, async (req, res) => {
  const { name, nickname } = req.body || {};
  if (!name || !String(name).trim()) return res.status(400).json({ error: 'Group name required' });
  if (!nickname || !String(nickname).trim()) return res.status(400).json({ error: 'Nickname required' });
  let code = makeCode();
  for (let tries = 0; tries < 5; tries++) {
    try {
      const info = await qRun('INSERT INTO groups (code, name) VALUES (?, ?)', [code, String(name).trim()]);
      const member = await qRun('INSERT INTO members (group_id, nickname, user_id) VALUES (?, ?, ?)',
        [Number(info.lastInsertRowid), String(nickname).trim(), req.user ? req.user.id : null]);
      const group = await getGroup(code);
      return res.status(201).json({ ...(await groupPayload(group)), your_member_id: Number(member.lastInsertRowid) });
    } catch (e) { code = makeCode(); }
  }
  return res.status(500).json({ error: 'Could not create group, try again' });
});

app.post('/api/groups/:code/join', optionalAuth, async (req, res) => {
  const group = await getGroup(req.params.code);
  if (!group) return res.status(404).json({ error: 'Group not found' });
  // Logged-in users rejoin as their existing member row, never a duplicate.
  if (req.user) {
    const mine = await qGet('SELECT id FROM members WHERE group_id = ? AND user_id = ?', [group.id, req.user.id]);
    if (mine) return res.json({ ...(await groupPayload(group)), your_member_id: mine.id, rejoined: true });
  }
  const { nickname } = req.body || {};
  if (!nickname || !String(nickname).trim()) return res.status(400).json({ error: 'Nickname required' });
  const nick = String(nickname).trim();
  const existing = await qGet('SELECT id FROM members WHERE group_id = ? AND lower(nickname) = lower(?)', [group.id, nick]);
  if (existing) return res.json({ ...(await groupPayload(group)), your_member_id: existing.id, rejoined: true });
  const info = await qRun('INSERT INTO members (group_id, nickname, user_id) VALUES (?, ?, ?)',
    [group.id, nick, req.user ? req.user.id : null]);
  return res.status(201).json({ ...(await groupPayload(group)), your_member_id: Number(info.lastInsertRowid) });
});

app.get('/api/groups/:code', async (req, res) => {
  const group = await getGroup(req.params.code);
  if (!group) return res.status(404).json({ error: 'Group not found' });
  res.json(await groupPayload(group));
});

app.get('/api/groups/:code/balances', async (req, res) => {
  const group = await getGroup(req.params.code);
  if (!group) return res.status(404).json({ error: 'Group not found' });
  res.json(await computeBalances(group));
});

app.post('/api/groups/:code/expenses', async (req, res) => {
  const group = await getGroup(req.params.code);
  if (!group) return res.status(404).json({ error: 'Group not found' });
  const { member_id, merchant, total, note, receipt, date, split_mode, split_data, tax, tip } = req.body || {};
  const member = await qGet('SELECT id FROM members WHERE id = ? AND group_id = ?', [member_id, group.id]);
  if (!member) return res.status(400).json({ error: 'Unknown member' });
  const totalCents = cents(total);
  if (!isFinite(totalCents) || totalCents <= 0) return res.status(400).json({ error: 'Total must be greater than 0' });
  const mode = split_mode === undefined ? 'equal' : String(split_mode);
  if (!['equal', 'shares', 'items'].includes(mode)) return res.status(400).json({ error: "split_mode must be 'equal', 'shares', or 'items'" });
  if (split_data !== undefined && split_data !== null && (typeof split_data !== 'object' || Array.isArray(split_data))) {
    return res.status(400).json({ error: 'split_data must be an object or null' });
  }
  const taxNum = tax === undefined ? 0 : Number(tax);
  const tipNum = tip === undefined ? 0 : Number(tip);
  if (!isFinite(taxNum) || taxNum < 0) return res.status(400).json({ error: 'tax must be a number >= 0' });
  if (!isFinite(tipNum) || tipNum < 0) return res.status(400).json({ error: 'tip must be a number >= 0' });
  const info = await qRun(
    'INSERT INTO expenses (group_id, member_id, merchant, total_cents, note, receipt, expense_date, split_mode, split_data, tax, tip) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [group.id, member.id, String(merchant || 'Expense').trim().slice(0, 80), totalCents,
      String(note || '').trim().slice(0, 200), receipt ? String(receipt) : null,
      date ? String(date).slice(0, 10) : new Date().toISOString().slice(0, 10),
      mode, split_data ? JSON.stringify(split_data) : null, taxNum, tipNum]);
  res.status(201).json({ id: Number(info.lastInsertRowid), ...(await groupPayload(group)) });
});

// Validate a settlement / nudge transfer. Returns an error string, or null.
async function validateTransfer(group, fromId, toId, amount) {
  const amt = Number(amount);
  if (!isFinite(amt) || amt <= 0) return 'Amount must be greater than 0';
  if (fromId == null || toId == null) return 'Unknown member';
  if (Number(fromId) === Number(toId)) return 'Cannot record a payment to yourself';
  const from = await qGet('SELECT id FROM members WHERE id = ? AND group_id = ?', [fromId, group.id]);
  const to = await qGet('SELECT id FROM members WHERE id = ? AND group_id = ?', [toId, group.id]);
  if (!from || !to) return 'Unknown member';
  return null;
}

app.post('/api/groups/:code/settlements', async (req, res) => {
  const group = await getGroup(req.params.code);
  if (!group) return res.status(404).json({ error: 'Group not found' });
  const { from_member_id, to_member_id, amount } = req.body || {};
  const err = await validateTransfer(group, from_member_id, to_member_id, amount);
  if (err) return res.status(400).json({ error: err });
  const info = await qRun(
    'INSERT INTO settlements (group_code, from_member_id, to_member_id, amount) VALUES (?, ?, ?, ?)',
    [group.code, Number(from_member_id), Number(to_member_id), Number(amount)]);
  const row = await qGet('SELECT * FROM settlements WHERE id = ?', [Number(info.lastInsertRowid)]);
  res.status(201).json(transferJson(row));
});

app.delete('/api/groups/:code/settlements/:id', async (req, res) => {
  const group = await getGroup(req.params.code);
  if (!group) return res.status(404).json({ error: 'Group not found' });
  const info = await qRun('DELETE FROM settlements WHERE id = ? AND group_code = ?', [req.params.id, group.code]);
  if (info.rowsAffected === 0) return res.status(404).json({ error: 'Settlement not found' });
  res.json({ ok: true, id: Number(req.params.id) });
});

app.post('/api/groups/:code/nudges', async (req, res) => {
  const group = await getGroup(req.params.code);
  if (!group) return res.status(404).json({ error: 'Group not found' });
  const { from_member_id, to_member_id, amount } = req.body || {};
  const err = await validateTransfer(group, from_member_id, to_member_id, amount);
  if (err) return res.status(400).json({ error: err });
  const info = await qRun(
    'INSERT INTO nudges (group_code, from_member_id, to_member_id, amount) VALUES (?, ?, ?, ?)',
    [group.code, Number(from_member_id), Number(to_member_id), Number(amount)]);
  const row = await qGet('SELECT * FROM nudges WHERE id = ?', [Number(info.lastInsertRowid)]);
  res.status(201).json(transferJson(row));
});

// Payment handles: only fields present in the body are updated; an empty
// string clears a handle.
function handleValue(v) {
  if (v == null) return null;
  const s = String(v).trim();
  return s === '' ? null : s.slice(0, 80);
}
app.patch('/api/groups/:code/members/:id', async (req, res) => {
  const group = await getGroup(req.params.code);
  if (!group) return res.status(404).json({ error: 'Group not found' });
  const member = await qGet('SELECT id, nickname, venmo_handle, cashapp_handle, created_at FROM members WHERE id = ? AND group_id = ?', [req.params.id, group.id]);
  if (!member) return res.status(404).json({ error: 'Member not found' });
  const body = req.body || {};
  const sets = [];
  const args = [];
  if ('venmo_handle' in body) { sets.push('venmo_handle = ?'); args.push(handleValue(body.venmo_handle)); }
  if ('cashapp_handle' in body) { sets.push('cashapp_handle = ?'); args.push(handleValue(body.cashapp_handle)); }
  if (sets.length) {
    await qRun(`UPDATE members SET ${sets.join(', ')} WHERE id = ?`, [...args, member.id]);
  }
  const updated = await qGet('SELECT id, nickname, venmo_handle, cashapp_handle, created_at FROM members WHERE id = ?', [member.id]);
  res.json(memberJson(updated));
});

app.delete('/api/groups/:code/expenses/:id', async (req, res) => {
  const group = await getGroup(req.params.code);
  if (!group) return res.status(404).json({ error: 'Group not found' });
  const exp = await qGet('SELECT receipt FROM expenses WHERE id = ? AND group_id = ?', [req.params.id, group.id]);
  const info = await qRun('DELETE FROM expenses WHERE id = ? AND group_id = ?', [req.params.id, group.id]);
  if (info.rowsAffected === 0) return res.status(404).json({ error: 'Expense not found' });
  if (exp && exp.receipt) await qRun('DELETE FROM receipts WHERE filename = ?', [exp.receipt]);
  res.json(await groupPayload(group));
});

// Uploads live in memory only — the bytes go straight into the receipts
// table (Render's filesystem is ephemeral, so nothing is written to disk).
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 12 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    if (/^image\//.test(file.mimetype)) cb(null, true);
    else cb(new Error('Only image files allowed'));
  },
});

app.post('/api/groups/:code/ocr', upload.single('receipt'), async (req, res) => {
  const group = await getGroup(req.params.code);
  if (!group) return res.status(404).json({ error: 'Group not found' });
  if (!req.file) return res.status(400).json({ error: 'No image uploaded' });
  // tesseract.js reads from a file path, so stage the buffer in the OS temp
  // dir for the duration of the OCR call only.
  const ext = path.extname(req.file.originalname || '.jpg') || '.jpg';
  const finalName = crypto.randomBytes(8).toString('hex') + ext;
  const tmpPath = path.join(os.tmpdir(), 'split-ocr-' + finalName);
  try {
    fs.writeFileSync(tmpPath, req.file.buffer);
    const worker = await getWorker();
    const { data } = await worker.recognize(tmpPath);
    const parsed = parseReceipt(data.text || '');
    await qRun('INSERT INTO receipts (filename, data, mime) VALUES (?, ?, ?)',
      [finalName, req.file.buffer, req.file.mimetype || 'image/jpeg']);
    res.json({ ...parsed, receipt: finalName, confidence: data.confidence ?? null });
  } catch (e) {
    console.error('OCR error:', e.message);
    res.status(500).json({ error: 'Could not read that receipt — try a clearer photo or enter it manually.' });
  } finally {
    try { fs.unlinkSync(tmpPath); } catch {}
  }
});

// Receipt images are served from the database, same URL shape as before
// (/uploads/<filename>) so the Flutter app needs no changes.
app.get('/uploads/:file', async (req, res) => {
  const row = await qGet('SELECT data, mime FROM receipts WHERE filename = ?', [req.params.file]);
  if (!row) return res.status(404).send('Not found');
  const buf = toBuffer(row.data);
  res.set('Content-Type', row.mime || 'image/jpeg');
  res.set('Content-Length', String(buf.length));
  res.send(buf);
});

// ---- Flutter web build ----
if (fs.existsSync(WEB_DIR)) {
  app.use(express.static(WEB_DIR));
  app.use((req, res, next) => {
    if (req.path.startsWith('/api/') || req.path.startsWith('/uploads/')) return next();
    res.sendFile(path.join(WEB_DIR, 'index.html'));
  });
} else {
  app.get('/', (req, res) => res.send('<h1>Split</h1><p>Flutter web build not found yet — run <code>flutter build web --release</code> in the project root.</p>'));
}

async function main() {
  await db.executeMultiple(SCHEMA);
  await runMigrations();
  app.listen(PORT, () => {
    console.log(`Split server listening on http://localhost:${PORT}`);
    console.log(`DB mode: ${TURSO_URL ? 'Turso (hosted)' : 'local file ' + DB_PATH}`);
  });
}
main().catch(e => { console.error('Failed to start:', e); process.exit(1); });
