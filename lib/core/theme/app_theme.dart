import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Calm, minimal brand theme (teal accent on soft neutrals).
class AppTheme {
  static const brandNavy = Color(0xFF0B1B33);
  static const brandTeal = Color(0xFF2EC4B6);
  static const brandCoral = Color(0xFFFF6B5B);
  static const brandIndigo = Color(0xFF4A4E8C);

  static const _primary = Color(0xFF1F8F86);
  static const _surface = Color(0xFFF7F8F8);
  static const _card = Color(0xFFFFFFFF);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: brandTeal,
      brightness: Brightness.light,
      primary: _primary,
      onPrimary: Colors.white,
      secondary: brandIndigo,
      tertiary: brandCoral,
      surface: _surface,
      onSurface: const Color(0xFF1A2224),
      onSurfaceVariant: const Color(0xFF5C6A6E),
      outline: const Color(0xFFB0BABB),
      outlineVariant: const Color(0xFFE2E7E8),
      error: const Color(0xFFC23B3B),
    );
    return _build(scheme, isDark: false);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: brandTeal,
      brightness: Brightness.dark,
      primary: brandTeal,
      onPrimary: brandNavy,
      secondary: const Color(0xFF9AA3D6),
      tertiary: brandCoral,
      surface: brandNavy,
      onSurface: const Color(0xFFE8EEF0),
      onSurfaceVariant: const Color(0xFFA8B4B8),
      outline: const Color(0xFF4A5860),
      outlineVariant: const Color(0xFF243040),
      error: const Color(0xFFFF8A80),
    );
    return _build(scheme, isDark: true);
  }

  static ThemeData _build(ColorScheme scheme, {required bool isDark}) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: scheme.brightness,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkSparkle.splashFactory,
    );

    final text = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    return base.copyWith(
      textTheme: text.copyWith(
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          height: 1.25,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.1,
        ),
        titleSmall: text.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: text.bodyLarge?.copyWith(height: 1.45),
        bodyMedium: text.bodyMedium?.copyWith(height: 1.45),
        bodySmall: text.bodySmall?.copyWith(height: 1.4),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: text.titleMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 64,
        elevation: 0,
        backgroundColor: isDark ? scheme.surface : _card,
        surfaceTintColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: 0.12),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 22,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.1,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(color: scheme.outlineVariant),
          foregroundColor: scheme.onSurface,
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? scheme.surfaceContainerHighest : _card,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.4 : 0.8),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: scheme.onSurfaceVariant,
        titleTextStyle: text.titleSmall?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        subtitleTextStyle: text.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.7),
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? scheme.surface : _card,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: text.titleMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? scheme.surface : _card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        circularTrackColor: scheme.primary.withValues(alpha: 0.12),
      ),
    );
  }
}
