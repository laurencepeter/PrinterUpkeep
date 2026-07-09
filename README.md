# ICT Printer Upkeep & Procurement Tracking System

A production-quality system for Government ICT staff to track the complete
lifecycle of printer maintenance, repairs, consumables and procurement — from
the moment a request is received until the ticket is closed. The primary
objective: **know exactly where every printer request is in the process at all
times.**

Designed for future expansion into a complete ICT Asset Management / ITSM
platform (computers, monitors, network equipment, …) without major
refactoring.

## Technology Stack

| Layer      | Technology |
|------------|------------|
| Frontend   | Flutter (Material 3, desktop-first responsive, dark & light mode), Riverpod |
| Backend    | Node.js 22 + TypeScript, Express, Clean Architecture, Repository Pattern |
| Database   | PostgreSQL 16, forward-only SQL migrations |
| Auth       | JWT (simple login now; the auth layer is isolated so SSO/OIDC can be added later) |
| Deployment | Docker Compose, fully environment-variable driven |

## Key Design Decisions

### Workflow stages, not a status column

Tickets never have a mutable "status" field. Instead every ticket moves
through **workflow stages** and every movement is an *insert* into
`ticket_stage_history` (timestamp + user + notes, never overwritten). The
current status is always **derived** from the latest stage. This preserves the
full audit trail, makes duration reporting trivial, and prevents information
loss as tickets progress through the approval chain.

```
Open → ICT Ticket Received → Vendor Contacted → Quotation Received
     → Requisition Prepared → Sent to Accounts → Funds Confirmed
     → Sent to GA → GA Approved → Purchase Order Issued
     → Vendor Work In Progress → Completed → Closed
```

Every ticket displays a colour-coded process tracker (green = done,
blue = current, yellow = waiting, red = blocked, grey = not started) and a
`■■■■□□□□□□` progress bar.

### Minimal typing

Dropdowns, searchable autocompletes, multi-select chips, date pickers and
auto-generated values everywhere. Ticket numbers (`ICT-2026-000001`) and
requisition numbers (`REQ-2026-0001`) are generated automatically —
gap-free, race-safe, per-year sequences.

### Data portability

Everything exports to **CSV, Excel, PDF and JSON**; vendors, printers and
departments import from CSV/Excel/JSON with duplicate validation — so data
can migrate into a future enterprise system.

## Repository Layout

```
├── server/          REST API (TypeScript, Clean Architecture)
│   ├── migrations/  SQL migrations (schema + seed reference data)
│   └── src/
│       ├── domain/          entities, workflow rules, errors
│       ├── application/     use-case services (tickets, auth, exports, notifications)
│       ├── infrastructure/  PostgreSQL repositories
│       └── presentation/    Express routes, middleware, DTO validation (zod)
├── app/             Flutter frontend (Material 3 + Riverpod)
├── docs/            API reference, database schema, deployment guide
└── docker-compose.yml
```

## Quick Start (Docker)

```bash
cp .env.example .env       # set DB_PASSWORD and JWT_SECRET (required)
docker compose up -d --build
```

Open `http://localhost:8000` and sign in with the admin account from `.env`
(default `admin` / `ChangeMe123!` — **change it immediately** under
Settings → Change password).

Migrations run automatically at API startup; the first boot also creates the
admin account.

## Local Development

```bash
# API (needs a local PostgreSQL 16)
cd server
npm install
npm run migrate
npm run dev              # http://localhost:8080

# Flutter app
cd app
flutter create . --platforms web,windows,linux   # one-time platform scaffolding
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
```

## Modules

- **Dashboard** — open/awaiting/WIP/completed counters, owned vs leased,
  average completion time, monthly/department/vendor/status charts, recent
  activity, notification feed (awaiting action, overdue, vendor delays).
- **Tickets** — dropdown-driven intake form, workflow tracker, quotations,
  requisitions (with printable PDF), Accounts & GA approvals, purchase
  orders, delivery notes, attachments, notes, full status history.
- **Printers** — asset register (owned/leased, warranty, status) with
  per-printer maintenance history.
- **Vendors** — CRUD with duplicate prevention and deactivation (never
  deletion — history is preserved).
- **Departments** — CRUD.
- **Users** — Admin / ICT Officer / Viewer roles with enforced permissions.
- **Reports** — monthly repairs, vendor performance, department usage,
  average repair time, consumables cost, most common issues, most repaired
  printers, tickets by officer, owned vs leased — all exportable.
- **Audit log** — every change stores old value, new value, user and time.

## Documentation

- [API reference](docs/API.md)
- [Database schema](docs/DATABASE.md)
- [Deployment & system requirements](docs/DEPLOYMENT.md) (sized for ≤25 users)

## Extending to other ICT asset types

`tickets.asset_type` (default `'printer'`) and per-asset-type workflows in
`workflow_stages` mean a computer or network-equipment lifecycle can be added
by inserting new stage rows and one new asset table — no schema refactor. See
[docs/DATABASE.md](docs/DATABASE.md#future-expansion).
