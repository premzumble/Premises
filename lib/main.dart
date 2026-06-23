import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/session_manager.dart';
import 'core/api_service.dart';
import 'core/services/notification_service.dart';
import 'routes/app_router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize notification service
  await NotificationService.initialize();

  // Restore persisted session before routing decisions are made
  await SessionManager.restore();

  // Validate the restored token against the live backend.
  // If it fails (expired, wrong device, server unreachable), force re-login.
  if (SessionManager.isLoggedIn) {
    final valid = await _validateSession();
    if (!valid) {
      await SessionManager.clear();
    }
  }

  runApp(const MyApp());
}

Future<bool> _validateSession() async {
  try {
    if (SessionManager.isAdmin) {
      await ApiService.fetchSettings();
    } else {
      await ApiService.fetchFacultyProfile();
    }
    return true;
  } on ApiException catch (e) {
    if (e.isAuthError) {
      debugPrint('[Main] Session validation failed (auth error): $e');
      return false;
    }
    debugPrint('[Main] Session validation encountered network/server error: $e');
    return true;
  } catch (e) {
    debugPrint('[Main] Session validation encountered unexpected error: $e');
    return true;
  }
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Premises',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.light,
      routerConfig: AppRouter.router,
    );
  }
}
