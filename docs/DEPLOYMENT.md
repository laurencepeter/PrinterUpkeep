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

The `docker compose up` above (no `-f` flag) auto-merges
`docker-compose.override.yml`, which publishes the web UI on the host at
`http://<server>:${WEB_PORT:-8000}`. That override is where the host-port
bind lives — the base `docker-compose.yml` only `expose`s port 80 so that
managed platforms can proxy to it instead (see below).

### Building on a managed host / PaaS

This is a **multi-service** app (PostgreSQL + API + web), so there is
deliberately **no root `Dockerfile`**. When deploying on a platform that builds
automatically, set the build type to **Docker Compose** (pointing at
`docker-compose.yml`), **not** "Dockerfile". A plain `docker build` at the repo
root will fail with `open Dockerfile: no such file or directory` because there
is no single image to build.

On a managed host the stack is assembled from two sources:

- **`api`** is built on the deploy host from `server/Dockerfile` (a quick
  Node build).
- **`web`** is **not** built on the deploy host. The Flutter web build pulls a
  ~2 GB SDK image and takes several minutes — too slow/heavy for a typical
  deploy window (it was timing out mid-compile). Instead it is **pre-built by
  GitHub Actions** (`.github/workflows/build-web-image.yml`) and published to
  GHCR as `ghcr.io/<owner>/printerupkeep-web:main`; the deploy host just
  **pulls** that small nginx image. See
  [Pre-built web image](#pre-built-web-image) below for the one-time setup.

Both custom services expose health checks (`api` → `GET /api/health`,
`web` → `GET /`) so the platform can gate the release on a healthy stack, and
`web` only starts once `api` reports healthy.

#### Pre-built web image

The `web` service in `docker-compose.yml` references a registry image:

```yaml
image: ${WEB_IMAGE:-ghcr.io/laurencepeter/printerupkeep-web:main}
```

- **CI publishes it.** On every push to `main` that touches `app/**`, the
  `Build web image` workflow builds `app/Dockerfile` and pushes
  `:main`, `:latest`, and `:sha-<commit>` tags to GHCR. You can also run it
  manually from the Actions tab (**Run workflow**) — do this once before the
  first deploy so the `:main` tag exists.
- **Let CI finish before deploying.** If your platform auto-deploys on push,
  the deploy may start before the image is published and fail to pull. Either
  wait for the workflow to go green, or trigger the deploy afterward.
- **Registry access.** GHCR packages are private by default. Either make the
  `printerupkeep-web` package **public** (Package settings → Change visibility)
  so the host can pull it anonymously, or add a GHCR pull credential (a PAT with
  `read:packages`) to your platform's registry settings.
- **Pinning.** `WEB_IMAGE` overrides the tag/digest, e.g.
  `WEB_IMAGE=ghcr.io/laurencepeter/printerupkeep-web:sha-<commit>` to pin an
  exact build instead of following `:main`.

Local development is unaffected: `docker-compose.override.yml` re-adds a build
context for `web`, so `docker compose up -d --build` still builds it from
`./app` source (no registry access needed).

**Ports on a managed host.** The base `docker-compose.yml` deliberately does
**not** publish a fixed host port for `web` — it only `expose`s port 80.
Managed platforms build with an explicit file flag
(`docker compose -f docker-compose.yml up -d`), which disables Compose's
automatic override loading, so the host-port bind in
`docker-compose.override.yml` is skipped and the platform's own reverse proxy
routes your domain to the container. This avoids
`Bind for 0.0.0.0:8000 failed: port is already allocated` when port 8000 is
already taken on the shared host. Point the service at your domain in the
platform UI (e.g. Coolify's Domains field); nothing else is required. If you
still want a fixed host port on such a platform, add a `ports:` mapping to the
service in the platform's compose configuration and pick a port you know is
free.

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
| `WEB_PORT` | 8000 | Host port for the web UI (local / direct deploys only; see override) |
| `WEB_IMAGE` | `ghcr.io/laurencepeter/printerupkeep-web:main` | Pre-built web image pulled on managed hosts; override to pin a tag/digest |

## Future: cloud & SSO

- The stack is 12-factor: config via env vars, stateless containers, volumes
  for state — it moves to any cloud container service (ECS, Cloud Run + Cloud
  SQL, AKS) without code changes; point `DB_*` at a managed PostgreSQL.
- Authentication is isolated in `server/src/application/authService.ts` and a
  single Express middleware. Swapping simple login for SSO (OIDC/SAML)
  replaces one service + adds a callback route; the role model and JWT
  session mechanics stay unchanged.
