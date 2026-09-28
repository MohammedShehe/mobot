import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MoColors {
  static const navy = Color(0xFF0F172A);
  static const panel = Color(0xFF17213A);
  static const teal = Color(0xFF14B8A6);
  static const mint = Color(0xFF2DD4BF);
  static const ink = Color(0xFF1E2A47);
}

ThemeData moTheme(Brightness b) {
  final dark = b == Brightness.dark;
  final accent = dark ? MoColors.mint : MoColors.teal;
  final scheme = ColorScheme.fromSeed(
    seedColor: MoColors.teal,
    brightness: b,
  ).copyWith(
    primary: accent,
    surface: dark ? MoColors.navy : Colors.white,
    onSurface: dark ? const Color(0xFFF1F5F9) : MoColors.ink,
  );
  final base = ThemeData(brightness: b, useMaterial3: true, colorScheme: scheme);
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: GoogleFonts.spaceGroteskTextTheme(base.textTheme)
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
    dividerColor: scheme.onSurface.withValues(alpha: 0.08),
    inputDecorationTheme: const InputDecorationTheme(border: InputBorder.none),
  );
}

/// Surface colour for cards / bubbles in the current theme.
Color moPanel(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? MoColors.panel
    : const Color(0xFFF1F5F9);

/// Logo variant that matches the theme (dark theme -> white-stroke logo).
String moLogo(BuildContext c) => Theme.of(c).brightness == Brightness.dark
    ? 'assets/logo_dark.png'
    : 'assets/logo_light.png';
