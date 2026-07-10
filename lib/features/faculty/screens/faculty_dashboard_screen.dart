import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api_service.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_sizes.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/session_manager.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/notification_persistence_service.dart';
import '../../../core/services/geofence_websocket.dart';


class FacultyDashboardScreen extends StatefulWidget {
  const FacultyDashboardScreen({super.key});

  @override
  State<FacultyDashboardScreen> createState() => _FacultyDashboardScreenState();
}

class _FacultyDashboardScreenState extends State<FacultyDashboardScreen> with WidgetsBindingObserver {
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _summary;
  Timer? _refreshTimer;
  StreamSubscription<String?>? _statusSubscription;
  StreamSubscription<bool>? _failedSubscription;
  StreamSubscription<void>? _eventLoggedSubscription;
  StreamSubscription<String>? _transitionSubscription;
  String? _locationStatus;
  bool _isActionLoading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadDashboard(showLoading: true);
    
    // Start periodic background updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadDashboard(showLoading: false);
    });

    // Initialize WebSockets for push notifications of geofence changes
    GeofenceWebSocketClient.connect();

    // Listen to real-time geofence transitions to update the UI instantly
    _transitionSubscription = LocationService.geofenceTransitionController.stream.listen((status) {
      debugPrint('[Dashboard] Real-time Geofence Transition: $status');
      if (mounted) {
        setState(() {
          if (_summary != null) {
            _summary!['campus_status'] = status;
          }
        });
      }
    });

    // Listen to location service updates
    _statusSubscription = LocationService.statusController.stream.listen((status) {
      debugPrint('[Dashboard] Location Status Update: $status');
      if (mounted) {
        setState(() {
          _locationStatus = status;
        });
      }
    });

    _failedSubscription = LocationService.attendanceFailedController.stream.listen((failed) {
      debugPrint('[Dashboard] Automatic Attendance Failure: $failed');
      if (mounted) setState(() {});
    });

    _eventLoggedSubscription = LocationService.eventLoggedController.stream.listen((_) {
      debugPrint('[Dashboard] Location Event Logged. Reloading dashboard summary...');
      _loadDashboard(showLoading: false);
    });

    // Initialize services
    NotificationService.requestPermissions();
    LocationService.initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    GeofenceWebSocketClient.disconnect();
    _refreshTimer?.cancel();
    _statusSubscription?.cancel();
    _failedSubscription?.cancel();
    _eventLoggedSubscription?.cancel();
    _transitionSubscription?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[Dashboard] App Resumed. Refreshing data...');
      _loadDashboard(showLoading: false);
      LocationService.syncWithServer();
    }
  }

  Future<void> _loadDashboard({required bool showLoading}) async {
    if (showLoading && _summary == null) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final data = await ApiService.fetchDashboardSummary();
      if (mounted) {
        setState(() {
          _summary = data;
          _isLoading = false;
          _errorMessage = null;
        });
        
        // Cache geofence configuration globally
        final double lat = data['geofence_latitude'] != null ? (data['geofence_latitude'] as num).toDouble() : 0.0;
        final double lng = data['geofence_longitude'] != null ? (data['geofence_longitude'] as num).toDouble() : 0.0;
        final double rad = data['geofence_radius'] != null ? (data['geofence_radius'] as num).toDouble() : 0.0;
        final String type = data['geofence_type'] as String? ?? 'circle';
        final vertices = data['geofence_vertices'];
        final String? verticesJson = vertices != null ? json.encode(vertices) : null;
        final int allowedOutside = data['allowed_outside_minutes'] as int? ?? 25;
        final int rem1 = data['reminder_1_minutes'] as int? ?? 0;
        final int rem2 = data['reminder_2_minutes'] as int? ?? 0;
        final int rem3 = data['reminder_3_minutes'] as int? ?? 0;
        final int eval = data['evaluation_minutes'] as int? ?? 15;
        final String? gfId = data['geofence_id'] as String?;
        final String? gfUpdatedAt = data['geofence_updated_at'] as String?;

        final bool geofenceChanged = gfId != SessionManager.geofenceId || gfUpdatedAt != SessionManager.geofenceUpdatedAt;

        debugPrint('[DASHBOARD CACHE] type=$type, lat=$lat, lng=$lng, rad=$rad, geofenceChanged=$geofenceChanged');
        debugPrint('[DASHBOARD CACHE] vertices=${vertices != null ? (vertices as List).length : "null"} items');
        debugPrint('[DASHBOARD CACHE] verticesJson=${verticesJson != null ? "${verticesJson.length} chars" : "null"}');
        if (verticesJson != null) {
          debugPrint('[DASHBOARD CACHE] verticesJson first 200 chars: ${verticesJson.substring(0, verticesJson.length < 200 ? verticesJson.length : 200)}');
        }

        SessionManager.cacheGeofence(lat, lng, rad, type, verticesJson, allowedOutside, rem1, rem2, rem3, eval, gfId, gfUpdatedAt);
        
        // Force location service to re-evaluate if geofence configuration changed or if it hasn't evaluated initial location yet
        final bool shouldForce = geofenceChanged || !LocationService.hasEvaluatedInitialLocation;
        if (shouldForce) {
          debugPrint('[DASHBOARD] Geofence config changed or initial evaluation pending. Forcing immediate GPS evaluation.');
          LocationService.hasEvaluatedInitialLocation = true;
          LocationService.forceReevaluate(geofenceChanged: true);
        }

        // Update location service check-in/out reference
        LocationService.checkInTime = data['check_in_time'];
        LocationService.checkOutTime = data['check_out_time'];
        if (!LocationService.shouldIgnoreServerStatus) {
          LocationService.serverCampusStatus = data['campus_status'];
        }
        _checkOfficiallyRegisteredNotification(data);
      }
    } on ApiException catch (e) {
      if (mounted && showLoading) {
        setState(() {
          _errorMessage = e.message;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && showLoading) {
        setState(() {
          _errorMessage = 'Failed to load dashboard summary.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _checkOfficiallyRegisteredNotification(Map<String, dynamic> data) async {
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

  Future<void> _registerAttendanceManually() async {


    setState(() {
      _isActionLoading = true;
    });

    try {
      final success = await LocationService.forceRegisterAttendance();
      if (success) {
        await _loadDashboard(showLoading: false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Attendance registered successfully.'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isActionLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isLoading && _summary == null) {
      return _buildSkeletonLoader(context, isDark);
    }

    if (_errorMessage != null && _summary == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: AppTypography.bodyLarge),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _loadDashboard(showLoading: true),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    final s = _summary!;
    final checkIn = s['check_in_time'];
    final checkOut = s['check_out_time'];
    final campusStatus = s['campus_status'] ?? 'UNKNOWN';

    // Day is fully complete — checked in AND checked out
    final bool dayCompleted = checkIn != null && checkOut != null;

    // Only show manual button if: inside geofence + no check-in + auto failed
    final bool showManualButton = LocationService.isInsideGeofence == true &&
        checkIn == null &&
        LocationService.automaticAttendanceFailed;

    // Only show "outside" warning if: has check-in, NOT checked out yet, campus=OUTSIDE
    final bool showWarning = !dayCompleted &&
        s['warning_message'] != null &&
        campusStatus != 'COMPLETED' &&
        !showManualButton;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () => _loadDashboard(showLoading: true),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Welcome Profile Card
                  _buildProfileCard(theme, isDark, s),
                  const SizedBox(height: 16),
                  


                  // Standard automatic attendance status banner
                  _buildLocationStatusBanner(theme, isDark),
                  const SizedBox(height: 20),

                  // Warning Banner + Register button if automatic check-in failed inside campus
                  if (showManualButton) ...[
                    _buildWarningBanner(
                      'You are inside the campus but your attendance has not been registered.',
                      actionButton: _isActionLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: AppColors.warning,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              ),
                              onPressed: _registerAttendanceManually,
                              child: const Text('Register Attendance', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  if (showWarning) ...[
                    _buildWarningBanner(s['warning_message']),
                    const SizedBox(height: 20),
                  ],

                  LayoutBuilder(
                    builder: (context, constraints) {
                      final useVerticalLayout = constraints.maxWidth < 600;

                      final presenceColumn = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text("Today's Attendance Status", style: AppTypography.h3),
                          const SizedBox(height: 12),
                          _buildAttendanceCard(isDark, s),
                          const SizedBox(height: 20),
                          Text("Working Hours", style: AppTypography.h3),
                          const SizedBox(height: 12),
                          _buildWorkingHoursCard(isDark, s),
                        ],
                      );

                      final quickActionsColumn = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Quick Actions', style: AppTypography.h3),
                          const SizedBox(height: 12),
                          _buildQuickActions(context, s),
                        ],
                      );

                      if (useVerticalLayout) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            presenceColumn,
                            const SizedBox(height: 24),
                            quickActionsColumn,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: presenceColumn,
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 2,
                            child: quickActionsColumn,
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildProfileCard(ThemeData theme, bool isDark, Map<String, dynamic> s) {
    final name = SessionManager.fullName ?? 'Faculty User';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'F';
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;

    return Card(
      color: theme.colorScheme.primary.withOpacity(0.04),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.primary.withOpacity(0.08)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: isMobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                        child: Text(
                          initial,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome back,',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildPresenceTag(s),
                ],
              )
            : Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                    child: Text(
                      initial,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back,',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  _buildPresenceTag(s),
                ],
              ),
      ),
    );
  }

  Widget _buildPresenceTag(Map<String, dynamic> s) {
    final campusStatus = s['campus_status'] ?? 'UNKNOWN';
    final bool? gpsInside = LocationService.isInsideGeofence;
    final bool? effectiveInside = gpsInside ?? (campusStatus == 'UNKNOWN' ? null : (campusStatus == 'INSIDE'));

    final String label;
    final Color color;

    if (campusStatus == 'COMPLETED') {
      label = 'OFFICIALLY REGISTERED';
      color = AppColors.success;
    } else if (effectiveInside == true) {
      label = 'IN PREMISES';
      color = AppColors.success;
    } else {
      label = 'OUTSIDE PREMISES';
      color = AppColors.warning;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationStatusBanner(ThemeData theme, bool isDark) {
    // Determine display text based ONLY on actual GPS status
    final String status;
    final IconData icon;
    final Color color;
    String? subtitle;
    List<Widget> badges = [];

    final bool? gpsInside = LocationService.isInsideGeofence;
    final String? locMsg = _locationStatus ?? LocationService.statusMessage;
    final campusStatus = _summary?['campus_status'] ?? 'UNKNOWN';
    final bool? effectiveInside = gpsInside ?? (campusStatus == 'UNKNOWN' ? null : (campusStatus == 'INSIDE'));

    if (locMsg != null && (locMsg.contains('disabled') || locMsg.contains('denied') || locMsg.contains('permanently'))) {
      status = 'GPS Service Required';
      icon = Icons.location_off_outlined;
      color = AppColors.danger;
      subtitle = locMsg;
    } else if (effectiveInside == true) {
      status = 'Inside Premises';
      icon = Icons.my_location;
      color = AppColors.success;
      subtitle = 'Your device is currently inside the campus boundary.';
      badges = [
        _buildMiniBadge('GPS ACQUIRED', AppColors.success, isDark),
        _buildMiniBadge('MONITORING', AppColors.success, isDark),
      ];
    } else if (effectiveInside == false) {
      status = 'Outside Premises';
      icon = Icons.location_searching;
      color = Colors.orange;
      subtitle = 'Your device is outside the campus boundary.';
      badges = [
        _buildMiniBadge('GPS ACQUIRED', AppColors.success, isDark),
        _buildMiniBadge('MONITORING', Colors.orange, isDark),
      ];
    } else {
      // GPS not resolved yet or waiting for config
      status = locMsg ?? 'Initializing tracking...';
      icon = Icons.gps_not_fixed;
      color = Colors.grey;
      subtitle = 'Acquiring high-accuracy GPS lock...';
    }

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        status,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        subtitle ?? '',
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.grey[400] : Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: badges
                    .expand((widget) => [widget, const SizedBox(width: 8)])
                    .toList()
                  ..removeLast(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMiniBadge(String text, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildWarningBanner(String message, {Widget? actionButton}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          if (actionButton != null) ...[
            const SizedBox(width: 16),
            actionButton,
          ],
        ],
      ),
    );
  }

  Map<String, dynamic> _getAttendanceStateLabelAndColor(Map<String, dynamic> s) {
    final campusStatus = s['campus_status'] ?? 'UNKNOWN';
    final attendanceStatus = s['attendance_status'] ?? 'NOT_STARTED';

    if (campusStatus == 'COMPLETED') {
      return {'label': 'Daily Shift Completed', 'color': AppColors.success};
    }
    
    switch (attendanceStatus) {
      case 'PRESENT':
        return {'label': 'Checked In', 'color': AppColors.success};
      case 'ABSENT':
        return {'label': 'Absent', 'color': AppColors.danger};
      case 'HALF_DAY':
        return {'label': 'Half Day', 'color': AppColors.warning};
      case 'OUTSIDE':
        return {'label': 'Checked In (Outside)', 'color': AppColors.warning};
      default:
        return {'label': 'Pending / Not Started', 'color': Colors.grey};
    }
  }

  Widget _buildAttendanceCard(bool isDark, Map<String, dynamic> s) {
    final state = _getAttendanceStateLabelAndColor(s);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildInfoRow(Icons.rule_folder_outlined, 'Attendance Status:', state['label'], valueColor: state['color']),
            _buildInfoRow(Icons.punch_clock_outlined, 'First Gate Entrance:', _formatTime(s['check_in_time'])),
            _buildInfoRow(Icons.exit_to_app_outlined, 'Last Gate Exit:', _formatTime(s['check_out_time'])),
            _buildInfoRow(Icons.timer_outlined, 'Total Working Time:', s['working_duration'] ?? '00h 00m'),
            if (s['reason_status'] != null)
              _buildInfoRow(Icons.assignment_turned_in_outlined, 'Excusal Request Status:', s['reason_status'], 
                valueColor: _getStatusColor(s['reason_status'])),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkingHoursCard(bool isDark, Map<String, dynamic> s) {
    final department = s['department_name'] as String?;
    final startTime = s['policy_start_time'] as String? ?? '--:--';
    final endTime = s['policy_end_time'] as String? ?? '--:--';
    final source = s['policy_source'] as String? ?? 'Organization Default Schedule';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (department != null && department.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.business_outlined, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Department: $department',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
            ],
            _buildInfoRow(Icons.login_outlined, 'Expected Entry Time:', startTime),
            _buildInfoRow(Icons.logout_outlined, 'Expected Exit Time:', endTime),
            _buildInfoRow(Icons.info_outline, 'Schedule Source:', source, valueColor: Colors.blueGrey),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, Map<String, dynamic> s) {
    return Column(
      children: [
        _actionItem(
          Icons.assignment_outlined, 
          'Submit Excusal', 
          s['reason_required'] == true ? 'Action Required' : 'Optional',
          s['reason_required'] == true ? AppColors.warning : null,
          () => context.go('/faculty/reason-request'),
        ),
        const SizedBox(height: 12),
        _actionItem(Icons.history, 'Attendance History', 'View full logs', null, () => context.go('/faculty/history')),
        const SizedBox(height: 12),
        _actionItem(Icons.notifications_none_outlined, 'Notifications', 'Recent alerts', null, () => context.go('/faculty/notifications')),
        const SizedBox(height: 12),
        _actionItem(Icons.phone_android_outlined, 'Registered Device', 'Manage handset', null, () => context.go('/faculty/device')),
        const SizedBox(height: 12),
        _actionItem(Icons.person_outline, 'My Profile', 'Account settings', null, () => context.go('/faculty/profile')),
      ],
    );
  }

  Widget _actionItem(IconData icon, String title, String subtitle, Color? badgeColor, VoidCallback onTap) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(icon, size: 24, color: badgeColor ?? AppColors.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(subtitle, style: AppTypography.caption),
                  ],
                ),
              ),
              if (badgeColor != null)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: badgeColor, shape: BoxShape.circle),
                ),
              const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {Color? valueColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final secondaryColor = isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: secondaryColor),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(color: secondaryColor, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.borderDark.withOpacity(0.3) : AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark ? AppColors.borderDark : AppColors.borderLight,
                    width: 0.5,
                  ),
                ),
                child: Text(
                  value, 
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    fontSize: 11,
                    color: valueColor ?? (isDark ? AppColors.textPrimaryDark : AppColors.primary),
                  )
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '--:--';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '--:--';
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'APPROVED': return AppColors.success;
      case 'REJECTED': return AppColors.danger;
      case 'PENDING': return Colors.orange;
      default: return Colors.grey;
    }
  }

  Widget _buildSkeletonLoader(BuildContext context, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Welcome card skeleton
              SkeletonPlaceholder(width: double.infinity, height: 100, borderRadius: 12),
              const SizedBox(height: 20),
              // Status banner skeleton
              SkeletonPlaceholder(width: double.infinity, height: 60, borderRadius: 12),
              const SizedBox(height: 20),
              // Presence Info & actions layout
              LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 600) {
                    return Column(
                      children: [
                        SkeletonPlaceholder(width: double.infinity, height: 180, borderRadius: 12),
                        const SizedBox(height: 24),
                        SkeletonPlaceholder(width: double.infinity, height: 280, borderRadius: 12),
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: SkeletonPlaceholder(width: double.infinity, height: 180, borderRadius: 12),
                      ),
                      const SizedBox(width: 24),
                      Expanded(
                        flex: 2,
                        child: SkeletonPlaceholder(width: double.infinity, height: 280, borderRadius: 12),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SkeletonPlaceholder extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonPlaceholder({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<SkeletonPlaceholder> createState() => _SkeletonPlaceholderState();
}

class _SkeletonPlaceholderState extends State<SkeletonPlaceholder>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 0.8).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: _animation.value,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[800] : Colors.grey[300],
              borderRadius: BorderRadius.circular(widget.borderRadius),
            ),
          ),
        );
      },
    );
  }
}
