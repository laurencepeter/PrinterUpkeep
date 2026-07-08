-- ============================================================================
-- Migration 003: Extended printer details
--   * name (friendly name / hostname shown to users)
--   * network identity: ip_address, mac_address, connection_type
--   * lease terms: start/end dates + monthly cost (for leased printers)
--   * purchase info: date + cost (for owned printers)
--   * capabilities & servicing: colour/mono, consumables model,
--     last service / next service due (feeds servicing reminders)
-- ============================================================================

ALTER TABLE printers
    ADD COLUMN name               TEXT,
    ADD COLUMN ip_address         TEXT,
    ADD COLUMN mac_address        TEXT,
    ADD COLUMN connection_type    TEXT NOT NULL DEFAULT 'network'
        CHECK (connection_type IN ('network', 'wifi', 'usb', 'other')),
    ADD COLUMN is_color           BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN consumables_model  TEXT,
    ADD COLUMN lease_start        DATE,
    ADD COLUMN lease_end          DATE,
    ADD COLUMN lease_monthly_cost NUMERIC(12, 2),
    ADD COLUMN purchase_date      DATE,
    ADD COLUMN purchase_cost      NUMERIC(12, 2),
    ADD COLUMN last_service_date  DATE,
    ADD COLUMN next_service_due   DATE,
    ADD CONSTRAINT ck_printers_lease_dates
        CHECK (lease_start IS NULL OR lease_end IS NULL OR lease_end >= lease_start);

-- IP addresses should be unique on the network when set.
CREATE UNIQUE INDEX ux_printers_ip ON printers (ip_address) WHERE ip_address IS NOT NULL;

INSERT INTO settings (key, value, description) VALUES
    ('lease_expiry_warn_days', '30', 'Days before a printer lease ends to raise a dashboard alert'),
    ('service_due_warn_days',  '14', 'Days before a printer''s next service is due to raise an alert')
ON CONFLICT (key) DO NOTHING;
