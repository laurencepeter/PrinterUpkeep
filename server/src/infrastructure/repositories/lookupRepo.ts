import { query, queryOne } from '../../db/pool';
import { WorkflowStage } from '../../domain/workflow';

export const lookupRepo = {
  async workflowStages(assetType = 'printer'): Promise<WorkflowStage[]> {
    return query<WorkflowStage>(
      `SELECT id, asset_type, code, name, status_label, sort_order, is_terminal
       FROM workflow_stages WHERE asset_type = $1 ORDER BY sort_order`,
      [assetType],
    );
  },

  async stageByCode(code: string, assetType = 'printer'): Promise<WorkflowStage | null> {
    return queryOne<WorkflowStage>(
      `SELECT id, asset_type, code, name, status_label, sort_order, is_terminal
       FROM workflow_stages WHERE asset_type = $1 AND code = $2`,
      [assetType, code],
    );
  },

  async stageById(id: number): Promise<WorkflowStage | null> {
    return queryOne<WorkflowStage>(
      `SELECT id, asset_type, code, name, status_label, sort_order, is_terminal
       FROM workflow_stages WHERE id = $1`,
      [id],
    );
  },

  async issueCategories() {
    return query(
      `SELECT id, name, sort_order, is_active FROM issue_categories
       WHERE is_active ORDER BY sort_order`,
    );
  },

  async roles() {
    return query(`SELECT id, code, name, description FROM roles ORDER BY id`);
  },
};

export const settingsRepo = {
  async all() {
    return query(`SELECT key, value, description, updated_at FROM settings ORDER BY key`);
  },

  async get(key: string): Promise<string | null> {
    const row = await queryOne<{ value: string }>(`SELECT value FROM settings WHERE key = $1`, [key]);
    return row?.value ?? null;
  },

  async getInt(key: string, fallback: number): Promise<number> {
    const value = await this.get(key);
    const parsed = value === null ? NaN : parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : fallback;
  },

  async set(key: string, value: string) {
    await query(
      `INSERT INTO settings (key, value) VALUES ($1, $2)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now()`,
      [key, value],
    );
  },
};
