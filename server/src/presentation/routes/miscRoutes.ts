import { Router } from 'express';
import { z } from 'zod';
import { adminOnly, asyncHandler, requireAuth } from '../middleware';
import { notificationRepo } from '../../infrastructure/repositories/notificationRepo';
import { auditRepo } from '../../infrastructure/repositories/auditRepo';
import { settingsRepo } from '../../infrastructure/repositories/lookupRepo';
import { notificationService } from '../../application/notificationService';

// Notifications ------------------------------------------------------------

export const notificationRoutes = Router();
notificationRoutes.use(requireAuth);

notificationRoutes.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(await notificationRepo.listForUser(req.user!.id, req.query.unread_only === 'true'));
  }),
);

notificationRoutes.post(
  '/scan',
  asyncHandler(async (_req, res) => {
    await notificationService.scan();
    res.json({ ok: true });
  }),
);

notificationRoutes.post(
  '/:id/read',
  asyncHandler(async (req, res) => {
    await notificationRepo.markRead(parseInt(req.params.id, 10), req.user!.id);
    res.json({ ok: true });
  }),
);

notificationRoutes.post(
  '/read-all',
  asyncHandler(async (req, res) => {
    await notificationRepo.markAllRead(req.user!.id);
    res.json({ ok: true });
  }),
);

// Audit log ------------------------------------------------------------------

export const auditRoutes = Router();
auditRoutes.use(requireAuth);

auditRoutes.get(
  '/',
  asyncHandler(async (req, res) => {
    res.json(
      await auditRepo.list({
        entityType: req.query.entity_type as string | undefined,
        entityId: req.query.entity_id as string | undefined,
        userId: req.query.user_id as string | undefined,
        page: Math.max(1, parseInt(String(req.query.page ?? '1'), 10)),
        pageSize: Math.min(200, parseInt(String(req.query.page_size ?? '50'), 10)),
      }),
    );
  }),
);

// Settings -------------------------------------------------------------------

export const settingsRoutes = Router();
settingsRoutes.use(requireAuth);

settingsRoutes.get(
  '/',
  asyncHandler(async (_req, res) => {
    res.json(await settingsRepo.all());
  }),
);

settingsRoutes.put(
  '/:key',
  adminOnly,
  asyncHandler(async (req, res) => {
    const { value } = z.object({ value: z.string() }).parse(req.body);
    await settingsRepo.set(req.params.key, value);
    await auditRepo.log({
      entityType: 'setting', entityId: req.params.key, action: 'update',
      newValue: value, userId: req.user!.id,
    });
    res.json({ ok: true });
  }),
);
