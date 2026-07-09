-- ============================================================================
-- Migration 002: Reference data (roles, workflow stages, issue categories,
-- default settings). Idempotent inserts so re-running is safe.
-- ============================================================================

INSERT INTO roles (code, name, description) VALUES
    ('admin',       'Administrator', 'Full access including user management and settings'),
    ('ict_officer', 'ICT Officer',   'Create and manage tickets, vendors, printers, departments'),
    ('viewer',      'Viewer',        'Read-only access to dashboards, tickets and reports')
ON CONFLICT (code) DO NOTHING;

-- The printer procurement/repair lifecycle. Status labels are what tickets
-- display; the stage name is what the workflow tracker displays.
INSERT INTO workflow_stages (asset_type, code, name, status_label, sort_order, is_terminal) VALUES
    ('printer', 'open',                 'Open',                    'Open',                    1,  FALSE),
    ('printer', 'ict_ticket_received',  'ICT Ticket Received',     'Open',                    2,  FALSE),
    ('printer', 'vendor_contacted',     'Vendor Contacted',        'Vendor Contacted',        3,  FALSE),
    ('printer', 'quotation_received',   'Quotation Received',      'Awaiting Quote',          4,  FALSE),
    ('printer', 'requisition_prepared', 'Requisition Prepared',    'Awaiting Funds',          5,  FALSE),
    ('printer', 'sent_to_accounts',     'Sent to Accounts',        'Awaiting Accounts',       6,  FALSE),
    ('printer', 'funds_confirmed',      'Funds Confirmed',         'Awaiting Accounts',       7,  FALSE),
    ('printer', 'sent_to_ga',           'Sent to GA',              'Awaiting GA',             8,  FALSE),
    ('printer', 'ga_approved',          'GA Approved',             'Awaiting Purchase Order', 9,  FALSE),
    ('printer', 'po_issued',            'Purchase Order Issued',   'Work In Progress',        10, FALSE),
    ('printer', 'vendor_wip',           'Vendor Work In Progress', 'Work In Progress',        11, FALSE),
    ('printer', 'completed',            'Completed',               'Completed',               12, FALSE),
    ('printer', 'closed',               'Closed',                  'Closed',                  13, TRUE),
    ('printer', 'cancelled',            'Cancelled',               'Cancelled',               99, TRUE)
ON CONFLICT (asset_type, code) DO NOTHING;

INSERT INTO issue_categories (name, sort_order) VALUES
    ('No Power',           1),
    ('Paper Jam',          2),
    ('Poor Print Quality', 3),
    ('Network',            4),
    ('Scanner',            5),
    ('Consumables',        6),
    ('Hardware Failure',   7),
    ('Maintenance',        8),
    ('Other',              9)
ON CONFLICT (name) DO NOTHING;

INSERT INTO settings (key, value, description) VALUES
    ('org_name',            'Ministry ICT Department', 'Organisation name shown in the app and on PDFs'),
    ('ticket_prefix',       'ICT',  'Prefix for auto-generated ticket numbers'),
    ('requisition_prefix',  'REQ',  'Prefix for auto-generated requisition numbers'),
    ('overdue_days',        '7',    'Days without a stage change before a ticket is flagged overdue'),
    ('vendor_delay_days',   '5',    'Days waiting on a vendor before flagging a vendor delay'),
    ('default_currency',    'USD',  'Default currency for quotation amounts')
ON CONFLICT (key) DO NOTHING;
