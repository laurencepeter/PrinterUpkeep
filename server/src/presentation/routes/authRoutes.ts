import { Router } from 'express';
import { z } from 'zod';
import { authService } from '../../application/authService';
import { asyncHandler, requireAuth } from '../middleware';
import { userRepo } from '../../infrastructure/repositories/userRepo';
import { ValidationError, UnauthorizedError } from '../../domain/errors';
import bcrypt from 'bcryptjs';

export const authRoutes = Router();

const loginSchema = z.object({ username: z.string().min(1), password: z.string().min(1) });

authRoutes.post(
  '/login',
  asyncHandler(async (req, res) => {
    const { username, password } = loginSchema.parse(req.body);
    res.json(await authService.login(username, password));
  }),
);

authRoutes.get(
  '/me',
  requireAuth,
  asyncHandler(async (req, res) => {
    res.json(await userRepo.byId(req.user!.id));
  }),
);

authRoutes.post(
  '/change-password',
  requireAuth,
  asyncHandler(async (req, res) => {
    const schema = z.object({ currentPassword: z.string().min(1), newPassword: z.string().min(8) });
    const { currentPassword, newPassword } = schema.parse(req.body);
    const record = await userRepo.byUsernameWithHash(req.user!.username);
    if (!record || !(await bcrypt.compare(currentPassword, record.password_hash as string))) {
      throw new UnauthorizedError('Current password is incorrect');
    }
    if (currentPassword === newPassword) throw new ValidationError('New password must differ');
    await userRepo.update(req.user!.id, { passwordHash: await authService.hashPassword(newPassword) });
    res.json({ ok: true });
  }),
);
