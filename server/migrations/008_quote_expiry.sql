-- Target the PrinterUpkeep schema (see migration 001).
SET search_path TO printerupkeep, public;

-- ============================================================================
-- Migration 008: Quotation validity / expiry reminders
--
-- Vendors' quotations are only valid for a limited period. Officers record the
-- date on the quote and its expiry date; the hourly notification scan and the
-- ticket detail screen then warn (yellow) and escalate (red) as expiry nears,
-- with next steps based on where the ticket is in the approval chain.
-- ============================================================================

ALTER TABLE quotations
    ADD COLUMN IF NOT EXISTS quote_date  DATE,
    ADD COLUMN IF NOT EXISTS expiry_date DATE;

ALTER TABLE quotations
    ADD CONSTRAINT ck_quotations_expiry_after_quote
        CHECK (quote_date IS NULL OR expiry_date IS NULL OR expiry_date >= quote_date);

CREATE INDEX IF NOT EXISTS ix_quotations_expiry ON quotations (expiry_date)
    WHERE expiry_date IS NOT NULL;

INSERT INTO settings (key, value, description) VALUES
    ('quote_expiry_warn_days',     '15', 'Days before a quotation expires to raise a yellow (warning) reminder'),
    ('quote_expiry_critical_days', '10', 'Days before a quotation expires to escalate to a red (critical) reminder')
ON CONFLICT (key) DO NOTHING;
