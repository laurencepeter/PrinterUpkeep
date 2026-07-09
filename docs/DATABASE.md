# Database Schema

PostgreSQL 16. Normalised (3NF). Migrations live in `server/migrations/` and
are applied automatically at API startup (forward-only, tracked in
`schema_migrations`).

## Entity Overview

```
roles ──< users ──────────────┐
                              │ created_by / assigned_to / changed_by
departments ──< printers      │
      │             │         │
      └──────< tickets >──────┘
vendors ──────<   │   >── issue_categories
                  │
                  │ current_stage_id (cache)
workflow_stages ──┤
                  ├──< ticket_stage_history   (INSERT-ONLY audit trail)
                  ├──< ticket_notes
                  ├──< ticket_files ──┐ file_id
                  ├──< quotations ────┤
                  ├──< requisitions ──┤
                  ├──< approvals      │  (accounts + ga)
                  ├──< purchase_orders┤
                  └──< delivery_notes ┘
audit_logs, notifications, settings, ticket_sequences (standalone)
```

## Core Tables

### workflow_stages
Data-driven workflow, keyed by `(asset_type, code)`. Columns: `name` (tracker
display), `status_label` (derived ticket status, e.g. "Awaiting Accounts"),
`sort_order`, `is_terminal`. The printer workflow ships 14 stages
(13 happy-path + `cancelled`).

### tickets
One row per request. Highlights:

- `ticket_number` — unique, auto-generated `ICT-YYYY-NNNNNN` from
  `ticket_sequences` (per-prefix, per-year counter incremented under a row
  lock: gap-free and race-safe).
- `asset_type` — default `'printer'`; the extension point for future asset
  classes.
- `current_stage_id` — **denormalised cache** of the latest stage, updated in
  the same transaction as every `ticket_stage_history` insert. Used only for
  fast filtering; history is the source of truth.
- `is_blocked` / `blocked_reason` — red state in the tracker.
- Full intake detail: date/time received, reporting method (walk_in / phone /
  email / ict_ticket / vendor_ticket), reporter contacts, department, printer,
  issue category, priority (low/medium/high/critical), description, vendor,
  assigned ICT officer.

### ticket_stage_history — INSERT-ONLY
`(ticket_id, stage_id, changed_by, notes, created_at)`. Never updated or
deleted. Powers the per-ticket timeline (“Received 8:45 AM → Vendor Contacted
9:12 AM → …”), stage-duration reports and the process tracker.

### Procurement chain
- `quotations` — vendor contact date, requested/received dates, number,
  amount, currency, uploaded file.
- `requisitions` — auto-numbered `REQ-YYYY-NNNN`, prepared date, signed-copy
  file.
- `approvals` — one structure for both checkpoints, discriminated by
  `approval_type` (`accounts` | `ga`): sent date, decision (pending /
  approved / rejected / funds_available / funds_unavailable), decision date
  and `approved_by` (name of the officer who approved — feeds the IT
  approvals-by-department report).
- `purchase_orders`, `delivery_notes` — numbers, dates, file links.

### Consumables catalogue
- `printer_consumables` — the per-printer catalogue of toners/drums/parts an
  admin maintains: `kind` (toner/ink/drum/maintenance_kit/fuser/part/other),
  `color` (black/cyan/magenta/yellow/tricolor/other, or NULL for non-colour
  parts) and `model_code`. Editing replaces the set (old rows soft-removed via
  `is_active`) so historical ticket references survive.
- `ticket_consumables` — which catalogue items a ticket asked to replace.
  Descriptive columns are snapshotted (so later catalogue edits never rewrite
  history) alongside a nullable `consumable_id` reference.

### Supporting tables
- `vendors` — unique index on `lower(company_name)` prevents duplicates;
  `vendor_types text[]` (printer/consumables/maintenance/other); deactivated,
  never deleted.
- `printers` — asset number, friendly name, model, serial, owned/leased,
  department, location/building/floor, vendor, warranty expiry, status
  (active/repair/disposed). Network identity: unique IP address, MAC
  address, connection type (network/wifi/usb/other), colour/mono flag and a
  free-text consumables (toner) model, plus a structured consumables
  catalogue (see `printer_consumables`). Lease terms for leased units: start/end dates
  (CHECK `lease_end >= lease_start`) and monthly cost; purchase date/cost
  for owned units. Servicing: last service date and next service due — both
  feed the automatic notification scan (`lease_expiry_warn_days`,
  `service_due_warn_days` settings).
- `users` + `roles` — bcrypt password hashes; roles: admin, ict_officer,
  viewer.
- `ticket_files` — metadata + disk path under `UPLOAD_DIR` (Docker volume);
  categorised (screenshot/photo/document/quotation/requisition/
  purchase_order/delivery_note).
- `audit_logs` — entity type/id, action, field, old value, new value, user,
  timestamp. One row per changed field on updates.
- `notifications` — per-user or broadcast (`user_id IS NULL`); types:
  awaiting_action, overdue, vendor_delay.
- `settings` — key/value (org name, number prefixes, overdue thresholds,
  default currency).

## Indexing

Foreign keys used in list filters are indexed
(`current_stage_id`, `department_id`, `vendor_id`, `printer_id`,
`assigned_to`, `date_received`), plus `(ticket_id, created_at)` on the history
table and `(entity_type, entity_id)` on audit logs. At the expected volume
(hundreds–thousands of tickets/year, ≤25 users) every query in the app is
millisecond-range.

## Future Expansion

To add a new asset class (e.g. computers):

1. Create the asset table (mirroring `printers`).
2. Insert its workflow rows into `workflow_stages` with
   `asset_type='computer'` (reuse the printer stages or define new ones).
3. Add a nullable `computer_id` FK to `tickets` (or introduce a polymorphic
   `asset_id` + `asset_type` pair — both are additive changes).

No existing table, query or history row changes. The status-derivation,
tracker, notification and reporting machinery all key off
`(asset_type, workflow_stages)` already.
