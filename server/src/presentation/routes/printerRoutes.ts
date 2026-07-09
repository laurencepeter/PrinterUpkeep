import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, requireAuth, writeAccess } from '../middleware';
import { printerRepo } from '../../infrastructure/repositories/printerRepo';
import { auditRepo } from '../../infrastructure/repositories/auditRepo';
import { NotFoundError } from '../../domain/errors';

export const printerRoutes = Router();
printerRoutes.use(requireAuth);

const dateStr = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'expected YYYY-MM-DD');

const printerBase = z
  .object({
    assetNumber: z.string().min(1),
    model: z.string().min(1),
    name: z.string().nullable().optional(),
    serialNumber: z.string().optional(),
    printerType: z.enum(['owned', 'leased']),
    ipAddress: z
      .string()
      .regex(/^(\d{1,3}\.){3}\d{1,3}$/, 'invalid IPv4 address')
      .nullable()
      .optional(),
    macAddress: z.string().nullable().optional(),
    connectionType: z.enum(['network', 'wifi', 'usb', 'other']).optional(),
    isColor: z.boolean().optional(),
    consumablesModel: z.string().nullable().optional(),
    departmentId: z.string().uuid().nullable().optional(),
    location: z.string().optional(),
    building: z.string().optional(),
    floor: z.string().optional(),
    vendorId: z.string().uuid().nullable().optional(),
    warrantyExpiry: dateStr.nullable().optional(),
    leaseStart: dateStr.nullable().optional(),
    leaseEnd: dateStr.nullable().optional(),
    leaseMonthlyCost: z.number().nonnegative().nullable().optional(),
    purchaseDate: dateStr.nullable().optional(),
    purchaseCost: z.number().nonnegative().nullable().optional(),
    lastServiceDate: dateStr.nullable().optional(),
    nextServiceDue: dateStr.nullable().optional(),
    status: z.enum(['active', 'repair', 'disposed']).optional(),
    notes: z.string().optional(),
  });

const leaseDateRule = {
  check: (p: { leaseStart?: string | null; leaseEnd?: string | null }) =>
    !p.leaseStart || !p.leaseEnd || p.leaseEnd >= p.leaseStart,
  message: 'leaseEnd must be on or after leaseStart',
};

const printerSchema = printerBase.refine(leaseDateRule.check, { message: leaseDateRule.message });
const printerUpdateSchema = printerBase
  .partial()
  .refine(leaseDateRule.check, { message: leaseDateRule.message });

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
    const data = printerUpdateSchema.parse(req.body);
    const before = await printerRepo.byId(req.params.id);
    if (!before) throw new NotFoundError('Printer');
    const printer = await printerRepo.update(req.params.id, data);
    await auditRepo.logDiff('printer', req.params.id, req.user!.id, before, printer as Record<string, unknown>);
    res.json(printer);
  }),
);
