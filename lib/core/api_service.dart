import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'session_manager.dart';
import 'app_config.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Base URL for all API requests.
/// For Flutter Web (running on any localhost port), this MUST be the backend URL.
/// The backend's DEV_MODE CORS middleware will accept any localhost origin.
const String _kBaseUrl = kApiBaseUrl;

/// Request timeout duration. Adjust as needed for slow networks.
const Duration _kTimeout = Duration(seconds: 15);

// ---------------------------------------------------------------------------
// ApiService
// ---------------------------------------------------------------------------

/// Centralized, industry-grade HTTP client for all Premises API requests.
///
/// Features:
/// - Automatic timeout handling
/// - Structured error classification (network vs. server vs. auth)
/// - Descriptive error messages for each failure mode
/// - Bearer token injection for authenticated routes
/// - UTF-8 safe response decoding
class ApiService {
  ApiService._();

  // -------------------------------------------------------------------------
  // Headers
  // -------------------------------------------------------------------------
  static Map<String, String> _headers({bool requiresAuth = false}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (requiresAuth) {
      final token = SessionManager.accessToken;
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  // -------------------------------------------------------------------------
  // Response Parser
  // -------------------------------------------------------------------------
  static Map<String, dynamic> _parseResponse(http.Response response) {
    late Map<String, dynamic> body;

    try {
      body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(
        message: 'The server returned an unreadable response. Please try again.',
        statusCode: response.statusCode,
        type: ApiErrorType.parseError,
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    // Extract the error message from standard or FastAPI error body
    final message = _extractErrorMessage(body, response.statusCode);
    final type = _classifyStatusCode(response.statusCode);

    throw ApiException(message: message, statusCode: response.statusCode, type: type);
  }

  static String _extractErrorMessage(Map<String, dynamic> body, int statusCode) {
    // Our StandardResponse format
    if (body['message'] != null && body['message'].toString().isNotEmpty) {
      return body['message'].toString();
    }
    // FastAPI validation error format
    if (body['detail'] != null) {
      final detail = body['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map && first['msg'] != null) {
          return 'Validation error: ${first['msg']}';
        }
      }
      return detail.toString();
    }
    // Fallback by status code
    return _defaultMessageForStatus(statusCode);
  }

  static String _defaultMessageForStatus(int statusCode) {
    switch (statusCode) {
      case 400: return 'Bad request. Please check your input and try again.';
      case 401: return 'Authentication failed. Please log in again.';
      case 403: return 'Access denied. You do not have permission to perform this action.';
      case 404: return 'The requested resource was not found.';
      case 409: return 'This record already exists. Please use a different value.';
      case 422: return 'Invalid data submitted. Please check all fields.';
      case 429: return 'Too many requests. Please wait a moment and try again.';
      case 500: return 'An unexpected server error occurred. Please contact support.';
      case 502: return 'Server is temporarily unavailable. Please try again shortly.';
      case 503: return 'Service unavailable. The server may be under maintenance.';
      default:  return 'Request failed with status $statusCode.';
    }
  }

  static ApiErrorType _classifyStatusCode(int statusCode) {
    if (statusCode == 401) return ApiErrorType.unauthorized;
    if (statusCode == 403) return ApiErrorType.forbidden;
    if (statusCode == 404) return ApiErrorType.notFound;
    if (statusCode == 409) return ApiErrorType.conflict;
    if (statusCode == 422) return ApiErrorType.validation;
    if (statusCode >= 500) return ApiErrorType.server;
    return ApiErrorType.client;
  }

  // -------------------------------------------------------------------------
  // Internal request executor with timeout + error wrapping
  // -------------------------------------------------------------------------
  static Future<http.Response> _execute(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_kTimeout);
    } on TimeoutException {
      throw ApiException(
        message: 'Request timed out. Please check your connection and try again.',
        statusCode: 0,
        type: ApiErrorType.timeout,
      );
    } catch (e) {
      // On Flutter Web, CORS and network errors surface as generic exceptions.
      // On mobile/desktop, network errors also surface here.
      debugPrint('[ApiService] Request error: $e');

      final errStr = e.toString().toLowerCase();
      final isNetworkIssue = errStr.contains('socket') ||
          errStr.contains('connection') ||
          errStr.contains('network') ||
          errStr.contains('failed to fetch') || // Flutter Web XHR error
          errStr.contains('xmlhttprequest') ||
          errStr.contains('cors');

      if (isNetworkIssue) {
        throw ApiException(
          message: kIsWeb
              ? 'Cannot reach the server. Make sure the backend is running at '
                  'http://localhost:8000 and that DEV_MODE=true is set in backend/.env.'
              : 'Cannot reach the server. Please check your internet connection '
                  'and ensure the backend is running.',
          statusCode: 0,
          type: ApiErrorType.network,
        );
      }

      // Re-throw ApiException as-is (double-caught from inner call)
      if (e is ApiException) rethrow;

      throw ApiException(
        message: 'An unexpected error occurred. Please try again.',
        statusCode: 0,
        type: ApiErrorType.unknown,
      );
    }
  }


  // =========================================================================
  // AUTH ENDPOINTS
  // =========================================================================

  /// POST /auth/register-admin
  /// Step 1: Initiates admin registration, triggers OTP.
  static Future<void> registerAdmin({
    required String orgName,
    required String orgType,
    required String adminName,
    required String email,
    required String password,
  }) async {
    final response = await _execute(() => http.post(
          Uri.parse('$_kBaseUrl/auth/register-admin'),
          headers: _headers(),
          body: jsonEncode({
            'org_name': orgName,
            'org_type': orgType,
            'admin_name': adminName,
            'email': email,
            'password': password,
          }),
        ));
    _parseResponse(response);
  }

  /// POST /auth/verify-otp
  /// Step 2: Verifies OTP and creates the organization + admin account.
  static Future<Map<String, dynamic>> verifyOtp({
    required String email,
    required String otp,
  }) async {
    final response = await _execute(() => http.post(
          Uri.parse('$_kBaseUrl/auth/verify-otp'),
          headers: _headers(),
          body: jsonEncode({'email': email, 'otp': otp}),
        ));
    final parsed = _parseResponse(response);
    return parsed['data'] as Map<String, dynamic>;
  }

  /// GET /auth/org-details?code=XXX
  /// Returns organization name + departments for faculty registration (legacy helper).
  static Future<Map<String, dynamic>> getOrgDetails(String code) async {
    return await orgLookup(code: code);
  }

  /// GET /auth/org-lookup?email=XXX&code=YYY
  /// Returns organization details + departments by email or code.
  static Future<Map<String, dynamic>> orgLookup({String? email, String? code}) async {
    final queryParams = <String>[];
    if (email != null && email.isNotEmpty) {
      queryParams.add('email=${Uri.encodeQueryComponent(email)}');
    }
    if (code != null && code.isNotEmpty) {
      queryParams.add('code=${Uri.encodeQueryComponent(code)}');
    }
    final url = '$_kBaseUrl/auth/org-lookup?${queryParams.join('&')}';
    final response = await _execute(() => http.get(
          Uri.parse(url),
          headers: _headers(),
        ));
    final parsed = _parseResponse(response);
    return parsed['data'] as Map<String, dynamic>;
  }

  /// POST /auth/register
  /// Faculty self-registration (pending admin approval).
  static Future<void> registerFaculty({
    required String fullName,
    required String email,
    required String password,
    String? organizationCode,
    String? departmentId,
  }) async {
    final devId = await SessionManager.getDeviceIdentifier();
    final model = await SessionManager.getDeviceModel();
    final platform = await SessionManager.getDevicePlatform();

    final body = <String, dynamic>{
      'full_name': fullName,
      'email': email,
      'password': password,
      'device_identifier': devId,
      'device_model': model,
      'platform': platform,
    };
    if (organizationCode != null && organizationCode.isNotEmpty) {
      body['organization_code'] = organizationCode;
    }
    if (departmentId != null && departmentId.isNotEmpty) {
      body['department_id'] = departmentId;
    }

    final response = await _execute(() => http.post(
          Uri.parse('$_kBaseUrl/auth/register'),
          headers: _headers(),
          body: jsonEncode(body),
        ));
    _parseResponse(response);
  }

  /// POST /auth/login
  /// Unified login — backend auto-detects admin vs faculty and binds devices.
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    String? otp,
  }) async {
    final devId = await SessionManager.getDeviceIdentifier();
    final model = await SessionManager.getDeviceModel();
    final platform = await SessionManager.getDevicePlatform();
    final osVer = await SessionManager.getDeviceOSVersion();
    final manuf = await SessionManager.getDeviceManufacturer();

    final body = <String, dynamic>{
      'email': email,
      'password': password,
      'device_identifier': devId,
      'device_model': model,
      'platform': platform,
      'os_version': osVer,
      'manufacturer': manuf,
    };
    if (otp != null && otp.isNotEmpty) {
      body['otp'] = otp;
    }

    final response = await _execute(() => http.post(
          Uri.parse('$_kBaseUrl/auth/login'),
          headers: _headers(),
          body: jsonEncode(body),
        ));
    final parsed = _parseResponse(response);
    return parsed['data'] as Map<String, dynamic>;
  }

  /// POST /auth/refresh
  /// Refreshes the access token using the stored refresh token.
  static Future<String?> refreshAccessToken() async {
    final refreshToken = SessionManager.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return null;

    try {
      final response = await _execute(() => http.post(
            Uri.parse('$_kBaseUrl/auth/refresh'),
            headers: _headers(),
            body: jsonEncode({'refresh_token': refreshToken}),
          ));
      final parsed = _parseResponse(response);
      return parsed['data']?['access_token'] as String?;
    } catch (_) {
      return null; // Silent failure — caller handles session expiry
    }
  }

  // -------------------------------------------------------------------------
  // Authenticated executor with automatic token refresh on 401
  // -------------------------------------------------------------------------
  static Future<http.Response> _executeWithAuthRetry(
      Future<http.Response> Function() requestFn) async {
    var response = await _execute(requestFn);
    
    if (response.statusCode == 401) {
      debugPrint('[ApiService] 401 Unauthorized detected. Attempting token refresh...');
      final newToken = await refreshAccessToken();
      if (newToken != null && newToken.isNotEmpty) {
        await SessionManager.saveAccessToken(newToken);
        debugPrint('[ApiService] Token refreshed. Retrying original request...');
        // Retry original request (will evaluate new access token dynamically)
        response = await _execute(requestFn);
      }
    }
    
    return response;
  }

  // =========================================================================
  // GENERIC AUTHENTICATED REQUESTS
  // =========================================================================

  /// Authenticated GET request.
  static Future<Map<String, dynamic>> get(String path) async {
    final response = await _executeWithAuthRetry(() => http.get(
          Uri.parse('$_kBaseUrl$path'),
          headers: _headers(requiresAuth: true),
        ));
    return _parseResponse(response);
  }

  /// Authenticated GET request that returns raw response body as String.
  /// Useful for non-JSON content (e.g. CSV exports).
  static Future<String> getRaw(String path) async {
    final response = await _executeWithAuthRetry(() => http.get(
          Uri.parse('$_kBaseUrl$path'),
          headers: _headers(requiresAuth: true),
        ));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return utf8.decode(response.bodyBytes);
    }
    // Parse error JSON if possible, otherwise throw standard status message
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final message = _extractErrorMessage(body, response.statusCode);
      final type = _classifyStatusCode(response.statusCode);
      throw ApiException(message: message, statusCode: response.statusCode, type: type);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException(
        message: _defaultMessageForStatus(response.statusCode),
        statusCode: response.statusCode,
        type: _classifyStatusCode(response.statusCode),
      );
    }
  }

  /// Authenticated POST request.
  static Future<Map<String, dynamic>> post(
      String path, Map<String, dynamic> body) async {
    final response = await _executeWithAuthRetry(() => http.post(
          Uri.parse('$_kBaseUrl$path'),
          headers: _headers(requiresAuth: true),
          body: jsonEncode(body),
        ));
    return _parseResponse(response);
  }

  /// Authenticated PUT request.
  static Future<Map<String, dynamic>> put(
      String path, Map<String, dynamic> body) async {
    final response = await _executeWithAuthRetry(() => http.put(
          Uri.parse('$_kBaseUrl$path'),
          headers: _headers(requiresAuth: true),
          body: jsonEncode(body),
        ));
    return _parseResponse(response);
  }

  /// Authenticated PATCH request.
  static Future<Map<String, dynamic>> patch(
      String path, Map<String, dynamic> body) async {
    final response = await _executeWithAuthRetry(() => http.patch(
          Uri.parse('$_kBaseUrl$path'),
          headers: _headers(requiresAuth: true),
          body: jsonEncode(body),
        ));
    return _parseResponse(response);
  }

  /// Authenticated DELETE request.
  static Future<Map<String, dynamic>> delete(String path) async {
    final response = await _executeWithAuthRetry(() => http.delete(
          Uri.parse('$_kBaseUrl$path'),
          headers: _headers(requiresAuth: true),
        ));
    return _parseResponse(response);
  }

  // =========================================================================
  // GEOFENCE ENDPOINTS
  // =========================================================================

  /// GET /geofence/search?query=xxx
  static Future<List<Map<String, dynamic>>> searchLocation(String query) async {
    final response = await get('/geofence/search?query=${Uri.encodeQueryComponent(query)}');
    final data = response['data'] as List;
    return List<Map<String, dynamic>>.from(data.map((item) => Map<String, dynamic>.from(item as Map)));
  }

  // =========================================================================
  // SETTINGS & DEPARTMENTS ENDPOINTS
  // =========================================================================

  /// GET /settings/policy
  static Future<Map<String, dynamic>> fetchPolicy({String? departmentId}) async {
    var path = '/settings/policy';
    if (departmentId != null) {
      path += '?department_id=$departmentId';
    }
    final response = await get(path);
    return response['data'] as Map<String, dynamic>;
  }

  /// PUT /settings/policy
  static Future<Map<String, dynamic>> updatePolicy(Map<String, dynamic> body) async {
    final response = await put('/settings/policy', body);
    return response['data'] as Map<String, dynamic>;
  }

  /// GET /settings/settings
  static Future<Map<String, dynamic>> fetchSettings() async {
    final response = await get('/settings/settings');
    return response['data'] as Map<String, dynamic>;
  }

  /// PUT /settings/settings
  static Future<Map<String, dynamic>> updateSettings(Map<String, dynamic> body) async {
    final response = await put('/settings/settings', body);
    return response['data'] as Map<String, dynamic>;
  }

  /// GET /settings/departments
  static Future<List<Map<String, dynamic>>> fetchDepartments() async {
    final response = await get('/settings/departments');
    final data = response['data'] as List;
    return List<Map<String, dynamic>>.from(data.map((item) => Map<String, dynamic>.from(item as Map)));
  }

  /// POST /settings/departments
  static Future<Map<String, dynamic>> createDepartment(String name, String description) async {
    final response = await post('/settings/departments', {
      'name': name,
      'description': description,
      'is_active': true,
    });
    return response['data'] as Map<String, dynamic>;
  }

  /// DELETE /settings/departments/{id}
  static Future<void> deleteDepartment(String id) async {
    await delete('/settings/departments/$id');
  }

  // =========================================================================
  // CONNECTIVITY CHECK
  // =========================================================================

  /// Pings the backend health endpoint.
  /// Returns true if the backend is reachable.
  static Future<bool> isBackendReachable() async {
    try {
      final response = await http
          .get(Uri.parse('$kBaseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // =========================================================================
  // FACULTY ENDPOINTS
  // =========================================================================

  /// GET /faculty/profile
  static Future<Map<String, dynamic>> fetchFacultyProfile() async {
    final response = await get('/faculty/profile');
    return response['data'] as Map<String, dynamic>;
  }

  /// PUT /faculty/profile
  static Future<Map<String, dynamic>> updateFacultyProfile(Map<String, dynamic> data) async {
    final response = await put('/faculty/profile', data);
    return response['data'] as Map<String, dynamic>;
  }

  /// GET /faculty/dashboard-summary
  static Future<Map<String, dynamic>> fetchDashboardSummary() async {
    final response = await get('/faculty/dashboard-summary');
    return response['data'] as Map<String, dynamic>;
  }

  /// POST /faculty/reason-requests
  static Future<void> submitReasonRequest({
    required String reasonType,
    String? notes,
    double? latitude,
    double? longitude,
  }) async {
    await post('/faculty/reason-requests', {
      'reason_type': reasonType,
      'notes': notes,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  /// GET /faculty/notifications
  static Future<List<Map<String, dynamic>>> fetchNotifications() async {
    final response = await get('/faculty/notifications');
    final data = response['data'] as List;
    return List<Map<String, dynamic>>.from(data.map((item) => Map<String, dynamic>.from(item as Map)));
  }

  /// POST /faculty/notifications/{id}/read
  static Future<void> markNotificationAsRead(String id) async {
    await post('/faculty/notifications/$id/read', {});
  }

  /// POST /faculty/notifications/mark-all-read
  static Future<void> markAllNotificationsAsRead() async {
    await post('/faculty/notifications/mark-all-read', {});
  }

  /// GET /faculty/attendance-history
  static Future<Map<String, dynamic>> fetchAttendanceHistory({
    required String rangeType,
    String? startDate,
    String? endDate,
    int page = 1,
  }) async {
    var path = '/faculty/attendance-history?range_type=$rangeType&page=$page';
    if (startDate != null && startDate.isNotEmpty) {
      path += '&start_date=$startDate';
    }
    if (endDate != null && endDate.isNotEmpty) {
      path += '&end_date=$endDate';
    }
    final response = await get(path);
    return response['data'] as Map<String, dynamic>;
  }

  /// GET /faculty/devices
  static Future<List<Map<String, dynamic>>> fetchDeviceHistory() async {
    final response = await get('/faculty/devices');
    final data = response['data'] as List;
    return List<Map<String, dynamic>>.from(data.map((item) => Map<String, dynamic>.from(item as Map)));
  }

  /// POST /attendance/check-in
  static Future<Map<String, dynamic>> reportLocationEvent({
    required double latitude,
    required double longitude,
    required String eventType,
  }) async {
    final devId = await SessionManager.getDeviceIdentifier();
    final body = {
      'latitude': latitude,
      'longitude': longitude,
      'event_type': eventType,
      'device_identifier': devId,
      'event_time': DateTime.now().toUtc().toIso8601String(),
    };
    final response = await post('/attendance/check-in', body);
    return response['data'] as Map<String, dynamic>;
  }

  // =========================================================================
  // ADMIN WALKTHROUGH ENDPOINTS
  // =========================================================================

  /// POST /admin/walkthrough/complete
  static Future<void> markWalkthroughCompleted() async {
    await post('/admin/walkthrough/complete', {});
  }

  // =========================================================================
  // FORGOT PASSWORD FLOW
  // =========================================================================

  /// POST /auth/forgot-password
  static Future<void> initiateForgotPassword(String email) async {
    await post('/auth/forgot-password', {'email': email});
  }

  /// POST /auth/verify-reset-otp
  static Future<void> verifyResetOtp(String email, String otp) async {
    await post('/auth/verify-reset-otp', {'email': email, 'otp': otp});
  }

  /// POST /auth/reset-password
  static Future<void> resetPassword(String email, String otp, String newPassword) async {
    await post('/auth/reset-password', {
      'email': email,
      'otp': otp,
      'new_password': newPassword,
    });
  }

  /// POST /admin/attendance/override
  static Future<Map<String, dynamic>> overrideAttendance({
    required String facultyId,
    required String attendanceDate,
    required String overrideStatus,
    required String overrideReason,
    required String overrideRemarks,
    String? manualCheckInTime,
    String? manualCheckOutTime,
    double? effectiveWorkingHours,
    bool forceReplace = false,
  }) async {
    final response = await post('/admin/attendance/override', {
      'faculty_id': facultyId,
      'attendance_date': attendanceDate,
      'override_status': overrideStatus,
      'override_reason': overrideReason,
      'override_remarks': overrideRemarks,
      if (manualCheckInTime != null) 'manual_check_in_time': manualCheckInTime,
      if (manualCheckOutTime != null) 'manual_check_out_time': manualCheckOutTime,
      if (effectiveWorkingHours != null) 'effective_working_hours': effectiveWorkingHours,
      'force_replace': forceReplace,
    });
    return response;
  }

  /// POST /faculty/notifications/{notification_id}/acknowledge
  static Future<Map<String, dynamic>> acknowledgeNotification(String notificationId) async {
    final response = await post('/faculty/notifications/$notificationId/acknowledge', {});
    return response;
  }
}


// ---------------------------------------------------------------------------
// ApiException — structured exception for all API failures
// ---------------------------------------------------------------------------

enum ApiErrorType {
  /// 4xx client errors (bad request, validation, conflict, etc.)
  client,
  /// 401 Unauthorized
  unauthorized,
  /// 403 Forbidden
  forbidden,
  /// 404 Not Found
  notFound,
  /// 409 Conflict
  conflict,
  /// 422 Validation
  validation,
  /// 5xx Server errors
  server,
  /// Network/connection errors (backend not reachable, no internet)
  network,
  /// Request timed out
  timeout,
  /// Response body could not be parsed
  parseError,
  /// Catch-all unknown
  unknown,
}

/// Thrown by [ApiService] on any non-2xx response or network failure.
class ApiException implements Exception {
  final String message;
  final int statusCode;
  final ApiErrorType type;

  const ApiException({
    required this.message,
    required this.statusCode,
    required this.type,
  });

  bool get isNetworkError =>
      type == ApiErrorType.network || type == ApiErrorType.timeout;

  bool get isAuthError =>
      type == ApiErrorType.unauthorized || type == ApiErrorType.forbidden;

  bool get isServerError => type == ApiErrorType.server;

  bool get isClientError =>
      type == ApiErrorType.client ||
      type == ApiErrorType.validation ||
      type == ApiErrorType.conflict ||
      type == ApiErrorType.notFound;

  @override
  String toString() => 'ApiException[$statusCode/${type.name}]: $message';
}
