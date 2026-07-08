import { NextFunction, Request, Response } from 'express';
import { ZodError } from 'zod';
import { AppError, ForbiddenError, UnauthorizedError } from '../domain/errors';
import { AuthUser, RoleCode } from '../domain/types';
import { authService } from '../application/authService';

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      user?: AuthUser;
    }
  }
}

/** Wrap async handlers so rejections reach the error middleware. */
export function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<unknown>,
) {
  return (req: Request, res: Response, next: NextFunction) => {
    fn(req, res, next).catch(next);
  };
}

export function requireAuth(req: Request, _res: Response, next: NextFunction): void {
  const header = req.headers.authorization;
  const token =
    header?.startsWith('Bearer ') ? header.slice(7) : (req.query.token as string | undefined);
  if (!token) throw new UnauthorizedError();
  req.user = authService.verify(token);
  next();
}

/**
 * Role gate. viewer < ict_officer < admin. Viewers can only read; write
 * routes require at least ict_officer.
 */
export function requireRole(...roles: RoleCode[]) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.user) throw new UnauthorizedError();
    if (!roles.includes(req.user.role)) throw new ForbiddenError();
    next();
  };
}

export const writeAccess = requireRole('admin', 'ict_officer');
export const adminOnly = requireRole('admin');

export function errorHandler(err: unknown, _req: Request, res: Response, _next: NextFunction): void {
  if (err instanceof AppError) {
    res.status(err.statusCode).json({ error: { code: err.code, message: err.message } });
    return;
  }
  if (err instanceof ZodError) {
    res.status(400).json({
      error: {
        code: 'validation_error',
        message: err.errors.map((e) => `${e.path.join('.')}: ${e.message}`).join('; '),
      },
    });
    return;
  }
  // Unique-constraint violations surface as friendly conflicts.
  const pgErr = err as { code?: string; detail?: string; message?: string };
  if (pgErr.code === '23505') {
    res.status(409).json({ error: { code: 'conflict', message: 'A record with that value already exists' } });
    return;
  }
  console.error('[error]', err);
  res.status(500).json({ error: { code: 'internal', message: 'Internal server error' } });
}
