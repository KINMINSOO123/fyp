import 'package:flutter/material.dart';

abstract final class BakeryColors {
  static const primary = Color(0xFF5D4037);
  static const primaryLight = Color(0xFF8D6E63);
  static const accent = Color(0xFFF9A825);
  static const background = Color(0xFFFFF8F0);
  static const surface = Colors.white;
  static const text = Color(0xFF212121);
  static const secondary = Color(0xFF616161);
  static const divider = Color(0xFFE0D5CB);
  static const success = Color(0xFF2E7D32);
  static const warning = Color(0xFFED6C02);
  static const error = Color(0xFFC62828);
}

abstract final class BakeryTheme {
  static ThemeData get light {
    const radius = BorderRadius.all(Radius.circular(12));
    const scheme = ColorScheme.light(
      primary: BakeryColors.primary,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFEFEBE9),
      onPrimaryContainer: BakeryColors.primary,
      secondary: BakeryColors.accent,
      onSecondary: BakeryColors.text,
      surface: BakeryColors.surface,
      onSurface: BakeryColors.text,
      error: BakeryColors.error,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: BakeryColors.background,
    );
    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        headlineMedium: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: BakeryColors.text,
        ),
        headlineSmall: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: BakeryColors.text,
        ),
        titleLarge: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: BakeryColors.text,
        ),
        titleMedium: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: BakeryColors.text,
        ),
        bodyMedium: const TextStyle(
          fontSize: 13,
          height: 1.45,
          color: BakeryColors.secondary,
        ),
        labelLarge: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: BakeryColors.primary,
        foregroundColor: Colors.white,
        elevation: 1,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: BakeryColors.surface,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: 0.12),
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: const OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: BakeryColors.divider),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: BakeryColors.divider),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide(color: BakeryColors.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BakeryColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, 46),
          shape: const RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: BakeryColors.primary,
          minimumSize: const Size(0, 44),
          side: const BorderSide(color: BakeryColors.primaryLight),
          shape: const RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: BakeryColors.primary),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: BakeryColors.primary,
        foregroundColor: Colors.white,
      ),
      dividerTheme: const DividerThemeData(color: BakeryColors.divider),
      listTileTheme: const ListTileThemeData(
        iconColor: BakeryColors.primaryLight,
        textColor: BakeryColors.text,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: BakeryColors.primary.withValues(alpha: 0.10),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: states.contains(WidgetState.selected)
                ? BakeryColors.primary
                : BakeryColors.secondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? BakeryColors.accent
                : const Color(0xFFBDBDBD),
          ),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: BakeryColors.primary,
        contentTextStyle: TextStyle(color: Colors.white),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: const Color(0xFFEFEBE9),
        labelStyle: const TextStyle(
          color: BakeryColors.primary,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
        shape: const StadiumBorder(),
      ),
    );
  }
}
