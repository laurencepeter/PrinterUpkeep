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
  },
};
