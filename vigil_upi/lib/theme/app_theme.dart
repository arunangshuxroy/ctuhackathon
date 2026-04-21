// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Color Palette ─────────────────────────────────────────────────────────
  static const bg = Color(0xFF080B14);          // Midnight Obsidian
  static const surface = Color(0xFF0F1623);     // Card surface
  static const glass = Color(0x1AFFFFFF);       // Glassmorphic overlay
  static const accent = Color(0xFF6C63FF);      // Soulprint violet
  static const accentGlow = Color(0x556C63FF);  // Glow halo
  static const success = Color(0xFF00E5A0);     // Confidence high
  static const warning = Color(0xFFFFB300);     // Confidence medium
  static const danger = Color(0xFFFF3B5C);      // Anomaly red
  static const textPrimary = Color(0xFFF0F4FF);
  static const textSecondary = Color(0xFF8892A4);

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: accent,
          secondary: success,
          surface: surface,
          error: danger,
        ),
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme).apply(
          bodyColor: textPrimary,
          displayColor: textPrimary,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: accent, width: 1.5),
          ),
          labelStyle: const TextStyle(color: textSecondary),
          hintStyle: const TextStyle(color: textSecondary),
        ),
      );
}
