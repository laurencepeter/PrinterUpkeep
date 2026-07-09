-- ============================================================================
-- Migration 004: Structured consumables catalogue + approval attribution
--
-- Goal: minimise typing / human error when raising a ticket. Admins define,
-- per printer, exactly which toners / drums / parts that printer takes (kind,
-- colour, model code). When a case is logged the reporter simply ticks which
-- colour(s) need replacing — no free typing of model numbers.
--
--   * printer_consumables — the per-printer catalogue (admin maintained)
--   * ticket_consumables  — which catalogue items a ticket requests; values
--     are snapshotted so history survives catalogue edits/removals.
--   * approvals.approved_by — the name of the Accounts/GA officer who
--     approved, so the IT approvals report can show "who approved & when".
-- ============================================================================

CREATE TABLE printer_consumables (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    printer_id  UUID NOT NULL REFERENCES printers(id) ON DELETE CASCADE,
    kind        TEXT NOT NULL DEFAULT 'toner'
                CHECK (kind IN ('toner', 'ink', 'drum', 'maintenance_kit',
                                'fuser', 'part', 'other')),
    -- NULL colour = not colour-specific (e.g. a drum unit or a fuser).
    color       TEXT
                CHECK (color IS NULL OR color IN
                       ('black', 'cyan', 'magenta', 'yellow', 'tricolor', 'other')),
    model_code  TEXT,                      -- e.g. "HP 26A (CF226A)"
    label       TEXT,                      -- friendly label, e.g. "Black Toner"
    sort_order  SMALLINT NOT NULL DEFAULT 0,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_printer_consumables_printer ON printer_consumables (printer_id);

-- Which consumables a ticket asked to be replaced. consumable_id is kept for
-- reference but the descriptive columns are snapshotted so a later catalogue
-- edit never rewrites historical tickets.
CREATE TABLE ticket_consumables (
    id            BIGSERIAL PRIMARY KEY,
    ticket_id     UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    consumable_id UUID REFERENCES printer_consumables(id) ON DELETE SET NULL,
    kind          TEXT,
    color         TEXT,
    label         TEXT,
    model_code    TEXT,
    quantity      SMALLINT NOT NULL DEFAULT 1,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX ix_ticket_consumables_ticket ON ticket_consumables (ticket_id);

ALTER TABLE approvals ADD COLUMN approved_by TEXT;
