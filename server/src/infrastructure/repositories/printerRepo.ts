import { query, queryOne } from '../../db/pool';

const SELECT = `
  SELECT p.*, d.name AS department_name, v.company_name AS vendor_name
  FROM printers p
  LEFT JOIN departments d ON d.id = p.department_id
  LEFT JOIN vendors v ON v.id = p.vendor_id`;

export const printerRepo = {
  async list(opts: { search?: string; departmentId?: string; printerType?: string; status?: string } = {}) {
    const where: string[] = [];
    const params: unknown[] = [];
    if (opts.search) {
      params.push(`%${opts.search}%`);
      where.push(
        `(p.asset_number ILIKE $${params.length} OR p.model ILIKE $${params.length} OR p.serial_number ILIKE $${params.length})`,
      );
    }
    if (opts.departmentId) {
      params.push(opts.departmentId);
      where.push(`p.department_id = $${params.length}`);
    }
    if (opts.printerType) {
      params.push(opts.printerType);
      where.push(`p.printer_type = $${params.length}`);
    }
    if (opts.status) {
      params.push(opts.status);
      where.push(`p.status = $${params.length}`);
    }
    return query(
      `${SELECT} ${where.length ? `WHERE ${where.join(' AND ')}` : ''} ORDER BY p.asset_number`,
      params,
    );
  },

  async byId(id: string) {
    return queryOne(`${SELECT} WHERE p.id = $1`, [id]);
  },

  async create(data: {
    assetNumber: string;
    model: string;
    serialNumber?: string | null;
    printerType: string;
    departmentId?: string | null;
    location?: string | null;
    building?: string | null;
    floor?: string | null;
    vendorId?: string | null;
    warrantyExpiry?: string | null;
    status?: string;
    notes?: string | null;
  }) {
    return queryOne(
      `INSERT INTO printers (asset_number, model, serial_number, printer_type, department_id,
                             location, building, floor, vendor_id, warranty_expiry, status, notes)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, COALESCE($11, 'active'), $12)
       RETURNING *`,
      [
        data.assetNumber,
        data.model,
        data.serialNumber ?? null,
        data.printerType,
        data.departmentId ?? null,
        data.location ?? null,
        data.building ?? null,
        data.floor ?? null,
        data.vendorId ?? null,
        data.warrantyExpiry ?? null,
        data.status ?? null,
        data.notes ?? null,
      ],
    );
  },

  async update(id: string, data: Record<string, unknown>) {
    return queryOne(
      `UPDATE printers SET
         asset_number    = COALESCE($2, asset_number),
         model           = COALESCE($3, model),
         serial_number   = COALESCE($4, serial_number),
         printer_type    = COALESCE($5, printer_type),
         department_id   = COALESCE($6, department_id),
         location        = COALESCE($7, location),
         building        = COALESCE($8, building),
         floor           = COALESCE($9, floor),
         vendor_id       = COALESCE($10, vendor_id),
         warranty_expiry = COALESCE($11, warranty_expiry),
         status          = COALESCE($12, status),
         notes           = COALESCE($13, notes),
         updated_at      = now()
       WHERE id = $1 RETURNING *`,
      [
        id,
        data.assetNumber ?? null,
        data.model ?? null,
        data.serialNumber ?? null,
        data.printerType ?? null,
        data.departmentId ?? null,
        data.location ?? null,
        data.building ?? null,
        data.floor ?? null,
        data.vendorId ?? null,
        data.warrantyExpiry ?? null,
        data.status ?? null,
        data.notes ?? null,
      ],
    );
  },

  /** Maintenance history: all tickets ever raised for this printer. */
  async maintenanceHistory(printerId: string) {
    return query(
      `SELECT t.id, t.ticket_number, t.date_received, t.priority, t.completion_date,
              ic.name AS issue_category, ws.name AS current_stage, ws.status_label
       FROM tickets t
       LEFT JOIN issue_categories ic ON ic.id = t.issue_category_id
       JOIN workflow_stages ws ON ws.id = t.current_stage_id
       WHERE t.printer_id = $1
       ORDER BY t.date_received DESC`,
      [printerId],
    );
  },
};
