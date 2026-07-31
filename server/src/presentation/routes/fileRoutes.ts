import { Router } from 'express';
import path from 'path';
import crypto from 'crypto';
import multer from 'multer';
import { z } from 'zod';
import { config } from '../../config';
import { asyncHandler, requireAuth, writeAccess } from '../middleware';
import { queryOne } from '../../db/pool';
import { NotFoundError, ValidationError } from '../../domain/errors';
import { auditRepo } from '../../infrastructure/repositories/auditRepo';
import { fileStorage, StorageNotFound } from '../../infrastructure/storage/fileStorage';

export const fileRoutes = Router();
fileRoutes.use(requireAuth);

const ALLOWED_MIME = new Set([
  'image/png', 'image/jpeg', 'image/gif', 'image/webp',
  'application/pdf',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'text/plain', 'text/csv',
]);

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: config.uploads.maxFileSizeMb * 1024 * 1024 },
});

// POST /api/files/tickets/:ticketId?category=quotation — multipart upload.
fileRoutes.post(
  '/tickets/:ticketId',
  writeAccess,
  upload.single('file'),
  asyncHandler(async (req, res) => {
    if (!req.file) throw new ValidationError('No file uploaded (field name: file)');
    if (!ALLOWED_MIME.has(req.file.mimetype)) {
      throw new ValidationError(`File type not allowed: ${req.file.mimetype}`);
    }
    const category = z
      .enum(['screenshot', 'photo', 'document', 'quotation', 'requisition', 'purchase_order', 'delivery_note'])
      .parse((req.query.category as string) ?? 'document');

    const ticket = await queryOne(`SELECT id FROM tickets WHERE id = $1`, [req.params.ticketId]);
    if (!ticket) throw new NotFoundError('Ticket');

    // Storage key is <ticketId>/<random>-<safe name> — never trust the
    // client-supplied filename for the path. Same key shape on disk and in
    // the Supabase bucket, so it's stored verbatim in storage_path.
    const safeName = path.basename(req.file.originalname).replace(/[^\w.\-]+/g, '_');
    const storageKey = `${req.params.ticketId}/${crypto.randomBytes(8).toString('hex')}-${safeName}`;
    await fileStorage.put(storageKey, req.file.buffer, req.file.mimetype);

    const record = await queryOne(
      `INSERT INTO ticket_files (ticket_id, category, file_name, mime_type, size_bytes, storage_path, uploaded_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
      [
        req.params.ticketId, category, safeName, req.file.mimetype, req.file.size,
        storageKey, req.user!.id,
      ],
    );
    await auditRepo.log({
      entityType: 'ticket_file', entityId: String(record!.id), action: 'upload',
      newValue: safeName, userId: req.user!.id,
    });
    res.status(201).json(record);
  }),
);

fileRoutes.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const record = await queryOne(`SELECT * FROM ticket_files WHERE id = $1`, [req.params.id]);
    if (!record) throw new NotFoundError('File');
    try {
      const object = await fileStorage.get(record.storage_path as string);
      res.setHeader('Content-Type', (record.mime_type as string) || object.contentType || 'application/octet-stream');
      res.setHeader('Content-Disposition', `inline; filename="${record.file_name}"`);
      res.send(object.buffer);
    } catch (err) {
      if (err instanceof StorageNotFound) throw new NotFoundError('File');
      throw err;
    }
  }),
);

fileRoutes.delete(
  '/:id',
  writeAccess,
  asyncHandler(async (req, res) => {
    const record = await queryOne(`DELETE FROM ticket_files WHERE id = $1 RETURNING *`, [req.params.id]);
    if (!record) throw new NotFoundError('File');
    await fileStorage.delete(record.storage_path as string);
    await auditRepo.log({
      entityType: 'ticket_file', entityId: req.params.id, action: 'delete',
      oldValue: record.file_name as string, userId: req.user!.id,
    });
    res.json({ ok: true });
  }),
);
