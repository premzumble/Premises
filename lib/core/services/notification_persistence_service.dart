import 'package:shared_preferences/shared_preferences.dart';

/// Persistently tracks which notifications or alerts have already been 
/// presented to the user to avoid reappearance on app launch.
class NotificationPersistenceService {
  NotificationPersistenceService._();

  static const String _prefix = 'notif_shown_';

  /// Marks a specific notification ID as "shown" for the current date.
  /// For daily recurring events like "Attendance Registered", we use the date.
  static Future<void> markAsShown(String key, {String? date}) async {
    final prefs = await SharedPreferences.getInstance();
    final fullKey = date != null ? '${_prefix}${key}_$date' : '$_prefix$key';
    await prefs.setBool(fullKey, true);
  }

  /// Checks if a notification with this key has already been shown.
  static Future<bool> isShown(String key, {String? date}) async {
    final prefs = await SharedPreferences.getInstance();
    final fullKey = date != null ? '${_prefix}${key}_$date' : '$_prefix$key';
    return prefs.getBool(fullKey) ?? false;
  }

  /// Clears old notification flags (optional maintenance).
  static Future<void> clearOldFlags() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    
    // Simple logic: if many flags exist, clear them all to prevent bloat.
    // In a real app, we might check dates.
    if (keys.length > 100) {
      for (final k in keys) {
        await prefs.remove(k);
      }
    }
  }
}
