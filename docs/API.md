# REST API Reference

Base URL: `/api`. All responses are JSON (snake_case keys). All endpoints
except `POST /api/auth/login` and `GET /api/health` require a JWT:

```
Authorization: Bearer <token>
```

For browser downloads (exports, files, PDFs) the token may instead be passed
as a `?token=` query parameter.

**Roles:** `viewer` (read-only), `ict_officer` (all reads + writes except user
management and system settings), `admin` (everything).

**Errors** are always `{ "error": { "code": "...", "message": "..." } }` with
an appropriate HTTP status (400 validation, 401 auth, 403 permission,
404 missing, 409 duplicate/conflict, 500 internal).

---

## Auth

| Method | Path | Role | Description |
|---|---|---|---|
| POST | `/auth/login` | — | `{username, password}` → `{token, user}` |
| GET  | `/auth/me` | any | Current user profile |
| POST | `/auth/change-password` | any | `{currentPassword, newPassword}` |

## Lookups (dropdown data)

| Method | Path | Description |
|---|---|---|
| GET | `/lookups/workflow-stages?asset_type=printer` | Ordered workflow stages |
| GET | `/lookups/issue-categories` | Issue category dropdown |
| GET | `/lookups/roles` | Role list |
| GET | `/lookups/enums` | Priorities, reporting methods, printer/vendor types, file categories |

## Tickets

| Method | Path | Role | Description |
|---|---|---|---|
| GET | `/tickets` | any | Paged list. Filters: `search`, `status`, `stages` (csv of codes), `department_id`, `vendor_id`, `printer_id`, `assigned_to`, `priority`, `printer_type` (owned/leased), `issue_category_id`, `date_from`, `date_to`, `open_only`, `page`, `page_size` |
| GET | `/tickets/:id` | any | Full detail: ticket, `progress` (0–1), `tracker` (per-stage state: done/current/waiting/blocked/not_started), `history`, `notes`, `files`, `quotations`, `requisitions`, `approvals`, `purchase_orders`, `delivery_notes` |
| POST | `/tickets` | officer | Create. `reportedBy` required; ticket number auto-generated (`ICT-YYYY-NNNNNN`); starts at stage `open` |
| PATCH | `/tickets/:id` | officer | Update fields incl. `isBlocked`/`blockedReason` |
| POST | `/tickets/:id/stage` | officer | `{stage: <code>, notes?}` — inserts stage history (timestamp + user + notes), never overwrites |
| GET | `/tickets/:id/history` | any | Full stage history |
| POST | `/tickets/:id/notes` | officer | `{note}` |
| POST | `/tickets/:id/quotations` | officer | Create/update (`id` present = update) quotation |
| POST | `/tickets/:id/requisitions` | officer | Create (number auto-generated `REQ-YYYY-NNNN`) or update |
| GET | `/tickets/:id/requisitions/:reqId/pdf` | any | Printable requisition PDF for signing |
| POST | `/tickets/:id/approvals/accounts` | officer | `{sentDate?, decision?, decisionDate?, notes?}` — decisions: pending / funds_available / funds_unavailable |
| POST | `/tickets/:id/approvals/ga` | officer | decisions: pending / approved / rejected |
| POST | `/tickets/:id/purchase-orders` | officer | `{poNumber, issuedDate?, fileId?}` |
| POST | `/tickets/:id/delivery-notes` | officer | `{dnNumber?, receivedDate?, fileId?}` |

Workflow stage codes, in order: `open`, `ict_ticket_received`,
`vendor_contacted`, `quotation_received`, `requisition_prepared`,
`sent_to_accounts`, `funds_confirmed`, `sent_to_ga`, `ga_approved`,
`po_issued`, `vendor_wip`, `completed`, `closed`; plus `cancelled`. Backward
moves are allowed (real processes loop); terminal stages accept no moves.

## Vendors / Printers / Departments / Users

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/vendors?search=&include_inactive=` | any | |
| POST | `/vendors` | officer | 409 on duplicate company name (case-insensitive) |
| PATCH | `/vendors/:id` | officer | |
| DELETE | `/vendors/:id` | officer | Deactivates (never deletes) |
| GET | `/printers?search=&department_id=&printer_type=&status=` | any | |
| GET | `/printers/:id/history` | any | Maintenance history (all tickets for the printer) |
| POST/PATCH | `/printers…` | officer | |
| GET/POST/PATCH/DELETE | `/departments…` | officer (writes) | DELETE deactivates |
| GET | `/users` | any | Needed for "Assigned to" dropdowns |
| POST/PATCH | `/users…` | admin | Passwords bcrypt-hashed |

## Dashboard, Reports, Exports

| Method | Path | Description |
|---|---|---|
| GET | `/dashboard` | Stats (open, completed today, awaiting vendor/quote/accounts/GA, WIP, completed, closed, owned/leased printers, avg completion days), recent activity, and chart datasets |
| GET | `/reports` | List of report keys |
| GET | `/reports/:key?format=json\|csv\|xlsx\|pdf` | Reports: `monthly-repairs`, `vendor-performance`, `department-usage`, `average-repair-time`, `consumables-cost`, `common-issues`, `most-repaired-printers`, `tickets-by-officer`, `owned-vs-leased` |
| GET | `/export/:entity?format=csv\|xlsx\|pdf\|json` | Entities: `tickets` (accepts ticket filters), `vendors`, `printers`, `departments` |
| POST | `/export/import/:entity` | Multipart upload (`file`: .csv/.xlsx/.json) for `vendors`, `printers`, `departments`. Duplicates are validated and reported, never overwritten |

## Files

| Method | Path | Description |
|---|---|---|
| POST | `/files/tickets/:ticketId?category=` | Multipart upload. Categories: screenshot, photo, document, quotation, requisition, purchase_order, delivery_note. Allowed types: images, PDF, Office docs, text/CSV. Max size via `MAX_FILE_SIZE_MB` |
| GET | `/files/:id` | Download/stream |
| DELETE | `/files/:id` | Remove attachment |

## Notifications, Audit, Settings

| Method | Path | Description |
|---|---|---|
| GET | `/notifications?unread_only=` | Own + broadcast notifications |
| POST | `/notifications/scan` | Force overdue/vendor-delay scan (also runs hourly) |
| POST | `/notifications/:id/read`, `/notifications/read-all` | Mark read |
| GET | `/audit-logs?entity_type=&entity_id=&user_id=&page=` | Every change: old value, new value, user, timestamp |
| GET | `/settings` | All settings |
| PUT | `/settings/:key` (admin) | `{value}` — e.g. `org_name`, `overdue_days`, `vendor_delay_days` |
