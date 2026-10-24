# 88 Billiards: Admin Server Plan

Server: `foodbase` (SSH alias, `admin-fb@ssh.foodbase.app` through a Cloudflare Access tunnel).
Stack: **NestJS + PostgreSQL**, admin web UI built later from the design you send.
First release: **sync API + dashboard + management** (prices, products, users pushed down to tablets).

Status: PLAN. Nothing has been installed on the server yet.

## Decided

| Topic | Decision |
|---|---|
| Backend | NestJS (TypeScript), PostgreSQL |
| First release scope | Dashboard and management (read everything, edit prices, products, rates, users) |
| Server setup | Done from PowerShell over `ssh foodbase` first |
| Admin web UI | You send the design later. API comes first, UI is built against it |
| Public address | Decide later (server listens on localhost only until then) |

## Open (answer when you reach them)

1. What else runs on foodbase (Docker? Postgres? nginx/Caddy?). Needed before Phase S0 ends.
2. Address: subdomain of foodbase.app, own domain, or behind Cloudflare Access.
3. Race income question (plan v2 Q1): table fee only, or the whole bet? Changes the report math.
4. Who owns config after launch: tablet Settings, admin panel, or both (see Sync rules).

---

## Phase S0: Server setup (PowerShell, you run, I guide)

I could not log in non-interactively (key refused from both Git Bash and PowerShell), so this phase needs you in the loop.

1. In PowerShell run `ssh foodbase` once. If Cloudflare asks you to sign in, finish it in the browser. Paste me the output of the inventory block below.
2. Inventory (read only):
   ```powershell
   ssh foodbase "hostname; uname -sr; head -2 /etc/os-release; nproc; free -h | head -2; df -h / | tail -1; for c in node npm docker psql nginx caddy pm2 git cloudflared; do printf '%s: ' $c; (command -v $c >/dev/null && echo yes) || echo no; done; ss -tlnp | awk 'NR>1{print \$4}'; docker ps --format '{{.Names}} {{.Image}} {{.Ports}}'"
   ```
3. Depending on the result I give you the exact commands to:
   - install Node 22 LTS and PostgreSQL 16 (or add a database to the existing one),
   - create a separate DB and DB user `billiards` (never share FoodBase's DB or user),
   - create `/opt/88billiards` owned by a non-root user, run the API under systemd (or Docker) bound to `127.0.0.1:4088`,
   - nightly `pg_dump` to a local folder, 14 day retention, and one copy off the box,
   - `ufw`: nothing new opened. Public access only through the Cloudflare tunnel once the address is chosen.
4. Done when: `curl http://127.0.0.1:4088/health` returns ok on the server, restarts after a reboot, and a backup file exists.

Rules I will follow on the shared server: every command shown to you first, no changes to FoodBase's services, nothing run with `sudo` that you did not see.

## Phase S1: API skeleton (repo folder `server/`)

- NestJS app, Prisma + PostgreSQL, config via `.env`, `/health`, structured logs, OpenAPI docs at `/docs` (dev only).
- Database mirrors the app's Drift tables one to one (`app/lib/data/tables.dart`): branch, pool_table, floor_zone, time_rate, game_type, session, session_extension, session_game, race_detail, complimentary_item, product, sale, sale_item, stock_movement, expense, payment, void_log, audit_log, plus server-only `web_user`, `device`, `sync_cursor`.
- Same base columns on every synced row: `id` (UUID, global PK), `branch_id`, `device_id`, `created_at`, `updated_at`, `deleted_at`. Server adds `server_seq` (bigint, from a sequence) so pulls never miss rows.
- Money stays whole pesos (`int`), same as the app.

## Phase S2: Sync (the part that must be right)

Endpoints (all JSON, gzip):

| Call | What it does |
|---|---|
| `POST /v1/devices/pair` | Tablet sends a one-time pairing code made in the admin panel, gets a long random device token + its `branch_id`. Token stored in the app's `AppSettings`. |
| `POST /v1/sync/push` | `{ deviceId, rows: { table: [row...] } }`. Upsert by `id`, in one transaction. Safe to retry. Returns the ids accepted. |
| `GET /v1/sync/pull?since=<server_seq>` | Rows changed since the cursor for that branch, config tables first. Returns a new cursor. |
| `POST /v1/sync/heartbeat` | Last sync time, app version, pending change count (feeds the stale-branch alert). |

Rules:

- **Two kinds of tables.** Device-owned (sessions, sales, payments, expenses, voids, stock movements, audit): only tablets write them, server just stores. Config tables (time rates, game types, products' name/price/category/active, pool tables, floor zones): both sides can edit, last write wins by `updated_at`; admin edits are stamped with server time.
- **Stock is never overwritten.** Server ignores `stock` on pushed product rows and computes it as the sum of `stock_movement.delta`. Admin stock changes become new movement rows (`reason = adjustment`) that tablets pull and apply as deltas, matching process flow B in the design PDF.
- **Append only:** audit_log, stock_movement, void_log. Server rejects updates and deletes on them.
- **Idempotent:** pushing the same row twice changes nothing; a retry after a dropped connection can never double count.
- **Clock skew:** if a tablet clock is off by more than a few minutes, the server records `received_at` and flags the device.
- Tablet side (later, in `app/`): a sync service that reads rows where `synced = false`, pushes, marks `synced = true`, then pulls. The `synced` column and `kSyncMinutes` / `kLastSync` settings already exist.

Test: a script that replays the demo seed (`app/lib/dev/demo_seed.dart`) through push twice, pulls into a second fake device, and checks totals match.

## Phase S3: Auth and users

- Admin login is a **6-digit PIN, no username** (plan v2). Roles: **Owner** everything, **Admin** everything except users and PINs.
- PINs hashed with argon2id and a per-user salt. Because there is no username, login checks the PIN against every active user (a handful), so each attempt costs a few hashes.
- Weakness to accept or fix: a 6-digit PIN is only 1,000,000 combinations and "5 tries then lock the account" cannot work without knowing which account. Defaults I will build: throttling per IP with growing delays, a global lockout after repeated failures, every failed attempt in the audit log. **Strong recommendation:** put the panel behind Cloudflare Access too (decided when we pick the address).
- Sessions: httpOnly, secure, same-site cookie, 12 hour expiry, sign out everywhere on PIN change.
- Owner can create users, reset PINs. Forgotten PIN is reset by the Owner (plan v2).

## Phase S4: Admin API (what the web panel will call)

| Module | Endpoints (summary) | Role |
|---|---|---|
| Overview | totals for income, expenses, voids, net; per-branch table; low stock; recent voids and audit | Owner, Admin |
| Branches | list, create, rename, settings, **pairing code**, devices and last sync, revoke device | Owner, Admin |
| Live tables | per branch: table, status (playing, free, ending soon, waiting to pay), mode, time left, amount. Up to 5 min behind. | both |
| Reports | day, week, month, per branch or all; income by time / game / race fee / benta; expenses; voids; net. Same formula as the app: `Net = table income + benta - expenses - voids` | both |
| Transactions | list, filter, detail, unpaid list | both |
| Inventory | per branch stock, **inventory log** (every movement), stock in, adjust | both |
| Products | add, edit, price, cost, category, image upload, deactivate | both |
| Pricing | time rates, game types and price per game, race presets, pushed down to branches | both |
| Tables and map | add, rename, drag layout, per branch | both |
| Expenses | list and categories (edit is audited) | both |
| Audit log | read only, filter by actor, action, branch | both |
| Users | create, role, reset PIN | Owner |
| Alerts | low stock, branch not synced for 15 min (configurable) | both |

- Report math lives in one server service and is tested against the same fixtures as the app's `report_repository.dart`, so the tablet and the panel can never show different profit for the same day.
- Every write by an admin goes to `audit_log` with old and new value.
- Product images: stored on disk under the app folder, served through the API, resized on upload.

## Phase S5: Alerts and polish

- Low-stock and stale-branch checks run every minute on the server. First version shows them in the panel; email or push (FCM) is a later add.
- Rate limiting, request size limits, CORS locked to the panel origin, helmet headers, dependency audit.
- Backup restore drill (restore last dump into a scratch DB, confirm row counts).

## Phase S6: Admin web UI

Waiting for your design. Plan: React + Vite + TypeScript served as static files by the same NestJS process, so one service to run. Reuses the POS look (Barlow fonts, gold on dark green) as in the Overview page of the design PDF (page 13): Overview, Branches, Live tables, Income and expenses, Inventory, Voids and audit log, Products and prices, Users and roles, Settings.

## Phase S7: Connect the tablet app

- Settings > Sync: pairing code field, "Sync now", status (already stubbed).
- Sync service with the app's 5 minute interval; Android uses workmanager. Windows debug build gets a timer.
- First sync uploads everything with `synced = false`; pull applies config changes (prices, products, rates, map).
- Test on the scratch DB first, then a real tablet.

## Repo layout

```
88 Billards/
  app/       Flutter POS (exists)
  server/    NestJS API, Prisma schema, migrations, tests
  admin/     React panel (after the design arrives)
  docs/      this plan
```

## Order of work

1. S0 server setup with you in PowerShell.
2. S1 skeleton and database.
3. S2 sync with tests (biggest risk, built before any UI).
4. S3 auth, S4 admin API.
5. S6 UI when the design is ready, then S7 app connection, S5 alerts and backups hardening.

## Risks

- **Shared server:** FoodBase is production. A wrong command can hurt it, so the setup is step by step and reviewed.
- **PIN-only login on the internet** is weak without Cloudflare Access or similar.
- **Two places editing prices** (tablet Settings and admin) can fight; pick an owner for config (Open item 4). My default is admin-owned, tablet Settings read only for prices once paired.
- **Report mismatch** between app and server if the race income question stays open.
