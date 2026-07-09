import { PoolClient } from 'pg';
import { query, queryOne, withTransaction } from '../../db/pool';

export interface TicketFilters {
  search?: string;          // matches ticket number, reporter, description
  stageCodes?: string[];
  statusLabel?: string;
  departmentId?: string;
  vendorId?: string;
  printerId?: string;
  assignedTo?: string;
  priority?: string;
  printerType?: string;     // owned | leased
  issueCategoryId?: number;
  dateFrom?: string;
  dateTo?: string;
  openOnly?: boolean;
  page: number;
  pageSize: number;
}

const LIST_COLUMNS = `
  t.id, t.ticket_number, t.date_received, t.time_received, t.reported_by,
         t.priority, t.is_blocked, t.is_cancelled, t.created_at, t.updated_at,
         t.ict_ticket_number, t.vendor_ticket_number, t.completion_date,
         d.name  AS department_name,
         v.company_name AS vendor_name,
         p.asset_number AS printer_asset_number, p.model AS printer_model,
         p.printer_type,
         ic.name AS issue_category,
         au.full_name AS assigned_to_name, t.assigned_to,
         ws.id AS stage_id, ws.code AS stage_code, ws.name AS stage_name,
         ws.status_label, ws.sort_order AS stage_sort_order, ws.is_terminal`;

const LIST_FROM = `
  FROM tickets t
  JOIN workflow_stages ws ON ws.id = t.current_stage_id
  LEFT JOIN departments d ON d.id = t.department_id
  LEFT JOIN vendors v ON v.id = t.vendor_id
  LEFT JOIN printers p ON p.id = t.printer_id
  LEFT JOIN issue_categories ic ON ic.id = t.issue_category_id
  LEFT JOIN users au ON au.id = t.assigned_to`;

function buildWhere(filters: TicketFilters): { whereSql: string; params: unknown[] } {
  const where: string[] = [];
  const params: unknown[] = [];
  const add = (clause: (n: number) => string, value: unknown) => {
    params.push(value);
    where.push(clause(params.length));
  };

  if (filters.search) {
    add(
      (n) =>
        `(t.ticket_number ILIKE $${n} OR t.reported_by ILIKE $${n} OR t.description ILIKE $${n}
          OR t.ict_ticket_number ILIKE $${n} OR t.vendor_ticket_number ILIKE $${n})`,
      `%${filters.search}%`,
    );
  }
  if (filters.stageCodes?.length) add((n) => `ws.code = ANY($${n})`, filters.stageCodes);
  if (filters.statusLabel) add((n) => `ws.status_label = $${n}`, filters.statusLabel);
  if (filters.departmentId) add((n) => `t.department_id = $${n}`, filters.departmentId);
  if (filters.vendorId) add((n) => `t.vendor_id = $${n}`, filters.vendorId);
  if (filters.printerId) add((n) => `t.printer_id = $${n}`, filters.printerId);
  if (filters.assignedTo) add((n) => `t.assigned_to = $${n}`, filters.assignedTo);
  if (filters.priority) add((n) => `t.priority = $${n}`, filters.priority);
  if (filters.printerType) add((n) => `p.printer_type = $${n}`, filters.printerType);
  if (filters.issueCategoryId) add((n) => `t.issue_category_id = $${n}`, filters.issueCategoryId);
  if (filters.dateFrom) add((n) => `t.date_received >= $${n}`, filters.dateFrom);
  if (filters.dateTo) add((n) => `t.date_received <= $${n}`, filters.dateTo);
  if (filters.openOnly) where.push(`NOT ws.is_terminal AND ws.code NOT IN ('completed')`);

  return { whereSql: where.length ? `WHERE ${where.join(' AND ')}` : '', params };
}

export const ticketRepo = {
  /**
   * Atomically allocate the next number for a prefix/year, e.g.
   * ('ICT', 2026) -> 'ICT-2026-000001'. Row-level lock via upsert keeps
   * numbers gap-free and race-safe.
   */
  async nextNumber(client: PoolClient, prefix: string, pad = 6): Promise<string> {
    const year = new Date().getFullYear();
    const result = await client.query(
      `INSERT INTO ticket_sequences (prefix, year, last_value) VALUES ($1, $2, 1)
       ON CONFLICT (prefix, year) DO UPDATE SET last_value = ticket_sequences.last_value + 1
       RETURNING last_value`,
      [prefix, year],
    );
    const n: number = result.rows[0].last_value;
    return `${prefix}-${year}-${String(n).padStart(pad, '0')}`;
  },

  async list(filters: TicketFilters) {
    const { whereSql, params } = buildWhere(filters);
    const totalRow = await query<{ count: string }>(
      `SELECT count(*)::text AS count FROM tickets t
       JOIN workflow_stages ws ON ws.id = t.current_stage_id
       LEFT JOIN printers p ON p.id = t.printer_id
       ${whereSql}`,
      params,
    );
    const listParams = [...params, filters.pageSize, (filters.page - 1) * filters.pageSize];
    const items = await query(
      `SELECT ${LIST_COLUMNS} ${LIST_FROM} ${whereSql}
       ORDER BY t.created_at DESC
       LIMIT $${listParams.length - 1} OFFSET $${listParams.length}`,
      listParams,
    );
    return { items, total: parseInt(totalRow[0].count, 10), page: filters.page, pageSize: filters.pageSize };
  },

  /** Full rows matching filters, for export (no pagination). */
  async listForExport(filters: TicketFilters) {
    const { whereSql, params } = buildWhere(filters);
    return query(
      `SELECT ${LIST_COLUMNS}, t.description, t.contact_phone, t.contact_email, t.reporting_method, t.remarks
       ${LIST_FROM} ${whereSql} ORDER BY t.created_at DESC`,
      params,
    );
  },

  async byId(id: string) {
    return queryOne(
      `SELECT t.*,
              d.name AS department_name,
              v.company_name AS vendor_name,
              p.asset_number AS printer_asset_number, p.model AS printer_model,
              p.printer_type, p.serial_number AS printer_serial,
              p.location AS printer_location, p.building AS printer_building,
              p.floor AS printer_floor,
              ic.name AS issue_category,
              au.full_name AS assigned_to_name,
              cu.full_name AS created_by_name,
              ws.id AS stage_id, ws.code AS stage_code, ws.name AS stage_name,
              ws.status_label, ws.sort_order AS stage_sort_order, ws.is_terminal
       FROM tickets t
       JOIN workflow_stages ws ON ws.id = t.current_stage_id
       LEFT JOIN departments d ON d.id = t.department_id
       LEFT JOIN vendors v ON v.id = t.vendor_id
       LEFT JOIN printers p ON p.id = t.printer_id
       LEFT JOIN issue_categories ic ON ic.id = t.issue_category_id
       LEFT JOIN users au ON au.id = t.assigned_to
       LEFT JOIN users cu ON cu.id = t.created_by
       WHERE t.id = $1`,
      [id],
    );
  },

  async stageHistory(ticketId: string) {
    return query(
      `SELECT h.id, h.notes, h.created_at,
              ws.code AS stage_code, ws.name AS stage_name, ws.status_label, ws.sort_order,
              u.full_name AS changed_by_name
       FROM ticket_stage_history h
       JOIN workflow_stages ws ON ws.id = h.stage_id
       JOIN users u ON u.id = h.changed_by
       WHERE h.ticket_id = $1
       ORDER BY h.created_at, h.id`,
      [ticketId],
    );
  },

  async notes(ticketId: string) {
    return query(
      `SELECT n.id, n.note, n.created_at, u.full_name AS user_name
       FROM ticket_notes n JOIN users u ON u.id = n.user_id
       WHERE n.ticket_id = $1 ORDER BY n.created_at DESC`,
      [ticketId],
    );
  },

  async addNote(ticketId: string, userId: string, note: string) {
    return queryOne(
      `INSERT INTO ticket_notes (ticket_id, user_id, note) VALUES ($1, $2, $3) RETURNING *`,
      [ticketId, userId, note],
    );
  },

  async files(ticketId: string) {
    return query(
      `SELECT f.id, f.category, f.file_name, f.mime_type, f.size_bytes, f.created_at,
              u.full_name AS uploaded_by_name
       FROM ticket_files f JOIN users u ON u.id = f.uploaded_by
       WHERE f.ticket_id = $1 ORDER BY f.created_at DESC`,
      [ticketId],
    );
  },

  async quotations(ticketId: string) {
    return query(
      `SELECT q.*, v.company_name AS vendor_name FROM quotations q
       LEFT JOIN vendors v ON v.id = q.vendor_id
       WHERE q.ticket_id = $1 ORDER BY q.created_at`,
      [ticketId],
    );
  },

  async requisitions(ticketId: string) {
    return query(`SELECT * FROM requisitions WHERE ticket_id = $1 ORDER BY created_at`, [ticketId]);
  },

  async approvals(ticketId: string) {
    return query(`SELECT * FROM approvals WHERE ticket_id = $1 ORDER BY created_at`, [ticketId]);
  },

  async purchaseOrders(ticketId: string) {
    return query(`SELECT * FROM purchase_orders WHERE ticket_id = $1 ORDER BY created_at`, [ticketId]);
  },

  /** Consumables/parts a ticket asked to be replaced. */
  async ticketConsumables(ticketId: string) {
    return query(
      `SELECT id, consumable_id, kind, color, label, model_code, quantity
       FROM ticket_consumables WHERE ticket_id = $1 ORDER BY id`,
      [ticketId],
    );
  },

  async deliveryNotes(ticketId: string) {
    return query(`SELECT * FROM delivery_notes WHERE ticket_id = $1 ORDER BY created_at`, [ticketId]);
  },

  async create(data: Record<string, unknown>, initialStageId: number, userId: string) {
    return withTransaction(async (client) => {
      const ticketNumber = await this.nextNumber(client, String(data.ticketPrefix ?? 'ICT'));
      const result = await client.query(
        `INSERT INTO tickets
           (ticket_number, date_received, time_received, ict_ticket_number, vendor_ticket_number,
            reported_by, department_id, contact_phone, contact_email, reporting_method,
            printer_id, issue_category_id, priority, description, vendor_id, assigned_to,
            current_stage_id, created_by)
         VALUES ($1, COALESCE($2, CURRENT_DATE), COALESCE($3, CURRENT_TIME), $4, $5, $6, $7, $8,
                 $9, COALESCE($10, 'walk_in'), $11, $12, COALESCE($13, 'medium'), $14, $15, $16, $17, $18)
         RETURNING id, ticket_number`,
        [
          ticketNumber,
          data.dateReceived ?? null,
          data.timeReceived ?? null,
          data.ictTicketNumber ?? null,
          data.vendorTicketNumber ?? null,
          data.reportedBy,
          data.departmentId ?? null,
          data.contactPhone ?? null,
          data.contactEmail ?? null,
          data.reportingMethod ?? null,
          data.printerId ?? null,
          data.issueCategoryId ?? null,
          data.priority ?? null,
          data.description ?? null,
          data.vendorId ?? null,
          data.assignedTo ?? null,
          initialStageId,
          userId,
        ],
      );
      const ticket = result.rows[0];
      await client.query(
        `INSERT INTO ticket_stage_history (ticket_id, stage_id, changed_by, notes)
         VALUES ($1, $2, $3, $4)`,
        [ticket.id, initialStageId, userId, 'Ticket created'],
      );

      // Snapshot each requested consumable from the printer's catalogue so the
      // ticket keeps a faithful record even if the catalogue changes later.
      const consumables = Array.isArray(data.consumables)
        ? (data.consumables as Array<{ consumableId: string; quantity?: number }>)
        : [];
      for (const c of consumables) {
        if (!c.consumableId) continue;
        await client.query(
          `INSERT INTO ticket_consumables (ticket_id, consumable_id, kind, color, label, model_code, quantity)
           SELECT $1, pc.id, pc.kind, pc.color, pc.label, pc.model_code, COALESCE($3, 1)
           FROM printer_consumables pc WHERE pc.id = $2`,
          [ticket.id, c.consumableId, c.quantity ?? null],
        );
      }
      return ticket as { id: string; ticket_number: string };
    });
  },

  async update(id: string, data: Record<string, unknown>) {
    return queryOne(
      `UPDATE tickets SET
         ict_ticket_number    = COALESCE($2, ict_ticket_number),
         vendor_ticket_number = COALESCE($3, vendor_ticket_number),
         reported_by          = COALESCE($4, reported_by),
         department_id        = COALESCE($5, department_id),
         contact_phone        = COALESCE($6, contact_phone),
         contact_email        = COALESCE($7, contact_email),
         reporting_method     = COALESCE($8, reporting_method),
         printer_id           = COALESCE($9, printer_id),
         issue_category_id    = COALESCE($10, issue_category_id),
         priority             = COALESCE($11, priority),
         description          = COALESCE($12, description),
         vendor_id            = COALESCE($13, vendor_id),
         assigned_to          = COALESCE($14, assigned_to),
         is_blocked           = COALESCE($15, is_blocked),
         blocked_reason       = COALESCE($16, blocked_reason),
         completion_date      = COALESCE($17, completion_date),
         remarks              = COALESCE($18, remarks),
         updated_at           = now()
       WHERE id = $1 RETURNING *`,
      [
        id,
        data.ictTicketNumber ?? null,
        data.vendorTicketNumber ?? null,
        data.reportedBy ?? null,
        data.departmentId ?? null,
        data.contactPhone ?? null,
        data.contactEmail ?? null,
        data.reportingMethod ?? null,
        data.printerId ?? null,
        data.issueCategoryId ?? null,
        data.priority ?? null,
        data.description ?? null,
        data.vendorId ?? null,
        data.assignedTo ?? null,
        data.isBlocked ?? null,
        data.blockedReason ?? null,
        data.completionDate ?? null,
        data.remarks ?? null,
      ],
    );
  },

  /** Insert stage history + update the cached current stage, atomically. */
  async changeStage(ticketId: string, stageId: number, userId: string, notes?: string) {
    return withTransaction(async (client) => {
      await client.query(
        `INSERT INTO ticket_stage_history (ticket_id, stage_id, changed_by, notes)
         VALUES ($1, $2, $3, $4)`,
        [ticketId, stageId, userId, notes ?? null],
      );
      const extra =
        `, is_cancelled = (SELECT code = 'cancelled' FROM workflow_stages WHERE id = $2)` +
        `, completion_date = CASE WHEN (SELECT code FROM workflow_stages WHERE id = $2) = 'completed'
                                  THEN COALESCE(completion_date, CURRENT_DATE) ELSE completion_date END`;
      await client.query(
        `UPDATE tickets SET current_stage_id = $2, updated_at = now() ${extra} WHERE id = $1`,
        [ticketId, stageId],
      );
    });
  },
};
