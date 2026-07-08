import 'package:flutter/material.dart';

/// Government-professional Material 3 theme: restrained navy seed colour,
/// clear contrast, identical component shapes in light and dark mode.
class AppTheme {
  static const _seed = Color(0xFF1A4480); // government navy

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      visualDensity: VisualDensity.compact,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
        isDense: true,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHighest),
      ),
    );
  }
}

/// Workflow state colours per the specification:
/// green=completed, blue=current, yellow=waiting, red=blocked, grey=not started.
class StageColors {
  static const done = Color(0xFF2E7D32);
  static const current = Color(0xFF1565C0);
  static const waiting = Color(0xFFF9A825);
  static const blocked = Color(0xFFC62828);
  static const notStarted = Color(0xFF9E9E9E);

  static Color forState(String state) => switch (state) {
        'done' => done,
        'current' => current,
        'waiting' => waiting,
        'blocked' => blocked,
        _ => notStarted,
      };
}

class PriorityColors {
  static Color forPriority(String priority) => switch (priority) {
        'critical' => const Color(0xFFC62828),
        'high' => const Color(0xFFEF6C00),
        'medium' => const Color(0xFF1565C0),
        _ => const Color(0xFF616161),
      };
}
