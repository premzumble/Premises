import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_sizes.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/session_manager.dart';
import '../../../core/api_service.dart';

class AdminNavigation extends StatefulWidget {
  final Widget child;
  final String location;

  const AdminNavigation({
    super.key,
    required this.child,
    required this.location,
  });

  @override
  State<AdminNavigation> createState() => _AdminNavigationState();
}

class _AdminNavigationState extends State<AdminNavigation> {
  int _unreadNotifications = 0;
  List<dynamic> _notifications = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadNotificationCounts();
    // Start periodic auto-refresh every 10 seconds for real-time updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _loadNotificationCounts();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadNotificationCounts() async {
    try {
      final countsRes = await ApiService.get('/admin/pending-counts');
      final notifRes = await ApiService.get('/admin/notifications');

      if (mounted) {
        setState(() {
          _unreadNotifications = countsRes['data']['unread_notifications'] as int;
          _notifications = notifRes['data'] as List<dynamic>;
        });
      }
    } catch (e) {
      debugPrint('[AdminNavigation] Error loading notifications: $e');
    }
  }

  Future<void> _markAllNotificationsRead() async {
    try {
      await ApiService.post('/admin/notifications/mark-all-read', {});
      await _loadNotificationCounts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All notifications marked as read.'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to mark read: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }

  void _showNotificationsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Admin Notifications', style: AppTypography.h3),
                  if (_notifications.any((n) => !(n['read'] as bool)))
                    TextButton(
                      onPressed: () async {
                        await _markAllNotificationsRead();
                        setDialogState(() {
                          _notifications = _notifications.map((n) {
                            final m = Map<String, dynamic>.from(n);
                            m['read'] = true;
                            return m;
                          }).toList();
                        });
                        setState(() {
                          _unreadNotifications = 0;
                        });
                      },
                      child: const Text('Mark all read', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              content: SizedBox(
                width: MediaQuery.of(context).size.width < 480
                    ? MediaQuery.of(context).size.width * 0.85
                    : 400,
                height: 350,
                child: _notifications.isEmpty
                    ? const Center(child: Text('No recent notifications.'))
                    : ListView.builder(
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final notif = _notifications[index];
                          final isRead = notif['read'] as bool;
                          IconData icon = Icons.notifications_outlined;
                          if (notif['type'] == 'ADMIN_FACULTY_REGISTRATION') {
                            icon = Icons.badge_outlined;
                          } else if (notif['type'] == 'ADMIN_DEVICE_SWAP') {
                            icon = Icons.swap_horiz_outlined;
                          } else if (notif['type'] == 'ADMIN_GEOFENCE_EXCUSAL') {
                            icon = Icons.location_off_outlined;
                          }

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            leading: CircleAvatar(
                              backgroundColor: isRead ? Colors.grey[200] : AppColors.primary.withOpacity(0.1),
                              child: Icon(icon, color: isRead ? Colors.grey : AppColors.primary, size: 20),
                            ),
                            title: Text(
                              notif['title']?.toString() ?? '',
                              style: TextStyle(
                                fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 2),
                                Text(notif['message']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
                                const SizedBox(height: 2),
                                Text(_formatTime(notif['sent_at']?.toString() ?? ''), style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              ],
                            ),
                            trailing: !isRead
                                ? const CircleAvatar(radius: 4, backgroundColor: AppColors.primary)
                                : null,
                          );
                        },
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  int _getSelectedIndex() {
    final loc = widget.location;
    if (loc.startsWith('/admin/dashboard')) return 0;
    if (loc.startsWith('/admin/faculty')) return 1;
    if (loc.startsWith('/admin/attendance')) return 2;
    if (loc.startsWith('/admin/reports')) return 3;
    if (loc.startsWith('/admin/logs')) return 4;
    if (loc.startsWith('/admin/requests')) return 5;
    if (loc.startsWith('/admin/settings')) return 6;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/admin/dashboard');
        break;
      case 1:
        context.go('/admin/faculty');
        break;
      case 2:
        context.go('/admin/attendance');
        break;
      case 3:
        context.go('/admin/reports');
        break;
      case 4:
        context.go('/admin/logs');
        break;
      case 5:
        context.go('/admin/requests');
        break;
      case 6:
        context.go('/admin/settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;

    // Responsive breakpoints
    final isMobile = width < 640;
    final isTablet = width >= 640 && width < 960;
    final isDesktop = width >= 960;

    final selectedIndex = _getSelectedIndex();

    return Scaffold(
      appBar: isMobile
          ? AppBar(
              title: Text(
                'Premises',
                style: AppTypography.h3.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
              ),
              actions: _buildAppBarActions(context),
            )
          : null,
      body: Row(
        children: [
          // 1. Desktop Sidebar (Permanent Sidebar)
          if (isDesktop)
            Container(
              width: 250,
              decoration: BoxDecoration(
                color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                border: Border(
                  right: BorderSide(
                    color: isDark ? AppColors.borderDark : AppColors.borderLight,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Wordmark Branding
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: Text(
                      'Premises',
                      style: AppTypography.h2.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),

                  // Navigation Links
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSidebarCategory('Main Menu'),
                          _buildSidebarItem(0, Icons.dashboard_outlined, 'Dashboard', selectedIndex, context),

                          AppSizes.gapMd,
                          _buildSidebarCategory('Management'),
                          _buildSidebarItem(1, Icons.badge_outlined, 'Faculty', selectedIndex, context),
                          _buildSidebarItem(2, Icons.calendar_month_outlined, 'Attendance', selectedIndex, context),
                          _buildSidebarItem(3, Icons.analytics_outlined, 'Reports', selectedIndex, context),

                          AppSizes.gapMd,
                          _buildSidebarCategory('Audits & Operations'),
                          _buildSidebarItem(4, Icons.history_toggle_off, 'Logs', selectedIndex, context),
                          _buildSidebarItem(5, Icons.pending_actions_outlined, 'Requests', selectedIndex, context),

                          AppSizes.gapMd,
                          _buildSidebarCategory('System'),
                          _buildSidebarItem(6, Icons.settings_outlined, 'Settings', selectedIndex, context),
                        ],
                      ),
                    ),
                  ),

                  // Bottom Profile Panel
                  _buildDesktopProfilePanel(context),
                ],
              ),
            ),

          // 2. Tablet Navigation Rail
          if (isTablet)
            Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: isDark ? AppColors.borderDark : AppColors.borderLight,
                  ),
                ),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  Icon(Icons.domain, color: theme.colorScheme.primary, size: 28),
                  const SizedBox(height: 24),
                  Expanded(
                    child: NavigationRail(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: (idx) => _onItemTapped(idx, context),
                      labelType: NavigationRailLabelType.all,
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.dashboard_outlined),
                          selectedIcon: Icon(Icons.dashboard),
                          label: Text('Dashboard', style: TextStyle(fontSize: 10)),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.badge_outlined),
                          selectedIcon: Icon(Icons.badge),
                          label: Text('Faculty', style: TextStyle(fontSize: 10)),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.calendar_month_outlined),
                          selectedIcon: Icon(Icons.calendar_month),
                          label: Text('Attendance', style: TextStyle(fontSize: 10)),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.analytics_outlined),
                          selectedIcon: Icon(Icons.analytics),
                          label: Text('Reports', style: TextStyle(fontSize: 10)),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.history_toggle_off),
                          selectedIcon: Icon(Icons.history),
                          label: Text('Logs', style: TextStyle(fontSize: 10)),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.pending_actions_outlined),
                          selectedIcon: Icon(Icons.pending_actions),
                          label: Text('Requests', style: TextStyle(fontSize: 10)),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.settings_outlined),
                          selectedIcon: Icon(Icons.settings),
                          label: Text('Settings', style: TextStyle(fontSize: 10)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Main Content Panel
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Desktop/Tablet Top App Bar
                if (!isMobile)
                  Container(
                    height: 70,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                      border: Border(
                        bottom: BorderSide(
                          color: isDark ? AppColors.borderDark : AppColors.borderLight,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _getScreenTitle(selectedIndex),
                          style: AppTypography.h3.copyWith(
                            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                          ),
                        ),
                        const Spacer(),
                        ..._buildAppBarActions(context),
                      ],
                    ),
                  ),

                // Core Page Content
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(isMobile ? 16.0 : 28.0),
                    child: widget.child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      // 3. Mobile Bottom Navigation
      bottomNavigationBar: isMobile
          ? BottomNavigationBar(
              currentIndex: selectedIndex > 4 ? 4 : selectedIndex,
              onTap: (idx) {
                if (idx == 4) {
                  _onItemTapped(6, context);
                } else {
                  _onItemTapped(idx, context);
                }
              },
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.dashboard_outlined),
                  activeIcon: Icon(Icons.dashboard),
                  label: 'Dashboard',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.badge_outlined),
                  activeIcon: Icon(Icons.badge),
                  label: 'Faculty',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.calendar_month_outlined),
                  activeIcon: Icon(Icons.calendar_month),
                  label: 'Attendance',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.pending_actions_outlined),
                  activeIcon: Icon(Icons.pending_actions),
                  label: 'Requests',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings_outlined),
                  activeIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            )
          : null,
    );
  }

  List<Widget> _buildAppBarActions(BuildContext context) {
    return [
      IconButton(
        icon: Badge(
          label: Text('$_unreadNotifications'),
          isLabelVisible: _unreadNotifications > 0,
          child: const Icon(Icons.notifications_none_outlined, size: 20),
        ),
        onPressed: _showNotificationsDialog,
      ),
      const SizedBox(width: 8),
      IconButton(
        icon: const Icon(Icons.help_outline, size: 20),
        onPressed: () {},
      ),
      const SizedBox(width: 12),
    ];
  }

  Widget _buildSidebarCategory(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: AppColors.textMutedLight.withOpacity(0.8),
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildSidebarItem(
    int index,
    IconData icon,
    String label,
    int selectedIndex,
    BuildContext context,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSelected = selectedIndex == index;

    Color itemColor = isSelected
        ? AppColors.primary
        : (isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight);

    Color bg = isSelected
        ? AppColors.primary.withOpacity(0.06)
        : Colors.transparent;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: itemColor, size: 20),
        title: Text(
          label,
          style: AppTypography.bodyLarge.copyWith(
            color: itemColor,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        onTap: () => _onItemTapped(index, context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        ),
      ),
    );
  }

  Widget _buildDesktopProfilePanel(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final name = SessionManager.fullName ?? 'Administrator';
    final email = SessionManager.email ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'A';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.borderDark : AppColors.borderLight,
          ),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
            child: Text(initial,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  email,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_vert,
              size: 18,
              color: isDark ? AppColors.textMutedDark : AppColors.textMutedLight,
            ),
            onSelected: (val) async {
              if (val == 'logout') {
                await SessionManager.clear();
                if (context.mounted) context.go('/login');
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, size: 16, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Logout', style: TextStyle(fontSize: 13, color: Colors.red)),
                    ],
                  )),
            ],
          ),
        ],
      ),
    );
  }

  String _getScreenTitle(int index) {
    switch (index) {
      case 0:
        return 'System Dashboard';
      case 1:
        return 'Faculty Directory';
      case 2:
        return 'Daily Attendance Logs';
      case 3:
        return 'Reporting Hub';
      case 4:
        return 'System Audit Logs';
      case 5:
        return 'Approvals Queue';
      case 6:
        return 'Global Settings';
      default:
        return 'Premises';
    }
  }
}
