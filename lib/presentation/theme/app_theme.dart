import 'package:flutter/material.dart';

class AppTheme {
  // Brand & Sensor Colors
  static const Color polarRed = Color(0xFFE5002B);
  static const Color polarCyan = Color(0xFF00C7D4);
  static const Color darkBackground = Color(0xFF0D1117);
  static const Color darkCard = Color(0xFF161B22);
  static const Color darkBorder = Color(0xFF30363D);

  // Sleep Stage Colors
  static const Color wakeColor = Color(0xFFFF6B6B);   // Coral / Pink
  static const Color remColor = Color(0xFF9D4EDD);    // Violet / Purple
  static const Color lightColor = Color(0xFF48CAE4);  // Light Cyan
  static const Color deepColor = Color(0xFF023E8A);   // Deep Indigo Navy

  // Recovery Scores
  static const Color recoveryOptimal = Color(0xFF2EC4B6);
  static const Color recoveryGood = Color(0xFF20BF55);
  static const Color recoveryModerate = Color(0xFFFF9F1C);
  static const Color recoveryLow = Color(0xFFE71D36);

  static Color getRecoveryColor(int score) {
    if (score >= 85) return recoveryOptimal;
    if (score >= 70) return recoveryGood;
    if (score >= 50) return recoveryModerate;
    return recoveryLow;
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: polarCyan,
        secondary: polarRed,
        surface: darkCard,
        error: recoveryLow,
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkCard,
        selectedItemColor: polarCyan,
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
    );
  }
}
