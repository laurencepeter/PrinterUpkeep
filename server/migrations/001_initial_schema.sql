-- ============================================================================
-- ICT Printer Upkeep & Procurement Tracking System
-- Migration 001: Initial schema
--
-- Design notes:
--  * Workflow stages are data-driven (workflow_stages table) so new asset
--    types / workflows can be added later without schema changes.
--  * ticket_stage_history is INSERT-ONLY. The ticket's current stage is
--    derived from the latest history row. tickets.current_stage_id is a
--    denormalised cache updated in the same transaction as each history
--    insert, purely for fast listing/filtering; history is the source of
--    truth.
--  * tickets.asset_type defaults to 'printer' so computers, monitors,
--    network equipment etc. can be added later without refactoring.
-- ============================================================================

CREATE TABLE roles (
    id          SMALLSERIAL PRIMARY KEY,
    code        TEXT NOT NULL UNIQUE,          -- admin | ict_officer | viewer
    name        TEXT NOT NULL,
    description TEXT
);

CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username      TEXT NOT NULL UNIQUE,
    full_name     TEXT NOT NULL,
    email         TEXT UNIQUE,
    phone         TEXT,
    password_hash TEXT NOT NULL,
    role_id       SMALLINT NOT NULL REFERENCES roles(id),
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE departments (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name       TEXT NOT NULL UNIQUE,
    code       TEXT UNIQUE,
    building   TEXT,
    floor      TEXT,
    is_active  BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE vendors (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    company_name   TEXT NOT NULL,
    address        TEXT,
    phone          TEXT,
    email          TEXT,
    contact_person TEXT,
    website        TEXT,
    notes          TEXT,
    vendor_types   TEXT[] NOT NULL DEFAULT '{}',  -- printer | consumables | maintenance | other
    is_active      BOOLEAN NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Prevent duplicate vendors (case-insensitive company name).
CREATE UNIQUE INDEX ux_vendors_company_name ON vendors (lower(company_name));

CREATE TABLE printers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_number    TEXT NOT NULL UNIQUE,
    model           TEXT NOT NULL,
    serial_number   TEXT UNIQUE,
    printer_type    TEXT NOT NULL DEFAULT 'owned'
                    CHECK (printer_type IN ('owned', 'leased')),
    department_id   UUID REFERENCES departments(id),
    location        TEXT,
    building        TEXT,
    floor           TEXT,
    vendor_id       UUID REFERENCES vendors(id),
    warranty_expiry DATE,
    status          TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'repair', 'disposed')),
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Data-driven issue categories so admins can extend the dropdown.
CREATE TABLE issue_categories (
    id         SMALLSERIAL PRIMARY KEY,
    name       TEXT NOT NULL UNIQUE,
    sort_order SMALLINT NOT NULL DEFAULT 0,
    is_active  BOOLEAN NOT NULL DEFAULT TRUE
);

-- Data-driven workflow. asset_type allows different workflows per asset
-- class in the future (e.g. 'computer', 'network').
CREATE TABLE workflow_stages (
    id          SMALLSERIAL PRIMARY KEY,
    asset_type  TEXT NOT NULL DEFAULT 'printer',
    code        TEXT NOT NULL,
    name        TEXT NOT NULL,               -- display name, e.g. "Funds Confirmed"
    status_label TEXT NOT NULL,              -- derived ticket status, e.g. "Awaiting GA"
    sort_order  SMALLINT NOT NULL,
    is_terminal BOOLEAN NOT NULL DEFAULT FALSE,
    UNIQUE (asset_type, code),
    UNIQUE (asset_type, sort_order)
);

CREATE TABLE tickets (
    id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_number        TEXT NOT NULL UNIQUE,      -- ICT-2026-000001, auto-generated
    asset_type           TEXT NOT NULL DEFAULT 'printer',
    date_received        DATE NOT NULL DEFAULT CURRENT_DATE,
    time_received        TIME NOT NULL DEFAULT CURRENT_TIME,
    ict_ticket_number    TEXT,
    vendor_ticket_number TEXT,
    reported_by          TEXT NOT NULL,
    department_id        UUID REFERENCES departments(id),
    contact_phone        TEXT,
    contact_email        TEXT,
    reporting_method     TEXT NOT NULL DEFAULT 'walk_in'
                         CHECK (reporting_method IN
                           ('walk_in', 'phone', 'email', 'ict_ticket', 'vendor_ticket')),
    printer_id           UUID REFERENCES printers(id),
    issue_category_id    SMALLINT REFERENCES issue_categories(id),
    priority             TEXT NOT NULL DEFAULT 'medium'
                         CHECK (priority IN ('low', 'medium', 'high', 'critical')),
    description          TEXT,
    vendor_id            UUID REFERENCES vendors(id),
    assigned_to          UUID REFERENCES users(id),
    current_stage_id     SMALLINT NOT NULL REFERENCES workflow_stages(id),
    is_blocked           BOOLEAN NOT NULL DEFAULT FALSE,
    blocked_reason       TEXT,
    is_cancelled         BOOLEAN NOT NULL DEFAULT FALSE,
    cancelled_reason     TEXT,
    completion_date      DATE,
    remarks              TEXT,
    created_by           UUID NOT NULL REFERENCES users(id),
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_tickets_current_stage ON tickets (current_stage_id);
CREATE INDEX ix_tickets_department    ON tickets (department_id);
CREATE INDEX ix_tickets_vendor        ON tickets (vendor_id);
CREATE INDEX ix_tickets_printer       ON tickets (printer_id);
CREATE INDEX ix_tickets_assigned_to   ON tickets (assigned_to);
CREATE INDEX ix_tickets_date_received ON tickets (date_received);

-- Per-year sequence backing ICT-YYYY-NNNNNN ticket numbers.
CREATE TABLE ticket_sequences (
    prefix     TEXT NOT NULL,     -- 'ICT', 'REQ', 'PO'
    year       INT  NOT NULL,
    last_value INT  NOT NULL DEFAULT 0,
    PRIMARY KEY (prefix, year)
);

-- INSERT-ONLY. Never update or delete rows here.
CREATE TABLE ticket_stage_history (
    id         BIGSERIAL PRIMARY KEY,
    ticket_id  UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    stage_id   SMALLINT NOT NULL REFERENCES workflow_stages(id),
    changed_by UUID NOT NULL REFERENCES users(id),
    notes      TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_stage_history_ticket ON ticket_stage_history (ticket_id, created_at);

CREATE TABLE ticket_notes (
    id         BIGSERIAL PRIMARY KEY,
    ticket_id  UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    user_id    UUID NOT NULL REFERENCES users(id),
    note       TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE ticket_files (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id    UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    category     TEXT NOT NULL DEFAULT 'document'
                 CHECK (category IN ('screenshot', 'photo', 'document', 'quotation',
                                     'requisition', 'purchase_order', 'delivery_note')),
    file_name    TEXT NOT NULL,
    mime_type    TEXT NOT NULL,
    size_bytes   BIGINT NOT NULL,
    storage_path TEXT NOT NULL,
    uploaded_by  UUID NOT NULL REFERENCES users(id),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_ticket_files_ticket ON ticket_files (ticket_id);

CREATE TABLE quotations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id           UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    vendor_id           UUID REFERENCES vendors(id),
    vendor_contact_date DATE,
    requested_date      DATE,
    received_date       DATE,
    quotation_number    TEXT,
    amount              NUMERIC(14, 2),
    currency            TEXT NOT NULL DEFAULT 'USD',
    file_id             UUID REFERENCES ticket_files(id),
    notes               TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_quotations_ticket ON quotations (ticket_id);

CREATE TABLE requisitions (
    id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id          UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    requisition_number TEXT NOT NULL UNIQUE,       -- REQ-YYYY-NNNN, auto-generated
    prepared_date      DATE NOT NULL DEFAULT CURRENT_DATE,
    signed_file_id     UUID REFERENCES ticket_files(id),
    notes              TEXT,
    created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Accounts / GA approvals share one structure; approval_type discriminates.
CREATE TABLE approvals (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id     UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    approval_type TEXT NOT NULL CHECK (approval_type IN ('accounts', 'ga')),
    sent_date     DATE,
    decision      TEXT NOT NULL DEFAULT 'pending'
                  CHECK (decision IN ('pending', 'approved', 'rejected', 'funds_available',
                                      'funds_unavailable')),
    decision_date DATE,
    notes         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_approvals_ticket ON approvals (ticket_id, approval_type);

CREATE TABLE purchase_orders (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id   UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    po_number   TEXT NOT NULL UNIQUE,
    issued_date DATE NOT NULL DEFAULT CURRENT_DATE,
    file_id     UUID REFERENCES ticket_files(id),
    notes       TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE delivery_notes (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    ticket_id     UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    dn_number     TEXT,
    received_date DATE,
    file_id       UUID REFERENCES ticket_files(id),
    notes         TEXT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE audit_logs (
    id          BIGSERIAL PRIMARY KEY,
    entity_type TEXT NOT NULL,       -- ticket | vendor | printer | department | user | ...
    entity_id   TEXT NOT NULL,
    action      TEXT NOT NULL,       -- create | update | delete | stage_change | login | ...
    field       TEXT,
    old_value   TEXT,
    new_value   TEXT,
    user_id     UUID REFERENCES users(id),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_audit_entity ON audit_logs (entity_type, entity_id);
CREATE INDEX ix_audit_created ON audit_logs (created_at);

CREATE TABLE notifications (
    id         BIGSERIAL PRIMARY KEY,
    user_id    UUID REFERENCES users(id),   -- NULL = broadcast to all users
    ticket_id  UUID REFERENCES tickets(id) ON DELETE CASCADE,
    type       TEXT NOT NULL,               -- awaiting_action | overdue | vendor_delay | approval
    title      TEXT NOT NULL,
    message    TEXT NOT NULL,
    is_read    BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_notifications_user ON notifications (user_id, is_read);

CREATE TABLE settings (
    key         TEXT PRIMARY KEY,
    value       TEXT NOT NULL,
    description TEXT,
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
