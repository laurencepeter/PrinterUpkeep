import { query, queryOne } from '../../db/pool';

export const departmentRepo = {
  async list(includeInactive = false) {
    return query(
      `SELECT d.*, (SELECT count(*) FROM tickets t WHERE t.department_id = d.id)::int AS ticket_count
       FROM departments d
       ${includeInactive ? '' : 'WHERE d.is_active'}
       ORDER BY d.name`,
    );
  },

  async byId(id: string) {
    return queryOne(`SELECT * FROM departments WHERE id = $1`, [id]);
  },

  async create(data: { name: string; code?: string | null; building?: string | null; floor?: string | null }) {
    return queryOne(
      `INSERT INTO departments (name, code, building, floor)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [data.name, data.code ?? null, data.building ?? null, data.floor ?? null],
    );
  },

  async update(
    id: string,
    data: { name?: string; code?: string | null; building?: string | null; floor?: string | null; isActive?: boolean },
  ) {
    return queryOne(
      `UPDATE departments SET
         name       = COALESCE($2, name),
         code       = COALESCE($3, code),
         building   = COALESCE($4, building),
         floor      = COALESCE($5, floor),
         is_active  = COALESCE($6, is_active),
         updated_at = now()
       WHERE id = $1 RETURNING *`,
      [id, data.name ?? null, data.code ?? null, data.building ?? null, data.floor ?? null, data.isActive ?? null],
    );
  },
};
