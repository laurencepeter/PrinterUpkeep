import { query } from '../db/pool';
import { notificationRepo } from '../infrastructure/repositories/notificationRepo';
import { settingsRepo } from '../infrastructure/repositories/lookupRepo';

/**
 * Periodic scan that raises dashboard notifications for overdue tickets and
 * vendor delays. Runs at startup and then hourly (see index.ts). Thresholds
 * are configurable in settings (overdue_days, vendor_delay_days).
 */
export const notificationService = {
  async scan(): Promise<void> {
    const overdueDays = await settingsRepo.getInt('overdue_days', 7);
    const vendorDelayDays = await settingsRepo.getInt('vendor_delay_days', 5);

    // Overdue: open tickets with no stage movement for N days.
    const overdue = await query(
      `SELECT t.id, t.ticket_number,
              EXTRACT(DAY FROM now() - h.last_change)::int AS stalled_days
       FROM tickets t
       JOIN workflow_stages ws ON ws.id = t.current_stage_id
       JOIN LATERAL (
         SELECT max(created_at) AS last_change FROM ticket_stage_history WHERE ticket_id = t.id
       ) h ON TRUE
       WHERE NOT ws.is_terminal AND ws.code NOT IN ('completed')
         AND h.last_change < now() - ($1 || ' days')::interval`,
      [overdueDays],
    );
    for (const t of overdue) {
      if (await notificationRepo.existsUnread(t.id as string, 'overdue')) continue;
      await notificationRepo.create({
        ticketId: t.id as string,
        type: 'overdue',
        title: 'Overdue ticket',
        message: `${t.ticket_number} has had no progress for ${t.stalled_days} days`,
      });
    }

    // Vendor delays: stuck at a vendor-facing stage for N days.
    const delayed = await query(
      `SELECT t.id, t.ticket_number, v.company_name,
              EXTRACT(DAY FROM now() - h.last_change)::int AS stalled_days
       FROM tickets t
       JOIN workflow_stages ws ON ws.id = t.current_stage_id
       LEFT JOIN vendors v ON v.id = t.vendor_id
       JOIN LATERAL (
         SELECT max(created_at) AS last_change FROM ticket_stage_history WHERE ticket_id = t.id
       ) h ON TRUE
       WHERE ws.code IN ('vendor_contacted', 'vendor_wip')
         AND h.last_change < now() - ($1 || ' days')::interval`,
      [vendorDelayDays],
    );
    for (const t of delayed) {
      if (await notificationRepo.existsUnread(t.id as string, 'vendor_delay')) continue;
      await notificationRepo.create({
        ticketId: t.id as string,
        type: 'vendor_delay',
        title: 'Vendor delay',
        message: `${t.ticket_number} waiting on ${t.company_name ?? 'vendor'} for ${t.stalled_days} days`,
      });
    }

    // Printer lease expiry warnings.
    const leaseWarnDays = await settingsRepo.getInt('lease_expiry_warn_days', 30);
    const expiringLeases = await query(
      `SELECT id, asset_number, COALESCE(name, model) AS display_name, lease_end,
              (lease_end - CURRENT_DATE)::int AS days_left
       FROM printers
       WHERE printer_type = 'leased' AND status <> 'disposed'
         AND lease_end IS NOT NULL
         AND lease_end <= CURRENT_DATE + ($1 || ' days')::interval
         AND lease_end >= CURRENT_DATE`,
      [leaseWarnDays],
    );
    for (const p of expiringLeases) {
      const message = `Lease for ${p.asset_number} (${p.display_name}) ends in ${p.days_left} days (${p.lease_end})`;
      if (await notificationExists('lease_expiry', message)) continue;
      await notificationRepo.create({ type: 'lease_expiry', title: 'Printer lease expiring', message });
    }

    // Scheduled servicing reminders.
    const serviceWarnDays = await settingsRepo.getInt('service_due_warn_days', 14);
    const serviceDue = await query(
      `SELECT id, asset_number, COALESCE(name, model) AS display_name, next_service_due,
              (next_service_due - CURRENT_DATE)::int AS days_left
       FROM printers
       WHERE status <> 'disposed'
         AND next_service_due IS NOT NULL
         AND next_service_due <= CURRENT_DATE + ($1 || ' days')::interval`,
      [serviceWarnDays],
    );
    for (const p of serviceDue) {
      const message =
        (p.days_left as number) < 0
          ? `Service for ${p.asset_number} (${p.display_name}) is overdue since ${p.next_service_due}`
          : `Service for ${p.asset_number} (${p.display_name}) due in ${p.days_left} days (${p.next_service_due})`;
      if (await notificationExists('service_due', message)) continue;
      await notificationRepo.create({ type: 'service_due', title: 'Printer service due', message });
    }
  },
};

/** Printer alerts carry no ticket_id; dedupe unread ones by exact message. */
async function notificationExists(type: string, message: string): Promise<boolean> {
  const rows = await query(
    `SELECT 1 FROM notifications WHERE type = $1 AND message = $2 AND NOT is_read LIMIT 1`,
    [type, message],
  );
  return rows.length > 0;
}
