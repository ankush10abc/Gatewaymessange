import 'package:flutter/material.dart';

class AppTheme {
  // WhatsApp official colors
  // static const Color whatsAppGreen = Color(0xFF00A884);
  static const Color whatsAppGreen = Color(0xFF142c98);
  // static const Color whatsAppDarkGreen = Color(0xFF008069);
  static const Color whatsAppDarkGreen = Color(0xFF051868);
  // static const Color whatsAppLightGreen = Color(0xFF25D366);
  static const Color whatsAppLightGreen = Color(0xFF3e75e5);
  // static const Color whatsAppTeal = Color(0xFF128C7E);
  static const Color whatsAppTeal = Color(0xFF2352b1);
  // static const Color whatsAppBlue = Color(0xFF53BDEB);
  static const Color whatsAppBlue = Color(0xFF3e75e5);
  static const Color whatsAppChatBg = Color(0xFFEFE7DD);
  static const Color whatsAppDarkBg = Color(0xFF0B141A);
  static const Color whatsAppDarkSurface = Color(0xFF202C33);
  static const Color whatsAppMyMessageBg = Color(0xFFD9FDD3);
  // static const Color splashcolor = Color(0xFF1dab61);
  static const Color splashcolor = Color(0xFF3e75e5);

  static ThemeData get lightTheme {
    return ThemeData(
      // primarySwatch: MaterialColor(0xFF00A884, {
      primarySwatch: MaterialColor(0xFF051868, {
        50: Color(0xFFE0F7F4),
        100: Color(0xFFB3EBE3),
        200: Color(0xFF80DDD1),
        300: Color(0xFF4DCFBE),
        400: Color(0xFF26C5B0),
        500: whatsAppGreen,
        600: Color(0xFF009A7C),
        700: Color(0xFF008A71),
        800: Color(0xFF007A66),
        900: Color(0xFF005D52),
      }),
      primaryColor: whatsAppGreen,
      // 👇 ADD THIS
      iconTheme: const IconThemeData(
        color: Colors.black,
      ),

      scaffoldBackgroundColor: Colors.white,
      appBarTheme: AppBarTheme(
        backgroundColor: whatsAppGreen,
        foregroundColor: Colors.white,
        elevation: 1,
        centerTitle: false,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: whatsAppGreen,
        foregroundColor: Colors.white,
      ),
      colorScheme: ColorScheme.light(
        primary: whatsAppGreen,
        secondary: whatsAppLightGreen,
        surface: Colors.white,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      // primarySwatch: MaterialColor(0xFF00A884, {
      primarySwatch: MaterialColor(0xFF051868, {
        50: Color(0xFFE0F7F4),
        100: Color(0xFFB3EBE3),
        200: Color(0xFF80DDD1),
        300: Color(0xFF4DCFBE),
        400: Color(0xFF26C5B0),
        500: whatsAppGreen,
        600: Color(0xFF009A7C),
        700: Color(0xFF008A71),
        800: Color(0xFF007A66),
        900: Color(0xFF005D52),
      }),
      primaryColor: whatsAppGreen,
      scaffoldBackgroundColor: whatsAppDarkBg,
      appBarTheme: AppBarTheme(
        backgroundColor: whatsAppDarkSurface,
        foregroundColor: Colors.white,
        elevation: 1,
        centerTitle: false,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: whatsAppGreen,
        foregroundColor: Colors.white,
      ),
      colorScheme: ColorScheme.dark(
        primary: whatsAppGreen,
        secondary: whatsAppLightGreen,
        surface: whatsAppDarkSurface,
        background: whatsAppDarkBg,
      ),
    );
  }
}
