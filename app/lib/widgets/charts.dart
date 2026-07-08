import 'package:flutter/material.dart';
import '../models/models.dart';

/// Dependency-free chart widgets: a vertical bar chart for time series and a
/// horizontal bar list for categorical breakdowns. Deliberately simple and
/// print-friendly for a government dashboard.
class MonthlyBarChart extends StatelessWidget {
  const MonthlyBarChart({super.key, required this.points, this.height = 180});

  final List<ChartPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const _EmptyChart();
    final maxCount = points.map((p) => p.count).reduce((a, b) => a > b ? a : b);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final p in points)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${p.count}', style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 2),
                    Tooltip(
                      message: '${p.label}: ${p.count}',
                      child: Container(
                        height: maxCount == 0 ? 2 : (height - 46) * (p.count / maxCount),
                        decoration: BoxDecoration(
                          color: scheme.primary,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      p.label.length >= 7 ? p.label.substring(5) : p.label,
                      style: Theme.of(context).textTheme.labelSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class HorizontalBarList extends StatelessWidget {
  const HorizontalBarList({super.key, required this.points, this.color});

  final List<ChartPoint> points;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const _EmptyChart();
    final maxCount = points.map((p) => p.count).reduce((a, b) => a > b ? a : b);
    final barColor = color ?? Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        for (final p in points)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                SizedBox(
                  width: 130,
                  child: Text(
                    p.label,
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => Stack(
                      children: [
                        Container(
                          height: 16,
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        Container(
                          height: 16,
                          width: maxCount == 0
                              ? 0
                              : constraints.maxWidth * (p.count / maxCount),
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    ' ${p.count}',
                    style: Theme.of(context).textTheme.labelMedium,
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text('No data yet', style: Theme.of(context).textTheme.bodySmall),
        ),
      );
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, this.icon, this.color, this.onTap});

  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 28, color: color ?? scheme.primary),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(value,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    Text(label,
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
