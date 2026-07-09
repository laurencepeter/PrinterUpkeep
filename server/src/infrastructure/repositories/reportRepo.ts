import { query } from '../../db/pool';

export const reportRepo = {
  /** Monthly repairs/requests over the last N months. */
  async monthlyRepairs(months = 12) {
    return query(
      `SELECT to_char(date_trunc('month', date_received), 'YYYY-MM') AS month,
              count(*)::int AS total,
              count(*) FILTER (WHERE completion_date IS NOT NULL)::int AS completed
       FROM tickets
       WHERE date_received >= date_trunc('month', CURRENT_DATE) - ($1 || ' months')::interval
       GROUP BY 1 ORDER BY 1`,
      [months - 1],
    );
  },

  /** Vendor performance: volume, avg completion days, total quoted amount. */
  async vendorPerformance() {
    return query(`
      SELECT v.company_name AS vendor,
             count(t.id)::int AS tickets,
             count(t.id) FILTER (WHERE t.completion_date IS NOT NULL)::int AS completed,
             round(avg(t.completion_date - t.date_received) FILTER (WHERE t.completion_date IS NOT NULL), 1) AS avg_days,
             COALESCE(sum(q.amount), 0) AS total_quoted
      FROM vendors v
      LEFT JOIN tickets t ON t.vendor_id = v.id
      LEFT JOIN quotations q ON q.ticket_id = t.id
      GROUP BY v.id, v.company_name
      HAVING count(t.id) > 0
      ORDER BY tickets DESC
    `);
  },

  async departmentUsage() {
    return query(`
      SELECT d.name AS department,
             count(t.id)::int AS tickets,
             count(DISTINCT t.printer_id)::int AS printers_affected,
             round(avg(t.completion_date - t.date_received) FILTER (WHERE t.completion_date IS NOT NULL), 1) AS avg_days
      FROM departments d
      LEFT JOIN tickets t ON t.department_id = d.id
      GROUP BY d.id, d.name
      ORDER BY tickets DESC
    `);
  },

  async averageRepairTime() {
    return query(`
      SELECT to_char(date_trunc('month', completion_date), 'YYYY-MM') AS month,
             round(avg(completion_date - date_received), 1) AS avg_days,
             count(*)::int AS completed
      FROM tickets
      WHERE completion_date IS NOT NULL
      GROUP BY 1 ORDER BY 1
    `);
  },

  async consumablesCost() {
    return query(`
      SELECT to_char(date_trunc('month', t.date_received), 'YYYY-MM') AS month,
             COALESCE(sum(q.amount), 0) AS amount
      FROM tickets t
      JOIN issue_categories ic ON ic.id = t.issue_category_id AND ic.name = 'Consumables'
      LEFT JOIN quotations q ON q.ticket_id = t.id
      GROUP BY 1 ORDER BY 1
    `);
  },

  async commonIssues() {
    return query(`
      SELECT COALESCE(ic.name, 'Uncategorised') AS issue, count(*)::int AS count
      FROM tickets t LEFT JOIN issue_categories ic ON ic.id = t.issue_category_id
      GROUP BY 1 ORDER BY count DESC
    `);
  },

  async mostRepairedPrinters(limit = 15) {
    return query(
      `SELECT p.asset_number, p.model, p.printer_type, d.name AS department,
              count(t.id)::int AS repairs
       FROM printers p
       JOIN tickets t ON t.printer_id = p.id
       LEFT JOIN departments d ON d.id = p.department_id
       GROUP BY p.id, p.asset_number, p.model, p.printer_type, d.name
       ORDER BY repairs DESC LIMIT $1`,
      [limit],
    );
  },

  async ticketsByOfficer() {
    return query(`
      SELECT u.full_name AS officer,
             count(t.id)::int AS assigned,
             count(t.id) FILTER (WHERE t.completion_date IS NOT NULL)::int AS completed,
             round(avg(t.completion_date - t.date_received) FILTER (WHERE t.completion_date IS NOT NULL), 1) AS avg_days
      FROM users u
      JOIN tickets t ON t.assigned_to = u.id
      GROUP BY u.id, u.full_name
      ORDER BY assigned DESC
    `);
  },

  async ownedVsLeased() {
    return query(`
      SELECT COALESCE(p.printer_type, 'unknown') AS type,
             count(t.id)::int AS tickets,
             round(avg(t.completion_date - t.date_received) FILTER (WHERE t.completion_date IS NOT NULL), 1) AS avg_days,
             COALESCE(sum(q.amount), 0) AS total_cost
      FROM tickets t
      LEFT JOIN printers p ON p.id = t.printer_id
      LEFT JOIN quotations q ON q.ticket_id = t.id
      GROUP BY 1 ORDER BY 1
    `);
  },
};
