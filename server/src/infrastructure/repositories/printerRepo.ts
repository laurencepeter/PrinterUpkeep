import { query, queryOne, withTransaction } from '../../db/pool';

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
        `(p.asset_number ILIKE $${params.length} OR p.model ILIKE $${params.length}
          OR p.serial_number ILIKE $${params.length} OR p.name ILIKE $${params.length}
          OR p.ip_address ILIKE $${params.length})`,
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

  async create(data: Record<string, unknown>) {
    return queryOne(
      `INSERT INTO printers (asset_number, model, serial_number, printer_type, department_id,
                             location, building, floor, vendor_id, warranty_expiry, status, notes,
                             name, ip_address, mac_address, connection_type, is_color,
                             consumables_model, lease_start, lease_end, lease_monthly_cost,
                             purchase_date, purchase_cost, last_service_date, next_service_due)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, COALESCE($11, 'active'), $12,
               $13, $14, $15, COALESCE($16, 'network'), COALESCE($17, FALSE),
               $18, $19, $20, $21, $22, $23, $24, $25)
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
        data.name ?? null,
        data.ipAddress ?? null,
        data.macAddress ?? null,
        data.connectionType ?? null,
        data.isColor ?? null,
        data.consumablesModel ?? null,
        data.leaseStart ?? null,
        data.leaseEnd ?? null,
        data.leaseMonthlyCost ?? null,
        data.purchaseDate ?? null,
        data.purchaseCost ?? null,
        data.lastServiceDate ?? null,
        data.nextServiceDue ?? null,
      ],
    );
  },

  async update(id: string, data: Record<string, unknown>) {
    // Lease/purchase/service fields use explicit-null semantics so switching a
    // printer from leased to owned can clear its lease terms: `undefined`
    // keeps the current value, an explicit JSON null clears the column.
    const keep = (v: unknown) => (v === undefined ? undefined : v);
    return queryOne(
      `UPDATE printers SET
         asset_number       = COALESCE($2, asset_number),
         model              = COALESCE($3, model),
         serial_number      = COALESCE($4, serial_number),
         printer_type       = COALESCE($5, printer_type),
         department_id      = COALESCE($6, department_id),
         location           = COALESCE($7, location),
         building           = COALESCE($8, building),
         floor              = COALESCE($9, floor),
         vendor_id          = COALESCE($10, vendor_id),
         warranty_expiry    = COALESCE($11, warranty_expiry),
         status             = COALESCE($12, status),
         notes              = COALESCE($13, notes),
         name               = CASE WHEN $34 THEN $14 ELSE name              END,
         ip_address         = CASE WHEN $35 THEN $15 ELSE ip_address        END,
         mac_address        = CASE WHEN $36 THEN $16 ELSE mac_address       END,
         connection_type    = COALESCE($17, connection_type),
         is_color           = COALESCE($18, is_color),
         consumables_model  = CASE WHEN $37 THEN $19 ELSE consumables_model END,
         lease_start        = CASE WHEN $20 THEN $21::date    ELSE lease_start        END,
         lease_end          = CASE WHEN $22 THEN $23::date    ELSE lease_end          END,
         lease_monthly_cost = CASE WHEN $24 THEN $25::numeric ELSE lease_monthly_cost END,
         purchase_date      = CASE WHEN $26 THEN $27::date    ELSE purchase_date      END,
         purchase_cost      = CASE WHEN $28 THEN $29::numeric ELSE purchase_cost      END,
         last_service_date  = CASE WHEN $30 THEN $31::date    ELSE last_service_date  END,
         next_service_due   = CASE WHEN $32 THEN $33::date    ELSE next_service_due   END,
         updated_at         = now()
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
        data.name ?? null,
        data.ipAddress ?? null,
        data.macAddress ?? null,
        data.connectionType ?? null,
        data.isColor ?? null,
        data.consumablesModel ?? null,
        keep(data.leaseStart) !== undefined, data.leaseStart ?? null,
        keep(data.leaseEnd) !== undefined, data.leaseEnd ?? null,
        keep(data.leaseMonthlyCost) !== undefined, data.leaseMonthlyCost ?? null,
        keep(data.purchaseDate) !== undefined, data.purchaseDate ?? null,
        keep(data.purchaseCost) !== undefined, data.purchaseCost ?? null,
        keep(data.lastServiceDate) !== undefined, data.lastServiceDate ?? null,
        keep(data.nextServiceDue) !== undefined, data.nextServiceDue ?? null,
        keep(data.name) !== undefined,
        keep(data.ipAddress) !== undefined,
        keep(data.macAddress) !== undefined,
        keep(data.consumablesModel) !== undefined,
      ],
    );
  },

  /** The consumables/parts catalogue an admin has defined for this printer. */
  async consumables(printerId: string) {
    return query(
      `SELECT id, printer_id, kind, color, model_code, label, sort_order, is_active
       FROM printer_consumables
       WHERE printer_id = $1 AND is_active
       ORDER BY sort_order, kind, color`,
      [printerId],
    );
  },

  /**
   * Replace a printer's consumables catalogue wholesale. The card editor sends
   * the full desired set; existing rows are soft-removed (is_active = false) so
   * historical ticket references remain intact, then the new set is inserted.
   */
  async replaceConsumables(
    printerId: string,
    items: Array<{ kind?: string; color?: string | null; modelCode?: string | null; label?: string | null }>,
  ) {
    return withTransaction(async (client) => {
      await client.query(`UPDATE printer_consumables SET is_active = FALSE WHERE printer_id = $1`, [
        printerId,
      ]);
      let order = 0;
      for (const item of items) {
        await client.query(
          `INSERT INTO printer_consumables (printer_id, kind, color, model_code, label, sort_order)
           VALUES ($1, COALESCE($2, 'toner'), $3, $4, $5, $6)`,
          [
            printerId,
            item.kind ?? null,
            item.color ?? null,
            item.modelCode ?? null,
            item.label ?? null,
            order++,
          ],
        );
      }
      const result = await client.query(
        `SELECT id, printer_id, kind, color, model_code, label, sort_order, is_active
         FROM printer_consumables
         WHERE printer_id = $1 AND is_active
         ORDER BY sort_order, kind, color`,
        [printerId],
      );
      return result.rows;
    });
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
