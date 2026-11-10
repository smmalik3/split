# Split — snap receipts, split them equally

A Flutter web app (mobile-ready codebase: Android + iOS folders included) with a
Node.js + SQLite backend on this VM. No accounts — friends join a group with a
shareable link + nickname.

## Run it

```bash
./start.sh    # starts the server on http://localhost:8787
./stop.sh     # stops it
```

Logs: `data/server.log`. Data (SQLite + receipt photos): `data/`.
Public link for friends: `./tunnel.sh` tries a Cloudflare quick tunnel, but it
currently FAILS in this environment — the egress proxy blocks
`api.trycloudflare.com` (cloudflared errors with `tls: first record does not
look like a TLS handshake`, and curl to that host times out). Until a public
tunnel works, friends need to be on the same network / use the local URL
below. The tunnel URL would be ephemeral anyway (changes on every restart).

## Deploy to Render (free) + Turso (free) — current target

The app runs on Render's free web tier (Docker runtime, from
`render.yaml`) with a free Turso database (hosted libSQL — SQLite
compatible). No card needed for either free tier.

**What Salman must do himself** (accounts can't be created for him):

1. Create a free [Turso](https://turso.tech) account, then in the Turso
   dashboard (or CLI: `turso db create split --region iad`):
   create a database named `split` and copy its URL
   (`libsql://split-<username>.turso.io`) and an auth token
   (`turso db tokens create split`).
2. Create a free [Render](https://render.com) account (sign up with
   GitHub), then **New > Blueprint** and connect the GitHub repo
   `smmalik3/split`. Render reads `render.yaml` and will prompt for two
   environment variables — paste the Turso URL as `TURSO_DATABASE_URL`
   and the token as `TURSO_AUTH_TOKEN`.
3. Deploy. The public URL will be `https://split.onrender.com`
   (or whatever name Render assigns).

Notes:
- The first deploy starts with an **empty database**; groups created
  locally do not carry over.
- Render's free web service spins down after 15 minutes without traffic
  and cold-starts on the next request (a few seconds). Data is safe: it
  lives in Turso, not on Render's ephemeral filesystem.
- Turso free tier (verified Nov 10, 2026): 100 databases, 5 GB storage,
  500M rows read/month, 10M rows written/month, no card. Caveat: a free
  database is archived after 10 days with no queries — use the app at
  least once every 10 days, or unarchive it from the Turso dashboard/CLI.
- To update after code changes: push to GitHub and Render redeploys
  automatically (auto-deploy is on by default for Blueprint services).

## Deploy to Fly.io — SUPERSEDED

Fly.io was the first deployment target, but it has **no free tier for
new accounts** (verified Nov 10, 2026): new accounts get a $1 trial
credit for 7 days, trial machines stop after 5 minutes of running, and
a card is required after the trial (~$2.34/mo at this size, waived if
under $5/mo). The `Dockerfile`, `fly.toml` and the notes below are kept
for reference, but **Render + Turso is the current target**.

The app is ready to deploy — `Dockerfile`, `fly.toml` and `.dockerignore`
are in the project root. **Heads-up on cost (verified Nov 10, 2026): Fly.io
has no free tier for new accounts.** New accounts get a $1 trial credit for
7 days, no card needed to sign up — but trial machines are stopped after
5 minutes of running, so the app will not stay up until a card is added.
After the trial, a card is required. Expected ongoing cost at this size:
shared-cpu-1x 256MB machine $2.19/mo + 1GB volume $0.15/mo = ~$2.34/mo —
and Fly.io's own cost-management docs say monthly bills under $5 for a
personal organization are waived, so the expected bill is $0 unless usage
grows (egress is $0.02/GB in North America/Europe). Sources: fly.io/pricing
and docs.fly.io/about/free-trial, both checked Nov 10, 2026.

What Salman must do himself: create the free Fly.io account (no card needed
to sign up), then run the commands below from the project directory
(`flyctl` install: `curl -L https://fly.io/install.sh | sh`, or
`brew install flyctl` on macOS).

```bash
fly auth login                                    # opens a browser to log in
fly apps create split-salmans                     # if the name is taken, pick another and update fly.toml
fly volumes create split_data --region iad --size 1 --app split-salmans
fly deploy                                        # builds the image on Fly's remote builder
fly open                                          # https://split-salmans.fly.dev
```

Notes:
- The first deploy starts with an **empty database** (the local DB is not
  copied — see `.dockerignore`); groups created locally do not carry over.
- After the 7-day trial ends (or the $1 credit is used up), add a card at
  fly.io/trial or the machine stops and cannot be restarted.
- The app must stay always-on (`auto_stop_machines = 'off'` in fly.toml),
  because the SQLite data lives on the attached volume.
- To update after code changes: `fly deploy` again from the project root.

## Rebuild the web app after changing Flutter code

```bash
export PATH="$HOME/bin:$HOME/flutter/bin:$PATH"
flutter build web --release
./start.sh   # or restart the server to pick up the new build
```

## API (same origin)

- `POST /api/groups` {name, nickname} → creates group, returns 6-char code
- `POST /api/groups/:code/join` {nickname}
- `GET  /api/groups/:code` → group, members, expenses
- `GET  /api/groups/:code/balances` → per-person paid/share/net + settle-up transfers
- `POST /api/groups/:code/expenses` {member_id, merchant, total, note?, receipt?, date?}
- `DELETE /api/groups/:code/expenses/:id`
- `POST /api/groups/:code/ocr` (multipart `receipt` image) → parsed merchant/total/date/items
- `GET  /uploads/:file` → receipt photos

## How the pieces fit

- `lib/` — Flutter app (Material 3, mobile-first)
- `server/server.js` — Express + @libsql/client + tesseract.js OCR.
  Uses Turso (hosted libSQL) when `TURSO_DATABASE_URL` /
  `TURSO_AUTH_TOKEN` are set, otherwise a local SQLite file — same SQL
  dialect either way. Receipt photos are stored as BLOBs in the
  database (Render's filesystem is ephemeral).
- `data/db/split.db` — local SQLite database (dev only, never committed)
- `data/uploads/` — legacy on-disk receipt photos (dev only; the current
  server stores receipt images in the database instead)
- `data/tesseract-cache/eng.traineddata.gz` — OCR language data (pre-downloaded;
  tesseract.js's CDN fetch hangs in this environment, so the server points at
  this local copy; it IS committed — the Docker build bakes it into the image)
