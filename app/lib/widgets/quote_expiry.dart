import 'package:flutter/material.dart';
import '../core/theme.dart';

/// Quotation validity: yellow inside the warning window (default 15 days),
/// red inside the critical window (default 10 days) and once expired.
/// The level and next steps are computed server-side (see quoteExpiry.ts).
class QuoteExpiry {
  static Color? colorFor(String? level) => switch (level) {
        'warning' => StageColors.waiting,
        'critical' || 'expired' => StageColors.blocked,
        _ => null,
      };

  static IconData iconFor(String? level) => switch (level) {
        'expired' => Icons.event_busy,
        'critical' => Icons.error_outline,
        _ => Icons.schedule,
      };

  static String describe(int? daysLeft) {
    if (daysLeft == null) return 'No expiry date';
    if (daysLeft < 0) return 'Expired ${-daysLeft} day${daysLeft == -1 ? '' : 's'} ago';
    if (daysLeft == 0) return 'Expires today';
    return 'Expires in $daysLeft day${daysLeft == 1 ? '' : 's'}';
  }

  static int? daysLeft(Map<String, dynamic> q) => (q['days_to_expiry'] as num?)?.toInt();
}

/// Small colour-coded pill, e.g. "Expires in 12 days".
class QuoteExpiryChip extends StatelessWidget {
  const QuoteExpiryChip({super.key, required this.level, required this.daysLeft});

  final String? level;
  final int? daysLeft;

  @override
  Widget build(BuildContext context) {
    final color = QuoteExpiry.colorFor(level) ?? StageColors.done;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(QuoteExpiry.iconFor(level), size: 14, color: color),
          const SizedBox(width: 4),
          Text(QuoteExpiry.describe(daysLeft),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

/// Banner with the reminder and the recommended next steps. Renders nothing
/// when the quote is outside the warning window.
class QuoteExpiryBanner extends StatelessWidget {
  const QuoteExpiryBanner({super.key, required this.quotation});

  final Map<String, dynamic> quotation;

  @override
  Widget build(BuildContext context) {
    final level = quotation['expiry_level'] as String?;
    final color = QuoteExpiry.colorFor(level);
    final steps = ((quotation['expiry_next_steps'] as List?) ?? const []).cast<String>();
    if (color == null || steps.isEmpty) return const SizedBox.shrink();

    final days = QuoteExpiry.daysLeft(quotation);
    final title = level == 'expired'
        ? 'Quotation expired - ${QuoteExpiry.describe(days).toLowerCase()}'
        : 'Quotation ${QuoteExpiry.describe(days).toLowerCase()} (${quotation['expiry_date'].toString().split('T').first})';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border(left: BorderSide(color: color, width: 4)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(QuoteExpiry.iconFor(level), color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('Next steps', style: Theme.of(context).textTheme.labelMedium),
          for (final (i, s) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('${i + 1}. $s'),
            ),
        ],
      ),
    );
  }
}
