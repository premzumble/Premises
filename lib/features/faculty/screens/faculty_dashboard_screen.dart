import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api_service.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_sizes.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/widgets/status_chip.dart';
import '../../../core/session_manager.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/notification_service.dart';


class FacultyDashboardScreen extends StatefulWidget {
  const FacultyDashboardScreen({super.key});

  @override
  State<FacultyDashboardScreen> createState() => _FacultyDashboardScreenState();
}

class _FacultyDashboardScreenState extends State<FacultyDashboardScreen> {
  static bool _sentCompletedNotification = false;
  bool _isLoading = true;
  String? _errorMessage;
  Map<String, dynamic>? _summary;
  Timer? _refreshTimer;
  StreamSubscription<String?>? _statusSubscription;
  StreamSubscription<bool>? _failedSubscription;
  String? _locationStatus;
  bool _isActionLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDashboard(showLoading: true);
    
    // Start periodic background updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _loadDashboard(showLoading: false);
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

    // Initialize services
    NotificationService.requestPermissions();
    LocationService.initialize();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _statusSubscription?.cancel();
    _failedSubscription?.cancel();
    super.dispose();
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
        final lat = data['geofence_latitude'] as double? ?? 0.0;
        final lng = data['geofence_longitude'] as double? ?? 0.0;
        final rad = data['geofence_radius'] as double? ?? 0.0;
        final allowedOutside = data['allowed_outside_minutes'] as int? ?? 25;
        final rem1 = data['reminder_1_minutes'] as int? ?? 0;
        final rem2 = data['reminder_2_minutes'] as int? ?? 0;
        final rem3 = data['reminder_3_minutes'] as int? ?? 0;
        final eval = data['evaluation_minutes'] as int? ?? 15;
        SessionManager.cacheGeofence(lat, lng, rad, allowedOutside, rem1, rem2, rem3, eval);
        LocationService.checkCurrentLocation();

        // Update location service check-in/out reference
        LocationService.checkInTime = data['check_in_time'];
        LocationService.checkOutTime = data['check_out_time'];
        LocationService.serverCampusStatus = data['campus_status'];
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

  void _checkOfficiallyRegisteredNotification(Map<String, dynamic> data) {
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
                  const SizedBox(height: 20),

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
                          Text("Today's Presence Info", style: AppTypography.h3),
                          const SizedBox(height: 12),
                          _buildPresenceCard(isDark, s),
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

    return Card(
      color: theme.colorScheme.primary.withOpacity(0.04),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
              child: Text(initial, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Welcome back, $name', style: AppTypography.h3),
                  Text(
                    'Faculty Member',
                    style: AppTypography.caption.copyWith(
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),
            _buildPresenceTag(s),
          ],
        ),
      ),
    );
  }

  Widget _buildPresenceTag(Map<String, dynamic> s) {
    final campusStatus = s['campus_status'] ?? 'UNKNOWN';
    final bool? gpsInside = LocationService.isInsideGeofence;

    final String label;
    final Color bgColor;
    final Color textColor;

    if (campusStatus == 'COMPLETED') {
      label = 'OFFICIALLY REGISTERED';
      bgColor = AppColors.success.withOpacity(0.12);
      textColor = AppColors.success;
    } else if (gpsInside == true || campusStatus == 'INSIDE') {
      label = 'IN PREMISES';
      bgColor = AppColors.success.withOpacity(0.12);
      textColor = AppColors.success;
    } else {
      label = 'OUTSIDE PREMISES';
      bgColor = AppColors.warning.withOpacity(0.12);
      textColor = AppColors.warning;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildLocationStatusBanner(ThemeData theme, bool isDark) {
    // Determine display text based on actual GPS + attendance state
    final String status;
    final IconData icon;
    final Color color;

    final bool? gpsInside = LocationService.isInsideGeofence;
    final String? locMsg = _locationStatus ?? LocationService.statusMessage;
    final campusStatus = _summary?['campus_status'] ?? 'UNKNOWN';

    if (campusStatus == 'COMPLETED') {
      // Day is done — positive confirmation
      status = 'Attendance completed for today. See you tomorrow!';
      icon = Icons.check_circle_outline;
      color = AppColors.success;
    } else if (locMsg != null && (locMsg.contains('disabled') || locMsg.contains('denied') || locMsg.contains('permanently'))) {
      status = locMsg;
      icon = Icons.location_off_outlined;
      color = AppColors.danger;
    } else if (gpsInside == true) {
      status = 'You are inside the campus. Location tracking active.';
      icon = Icons.my_location;
      color = AppColors.success;
    } else if (gpsInside == false) {
      status = 'You are outside the campus boundary.';
      icon = Icons.location_searching;
      color = campusStatus == 'COMPLETED' ? AppColors.success : Colors.orange;
    } else {
      // GPS not resolved yet
      status = locMsg ?? 'Initializing real-time tracking...';
      icon = Icons.gps_not_fixed;
      color = Colors.grey;
    }

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                status,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
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

  Widget _buildPresenceCard(bool isDark, Map<String, dynamic> s) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildInfoRow(Icons.pin_drop_outlined, 'Campus Boundary Status:', s['campus_status'] ?? 'UNKNOWN'),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value, 
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.w600, 
                fontSize: 13,
                color: valueColor,
              )
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
