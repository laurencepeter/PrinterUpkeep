import { Router } from 'express';
import { z } from 'zod';
import { adminOnly, asyncHandler, requireAuth } from '../middleware';
import { userRepo } from '../../infrastructure/repositories/userRepo';
import { authService } from '../../application/authService';
import { auditRepo } from '../../infrastructure/repositories/auditRepo';

export const userRoutes = Router();
userRoutes.use(requireAuth);

// All authenticated users can list users (needed for "Assigned To" dropdowns).
userRoutes.get(
  '/',
  asyncHandler(async (_req, res) => {
    res.json(await userRepo.list());
  }),
);

userRoutes.post(
  '/',
  adminOnly,
  asyncHandler(async (req, res) => {
    const schema = z.object({
      username: z.string().min(3),
      fullName: z.string().min(1),
      email: z.string().email().optional(),
      phone: z.string().optional(),
      password: z.string().min(8),
      roleCode: z.enum(['admin', 'ict_officer', 'viewer']),
    });
    const data = schema.parse(req.body);
    const created = await userRepo.create({
      ...data,
      passwordHash: await authService.hashPassword(data.password),
    });
    await auditRepo.log({
      entityType: 'user', entityId: String(created!.id), action: 'create',
      newValue: data.username, userId: req.user!.id,
    });
    res.status(201).json(await userRepo.byId(String(created!.id)));
  }),
);

userRoutes.patch(
  '/:id',
  adminOnly,
  asyncHandler(async (req, res) => {
    const schema = z.object({
      fullName: z.string().optional(),
      email: z.string().email().nullable().optional(),
      phone: z.string().nullable().optional(),
      roleCode: z.enum(['admin', 'ict_officer', 'viewer']).optional(),
      isActive: z.boolean().optional(),
      password: z.string().min(8).optional(),
    });
    const data = schema.parse(req.body);
    await userRepo.update(req.params.id, {
      ...data,
      passwordHash: data.password ? await authService.hashPassword(data.password) : undefined,
    });
    await auditRepo.log({
      entityType: 'user', entityId: req.params.id, action: 'update', userId: req.user!.id,
    });
    res.json(await userRepo.byId(req.params.id));
  }),
);
