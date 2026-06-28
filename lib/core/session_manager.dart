import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages authentication state, persisting tokens and user info
/// to SharedPreferences for session restoration across app restarts.
class SessionManager {
  SessionManager._();

  static const _keyDeviceIdentifier = 'session_device_identifier';

  static Future<String> getDeviceIdentifier() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_keyDeviceIdentifier);
    if (id == null || id.isEmpty) {
      final rand = DateTime.now().microsecondsSinceEpoch.toString();
      id = 'DEV-$rand';
      await prefs.setString(_keyDeviceIdentifier, id);
    }
    return id;
  }

  static Future<String> getDeviceModel() async {
    if (kIsWeb) return 'Web Browser';
    return 'Desktop/Mobile Client';
  }

  static Future<String> getDevicePlatform() async {
    if (kIsWeb) return 'WEB';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android: return 'ANDROID';
      case TargetPlatform.iOS: return 'IOS';
      case TargetPlatform.windows: return 'WINDOWS';
      case TargetPlatform.macOS: return 'MACOS';
      case TargetPlatform.linux: return 'LINUX';
      default: return 'UNKNOWN';
    }
  }

  static Future<String> getDeviceOSVersion() async {
    return '1.0.0';
  }

  static Future<String> getDeviceManufacturer() async {
    if (kIsWeb) return 'BrowserVendor';
    return 'SystemManufacturer';
  }

  // In-memory cache
  static String? _accessToken;
  static String? _refreshToken;
  static String? _role;
  static String? _userId;
  static String? _email;
  static String? _fullName;
  static String? _organizationId;

  // SharedPreferences keys
  static const _keyAccessToken = 'session_access_token';
  static const _keyRefreshToken = 'session_refresh_token';
  static const _keyRole = 'session_role';
  static const _keyUserId = 'session_user_id';
  static const _keyEmail = 'session_email';
  static const _keyFullName = 'session_full_name';
  static const _keyOrgId = 'session_organization_id';

  // -----------------------------------------------------------------------
  // Getters (read from memory cache)
  // -----------------------------------------------------------------------
  static String? get accessToken => _accessToken;
  static String? get refreshToken => _refreshToken;
  static String? get role => _role;
  static String? get userId => _userId;
  static String? get email => _email;
  static String? get fullName => _fullName;
  static String? get organizationId => _organizationId;

  static bool get isLoggedIn => _accessToken != null && _accessToken!.isNotEmpty;
  static bool get isAdmin => _role == 'ADMIN';
  static bool get isFaculty => _role == 'FACULTY';

  // -----------------------------------------------------------------------
  // Restore session from disk (call at app start)
  // -----------------------------------------------------------------------
  static Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_keyAccessToken);
    _refreshToken = prefs.getString(_keyRefreshToken);
    _role = prefs.getString(_keyRole);
    _userId = prefs.getString(_keyUserId);
    _email = prefs.getString(_keyEmail);
    _fullName = prefs.getString(_keyFullName);
    _organizationId = prefs.getString(_keyOrgId);

    // Restore geofence cache
    _geofenceLatitude = prefs.getDouble('session_geofence_latitude');
    _geofenceLongitude = prefs.getDouble('session_geofence_longitude');
    _geofenceRadius = prefs.getDouble('session_geofence_radius');
    _geofenceType = prefs.getString('session_geofence_type');
    _geofenceVerticesJson = prefs.getString('session_geofence_vertices_json');
    _allowedOutsideMinutes = prefs.getInt('session_allowed_outside_minutes');
    _reminder1Minutes = prefs.getInt('session_reminder_1_minutes');
    _reminder2Minutes = prefs.getInt('session_reminder_2_minutes');
    _reminder3Minutes = prefs.getInt('session_reminder_3_minutes');
    _evaluationMinutes = prefs.getInt('session_evaluation_minutes');
  }

  // -----------------------------------------------------------------------
  // Save refreshed access token
  // -----------------------------------------------------------------------
  static Future<void> saveAccessToken(String token) async {
    _accessToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccessToken, token);
  }

  // -----------------------------------------------------------------------
  // Save session after login
  // -----------------------------------------------------------------------
  static Future<void> saveSession({
    required String accessToken,
    required String refreshToken,
    required String role,
    required String userId,
    required String email,
    required String fullName,
    required String organizationId,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _role = role;
    _userId = userId;
    _email = email;
    _fullName = fullName;
    _organizationId = organizationId;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccessToken, accessToken);
    await prefs.setString(_keyRefreshToken, refreshToken);
    await prefs.setString(_keyRole, role);
    await prefs.setString(_keyUserId, userId);
    await prefs.setString(_keyEmail, email);
    await prefs.setString(_keyFullName, fullName);
    await prefs.setString(_keyOrgId, organizationId);
  }

  // -----------------------------------------------------------------------
  // Clear session on logout
  // -----------------------------------------------------------------------
  static Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    _role = null;
    _userId = null;
    _email = null;
    _fullName = null;
    _organizationId = null;
    _geofenceLatitude = null;
    _geofenceLongitude = null;
    _geofenceRadius = null;
    _geofenceType = null;
    _geofenceVerticesJson = null;
    unreadNotifications.value = 0;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccessToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyRole);
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyEmail);
    await prefs.remove(_keyFullName);
    await prefs.remove(_keyOrgId);
    
    await prefs.remove('session_geofence_latitude');
    await prefs.remove('session_geofence_longitude');
    await prefs.remove('session_geofence_radius');
    await prefs.remove('session_geofence_type');
    await prefs.remove('session_geofence_vertices_json');
    await prefs.remove('session_allowed_outside_minutes');
    await prefs.remove('session_reminder_1_minutes');
    await prefs.remove('session_reminder_2_minutes');
    await prefs.remove('session_reminder_3_minutes');
    await prefs.remove('session_evaluation_minutes');
  }

  // Geofence cache
  static double? _geofenceLatitude;
  static double? _geofenceLongitude;
  static double? _geofenceRadius;
  static String? _geofenceType;
  static String? _geofenceVerticesJson;
  static int? _allowedOutsideMinutes;
  static int? _reminder1Minutes;
  static int? _reminder2Minutes;
  static int? _reminder3Minutes;
  static int? _evaluationMinutes;

  static double? get geofenceLatitude => _geofenceLatitude;
  static double? get geofenceLongitude => _geofenceLongitude;
  static double? get geofenceRadius => _geofenceRadius;
  static String? get geofenceType => _geofenceType;
  static String? get geofenceVerticesJson => _geofenceVerticesJson;
  static int? get allowedOutsideMinutes => _allowedOutsideMinutes;
  static int? get reminder1Minutes => _reminder1Minutes;
  static int? get reminder2Minutes => _reminder2Minutes;
  static int? get reminder3Minutes => _reminder3Minutes;
  static int? get evaluationMinutes => _evaluationMinutes;

  static void cacheGeofence(
    double lat,
    double lng,
    double rad,
    String type,
    String? verticesJson, [
    int? allowedOutside,
    int? reminder1,
    int? reminder2,
    int? reminder3,
    int? evaluation,
  ]) {
    _geofenceLatitude = lat;
    _geofenceLongitude = lng;
    _geofenceRadius = rad;
    _geofenceType = type;
    _geofenceVerticesJson = verticesJson;
    if (allowedOutside != null) _allowedOutsideMinutes = allowedOutside;
    if (reminder1 != null) _reminder1Minutes = reminder1;
    if (reminder2 != null) _reminder2Minutes = reminder2;
    if (reminder3 != null) _reminder3Minutes = reminder3;
    if (evaluation != null) _evaluationMinutes = evaluation;

    SharedPreferences.getInstance().then((prefs) {
      prefs.setDouble('session_geofence_latitude', lat);
      prefs.setDouble('session_geofence_longitude', lng);
      prefs.setDouble('session_geofence_radius', rad);
      prefs.setString('session_geofence_type', type);
      if (verticesJson != null) {
        prefs.setString('session_geofence_vertices_json', verticesJson);
      } else {
        prefs.remove('session_geofence_vertices_json');
      }
      if (allowedOutside != null) {
        prefs.setInt('session_allowed_outside_minutes', allowedOutside);
      }
      if (reminder1 != null) prefs.setInt('session_reminder_1_minutes', reminder1);
      if (reminder2 != null) prefs.setInt('session_reminder_2_minutes', reminder2);
      if (reminder3 != null) prefs.setInt('session_reminder_3_minutes', reminder3);
      if (evaluation != null) prefs.setInt('session_evaluation_minutes', evaluation);
    });
  }

  // Global unread notifications notifier
  static final ValueNotifier<int> unreadNotifications = ValueNotifier<int>(0);

  // -----------------------------------------------------------------------
  // UI State Persistence (Banners & Walkthroughs)
  // -----------------------------------------------------------------------

  static const _keyOrgCodeBannerTriggered = 'ui_org_code_banner_triggered';

  /// Returns [true] if the post-registration organization code banner should be shown.
  static Future<bool> shouldShowOrgCodeBanner() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyOrgCodeBannerTriggered) ?? false;
  }

  /// Sets the flag to show the banner (called only once after successful registration).
  static Future<void> triggerOrgCodeBanner() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOrgCodeBannerTriggered, true);
  }

  /// Permanently dismisses the organization code banner.
  static Future<void> setOrgCodeBannerSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyOrgCodeBannerTriggered, false);
  }
}
