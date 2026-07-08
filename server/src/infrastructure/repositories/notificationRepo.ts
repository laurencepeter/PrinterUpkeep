import { query, queryOne } from '../../db/pool';

export const notificationRepo = {
  /** Notifications for a user: their own plus broadcasts. */
  async listForUser(userId: string, unreadOnly = false) {
    return query(
      `SELECT n.*, t.ticket_number
       FROM notifications n LEFT JOIN tickets t ON t.id = n.ticket_id
       WHERE (n.user_id = $1 OR n.user_id IS NULL)
         ${unreadOnly ? 'AND NOT n.is_read' : ''}
       ORDER BY n.created_at DESC
       LIMIT 100`,
      [userId],
    );
  },

  async create(data: {
    userId?: string | null;
    ticketId?: string | null;
    type: string;
    title: string;
    message: string;
  }) {
    return queryOne(
      `INSERT INTO notifications (user_id, ticket_id, type, title, message)
       VALUES ($1, $2, $3, $4, $5) RETURNING *`,
      [data.userId ?? null, data.ticketId ?? null, data.type, data.title, data.message],
    );
  },

  /** Avoid duplicate open alerts of the same type for the same ticket. */
  async existsUnread(ticketId: string, type: string): Promise<boolean> {
    const row = await queryOne(
      `SELECT 1 AS x FROM notifications WHERE ticket_id = $1 AND type = $2 AND NOT is_read LIMIT 1`,
      [ticketId, type],
    );
    return row !== null;
  },

  async markRead(id: number, userId: string) {
    await query(
      `UPDATE notifications SET is_read = TRUE
       WHERE id = $1 AND (user_id = $2 OR user_id IS NULL)`,
      [id, userId],
    );
  },

  async markAllRead(userId: string) {
    await query(
      `UPDATE notifications SET is_read = TRUE WHERE (user_id = $1 OR user_id IS NULL) AND NOT is_read`,
      [userId],
    );
  },
};
