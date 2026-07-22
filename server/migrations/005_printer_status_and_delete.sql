-- ============================================================================
-- Migration 005: Administrative printer controls
--
--   * Add an 'inactive' printer status (an active printer temporarily taken
--     out of service — distinct from 'disposed', which is retired for good).
--   * Allow a system administrator to delete a printer even when maintenance
--     tickets reference it: the ticket history is preserved and its printer
--     link is set to NULL (the deletion, and the tickets it was linked to, are
--     captured in the audit log before the row is removed).
-- ============================================================================

ALTER TABLE printers DROP CONSTRAINT IF EXISTS printers_status_check;
ALTER TABLE printers ADD CONSTRAINT printers_status_check
    CHECK (status IN ('active', 'inactive', 'repair', 'disposed'));

-- Preserve ticket history when a printer is deleted (link becomes NULL rather
-- than blocking the delete or cascading the tickets away).
ALTER TABLE tickets DROP CONSTRAINT IF EXISTS tickets_printer_id_fkey;
ALTER TABLE tickets ADD CONSTRAINT tickets_printer_id_fkey
    FOREIGN KEY (printer_id) REFERENCES printers(id) ON DELETE SET NULL;
