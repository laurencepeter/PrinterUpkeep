import { query } from '../../db/pool';

export interface AuditEntry {
  entityType: string;
  entityId: string;
  action: string;
  field?: string;
  oldValue?: unknown;
  newValue?: unknown;
  userId?: string;
}

function asText(value: unknown): string | null {
  if (value === undefined || value === null) return null;
  return typeof value === 'string' ? value : JSON.stringify(value);
}

export const auditRepo = {
  async log(entry: AuditEntry): Promise<void> {
    await query(
      `INSERT INTO audit_logs (entity_type, entity_id, action, field, old_value, new_value, user_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [
        entry.entityType,
        entry.entityId,
        entry.action,
        entry.field ?? null,
        asText(entry.oldValue),
        asText(entry.newValue),
        entry.userId ?? null,
      ],
    );
  },

  /** Log one row per changed field between two record snapshots. */
  async logDiff(
    entityType: string,
    entityId: string,
    userId: string,
    before: Record<string, unknown>,
    after: Record<string, unknown>,
  ): Promise<void> {
    for (const key of Object.keys(after)) {
      const oldVal = before[key];
      const newVal = after[key];
      if (JSON.stringify(oldVal) !== JSON.stringify(newVal)) {
        await this.log({
          entityType,
          entityId,
          action: 'update',
          field: key,
          oldValue: oldVal,
          newValue: newVal,
          userId,
        });
      }
    }
  },

  async list(filters: {
    entityType?: string;
    entityId?: string;
    userId?: string;
    page: number;
    pageSize: number;
  }) {
    const where: string[] = [];
    const params: unknown[] = [];
    if (filters.entityType) {
      params.push(filters.entityType);
      where.push(`a.entity_type = $${params.length}`);
    }
    if (filters.entityId) {
      params.push(filters.entityId);
      where.push(`a.entity_id = $${params.length}`);
    }
    if (filters.userId) {
      params.push(filters.userId);
      where.push(`a.user_id = $${params.length}`);
    }
    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

    const totalRow = await query<{ count: string }>(
      `SELECT count(*)::text AS count FROM audit_logs a ${whereSql}`,
      params,
    );
    params.push(filters.pageSize, (filters.page - 1) * filters.pageSize);
    const items = await query(
      `SELECT a.*, u.full_name AS user_name
       FROM audit_logs a LEFT JOIN users u ON u.id = a.user_id
       ${whereSql}
       ORDER BY a.created_at DESC
       LIMIT $${params.length - 1} OFFSET $${params.length}`,
      params,
    );
    return {
      items,
      total: parseInt(totalRow[0].count, 10),
      page: filters.page,
      pageSize: filters.pageSize,
    };
  },
};
