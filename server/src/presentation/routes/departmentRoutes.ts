import { Router } from 'express';
import { z } from 'zod';
import { asyncHandler, requireAuth, writeAccess } from '../middleware';
import { departmentRepo } from '../../infrastructure/repositories/departmentRepo';
import { auditRepo } from '../../infrastructure/repositories/auditRepo';
import { NotFoundError } from '../../domain/errors';

export const departmentRoutes = Router();
departmentRoutes.use(requireAuth);

const schema = z.object({
  name: z.string().min(1),
  code: z.string().optional(),
  building: z.string().optional(),
  floor: z.string().optional(),
});

departmentRoutes.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await departmentRepo.list(req.query.include_inactive === 'true'));
  }),
);

departmentRoutes.post(
  '/',
  writeAccess,
  asyncHandler(async (req, res) => {
    const dept = await departmentRepo.create(schema.parse(req.body));
    await auditRepo.log({
      entityType: 'department', entityId: String(dept!.id), action: 'create',
      newValue: dept!.name as string, userId: req.user!.id,
    });
    res.status(201).json(dept);
  }),
);

departmentRoutes.patch(
  '/:id',
  writeAccess,
  asyncHandler(async (req, res) => {
    const data = schema.partial().extend({ isActive: z.boolean().optional() }).parse(req.body);
    const before = await departmentRepo.byId(req.params.id);
    if (!before) throw new NotFoundError('Department');
    const dept = await departmentRepo.update(req.params.id, data);
    await auditRepo.logDiff('department', req.params.id, req.user!.id, before, dept as Record<string, unknown>);
    res.json(dept);
  }),
);

departmentRoutes.delete(
  '/:id',
  writeAccess,
  asyncHandler(async (req, res) => {
    const dept = await departmentRepo.update(req.params.id, { isActive: false });
    if (!dept) throw new NotFoundError('Department');
    await auditRepo.log({
      entityType: 'department', entityId: req.params.id, action: 'deactivate', userId: req.user!.id,
    });
    res.json(dept);
  }),
);
