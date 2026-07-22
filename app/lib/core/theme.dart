import 'package:flutter/material.dart';

/// Government-professional Material 3 theme: restrained navy seed colour,
/// clear contrast, identical component shapes in light and dark mode, with
/// smooth cross-platform page transitions so navigating never feels abrupt.
class AppTheme {
  static const _seed = Color(0xFF1A4480); // government navy

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  // A consistent, smooth zoom/fade on every platform (web & desktop included,
  // where the default is otherwise an abrupt cut).
  static const _transitions = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: ZoomPageTransitionsBuilder(),
      TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
      TargetPlatform.linux: ZoomPageTransitionsBuilder(),
      TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
      TargetPlatform.windows: ZoomPageTransitionsBuilder(),
    },
  );

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final dark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? scheme.surface : const Color(0xFFF4F6FB),
      visualDensity: VisualDensity.adaptivePlatformDensity,
      pageTransitionsTheme: _transitions,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surfaceTint,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: dark ? scheme.surface : Colors.white,
        indicatorColor: scheme.secondaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onSecondaryContainer),
        selectedLabelTextStyle: TextStyle(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        color: dark ? scheme.surfaceContainerLow : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        filled: true,
        fillColor: dark ? scheme.surfaceContainerHighest.withValues(alpha: 0.3) : Colors.white,
        isDense: true,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHighest),
        headingTextStyle: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

/// Colour coding for a printer's operational status, tuned to be easy on the
/// eyes: a soft tinted background with a saturated foreground dot + label
/// rather than a loud solid fill.
///
///   active   → green  (in service)
///   inactive → red    (temporarily out of service — needs attention)
///   repair   → amber  (being addressed)
///   disposed → near-black / slate (retired for good)
class PrinterStatusColors {
  const PrinterStatusColors._();

  static const _green = Color(0xFF2E7D32);
  static const _red = Color(0xFFC62828);
  static const _amber = Color(0xFFF9A825);
  static const _slateLight = Color(0xFF37474F); // near-black in light mode
  static const _slateDark = Color(0xFF90A4AE); // legible on dark surfaces

  /// The accent colour for a status, brightness-aware so 'disposed' stays
  /// readable in dark mode where a near-black would vanish.
  static Color color(String status, [Brightness brightness = Brightness.light]) {
    switch (status) {
      case 'active':
        return _green;
      case 'inactive':
        return _red;
      case 'repair':
        return _amber;
      case 'disposed':
        return brightness == Brightness.dark ? _slateDark : _slateLight;
      default:
        return const Color(0xFF9E9E9E);
    }
  }

  static String label(String status) => switch (status) {
        'active' => 'Active',
        'inactive' => 'Inactive',
        'repair' => 'In Repair',
        'disposed' => 'Disposed',
        _ => status.isEmpty ? '—' : '${status[0].toUpperCase()}${status.substring(1)}',
      };

  static IconData icon(String status) => switch (status) {
        'active' => Icons.check_circle,
        'inactive' => Icons.pause_circle_filled,
        'repair' => Icons.build_circle,
        'disposed' => Icons.delete_forever,
        _ => Icons.help,
      };
}

/// A soft, colour-coded status pill used across printer views. Animates its
/// colour when the underlying status changes.
class PrinterStatusBadge extends StatelessWidget {
  const PrinterStatusBadge(this.status, {super.key, this.dense = false});

  final String status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final c = PrinterStatusColors.color(status, brightness);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: brightness == Brightness.dark ? 0.22 : 0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PrinterStatusColors.icon(status), size: dense ? 13 : 15, color: c),
          SizedBox(width: dense ? 4 : 6),
          Text(
            PrinterStatusColors.label(status),
            style: TextStyle(
              color: brightness == Brightness.dark ? Colors.white : const Color(0xFF1B1B1B),
              fontWeight: FontWeight.w600,
              fontSize: dense ? 11 : 12,
            ),
          ),
        ],
      ),
    );
  }
}
