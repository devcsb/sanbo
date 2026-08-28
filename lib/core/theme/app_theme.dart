import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Brand primitives and component tokens for Sanbo's calm, layered UI.
///
/// Visual language borrows Astryx's warm paper surfaces, soft elevation,
/// generous radii, and pill CTAs while keeping Sanbo teal / navy / coral.
class AppTheme {
  static const brandNavy = Color(0xFF0B1B33);
  static const brandTeal = Color(0xFF2EC4B6);
  static const brandCoral = Color(0xFFFF6B5B);
  static const brandIndigo = Color(0xFF4A4E8C);

  /// Accessible primary for light filled buttons (on white / on-primary white).
  static const primary = Color(0xFF0F766E);

  static const pagePadding = 22.0;
  static const pageMaxWidth = 720.0;
  static const radiusSmall = 12.0;
  static const radiusMedium = 20.0;
  static const radiusLarge = 28.0;
  static const radiusPill = 999.0;

  // Motion tokens live next to the rest of the visual language so a future
  // theme refresh cannot leave transitions with a second, drifting source of
  // truth.
  static const motionStandard = Duration(milliseconds: 180);
  static const motionExpand = Duration(milliseconds: 240);
  static const motionFeedback = Duration(milliseconds: 120);
  static const motionCurve = Curves.easeOutCubic;

  static const _lightSurface = Color(0xFFF6F3ED);
  static const _lightCard = Color(0xFFFFFFFF);
  static const _lightMuted = Color(0xFFEEE9E0);
  static const _darkSurface = Color(0xFF0C1219);
  static const _darkCard = Color(0xFF161D27);

  /// Soft layered elevation inspired by Astryx `--shadow-low` / `--shadow-high`.
  static List<BoxShadow> elevationLow(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Color.fromRGBO(5, 30, 50, isDark ? 0.28 : 0.06),
        offset: const Offset(0, 1),
        blurRadius: 2,
      ),
      BoxShadow(
        color: Color.fromRGBO(5, 30, 50, isDark ? 0.22 : 0.07),
        offset: const Offset(0, 4),
        blurRadius: 14,
      ),
    ];
  }

  static List<BoxShadow> elevationHigh(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return [
      BoxShadow(
        color: Color.fromRGBO(5, 30, 50, isDark ? 0.32 : 0.08),
        offset: const Offset(0, 2),
        blurRadius: 4,
      ),
      BoxShadow(
        color: Color.fromRGBO(5, 30, 50, isDark ? 0.34 : 0.12),
        offset: const Offset(0, 12),
        blurRadius: 28,
      ),
    ];
  }

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: brandTeal,
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: const Color(0xFFCCF3EE),
      onPrimaryContainer: const Color(0xFF053B37),
      secondary: brandIndigo,
      onSecondary: Colors.white,
      secondaryContainer: const Color(0xFFE2E4F5),
      onSecondaryContainer: const Color(0xFF1E2148),
      tertiary: brandCoral,
      onTertiary: brandNavy,
      tertiaryContainer: const Color(0xFFFFDAD5),
      onTertiaryContainer: const Color(0xFF3B0710),
      surface: _lightSurface,
      onSurface: const Color(0xFF15110C),
      onSurfaceVariant: const Color(0xFF5A6468),
      surfaceContainerLowest: _lightCard,
      surfaceContainerLow: const Color(0xFFFBF9F5),
      surfaceContainer: _lightCard,
      surfaceContainerHigh: _lightMuted,
      surfaceContainerHighest: const Color(0xFFE6E1D7),
      outline: const Color(0xFF6F7A7E),
      outlineVariant: const Color(0xFFE2DDD3),
      error: const Color(0xFFC23B3B),
      onError: Colors.white,
      errorContainer: const Color(0xFFFFDAD6),
      onErrorContainer: const Color(0xFF410002),
    );
    return _build(scheme, isDark: false);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: brandTeal,
      brightness: Brightness.dark,
      primary: brandTeal,
      onPrimary: brandNavy,
      primaryContainer: const Color(0xFF0F4F4A),
      onPrimaryContainer: const Color(0xFFB8F5EE),
      secondary: const Color(0xFFA8B0DC),
      onSecondary: const Color(0xFF1A1E3D),
      secondaryContainer: const Color(0xFF2E335F),
      onSecondaryContainer: const Color(0xFFDCE0FF),
      tertiary: brandCoral,
      onTertiary: brandNavy,
      tertiaryContainer: const Color(0xFF7A2D2A),
      onTertiaryContainer: const Color(0xFFFFDAD5),
      surface: _darkSurface,
      onSurface: const Color(0xFFE8EEF0),
      onSurfaceVariant: const Color(0xFFA8B4B8),
      surfaceContainerLowest: const Color(0xFF080C12),
      surfaceContainerLow: _darkCard,
      surfaceContainer: const Color(0xFF1B2430),
      surfaceContainerHigh: const Color(0xFF243040),
      surfaceContainerHighest: const Color(0xFF2E3B4D),
      outline: const Color(0xFF7A8992),
      outlineVariant: const Color(0xFF2A3544),
      error: const Color(0xFFFF8A80),
      onError: const Color(0xFF690005),
      errorContainer: const Color(0xFF93000A),
      onErrorContainer: const Color(0xFFFFDAD6),
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
      visualDensity: VisualDensity.standard,
    );

    final text = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    final surfaceColor = isDark ? scheme.surfaceContainerLow : _lightCard;
    final borderColor = scheme.outlineVariant.withValues(
      alpha: isDark ? 0.7 : 0.95,
    );
    final softShadow = elevationLow(scheme.brightness);

    return base.copyWith(
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -1.1,
          height: 1.12,
        ),
        headlineMedium: text.headlineMedium?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
          height: 1.16,
        ),
        headlineSmall: text.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.55,
          height: 1.22,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.35,
          height: 1.28,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          height: 1.35,
        ),
        titleSmall: text.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          height: 1.35,
        ),
        bodyLarge: text.bodyLarge?.copyWith(height: 1.55, letterSpacing: 0.05),
        bodyMedium: text.bodyMedium?.copyWith(height: 1.52),
        bodySmall: text.bodySmall?.copyWith(height: 1.45),
        labelLarge: text.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: -0.05,
        ),
        labelMedium: text.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          letterSpacing: 0.05,
        ),
      ),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        toolbarHeight: 64,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle:
            (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
                .copyWith(statusBarColor: Colors.transparent),
        titleTextStyle: text.titleMedium?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.25,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface),
        actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 74,
        elevation: 0,
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.22 : 0.14),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusPill),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: -0.05,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 54),
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusPill),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusPill),
          ),
          side: BorderSide(color: scheme.outline.withValues(alpha: 0.55)),
          foregroundColor: scheme.onSurface,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: scheme.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSmall),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: scheme.onSurfaceVariant,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: surfaceColor,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          side: BorderSide(color: borderColor),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: 12,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
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
        color: borderColor,
        thickness: 1,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLarge),
        ),
        titleTextStyle: text.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(radiusLarge),
          ),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusPill),
            ),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: borderColor)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        side: BorderSide(color: borderColor),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusPill),
        ),
        labelStyle: text.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.primary.withValues(alpha: 0.12),
        circularTrackColor: scheme.primary.withValues(alpha: 0.12),
      ),
      // Soft ambient elevation for floating chrome (nav shells, overlays).
      extensions: <ThemeExtension<dynamic>>[
        SanboSurfaces(
          panelShadow: softShadow,
          floatShadow: elevationHigh(scheme.brightness),
          panelBorder: borderColor,
          mutedFill: isDark ? scheme.surfaceContainer : _lightMuted,
        ),
      ],
    );
  }
}

/// Surface tokens used by SoftPanel / floating chrome.
@immutable
class SanboSurfaces extends ThemeExtension<SanboSurfaces> {
  const SanboSurfaces({
    required this.panelShadow,
    required this.floatShadow,
    required this.panelBorder,
    required this.mutedFill,
  });

  final List<BoxShadow> panelShadow;
  final List<BoxShadow> floatShadow;
  final Color panelBorder;
  final Color mutedFill;

  static SanboSurfaces of(BuildContext context) {
    return Theme.of(context).extension<SanboSurfaces>() ??
        SanboSurfaces(
          panelShadow: AppTheme.elevationLow(Theme.of(context).brightness),
          floatShadow: AppTheme.elevationHigh(Theme.of(context).brightness),
          panelBorder: Theme.of(context).colorScheme.outlineVariant,
          mutedFill: Theme.of(context).colorScheme.surfaceContainerHigh,
        );
  }

  @override
  SanboSurfaces copyWith({
    List<BoxShadow>? panelShadow,
    List<BoxShadow>? floatShadow,
    Color? panelBorder,
    Color? mutedFill,
  }) {
    return SanboSurfaces(
      panelShadow: panelShadow ?? this.panelShadow,
      floatShadow: floatShadow ?? this.floatShadow,
      panelBorder: panelBorder ?? this.panelBorder,
      mutedFill: mutedFill ?? this.mutedFill,
    );
  }

  @override
  SanboSurfaces lerp(ThemeExtension<SanboSurfaces>? other, double t) {
    if (other is! SanboSurfaces) return this;
    return SanboSurfaces(
      panelShadow: t < 0.5 ? panelShadow : other.panelShadow,
      floatShadow: t < 0.5 ? floatShadow : other.floatShadow,
      panelBorder: Color.lerp(panelBorder, other.panelBorder, t) ?? panelBorder,
      mutedFill: Color.lerp(mutedFill, other.mutedFill, t) ?? mutedFill,
    );
  }
}
