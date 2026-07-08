import { Router } from 'express';
import { asyncHandler, requireAuth } from '../middleware';
import { lookupRepo } from '../../infrastructure/repositories/lookupRepo';

/** Reference data for dropdowns — the app is dropdown-driven by design. */
export const lookupRoutes = Router();
lookupRoutes.use(requireAuth);

lookupRoutes.get(
  '/workflow-stages',
  asyncHandler(async (req, res) => {
    res.json(await lookupRepo.workflowStages((req.query.asset_type as string) ?? 'printer'));
  }),
);

lookupRoutes.get(
  '/issue-categories',
  asyncHandler(async (_req, res) => {
    res.json(await lookupRepo.issueCategories());
  }),
);

lookupRoutes.get(
  '/roles',
  asyncHandler(async (_req, res) => {
    res.json(await lookupRepo.roles());
  }),
);

lookupRoutes.get('/enums', (_req, res) => {
  res.json({
    priorities: ['low', 'medium', 'high', 'critical'],
    reporting_methods: ['walk_in', 'phone', 'email', 'ict_ticket', 'vendor_ticket'],
    printer_types: ['owned', 'leased'],
    printer_statuses: ['active', 'repair', 'disposed'],
    vendor_types: ['printer', 'consumables', 'maintenance', 'other'],
    file_categories: [
      'screenshot', 'photo', 'document', 'quotation', 'requisition', 'purchase_order', 'delivery_note',
    ],
    approval_decisions: ['pending', 'approved', 'rejected', 'funds_available', 'funds_unavailable'],
  });
});
