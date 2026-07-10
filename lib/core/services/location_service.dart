import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../api_service.dart';
import '../session_manager.dart';
import 'notification_service.dart';
import 'notification_persistence_service.dart';

class LocationService {
  LocationService._();

  static StreamSubscription<Position>? _positionStreamSubscription;
  static Position? lastPosition;
  static bool isTracking = false;
  static bool? isInsideGeofence;
  static String? statusMessage;
  static bool automaticAttendanceFailed = false;
  static bool isCheckingIn = false;
  static bool isCheckingOut = false;

  // Cached state from the dashboard summary response
  static String? checkInTime;
  static String? checkOutTime;
  static DateTime? _exitStartTime;
  static bool _sentReminder1 = false;
  static bool _sentReminder2 = false;
  static bool _sentReminder3 = false;
  static bool _sentEvaluationAlert = false;
  static String? serverCampusStatus;
  static DateTime? lastEventTime;

  // Real-time optimization state
  static bool hasEvaluatedInitialLocation = false;
  static String? localCampusStatus;
  static String? _targetState;
  static int _consecutiveTicks = 0;
  static LocationAccuracy _currentAccuracy = LocationAccuracy.high;
  static double _currentDistanceFilter = 2.0;
  static int _currentIntervalSeconds = 4;

  static bool get shouldIgnoreServerStatus {
    if (lastEventTime == null) return false;
    return DateTime.now().difference(lastEventTime!) < const Duration(seconds: 15);
  }

  static final StreamController<String?> statusController = StreamController<String?>.broadcast();
  static final StreamController<bool> attendanceFailedController = StreamController<bool>.broadcast();
  static final StreamController<void> eventLoggedController = StreamController<void>.broadcast();
  static final StreamController<String> geofenceTransitionController = StreamController<String>.broadcast();

  static LocationSettings _buildLocationSettings(LocationAccuracy accuracy, double distanceFilter, int intervalSeconds) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter.round(),
        forceLocationManager: false,
        intervalDuration: Duration(seconds: intervalSeconds),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "Premises is monitoring campus presence in the background.",
          notificationTitle: "Location Tracking Active",
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      return AppleSettings(
        accuracy: accuracy,
        activityType: ActivityType.fitness,
        distanceFilter: distanceFilter.round(),
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      return LocationSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter.round(),
      );
    }
  }

  static void _restartPositionStream() {
    if (_positionStreamSubscription != null) {
      _positionStreamSubscription!.cancel();
      _positionStreamSubscription = null;
    }
    
    final locationSettings = _buildLocationSettings(_currentAccuracy, _currentDistanceFilter, _currentIntervalSeconds);
    
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) async {
        await _handlePositionUpdate(position);
      },
      onError: (e) {
        debugPrint('[LocationService] Stream error: $e');
      },
    );
  }

  static void _adjustSettings(double distanceToBoundary) {
    LocationAccuracy targetAccuracy;
    double targetDistanceFilter;
    int targetIntervalSeconds;

    if (distanceToBoundary > 500) {
      // Far away: Eco Mode
      targetAccuracy = LocationAccuracy.medium;
      targetDistanceFilter = 25.0;
      targetIntervalSeconds = 30;
    } else {
      // Close/Inside: Proximity Mode
      targetAccuracy = LocationAccuracy.high;
      targetDistanceFilter = 2.0;
      targetIntervalSeconds = 4;
    }

    if (targetAccuracy != _currentAccuracy ||
        targetDistanceFilter != _currentDistanceFilter ||
        targetIntervalSeconds != _currentIntervalSeconds) {
      
      _currentAccuracy = targetAccuracy;
      _currentDistanceFilter = targetDistanceFilter;
      _currentIntervalSeconds = targetIntervalSeconds;
      
      debugPrint('[LocationService] Adjusting GPS -> Accuracy: $targetAccuracy, Filter: ${targetDistanceFilter}m, Interval: ${targetIntervalSeconds}s');
      _restartPositionStream();
    }
  }

  static Future<void> initialize() async {
    if (isTracking) return;

    debugPrint('[LocationService] Initializing real-time tracking...');

    bool serviceEnabled;
    LocationPermission permission;

    // 1. Checking GPS Service
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      statusMessage = 'GPS is disabled. Please enable location services.';
      statusController.add(statusMessage);
      debugPrint('[LocationService] GPS service is disabled.');
      return;
    }

    // 2. Checking Permission
    permission = await Geolocator.checkPermission();
    debugPrint('[LocationService] Current permission status: $permission');

    if (permission == LocationPermission.denied) {
      statusMessage = 'Requesting location permissions...';
      statusController.add(statusMessage);
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        statusMessage = 'Location permission denied. Please allow permissions to track attendance.';
        statusController.add(statusMessage);
        debugPrint('[LocationService] Permission denied by user.');
        return;
      }
    }

    if (permission == LocationPermission.whileInUse) {
      statusMessage = 'Requesting background location...';
      statusController.add(statusMessage);
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      statusMessage = 'Location permissions are permanently denied. Please enable them in system settings.';
      statusController.add(statusMessage);
      debugPrint('[LocationService] Permission permanently denied.');
      return;
    }

    statusMessage = 'Getting current location...';
    statusController.add(statusMessage);
    isTracking = true;

    // Start with Proximity settings
    _currentAccuracy = LocationAccuracy.high;
    _currentDistanceFilter = 2.0;
    _currentIntervalSeconds = 4;

    // 3. Get initial position
    try {
      final initialPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      debugPrint('[LocationService] Initial position: ${initialPosition.latitude}, ${initialPosition.longitude}');
      await _handlePositionUpdate(initialPosition);
    } catch (e) {
      debugPrint('[LocationService] Failed to get initial position: $e');
    }

    // 4. Start real-time stream
    _restartPositionStream();
  }

  static void stop() {
    debugPrint('[LocationService] Stopping tracking.');
    if (_positionStreamSubscription != null) {
      _positionStreamSubscription!.cancel();
      _positionStreamSubscription = null;
    }
    isTracking = false;
    isInsideGeofence = null;
    hasEvaluatedInitialLocation = false;
  }

  static Future<void> _handlePositionUpdate(Position position, {bool forceDirectUpdate = false}) async {
    lastPosition = position;
    final double? gfLat = SessionManager.geofenceLatitude;

    if (gfLat == null) {
      debugPrint('[LocationService] Geofence configuration missing. Waiting for dashboard sync...');
      statusMessage = 'Waiting for geofence configuration...';
      statusController.add(statusMessage);
      isInsideGeofence = null;
      return;
    }

    final eval = evaluateGeofence(position.latitude, position.longitude);
    final bool currentlyInside = eval.isInside;
    final double distance = eval.distance;

    final String newState = currentlyInside ? 'INSIDE' : 'OUTSIDE';
    if (forceDirectUpdate || isInsideGeofence == null) {
      debugPrint('[LocationService] FORCED DIRECT/INITIAL Update: transitioning immediately to $newState (force=$forceDirectUpdate, isInsideNull=${isInsideGeofence == null})');
      localCampusStatus = newState;
      _targetState = newState;
      _consecutiveTicks = 2; // confirmed
      isInsideGeofence = (localCampusStatus == 'INSIDE');
      geofenceTransitionController.add(localCampusStatus!);
    } else {
      if (localCampusStatus == null) {
        localCampusStatus = newState;
        _targetState = newState;
        _consecutiveTicks = 2;
      } else {
        if (newState != _targetState) {
          _targetState = newState;
          _consecutiveTicks = 1;
        } else {
          _consecutiveTicks++;
        }
      }

      if (_consecutiveTicks >= 2 && newState != localCampusStatus) {
        debugPrint('[LocationService] CONFIRMED Transition: $localCampusStatus -> $newState');
        localCampusStatus = newState;
        geofenceTransitionController.add(localCampusStatus!);
      }
      
      isInsideGeofence = (localCampusStatus == 'INSIDE');
    }

    // Adjust settings dynamically
    _adjustSettings(distance);

    debugPrint('[LocationService] Update -> Lat: ${position.latitude.toStringAsFixed(6)}, Lng: ${position.longitude.toStringAsFixed(6)}, Distance: ${distance.toStringAsFixed(1)}m, Debounced Inside: $isInsideGeofence (Raw: $currentlyInside)');

    if (isInsideGeofence == true) {
      _exitStartTime = null;
      _sentReminder1 = false;
      _sentReminder2 = false;
      _sentReminder3 = false;
      _sentEvaluationAlert = false;
      statusMessage = 'Inside Campus (Dist: ${distance.toStringAsFixed(1)}m)';
      statusController.add(statusMessage);

      final bool hasCheckedIn = checkInTime != null;
      final bool hasCheckedOut = checkOutTime != null;

      if (!hasCheckedIn && !isCheckingIn) {
        isCheckingIn = true;
        debugPrint('[LocationService] Boundary ENTER detected. Registering check-in...');
        
        try {
          await ApiService.reportLocationEvent(
            latitude: position.latitude,
            longitude: position.longitude,
            eventType: 'ENTER_CAMPUS',
          );
          
          serverCampusStatus = 'INSIDE';
          lastEventTime = DateTime.now();
          automaticAttendanceFailed = false;
          attendanceFailedController.add(false);
          statusMessage = 'Attendance registered successfully.';
          statusController.add(statusMessage);

          NotificationService.showNotification(
            id: 1,
            title: 'You are in Premises',
            body: 'Your attendance has been marked successfully.',
          );
          debugPrint('[LocationService] Automatic check-in success.');
          eventLoggedController.add(null);
        } catch (e) {
          debugPrint('[LocationService] Automatic check-in failed: $e');
          automaticAttendanceFailed = true;
          attendanceFailedController.add(true);
          statusMessage = 'Check-in failed. Please register manually.';
          statusController.add(statusMessage);
          
          NotificationService.showNotification(
            id: 2,
            title: 'Attendance Error',
            body: 'Automatic check-in failed. Please open the app to register manually.',
          );
        } finally {
          isCheckingIn = false;
        }
      } else if (hasCheckedIn && !hasCheckedOut && !isCheckingIn && serverCampusStatus == 'OUTSIDE') {
        isCheckingIn = true;
        debugPrint('[LocationService] Boundary RETURN detected. Registering return...');
        try {
          await ApiService.reportLocationEvent(
            latitude: position.latitude,
            longitude: position.longitude,
            eventType: 'RETURN_CAMPUS',
          );
          
          serverCampusStatus = 'INSIDE';
          lastEventTime = DateTime.now();
          automaticAttendanceFailed = false;
          attendanceFailedController.add(false);
          statusMessage = 'Returned to Premises. Tracking active.';
          statusController.add(statusMessage);

          NotificationService.showNotification(
            id: 10,
            title: 'Returned to Premises',
            body: 'Your attendance tracking has resumed.',
          );
          debugPrint('[LocationService] Automatic return success.');
          eventLoggedController.add(null);
        } catch (e) {
          debugPrint('[LocationService] Automatic return failed: $e');
        } finally {
          isCheckingIn = false;
        }
      }
    } else {
      // User is outside geofence
      statusMessage = 'Outside Campus (Dist: ${distance.toStringAsFixed(1)}m)';
      statusController.add(statusMessage);

      final bool hasCheckedIn = checkInTime != null;
      final bool hasCheckedOut = checkOutTime != null;
      
      if (hasCheckedIn && !hasCheckedOut) {
        // 1. Immediately log exit and show initial notification (only once!)
        if (serverCampusStatus != 'OUTSIDE' && !isCheckingOut) {
          isCheckingOut = true;
          debugPrint('[LocationService] Boundary EXIT detected. Registering exit event...');
          
          try {
            await ApiService.reportLocationEvent(
              latitude: position.latitude,
              longitude: position.longitude,
              eventType: 'EXIT_CAMPUS',
            );
            
            serverCampusStatus = 'OUTSIDE';
            lastEventTime = DateTime.now();
            statusMessage = 'Outside Campus (Exit logged).';
            statusController.add(statusMessage);
            _exitStartTime = DateTime.now();

            final limit = SessionManager.evaluationMinutes ?? SessionManager.allowedOutsideMinutes ?? 25;
            NotificationService.showNotification(
              id: 3,
              title: 'Left Premises',
              body: 'You have left Premises. Please return within $limit minutes to avoid absence.',
            );
            debugPrint('[LocationService] Automatic exit log success.');
            eventLoggedController.add(null);
          } catch (e) {
            debugPrint('[LocationService] Automatic exit log failed: $e');
          } finally {
            isCheckingOut = false;
          }
        }

        // 2. Track duration outside and send notifications based on delays
        if (_exitStartTime != null) {
          final minutesOutside = DateTime.now().difference(_exitStartTime!).inMinutes;
          
          final r1 = SessionManager.reminder1Minutes ?? 0;
          final r2 = SessionManager.reminder2Minutes ?? 0;
          final r3 = SessionManager.reminder3Minutes ?? 0;
          final eval = SessionManager.evaluationMinutes ?? SessionManager.allowedOutsideMinutes ?? 25;

          // Warning 1
          if (r1 > 0 && minutesOutside >= r1 && !_sentReminder1) {
            _sentReminder1 = true;
            NotificationService.showNotification(
              id: 91,
              title: 'Campus Boundary Warning 1',
              body: 'You have been outside for $minutesOutside minute(s). Please return to campus.',
            );
          }

          // Warning 2
          if (r2 > 0 && minutesOutside >= r2 && !_sentReminder2) {
            _sentReminder2 = true;
            NotificationService.showNotification(
              id: 92,
              title: 'Campus Boundary Warning 2',
              body: 'You have been outside for $minutesOutside minute(s). Please return to campus.',
            );
          }

          // Final Warning 3
          if (r3 > 0 && minutesOutside >= r3 && !_sentReminder3) {
            _sentReminder3 = true;
            NotificationService.showNotification(
              id: 93,
              title: 'Campus Boundary Final Warning',
              body: 'Final Warning: You have been outside for $minutesOutside minute(s). Return immediately to avoid absence.',
            );
          }

          // Evaluation Trigger
          if (minutesOutside >= eval && !_sentEvaluationAlert) {
            _sentEvaluationAlert = true;
            NotificationService.showNotification(
              id: 94,
              title: 'Campus Absence Evaluated',
              body: 'Absence Limit Reached: You have been outside the campus boundary for $eval minutes.',
            );
          }
        }
      }
    }
  }

  static Future<bool> forceRegisterAttendance() async {
    debugPrint('[LocationService] Manual registration triggered.');
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final double? gfLat = SessionManager.geofenceLatitude;

      if (gfLat == null) {
        throw Exception('Geofence configuration is missing.');
      }

      final eval = evaluateGeofence(position.latitude, position.longitude);

      if (!eval.isInside) {
        throw Exception('You must be inside the campus boundaries to register attendance. Current distance: ${eval.distance.toStringAsFixed(1)}m');
      }

      isCheckingIn = true;
      try {
        await ApiService.reportLocationEvent(
          latitude: position.latitude,
          longitude: position.longitude,
          eventType: 'ENTER_CAMPUS',
        );
        automaticAttendanceFailed = false;
        lastEventTime = DateTime.now();
        attendanceFailedController.add(false);
        isInsideGeofence = true;
        statusMessage = 'Attendance registered successfully.';
        statusController.add(statusMessage);
        
        NotificationService.showNotification(
          id: 4,
          title: 'Attendance Registered',
          body: 'Your attendance has been logged successfully.',
        );
        debugPrint('[LocationService] Force check-in success.');
        return true;
      } finally {
        isCheckingIn = false;
      }
    } catch (e) {
      debugPrint('[LocationService] Force check-in failed: $e');
      rethrow;
    }
  }

  static Future<void> checkCurrentLocation({bool geofenceChanged = false}) async {
    debugPrint('[LocationService] Performing manual/immediate location verification (geofenceChanged: $geofenceChanged)...');
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      await _handlePositionUpdate(position, forceDirectUpdate: geofenceChanged);
    } catch (e) {
      debugPrint('[LocationService] Failed to check current location: $e');
    }
  }

  static Future<void> forceReevaluate({bool geofenceChanged = false}) async {
    debugPrint('[LocationService] Forcing immediate GPS location evaluation (geofenceChanged: $geofenceChanged)...');
    await checkCurrentLocation(geofenceChanged: geofenceChanged);
  }

  static Future<void> _checkCompletionNotification(Map<String, dynamic> data) async {
    final checkIn = data['check_in_time'];
    final campusStatus = data['campus_status'];

    if (checkIn == null) {
      return;
    }

    final todayStr = DateTime.now().toIso8601String().split('T').first;
    final alreadyShown = await NotificationPersistenceService.isShown('completion', date: todayStr);

    if (campusStatus == 'COMPLETED' && !alreadyShown) {
      await NotificationPersistenceService.markAsShown('completion', date: todayStr);
      NotificationService.showNotification(
        id: 100,
        title: 'Attendance Registered',
        body: "Your today's attendance is officially registered.",
      );
    }
  }

  static Future<void> syncWithServer() async {
    try {
      final data = await ApiService.fetchDashboardSummary();
      checkInTime = data['check_in_time'];
      checkOutTime = data['check_out_time'];
      serverCampusStatus = data['campus_status'];
      
      if (localCampusStatus == null && serverCampusStatus != null && serverCampusStatus != 'UNKNOWN') {
        localCampusStatus = serverCampusStatus;
        _targetState = serverCampusStatus;
        _consecutiveTicks = 2;
      }
      // Cache geofence
      final lat = data['geofence_latitude'] != null ? (data['geofence_latitude'] as num).toDouble() : 0.0;
      final lng = data['geofence_longitude'] != null ? (data['geofence_longitude'] as num).toDouble() : 0.0;
      final rad = data['geofence_radius'] != null ? (data['geofence_radius'] as num).toDouble() : 0.0;
      final type = data['geofence_type'] as String? ?? 'circle';
      final vertices = data['geofence_vertices'];
      final String? verticesJson = vertices != null ? json.encode(vertices) : null;
      final allowedOutside = data['allowed_outside_minutes'] as int? ?? 25;
      final rem1 = data['reminder_1_minutes'] as int? ?? 0;
      final rem2 = data['reminder_2_minutes'] as int? ?? 0;
      final rem3 = data['reminder_3_minutes'] as int? ?? 0;
      final eval = data['evaluation_minutes'] as int? ?? 15;
      final gfId = data['geofence_id'] as String?;
      final gfUpdatedAt = data['geofence_updated_at'] as String?;

      final bool geofenceChanged = (SessionManager.geofenceLatitude != lat ||
          SessionManager.geofenceLongitude != lng ||
          SessionManager.geofenceRadius != rad ||
          SessionManager.geofenceType != type ||
          SessionManager.geofenceVerticesJson != verticesJson ||
          SessionManager.geofenceId != gfId ||
          SessionManager.geofenceUpdatedAt != gfUpdatedAt);

      final bool shouldForce = geofenceChanged || !hasEvaluatedInitialLocation;
      if (shouldForce) {
        hasEvaluatedInitialLocation = true;
      }
      
      SessionManager.cacheGeofence(
        lat, lng, rad, type, verticesJson, allowedOutside, rem1, rem2, rem3, eval, gfId, gfUpdatedAt
      );

      // Force location service to re-evaluate with the newly cached geofence configuration
      await forceReevaluate(geofenceChanged: shouldForce);

      // Check for completion notification
      _checkCompletionNotification(data);
    } catch (e) {
      debugPrint('[LocationService] Failed to sync with server: $e');
    }
  }

  // ─── Geofence Evaluation Core ──────────────────────────────────────────────

  static bool _isPointInBoundingBox(double lat, double lng, List<Map<String, double>> vertices) {
    if (vertices.isEmpty) return false;
    double minLat = vertices[0]['lat']!;
    double maxLat = vertices[0]['lat']!;
    double minLng = vertices[0]['lng']!;
    double maxLng = vertices[0]['lng']!;
    
    for (int i = 1; i < vertices.length; i++) {
      final v = vertices[i];
      final vLat = v['lat']!;
      final vLng = v['lng']!;
      if (vLat < minLat) minLat = vLat;
      if (vLat > maxLat) maxLat = vLat;
      if (vLng < minLng) minLng = vLng;
      if (vLng > maxLng) maxLng = vLng;
    }
    
    // Add small buffer (~10m) to bounds for high accuracy threshold transitions
    const double buffer = 0.0001;
    return lat >= (minLat - buffer) && lat <= (maxLat + buffer) &&
           lng >= (minLng - buffer) && lng <= (maxLng + buffer);
  }

  static GeofenceEvaluation evaluateGeofence(double lat, double lng) {
    final double? gfLat = SessionManager.geofenceLatitude;
    final double? gfLng = SessionManager.geofenceLongitude;
    final double? gfRad = SessionManager.geofenceRadius;
    final String type = SessionManager.geofenceType ?? 'circle';
    final String? verticesJson = SessionManager.geofenceVerticesJson;

    debugPrint('[GEOFENCE EVAL] type=$type, gfLat=$gfLat, gfLng=$gfLng, gfRad=$gfRad');
    debugPrint('[GEOFENCE EVAL] verticesJson is ${verticesJson == null ? "NULL" : "present (${verticesJson.length} chars)"}');
    debugPrint('[GEOFENCE EVAL] Faculty position: ($lat, $lng)');

    if (gfLat == null || gfLng == null || gfRad == null) {
      debugPrint('[GEOFENCE EVAL] BAIL: null lat/lng/rad');
      return GeofenceEvaluation(false, double.infinity);
    }

    if (type == 'polygon' && verticesJson != null) {
      try {
        final List<dynamic> decoded = json.decode(verticesJson);
        debugPrint('[GEOFENCE EVAL] Decoded ${decoded.length} vertices from JSON');
        final List<Map<String, double>> vertices = decoded.map((item) {
          final Map<String, dynamic> m = item as Map<String, dynamic>;
          return {
            'lat': (m['latitude'] as num).toDouble(),
            'lng': (m['longitude'] as num).toDouble(),
          };
        }).toList();

        debugPrint('[GEOFENCE EVAL] Parsed ${vertices.length} polygon vertices:');
        for (int i = 0; i < vertices.length; i++) {
          debugPrint('[GEOFENCE EVAL]   vertex[$i] = (${vertices[i]['lat']}, ${vertices[i]['lng']})');
        }

        if (vertices.length >= 3) {
          // Bounding box pre-check optimization
          final bool insideBB = _isPointInBoundingBox(lat, lng, vertices);
          final bool isInside = insideBB && _checkPointInPolygon(lat, lng, vertices);
          final double distance = isInside ? 0.0 : _distanceToPolygonMeters(lat, lng, vertices);
          debugPrint('[GEOFENCE EVAL] Polygon result: inside=$isInside (insideBB=$insideBB), distance=$distance');
          return GeofenceEvaluation(isInside, distance);
        } else {
          debugPrint('[GEOFENCE EVAL] WARN: fewer than 3 vertices, falling through to circle');
        }
      } catch (e) {
        debugPrint('[LocationService] Error evaluating polygon geofence: $e');
      }
    } else {
      debugPrint('[GEOFENCE EVAL] Not taking polygon path: type=$type, verticesJson=${verticesJson == null ? "null" : "present"}');
    }

    // Default to circle distance check
    final double distance = Geolocator.distanceBetween(lat, lng, gfLat, gfLng);
    debugPrint('[GEOFENCE EVAL] Circle fallback: distance=$distance, radius=$gfRad, inside=${distance <= gfRad}');
    return GeofenceEvaluation(distance <= gfRad, distance);
  }

  static bool _isOnVertexOrEdge(double lat, double lng, List<Map<String, double>> vertices, {double epsilon = 1e-9}) {
    // Check vertices
    for (final v in vertices) {
      if ((v['lat']! - lat).abs() < epsilon && (v['lng']! - lng).abs() < epsilon) {
        return true;
      }
    }
    // Check edges
    int n = vertices.length;
    for (int i = 0; i < n; i++) {
      final p1 = vertices[i];
      final p2 = vertices[(i + 1) % n];
      
      final p1Lat = p1['lat']!;
      final p1Lng = p1['lng']!;
      final p2Lat = p2['lat']!;
      final p2Lng = p2['lng']!;
      
      final crossProduct = (lat - p1Lat) * (p2Lng - p1Lng) - (lng - p1Lng) * (p2Lat - p1Lat);
      if (crossProduct.abs() < epsilon) {
        final dotProduct = (lat - p1Lat) * (p2Lat - p1Lat) + (lng - p1Lng) * (p2Lng - p1Lng);
        if (dotProduct >= 0) {
          final abLenSq = math.pow(p2Lat - p1Lat, 2) + math.pow(p2Lng - p1Lng, 2);
          if (dotProduct <= abLenSq) {
            return true;
          }
        }
      }
    }
    return false;
  }

  static bool _checkPointInPolygon(double lat, double lng, List<Map<String, double>> vertices) {
    int numVertices = vertices.length;
    if (numVertices < 3) return false;
    
    // Treat points exactly on vertices or edges as inside
    if (_isOnVertexOrEdge(lat, lng, vertices)) {
      return true;
    }
    
    bool inside = false;
    double p1x = vertices[0]['lat']!;
    double p1y = vertices[0]['lng']!;
    
    for (int i = 1; i <= numVertices; i++) {
      double p2x = vertices[i % numVertices]['lat']!;
      double p2y = vertices[i % numVertices]['lng']!;
      
      if (lng > math.min(p1y, p2y)) {
        if (lng <= math.max(p1y, p2y)) {
          if (lat <= math.max(p1x, p2x)) {
            double xinters = 0.0;
            if (p1y != p2y) {
              xinters = (lng - p1y) * (p2x - p1x) / (p2y - p1y) + p1x;
            }
            if (p1x == p2x || lat <= xinters) {
              inside = !inside;
            }
          }
        }
      }
      p1x = p2x;
      p1y = p2y;
    }
    return inside;
  }

  static double _distanceToSegmentMeters(double latP, double lngP, double latA, double lngA, double latB, double lngB) {
    const double R = 6371000.0;
    final double latCenterRad = latP * math.pi / 180.0;
    final double cosLat = math.cos(latCenterRad);
    
    final double ax = (lngA - lngP) * math.pi / 180.0 * R * cosLat;
    final double ay = (latA - latP) * math.pi / 180.0 * R;
    final double bx = (lngB - lngP) * math.pi / 180.0 * R * cosLat;
    final double by = (latB - latP) * math.pi / 180.0 * R;
    
    final double dx = bx - ax;
    final double dy = by - ay;
    final double lenSq = dx * dx + dy * dy;
    
    if (lenSq == 0.0) {
      return math.sqrt(ax * ax + ay * ay);
    }
    
    double t = ((0.0 - ax) * dx + (0.0 - ay) * dy) / lenSq;
    t = math.max(0.0, math.min(1.0, t));
    
    final double cx = ax + t * dx;
    final double cy = ay + t * dy;
    return math.sqrt(cx * cx + cy * cy);
  }

  static double _distanceToPolygonMeters(double latP, double lngP, List<Map<String, double>> vertices) {
    int n = vertices.length;
    if (n == 0) return double.infinity;
    double minD = double.infinity;
    for (int i = 0; i < n; i++) {
      final double latA = vertices[i]['lat']!;
      final double lngA = vertices[i]['lng']!;
      final double latB = vertices[(i + 1) % n]['lat']!;
      final double lngB = vertices[(i + 1) % n]['lng']!;
      final double d = _distanceToSegmentMeters(latP, lngP, latA, lngA, latB, lngB);
      if (d < minD) {
        minD = d;
      }
    }
    return minD;
  }
}

class GeofenceEvaluation {
  final bool isInside;
  final double distance;
  GeofenceEvaluation(this.isInside, this.distance);
}

