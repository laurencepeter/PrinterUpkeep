/**
 * Quotation validity rules. A quote only matters until a purchase order locks
 * the price in, so reminders stop once the ticket reaches `po_issued`.
 */

export type QuoteExpiryLevel = 'ok' | 'warning' | 'critical' | 'expired';

export const QUOTE_EXPIRY_DEFAULTS = { warnDays: 15, criticalDays: 10 } as const;

/** Stages where an expiring quote can still derail procurement. */
export const QUOTE_SENSITIVE_STAGES = [
  'vendor_contacted',
  'quotation_received',
  'requisition_prepared',
  'sent_to_accounts',
  'funds_confirmed',
  'sent_to_ga',
  'ga_approved',
] as const;

export function isQuoteSensitiveStage(stageCode: string): boolean {
  return (QUOTE_SENSITIVE_STAGES as readonly string[]).includes(stageCode);
}

/** yellow at <= warnDays, red at <= criticalDays, expired once past the date. */
export function classifyQuoteExpiry(
  daysLeft: number | null,
  warnDays: number = QUOTE_EXPIRY_DEFAULTS.warnDays,
  criticalDays: number = QUOTE_EXPIRY_DEFAULTS.criticalDays,
): QuoteExpiryLevel | null {
  if (daysLeft === null || !Number.isFinite(daysLeft)) return null;
  if (daysLeft < 0) return 'expired';
  if (daysLeft <= criticalDays) return 'critical';
  if (daysLeft <= warnDays) return 'warning';
  return 'ok';
}

/** Actionable next steps for the officer, based on where the ticket sits. */
export function quoteExpiryNextSteps(stageCode: string, level: QuoteExpiryLevel): string[] {
  if (level === 'ok' || !isQuoteSensitiveStage(stageCode)) return [];

  if (level === 'expired') {
    return [
      'Contact the vendor for a revised quotation or a written validity extension',
      'Update the quotation with the new amount and expiry date',
      'If the amount changed, revise the requisition and re-confirm funds with Accounts',
    ];
  }

  const steps: string[] = [];
  switch (stageCode) {
    case 'vendor_contacted':
    case 'quotation_received':
      steps.push('Prepare the requisition now');
      steps.push('Send it to Accounts for funds confirmation');
      break;
    case 'requisition_prepared':
      steps.push('Send the requisition to Accounts today');
      break;
    case 'sent_to_accounts':
      steps.push('Follow up with Accounts for funds confirmation');
      break;
    case 'funds_confirmed':
      steps.push('Forward to GA for approval');
      break;
    case 'sent_to_ga':
      steps.push('Follow up with GA for approval');
      break;
    case 'ga_approved':
      steps.push('Issue the purchase order before the quote expires');
      break;
  }
  if (level === 'critical') {
    steps.push('Ask the vendor to confirm in writing that the quoted price will be held / extended');
  }
  return steps;
}
