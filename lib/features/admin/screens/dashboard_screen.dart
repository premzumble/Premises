import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:showcaseview/showcaseview.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_sizes.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/widgets/search_bar.dart';
import '../../../core/api_service.dart';
import '../../../core/session_manager.dart';
import '../walkthrough/controller/walkthrough_controller.dart';
import '../walkthrough/walkthrough_steps_definition.dart';
import '../walkthrough/widgets/walkthrough_tooltip.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _searchController = TextEditingController();
  bool _isLoading = true;
  String? _errorMessage;
  int _presentCount = 0;
  int _outsideCount = 0;
  int _absentCount = 0;
  int _pendingRequestsCount = 0;
  int _totalFacultyCount = 0;
  String _orgName = '';
  String _orgCode = '';
  String _adminEmail = '';
  String _orgCreatedAt = '';
  String _orgStatus = '';
  bool _showBanner = false;
  List<dynamic> _recentActivities = [];
  Timer? _refreshTimer;

  Future<void> _checkBannerStatus() async {
    final shouldShow = await SessionManager.shouldShowOrgCodeBanner();
    if (mounted && _orgName.isNotEmpty && _orgCode.isNotEmpty) {
      setState(() {
        _showBanner = shouldShow;
      });
    }
  }

  // Dynamic policy settings
  int? _allowedOutsideMinutes;
  int? _reminder1Minutes;
  int? _reminder2Minutes;
  int? _reminder3Minutes;
  int? _evaluationMinutes;
  String? _startTime;
  String? _endTime;
  String? _halfDayCutoffTime;
  String? _absentCutoffTime;

  String _formatPolicyTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '--:--';
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        final ampm = hour >= 12 ? 'PM' : 'AM';
        final formattedHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        final formattedMinute = minute.toString().padLeft(2, '0');
        return '$formattedHour:$formattedMinute $ampm';
      }
    } catch (_) {}
    return timeStr;
  }

  @override
  void initState() {
    super.initState();
    _fetchSummaryData(showLoading: true);
    // Auto refresh every 10 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) {
        _fetchSummaryData(showLoading: false);
      }
    });
    // Notify walkthrough controller that Dashboard is rendered.
    // The controller starts Phase 1 only when awaiting this signal.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        WalkthroughController.instance.onDashboardReady(context);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchSummaryData({required bool showLoading}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final res = await ApiService.get('/admin/dashboard-summary');
      if (res['success'] == true && res['data'] != null) {
        final data = res['data'];
        
        // Fetch active policy dynamically
        Map<String, dynamic>? policyData;
        try {
          final policyRes = await ApiService.fetchPolicy();
          if (policyRes['success'] == true) {
            policyData = policyRes['data'];
          }
        } catch (e) {
          debugPrint('Failed to fetch policy: $e');
        }

        if (mounted) {
          setState(() {
            _presentCount = data['present_count'] ?? 0;
            _outsideCount = data['outside_count'] ?? 0;
            _absentCount = data['absent_count'] ?? 0;
            _pendingRequestsCount = data['pending_requests_count'] ?? 0;
            _totalFacultyCount = data['total_faculty'] ?? 0;
            _orgName = data['org_name'] ?? '';
            _orgCode = data['org_code'] ?? '';
            _adminEmail = data['admin_email'] ?? '';
            _orgStatus = data['org_status'] ?? 'ACTIVE';
            
            if (data['org_created_at'] != null) {
              try {
                final dt = DateTime.parse(data['org_created_at']);
                _orgCreatedAt = "${dt.day}/${dt.month}/${dt.year}";
              } catch (_) {
                _orgCreatedAt = data['org_created_at'];
              }
            }

            _recentActivities = data['recent_activities'] ?? [];
            
            // Check if first login for banner (persisted via SharedPreferences)
            _checkBannerStatus();
            
            if (policyData != null) {
              _allowedOutsideMinutes = policyData['allowed_outside_minutes'];
              _reminder1Minutes = policyData['reminder_1_minutes'];
              _reminder2Minutes = policyData['reminder_2_minutes'];
              _reminder3Minutes = policyData['reminder_3_minutes'];
              _evaluationMinutes = policyData['evaluation_minutes'];
              _startTime = policyData['start_time'];
              _endTime = policyData['end_time'];
              _halfDayCutoffTime = policyData['half_day_cutoff_time'];
              _absentCutoffTime = policyData['absent_cutoff_time'];
            }
            
            _isLoading = false;
            _errorMessage = null;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage = res['message'] ?? 'Failed to load summary data.';
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted && showLoading) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return "${months[now.month - 1]} ${now.day}, ${now.year}";
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(48.0),
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null && _orgName.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _fetchSummaryData(showLoading: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    int gridCount = width < 600 ? 1 : (width < 1200 ? 2 : 5);
    double childAspectRatio = width < 600 ? 3.0 : 1.8;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_showBanner) _buildFirstLoginBanner(theme, isDark),
          // Greeting & Quick Search Row
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 700;

              final greetingBlock = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Premises',
                        style: AppTypography.h1.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'ORGANIZATION SPACE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Smart Attendance & Premises Monitoring',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.w500,
                      color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome back, ${SessionManager.fullName ?? 'Admin'}',
                    style: AppTypography.h2.copyWith(
                      color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.corporate_fare, size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        _orgName.isNotEmpty ? _orgName : 'Loading organization...',
                        style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      const Text('•', style: TextStyle(color: Colors.grey)),
                      const SizedBox(width: 8),
                      Text(
                        _getFormattedDate(),
                        style: AppTypography.caption,
                      ),
                    ],
                  ),
                ],
              );

              final searchField = SizedBox(
                width: isWide ? 280 : double.infinity,
                child: AppSearchBar(
                  controller: _searchController,
                  hint: 'Quick search anything...',
                ),
              );

              return isWide
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        greetingBlock,
                        searchField,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        greetingBlock,
                        const SizedBox(height: 16),
                        searchField,
                      ],
                    );
            },
          ),
          const SizedBox(height: 32),

          // KPI Cards Grid — wrapped with Showcase for tour Step 1
          Showcase.withWidget(
            key: WalkthroughKeys.kpiGrid,
            overlayOpacity: 0.75,
            disableDefaultTargetGestures: true,
            targetShapeBorder: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
            targetPadding: const EdgeInsets.all(6),
            container: const WalkthroughTooltip(
              stepNumber: 1,
              title: 'Live Attendance Overview',
              body:
                  'Your real-time command center. See who is present on campus, outside the geofence, or absent — all updated live every 10 seconds.',
              icon: Icons.dashboard_outlined,
              isFirstInPhase: true,
              callToAction: 'Tap any card to navigate to that filtered view.',
            ),
            child: GridView.count(
              crossAxisCount: gridCount,
              childAspectRatio: childAspectRatio,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildDashboardKpiCard(
                  title: 'Present Faculty',
                  value: '$_presentCount',
                  description: 'Active presence inside campus',
                  trend: 'Live',
                  isPositive: true,
                  icon: Icons.check_circle_outlined,
                  color: AppColors.success,
                  onTap: () => context.go('/admin/faculty?status=active'),
                ),
                _buildDashboardKpiCard(
                  title: 'Outside Campus',
                  value: '$_outsideCount',
                  description: 'Out-of-bounds warning state',
                  trend: 'Warning',
                  isPositive: false,
                  icon: Icons.wrong_location_outlined,
                  color: AppColors.warning,
                  onTap: () => context.go('/admin/attendance'),
                ),
                _buildDashboardKpiCard(
                  title: 'Absent Faculty',
                  value: '$_absentCount',
                  description: 'No check-in detected today',
                  trend: 'Absent',
                  isPositive: false,
                  icon: Icons.cancel_outlined,
                  color: AppColors.danger,
                  onTap: () => context.go('/admin/attendance'),
                ),
                _buildDashboardKpiCard(
                  title: 'Pending Requests',
                  value: '$_pendingRequestsCount',
                  description: 'Awaiting admin approvals',
                  trend: _pendingRequestsCount > 0 ? 'Action req.' : 'Clear',
                  isPositive: _pendingRequestsCount == 0,
                  icon: Icons.pending_actions_outlined,
                  color: AppColors.info,
                  onTap: () => context.go('/admin/requests'),
                ),
                _buildDashboardKpiCard(
                  title: 'Total Directory',
                  value: '$_totalFacultyCount',
                  description: 'Total registered faculty members',
                  trend: 'Active',
                  isPositive: true,
                  icon: Icons.people_outline,
                  color: theme.colorScheme.primary,
                  onTap: () => context.go('/admin/faculty'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // Lower Section
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth > 900;
              final widgets = [
                _buildActivePolicySummary(context),
                const SizedBox(height: 24),
                _buildOrgInfoCard(context),
                const SizedBox(height: 24),
                _buildActivityFeed(context),
              ];

              return isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: Column(
                          children: [
                            widgets[0],
                            const SizedBox(height: 24),
                            widgets[2],
                          ],
                        )),
                        const SizedBox(width: 24),
                        Expanded(flex: 2, child: widgets[4]),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        widgets[0],
                        const SizedBox(height: 24),
                        widgets[2],
                        const SizedBox(height: 24),
                        widgets[4],
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardKpiCard({
    required String title,
    required String value,
    required String description,
    required String trend,
    required bool isPositive,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return _HoverableKpiCard(
      title: title,
      value: value,
      description: description,
      trend: trend,
      isPositive: isPositive,
      icon: icon,
      color: color,
      onTap: onTap,
    );
  }

  Widget _buildActivePolicySummary(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Active Attendance Policy', style: AppTypography.h3),
                Icon(Icons.shield_outlined, color: theme.colorScheme.primary, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Current operational geofence limits and notification timings.',
              style: AppTypography.caption,
            ),
            const Divider(height: 32),
            _buildPolicyRow(
              Icons.timer_outlined,
              'Allowed Outside Duration',
              _allowedOutsideMinutes != null ? '$_allowedOutsideMinutes Minutes' : 'Loading...',
            ),
            _buildPolicyRow(
              Icons.notifications_active_outlined,
              'Trigger Reminders',
              (_reminder1Minutes != null && _reminder2Minutes != null && _reminder3Minutes != null)
                  ? '${_reminder1Minutes}m, ${_reminder2Minutes}m, ${_reminder3Minutes}m'
                  : 'Loading...',
            ),
            _buildPolicyRow(
              Icons.update_outlined,
              'Evaluation Frequency',
              _evaluationMinutes != null ? 'Every $_evaluationMinutes Minutes' : 'Loading...',
            ),
            _buildPolicyRow(
              Icons.running_with_errors_outlined,
              'Half-Day Cutoff Threshold',
              _halfDayCutoffTime != null ? 'After ${_formatPolicyTime(_halfDayCutoffTime)}' : 'Loading...',
            ),
            _buildPolicyRow(
              Icons.alarm_off_outlined,
              'Absent Cutoff Threshold',
              _absentCutoffTime != null ? 'Before ${_formatPolicyTime(_absentCutoffTime)}' : 'Loading...',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFirstLoginBanner(ThemeData theme, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(28, 16, 28, 0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 20, color: AppColors.primary),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              'Your Organization Code has been emailed to you and is available below. Faculty members will need this code during registration.',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.primary),
            ),
          ),
          IconButton(
            onPressed: () async {
              setState(() => _showBanner = false);
              await SessionManager.setOrgCodeBannerSeen();
            },
            icon: const Icon(Icons.close, size: 18, color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildOrgInfoCard(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.corporate_fare_outlined, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Text('Organization Information', style: AppTypography.h3),
              ],
            ),
            const Divider(height: 32),
            _buildDetailRow('Organization Name:', _orgName),
            _buildCodeRow('Organization Code:', _orgCode),
            _buildDetailRow('Administrator:', _adminEmail),
            _buildDetailRow('Created Date:', _orgCreatedAt),
            _buildStatusRow('System Status:', _orgStatus),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.bodyMedium.copyWith(color: Colors.grey)),
          Text(value, style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String status) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.bodyMedium.copyWith(color: Colors.grey)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              status.toUpperCase(),
              style: const TextStyle(color: AppColors.success, fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeRow(String label, String code) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTypography.bodyMedium.copyWith(color: Colors.grey)),
          Row(
            children: [
              Text(
                code,
                style: AppTypography.bodyLarge.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: code));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Organization Code copied successfully.'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.copy, size: 16, color: Colors.grey),
                tooltip: 'Copy Code',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPolicyRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActivityFeed(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Quick Approvals Preview', style: AppTypography.h3),
            const SizedBox(height: 4),
            Text('Recent pending registration request items.', style: AppTypography.caption),
            const Divider(height: 24),
            if (_recentActivities.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: Text(
                    'No recent pending requests.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
              )
            else
              ..._recentActivities.map((act) {
                final name = act['name'] ?? 'Unknown Faculty';
                final type = act['type'] ?? 'Request';
                final rawTime = act['time'];
                String timeStr = 'Just now';
                if (rawTime != null) {
                  try {
                    final dt = DateTime.parse(rawTime.toString());
                    final diff = DateTime.now().difference(dt);
                    if (diff.inMinutes < 1) {
                      timeStr = 'Just now';
                    } else if (diff.inMinutes < 60) {
                      timeStr = '${diff.inMinutes}m ago';
                    } else if (diff.inHours < 24) {
                      timeStr = '${diff.inHours}h ago';
                    } else {
                      timeStr = '${diff.inDays}d ago';
                    }
                  } catch (_) {
                    timeStr = rawTime.toString().split('T').first;
                  }
                }
                return _buildActivityItem(name, type, timeStr);
              }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(String name, String type, String time) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primary.withOpacity(0.08),
            child: Text(
              name.isEmpty ? '?' : name.split(' ').last[0],
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                Text(type, style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
          ),
          Text(time, style: const TextStyle(color: Colors.grey, fontSize: 11)),
        ],
      ),
    );
  }
}

class _HoverableKpiCard extends StatefulWidget {
  final String title;
  final String value;
  final String description;
  final String trend;
  final bool isPositive;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _HoverableKpiCard({
    required this.title,
    required this.value,
    required this.description,
    required this.trend,
    required this.isPositive,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<_HoverableKpiCard> createState() => _HoverableKpiCardState();
}

class _HoverableKpiCardState extends State<_HoverableKpiCard> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          transformAlignment: Alignment.center,
          transform: _isPressed 
              ? (Matrix4.identity()..scale(0.96)) 
              : (_isHovered ? (Matrix4.identity()..translate(0, -4)) : Matrix4.identity()),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppSizes.radiusLg),
            border: Border.all(
              color: _isHovered 
                  ? theme.colorScheme.primary.withOpacity(0.5) 
                  : (isDark ? AppColors.borderDark : AppColors.borderLight),
              width: _isHovered ? 1.5 : 1.0,
            ),
            boxShadow: _isHovered 
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      offset: const Offset(0, 10),
                      blurRadius: 20,
                    )
                  ] 
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      offset: const Offset(0, 2),
                      blurRadius: 4,
                    )
                  ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                        ),
                      ),
                    ),
                    Icon(widget.icon, color: widget.color, size: 18),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  textBaseline: TextBaseline.alphabetic,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  children: [
                    Text(
                      widget.value,
                      style: AppTypography.h1.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 28,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: widget.isPositive 
                            ? AppColors.success.withOpacity(0.1) 
                            : AppColors.danger.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.trend,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: widget.isPositive ? AppColors.success : AppColors.danger,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  widget.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    fontSize: 10,
                    color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
