import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import '../api_service.dart';
import '../session_manager.dart';
import 'notification_service.dart';

class LocationService {
  LocationService._();

  static StreamSubscription<Position>? _positionStreamSubscription;
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
  static bool _sentOutsideWarning = false;
  static bool _sentReminder1 = false;
  static bool _sentReminder2 = false;
  static bool _sentReminder3 = false;
  static bool _sentEvaluationAlert = false;
  static String? serverCampusStatus;

  static final StreamController<String?> statusController = StreamController<String?>.broadcast();
  static final StreamController<bool> attendanceFailedController = StreamController<bool>.broadcast();

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

    late final LocationSettings locationSettings;
    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
        forceLocationManager: false,
        intervalDuration: const Duration(seconds: 10),
        // This is key for background updates on Android
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "Premises is monitoring campus presence in the background.",
          notificationTitle: "Location Tracking Active",
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 5,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );
    }

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
    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings)
        .listen((Position position) {
      _handlePositionUpdate(position);
    }, onError: (error) {
      debugPrint('[LocationService] Stream error: $error');
      statusMessage = 'Location service unavailable.';
      statusController.add(statusMessage);
    });

    // 5. Start periodic background synchronization (every 30 seconds)
    Timer.periodic(const Duration(seconds: 30), (timer) async {
      if (isTracking) {
        await syncWithServer();
        await checkCurrentLocation();
      } else {
        timer.cancel();
      }
    });
  }

  static void stop() {
    debugPrint('[LocationService] Stopping tracking.');
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    isTracking = false;
    isInsideGeofence = null;
  }

  static Future<void> _handlePositionUpdate(Position position) async {
    final double? gfLat = SessionManager.geofenceLatitude;
    final double? gfLng = SessionManager.geofenceLongitude;
    final double? gfRad = SessionManager.geofenceRadius;

    if (gfLat == null || gfLng == null || gfRad == null) {
      debugPrint('[LocationService] Geofence configuration not found in SessionManager.');
      return;
    }

    final double distance = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      gfLat,
      gfLng,
    );

    final bool currentlyInside = distance <= gfRad;
    isInsideGeofence = currentlyInside;

    debugPrint('[LocationService] Update -> Lat: ${position.latitude.toStringAsFixed(6)}, Lng: ${position.longitude.toStringAsFixed(6)}, Distance: ${distance.toStringAsFixed(1)}m, Inside: $currentlyInside');

    if (currentlyInside) {
      _exitStartTime = null;
      _sentOutsideWarning = false;
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
          automaticAttendanceFailed = false;
          attendanceFailedController.add(false);
          statusMessage = 'Attendance registered successfully.';
          statusController.add(statusMessage);

          NotificationService.showNotification(
            id: 1,
            title: 'You are in the premises',
            body: 'Your attendance has been marked successfully.',
          );
          debugPrint('[LocationService] Automatic check-in success.');
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
          automaticAttendanceFailed = false;
          attendanceFailedController.add(false);
          statusMessage = 'Returned to premises. Tracking active.';
          statusController.add(statusMessage);

          NotificationService.showNotification(
            id: 10,
            title: 'Returned to premises',
            body: 'Your attendance tracking has resumed.',
          );
          debugPrint('[LocationService] Automatic return success.');
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
            statusMessage = 'Outside Campus (Exit logged).';
            statusController.add(statusMessage);
            _exitStartTime = DateTime.now();

            final limit = SessionManager.evaluationMinutes ?? SessionManager.allowedOutsideMinutes ?? 25;
            NotificationService.showNotification(
              id: 3,
              title: 'Left the premises',
              body: 'You have left the premises. Please return within $limit minutes to avoid absence.',
            );
            debugPrint('[LocationService] Automatic exit log success.');
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
      final double? gfLng = SessionManager.geofenceLongitude;
      final double? gfRad = SessionManager.geofenceRadius;

      if (gfLat == null || gfLng == null || gfRad == null) {
        throw Exception('Geofence configuration is missing.');
      }

      final double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        gfLat,
        gfLng,
      );

      if (distance > gfRad) {
        throw Exception('You must be inside the campus boundaries to register attendance. Current distance: ${distance.toStringAsFixed(1)}m');
      }

      isCheckingIn = true;
      try {
        await ApiService.reportLocationEvent(
          latitude: position.latitude,
          longitude: position.longitude,
          eventType: 'ENTER_CAMPUS',
        );
        automaticAttendanceFailed = false;
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

  static Future<void> checkCurrentLocation() async {
    debugPrint('[LocationService] Performing manual/immediate location verification...');
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      await _handlePositionUpdate(position);
    } catch (e) {
      debugPrint('[LocationService] Failed to check current location: $e');
    }
  }

  static bool _sentCompletedNotification = false;

  static void _checkCompletionNotification(Map<String, dynamic> data) {
    final checkIn = data['check_in_time'];
    final campusStatus = data['campus_status'];

    if (checkIn == null) {
      _sentCompletedNotification = false;
      return;
    }

    if (campusStatus == 'COMPLETED' && !_sentCompletedNotification) {
      _sentCompletedNotification = true;
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
      
      // Cache geofence
      final lat = data['geofence_latitude'] as double? ?? 0.0;
      final lng = data['geofence_longitude'] as double? ?? 0.0;
      final rad = data['geofence_radius'] as double? ?? 0.0;
      final allowedOutside = data['allowed_outside_minutes'] as int? ?? 25;
      final rem1 = data['reminder_1_minutes'] as int? ?? 0;
      final rem2 = data['reminder_2_minutes'] as int? ?? 0;
      final rem3 = data['reminder_3_minutes'] as int? ?? 0;
      final eval = data['evaluation_minutes'] as int? ?? 15;
      SessionManager.cacheGeofence(lat, lng, rad, allowedOutside, rem1, rem2, rem3, eval);

      // Check for completion notification
      _checkCompletionNotification(data);
    } catch (e) {
      debugPrint('[LocationService] Failed to sync with server: $e');
    }
  }
}

