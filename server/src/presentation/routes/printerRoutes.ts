import { Router } from 'express';
import { z } from 'zod';
import { adminOnly, asyncHandler, requireAuth, writeAccess } from '../middleware';
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
    status: z.enum(['active', 'inactive', 'repair', 'disposed']).optional(),
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

// --- Consumables catalogue (toners / drums / parts this printer takes) ------

printerRoutes.get(
  '/:id/consumables',
  asyncHandler(async (req, res) => {
    res.json(await printerRepo.consumables(req.params.id));
  }),
);

const consumableItem = z.object({
  kind: z.enum(['toner', 'ink', 'drum', 'maintenance_kit', 'fuser', 'part', 'other']).optional(),
  color: z.enum(['black', 'cyan', 'magenta', 'yellow', 'tricolor', 'other']).nullable().optional(),
  modelCode: z.string().nullable().optional(),
  label: z.string().nullable().optional(),
});

// Replace the whole catalogue for a printer (edit rows on a card, then save).
printerRoutes.put(
  '/:id/consumables',
  writeAccess,
  asyncHandler(async (req, res) => {
    const { items } = z.object({ items: z.array(consumableItem) }).parse(req.body);
    const before = await printerRepo.byId(req.params.id);
    if (!before) throw new NotFoundError('Printer');
    const saved = await printerRepo.replaceConsumables(req.params.id, items);
    await auditRepo.log({
      entityType: 'printer', entityId: req.params.id, action: 'update',
      field: 'consumables', newValue: String(items.length), userId: req.user!.id,
    });
    res.json(saved);
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

// Hard-delete a printer (system administrators only). Deleting is rarely
// necessary — setting a printer 'inactive' or 'disposed' keeps its record —
// so before the row is removed we snapshot the printer and every ticket it was
// linked to into the audit log, giving a permanent record of what existed and
// what it was connected to.
printerRoutes.delete(
  '/:id',
  adminOnly,
  asyncHandler(async (req, res) => {
    const printer = (await printerRepo.byId(req.params.id)) as Record<string, unknown> | null;
    if (!printer) throw new NotFoundError('Printer');
    const linkedTickets = await printerRepo.linkedTicketNumbers(req.params.id);

    await auditRepo.log({
      entityType: 'printer',
      entityId: req.params.id,
      action: 'delete',
      field: 'printer',
      oldValue: {
        asset_number: printer.asset_number,
        name: printer.name,
        model: printer.model,
        serial_number: printer.serial_number,
        ip_address: printer.ip_address,
        status: printer.status,
        department_name: printer.department_name,
        linked_tickets: linkedTickets,
      },
      newValue: `deleted (${linkedTickets.length} linked ticket(s) preserved)`,
      userId: req.user!.id,
    });

    await printerRepo.remove(req.params.id);
    res.json({ ok: true, deletedTickets: 0, unlinkedTickets: linkedTickets.length });
  }),
);
