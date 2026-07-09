import { queryOne, withTransaction } from '../../db/pool';
import { ticketRepo } from './ticketRepo';

/** Quotations, requisitions, approvals (Accounts/GA), POs and delivery notes. */
export const procurementRepo = {
  async upsertQuotation(ticketId: string, data: Record<string, unknown>) {
    if (data.id) {
      return queryOne(
        `UPDATE quotations SET
           vendor_id           = COALESCE($2, vendor_id),
           vendor_contact_date = COALESCE($3, vendor_contact_date),
           requested_date      = COALESCE($4, requested_date),
           received_date       = COALESCE($5, received_date),
           quotation_number    = COALESCE($6, quotation_number),
           amount              = COALESCE($7, amount),
           currency            = COALESCE($8, currency),
           file_id             = COALESCE($9, file_id),
           notes               = COALESCE($10, notes),
           updated_at          = now()
         WHERE id = $1 AND ticket_id = $11 RETURNING *`,
        [
          data.id, data.vendorId ?? null, data.vendorContactDate ?? null, data.requestedDate ?? null,
          data.receivedDate ?? null, data.quotationNumber ?? null, data.amount ?? null,
          data.currency ?? null, data.fileId ?? null, data.notes ?? null, ticketId,
        ],
      );
    }
    return queryOne(
      `INSERT INTO quotations (ticket_id, vendor_id, vendor_contact_date, requested_date,
                               received_date, quotation_number, amount, currency, file_id, notes)
       VALUES ($1, $2, $3, $4, $5, $6, $7, COALESCE($8, 'USD'), $9, $10) RETURNING *`,
      [
        ticketId, data.vendorId ?? null, data.vendorContactDate ?? null, data.requestedDate ?? null,
        data.receivedDate ?? null, data.quotationNumber ?? null, data.amount ?? null,
        data.currency ?? null, data.fileId ?? null, data.notes ?? null,
      ],
    );
  },

  /** Requisition numbers are auto-generated (REQ-YYYY-NNNN). */
  async createRequisition(ticketId: string, data: Record<string, unknown>, prefix = 'REQ') {
    return withTransaction(async (client) => {
      const reqNumber = await ticketRepo.nextNumber(client, prefix, 4);
      const result = await client.query(
        `INSERT INTO requisitions (ticket_id, requisition_number, prepared_date, signed_file_id, notes)
         VALUES ($1, $2, COALESCE($3, CURRENT_DATE), $4, $5) RETURNING *`,
        [ticketId, reqNumber, data.preparedDate ?? null, data.signedFileId ?? null, data.notes ?? null],
      );
      return result.rows[0];
    });
  },

  async updateRequisition(id: string, ticketId: string, data: Record<string, unknown>) {
    return queryOne(
      `UPDATE requisitions SET
         prepared_date  = COALESCE($3, prepared_date),
         signed_file_id = COALESCE($4, signed_file_id),
         notes          = COALESCE($5, notes),
         updated_at     = now()
       WHERE id = $1 AND ticket_id = $2 RETURNING *`,
      [id, ticketId, data.preparedDate ?? null, data.signedFileId ?? null, data.notes ?? null],
    );
  },

  /** One approval row per type per ticket; upsert semantics. */
  async upsertApproval(ticketId: string, approvalType: 'accounts' | 'ga', data: Record<string, unknown>) {
    const existing = await queryOne(
      `SELECT id FROM approvals WHERE ticket_id = $1 AND approval_type = $2 ORDER BY created_at DESC LIMIT 1`,
      [ticketId, approvalType],
    );
    if (existing) {
      return queryOne(
        `UPDATE approvals SET
           sent_date     = COALESCE($2, sent_date),
           decision      = COALESCE($3, decision),
           decision_date = COALESCE($4, decision_date),
           notes         = COALESCE($5, notes),
           updated_at    = now()
         WHERE id = $1 RETURNING *`,
        [existing.id, data.sentDate ?? null, data.decision ?? null, data.decisionDate ?? null, data.notes ?? null],
      );
    }
    return queryOne(
      `INSERT INTO approvals (ticket_id, approval_type, sent_date, decision, decision_date, notes)
       VALUES ($1, $2, $3, COALESCE($4, 'pending'), $5, $6) RETURNING *`,
      [ticketId, approvalType, data.sentDate ?? null, data.decision ?? null, data.decisionDate ?? null, data.notes ?? null],
    );
  },

  async createPurchaseOrder(ticketId: string, data: Record<string, unknown>) {
    return queryOne(
      `INSERT INTO purchase_orders (ticket_id, po_number, issued_date, file_id, notes)
       VALUES ($1, $2, COALESCE($3, CURRENT_DATE), $4, $5) RETURNING *`,
      [ticketId, data.poNumber, data.issuedDate ?? null, data.fileId ?? null, data.notes ?? null],
    );
  },

  async createDeliveryNote(ticketId: string, data: Record<string, unknown>) {
    return queryOne(
      `INSERT INTO delivery_notes (ticket_id, dn_number, received_date, file_id, notes)
       VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [ticketId, data.dnNumber ?? null, data.receivedDate ?? null, data.fileId ?? null, data.notes ?? null],
    );
  },
};
