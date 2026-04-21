// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Semantic colors (brightness-independent) ─────────────────────────────
  static const success          = Color(0xFF5AC05F);  // R90 G192 B95
  static const onSuccess        = Color(0xFF0A2E0B);
  static const successContainer = Color(0xFF1A4D1C);
  static const onSuccessContainer = Color(0xFFB7F0BA);

  static const danger           = Color(0xFFEC6765);  // R236 G103 B101
  static const onDanger         = Color(0xFF2D0000);
  static const dangerContainer  = Color(0xFF4E1010);
  static const onDangerContainer = Color(0xFFFFCDD2);

  static const warning          = Color(0xFFFFB300);
  static const onWarning        = Color(0xFF3D2A00);
  static const warningContainer = Color(0xFF5C3D00);
  static const onWarningContainer = Color(0xFFFFDEA0);

  // ── Fallback static palettes ──────────────────────────────────────────────
  static const _darkScheme = ColorScheme.dark(
    primary:               Color(0xFF6750A4),
    onPrimary:             Color(0xFFFFFFFF),
    primaryContainer:      Color(0xFF4F378B),
    onPrimaryContainer:    Color(0xFFEADDFF),
    secondary:             Color(0xFF625B71),
    onSecondary:           Color(0xFFFFFFFF),
    secondaryContainer:    Color(0xFF4A4458),
    onSecondaryContainer:  Color(0xFFE8DEF8),
    tertiary:              Color(0xFF7D5260),
    onTertiary:            Color(0xFFFFFFFF),
    tertiaryContainer:     Color(0xFF633B48),
    onTertiaryContainer:   Color(0xFFFFD8E4),
    surface:               Color(0xFF141218),
    onSurface:             Color(0xFFE6E1E5),
    surfaceContainerHighest: Color(0xFF36343B),
    onSurfaceVariant:      Color(0xFFCAC4D0),
    outline:               Color(0xFF938F99),
    outlineVariant:        Color(0xFF49454F),
    error:                 Color(0xFFCF6679),
    onError:               Color(0xFFFFFFFF),
    errorContainer:        Color(0xFF4E1527),
    onErrorContainer:      Color(0xFFFFB3C1),
    inverseSurface:        Color(0xFFE6E1E5),
    onInverseSurface:      Color(0xFF322F35),
    inversePrimary:        Color(0xFF6750A4),
  );

  static const _lightScheme = ColorScheme.light(
    primary:               Color(0xFF6750A4),
    onPrimary:             Color(0xFFFFFFFF),
    primaryContainer:      Color(0xFFEADDFF),
    onPrimaryContainer:    Color(0xFF21005D),
    secondary:             Color(0xFF625B71),
    onSecondary:           Color(0xFFFFFFFF),
    secondaryContainer:    Color(0xFFE8DEF8),
    onSecondaryContainer:  Color(0xFF1D192B),
    tertiary:              Color(0xFF7D5260),
    onTertiary:            Color(0xFFFFFFFF),
    tertiaryContainer:     Color(0xFFFFD8E4),
    onTertiaryContainer:   Color(0xFF31111D),
    surface:               Color(0xFFFFFBFE),
    onSurface:             Color(0xFF1C1B1F),
    surfaceContainerHighest: Color(0xFFE6E1E5),
    onSurfaceVariant:      Color(0xFF49454F),
    outline:               Color(0xFF79747E),
    outlineVariant:        Color(0xFFCAC4D0),
    error:                 Color(0xFFB3261E),
    onError:               Color(0xFFFFFFFF),
    errorContainer:        Color(0xFFF9DEDC),
    onErrorContainer:      Color(0xFF410E0B),
    inverseSurface:        Color(0xFF313033),
    onInverseSurface:      Color(0xFFF4EFF4),
    inversePrimary:        Color(0xFFD0BCFF),
  );

  static ThemeData dark([ColorScheme? dynamic]) =>
      _build(dynamic ?? _darkScheme);

  static ThemeData light([ColorScheme? dynamic]) =>
      _build(dynamic ?? _lightScheme);

  // ── Core builder — everything derived from cs ─────────────────────────────
  static ThemeData _build(ColorScheme cs) {
    final isDark = cs.brightness == Brightness.dark;
    final base = isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);

    final textColor = cs.onSurface;
    final subtleColor = cs.onSurfaceVariant;

    return base.copyWith(
      colorScheme: cs,
      scaffoldBackgroundColor: cs.surface,
      textTheme: GoogleFonts.interTextTheme(base.textTheme).copyWith(
        displayLarge:  GoogleFonts.inter(fontSize: 57, fontWeight: FontWeight.w400, color: textColor),
        displayMedium: GoogleFonts.inter(fontSize: 45, fontWeight: FontWeight.w400, color: textColor),
        displaySmall:  GoogleFonts.inter(fontSize: 36, fontWeight: FontWeight.w400, color: textColor),
        headlineLarge:  GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w600, color: textColor),
        headlineMedium: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w600, color: textColor),
        headlineSmall:  GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w600, color: textColor),
        titleLarge:  GoogleFonts.inter(fontSize: 22, fontWeight: FontWeight.w500, color: textColor),
        titleMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: textColor, letterSpacing: 0.15),
        titleSmall:  GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: textColor, letterSpacing: 0.1),
        bodyLarge:   GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w400, color: textColor, letterSpacing: 0.5),
        bodyMedium:  GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, color: textColor, letterSpacing: 0.25),
        bodySmall:   GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w400, color: subtleColor, letterSpacing: 0.4),
        labelLarge:  GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: textColor, letterSpacing: 0.1),
        labelMedium: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: subtleColor, letterSpacing: 0.5),
        labelSmall:  GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: subtleColor, letterSpacing: 0.5),
      ),
      cardTheme: CardThemeData(
        color: cs.surfaceContainerHighest,
        elevation: 1,
        surfaceTintColor: cs.primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          side: BorderSide(color: cs.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
          textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: cs.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: cs.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: cs.error, width: 2),
        ),
        labelStyle: GoogleFonts.inter(color: cs.onSurfaceVariant, fontSize: 16, letterSpacing: 0.5),
        hintStyle: GoogleFonts.inter(color: cs.outlineVariant, fontSize: 16),
        prefixIconColor: cs.onSurfaceVariant,
        suffixIconColor: cs.onSurfaceVariant,
        floatingLabelStyle: GoogleFonts.inter(color: cs.primary, fontSize: 12),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: cs.surfaceContainerHighest,
        selectedColor: cs.primaryContainer,
        side: BorderSide(color: cs.outlineVariant),
        labelStyle: GoogleFonts.inter(color: cs.onSurface, fontSize: 14, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        iconTheme: IconThemeData(color: cs.onSurfaceVariant, size: 18),
        checkmarkColor: cs.onPrimaryContainer,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cs.inverseSurface,
        contentTextStyle: GoogleFonts.inter(color: cs.onInverseSurface, fontSize: 14),
        actionTextColor: cs.inversePrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.surface,
        surfaceTintColor: cs.primary,
        modalBackgroundColor: cs.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        elevation: 1,
        modalElevation: 1,
        dragHandleColor: cs.outlineVariant,
        dragHandleSize: const Size(32, 4),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.surfaceContainerHighest,
        surfaceTintColor: cs.primary,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: GoogleFonts.inter(color: cs.onSurface, fontSize: 24, fontWeight: FontWeight.w400),
        contentTextStyle: GoogleFonts.inter(color: cs.onSurfaceVariant, fontSize: 14),
      ),
      dividerTheme: DividerThemeData(color: cs.outlineVariant, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        tileColor: Colors.transparent,
        iconColor: cs.onSurfaceVariant,
        titleTextStyle: GoogleFonts.inter(color: cs.onSurface, fontSize: 16, fontWeight: FontWeight.w400),
        subtitleTextStyle: GoogleFonts.inter(color: cs.onSurfaceVariant, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: cs.primary,
        linearTrackColor: cs.surfaceContainerHighest,
        circularTrackColor: cs.surfaceContainerHighest,
        linearMinHeight: 4,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? cs.onPrimary : cs.outline),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? cs.primary : cs.surfaceContainerHighest),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: cs.onSurfaceVariant,
          highlightColor: cs.primary.withOpacity(0.12),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        surfaceTintColor: cs.primary,
        elevation: 0,
        scrolledUnderElevation: 3,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(color: cs.onSurface, fontSize: 22, fontWeight: FontWeight.w400),
        iconTheme: IconThemeData(color: cs.onSurface),
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent)
            : SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
      ),
    );
  }
}
