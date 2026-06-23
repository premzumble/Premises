import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/api_service.dart';
import '../../../core/design_system/app_colors.dart';
import '../../../core/design_system/app_sizes.dart';
import '../../../core/design_system/app_typography.dart';
import '../../../core/session_manager.dart';

class FacultyNavigation extends StatefulWidget {
  final Widget child;
  final String location;

  const FacultyNavigation({
    super.key,
    required this.child,
    required this.location,
  });

  @override
  State<FacultyNavigation> createState() => _FacultyNavigationState();
}

class _FacultyNavigationState extends State<FacultyNavigation> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadNotificationCount();
    // Poll notifications every 10 seconds for real-time badge updates
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _loadNotificationCount();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadNotificationCount() async {
    try {
      final list = await ApiService.fetchNotifications();
      final unreadCount = list.where((n) => n['read_at'] == null).length;
      SessionManager.unreadNotifications.value = unreadCount;
    } catch (_) {
      // Ignore background fetch errors
    }
  }

  int _getSelectedIndex() {
    final loc = widget.location;
    if (loc.startsWith('/faculty/dashboard')) return 0;
    if (loc.startsWith('/faculty/history')) return 1;
    if (loc.startsWith('/faculty/notifications')) return 2;
    if (loc.startsWith('/faculty/device')) return 3;
    if (loc.startsWith('/faculty/profile')) return 4;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/faculty/dashboard');
        break;
      case 1:
        context.go('/faculty/history');
        break;
      case 2:
        context.go('/faculty/notifications');
        break;
      case 3:
        context.go('/faculty/device');
        break;
      case 4:
        context.go('/faculty/profile');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final width = MediaQuery.of(context).size.width;
    
    final isMobile = width < 640;
    final isTablet = width >= 640 && width < 960;
    final isDesktop = width >= 960;

    final selectedIndex = _getSelectedIndex();

    return Scaffold(
      appBar: isMobile
          ? AppBar(
              title: Text(
                'Premises Faculty',
                style: AppTypography.h3.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
              ),
              actions: _buildAppBarActions(context),
            )
          : null,
      body: Row(
        children: [
          // Desktop Sidebar
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
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSidebarCategory('Faculty Menu'),
                          _buildSidebarItem(0, Icons.home_outlined, 'My Presence', selectedIndex, context),
                          _buildSidebarItem(1, Icons.history, 'Attendance History', selectedIndex, context),
                          _buildSidebarItem(2, Icons.notifications_none_outlined, 'Notifications', selectedIndex, context),
                          _buildSidebarItem(3, Icons.phone_android_outlined, 'Device Management', selectedIndex, context),
                          _buildSidebarItem(4, Icons.person_outline, 'My Profile', selectedIndex, context),
                        ],
                      ),
                    ),
                  ),
                  _buildDesktopProfilePanel(context),
                ],
              ),
            ),

          // Tablet Navigation Rail
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
                  Icon(Icons.badge_outlined, color: theme.colorScheme.primary, size: 28),
                  const SizedBox(height: 24),
                  Expanded(
                    child: NavigationRail(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: (idx) => _onItemTapped(idx, context),
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        const NavigationRailDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home),
                          label: Text('Presence', style: TextStyle(fontSize: 10)),
                        ),
                        const NavigationRailDestination(
                          icon: Icon(Icons.history),
                          selectedIcon: Icon(Icons.history_toggle_off),
                          label: Text('History', style: TextStyle(fontSize: 10)),
                        ),
                        NavigationRailDestination(
                          icon: ValueListenableBuilder<int>(
                            valueListenable: SessionManager.unreadNotifications,
                            builder: (context, count, child) {
                              return Badge(
                                label: Text('$count'),
                                isLabelVisible: count > 0,
                                child: const Icon(Icons.notifications_none_outlined),
                              );
                            },
                          ),
                          selectedIcon: ValueListenableBuilder<int>(
                            valueListenable: SessionManager.unreadNotifications,
                            builder: (context, count, child) {
                              return Badge(
                                label: Text('$count'),
                                isLabelVisible: count > 0,
                                child: const Icon(Icons.notifications),
                              );
                            },
                          ),
                          label: const Text('Alerts', style: TextStyle(fontSize: 10)),
                        ),
                        const NavigationRailDestination(
                          icon: Icon(Icons.phone_android_outlined),
                          selectedIcon: Icon(Icons.phone_android),
                          label: Text('Device', style: TextStyle(fontSize: 10)),
                        ),
                        const NavigationRailDestination(
                          icon: Icon(Icons.person_outline),
                          selectedIcon: Icon(Icons.person),
                          label: Text('Profile', style: TextStyle(fontSize: 10)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Main Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                          'Faculty Workspace',
                          style: AppTypography.h3.copyWith(
                            color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                          ),
                        ),
                        const Spacer(),
                        ..._buildAppBarActions(context),
                      ],
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.all(isMobile ? 12.0 : 20.0),
                    child: widget.child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isMobile
          ? BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              currentIndex: selectedIndex,
              onTap: (idx) => _onItemTapped(idx, context),
              selectedItemColor: theme.colorScheme.primary,
              unselectedItemColor: Colors.grey,
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.home_outlined),
                  activeIcon: Icon(Icons.home),
                  label: 'Presence',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.history),
                  activeIcon: Icon(Icons.history_toggle_off),
                  label: 'History',
                ),
                BottomNavigationBarItem(
                  icon: ValueListenableBuilder<int>(
                    valueListenable: SessionManager.unreadNotifications,
                    builder: (context, count, child) {
                      return Badge(
                        label: Text('$count'),
                        isLabelVisible: count > 0,
                        child: const Icon(Icons.notifications_none_outlined),
                      );
                    },
                  ),
                  activeIcon: ValueListenableBuilder<int>(
                    valueListenable: SessionManager.unreadNotifications,
                    builder: (context, count, child) {
                      return Badge(
                        label: Text('$count'),
                        isLabelVisible: count > 0,
                        child: const Icon(Icons.notifications),
                      );
                    },
                  ),
                  label: 'Alerts',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.phone_android_outlined),
                  activeIcon: Icon(Icons.phone_android),
                  label: 'Device',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.person_outline),
                  activeIcon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            )
          : null,
    );
  }

  List<Widget> _buildAppBarActions(BuildContext context) {
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8.0, right: 12.0),
        child: ValueListenableBuilder<int>(
          valueListenable: SessionManager.unreadNotifications,
          builder: (context, count, child) {
            return Badge(
              label: Text('$count'),
              isLabelVisible: count > 0,
              child: IconButton(
                icon: const Icon(Icons.notifications_none_outlined, size: 20),
                onPressed: () => context.go('/faculty/notifications'),
              ),
            );
          },
        ),
      ),
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

    Widget leadingWidget = Icon(icon, color: itemColor, size: 20);
    if (index == 2) {
      leadingWidget = ValueListenableBuilder<int>(
        valueListenable: SessionManager.unreadNotifications,
        builder: (context, count, child) {
          return Badge(
            label: Text('$count'),
            isLabelVisible: count > 0,
            child: Icon(icon, color: itemColor, size: 20),
          );
        },
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      ),
      child: ListTile(
        dense: true,
        leading: leadingWidget,
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
    final name = SessionManager.fullName ?? 'Faculty';
    final email = SessionManager.email ?? '';
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'F';

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
                      Text('Logout',
                          style: TextStyle(fontSize: 13, color: Colors.red)),
                    ],
                  )),
            ],
          ),
        ],
      ),
    );
  }
}
