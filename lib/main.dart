import 'package:flutter/material.dart';
import 'core/constants/app_colors.dart';
import 'core/database/database_service.dart';
import 'views/dashboard_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialisation du stockage local ultra-rapide (SQLite Desktop/Mobile ou Cache Web PWA)
  await DatabaseService.instance.init();

  runApp(const DocPocketMedocsApp());
}

class DocPocketMedocsApp extends StatelessWidget {
  const DocPocketMedocsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DocPocket Medocs',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryBlue,
          primary: AppColors.primaryBlue,
          secondary: AppColors.primaryDark,
          surface: Colors.white,
        ),
        fontFamily: '-apple-system',
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Colors.white,
          foregroundColor: AppColors.slateDark,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.slateLight),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.slateLight),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
          ),
          labelStyle: const TextStyle(color: AppColors.slateMedium),
        ),
      ),
      home: const DashboardView(),
    );
  }
}
