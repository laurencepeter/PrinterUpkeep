import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, requireAuth, writeAccess } from '../middleware';
import { printerRepo } from '../../infrastructure/repositories/printerRepo';
import { auditRepo } from '../../infrastructure/repositories/auditRepo';
import { NotFoundError } from '../../domain/errors';

export const printerRoutes = Router();
printerRoutes.use(requireAuth);

const printerSchema = z.object({
  assetNumber: z.string().min(1),
  model: z.string().min(1),
  serialNumber: z.string().optional(),
  printerType: z.enum(['owned', 'leased']),
  departmentId: z.string().uuid().nullable().optional(),
  location: z.string().optional(),
  building: z.string().optional(),
  floor: z.string().optional(),
  vendorId: z.string().uuid().nullable().optional(),
  warrantyExpiry: z.string().nullable().optional(),
  status: z.enum(['active', 'repair', 'disposed']).optional(),
  notes: z.string().optional(),
});

printerRoutes.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(
      await printerRepo.list({
        search: req.query.search as string | undefined,
        departmentId: req.query.department_id as string | undefined,
        printerType: req.query.printer_type as string | undefined,
        status: req.query.status as string | undefined,
      }),
    );
  }),
);

printerRoutes.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const printer = await printerRepo.byId(req.params.id);
    if (!printer) throw new NotFoundError('Printer');
    res.json(printer);
  }),
);

printerRoutes.get(
  '/:id/history',
  asyncHandler(async (req, res) => {
    res.json(await printerRepo.maintenanceHistory(req.params.id));
  }),
);

printerRoutes.post(
  '/',
  writeAccess,
  asyncHandler(async (req, res) => {
    const data = printerSchema.parse(req.body);
    const printer = await printerRepo.create(data);
    await auditRepo.log({
      entityType: 'printer', entityId: String(printer!.id), action: 'create',
      newValue: data.assetNumber, userId: req.user!.id,
    });
    res.status(201).json(printer);
  }),
);

printerRoutes.patch(
  '/:id',
  writeAccess,
  asyncHandler(async (req, res) => {
    const data = printerSchema.partial().parse(req.body);
    const before = await printerRepo.byId(req.params.id);
    if (!before) throw new NotFoundError('Printer');
    const printer = await printerRepo.update(req.params.id, data);
    await auditRepo.logDiff('printer', req.params.id, req.user!.id, before, printer as Record<string, unknown>);
    res.json(printer);
  }),
);
