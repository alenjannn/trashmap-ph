import 'package:flutter/material.dart';

class AppTheme {
  // Premium Nature/Agri Palette
  static const Color primary = Color(0xFF1B4332);      // Deep Forest
  static const Color secondary = Color(0xFF40916C);    // Mid Green
  static const Color accent = Color(0xFF74C69D);       // Soft Sage
  static const Color primarySoft = Color(0xFFD8F3DC);  // Light Mint
  static const Color surface = Color(0xFFF9FBF9);      // Off-white / Cream
  static const Color textMain = Color(0xFF081C15);     // Darkest Green/Black
  static const Color textDim = Color(0xFF4B5563);      // Gray

  // Liquid Glass Tokens
  static Color glassBackground = Colors.white.withOpacity(0.7);
  static Color glassBorder = Colors.white.withOpacity(0.5);

  static ThemeData light() {
    final ColorScheme colorScheme = ColorScheme.fromSeed(
      seedColor: primary,
      primary: primary,
      secondary: secondary,
      tertiary: accent,
      surface: surface,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surface,
      
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: textMain,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w900,
          color: textMain,
          letterSpacing: -1.0,
        ),
      ),

      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 10,
        shadowColor: const Color(0x0D000000),
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
          side: BorderSide(color: Colors.white.withOpacity(0.8), width: 1.5),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: Colors.black.withOpacity(0.05)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: Colors.black.withOpacity(0.05)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent, // Controlled by our glass wrapper
        indicatorColor: primarySoft.withOpacity(0.5),
        height: 70,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 11,
            letterSpacing: 0.5,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: states.contains(WidgetState.selected) ? primary : const Color(0xFF64748B),
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
          (Set<WidgetState> states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected) ? primary : const Color(0xFF64748B),
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 0.5),
          elevation: 8,
          shadowColor: primary.withOpacity(0.3),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary.withOpacity(0.1), width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: textMain.withOpacity(0.9),
        contentTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
