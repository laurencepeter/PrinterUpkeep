/**
 * Workflow domain logic.
 *
 * Stages live in the workflow_stages table (data-driven, per asset_type).
 * A ticket's current stage is the latest row in ticket_stage_history;
 * tickets.current_stage_id caches it for fast filtering. Status is always
 * DERIVED from the stage (stage.status_label) — there is no independent
 * status column to drift out of sync.
 */

export interface WorkflowStage {
  id: number;
  asset_type: string;
  code: string;
  name: string;
  status_label: string;
  sort_order: number;
  is_terminal: boolean;
}

export const STAGE_CODES = {
  OPEN: 'open',
  ICT_TICKET_RECEIVED: 'ict_ticket_received',
  VENDOR_CONTACTED: 'vendor_contacted',
  QUOTATION_RECEIVED: 'quotation_received',
  REQUISITION_PREPARED: 'requisition_prepared',
  SENT_TO_ACCOUNTS: 'sent_to_accounts',
  FUNDS_CONFIRMED: 'funds_confirmed',
  SENT_TO_GA: 'sent_to_ga',
  GA_APPROVED: 'ga_approved',
  PO_ISSUED: 'po_issued',
  VENDOR_WIP: 'vendor_wip',
  COMPLETED: 'completed',
  CLOSED: 'closed',
  CANCELLED: 'cancelled',
} as const;

/**
 * A stage change is valid if it moves to any non-cancelled stage (forward or
 * backward — real processes loop, e.g. a rejected quotation returns to
 * "Vendor Contacted"), as long as the ticket is not already terminal.
 * Cancellation is allowed from any non-terminal stage.
 */
export function canTransition(from: WorkflowStage, to: WorkflowStage): boolean {
  if (from.is_terminal) return false;
  if (to.code === from.code) return false;
  return true;
}

/** Progress through the happy path, 0..1, for the ■■■■□□□□□□ bar. */
export function progressFraction(stage: WorkflowStage, allStages: WorkflowStage[]): number {
  const path = allStages
    .filter((s) => s.sort_order < 90) // exclude cancelled (sort_order 99)
    .sort((a, b) => a.sort_order - b.sort_order);
  const index = path.findIndex((s) => s.id === stage.id);
  if (index < 0) return 0;
  return (index + 1) / path.length;
}
