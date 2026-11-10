// Split — backend: Express + libSQL (Turso hosted, or local file) + tesseract.js OCR.
// Serves the Flutter web build, the REST API, and receipt images.
// No auth. No secrets. DB config comes from env; without it, a local file DB
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
`;

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
async function groupPayload(group) {
  const members = await qAll('SELECT id, nickname, created_at FROM members WHERE group_id = ? ORDER BY id', [group.id]);
  const expenses = await qAll(`
    SELECT e.*, m.nickname AS payer
    FROM expenses e JOIN members m ON m.id = e.member_id
    WHERE e.group_id = ? ORDER BY e.expense_date DESC, e.id DESC`, [group.id]);
  const totalCents = expenses.reduce((s, e) => s + e.total_cents, 0);
  return {
    code: group.code,
    name: group.name,
    created_at: group.created_at,
    members,
    expenses: expenses.map(e => ({
      id: e.id, merchant: e.merchant, total: dollars(e.total_cents),
      total_cents: e.total_cents, note: e.note, receipt: e.receipt,
      date: e.expense_date, payer: e.payer, payer_id: e.member_id,
      created_at: e.created_at,
    })),
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

app.post('/api/groups', async (req, res) => {
  const { name, nickname } = req.body || {};
  if (!name || !String(name).trim()) return res.status(400).json({ error: 'Group name required' });
  if (!nickname || !String(nickname).trim()) return res.status(400).json({ error: 'Nickname required' });
  let code = makeCode();
  for (let tries = 0; tries < 5; tries++) {
    try {
      const info = await qRun('INSERT INTO groups (code, name) VALUES (?, ?)', [code, String(name).trim()]);
      const member = await qRun('INSERT INTO members (group_id, nickname) VALUES (?, ?)', [Number(info.lastInsertRowid), String(nickname).trim()]);
      const group = await getGroup(code);
      return res.status(201).json({ ...(await groupPayload(group)), your_member_id: Number(member.lastInsertRowid) });
    } catch (e) { code = makeCode(); }
  }
  return res.status(500).json({ error: 'Could not create group, try again' });
});

app.post('/api/groups/:code/join', async (req, res) => {
  const group = await getGroup(req.params.code);
  if (!group) return res.status(404).json({ error: 'Group not found' });
  const { nickname } = req.body || {};
  if (!nickname || !String(nickname).trim()) return res.status(400).json({ error: 'Nickname required' });
  const nick = String(nickname).trim();
  const existing = await qGet('SELECT id FROM members WHERE group_id = ? AND lower(nickname) = lower(?)', [group.id, nick]);
  if (existing) return res.json({ ...(await groupPayload(group)), your_member_id: existing.id, rejoined: true });
  const info = await qRun('INSERT INTO members (group_id, nickname) VALUES (?, ?)', [group.id, nick]);
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
  const { member_id, merchant, total, note, receipt, date } = req.body || {};
  const member = await qGet('SELECT id FROM members WHERE id = ? AND group_id = ?', [member_id, group.id]);
  if (!member) return res.status(400).json({ error: 'Unknown member' });
  const totalCents = cents(total);
  if (!isFinite(totalCents) || totalCents <= 0) return res.status(400).json({ error: 'Total must be greater than 0' });
  const info = await qRun(
    'INSERT INTO expenses (group_id, member_id, merchant, total_cents, note, receipt, expense_date) VALUES (?, ?, ?, ?, ?, ?, ?)',
    [group.id, member.id, String(merchant || 'Expense').trim().slice(0, 80), totalCents,
      String(note || '').trim().slice(0, 200), receipt ? String(receipt) : null,
      date ? String(date).slice(0, 10) : new Date().toISOString().slice(0, 10)]);
  res.status(201).json({ id: Number(info.lastInsertRowid), ...(await groupPayload(group)) });
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
  app.listen(PORT, () => {
    console.log(`Split server listening on http://localhost:${PORT}`);
    console.log(`DB mode: ${TURSO_URL ? 'Turso (hosted)' : 'local file ' + DB_PATH}`);
  });
}
main().catch(e => { console.error('Failed to start:', e); process.exit(1); });
