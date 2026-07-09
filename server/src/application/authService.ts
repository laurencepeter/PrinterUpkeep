import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { config } from '../config';
import { AuthUser, RoleCode } from '../domain/types';
import { UnauthorizedError } from '../domain/errors';
import { userRepo } from '../infrastructure/repositories/userRepo';
import { auditRepo } from '../infrastructure/repositories/auditRepo';

export const authService = {
  async login(username: string, password: string): Promise<{ token: string; user: AuthUser }> {
    const record = await userRepo.byUsernameWithHash(username);
    if (!record || !record.is_active) throw new UnauthorizedError('Invalid username or password');

    const ok = await bcrypt.compare(password, record.password_hash as string);
    if (!ok) throw new UnauthorizedError('Invalid username or password');

    const user: AuthUser = {
      id: record.id as string,
      username: record.username as string,
      fullName: record.full_name as string,
      role: record.role as RoleCode,
    };
    const token = jwt.sign(user as object, config.auth.jwtSecret, {
      expiresIn: config.auth.tokenTtl,
    } as jwt.SignOptions);

    await auditRepo.log({ entityType: 'user', entityId: user.id, action: 'login', userId: user.id });
    return { token, user };
  },

  verify(token: string): AuthUser {
    try {
      const payload = jwt.verify(token, config.auth.jwtSecret) as AuthUser;
      return { id: payload.id, username: payload.username, fullName: payload.fullName, role: payload.role };
    } catch {
      throw new UnauthorizedError('Invalid or expired token');
    }
  },

  async hashPassword(password: string): Promise<string> {
    return bcrypt.hash(password, 10);
  },

  /** Create the initial admin account on first boot if no users exist. */
  async bootstrapAdmin(): Promise<void> {
    if ((await userRepo.count()) > 0) return;
    const hash = await this.hashPassword(config.bootstrap.adminPassword);
    await userRepo.create({
      username: config.bootstrap.adminUsername,
      fullName: config.bootstrap.adminFullName,
      passwordHash: hash,
      roleCode: 'admin',
    });
    console.log(
      `[bootstrap] created admin user '${config.bootstrap.adminUsername}' — change the password immediately`,
    );
  },
};
