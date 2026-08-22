import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/login_screen.dart';
import 'theme/app_colors.dart';

void main() {
  runApp(const UdhaarApp());
}

class UdhaarApp extends StatelessWidget {
  const UdhaarApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = GoogleFonts.muktaTextTheme();

    return MaterialApp(
      title: 'Udhaar Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.warmCream,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.deepIndigo,
          primary: AppColors.deepIndigo,
          secondary: AppColors.marigold,
          error: AppColors.rickshawRed,
          surface: AppColors.warmCream,
        ),
        textTheme: baseTextTheme.copyWith(
          displayLarge: GoogleFonts.baloo2(fontWeight: FontWeight.w700, color: AppColors.deepIndigo),
          displayMedium: GoogleFonts.baloo2(fontWeight: FontWeight.w700, color: AppColors.deepIndigo),
          headlineLarge: GoogleFonts.baloo2(fontWeight: FontWeight.w700, color: AppColors.deepIndigo),
          headlineMedium: GoogleFonts.baloo2(fontWeight: FontWeight.w600, color: AppColors.deepIndigo),
          titleLarge: GoogleFonts.baloo2(fontWeight: FontWeight.w600, color: AppColors.deepIndigo),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.deepIndigo,
          foregroundColor: AppColors.warmCream,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.baloo2(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.warmCream,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            elevation: 2,
          ),
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.marigold.withOpacity(0.35), width: 1.5),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.deepIndigo.withOpacity(0.2)),
          ),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}