import 'package:flutter/material.dart';

/// Shared tokens for every screen: 4-point spacing, accessible ink, Material 3.
abstract final class FintechSpace {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

abstract final class FintechRadius {
  static const field = 16.0;
  static const card = 24.0;
  static const panel = 28.0;
  static const pill = 28.0;
}

abstract final class FintechDesign {
  static const navy = Color(0xFF123047);
  static const ink = Color(0xFF192933);
  static const muted = Color(0xFF475967);
  static const mint = Color(0xFF0D7557);
  static const pale = Color(0xFFEAF7F1);
  static const canvas = Color(0xFFF5F8FA);
  static const stroke = Color(0xFFD5E0E4);

  static ThemeData theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final base = ColorScheme.fromSeed(
      seedColor: mint,
      brightness: brightness,
      surface: dark ? const Color(0xFF13202A) : Colors.white,
    );
    final scheme = base.copyWith(
      primary: dark ? const Color(0xFF89DDC0) : mint,
      onPrimary: dark ? const Color(0xFF092B21) : Colors.white,
      onSurface: dark ? const Color(0xFFF0F5F7) : ink,
      onSurfaceVariant: dark ? const Color(0xFFCBD6DD) : muted,
      outline: dark ? const Color(0xFF6B808A) : stroke,
      surfaceContainerLow: dark ? const Color(0xFF1B2B36) : const Color(0xFFF0F6F8),
    );
    final border = scheme.outline;
    final surface = scheme.surface;
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF0D1921) : canvas,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF0D1921) : canvas,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: scheme.onSurface),
      ),
      textTheme: TextTheme(
        headlineMedium: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: scheme.onSurface, letterSpacing: -0.7),
        titleLarge: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: scheme.onSurface),
        titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: scheme.onSurface),
        bodyLarge: TextStyle(fontSize: 16, height: 1.4, color: scheme.onSurface),
        bodyMedium: TextStyle(fontSize: 14, height: 1.35, color: scheme.onSurface),
        bodySmall: TextStyle(fontSize: 12, height: 1.4, color: scheme.onSurfaceVariant),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: dark ? .18 : .08),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: border.withValues(alpha: .7)),
          borderRadius: BorderRadius.circular(FintechRadius.card),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 76,
        backgroundColor: surface,
        elevation: 2,
        indicatorColor: dark ? const Color(0xFF224B43) : pale,
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: states.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
        )),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          size: 23,
          color: states.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
        )),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: scheme.onSurface,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        unselectedLabelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: border,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: FintechSpace.md, vertical: FintechSpace.md),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(FintechRadius.field)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(FintechRadius.field), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(FintechRadius.field), borderSide: BorderSide(color: scheme.primary, width: 2)),
      ),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FintechRadius.field)),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      )),
      outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FintechRadius.field)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      )),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: scheme.primary,
        disabledColor: scheme.surfaceContainerLow,
        labelStyle: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700),
        side: BorderSide(color: border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FintechRadius.pill)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        textColor: scheme.onSurface,
        titleTextStyle: TextStyle(color: scheme.onSurface, fontSize: 15, fontWeight: FontWeight.w700),
        subtitleTextStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: FintechSpace.md, vertical: FintechSpace.xs),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      dialogTheme: DialogThemeData(backgroundColor: surface, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FintechRadius.card))),
    );
  }
}

/// A responsive bento tile for dashboard and reports.
class FintechBentoTile extends StatelessWidget {
  const FintechBentoTile({super.key, required this.child, this.onTap, this.padding = FintechSpace.md});
  final Widget child;
  final VoidCallback? onTap;
  final double padding;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FintechRadius.card),
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    ),
  );
}

class FintechBentoGrid extends StatelessWidget {
  const FintechBentoGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final columns = constraints.maxWidth < 400 ? 1 : constraints.maxWidth < 850 ? 2 : 3;
    final width = (constraints.maxWidth - FintechSpace.sm * (columns - 1)) / columns;
    return Wrap(
      spacing: FintechSpace.sm,
      runSpacing: FintechSpace.sm,
      children: children.map((child) => SizedBox(width: width, child: child)).toList(),
    );
  });
}

/// High-contrast filter control used on dashboard, Money Map and activity.
/// It intentionally does not depend on ChoiceChip defaults, which can render
/// unselected labels too faint on some Android Material themes.
class FintechFilterPill extends StatelessWidget {
  const FintechFilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? scheme.onPrimary : scheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: '$label filter',
      child: Material(
        color: selected ? scheme.primary : scheme.surface,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? scheme.primary : scheme.outline),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 17, color: foreground),
                    const SizedBox(width: 7),
                  ],
                  Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared elevated surface for dashboard, payment, planner and settings cards.
class FintechSurface extends StatelessWidget {
  const FintechSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(FintechSpace.md),
    this.onTap,
    this.tint,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: tint ?? scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FintechRadius.card),
        side: BorderSide(color: scheme.outline.withValues(alpha: .72)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FintechRadius.card),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
