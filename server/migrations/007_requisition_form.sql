-- ============================================================================
-- Migration 007: Government requisition form
--
-- Turns the requisition into a fully auto-generated procurement form matching
-- the Ministry's paper "REQUISITION FORM": a header (coat of arms + government
-- + ministry name), requester details, a priced line-item table with VAT, a
-- justification memo, and the approval blocks. The generated PDF is print-ready
-- so officers only sign, stamp and forward it.
-- ============================================================================

-- Form-level fields on the requisition itself. All nullable so existing rows
-- and the "just generate one" flow keep working; the officer fills them in.
ALTER TABLE requisitions
    ADD COLUMN IF NOT EXISTS requested_by        TEXT,
    ADD COLUMN IF NOT EXISTS department_name     TEXT,
    ADD COLUMN IF NOT EXISTS file_number         TEXT,
    ADD COLUMN IF NOT EXISTS supply_priority     TEXT
        CHECK (supply_priority IN ('emergency', 'urgent', 'regular')),
    ADD COLUMN IF NOT EXISTS memorandum          TEXT,
    ADD COLUMN IF NOT EXISTS prepared_by         TEXT,   -- Head of Department
    ADD COLUMN IF NOT EXISTS vat_rate            NUMERIC(5, 2) NOT NULL DEFAULT 12.5,
    -- Accounts department / accounting officer block
    ADD COLUMN IF NOT EXISTS expense_code        TEXT,
    ADD COLUMN IF NOT EXISTS annual_budget       NUMERIC(14, 2),
    ADD COLUMN IF NOT EXISTS expenditure_to_date NUMERIC(14, 2),
    ADD COLUMN IF NOT EXISTS amount_available    NUMERIC(14, 2),
    ADD COLUMN IF NOT EXISTS authorised_manager  TEXT,
    ADD COLUMN IF NOT EXISTS accounting_officer  TEXT;

-- Priced line items shown in the form's central table.
CREATE TABLE IF NOT EXISTS requisition_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requisition_id  UUID NOT NULL REFERENCES requisitions(id) ON DELETE CASCADE,
    sort_order      SMALLINT NOT NULL DEFAULT 0,
    quantity        NUMERIC(12, 2) NOT NULL DEFAULT 1,
    unit            TEXT,                              -- e.g. "each", "box", "ream"
    description     TEXT NOT NULL,                     -- Description of Works/Goods/Services
    unit_price      NUMERIC(14, 2) NOT NULL DEFAULT 0, -- Estimated Unit Price ($TT)
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ix_requisition_items_req ON requisition_items (requisition_id, sort_order);

-- Header / branding settings used by the generated form. Defaults match the
-- Ministry of Rural Development and Local Government; org_logo optionally holds
-- a base64-encoded PNG of the coat of arms rendered at the top of the form.
INSERT INTO settings (key, value, description) VALUES
    ('org_gov_name', 'Government of the Republic of Trinidad and Tobago',
        'Government name printed above the ministry on official forms'),
    ('org_ministry', 'Ministry of Rural Development and Local Government',
        'Ministry name printed in the requisition form header'),
    ('vat_rate',     '12.5', 'VAT percentage applied to requisition totals'),
    ('org_logo',     '',     'Base64-encoded PNG (no data: prefix) of the coat of arms shown on forms')
ON CONFLICT (key) DO NOTHING;
