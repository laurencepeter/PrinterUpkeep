import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, requireAuth, writeAccess } from '../middleware';
import { vendorRepo } from '../../infrastructure/repositories/vendorRepo';
import { auditRepo } from '../../infrastructure/repositories/auditRepo';
import { ConflictError, NotFoundError } from '../../domain/errors';

export const vendorRoutes = Router();
vendorRoutes.use(requireAuth);

const vendorSchema = z.object({
  companyName: z.string().min(1),
  address: z.string().optional(),
  phone: z.string().optional(),
  email: z.string().optional(),
  contactPerson: z.string().optional(),
  website: z.string().optional(),
  notes: z.string().optional(),
  vendorTypes: z.array(z.enum(['printer', 'consumables', 'maintenance', 'other'])).optional(),
});

vendorRoutes.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(
      await vendorRepo.list({
        search: req.query.search as string | undefined,
        includeInactive: req.query.include_inactive === 'true',
      }),
    );
  }),
);

vendorRoutes.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const vendor = await vendorRepo.byId(req.params.id);
    if (!vendor) throw new NotFoundError('Vendor');
    res.json(vendor);
  }),
);

vendorRoutes.post(
  '/',
  writeAccess,
  asyncHandler(async (req, res) => {
    const data = vendorSchema.parse(req.body);
    // Duplicate prevention: case-insensitive company-name match.
    if (await vendorRepo.byName(data.companyName)) {
      throw new ConflictError(`Vendor '${data.companyName}' already exists`);
    }
    const vendor = await vendorRepo.create(data);
    await auditRepo.log({
      entityType: 'vendor', entityId: String(vendor!.id), action: 'create',
      newValue: data.companyName, userId: req.user!.id,
    });
    res.status(201).json(vendor);
  }),
);

vendorRoutes.patch(
  '/:id',
  writeAccess,
  asyncHandler(async (req, res) => {
    const data = vendorSchema.partial().extend({ isActive: z.boolean().optional() }).parse(req.body);
    const before = await vendorRepo.byId(req.params.id);
    if (!before) throw new NotFoundError('Vendor');
    const vendor = await vendorRepo.update(req.params.id, data);
    await auditRepo.logDiff('vendor', req.params.id, req.user!.id, before, vendor as Record<string, unknown>);
    res.json(vendor);
  }),
);

// Deactivate rather than delete: history must be preserved.
vendorRoutes.delete(
  '/:id',
  writeAccess,
  asyncHandler(async (req, res) => {
    const vendor = await vendorRepo.update(req.params.id, { isActive: false });
    if (!vendor) throw new NotFoundError('Vendor');
    await auditRepo.log({
      entityType: 'vendor', entityId: req.params.id, action: 'deactivate', userId: req.user!.id,
    });
    res.json(vendor);
  }),
);
