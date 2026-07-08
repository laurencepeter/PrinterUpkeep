import { query, queryOne } from '../../db/pool';

export const dashboardRepo = {
  async stats() {
    const row = await queryOne(`
      SELECT
        count(*) FILTER (WHERE NOT ws.is_terminal AND ws.code <> 'completed')::int AS total_open,
        count(*) FILTER (WHERE ws.code = 'completed'
                         AND t.completion_date = CURRENT_DATE)::int               AS completed_today,
        count(*) FILTER (WHERE ws.code IN ('vendor_contacted', 'vendor_wip'))::int AS awaiting_vendor,
        count(*) FILTER (WHERE ws.status_label = 'Awaiting Quote')::int           AS awaiting_quote,
        count(*) FILTER (WHERE ws.status_label = 'Awaiting Accounts'
                         OR ws.status_label = 'Awaiting Funds')::int              AS awaiting_accounts,
        count(*) FILTER (WHERE ws.status_label = 'Awaiting GA')::int              AS awaiting_ga,
        count(*) FILTER (WHERE ws.status_label = 'Work In Progress')::int         AS work_in_progress,
        count(*) FILTER (WHERE ws.code = 'completed')::int                        AS completed,
        count(*) FILTER (WHERE ws.code = 'closed')::int                           AS closed,
        count(*) FILTER (WHERE ws.code = 'cancelled')::int                        AS cancelled,
        count(*) FILTER (WHERE t.is_blocked)::int                                 AS blocked
      FROM tickets t JOIN workflow_stages ws ON ws.id = t.current_stage_id
    `);

    const printers = await queryOne(`
      SELECT
        count(*) FILTER (WHERE printer_type = 'owned'  AND status <> 'disposed')::int AS owned_printers,
        count(*) FILTER (WHERE printer_type = 'leased' AND status <> 'disposed')::int AS leased_printers
      FROM printers
    `);

    // Average days from creation to the first 'completed' history entry.
    const avg = await queryOne<{ avg_days: string | null }>(`
      SELECT round(avg(EXTRACT(EPOCH FROM h.created_at - t.created_at) / 86400)::numeric, 1)::text AS avg_days
      FROM tickets t
      JOIN LATERAL (
        SELECT min(created_at) AS created_at
        FROM ticket_stage_history hh
        JOIN workflow_stages ws ON ws.id = hh.stage_id
        WHERE hh.ticket_id = t.id AND ws.code = 'completed'
      ) h ON h.created_at IS NOT NULL
    `);

    return {
      ...row,
      ...printers,
      avg_completion_days: avg?.avg_days === null ? null : parseFloat(avg!.avg_days!),
    };
  },

  async recentActivity(limit = 15) {
    return query(
      `SELECT h.created_at, t.id AS ticket_id, t.ticket_number,
              ws.name AS stage_name, ws.status_label, u.full_name AS changed_by_name, h.notes
       FROM ticket_stage_history h
       JOIN tickets t ON t.id = h.ticket_id
       JOIN workflow_stages ws ON ws.id = h.stage_id
       JOIN users u ON u.id = h.changed_by
       ORDER BY h.created_at DESC
       LIMIT $1`,
      [limit],
    );
  },

  async monthlyRequests(months = 12) {
    return query(
      `SELECT to_char(date_trunc('month', date_received), 'YYYY-MM') AS month, count(*)::int AS count
       FROM tickets
       WHERE date_received >= date_trunc('month', CURRENT_DATE) - ($1 || ' months')::interval
       GROUP BY 1 ORDER BY 1`,
      [months - 1],
    );
  },

  async byDepartment() {
    return query(`
      SELECT COALESCE(d.name, 'Unassigned') AS label, count(*)::int AS count
      FROM tickets t LEFT JOIN departments d ON d.id = t.department_id
      GROUP BY 1 ORDER BY count DESC LIMIT 12
    `);
  },

  async byVendor() {
    return query(`
      SELECT COALESCE(v.company_name, 'No Vendor') AS label, count(*)::int AS count
      FROM tickets t LEFT JOIN vendors v ON v.id = t.vendor_id
      GROUP BY 1 ORDER BY count DESC LIMIT 12
    `);
  },

  async ownedVsLeased() {
    return query(`
      SELECT COALESCE(p.printer_type, 'unknown') AS label, count(*)::int AS count
      FROM tickets t LEFT JOIN printers p ON p.id = t.printer_id
      GROUP BY 1 ORDER BY 1
    `);
  },

  async statusBreakdown() {
    return query(`
      SELECT ws.status_label AS label, count(*)::int AS count
      FROM tickets t JOIN workflow_stages ws ON ws.id = t.current_stage_id
      GROUP BY ws.status_label ORDER BY min(ws.sort_order)
    `);
  },
};
