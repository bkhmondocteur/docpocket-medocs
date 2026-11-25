import 'package:flutter/material.dart';
import 'core/constants/app_colors.dart';
import 'core/database/database_service.dart';
import 'core/services/license_service.dart';
import 'core/services/supabase_sync_service.dart';
import 'views/dashboard_view.dart';
import 'views/welcome_auth_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await DatabaseService.instance.init();
    await LicenseService.instance.init();
    await SupabaseSyncService.instance.init();

    // Synchronisation initiale au démarrage si le cabinet est activé
    if (LicenseService.instance.isAuthenticated) {
      try {
        await SupabaseSyncService.instance
            .syncStock(actionDescription: 'Démarrage application')
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
  } catch (e) {
    debugPrint('Init services warning: $e');
  }

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
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
          ),
          labelStyle: const TextStyle(color: AppColors.slateMedium),
        ),
      ),
      home: LicenseService.instance.isAuthenticated
          ? const DashboardView()
          : const WelcomeAuthView(),
    );
  }
}
