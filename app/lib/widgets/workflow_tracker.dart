import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/models.dart';

/// The ■■■■□□□□□□ progress bar shown on every ticket.
class StageProgressBar extends StatelessWidget {
  const StageProgressBar({super.key, required this.progress, this.blocks = 10, this.compact = false});

  final double progress;
  final int blocks;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final filled = (progress * blocks).round().clamp(0, blocks);
    final size = compact ? 10.0 : 16.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < blocks; i++)
          Container(
            width: size,
            height: size,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(
              color: i < filled
                  ? StageColors.done
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        const SizedBox(width: 8),
        Text('${(progress * 100).round()}%', style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

/// Vertical colour-coded workflow tracker: every stage with its state
/// (green done / blue current / yellow waiting / red blocked / grey pending).
class WorkflowTracker extends StatelessWidget {
  const WorkflowTracker({super.key, required this.steps, this.timestamps = const {}});

  final List<TrackerStep> steps;

  /// stage code -> timestamp text of when the stage was first reached.
  final Map<String, String> timestamps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, step) in steps.indexed) ...[
          Row(
            children: [
              _StageDot(state: step.state),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  step.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: step.state == 'current' ? FontWeight.bold : FontWeight.normal,
                    color: step.state == 'not_started' ? theme.disabledColor : null,
                  ),
                ),
              ),
              if (timestamps[step.code] != null)
                Text(timestamps[step.code]!, style: theme.textTheme.labelSmall),
              const SizedBox(width: 8),
              _StateChip(state: step.state),
            ],
          ),
          if (index != steps.length - 1)
            Padding(
              padding: const EdgeInsets.only(left: 9),
              child: Container(
                width: 2,
                height: 14,
                color: step.state == 'done'
                    ? StageColors.done
                    : theme.colorScheme.outlineVariant,
              ),
            ),
        ],
      ],
    );
  }
}

class _StageDot extends StatelessWidget {
  const _StageDot({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final color = StageColors.forState(state);
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: state == 'done' || state == 'current' || state == 'blocked'
            ? color
            : Colors.transparent,
        border: Border.all(color: color, width: 2),
      ),
      child: switch (state) {
        'done' => const Icon(Icons.check, size: 13, color: Colors.white),
        'blocked' => const Icon(Icons.priority_high, size: 13, color: Colors.white),
        'current' => const Icon(Icons.play_arrow, size: 13, color: Colors.white),
        _ => null,
      },
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final color = StageColors.forState(state);
    final label = switch (state) {
      'done' => 'Done',
      'current' => 'Current',
      'waiting' => 'Waiting',
      'blocked' => 'Blocked',
      _ => 'Pending',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

/// Small status pill used in ticket lists.
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.label, this.blocked = false});
  final String label;
  final bool blocked;

  @override
  Widget build(BuildContext context) {
    final color = blocked
        ? StageColors.blocked
        : switch (label) {
            'Completed' || 'Closed' => StageColors.done,
            'Cancelled' => StageColors.notStarted,
            'Work In Progress' => StageColors.current,
            _ => StageColors.waiting,
          };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        blocked ? '$label (Blocked)' : label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}
