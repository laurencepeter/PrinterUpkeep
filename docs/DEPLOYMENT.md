# Deployment Guide & System Requirements

## Sizing (≤10 concurrent users typical, 25 to be safe)

This workload is small: short bursts of CRUD traffic, occasional report
generation and file uploads. A single modest VM comfortably serves all three
containers (PostgreSQL + API + web).

### Minimum (works fine)

| Resource | Spec |
|---|---|
| CPU | 2 vCPU |
| RAM | 4 GB (Postgres ~512 MB, API ~256 MB, nginx ~32 MB, headroom for OS + Docker) |
| Disk | 40 GB SSD (database will stay in the low GBs for years; attachments dominate — budget ~1 GB per 1,000 attachments at typical scan sizes) |
| OS | Any 64-bit Linux with Docker Engine 24+ and Docker Compose v2 |
| Network | 100 Mbps LAN; the app is served on one port (default 8000) |

### Recommended (comfortable, room to grow into full ITSM)

| Resource | Spec |
|---|---|
| CPU | 4 vCPU |
| RAM | 8 GB |
| Disk | 100 GB SSD, with backups |

No GPU, no external cache, no message queue needed. The API uses a
10-connection PostgreSQL pool (`DB_POOL_SIZE`) — more than enough for 25
users; Postgres' default `max_connections=100` needs no tuning.

## Production Deployment

```bash
git clone <repo> && cd PrinterUpkeep
cp .env.example .env
# Edit .env:
#   DB_PASSWORD  — strong password (required)
#   JWT_SECRET   — `openssl rand -hex 32` (required)
#   ADMIN_*      — initial admin credentials
#   WEB_PORT     — port to serve on (default 8000)
docker compose up -d --build
```

- Migrations run automatically when the API starts.
- The first boot creates the admin account (only if no users exist).
- The web container proxies `/api/*` to the API container, so only
  `WEB_PORT` needs to be reachable by users.

### TLS / HTTPS

Put your standard reverse proxy (nginx, Caddy, Traefik or the ministry's
existing load balancer) in front of `WEB_PORT` and terminate TLS there.
Nothing in the app assumes a scheme or hostname.

### Backups

Two things hold state, both Docker volumes:

| Volume | Contents | Backup |
|---|---|---|
| `pgdata` | database | `docker compose exec db pg_dump -U printerupkeep printerupkeep > backup.sql` (nightly cron) |
| `uploads` | ticket attachments | file-level copy of the volume (e.g. `docker run --rm -v printerupkeep_uploads:/u -v /backup:/b alpine tar czf /b/uploads.tgz /u`) |

Restore = restore the SQL dump + the uploads tree; containers are stateless.

### Updating

```bash
git pull
docker compose up -d --build     # migrations apply automatically
```

### Health & monitoring

- `GET /api/health` returns `{"status":"ok"}` — point your uptime monitor at
  it.
- Logs: `docker compose logs -f api`.
- The API runs an hourly notification scan (overdue tickets, vendor delays);
  thresholds are configurable in Settings.

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `DB_HOST` / `DB_PORT` / `DB_NAME` / `DB_USER` / `DB_PASSWORD` | see compose | PostgreSQL connection |
| `DB_POOL_SIZE` | 10 | API connection pool |
| `PORT` | 8080 | API listen port (internal) |
| `JWT_SECRET` | — | **Required.** Signing key for tokens |
| `JWT_TTL` | 12h | Token lifetime |
| `UPLOAD_DIR` | ./uploads | Attachment storage (volume-mounted in Docker) |
| `MAX_FILE_SIZE_MB` | 20 | Upload limit |
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` / `ADMIN_FULL_NAME` | admin / ChangeMe123! / … | First-boot admin bootstrap |
| `WEB_PORT` | 8000 | Public port served by nginx |

## Future: cloud & SSO

- The stack is 12-factor: config via env vars, stateless containers, volumes
  for state — it moves to any cloud container service (ECS, Cloud Run + Cloud
  SQL, AKS) without code changes; point `DB_*` at a managed PostgreSQL.
- Authentication is isolated in `server/src/application/authService.ts` and a
  single Express middleware. Swapping simple login for SSO (OIDC/SAML)
  replaces one service + adds a callback route; the role model and JWT
  session mechanics stay unchanged.
