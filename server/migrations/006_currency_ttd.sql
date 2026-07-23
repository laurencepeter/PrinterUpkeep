-- ============================================================================
-- Migration 006: Standardise on TTD (Trinidad & Tobago Dollar)
--
-- The system is used by a single organisation whose currency is TTD, so the
-- default currency setting, the quotations column default and any existing
-- quotation rows are all moved off the historical 'USD' placeholder.
-- New quotations follow the `default_currency` setting (see procurementRepo).
-- ============================================================================

UPDATE settings SET value = 'TTD' WHERE key = 'default_currency';

ALTER TABLE quotations ALTER COLUMN currency SET DEFAULT 'TTD';

UPDATE quotations SET currency = 'TTD' WHERE currency IS NULL OR currency = 'USD';
