import { NotFoundError, ValidationError } from '../domain/errors';
import { canTransition, progressFraction, STAGE_CODES } from '../domain/workflow';
import { ticketRepo, TicketFilters } from '../infrastructure/repositories/ticketRepo';
import { lookupRepo } from '../infrastructure/repositories/lookupRepo';
import { auditRepo } from '../infrastructure/repositories/auditRepo';
import { notificationRepo } from '../infrastructure/repositories/notificationRepo';

export const ticketService = {
  async list(filters: TicketFilters) {
    return ticketRepo.list(filters);
  },

  /** Ticket detail plus everything the detail screen needs in one call. */
  async detail(id: string) {
    const ticket = await ticketRepo.byId(id);
    if (!ticket) throw new NotFoundError('Ticket');

    const [history, notes, files, quotations, requisitions, approvals, purchaseOrders, deliveryNotes, consumables, stages] =
      await Promise.all([
        ticketRepo.stageHistory(id),
        ticketRepo.notes(id),
        ticketRepo.files(id),
        ticketRepo.quotations(id),
        ticketRepo.requisitions(id),
        ticketRepo.approvals(id),
        ticketRepo.purchaseOrders(id),
        ticketRepo.deliveryNotes(id),
        ticketRepo.ticketConsumables(id),
        lookupRepo.workflowStages(ticket.asset_type as string),
      ]);

    const currentStage = stages.find((s) => s.id === ticket.stage_id)!;
    const reachedStageIds = new Set(history.map((h) => h.stage_code));

    // Workflow tracker: one entry per happy-path stage with its display state.
    const tracker = stages
      .filter((s) => s.sort_order < 90)
      .map((s) => {
        let state: 'done' | 'current' | 'blocked' | 'waiting' | 'not_started';
        if (s.sort_order < currentStage.sort_order) state = 'done';
        else if (s.id === currentStage.id) state = ticket.is_blocked ? 'blocked' : 'current';
        else if (s.sort_order === currentStage.sort_order + 1) state = 'waiting';
        else state = 'not_started';
        return {
          stage_id: s.id,
          code: s.code,
          name: s.name,
          sort_order: s.sort_order,
          state,
          reached: reachedStageIds.has(s.code),
        };
      });

    return {
      ticket,
      progress: progressFraction(currentStage, stages),
      tracker,
      history,
      notes,
      files,
      quotations,
      requisitions,
      approvals,
      purchase_orders: purchaseOrders,
      delivery_notes: deliveryNotes,
      consumables,
    };
  },

  async create(data: Record<string, unknown>, userId: string) {
    if (!data.reportedBy || String(data.reportedBy).trim() === '') {
      throw new ValidationError('reportedBy is required');
    }
    const openStage = await lookupRepo.stageByCode(STAGE_CODES.OPEN);
    if (!openStage) throw new Error('Workflow not seeded');

    const created = await ticketRepo.create(data, openStage.id, userId);
    await auditRepo.log({
      entityType: 'ticket',
      entityId: created.id,
      action: 'create',
      newValue: created.ticket_number,
      userId,
    });
    return this.detail(created.id);
  },

  async update(id: string, data: Record<string, unknown>, userId: string) {
    const before = await ticketRepo.byId(id);
    if (!before) throw new NotFoundError('Ticket');
    const after = await ticketRepo.update(id, data);
    await auditRepo.logDiff('ticket', id, userId, before, after as Record<string, unknown>);
    return this.detail(id);
  },

  /**
   * Move a ticket to a new workflow stage. Inserts history (never
   * overwrites), stamps timestamp + user + notes, updates the cached stage.
   */
  async changeStage(id: string, stageCode: string, userId: string, notes?: string) {
    const ticket = await ticketRepo.byId(id);
    if (!ticket) throw new NotFoundError('Ticket');

    const from = await lookupRepo.stageById(ticket.stage_id as number);
    const to = await lookupRepo.stageByCode(stageCode, ticket.asset_type as string);
    if (!to) throw new ValidationError(`Unknown stage: ${stageCode}`);
    if (!from || !canTransition(from, to)) {
      throw new ValidationError(`Cannot move from '${from?.name}' to '${to.name}'`);
    }

    await ticketRepo.changeStage(id, to.id, userId, notes);
    await auditRepo.log({
      entityType: 'ticket',
      entityId: id,
      action: 'stage_change',
      field: 'stage',
      oldValue: from.name,
      newValue: to.name,
      userId,
    });

    // Surface approval-chain stages on the dashboard notification feed.
    const approvalStages: Record<string, string> = {
      sent_to_accounts: 'Ticket awaiting Accounts approval',
      sent_to_ga: 'Ticket awaiting GA approval',
      vendor_contacted: 'Awaiting vendor response',
    };
    if (approvalStages[stageCode]) {
      await notificationRepo.create({
        ticketId: id,
        type: 'awaiting_action',
        title: approvalStages[stageCode],
        message: `${ticket.ticket_number}: ${approvalStages[stageCode]}`,
      });
    }
    return this.detail(id);
  },

  async addNote(id: string, userId: string, note: string) {
    if (!note.trim()) throw new ValidationError('Note cannot be empty');
    const ticket = await ticketRepo.byId(id);
    if (!ticket) throw new NotFoundError('Ticket');
    return ticketRepo.addNote(id, userId, note.trim());
  },
};
