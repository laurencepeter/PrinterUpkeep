import { PoolClient } from 'pg';
import { queryOne, withTransaction } from '../../db/pool';
import { ticketRepo } from './ticketRepo';
import { settingsRepo } from './lookupRepo';

/** One priced line on a requisition form. */
export interface ItemInput {
  quantity?: number;
  unit?: string | null;
  description: string;
  unitPrice?: number;
}

/** Quotations, requisitions, approvals (Accounts/GA), POs and delivery notes. */
export const procurementRepo = {
  async upsertQuotation(ticketId: string, data: Record<string, unknown>) {
    // New quotations take the organisation's configured currency (TTD) unless
    // one is explicitly supplied, so amounts are never mislabelled.
    const currency =
      (data.currency as string | undefined) ??
      (await settingsRepo.get('default_currency')) ??
      'TTD';
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
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10) RETURNING *`,
      [
        ticketId, data.vendorId ?? null, data.vendorContactDate ?? null, data.requestedDate ?? null,
        data.receivedDate ?? null, data.quotationNumber ?? null, data.amount ?? null,
        currency, data.fileId ?? null, data.notes ?? null,
      ],
    );
  },

  /** Requisition numbers are auto-generated (REQ-YYYY-NNNN). */
  async createRequisition(ticketId: string, data: Record<string, unknown>, prefix = 'REQ') {
    return withTransaction(async (client) => {
      const reqNumber = await ticketRepo.nextNumber(client, prefix, 4);
      const result = await client.query(
        `INSERT INTO requisitions
           (ticket_id, requisition_number, prepared_date, signed_file_id, notes,
            requested_by, department_name, file_number, supply_priority, memorandum,
            prepared_by, vat_rate, expense_code, annual_budget, expenditure_to_date,
            amount_available, authorised_manager, accounting_officer)
         VALUES ($1, $2, COALESCE($3, CURRENT_DATE), $4, $5,
                 $6, $7, $8, $9, $10,
                 $11, COALESCE($12, 12.5), $13, $14, $15,
                 $16, $17, $18) RETURNING *`,
        [
          ticketId, reqNumber, data.preparedDate ?? null, data.signedFileId ?? null, data.notes ?? null,
          data.requestedBy ?? null, data.departmentName ?? null, data.fileNumber ?? null,
          data.supplyPriority ?? null, data.memorandum ?? null,
          data.preparedBy ?? null, data.vatRate ?? null, data.expenseCode ?? null,
          data.annualBudget ?? null, data.expenditureToDate ?? null, data.amountAvailable ?? null,
          data.authorisedManager ?? null, data.accountingOfficer ?? null,
        ],
      );
      const requisition = result.rows[0];
      if (Array.isArray(data.items)) {
        await this.replaceRequisitionItems(client, requisition.id as string, data.items as ItemInput[]);
      }
      return requisition;
    });
  },

  async updateRequisition(id: string, ticketId: string, data: Record<string, unknown>) {
    return withTransaction(async (client) => {
      const result = await client.query(
        `UPDATE requisitions SET
           prepared_date       = COALESCE($3, prepared_date),
           signed_file_id      = COALESCE($4, signed_file_id),
           notes               = COALESCE($5, notes),
           requested_by        = COALESCE($6, requested_by),
           department_name     = COALESCE($7, department_name),
           file_number         = COALESCE($8, file_number),
           supply_priority     = COALESCE($9, supply_priority),
           memorandum          = COALESCE($10, memorandum),
           prepared_by         = COALESCE($11, prepared_by),
           vat_rate            = COALESCE($12, vat_rate),
           expense_code        = COALESCE($13, expense_code),
           annual_budget       = COALESCE($14, annual_budget),
           expenditure_to_date = COALESCE($15, expenditure_to_date),
           amount_available    = COALESCE($16, amount_available),
           authorised_manager  = COALESCE($17, authorised_manager),
           accounting_officer  = COALESCE($18, accounting_officer),
           updated_at          = now()
         WHERE id = $1 AND ticket_id = $2 RETURNING *`,
        [
          id, ticketId, data.preparedDate ?? null, data.signedFileId ?? null, data.notes ?? null,
          data.requestedBy ?? null, data.departmentName ?? null, data.fileNumber ?? null,
          data.supplyPriority ?? null, data.memorandum ?? null,
          data.preparedBy ?? null, data.vatRate ?? null, data.expenseCode ?? null,
          data.annualBudget ?? null, data.expenditureToDate ?? null, data.amountAvailable ?? null,
          data.authorisedManager ?? null, data.accountingOfficer ?? null,
        ],
      );
      // Line items are replaced wholesale only when the caller sends them, so a
      // partial field update never wipes an existing item list.
      if (Array.isArray(data.items)) {
        await this.replaceRequisitionItems(client, id, data.items as ItemInput[]);
      }
      return result.rows[0] ?? null;
    });
  },

  /** Replace all line items for a requisition (delete + re-insert in order). */
  async replaceRequisitionItems(client: PoolClient, requisitionId: string, items: ItemInput[]) {
    await client.query(`DELETE FROM requisition_items WHERE requisition_id = $1`, [requisitionId]);
    let order = 0;
    for (const item of items) {
      if (!item || !String(item.description ?? '').trim()) continue;
      await client.query(
        `INSERT INTO requisition_items (requisition_id, sort_order, quantity, unit, description, unit_price)
         VALUES ($1, $2, COALESCE($3, 1), $4, $5, COALESCE($6, 0))`,
        [
          requisitionId, order++, item.quantity ?? null, item.unit ?? null,
          String(item.description).trim(), item.unitPrice ?? null,
        ],
      );
    }
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
           approved_by   = COALESCE($6, approved_by),
           updated_at    = now()
         WHERE id = $1 RETURNING *`,
        [
          existing.id, data.sentDate ?? null, data.decision ?? null, data.decisionDate ?? null,
          data.notes ?? null, data.approvedBy ?? null,
        ],
      );
    }
    return queryOne(
      `INSERT INTO approvals (ticket_id, approval_type, sent_date, decision, decision_date, notes, approved_by)
       VALUES ($1, $2, $3, COALESCE($4, 'pending'), $5, $6, $7) RETURNING *`,
      [
        ticketId, approvalType, data.sentDate ?? null, data.decision ?? null, data.decisionDate ?? null,
        data.notes ?? null, data.approvedBy ?? null,
      ],
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
