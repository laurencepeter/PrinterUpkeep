import { query, queryOne } from '../../db/pool';

const SELECT = `
  SELECT u.id, u.username, u.full_name, u.email, u.phone, u.is_active,
         u.created_at, u.updated_at, r.code AS role, r.name AS role_name
  FROM users u JOIN roles r ON r.id = u.role_id`;

export const userRepo = {
  async list() {
    return query(`${SELECT} ORDER BY u.full_name`);
  },

  async byId(id: string) {
    return queryOne(`${SELECT} WHERE u.id = $1`, [id]);
  },

  async byUsernameWithHash(username: string) {
    return queryOne(
      `SELECT u.id, u.username, u.full_name, u.password_hash, u.is_active, r.code AS role
       FROM users u JOIN roles r ON r.id = u.role_id
       WHERE lower(u.username) = lower($1)`,
      [username],
    );
  },

  async create(data: {
    username: string;
    fullName: string;
    email?: string | null;
    phone?: string | null;
    passwordHash: string;
    roleCode: string;
  }) {
    return queryOne(
      `INSERT INTO users (username, full_name, email, phone, password_hash, role_id)
       VALUES ($1, $2, $3, $4, $5, (SELECT id FROM roles WHERE code = $6))
       RETURNING id`,
      [data.username, data.fullName, data.email ?? null, data.phone ?? null, data.passwordHash, data.roleCode],
    );
  },

  async update(
    id: string,
    data: {
      fullName?: string;
      email?: string | null;
      phone?: string | null;
      roleCode?: string;
      isActive?: boolean;
      passwordHash?: string;
    },
  ) {
    await query(
      `UPDATE users SET
         full_name     = COALESCE($2, full_name),
         email         = COALESCE($3, email),
         phone         = COALESCE($4, phone),
         role_id       = COALESCE((SELECT id FROM roles WHERE code = $5), role_id),
         is_active     = COALESCE($6, is_active),
         password_hash = COALESCE($7, password_hash),
         updated_at    = now()
       WHERE id = $1`,
      [
        id,
        data.fullName ?? null,
        data.email ?? null,
        data.phone ?? null,
        data.roleCode ?? null,
        data.isActive ?? null,
        data.passwordHash ?? null,
      ],
    );
  },

  async count(): Promise<number> {
    const row = await queryOne<{ count: string }>(`SELECT count(*)::text AS count FROM users`);
    return parseInt(row!.count, 10);
  },
};
