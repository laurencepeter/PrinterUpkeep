import { Router } from 'express';
import { z } from 'zod';
import PDFDocument from 'pdfkit';
import { settingsRepo } from '../../infrastructure/repositories/lookupRepo';
import { asyncHandler, requireAuth, writeAccess } from '../middleware';
import { ticketService } from '../../application/ticketService';
import { ticketRepo, TicketFilters } from '../../infrastructure/repositories/ticketRepo';
import { procurementRepo } from '../../infrastructure/repositories/procurementRepo';
import { auditRepo } from '../../infrastructure/repositories/auditRepo';

export const ticketRoutes = Router();
ticketRoutes.use(requireAuth);

function parseFilters(q: Record<string, unknown>): TicketFilters {
  return {
    search: q.search as string | undefined,
    stageCodes: q.stages ? String(q.stages).split(',') : undefined,
    statusLabel: q.status as string | undefined,
    departmentId: q.department_id as string | undefined,
    vendorId: q.vendor_id as string | undefined,
    printerId: q.printer_id as string | undefined,
    assignedTo: q.assigned_to as string | undefined,
    priority: q.priority as string | undefined,
    printerType: q.printer_type as string | undefined,
    issueCategoryId: q.issue_category_id ? parseInt(String(q.issue_category_id), 10) : undefined,
    dateFrom: q.date_from as string | undefined,
    dateTo: q.date_to as string | undefined,
    openOnly: q.open_only === 'true',
    page: Math.max(1, parseInt(String(q.page ?? '1'), 10)),
    pageSize: Math.min(200, Math.max(1, parseInt(String(q.page_size ?? '25'), 10))),
  };
}

ticketRoutes.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await ticketService.list(parseFilters(req.query as Record<string, unknown>)));
  }),
);

ticketRoutes.get(
  '/:id',
  asyncHandler(async (req, res) => {
    res.json(await ticketService.detail(req.params.id));
  }),
);

const createSchema = z.object({
  reportedBy: z.string().min(1),
  dateReceived: z.string().optional(),
  timeReceived: z.string().optional(),
  ictTicketNumber: z.string().optional(),
  vendorTicketNumber: z.string().optional(),
  departmentId: z.string().uuid().optional(),
  contactPhone: z.string().optional(),
  contactEmail: z.string().optional(),
  reportingMethod: z.enum(['walk_in', 'phone', 'email', 'ict_ticket', 'vendor_ticket']).optional(),
  printerId: z.string().uuid().optional(),
  issueCategoryId: z.number().int().optional(),
  priority: z.enum(['low', 'medium', 'high', 'critical']).optional(),
  description: z.string().optional(),
  vendorId: z.string().uuid().optional(),
  assignedTo: z.string().uuid().optional(),
});

ticketRoutes.post(
  '/',
  writeAccess,
  asyncHandler(async (req, res) => {
    const data = createSchema.parse(req.body);
    res.status(201).json(await ticketService.create(data, req.user!.id));
  }),
);

ticketRoutes.patch(
  '/:id',
  writeAccess,
  asyncHandler(async (req, res) => {
    const data = createSchema.partial().extend({
      isBlocked: z.boolean().optional(),
      blockedReason: z.string().nullable().optional(),
      completionDate: z.string().nullable().optional(),
      remarks: z.string().nullable().optional(),
    }).parse(req.body);
    res.json(await ticketService.update(req.params.id, data, req.user!.id));
  }),
);

ticketRoutes.post(
  '/:id/stage',
  writeAccess,
  asyncHandler(async (req, res) => {
    const { stage, notes } = z.object({ stage: z.string().min(1), notes: z.string().optional() }).parse(req.body);
    res.json(await ticketService.changeStage(req.params.id, stage, req.user!.id, notes));
  }),
);

ticketRoutes.post(
  '/:id/notes',
  writeAccess,
  asyncHandler(async (req, res) => {
    const { note } = z.object({ note: z.string().min(1) }).parse(req.body);
    res.status(201).json(await ticketService.addNote(req.params.id, req.user!.id, note));
  }),
);

// --- Procurement sub-resources -------------------------------------------

ticketRoutes.post(
  '/:id/quotations',
  writeAccess,
  asyncHandler(async (req, res) => {
    const result = await procurementRepo.upsertQuotation(req.params.id, req.body ?? {});
    await auditRepo.log({
      entityType: 'quotation', entityId: String(result!.id), action: req.body?.id ? 'update' : 'create',
      userId: req.user!.id,
    });
    res.status(201).json(result);
  }),
);

ticketRoutes.post(
  '/:id/requisitions',
  writeAccess,
  asyncHandler(async (req, res) => {
    const result = req.body?.id
      ? await procurementRepo.updateRequisition(String(req.body.id), req.params.id, req.body)
      : await procurementRepo.createRequisition(req.params.id, req.body ?? {});
    await auditRepo.log({
      entityType: 'requisition', entityId: String(result!.id), action: req.body?.id ? 'update' : 'create',
      userId: req.user!.id,
    });
    res.status(201).json(result);
  }),
);

ticketRoutes.post(
  '/:id/approvals/:type',
  writeAccess,
  asyncHandler(async (req, res) => {
    const type = z.enum(['accounts', 'ga']).parse(req.params.type);
    const result = await procurementRepo.upsertApproval(req.params.id, type, req.body ?? {});
    await auditRepo.log({
      entityType: 'approval', entityId: String(result!.id), action: 'upsert',
      field: type, newValue: req.body?.decision, userId: req.user!.id,
    });
    res.status(201).json(result);
  }),
);

ticketRoutes.post(
  '/:id/purchase-orders',
  writeAccess,
  asyncHandler(async (req, res) => {
    const body = z.object({
      poNumber: z.string().min(1),
      issuedDate: z.string().optional(),
      fileId: z.string().uuid().optional(),
      notes: z.string().optional(),
    }).parse(req.body);
    const result = await procurementRepo.createPurchaseOrder(req.params.id, body);
    await auditRepo.log({
      entityType: 'purchase_order', entityId: String(result!.id), action: 'create',
      newValue: body.poNumber, userId: req.user!.id,
    });
    res.status(201).json(result);
  }),
);

ticketRoutes.post(
  '/:id/delivery-notes',
  writeAccess,
  asyncHandler(async (req, res) => {
    const result = await procurementRepo.createDeliveryNote(req.params.id, req.body ?? {});
    await auditRepo.log({
      entityType: 'delivery_note', entityId: String(result!.id), action: 'create', userId: req.user!.id,
    });
    res.status(201).json(result);
  }),
);

ticketRoutes.get(
  '/:id/history',
  asyncHandler(async (req, res) => {
    res.json(await ticketRepo.stageHistory(req.params.id));
  }),
);

// Printable requisition form for signing.
ticketRoutes.get(
  '/:id/requisitions/:reqId/pdf',
  asyncHandler(async (req, res) => {
    const detail = await ticketService.detail(req.params.id);
    const requisition = (detail.requisitions as Array<Record<string, unknown>>).find(
      (r) => String(r.id) === req.params.reqId,
    );
    if (!requisition) throw new Error('Requisition not found');
    const orgName = (await settingsRepo.get('org_name')) ?? 'ICT Department';
    const t = detail.ticket as Record<string, unknown>;
    const quotation = (detail.quotations as Array<Record<string, unknown>>)[0];

    const doc = new PDFDocument({ margin: 50, size: 'A4' });
    res.setHeader('Content-Type', 'application/pdf');
    res.setHeader('Content-Disposition', `attachment; filename="${requisition.requisition_number}.pdf"`);
    doc.pipe(res);

    doc.fontSize(16).font('Helvetica-Bold').text(orgName, { align: 'center' });
    doc.fontSize(13).text('PURCHASE REQUISITION', { align: 'center' });
    doc.moveDown(1.5);

    const line = (label: string, value: unknown) => {
      doc.fontSize(10).font('Helvetica-Bold').text(`${label}: `, { continued: true });
      doc.font('Helvetica').text(value === null || value === undefined ? '—' : String(value));
      doc.moveDown(0.4);
    };
    line('Requisition Number', requisition.requisition_number);
    line('Date Prepared', requisition.prepared_date);
    line('Ticket Number', t.ticket_number);
    line('Department', t.department_name);
    line('Printer', t.printer_asset_number ? `${t.printer_asset_number} — ${t.printer_model}` : null);
    line('Issue', t.issue_category);
    line('Description', t.description);
    line('Vendor', t.vendor_name);
    if (quotation) {
      line('Quotation Number', quotation.quotation_number);
      line('Quotation Amount', quotation.amount ? `${quotation.currency} ${quotation.amount}` : null);
    }
    line('Notes', requisition.notes);
    doc.moveDown(3);
    doc.fontSize(10).font('Helvetica');
    doc.text('_________________________          _________________________');
    doc.text('Prepared By (ICT)                              Approved By (Accounts/GA)');
    doc.end();
  }),
);
